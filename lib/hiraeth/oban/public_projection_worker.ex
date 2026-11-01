defmodule Hiraeth.Oban.PublicProjectionWorker do
  @moduledoc "Rebuilds the derived public read model after catalog or cover changes."

  use Oban.Worker,
    queue: :projection,
    unique: [period: 300],
    max_attempts: 3

  alias Hiraeth.Catalog.PublicWorkProjection

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case PublicWorkProjection.rebuild!(trigger: Map.get(args, "trigger", "oban")) do
      {:ok, summary} -> {:ok, summary}
      {:error, :busy} -> {:ok, %{skipped: :busy}}
      {:error, reason} -> {:error, reason}
    end
  end
end
