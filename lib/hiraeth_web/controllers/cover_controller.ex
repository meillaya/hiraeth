defmodule HiraethWeb.CoverController do
  @moduledoc """
  Serves cached cover files from disk, refilling a miss from object storage.

  `Plug.Static` serves files already on disk. This controller handles the miss:
  it validates the path, confirms the database still marks the cover public,
  fetches the object, writes the local cache, and returns the bytes. Keeping the
  `/covers/cache/...` path same-origin preserves the CSP and the page contract.
  """

  use HiraethWeb, :controller

  require Logger

  alias Hiraeth.Covers
  alias Hiraeth.Covers.{CachePruner, CoverAsset, Store}

  @cache_root "priv/static/covers/cache"
  @allowed_content_types ~w(image/jpeg image/png image/webp image/gif image/avif)
  @max_body_bytes 10 * 1024 * 1024

  # The response is an image whose content type is checked against a fixed
  # allowlist and whose body is capped, so it cannot be rendered as HTML.
  # sobelow_skip ["XSS.SendResp"]
  def show(conn, %{"path" => relative}) do
    path = Path.join(@cache_root, relative)

    case serve(relative) do
      {:ok, body, content_type} ->
        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("cache-control", cache_control(path))
        |> send_resp(200, body)

      :not_found ->
        # A cover the durable store does not hold is a cold miss nothing will
        # fix mid-session. Telling the browser and any intermediary keeps the
        # next navigation from paying for the lookup again.
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("cache-control", "public, max-age=60")
        |> send_resp(404, "")
    end
  end

  defp cache_control(path) do
    if Covers.responsive_variant_path?(path) do
      "public, max-age=31536000, immutable"
    else
      "public, max-age=86400"
    end
  end

  defp serve(relative) do
    path = Path.join(@cache_root, relative)

    with true <- Covers.cache_file_path_safe?(path),
         {:ok, _asset} <- visible_asset(path),
         {:ok, body, content_type} <- read_or_fetch(path) do
      {:ok, body, content_type}
    else
      _other -> :not_found
    end
  end

  defp visible_asset(path) do
    case Hiraeth.Repo.query!(
           """
           select id
           from cover_assets
           where cached_file_path = $1
              or thumbnail_file_path = $1
              or exists (
                select 1
                from jsonb_array_elements(responsive_variants) as variant
                where variant->>'path' = $1
              )
           limit 1
           """,
           [path]
         ).rows do
      [[id]] ->
        proxyable_asset(id)

      _missing_or_error ->
        :not_public
    end
  end

  defp proxyable_asset(id) do
    case Ash.get(CoverAsset, id, authorize?: false) do
      {:ok, %CoverAsset{} = asset} ->
        if Covers.proxyable_cover_asset?(asset), do: {:ok, asset}, else: :not_public

      _missing_or_error ->
        :not_public
    end
  end

  defp read_or_fetch(path) do
    if File.regular?(path) do
      local_file(path)
    else
      fetch_object(path)
    end
  end

  # The path passed Covers.cache_file_path_safe?/1 before this read: it is under
  # the cache root and has no symlink ancestor.
  # sobelow_skip ["Traversal.FileModule"]
  defp local_file(path) do
    case File.read(path) do
      {:ok, body} ->
        case content_type_for(path) do
          type when type in @allowed_content_types -> {:ok, body, type}
          _unsupported -> :not_found
        end

      {:error, _reason} ->
        :not_found
    end
  end

  defp fetch_object(path) do
    key = Covers.object_key(path)

    with true <- is_binary(key),
         {:ok, body, stored_type} <- Store.get(key),
         true <- byte_size(body) <= @max_body_bytes,
         type when type in @allowed_content_types <- normalize_content_type(stored_type, path),
         :ok <- write_local(path, body) do
      Task.start(fn -> CachePruner.prune!() end)
      {:ok, body, type}
    else
      _missing_or_error -> :not_found
    end
  end

  defp normalize_content_type(nil, path), do: content_type_for(path)

  defp normalize_content_type(type, _path) when is_binary(type) do
    type
    |> String.split(";")
    |> List.first()
    |> String.trim()
    |> String.downcase()
  end

  defp content_type_for(path), do: MIME.from_path(path)

  # The path passed Covers.cache_file_path_safe?/1 before this write: it is
  # under the cache root and has no symlink ancestor.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_local(path, body) do
    with true <- Covers.cache_file_path_safe?(path),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      write_temporary(path, body)
    else
      _unsafe_or_error -> {:error, :unsafe_path}
    end
  end

  # The temporary path is derived from a validated cache path.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_temporary(path, body) do
    temporary = "#{path}.tmp-#{System.unique_integer([:positive])}"

    case File.write(temporary, body) do
      :ok -> rename_temporary(temporary, path)
      {:error, reason} -> {:error, reason}
    end
  end

  # The temporary path is derived from a validated cache path.
  # sobelow_skip ["Traversal.FileModule"]
  defp rename_temporary(temporary, path) do
    case File.rename(temporary, path) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm(temporary)
        {:error, reason}
    end
  end
end
