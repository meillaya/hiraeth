defmodule HiraethWeb.UiStatesLiveTest do
  use HiraethWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HiraethWeb.PageTestHelpers

  alias Hiraeth.Catalog.{Edition, Identifier, Publisher, Series, SeriesMembership, Work}
  alias Hiraeth.Catalog.PublicWorkProjection
  alias Hiraeth.Sources.SourceRecord
  alias HiraethWeb.CatalogComponents

  test "reusable state components render loading and generic errors" do
    assert render_component(&CatalogComponents.loading_skeleton/1,
             id: "state-loading",
             label: "Loading catalog cards"
           ) =~ "Loading catalog cards"

    assert render_component(&CatalogComponents.error_block/1,
             id: "state-error",
             title: "Could not read shelf",
             message: "The archive kept your filters intact."
           ) =~ "The archive kept your filters intact."
  end

  test "empty catalog and query states preserve the user's filter context", %{conn: conn} do
    {:ok, browse, _html} = live(conn, ~p"/browse?q=zzzz-no-catalog-match-🚫&page=99")
    assert has_element?(browse, "#browse-empty", "No catalog entries match")
    assert has_element?(browse, "#browse-empty", "zzzz-no-catalog-match-🚫")
  end

  test "not-found and missing-cover states are explicit", %{conn: conn} do
    Hiraeth.DemoFixtures.seed!()
    assert {:ok, _summary} = PublicWorkProjection.rebuild!(trigger: "test")

    {publisher, _conn} = page(conn, "/publishers/not-a-publisher", 404)
    assert page_has?(publisher, "#catalog-page-not-found", "No publisher matches")
    assert page_has?(publisher, "a[href='/browse']", "Back to books")

    assert redirected_to(get(conn, ~p"/editions/the-orchard-of-minor-moons-paperback")) ==
             "/books/the-orchard-of-minor-moons-paperback"

    {book, _html} = page(conn, "/books/the-orchard-of-minor-moons-paperback")
    assert page_has?(book, "#missing-cover-note", "Cover unavailable")
    assert page_has?(book, "#missing-cover-the-orchard-of-minor-moons-paperback")

    assert redirected_to(get(conn, ~p"/editions/not-an-edition")) == "/browse"
  end

  test "publisher with no editions and series with unknown order explain their state", %{
    conn: conn
  } do
    admin = %{id: Ash.UUID.generate(), catalog_write?: true}

    publisher =
      create!(Publisher, %{name: "Empty Shelf Press", slug: "empty-shelf-press"}, admin)

    {publisher_view, _conn} = page(conn, "/publishers/#{publisher.slug}")
    assert page_has?(publisher_view, "#publisher-no-editions", "No books are attached")

    series = create!(Series, %{title: "Unnumbered Sequence", slug: "unnumbered-sequence"}, admin)
    work = create!(Work, %{title: "Loose Leaf Noon", slug: "loose-leaf-noon"}, admin)

    edition =
      create!(
        Edition,
        %{
          title: "Loose Leaf Noon",
          slug: "loose-leaf-noon-paperback",
          format: "paperback",
          work_id: work.id,
          publisher_id: publisher.id
        },
        admin
      )

    create!(SeriesMembership, %{series_id: series.id, work_id: work.id, position: nil}, admin)

    create!(
      Identifier,
      %{identifier_type: "isbn_13", value: "9780000001998", edition_id: edition.id},
      admin
    )

    create!(
      SourceRecord,
      %{
        provider: "local_demo_fixture",
        source_type: "fixture",
        source_uri: "local_demo_fixture:edition:#{edition.slug}",
        license_note: "Local test fixture.",
        source_identity: "9780000001998",
        edition_id: edition.id,
        raw_payload: %{"edition" => %{"isbn_13" => "9780000001998", "title" => "Loose Leaf Noon"}},
        imported_at: DateTime.utc_now(:second)
      },
      admin
    )

    assert {:ok, _summary} = PublicWorkProjection.rebuild!(trigger: "test")

    {series_view, _html} = page(conn, "/series/#{series.slug}")
    refute page_has?(series_view, "#series-unknown-order")
    assert page_has?(series_view, "#series-editions", "Loose Leaf Noon")
  end

  defp create!(resource, attrs, actor) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(actor: actor)
  end
end
