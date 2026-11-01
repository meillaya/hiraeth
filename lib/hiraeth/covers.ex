defmodule Hiraeth.Covers do
  @moduledoc "Ash domain and facade: cover assets, assignments, and the sandboxed cover cache."

  use Ash.Domain

  alias Hiraeth.Catalog.PublicWorkProjection
  alias Hiraeth.Covers.{CachePruner, CoverAsset, CoverAssignment, Store}
  alias Hiraeth.RealCatalog.SourcePolicy

  require Logger

  @cache_root "priv/static/covers/cache"
  @thumbnail_timeout 5_000
  @thumbnail_command_timeout "5s"
  @variant_widths [200, 400, 800]
  @variant_formats ["webp", "jpg"]
  @variant_timeout 8_000
  @variant_command_timeout "8s"
  @default_max_body_size 40 * 1024 * 1024

  @accepted_content_types %{
    "image/jpeg" => :jpeg,
    "image/jpg" => :jpeg,
    "image/png" => :png,
    "image/webp" => :webp,
    "image/gif" => :gif
  }

  resources do
    resource Hiraeth.Covers.CoverAsset
    resource Hiraeth.Covers.CoverAssignment
  end

  def fallback_cover do
    %{
      source_url: nil,
      provider: "hiraeth",
      rights_basis: "fallback_placeholder",
      cache_policy: "generated_placeholder",
      attribution_text: "No public cover available"
    }
  end

  def public_cover_for_edition(edition_id) do
    assignment =
      CoverAssignment
      |> Ash.Query.for_read(:public_for_edition, %{edition_id: edition_id})
      |> Ash.read!()
      |> Ash.load!(:cover_asset)
      |> Enum.find(fn assignment -> public_cover_asset?(assignment.cover_asset) end)

    case assignment do
      nil -> fallback_cover()
      %{cover_asset: cover_asset} -> public_cover_map(cover_asset)
    end
  end

  def audit_public_cover_provenance!(path) do
    assignments =
      CoverAssignment
      |> Ash.Query.for_read(:public)
      |> Ash.read!()
      |> Ash.load!([:cover_asset, :edition])

    invalid_public_covers =
      assignments
      |> Enum.reject(fn assignment -> public_cover_provenance_valid?(assignment.cover_asset) end)
      |> Enum.map(fn assignment ->
        %{
          cover_assignment_id: assignment.id,
          cover_asset_id: assignment.cover_asset_id,
          edition_id: assignment.edition_id,
          reason: "public assignment does not have valid visible cover provenance"
        }
      end)

    audit = %{
      checked_public_assignments: Enum.count(assignments),
      invalid_public_covers: invalid_public_covers
    }

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, Jason.encode!(audit, pretty: true))

    audit
  end

  def public_cover_asset?(%CoverAsset{} = cover_asset) do
    uri = parse_uri(cover_asset.source_url)

    cover_asset.takedown_state == "visible" and present?(cover_asset.source_url) and
      present?(cover_asset.provider) and present?(cover_asset.rights_basis) and
      uri.scheme == "https" and SourcePolicy.cover_host_allowed?(cover_asset.provider, uri.host) and
      cache_policy_public?(cover_asset)
  end

  def public_cover_asset?(_cover_asset), do: false

  @doc """
  Returns true when a cover may be served by the proxy.

  This check does not require the local file to exist, because refilling that
  file is the proxy's job. It still requires the stored policy, source host, and
  takedown state to allow public serving.
  """
  @spec proxyable_cover_asset?(term()) :: boolean()
  def proxyable_cover_asset?(%CoverAsset{} = cover_asset) do
    uri = parse_uri(cover_asset.source_url)

    cover_asset.takedown_state == "visible" and present?(cover_asset.source_url) and
      present?(cover_asset.provider) and present?(cover_asset.rights_basis) and
      uri.scheme == "https" and SourcePolicy.cover_host_allowed?(cover_asset.provider, uri.host) and
      cover_asset.cache_policy == "cache_allowed" and
      cover_asset.rights_basis == "local_cache_permitted"
  end

  def proxyable_cover_asset?(_cover_asset), do: false

  def public_cover_provenance_valid?(%CoverAsset{} = cover_asset) do
    uri = parse_uri(cover_asset.source_url)

    cover_asset.takedown_state == "visible" and present?(cover_asset.source_url) and
      present?(cover_asset.provider) and present?(cover_asset.rights_basis) and
      uri.scheme == "https" and SourcePolicy.cover_host_allowed?(cover_asset.provider, uri.host) and
      cache_policy_provenance_valid?(cover_asset)
  end

  def public_cover_provenance_valid?(_cover_asset), do: false

  def public_cover_rejection_reason(nil), do: "cover assignment has no cover asset"

  def public_cover_rejection_reason(%CoverAsset{} = asset) do
    uri = parse_uri(asset.source_url)

    cond do
      asset.takedown_state != "visible" ->
        "cover is hidden or under takedown"

      rejection = basic_field_rejection(asset) ->
        rejection

      uri.scheme != "https" ->
        "cover source URL must be HTTPS"

      not SourcePolicy.cover_host_allowed?(asset.provider, uri.host) ->
        "cover source URL host is not allowlisted for provider"

      rejection = cache_policy_rejection(asset) ->
        rejection

      true ->
        "cover provenance is incomplete"
    end
  end

  defp basic_field_rejection(asset) do
    cond do
      not present?(asset.source_url) -> "cover source URL is missing"
      not present?(asset.provider) -> "cover provider is missing"
      not present?(asset.rights_basis) -> "cover rights basis is missing"
      true -> nil
    end
  end

  defp cache_policy_rejection(asset) do
    cond do
      not known_cache_policy?(asset) ->
        "cover cache_policy must be cache_allowed with a validated local cached file"

      asset.cache_policy == "link_only" ->
        link_only_rejection(asset)

      asset.cache_policy == "cache_allowed" ->
        cache_allowed_rejection(asset)

      true ->
        nil
    end
  end

  defp known_cache_policy?(%{cache_policy: policy}), do: policy in ["link_only", "cache_allowed"]

  defp link_only_rejection(asset) do
    if present?(asset.cached_file_path) or present?(asset.thumbnail_file_path) do
      "cover cache file path is not allowed for link-only public display"
    else
      "public cover display requires cache_allowed with a validated local cached file"
    end
  end

  defp cache_allowed_rejection(asset) do
    cond do
      asset.rights_basis != "local_cache_permitted" ->
        "cached cover requires local cache rights basis"

      not present?(asset.cached_file_path) ->
        "cached cover file path is required for cacheable public display"

      not safe_cached_file_path?(asset.cached_file_path) ->
        "cached cover file path must be under priv/static/covers/cache"

      true ->
        nil
    end
  end

  def cache_public_covers!(opts \\ []) do
    cache_root = opts |> Keyword.get(:cache_root, @cache_root) |> ensure_safe_cache_root!()
    force? = Keyword.get(opts, :force?, false)
    req_options = Keyword.get(opts, :req_options, [])
    max_body_size = Keyword.get(opts, :max_body_size, @default_max_body_size)
    fetch = Keyword.get(opts, :fetch)
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)
    timeout = Keyword.get(opts, :timeout, 15_000)
    thumbnailer = Keyword.get(opts, :thumbnailer, &generate_thumbnail/2)
    thumbnail_timeout = Keyword.get(opts, :thumbnail_timeout, @thumbnail_timeout)
    variant_generator = Keyword.get(opts, :variant_generator, &generate_variants/3)
    variant_timeout = Keyword.get(opts, :variant_timeout, @variant_timeout)
    variants_only? = Keyword.get(opts, :variants_only?, false)
    strict? = Keyword.get(opts, :strict?, false)
    source_urls = Keyword.get(opts, :source_urls, :all)
    provider = Keyword.get(opts, :provider)
    prefer_store? = Keyword.get(opts, :prefer_store?, true)

    File.mkdir_p!(cache_root)
    verify_safe_cache_root!(cache_root)

    CoverAsset
    |> Ash.read!(authorize?: false)
    |> filter_source_urls(source_urls)
    |> filter_provider(provider)
    |> Enum.filter(fn asset ->
      cache_candidate?(asset) and
        (not variants_only? or
           (present?(asset.cached_file_path) and missing_responsive_variants?(asset)))
    end)
    |> Task.async_stream(
      &cover_cache_plan(
        &1,
        cache_root,
        force?,
        fetch,
        req_options,
        max_body_size,
        prefer_store?,
        variants_only?
      ),
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(
      %{cached: 0, thumbnails: 0, variants: 0, skipped: 0, failed: 0, failures: [], assets: []},
      fn
        {:ok, {:skip, _asset}}, summary ->
          %{summary | skipped: summary.skipped + 1}

        {:ok, {:variants, asset, source_path}}, summary ->
          {variant_asset, variants} =
            store_responsive_variants(
              asset,
              source_path,
              cache_root,
              variant_generator,
              variant_timeout
            )

          summary
          |> count_variants(variants)
          |> Map.update!(:assets, &[variant_asset | &1])

        {:ok, {:thumbnail, asset, cache_path, thumbnail_path}}, summary ->
          thumbnail_file_path =
            maybe_generate_thumbnail(cache_path, thumbnail_path, thumbnailer, thumbnail_timeout)

          {variant_asset, variants} =
            store_responsive_variants(
              asset,
              cache_path,
              cache_root,
              variant_generator,
              variant_timeout
            )

          cached_asset =
            variant_asset
            |> Ash.Changeset.for_update(:update, %{thumbnail_file_path: thumbnail_file_path})
            |> Ash.update!(authorize?: false)

          upload_cached_paths(
            [asset.cached_file_path, thumbnail_file_path] ++ variant_paths(variants)
          )

          summary
          |> count_variants(variants)
          |> count_cached(cached_asset, thumbnail_file_path)

        {:ok, {:adopt, asset, cache_path, thumbnail_path}}, summary ->
          {variant_asset, variants} =
            store_responsive_variants(
              asset,
              cache_path,
              cache_root,
              variant_generator,
              variant_timeout
            )

          cached_asset =
            variant_asset
            |> Ash.Changeset.for_update(:update, %{
              cache_policy: "cache_allowed",
              cached_file_path: cache_path,
              thumbnail_file_path: thumbnail_path,
              cached_at: DateTime.utc_now(:second)
            })
            |> Ash.update!(authorize?: false)

          upload_cached_paths([cache_path, thumbnail_path] ++ variant_paths(variants))

          summary
          |> count_variants(variants)
          |> count_cached(cached_asset, thumbnail_path)

        {:ok, {:cache, asset, cache_path, body}}, summary ->
          ensure_safe_cache_write_path!(cache_path, cache_root)
          File.write!(cache_path, body)

          thumbnail_file_path =
            maybe_generate_thumbnail(
              cache_path,
              thumbnail_path(asset, cache_root),
              thumbnailer,
              thumbnail_timeout
            )

          {variant_asset, variants} =
            store_responsive_variants(
              asset,
              cache_path,
              cache_root,
              variant_generator,
              variant_timeout
            )

          cached_asset =
            variant_asset
            |> Ash.Changeset.for_update(:update, %{
              cache_policy: "cache_allowed",
              cached_file_path: cache_path,
              thumbnail_file_path: thumbnail_file_path,
              cached_at: DateTime.utc_now(:second)
            })
            |> Ash.update!(authorize?: false)

          upload_cached_paths([cache_path, thumbnail_file_path] ++ variant_paths(variants))

          summary
          |> count_variants(variants)
          |> count_cached(cached_asset, thumbnail_file_path)

        {:ok, {:error, asset, reason}}, summary ->
          handle_cache_failure(summary, asset.source_url, reason, strict?)

        {:exit, reason}, summary ->
          handle_cache_failure(summary, nil, inspect(reason), strict?)
      end
    )
    |> Map.update!(:assets, &Enum.reverse/1)
    |> Map.update!(:failures, &Enum.reverse/1)
    |> tap(fn _summary -> CachePruner.prune!(cache_root: cache_root) end)
    |> tap(fn _summary -> PublicWorkProjection.enqueue_safe("cover_cache") end)
  end

  @doc """
  Returns cover-cache coverage grouped by provider.

  `cached` counts eligible assets whose original cache file exists; `thumbnails`
  counts eligible assets with both the original and thumbnail present;
  `variants` counts eligible assets with a complete responsive variant set.
  """
  @spec audit_cache(keyword()) :: [map()]
  def audit_cache(opts \\ []) do
    provider = Keyword.get(opts, :provider)

    CoverAsset
    |> Ash.read!(authorize?: false)
    |> filter_provider(provider)
    |> Enum.group_by(& &1.provider)
    |> Enum.map(fn {provider, assets} -> coverage_for_provider(provider, assets) end)
    |> Enum.sort_by(& &1.provider)
  end

  @doc "Returns true when an asset is eligible for public caching."
  @spec cache_eligible?(term()) :: boolean()
  def cache_eligible?(%CoverAsset{} = asset), do: cache_candidate?(asset)
  def cache_eligible?(_asset), do: false

  @doc """
  Returns the source URLs of cache-eligible assets that have no cached original.

  These are the assets a public page cannot render yet. A seed or import can
  create them faster than the weekly refresh runs, so the backfill worker uses
  this scope instead of sweeping the whole catalog.
  """
  @spec missing_cache_source_urls() :: [String.t()]
  def missing_cache_source_urls do
    CoverAsset
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(cache_candidate?(&1) and not present?(&1.cached_file_path)))
    |> Enum.map(& &1.source_url)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns source URLs whose cached original exists but whose responsive variant
  set is missing or stale. A cold container can refill originals from R2 and
  then rebuild variants from the local original without re-fetching the source.
  """
  @spec missing_variant_source_urls() :: [String.t()]
  def missing_variant_source_urls do
    public_asset_ids = public_cover_asset_ids()

    CoverAsset
    |> Ash.read!(authorize?: false)
    |> Enum.filter(
      &(MapSet.member?(public_asset_ids, &1.id) and cache_candidate?(&1) and
          present?(&1.cached_file_path) and missing_responsive_variants?(&1))
    )
    |> Enum.map(& &1.source_url)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp public_cover_asset_ids do
    CoverAssignment
    |> Ash.Query.for_read(:public)
    |> Ash.read!(authorize?: false)
    |> MapSet.new(& &1.cover_asset_id)
  end

  @doc "Returns true when the stored cache path exists and is safe to serve."
  @spec cached_file_available?(String.t() | nil) :: boolean()
  def cached_file_available?(path), do: cached_file_present?(path)

  defp coverage_for_provider(provider, assets) do
    eligible = Enum.filter(assets, &cache_eligible?/1)

    cached =
      Enum.count(eligible, &cached_file_available?(&1.cached_file_path))

    thumbnails =
      Enum.count(eligible, fn asset ->
        cached_file_available?(asset.cached_file_path) and
          cached_file_available?(asset.thumbnail_file_path)
      end)

    variants =
      Enum.count(eligible, fn asset ->
        cached_file_available?(asset.cached_file_path) and responsive_variants_current?(asset)
      end)

    %{
      provider: provider,
      assets: length(assets),
      eligible: length(eligible),
      cached: cached,
      thumbnails: thumbnails,
      variants: variants,
      missing_cache: length(eligible) - cached,
      missing_thumbnails: cached - thumbnails,
      missing_variants: cached - variants,
      non_public: length(assets) - length(eligible)
    }
  end

  defp filter_source_urls(assets, :all), do: assets

  defp filter_source_urls(assets, source_urls) when is_list(source_urls) do
    allowed = MapSet.new(source_urls)
    Enum.filter(assets, &MapSet.member?(allowed, &1.source_url))
  end

  defp filter_provider(assets, nil), do: assets

  defp filter_provider(assets, provider) when is_binary(provider) do
    Enum.filter(assets, &(&1.provider == provider))
  end

  defp count_cached(summary, asset, thumbnail_path) do
    summary
    |> Map.update!(:cached, &(&1 + 1))
    |> Map.update!(:assets, &[asset | &1])
    |> count_thumbnail(thumbnail_path)
  end

  defp count_thumbnail(summary, path) when is_binary(path) do
    if File.regular?(path) do
      %{summary | thumbnails: summary.thumbnails + 1}
    else
      summary
    end
  end

  defp count_thumbnail(summary, _path), do: summary

  defp count_variants(summary, []), do: summary

  defp count_variants(summary, variants) when is_list(variants) do
    %{summary | variants: summary.variants + 1}
  end

  defp cover_cache_plan(
         %CoverAsset{} = asset,
         cache_root,
         force?,
         fetch,
         req_options,
         max_body_size,
         prefer_store?,
         variants_only?
       ) do
    cache_path = cache_path(asset, cache_root)
    thumbnail_path = thumbnail_path(asset, cache_root)

    cond do
      variants_only? and cached_file_present?(asset.cached_file_path) ->
        {:variants, asset, asset.cached_file_path}

      variants_only? ->
        # A cold worker has the database path but no local original. Refill it
        # from the durable store (or the publisher as a last resort) inside the
        # variant pass so the worker does not need a page visit to warm each
        # cover before rendering its variants.
        fetch_into_cache(
          asset,
          cache_path,
          fetch,
          req_options,
          max_body_size,
          prefer_store?
        )

      cached_skip?(asset, force?) ->
        {:skip, asset}

      thumbnail_only_replay?(asset, force?) ->
        {:thumbnail, asset, asset.cached_file_path, thumbnail_path}

      adopt_cached_files?(cache_path, thumbnail_path, force?) ->
        {:adopt, asset, cache_path, thumbnail_path}

      true ->
        fetch_into_cache(
          asset,
          cache_path,
          fetch,
          req_options,
          max_body_size,
          prefer_store?
        )
    end
  end

  defp cached_skip?(asset, force?) do
    not force? and cached_file_present?(asset.cached_file_path) and
      cached_file_present?(asset.thumbnail_file_path)
  end

  defp thumbnail_only_replay?(asset, force?) do
    not force? and cached_file_present?(asset.cached_file_path)
  end

  defp adopt_cached_files?(cache_path, thumbnail_path, force?) do
    not force? and cached_file_present?(cache_path) and cached_file_present?(thumbnail_path)
  end

  defp fetch_into_cache(
         asset,
         cache_path,
         fetch,
         req_options,
         max_body_size,
         prefer_store?
       ) do
    body =
      case stored_cover_body(cache_path, prefer_store?) do
        {:ok, stored_body} ->
          validate_fetched_cover!(stored_body, asset.source_url, max_body_size)

        :missing ->
          fetch_cover_body(asset, fetch, req_options, max_body_size)
          |> validate_fetched_cover!(asset.source_url, max_body_size)
      end

    {:cache, asset, cache_path, body}
  rescue
    exception -> {:error, asset, Exception.message(exception)}
  catch
    kind, reason -> {:error, asset, "#{kind}: #{inspect(reason)}"}
  end

  # A cold container can refill its working set from the durable copy without
  # re-fetching every publisher URL. Only a missing object falls through to the
  # source; a store error is treated as a miss so the source remains a recovery
  # path.
  defp stored_cover_body(cache_path, true) do
    if Store.configured?() do
      case Store.get(object_key(cache_path)) do
        {:ok, body, _content_type} -> {:ok, body}
        :missing -> :missing
        {:error, _reason} -> :missing
      end
    else
      :missing
    end
  end

  defp stored_cover_body(_cache_path, _prefer_store?), do: :missing

  defp fetch_cover_body(%CoverAsset{} = asset, nil, req_options, max_body_size) do
    asset.source_url
    |> req_fetch!(req_options, max_body_size, SourcePolicy.cover_hosts(asset.provider))
  end

  defp fetch_cover_body(%CoverAsset{} = asset, fetch, _req_options, _max_body_size) do
    fetch.(asset.source_url)
  end

  defp handle_cache_failure(_summary, source_url, reason, true) do
    raise "cover cache failed for #{source_url || "unknown source"}: #{reason}"
  end

  defp handle_cache_failure(summary, source_url, reason, false) do
    failure = %{source_url: source_url, reason: reason}

    summary
    |> Map.update!(:failed, &(&1 + 1))
    |> Map.update!(:failures, &[failure | &1])
  end

  def purge_cached_cover!(%CoverAsset{} = asset) do
    deletable_variant_paths = variant_paths(asset.responsive_variants)

    [asset.cached_file_path, asset.thumbnail_file_path | deletable_variant_paths]
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&delete_stored_cover/1)

    [asset.cached_file_path, asset.thumbnail_file_path | deletable_variant_paths]
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn path ->
      if safe_cached_file_path?(path) and File.exists?(path) do
        File.rm!(path)
      end
    end)

    asset
    |> Ash.Changeset.for_update(:update, %{
      cached_file_path: nil,
      thumbnail_file_path: nil,
      responsive_variants: [],
      cached_at: nil
    })
    |> Ash.update!(authorize?: false)
  end

  @doc """
  Returns the object key for a cached file, relative to `priv/static`.

  The key matches the public URL path, for example `covers/cache/<sha>.jpg`.
  """
  @spec object_key(String.t()) :: String.t() | nil
  def object_key(path) when is_binary(path) do
    expanded = Path.expand(path)
    static_root = Path.expand("priv/static")

    if String.starts_with?(expanded, static_root <> "/") do
      Path.relative_to(expanded, static_root)
    end
  end

  def object_key(_path), do: nil

  @doc """
  Returns true for a cache path that is under the cache root and has no symlink
  ancestor. The file itself may be missing, which is the proxy fetch case.
  """
  @spec cache_file_path_safe?(String.t()) :: boolean()
  def cache_file_path_safe?(path) when is_binary(path) do
    expanded = Path.expand(path)
    root = expanded_cache_root()
    relative = Path.relative_to(expanded, root)

    String.starts_with?(expanded, root <> "/") and
      relative not in ["", "."] and
      not String.starts_with?(relative, "..") and
      no_symlink_ancestors?(expanded, root)
  end

  def cache_file_path_safe?(_path), do: false

  @doc """
  Uploads locally cached covers and thumbnails to the configured store.

  Pass `source_urls:` or `provider:` to scope the upload; without options every
  cover asset is considered.
  """
  @spec upload_cached_covers!(keyword()) :: %{
          uploaded: non_neg_integer(),
          failed: non_neg_integer()
        }
  def upload_cached_covers!(opts \\ []) do
    if Store.configured?() do
      source_urls = Keyword.get(opts, :source_urls, :all)
      provider = Keyword.get(opts, :provider)

      CoverAsset
      |> Ash.read!(authorize?: false)
      |> filter_source_urls(source_urls)
      |> filter_provider(provider)
      |> Enum.reduce(%{uploaded: 0, failed: 0}, &upload_asset/2)
    else
      %{uploaded: 0, failed: 0}
    end
  end

  defp upload_asset(asset, summary) do
    [asset.cached_file_path, asset.thumbnail_file_path | variant_paths(asset.responsive_variants)]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(summary, &upload_and_count/2)
  end

  defp upload_and_count(path, summary) do
    case upload_cached_path(path) do
      :ok -> %{summary | uploaded: summary.uploaded + 1}
      :error -> %{summary | failed: summary.failed + 1}
      :skipped -> summary
    end
  end

  defp upload_cached_paths(paths) do
    Enum.each(paths, &upload_cached_path/1)
  end

  defp upload_cached_path(path) when is_binary(path) do
    key = object_key(path)

    cond do
      is_nil(key) ->
        :skipped

      not File.regular?(path) ->
        :skipped

      true ->
        content_type = MIME.from_path(path)

        with {:ok, body} <- File.read(path),
             :ok <- Store.put(key, body, content_type) do
          :ok
        else
          {:error, reason} ->
            Logger.warning("cover upload failed key=#{key}: #{inspect(reason)}")
            :error
        end
    end
  end

  defp upload_cached_path(_path), do: :skipped

  defp delete_stored_cover(path) when is_binary(path) do
    key = object_key(path)

    if is_binary(key) do
      case Store.delete(key) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("cover delete failed key=#{key}: #{inspect(reason)}")
      end
    end
  end

  defp delete_stored_cover(_path), do: :ok

  def cache_path(%CoverAsset{} = asset, cache_root \\ @cache_root) do
    extension = asset.source_url |> URI.parse() |> Map.get(:path) |> extension_from_path()
    Path.join(cache_root, "#{sha256(asset.source_url)}#{extension}")
  end

  def thumbnail_path(%CoverAsset{} = asset, cache_root \\ @cache_root) do
    Path.join(cache_root, "#{sha256(asset.source_url)}-thumb.jpg")
  end

  defp public_cover_map(%CoverAsset{} = cover_asset) do
    %{
      id: cover_asset.id,
      source_url: cover_asset.source_url,
      public_url: public_cover_url(cover_asset),
      provider: cover_asset.provider,
      rights_basis: cover_asset.rights_basis,
      attribution_text: cover_asset.attribution_text,
      attribution_url: cover_asset.attribution_url,
      cache_policy: cover_asset.cache_policy,
      cached_file_path: cover_asset.cached_file_path,
      thumbnail_file_path: cover_asset.thumbnail_file_path,
      thumbnail_url: public_thumbnail_url(cover_asset.thumbnail_file_path),
      responsive_variants: public_variants(cover_asset.responsive_variants)
    }
  end

  defp public_cover_url(%CoverAsset{cache_policy: "cache_allowed", cached_file_path: path})
       when is_binary(path) do
    static_path(path)
  end

  defp public_cover_url(%CoverAsset{}), do: nil

  defp public_thumbnail_url(path) do
    if safe_cached_file_path?(path), do: static_path(path)
  end

  defp public_variants(variants) when is_list(variants) do
    variants
    |> Enum.flat_map(fn variant ->
      path = variant_path(variant)
      url = public_variant_url(path)

      if is_binary(url) do
        [
          %{
            format: variant_value(variant, :format),
            width: variant_value(variant, :width),
            sha256: variant_value(variant, :sha256),
            bytes: variant_value(variant, :bytes),
            url: url
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(&{&1.width, &1.format})
  end

  defp public_variants(_variants), do: []

  defp public_variant_url(path) do
    if safe_cached_file_path?(path), do: static_path(path)
  end

  defp cache_policy_public?(%CoverAsset{cache_policy: "cache_allowed"} = asset),
    do:
      asset.rights_basis == "local_cache_permitted" and
        safe_cached_file_path?(asset.cached_file_path)

  defp cache_policy_public?(_asset), do: false

  defp cache_policy_provenance_valid?(%CoverAsset{cache_policy: "cache_allowed"} = asset),
    do:
      asset.rights_basis == "local_cache_permitted" and
        (not present?(asset.cached_file_path) or safe_cached_file_path?(asset.cached_file_path))

  defp cache_policy_provenance_valid?(_asset), do: false

  defp maybe_generate_thumbnail(source_path, thumbnail_path, thumbnailer, timeout) do
    with true <- safe_cached_file_path?(source_path),
         true <- safe_cache_write_path?(thumbnail_path, expanded_cache_root()),
         {:ok, generated_path} <-
           run_thumbnailer(thumbnailer, source_path, thumbnail_path, timeout),
         true <- safe_cached_file_path?(generated_path) do
      generated_path
    else
      _ -> nil
    end
  end

  defp run_thumbnailer(thumbnailer, source_path, thumbnail_path, timeout)
       when is_function(thumbnailer, 2) do
    task = Task.async(fn -> thumbnailer.(source_path, thumbnail_path) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, generated_path}} when is_binary(generated_path) -> {:ok, generated_path}
      {:ok, generated_path} when is_binary(generated_path) -> {:ok, generated_path}
      _result -> :error
    end
  end

  defp run_thumbnailer(_thumbnailer, _source_path, _thumbnail_path, _timeout), do: :error

  @thumbnail_programs ["magick", "convert"]

  # ImageMagick 7 installs `magick`; Debian's ImageMagick 6 package installs
  # `convert`. Both accept the same resize invocation.
  @doc false
  def thumbnail_command do
    Enum.find_value(@thumbnail_programs, fn program ->
      case System.find_executable(program) do
        nil -> nil
        path -> {program, path}
      end
    end)
  end

  @doc false
  def generate_thumbnail(source_path, thumbnail_path) do
    with {_program, command} when is_binary(command) <- thumbnail_command(),
         timeout when is_binary(timeout) <- System.find_executable("timeout"),
         {_, 0} <-
           System.cmd(
             timeout,
             [
               @thumbnail_command_timeout,
               command,
               source_path,
               "-auto-orient",
               "-thumbnail",
               "400x600>",
               "-strip",
               "-quality",
               "82",
               thumbnail_path
             ],
             stderr_to_stdout: true
           ),
         true <- File.exists?(thumbnail_path) do
      {:ok, thumbnail_path}
    else
      _ -> nil
    end
  end

  @doc """
  Generates the responsive WebP/JPEG variant set for one cached original.

  A variant filename embeds the hash of its own bytes, so the URL changes when
  the rendered image changes and can be cached immutably. ImageMagick is a
  runtime dependency of the release image; when it is unavailable the function
  returns an empty list and the caller keeps the existing cover URLs.
  """
  @spec generate_variants(String.t(), CoverAsset.t(), String.t()) :: [map()]
  def generate_variants(source_path, %CoverAsset{} = asset, cache_root \\ @cache_root) do
    source_hash = sha256(asset.source_url)

    for width <- @variant_widths,
        format <- @variant_formats,
        {:ok, variant} <- [generate_variant(source_path, cache_root, source_hash, width, format)] do
      variant
    end
  end

  defp generate_variant(source_path, cache_root, source_hash, width, format) do
    temporary_path =
      Path.join(
        cache_root,
        "#{source_hash}-#{width}w-#{System.unique_integer([:positive])}.tmp.#{format}"
      )

    try do
      with {_program, command} when is_binary(command) <- thumbnail_command(),
           timeout when is_binary(timeout) <- System.find_executable("timeout"),
           true <- safe_cached_file_path?(source_path),
           true <- safe_cache_write_path?(temporary_path, expanded_cache_root()),
           {_, 0} <-
             System.cmd(
               timeout,
               [
                 @variant_command_timeout,
                 command,
                 source_path,
                 "-auto-orient",
                 "-resize",
                 "#{width}x>",
                 "-strip",
                 "-quality",
                 "82",
                 temporary_path
               ],
               stderr_to_stdout: true
             ),
           {:ok, body} <- File.read(temporary_path),
           content_hash = sha256(body),
           final_path =
             Path.join(cache_root, "#{source_hash}-#{width}w-#{content_hash}.#{format}"),
           :ok <- move_variant(temporary_path, final_path),
           {:ok, stat} <- File.stat(final_path) do
        {:ok,
         %{
           "path" => final_path,
           "format" => format,
           "width" => width,
           "sha256" => content_hash,
           "bytes" => stat.size
         }}
      else
        _ -> nil
      end
    after
      File.rm(temporary_path)
    end
  end

  defp move_variant(temporary_path, final_path) do
    case File.rename(temporary_path, final_path) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_responsive_variants(asset, source_path, cache_root, generator, timeout) do
    variants = maybe_generate_variants(source_path, asset, cache_root, generator, timeout)

    if variants == [] do
      {asset, []}
    else
      updated =
        asset
        |> Ash.Changeset.for_update(:update, %{responsive_variants: variants})
        |> Ash.update!(authorize?: false)

      {updated, variants}
    end
  end

  defp maybe_generate_variants(source_path, asset, cache_root, generator, timeout)
       when is_function(generator, 3) do
    task = Task.async(fn -> generator.(source_path, asset, cache_root) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, variants} when is_list(variants) -> normalize_variants(variants)
      _result -> []
    end
  rescue
    _exception -> []
  end

  defp maybe_generate_variants(_source_path, _asset, _cache_root, _generator, _timeout), do: []

  defp normalize_variants(variants) do
    variants
    |> Enum.flat_map(fn variant ->
      path = variant_value(variant, :path)
      format = variant_value(variant, :format)
      width = variant_value(variant, :width)

      if is_binary(path) and format in @variant_formats and is_integer(width) and width > 0 and
           safe_cached_file_path?(path) do
        [
          %{
            "path" => stored_variant_path(path),
            "format" => format,
            "width" => width,
            "sha256" => variant_value(variant, :sha256) || sha256(File.read!(path)),
            "bytes" => variant_value(variant, :bytes) || File.stat!(path).size
          }
        ]
      else
        []
      end
    end)
    |> Enum.uniq_by(&{&1["width"], &1["format"]})
    |> Enum.sort_by(&{&1["width"], &1["format"]})
  end

  defp stored_variant_path(path) do
    expanded = Path.expand(path)
    cwd = Path.expand(".")

    if String.starts_with?(expanded, cwd <> "/") do
      Path.relative_to(expanded, cwd)
    else
      path
    end
  end

  defp responsive_variants_current?(%CoverAsset{responsive_variants: variants})
       when is_list(variants) and variants != [] do
    present =
      variants
      |> Enum.map(fn variant ->
        {variant_value(variant, :width), variant_value(variant, :format), variant_path(variant)}
      end)
      |> Enum.filter(fn {width, format, path} ->
        is_integer(width) and format in @variant_formats and
          safe_cached_file_path?(path)
      end)
      |> MapSet.new(fn {width, format, _path} -> {width, format} end)

    Enum.all?(for(width <- @variant_widths, format <- @variant_formats, do: {width, format}), fn
      key -> MapSet.member?(present, key)
    end)
  end

  defp responsive_variants_current?(_asset), do: false

  defp missing_responsive_variants?(%CoverAsset{} = asset) do
    not responsive_variants_current?(asset)
  end

  defp variant_paths(variants) when is_list(variants) do
    variants |> Enum.map(&variant_path/1) |> Enum.reject(&is_nil/1)
  end

  defp variant_paths(_variants), do: []

  defp variant_path(variant) when is_map(variant), do: variant_value(variant, :path)
  defp variant_path(_variant), do: nil

  defp variant_value(variant, key) when is_map(variant) do
    Map.get(variant, key) || Map.get(variant, Atom.to_string(key))
  end

  defp variant_value(_variant, _key), do: nil

  @doc "True when a cache path is a content-hashed responsive variant."
  @spec responsive_variant_path?(term()) :: boolean()
  def responsive_variant_path?(path) when is_binary(path) do
    path =~ ~r/-\d+w-[0-9a-f]{64}\.(webp|jpg)$/
  end

  def responsive_variant_path?(_path), do: false

  defp cache_candidate?(%CoverAsset{} = asset) do
    uri = parse_uri(asset.source_url)

    asset.takedown_state == "visible" and asset.cache_policy == "cache_allowed" and
      asset.rights_basis == "local_cache_permitted" and present?(asset.source_url) and
      uri.scheme == "https" and SourcePolicy.cover_host_allowed?(asset.provider, uri.host)
  end

  defp safe_cached_file_path?(path) when is_binary(path) do
    path = Path.expand(path)
    cache_root = expanded_cache_root()

    with true <- String.starts_with?(path, cache_root <> "/"),
         true <- cache_root_directory?(cache_root),
         true <- no_symlink_components?(path, cache_root),
         true <- File.regular?(path) do
      true
    else
      _ -> false
    end
  end

  defp safe_cached_file_path?(_path), do: false

  defp cache_root_directory?(cache_root) do
    case File.lstat(cache_root) do
      {:ok, %{type: :directory}} -> true
      _ -> false
    end
  end

  defp no_symlink_components?(path, cache_root) do
    path
    |> Path.relative_to(cache_root)
    |> Path.split()
    |> Enum.reduce_while(cache_root, fn component, parent ->
      current = Path.join(parent, component)

      case File.lstat(current) do
        {:ok, %{type: :symlink}} -> {:halt, false}
        {:ok, _stat} -> {:cont, current}
        {:error, _reason} -> {:halt, false}
      end
    end)
    |> is_binary()
  end

  defp no_symlink_ancestors?(path, cache_root) do
    path
    |> Path.relative_to(cache_root)
    |> Path.split()
    |> Enum.reduce_while(cache_root, fn component, parent ->
      current = Path.join(parent, component)

      case File.lstat(current) do
        {:ok, %{type: :symlink}} -> {:halt, false}
        {:ok, _stat} -> {:cont, current}
        {:error, _reason} -> {:halt, current}
      end
    end)
    |> Kernel.!=(false)
  end

  defp cached_file_present?(path) when is_binary(path) do
    safe_cached_file_path?(path)
  end

  defp cached_file_present?(_path), do: false

  defp static_path(path) when is_binary(path) do
    path = Path.expand(path)
    static_root = Path.expand("priv/static")

    if String.starts_with?(path, static_root <> "/") do
      "/" <> Path.relative_to(path, static_root)
    end
  end

  defp static_path(_path), do: nil

  defp ensure_safe_cache_root!(cache_root) when is_binary(cache_root) do
    expanded_root = Path.expand(cache_root)
    allowed_root = expanded_cache_root()

    cond do
      expanded_root != allowed_root and
          not String.starts_with?(expanded_root, allowed_root <> "/") ->
        raise ArgumentError,
              "cover cache_root must stay under #{@cache_root}, got: #{cache_root}"

      symlink_path_component?(expanded_root, allowed_root) ->
        raise ArgumentError,
              "cover cache_root must not include symlink path components, got: #{cache_root}"

      true ->
        cache_root
    end
  end

  defp ensure_safe_cache_root!(cache_root) do
    raise ArgumentError, "cover cache_root must be a path string, got: #{inspect(cache_root)}"
  end

  defp verify_safe_cache_root!(cache_root) do
    expanded_root = Path.expand(cache_root)
    allowed_root = expanded_cache_root()

    with true <-
           expanded_root == allowed_root or
             String.starts_with?(expanded_root, allowed_root <> "/"),
         false <- symlink_path_component?(expanded_root, allowed_root),
         {:ok, %{type: :directory}} <- File.lstat(expanded_root) do
      :ok
    else
      _ ->
        raise ArgumentError,
              "cover cache_root must be a non-symlink directory under #{@cache_root}, got: #{cache_root}"
    end
  end

  defp ensure_safe_cache_write_path!(cache_path, cache_root) do
    unless safe_cache_write_path?(cache_path, cache_root) do
      raise ArgumentError,
            "cover cache path must stay under a non-symlink cache_root before writes: #{cache_path}"
    end
  end

  defp safe_cache_write_path?(cache_path, cache_root)
       when is_binary(cache_path) and is_binary(cache_root) do
    expanded_path = Path.expand(cache_path)
    expanded_root = Path.expand(cache_root)

    with true <- String.starts_with?(expanded_path, expanded_root <> "/"),
         false <- symlink_path_component?(Path.dirname(expanded_path), expanded_root),
         false <- symlink_file?(expanded_path) do
      true
    else
      _ -> false
    end
  end

  defp safe_cache_write_path?(_cache_path, _cache_root), do: false

  defp symlink_path_component?(path, root) do
    root = Path.expand(root)

    path
    |> Path.expand()
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reduce_while(root, fn component, parent ->
      current = Path.join(parent, component)

      case File.lstat(current) do
        {:ok, %{type: :symlink}} -> {:halt, true}
        {:ok, _stat} -> {:cont, current}
        {:error, :enoent} -> {:halt, false}
        {:error, _reason} -> {:halt, false}
      end
    end)
    |> Kernel.==(true)
  end

  defp symlink_file?(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> true
      _ -> false
    end
  end

  defp expanded_cache_root, do: Path.expand(@cache_root)

  @doc false
  def req_fetch!(url, req_options, max_body_size, allowed_cover_hosts \\ :all) do
    request_url = encoded_cover_request_url(url)

    req_options =
      req_options
      |> Keyword.put(:decode_body, false)
      |> Keyword.put(:redirect, false)
      |> Keyword.put(:into, bounded_cover_body_collector(max_body_size))

    response =
      request_url
      |> Req.get!(req_options)
      |> maybe_follow_safe_cover_redirect(request_url, req_options, allowed_cover_hosts)

    cond do
      response.status not in 200..299 ->
        raise "cover cache request failed with status #{response.status} for #{url}"

      response.private[:hiraeth_cover_body_too_large?] ->
        received_bytes = response.private[:hiraeth_cover_received_bytes] || 0

        raise "cover cache body size #{received_bytes} exceeds max body size #{max_body_size} for #{url}"

      true ->
        response
        |> put_streamed_cover_body()
        |> validate_fetched_cover!(url, max_body_size)
    end
  end

  defp encoded_cover_request_url(url) when is_binary(url) do
    uri = URI.parse(url)

    uri
    |> Map.put(:path, percent_encode_path(uri.path))
    |> URI.to_string()
  end

  defp percent_encode_path(nil), do: nil

  defp percent_encode_path(path) do
    path
    |> String.split("/", trim: false)
    |> Enum.map_join(
      "/",
      &URI.encode(&1, fn char -> URI.char_unreserved?(char) or char == ?% end)
    )
  end

  defp maybe_follow_safe_cover_redirect(response, request_url, req_options, allowed_cover_hosts),
    do: follow_safe_cover_redirects(response, request_url, req_options, allowed_cover_hosts, 3)

  defp follow_safe_cover_redirects(response, _request_url, _req_options, _allowed_cover_hosts, 0),
    do: response

  defp follow_safe_cover_redirects(
         %Req.Response{status: status} = response,
         request_url,
         req_options,
         allowed_cover_hosts,
         remaining_hops
       )
       when status in 300..399 do
    with [location | _] <- Req.Response.get_header(response, "location"),
         {:ok, redirect_url} <-
           safe_cover_redirect_url(request_url, location, allowed_cover_hosts) do
      redirect_url
      |> Req.get!(req_options)
      |> follow_safe_cover_redirects(
        redirect_url,
        req_options,
        allowed_cover_hosts,
        remaining_hops - 1
      )
    else
      _not_safe_or_not_present -> response
    end
  end

  defp follow_safe_cover_redirects(
         response,
         _request_url,
         _req_options,
         _allowed_cover_hosts,
         _remaining_hops
       ),
       do: response

  defp safe_cover_redirect_url(request_url, location, allowed_cover_hosts) do
    source_uri = URI.parse(request_url)
    target_uri = request_url |> URI.merge(location)

    if safe_cover_redirect?(source_uri.host, target_uri) and
         redirect_host_allowed?(target_uri.host, allowed_cover_hosts) do
      {:ok, URI.to_string(target_uri)}
    else
      :error
    end
  end

  defp safe_cover_redirect?("covers.openlibrary.org", %{
         scheme: "https",
         host: "archive.org",
         path: "/download/" <> _rest
       }),
       do: true

  defp safe_cover_redirect?("covers.openlibrary.org", %{scheme: "https", host: host}),
    do: internet_archive_cover_host?(host)

  defp safe_cover_redirect?("archive.org", %{scheme: "https", host: host}),
    do: internet_archive_cover_host?(host)

  defp safe_cover_redirect?("static1.squarespace.com", %{
         scheme: "https",
         host: "images.squarespace-cdn.com"
       }),
       do: true

  defp safe_cover_redirect?("images.squarespace-cdn.com", %{
         scheme: "https",
         host: "images.squarespace-cdn.com"
       }),
       do: true

  defp safe_cover_redirect?(_source_host, _target_uri), do: false

  defp redirect_host_allowed?(_host, :all), do: true

  defp redirect_host_allowed?(host, allowed_cover_hosts) do
    allowed_hosts = Enum.map(allowed_cover_hosts, &to_string/1)

    Enum.any?(allowed_hosts, &redirect_host_matches?(host, &1)) or
      open_library_redirect_host_allowed?(host, allowed_hosts)
  end

  defp redirect_host_matches?(host, "." <> suffix), do: String.ends_with?(host, "." <> suffix)
  defp redirect_host_matches?(host, allowed_host), do: host == allowed_host

  defp open_library_redirect_host_allowed?(host, allowed_hosts) do
    "covers.openlibrary.org" in allowed_hosts and
      (host == "archive.org" or internet_archive_cover_host?(host))
  end

  defp internet_archive_cover_host?(host) when is_binary(host),
    do: String.ends_with?(host, ".us.archive.org")

  defp internet_archive_cover_host?(_host), do: false

  defp bounded_cover_body_collector(max_body_size) do
    fn {:data, data}, {request, response} ->
      received_bytes = (response.private[:hiraeth_cover_received_bytes] || 0) + byte_size(data)

      private =
        response.private
        |> Map.put(:hiraeth_cover_received_bytes, received_bytes)

      if received_bytes > max_body_size do
        response = %{response | private: Map.put(private, :hiraeth_cover_body_too_large?, true)}
        {:halt, {request, response}}
      else
        private =
          Map.update(private, :hiraeth_cover_body_chunks, [data], fn chunks -> [data | chunks] end)

        {:cont, {request, %{response | private: private}}}
      end
    end
  end

  defp put_streamed_cover_body(%Req.Response{} = response) do
    body =
      response.private
      |> Map.get(:hiraeth_cover_body_chunks, [])
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    %{response | body: body}
  end

  defp validate_fetched_cover!(fetched, url, max_body_size) do
    {body, content_type} = fetched_cover_body_and_content_type(fetched)

    unless is_binary(body) do
      raise "cover cache body for #{url} must be binary raster image bytes"
    end

    body_size = byte_size(body)

    if body_size > max_body_size do
      raise "cover cache body size #{body_size} exceeds max body size #{max_body_size} for #{url}"
    end

    expected_type = validate_content_type!(content_type, url)
    detected_type = validate_raster_magic_bytes!(body, url)

    if expected_type && expected_type != detected_type do
      raise "cover cache content-type #{content_type} does not match raster magic bytes #{detected_type} for #{url}"
    end

    body
  end

  defp fetched_cover_body_and_content_type(%Req.Response{} = response) do
    content_type = response |> Req.Response.get_header("content-type") |> List.first()
    {response.body, content_type}
  end

  defp fetched_cover_body_and_content_type(%{body: body} = fetched) do
    content_type =
      fetched
      |> fetched_content_type()
      |> first_header_value()

    {body, content_type}
  end

  defp fetched_cover_body_and_content_type(body), do: {body, nil}

  defp fetched_content_type(fetched) do
    Map.get(fetched, :content_type) ||
      Map.get(fetched, "content-type") ||
      content_type_from_headers(Map.get(fetched, :headers))
  end

  defp content_type_from_headers(nil), do: nil

  defp content_type_from_headers(headers) when is_map(headers) do
    headers["content-type"] || headers["Content-Type"]
  end

  defp content_type_from_headers(headers) when is_list(headers) do
    headers
    |> Enum.find_value(fn
      {name, value} when is_binary(name) ->
        if String.downcase(name) == "content-type", do: value

      _entry ->
        nil
    end)
  end

  defp content_type_from_headers(_headers), do: nil

  defp first_header_value([value | _rest]), do: value
  defp first_header_value(value), do: value

  defp validate_content_type!(nil, _url), do: nil

  defp validate_content_type!(content_type, url) when is_binary(content_type) do
    normalized =
      content_type
      |> String.split(";", parts: 2)
      |> hd()
      |> String.trim()
      |> String.downcase()

    case Map.fetch(@accepted_content_types, normalized) do
      {:ok, type} ->
        type

      :error ->
        raise "cover cache content-type must be image/jpeg, image/png, image/webp, or image/gif raster image/ bytes for #{url}; got #{content_type}"
    end
  end

  defp validate_content_type!(content_type, url) do
    raise "cover cache content-type must be an image/ raster value for #{url}; got #{inspect(content_type)}"
  end

  defp validate_raster_magic_bytes!(body, url) do
    cond do
      jpeg?(body) -> :jpeg
      png?(body) -> :png
      webp?(body) -> :webp
      gif?(body) -> :gif
      true -> raise "cover cache magic bytes do not identify an accepted raster image for #{url}"
    end
  end

  defp jpeg?(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: true
  defp jpeg?(_body), do: false

  defp png?(<<0x89, ?P, ?N, ?G, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: true
  defp png?(_body), do: false

  defp webp?(<<"RIFF", _size::little-32, "WEBP", _rest::binary>>), do: true
  defp webp?(_body), do: false

  defp gif?(<<"GIF87a", _rest::binary>>), do: true
  defp gif?(<<"GIF89a", _rest::binary>>), do: true
  defp gif?(_body), do: false

  defp extension_from_path(path) when is_binary(path) do
    case path |> Path.extname() |> String.downcase() do
      extension when extension in [".jpg", ".jpeg", ".png", ".webp", ".gif"] -> extension
      _extension -> ".jpg"
    end
  end

  defp extension_from_path(_path), do: ".jpg"

  defp sha256(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp parse_uri(value) when is_binary(value), do: URI.parse(value)
  defp parse_uri(_value), do: %URI{}
end
