defmodule Hiraeth.Ingestion.AppliedStateDiffTest do
  @moduledoc """
  The diff baseline is applied catalog state, not candidate history.

  A run that fails before apply leaves candidate rows behind. Those rows must not
  make the next run classify the same records as unchanged.
  """

  use Hiraeth.DataCase, async: true

  alias Hiraeth.Ingestion.{Phases, ProviderManifest, RecordCandidate}
  alias Hiraeth.TestSupport.IngestionFixtures

  @manifest_path Path.join([
                   File.cwd!(),
                   "test/support/fixtures/provider_manifests/valid_api_manifest.json"
                 ])

  @record %{
    "source_uri" => "https://www.testpublisher.com/books/applied-state",
    "source_product_id" => "applied-state",
    "work" => %{"title" => "Applied State Book"},
    "edition" => %{"title" => "Applied State Book", "isbn_13" => "9781646050001"}
  }

  setup do
    source = IngestionFixtures.create_provider_source!("applied-state")
    manifest = ProviderManifest.load!(@manifest_path)

    %{source: source, manifest: manifest}
  end

  test "a candidate from a run that never applied is not a baseline", %{
    source: source,
    manifest: manifest
  } do
    first = diff_run!(source, manifest, "first")
    assert [first_candidate] = first.record_candidates
    assert first_candidate.diff_classification == "new"
    assert is_nil(first_candidate.applied_at)

    second = diff_run!(source, manifest, "second")
    assert [second_candidate] = second.record_candidates
    assert second_candidate.diff_classification == "new"
    assert is_nil(second_candidate.previous_fingerprint)

    mark_applied!(first_candidate)

    third = diff_run!(source, manifest, "third")
    assert [third_candidate] = third.record_candidates
    assert third_candidate.diff_classification == "unchanged"
    assert third_candidate.previous_fingerprint == first_candidate.fingerprint
  end

  defp diff_run!(source, manifest, suffix) do
    run = IngestionFixtures.create_provider_run!(source, "applied-state-#{suffix}")
    snapshot = IngestionFixtures.create_source_snapshot!(source, run, "applied-state-#{suffix}")

    {:ok, context} =
      Phases.DiffCandidates.run(%{
        dataset: %{records: [@record]},
        manifest: manifest,
        provider_run_id: run.id,
        source_snapshot: snapshot
      })

    context
  end

  defp mark_applied!(%RecordCandidate{} = candidate) do
    candidate
    |> Ash.Changeset.for_update(:mark_applied, %{applied_at: DateTime.utc_now(:second)})
    |> Ash.update!(actor: IngestionFixtures.catalog_writer())
  end
end
