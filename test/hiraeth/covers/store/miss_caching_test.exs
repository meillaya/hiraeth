defmodule Hiraeth.Covers.Store.MissCachingTest do
  @moduledoc """
  A cover the durable store reported missing must not cost a round trip on
  every page view, and a later upload must still be visible.
  """

  use ExUnit.Case, async: false

  alias Hiraeth.Covers.MissCache
  alias Hiraeth.Covers.Store

  @key "covers/cache/miss-cache-test.jpg"

  defmodule CountingStore do
    @behaviour Hiraeth.Covers.Store

    def start_link, do: Agent.start_link(fn -> %{gets: 0, present: false} end, name: agent())

    @impl true
    def configured?, do: true

    @impl true
    def get(_key), do: Agent.get_and_update(agent(), &count_get/1)

    @impl true
    def put(_key, _body, _content_type), do: :ok

    @impl true
    def delete(_key), do: :ok

    def gets, do: Agent.get(agent(), & &1.gets)

    def mark_present, do: Agent.update(agent(), &%{&1 | present: true})

    defp count_get(state) do
      state = %{state | gets: state.gets + 1}

      if state.present do
        {{:ok, "image bytes", "image/jpeg"}, state}
      else
        {:missing, state}
      end
    end

    defp agent, do: __MODULE__.Agent
  end

  setup do
    previous = Application.get_env(:hiraeth, Store)

    {:ok, _pid} = CountingStore.start_link()
    Application.put_env(:hiraeth, Store, adapter: CountingStore)
    MissCache.forget(@key)

    on_exit(fn ->
      MissCache.forget(@key)
      Application.put_env(:hiraeth, Store, previous || [])
    end)

    :ok
  end

  test "a remembered miss is answered without consulting the store" do
    refute MissCache.known_missing?(@key)

    assert Store.get(@key) == :missing
    assert MissCache.known_missing?(@key)

    assert Store.get(@key) == :missing
    assert CountingStore.gets() == 1
  end

  test "writing an object clears its remembered miss" do
    assert Store.get(@key) == :missing
    assert MissCache.known_missing?(@key)

    CountingStore.mark_present()
    assert Store.put(@key, "image bytes", "image/jpeg") == :ok
    refute MissCache.known_missing?(@key)

    assert {:ok, "image bytes", "image/jpeg"} = Store.get(@key)
    assert CountingStore.gets() == 2
  end

  test "forget makes the store authoritative again" do
    MissCache.remember_missing(@key)
    assert MissCache.known_missing?(@key)

    MissCache.forget(@key)

    refute MissCache.known_missing?(@key)
  end
end
