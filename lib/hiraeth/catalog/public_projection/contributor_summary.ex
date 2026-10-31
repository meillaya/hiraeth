defmodule Hiraeth.Catalog.PublicProjection.ContributorSummary do
  @moduledoc """
  Contributor index row and contributor detail page.

  The contributor index lists roles and a book count; the detail page fills
  `books` on the same struct.
  """

  @enforce_keys [:id, :name, :display_name, :slug, :books_count]
  defstruct [:id, :name, :display_name, :slug, :books_count, roles: [], books: []]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          display_name: String.t(),
          slug: String.t(),
          books_count: non_neg_integer(),
          roles: [String.t()],
          books: [Hiraeth.Catalog.PublicProjection.Book.t()]
        }
end
