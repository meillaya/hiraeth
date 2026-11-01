defmodule Hiraeth.Catalog.PublicWorks do
  @moduledoc """
  Reads the derived public-work table.

  Every function here is a pure read of `catalog_public_works`. The full book
  payload is decoded only after paging/filtering, so the browser never joins the
  canonical catalog tables.
  """

  import Ecto.Query

  alias Hiraeth.Catalog.PublicProjection
  alias Hiraeth.Catalog.PublicWork
  alias Hiraeth.Repo

  @page_size 24
  @max_page 10_000
  @series_preview_limit 4

  @type filters :: %{optional(atom() | String.t()) => term()}

  @doc """
  Counts the public works that match the filters without decoding a payload.

  Header counters only need the number; going through `book_page/3` would also
  fetch and decode a page of books that is thrown away.
  """
  @spec count() :: non_neg_integer()
  @spec count(filters() | String.t() | nil) :: non_neg_integer()
  def count(filters \\ nil) do
    filters
    |> normalize_filters()
    |> then(fn normalized -> from(work in PublicWork) |> apply_filters(normalized) end)
    |> Repo.aggregate(:count, :work_id)
  end

  @spec book_page(filters() | String.t() | nil, pos_integer() | String.t(), pos_integer()) ::
          PublicProjection.Page.t(PublicProjection.Book.t())
  def book_page(filters, page, page_size \\ @page_size) do
    filters = normalize_filters(filters)
    requested_page = page |> parse_page() |> max(1) |> min(@max_page)

    query =
      from(work in PublicWork)
      |> apply_filters(filters)
      |> order_for(filters.sort)

    total_count = Repo.aggregate(query, :count, :work_id)
    total_pages = max(ceil_div(max(total_count, 1), page_size), 1)
    current_page = min(requested_page, total_pages)
    offset = (current_page - 1) * page_size

    entries =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&decode!/1)

    PublicProjection.page!(%{
      entries: entries,
      page: current_page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    })
  end

  @spec get(String.t()) :: PublicProjection.Book.t() | nil
  def get(slug) when is_binary(slug) do
    work =
      Repo.one(
        from(work in PublicWork,
          where: work.slug == ^slug or fragment("? = ANY(?)", ^slug, work.edition_slugs),
          limit: 1
        )
      )

    work && decode!(work)
  end

  def get(_slug), do: nil

  @spec books_for_publisher(String.t()) :: [PublicProjection.Book.t()]
  def books_for_publisher(slug) do
    Repo.all(
      from(work in PublicWork,
        where: work.publisher_slug == ^slug,
        order_by: [desc_nulls_last: work.newest_sort, asc: work.title_sort]
      )
    )
    |> Enum.map(&decode!/1)
  end

  @spec publisher_summaries() :: [map()]
  def publisher_summaries do
    samples = cover_samples_by_publisher()

    Enum.map(publisher_options(), fn publisher ->
      Map.merge(publisher, %{
        id: publisher.slug,
        cover_sample: Map.get(samples, publisher.slug)
      })
    end)
  end

  @doc """
  Lists the presses that own public works, without cover samples.

  Filter controls and press counters only need the slug and name; returning the
  directory projection would decode one book payload per press for nothing.
  """
  @spec publisher_options() :: [map()]
  def publisher_options do
    Repo.all(
      from(work in PublicWork,
        where: not is_nil(work.publisher_slug),
        group_by: [work.publisher_slug, work.publisher_name],
        select: %{
          slug: work.publisher_slug,
          name: work.publisher_name,
          editions_count: count(work.work_id)
        }
      )
    )
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  # One cover sample per press. The winning row is chosen in SQL and only those
  # payloads cross the wire; streaming every covered work (the previous shape)
  # moved tens of megabytes for a directory of a few dozen rows.
  defp cover_samples_by_publisher do
    rows =
      Repo.query!("""
      select distinct on (publisher_slug) publisher_slug, work_id::text
      from catalog_public_works
      where has_cover = true and publisher_slug is not null
      order by publisher_slug, published_on desc nulls last, title_sort asc
      """).rows

    books = books_by_work_ids(Enum.map(rows, &List.last/1))

    Map.new(rows, fn [slug, work_id] -> {slug, Map.get(books, work_id)} end)
    |> Map.reject(fn {_slug, book} -> is_nil(book) end)
  end

  @spec publisher_has_editions?(String.t()) :: boolean()
  def publisher_has_editions?(slug) do
    Repo.query!(
      """
      select 1
      from editions e
      join publishers p on p.id = e.publisher_id
      where p.slug = $1
      limit 1
      """,
      [slug]
    ).rows != []
  end

  @spec books_for_series(String.t()) :: [PublicProjection.Book.t()]
  def books_for_series(slug) do
    Repo.all(
      from(work in PublicWork,
        where: fragment("? @> ARRAY[?]::text[]", work.series_slugs, ^slug),
        order_by: [desc_nulls_last: work.newest_sort, asc: work.title_sort]
      )
    )
    |> Enum.map(&decode!/1)
  end

  @spec books_for_contributor(String.t()) :: [PublicProjection.Book.t()]
  def books_for_contributor(slug) do
    Repo.all(
      from(work in PublicWork,
        where: fragment("? @> ARRAY[?]::text[]", work.contributor_slugs, ^slug),
        order_by: [desc_nulls_last: work.newest_sort, asc: work.title_sort]
      )
    )
    |> Enum.map(&decode!/1)
  end

  @spec publisher_summary(String.t()) :: map() | nil
  def publisher_summary(slug) do
    case Repo.query!(
           "select id, name, slug, description from publishers where slug = $1 limit 1",
           [slug]
         ).rows do
      [[id, name, slug, description]] ->
        %{id: id, name: name, slug: slug, description: description}

      _ ->
        nil
    end
  end

  @doc """
  Lists collections with their public book count and preview books.

  Previews are ranked and capped in SQL, so a directory page transfers a
  handful of payloads per collection instead of every work in every collection.
  """
  @spec series_list() :: [map()]
  @spec series_list(pos_integer()) :: [map()]
  def series_list(preview_limit \\ @series_preview_limit) do
    rows = series_rows()

    previews =
      rows
      |> Enum.map(fn [_id, _title, slug, _publisher, _publisher_slug, _unknown] -> slug end)
      |> series_previews(preview_limit)

    Enum.map(rows, fn [id, title, slug, publisher, publisher_slug, unknown_positions] ->
      preview = Map.get(previews, slug, %{books_count: 0, books: []})

      %{
        id: id,
        title: title,
        slug: slug,
        publisher: publisher,
        publisher_slug: publisher_slug,
        unknown_order?: unknown_positions > 0,
        books_count: preview.books_count,
        books: preview.books
      }
    end)
  end

  @doc """
  Returns one collection with every public book it holds.
  """
  @spec series_detail(String.t()) :: map() | nil
  def series_detail(slug) when is_binary(slug) do
    case Enum.find(series_rows(), fn [_id, _title, row_slug | _rest] -> row_slug == slug end) do
      nil ->
        nil

      [id, title, series_slug, publisher, publisher_slug, unknown_positions] ->
        books = books_for_series(series_slug)

        %{
          id: id,
          title: title,
          slug: series_slug,
          publisher: publisher,
          publisher_slug: publisher_slug,
          unknown_order?: unknown_positions > 0,
          books_count: length(books),
          books: books
        }
    end
  end

  def series_detail(_slug), do: nil

  @doc """
  Lists collections that hold at least one public work, without book payloads.
  """
  @spec series_options() :: [map()]
  def series_options do
    Repo.query!("""
    select s.slug, s.title, count(work.work_id) as books_count
    from series s
    left join catalog_public_works work on work.series_slugs @> array[s.slug]::text[]
    group by s.slug, s.title
    having count(work.work_id) > 0
    """).rows
    |> Enum.map(fn [slug, title, books_count] ->
      %{slug: slug, title: title, books_count: books_count}
    end)
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  defp series_rows do
    Repo.query!("""
    select s.id, s.title, s.slug, p.name, p.slug,
           count(sm.id) filter (where sm.position is null) as unknown_positions
    from series s
    left join publishers p on p.id = s.publisher_id
    left join series_memberships sm on sm.series_id = s.id
    group by s.id, s.title, s.slug, p.name, p.slug
    order by lower(s.title)
    """).rows
  end

  # One grouped pass ranks every public work inside its collections and returns
  # the count plus the leading work ids per collection. Only those payloads are
  # decoded afterwards.
  defp series_previews([], _limit), do: %{}

  defp series_previews(slugs, limit) when is_integer(limit) and limit > 0 do
    rows =
      Repo.query!(
        """
        with ranked as (
          select series_slug, work_id,
                 row_number() over (
                   partition by series_slug
                   order by newest_sort desc nulls last, title_sort asc
                 ) as rank
          from catalog_public_works work, unnest(work.series_slugs) as series_slug
          where work.series_slugs && $1::text[]
        )
        select series_slug,
               count(*) as books_count,
               coalesce(
                 array_agg(work_id::text order by rank) filter (where rank <= $2),
                 '{}'::text[]
               ) as preview_work_ids
        from ranked
        group by series_slug
        """,
        [slugs, limit]
      ).rows

    books = books_by_work_ids(Enum.flat_map(rows, &List.last/1) |> Enum.uniq())

    Map.new(rows, fn [slug, books_count, work_ids] ->
      previews =
        work_ids
        |> Enum.map(&Map.get(books, &1))
        |> Enum.reject(&is_nil/1)

      {slug, %{books_count: books_count, books: previews}}
    end)
  end

  defp series_previews(slugs, _limit), do: series_previews(slugs, @series_preview_limit)

  # Fetches only the payload column for the requested works, then decodes each
  # one once. Directory queries resolve a handful of ids at a time.
  defp books_by_work_ids([]), do: %{}

  defp books_by_work_ids(work_ids) do
    Repo.all(
      from(work in PublicWork,
        where: work.work_id in ^work_ids,
        select: %{work_id: work.work_id, payload: work.payload}
      )
    )
    |> Map.new(&{&1.work_id, decode_payload!(&1.payload)})
  end

  @spec home_candidates(pos_integer()) :: [PublicProjection.Book.t()]
  def home_candidates(limit \\ 80) do
    Repo.all(
      from(work in PublicWork,
        where: work.is_book == true and not is_nil(work.published_on),
        order_by: [desc_nulls_last: work.published_on, asc: work.title_sort],
        limit: ^limit
      )
    )
    |> Enum.map(&decode!/1)
  end

  defp filter_query(query, value) do
    term = "%#{escape_like(String.downcase(value))}%"
    normalized = normalize_identifier(value)

    cond do
      not searchable_query?(value) ->
        where(query, [work], false)

      String.length(String.trim(value)) < 3 ->
        # One- and two-character terms cannot use the trigram index. The
        # expression GIN index still answers the full-text half, while an
        # ILIKE substring scan would read the whole table on every keystroke.
        where(
          query,
          [work],
          fragment(
            "to_tsvector('simple', ?) @@ websearch_to_tsquery('simple', ?)",
            work.search_text,
            ^value
          )
        )

      true ->
        where(
          query,
          [work],
          fragment(
            "to_tsvector('simple', ?) @@ websearch_to_tsquery('simple', ?)",
            work.search_text,
            ^value
          ) or
            ilike(work.search_text, ^term) or
            (^normalized != "" and ilike(work.search_text, ^"%#{normalized}%"))
        )
    end
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:q, value}, query when value not in [nil, ""] ->
        filter_query(query, value)

      {:publisher, value}, query when value not in [nil, ""] ->
        needle = String.downcase(value)

        where(
          query,
          [work],
          work.publisher_slug == ^needle or
            ilike(work.publisher_name, ^"%#{escape_like(needle)}%")
        )

      {:role, value}, query when value not in [nil, ""] ->
        where(
          query,
          [work],
          fragment("? @> ARRAY[?]::text[]", work.role_values, ^String.downcase(value))
        )

      {:contributor, value}, query when value not in [nil, ""] ->
        needle = String.downcase(value)

        where(
          query,
          [work],
          fragment("? @> ARRAY[?]::text[]", work.contributor_slugs, ^needle) or
            fragment(
              "array_to_string(?, ' ') ilike ?",
              work.contributor_names,
              ^"%#{escape_like(needle)}%"
            )
        )

      {:format, value}, query when value not in [nil, ""] ->
        where(
          query,
          [work],
          fragment("? @> ARRAY[?]::text[]", work.format_values, ^String.downcase(value))
        )

      {:language, value}, query when value not in [nil, ""] ->
        where(
          query,
          [work],
          fragment("? @> ARRAY[?]::text[]", work.language_values, ^String.downcase(value))
        )

      {:subject, value}, query when value not in [nil, ""] ->
        where(
          query,
          [work],
          fragment("? @> ARRAY[?]::text[]", work.subject_values, ^to_string(value))
        )

      {:series, value}, query when value not in [nil, ""] ->
        needle = String.downcase(value)

        where(
          query,
          [work],
          fragment("? @> ARRAY[?]::text[]", work.series_slugs, ^needle) or
            fragment(
              "array_to_string(?, ' ') ilike ?",
              work.series_titles,
              ^"%#{escape_like(needle)}%"
            )
        )

      {:year, value}, query when value not in [nil, ""] ->
        case Integer.parse(to_string(value)) do
          {year, ""} -> where(query, [work], work.publication_year == ^year)
          _ -> where(query, false)
        end

      _other, query ->
        query
    end)
  end

  defp order_for(query, "title"), do: order_by(query, asc: :title_sort, asc: :slug)

  defp order_for(query, "author"),
    do: order_by(query, asc_nulls_last: :author_sort, asc: :title_sort, asc: :slug)

  defp order_for(query, "recently_added"),
    do: order_by(query, desc_nulls_last: :imported_sort, asc: :title_sort, asc: :slug)

  defp order_for(query, _newest),
    do: order_by(query, desc_nulls_last: :newest_sort, asc: :title_sort, asc: :slug)

  defp normalize_filters(filters) when is_map(filters) do
    %{
      q: value(filters, :q) || value(filters, :query) || "",
      publisher: value(filters, :publisher),
      role: value(filters, :role),
      contributor: value(filters, :contributor),
      format: value(filters, :format),
      language: value(filters, :language),
      subject: value(filters, :subject),
      series: value(filters, :series),
      year: value(filters, :year),
      sort: normalize_sort(value(filters, :sort))
    }
  end

  defp normalize_filters(query), do: normalize_filters(%{q: query})

  defp value(filters, key) do
    case Map.get(filters, key) || Map.get(filters, to_string(key)) do
      value when is_binary(value) -> String.trim(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp normalize_sort(sort) when sort in ["newest", "title", "author", "recently_added"], do: sort
  defp normalize_sort(_sort), do: "newest"

  defp decode!(%PublicWork{payload: payload}), do: decode_payload!(payload)

  defp decode_payload!(payload) when is_binary(payload) do
    payload |> :erlang.binary_to_term() |> PublicProjection.book!()
  rescue
    exception in ArgumentError ->
      reraise RuntimeError,
              "invalid public work payload: #{Exception.message(exception)}",
              __STACKTRACE__
  end

  defp parse_page(page) when is_integer(page), do: page

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> page
      _ -> 1
    end
  end

  defp parse_page(_page), do: 1

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)

  defp searchable_query?(value) do
    Regex.match?(~r/[\p{L}\p{N}]/u, value)
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp normalize_identifier(value) do
    value |> to_string() |> String.replace(~r/[^0-9xX]/, "") |> String.downcase()
  end
end
