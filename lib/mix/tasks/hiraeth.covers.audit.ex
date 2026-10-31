defmodule Mix.Tasks.Hiraeth.Covers.Audit do
  @moduledoc """
  Reports public cover cache coverage by provider.

  Usage:
      mix hiraeth.covers.audit [--provider <slug>] [--json] [--strict]

  With `--strict`, the task exits non-zero when an eligible cover is missing a
  cached original or thumbnail.
  """

  use Mix.Task

  alias Hiraeth.Covers

  @shortdoc "Reports public cover cache coverage"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case do_run(args) do
      :ok ->
        :ok

      {:error, message} ->
        Mix.shell().error(message)
        exit({:shutdown, 1})
    end
  end

  @doc false
  def do_run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [provider: :string, json: :boolean, strict: :boolean]
      )

    provider = Keyword.get(opts, :provider)
    audit = Covers.audit_cache(provider: provider)
    print(audit, opts)

    if Keyword.get(opts, :strict, false) and missing?(audit) do
      {:error, "cover audit found missing cached originals or thumbnails."}
    else
      :ok
    end
  end

  defp missing?(audit) do
    Enum.any?(audit, &(&1.missing_cache > 0 or &1.missing_thumbnails > 0))
  end

  defp print(audit, opts) do
    if Keyword.get(opts, :json, false) do
      Mix.shell().info(Jason.encode!(%{providers: audit}, pretty: true))
    else
      Enum.each(audit, fn row ->
        Mix.shell().info(
          "cover_audit provider=#{row.provider} assets=#{row.assets} eligible=#{row.eligible} " <>
            "cached=#{row.cached} thumbnails=#{row.thumbnails} " <>
            "missing_cache=#{row.missing_cache} missing_thumbnails=#{row.missing_thumbnails} " <>
            "non_public=#{row.non_public}"
        )
      end)
    end
  end
end
