# Scalability, infrastructure, and architecture

This note answers three questions with evidence: what the system costs per
request today, which resource fails first as load grows, and which architecture
changes have the highest return. Numbers measured locally on the seeded corpus
are labelled as such; vendor limits are cited.

## Workload shape

The public workload is read-only and small in row count by database standards.

| Quantity | Value | Source |
|---|---|---|
| Source records / editions | 8,776 | `priv/repo/seeds.exs` output |
| Works (book pages) | 7,011 | measured in the seeded test database |
| Publishers | 23 | measured in the seeded test database |
| Provider manifests | 11 enabled, 28 registry rows | `priv/catalog_sources/provider_manifests`, `provider_backfill_test.exs` |
| Records declared by enabled manifests | 2,462 | sum of `expected_record_count` |
| Oban queues | ingestion 4, covers 4, audit 2 | `config/config.exs` |
| Ecto pool size | 10 by default | `config/runtime.exs` |
| Scheduler cadence | every 15 minutes, 2 dispatches per tick | `config/config.exs`, `ProviderScheduler` |
| Job timeout | 45 minutes | `ProviderIngestionWorker` |
| Public page size | 24; API allows up to 100 | `PublicCatalog`, API controller |

The write workload is the ingestion pipeline: fetch, validate, cache covers,
apply, audit. The scheduled work is larger than the read workload and shares the
same database and the same BEAM node.

## Measured read cost

Measured on 31 October 2026 against 8,776 editions in the local PostgreSQL 16
instance, single process, warm filesystem cache, `:persistent_term` cache cleared
where marked cold. Values are wall-clock milliseconds for the Elixir function
call only, without HTTP or JSON encoding.

| Operation | Cold | Warm |
|---|---|---|
| `book_page(nil, 1)` | 39.2 ms | 17.8 ms |
| `book_page(sort: "title")` | 14.1 ms | |
| `book_page(sort: "author")` | 45.7 ms | |
| `book_page(sort: "recently_added")` | 17.6 ms | |
| `search_books("fitzcarraldo")` | 42.6 ms | |
| `publishers()` | 19.8 ms | 17.1 ms |
| `publisher(slug)` | 7.9 ms | 5.4 ms |
| `book(slug)` | 7.8 ms | |
| `edition(slug)` | 7.7 ms | |

Three observations follow from the numbers.

The in-process cache is doing most of the work on repeat traffic: the book page
drops from 39 ms to 18 ms and the publisher directory from 20 ms to 17 ms within
the 30-second TTL. The cache is per node and is not shared, which is acceptable
while there is one node and becomes a consistency question on more.

The author sort costs 45.7 ms, about 2.5 times the default order, because it
correlates a contributor subquery per edition row. It is inside the 175 ms warm
budget asserted by `test/hiraeth_web/public_catalog_performance_test.exs`, but it
is the first query to watch if the corpus grows.

Every list query does a windowed count over the same join. At 7,011 works the
cost is tens of milliseconds; at ten times the corpus it is the first read path
that needs a materialized count or a denormalized sort table.

## Which resource fails first

The database pool, not CPU or memory. The web service, Oban workers, and the
scheduler all draw from one Ecto pool of 10 connections. A scheduled ingestion
can occupy all four ingestion slots for minutes while cover caching adds four
more network-bound workers, and every public page still needs a connection. The
connection ceiling is 10, while PostgreSQL's default `max_connections` is 100,
so the app is not near the server limit; it is artificially limited by one
pool shared across two different workloads
([PostgreSQL connection settings](https://www.postgresql.org/docs/current/runtime-config-connection.html)).

The second failure is the cover cache. Railway volumes have one volume per
service, cannot be attached to replicas, and force a small downtime on redeploy
even with a healthcheck, because two deployments cannot be active and mounted to
the same volume. Volumes are limited to 5 GB on Hobby and 50 GB on Pro, with
3,000 read and 3,000 write IOPS, and a non-root container can hit permission
errors on a mounted volume
([Railway volumes](https://docs.railway.com/volumes/reference)). Hiraeth's
Dockerfile runs as a non-root user and symlinks the cover cache to a volume, so
both the redeploy downtime and the permission caveat apply. A cover cache on a
volume makes zero-downtime deploys and horizontal replicas impossible on
Railway, regardless of how fast the code is.

The third failure is ingestion convergence. Exact `expected_record_count`
equality, all-or-nothing validation, and an unchanged-classification that reads
candidate rows rather than applied rows mean a transient failure can keep the
catalog stale while every scheduled run reports a result. This is a correctness
failure that presents as a capacity problem: retries amplify write load without
changing the data.

The fourth is unauthenticated API traffic. There is no rate limit, no response
cache header, and each request can cost 40 ms of database time. A crawler on
`/api/v1/books` is indistinguishable from a legitimate client.

## LiveView model

LiveView keeps one stateful process per connected user, and the browser
reconnects with exponential backoff after a disconnect; state that lives only in
assigns is lost on deploy
([LiveView deployments](https://hexdocs.pm/phoenix_live_view/deployments.html)).
Hiraeth's public LiveViews are read-only, paginated, and derive their state from
query parameters, so a deploy loses at most the selected book and the current
scroll position. That is the cheap end of the LiveView trade-off.

The catalog's pages hold at most a page of books in assigns, plus a publisher or
series detail. Memory per connection is therefore bounded by the page size, not
by the corpus. The practical ceiling for concurrent viewers is the database
pool, since every mount that queries does so through the same 10 connections.

The current code does catalog queries in `mount/3` before `connected?` is true.
Phoenix renders the dead view first and then runs the connected mount, so a page
view can pay for the same queries twice. Guarding database work with
`connected?/1` and assigning placeholders on the dead render removes that
duplicate. It is not a correctness bug, but it doubles the read cost of every
page view under load.

## Oban and ingestion

`Oban.Worker` defaults `timeout/1` to `:infinity`, so an unbounded job relies
entirely on the process staying alive. `Oban.Lifeline` rescues jobs stuck in
`executing` after a node shutdown on a time basis, one hour by default, and
marks them discarded when attempts are exhausted
([Oban.Lifeline](https://hexdocs.pm/oban/Oban.Lifeline.html)). The worker now
sets a 45-minute timeout and Oban is configured with `lifeline:
[rescue_after: {1, :hour}]`, which closes the permanent-wedge failure from the
audit for a job that outlives its node.

Two structural limits remain. The pipeline runs fetch, normalization, cover
downloads, apply, and audit in one job, so its worst-case duration is the sum of
all stages. And the ingestion queue shares a pool with the web traffic. The
shape that scales is one job per provider phase, with cover caching in its own
queue keyed by candidate batch, each with a bounded item count. The `:covers`
queue already exists; the pipeline does not use it for this work.

## Postgres

The read path is indexed for the queries it actually runs: `editions.work_id`,
`source_records.edition_id`, `contributions` by edition and work,
`series_memberships.work_id`. Query plans were not captured during this audit;
`EXPLAIN (ANALYZE, BUFFERS)` on `book_page/3` and `publisher/1` is the next step
before any index change. The author sort is the one query with a correlated
subquery and should get that treatment first.

The write path is the importer's bulk upsert, which the changelog records at
roughly 50 to 160 seconds for the full corpus. That is a batch job, not a
request-path concern. The concern is that a 30-minute importer transaction holds
locks and connections while public reads run against the same pool.

Pool sizing guidance follows from the workload split, not from a formula. A web
service with a 10-connection pool and a worker service with its own 10 leaves 80
of PostgreSQL's default 100 available for the platform and for operators. One
service with 10 shares all of it. The fix is a service split or a per-workload
pool budget, not a larger single pool
([Ecto.Postgres options](https://hexdocs.pm/ecto_sql/Ecto.Adapters.Postgres.html)).

## Railway deployment posture

Hiraeth currently deploys one Phoenix service that also runs Oban, one private
sidecar, and Railway-managed Postgres. The healthcheck split is deliberate:
`/health` answers without touching dependencies, and `/ready` checks the database
and the sidecar. `/health` passing therefore does not mean the service can serve
catalog pages, and `/ready` is the probe that should gate traffic. Whichever path
the platform is configured to use must be written down; a platform probe against
`/ready` also needs the `force_ssl` exemption that `/health` already has
([Railway healthchecks](https://docs.railway.com/deployments/healthchecks)).

Private networking keeps the sidecar off the public internet
([Railway private networking](https://docs.railway.com/networking/private-networking)).
It does not authenticate requests. The sidecar's host allowlist is supplied by
the caller, so the private network is the only boundary. A shared secret header,
server-side manifests, or both are required before treating the sidecar as a
trusted internal service.

## Recommendations, ordered by return

1. Split the worker process from the web service. Give Oban its own pool and
   keep web page latency independent of ingestion. This is the smallest change
   that removes the first failure mode.
2. Move the cover cache off the single attached volume, or accept the
   consequences in writing. Object storage with a local disk cache keeps
   `/covers/cache` stable, allows replicas, and removes redeploy downtime. If
   the volume stays, document the single-replica and redeploy constraints and
   fix the working-directory-relative cache root.
3. Add a rate limit and a response cache header to `/api/v1`. The API is
   read-only and cacheable by content type; a 30-second `Cache-Control` matches
   the existing read model TTL.
4. Run migrations as a release step before the new image serves traffic.
5. Attach a telemetry reporter and set `measurements: :default` on the poller.
   Without an export, none of the declared Phoenix, VM, or ingestion metrics are
   observable.
6. Chunk ingestion by phase, apply per-record quarantine on validation findings,
   and compare changes against applied state rather than the previous candidate.
7. Guard dead-render database work with `connected?/1` on the catalog LiveViews.
8. Add `EXPLAIN (ANALYZE, BUFFERS)` tests for the five public list queries, with
   a budget on both elapsed time and planned rows.

## Rejected directions

- AshJsonApi for the public API. The public read model is SQL with source-policy
  gates; exposing Ash resources would duplicate those rules or change the public
  output.
- A second Ecto pool inside the same service without a service split. It helps
  only if Oban and web get separate connection budgets, which is the same work
  as a split with less isolation.
- Multiple Railway replicas with the current volume. Volumes cannot be shared
  across replicas.
- A distributed cache (Redis) at the current scale. The read model is 30 seconds
  stale by design and the cache is a latency optimization, not a correctness
  mechanism. It becomes relevant when more than one node serves traffic.

## Sources

- Phoenix LiveView, Deployments and recovery:
  https://hexdocs.pm/phoenix_live_view/deployments.html
- Oban, `Oban.Lifeline`: https://hexdocs.pm/oban/Oban.Lifeline.html
- Oban, worker timeout callback: https://hexdocs.pm/oban/Oban.Worker.html#c:timeout/1
- PostgreSQL, connection settings and `max_connections`:
  https://www.postgresql.org/docs/current/runtime-config-connection.html
- Ecto SQL, PostgreSQL adapter options:
  https://hexdocs.pm/ecto_sql/Ecto.Adapters.Postgres.html
- Railway, volumes reference: https://docs.railway.com/volumes/reference
- Railway, healthchecks: https://docs.railway.com/deployments/healthchecks
- Railway, private networking: https://docs.railway.com/networking/private-networking
- Railway, production readiness checklist:
  https://docs.railway.com/overview/production-readiness-checklist
