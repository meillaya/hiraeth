defmodule Mix.Tasks.Hiraeth.Covers.Upload do
  @moduledoc """
  Uploads every locally cached public cover to the configured object store.

  Use this after pointing `HIRAETH_COVER_STORE=s3` at an existing disk cache,
  or to rebuild a bucket whose objects were lost.
  """

  use Mix.Task

  alias Hiraeth.Covers
  alias Hiraeth.Covers.Store

  @shortdoc "Uploads cached covers to object storage"
  @impl Mix.Task

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [json: :boolean])

    if Store.configured?() do
      summary = Covers.upload_cached_covers!()

      if Keyword.get(opts, :json, false) do
        Mix.shell().info(Jason.encode!(summary))
      else
        Mix.shell().info("cover_upload_uploaded=#{summary.uploaded}")
        Mix.shell().info("cover_upload_failed=#{summary.failed}")
      end
    else
      Mix.shell().error(
        "cover object store is not configured; set HIRAETH_COVER_STORE=s3 and the R2_* variables"
      )

      exit({:shutdown, 1})
    end
  end
end
