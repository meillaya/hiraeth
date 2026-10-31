defmodule Hiraeth.Covers.Store.Local do
  @moduledoc """
  No-op durable store for local development and tests.

  The local disk cache is the only cache in this mode. Writes succeed so the
  cache pipeline does not branch on the adapter.
  """

  @behaviour Hiraeth.Covers.Store

  @impl true
  def put(_key, _body, _content_type), do: :ok

  @impl true
  def get(_key), do: :missing

  @impl true
  def delete(_key), do: :ok

  @impl true
  def configured?, do: false
end
