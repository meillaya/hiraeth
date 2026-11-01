defmodule HiraethWeb.CoverCacheHeadersTest do
  use HiraethWeb.ConnCase, async: false

  test "cached cover files carry a long browser cache and nosniff", %{conn: conn} do
    filename = "headers-#{System.unique_integer([:positive])}.jpg"
    path = Path.join("priv/static/covers/cache", filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, <<0xFF, 0xD8, 0xFF, 0xE0>>)
    on_exit(fn -> File.rm(path) end)

    conn = get(conn, "/covers/cache/#{filename}")

    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "a cover the cache cannot serve answers a cacheable 404", %{conn: conn} do
    conn = get(conn, "/covers/cache/missing-#{System.unique_integer([:positive])}.jpg")

    assert conn.status == 404
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end
end
