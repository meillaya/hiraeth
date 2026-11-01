defmodule Hiraeth.Catalog.PublicWork do
  @moduledoc """
  Derived, public-only row for one work.

  The payload is the encoded `Hiraeth.Catalog.PublicProjection.Book`; the
  scalar and array columns exist only so the browser can filter, sort, search,
  and page without joining the canonical catalog tables.
  """

  use Ecto.Schema

  @primary_key {:work_id, Ecto.UUID, autogenerate: false}
  schema "catalog_public_works" do
    field :payload, :binary
    field :build_id, Ecto.UUID
    field :slug, :string
    field :title, :string
    field :subtitle, :string
    field :title_sort, :string
    field :author_sort, :string
    field :publisher_name, :string
    field :publisher_slug, :string
    field :published_on, :date
    field :publication_year, :integer
    field :newest_sort, :date
    field :imported_sort, :utc_datetime_usec
    field :is_book, :boolean, default: true
    field :has_cover, :boolean, default: false
    field :format_values, {:array, :string}, default: []
    field :language_values, {:array, :string}, default: []
    field :role_values, {:array, :string}, default: []
    field :contributor_slugs, {:array, :string}, default: []
    field :contributor_names, {:array, :string}, default: []
    field :series_slugs, {:array, :string}, default: []
    field :series_titles, {:array, :string}, default: []
    field :subject_values, {:array, :string}, default: []
    field :edition_slugs, {:array, :string}, default: []
    field :search_text, :string
    field :refreshed_at, :utc_datetime_usec
  end
end
