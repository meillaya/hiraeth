defmodule Hiraeth.Catalog.PublicProjectionState do
  @moduledoc "Singleton status row for the derived public read model."

  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "catalog_public_projection_state" do
    field :revision, Ecto.UUID
    field :status, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :row_count, :integer
    field :error, :string
    field :trigger, :string
  end
end
