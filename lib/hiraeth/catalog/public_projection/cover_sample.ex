defmodule Hiraeth.Catalog.PublicProjection.CoverSample do
  @moduledoc "Representative cover and title used on publisher index rows."

  @enforce_keys [:title, :cover]
  defstruct [:title, :cover]

  @type t :: %__MODULE__{
          title: String.t(),
          cover: Hiraeth.Catalog.PublicProjection.Cover.t()
        }
end
