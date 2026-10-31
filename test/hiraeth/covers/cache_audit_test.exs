defmodule Hiraeth.Covers.CacheAuditTest do
  use Hiraeth.DataCase, async: true

  alias Hiraeth.Catalog.{Edition, Publisher, Work}
  alias Hiraeth.Covers
  alias Hiraeth.Covers.CoverAsset

  setup do
    admin = trusted_catalog_actor()
    publisher = publisher!(admin)

    work =
      Work
      |> Ash.Changeset.for_create(:create, %{
        title: "Audit Work #{System.unique_integer([:positive])}",
        slug: "audit-work-#{System.unique_integer([:positive])}"
      })
      |> Ash.create!(actor: admin)

    edition =
      Edition
      |> Ash.Changeset.for_create(:create, %{
        title: "Audit Edition",
        slug: "audit-edition-#{System.unique_integer([:positive])}",
        work_id: work.id,
        publisher_id: publisher.id
      })
      |> Ash.create!(actor: admin)

    cache_root =
      Path.join("priv/static/covers/cache", "audit-#{System.unique_integer([:positive])}")

    File.mkdir_p!(cache_root)
    on_exit(fn -> File.rm_rf!(cache_root) end)

    %{admin: admin, edition: edition, cache_root: cache_root}
  end

  test "audit counts cached originals, thumbnails, and missing files", %{
    admin: admin,
    cache_root: cache_root
  } do
    cached_path = Path.join(cache_root, "cached.jpg")
    thumbnail_path = Path.join(cache_root, "cached-thumb.jpg")
    missing_path = Path.join(cache_root, "missing.jpg")

    File.write!(cached_path, "cached")
    File.write!(thumbnail_path, "thumb")

    cached_asset =
      cover_asset!(admin, %{
        source_url: "https://covers.example.test/audit-cached.jpg",
        rights_basis: "local_cache_permitted",
        cache_policy: "cache_allowed",
        cached_file_path: cached_path,
        thumbnail_file_path: thumbnail_path
      })

    missing_thumb_asset =
      cover_asset!(admin, %{
        source_url: "https://covers.example.test/audit-missing-thumb.jpg",
        rights_basis: "local_cache_permitted",
        cache_policy: "cache_allowed",
        cached_file_path: cached_path,
        thumbnail_file_path: nil
      })

    missing_asset =
      cover_asset!(admin, %{
        source_url: "https://covers.example.test/audit-missing.jpg",
        rights_basis: "local_cache_permitted",
        cache_policy: "cache_allowed",
        cached_file_path: missing_path
      })

    link_only_asset =
      cover_asset!(admin, %{
        source_url: "https://covers.example.test/audit-link-only.jpg",
        rights_basis: "provider_link_allowed",
        cache_policy: "link_only"
      })

    assert Covers.cache_eligible?(cached_asset)
    assert Covers.cache_eligible?(missing_thumb_asset)
    assert Covers.cache_eligible?(missing_asset)
    refute Covers.cache_eligible?(link_only_asset)

    [audit] = Covers.audit_cache(provider: "fixture-covers")

    assert audit.provider == "fixture-covers"
    assert audit.assets == 4
    assert audit.eligible == 3
    assert audit.cached == 2
    assert audit.thumbnails == 1
    assert audit.missing_cache == 1
    assert audit.missing_thumbnails == 1
    assert audit.non_public == 1
  end

  test "provider-scoped sync only fetches the requested provider", %{
    admin: admin,
    cache_root: cache_root
  } do
    target =
      cover_asset!(admin, %{
        source_url: "https://covers.example.test/audit-target.jpg",
        rights_basis: "local_cache_permitted",
        cache_policy: "cache_allowed"
      })

    other =
      cover_asset!(admin, %{
        source_url: "https://cdn.shopify.com/audit-other.jpg",
        provider: "deep_vellum_official_store",
        rights_basis: "local_cache_permitted",
        cache_policy: "cache_allowed"
      })

    summary =
      Covers.cache_public_covers!(
        provider: "fixture-covers",
        cache_root: cache_root,
        fetch: fn
          "https://covers.example.test/audit-target.jpg" -> jpeg_bytes()
          url -> raise "unexpected fetch for #{url}"
        end,
        thumbnailer: fn source_path, thumbnail_path ->
          File.write!(thumbnail_path, "thumb for #{source_path}")
          {:ok, thumbnail_path}
        end
      )

    assert summary.cached == 1
    assert summary.failed == 0
    assert summary.thumbnails == 1
    assert File.regular?(Covers.cache_path(target, cache_root))
    refute File.exists?(Covers.cache_path(other, cache_root))
  end

  defp publisher!(admin) do
    Publisher
    |> Ash.Changeset.for_create(:create, %{
      name: "Audit Press #{System.unique_integer([:positive])}",
      slug: "audit-press-#{System.unique_integer([:positive])}"
    })
    |> Ash.create!(actor: admin)
  end

  defp cover_asset!(admin, attrs) do
    attrs =
      Map.merge(
        %{
          source_url: "https://covers.example.test/#{System.unique_integer([:positive])}.jpg",
          provider: "fixture-covers",
          rights_basis: "provider_link_allowed",
          cache_policy: "link_only",
          takedown_state: "visible"
        },
        attrs
      )

    CoverAsset
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(actor: admin)
  end

  defp jpeg_bytes, do: <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00, 0x00, 0x00>>
end
