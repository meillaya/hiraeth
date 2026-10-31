defmodule Hiraeth.Catalog.PublicProjection.Grouping do
  @moduledoc "One counted facet value on a publisher page, such as a format or language."

  @enforce_keys [:label, :count]
  defstruct [:label, :count, slug: nil]

  @type t :: %__MODULE__{
          label: String.t(),
          count: non_neg_integer(),
          slug: String.t() | nil
        }
end
