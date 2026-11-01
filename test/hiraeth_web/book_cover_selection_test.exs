defmodule HiraethWeb.BookCoverSelectionTest do
  @moduledoc """
  Pins the public book cover rule: the current printing's cover wins.

  A reissued title is one work with several editions. The book projection keeps
  the oldest paperback for stable title/author metadata, but the cover must come
  from the newest displayable edition so a reissue shows its new cover (or the
  publisher's "cover coming soon" image) instead of the retired one.
  """

  use Hiraeth.DataCase, async: false

  alias Hiraeth.Catalog.PublicWorkProjection
  alias Hiraeth.Covers
  alias Hiraeth.Covers.CoverAsset
  alias Hiraeth.RealCatalog.{Dataset, Importer}
  alias HiraethWeb.PublicCatalog

  setup do
    PublicCatalog.clear_cache()
    on_exit(fn -> PublicCatalog.clear_cache() end)
    :ok
  end

  test "book cover follows the newest edition when a title is reissued" do
    {:ok, dataset} = Dataset.load_file(Dataset.file_for_provider("dalkey_archive_official_store"))

    records = serpent_records(dataset)
    assert length(records) == 3

    unique = System.unique_integer([:positive])
    {records, cover_urls} = rewrite_covers(records, unique)

    cache_paths =
      Enum.flat_map(cover_urls, fn url ->
        probe = %CoverAsset{source_url: url}
        [Covers.cache_path(probe), Covers.thumbnail_path(probe)]
      end)

    Enum.each(cache_paths, fn path ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "cover selection test bytes")
    end)

    on_exit(fn -> Enum.each(cache_paths, &File.rm/1) end)

    tmp = Path.join(System.tmp_dir!(), "hiraeth-cover-selection-#{unique}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(
      Path.join(tmp, "dalkey_serpent_reissue.json"),
      Jason.encode!(dataset_payload(dataset, records), pretty: true)
    )

    assert {:ok, _summary} = Importer.seed!(tmp)
    assert {:ok, _summary} = PublicWorkProjection.rebuild!(trigger: "test")

    book = PublicCatalog.book("dalkey-archive-serpent")
    assert book.cover
    assert book.cover.source_url == newest_cover_url(unique)
    refute book.cover.source_url == retired_cover_url(unique)
  end

  defp serpent_records(dataset) do
    dataset.records
    |> Enum.filter(
      &(&1.source_uri in [
          "https://dalkeyarchive.store/products/serpent",
          "https://dalkeyarchive.store/products/serpent-1"
        ])
    )
    |> Enum.sort_by(& &1.source_uri)
  end

  defp rewrite_covers(records, unique) do
    records =
      Enum.map(records, fn record ->
        url =
          if String.ends_with?(record.source_uri, "/serpent-1"),
            do: newest_cover_url(unique),
            else: retired_cover_url(unique)

        %{record | cover: %{record.cover | source_url: url}}
      end)

    {records, Enum.uniq([newest_cover_url(unique), retired_cover_url(unique)])}
  end

  defp newest_cover_url(unique),
    do: "https://cdn.shopify.com/s/files/1/0594/2915/9067/files/cover-selection-new-#{unique}.jpg"

  defp retired_cover_url(unique),
    do:
      "https://cdn.shopify.com/s/files/1/0594/2915/9067/products/cover-selection-old-#{unique}.jpg"

  defp dataset_payload(dataset, records) do
    dataset
    |> Map.take([:provider, :retrieved_at, :license_note, :provider_permissions])
    |> Map.put(:records, records)
  end
end
