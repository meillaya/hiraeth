defmodule Hiraeth.RealCatalog.RefreshTest do
  use ExUnit.Case, async: true

  alias Hiraeth.RealCatalog.Refresh

  test "add mode keeps existing records and adds only new titles" do
    current = dataset([record("9780306406157", "current-a", "title-a")])

    candidate =
      dataset([
        record("9780306406157", "candidate-a", "title-a"),
        record("9783161484100", "candidate-b", "title-b")
      ])

    assert {:ok, diff} = Refresh.merge(current, candidate, mode: :add)
    assert diff.new == 1
    assert diff.changed == 1
    assert diff.retained == 0
    assert diff.removed == 0

    assert Enum.map(diff.records, & &1.source_product_id) |> Enum.sort() == [
             "candidate-b",
             "current-a"
           ]
  end

  test "update mode replaces existing records and keeps out-of-source titles" do
    current =
      dataset([
        record("9780306406157", "current-a", "title-a"),
        record("9780131103627", "current-removed", "title-removed")
      ])

    candidate =
      dataset([
        record("9780306406157", "candidate-a", "title-a"),
        record("9783161484100", "candidate-b", "title-b")
      ])

    assert {:ok, diff} = Refresh.merge(current, candidate, mode: :update)
    assert diff.new == 1
    assert diff.changed == 1
    assert diff.retained == 1
    assert diff.removed == 1

    assert Enum.map(diff.records, & &1.source_product_id) |> Enum.sort() ==
             ["candidate-a", "candidate-b", "current-removed"]
  end

  test "prune mode requires explicit removal authorization" do
    current =
      dataset([
        record("9780306406157", "current-a", "title-a"),
        record("9780131103627", "current-removed", "title-removed")
      ])

    candidate = dataset([record("9780306406157", "candidate-a", "title-a")])

    assert {:error, message} = Refresh.merge(current, candidate, mode: :prune)
    assert message =~ "allow-removals"

    assert {:ok, diff} = Refresh.merge(current, candidate, mode: :prune, allow_removals: true)
    assert diff.removed == 1
    assert diff.retained == 0
    assert Enum.map(diff.records, & &1.source_product_id) == ["candidate-a"]
  end

  test "candidate without ISBN matches an existing record by source_product_id" do
    current = dataset([record("9780306406157", "shared-id", "title-a")])
    candidate = dataset([record(nil, "shared-id", "title-a")])

    assert {:ok, diff} = Refresh.merge(current, candidate, mode: :update)
    assert diff.new == 0
    assert diff.changed == 1
    assert diff.records |> hd() |> get_in([:edition, :isbn_13]) == nil
  end

  test "candidate without ISBN or matching source id falls back to source URI and format" do
    current = dataset([record("9780306406157", "old-id", "title-a")])
    candidate = dataset([record(nil, "new-id", "title-a")])
    # Same source URI and format, different source product id.
    [current_record] = current.records
    [candidate_record] = candidate.records

    current = %{current | records: [current_record]}
    candidate = %{candidate | records: [candidate_record]}

    assert {:ok, diff} = Refresh.merge(current, candidate, mode: :update)
    assert diff.new == 0
    assert diff.changed == 1
  end

  defp dataset(records), do: %{provider: "fixture", records: records}

  defp record(isbn, source_product_id, title) do
    %{
      source_uri: "https://example.test/books/#{title}",
      source_product_id: source_product_id,
      publisher: "Fixture Press",
      work: %{title: title},
      edition: %{title: title, format: "paperback", isbn_13: isbn},
      contributors: [%{name: "Author", role: "author"}],
      displayed_fields: ["title"],
      curation: %{status: "approved"},
      field_sources: %{}
    }
  end
end
