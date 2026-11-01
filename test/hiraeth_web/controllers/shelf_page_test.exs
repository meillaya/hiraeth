defmodule HiraethWeb.ShelfPageTest do
  use HiraethWeb.ConnCase, async: false

  @moduletag :public_catalog_full

  import HiraethWeb.PageTestHelpers

  alias Hiraeth.CatalogCleanup
  alias HiraethWeb.PublicCatalog

  setup_all do
    CatalogCleanup.ensure_committed_catalog_fixtures!()
    :ok
  end

  test "GET /shelf renders the browser-local shelf shell and starter books", %{conn: conn} do
    {html, _conn} = page(conn, "/shelf")

    assert page_has?(html, "#shelf-shell")
    assert page_has?(html, "#shelf-title", "Shelf")
    assert page_has?(html, "#shelf-page-empty", "A shelf waiting to be filled.")
    assert page_has?(html, "#shelf-page-empty", "A place to start")
    assert page_has?(html, "[data-shelf-total]", "0")
    assert page_has?(html, "[data-shelf-export][hidden]")
    assert page_has?(html, "#shelf-start-grid .sb-book")
    assert page_has?(html, "#shelf-dialog", "Your shelf")
    assert page_has?(html, ".sb-footer__nav a[href=\"/shelf\"]")
  end

  test "a book page exposes the save control and a bounded same-press tray", %{conn: conn} do
    publisher = Enum.find(PublicCatalog.publishers(), &(&1.editions_count > 1))
    assert publisher

    book = PublicCatalog.book_page(%{"publisher" => publisher.slug}, 1, 1).entries |> hd()
    {html, _conn} = page(conn, "/books/#{book.slug}")

    assert page_has?(html, "#book-save-shelf[data-save-slug=\"#{book.slug}\"]", "Save to shelf")
    assert page_has?(html, "#more-from-press", "More from #{book.publisher}")
    assert page_has?(html, "#more-from-press", "Selected volumes")
    assert page_has?(html, "#more-from-press", "All records")

    section =
      html
      |> String.split(~s(id="more-from-press"), parts: 2)
      |> List.last()
      |> String.split("</section>", parts: 2)
      |> hd()

    cards = Regex.scan(~r/class="sb-book"/, section) |> length()

    assert cards in 1..4
    refute section =~ ~s(href="/books/#{book.slug}")
    assert section =~ ~s(href="/publishers/#{publisher.slug}")
  end

  test "book pages without a press omit the more-from tray", %{conn: conn} do
    book =
      PublicCatalog.book_page(nil, 1, 50).entries
      |> Enum.find(&is_nil(&1.publisher_slug))

    if book do
      {html, _conn} = page(conn, "/books/#{book.slug}")
      refute page_has?(html, "#more-from-press")
    end
  end
end
