defmodule Hiraeth.Oban.CoverBackfillWorker do
  @moduledoc """
  Oban worker that caches cover assets which have no cached original yet.

  A seed, import, or publisher refresh can add cover assets faster than the
  weekly `CoverRefreshWorker` runs, and a cold container has no local files to
  adopt, so the public projection hides those covers until a cache pass fills
  them. This worker runs the same cache pipeline scoped to the assets that are
  actually missing, which keeps the catalog self-healing after an import or a
  fresh deploy without re-fetching every cover on the site.

  It never forces a refresh, never invents a cover, and reports failures rather
  than raising, matching the weekly worker's non-strict behavior. Job args can
  scope a run for tests or operators:

    * `"cache_root"` — an alternate cache root under
      `priv/static/covers/cache` (rejected by the sandbox guard otherwise)
    * `"source_urls"` — restrict the pass to specific cover source URLs
  """

  use Oban.Worker,
    queue: :covers,
    unique: [period: 600],
    max_attempts: 1

  alias Hiraeth.Covers

  @default_cache_root "priv/static/covers/cache"

  def default_cache_root, do: @default_cache_root

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args = args || %{}
    source_urls = Map.get(args, "source_urls") || Covers.missing_cache_source_urls()

    if source_urls == [] do
      {:ok, %{missing: 0, cached: 0, thumbnails: 0, failed: 0}}
    else
      summary =
        Covers.cache_public_covers!(
          source_urls: source_urls,
          cache_root: Map.get(args, "cache_root", @default_cache_root),
          timeout: 30_000,
          max_concurrency: 4
        )

      {:ok,
       %{
         missing: length(source_urls),
         cached: summary.cached,
         thumbnails: summary.thumbnails,
         failed: summary.failed
       }}
    end
  end
end
