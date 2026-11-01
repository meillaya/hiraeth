defmodule HiraethWeb.PageCache do
  @moduledoc """
  Small ETS cache for server-rendered catalogue pages.

  Entries are keyed by path and query, expire by TTL, and are cleared when the
  projection revision changes. The cache deliberately never stores responses
  with cookies or flash.
  """

  use GenServer

  @table :hiraeth_page_cache
  @max_entries 2_000
  @default_ttl_ms :timer.seconds(300)

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_arg), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:hiraeth, :page_cache, true)

  @spec fetch(term(), (-> {binary(), String.t()}), timeout()) ::
          {:ok, binary(), String.t()} | :miss
  def fetch(key, fun, ttl \\ @default_ttl_ms) do
    if enabled?() do
      now = System.monotonic_time(:millisecond)

      case :ets.lookup(@table, key) do
        [{^key, body, etag, expires_at}] when expires_at > now ->
          {:ok, body, etag}

        _ ->
          {body, etag} = fun.()
          :ets.insert(@table, {key, body, etag, now + ttl})
          trim()
          {:ok, body, etag}
      end
    else
      {body, etag} = fun.()
      {:ok, body, etag}
    end
  end

  @spec put(term(), binary(), String.t()) :: :ok
  def put(key, body, etag) do
    if enabled?() do
      :ets.insert(
        @table,
        {key, body, etag, System.monotonic_time(:millisecond) + @default_ttl_ms}
      )

      trim()
    end

    :ok
  end

  @spec clear() :: :ok
  def clear do
    if enabled?(), do: :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec etag(binary()) :: String.t()
  def etag(body) do
    body
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&"\"#{&1}\"")
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  defp delete_if_expired({key, _body, _etag, expires_at}, now) do
    if expires_at < now, do: :ets.delete(@table, key)
  end

  defp trim do
    size = :ets.info(@table, :size)

    if size > @max_entries do
      now = System.monotonic_time(:millisecond)

      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_key, _body, _etag, expires_at} -> expires_at end)
      |> Enum.take(size - @max_entries)
      |> Enum.each(&delete_if_expired(&1, now))
    end
  end
end
