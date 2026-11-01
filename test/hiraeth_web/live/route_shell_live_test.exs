defmodule HiraethWeb.RouteShellLiveTest do
  use HiraethWeb.ConnCase, async: false

  @moduletag :public_catalog_full

  import Phoenix.LiveViewTest
  import HiraethWeb.PageTestHelpers
  alias HiraethWeb.PublicCatalog

  setup_all do
    Hiraeth.CatalogCleanup.ensure_committed_catalog_fixtures!()
    :ok
  end

  test "GET / renders the editorial home shell", %{conn: conn} do
    {view, _html} = page(conn, "/")

    assert page_has?(view, "#home-shell")
    assert page_has?(view, "#home-spotlight")
    assert page_has?(view, "#recent-acquisitions")
  end

  test "GET /browse filters real books and displays details on selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/browse")

    assert has_element?(view, "#browse-shell")

    assert has_element?(view, "#catalog-index", "Shelf")

    assert has_element?(
             view,
             "#catalog-page-count",
             "Page 1 of #{ceil_div(PublicCatalog.book_page(nil, 1).total_count, PublicCatalog.page_size())}"
           )

    {:ok, filtered, _html} = live(conn, ~p"/browse?q=Tunnel")
    assert has_element?(filtered, "#catalog-index h4", "The Tunnel")
    assert has_element?(filtered, "#catalog-grid", "William H. Gass")
  end

  test "GET /search filters items dynamically", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/search")

    assert has_element?(view, "#search-shell")

    assert has_element?(
             view,
             "#search-results",
             "#{format_count(PublicCatalog.book_page(nil, 1).total_count)} found"
           )

    view
    |> form("#catalog-search-form", search: %{query: "Archipelago"})
    |> render_change()

    assert has_element?(view, "#search-results", "Bob and Hilbert")

    view
    |> form("#catalog-search-form", search: %{query: "][\'<>☃"})
    |> render_change()

    assert has_element?(view, "#search-empty", "No catalog entries match")
  end

  defp format_count(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  test "GET /publishers renders the real publisher directory", %{conn: conn} do
    {html, _conn} = page(conn, "/publishers")

    assert page_has?(html, "#publishers-shell")
    assert page_has?(html, "#publisher-deep-vellum")
    assert page_has?(html, "#publisher-dalkey-archive")
    assert page_has?(html, "#publisher-archipelago-books")
  end

  test "GET /series renders grouped collection shell even when pilot data has no series", %{
    conn: conn
  } do
    {view, _html} = page(conn, "/series")
    assert page_has?(view, "#series-shell")
  end

  test "route shells do not nest main landmarks inside the app layout", %{conn: conn} do
    assert_static_single_main(conn, "/contributors", "#contributors-shell")
    assert_static_single_main(conn, "/contributors/david-bowles", "#contributor-detail-shell")
    assert_static_single_main(conn, "/series", "#series-shell")
    assert_static_single_main(conn, "/books/deep-vellum-immigrant", "#book-detail-shell")

    {:ok, _view, html} = live(conn, ~p"/search")
    assert_single_main_html(html, "#search-shell")
  end

  defp assert_static_single_main(conn, path, shell_selector) do
    {html, _conn} = page(conn, path)
    assert_single_main_html(html, shell_selector)
  end

  defp assert_single_main_html(html, shell_selector) do
    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query(shell_selector) |> LazyHTML.to_tree() |> length() == 1
    assert document |> LazyHTML.query("main") |> LazyHTML.to_tree() |> length() == 1

    assert document |> LazyHTML.query("main #{shell_selector}") |> LazyHTML.to_tree() |> length() ==
             1
  end

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
end
