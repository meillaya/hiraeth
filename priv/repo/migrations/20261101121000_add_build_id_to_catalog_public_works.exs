defmodule Hiraeth.Repo.Migrations.AddBuildIdToCatalogPublicWorks do
  use Ecto.Migration

  def up do
    alter table(:catalog_public_works) do
      add :build_id, :uuid
    end
  end

  def down do
    alter table(:catalog_public_works) do
      remove :build_id
    end
  end
end
