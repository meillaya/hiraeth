defmodule Hiraeth.RealCatalog.SourceAuthorityTest do
  use ExUnit.Case, async: true

  alias Hiraeth.RealCatalog.{Dataset, RefreshProfiles, SourceAuthority}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "hiraeth-source-authority-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "build derives counts and generated_at from the dataset, not the policy file", %{dir: dir} do
    write_authority!(dir, provider_entry("provider_b", 1))
    write_dataset!(dir, "not-the-provider-name.json", "provider_b", [record("9780000000001")])

    assert {:ok, built} = SourceAuthority.build(dir)
    [provider] = built["providers"]

    assert provider["dataset_file"] == "not-the-provider-name.json"
    assert provider["approved_source_records"] == 1
    assert get_in(provider, ["coverage", "expected_record_count"]) == 1
    assert get_in(provider, ["coverage", "generated_at"]) == "2026-01-01T00:00:00Z"
  end

  test "write then check is in sync, and a dataset addition is detected", %{dir: dir} do
    write_authority!(dir, provider_entry("provider_b", 1))
    write_dataset!(dir, "provider-b.json", "provider_b", [record("9780000000001")])

    assert {:ok, _manifest} = SourceAuthority.write!(dir)
    assert {:ok, :in_sync} = SourceAuthority.check(dir)

    write_dataset!(dir, "provider-b.json", "provider_b", [
      record("9780000000001"),
      record("9780000000002")
    ])

    assert {:error, %{authority: ["provider_b"]}} = SourceAuthority.check(dir)
    assert {:ok, _manifest} = SourceAuthority.write!(dir)
    assert {:ok, :in_sync} = SourceAuthority.check(dir)
  end

  test "write refuses a record-count decrease unless allow_removals is true", %{dir: dir} do
    write_authority!(dir, provider_entry("provider_b", 2))

    write_dataset!(dir, "provider-b.json", "provider_b", [
      record("9780000000001"),
      record("9780000000002")
    ])

    assert {:ok, _manifest} = SourceAuthority.write!(dir)

    write_dataset!(dir, "provider-b.json", "provider_b", [record("9780000000001")])

    assert {:error, {:record_count_decrease_blocked, [{"provider_b", 2, 1}]}} =
             SourceAuthority.write!(dir)

    assert {:ok, _manifest} = SourceAuthority.write!(dir, allow_removals: true)
    assert {:ok, :in_sync} = SourceAuthority.check(dir)
  end

  test "build reports providers with no policy or no dataset", %{dir: dir} do
    write_authority!(dir, provider_entry("provider_b", 1))
    write_dataset!(dir, "provider-c.json", "provider_c", [record("9780000000001")])

    assert {:error, {:missing_policy, ["provider_c"]}} = SourceAuthority.build(dir)

    File.rm!(Path.join(dir, "provider-c.json"))
    write_authority!(dir, provider_entry("provider_b", 1))
    assert {:error, {:missing_dataset, ["provider_b"]}} = SourceAuthority.build(dir)
  end

  test "refresh profiles cover every authority provider and reference existing files" do
    assert :ok = RefreshProfiles.validate!()
  end

  test "Dataset.file_for_provider resolves by declared provider and rejects duplicates", %{
    dir: dir
  } do
    write_dataset!(dir, "one.json", "provider_b", [record("9780000000001")])

    assert Dataset.file_for_provider("provider_b", dir) == Path.join(dir, "one.json")

    write_dataset!(dir, "two.json", "provider_b", [record("9780000000002")])
    assert Dataset.file_for_provider("provider_b", dir) == nil
    assert {:ok, %{"provider_b" => files}} = Dataset.provider_index(dir)
    assert length(files) == 2
  end

  defp write_authority!(dir, entry) do
    manifest = %{
      "version" => 1,
      "completeness_boundary" => "approved_source_corpus",
      "providers" => [entry]
    }

    File.write!(
      Path.join(dir, "source_authority_manifest.json"),
      Jason.encode!(manifest, pretty: true)
    )
  end

  defp provider_entry(provider, expected_count) do
    %{
      "provider" => provider,
      "dataset_file" => "wrong.json",
      "publisher_name" => "Test Publisher",
      "status" => "approved",
      "allowed_source_hosts" => ["example.test"],
      "allowed_cover_hosts" => ["covers.example.test"],
      "coverage" => %{
        "expected_record_count" => expected_count,
        "coverage_state" => "test",
        "gap_policy" => "import_with_gaps",
        "generated_at" => "2025-01-01T00:00:00Z"
      },
      "approved_source_records" => expected_count
    }
  end

  defp write_dataset!(dir, filename, provider, records) do
    dataset = %{
      "provider" => provider,
      "retrieved_at" => "2026-01-01T00:00:00Z",
      "license_note" => "test license",
      "provider_permissions" => %{},
      "records" => records
    }

    File.write!(Path.join(dir, filename), Jason.encode!(dataset, pretty: true))
  end

  defp record(isbn) do
    %{
      "source_uri" => "https://example.test/#{isbn}",
      "source_product_id" => isbn,
      "publisher" => "Test Publisher",
      "work" => %{"title" => "Book #{isbn}"},
      "edition" => %{"title" => "Book #{isbn}", "format" => "paperback", "isbn_13" => isbn},
      "contributors" => [%{"name" => "Author", "role" => "author"}],
      "displayed_fields" => ["title"],
      "curation" => %{"status" => "approved"},
      "field_sources" => %{
        "title" => %{
          "provider" => "provider_b",
          "source_uri" => "https://example.test/#{isbn}",
          "source_type" => "publisher_dataset",
          "rights_basis" => "test"
        }
      },
      "cover" => %{
        "source_url" => "https://covers.example.test/#{isbn}.jpg",
        "provider" => "provider_b",
        "rights_basis" => "local_cache_permitted",
        "cache_policy" => "cache_allowed"
      },
      "missing_fields" => %{}
    }
  end
end
