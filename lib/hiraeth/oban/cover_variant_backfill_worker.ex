defmodule Hiraeth.Oban.CoverVariantBackfillWorker do
  @moduledoc """
  Oban worker that builds responsive WebP/JPEG variants for cached covers.

  The original cover cache predates responsive delivery, so a deploy carries
  assets whose originals are cached but whose variants do not exist yet. This
  pass runs after the original-cover backfill, is scoped to assets with a local
  original, and is a no-op once every variant set is complete.

  It never fetches a publisher URL: variants are rendered from the already
  cached original, so a failure leaves the existing single-cover URL in place.
  """

  use Oban.Worker,
    queue: :covers,
    unique: [period: 600],
    max_attempts: 1

  alias Hiraeth.Covers

  require Logger

  @default_cache_root "priv/static/covers/cache"
  @batch_size 100

  def default_cache_root, do: @default_cache_root

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args = args || %{}
    source_urls = Map.get(args, "source_urls") || Covers.missing_variant_source_urls()

    if source_urls == [] do
      {:ok, %{missing: 0, variants: 0, failed: 0}}
    else
      batch = Enum.take(source_urls, @batch_size)

      Logger.info(
        "cover variant backfill started batch=#{length(batch)} remaining=#{length(source_urls)}"
      )

      summary =
        Covers.cache_public_covers!(
          source_urls: batch,
          variants_only?: true,
          cache_root: Map.get(args, "cache_root", @default_cache_root),
          timeout: 20_000,
          max_concurrency: 4
        )

      Logger.info(
        "cover variant backfill finished variants=#{summary.variants} failed=#{summary.failed}"
      )

      if length(source_urls) > length(batch) and summary.failed == 0 do
        %{"batch" => System.unique_integer([:positive])}
        |> __MODULE__.new(schedule_in: 5)
        |> Oban.insert()
      end

      {:ok,
       %{
         missing: length(source_urls),
         variants: summary.variants,
         failed: summary.failed
       }}
    end
  end
end
