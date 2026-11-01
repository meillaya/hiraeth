defmodule Hiraeth.Covers.ResponsiveVariantsTest do
  @moduledoc "Responsive variants are content-hashed, multi-format, and sandboxed."

  use Hiraeth.DataCase, async: false

  alias Hiraeth.Catalog.{Edition, Publisher, Work}
  alias Hiraeth.Covers
  alias Hiraeth.Covers.{CoverAsset, CoverAssignment}

  setup do
    unique = System.unique_integer([:positive])
    cache_root = Path.join("priv/static/covers/cache", "variant-test-#{unique}")
    source_path = Path.join(cache_root, "original.jpg")

    File.mkdir_p!(cache_root)
    File.write!(source_path, "source image")

    original_path = System.get_env("PATH")
    bin_dir = Path.join(System.tmp_dir!(), "hiraeth-variant-bin-#{unique}")
    File.mkdir_p!(bin_dir)
    fake_convert!(bin_dir)

    System.put_env("PATH", bin_dir <> ":" <> original_path)
    on_exit(fn -> restore_path(original_path) end)
    on_exit(fn -> File.rm_rf!(cache_root) end)
    on_exit(fn -> File.rm_rf!(bin_dir) end)

    asset = cover_asset!(unique)
    %{asset: asset, cache_root: cache_root, source_path: source_path}
  end

  test "generates six WebP/JPEG variants with content-hashed filenames", %{
    asset: asset,
    cache_root: cache_root,
    source_path: source_path
  } do
    variants = Covers.generate_variants(source_path, asset, cache_root)

    assert length(variants) == 6
    assert Enum.map(variants, & &1["width"]) |> Enum.uniq() |> Enum.sort() == [200, 400, 800]
    assert Enum.map(variants, & &1["format"]) |> Enum.uniq() |> Enum.sort() == ["jpg", "webp"]

    for variant <- variants do
      assert File.regular?(variant["path"])

      assert variant["path"] =~ ~r/-\d+w-[0-9a-f]{64}\.(jpg|webp)$/
      assert Covers.responsive_variant_path?(variant["path"])

      body = File.read!(variant["path"])
      assert variant["sha256"] == sha256(body)
      assert variant["bytes"] == byte_size(body)
    end

    refute Covers.responsive_variant_path?(
             Path.join(cache_root, "#{sha256(asset.source_url)}-thumb.jpg")
           )
  end

  test "a cache write stores the variant set on the asset", %{
    asset: asset,
    cache_root: cache_root,
    source_path: source_path
  } do
    thumbnail_path = Covers.thumbnail_path(asset, cache_root)
    File.write!(thumbnail_path, "thumbnail")

    asset =
      update_asset!(asset, %{cached_file_path: source_path, thumbnail_file_path: thumbnail_path})

    variant_generator = fn source_path, asset, root ->
      Covers.generate_variants(source_path, asset, root)
    end

    summary =
      Covers.cache_public_covers!(
        cache_root: cache_root,
        variants_only?: true,
        source_urls: [asset.source_url],
        variant_generator: variant_generator
      )

    assert summary.variants == 1
    reloaded = Ash.get!(CoverAsset, asset.id, authorize?: false)
    assert length(reloaded.responsive_variants) == 6

    for variant <- reloaded.responsive_variants do
      assert Covers.responsive_variant_path?(variant["path"])
      assert File.regular?(variant["path"])
    end
  end

  test "variant backfill includes assets whose original is not local yet", %{
    asset: asset,
    cache_root: cache_root,
    source_path: source_path
  } do
    refute asset.source_url in Covers.missing_variant_source_urls()

    asset = assign_public_cover!(asset)

    thumbnail_path = Covers.thumbnail_path(asset, cache_root)
    File.write!(thumbnail_path, "thumbnail")

    asset =
      update_asset!(asset, %{cached_file_path: source_path, thumbnail_file_path: thumbnail_path})

    assert asset.source_url in Covers.missing_variant_source_urls()

    variants = Covers.generate_variants(source_path, asset, cache_root)
    asset = update_asset!(asset, %{responsive_variants: variants})

    refute asset.source_url in Covers.missing_variant_source_urls()

    File.rm!(hd(variants)["path"])
    assert asset.source_url in Covers.missing_variant_source_urls()
  end

  defp assign_public_cover!(asset) do
    suffix = System.unique_integer([:positive])
    actor = %{id: "variant-test", catalog_write?: true}

    publisher =
      Publisher
      |> Ash.Changeset.for_create(:create, %{
        name: "Variant Test Press #{suffix}",
        slug: "variant-test-press-#{suffix}"
      })
      |> Ash.create!(actor: actor)

    work =
      Work
      |> Ash.Changeset.for_create(:create, %{
        title: "Variant Test Novel #{suffix}",
        slug: "variant-test-novel-#{suffix}",
        publication_state: "published"
      })
      |> Ash.create!(actor: actor)

    edition =
      Edition
      |> Ash.Changeset.for_create(:create, %{
        title: "Variant Test Novel #{suffix}",
        slug: "variant-test-novel-#{suffix}-paperback",
        format: "paperback",
        work_id: work.id,
        publisher_id: publisher.id
      })
      |> Ash.create!(actor: actor)

    CoverAssignment
    |> Ash.Changeset.for_create(:create, %{
      edition_id: edition.id,
      cover_asset_id: asset.id,
      visible?: true,
      position: 1
    })
    |> Ash.create!(actor: actor)

    asset
  end

  defp update_asset!(asset, attrs) do
    asset
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update!(actor: %{id: "variant-test", catalog_write?: true})
  end

  defp cover_asset!(unique) do
    CoverAsset
    |> Ash.Changeset.for_create(:create, %{
      source_url: "https://cdn.shopify.com/s/files/variant-test-#{unique}.jpg",
      provider: "deep_vellum_official_store",
      rights_basis: "local_cache_permitted",
      cache_policy: "cache_allowed",
      takedown_state: "visible"
    })
    |> Ash.create!(actor: %{id: "variant-test", catalog_write?: true})
  end

  defp fake_convert!(dir) do
    path = Path.join(dir, "convert")

    File.write!(path, """
    #!/bin/sh
    last=""
    for arg in "$@"; do last="$arg"; done
    printf 'responsive variant %s' "$last" > "$last"
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp sha256(value) do
    value |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp restore_path(nil), do: System.delete_env("PATH")
  defp restore_path(path), do: System.put_env("PATH", path)
end
