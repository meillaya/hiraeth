defmodule Mix.Tasks.Hiraeth.Covers.Sync do
  @moduledoc """
  Caches missing public covers and thumbnails, then audits the result.

  Usage:
      mix hiraeth.covers.sync --provider <slug> [--force] [--json]
      mix hiraeth.covers.sync --all [--force] [--json]
      mix hiraeth.covers.sync --all --allow-missing
      mix hiraeth.covers.sync --all --variants

  `--variants` renders the responsive WebP/JPEG set from local originals
  instead of fetching publisher sources. An asset without a cached original is
  skipped until the original-cover pass has run.

  The task never fabricates a cover. A failed fetch or thumbnail leaves the
  asset uncached and is reported in the summary; the command exits non-zero
  unless `--allow-missing` is given.
  """

  use Mix.Task

  alias Hiraeth.Covers

  @shortdoc "Caches missing public covers and thumbnails"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case do_run(args) do
      :ok ->
        :ok

      {:error, message} ->
        Mix.shell().error(message)
        exit({:shutdown, 1})
    end
  end

  @doc false
  def do_run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          provider: :string,
          all: :boolean,
          force: :boolean,
          missing: :boolean,
          variants: :boolean,
          json: :boolean,
          allow_missing: :boolean,
          cache_root: :string,
          concurrency: :integer,
          timeout: :integer
        ],
        aliases: [f: :force]
      )

    provider = Keyword.get(opts, :provider)
    all? = Keyword.get(opts, :all, false)

    cond do
      is_binary(provider) and String.trim(provider) != "" and all? ->
        {:error, "Use either --provider <slug> or --all, not both."}

      is_binary(provider) and String.trim(provider) != "" ->
        sync(provider, opts)

      all? ->
        sync(nil, opts)

      true ->
        {:error, "Usage: mix hiraeth.covers.sync --provider <slug> | --all [--json]"}
    end
  end

  defp sync(provider, opts) do
    summary =
      Covers.cache_public_covers!(
        provider: provider,
        force?: Keyword.get(opts, :force, false),
        variants_only?: Keyword.get(opts, :variants, false),
        cache_root: Keyword.get(opts, :cache_root, "priv/static/covers/cache"),
        max_concurrency: Keyword.get(opts, :concurrency, 4),
        timeout: Keyword.get(opts, :timeout, 15_000)
      )

    audit = Covers.audit_cache(provider: provider)
    print(summary, audit, opts)

    if failed?(summary, audit, opts) and not Keyword.get(opts, :allow_missing, false) do
      {:error,
       "cover sync left missing cache entries; rerun or pass --allow-missing to report only."}
    else
      :ok
    end
  end

  defp failed?(summary, audit, opts) do
    summary.failed > 0 or
      Enum.any?(audit, fn row ->
        row.missing_cache > 0 or row.missing_thumbnails > 0 or
          (Keyword.get(opts, :variants, false) and row.missing_variants > 0)
      end)
  end

  defp print(summary, audit, opts) do
    payload = %{
      cached: summary.cached,
      thumbnails: summary.thumbnails,
      variants: summary.variants,
      skipped: summary.skipped,
      failed: summary.failed,
      failures: summary.failures,
      audit: audit
    }

    if Keyword.get(opts, :json, false) do
      Mix.shell().info(Jason.encode!(payload, pretty: true))
    else
      Mix.shell().info("cover_cache_cached=#{summary.cached}")
      Mix.shell().info("cover_cache_thumbnails=#{summary.thumbnails}")
      Mix.shell().info("cover_cache_variants=#{summary.variants}")
      Mix.shell().info("cover_cache_skipped=#{summary.skipped}")
      Mix.shell().info("cover_cache_failed=#{summary.failed}")

      Enum.each(summary.failures, fn failure ->
        Mix.shell().info("cover_cache_failure=#{failure.source_url}: #{failure.reason}")
      end)

      print_audit(audit)
    end
  end

  defp print_audit(audit) do
    Enum.each(audit, fn row ->
      Mix.shell().info(
        "cover_audit provider=#{row.provider} assets=#{row.assets} eligible=#{row.eligible} " <>
          "cached=#{row.cached} thumbnails=#{row.thumbnails} variants=#{row.variants} " <>
          "missing_cache=#{row.missing_cache} missing_thumbnails=#{row.missing_thumbnails} " <>
          "missing_variants=#{row.missing_variants}"
      )
    end)
  end
end
