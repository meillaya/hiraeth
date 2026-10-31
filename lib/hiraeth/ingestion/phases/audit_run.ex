defmodule Hiraeth.Ingestion.Phases.AuditRun do
  @moduledoc """
  Runs provenance audit as an explicit ingestion phase.

  Audit evidence is a report, not a gate. A failed audit after a committed apply
  records the failure and leaves `provenance_audit` nil, but it does not fail the
  run and trigger a full re-ingest.
  """

  alias Hiraeth.Ingestion.Phases.RunState
  alias Hiraeth.ProvenanceAudit

  def run(%{provider_run_id: run_id, manifest: manifest} = context) do
    audit = ProvenanceAudit.run!(providers: [manifest.provider], fail_on_error?: false)

    RunState.mark_phase(run_id, :audit_run, :succeeded, %{
      source_count: audit.source_records,
      message: "Provenance audit completed for #{manifest.provider}."
    })

    {:ok, Map.put(context, :provenance_audit, audit)}
  rescue
    error ->
      RunState.mark_phase(context.provider_run_id, :audit_run, :failed, %{
        error_count: 1,
        error: %{code: :audit_failed, message: Exception.message(error)}
      })

      {:ok,
       context
       |> Map.put(:provenance_audit, nil)
       |> Map.put(:audit_error, Exception.message(error))}
  end
end
