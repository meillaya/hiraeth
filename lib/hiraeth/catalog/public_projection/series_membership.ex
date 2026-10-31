defmodule Hiraeth.Catalog.PublicProjection.SeriesMembership do
  @moduledoc "A work slot inside a series, with the source position when known."

  @enforce_keys [:work_id, :position]
  defstruct [:work_id, :position]

  @type t :: %__MODULE__{
          work_id: String.t(),
          position: non_neg_integer() | nil
        }
end
