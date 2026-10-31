# Hiraeth Sidecar

FastAPI microservice that runs Scrapling spiders and fetch adapters alongside the Hiraeth Phoenix application.

## Run locally from a devenv shell (preferred today)

The current local Hiraeth sidecar transport is loopback. `devenv.nix`
declares a managed `scrapling-sidecar` process that binds `127.0.0.1:8000`;
use the devenv process runner or the configured `test:sidecar-ready` task for
managed local checks. For direct debugging, run the same app from a `devenv
shell` and point Phoenix at loopback:

```bash
# terminal 1 (direct debugging path)
devenv shell
cd sidecar
uv run --extra dev uvicorn app.main:app --host 127.0.0.1 --port 8000

# terminal 2
devenv shell
SCRAPLING_SIDECAR_URL=http://127.0.0.1:8000 mix phx.server
```

The sidecar process must bind to `127.0.0.1:8000` for local host access only.
Do not publish it on `0.0.0.0` or expose it directly to the public internet.
Local devenv process management does not make the Phoenix/sidecar production
runtime Nix/devenv-only. Docker remains the production runtime boundary
reference: Railway builds the Phoenix service from the root `Dockerfile` and
the sidecar from `sidecar/Dockerfile`, and Phoenix reaches the private
sidecar over the Railway private network.

## Run locally without devenv

Requires Python 3.11+.

```bash
cd sidecar
uv pip install -e ".[dev]"
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

## Run with Docker fallback

```bash
docker build -t hiraeth-sidecar sidecar/
docker run -p 127.0.0.1:8000:8000 -e HIRAETH_SIDECAR_TOKEN=dev-secret hiraeth-sidecar
```

The image runs in secure mode. It requires `HIRAETH_SIDECAR_TOKEN`, loads the
provider manifests copied into `sidecar/manifests`, and rejects data requests
that are not signed by Phoenix. Run `bash scripts/catalog/sync_sidecar_manifests.sh`
after changing a manifest under `priv/catalog_sources/provider_manifests`;
`tests/test_manifest_sync.py` fails when the copies drift.

The direct `docker run` command is a loopback-only debugging fallback for the
sidecar image; everyday local development runs through devenv. In production
the sidecar builds from `sidecar/Dockerfile` on Railway and stays private on
the Railway private network, with no public domain or host port, with Phoenix
reaching it via `SCRAPLING_SIDECAR_URL=http://sidecar.railway.internal:8000`.

Do not expose the sidecar directly to the public internet.

## Secure mode

The production image sets `HIRAETH_SIDECAR_REQUIRE_SECURE=1`,
`HIRAETH_PROVIDER_MANIFESTS_DIR=/app/manifests`, and requires
`HIRAETH_SIDECAR_TOKEN`. In secure mode:

- the provider manifest on disk decides `source_hosts`, `cover_hosts`, and the
  adapter configuration, and the request configuration is ignored;
- `/fetch/`, `/scrape/`, and `/scrape/detail` require
  `x-hiraeth-timestamp` and `x-hiraeth-signature`, an HMAC-SHA256 over
  `<timestamp>.<raw body>` using the shared token, within 300 seconds;
- `/health/` stays open for the platform probe;
- a provider without a manifest is rejected with `provider_unknown`.

Phoenix signs requests when `SCRAPLING_SIDECAR_TOKEN` is configured and requires
it in production. Both services must use the same value. Local direct-debug runs
without the token remain open, which is a development posture only.

## CORS

Browser CORS is disabled unless explicit origins are configured. Set
`HIRAETH_SIDECAR_CORS_ORIGINS` to a comma-separated list of exact Phoenix
origins that may call the sidecar from a browser:

```bash
HIRAETH_SIDECAR_CORS_ORIGINS=http://localhost:4000 uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Origins must include an `http` or `https` scheme and host, for example
`http://localhost:4000` or `https://catalog.example.com`. Wildcards such as
`*` are rejected at startup. Server-to-server calls from Phoenix do not need
CORS; prefer keeping the sidecar private and unset this variable in production
unless browser access is explicitly required.

## Test

```bash
cd sidecar
pytest tests/
```

## Endpoints

- `GET /health/`: liveness probe
- `POST /fetch/`: allowlisted provider API fetch. In secure mode the server manifest decides the endpoint. Outside secure mode the request config must supply an HTTPS endpoint on a public host listed in `config.source_hosts`.
- `POST /scrape/`: Scrapling catalog scrape. Provider-specific spiders retain their own allowlists. In secure mode the server manifest supplies the start URLs and hosts; otherwise generic scraping requires non-empty `config.start_urls` whose HTTPS public hosts match explicit `config.source_hosts`.
- `POST /scrape/detail`: allowlisted publisher detail enrichment.
