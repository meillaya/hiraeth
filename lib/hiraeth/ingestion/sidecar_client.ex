defmodule Hiraeth.Ingestion.SidecarClient do
  @moduledoc """
  Req-based HTTP client for communicating with the Scrapling FastAPI sidecar.

  Every call returns `{:ok, result}` or `{:error, reason}` and does not raise on
  transport failures. A missing `:hiraeth, :scrapling_sidecar` base URL is a
  deployment configuration error and raises at call time with a named message.
  """

  @health_timeout 30_000
  @scrape_timeout 300_000
  @detail_timeout 10_000
  @detail_max_retries 3

  @typedoc "Typed error codes the private sidecar returns in its error envelope."
  @type error_code ::
          :rate_limited
          | :blocked
          | :schema_changed
          | :empty_response
          | :invalid_host
          | :network
          | :parse_failed
          | :internal_error

  @typedoc "A transport message or a typed sidecar error and its message."
  @type error :: String.t() | {error_code(), String.t()}

  @typedoc "Sidecar health payload."
  @type health :: %{status: String.t() | nil, scrapling: boolean() | nil}

  @typedoc "Provider slug plus the validated manifest configuration to send."
  @type provider_config :: %{required(:provider) => String.t(), required(:config) => map()}

  @typedoc "Fetched or scraped provider records."
  @type records :: %{records: [map()]}

  @doc """
  Checks sidecar health via GET /health/.

  Returns `{:ok, %{status: "ok", scrapling: true}}` on success,
  or `{:error, reason}` on failure.
  """
  @spec health() :: {:ok, health()} | {:error, error()}
  @spec health(keyword()) :: {:ok, health()} | {:error, error()}
  def health(opts \\ []) do
    base_url = base_url()
    req_options = Keyword.get(opts, :req_options, [])

    default_options = [
      receive_timeout: @health_timeout,
      retry: false
    ]

    case Req.get("#{base_url}/health/", Keyword.merge(default_options, req_options)) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, %{status: body["status"], scrapling: body["scrapling"]}}

      {:ok, %{status: status}} when status in 200..299 ->
        {:error, "sidecar health check returned a non-object body"}

      {:ok, %{status: status}} ->
        {:error, "sidecar health check failed with status #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  @doc """
  Fetches records from the sidecar via POST /fetch/.

  `provider_config` is a map with `provider` (slug) and `config` (manifest map).
  Returns `{:ok, %{records: [...]}}` on success, or `{:error, reason}` on failure.
  """
  @spec fetch(provider_config()) :: {:ok, records()} | {:error, error()}
  @spec fetch(provider_config(), keyword()) :: {:ok, records()} | {:error, error()}
  def fetch(provider_config, opts \\ []) do
    post_records("fetch", "/fetch/", provider_config, opts)
  end

  @doc """
  Scrapes records from the sidecar via POST /scrape/.

  `provider_config` is a map with `provider` (slug) and `config` (manifest map).
  Returns `{:ok, %{records: [...]}}` on success, or `{:error, reason}` on failure.
  """
  @spec scrape(provider_config()) :: {:ok, records()} | {:error, error()}
  @spec scrape(provider_config(), keyword()) :: {:ok, records()} | {:error, error()}
  def scrape(provider_config, opts \\ []) do
    post_records("scrape", "/scrape/", provider_config, opts)
  end

  @doc """
  Fetches detail-page enrichment from the sidecar via POST /scrape/detail.

  Returns `{:ok, detail}` on success, or `{:error, reason}` on failure.
  The detail endpoint is intentionally bounded because worker ingestion can
  proceed with the original record if detail enrichment is unavailable.
  """
  @spec detail(String.t(), String.t()) :: {:ok, map()} | {:error, error()}
  @spec detail(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, error()}
  def detail(source_uri, vendor, opts \\ []) when is_binary(source_uri) and is_binary(vendor) do
    base_url = base_url()
    req_options = Keyword.get(opts, :req_options, [])

    default_options = [
      json: detail_request_body(source_uri, vendor, opts),
      receive_timeout: @detail_timeout,
      retry: :transient,
      max_retries: @detail_max_retries
    ]

    case Req.post("#{base_url}/scrape/detail", Keyword.merge(default_options, req_options)) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} when status in 200..299 ->
        {:error, "sidecar detail returned a non-object body"}

      {:ok, %{status: status, body: body}} ->
        sidecar_error_or_status_error("detail", status, body)

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  # Both record endpoints share one transport and one response contract.
  defp post_records(operation, path, provider_config, opts) do
    base_url = base_url()
    req_options = Keyword.get(opts, :req_options, [])

    default_options = [
      json: provider_config,
      receive_timeout: @scrape_timeout,
      retry: false
    ]

    case Req.post("#{base_url}#{path}", Keyword.merge(default_options, req_options)) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, %{records: body["records"] || []}}

      {:ok, %{status: status}} when status in 200..299 ->
        {:error, "sidecar #{operation} returned a non-object body"}

      {:ok, %{status: status, body: body}} ->
        sidecar_error_or_status_error(operation, status, body)

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp base_url do
    case Application.get_env(:hiraeth, :scrapling_sidecar, [])[:base_url] do
      url when is_binary(url) and url != "" ->
        String.trim_trailing(url, "/")

      _missing ->
        raise ArgumentError,
              "missing :hiraeth, :scrapling_sidecar base_url; set SCRAPLING_SIDECAR_URL"
    end
  end

  defp detail_request_body(source_uri, vendor, opts) do
    case Keyword.get(opts, :max_bytes) do
      max_bytes when is_integer(max_bytes) and max_bytes > 0 ->
        %{url: source_uri, vendor: vendor, max_bytes: max_bytes}

      _max_bytes ->
        %{url: source_uri, vendor: vendor}
    end
  end

  defp sidecar_error_or_status_error(operation, status, body) do
    case typed_sidecar_error(body) do
      {:ok, error} -> {:error, error}
      :error -> {:error, "sidecar #{operation} failed with status #{status}"}
    end
  end

  defp typed_sidecar_error(%{"detail" => %{"code" => code, "message" => message}})
       when is_binary(message) do
    case sidecar_error_code(code) do
      {:ok, atom} -> {:ok, {atom, message}}
      :error -> :error
    end
  end

  defp typed_sidecar_error(_body), do: :error

  defp sidecar_error_code("rate_limited"), do: {:ok, :rate_limited}
  defp sidecar_error_code("blocked"), do: {:ok, :blocked}
  defp sidecar_error_code("schema_changed"), do: {:ok, :schema_changed}
  defp sidecar_error_code("empty_response"), do: {:ok, :empty_response}
  defp sidecar_error_code("invalid_host"), do: {:ok, :invalid_host}
  defp sidecar_error_code("network"), do: {:ok, :network}
  defp sidecar_error_code("parse_failed"), do: {:ok, :parse_failed}
  defp sidecar_error_code("internal_error"), do: {:ok, :internal_error}
  defp sidecar_error_code(_code), do: :error
end
