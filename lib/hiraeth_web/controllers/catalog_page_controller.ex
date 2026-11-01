defmodule HiraethWeb.CatalogPageController do
  use HiraethWeb, :controller

  alias Phoenix.HTML.Safe

  alias HiraethWeb.{CatalogPageHTML, Layouts, PageCache, PublicCatalog}

  plug :put_layout, false

  def home(conn, _params) do
    selection = PublicCatalog.home_selection(4)
    publishers = PublicCatalog.publishers()
    series = PublicCatalog.series()

    presses =
      publishers
      |> Enum.sort_by(&{-(&1.editions_count || 0), &1.name})
      |> Enum.take(6)

    assigns = %{
      page_title: "Independent literary presses",
      catalog_count: PublicCatalog.book_page(%{"sort" => "recently_added"}, 1, 1).total_count,
      press_count: length(publishers),
      series_count: length(series),
      spotlight: selection.spotlight,
      spotlight_upcoming?: upcoming?(selection.spotlight),
      presses: presses,
      recent: selection.recent
    }

    conn
    |> assign(assigns)
    |> send_page(:home, assigns)
  end

  def book(conn, %{"slug" => slug}) do
    case PublicCatalog.book(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> send_page(:not_found,
          page_title: "Book not found",
          message: "No book matches that slug."
        )

      book ->
        cached_page(conn, {:book, slug}, 300, fn ->
          render_page(:book, page_title: book.title, book: book, catalog_count: nil)
        end)
    end
  end

  def series(conn, _params) do
    series = PublicCatalog.series_with_preview_editions()
    streams = %{series_editions: []}

    cached_page(conn, {:series, conn.query_string}, 60, fn ->
      render_page(:series,
        page_title: "Collections",
        series: series,
        series_empty?: series == [],
        streams: streams,
        catalog_count: nil
      )
    end)
  end

  def series_show(conn, %{"slug" => slug}) do
    case PublicCatalog.series_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> send_page(:not_found,
          page_title: "Collection not found",
          message: "No collection matches that slug."
        )

      series ->
        editions = List.wrap(series.editions)

        streams = %{
          series_editions: Enum.map(editions, &{"series-edition-#{&1.work_id}", &1})
        }

        cached_page(conn, {:series, slug}, 300, fn ->
          render_page(:series_show, page_title: series.title, series: series, streams: streams)
        end)
    end
  end

  def contributors(conn, params) do
    role = Map.get(params, "role")
    contributors = PublicCatalog.contributors(role)
    streams = %{contributors: Enum.map(contributors, &{"contributor-#{&1.slug}", &1})}

    cached_page(conn, {:contributors, role, conn.query_string}, 60, fn ->
      render_page(:contributors,
        page_title: contributor_title(role),
        role: normalize_role(role),
        streams: streams,
        catalog_count: nil
      )
    end)
  end

  def contributor(conn, %{"slug" => slug}) do
    case PublicCatalog.contributor(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> send_page(:not_found,
          page_title: "Contributor not found",
          message: "No contributor matches that slug."
        )

      contributor ->
        streams = %{
          contributor_books: Enum.map(contributor.books, &{"contributor-book-#{&1.work_id}", &1})
        }

        cached_page(conn, {:contributor, slug}, 300, fn ->
          render_page(:contributor,
            page_title: contributor.name,
            contributor: contributor,
            streams: streams
          )
        end)
    end
  end

  def edition(conn, %{"slug" => slug}) do
    case PublicCatalog.book(slug) do
      nil -> redirect(conn, to: "/browse")
      book -> redirect(conn, to: "/books/#{book.slug}")
    end
  end

  defp send_page(conn, template, assigns) do
    {body, etag} = render_page(template, assigns)

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("etag", etag)
    |> put_resp_header("cache-control", cache_control(template))
    |> send_resp(conn.status || 200, body)
  end

  defp cached_page(%{method: "HEAD"} = conn, _key, _ttl_seconds, render_fun) do
    {body, etag} = render_fun.()

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("etag", etag)
    |> send_resp(conn.status || 200, body)
  end

  defp cached_page(conn, key, ttl_seconds, render_fun) do
    key = {key, conn.query_string}

    {:ok, body, etag} = PageCache.fetch(key, render_fun, :timer.seconds(ttl_seconds))

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("etag", etag)
    |> put_resp_header("cache-control", "public, max-age=60, stale-while-revalidate=300")
    |> maybe_not_modified(etag, body)
  end

  defp maybe_not_modified(conn, etag, body) do
    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      send_resp(conn, conn.status || 200, body)
    end
  end

  defp render_page(template, assigns) do
    assigns = assigns |> Map.new() |> Map.put_new(:flash, %{})
    inner = apply(CatalogPageHTML, template, [assigns])
    root_assigns = %{inner_content: inner, page_title: assigns[:page_title], flash: %{}}
    body = Layouts.root(root_assigns) |> Safe.to_iodata() |> IO.iodata_to_binary()
    {body, PageCache.etag(body)}
  end

  defp cache_control(:home), do: "no-store"
  defp cache_control(_template), do: "public, max-age=60, stale-while-revalidate=300"

  defp upcoming?(%{published_on: %Date{} = date}), do: Date.compare(date, Date.utc_today()) == :gt
  defp upcoming?(_book), do: false

  defp contributor_title("author"), do: "Authors"
  defp contributor_title("translator"), do: "Translators"
  defp contributor_title(_role), do: "Contributors"

  defp normalize_role(role) when role in ["author", "translator"], do: role
  defp normalize_role(_role), do: nil
end
