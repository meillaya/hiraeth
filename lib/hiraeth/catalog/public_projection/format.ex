defmodule Hiraeth.Catalog.PublicProjection.Format do
  @moduledoc "Edition-format summary nested under a public book."

  alias Hiraeth.Catalog.PublicProjection.Dimensions

  @behaviour Access

  @enforce_keys [:edition_slug, :format_label, :identifiers]
  defstruct [
    :edition_slug,
    :format,
    :format_label,
    :source_identity,
    :published_on,
    :language_code,
    :page_count,
    :height_mm,
    :width_mm,
    :depth_mm,
    :dimensions,
    identifiers: []
  ]

  @type t :: %__MODULE__{
          edition_slug: String.t(),
          format: String.t() | nil,
          format_label: String.t(),
          source_identity: String.t() | nil,
          published_on: Date.t() | nil,
          language_code: String.t() | nil,
          page_count: non_neg_integer() | nil,
          height_mm: integer() | nil,
          width_mm: integer() | nil,
          depth_mm: integer() | nil,
          dimensions: Dimensions.t() | nil,
          identifiers: [String.t()]
        }

  @spec fetch(t(), term()) :: {:ok, term()} | :error
  defdelegate fetch(projection, key), to: Hiraeth.Catalog.PublicProjection.Access

  @spec get_and_update(t(), term(), (term() -> {term(), term()})) :: {term(), term()}
  defdelegate get_and_update(projection, key, function),
    to: Hiraeth.Catalog.PublicProjection.Access

  @spec pop(t(), term()) :: {term(), t()}
  defdelegate pop(projection, key), to: Hiraeth.Catalog.PublicProjection.Access
end
