defmodule Hiraeth.Catalog.PublicProjection.Dimensions do
  @moduledoc "Physical book dimensions in millimetres, when the source states them."

  defstruct [:height_mm, :width_mm, :depth_mm]

  @type t :: %__MODULE__{
          height_mm: integer() | nil,
          width_mm: integer() | nil,
          depth_mm: integer() | nil
        }
end
