defmodule Hiraeth.Repo.Migrations.RelaxCatalogPublicWorksSlug do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:catalog_public_works, [:slug],
                     name: "catalog_public_works_slug_index"
                   )

    create_if_not_exists index(:catalog_public_works, [:slug])
  end

  def down do
    drop_if_exists index(:catalog_public_works, [:slug])
    create unique_index(:catalog_public_works, [:slug])
  end
end
