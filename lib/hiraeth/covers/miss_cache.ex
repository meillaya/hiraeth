defmodule Hiraeth.Covers.MissCache do
  @moduledoc """
  Short-lived memory of cover objects the durable store reported missing.

  A cold replica asks the object store for a cover it does not have on disk.
  When the object is absent the round trip costs about a second, and the same
  request repeats on every page view that references the cover. Remembering the
  miss keeps the proxy path fast.

  An entry expires on its own and a successful `Hiraeth.Covers.Store.put/3`
  clears it, so a later upload is visible without a restart.
  """

  use GenServer

  @table :hiraeth_cover_miss_cache
  @ttl_ms :timer.seconds(60)
  @max_entries 5_000

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_arg), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Returns true when the store recently reported this key as missing.
  """
  @spec known_missing?(String.t()) :: boolean()
  def known_missing?(key) when is_binary(key) do
    case :ets.lookup(@table, key) do
      [{^key, expires_at}] ->
        if expires_at > now_ms() do
          true
        else
          :ets.delete(@table, key)
          false
        end

      [] ->
        false
    end
  rescue
    ArgumentError -> false
  end

  def known_missing?(_key), do: false

  @doc """
  Remembers that the store has no object under this key.
  """
  @spec remember_missing(String.t()) :: :ok
  def remember_missing(key) when is_binary(key) do
    :ets.insert(@table, {key, now_ms() + @ttl_ms})
    trim()
    :ok
  rescue
    ArgumentError -> :ok
  end

  def remember_missing(_key), do: :ok

  @doc """
  Forgets a miss, called when an object is written.
  """
  @spec forget(String.t()) :: :ok
  def forget(key) when is_binary(key) do
    :ets.delete(@table, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def forget(_key), do: :ok

  @impl true
  def init(:ok) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  # A miss cache is only useful while it is small; dropping it wholesale is
  # cheaper than sorting entries and the next request simply re-checks.
  defp trim do
    if :ets.info(@table, :size) > @max_entries do
      :ets.delete_all_objects(@table)
    end

    :ok
  end
end
