defmodule Hiraeth.Catalog.PublicProjection.Contributor do
  @moduledoc "Contributor summary exposed on public catalog cards and detail pages."

  @behaviour Access

  @enforce_keys [:name]
  defstruct [:id, :contribution_id, :position, :role, :name, :slug]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          contribution_id: String.t() | nil,
          position: non_neg_integer() | nil,
          role: String.t() | nil,
          name: String.t(),
          slug: String.t() | nil
        }

  @spec fetch(t(), term()) :: {:ok, term()} | :error
  defdelegate fetch(projection, key), to: Hiraeth.Catalog.PublicProjection.Access

  @spec get_and_update(t(), term(), (term() -> {term(), term()})) :: {term(), term()}
  defdelegate get_and_update(projection, key, function),
    to: Hiraeth.Catalog.PublicProjection.Access

  @spec pop(t(), term()) :: {term(), t()}
  defdelegate pop(projection, key), to: Hiraeth.Catalog.PublicProjection.Access
end
