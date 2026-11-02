defmodule Hiraeth.TestSupport.CoverStoreFake do
  @moduledoc false
  @behaviour Hiraeth.Covers.Store

  @table :hiraeth_cover_store_fake

  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @impl true
  def put(key, body, content_type) do
    ensure_table()
    :ets.insert(@table, {key, body, content_type})
    :ok
  end

  @impl true
  def get(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, body, content_type}] -> {:ok, body, content_type}
      [] -> :missing
    end
  end

  @impl true
  def head(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, body, _content_type}] ->
        {:ok, %{size: byte_size(body), etag: "\"" <> md5_hex(body) <> "\""}}

      [] ->
        :missing
    end
  end

  @impl true
  def delete(key) do
    ensure_table()
    :ets.delete(@table, key)
    :ok
  end

  @impl true
  def configured?, do: true

  defp md5_hex(body), do: Base.encode16(:crypto.hash(:md5, body), case: :lower)

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end
  end
end
