defmodule Mix.Tasks.Hiraeth.PublicProjection.Rebuild do
  @shortdoc "Rebuilds the derived public catalog read model"
  @moduledoc """
  Rebuilds `catalog_public_works` from the canonical catalog.

      mix hiraeth.public_projection.rebuild --json
  """

  use Mix.Task

  alias Hiraeth.Catalog.PublicWorkProjection

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean, trigger: :string])
    trigger = Keyword.get(opts, :trigger, "mix")

    case PublicWorkProjection.rebuild!(trigger: trigger) do
      {:ok, summary} ->
        if opts[:json],
          do: IO.puts(Jason.encode!(summary)),
          else: Mix.shell().info(inspect(summary))

      {:error, :busy} ->
        Mix.raise("public projection rebuild skipped: another rebuild is running")

      {:error, reason} ->
        Mix.raise("public projection rebuild failed: #{inspect(reason)}")
    end
  end
end
