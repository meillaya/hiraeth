defmodule Hiraeth.Catalog.PublicProjection.Edition do
  @moduledoc """
  Edition detail projection.

  This is the full edition record behind `/editions/:slug`. Book pages nest the
  smaller `Format` projection instead, so a book listing does not carry source
  provenance it does not render.
  """

  alias Hiraeth.Catalog.PublicProjection.{Contributor, Cover, Dimensions, Source}

  # One flat struct keeps the edition response and its LiveView assign in one
  # shape. The field count is the public edition schema, not incidental state.
  @enforce_keys [:id, :work_id, :title, :slug]
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :id,
    :work_id,
    :title,
    :subtitle,
    :slug,
    :format,
    :published_on,
    :year,
    :publisher,
    :publisher_slug,
    :author,
    :isbn,
    :series_slug,
    :cover,
    :description,
    :storefront_url,
    :original_title,
    :original_language_code,
    :language_code,
    :page_count,
    :height_mm,
    :width_mm,
    :depth_mm,
    :dimensions,
    :source,
    :source_uri,
    authors: [],
    translators: [],
    contributors_by_role: %{},
    contributor_names: [],
    identifiers: [],
    series_titles: [],
    subjects: [],
    editorial_praise: [],
    review_links: [],
    missing_fields: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          work_id: String.t(),
          title: String.t(),
          subtitle: String.t() | nil,
          slug: String.t(),
          format: String.t() | nil,
          published_on: Date.t() | nil,
          year: integer() | nil,
          publisher: String.t() | nil,
          publisher_slug: String.t() | nil,
          author: String.t() | nil,
          isbn: String.t() | nil,
          series_slug: String.t() | nil,
          cover: Cover.t() | nil,
          description: String.t() | nil,
          storefront_url: String.t() | nil,
          original_title: String.t() | nil,
          original_language_code: String.t() | nil,
          language_code: String.t() | nil,
          page_count: non_neg_integer() | nil,
          height_mm: integer() | nil,
          width_mm: integer() | nil,
          depth_mm: integer() | nil,
          dimensions: Dimensions.t() | nil,
          source: Source.t() | nil,
          source_uri: String.t() | nil,
          authors: [Contributor.t()],
          translators: [Contributor.t()],
          contributors_by_role: %{optional(String.t()) => [Contributor.t()]},
          contributor_names: [String.t()],
          identifiers: [String.t()],
          series_titles: [String.t()],
          subjects: [String.t()],
          editorial_praise: [map()],
          review_links: [map()],
          missing_fields: %{optional(String.t()) => String.t()}
        }
end
