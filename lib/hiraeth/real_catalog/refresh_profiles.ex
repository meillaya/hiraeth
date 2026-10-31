defmodule Hiraeth.RealCatalog.RefreshProfiles do
  @moduledoc """
  Loads and validates the checked-in refresh strategy for every authority provider.

  A profile is policy, not generated evidence: it names the script or sidecar
  manifest used to fetch current records. The derived record counts stay in the
  generated authority/artifact/coverage files.
  """

  alias Hiraeth.RealCatalog.Dataset

  @profiles_file "refresh_profiles.json"

  @type profile :: %{
          required(String.t()) => String.t(),
          optional(String.t()) => String.t()
        }

  @doc "Returns the refresh profiles file path."
  @spec path(String.t()) :: String.t()
  def path(dir \\ default_dir()) do
    Path.join(dir, @profiles_file)
  end

  @doc "Loads the profiles map, raising on malformed JSON."
  @spec load!() :: %{String.t() => profile()}
  def load! do
    path()
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("providers")
  end

  @doc "Returns every provider with a refresh profile."
  @spec providers() :: [String.t()]
  def providers do
    load!() |> Map.keys() |> Enum.sort()
  end

  @doc "Returns one provider profile."
  @spec fetch!(String.t()) :: profile()
  def fetch!(provider) when is_binary(provider) do
    case Map.fetch(load!(), provider) do
      {:ok, profile} -> profile
      :error -> raise ArgumentError, "no refresh profile for provider #{provider}"
    end
  end

  @doc """
  Verifies that profiles cover exactly the authority providers and that every
  referenced script/manifest/output exists.
  """
  @spec validate!() :: :ok
  def validate! do
    case Dataset.load_source_authority_manifest() do
      {:ok, authority} ->
        validate_coverage!(authority)

      {:error, reason} ->
        raise ArgumentError, "source authority manifest load failed: #{inspect(reason)}"
    end
  end

  defp validate_coverage!(authority) do
    authority_providers =
      authority
      |> Map.get("providers", [])
      |> Enum.map(& &1["provider"])
      |> Enum.sort()

    profiles = load!()
    profile_providers = profiles |> Map.keys() |> Enum.sort()

    missing = authority_providers -- profile_providers
    extra = profile_providers -- authority_providers

    cond do
      missing != [] ->
        raise ArgumentError, "providers without refresh profiles: #{Enum.join(missing, ", ")}"

      extra != [] ->
        raise ArgumentError,
              "refresh profiles without authority providers: #{Enum.join(extra, ", ")}"

      true ->
        validate_entries!(profiles)
    end
  end

  defp validate_entries!(profiles) do
    Enum.each(profiles, fn {provider, profile} ->
      case profile["strategy"] do
        "script" ->
          script = profile["script"] || raise ArgumentError, "#{provider}: script is required"

          output =
            profile["output_file"] || raise ArgumentError, "#{provider}: output_file is required"

          ensure_file!(script, "#{provider}: script")

          ensure_file!(
            Path.join(["priv", "catalog_sources", "real_publishers", output]),
            "#{provider}: output_file"
          )

        "sidecar" ->
          manifest =
            profile["manifest"] || raise ArgumentError, "#{provider}: manifest is required"

          ensure_file!(manifest, "#{provider}: manifest")

        other ->
          raise ArgumentError, "#{provider}: unknown refresh strategy #{inspect(other)}"
      end
    end)

    :ok
  end

  defp ensure_file!(path, label) do
    unless File.regular?(path) do
      raise ArgumentError, "#{label} does not exist: #{path}"
    end
  end

  defp default_dir do
    Application.get_env(
      :hiraeth,
      :refresh_profiles_dir,
      Application.app_dir(:hiraeth, "priv/catalog_sources")
    )
  end
end
