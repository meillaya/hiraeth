defmodule Hiraeth.Repo.Migrations.AddCoverResponsiveVariants do
  @moduledoc """
  Stores generated responsive cover variants for one cover asset.

  Each entry is `%{"path" => ..., "format" => "webp" | "jpg", "width" => 200,
  "sha256" => ..., "bytes" => ...}`. Paths are same-origin cache paths with a
  content hash in the filename, so a variant URL is immutable.
  """

  use Ecto.Migration

  def change do
    alter table(:cover_assets) do
      add :responsive_variants, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
