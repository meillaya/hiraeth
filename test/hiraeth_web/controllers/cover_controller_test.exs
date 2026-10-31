defmodule HiraethWeb.CoverControllerTest do
  @moduledoc """
  The cover proxy fills local misses from the object store and refuses
  non-public or unsafe paths.
  """

  use HiraethWeb.ConnCase, async: false

  alias Hiraeth.Covers
  alias Hiraeth.Covers.CoverAsset
  alias Hiraeth.TestSupport.CoverStoreFake

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00, 0x00, 0x00>>

  setup do
    previous = Application.get_env(:hiraeth, Hiraeth.Covers.Store)
    Application.put_env(:hiraeth, Hiraeth.Covers.Store, adapter: CoverStoreFake)
    CoverStoreFake.reset()

    on_exit(fn ->
      CoverStoreFake.reset()

      if is_nil(previous) do
        Application.delete_env(:hiraeth, Hiraeth.Covers.Store)
      else
        Application.put_env(:hiraeth, Hiraeth.Covers.Store, previous)
      end
    end)

    :ok
  end

  test "serves a missing local file from the object store and fills the cache", %{conn: conn} do
    asset = cover_asset!()
    key = Covers.object_key(asset.cached_file_path)
    assert :ok = CoverStoreFake.put(key, @jpeg, "image/jpeg")
    on_exit(fn -> File.rm(asset.cached_file_path) end)

    conn = get(conn, "/" <> key)

    assert conn.status == 200
    assert conn.resp_body == @jpeg
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert File.read!(asset.cached_file_path) == @jpeg
  end

  test "returns 404 for a cover that is under takedown", %{conn: conn} do
    asset = cover_asset!(takedown_state: "hidden")
    key = Covers.object_key(asset.cached_file_path)
    assert :ok = CoverStoreFake.put(key, @jpeg, "image/jpeg")
    on_exit(fn -> File.rm(asset.cached_file_path) end)

    conn = get(conn, "/" <> key)

    assert conn.status == 404
    refute File.exists?(asset.cached_file_path)
  end

  test "returns 404 when the object is missing", %{conn: conn} do
    asset = cover_asset!()

    conn = get(conn, "/" <> Covers.object_key(asset.cached_file_path))

    assert conn.status == 404
    refute File.exists?(asset.cached_file_path)
  end

  test "rejects a traversal path before touching storage", %{conn: conn} do
    conn = HiraethWeb.CoverController.show(conn, %{"path" => "../secret.jpg"})

    assert conn.status == 404
  end

  test "rejects an object with an unsupported content type", %{conn: conn} do
    asset = cover_asset!()
    key = Covers.object_key(asset.cached_file_path)
    assert :ok = CoverStoreFake.put(key, "<html>not an image</html>", "text/html")

    conn = get(conn, "/" <> key)

    assert conn.status == 404
    refute File.exists?(asset.cached_file_path)
  end

  defp cover_asset!(attrs \\ []) do
    unique = System.unique_integer([:positive])

    defaults = %{
      source_url: "https://cdn.shopify.com/s/files/controller-#{unique}.jpg",
      provider: "deep_vellum_official_store",
      rights_basis: "local_cache_permitted",
      cache_policy: "cache_allowed",
      takedown_state: "visible",
      cached_file_path: "priv/static/covers/cache/controller-#{unique}.jpg"
    }

    CoverAsset
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, Map.new(attrs)))
    |> Ash.create!(actor: %{id: "cover-controller-test", catalog_write?: true})
  end
end
