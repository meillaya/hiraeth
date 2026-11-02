defmodule HiraethWeb.BrandAssetsTest do
  @moduledoc "The Hiraeth wordmark and icon set are part of every page shell."

  use HiraethWeb.ConnCase, async: true

  test "the page head links the icon set and the header renders the wordmark", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(rel="icon" href="/images/logo/favicon.svg")
    assert html =~ ~s(rel="icon" href="/favicon.ico")
    assert html =~ ~s(rel="apple-touch-icon" href="/images/logo/apple-touch-icon.png")
    assert html =~ ~s(rel="manifest" href="/images/logo/site.webmanifest")
    assert html =~ ~s(name="theme-color" content="#dfe7de")
    assert html =~ ~s(src="/images/logo/logo-wordmark.svg")
  end

  test "the SVG wordmark and icon files are served from the static root", %{conn: conn} do
    for {path, content_type} <- [
          {"/images/logo/logo-wordmark.svg", "image/svg+xml"},
          {"/images/logo/favicon.svg", "image/svg+xml"},
          {"/images/logo/apple-touch-icon.png", "image/png"},
          {"/images/logo/site.webmanifest", "application/manifest+json"},
          {"/favicon.ico", "image/vnd.microsoft.icon"}
        ] do
      conn = get(conn, path)

      assert conn.status == 200, "#{path} returned #{conn.status}"
      assert get_resp_header(conn, "content-type") == [content_type]
    end
  end
end
