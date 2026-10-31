defmodule Hiraeth.Catalog.PublicProjection.Source do
  @moduledoc "Source provenance summary for public catalog metadata."

  @behaviour Access

  @enforce_keys [:source_record_id, :provider, :source_type, :source_uri]
  defstruct [
    :id,
    :source_record_id,
    :provider,
    :source_type,
    :source_uri,
    :license_note,
    :import_run_id,
    :imported_at,
    :source_identity,
    field_sources: %{},
    provider_permissions: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          source_record_id: String.t(),
          provider: String.t(),
          source_type: String.t(),
          source_uri: String.t(),
          license_note: String.t() | nil,
          import_run_id: String.t() | nil,
          imported_at: DateTime.t() | nil,
          source_identity: String.t() | nil,
          field_sources: %{optional(String.t()) => term()},
          provider_permissions: %{optional(String.t()) => term()}
        }

  @spec fetch(t(), term()) :: {:ok, term()} | :error
  defdelegate fetch(projection, key), to: Hiraeth.Catalog.PublicProjection.Access

  @spec get_and_update(t(), term(), (term() -> {term(), term()})) :: {term(), term()}
  defdelegate get_and_update(projection, key, function),
    to: Hiraeth.Catalog.PublicProjection.Access

  @spec pop(t(), term()) :: {term(), t()}
  defdelegate pop(projection, key), to: Hiraeth.Catalog.PublicProjection.Access
end
