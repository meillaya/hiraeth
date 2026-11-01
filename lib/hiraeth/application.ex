defmodule Hiraeth.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  alias Hiraeth.Oban.{
    CoverBackfillWorker,
    CoverVariantBackfillWorker,
    PublicProjectionWorker
  }

  alias Hiraeth.ServiceRole

  @impl true
  def start(_type, _args) do
    children = children_for(ServiceRole.current())

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hiraeth.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        if ServiceRole.worker?(), do: enqueue_worker_boot_jobs()
        {:ok, pid}

      other ->
        other
    end
  end

  @doc false
  def children_for(role) do
    [
      HiraethWeb.Telemetry,
      Hiraeth.Repo,
      {DNSCluster, query: Application.get_env(:hiraeth, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hiraeth.PubSub},
      HiraethWeb.PageCache,
      Hiraeth.Covers.MissCache
    ] ++ worker_children(role) ++ web_children(role)
  end

  defp worker_children(role) when role in [:all, :worker] do
    [{Oban, Application.fetch_env!(:hiraeth, Oban)}]
  end

  defp worker_children(_role), do: []

  defp web_children(role) when role in [:all, :web] do
    [HiraethWeb.ProjectionWatcher, HiraethWeb.Endpoint]
  end

  defp web_children(_role), do: []

  defp enqueue_worker_boot_jobs do
    enqueue_cover_backfill()
    enqueue_cover_variant_backfill()

    if Application.get_env(:hiraeth, :public_projection_on_boot, true) do
      %{"trigger" => "boot"}
      |> PublicProjectionWorker.new()
      |> Oban.insert()
    end
  rescue
    exception ->
      Logger.warning("worker boot jobs skipped: #{Exception.message(exception)}")
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

  # Existing cache entries predate responsive delivery. This pass renders
  # variants from the local originals after the original backfill, so a deploy
  # does not need a publisher fetch to add srcset URLs.
  defp enqueue_cover_variant_backfill do
    if Application.get_env(:hiraeth, :cover_backfill_on_boot, false) do
      %{}
      |> CoverVariantBackfillWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, job} ->
          Logger.info("cover variant backfill enqueued job_id=#{job.id}")

        {:error, reason} ->
          Logger.warning("cover variant backfill could not be enqueued: #{inspect(reason)}")
      end
    end
  rescue
    exception ->
      Logger.warning("cover variant backfill enqueue skipped: #{Exception.message(exception)}")
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HiraethWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
