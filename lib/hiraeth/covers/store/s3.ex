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
  def head(key) do
    with {:ok, request, config} <- request() do
      case Req.head(request,
             url: object_url(config, key),
             receive_timeout: @timeout
           ) do
        {:ok, %{status: 200} = response} ->
          {:ok, %{size: content_length(response), etag: response_header(response, "etag")}}

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
        Req.new(config[:req_options] || [])
        |> ReqS3.attach(
          aws_sigv4: [
            service: :s3,
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

  # New Railway and R2 buckets use virtual-hosted URLs, where the bucket is a
  # subdomain of the endpoint. ReqS3 signs any URL, so build the full URL here
  # instead of relying on its path-style `s3://` expansion.
  defp object_url(config, key) when is_binary(key) and key != "" do
    endpoint = URI.parse(config[:endpoint])

    %{endpoint | host: "#{config[:bucket]}.#{endpoint.host}", path: "/" <> key, query: nil}
    |> URI.to_string()
  end

  defp content_type(%Req.Response{} = response) do
    case Req.Response.get_header(response, "content-type") do
      [content_type | _rest] -> content_type |> String.split(";") |> List.first() |> String.trim()
      _missing -> nil
    end
  end

  defp content_length(%Req.Response{} = response) do
    case response_header(response, "content-length") do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {size, ""} when size >= 0 -> size
          _invalid -> nil
        end
    end
  end

  defp response_header(%Req.Response{} = response, name) do
    case Req.Response.get_header(response, name) do
      [value | _rest] -> value
      _missing -> nil
    end
  end
end
