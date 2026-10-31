defmodule Hiraeth.Catalog.PublicProjection.Series do
  @moduledoc """
  Series index row and series detail page.

  Index rows carry `memberships` and `preview_editions`; the detail page fills
  `editions` and clears the preview fields.
  """

  @enforce_keys [:id, :title, :name, :slug, :editions_count, :unknown_order?]
  defstruct [
    :id,
    :title,
    :name,
    :slug,
    :publisher,
    :publisher_slug,
    :editions_count,
    :unknown_order?,
    editions: [],
    memberships: [],
    preview_editions: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          name: String.t(),
          slug: String.t(),
          publisher: String.t() | nil,
          publisher_slug: String.t() | nil,
          editions_count: non_neg_integer(),
          unknown_order?: boolean(),
          editions: [Hiraeth.Catalog.PublicProjection.Book.t()],
          memberships: [Hiraeth.Catalog.PublicProjection.SeriesMembership.t()],
          preview_editions: [Hiraeth.Catalog.PublicProjection.Book.t()]
        }
end
