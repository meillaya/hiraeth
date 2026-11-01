defmodule Hiraeth.Catalog.PublicWorkProjectionTest do
  use HiraethWeb.ConnCase, async: false

  @moduletag :public_catalog_full

  alias Ecto.Adapters.SQL.Sandbox
  alias Hiraeth.Catalog.{PublicWorkProjection, PublicWorks}
  alias HiraethWeb.PublicCatalog

  setup_all do
    Hiraeth.CatalogCleanup.ensure_committed_catalog_fixtures!()

    {:ok, summary} =
      Sandbox.unboxed_run(Hiraeth.Repo, fn ->
        PublicWorkProjection.rebuild!(trigger: "test")
      end)

    {:ok, summary: summary}
  end

  test "rebuild leaves a ready revision and every public work", %{summary: summary} do
    assert summary.rows > 0

    assert %{status: "ready", revision: revision, row_count: row_count} =
             PublicWorkProjection.state()

    assert is_binary(revision)
    assert row_count == summary.rows
  end

  test "read model page matches the legacy book page" do
    legacy = PublicCatalog.book_page(nil, 1)
    read = PublicWorks.book_page(nil, 1)

    assert read.total_count == legacy.total_count
    assert Enum.map(read.entries, & &1.slug) == Enum.map(legacy.entries, & &1.slug)
  end

  test "filters and sorts match across both read paths" do
    for filters <- [
          %{q: "Immigrant"},
          %{publisher: "deep-vellum"},
          %{format: "paperback"},
          %{sort: "title"},
          %{sort: "author"},
          %{sort: "recently_added"},
          %{year: "2026"},
          %{q: "9781646054541"},
          %{q: "%"},
          %{role: "translator", contributor: "david-bowles"}
        ] do
      legacy = PublicCatalog.book_page(filters, 1)
      read = PublicWorks.book_page(filters, 1)

      assert read.total_count == legacy.total_count, inspect(filters)
      assert Enum.map(read.entries, & &1.slug) == Enum.map(legacy.entries, & &1.slug)
    end
  end

  test "book and edition slugs resolve from the read model" do
    assert %{title: "Immigrant"} = PublicWorks.get("deep-vellum-immigrant")

    assert %{title: "Immigrant"} =
             PublicWorks.get("deep-vellum-immigrant-paperback-9781646054541")

    assert PublicWorks.get("not-a-book") == nil
  end

  test "publisher and series projections are derived from the read model" do
    publisher = PublicCatalog.publisher("deep-vellum")
    assert publisher.editions_count == 274
    assert length(publisher.editions) == 274

    series = PublicCatalog.series_by_slug("dalkey-archive-essentials")
    assert series.editions_count == 42
    assert length(series.editions) == 42
  end
end
