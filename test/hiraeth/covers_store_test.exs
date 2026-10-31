defmodule Hiraeth.CoversStoreTest do
  @moduledoc "Cached covers upload to and delete from the configured object store."

  use Hiraeth.DataCase, async: false

  alias Hiraeth.Covers
  alias Hiraeth.Covers.CoverAsset
  alias Hiraeth.TestSupport.CoverStoreFake

  @original <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00, 0x00, 0x00>>
  @thumbnail "thumbnail bytes"

  setup do
    previous = Application.get_env(:hiraeth, Hiraeth.Covers.Store)
    Application.put_env(:hiraeth, Hiraeth.Covers.Store, adapter: CoverStoreFake)
    CoverStoreFake.reset()

    unique = System.unique_integer([:positive])
    root = Path.join("priv/static/covers/cache", "store-test-#{unique}")
    File.mkdir_p!(root)

    original_path = Path.join(root, "cover.jpg")
    thumbnail_path = Path.join(root, "cover-thumb.jpg")
    File.write!(original_path, @original)
    File.write!(thumbnail_path, @thumbnail)

    asset = cover_asset!(original_path, thumbnail_path)

    on_exit(fn ->
      File.rm_rf!(root)

      if is_nil(previous) do
        Application.delete_env(:hiraeth, Hiraeth.Covers.Store)
      else
        Application.put_env(:hiraeth, Hiraeth.Covers.Store, previous)
      end
    end)

    %{asset: asset, original_path: original_path, thumbnail_path: thumbnail_path}
  end

  test "uploads cached originals and thumbnails", %{
    asset: asset,
    original_path: original_path,
    thumbnail_path: thumbnail_path
  } do
    assert %{uploaded: 2, failed: 0} =
             Covers.upload_cached_covers!(source_urls: [asset.source_url])

    assert {:ok, @original, "image/jpeg"} =
             CoverStoreFake.get(Covers.object_key(original_path))

    assert {:ok, @thumbnail, "image/jpeg"} =
             CoverStoreFake.get(Covers.object_key(thumbnail_path))
  end

  test "cache writes upload originals and thumbnails" do
    unique = System.unique_integer([:positive])
    root = Path.join("priv/static/covers/cache", "store-cache-#{unique}")
    source_url = "https://cdn.shopify.com/s/files/store-cache-#{unique}.jpg"
    asset = cover_asset_without_paths!(source_url)
    on_exit(fn -> File.rm_rf!(root) end)

    summary =
      Covers.cache_public_covers!(
        cache_root: root,
        source_urls: [source_url],
        fetch: fn ^source_url -> @original end,
        thumbnailer: fn _source_path, thumbnail_path ->
          File.write!(thumbnail_path, @thumbnail)
          {:ok, thumbnail_path}
        end
      )

    assert summary.cached == 1
    assert [cached] = summary.assets

    assert {:ok, @original, "image/jpeg"} =
             CoverStoreFake.get(Covers.object_key(cached.cached_file_path))

    assert {:ok, @thumbnail, "image/jpeg"} =
             CoverStoreFake.get(Covers.object_key(cached.thumbnail_file_path))

    assert is_binary(asset.id)
  end

  test "purge removes local files and stored objects", %{
    asset: asset,
    original_path: original_path,
    thumbnail_path: thumbnail_path
  } do
    assert %{uploaded: 2, failed: 0} =
             Covers.upload_cached_covers!(source_urls: [asset.source_url])

    purged = Covers.purge_cached_cover!(asset)

    refute File.exists?(original_path)
    refute File.exists?(thumbnail_path)
    assert CoverStoreFake.get(Covers.object_key(original_path)) == :missing
    assert CoverStoreFake.get(Covers.object_key(thumbnail_path)) == :missing
    assert purged.cached_file_path == nil
    assert purged.thumbnail_file_path == nil
  end

  defp cover_asset_without_paths!(source_url) do
    unique = System.unique_integer([:positive])

    CoverAsset
    |> Ash.Changeset.for_create(:create, %{
      source_url:
        "https://cdn.shopify.com/s/files/store-cache-#{unique}.jpg"
        |> then(fn _ -> source_url end),
      provider: "deep_vellum_official_store",
      rights_basis: "local_cache_permitted",
      cache_policy: "cache_allowed",
      takedown_state: "visible"
    })
    |> Ash.create!(actor: %{id: "cover-store-test", catalog_write?: true})
  end

  defp cover_asset!(original_path, thumbnail_path) do
    unique = System.unique_integer([:positive])

    CoverAsset
    |> Ash.Changeset.for_create(:create, %{
      source_url: "https://cdn.shopify.com/s/files/store-test-#{unique}.jpg",
      provider: "deep_vellum_official_store",
      rights_basis: "local_cache_permitted",
      cache_policy: "cache_allowed",
      takedown_state: "visible",
      cached_file_path: original_path,
      thumbnail_file_path: thumbnail_path
    })
    |> Ash.create!(actor: %{id: "cover-store-test", catalog_write?: true})
  end
end
