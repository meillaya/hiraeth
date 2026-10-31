defmodule Hiraeth.Catalog.PublicProjection.Page do
  @moduledoc """
  Paged envelope for public catalog reads.

  The envelope is generic over its entry type so a page of books and a page of
  editions share one shape and one serializer.
  """

  @enforce_keys [:entries, :page, :page_size, :total_count, :total_pages]
  defstruct [:entries, :page, :page_size, :total_count, :total_pages]

  @type t(entry) :: %__MODULE__{
          entries: [entry],
          page: pos_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: pos_integer()
        }

  @type t :: t(term())
end
