defmodule HiraethWeb.SitemapController do
  @moduledoc """
  Generated XML sitemap and robots policy for the public catalogue.

  The sitemap is built from the public read model, so it can only list pages
  that the browser can also resolve. It is cached in the same ETS page cache as
  controller-rendered pages and invalidated by the projection watcher.
  """

  use HiraethWeb, :controller

  alias HiraethWeb.{PageCache, PublicCatalog}

  @ttl :timer.hours(1)

  def sitemap(conn, _params) do
    {:ok, body, etag} =
      PageCache.fetch(
        :sitemap,
        fn ->
          body = render_sitemap(PublicCatalog.sitemap_entries())
          {body, PageCache.etag(body)}
        end,
        @ttl
      )

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("etag", etag)
    |> put_resp_header("cache-control", "public, max-age=3600, stale-while-revalidate=86400")
    |> maybe_not_modified(etag, body)
  end

  def robots(conn, _params) do
    body =
      """
      User-agent: *
      Allow: /
      Disallow: /ops
      Disallow: /admin

      Sitemap: #{HiraethWeb.Endpoint.url()}/sitemap.xml
      """

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, body)
  end

  defp render_sitemap(entries) do
    urls =
      Enum.map_join(entries, "\n", fn entry ->
        lastmod =
          case entry.lastmod do
            %Date{} = date -> "\n    <lastmod>#{Date.to_iso8601(date)}</lastmod>"
            _ -> ""
          end

        "  <url>\n    <loc>#{xml_escape(HiraethWeb.Endpoint.url() <> entry.path)}</loc>" <>
          lastmod <> "\n  </url>"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """
  end

  defp xml_escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp maybe_not_modified(conn, etag, body) do
    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      send_resp(conn, 200, body)
    end
  end
end
