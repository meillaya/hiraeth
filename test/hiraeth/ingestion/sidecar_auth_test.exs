defmodule Hiraeth.Ingestion.SidecarAuthTest do
  @moduledoc """
  Phoenix signs sidecar data requests when a shared secret is configured.
  """

  use ExUnit.Case, async: false

  alias Hiraeth.Ingestion.SidecarClient

  setup do
    previous = Application.get_env(:hiraeth, :scrapling_sidecar)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:hiraeth, :scrapling_sidecar)
      else
        Application.put_env(:hiraeth, :scrapling_sidecar, previous)
      end
    end)

    :ok
  end

  test "fetch requests carry a timestamped HMAC of the raw body" do
    configure_sidecar("test-secret")

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [timestamp] = Plug.Conn.get_req_header(conn, "x-hiraeth-timestamp")
      [signature] = Plug.Conn.get_req_header(conn, "x-hiraeth-signature")

      expected =
        :crypto.mac(:hmac, :sha256, "test-secret", timestamp <> "." <> body)
        |> Base.encode16(case: :lower)

      assert signature == expected

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"provider":"deep_vellum","status":"ok","records":[]}))
    end

    assert {:ok, %{records: []}} =
             SidecarClient.fetch(
               %{provider: "deep_vellum", config: %{}},
               req_options: [plug: plug]
             )
  end

  test "detail requests are signed the same way" do
    configure_sidecar("test-secret")

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [timestamp] = Plug.Conn.get_req_header(conn, "x-hiraeth-timestamp")
      [signature] = Plug.Conn.get_req_header(conn, "x-hiraeth-signature")

      expected =
        :crypto.mac(:hmac, :sha256, "test-secret", timestamp <> "." <> body)
        |> Base.encode16(case: :lower)

      assert signature == expected

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        ~s({"vendor":"deep_vellum_official_store","source_uri":"https://example.com/book"})
      )
    end

    assert {:ok, %{"vendor" => "deep_vellum_official_store"}} =
             SidecarClient.detail(
               "https://example.com/book",
               "deep_vellum_official_store",
               req_options: [plug: plug]
             )
  end

  test "no signature headers are sent without a configured token" do
    configure_sidecar(nil)

    plug = fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-hiraeth-signature") == []

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"provider":"deep_vellum","status":"ok","records":[]}))
    end

    assert {:ok, %{records: []}} =
             SidecarClient.fetch(
               %{provider: "deep_vellum", config: %{}},
               req_options: [plug: plug]
             )
  end

  defp configure_sidecar(token) do
    Application.put_env(:hiraeth, :scrapling_sidecar,
      base_url: "http://localhost:8000",
      token: token
    )
  end
end
