defmodule HiraethWeb.ProjectionWatcher do
  @moduledoc """
  Clears the page cache when the worker swaps the public read model.

  Web and worker are separate services, so a local PubSub broadcast cannot see
  the worker's commit. A two-second singleton poll is cheap and also covers
  multiple web replicas; the page TTL is the fallback.
  """

  use GenServer

  alias Hiraeth.Catalog.PublicWorkProjection
  alias HiraethWeb.PageCache

  @interval :timer.seconds(2)

  def start_link(_arg), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    schedule()
    {:ok, %{revision: current_revision()}}
  end

  @impl true
  def handle_info(:poll, state) do
    revision = current_revision()

    state =
      if revision != state.revision do
        PageCache.clear()
        %{state | revision: revision}
      else
        state
      end

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :poll, @interval)

  defp current_revision do
    case PublicWorkProjection.state() do
      %{revision: revision} -> revision
      _ -> nil
    end
  rescue
    _exception -> nil
  end
end
