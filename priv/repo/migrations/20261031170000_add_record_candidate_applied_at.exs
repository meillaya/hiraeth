defmodule Hiraeth.Repo.Migrations.AddRecordCandidateAppliedAt do
  @moduledoc """
  Records when a candidate's record reached the catalog.

  The diff baseline only trusts applied candidates. Existing rows are left null,
  so the first run after this migration re-emits them instead of treating them
  as unchanged.
  """

  use Ecto.Migration

  def change do
    alter table(:record_candidates) do
      add :applied_at, :utc_datetime
    end
  end
end
