defmodule Hiraeth.Catalog.PublicProjection.Cover do
  @moduledoc "Publicly renderable local cover projection."

  @behaviour Access

  defstruct [
    :source_url,
    :public_url,
    :provider,
    :rights_basis,
    :attribution_text,
    :attribution_url,
    :cache_policy,
    :takedown_state,
    :cached_file_path,
    :thumbnail_file_path,
    :thumbnail_url,
    responsive_variants: []
  ]

  @type variant :: %{
          format: String.t(),
          width: non_neg_integer(),
          sha256: String.t() | nil,
          bytes: non_neg_integer() | nil,
          url: String.t()
        }

  @type t :: %__MODULE__{
          source_url: String.t() | nil,
          public_url: String.t() | nil,
          provider: String.t() | nil,
          rights_basis: String.t() | nil,
          attribution_text: String.t() | nil,
          attribution_url: String.t() | nil,
          cache_policy: String.t() | nil,
          takedown_state: String.t() | nil,
          cached_file_path: String.t() | nil,
          thumbnail_file_path: String.t() | nil,
          thumbnail_url: String.t() | nil,
          responsive_variants: [variant()]
        }

  @spec fetch(t(), term()) :: {:ok, term()} | :error
  defdelegate fetch(projection, key), to: Hiraeth.Catalog.PublicProjection.Access

  @spec get_and_update(t(), term(), (term() -> {term(), term()})) :: {term(), term()}
  defdelegate get_and_update(projection, key, function),
    to: Hiraeth.Catalog.PublicProjection.Access

  @spec pop(t(), term()) :: {term(), t()}
  defdelegate pop(projection, key), to: Hiraeth.Catalog.PublicProjection.Access
end
