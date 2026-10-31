# SIDECAR KNOWLEDGE BASE

## OVERVIEW
Private FastAPI + Pydantic + Scrapling service for approved provider fetch/scrape paths. It is an internal ingestion helper, not a public API.

## STRUCTURE
| Area | Owns |
|---|---|
| `app/main.py` | FastAPI app, router registration, CORS/security posture |
| `app/models.py` | request/response models, typed error contract |
| `app/url_validation.py` | HTTPS, host allowlist, private-network rejection |
| `app/provider_manifests.py` | secure-mode manifest registry and provider policy |
| `app/auth.py` | HMAC request authentication for data endpoints |
| `manifests/` | build-context copies of the governed provider manifests |
| `app/routers/fetch.py` | adapter-backed `/fetch/` endpoint |
| `app/routers/scrape.py` | spider-backed `/scrape/` and `/scrape/detail/` endpoints |
| `app/adapters/` | Shopify/Woo/Squarespace/WordPress fetch adapters |
| `app/spiders/` | provider-specific Scrapling spiders/parsers |
| `tests/` | pytest contract, URL safety, CORS, provider behavior |

## COMMANDS
```bash
uv run --extra dev uvicorn app.main:app --host 127.0.0.1 --port 8000
uv run --extra dev pytest -q
pytest tests/
```

## CONVENTIONS
- Use Scrapling only for scraping. Do not add another crawler/scraping framework.
- Keep docs/openapi/redoc UI disabled unless a task explicitly changes the private contract.
- CORS is env-driven by `HIRAETH_SIDECAR_CORS_ORIGINS`, exact-origin only, never wildcard.
- URL validation rejects private, loopback, link-local, localhost/internal, userinfo, and non-HTTPS fetch URLs unless a test fixture explicitly covers rejection.
- Routers map failures through typed errors from `models.py`; preserve error codes and snapshot contracts.
- Secure mode owns provider policy: the manifest on disk decides hosts and adapter config, and the request only names the provider. Never restore caller-supplied `source_hosts` in secure mode.
- Data requests require a timestamped HMAC signature when `HIRAETH_SIDECAR_TOKEN` is set. Keep `/health/` open.
- `manifests/` is a build-context copy of `priv/catalog_sources/provider_manifests`. Change the source, run `bash scripts/catalog/sync_sidecar_manifests.sh`, and keep `tests/test_manifest_sync.py` passing.
- Tests patch network calls with fixtures/mocks; do not require live external network for pytest.
- Async tests use existing anyio/pytest patterns; keep fixture HTML deterministic.
- Devenv loopback is preferred locally; the sidecar Dockerfile remains the production-boundary reference.
- Lint/type/supply-chain gates: `uv run ruff check .`, `uv run ruff format --check .`, `uv run pyright` (`pyrightconfig.json`, basic mode), and `uv audit` run in the deep CI lane; keep them passing.
- `httpx` is a runtime dependency (the hardened image boots on it); dev extras are pytest/ruff/pyright only.
- `Dockerfile` is hardened: pinned base image, no dev extras, non-root USER, healthcheck. Keep docs UI disabled and never publish host ports.
- Deploy the sidecar from a *sidecar-only* build context (stage `Dockerfile`, `railway.json`, `pyproject.toml`, `uv.lock`, `app/`, and `manifests/` in a directory outside the repo, then `railway up` there with explicit project/environment/service). Running `railway up` from inside the repo uploads the repository root and applies the web service's `railway.json`, which replaces the sidecar's Dockerfile build setting and boots the Phoenix image in its place.

## ANTI-PATTERNS
- Binding the sidecar publicly in local guidance.
- Adding discovery endpoints, broad provider enumeration, wildcard CORS, or public OpenAPI docs.
- Letting provider-specific URL checks drift into ad hoc string matching in routers.
- Hand-editing `sidecar/manifests/*.json`; they are generated copies.
- Disabling secure mode in the production image or accepting unsigned data requests when a token is configured.
- Returning untyped raw exceptions or changing snapshot output without updating contract tests.
- Downloading browsers at runtime when Nix/devenv supplies the browser executable.
