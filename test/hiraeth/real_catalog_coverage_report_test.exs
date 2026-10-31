defmodule Hiraeth.RealCatalogCoverageReportTest do
  use ExUnit.Case, async: true

  @moduletag :full_catalog
  @moduletag :slow

  alias Hiraeth.RealCatalog.CoverageReport

  @dataset_dir Path.expand("../../priv/catalog_sources/real_publishers", __DIR__)
  @coverage_report Path.join(@dataset_dir, "source_coverage_report.json")

  test "checked-in coverage report matches approved source corpus" do
    assert {:ok, built} = CoverageReport.build(@dataset_dir)

    checked_in =
      @coverage_report
      |> File.read!()
      |> Jason.decode!()

    authority =
      @dataset_dir
      |> Path.join("source_authority_manifest.json")
      |> File.read!()
      |> Jason.decode!()

    expected_total =
      authority["providers"]
      |> Enum.map(&get_in(&1, ["coverage", "expected_record_count"]))
      |> Enum.sum()

    assert checked_in == built
    assert built["completeness_boundary"] == "approved_source_corpus"

    assert built["totals"] == %{
             "providers" => length(authority["providers"]),
             "attempted_records" => expected_total,
             "approved_source_records" => expected_total,
             "skipped_source_records" => 0
           }

    for provider <- built["providers"] do
      assert provider["attempted_records"] == provider["expected_record_count"]
      assert provider["approved_source_records"] == provider["attempted_records"]
      assert provider["skipped_source_records"] == 0
      assert provider["gap_policy"] == "import_with_gaps"
      assert is_binary(provider["checksums"]["dataset_sha256"])
      assert byte_size(provider["checksums"]["dataset_sha256"]) == 64
    end
  end

  test "coverage report preserves authorized full-catalog gaps without fabricating records" do
    assert {:ok, report} = CoverageReport.build(@dataset_dir)

    new_directions = provider!(report, "new_directions_official_site")
    refute new_directions["source_blocked"]
    refute new_directions["source_expansion_blocked"]
    assert new_directions["source_status"] == "approved_official_html_source_available"
    assert new_directions["gap_counts"]["missing_cover"] == 0

    assert new_directions["approved_source_records"] ==
             new_directions["expected_record_count"]

    assert new_directions["approved_source_records"] > 0

    transit = provider!(report, "transit_books_official_site")
    refute transit["source_blocked"]
    assert transit["gap_counts"]["missing_cover"] == 0
    assert transit["gap_counts"]["missing_review_links"] >= 0

    historical_materialism = provider!(report, "historical_materialism_official_site")

    assert historical_materialism["approved_source_records"] ==
             historical_materialism["expected_record_count"]

    assert historical_materialism["gap_counts"]["missing_isbn"] >= 0

    semiotexte = provider!(report, "semiotexte_official_site")
    assert semiotexte["approved_source_records"] == semiotexte["expected_record_count"]
    assert semiotexte["gap_counts"]["missing_cover"] == 0

    deep_vellum = provider!(report, "deep_vellum_official_store")
    dalkey_archive = provider!(report, "dalkey_archive_official_store")

    assert is_integer(deep_vellum["gap_counts"]["missing_cover"])
    assert is_integer(dalkey_archive["gap_counts"]["missing_cover"])
    assert is_integer(deep_vellum["gap_counts"]["missing_isbn"])

    nyrb = provider!(report, "nyrb_official_store")
    assert nyrb["approved_source_records"] == nyrb["expected_record_count"]

    seven_stories = provider!(report, "seven_stories_press_official_site")
    assert seven_stories["approved_source_records"] == seven_stories["expected_record_count"]
    assert seven_stories["gap_counts"]["missing_isbn"] >= 0

    pushkin = provider!(report, "pushkin_press_official_site")
    assert pushkin["approved_source_records"] == pushkin["expected_record_count"]

    fitzcarraldo = provider!(report, "fitzcarraldo_editions_official_site")
    assert fitzcarraldo["approved_source_records"] == fitzcarraldo["expected_record_count"]
    assert fitzcarraldo["gap_counts"]["missing_cover"] == 0

    and_other_stories = provider!(report, "and_other_stories_official_store")

    assert and_other_stories["approved_source_records"] ==
             and_other_stories["expected_record_count"]

    astra_house = provider!(report, "astra_house_official_store")
    assert astra_house["approved_source_records"] == astra_house["expected_record_count"]

    coffee_house_press = provider!(report, "coffee_house_press_official_store")

    assert coffee_house_press["approved_source_records"] ==
             coffee_house_press["expected_record_count"]

    seagull_books = provider!(report, "seagull_books_official_store")
    assert seagull_books["approved_source_records"] == seagull_books["expected_record_count"]

    wakefield_press = provider!(report, "wakefield_press_official_store")
    assert wakefield_press["approved_source_records"] == wakefield_press["expected_record_count"]
  end

  test "repeat coverage report writes are stable" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "hiraeth-coverage-report-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    first = Path.join(tmp, "first.json")
    second = Path.join(tmp, "second.json")

    CoverageReport.write!(@dataset_dir, first)
    CoverageReport.write!(@dataset_dir, second)

    assert File.read!(first) == File.read!(second)
  end

  defp provider!(report, provider) do
    Enum.find(report["providers"], &(&1["provider"] == provider)) ||
      flunk("missing provider #{provider}")
  end
end
