defmodule HiraethWeb.PublicCatalog do
  @moduledoc """
  Public read facade over the materialized `catalog_public_works` read model.

  The module deliberately projects only known persisted fields. It never fills in
  unknown dates, languages, dimensions, page counts, or cover art. The legacy
  canonical-query fallback has been removed; imports and seeds refresh the read
  model through `Hiraeth.Catalog.PublicWorkProjection`.
  """

  alias Hiraeth.Catalog.PublicProjection
  alias Hiraeth.Catalog.PublicWorks
  alias Hiraeth.Covers
  alias Hiraeth.Covers.Policy
  alias Hiraeth.Covers.Store
  alias Hiraeth.RealCatalog.SourcePolicy

  @page_size 24
  @max_page 10_000
  @publisher_group_limit 8
  @home_candidate_limit 80
  @home_spotlight_limit 20
  @home_recent_window_months 18
  @home_title_exclusions "subscription|bundle|gift card|gift_card|merch|box set|boxed set"
  @home_non_book_formats ~w(bundle subscription gift_card merch supporter_only)
  @cache_missing :__hiraeth_public_catalog_cache_missing__
  @default_cache_ttl_ms :timer.seconds(30)
  @undated_sort_value Date.to_gregorian_days(~D[0001-01-01])

  @type book_query :: map() | String.t() | nil
  @type page_param :: pos_integer() | String.t()

  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @spec books() :: [PublicProjection.Book.t()]
  def books do
    book_page(nil, 1).entries
  end

  @doc false
  @spec snapshot_books() :: [PublicProjection.Book.t()]
  def snapshot_books do
    edition_rows("", [])
    |> Enum.map(&edition_projection_from_row/1)
    |> Enum.group_by(& &1.work_id)
    |> Enum.map(fn {_work_id, editions} -> book_projection(editions) end)
  end

  @spec search_books(book_query()) :: [PublicProjection.Book.t()]
  def search_books(query) do
    book_page(query, 1).entries
  end

  @doc """
  Returns the homepage candidate pool: recent or forthcoming books only.

  Subscriptions, bundles, gift cards, and merchandise are products, not books,
  so they never enter the homepage pool. The filter lives here so the hero and
  the random picks share one rule.
  """
  @spec home_candidates() :: [PublicProjection.Book.t()]
  def home_candidates do
    cached({:home_candidates}, fn -> load_home_candidates() end)
  end

  @doc """
  Selects the homepage hero and random recent-or-forthcoming titles.

  The hero is the nearest forthcoming book that has a displayable cover; when
  no forthcoming title exists it falls back to the newest candidate. The other
  titles are sampled per call so each homepage visit differs, excluding the
  hero and preferring books with covers.
  """
  @spec home_selection() :: %{
          spotlight: PublicProjection.Book.t() | nil,
          recent: [PublicProjection.Book.t()]
        }
  @spec home_selection(pos_integer()) :: %{
          spotlight: PublicProjection.Book.t() | nil,
          recent: [PublicProjection.Book.t()]
        }
  def home_selection(limit \\ 4) when is_integer(limit) and limit > 0 do
    spotlight = home_spotlight()

    %{
      spotlight: spotlight,
      recent: home_random_recent(home_candidates(), spotlight, limit)
    }
  end

  @spec book_page(book_query(), page_param()) ::
          PublicProjection.Page.t(PublicProjection.Book.t())
  @spec book_page(book_query(), page_param(), pos_integer()) ::
          PublicProjection.Page.t(PublicProjection.Book.t())
  def book_page(query, page, page_size \\ @page_size) do
    PublicWorks.book_page(query, page, page_size)
  end

  @doc """
  Returns the number of public books matching the filters.
  """
  @spec book_count() :: non_neg_integer()
  @spec book_count(book_query()) :: non_neg_integer()
  def book_count(query \\ nil), do: PublicWorks.count(query)

  @spec book(String.t()) :: PublicProjection.Book.t() | nil
  def book(slug), do: PublicWorks.get(slug)

  defp books_for_work_ids([]), do: []

  defp books_for_work_ids(work_ids) do
    work_order =
      work_ids
      |> Enum.map(&uuid_text/1)
      |> Enum.with_index()
      |> Map.new()

    work_ids
    |> editions_for_work_ids()
    |> Enum.group_by(& &1.work_id)
    |> Enum.map(fn {_work_id, editions} -> book_projection(editions) end)
    |> Enum.sort_by(fn book -> Map.get(work_order, book.work_id, 999_999) end)
  end

  defp load_home_candidates do
    {:ok, %{rows: rows}} =
      Hiraeth.Repo.query(
        """
        select e.work_id
        from editions e
        join works w on w.id = e.work_id
        join source_records sr on sr.edition_id = e.id
        where e.published_on is not null
          and (
            e.published_on > current_date
            or e.published_on >= current_date - make_interval(months => $3::int)
          )
          and w.title !~* $1
          and coalesce(e.format, '') <> all($2::text[])
        group by e.work_id
        order by max(e.published_on) desc, min(w.title)
        limit $4
        """,
        [
          @home_title_exclusions,
          @home_non_book_formats,
          @home_recent_window_months,
          @home_candidate_limit
        ]
      )

    rows
    |> Enum.map(&List.first/1)
    |> books_for_work_ids()
  end

  defp home_spotlight do
    cached({:home_spotlight}, fn -> load_home_spotlight() end)
  end

  defp load_home_spotlight do
    upcoming =
      upcoming_work_ids()
      |> books_for_work_ids()

    Enum.find(upcoming, &displayable_book_cover?/1) ||
      List.first(upcoming) ||
      fallback_spotlight()
  end

  defp upcoming_work_ids do
    {:ok, %{rows: rows}} =
      Hiraeth.Repo.query(
        """
        select e.work_id, min(e.published_on) as upcoming_on
        from editions e
        join works w on w.id = e.work_id
        join source_records sr on sr.edition_id = e.id
        where e.published_on > current_date
          and w.title !~* $1
          and coalesce(e.format, '') <> all($2::text[])
        group by e.work_id
        order by upcoming_on asc, min(w.title)
        limit $3
        """,
        [@home_title_exclusions, @home_non_book_formats, @home_spotlight_limit]
      )

    Enum.map(rows, &List.first/1)
  end

  defp fallback_spotlight do
    candidates = home_candidates()
    Enum.find(candidates, &displayable_book_cover?/1) || List.first(candidates)
  end

  defp home_random_recent(candidates, spotlight, limit) do
    spotlight_work_id = spotlight && spotlight.work_id

    pool =
      Enum.reject(candidates, fn book -> book.work_id == spotlight_work_id end)

    covered = Enum.filter(pool, &displayable_book_cover?/1)
    pool = if length(covered) >= limit, do: covered, else: pool

    pool
    |> Enum.shuffle()
    |> Enum.take(limit)
  end

  defp displayable_book_cover?(%{cover: cover}), do: not is_nil(cover)

  defp editions_for_work_ids(work_ids) do
    edition_rows("where e.work_id = any($1::uuid[])", [work_ids])
    |> Enum.map(&edition_projection_from_row/1)
  end

  defp work_id_for_slug(slug) do
    {:ok, %{rows: rows}} =
      Hiraeth.Repo.query(
        """
        select e.work_id
        from editions e
        join works w on w.id = e.work_id
        where (
            e.slug = $1
            or w.slug = $1
            or regexp_replace(e.slug, '-(paperback|hardcover|ebook|audiobook)-[0-9xX-]+$', '') = $1
          )
          and exists (
            select 1
            from source_records sr
            where sr.edition_id = e.id
          )
        limit 1
        """,
        [slug]
      )

    case rows do
      [[work_id]] -> work_id
      _rows -> nil
    end
  end

  @spec editions() :: [PublicProjection.Edition.t()]
  def editions do
    edition_rows("", [])
    |> Enum.map(&edition_projection_from_row/1)
    |> Enum.sort_by(&publication_date_sort_key/1)
  end

  @spec search_editions(book_query()) :: [PublicProjection.Edition.t()]
  def search_editions(query) do
    editions()
    |> Enum.filter(&matches?(&1, query))
  end

  @spec paginate([entry], page_param()) :: PublicProjection.Page.t(entry) when entry: term()
  @spec paginate([entry], page_param(), pos_integer()) :: PublicProjection.Page.t(entry)
        when entry: term()
  def paginate(items, page, page_size \\ @page_size) do
    total_count = length(items)
    total_pages = max(ceil_div(max(total_count, 1), page_size), 1)
    current_page = page |> parse_page() |> max(1) |> min(@max_page) |> min(total_pages) |> max(1)

    PublicProjection.page!(%{
      entries: Enum.slice(items, (current_page - 1) * page_size, page_size),
      page: current_page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    })
  end

  @spec publishers() :: [PublicProjection.Publisher.t()]
  def publishers do
    cached({:publishers}, fn -> load_publishers() end)
  end

  defp load_publishers do
    PublicWorks.publisher_summaries()
    |> Enum.map(&publisher_summary_projection/1)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp publisher_summary_projection(summary) do
    cover_sample = summary.cover_sample |> cover_sample_for_book()

    PublicProjection.publisher!(%{
      id: uuid_text(summary.id),
      name: summary.name,
      slug: summary.slug,
      description: summary[:description],
      editions: [],
      editions_count: summary.editions_count,
      cover_sample: cover_sample,
      groupings: empty_publisher_groupings()
    })
  end

  @spec publisher(String.t()) :: PublicProjection.Publisher.t() | nil
  def publisher(slug), do: publisher_from_read_model(slug)

  defp publisher_from_read_model(slug) do
    case PublicWorks.publisher_summary(slug) do
      nil ->
        nil

      summary ->
        books = PublicWorks.books_for_publisher(slug)

        cond do
          books == [] and PublicWorks.publisher_has_editions?(slug) ->
            nil

          books == [] ->
            PublicProjection.publisher!(%{
              id: uuid_text(summary.id),
              name: summary.name,
              slug: summary.slug,
              description: summary.description,
              editions: [],
              editions_count: 0,
              cover_sample: nil,
              groupings: empty_publisher_groupings()
            })

          true ->
            cover_sample = books |> Enum.find(& &1.cover) |> cover_sample_for_book()

            publisher =
              PublicProjection.publisher!(%{
                id: uuid_text(summary.id),
                name: summary.name,
                slug: summary.slug,
                description: summary.description,
                editions: [],
                editions_count: length(books),
                cover_sample: cover_sample,
                groupings: publisher_groupings(books)
              })

            %{publisher | editions: books}
        end
    end
  end

  defp cover_sample_for_book(nil), do: nil

  defp cover_sample_for_book(%{cover: cover, title: title}) when not is_nil(cover),
    do: PublicProjection.cover_sample!(%{title: title, cover: cover})

  defp cover_sample_for_book(_book), do: nil

  @spec clear_cache() :: :ok
  def clear_cache do
    __MODULE__
    |> cache_registry_key()
    |> :persistent_term.get([])
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase(cache_registry_key(__MODULE__))
    :ok
  end

  defp cached(key, fun) do
    if public_catalog_cache?() do
      cached_value(cache_key(key), fun)
    else
      fun.()
    end
  end

  defp cached_value(cache_key, fun) do
    now_ms = System.monotonic_time(:millisecond)

    case :persistent_term.get(cache_key, @cache_missing) do
      %{expires_at: expires_at, value: value} when expires_at == :infinity ->
        value

      %{expires_at: expires_at, value: value}
      when is_integer(expires_at) and expires_at > now_ms ->
        value

      _expired_missing_or_legacy_cache ->
        compute_and_cache(cache_key, fun)
    end
  end

  defp compute_and_cache(cache_key, fun) do
    value = fun.()

    # Misses are not cached: an attacker-chosen slug would otherwise add a
    # permanent :persistent_term key for every request.
    if is_nil(value) do
      value
    else
      :persistent_term.put(cache_key, %{expires_at: cache_expires_at(), value: value})
      remember_cache_key(cache_key)
      value
    end
  end

  defp public_catalog_cache? do
    Application.get_env(:hiraeth, :public_catalog_cache, true)
  end

  defp cache_expires_at do
    case Application.get_env(:hiraeth, :public_catalog_cache_ttl_ms, @default_cache_ttl_ms) do
      :infinity ->
        :infinity

      ttl_ms when is_integer(ttl_ms) and ttl_ms > 0 ->
        System.monotonic_time(:millisecond) + ttl_ms

      _zero_or_invalid_ttl ->
        System.monotonic_time(:millisecond)
    end
  end

  defp cache_key(key), do: {__MODULE__, :cache, key}
  defp cache_registry_key(module), do: {module, :cache_keys}

  defp remember_cache_key(cache_key) do
    registry_key = cache_registry_key(__MODULE__)

    cache_keys =
      registry_key
      |> :persistent_term.get([])
      |> List.wrap()

    if cache_key in cache_keys do
      :ok
    else
      :persistent_term.put(registry_key, [cache_key | cache_keys])
    end
  end

  @spec contributors() :: [PublicProjection.ContributorSummary.t()]
  @spec contributors(String.t() | nil) :: [PublicProjection.ContributorSummary.t()]
  def contributors(role \\ nil) do
    role
    |> contributor_summary_rows()
    |> Enum.map(&contributor_summary_from_row/1)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  @spec contributor(String.t()) :: PublicProjection.ContributorSummary.t() | nil
  def contributor(slug) do
    case contributor_summary_by_slug(slug) do
      nil ->
        nil

      contributor ->
        books =
          slug
          |> contributor_work_ids()
          |> books_for_work_ids()

        %{contributor | books: books, books_count: length(books)}
    end
  end

  @doc """
  Returns absolute-path entries for the XML sitemap.

  Book entries carry the read model's last refresh date; index pages have no
  reliable modified date and are emitted without one. Duplicate slugs are
  collapsed so a work with several editions appears once.
  """
  @spec sitemap_entries() :: [%{path: String.t(), lastmod: Date.t() | nil}]
  def sitemap_entries do
    books =
      Hiraeth.Repo.query!("""
      select slug, max(refreshed_at)::date
      from catalog_public_works
      where is_book = true
      group by slug
      order by slug
      """).rows
      |> Enum.map(fn [slug, lastmod] -> %{path: "/books/#{slug}", lastmod: lastmod} end)

    publishers =
      publishers()
      |> Enum.map(&%{path: "/publishers/#{&1.slug}", lastmod: nil})

    series =
      series()
      |> Enum.map(&%{path: "/series/#{&1.slug}", lastmod: nil})

    contributors =
      contributors(nil)
      |> Enum.map(&%{path: "/contributors/#{&1.slug}", lastmod: nil})

    static =
      Enum.map(["/", "/browse", "/publishers", "/series", "/contributors"], fn path ->
        %{path: path, lastmod: nil}
      end)

    (static ++ books ++ publishers ++ series ++ contributors)
    |> Enum.uniq_by(& &1.path)
  end

  @doc """
  Lists collections that hold public books, with up to four preview books each.
  """
  @spec series() :: [PublicProjection.Series.t()]
  def series do
    cached({:series}, fn -> load_series() end)
  end

  defp load_series do
    PublicWorks.series_list()
    |> Enum.filter(&(&1.books != []))
    |> Enum.map(&series_projection_from_read_model(&1, :index))
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  @spec series_with_preview_editions() :: [PublicProjection.Series.t()]
  @spec series_with_preview_editions(pos_integer()) :: [PublicProjection.Series.t()]
  def series_with_preview_editions(limit \\ 4) do
    cached({:series_previews, limit}, fn -> load_series_previews(limit) end)
  end

  defp load_series_previews(limit) do
    PublicWorks.series_list(limit)
    |> Enum.filter(&(&1.books != []))
    |> Enum.map(&series_projection_from_read_model(&1, {:preview, limit}))
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  @spec series_by_slug(String.t()) :: PublicProjection.Series.t() | nil
  def series_by_slug(slug) do
    case PublicWorks.series_detail(slug) do
      nil -> nil
      %{books: []} -> nil
      summary -> series_projection_from_read_model(summary, :detail)
    end
  end

  @doc """
  Returns the collection labels used by filter controls.

  The filter tray needs a slug and a title per collection, not its books.
  """
  @spec series_options() :: [map()]
  def series_options do
    cached({:series_options}, fn -> PublicWorks.series_options() end)
  end

  @doc """
  Returns the press labels used by filter controls and counters.
  """
  @spec publisher_options() :: [map()]
  def publisher_options do
    cached({:publisher_options}, fn -> PublicWorks.publisher_options() end)
  end

  @spec edition(String.t()) :: PublicProjection.Edition.t() | nil
  def edition(slug) do
    case work_id_for_slug(slug) do
      nil ->
        nil

      work_id ->
        work_id
        |> List.wrap()
        |> editions_for_work_ids()
        |> Enum.find(&(&1.slug == slug))
    end
  end

  defp empty_publisher_groupings do
    PublicProjection.groupings!(%{
      formats: [],
      languages: [],
      original_languages: [],
      series: [],
      translations: [],
      contributor_roles: []
    })
  end

  defp publisher_groupings(books) do
    PublicProjection.groupings!(%{
      formats: publisher_format_groupings(books),
      languages: publisher_language_groupings(books),
      original_languages: edition_count_group(books, & &1.original_language_code),
      series: publisher_series_groupings(books),
      translations: publisher_translation_groupings(books),
      contributor_roles: publisher_contributor_role_groupings(books)
    })
  end

  defp publisher_format_groupings(books) do
    books
    |> Enum.flat_map(&Map.get(&1, :formats, []))
    |> Enum.map(&format_label(&1.format))
    |> Enum.reject(&blank?/1)
    |> bounded_count_group()
  end

  defp publisher_language_groupings(books) do
    books
    |> Enum.flat_map(&Map.get(&1, :formats, []))
    |> Enum.map(& &1.language_code)
    |> Enum.reject(&blank?/1)
    |> bounded_count_group()
  end

  defp edition_count_group(editions, value_fun) do
    editions
    |> Enum.map(value_fun)
    |> Enum.reject(&blank?/1)
    |> bounded_count_group()
  end

  defp publisher_series_groupings(editions) do
    editions
    |> Enum.flat_map(&publisher_series_rows/1)
    |> Enum.reject(fn {title, _slug, _work_id} -> blank?(title) end)
    |> group_series_by_title_and_slug()
    |> Enum.map(&series_group_summary/1)
    |> sort_and_bound_groups()
  end

  defp publisher_series_rows(edition) do
    edition.series_titles
    |> Enum.with_index()
    |> Enum.map(fn {title, index} ->
      slug = if index == 0, do: edition.series_slug
      {title, slug, edition.work_id}
    end)
  end

  defp group_series_by_title_and_slug(rows) do
    Enum.group_by(
      rows,
      fn {title, slug, _work_id} -> {title, slug} end,
      fn {_title, _slug, work_id} -> work_id end
    )
  end

  defp series_group_summary({{title, slug}, work_ids}) do
    PublicProjection.grouping!(%{
      label: title,
      slug: slug,
      count: work_ids |> Enum.uniq() |> length()
    })
  end

  defp publisher_translation_groupings(editions) do
    editions
    |> Enum.filter(&translated_edition?/1)
    |> Enum.map(fn edition ->
      language_codes = edition_language_codes(edition)

      cond do
        present?(edition.original_language_code) and language_codes != [] ->
          edition_language = List.first(language_codes)
          "#{edition.original_language_code} → #{edition_language}"

        present?(edition.original_language_code) ->
          "from #{edition.original_language_code}"

        language_codes != [] ->
          "translated into #{List.first(language_codes)}"

        true ->
          "translated works"
      end
    end)
    |> bounded_count_group()
  end

  defp translated_edition?(edition) do
    language_codes = edition_language_codes(edition)

    (map_size(edition.contributors_by_role || %{}) > 0 and
       Map.has_key?(edition.contributors_by_role || %{}, "translator")) or
      (present?(edition.original_language_code) and
         Enum.any?(language_codes, &(&1 != edition.original_language_code)))
  end

  defp edition_language_codes(edition) do
    edition
    |> Map.get(:formats, [])
    |> Enum.map(& &1.language_code)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
  end

  defp publisher_contributor_role_groupings(editions) do
    editions
    |> Enum.flat_map(&contributor_role_pairs/1)
    |> Enum.reject(fn {role, contributor_key} -> blank?(role) or blank?(contributor_key) end)
    |> group_contributor_roles_by_role()
    |> Enum.map(&contributor_role_summary/1)
    |> sort_and_bound_groups()
  end

  defp contributor_role_pairs(edition) do
    edition.contributors_by_role
    |> Enum.flat_map(fn {role, contributors} ->
      Enum.map(contributors, fn contributor -> {role, contributor.slug || contributor.name} end)
    end)
  end

  defp group_contributor_roles_by_role(rows) do
    Enum.group_by(
      rows,
      fn {role, _contributor_key} -> role end,
      fn {_role, contributor_key} -> contributor_key end
    )
  end

  defp contributor_role_summary({role, contributor_keys}) do
    PublicProjection.grouping!(%{label: role, count: contributor_keys |> Enum.uniq() |> length()})
  end

  defp bounded_count_group(values) do
    values
    |> Enum.group_by(& &1)
    |> Enum.map(fn {value, entries} ->
      PublicProjection.grouping!(%{label: value, count: length(entries)})
    end)
    |> sort_and_bound_groups()
  end

  defp sort_and_bound_groups(groups) do
    groups
    |> Enum.sort_by(&{-&1.count, String.downcase(to_string(&1.label))})
    |> Enum.take(@publisher_group_limit)
  end

  defp contributor_summary_rows(role) do
    {where, params} = contributor_role_where(role)
    where = exclude_placeholder_contributors(where)

    {:ok, %{rows: rows}} =
      Hiraeth.Repo.query(
        """
        select
          ct.id,
          ct.display_name,
          ct.slug,
          coalesce(jsonb_agg(distinct c.role) filter (where c.role is not null), '[]'::jsonb),
          count(distinct e.work_id) as books_count
        from contributors ct
        join contributions c on c.contributor_id = ct.id
        join editions e on e.work_id = c.work_id or e.id = c.edition_id
        join source_records sr on sr.edition_id = e.id
        #{where}
        group by ct.id, ct.display_name, ct.slug
        """,
        params
      )

    rows
  end

  defp contributor_summary_by_slug(slug) do
    {:ok, %{rows: rows}} =
      Hiraeth.Repo.query(
        """
        select
          ct.id,
          ct.display_name,
          ct.slug,
          coalesce(jsonb_agg(distinct c.role) filter (where c.role is not null), '[]'::jsonb),
          count(distinct e.work_id) as books_count
        from contributors ct
        join contributions c on c.contributor_id = ct.id
        join editions e on e.work_id = c.work_id or e.id = c.edition_id
        join source_records sr on sr.edition_id = e.id
        where ct.slug = $1
          and ct.display_name not in ('Unknown contributor', 'Unknown author')
        group by ct.id, ct.display_name, ct.slug
        limit 1
        """,
        [slug]
      )

    rows |> List.first() |> then(&(&1 && contributor_summary_from_row(&1)))
  end

  defp contributor_work_ids(slug) do
    {:ok, %{rows: rows}} =
      Hiraeth.Repo.query(
        """
        select e.work_id
        from contributors ct
        join contributions c on c.contributor_id = ct.id
        join editions e on e.work_id = c.work_id or e.id = c.edition_id
        join source_records sr on sr.edition_id = e.id
        where ct.slug = $1
          and ct.display_name not in ('Unknown contributor', 'Unknown author')
        group by e.work_id
        order by max(e.published_on) desc nulls last, min(lower(e.title)), min(e.slug)
        """,
        [slug]
      )

    Enum.map(rows, fn [work_id] -> work_id end)
  end

  defp exclude_placeholder_contributors("") do
    "where ct.display_name not in ('Unknown contributor', 'Unknown author')"
  end

  defp exclude_placeholder_contributors(where) do
    where <> " and ct.display_name not in ('Unknown contributor', 'Unknown author')"
  end

  defp contributor_role_where(role) do
    case normalize_contributor_role(role) do
      nil -> {"", []}
      role -> {"where c.role = $1", [role]}
    end
  end

  defp normalize_contributor_role(role) when role in [nil, ""], do: nil

  defp normalize_contributor_role(role) do
    case normalize_text(role) do
      role when role in ["author", "translator"] -> role
      _other -> "__none__"
    end
  end

  defp contributor_summary_from_row([id, display_name, slug, roles, books_count]) do
    PublicProjection.contributor_summary!(%{
      id: uuid_text(id),
      name: display_name,
      display_name: display_name,
      slug: slug,
      roles: Enum.sort(roles || []),
      books: [],
      books_count: books_count
    })
  end

  defp series_projection_from_read_model(summary, mode) do
    books = List.wrap(summary.books)
    books_count = summary[:books_count] || length(books)

    {editions, preview_editions} =
      case mode do
        {:preview, limit} -> {[], Enum.take(books, limit)}
        :detail -> {books, []}
        :index -> {[], Enum.take(books, 4)}
      end

    series =
      PublicProjection.series!(%{
        id: uuid_text(summary.id),
        title: summary.title,
        name: summary.title,
        slug: summary.slug,
        publisher: summary.publisher,
        publisher_slug: summary.publisher_slug,
        editions_count: books_count,
        unknown_order?: summary.unknown_order?,
        editions: [],
        memberships: [],
        preview_editions: preview_editions
      })

    if mode == :detail, do: %{series | editions: editions}, else: series
  end

  defp edition_rows(where_sql, params) do
    {:ok, %{rows: rows}} =
      Hiraeth.Repo.query(
        """
        select
          e.id,
          e.work_id,
          e.title,
          e.subtitle,
          e.slug,
          e.format,
          e.published_on,
          p.name,
          p.slug,
          w.description,
          w.editorial_praise,
          w.storefront_url,
          w.original_title,
          w.original_language_code,
          w.subjects,
          e.language_code,
          e.page_count,
          e.height_mm,
          e.width_mm,
          e.depth_mm,
          coalesce(identifiers.data, '[]'::jsonb),
          coalesce(contributors.data, '[]'::jsonb),
          coalesce(series.data, '[]'::jsonb),
          coalesce(covers.data, '[]'::jsonb),
          source.data
        from editions e
        join works w on w.id = e.work_id
        join publishers p on p.id = e.publisher_id
        join lateral (
          select jsonb_agg(i.value order by i.value) as data
          from identifiers i
          where i.edition_id = e.id and i.identifier_type = 'isbn_13'
        ) identifiers on true
        join lateral (
          select jsonb_build_object(
            'id', sr.id,
            'source_record_id', sr.id,
            'provider', sr.provider,
            'source_type', sr.source_type,
            'source_uri', sr.source_uri,
            'license_note', sr.license_note,
            'import_run_id', sr.import_run_id,
            'imported_at', sr.imported_at,
            'field_sources', sr.raw_payload->'field_sources',
            'provider_permissions', sr.raw_payload->'provider_permissions',
            'source_identity', coalesce(sr.source_identity, sr.raw_payload->>'source_identity'),
            'review_links', sr.raw_payload->'review_links',
            'missing_fields', sr.raw_payload->'missing_fields'
          ) as data
          from source_records sr
          where sr.edition_id = e.id
          order by sr.imported_at desc nulls last, sr.id
          limit 1
        ) source on true
        left join lateral (
          select jsonb_agg(
            jsonb_build_object(
              'id', ct.id,
              'contribution_id', c.id,
              'position', c.position,
              'role', c.role,
              'name', ct.display_name,
              'slug', ct.slug
            )
            order by coalesce(c.position, 0), c.role, c.id
          ) as data
          from contributions c
          join contributors ct on ct.id = c.contributor_id
          where c.work_id = e.work_id or c.edition_id = e.id
        ) contributors on true
        left join lateral (
          select jsonb_agg(
            jsonb_build_object(
              'id', sm.id,
              'position', sm.position,
              'title', s.title,
              'slug', s.slug
            )
            order by coalesce(sm.position, 0), sm.id
          ) as data
          from series_memberships sm
          join series s on s.id = sm.series_id
          where sm.work_id = e.work_id
        ) series on true
        left join lateral (
          select jsonb_agg(
            jsonb_build_object(
              'id', ca.id,
              'position', ca.position,
              'visible?', ca."visible?",
              'source_url', cover.source_url,
              'provider', cover.provider,
              'rights_basis', cover.rights_basis,
              'attribution_text', cover.attribution_text,
              'attribution_url', cover.attribution_url,
              'cache_policy', cover.cache_policy,
              'cached_file_path', cover.cached_file_path,
              'thumbnail_file_path', cover.thumbnail_file_path,
              'responsive_variants', cover.responsive_variants,
              'takedown_state', cover.takedown_state
            )
            order by coalesce(ca.position, 0), ca.id
          ) as data
          from cover_assignments ca
          join cover_assets cover on cover.id = ca.cover_asset_id
          where ca.edition_id = e.id
        ) covers on true
        #{where_sql}
        """,
        params
      )

    rows
  end

  defp edition_projection_from_row([
         id,
         work_id,
         title,
         subtitle,
         slug,
         format,
         published_on,
         publisher,
         publisher_slug,
         description,
         editorial_praise,
         storefront_url,
         original_title,
         original_language_code,
         subjects,
         language_code,
         page_count,
         height_mm,
         width_mm,
         depth_mm,
         identifiers,
         contributors,
         series,
         covers,
         source
       ]) do
    identifiers = Enum.sort(identifiers || [])
    contributors = contributors || []
    contributors_by_role = contributors_by_role_from_data(contributors)
    series = series || []
    cover = covers |> public_cover_data() |> cover_projection_from_data()

    PublicProjection.edition!(%{
      id: uuid_text(id),
      work_id: uuid_text(work_id),
      title: title,
      subtitle: subtitle,
      slug: slug,
      format: format,
      published_on: published_on,
      year: published_on && published_on.year,
      publisher: publisher,
      publisher_slug: publisher_slug,
      author: contributor_text_from_data(contributors),
      authors: Map.get(contributors_by_role, "author", []),
      translators: Map.get(contributors_by_role, "translator", []),
      contributors_by_role: contributors_by_role,
      contributor_names: contributor_names_from_data(contributors),
      identifiers: identifiers,
      isbn: List.first(identifiers),
      series_titles: series_titles_from_data(series),
      series_slug: first_series_slug_from_data(series),
      cover: cover,
      description: description,
      editorial_praise: editorial_praise || [],
      storefront_url: storefront_url,
      original_title: original_title,
      original_language_code: original_language_code,
      subjects: subjects || [],
      language_code: language_code,
      page_count: page_count,
      height_mm: height_mm,
      width_mm: width_mm,
      depth_mm: depth_mm,
      dimensions: dimensions_projection(height_mm, width_mm, depth_mm),
      source: atomize_source(source),
      source_uri: source && source["source_uri"],
      review_links: source_review_links(source),
      missing_fields: source_missing_fields(source)
    })
  end

  defp book_projection(editions) do
    editions = Enum.sort_by(editions, &format_sort_key/1)
    primary = List.first(editions)
    latest_published_on = latest_published_on(editions)

    %{}
    |> Map.merge(
      Map.take(primary, [
        :work_id,
        :title,
        :subtitle,
        :publisher,
        :publisher_slug,
        :author,
        :authors,
        :translators,
        :contributors_by_role,
        :contributor_names,
        :series_titles,
        :series_slug,
        :source,
        :original_title,
        :original_language_code,
        :subjects
      ])
    )
    |> Map.put(:id, primary.work_id)
    |> Map.put(:slug, work_slug(primary))
    |> Map.put(:cover, book_cover(editions))
    |> Map.put(:description, first_present(editions, :description))
    |> Map.put(:editorial_praise, first_present(editions, :editorial_praise) || [])
    |> Map.put(:praise, first_present(editions, :editorial_praise) || [])
    |> Map.put(:storefront_url, first_present(editions, :storefront_url))
    |> Map.put(:review_links, first_present(editions, :review_links) || [])
    |> Map.put(:missing_fields, merge_missing_fields(editions))
    |> Map.put(:formats, Enum.map(editions, &format_projection/1))
    |> Map.put(
      :identifiers,
      editions |> Enum.flat_map(& &1.identifiers) |> Enum.uniq() |> Enum.sort()
    )
    |> Map.put(:isbn, editions |> Enum.flat_map(& &1.identifiers) |> Enum.uniq() |> List.first())
    |> Map.put(:sources, editions |> Enum.map(& &1.source) |> Enum.reject(&is_nil/1))
    |> Map.put(:published_on, latest_published_on)
    |> Map.put(:year, latest_published_on && latest_published_on.year)
    |> PublicProjection.book!()
  end

  defp latest_published_on(editions) do
    editions
    |> Enum.map(& &1.published_on)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(Date, fn -> nil end)
  end

  # Books are represented by their oldest paperback for stable metadata; the
  # cover decision lives in Hiraeth.Covers.Policy so every public read agrees.
  defp book_cover(editions), do: Policy.cover_edition(editions)

  defp format_projection(edition) do
    PublicProjection.format!(%{
      edition_slug: edition.slug,
      format: edition.format,
      format_label: format_label(edition.format),
      identifiers: edition.identifiers,
      source_identity:
        if(edition.identifiers == [],
          do: (edition.source && edition.source.source_identity) || edition.slug,
          else: nil
        ),
      published_on: edition.published_on,
      language_code: edition.language_code,
      page_count: edition.page_count,
      height_mm: edition.height_mm,
      width_mm: edition.width_mm,
      depth_mm: edition.depth_mm,
      dimensions: edition.dimensions
    })
  end

  defp dimensions_projection(nil, nil, nil), do: nil

  defp dimensions_projection(height_mm, width_mm, depth_mm) do
    PublicProjection.dimensions!(%{
      height_mm: height_mm,
      width_mm: width_mm,
      depth_mm: depth_mm
    })
  end

  defp source_review_links(source) when is_map(source), do: source["review_links"] || []
  defp source_review_links(_source), do: []

  defp source_missing_fields(source) when is_map(source), do: source["missing_fields"] || %{}
  defp source_missing_fields(_source), do: %{}

  defp merge_missing_fields(editions) do
    editions
    |> Enum.map(&Map.get(&1, :missing_fields, %{}))
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  defp first_present(editions, key) do
    editions
    |> Enum.map(&Map.get(&1, key))
    |> Enum.find(&(not blank?(&1)))
  end

  defp work_slug(edition) do
    edition.slug
    |> String.replace(~r/-(paperback|hardcover|ebook|audiobook)-[0-9xX-]+$/, "")
  end

  defp format_label(nil), do: "Unknown format"

  defp format_label(format) do
    format
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_sort_key(edition),
    do: {format_rank(edition.format), edition.published_on || ~D[9999-12-31], edition.slug}

  defp format_rank("paperback"), do: 0
  defp format_rank("hardcover"), do: 1
  defp format_rank("ebook"), do: 2
  defp format_rank("audiobook"), do: 3
  defp format_rank(_format), do: 9

  defp cover_projection_from_data(nil), do: nil

  defp cover_projection_from_data(asset) do
    PublicProjection.cover!(%{
      source_url: asset["source_url"],
      public_url: cover_public_url_from_data(asset),
      provider: asset["provider"],
      rights_basis: asset["rights_basis"],
      attribution_text: asset["attribution_text"],
      attribution_url: asset["attribution_url"],
      cache_policy: asset["cache_policy"],
      takedown_state: asset["takedown_state"],
      cached_file_path: asset["cached_file_path"],
      thumbnail_file_path: asset["thumbnail_file_path"],
      thumbnail_url: thumbnail_url_from_data(asset["thumbnail_file_path"]),
      responsive_variants: responsive_variants_from_data(asset["responsive_variants"])
    })
  end

  defp responsive_variants_from_data(variants) when is_list(variants) do
    variants
    |> Enum.flat_map(fn variant ->
      path = variant["path"]
      url = if cached_file_available?(path), do: static_cover_path(path)

      if is_binary(url) do
        [
          %{
            format: variant["format"],
            width: variant["width"],
            sha256: variant["sha256"],
            bytes: variant["bytes"],
            url: url
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(&{&1.width, &1.format})
  end

  defp responsive_variants_from_data(_variants), do: []

  defp cover_public_url_from_data(%{
         "cache_policy" => "cache_allowed",
         "cached_file_path" => path
       })
       when is_binary(path) do
    static_cover_path(path)
  end

  defp cover_public_url_from_data(_asset), do: nil

  defp thumbnail_url_from_data(path) do
    if cached_file_available?(path), do: static_cover_path(path)
  end

  defp public_cover_data(covers) do
    covers
    |> Enum.filter(&public_cover_data?/1)
    |> Enum.sort_by(&{&1["position"] || 0, &1["id"]})
    |> List.first()
  end

  defp public_cover_data?(asset) do
    uri = parse_uri(asset["source_url"])

    truthy?(asset["visible?"]) and asset["takedown_state"] == "visible" and
      present?(asset["source_url"]) and present?(asset["provider"]) and
      present?(asset["rights_basis"]) and uri.scheme == "https" and
      SourcePolicy.cover_host_allowed?(asset["provider"], uri.host) and
      public_cache_policy_data?(asset)
  end

  defp public_cache_policy_data?(%{
         "cache_policy" => "cache_allowed",
         "rights_basis" => "local_cache_permitted",
         "cached_file_path" => path
       }) do
    cached_file_available?(path)
  end

  defp public_cache_policy_data?(_asset), do: false

  # With a durable object store the local file is only a cache. A cold node
  # must still emit the same-origin URL so the proxy can refill it. Local-only
  # mode keeps requiring the file so a missing cache entry becomes a fallback.
  defp cached_file_available?(path) do
    safe_cached_file_path?(path) or
      (Store.configured?() and Covers.cache_file_path_safe?(path))
  end

  defp static_cover_path(path) when is_binary(path) do
    path = Path.expand(path)
    static_root = Path.expand("priv/static")

    if String.starts_with?(path, static_root <> "/") do
      "/" <> Path.relative_to(path, static_root)
    end
  end

  defp static_cover_path(_path), do: nil

  defp contributor_names_from_data(contributors) do
    contributors
    |> Enum.sort_by(&{&1["position"] || 0, &1["role"], &1["id"]})
    |> Enum.map(& &1["name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp contributor_text_from_data(contributors) do
    case contributor_names_from_data(contributors) do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end

  defp contributors_by_role_from_data(contributors) do
    contributors
    |> Enum.sort_by(&{&1["position"] || 0, &1["role"], &1["id"]})
    |> Enum.reduce(%{}, fn contributor, grouped ->
      role = contributor["role"] || "contributor"

      entry =
        PublicProjection.contributor!(%{
          id: uuid_text(contributor["id"]),
          name: contributor["name"],
          slug: contributor["slug"],
          role: role,
          position: contributor["position"]
        })

      Map.update(grouped, role, [entry], &(&1 ++ [entry]))
    end)
    |> Map.new(fn {role, entries} ->
      {role, Enum.uniq_by(entries, &{&1.name, &1.slug, &1.role})}
    end)
  end

  defp series_titles_from_data(series) do
    series
    |> Enum.sort_by(&{&1["position"] || 0, &1["id"]})
    |> Enum.map(& &1["title"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp first_series_slug_from_data(series) do
    series
    |> Enum.sort_by(&{&1["position"] || 0, &1["id"]})
    |> Enum.map(& &1["slug"])
    |> Enum.reject(&is_nil/1)
    |> List.first()
  end

  defp matches?(_edition, nil), do: true
  defp matches?(_edition, ""), do: true

  defp matches?(edition, query) do
    needle = normalize_text(query)
    identifier_needle = normalize_identifier(query)

    searchable_text =
      [
        edition.title,
        edition.subtitle,
        edition.publisher,
        edition.author,
        edition.series_titles,
        edition.identifiers
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(" ", &to_string/1)
      |> normalize_text()

    searchable_identifiers = Enum.map_join(edition.identifiers, " ", &normalize_identifier/1)

    String.contains?(searchable_text, needle) or
      (identifier_needle != "" and String.contains?(searchable_identifiers, identifier_needle))
  end

  defp publication_date_sort_key(edition) do
    published_rank =
      case edition.published_on do
        %Date{} = date -> -Date.to_gregorian_days(date)
        _missing -> -@undated_sort_value
      end

    {published_rank, String.downcase(edition.title || ""), edition.slug}
  end

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)

  defp parse_page(page) when is_integer(page), do: page

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> page
      _ -> 1
    end
  end

  defp parse_page(_page), do: 1

  defp blank?(value), do: value in [nil, [], ""]

  defp atomize_source(nil), do: nil

  defp atomize_source(source) do
    PublicProjection.source!(%{
      id: uuid_text(source["id"]),
      source_record_id: uuid_text(source["source_record_id"]),
      provider: source["provider"],
      source_type: source["source_type"],
      source_uri: source["source_uri"],
      source_identity: source["source_identity"],
      license_note: source["license_note"],
      import_run_id: source["import_run_id"],
      imported_at: parse_imported_at(source["imported_at"]),
      field_sources: source["field_sources"] || %{},
      provider_permissions: source["provider_permissions"] || %{}
    })
  end

  defp parse_imported_at(%DateTime{} = value), do: value
  defp parse_imported_at(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")

  defp parse_imported_at(value) when is_binary(value) do
    with {:error, _reason} <- DateTime.from_iso8601(value),
         {:ok, naive} <- NaiveDateTime.from_iso8601(value) do
      DateTime.from_naive!(naive, "Etc/UTC")
    else
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp parse_imported_at(_value), do: nil

  defp safe_cached_file_path?(path) when is_binary(path) do
    path = Path.expand(path)
    cache_root = Path.expand("priv/static/covers/cache")

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

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp parse_uri(value) when is_binary(value), do: URI.parse(value)
  defp parse_uri(_value), do: %URI{}

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false

  defp uuid_text(value) when is_binary(value) and byte_size(value) == 16 do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp uuid_text(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp uuid_text(value), do: value

  defp normalize_text(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_identifier(value) do
    value
    |> to_string()
    |> String.replace(~r/[^0-9xX]/, "")
    |> String.downcase()
  end
end
