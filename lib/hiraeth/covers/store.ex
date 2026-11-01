defmodule Hiraeth.Covers.Store do
  @moduledoc """
  Durable object store for cached public covers.

  The local disk is a cache. This boundary keeps the same content-addressed
  objects off-box so a restart or a second replica can refill the local cache
  without re-fetching every publisher source.
  """

  @type key :: String.t()
  @type result :: :ok | {:error, term()}

  @callback put(key(), binary(), String.t()) :: result()
  @callback get(key()) :: {:ok, binary(), String.t() | nil} | :missing | {:error, term()}
  @callback delete(key()) :: result()
  @callback configured?() :: boolean()

  alias Hiraeth.Covers.MissCache

  @doc "Stores one object under a content-addressed key."
  @spec put(key(), binary(), String.t()) :: result()
  def put(key, body, content_type) do
    MissCache.forget(key)
    impl().put(key, body, content_type)
  end

  @doc """
  Returns an object body and its content type, or `:missing`.

  A miss the durable store already reported is answered from
  `Hiraeth.Covers.MissCache` until the entry expires, so a cold replica does not
  pay for the same absent object on every page view.
  """
  @spec get(key()) :: {:ok, binary(), String.t() | nil} | :missing | {:error, term()}
  def get(key) do
    if MissCache.known_missing?(key), do: :missing, else: fetch_or_remember_miss(key)
  end

  defp fetch_or_remember_miss(key) do
    case impl().get(key) do
      :missing ->
        if configured?(), do: MissCache.remember_missing(key)
        :missing

      other ->
        other
    end
  end

  @doc "Deletes one object. Missing objects are not an error."
  @spec delete(key()) :: result()
  def delete(key) do
    MissCache.forget(key)
    impl().delete(key)
  end

  @doc "Returns true when a durable store is configured."
  @spec configured?() :: boolean()
  def configured?, do: impl().configured?()

  @spec config() :: keyword()
  def config, do: Application.get_env(:hiraeth, __MODULE__, [])

  defp impl do
    config()[:adapter] || Hiraeth.Covers.Store.Local
  end
end
