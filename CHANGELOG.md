# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Softbound design system: canonical tokens in `assets/css/tokens.css`, the component layer in `assets/css/softbound.css`, the self-hosted Archivo variable font, and a formal responsive specification in `design/index.html` (tokens, type scale, breakpoint matrix, component contracts, and acceptance checklist).
- `scripts/qa/design_screenshots.mjs` captures every public surface at nine acceptance widths (390–1440px) and fails on horizontal overflow, sheet inset drift, or header-mode drift.
- R2-backed public cover storage. `Hiraeth.Covers.Store` has local and S3 implementations, cache writes upload originals and thumbnails, purge deletes both copies, and `mix hiraeth.covers.upload` backfills a bucket from the local cache.
- `/covers/cache/*path` proxy for local misses. It validates the path, checks the cover is still public in the database, fetches from R2, writes the local cache atomically, and serves the bytes with the same same-origin URL.
- `Hiraeth.Covers.CachePruner` and `HIRAETH_COVER_CACHE_MAX_BYTES` (default 1 GiB) bound the local working set.
- `Hiraeth.Oban.CoverBackfillWorker` fills cover assets that a seed or import created without a cached original. Production enqueues it once at boot behind `HIRAETH_COVER_BACKFILL_ON_BOOT` (default true, independent of the ingestion kill switch because it never ingests catalog data), and it is scoped to missing assets, so it is a no-op when coverage is complete.
- Secure sidecar mode: the production image requires `HIRAETH_SIDECAR_TOKEN`, loads provider manifests from `/app/manifests`, ignores caller-supplied host policy, and rejects unsigned or stale data requests with a typed `unauthorized` error. Phoenix signs fetch, scrape, and detail bodies with an HMAC-SHA256 over the timestamp and raw body.
- `RecordCandidate.applied_at` and the `mark_applied` action, migration `20261031170000_add_record_candidate_applied_at.exs`. `ApplyCandidates` sets the marker after the importer commits.
- `sidecar/manifests/` build copies and `scripts/catalog/sync_sidecar_manifests.sh`; `tests/test_manifest_sync.py` fails when the copy and the governed source differ.
- Typed public boundary: every public catalog read shape is a `Hiraeth.Catalog.PublicProjection` struct with a `t/0` type, built through strict, idempotent builders that reject unknown keys. `HiraethWeb.PublicCatalog` and `Hiraeth.Ingestion.SidecarClient` now carry `@spec` for every exported arity. `test/hiraeth/public_api_contract_test.exs` fails the fast lane when a public function or projection loses its type.
- Versioned read-only JSON API at `/api/v1` for books, editions, publishers, series, contributors, and the served OpenAPI document. The contract is OpenAPI 3.0 generated from controller operations and schema modules, every endpoint response is validated against it in tests, and the route contract test pins the exact path list. Reference: `docs/api/v1.md`.
- Working `title`, `author`, and `recently_added` orderings for book pages. The home page's "Recently imported" link now matches the order it requests.
- `docs/` tree with the API reference, the typed boundary design note, the scalability and operations research, and this audit's findings.
- `mix hiraeth.real_catalog.seed_provider --provider <slug>` as the per-provider recovery path. Loads `priv/catalog_sources/real_publishers/<slug>.json`, validates against the provider manifest when one is checked in, creates an `ImportRun`, and delegates to `Hiraeth.RealCatalog.Importer.seed_provider!/3`. Each provider runs in its own `Ash.transact`, so a single failure does not poison the rest of the corpus. Use this when the whole-corpus `priv/repo/seeds.exs` aborts midway through one provider.
- `config/dev.exs` now honors `DATABASE_URL` when set, so `railway run -- mix ...` from a developer machine reaches the Railway Postgres without needing to override `DATABASE_HOST`/`DATABASE_PORT`/`DATABASE_USER`/`DATABASE_PASSWORD` individually. Standalone localhost defaults are preserved when `DATABASE_URL` is unset.
- `priv/test_lanes.exs` is the single source of truth for the slow/full_catalog/integration/performance/browser/public_catalog_full cost-tag list. `mix test.fast`, `mix test.full`, and `mix ci` all derive their `--exclude` / `--include` flags from this file. Contract test: `test/hiraeth/mix_alias_contract_test.exs`.
- `test/hiraeth/dev_database_url_override_test.exs` now uses `Config.Reader.read!/2` to evaluate `config/dev.exs` for the `:dev` env, so the three config-eval assertions run in ~30 ms instead of spawning a `mix run` subprocess per case.
- Self-hosted OFL fonts (Newsreader, Space Grotesk, Space Mono) with `@font-face` rules and license/provenance documentation under `priv/static/fonts/`.
- Three full-site design prototypes built from real catalog data under `artifacts/design-prototypes/` as the sanctioned UI exploration artifact.
- Per-provider `cadence_hours` on provider manifests and `ProviderSource` (default 24h) with manifest validation and backfill.
- Weekly scheduled cover cache refresh and provenance audit workers on the idle `:covers` and `:audit` Oban queues.
- README pointer to the "Autonomous catalog updates" ops runbook section for what runs when, the kill-switch, and rollout order.

### Changed

- The public browser UI is rebuilt as the Softbound edition: a single paper sheet on a sage ground, Newsreader display type with Archivo interface text, a featured-forthcoming homepage hero, a four-title recent/forthcoming shelf, filter-tray browse, book records, press dossiers, collection shelves, contributor directory, and search. The dark theme toggle and its palette are retired; Softbound is light-only.
- The homepage hero is now the nearest forthcoming book with a displayable cover, and the four cards beneath it are sampled per visit from recent or forthcoming books. Subscriptions, bundles, gift cards, and merchandise are excluded from both the hero and the cards by a single candidate rule in `HiraethWeb.PublicCatalog`.
- Public cover selection is centralized in `Hiraeth.Covers.Policy` for every read path. A work shows exactly one cover, owned by one edition: the newest displayable print cover wins (so a reissue replaces the retired cover, including a publisher "cover coming soon" image), with a newest non-print cover as the fallback for ebook-only works. The rule is evaluated at read time, so changing it never refetches cached covers.
- Provider manifests can declare a canonical print cover listing with `cover_source` (`{"endpoint": "...", "match": "title"}`). The Squarespace adapter sources print products' covers from that listing and keeps a non-print cover only as a digital-only fallback; the read policy still renders the print cover whenever the work has one. Tilted Axis Press now sources print covers from `/shop?category=print`; the rule is generic, so another split-format provider only needs a manifest declaration.
- The cover cache no longer depends on a Railway volume. The Docker image keeps a bounded ephemeral directory, and the durable copy lives in R2 when `HIRAETH_COVER_STORE=s3`. The bucket is private, so images stay proxied through Phoenix and the `img-src 'self'` CSP is unchanged.
- `DiffCandidates` only treats applied candidates as the baseline, so a run that fails before apply cannot make the next run classify its records `unchanged`. Scheduled auto-approval drops `unchanged` because those rows are never applied.
- Sidecar data requests are signed and the production image refuses to start without a token and manifests. Both Phoenix and the sidecar must set `SCRAPLING_SIDECAR_TOKEN`; `.env.example` marks it required.
- Dependencies updated to the latest stable releases within their major versions: Ash 3.37, AshPostgres 2.15, Bandit 1.14, Mint 1.11, LiveView 1.2.13, PlugCrypto 2.2.1, Decimal 3.2. `mix hex.audit` reports no advisories. Ash 3.37 requires an explicit `default_string_length_count`, set to `:codepoints` so Elixir and Postgres count the same way.
- Provider source identity is now the bare provider slug everywhere, matching the registry backfill. The lazy registration paths in `RunState` and `CoverCandidateRun` store the checked-in manifest path instead of a source URL, and the scheduler skips a source whose manifest is not a readable local file before it can consume a dispatch slot.
- The ingestion worker declares a 45-minute timeout and Oban runs `Oban.Lifeline` with a one-hour rescue window, so a deploy cannot leave a job executing forever behind the provider's unique key.
- The post-ingestion audit phase no longer fails an already-applied run. Audit findings and write errors are recorded on the run, and the catalog work stands.
- The local standalone Postgres cluster, log, and socket live under the gitignored `tmp/` tree, so a checkout on an external volume keeps database writes off the system disk. `HIRAETH_PGDATA` still overrides the path.
- The sidecar maps transport failures by exception type, returns a typed `internal_error` for unexpected failures instead of a bare 500, and regenerates its reviewed OpenAPI snapshot.
- The real-corpus importer (`Hiraeth.RealCatalog.Importer`) was rewritten from per-record `Ash.create!` round-trips to a two-phase bulk pipeline: per-dataset row precompute keyed by natural identity (first-wins dedupe, no precomputed ids), then per-table `Ash.bulk_create` upserts (per-resource `upsert_identity` + minimal `upsert_fields {:replace, identity_keys}`, never `:replace_all`) inside one transaction per dataset, with per-row `Ash.update!`/`destroy!` only for actual sync/prune diffs. Measured post-bulk: per-seed full-corpus seed ~50-160s locally (102.7s + 50.2s per dataset pass, down from multi-minute per-record seeds), 162.3s end-to-end, well under a 300s envelope.
- Mix aliases collapsed to `gate` (single fast blocking gate), `ci` (full lane), `test.fast`, and `test.full`; the Makefile `verify` chain slimmed to `audit-provenance verify-summary qa-pack`.
- Frontend correctness is verified by the LiveView and route logic test suites under `test/hiraeth_web/`; the browser-QA lane was removed.
- Local development is devenv-only; the root and `sidecar/Dockerfile` remain the production runtime boundary.
- Sidecar `base_url` config de-duplicated: the default lives in `config/config.exs`, dev/test inherit it, and `config/runtime.exs` reads `SCRAPLING_SIDECAR_URL`.
- `.gitattributes` language classification refreshed: the language bar now reflects app code; governed corpora, resource snapshots, fixture data, lockfiles, and vendored JS are excluded via linguist attributes.

### Fixed

- Nested query parameter shapes such as `?q[a]=b` no longer raise inside the catalog LiveViews; only scalar filter values are accepted.
- A page number beyond the database integer range no longer raises `DBConnection.EncodeError`; the page is capped before the SQL offset is built.
- The publisher and contributor cache no longer stores negative lookups, so arbitrary slugs cannot grow `:persistent_term` without bound.
- `/ready` bounds its connect timeout as well as its receive timeout.
- `Plug.Parsers` no longer accepts multipart bodies and caps request bodies at 100 KB.
- `SourceLedgerEntry` is append-only again: the `:update` and `:destroy` actions are gone.
- `SidecarClient` returns a typed error for a non-object success body and raises a named error when the sidecar base URL is missing.
- The CSP is no longer exempted from Sobelow, and `test/hiraeth_web/security_headers_test.exs` asserts the header.

### Removed

- Unrouted page scaffold, Swoosh/Mailer, and the dev-only mailbox route.
- `Hiraeth.Search` domain, the Imports CSV workflow (including its tables via a drop migration), and the never-enqueued `SourceSnapshotReplayWorker`.
- `compose.yaml` and every Compose reference; devenv owns local, Dockerfiles own production.
- The dead `scripts-tests` CI lane (`deep.yml`) and the root `pyproject.toml` that drove it; the catalog-generator pytest suite under `tests/scripts` is retired.
- The original `docs/` directory and every dangling `docs/*.md` reference (tests, Makefile, README, AGENTS.md, CI comments, covers guide). A new `docs/` tree now holds the API reference, architecture notes, and audit; the dev/qa/ops scripts are recreated from scratch as part of the devenv-end-to-end restore.
- GitHub Actions: deleted `.github/workflows/ci.yml` and `.github/workflows/deep.yml` and disabled Actions on the repository; verification is local-only (`mix gate`, `mix ci`, `make verify`) until a replacement is designed.
- ExCoveralls and the 86.1 coverage floor: `coveralls.json`, the `excoveralls` dependency, the `test_coverage` project config, the Makefile `coverage` target, and the coveralls gate in `scripts/qa/perf/measure_gates.sh`.
- The opt-in `:nightly` test lane: `nightly_tags` in `priv/test_lanes.exs`, the `test_helper.exs` default exclusion, the nightly contract assertions in `mix_alias_contract_test.exs`, and the three full-corpus `@tag :nightly` tests.

## [1.0.0] - 2026-08-05

### Added

- Tiered verification gates: fast local blocking gate (`mix gate`), parallel CI static + fast-test jobs, and a deep verification lane (dialyzer, coverage, full suite, LiveView/route logic tests, ingestion drills, sidecar pytest, release image builds).
- Static analysis and coverage tooling: Credo strict, Dialyzer (with persisted PLT), Sobelow, ExCoveralls with a coverage floor, and `mix quality` / `mix ci` aliases.
- Dependency security gates: `hex.audit` in CI and `uv audit` for the sidecar; patched vulnerable Elixir dependencies.
- Python quality gates for the sidecar: ruff (lint + format), pyright basic check, and wiring of the orphaned `tests/scripts` suite into CI.
- Root `.editorconfig` covering Elixir, Python, shell, JS, YAML, and JSON.
- Production runtime hardening: `config/runtime.exs` requires `PHX_HOST`, `SCRAPLING_SIDECAR_URL`, and `LIVE_VIEW_SIGNING_SALT` in prod, with JSON logging via `logger_json` and a validated `LOG_LEVEL`.
- Secure session cookies (`secure` flag + `encryption_salt`) and a compile-time gate that drops the RequestLogger plug in prod.
- `/health` excluded from `force_ssl` and a prod `require_sidecar` readiness flag so Railway healthchecks pass while `/ready` stays the operator probe.
- Content-Security-Policy on the `:browser` pipeline (self-contained page contract, no remote resources).
- Release artifacts: explicit `releases` config in `mix.exs`, a root multi-stage Dockerfile, a hardened sidecar Dockerfile (pinned base, non-root user, healthcheck, no dev extras), and a CI `release-build` gate.
- Ops tooling: `scripts/ops/db_backup.sh` and `scripts/ops/db_restore_drill.sh` with Makefile targets and live-DB/prod-URL guards.
- `.env.example` completed with required/optional markers and a parity contract test that derives the required set from `config/runtime.exs`.

### Changed

- `config/runtime.exs` prod branch now raises on missing required environment variables instead of silently defaulting.
- Sidecar `httpx` moved from dev extras to runtime dependencies so the hardened image boots; `apify_fingerprint_datapoints` pinned to keep browser fingerprint data compatible with the base image's Scrapling.
- Makefile `bootstrap-check` and `qa-pack` no longer depend on `.omo` files; `test-ingest` no longer fabricates a JUnit report.
- `compose.yaml` Phoenix template references the committed root Dockerfile.
- `docs/production-operations.md` resolves the six runtime decisions for Railway (private networking, backups, memory, healthchecks, pre-deploy, rollback) while preserving the Docker-boundary language.

### Fixed

- `RealCatalogSourceManifestTest` made tolerant of environment differences (empty snapshot dir on clean checkouts no longer fails).
- Remaining Dialyzer `pattern_match` findings in the scrape Mix tasks.
- Makefile `.PHONY` colon escaping for the `gates:measure` target.

### Security

- Patched vulnerable Elixir dependencies (Phoenix, Plug, Mint, hpax, Bandit, Postgrex, Swoosh, ymlr, Ash) via a single `mix deps.update`.
- Sobelow findings satisfied; `hex.audit` and `uv audit` gates added.
- Content-Security-Policy added; secure session cookies; RequestLogger gated off in prod.

### Removed

- Admin surface removed: admin routes, module layer, auth domain, migration, invite task, test suites, browser-QA/adversarial admin tags, and README/AGENTS references.
- Stale root `worklog.md` archived to `docs/history/worklog-2026-06.md`.
- Local `priv/repo/structure.sql` dump ignored (untracked artifact).

### Docs

- `docs/cleanup-policy.md` authorizes the four named cleanup exceptions.
- `docs/production-readiness.md` aligns the tiered gate docs and operator entrypoints table with the actual CI jobs and Mix tasks.
- `docs/production-operations.md` resolves runtime decisions for Railway.

## [0.1.0] - 2026-08-05

### Added

- Initial release of Hiraeth, a Phoenix LiveView + Ash discovery catalog for curated independent publisher books.
- Canonical work/edition catalog graph with Ash resources, actions, and policies (`lib/hiraeth/catalog`).
- Provenance-aware ingestion: provider runs, source snapshots, record candidates, diffs, quarantine, replay, and ingestion events (`lib/hiraeth/ingestion`).
- Deterministic real-catalog corpus: dataset, policy gates, validator, and importer (`lib/hiraeth/real_catalog`).
- Oban-backed autonomous ingestion phases: plan, fetch, normalize, validate, diff, cover-cache, apply, audit, quarantine, replay, and retention cleanup.
- Private-by-default Python sidecar (FastAPI + Scrapling) with strict CORS, typed errors, contract snapshots, and URL validation.
- Local-cache-only public cover display with typographic fallbacks for unsafe or missing covers.
- Public LiveView catalog surface: `/browse`, `/search`, `/publishers`, `/series`, `/contributors`, and book detail pages.
- Operator Mix tasks for ingestion, scraping, cover caching, and provenance audits.
- Production docs: contracts, cleanup policy, operations, readiness, and provenance/cover policy.
