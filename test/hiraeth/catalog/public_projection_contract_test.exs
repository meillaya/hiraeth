defmodule Hiraeth.Catalog.PublicProjectionContractTest do
  use HiraethWeb.ConnCase, async: false

  @moduletag :public_catalog_full

  alias Hiraeth.Catalog.PublicProjection
  alias HiraethWeb.PublicCatalog

  @book_keys [
    :id,
    :work_id,
    :title,
    :subtitle,
    :slug,
    :publisher,
    :publisher_slug,
    :author,
    :authors,
    :translators,
    :contributors_by_role,
    :contributor_names,
    :series_titles,
    :series_slug,
    :cover,
    :source,
    :original_title,
    :original_language_code,
    :subjects,
    :description,
    :editorial_praise,
    :praise,
    :storefront_url,
    :review_links,
    :missing_fields,
    :formats,
    :identifiers,
    :isbn,
    :sources,
    :published_on,
    :year
  ]

  @format_keys [
    :edition_slug,
    :format,
    :format_label,
    :identifiers,
    :source_identity,
    :published_on,
    :language_code,
    :page_count,
    :height_mm,
    :width_mm,
    :depth_mm,
    :dimensions
  ]

  @source_keys [
    :id,
    :source_record_id,
    :provider,
    :source_type,
    :source_uri,
    :license_note,
    :import_run_id,
    :imported_at,
    :field_sources,
    :provider_permissions,
    :source_identity
  ]

  setup_all do
    Hiraeth.CatalogCleanup.ensure_committed_catalog_fixtures!()
    :ok
  end

  test "public catalog book boundary returns typed stable projection structs" do
    assert %PublicProjection.Book{} = book = PublicCatalog.book("deep-vellum-immigrant")
    assert Map.keys(Map.from_struct(book)) |> Enum.sort() == Enum.sort(@book_keys)

    assert is_binary(book.id)
    assert is_binary(book.work_id)
    assert is_binary(book.slug)
    assert is_binary(book.title)
    assert is_list(book.subjects)
    assert is_list(book.identifiers)
    assert is_list(book.formats)
    assert is_list(book.sources)

    assert [%PublicProjection.Format{} = format | _] = book.formats
    assert Map.keys(Map.from_struct(format)) |> Enum.sort() == Enum.sort(@format_keys)
    assert is_binary(format.edition_slug)
    assert is_binary(format.format_label)
    assert is_list(format.identifiers)

    assert %PublicProjection.Source{} = book.source
    assert Map.keys(Map.from_struct(book.source)) |> Enum.sort() == Enum.sort(@source_keys)
    assert is_binary(book.source.source_record_id)
    assert is_binary(book.source.provider)
    assert is_map(book.source.field_sources)

    assert [%PublicProjection.Source{} | _] = book.sources
    assert [%PublicProjection.Contributor{} | _] = book.authors
    assert [%PublicProjection.Contributor{} | _] = book.translators
    assert %{"author" => [%PublicProjection.Contributor{} | _]} = book.contributors_by_role
  end

  test "paged public catalog entries use the same projection boundary" do
    assert %PublicProjection.Page{
             entries: [%PublicProjection.Book{} | _],
             page: 1,
             total_count: total_count
           } = PublicCatalog.book_page(nil, 1)

    assert total_count > 0
  end

  test "detail pages and index rows use typed structs instead of bare maps" do
    book = PublicCatalog.book("deep-vellum-immigrant")

    assert %PublicProjection.Publisher{} =
             publisher = PublicCatalog.publisher(book.publisher_slug)

    assert %PublicProjection.Groupings{} = publisher.groupings
    assert publisher.editions_count == length(publisher.editions)
    assert Enum.all?(publisher.editions, &match?(%PublicProjection.Book{}, &1))

    assert Enum.all?(
             publisher.groupings.formats ++ publisher.groupings.languages,
             &match?(%PublicProjection.Grouping{}, &1)
           )

    assert is_nil(publisher.cover_sample) or
             match?(%PublicProjection.CoverSample{}, publisher.cover_sample)

    assert %PublicProjection.Edition{} =
             edition = PublicCatalog.edition(hd(book.formats).edition_slug)

    assert is_nil(edition.cover) or match?(%PublicProjection.Cover{}, edition.cover)
    assert is_nil(edition.source) or match?(%PublicProjection.Source{}, edition.source)

    assert is_nil(edition.dimensions) or
             match?(%PublicProjection.Dimensions{}, edition.dimensions)

    assert Enum.all?(edition.authors, &match?(%PublicProjection.Contributor{}, &1))

    assert Enum.all?(PublicCatalog.series(), &match?(%PublicProjection.Series{}, &1))

    assert Enum.all?(
             PublicCatalog.contributors(),
             &match?(%PublicProjection.ContributorSummary{}, &1)
           )

    case PublicCatalog.series() do
      [%PublicProjection.Series{} = series | _] ->
        assert %PublicProjection.Series{} = detail = PublicCatalog.series_by_slug(series.slug)
        assert Enum.all?(detail.editions, &match?(%PublicProjection.Book{}, &1))
        assert detail.memberships == []

      [] ->
        :ok
    end
  end

  test "malformed filter shapes and enormous page numbers do not crash" do
    assert %PublicProjection.Page{} = PublicCatalog.book_page(%{"q" => %{"nested" => "value"}}, 1)
    assert %PublicProjection.Page{} = PublicCatalog.book_page(%{"q" => ["a", "b"]}, 1)

    assert %PublicProjection.Page{} = page = PublicCatalog.book_page(nil, 10 ** 30)
    assert page.page <= page.total_pages
  end

  test "the author sort returns a page without a grouping error" do
    assert %PublicProjection.Page{entries: [_ | _]} =
             PublicCatalog.book_page(%{"sort" => "author"}, 1, 5)
  end

  test "the title sort orders the page by work title" do
    titles =
      PublicCatalog.book_page(%{"sort" => "title"}, 1, 10).entries
      |> Enum.map(& &1.title)

    assert titles == Enum.sort_by(titles, &String.downcase/1)
  end

  test "more_from_publisher is bounded, same-press, and excludes the current work" do
    publisher = Enum.find(PublicCatalog.publishers(), &(&1.editions_count > 1))
    assert publisher, "the committed corpus must contain a press with multiple public works"

    book = PublicCatalog.book_page(%{"publisher" => publisher.slug}, 1, 1).entries |> hd()
    related = PublicCatalog.more_from_publisher(book, 4)

    assert length(related) in 1..4
    assert Enum.all?(related, &match?(%PublicProjection.Book{}, &1))
    assert Enum.all?(related, &(&1.publisher_slug == book.publisher_slug))
    refute Enum.any?(related, &(&1.work_id == book.work_id))
    refute Enum.any?(related, &(&1.slug == book.slug))

    assert PublicCatalog.more_from_publisher(book, 2) |> length() <= 2
    assert PublicCatalog.more_from_publisher(nil) == []
    assert PublicCatalog.more_from_publisher(%{book | publisher_slug: nil}) == []
  end
end
