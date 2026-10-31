defmodule Hiraeth.Oban.CoverBackfillWorkerTest do
  @moduledoc """
  Tests for the boot-time cover backfill worker.

  Cache writes only ever go to a sandboxed, unique subdirectory under
  priv/static/covers/cache (the only tree the Hiraeth.Covers cache guard
  permits) and are removed on exit. The real cache root itself is never
  targeted by these tests.
  """

  use Hiraeth.DataCase, async: true

  alias Hiraeth.Covers
  alias Hiraeth.Covers.CoverAsset
  alias Hiraeth.Oban.CoverBackfillWorker

  @real_cache_root "priv/static/covers/cache"

  setup do
    %{admin: trusted_catalog_actor()}
  end

  test "worker is a covers-queue job with a short uniqueness window" do
    changeset = CoverBackfillWorker.new(%{})

    assert Ecto.Changeset.fetch_change!(changeset, :queue) == "covers"
    assert Ecto.Changeset.fetch_change!(changeset, :max_attempts) == 1

    unique = Ecto.Changeset.fetch_change!(changeset, :unique)
    assert unique.period == 600
  end

  test "perform adopts pre-staged cache files for an uncached asset", %{admin: admin} do
    cache_root = sandboxed_cache_root!("cover-backfill")
    asset = cacheable_asset!(admin, %{cached_file_path: nil})

    File.write!(Covers.cache_path(asset, cache_root), jpeg_bytes())
    File.write!(Covers.thumbnail_path(asset, cache_root), jpeg_bytes())

    assert {:ok, %{missing: 1, cached: 1, thumbnails: 1, failed: 0}} =
             CoverBackfillWorker.perform(%Oban.Job{
               args: %{"cache_root" => cache_root, "source_urls" => [asset.source_url]}
             })

    reloaded = Ash.get!(CoverAsset, asset.id, authorize?: false)
    assert reloaded.cached_file_path == Covers.cache_path(asset, cache_root)
    assert reloaded.thumbnail_file_path == Covers.thumbnail_path(asset, cache_root)
    assert File.read!(reloaded.cached_file_path) == jpeg_bytes()
  end

  test "perform is a no-op when nothing is missing" do
    assert {:ok, %{missing: 0, cached: 0, thumbnails: 0, failed: 0}} =
             CoverBackfillWorker.perform(%Oban.Job{args: %{"source_urls" => []}})
  end

  test "missing cache scope lists only cache-eligible assets without an original", %{
    admin: admin
  } do
    uncached = cacheable_asset!(admin, %{cached_file_path: nil})

    _cached =
      cacheable_asset!(admin, %{
        cached_file_path: Path.join(@real_cache_root, "already-cached.jpg")
      })

    hidden =
      cacheable_asset!(admin, %{cached_file_path: nil, takedown_state: "takedown"})

    urls = Covers.missing_cache_source_urls()

    assert uncached.source_url in urls
    refute hidden.source_url in urls
    assert length(urls) == 1
  end

  defp cacheable_asset!(admin, overrides) do
    attrs =
      Map.merge(
        %{
          source_url:
            "https://covers.example.test/cover-backfill-#{System.unique_integer([:positive])}.jpg",
          provider: "fixture-covers",
          rights_basis: "local_cache_permitted",
          cache_policy: "cache_allowed",
          attribution_text: "Fixture cover provider",
          takedown_state: "visible"
        },
        overrides
      )

    CoverAsset
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(actor: admin)
  end

  defp sandboxed_cache_root!(prefix) do
    cache_root = Path.join(@real_cache_root, "#{prefix}-#{System.unique_integer([:positive])}")

    unless String.starts_with?(Path.expand(cache_root), Path.expand(@real_cache_root) <> "/") do
      raise "test cache root must stay inside a sandboxed subdirectory of #{@real_cache_root}"
    end

    File.mkdir_p!(cache_root)
    on_exit(fn -> File.rm_rf!(cache_root) end)

    cache_root
  end

  defp jpeg_bytes do
    <<0xFF, 0xD8, 0xFF, 0xE0, "fixture-jpeg-raster-bytes", 0xFF, 0xD9>>
  end
end
