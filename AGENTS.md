# PROJECT KNOWLEDGE BASE

**Generated:** 2026-10-31
**Commit:** b27645d
**Branch:** main

## OVERVIEW
Hiraeth is a Phoenix 1.8 / LiveView discovery catalog for indie publisher and bookstore data (v1.0.0, deployed to Railway). Ash resources own domain behavior; Scrapling-powered Python sidecar handles permitted external fetch/scrape work; local dev uses the nix-profile toolchain plus a standalone postgres (the devenv config files remain in-repo as dormant groundwork) while the Dockerfiles remain the production-boundary reference. The public browser UI is the light-only Hiraeth interface: one paper sheet, Newsreader/Archivo type, canonical `sb-*` tokens in `assets/css/tokens.css`, and static reference compositions plus a formal spec in `design/`.

## STRUCTURE
```
lib/hiraeth/             # Ash domains, catalog, ingestion, provenance, covers
lib/hiraeth/catalog      # canonical work/edition graph + Ash actions/policies
lib/hiraeth/ingestion    # provider runs, sidecar client, normalizers, replay
lib/hiraeth/real_catalog # deterministic corpus: dataset, policy gates, validator, importer
lib/hiraeth_web/         # Phoenix router, LiveViews, components, public UI, versioned JSON API
lib/hiraeth_web/api      # OpenAPI document, v1 controller, schemas, serializer
assets/css/              # Tailwind entry, Hiraeth tokens, and component layer
design/                  # formal Hiraeth spec + static page prototypes (docs-only)
docs/screenshots/        # versioned README captures + routes manifest
.github/workflows/       # hosted CI: gate, sidecar, visual + accessibility lanes
lib/mix/tasks/           # operator Mix tasks: ingest, scrape, covers, audits
test/                    # ExUnit, LiveView, fixture, and contract suites
test/support             # data_case, factories, contract fixtures
sidecar/                 # private FastAPI + Scrapling sidecar service
scripts/                 # QA/dev/catalog operational scripts
scripts/qa/ingestion     # production ingestion drills + adversarial drill
scripts/qa/design_screenshots.mjs  # responsive design contract check (local + CI)
scripts/qa/accessibility_screenshots.mjs  # axe-core WCAG A/AA contract check (local + CI)
scripts/qa/live_screenshots.mjs    # README gallery refresh
scripts/qa/perf          # perf baseline measurement harness (measure_gates.sh)
scripts/ops              # DB backup + restore-drill scripts (restore into separate DB only)
priv/                    # migrations, source data, snapshots, static covers
priv/repo/migrations     # Ash + custom migration history
priv/catalog_sources     # approved provider manifests, source registry
priv/catalog_sources/provider_manifests  # per-provider source allowlists
priv/resource_snapshots  # governed snapshot/replay evidence (incl. repo)
priv/static/covers       # hashed local cover cache (sandboxed writes only)
docs/                    # API reference, typed boundary design, scalability research, audit
artifacts/qa             # QA evidence outputs (make verify, provenance audits)
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Catalog business rules | `lib/hiraeth/catalog`, `lib/hiraeth/*.ex` | Ash domains/actions first |
| Ingestion/provenance | `lib/hiraeth/ingestion`, `lib/hiraeth/sources`, `lib/hiraeth/real_catalog` | preserve snapshots + ledgers |
| Public browser UI | `lib/hiraeth_web/live`, `lib/hiraeth_web/controllers/catalog_page_controller.ex`, `lib/hiraeth_web/public_catalog.ex` | static home/book/publisher/press/collection/contributor pages + LiveView browse/search |
| Design system and tokens | `assets/css/tokens.css`, `assets/css/hiraeth.css`, `design/index.html` | single token source; spec reads the live CSS; Hiraeth is light-only |
| Public read model | `lib/hiraeth/catalog/public_work*.ex`, `lib/hiraeth/catalog/public_works.ex` | one derived row per public work; one encoded book payload + filter/search columns |
| Static page delivery | `lib/hiraeth_web/controllers/catalog_page_controller.ex`, `lib/hiraeth_web/page_cache.ex` | home/book/publisher/press/collection/contributor are controller-rendered; browse/search stay LiveView; `/sitemap.xml` + `/robots.txt` are generated |
| Candidate review admin | `lib/hiraeth_web/controllers/admin_controller.ex`, `admin_html/` | BasicAuth write console for approve/reject/ignore/override; `/ops` stays read-only |
| Service roles | `lib/hiraeth/service_role.ex`, `HIRAETH_SERVICE_ROLE` | `web` = endpoint only, `worker` = Oban only, `all` = local/test |
| Browser capture checks | `scripts/qa/design_screenshots.mjs`, `scripts/qa/accessibility_screenshots.mjs`, `scripts/qa/live_screenshots.mjs` | Playwright; hosted CI runs design + axe lanes, `mix gate` stays browser-free |
| Cover selection and backfill | `lib/hiraeth/covers/policy.ex`, `lib/hiraeth/oban/cover_backfill_worker.ex`, `cover_variant_backfill_worker.ex` | one print-first cover per work; boot backfill fills missing cache and responsive variants |
| Public JSON API | `lib/hiraeth_web/api`, `docs/api/v1.md` | read-only `/api/v1`, schema-tested |
| Operator Mix tasks | `lib/mix/tasks` | ingest, scrape, covers, audits |
| External fetch/scrape | `sidecar/app`, `sidecar/tests` | private sidecar, Scrapling only |
| Dev/test orchestration | `scripts/dev/ensure_postgres.sh`, `devenv.nix`, `Makefile` | standalone postgres + nix-profile toolchain (devenv dormant) |
| Frontend verification | `test/hiraeth_web/live`, `test/hiraeth_web`, `.github/workflows/ci.yml` | LiveView/route logic tests plus hosted Playwright design/accessibility lanes; no browser lane in `mix gate` |
| Ingestion QA drills | `scripts/qa/ingestion` | production drill + adversarial drill |
| Test support harnesses | `test/support` | data_case, factories, contract fixtures |
| Migrations | `priv/repo/migrations` | Ash + custom migration history |
| Provider manifests | `priv/catalog_sources/provider_manifests` | per-provider source allowlists |
| Source snapshots | `priv/resource_snapshots/repo` | governed snapshot/replay evidence |
| Cover cache | `priv/static/covers` | bounded local cache; R2 is the durable origin at `/covers/cache/...` |
| DB backup/restore drills | `scripts/ops`, `Makefile` (`db-backup`, `db-restore-drill`) | restore drills target a separate DB, never live |
| Release/deployment | `Dockerfile` | multi-stage release image; Railway |

## CODE MAP
| Symbol / file | Type | Location | Role |
|---|---|---|---|
| `Hiraeth.Application` | OTP app | `lib/hiraeth/application.ex` | starts Repo, PubSub, then role-gated Oban/Endpoint |
| `HiraethWeb.Router` | router | `lib/hiraeth_web/router.ex` | public route boundary; hard CSP; `/admin` write console; `/sitemap.xml` + `/robots.txt` |
| `HiraethWeb.AdminController` | controller | `lib/hiraeth_web/controllers/admin_controller.ex` | BasicAuth candidate review; writes review state through Ash actions |
| `HiraethWeb.SitemapController` | controller | `lib/hiraeth_web/controllers/sitemap_controller.ex` | generated XML sitemap + robots policy |
| `Hiraeth.Oban.CoverVariantBackfillWorker` | Oban worker | `lib/hiraeth/oban/cover_variant_backfill_worker.ex` | renders missing responsive cover variants from cached originals |
| `HiraethWeb.HealthController` | controller | `lib/hiraeth_web/controllers/health_controller.ex` | `/health` + `/ready` (DB + optional sidecar check) |
| `HiraethWeb.PublicCatalog` | query facade | `lib/hiraeth_web/public_catalog.ex` | typed projection/filtering; home spotlight and four-title shelf selection; cover projection |
| `Hiraeth.Catalog.PublicProjection` | typed boundary | `lib/hiraeth/catalog/public_projection.ex` | projection structs + strict builders; covers carry content-hashed responsive variants |
| `HiraethWeb.Api.Spec` | OpenAPI document | `lib/hiraeth_web/api/spec.ex` | served at `/api/v1/openapi.json` |
| `HiraethWeb.Api.V1.CatalogController` | controller | `lib/hiraeth_web/api/v1/catalog_controller.ex` | versioned read endpoints |
| `HiraethWeb.Api.V1.Schemas` | wire schemas | `lib/hiraeth_web/api/v1/schemas.ex` | OpenAPI components |
| `HiraethWeb.Api.V1.Serializer` | serializer | `lib/hiraeth_web/api/v1/serializer.ex` | projection to JSON |
| `Hiraeth.Catalog` | Ash domain | `lib/hiraeth/catalog.ex` | canonical work/edition graph |
| `Hiraeth.Ingestion` | Ash domain | `lib/hiraeth/ingestion.ex` | provider runs, snapshots, candidates |
| `Hiraeth.Ingestion.SidecarClient` | HTTP client | `lib/hiraeth/ingestion/sidecar_client.ex` | typed boundary to private FastAPI sidecar |
| `Hiraeth.Sources` | Ash domain | `lib/hiraeth/sources.ex` | source records, ledgers, overrides |
| `Hiraeth.RealCatalog.SourcePolicy` | policy | `lib/hiraeth/real_catalog/source_policy.ex` | source/caching allowlists |
| `Hiraeth.RealCatalog.Importer` | trusted writer | `lib/hiraeth/real_catalog/importer.ex` | idempotent corpus seed into Catalog (validator-gated) |
| `Hiraeth.RealCatalog.Validator` | policy gate | `lib/hiraeth/real_catalog/validator.ex` | pre-seed findings gate; any finding blocks import |
| `Hiraeth.RealCatalog.SourceAuthority` | evidence generator | `lib/hiraeth/real_catalog/source_authority.ex` | regenerates/checks authority, artifact, and coverage manifests |
| `Hiraeth.RealCatalog.Refresh` | refresh orchestrator | `lib/hiraeth/real_catalog/refresh.ex` | fetch/merge/apply publisher datasets by refresh profile |
| `Hiraeth.RealCatalog.RefreshProfiles` | refresh policy | `lib/hiraeth/real_catalog/refresh_profiles.ex` | validates script/sidecar strategy coverage |
| `Hiraeth.ProvenanceAudit` | audit exporter | `lib/hiraeth/provenance_audit.ex` | source-ledger/takedown/cover-cache evidence exports |
| `Hiraeth.Ingestion.ManifestValidator` | manifest gate | `lib/hiraeth/ingestion/manifest_validator.ex` | validates provider manifests before ingestion accepts them |
| `Hiraeth.Covers` | domain facade | `lib/hiraeth/covers.ex` | cover cache safety + provenance |
| `Hiraeth.Covers.Policy` | read policy | `lib/hiraeth/covers/policy.ex` | picks the one public cover per work: newest print, non-print fallback |
| `Hiraeth.Catalog.PublicWorkProjection` | projector | `lib/hiraeth/catalog/public_work_projection.ex` | rebuilds `catalog_public_works` atomically and records a revision |
| `Hiraeth.Catalog.PublicWorks` | read facade | `lib/hiraeth/catalog/public_works.ex` | filters, sorts, searches, and pages the derived table |
| `HiraethWeb.CatalogPageController` | controller | `lib/hiraeth_web/controllers/catalog_page_controller.ex` | server-rendered catalogue pages and ETag/304 handling |
| `HiraethWeb.PageCache` | ETS cache | `lib/hiraeth_web/page_cache.ex` | caches static page bodies keyed by path/query |
| `Hiraeth.Oban.CoverBackfillWorker` | Oban worker | `lib/hiraeth/oban/cover_backfill_worker.ex` | boot-time cache fill for assets with no cached original |
| `Hiraeth.Oban.PublicProjectionWorker` | Oban worker | `lib/hiraeth/oban/public_projection_worker.ex` | rebuilds the public read model after imports/cover changes |
| `HiraethWeb.CatalogText` | text boundary | `lib/hiraeth_web/catalog_text.ex` | strips publisher markup/shortcodes; placeholder-name guard for contributor display |
| `HiraethWeb` public pages | browser surfaces | `lib/hiraeth_web/live`, `lib/hiraeth_web/controllers/catalog_page_controller.ex` | controller-rendered home/book/publisher/press/collections/contributors; LiveView browse/search |
| `Hiraeth.Oban.ProviderIngestionWorker` | Oban worker | `lib/hiraeth/oban/provider_ingestion_worker.ex` | per-provider fetch/normalize/apply pipeline |
| `Hiraeth.Oban.ProviderSchedulerWorker` | Oban worker | `lib/hiraeth/oban/provider_scheduler_worker.ex` | triggers provider runs on plan schedule |
| `Hiraeth.Oban.CoverRefreshWorker` | Oban worker | `lib/hiraeth/oban/cover_refresh_worker.ex` | weekly scheduled cover cache refresh |
| `Hiraeth.Oban.ProvenanceAuditWorker` | Oban worker | `lib/hiraeth/oban/provenance_audit_worker.ex` | weekly scheduled provenance audit export |
| `app.main` | FastAPI app | `sidecar/app/main.py` | sidecar routers + CORS/security posture |

## CONVENTIONS
- LiveView owns interactive browser UI (browse/search); record, publisher/press, collection, contributor, and home pages are controller-rendered from the read model. No React, no Vite SPA, no separate frontend app in v1.
- Use `agy` for substantial page/component design exploration before implementation.
- Use TDD for domain behavior, ingestion, normalization, provenance, cover handling, and UI flows.
- Ash resources/actions/policies are the domain source of truth; do not move business rules into controllers/templates.
- Use AshPostgres for persistence and AshPhoenix for Phoenix-facing Ash integration.
- Public UI reads typed projections; never serialize raw Ash/SQL/sidecar payloads into browser paths.
- Use `Req` for Elixir HTTP. Do not add HTTPoison/Tesla/httpc.
- Tailwind v4 stays in `assets/css/app.css` with `@import "tailwindcss" source(none);` and `@source` entries; never use `@apply`.
- Hiraeth is the only public skin: light-only, `sb-*` components, and values from `assets/css/tokens.css` / `assets/css/hiraeth.css`. Do not hardcode palette values, reintroduce a dark theme, or add remote fonts.
- Treat `design/` as reference material, not production code: `design/index.html` is the formal spec, the prototype pages under `design/` (`home.html`, `browse.html`, `book.html`, `press.html`, `publishers.html`, `series.html`, `shelf.html`) are static compositions, and the running implementation is `lib/hiraeth_web/live`. `design/**` is marked `linguist-documentation` in `.gitattributes`, so it stays tracked but is excluded from GitHub language stats.
- Render sourced publisher prose only through `HiraethWeb.CatalogText.plain/2`; never emit raw publisher HTML or shortcode soup. Use `CatalogText.unknown_contributor?/1` to suppress placeholder contributor names rather than fabricating replacements.
- Public covers are selected only by `Hiraeth.Covers.Policy`: the newest displayable print cover wins, with a newest non-print cover as the fallback. A split-format provider declares `cover_source` in its manifest; never hand-pick a cover in a LiveView or refresh the cache to change which edition is displayed.
- README captures are generated by `scripts/qa/live_screenshots.mjs` into versioned `docs/screenshots/hiraeth-*.png` names. Keep the versioned names when refreshing; GitHub can serve a stale image from a reused raw URL even after the file changes.
- LiveViews start templates with `<Layouts.app flash={@flash} ...>` and pass `current_scope` where required.
- Use `<.input>`, `<.icon>`, `<.link navigate|patch>`, `to_form`, and LiveView streams for collections.
- Local processes use Postgres `127.0.0.1:54320`, sidecar `127.0.0.1:8000`, Phoenix `127.0.0.1:4000`; start Postgres with `scripts/dev/ensure_postgres.sh start` (devenv files are dormant).
- Docker sidecar image (`sidecar/Dockerfile`) is the production service-network boundary; do not claim production is fully Nix/devenv-only.
- Prod runtime is hardened: force_ssl (exempts `/health`), Secure session cookie, JSON logs, `/ready` requires sidecar healthy; `DATABASE_URL`, `SCRAPLING_SIDECAR_URL`, and `SCRAPLING_SIDECAR_TOKEN` are required release env. The sidecar image runs in secure mode with server-side manifests and HMAC-signed requests.
- Public covers use a bounded local cache plus Cloudflare R2 when `HIRAETH_COVER_STORE=s3`; `/covers/cache/...` is same-origin and the proxy refills local misses from R2. New cache writes generate 200/400/800px WebP + JPEG variants with content-hashed filenames (ImageMagick `magick`/`convert`); originals/thumbnails carry a one-day cache and variants are immutable. Purge deletes every local and R2 copy.

## ANTI-PATTERNS (THIS PROJECT)
- Unversioned, write-capable, or undocumented HTTP surface. The only HTTP API is the read-only, schema-described `/api/v1` in `docs/api/v1.md`; new routes need a deliberate update to the route contract test and the OpenAPI document.
- Checkout/cart/account/social/reviews features in v1.
- Custom crawlers or scraping frameworks beyond Scrapling; random/Faker catalog metadata tests.
- Removing provider manifests, real-publisher datasets, source snapshots, or source-authority records without explicit publisher-removal authorization.
- Treating publisher permission as a reason to weaken official-source/provenance rules; sourced purchase links are preserved when present in the provider manifest, but missing links remain explicit gaps and must never be fabricated.
- Hotlinking remote cover images or rendering uncached/unsafe/hidden/takedown covers publicly.
- Runtime remote fonts or third-party scripts in public UI; pages and browser captures must stay self-contained.
- Touching `priv/static/covers/cache/*` during cleanup; use the sandbox/hash guard.
- Publicly exposing the sidecar, wildcard CORS, private/loopback/link-local fetch targets, or userinfo URLs.
- Rendering raw publisher HTML/shortcodes or placeholder contributor rows; use `HiraethWeb.CatalogText`.
- Adding a dark theme or hardcoded Hiraeth colors outside `assets/css/tokens.css`.
- Bypassing `Hiraeth.Covers.Policy` or treating a cover-cache refresh as the way to change which edition is displayed.
- Reusing a previous `docs/screenshots` filename after a visible redesign, which lets GitHub's raw image cache resurrect the old design.
- Treating the static `design/` prototypes or the Playwright capture scripts as a production surface or a `mix gate` browser lane; the hosted CI browser jobs are QA evidence, not runtime features.
- `Phoenix.HTML.form_for`, `<.form let=...>`, raw inline `<script>` in HEEx, `live_redirect`, `live_patch`, `<.flash_group>` outside layouts.

## COMMANDS
```bash
scripts/dev/ensure_postgres.sh start   # standalone postgres (127.0.0.1:54320)
mix gate                 # Layer 0 blocking gate (compile warnings-as-errors + format check + credo --strict + test.fast)
mix test.fast
mix test.full
HIRAETH_ALLOW_DEV_DB_RESET=1 make verify   # drops/reseeds dev DB; refuses non-local DATABASE_URL
make db-backup           # scripts/ops/db_backup.sh
make db-restore-drill    # scripts/ops/db_restore_drill.sh (separate DB only)
bash scripts/catalog/sync_sidecar_manifests.sh   # after changing a provider manifest
mix hiraeth.covers.upload                         # backfill R2 from the local cover cache
mix hiraeth.covers.sync --all --missing --json    # fill missing originals + thumbnails
mix hiraeth.covers.sync --all --variants          # render responsive WebP/JPEG variants
mix hiraeth.covers.audit --json                   # cover coverage report
mix hiraeth.real_catalog.sync --check             # authority/artifact/coverage drift gate
mix hiraeth.catalog.refresh --all --dry-run --json
mix hiraeth.public_projection.rebuild --json
node scripts/qa/design_screenshots.mjs http://127.0.0.1:4000 [outDir]
node scripts/qa/accessibility_screenshots.mjs http://127.0.0.1:4000 [outDir]
node scripts/qa/live_screenshots.mjs https://hiraeth.up.railway.app
cd sidecar && uv run --extra dev pytest -q
cd sidecar && uv run ruff check . && uv run pyright && uv audit
```

## NOTES
- `mix gate` checks compile with warnings-as-errors, unused deps, formatting (checks it, does not rewrite), strict Credo, and the fast test lane; sobelow/hex.audit/dialyzer are slower or network-dependent and run only in `mix ci`.
- Public API changes require updating `docs/api/v1.md`, the schema modules, and the two API contract tests together. The route contract test pins the exact `/api/v1` path list.
- `mix test.fast` excludes `slow`, `full_catalog`, `integration`, `performance`, `browser`, `public_catalog_full`. `mix test.full` is the complete suite; bare `mix test` runs the same default set.
- Verification runs locally (`mix gate`, `mix ci`, `make verify`) and in hosted GitHub Actions (`.github/workflows/ci.yml`): the gate job runs `mix gate`, the sidecar job runs pytest/ruff/pyright/audit, and the browser job runs `scripts/qa/design_screenshots.mjs` plus `scripts/qa/accessibility_screenshots.mjs` against a seeded dev server. `test/hiraeth/dev_environment_ci_contract_test.exs` pins those lanes. Browser checks stay out of `mix gate`.
- The Hiraeth spec at `design/index.html` reads computed values from `assets/css/tokens.css`; do not duplicate token values in templates or the spec. `design/**` is tracked but excluded from GitHub language statistics via `.gitattributes` (`linguist-documentation`); `.gitattributes` cannot untrack files, so use `.gitignore` plus `git rm --cached` if a file should actually leave Git.
- `HIRAETH_SERVICE_ROLE=worker` runs Oban without the endpoint. Railway production runs separate `web` and `worker` services; `mix hiraeth.public_projection.rebuild` is the manual recovery command and the worker is the normal owner. The legacy `HIRAETH_PUBLIC_READ_MODEL` flag is gone; `catalog_public_works` is the only public read path.
- Changing the Railway public domain means updating `PHX_HOST` on the `web` service too: it drives the canonical endpoint URL (sitemap/robots) and the default LiveView WebSocket origin check, so a stale value returns 403 on `/live/websocket` and leaves clients stuck on "Attempting to reconnect" until the longpoll fallback kicks in.
- Cover coverage self-heals: `HIRAETH_COVER_BACKFILL_ON_BOOT` (default true in prod) enqueues `CoverBackfillWorker` and `CoverVariantBackfillWorker` at boot, scoped to missing originals/variants and independent of `HIRAETH_SCHEDULED_INGEST`. Display selection is read-time `Covers.Policy`; a reissue with a newer print cover replaces the old cover without refetching unchanged assets. Variant filenames embed a content hash and are served `immutable`.
- README screenshots are versioned (`docs/screenshots/hiraeth-*.png`) and paired with `docs/screenshots/routes.json`. The live capture script writes both; the versioned names intentionally avoid GitHub's raw-image cache.
- devenv is dormant local-dev groundwork: local dev runs the nix-profile toolchain on bare PATH plus a standalone postgres via `scripts/dev/ensure_postgres.sh` (127.0.0.1:54320); CI lanes use setup-beam and a Postgres service, not devenv.
- `.omx`, `.omo`, `.omc`, `_build`, `deps`, `.devenv`, `.direnv`, caches, and artifacts are workspace/tool state unless a task explicitly targets them.
- Custom Mix aliases (`gate`, `ci`, `test.fast`, `test.full`) auto-run under `MIX_ENV=test` via `preferred_envs`; `mix test` auto-creates and migrates the DB first.
- `priv/repo/structure.sql` is a gitignored, untracked local pg_dump artifact; neither governed nor referenced. Do not commit it without explicit intent.
- Root `Dockerfile` builds the multi-stage release image (covers/cache is a bounded runtime directory, backed by R2 when configured); Docker remains the production-boundary reference while Railway runs the deployed catalog.
