# Repository audit, 31 October 2026

Scope: the whole repository at commit `c20797e` plus the working tree changes
made during this audit. The audit covered Elixir application code, the Python
sidecar, configuration, scripts, tests, migrations, and the documentation claims
about all of them.

Method: four read-only review passes (catalog and public reads, ingestion and
sidecar, web and release posture, infrastructure and tests), followed by manual
verification of each finding before a fix. Verification means reading the code
path, running the query or test that exposes it, or reproducing the behavior in
`elixir` or `python3`. Findings that could not be verified are marked as such.

## Baseline and final state

| Check | Before | After |
|---|---|---|
| `mix compile --warnings-as-errors` | clean | clean |
| `mix test.fast` | 517 passed | 534 passed |
| `mix test.full` | not run | 534 passed |
| `mix ci` | not run | passed, 534 tests |
| `mix dialyzer` | 2 errors (`call_without_opaque` on literal `MapSet`s) | 0 errors |
| `mix credo --strict` | clean | clean |
| `mix format --check-formatted` | clean | clean |
| `mix sobelow --exit Low` | passed only with a `Config.CSP` exemption | passes without the exemption |
| `mix hex.audit` | advisories in ash, ash_phoenix, ash_postgres, ash_sql, bandit, mint, phoenix_html, phoenix_live_view, plug_crypto, decimal | no advisories |
| Sidecar `pytest` | 1 failure (stale OpenAPI snapshot) | 124 passed |
| Sidecar `uv audit` | `protego` and `anyio` advisories | no advisories |
| Sidecar `ruff`, `ruff format --check`, `pyright` | clean | clean |

## Critical findings, fixed

### Provider sources had three identities and could point at a URL

`RunState` registered sources as `publisher:<provider>:<mode>`, `CoverCandidateRun`
registered the same provider as `publisher:<provider>:manifest`, and the registry
backfill used the bare provider slug. The two lazy paths also stored the
provider's first source URL in `manifest_uri`. The scheduler dispatches
`manifest_path: source.manifest_uri`, and `ProviderManifest.load!/1` calls
`File.read!/1`, so those rows could never succeed. Because the scheduler sorts
never-succeeded sources first and takes two per tick, the phantom rows could
consume every dispatch slot.

Fix: both lazy paths now use the bare provider slug and the checked-in manifest
path. `ProviderManifest` records the path it was loaded from, so the stored path
is the one the worker can open. A legacy row is still matched for the source
link, but the scheduler skips any source whose manifest is not a readable local
file, with a `:manifest_missing` skip event, before the dispatch cap.

### `make verify` could drop a production database

The `audit-provenance` recipe ran `mix ecto.drop --force` without setting
`MIX_ENV`, which targets the development database. `config/dev.exs` honors
`DATABASE_URL`, so an ambient URL from `railway run` or a shell export pointed
that drop at the production database. The seeded audit could also pass on an
empty catalog: the seed return value was discarded, and the summary gate only
checked for empty finding lists.

Fix: the recipe refuses to run without `HIRAETH_ALLOW_DEV_DB_RESET=1` and refuses
any `DATABASE_URL` that is not local. The seed task exits on `{:error, findings}`
and exits when a seeded audit finds zero source records. The Makefile and summary
script both require `source_records` to be positive.

### Orphaned Oban jobs could wedge a provider permanently

The ingestion worker had no `timeout/1`, and Oban's default is `:infinity`. The
job's unique key includes `:executing` with `period: :infinity`, and no Lifeline
was configured. A deploy during a run left the job `executing` forever, which
blocked every later insert for that provider, and the run stayed `running`, which
blocked the scheduler through `active_run_for/1`.

Fix: the worker declares a 45-minute timeout and Oban runs `lifeline:
[rescue_after: {1, :hour}]`, the current configuration shape for `Oban.Lifeline`
in Oban 2.24. `Oban.Plugins.Lifeline` is deprecated.

### The audit phase could fail a run after its apply committed

`Phases.AuditRun` called `ProvenanceAudit.run!/1` with `fail_on_error?: true`
after `ApplyCandidates` had written the catalog. An audit finding, or an
unwritable `artifacts/` directory in a release image, marked an applied run
failed and retried the entire pipeline.

Fix: the audit phase now runs with `fail_on_error?: false`. A failed audit still
writes a failed phase event and records `audit_error`, but the run completes.
The audit output directory writability and per-run isolation remain open; see
residual risks.

## High findings, fixed

| Finding | Evidence | Fix |
|---|---|---|
| Query parameter shape crashed the public LiveViews | `?q[a]=b` becomes a map, and `filter_value/2` called `to_string/1` on it | `CatalogFilterParams` keeps only scalar values; `filter_value/2` returns nil for maps and lists |
| An enormous `page` reached Postgrex as an int8 offset | `?page=10^26` produced a `DBConnection.EncodeError` | page capped at 10,000 before the offset is built, in both `book_page/3` and `paginate/3` |
| Every `sort` value was accepted and ignored | `work_page_order_sql/1` returned the publication-date order for all inputs | `title`, `author`, and `recently_added` orders implemented; the home page's `recently_added` link now matches its label |
| The cache stored misses keyed by arbitrary slugs | `/publishers/<random>` added a `:persistent_term` key per request | misses are no longer cached |
| `/ready` bounded only the receive timeout | Req's Finch connect timeout defaults to 30 seconds | connect timeout set to the same 500 ms as the receive timeout |
| No request body limit; multipart enabled with no body-consuming route | `Plug.Parsers` defaults to 8 MB | multipart removed, body cap 100 KB |
| The CSP Sobelow exemption outlived the CSP | `.sobelow-conf` ignored `Config.CSP` while `router.ex` already set a CSP | exemption removed; `security_headers_test.exs` asserts the header |
| `SourceLedgerEntry` exposed `:destroy` and `:update` | append-only evidence was mutable by a trusted actor | update and destroy actions removed; only `:create` and `:read` remain |
| Sidecar failures escaped as untyped 500s | `scrape.py` caught only `RuntimeError` and `ValueError` | routers catch `httpx` errors by type, re-raise intentional `HTTPException`s, and map unknown failures to a typed `internal_error` |
| `SidecarClient` could raise on a non-map 2xx body | `body["status"]` on a string body | response bodies are guarded; a non-object body returns a typed error |
| `SidecarClient` crashed on a missing base URL | `nil[:base_url]` | a named `ArgumentError` explains the missing configuration |

## Medium findings, fixed

| Finding | Fix |
|---|---|
| Several dependency families had known advisories | Elixir dependencies updated to the latest stable releases within their major versions; `default_string_length_count: :codepoints` set for the Ash 3.37 security change. Sidecar `protego` and `anyio` updated; `uv audit` is clean |
| Literal `MapSet` module attributes failed Dialyzer's opaque check | replaced with lists and membership tests |
| `mix ci` called `sobelow --config .sobelow-conf`, which Sobelow 0.18 rejects | command corrected; the config file is auto-loaded |
| `mix ci` did not run Dialyzer despite the README claiming it did | `dialyzer` added to the `ci` alias |
| The OpenAPI snapshot test failed after a dependency update | snapshot regenerated and reviewed; the new `internal_error` code is part of it |
| Publisher and series pages used bracket access on new structs | converted to dot access; `get_in/2` on an `Edition` replaced with field access |

## Residual risks, not fixed

These are verified defects or design limits that need a decision beyond this
change. Severity is the reviewer's assessment.

| Severity | Issue | Why it matters |
|---|---|---|
| Critical | Sidecar host allowlist arrives in the request body, and the sidecar has no authentication | Any caller that can reach the sidecar can allowlist an internal host. The service is private by network placement, not by its own boundary. Fix: load manifests server-side, resolve and pin the host, require a shared secret. |
| High | `expected_record_count` is an exact equality gate and validation is all-or-nothing | A publisher adding one book fails the whole provider run; one malformed record quarantines nothing and fails everything. |
| High | "unchanged" is derived from the previous candidate row, not from applied catalog state | A run that fails before apply makes the next run classify everything unchanged and import nothing. |
| High | Cancellation sets the job and run cancelled while the worker keeps executing to the next phase boundary | Apply can write after the operator is told the run is cancelled; the unique lock is released early. |
| Medium | Snapshot provenance is synthesized | `source_mode` says scrape when the API fallback produced the records, and `http_metadata.status` is hardcoded to 200. |
| Medium | Snapshot dedupe binds new candidates to an older run's snapshot | Provenance joins are ambiguous; the check is also not atomic. |
| Medium | Audit artifacts are written to one shared directory per run | Concurrent providers interleave writes; a release image without a writable `artifacts/` records a failed audit on every run. |
| Medium | Telemetry is inert in production | The poller gets `measurements: []` and no reporter is attached, so the declared metrics never leave the VM. |
| Medium | Oban runs in the web service | Ten job slots share a `pool_size` of 10 with page queries; a scheduler tick or cover refresh can starve the web pool. |
| Medium | Nothing runs migrations on deploy | A schema-changing deploy serves 500s until an operator runs `mix ash.migrate`. |
| Medium | `check_origin` is not configured | A second hostname makes every LiveView socket upgrade fail with a 403 while pages still render. |
| Medium | Cover paths resolve against the process working directory | Starting the release outside `/app` silently degrades every cover to the fallback. |
| Low | `Port` and `POOL_SIZE` parse with `String.to_integer/1` on an empty string | A defined-but-empty Railway variable raises before logging is configured. |
| Low | Documentation still claims files and lanes that do not exist | `docs/production-operations.md`, a release-build CI gate, `compose.yaml`, `live_session` boundaries, and a browser QA lane are all absent. |

## Findings that could not be verified

- Scrapling runtime behavior. The package is present in the sidecar lockfile but
  was not exercised against a live provider during this audit.
- Railway network reachability of the sidecar. The SSRF issue is real from the
  code, but whether an untrusted caller can reach the private service depends on
  the deployed network policy.
- Wall-clock cost of a full provider ingestion. No live sidecar call was made.
  Local catalog read latency was measured and is recorded in the scalability
  note.

## Test additions

- `test/hiraeth/public_api_contract_test.exs`: spec and `t/0` coverage for the
  public modules.
- `test/hiraeth_web/api/spec_contract_test.exs`: OpenAPI document shape.
- `test/hiraeth_web/api/v1_catalog_api_test.exs`: every endpoint validated
  against the served schema.
- `test/hiraeth_web/security_headers_test.exs`: the CSP survives.
- Public projection tests now assert typed publisher, series, contributor, and
  edition shapes, a huge page, malformed filter shapes, the title sort, and the
  author sort.
