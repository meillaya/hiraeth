defmodule Hiraeth.Covers.CachePruner do
  @moduledoc """
  Bounds the local cover cache.

  The durable copy lives in the object store, so the container only needs a
  working set. Pruning deletes the oldest files until the cache falls under the
  configured cap, then stops with some headroom.
  """

  @cache_root "priv/static/covers/cache"
  @default_max_bytes 1_073_741_824
  @headroom 0.8

  @doc """
  Prunes oldest files under the cache root until the cache fits the cap.

  Returns `{:ok, deleted_count}` or `{:ok, 0}` when the cache is offline or
  already under the cap.
  """
  @spec prune!(keyword()) :: {:ok, non_neg_integer()}
  def prune!(opts \\ []) do
    root = Keyword.get(opts, :cache_root, @cache_root)
    max_bytes = Keyword.get(opts, :max_bytes, configured_max_bytes())

    case cache_entries(root) do
      {:ok, entries} ->
        total = Enum.sum(Enum.map(entries, & &1.size))

        if total > max_bytes do
          {:ok, delete_oldest(entries, total, max_bytes)}
        else
          {:ok, 0}
        end

      :error ->
        {:ok, 0}
    end
  end

  defp configured_max_bytes do
    case Application.get_env(:hiraeth, :cover_cache_max_bytes, @default_max_bytes) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_max_bytes
    end
  end

  defp cache_entries(root) do
    if File.dir?(root) do
      entries =
        root
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&entry_for/1)

      {:ok, entries}
    else
      :error
    end
  end

  defp entry_for(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> %{path: path, size: stat.size, mtime: stat.mtime}
      {:error, _reason} -> %{path: path, size: 0, mtime: 0}
    end
  end

  defp delete_oldest(entries, total, max_bytes) do
    target = trunc(max_bytes * @headroom)

    {_remaining, deleted} =
      entries
      |> Enum.sort_by(& &1.mtime)
      |> Enum.reduce_while({total, 0}, &delete_until_target(&1, &2, target))

    deleted
  end

  # The path comes from Path.wildcard under the configured cache root, not from
  # request input.
  # sobelow_skip ["Traversal.FileModule"]
  defp delete_until_target(entry, {remaining, deleted}, target) do
    if remaining <= target do
      {:halt, {remaining, deleted}}
    else
      case File.rm(entry.path) do
        :ok -> {:cont, {remaining - entry.size, deleted + 1}}
        {:error, _reason} -> {:cont, {remaining, deleted}}
      end
    end
  end
end
