defmodule Hiraeth.Repo.Migrations.CreateCatalogPublicWorks do
  use Ecto.Migration

  def up do
    create table(:catalog_public_works, primary_key: false) do
      add :work_id, :uuid, primary_key: true
      add :payload, :binary, null: false
      add :slug, :text, null: false
      add :title, :text, null: false
      add :subtitle, :text
      add :title_sort, :text, null: false
      add :author_sort, :text
      add :publisher_name, :text
      add :publisher_slug, :text
      add :published_on, :date
      add :publication_year, :integer
      add :newest_sort, :date
      add :imported_sort, :utc_datetime_usec
      add :is_book, :boolean, null: false, default: true
      add :has_cover, :boolean, null: false, default: false
      add :format_values, {:array, :text}, null: false, default: []
      add :language_values, {:array, :text}, null: false, default: []
      add :role_values, {:array, :text}, null: false, default: []
      add :contributor_slugs, {:array, :text}, null: false, default: []
      add :contributor_names, {:array, :text}, null: false, default: []
      add :series_slugs, {:array, :text}, null: false, default: []
      add :series_titles, {:array, :text}, null: false, default: []
      add :subject_values, {:array, :text}, null: false, default: []
      add :edition_slugs, {:array, :text}, null: false, default: []
      add :search_text, :text, null: false, default: ""
      add :refreshed_at, :utc_datetime_usec, null: false
    end

    create index(:catalog_public_works, [:slug])
    create index(:catalog_public_works, [:publisher_slug])
    create index(:catalog_public_works, [:published_on])
    create index(:catalog_public_works, [:newest_sort])
    create index(:catalog_public_works, [:imported_sort])
    create index(:catalog_public_works, [:title_sort])
    create index(:catalog_public_works, [:author_sort])
    create index(:catalog_public_works, [:publication_year])

    for column <-
          ~w(format_values language_values role_values contributor_slugs series_slugs subject_values edition_slugs) do
      execute(
        "CREATE INDEX catalog_public_works_#{column}_gin ON catalog_public_works USING gin (#{column})"
      )
    end

    execute(
      "CREATE INDEX catalog_public_works_search_trgm ON catalog_public_works USING gin (search_text gin_trgm_ops)"
    )

    execute(
      "CREATE INDEX catalog_public_works_search_tsv ON catalog_public_works USING gin (to_tsvector('simple', search_text))"
    )

    create table(:catalog_public_projection_state, primary_key: false) do
      add :id, :smallint, primary_key: true, default: 1
      add :revision, :uuid
      add :status, :text, null: false, default: "idle"
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :row_count, :integer, null: false, default: 0
      add :error, :text
      add :trigger, :text
    end

    execute(
      "INSERT INTO catalog_public_projection_state (id, status) VALUES (1, 'idle') ON CONFLICT DO NOTHING"
    )
  end

  def down do
    drop table(:catalog_public_projection_state)
    drop table(:catalog_public_works)
  end
end
