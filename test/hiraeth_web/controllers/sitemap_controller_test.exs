defmodule HiraethWeb.SitemapControllerTest do
  @moduledoc "The sitemap is generated from the public read model."

  use HiraethWeb.ConnCase, async: false

  @moduletag :public_catalog_full

  setup_all do
    Hiraeth.CatalogCleanup.ensure_committed_catalog_fixtures!()
    :ok
  end

  test "sitemap.xml lists static, book, publisher, series, and contributor pages", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    assert conn.resp_body =~ ~s|<?xml version="1.0" encoding="UTF-8"?>|
    assert conn.resp_body =~ ~s|<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">|
    assert conn.resp_body =~ "/books/deep-vellum-immigrant</loc>"
    assert conn.resp_body =~ "/publishers/deep-vellum</loc>"
    assert conn.resp_body =~ "/series/dalkey-archive-essentials</loc>"
    assert conn.resp_body =~ "/contributors/david-bowles</loc>"
    assert conn.resp_body =~ "<lastmod>"
  end

  test "sitemap supports ETag revalidation", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")
    etag = get_resp_header(conn, "etag") |> List.first()
    assert etag

    conn =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get("/sitemap.xml")

    assert conn.status == 304
    assert conn.resp_body == ""
  end

  test "robots.txt points at the sitemap and keeps ops/admin out", %{conn: conn} do
    conn = get(conn, "/robots.txt")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert conn.resp_body =~ "Disallow: /ops"
    assert conn.resp_body =~ "Disallow: /admin"
    assert conn.resp_body =~ "/sitemap.xml"
  end
end
