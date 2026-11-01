# Cover sourcing and delivery

Hiraeth serves covers only from its own cache. A publisher cover URL is
provenance, not a public asset: the browser never hotlinks `images.penguinrandomhouse.com`,
`cdn.shopify.com`, Squarespace, S3, or any other remote host.

## One pipeline

```
official publisher page/API
  → record.cover.source_url (dataset)
  → HTTPS + provider cover-host allowlist
  → bounded fetch (redirect allowlist, body cap, image type allowlist)
  → priv/static/covers/cache/<sha>.<ext>
  → legacy 400×600 JPEG thumbnail
  → 200/400/800px WebP + JPEG responsive variants, content-hashed filenames
  → Cloudflare R2 (when HIRAETH_COVER_STORE=s3)
  → /covers/cache/... same-origin response
  → typographic fallback only for an explicit gap
```

Policy is owned by `priv/catalog_sources/provider_manifests/<provider>.json`
and `source_authority_manifest.json`; the runtime gate is
`Hiraeth.RealCatalog.SourcePolicy`. A cover is cache-eligible only when:

- `takedown_state == "visible"`
- `cache_policy == "cache_allowed"`
- `rights_basis == "local_cache_permitted"`
- the source URL is HTTPS and its host is in the provider's `cover_hosts`
- the provider is present in the source authority manifest

A record without a usable cover URL carries `no_cover_reason`; the UI renders a
typographic fallback. Nothing is fabricated.

## Operator commands

```sh
# Fill missing local files/thumbnails for one provider or all providers.
mix hiraeth.covers.sync --provider astra_house_official_store --json
mix hiraeth.covers.sync --all --missing --json
mix hiraeth.covers.sync --all --variants

# Report coverage without writing.
mix hiraeth.covers.audit --json
mix hiraeth.covers.audit --provider seven_stories_press_official_site --strict

# Legacy aliases remain valid.
mix hiraeth.cache_covers
mix hiraeth.covers.upload
```

`covers.sync` first tries a configured durable store, then falls back to the
same bounded `Covers.req_fetch!/4` source fetch as the weekly worker. It writes
the cache file atomically, generates the thumbnail and responsive variant set,
updates `cached_file_path` / `thumbnail_file_path` / `responsive_variants` /
`cached_at`, and uploads every object to R2 when configured. `--variants`
renders variants from an existing local original without fetching the publisher. It exits non-zero if an eligible cover remains uncached; use
`--allow-missing` to report only.

Thumbnail and variant generation use ImageMagick 7 (`magick`) or ImageMagick 6
(`convert`). The Docker runtime installs `imagemagick`; local bare-toolchain
users can add it with `nix profile add nixpkgs#imagemagick`. If the command is
missing, originals are still cached and the missing thumbnails/variants are
reported so the next run can retry.

## Delivery

- `Plug.Static` serves originals and legacy thumbnails with
  `cache-control: public, max-age=86400` and `x-content-type-options: nosniff`.
- Responsive variant URLs embed a SHA-256 of their own bytes, so the proxy
  serves them with `cache-control: public, max-age=31536000, immutable`.
- The `HiraethWeb.CoverController` refill path checks the database policy,
  fetches from R2, writes the local file atomically, and returns the same
  headers. A local hit never touches R2.
- Cards, shelves, and book heroes render a `<picture>` element with WebP and
  JPEG `srcset` entries at 200/400/800px. The 400px JPEG remains the fallback
  and the legacy thumbnail URL stays available for old payloads.
- Browser caches can retain an original or thumbnail for up to 24 hours.
  Variants are immutable by URL. Purging removes local and R2 copies
  immediately, so the proxy cannot serve them again.
- `Hiraeth.Covers.Policy` is the single cover decision for every public read.
  A work shows exactly one cover, owned by one edition: the newest print
  (paperback/hardcover) cover wins, so a reissued title shows the new printing's
  cover (or the publisher's "cover coming soon" image) instead of the retired
  one. A work with no displayable print cover falls back to its newest
  displayable non-print cover. Cards, the hero, and the API all receive the
  same cover object.

## Backfill after a seed or import

A seed only adopts cover files that already exist in the local cache; new
cover URLs stay uncached until a cache pass runs. Two mechanisms close that
gap:

- `mix hiraeth.covers.sync --all --missing` fills everything immediately and is
  the operator path after a manual seed. With `HIRAETH_COVER_STORE=s3` it
  uploads originals and thumbnails to R2.
- In production, `Hiraeth.Oban.CoverBackfillWorker` runs once at boot and is
  scoped to assets with no cached original. `Hiraeth.Oban.CoverVariantBackfillWorker`
  then renders missing responsive variants from those local originals. Both are
  no-ops when coverage is complete, and their ten-minute unique windows collapse
  restart storms. Set `HIRAETH_COVER_BACKFILL_ON_BOOT=false` to disable them;
  unlike cron, they are not governed by `HIRAETH_SCHEDULED_INGEST` because they
  never ingest catalog data, only cache covers already present in the governed
  dataset. The weekly `CoverRefreshWorker` remains the full-catalog sweep.

## Provider refresh and covers

`mix hiraeth.catalog.refresh --apply` runs the publisher refresh, imports the
merged dataset, and (unless `--skip-covers`) invokes the same provider-scoped
cover sync. The refresh strategy per provider lives in
`priv/catalog_sources/refresh_profiles.json`:

- scripts: `generate_full_catalog.py`, `extract_fitzcarraldo_catalog.py`,
  `extract_seven_stories_catalog.py`
- sidecar manifests: Astra House, And Other Stories, Coffee House, Seagull,
  Wakefield, NYRB, McNally, Tilted Axis, Unnamed Press, Pushkin Press

Publisher datasets and their cover URLs are regenerated from official sources;
the generated authority/artifact/coverage evidence is refreshed by the same
command.

When a Squarespace shop lists one product per format, the manifest can declare
the canonical print listing instead of relying on whichever product the shop
returns first:

```json
"cover_source": {
  "endpoint": "https://www.tiltedaxispress.com/shop?category=print",
  "match": "title"
}
```

The sidecar sources print products' covers from that listing, so a reissue or
corrected listing replaces whichever image the general shop listing exposed.
Non-print products keep their own cover only as a digital-only fallback; the
work-level policy still renders the print cover whenever the work has one, so a
title never shows two formats' art. Tilted Axis Press uses this declaration. The
manifest field is generic: another provider with the same print/digital split
only needs the manifest entry, not a provider-specific code path or a manual
cover pass.

## Current coverage notes

The five publishers that previously rendered no covers have dataset cover
metadata:

| Publisher | Provider slug |
|---|---|
| Astra House | `astra_house_official_store` |
| Pushkin Press | `pushkin_press_official_site` |
| Seven Stories Press | `seven_stories_press_official_site` |
| Tilted Axis Press | `tilted_axis_press_official_site` |
| Wakefield Press | `wakefield_press_official_store` |

Seven Stories has a small number of dead source image URLs (HTTP 403) in the
checked-in corpus. They remain explicit `missing_cache` findings rather than
being replaced with an invented image. A later discovery pass can resolve a new
official URL from the product page.

## Verification

- `mix hiraeth.covers.audit --json` is the coverage report.
- Cache-writing tests use a sandbox cache root; the root
  `priv/static/covers/cache/*` tree is never cleaned or regenerated by QA
  scripts. Run cache-writing checks through `scripts/qa/cover_cache_sandbox.sh`
  as required by the repository cleanup contract.
- Live checks after a deploy: request a `/covers/cache/*-thumb.jpg` URL and
  assert `cache-control`/`x-content-type-options`; open the five publisher
  pages and confirm cover images; open `/publishers/deep-vellum` and confirm
  the folded imprints are present.
