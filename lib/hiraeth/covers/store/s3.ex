defmodule Hiraeth.Covers.Store.S3 do
  @moduledoc """
  S3-compatible durable cover store, used with Cloudflare R2.

  Configuration comes from `config :hiraeth, Hiraeth.Covers.Store` and is built
  in `config/runtime.exs` from `R2_ENDPOINT`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY`, and `R2_REGION`. Requests use the existing `Req`
  client with the `ReqS3` SigV4 plugin.
  """

  @behaviour Hiraeth.Covers.Store

  alias Hiraeth.Covers.Store

  @timeout 15_000

  @impl true
  def configured? do
    config = Store.config()

    Enum.all?([:endpoint, :bucket, :access_key_id, :secret_access_key], fn key ->
      value = config[key]
      is_binary(value) and value != ""
    end)
  end

  @impl true
  def put(key, body, content_type) do
    with {:ok, request, config} <- request() do
      case Req.put(request,
             url: object_url(config, key),
             body: body,
             headers: [{"content-type", content_type}],
             receive_timeout: @timeout
           ) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, %{status: status}} -> {:error, {:http_status, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def get(key) do
    with {:ok, request, config} <- request() do
      case Req.get(request,
             url: object_url(config, key),
             decode_body: false,
             receive_timeout: @timeout
           ) do
        {:ok, %{status: 200, body: body} = response} ->
          {:ok, body, content_type(response)}

        {:ok, %{status: 404}} ->
          :missing

        {:ok, %{status: status}} ->
          {:error, {:http_status, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def delete(key) do
    with {:ok, request, config} <- request() do
      case Req.delete(request,
             url: object_url(config, key),
             receive_timeout: @timeout
           ) do
        {:ok, %{status: status}} when status in [200, 202, 204, 404] -> :ok
        {:ok, %{status: status}} -> {:error, {:http_status, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp request do
    config = Store.config()

    if configured?() do
      request =
        Req.new()
        |> ReqS3.attach(
          aws_endpoint_url_s3: config[:endpoint],
          aws_sigv4: [
            access_key_id: config[:access_key_id],
            secret_access_key: config[:secret_access_key],
            region: config[:region] || "auto"
          ]
        )

      {:ok, request, config}
    else
      {:error, :not_configured}
    end
  end

  defp object_url(config, key) when is_binary(key) and key != "" do
    "s3://#{config[:bucket]}/#{key}"
  end

  defp content_type(%Req.Response{} = response) do
    case Req.Response.get_header(response, "content-type") do
      [content_type | _rest] -> content_type
      _missing -> nil
    end
  end
end
