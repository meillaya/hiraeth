# Scalability, infrastructure, and architecture

This note answers three questions with evidence: what the system costs per
request today, which resource fails first as load grows, and which architecture
changes have the highest return. Numbers measured locally on the seeded corpus
are labelled as such; vendor limits are cited.

## Workload shape

The public workload is read-only and small in row count by database standards.

| Quantity | Value | Source |
|---|---|---|
| Source records / editions | 9,415 | `priv/repo/seeds.exs` output |
| Works (book pages) | 7,582 | measured in the seeded test database |
| Publisher pages (23 source providers) | 20 | measured in the seeded test database |
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

Measured on 31 October 2026 against 9,415 source records in the local PostgreSQL 16
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

These are local loopback calls. The directory rows were re-measured after the
1 November read-path change and the deployed latency told a different story than
the function timer; see "Directory payload transfer" below.

Three observations follow from the numbers.

The in-process cache is doing most of the work on repeat traffic: the book page
drops from 39 ms to 18 ms and the publisher directory from 20 ms to 17 ms within
the 30-second TTL. The cache is per node and is not shared, which is acceptable
while there is one node and becomes a consistency question on more.

The author sort costs 45.7 ms, about 2.5 times the default order, because it
correlates a contributor subquery per edition row. It is inside the 175 ms warm
budget asserted by `test/hiraeth_web/public_catalog_performance_test.exs`, but it
is the first query to watch if the corpus grows.

Every list query does a windowed count over the same join. At 7,582 works the
cost is tens of milliseconds; at ten times the corpus it is the first read path
that needs a materialized count or a denormalized sort table.

## Directory payload transfer

Measured 1 November 2026 against the deployed service (Railway,
`hiraeth.up.railway.app`, Postgres over the private network). The
trigger was `browse?publisher=archipelago-books` at 1.34 s while `/search` and
`/api/v1/books` answered in 65 ms on the same node.

Root cause: `catalog_public_works` stores one encoded book payload per work —
7,565 rows, 118 MB, 16 kB on average. The press directory needed one cover
sample per press and the collection directory needed members grouped per
collection, and both got there by pulling **every matching row with every
column** and reducing in Elixir. `/browse` calls both, which is why it, `/`,
`/publishers`, and `/publishers/:slug` all paid for the same two queries.

| Directory query | Rows | Payload on the wire |
|---|---|---|
| Publisher cover samples, before | 1,688 | 27 MB |
| Series preview books, before | 1,184 | 19 MB |
| Publisher cover samples, after | 17 | 305 kB |
| Series previews, after | 32 | 586 kB |

Both queries now choose the winning rows in SQL — `DISTINCT ON (publisher_slug)`
for cover samples and `row_number() OVER (PARTITION BY series_slug)` for
previews — and fetch payloads only for the ids that won. A directory render moved
46 MB → 891 kB, about 52 times less data. That ratio is the whole story: the same
queries take 45 ms and 31 ms on loopback, and 1.0 s and 0.3 s across a network.

Deployed effect, warm, three runs per route, `gzip`:

| Route | Before | After |
|---|---|---|
| `/` | 1.51 s | 0.05 s |
| `/browse` | 1.27 s | 0.10 s |
| `/browse?publisher=archipelago-books` | 1.34–1.48 s | 0.08 s |
| `/publishers` | 1.26 s | 0.055 s |
| `/publishers/archipelago-books` | 1.32 s | 0.18 s |
| `/series` | 0.33 s | 0.078 s |
| `/search` | 0.068 s | 0.08 s |
| `/api/v1/books?page=1` | 0.064 s | 0.075 s |

Fresh-node effect in-process, same corpus, five runs: `publishers()` 38.3 → 5.3 ms,
`series()` 67.0 → 4.2 ms, `series_with_preview_editions()` 65.1 → 3.8 ms, with
`publisher_options()` at 1.1 ms and `series_options()` at 0.5 ms.

Three rules follow.

1. Measure the wire, not only the function. The in-process timings were 20–40 ms
   and looked healthy while the deployed page took 1.3 s, because tens of
   megabytes crossed a WAN. Any directory query whose row count scales with the
   corpus is a transfer problem even when its timer looks acceptable.
2. Rank and cap in SQL. `DISTINCT ON` and window functions keep the payload fetch
   proportional to what the page renders, not to what the corpus holds. Counting
   is its own cheap query: `PublicWorks.count/1` exists so a header counter
   cannot accidentally fetch and decode a page of books.
3. A filter tray needs labels, not projections. `publisher_options/0` and
   `series_options/0` return labels and counts; the decoded directory projection
   stays on the pages that show covers.

### Cover delivery lessons

The 1.1 s 404 in the same waterfall was a separate gap, and none of it was
query planning.

- Responsive variants rendered by `CoverVariantBackfillWorker` were written to
  disk and never uploaded, so a cold replica asked R2 for files that never
  arrived. `cache_public_covers!/1` now uploads variant paths in every branch,
  not just the ones that also write an original.
- A store miss, or an object the proxy refuses to serve, is remembered for 60
  seconds by `Hiraeth.Covers.MissCache`; the response is a `404` with
  `cache-control: public, max-age=60`. Repeats dropped from 0.6–1.1 s to 60 ms.
- Content-hashed variants are served `immutable` for a year by both `Plug.Static`
  and the proxy, instead of revalidating daily.
- One asset is still unservable: a 34.7 MB Archipelago Books original with no
  thumbnail or variants recorded, over the proxy's 10 MB cap, so the grid falls
  back to the original URL and the image is broken. Only that one original in
  the cache is over the cap. The remedy is a data repair
  (`mix hiraeth.covers.sync --all --missing` on the worker), not a code change;
  until then the cost is one slow request per 60 s per node instead of one per
  page view.

The regression guard is `test/hiraeth_web/public_catalog_performance_test.exs`
(query budgets plus a case asserting collection counts come from SQL while the
detail view still carries every book) together with the directory-read
convention in `lib/hiraeth_web/AGENTS.md`.

## Which resource fails first

The database pool, not CPU or memory. The web service, Oban workers, and the
scheduler all draw from one Ecto pool of 10 connections. A scheduled ingestion
can occupy all four ingestion slots for minutes while cover caching adds four
more network-bound workers, and every public page still needs a connection. The
connection ceiling is 10, while PostgreSQL's default `max_connections` is 100,
so the app is not near the server limit; it is artificially limited by one
pool shared across two different workloads
([PostgreSQL connection settings](https://www.postgresql.org/docs/current/runtime-config-connection.html)).

The second failure was the cover cache on a Railway volume. Volumes have one
volume per service, cannot be attached to replicas, and force a small downtime
on redeploy even with a healthcheck
([Railway volumes](https://docs.railway.com/volumes/reference)). The cache now
uses Cloudflare R2 as the durable origin and keeps a bounded local working set.
The proxy refills a local miss at the existing `/covers/cache/...` path, so the
volume can be removed, the service can run replicas, and redeploys no longer
need to detach a volume. R2 charges $0.015 per GB-month with free egress and a
10 GB free tier ([R2 pricing](https://developers.cloudflare.com/r2/pricing/)).
At roughly 8,800 covers and a few GB with thumbnails, storage is a few cents per
month. Cards and book heroes use generated 400×600 thumbnails (tens of KB rather
than the multi-megabyte originals), and cover responses carry a one-day browser
cache. The first view after a cold start pays one bucket GET; the operator cover
sync and the proxy both read the durable store before falling back to a
publisher URL.

The third failure is ingestion convergence. `expected_record_count` is now a
floor rather than exact equality, so new titles pass while a record-count drop is
still blocked; the checked-in authority/artifact/coverage evidence is regenerated
by `mix hiraeth.real_catalog.sync --write` and checked by `--check`. The remaining
risk is an unchanged-classification that reads candidate rows rather than applied
rows, which can keep the catalog stale while every scheduled run reports a result.

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

Hiraeth deploys a `web` Phoenix service, a separate `worker` release with
`HIRAETH_SERVICE_ROLE=worker` and no public domain, one private sidecar, and
Railway-managed Postgres. The split is mirrored in a `staging` environment.
The healthcheck split is deliberate:
`/health` answers without touching dependencies, and `/ready` checks the database
and the sidecar. `/health` passing therefore does not mean the service can serve
catalog pages, and `/ready` is the probe that should gate traffic. Whichever path
the platform is configured to use must be written down; a platform probe against
`/ready` also needs the `force_ssl` exemption that `/health` already has
([Railway healthchecks](https://docs.railway.com/deployments/healthchecks)).

Private networking keeps the sidecar off the public internet
([Railway private networking](https://docs.railway.com/networking/private-networking)).
It is no longer the only boundary. The production sidecar image runs in secure
mode: it requires `HIRAETH_SIDECAR_TOKEN`, loads provider manifests from its own
filesystem, and rejects data requests that do not carry a timestamped HMAC over
the raw body. Phoenix signs every data request and refuses to boot in production
without the token. The host allowlist therefore comes from the image, not from
the request.

One gap remains. Validation still does not resolve and pin the destination
address, so a compromised official hostname could resolve into a private range.
That matters only if the sidecar starts handling URLs the manifest does not
name. It does not today.

## Recommendations, ordered by return

1. Done: the worker process is separate from the web service. Oban, projection
   rebuilds, cover backfill, and responsive-variant generation run on `worker`
   with their own pool, so web page latency is independent of ingestion.
2. Done: the cover cache moved to R2 with a local working set. Railway services
   set `HIRAETH_COVER_STORE=s3` with the R2 variables, and the local cache is
   capped by `HIRAETH_COVER_CACHE_MAX_BYTES`. The worker refills originals and
   renders variants from R2 on a cold start.
3. Done: directory and filter reads are bounded. Cover samples, collection
   previews, and the filter trays select keys in SQL and fetch only the payloads
   they render, and the press and collection directories sit in the public
   catalog TTL cache. Any new directory read must follow the same shape; see
   "Directory payload transfer" above.
4. Add a rate limit and a response cache header to `/api/v1`. The API is
   read-only and cacheable by content type; a 30-second `Cache-Control` matches
   the existing read model TTL.
5. Run migrations as a release step before the new image serves traffic.
6. Attach a telemetry reporter and set `measurements: :default` on the poller.
   Without an export, none of the declared Phoenix, VM, or ingestion metrics are
   observable.
7. Chunk ingestion by phase, apply per-record quarantine on validation findings,
   and compare changes against applied state rather than the previous candidate.
8. Guard dead-render database work with `connected?/1` on the catalog LiveViews.
   The duplicate page query in `BrowseLive.mount/3` is gone, but the first HTML
   still runs `handle_params/3` and its page query.
9. Add `EXPLAIN (ANALYZE, BUFFERS)` tests for the five public list queries, with
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
