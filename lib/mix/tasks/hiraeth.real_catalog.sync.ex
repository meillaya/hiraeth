defmodule Mix.Tasks.Hiraeth.RealCatalog.Sync do
  @moduledoc """
  Regenerates or verifies the checked-in real-catalog evidence.

  Usage:
      mix hiraeth.real_catalog.sync --check [--json]
      mix hiraeth.real_catalog.sync --write [--allow-removals] [--json]

  The authority manifest keeps its human-reviewed policy fields. This task
  rewrites only derived fields (`dataset_file`, `approved_source_records`,
  `coverage.expected_record_count`, `coverage.generated_at`) and then rebuilds
  `source_artifacts_manifest.json` and `source_coverage_report.json`.

  `--check` is read-only. `--write` refuses provider removals and record-count
  decreases unless `--allow-removals` is passed.
  """

  use Mix.Task

  alias Hiraeth.RealCatalog.{Dataset, SourceAuthority}

  @shortdoc "Regenerates or verifies real-catalog source authority evidence"

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
        strict: [write: :boolean, check: :boolean, allow_removals: :boolean, json: :boolean]
      )

    write? = Keyword.get(opts, :write, false)
    check? = Keyword.get(opts, :check, false)
    dir = dataset_dir()

    cond do
      write? and check? ->
        {:error, "Use either --write or --check, not both."}

      write? ->
        write(dir, opts)

      check? ->
        check(dir, opts)

      true ->
        check(dir, opts)
    end
  end

  defp write(dir, opts) do
    case SourceAuthority.write!(dir, allow_removals: Keyword.get(opts, :allow_removals, false)) do
      {:ok, manifest} ->
        result = %{
          status: "written",
          providers: length(Map.get(manifest, "providers", [])),
          records: total_records(manifest)
        }

        print(result, opts)
        :ok

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp check(dir, opts) do
    case SourceAuthority.check(dir) do
      {:ok, :in_sync} ->
        print(%{status: "in_sync"}, opts)
        :ok

      {:error, %{authority: _} = drift} ->
        print(Map.put(drift, :status, "drift"), opts)

        {:error,
         "source authority evidence is out of sync; run mix hiraeth.real_catalog.sync --write"}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp print(result, opts) do
    if Keyword.get(opts, :json, false) do
      Mix.shell().info(Jason.encode!(result, pretty: true))
    else
      Mix.shell().info("source_authority=#{result.status}")

      if Map.has_key?(result, :providers) do
        Mix.shell().info("providers=#{result.providers}")
        Mix.shell().info("records=#{result.records}")
      end
    end
  end

  defp total_records(manifest) do
    manifest
    |> Map.get("providers", [])
    |> Enum.reduce(0, fn provider, total ->
      total + (get_in(provider, ["coverage", "expected_record_count"]) || 0)
    end)
  end

  defp format_error({:missing_policy, providers}) do
    "No source authority policy entry for datasets: #{Enum.join(providers, ", ")}"
  end

  defp format_error({:missing_dataset, providers}) do
    "No dataset file for source authority providers: #{Enum.join(providers, ", ")}"
  end

  defp format_error({:provider_removal_blocked, providers}) do
    "Refusing to remove providers without --allow-removals: #{Enum.join(providers, ", ")}"
  end

  defp format_error({:record_count_decrease_blocked, decreases}) do
    details =
      decreases
      |> Enum.map_join(", ", fn {provider, old, new} -> "#{provider} #{old}->#{new}" end)

    "Refusing record-count decreases without --allow-removals: #{details}"
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp dataset_dir do
    Application.get_env(:hiraeth, :source_authority_dataset_dir, Dataset.default_dir())
  end
end
