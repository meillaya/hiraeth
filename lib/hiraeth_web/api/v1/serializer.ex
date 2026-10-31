defmodule HiraethWeb.Api.V1.Serializer do
  @moduledoc """
  Serializes public catalog projections into the versioned JSON contract.

  The serializer is the only place that turns a projection into wire data. It
  emits every declared field on every response, so the OpenAPI schema can mark
  fields as required and clients never have to guess whether a key is absent or
  null. Internal row identifiers and cache file paths are not emitted.
  """

  alias Hiraeth.Catalog.PublicProjection, as: Projection

  @type json :: %{optional(String.t()) => term()}

  @spec contributor(Projection.Contributor.t()) :: json()
  def contributor(%Projection.Contributor{} = contributor) do
    %{
      "id" => contributor.id,
      "name" => contributor.name,
      "slug" => contributor.slug,
      "role" => contributor.role,
      "position" => contributor.position
    }
  end

  @spec cover(Projection.Cover.t()) :: json()
  def cover(%Projection.Cover{} = cover) do
    %{
      "public_url" => cover.public_url,
      "thumbnail_url" => cover.thumbnail_url,
      "source_url" => cover.source_url,
      "provider" => cover.provider,
      "rights_basis" => cover.rights_basis,
      "attribution_text" => cover.attribution_text,
      "attribution_url" => cover.attribution_url
    }
  end

  @spec source(Projection.Source.t()) :: json()
  def source(%Projection.Source{} = source) do
    %{
      "provider" => source.provider,
      "source_type" => source.source_type,
      "source_uri" => source.source_uri,
      "source_identity" => source.source_identity,
      "license_note" => source.license_note,
      "imported_at" => datetime(source.imported_at)
    }
  end

  @spec dimensions(Projection.Dimensions.t()) :: json()
  def dimensions(%Projection.Dimensions{} = dimensions) do
    %{
      "height_mm" => dimensions.height_mm,
      "width_mm" => dimensions.width_mm,
      "depth_mm" => dimensions.depth_mm
    }
  end

  @spec format(Projection.Format.t()) :: json()
  def format(%Projection.Format{} = format) do
    %{
      "edition_slug" => format.edition_slug,
      "format" => format.format,
      "format_label" => format.format_label,
      "source_identity" => format.source_identity,
      "published_on" => date(format.published_on),
      "language_code" => format.language_code,
      "page_count" => format.page_count,
      "dimensions" => optional(format.dimensions, &dimensions/1),
      "identifiers" => format.identifiers
    }
  end

  @spec book(Projection.Book.t()) :: json()
  def book(%Projection.Book{} = book) do
    %{
      "id" => book.id,
      "slug" => book.slug,
      "title" => book.title,
      "subtitle" => book.subtitle,
      "publisher" => book.publisher,
      "publisher_slug" => book.publisher_slug,
      "author" => book.author,
      "description" => book.description,
      "original_title" => book.original_title,
      "original_language_code" => book.original_language_code,
      "published_on" => date(book.published_on),
      "year" => book.year,
      "isbn" => book.isbn,
      "storefront_url" => book.storefront_url,
      "subjects" => book.subjects,
      "praise" => praise(book.praise),
      "review_links" => review_links(book.review_links),
      "missing_fields" => string_map(book.missing_fields),
      "series_titles" => book.series_titles,
      "series_slug" => book.series_slug,
      "identifiers" => book.identifiers,
      "formats" => Enum.map(book.formats, &format/1),
      "authors" => Enum.map(book.authors, &contributor/1),
      "translators" => Enum.map(book.translators, &contributor/1),
      "contributors_by_role" => contributors_by_role(book.contributors_by_role),
      "contributor_names" => book.contributor_names,
      "cover" => renderable_cover(book.cover),
      "source" => optional(book.source, &source/1),
      "sources" => Enum.map(book.sources, &source/1)
    }
  end

  @spec edition(Projection.Edition.t()) :: json()
  def edition(%Projection.Edition{} = edition) do
    %{
      "id" => edition.id,
      "work_id" => edition.work_id,
      "slug" => edition.slug,
      "title" => edition.title,
      "subtitle" => edition.subtitle,
      "format" => edition.format,
      "published_on" => date(edition.published_on),
      "year" => edition.year,
      "publisher" => edition.publisher,
      "publisher_slug" => edition.publisher_slug,
      "author" => edition.author,
      "isbn" => edition.isbn,
      "series_slug" => edition.series_slug,
      "cover" => renderable_cover(edition.cover),
      "description" => edition.description,
      "storefront_url" => edition.storefront_url,
      "original_title" => edition.original_title,
      "original_language_code" => edition.original_language_code,
      "language_code" => edition.language_code,
      "page_count" => edition.page_count,
      "dimensions" => optional(edition.dimensions, &dimensions/1),
      "source" => optional(edition.source, &source/1),
      "source_uri" => edition.source_uri,
      "authors" => Enum.map(edition.authors, &contributor/1),
      "translators" => Enum.map(edition.translators, &contributor/1),
      "contributors_by_role" => contributors_by_role(edition.contributors_by_role),
      "contributor_names" => edition.contributor_names,
      "identifiers" => edition.identifiers,
      "series_titles" => edition.series_titles,
      "subjects" => edition.subjects,
      "praise" => praise(edition.editorial_praise),
      "review_links" => review_links(edition.review_links),
      "missing_fields" => string_map(edition.missing_fields)
    }
  end

  @spec grouping(Projection.Grouping.t()) :: json()
  def grouping(%Projection.Grouping{} = grouping) do
    %{"label" => grouping.label, "count" => grouping.count, "slug" => grouping.slug}
  end

  @spec groupings(Projection.Groupings.t()) :: json()
  def groupings(%Projection.Groupings{} = groupings) do
    %{
      "formats" => Enum.map(groupings.formats, &grouping/1),
      "languages" => Enum.map(groupings.languages, &grouping/1),
      "original_languages" => Enum.map(groupings.original_languages, &grouping/1),
      "series" => Enum.map(groupings.series, &grouping/1),
      "translations" => Enum.map(groupings.translations, &grouping/1),
      "contributor_roles" => Enum.map(groupings.contributor_roles, &grouping/1)
    }
  end

  @spec cover_sample(Projection.CoverSample.t()) :: json() | nil
  def cover_sample(%Projection.CoverSample{} = sample) do
    case renderable_cover(sample.cover) do
      nil -> nil
      cover -> %{"title" => sample.title, "cover" => cover}
    end
  end

  @spec series_membership(Projection.SeriesMembership.t()) :: json()
  def series_membership(%Projection.SeriesMembership{} = membership) do
    %{"work_id" => membership.work_id, "position" => membership.position}
  end

  @spec publisher(Projection.Publisher.t()) :: json()
  def publisher(%Projection.Publisher{} = publisher) do
    %{
      "id" => publisher.id,
      "name" => publisher.name,
      "slug" => publisher.slug,
      "description" => publisher.description,
      "editions_count" => publisher.editions_count,
      "cover_sample" => optional(publisher.cover_sample, &cover_sample/1),
      "groupings" => groupings(publisher.groupings),
      "editions" => Enum.map(publisher.editions, &book/1)
    }
  end

  @spec series(Projection.Series.t()) :: json()
  def series(%Projection.Series{} = series) do
    %{
      "id" => series.id,
      "title" => series.title,
      "name" => series.name,
      "slug" => series.slug,
      "publisher" => series.publisher,
      "publisher_slug" => series.publisher_slug,
      "editions_count" => series.editions_count,
      "unknown_order" => series.unknown_order?,
      "editions" => Enum.map(series.editions, &book/1),
      "memberships" => Enum.map(series.memberships, &series_membership/1),
      "preview_editions" => Enum.map(series.preview_editions, &book/1)
    }
  end

  @spec contributor_summary(Projection.ContributorSummary.t()) :: json()
  def contributor_summary(%Projection.ContributorSummary{} = contributor) do
    %{
      "id" => contributor.id,
      "name" => contributor.name,
      "display_name" => contributor.display_name,
      "slug" => contributor.slug,
      "roles" => contributor.roles,
      "books_count" => contributor.books_count,
      "books" => Enum.map(contributor.books, &book/1)
    }
  end

  @spec book_page(Projection.Page.t(Projection.Book.t())) :: json()
  def book_page(%Projection.Page{} = page), do: page(page, &book/1)

  @spec edition_page(Projection.Page.t(Projection.Edition.t())) :: json()
  def edition_page(%Projection.Page{} = page), do: page(page, &edition/1)

  @spec publisher_page(Projection.Page.t(Projection.Publisher.t())) :: json()
  def publisher_page(%Projection.Page{} = page), do: page(page, &publisher/1)

  @spec series_page(Projection.Page.t(Projection.Series.t())) :: json()
  def series_page(%Projection.Page{} = page), do: page(page, &series/1)

  @spec contributor_page(Projection.Page.t(Projection.ContributorSummary.t())) :: json()
  def contributor_page(%Projection.Page{} = page), do: page(page, &contributor_summary/1)

  @spec error(String.t(), String.t()) :: json()
  @spec error(String.t(), String.t(), map()) :: json()
  def error(code, message, details \\ %{}) do
    %{"error" => %{"code" => code, "message" => message, "details" => details}}
  end

  defp page(%Projection.Page{} = page, serializer) do
    %{
      "data" => Enum.map(page.entries, serializer),
      "meta" => %{
        "page" => page.page,
        "page_size" => page.page_size,
        "total_count" => page.total_count,
        "total_pages" => page.total_pages
      }
    }
  end

  defp contributors_by_role(contributors_by_role) when is_map(contributors_by_role) do
    Map.new(contributors_by_role, fn {role, contributors} ->
      {to_string(role), Enum.map(contributors, &contributor/1)}
    end)
  end

  # Praise and review links come from provider JSON, so unknown or malformed
  # entries are dropped rather than emitted with missing required keys.
  defp praise(entries) when is_list(entries) do
    entries
    |> Enum.filter(fn entry -> is_map(entry) and is_binary(entry["quote"]) end)
    |> Enum.map(fn entry ->
      %{
        "quote" => entry["quote"],
        "source" => entry["source"],
        "source_uri" => entry["source_uri"]
      }
    end)
  end

  defp praise(_entries), do: []

  defp review_links(entries) when is_list(entries) do
    entries
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn entry ->
      %{
        "source" => entry["source"],
        "source_uri" => entry["source_uri"],
        "rights_basis" => entry["rights_basis"],
        "excerpt" => entry["excerpt"]
      }
    end)
  end

  defp review_links(_entries), do: []

  defp string_map(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), if(is_binary(value), do: value, else: inspect(value))}
    end)
  end

  defp string_map(_map), do: %{}

  # A cover row can exist while its file is not cached yet. The public contract
  # only carries renderable covers, so a nil public URL drops the cover and the
  # client falls back to typographic presentation.
  defp renderable_cover(nil), do: nil

  defp renderable_cover(%Projection.Cover{} = cover) do
    if is_binary(cover.public_url), do: cover(cover), else: nil
  end

  defp optional(nil, _serializer), do: nil
  defp optional(value, serializer), do: serializer.(value)

  defp date(nil), do: nil
  defp date(%Date{} = date), do: Date.to_iso8601(date)

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
