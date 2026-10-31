defmodule Hiraeth.RealCatalog.SourceAuthority do
  @moduledoc """
  Builds the generated evidence for the checked-in real-publisher corpus.

  The authority manifest is policy plus derived evidence. Policy fields (allowed
  hosts/URLs, permission basis, takedown contact, boundaries, gap policy) are
  reviewed by an operator. The derived fields are rebuilt from the datasets:

    * `dataset_file`
    * `approved_source_records`
    * `coverage.expected_record_count`
    * `coverage.generated_at`

  `mix hiraeth.real_catalog.sync --write` rewrites the authority manifest and
  the two evidence manifests. `--check` proves the checked-in files match the
  datasets without writing anything.
  """

  alias Hiraeth.RealCatalog.{CoverageReport, Dataset, SourceArtifacts}

  @authority_file "source_authority_manifest.json"
  @artifacts_file "source_artifacts_manifest.json"
  @coverage_file "source_coverage_report.json"

  @type drift :: %{
          authority: [String.t()],
          artifacts: boolean(),
          coverage: boolean(),
          missing_policy: [String.t()],
          missing_dataset: [String.t()]
        }

  @doc """
  Builds the updated authority manifest from the datasets and current policy.
  """
  @spec build(String.t(), keyword()) ::
          {:ok, map()}
          | {:error, {:missing_policy, [String.t()]}}
          | {:error, {:missing_dataset, [String.t()]}}
          | {:error, term()}
  def build(dir \\ Dataset.default_dir(), _opts \\ []) do
    with {:ok, datasets} <- Dataset.load_dir(dir),
         {:ok, manifest} <- Dataset.load_source_authority_manifest(dir) do
      policy_providers =
        manifest
        |> Map.get("providers", [])
        |> Map.new(&{&1["provider"], &1})

      datasets_by_provider = Map.new(datasets, &{&1.provider, &1})
      provider_names = datasets_by_provider |> Map.keys() |> Enum.sort()

      case missing_coverage(policy_providers, datasets_by_provider, provider_names) do
        :ok ->
          providers = build_providers(provider_names, datasets_by_provider, policy_providers)
          {:ok, Map.put(manifest, "providers", providers)}

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp missing_coverage(policy_providers, datasets_by_provider, provider_names) do
    missing_policy = Enum.reject(provider_names, &Map.has_key?(policy_providers, &1))

    missing_dataset =
      policy_providers
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(datasets_by_provider, &1))
      |> Enum.sort()

    cond do
      missing_policy != [] -> {:error, {:missing_policy, missing_policy}}
      missing_dataset != [] -> {:error, {:missing_dataset, missing_dataset}}
      true -> :ok
    end
  end

  defp build_providers(provider_names, datasets_by_provider, policy_providers) do
    Enum.map(provider_names, fn provider ->
      dataset = Map.fetch!(datasets_by_provider, provider)
      policy = Map.fetch!(policy_providers, provider)

      policy
      |> Map.put("dataset_file", dataset.file)
      |> Map.put("approved_source_records", length(dataset.records || []))
      |> put_coverage(dataset)
    end)
  end

  @doc """
  Compares the checked-in authority/artifact/coverage files with the datasets.
  """
  @spec check(String.t()) :: {:ok, :in_sync} | {:error, drift()}
  def check(dir \\ Dataset.default_dir()) do
    with {:ok, built} <- build(dir),
         {:ok, checked_in} <- Dataset.load_source_authority_manifest(dir),
         {:ok, artifacts} <- SourceArtifacts.build_manifest(dir),
         {:ok, coverage} <- CoverageReport.build(dir),
         {:ok, checked_artifacts} <- load_json(Path.join(dir, @artifacts_file)),
         {:ok, checked_coverage} <- load_json(Path.join(dir, @coverage_file)) do
      authority_drift = authority_drift(built, checked_in)

      drift = %{
        authority: authority_drift,
        artifacts: artifacts != checked_artifacts,
        coverage: coverage != checked_coverage,
        missing_policy: [],
        missing_dataset: []
      }

      if authority_drift == [] and not drift.artifacts and not drift.coverage do
        {:ok, :in_sync}
      else
        {:error, drift}
      end
    else
      {:error, {:missing_policy, providers}} ->
        {:error,
         %{
           authority: [],
           artifacts: false,
           coverage: false,
           missing_policy: providers,
           missing_dataset: []
         }}

      {:error, {:missing_dataset, providers}} ->
        {:error,
         %{
           authority: [],
           artifacts: false,
           coverage: false,
           missing_policy: [],
           missing_dataset: providers
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Rewrites the authority manifest and both evidence manifests.

  Refuses to remove providers or reduce a provider's record count unless
  `allow_removals?: true` is passed.
  """
  @spec write!(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def write!(dir \\ Dataset.default_dir(), opts \\ []) do
    allow_removals? = Keyword.get(opts, :allow_removals, false)

    with {:ok, built} <- build(dir),
         {:ok, checked_in} <- Dataset.load_source_authority_manifest(dir),
         :ok <- reject_destructive_changes(built, checked_in, allow_removals?) do
      File.mkdir_p!(dir)
      write_json!(Path.join(dir, @authority_file), built)
      SourceArtifacts.write_manifest!(dir, Path.join(dir, @artifacts_file))
      CoverageReport.write!(dir, Path.join(dir, @coverage_file))

      {:ok, built}
    end
  end

  @doc "Returns the derived record count for a provider, or nil."
  @spec record_count(String.t(), String.t()) :: non_neg_integer() | nil
  def record_count(provider, dir \\ Dataset.default_dir()) do
    with {:ok, built} <- build(dir),
         %{} = policy <- Enum.find(Map.get(built, "providers", []), &(&1["provider"] == provider)) do
      get_in(policy, ["coverage", "expected_record_count"])
    else
      _ -> nil
    end
  end

  defp put_coverage(policy, dataset) do
    coverage =
      policy
      |> Map.get("coverage", %{})
      |> Map.put("expected_record_count", length(dataset.records || []))
      |> Map.put("generated_at", dataset.retrieved_at)

    Map.put(policy, "coverage", coverage)
  end

  defp reject_destructive_changes(built, checked_in, true) do
    _ = {built, checked_in}
    :ok
  end

  defp reject_destructive_changes(built, checked_in, false) do
    old_counts = provider_counts(checked_in)
    new_counts = provider_counts(built)

    removed_providers =
      old_counts
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(new_counts, &1))

    decreases =
      old_counts
      |> Enum.filter(fn {provider, old} ->
        is_integer(old) and is_integer(Map.get(new_counts, provider)) and
          Map.get(new_counts, provider) < old
      end)
      |> Enum.map(fn {provider, old} -> {provider, old, Map.fetch!(new_counts, provider)} end)

    cond do
      removed_providers != [] ->
        {:error, {:provider_removal_blocked, Enum.sort(removed_providers)}}

      decreases != [] ->
        {:error, {:record_count_decrease_blocked, decreases}}

      true ->
        :ok
    end
  end

  defp provider_counts(manifest) do
    manifest
    |> Map.get("providers", [])
    |> Map.new(fn provider ->
      {provider["provider"], get_in(provider, ["coverage", "expected_record_count"])}
    end)
  end

  defp authority_drift(built, checked_in) do
    built_providers = providers_by_name(built)
    checked_providers = providers_by_name(checked_in)

    changed =
      (Map.keys(built_providers) ++ Map.keys(checked_providers))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reject(fn provider ->
        Map.get(built_providers, provider) == Map.get(checked_providers, provider)
      end)

    top_level =
      built
      |> Map.drop(["providers"])
      |> then(fn top ->
        if top == Map.drop(checked_in, ["providers"]), do: [], else: ["top_level"]
      end)

    top_level ++ changed
  end

  defp providers_by_name(manifest) do
    manifest
    |> Map.get("providers", [])
    |> Map.new(&{&1["provider"], &1})
  end

  defp load_json(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_json, path, error}}
      {:error, reason} -> {:error, {reason, path}}
    end
  end

  defp write_json!(path, value) do
    temporary = "#{path}.tmp-#{System.unique_integer([:positive])}"
    File.write!(temporary, Jason.encode!(value, pretty: true) <> "\n")

    case File.rename(temporary, path) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm(temporary)
        raise "failed to replace #{path}: #{inspect(reason)}"
    end
  end
end
