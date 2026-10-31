defmodule Hiraeth.Catalog.PublicProjection.Publisher do
  @moduledoc """
  Publisher index row and publisher detail page.

  Index rows leave `editions` empty; the detail page fills the same struct with
  its books and counted facets instead of putting keys onto a bare map.
  """

  @enforce_keys [:id, :name, :slug, :editions_count, :groupings]
  defstruct [
    :id,
    :name,
    :slug,
    :description,
    :editions_count,
    :groupings,
    editions: [],
    cover_sample: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          slug: String.t(),
          description: String.t() | nil,
          editions_count: non_neg_integer(),
          groupings: Hiraeth.Catalog.PublicProjection.Groupings.t(),
          editions: [Hiraeth.Catalog.PublicProjection.Book.t()],
          cover_sample: Hiraeth.Catalog.PublicProjection.CoverSample.t() | nil
        }
end
