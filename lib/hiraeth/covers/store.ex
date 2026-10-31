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

  @doc "Stores one object under a content-addressed key."
  @spec put(key(), binary(), String.t()) :: result()
  def put(key, body, content_type), do: impl().put(key, body, content_type)

  @doc "Returns an object body and its content type, or `:missing`."
  @spec get(key()) :: {:ok, binary(), String.t() | nil} | :missing | {:error, term()}
  def get(key), do: impl().get(key)

  @doc "Deletes one object. Missing objects are not an error."
  @spec delete(key()) :: result()
  def delete(key), do: impl().delete(key)

  @doc "Returns true when a durable store is configured."
  @spec configured?() :: boolean()
  def configured?, do: impl().configured?()

  @spec config() :: keyword()
  def config, do: Application.get_env(:hiraeth, __MODULE__, [])

  defp impl do
    config()[:adapter] || Hiraeth.Covers.Store.Local
  end
end
