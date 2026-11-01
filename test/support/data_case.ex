defmodule Hiraeth.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Hiraeth.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Hiraeth.Catalog.PublicWorkProjection
  alias Hiraeth.CatalogCleanup
  alias Hiraeth.Repo
  alias HiraethWeb.PublicCatalog

  using do
    quote do
      alias Hiraeth.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Hiraeth.DataCase
    end
  end

  setup tags do
    # Sandbox owner must start BEFORE tag resets: resets then run inside the
    # test's own transaction (sandbox-scoped), which keeps the committed
    # corpus intact and never issues ACCESS EXCLUSIVE TRUNCATEs.
    Hiraeth.DataCase.setup_sandbox(tags)

    if tags[:reset_committed_catalog] do
      CatalogCleanup.reset_committed_catalog_in_sandbox!()
    end

    if tags[:reset_committed_ingestion] do
      CatalogCleanup.reset_committed_ingestion_control_plane_in_sandbox!()
    end

    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = SomeResource.create(%{field: nil})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Returns an in-memory catalog writer actor for Ash policy tests.

  The public application has no accounts or admin area; write-side tests still
  need an actor-like map so resource policies can distinguish trusted catalog
  ingestion from anonymous public reads.
  """
  def trusted_catalog_actor(attrs \\ %{}) do
    Map.merge(%{id: Ash.UUID.generate(), catalog_write?: true}, attrs)
  end

  @doc """
  Rebuilds the public read model after a test creates catalog rows directly.

  Public reads no longer have a canonical-query fallback, so a test that writes
  through Ash and then reads `HiraethWeb.PublicCatalog` must refresh the derived
  table the same way an import would.
  """
  def rebuild_public_projection! do
    {:ok, _summary} =
      PublicWorkProjection.rebuild!(trigger: "test")

    PublicCatalog.clear_cache()
    :ok
  end
end
