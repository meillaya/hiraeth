defmodule HiraethWeb.CoverCacheHeadersTest do
  use HiraethWeb.ConnCase, async: false

  alias Hiraeth.Covers
  alias Hiraeth.Covers.{CoverAsset, MissCache, Store}

  defmodule OversizedStore do
    @behaviour Hiraeth.Covers.Store

    @impl true
    def configured?, do: true

    @impl true
    def get(_key) do
      send(self(), :oversized_store_get)
      {:ok, :binary.copy(<<0>>, 11 * 1024 * 1024), "image/jpeg"}
    end

    @impl true
    def put(_key, _body, _content_type), do: :ok

    @impl true
    def delete(_key), do: :ok
  end

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

  test "content-hashed variants are immutable", %{conn: conn} do
    filename = "#{String.duplicate("a", 64)}-400w-#{String.duplicate("b", 64)}.webp"
    path = Path.join("priv/static/covers/cache", filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "variant bytes")
    on_exit(fn -> File.rm(path) end)

    conn = get(conn, "/covers/cache/#{filename}")

    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  test "a cover the cache cannot serve answers a cacheable 404", %{conn: conn} do
    conn = get(conn, "/covers/cache/missing-#{System.unique_integer([:positive])}.jpg")

    assert conn.status == 404
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "an object too large to proxy is not downloaded again", %{conn: conn} do
    previous = Application.get_env(:hiraeth, Store)
    suffix = System.unique_integer([:positive])
    filename = "oversized-cover-#{suffix}.jpg"
    path = Path.join("priv/static/covers/cache", filename)

    Application.put_env(:hiraeth, Store, adapter: OversizedStore)

    CoverAsset
    |> Ash.Changeset.for_create(:create, %{
      source_url: "https://cdn.shopify.com/oversized-cover-#{suffix}.jpg",
      provider: "deep_vellum_official_store",
      rights_basis: "local_cache_permitted",
      cache_policy: "cache_allowed",
      cached_file_path: path,
      takedown_state: "visible"
    })
    |> Ash.create!(authorize?: false)

    on_exit(fn ->
      File.rm(path)
      MissCache.forget(Covers.object_key(path))

      if is_nil(previous) do
        Application.delete_env(:hiraeth, Store)
      else
        Application.put_env(:hiraeth, Store, previous)
      end
    end)

    conn = get(conn, "/covers/cache/#{filename}")

    assert conn.status == 404
    assert_received :oversized_store_get

    conn = get(conn, "/covers/cache/#{filename}")

    assert conn.status == 404
    refute_received :oversized_store_get
  end
end
