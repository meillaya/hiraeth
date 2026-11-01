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

  @type filters :: %{optional(atom() | String.t()) => term()}

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
    Repo.all(
      from(work in PublicWork,
        where: not is_nil(work.publisher_slug),
        group_by: [work.publisher_slug, work.publisher_name],
        select: %{
          id: work.publisher_slug,
          slug: work.publisher_slug,
          name: work.publisher_name,
          editions_count: count(work.work_id)
        },
        order_by: [asc: work.publisher_name]
      )
    )
    |> Enum.map(&add_cover_sample/1)
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

  @spec series_list() :: [map()]
  def series_list do
    Repo.query!("""
    select s.id, s.title, s.slug, p.name, p.slug,
           count(sm.id) filter (where sm.position is null) as unknown_positions
    from series s
    left join publishers p on p.id = s.publisher_id
    left join series_memberships sm on sm.series_id = s.id
    group by s.id, s.title, s.slug, p.name, p.slug
    order by lower(s.title)
    """).rows
    |> Enum.map(fn [id, title, slug, publisher, publisher_slug, unknown_positions] ->
      books = books_for_series(slug)

      %{
        id: id,
        title: title,
        slug: slug,
        publisher: publisher,
        publisher_slug: publisher_slug,
        unknown_order?: unknown_positions > 0,
        books: books
      }
    end)
  end

  @spec series(String.t()) :: map() | nil
  def series(slug) do
    Enum.find(series_list(), &(&1.slug == slug))
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

  defp add_cover_sample(summary) do
    sample =
      Repo.one(
        from(work in PublicWork,
          where: work.publisher_slug == ^summary.slug and work.has_cover == true,
          order_by: [desc_nulls_last: work.published_on, asc: work.title_sort],
          limit: 1
        )
      )

    Map.put(summary, :cover_sample, sample && decode!(sample))
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:q, value}, query when value not in [nil, ""] ->
        term = "%#{escape_like(String.downcase(value))}%"
        normalized = normalize_identifier(value)

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

  defp decode!(%PublicWork{payload: payload}) do
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
