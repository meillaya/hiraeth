defmodule Hiraeth.Covers.Store.S3Test do
  @moduledoc "The S3 adapter addresses buckets with virtual-hosted URLs."

  use ExUnit.Case, async: false

  alias Hiraeth.Covers.Store

  setup do
    previous = Application.get_env(:hiraeth, Store)

    Application.put_env(:hiraeth, Store,
      adapter: Hiraeth.Covers.Store.S3,
      endpoint: "https://t3.storageapi.dev",
      bucket: "hiraeth-covers",
      access_key_id: "test-key",
      secret_access_key: "test-secret",
      region: "auto"
    )

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:hiraeth, Store)
      else
        Application.put_env(:hiraeth, Store, previous)
      end
    end)

    :ok
  end

  test "put uses the bucket subdomain and object key" do
    plug = fn conn ->
      assert conn.host == "hiraeth-covers.t3.storageapi.dev"
      assert conn.request_path == "/covers/cache/abc.jpg"
      Plug.Conn.resp(conn, 200, "")
    end

    configure_plug(plug)

    assert :ok = Store.put("covers/cache/abc.jpg", "image bytes", "image/jpeg")
  end

  test "get returns the body and content type, and maps 404 to missing" do
    plug = fn conn ->
      assert conn.host == "hiraeth-covers.t3.storageapi.dev"
      assert conn.request_path == "/covers/cache/abc.jpg"

      conn
      |> Plug.Conn.put_resp_content_type("image/jpeg")
      |> Plug.Conn.resp(200, "image bytes")
    end

    configure_plug(plug)
    assert {:ok, "image bytes", "image/jpeg"} = Store.get("covers/cache/abc.jpg")

    configure_plug(fn conn -> Plug.Conn.resp(conn, 404, "") end)
    assert Store.get("covers/cache/missing.jpg") == :missing
  end

  defp configure_plug(plug) do
    config = Application.get_env(:hiraeth, Store)
    Application.put_env(:hiraeth, Store, Keyword.put(config, :req_options, plug: plug))
  end
end
