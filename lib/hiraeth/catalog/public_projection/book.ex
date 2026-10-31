defmodule Hiraeth.Catalog.PublicProjection.Book do
  @moduledoc "Work-centric public catalog book projection."

  alias Hiraeth.Catalog.PublicProjection.{Contributor, Cover, Format, Source}

  @behaviour Access

  @enforce_keys [:id, :work_id, :title, :slug, :publisher, :publisher_slug, :formats]
  defstruct [
    :id,
    :work_id,
    :title,
    :subtitle,
    :slug,
    :publisher,
    :publisher_slug,
    :author,
    :cover,
    :source,
    :original_title,
    :original_language_code,
    :description,
    :storefront_url,
    :isbn,
    :published_on,
    :year,
    authors: [],
    translators: [],
    contributors_by_role: %{},
    contributor_names: [],
    series_titles: [],
    series_slug: nil,
    subjects: [],
    editorial_praise: [],
    praise: [],
    review_links: [],
    missing_fields: %{},
    formats: [],
    identifiers: [],
    sources: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          work_id: String.t(),
          title: String.t(),
          subtitle: String.t() | nil,
          slug: String.t(),
          publisher: String.t() | nil,
          publisher_slug: String.t() | nil,
          author: String.t() | nil,
          cover: Cover.t() | nil,
          source: Source.t() | nil,
          original_title: String.t() | nil,
          original_language_code: String.t() | nil,
          description: String.t() | nil,
          storefront_url: String.t() | nil,
          isbn: String.t() | nil,
          published_on: Date.t() | nil,
          year: integer() | nil,
          authors: [Contributor.t()],
          translators: [Contributor.t()],
          contributors_by_role: %{optional(String.t()) => [Contributor.t()]},
          contributor_names: [String.t()],
          series_titles: [String.t()],
          series_slug: String.t() | nil,
          subjects: [String.t()],
          editorial_praise: [map()],
          praise: [map()],
          review_links: [map()],
          missing_fields: %{optional(String.t()) => String.t()},
          formats: [Format.t()],
          identifiers: [String.t()],
          sources: [Source.t()]
        }

  @spec fetch(t(), term()) :: {:ok, term()} | :error
  defdelegate fetch(projection, key), to: Hiraeth.Catalog.PublicProjection.Access

  @spec get_and_update(t(), term(), (term() -> {term(), term()})) :: {term(), term()}
  defdelegate get_and_update(projection, key, function),
    to: Hiraeth.Catalog.PublicProjection.Access

  @spec pop(t(), term()) :: {term(), t()}
  defdelegate pop(projection, key), to: Hiraeth.Catalog.PublicProjection.Access
end
