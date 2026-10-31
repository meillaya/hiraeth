defmodule Hiraeth.RealCatalog.Refresh do
  @moduledoc """
  Fetches current records for a provider, merges them into the checked-in
  dataset, and optionally applies the result.

  Strategies are policy profiles from `refresh_profiles.json`: a checked-in
  operator script or a sidecar provider manifest. The default merge is additive
  (keep existing records, add new titles). `:update` replaces existing records
  with the source candidate; `:prune` replaces the dataset and requires explicit
  removal authorization.
  """

  alias Hiraeth.Covers
  alias Hiraeth.Imports.ImportRun
  alias Hiraeth.Ingestion.{ProviderManifest, SidecarClient}

  alias Hiraeth.RealCatalog.{
    Dataset,
    Importer,
    ISBN,
    RefreshProfiles,
    SourceAuthority,
    SourcePolicy,
    Validator
  }

  require Ash.Query

  @type diff :: %{
          records: [map()],
          new: non_neg_integer(),
          changed: non_neg_integer(),
          retained: non_neg_integer(),
          removed: non_neg_integer(),
          new_keys: [String.t()],
          removed_keys: [String.t()]
        }

  @doc """
  Fetches current records for a provider from its script or sidecar manifest.
  """
  @spec fetch(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def fetch(provider, opts \\ []) when is_binary(provider) do
    profile = RefreshProfiles.fetch!(provider)

    case profile["strategy"] do
      "script" -> fetch_script(provider, profile, opts)
      "sidecar" -> fetch_sidecar(provider, profile, opts)
      other -> {:error, "unknown refresh strategy for #{provider}: #{inspect(other)}"}
    end
  rescue
    error -> {:error, "refresh fetch failed for #{provider}: #{Exception.message(error)}"}
  end

  @doc """
  Merges a source candidate into the current dataset.

  Modes: `:add` (default), `:update` (replace changed records, keep removed),
  `:prune` (source wins and removals are applied when allowed).
  """
  @spec merge(map(), map(), keyword()) :: {:ok, diff()} | {:error, String.t()}
  def merge(current_dataset, candidate_dataset, opts \\ []) do
    mode = Keyword.get(opts, :mode, :add)
    allow_removals? = Keyword.get(opts, :allow_removals, false)
    current = Map.get(current_dataset, :records, []) || []
    candidate = Map.get(candidate_dataset, :records, []) || []

    current_by_key = Map.new(current, &{record_key(&1), &1})
    current_source_ids = unique_index(current, &source_id/1)
    current_source_uris = unique_index(current, &source_uri/1)
    current_uri_formats = unique_index(current, &uri_format_key/1)
    current_title_formats = unique_index(current, &title_format_key/1)

    candidate_matches =
      candidate_matches(
        candidate,
        current_by_key,
        current_source_ids,
        current_source_uris,
        current_uri_formats,
        current_title_formats
      )

    current_keys = Map.keys(current_by_key) |> MapSet.new()
    matched_keys = candidate_matches |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    new_matches =
      Enum.reject(candidate_matches, fn {_record, matched_key, _primary_key} ->
        MapSet.member?(current_keys, matched_key)
      end)

    new_keys = new_matches |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort()
    new_records = new_matches |> Enum.map(&elem(&1, 0)) |> Enum.uniq_by(&record_key/1)

    candidate_by_current_key =
      Map.new(candidate_matches, fn {record, key, _} -> {key, record} end)

    removed_keys = MapSet.difference(current_keys, matched_keys) |> Enum.sort()

    changed_keys =
      candidate_matches
      |> Enum.filter(fn {record, matched_key, _primary_key} ->
        MapSet.member?(current_keys, matched_key) and
          current_by_key[matched_key] != record
      end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    records =
      merged_records(
        mode,
        current,
        candidate,
        new_records,
        candidate_by_current_key,
        removed_keys,
        allow_removals?
      )

    {:ok, merge_summary(mode, records, new_keys, changed_keys, removed_keys)}
  catch
    {:error, _reason} = error -> error
  end

  defp candidate_matches(
         candidate,
         current_by_key,
         current_source_ids,
         current_source_uris,
         current_uri_formats,
         current_title_formats
       ) do
    Enum.map(candidate, fn record ->
      primary_key = record_key(record)

      matched_key =
        match_current_key(
          record,
          primary_key,
          current_by_key,
          current_source_ids,
          current_source_uris,
          current_uri_formats,
          current_title_formats
        )

      {record, matched_key, primary_key}
    end)
  end

  defp merged_records(:add, current, _candidate, new_records, _by_key, _removed, _allow) do
    current ++ new_records
  end

  defp merged_records(:update, current, _candidate, new_records, by_key, _removed, _allow) do
    Enum.map(current, fn record ->
      Map.get(by_key, record_key(record), record)
    end) ++ new_records
  end

  defp merged_records(:prune, _current, candidate, _new_records, _by_key, removed, allow) do
    if removed != [] and not allow do
      throw({:error, "refusing to remove #{length(removed)} records without --allow-removals"})
    else
      candidate
    end
  end

  defp merged_records(other, _current, _candidate, _new_records, _by_key, _removed, _allow) do
    throw({:error, "unknown refresh merge mode: #{inspect(other)}"})
  end

  defp merge_summary(mode, records, new_keys, changed_keys, removed_keys) do
    %{
      records: Enum.sort_by(records, &sort_key/1),
      new: length(new_keys),
      changed: length(changed_keys),
      retained: if(mode == :prune, do: 0, else: length(removed_keys)),
      removed: length(removed_keys),
      new_keys: new_keys,
      removed_keys: removed_keys
    }
  end

  @doc """
  Writes the merged dataset, regenerates evidence, imports it, and optionally
  caches the provider's covers.
  """
  @spec apply(String.t(), map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def apply(provider, candidate_dataset, opts \\ []) do
    with {:ok, current} <- current_dataset(provider),
         {:ok, diff} <- merge(current, candidate_dataset, opts),
         {:ok, dataset} <- build_dataset(provider, diff.records, candidate_dataset),
         :ok <- validate_dataset(provider, dataset),
         {:ok, path} <- write_dataset(provider, dataset),
         {:ok, _manifest} <-
           SourceAuthority.write!(Dataset.default_dir(),
             allow_removals: Keyword.get(opts, :allow_removals, false)
           ),
         {:ok, _summary} <- import_dataset(dataset) do
      cover_summary =
        if Keyword.get(opts, :covers, true) do
          try do
            {:ok, Covers.cache_public_covers!(provider: provider)}
          rescue
            error -> {:error, Exception.message(error)}
          end
        else
          {:ok, %{cached: 0, thumbnails: 0, skipped: 0, failed: 0, failures: []}}
        end

      case cover_summary do
        {:ok, summary} ->
          {:ok,
           diff
           |> Map.take([:new, :changed, :retained, :removed])
           |> Map.merge(%{
             provider: provider,
             path: path,
             covers: Map.take(summary, [:cached, :thumbnails, :skipped, :failed])
           })}

        {:error, reason} ->
          {:error, "cover sync failed for #{provider}: #{inspect(reason)}"}
      end
    end
  end

  @doc "Returns the checked-in dataset for a provider."
  @spec current_dataset(String.t()) :: {:ok, map()} | {:error, String.t()}
  def current_dataset(provider) do
    case Dataset.file_for_provider(provider) do
      nil -> {:error, "no checked-in dataset for provider #{provider}"}
      path -> Dataset.load_file(path)
    end
  end

  defp fetch_script(provider, profile, opts) do
    script = profile["script"]
    output_file = profile["output_file"]

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "hiraeth-refresh-#{provider}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    args = [script, "--out-dir", tmp_dir]

    args =
      case profile["arg_provider"] do
        value when is_binary(value) and value != "" -> args ++ ["--provider", value]
        _ -> args
      end

    try do
      case System.cmd(python(opts), args, cd: repo_root(), stderr_to_stdout: true) do
        {output, 0} ->
          path = Path.join(tmp_dir, output_file)

          case Dataset.load_file(path) do
            {:ok, dataset} ->
              {:ok, dataset}

            {:error, reason} ->
              {:error, "script output is unreadable: #{inspect(reason)}\n#{tail(output)}"}
          end

        {output, status} ->
          {:error, "script exited #{status} for #{provider}:\n#{tail(output)}"}
      end
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp fetch_sidecar(_provider, profile, _opts) do
    with {:ok, manifest} <- load_manifest(profile["manifest"]),
         :ok <- register_policy(profile["manifest"]),
         :ok <- sidecar_health(),
         {:ok, records} <- sidecar_records(manifest) do
      {:ok, sidecar_dataset(manifest, records)}
    end
  end

  defp load_manifest(path) do
    {:ok, ProviderManifest.load!(path)}
  rescue
    error -> {:error, "manifest load failed: #{Exception.message(error)}"}
  end

  defp register_policy(path) do
    {:ok, _provider} = SourcePolicy.load_provider_manifest(path)
    :ok
  end

  defp sidecar_health do
    case sidecar_client().health() do
      {:ok, %{status: "ok"}} ->
        :ok

      _error ->
        {:error,
         "Scrapling sidecar is not running. Start it locally with " <>
           "`cd sidecar && uv run --extra dev uvicorn app.main:app --host 127.0.0.1 --port 8000` " <>
           "or set SCRAPLING_SIDECAR_URL to a reachable private sidecar."}
    end
  end

  defp sidecar_records(manifest) do
    client = sidecar_client()
    provider_config = %{provider: manifest.provider, config: sidecar_config(manifest)}

    case ProviderManifest.effective_source_mode(manifest) do
      source_mode when is_binary(source_mode) ->
        result =
          case source_mode do
            "api" -> client.fetch(provider_config)
            "scrape" -> client.scrape(provider_config)
          end

        case result do
          {:ok, %{records: records}} when is_list(records) ->
            {:ok, Dataset.normalize(records)}

          {:error, reason} when is_binary(reason) ->
            {:error, "sidecar #{source_mode} failed: #{reason}"}

          {:error, reason} ->
            {:error, "sidecar #{source_mode} failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "invalid provider source_mode: #{inspect(reason)}"}
    end
  end

  defp sidecar_dataset(manifest, records) do
    %{
      provider: manifest.provider,
      records: records,
      file: "#{manifest.provider}.json",
      file_path: nil,
      file_checksum: checksum(records),
      license_note: manifest.permission_basis || "Operator-authorized public catalog refresh.",
      provider_permissions: %{
        provider: manifest.provider,
        source_urls: manifest.source_urls || [],
        source_hosts: manifest.source_hosts || [],
        cover_hosts: manifest.cover_hosts || [],
        permission_basis: manifest.permission_basis,
        cover_cache_policy: manifest.cover_cache_policy,
        excluded_content: manifest.excluded_content || [],
        takedown_contact: manifest.takedown_contact,
        not_legal_advice: not_legal_advice(manifest.not_legal_advice)
      }
    }
  end

  defp sidecar_config(manifest) do
    config =
      %{}
      |> Map.put(:source_hosts, manifest.source_hosts)
      |> Map.put(:publisher_name, manifest.name)

    config =
      if is_map(manifest.api) and manifest.api != %{},
        do: Map.put(config, :api, manifest.api),
        else: config

    config =
      if is_map(manifest.spider) and manifest.spider != %{},
        do: Map.put(config, :spider, manifest.spider),
        else: config

    if is_map(manifest.rate_limit),
      do: Map.put(config, :rate_limit, manifest.rate_limit),
      else: config
  end

  defp build_dataset(provider, records, candidate_dataset) do
    with {:ok, path} <- dataset_path(provider) do
      permissions =
        candidate_dataset
        |> Map.get(:provider_permissions, %{})
        |> ensure_permissions(provider)

      {:ok,
       %{
         provider: provider,
         records: records,
         retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
         license_note:
           Map.get(candidate_dataset, :license_note) ||
             Map.get(permissions, :permission_basis) ||
             "Operator-authorized public catalog refresh.",
         provider_permissions: permissions,
         file: Path.basename(path),
         file_path: path,
         file_checksum: checksum(records)
       }}
    end
  end

  defp ensure_permissions(permissions, provider) when is_map(permissions) do
    Map.put_new(permissions, :provider, provider)
  end

  defp ensure_permissions(_permissions, provider), do: %{provider: provider}

  defp validate_dataset(provider, dataset) do
    case Validator.validate_datasets([dataset], nil, record_count: :skip) do
      {:ok, _summary} ->
        :ok

      {:error, findings} ->
        samples = findings |> Enum.take(3) |> Enum.map_join("; ", & &1.reason)

        {:error,
         "validation failed for #{provider}: #{length(findings)} findings (first: #{samples})"}
    end
  end

  defp write_dataset(provider, dataset) do
    path = dataset.file_path
    temporary = "#{path}.tmp-#{System.unique_integer([:positive])}"

    File.write!(temporary, Jason.encode!(dataset, pretty: true) <> "\n")

    case File.rename(temporary, path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, "failed to write #{path}: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, "failed to write #{provider} dataset: #{Exception.message(error)}"}
  end

  defp import_dataset(dataset) do
    import_run =
      ImportRun
      |> Ash.Changeset.for_create(:create, %{
        provider: dataset.provider,
        status: "applied",
        row_limit: length(dataset.records || [])
      })
      |> Ash.create!(authorize?: false)

    Importer.seed_provider!(dataset, import_run, prune_stale?: true)
  rescue
    error -> {:error, "import failed for #{dataset.provider}: #{Exception.message(error)}"}
  end

  defp dataset_path(provider) do
    case Dataset.file_for_provider(provider) do
      nil -> {:error, "no checked-in dataset for provider #{provider}"}
      path -> {:ok, path}
    end
  end

  defp match_current_key(
         record,
         primary_key,
         by_key,
         source_ids,
         source_uris,
         uri_formats,
         title_formats
       ) do
    if Map.has_key?(by_key, primary_key) do
      primary_key
    else
      [
        fn -> lookup(source_ids, source_id(record)) end,
        fn -> lookup(source_uris, source_uri(record)) end,
        fn -> lookup(uri_formats, uri_format_key(record)) end,
        fn -> lookup(title_formats, title_format_key(record)) end
      ]
      |> Enum.find_value(fn fun -> fun.() end)
      |> Kernel.||(primary_key)
    end
  end

  defp lookup(index, key) when is_binary(key) do
    case Map.fetch(index, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp lookup(_index, _key), do: nil

  defp unique_index(records, key_fun) do
    records
    |> Enum.group_by(key_fun)
    |> Enum.flat_map(fn
      {nil, _records} -> []
      {"", _records} -> []
      {key, [record]} -> [{key, record_key(record)}]
      {_key, _ambiguous} -> []
    end)
    |> Map.new()
  end

  defp source_id(record) do
    value = record[:source_product_id] || record["source_product_id"]
    if is_binary(value) and String.trim(value) != "", do: value
  end

  defp source_uri(record) do
    value = record[:source_uri] || record["source_uri"]
    if is_binary(value) and String.trim(value) != "", do: value
  end

  defp uri_format_key(record) do
    with uri when is_binary(uri) <- source_uri(record),
         format when is_binary(format) <- record_format(record) do
      "#{uri}|#{format}"
    else
      _ -> nil
    end
  end

  defp title_format_key(record) do
    with title when is_binary(title) <- work_title(record),
         format when is_binary(format) <- record_format(record) do
      "#{title}|#{format}"
    else
      _ -> nil
    end
  end

  defp work_title(record) do
    value = get_in(record, [:work, :title]) || get_in(record, ["work", "title"])

    if is_binary(value) and String.trim(value) != "" do
      value |> String.trim() |> String.downcase()
    end
  end

  defp record_format(record) do
    value = get_in(record, [:edition, :format]) || get_in(record, ["edition", "format"])

    if is_binary(value) and String.trim(value) != "" do
      value |> String.trim() |> String.downcase()
    end
  end

  defp record_key(record) do
    isbn = get_in(record, [:edition, :isbn_13]) || get_in(record, ["edition", "isbn_13"])

    case ISBN.normalize(isbn) do
      {:ok, value} ->
        "isbn:#{value}"

      {:error, _reason} ->
        "source:#{record[:source_product_id] || record["source_product_id"] || record[:source_uri] || record["source_uri"]}"
    end
  end

  defp sort_key(record) do
    {
      String.downcase(
        to_string(get_in(record, [:work, :title]) || get_in(record, ["work", "title"]) || "")
      ),
      to_string(
        get_in(record, [:edition, :format]) || get_in(record, ["edition", "format"]) || ""
      ),
      to_string(
        get_in(record, [:edition, :isbn_13]) || get_in(record, ["edition", "isbn_13"]) || ""
      )
    }
  end

  defp checksum(records) do
    records
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp python(opts) do
    Keyword.get(opts, :python) || default_python()
  end

  defp default_python do
    sidecar_python = Path.expand(Path.join(["sidecar", ".venv", "bin", "python"]))

    if File.regular?(sidecar_python), do: sidecar_python, else: "python3"
  end

  defp repo_root do
    Application.get_env(:hiraeth, :refresh_repo_root, File.cwd!())
  end

  defp tail(output) do
    output |> String.split("\n") |> Enum.take(-12) |> Enum.join("\n")
  end

  defp not_legal_advice(value) when is_binary(value), do: value

  defp not_legal_advice(_value),
    do: "Operator-authorized ingestion policy and provenance metadata; not legal advice."

  defp sidecar_client do
    Application.get_env(:hiraeth, :sidecar_client, SidecarClient)
  end
end
