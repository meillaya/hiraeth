defmodule Hiraeth.Catalog.PublicWorkProjection do
  @moduledoc """
  Builds and swaps the derived public read model.

  The canonical tables remain the source of truth. This module only assembles
  one public row per work from the already-public book projection, writes the
  rows in one transaction, and records a revision the web tier can watch.
  """

  require Logger

  import Ecto.Query

  alias Hiraeth.Catalog.{PublicProjectionState, PublicWork}
  alias Hiraeth.Oban.PublicProjectionWorker
  alias Hiraeth.Repo
  alias HiraethWeb.PublicCatalog

  @lock_key 0x4849524145544857
  @title_exclusions ~r/subscription|bundle|gift card|gift_card|merch|box set|boxed set/i
  @non_book_formats ~w(bundle subscription gift_card merch supporter_only)

  @type summary :: %{
          revision: String.t() | nil,
          rows: non_neg_integer(),
          status: atom(),
          duration_ms: integer()
        }

  @spec rebuild!(keyword()) :: {:ok, summary()} | {:error, term()}
  def rebuild!(opts \\ []) do
    trigger = Keyword.get(opts, :trigger, "manual")
    started_ms = System.monotonic_time(:millisecond)

    if Keyword.get(opts, :mark_running, true), do: mark_running(trigger)

    result =
      Repo.transaction(
        fn ->
          case Repo.query!("select pg_try_advisory_xact_lock($1)", [@lock_key]) do
            %{rows: [[true]]} -> :ok
            _ -> Repo.rollback(:busy)
          end

          books = PublicCatalog.snapshot_books()
          refreshed_at = DateTime.utc_now()
          build_id = Ecto.UUID.generate()
          rows = Enum.map(books, &row_for(&1, refreshed_at, build_id))

          inserted =
            rows
            |> Enum.chunk_every(500)
            |> Enum.reduce(0, fn chunk, count -> count + insert_rows!(chunk) end)

          {deleted, _} =
            Repo.delete_all(from work in PublicWork, where: work.build_id != ^build_id)

          revision = Ecto.UUID.generate()

          Repo.update_all(
            from(state in PublicProjectionState, where: state.id == 1),
            set: [
              revision: revision,
              status: "ready",
              finished_at: refreshed_at,
              row_count: inserted,
              error: nil,
              trigger: trigger
            ]
          )

          %{
            revision: revision,
            rows: inserted,
            deleted: deleted,
            duration_ms: System.monotonic_time(:millisecond) - started_ms,
            status: :ok
          }
        end,
        timeout: :timer.minutes(5)
      )

    case result do
      {:ok, summary} ->
        Logger.info(
          "public projection ready rows=#{summary.rows} deleted=#{summary.deleted} " <>
            "duration_ms=#{summary.duration_ms} trigger=#{trigger}"
        )

        {:ok, summary}

      {:error, :busy} ->
        Logger.info("public projection skipped: another rebuild holds the lock")
        {:error, :busy}

      {:error, reason} ->
        mark_error(reason)
        Logger.error("public projection failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    exception ->
      mark_error(exception)

      Logger.error(
        "public projection crashed: #{Exception.message(exception)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:error, exception}
  end

  @spec enqueue_safe(String.t()) :: :ok
  def enqueue_safe(trigger \\ "catalog_change") do
    _ = enqueue(trigger)
    :ok
  rescue
    _exception -> :ok
  end

  @spec enqueue(String.t()) :: {:ok, term()} | {:error, term()}
  def enqueue(trigger \\ "catalog_change") do
    %{"trigger" => trigger}
    |> PublicProjectionWorker.new()
    |> Oban.insert()
  end

  @spec state() :: map() | nil
  def state do
    Repo.one(from state in PublicProjectionState, where: state.id == 1)
  end

  defp mark_running(trigger) do
    Repo.update_all(
      from(state in PublicProjectionState, where: state.id == 1),
      set: [
        status: "running",
        started_at: DateTime.utc_now(),
        error: nil,
        trigger: trigger
      ]
    )
  end

  defp mark_error(reason) do
    Repo.update_all(
      from(state in PublicProjectionState, where: state.id == 1),
      set: [status: "error", error: inspect(reason), finished_at: DateTime.utc_now()]
    )
  end

  defp row_for(%Hiraeth.Catalog.PublicProjection.Book{} = book, refreshed_at, build_id) do
    formats = book.formats || []
    format_values = formats |> Enum.map(& &1.format) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    language_values =
      formats |> Enum.map(& &1.language_code) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    language_values =
      Enum.uniq([book.original_language_code | language_values]) |> Enum.reject(&is_nil/1)

    contributors =
      [book.authors, book.translators, Map.values(book.contributors_by_role)]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    contributor_slugs =
      contributors |> Enum.map(& &1.slug) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    contributor_names =
      contributors |> Enum.map(& &1.name) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    role_values = book.contributors_by_role |> Map.keys() |> Enum.sort()

    series_titles = book.series_titles || []
    series_slugs = [book.series_slug] |> Enum.reject(&is_nil/1)

    edition_slugs =
      formats |> Enum.map(& &1.edition_slug) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    identifiers = [book.isbn | book.identifiers] |> Enum.reject(&is_nil/1) |> Enum.uniq()
    imported_at = latest_imported_at(book.sources)
    published_on = book.published_on

    search_text =
      [
        book.title,
        book.subtitle,
        book.publisher,
        Enum.map(book.authors, & &1.name),
        Enum.map(book.translators, & &1.name),
        contributor_names,
        series_titles,
        identifiers
      ]
      |> List.flatten()
      |> Enum.map_join(" ", &to_string/1)
      |> String.downcase()

    %{
      work_id: book.work_id,
      payload: :erlang.term_to_binary(book),
      slug: book.slug,
      title: book.title,
      subtitle: book.subtitle,
      title_sort: String.downcase(book.title || ""),
      author_sort: contributor_names |> Enum.map(&String.downcase/1) |> Enum.min(fn -> nil end),
      publisher_name: book.publisher,
      publisher_slug: book.publisher_slug,
      published_on: published_on,
      publication_year: published_on && published_on.year,
      newest_sort: published_on,
      imported_sort: usec(imported_at),
      is_book: book?(book, format_values),
      has_cover: not is_nil(book.cover),
      format_values: format_values,
      language_values: language_values,
      role_values: role_values,
      contributor_slugs: contributor_slugs,
      contributor_names: contributor_names,
      series_slugs: series_slugs,
      series_titles: series_titles,
      subject_values: book.subjects || [],
      edition_slugs: edition_slugs,
      search_text: search_text,
      refreshed_at: refreshed_at,
      build_id: build_id
    }
  end

  @columns [
    :work_id,
    :payload,
    :slug,
    :title,
    :subtitle,
    :title_sort,
    :author_sort,
    :publisher_name,
    :publisher_slug,
    :published_on,
    :publication_year,
    :newest_sort,
    :imported_sort,
    :is_book,
    :has_cover,
    :format_values,
    :language_values,
    :role_values,
    :contributor_slugs,
    :contributor_names,
    :series_slugs,
    :series_titles,
    :subject_values,
    :edition_slugs,
    :search_text,
    :refreshed_at,
    :build_id
  ]

  @casts %{
    work_id: "::uuid",
    published_on: "::date",
    newest_sort: "::date",
    imported_sort: "::timestamptz",
    refreshed_at: "::timestamptz",
    build_id: "::uuid",
    format_values: "::text[]",
    language_values: "::text[]",
    role_values: "::text[]",
    contributor_slugs: "::text[]",
    contributor_names: "::text[]",
    series_slugs: "::text[]",
    series_titles: "::text[]",
    subject_values: "::text[]",
    edition_slugs: "::text[]"
  }

  defp insert_rows!(rows) do
    width = length(@columns)

    values =
      rows
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {_row, row_index} ->
        placeholders =
          @columns
          |> Enum.with_index()
          |> Enum.map_join(", ", fn {column, column_index} ->
            "$#{row_index * width + column_index + 1}#{Map.get(@casts, column, "")}"
          end)

        "(" <> placeholders <> ")"
      end)

    updates =
      @columns
      |> Enum.reject(&(&1 == :work_id))
      |> Enum.map_join(", ", fn column -> "#{column} = EXCLUDED.#{column}" end)

    sql = """
    INSERT INTO catalog_public_works (#{Enum.join(@columns, ", ")})
    VALUES #{values}
    ON CONFLICT (work_id) DO UPDATE SET #{updates}
    """

    params =
      Enum.flat_map(rows, fn row ->
        Enum.map(@columns, fn
          :work_id -> Ecto.UUID.dump!(row.work_id)
          :build_id -> Ecto.UUID.dump!(row.build_id)
          column -> Map.fetch!(row, column)
        end)
      end)

    Repo.query!(sql, params, timeout: :timer.minutes(2))
    length(rows)
  end

  defp usec(%DateTime{} = value), do: %{value | microsecond: {elem(value.microsecond, 0), 6}}

  defp usec(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> usec()

  defp usec(_value), do: nil

  defp latest_imported_at(sources) do
    sources
    |> Enum.map(& &1.imported_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp book?(%{title: title}, formats) do
    not Regex.match?(@title_exclusions, title || "") and
      Enum.any?(formats, &(&1 not in @non_book_formats))
  end
end
