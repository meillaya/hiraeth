defmodule Hiraeth.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  alias Hiraeth.Oban.CoverBackfillWorker

  @impl true
  def start(_type, _args) do
    children = [
      HiraethWeb.Telemetry,
      Hiraeth.Repo,
      {DNSCluster, query: Application.get_env(:hiraeth, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hiraeth.PubSub},
      {Oban, Application.fetch_env!(:hiraeth, Oban)},
      # Start a worker by calling: Hiraeth.Worker.start_link(arg)
      # {Hiraeth.Worker, arg},
      # Start to serve requests, typically the last entry
      HiraethWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hiraeth.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        enqueue_cover_backfill()
        {:ok, pid}

      other ->
        other
    end
  end

  # A fresh deploy has an empty local cover cache and an import can add cover
  # assets between weekly refreshes. Enqueueing one scoped backfill at boot
  # keeps new covers from staying invisible; the worker is a no-op when nothing
  # is missing, and its uniqueness window collapses restarts.
  defp enqueue_cover_backfill do
    if Application.get_env(:hiraeth, :cover_backfill_on_boot, false) do
      %{}
      |> CoverBackfillWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, job} ->
          Logger.info("cover backfill enqueued job_id=#{job.id}")

        {:error, reason} ->
          Logger.warning("cover backfill could not be enqueued: #{inspect(reason)}")
      end
    end
  rescue
    exception ->
      Logger.warning("cover backfill enqueue skipped: #{Exception.message(exception)}")
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HiraethWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
