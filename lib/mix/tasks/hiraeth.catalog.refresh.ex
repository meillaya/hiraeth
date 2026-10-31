defmodule Mix.Tasks.Hiraeth.Catalog.Refresh do
  @moduledoc """
  Refreshes one or all real-publisher datasets from their official sources.

  Usage:
      mix hiraeth.catalog.refresh --provider <slug> --dry-run [--json]
      mix hiraeth.catalog.refresh --provider <slug> --apply [--json]
      mix hiraeth.catalog.refresh --all --apply [--json]

  Options:
    * `--dry-run` (default) fetches and diffs without writing.
    * `--apply` writes the dataset, regenerates evidence, imports it, and
      optionally caches covers.
    * `--replace-existing` replaces existing records with the source candidate.
    * `--prune` replaces the dataset with the source candidate; removals require
      `--allow-removals`.
    * `--skip-covers` skips the post-import cover sync.
    * `--python PATH` overrides the script interpreter.
  """

  use Mix.Task

  alias Hiraeth.RealCatalog.{Refresh, RefreshProfiles}

  @shortdoc "Refreshes publisher datasets from official sources"

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
    opts = parse_options(args)

    case validate_options(opts) do
      :ok ->
        RefreshProfiles.validate!()
        refresh(providers(opts), mode(opts), Keyword.get(opts, :apply, false), opts)

      {:error, message} ->
        {:error, message}
    end
  rescue
    error -> {:error, "refresh setup failed: #{Exception.message(error)}"}
  end

  defp parse_options(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          provider: :string,
          all: :boolean,
          apply: :boolean,
          dry_run: :boolean,
          allow_removals: :boolean,
          replace_existing: :boolean,
          prune: :boolean,
          skip_covers: :boolean,
          json: :boolean,
          python: :string
        ]
      )

    opts
  end

  defp validate_options(opts) do
    provider = Keyword.get(opts, :provider)
    all? = Keyword.get(opts, :all, false)

    cond do
      all? and is_binary(provider) ->
        {:error, "Use either --provider <slug> or --all, not both."}

      Keyword.get(opts, :apply, false) and Keyword.get(opts, :dry_run, false) ->
        {:error, "Use either --dry-run or --apply, not both."}

      not all? and (is_nil(provider) or String.trim(provider) == "") ->
        {:error,
         "Usage: mix hiraeth.catalog.refresh --provider <slug> | --all [--dry-run|--apply]"}

      true ->
        :ok
    end
  end

  defp providers(opts) do
    if Keyword.get(opts, :all, false) do
      RefreshProfiles.providers()
    else
      [Keyword.fetch!(opts, :provider)]
    end
  end

  defp refresh(providers, mode, apply?, opts) do
    results =
      Enum.map(providers, fn provider ->
        result = refresh_provider(provider, mode, apply?, opts)
        print_provider(result, opts)
        result
      end)

    errors = Enum.filter(results, &match?(%{status: "error"}, &1))

    if Keyword.get(opts, :json, false) do
      Mix.shell().info(
        Jason.encode!(%{mode: mode, apply: apply?, providers: results}, pretty: true)
      )
    end

    if errors == [] do
      :ok
    else
      {:error,
       "#{length(errors)} provider refresh(es) failed: #{Enum.map_join(errors, ", ", & &1.provider)}"}
    end
  end

  defp refresh_provider(provider, mode, apply?, opts) do
    case Refresh.fetch(provider, opts) do
      {:ok, candidate} -> candidate_result(provider, candidate, mode, apply?, opts)
      {:error, reason} -> error_result(provider, reason)
    end
  end

  defp candidate_result(provider, candidate, mode, true, opts) do
    case Refresh.apply(provider, candidate,
           mode: mode,
           allow_removals: Keyword.get(opts, :allow_removals, false),
           covers: not Keyword.get(opts, :skip_covers, false),
           python: Keyword.get(opts, :python)
         ) do
      {:ok, summary} -> Map.put(summary, :status, "applied")
      {:error, reason} -> error_result(provider, reason)
    end
  end

  defp candidate_result(provider, candidate, mode, false, opts) do
    with {:ok, current} <- Refresh.current_dataset(provider),
         {:ok, diff} <-
           Refresh.merge(current, candidate,
             mode: mode,
             allow_removals: Keyword.get(opts, :allow_removals, false)
           ) do
      dry_run_result(provider, diff)
    else
      {:error, reason} -> error_result(provider, reason)
    end
  end

  defp dry_run_result(provider, diff) do
    %{
      status: "dry_run",
      provider: provider,
      new: diff.new,
      changed: diff.changed,
      retained: diff.retained,
      removed: diff.removed,
      new_sample: Enum.take(diff.new_keys, 10),
      removed_sample: Enum.take(diff.removed_keys, 10)
    }
  end

  defp error_result(provider, reason) do
    %{status: "error", provider: provider, error: to_string(reason)}
  end

  defp print_provider(result, opts) do
    unless Keyword.get(opts, :json, false) do
      case result do
        %{status: "error"} ->
          Mix.shell().error("refresh_failed provider=#{result.provider} error=#{result.error}")

        %{status: "applied"} ->
          Mix.shell().info(
            "refresh_applied provider=#{result.provider} new=#{result.new} changed=#{result.changed} " <>
              "retained=#{result.retained} removed=#{result.removed} covers=#{inspect(result.covers)}"
          )

        %{status: "dry_run"} ->
          Mix.shell().info(
            "refresh_dry_run provider=#{result.provider} new=#{result.new} changed=#{result.changed} " <>
              "retained=#{result.retained} removed=#{result.removed}"
          )

          Enum.each(result.new_sample, &Mix.shell().info("  new #{&1}"))
          Enum.each(result.removed_sample, &Mix.shell().info("  removed #{&1}"))
      end
    end
  end

  defp mode(opts) do
    cond do
      Keyword.get(opts, :prune, false) -> :prune
      Keyword.get(opts, :replace_existing, false) -> :update
      true -> :add
    end
  end
end
