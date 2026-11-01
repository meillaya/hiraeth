defmodule Hiraeth.Covers.CoverAsset do
  @moduledoc "Ash resource: a source cover asset (cache path, host, fetch metadata, takedown state)."

  use Ash.Resource,
    domain: Hiraeth.Covers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cover_assets"
    repo Hiraeth.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :source_url, :string do
      allow_nil? false
      public? true
    end

    attribute :provider, :string do
      allow_nil? false
      public? true
    end

    attribute :rights_basis, :string do
      allow_nil? false
      public? true
    end

    attribute :attribution_text, :string do
      public? true
    end

    attribute :attribution_url, :string do
      public? true
    end

    attribute :cache_policy, :string do
      allow_nil? false
      default "link_only"
      public? true
    end

    attribute :cached_file_path, :string do
      public? true
    end

    attribute :cached_at, :utc_datetime do
      public? true
    end

    attribute :thumbnail_file_path, :string do
      public? true
    end

    attribute :responsive_variants, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :takedown_state, :string do
      allow_nil? false
      default "visible"
      public? true
    end
  end

  relationships do
    has_many :cover_assignments, Hiraeth.Covers.CoverAssignment
  end

  identities do
    identity :unique_source_url, [:source_url]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :source_url,
        :provider,
        :rights_basis,
        :attribution_text,
        :attribution_url,
        :cache_policy,
        :cached_file_path,
        :cached_at,
        :thumbnail_file_path,
        :responsive_variants,
        :takedown_state
      ]

      validate fn changeset, _context ->
        validate_cache_rights(changeset)
      end
    end

    update :update do
      require_atomic? false

      accept [
        :provider,
        :rights_basis,
        :attribution_text,
        :attribution_url,
        :cache_policy,
        :cached_file_path,
        :cached_at,
        :thumbnail_file_path,
        :responsive_variants,
        :takedown_state
      ]

      validate fn changeset, _context ->
        validate_cache_rights(changeset)
      end
    end
  end

  policies do
    policy action_type(:read) do
      description "Cover provenance is publicly readable for catalog display."
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "Only trusted catalog write actors can govern cover assets and takedown state."
      authorize_if actor_attribute_equals(:catalog_write?, true)
    end
  end

  defp validate_cache_rights(changeset) do
    cached_file_path = Ash.Changeset.get_attribute(changeset, :cached_file_path)
    thumbnail_file_path = Ash.Changeset.get_attribute(changeset, :thumbnail_file_path)
    responsive_variants = Ash.Changeset.get_attribute(changeset, :responsive_variants) || []
    cache_policy = Ash.Changeset.get_attribute(changeset, :cache_policy)
    rights_basis = Ash.Changeset.get_attribute(changeset, :rights_basis)

    cond do
      not valid_variants?(responsive_variants) ->
        {:error,
         field: :responsive_variants,
         message: "responsive variants must be maps with a safe cache path, format, and width"}

      (present?(cached_file_path) or present?(thumbnail_file_path) or
         responsive_variants != []) and
          not (cache_policy == "cache_allowed" and rights_basis == "local_cache_permitted") ->
        {:error,
         field: :cached_file_path,
         message: "cache file path requires cache_allowed policy and local cache rights basis"}

      true ->
        :ok
    end
  end

  defp valid_variants?(variants) when is_list(variants) do
    Enum.all?(variants, fn
      %{"path" => path, "format" => format, "width" => width} ->
        safe_variant_path?(path) and format in ["webp", "jpg"] and is_integer(width) and width > 0

      %{path: path, format: format, width: width} ->
        safe_variant_path?(path) and format in ["webp", "jpg"] and is_integer(width) and width > 0

      _variant ->
        false
    end)
  end

  defp valid_variants?(_variants), do: false

  defp safe_variant_path?(path) when is_binary(path) do
    String.starts_with?(path, "priv/static/covers/cache/") and
      not String.contains?(path, "..") and
      not String.contains?(path, "\0")
  end

  defp safe_variant_path?(_path), do: false

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
