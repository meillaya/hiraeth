defmodule HiraethWeb.BrowseLive.Components do
  use HiraethWeb, :html

  alias HiraethWeb.CatalogComponents
  alias HiraethWeb.CatalogFilterParams
  alias HiraethWeb.CatalogText

  def browse_shell(assigns) do
    ~H"""
    <div id="browse-shell">
      <header class="sb-pagehead">
        <p class="sb-kicker">
          The catalogue <span>/</span> {format_count(@pagination.total_count)} records
        </p>
        <div class="sb-pagehead__row">
          <h1>Books</h1>
          <p class="sb-pagehead__intro">
            Every record in the Hiraeth index, from {format_count(length(@publishers))} independent
            literary presses. Filter by press, format, or collection.
          </p>
        </div>
        <p class="sb-pagehead__meta">
          <span><strong>{format_count(@pagination.total_count)}</strong> books</span>
          <span><strong>{format_count(length(@publishers))}</strong> presses</span>
          <span><strong>{format_count(length(@series))}</strong> collections</span>
        </p>
      </header>

      <.filter_tray
        filter_form={@filter_form}
        filters={@filters}
        publishers={@publishers}
        series={@series}
        query={@query}
        view={@view}
      />

      <div class="sb-resultsline">
        <p><strong id="results-count">{format_count(@pagination.total_count)}</strong> books</p>
        <p id="results-range">
          Showing {range_text(@pagination)}
        </p>
      </div>

      <section id="catalog-index" aria-label="Catalogue results">
        <h2 class="visually-hidden">Shelf</h2>

        <%= if @pagination.total_count == 0 do %>
          <div class="sb-empty" id="browse-empty">
            <div id="catalog-empty">
              <h2>No catalog entries match.</h2>
              <p>Adjust the search or choose another shelf.</p>
              <p :if={@query not in [nil, ""]} class="sb-kicker">Current search: {@query}</p>
              <.link navigate={~p"/browse"} class="sb-link">Clear the filters</.link>
            </div>
          </div>
        <% else %>
          <div
            :if={@view == "covers"}
            id="catalog-grid"
            phx-update="stream"
            class="sb-grid"
          >
            <CatalogComponents.sb_book_card
              :for={{dom_id, book} <- @streams.books}
              dom_id={dom_id}
              book={book}
            />
          </div>

          <div :if={@view == "index"} id="catalogue-index" class="sb-index">
            <div class="sb-index__head">
              <span>No.</span>
              <span></span>
              <span>Title</span>
              <span>Press</span>
              <span>Year</span>
              <span>Formats</span>
            </div>
            <div
              :for={{book, index} <- Enum.with_index(@page_books, 1)}
              id={"index-#{book.work_id}"}
              class="sb-index__row"
            >
              <span class="sb-index__no">{number(index)}</span>
              <a
                class="sb-index__thumb"
                href={~p"/books/#{book.slug}"}
                tabindex="-1"
                aria-hidden="true"
              >
                <CatalogComponents.catalog_cover book={book} variant={:thumb} />
              </a>
              <div>
                <a class="sb-index__title" href={~p"/books/#{book.slug}"}>{book.title}</a>
                <span :if={author_line(book)} class="sb-index__author">{author_line(book)}</span>
              </div>
              <span class="sb-index__press">{book.publisher || "Unknown press"}</span>
              <span class="sb-index__year">{book_year(book)}</span>
              <span class="sb-index__formats">{format_summary(book)}</span>
            </div>
          </div>

          <.pager page={@pagination.page} total_pages={@pagination.total_pages} filters={@filters} />
        <% end %>
      </section>
    </div>
    """
  end

  defp filter_tray(assigns) do
    ~H"""
    <.form
      for={@filter_form}
      id="catalog-filter-form"
      phx-change="filter"
      phx-submit="filter"
      class="sb-filter"
      aria-label="Filter the catalogue"
    >
      <input type="hidden" name="filters[role]" value={@filters["role"]} />
      <input type="hidden" name="filters[contributor]" value={@filters["contributor"]} />
      <input type="hidden" name="filters[language]" value={@filters["language"]} />
      <input type="hidden" name="filters[subject]" value={@filters["subject"]} />
      <input type="hidden" name="filters[year]" value={@filters["year"]} />

      <div class="sb-filter__search">
        <label for="browse-search">Search</label>
        <input
          id="browse-search"
          type="search"
          name="filters[q]"
          value={@filters["q"]}
          placeholder="Title, author, press"
          autocomplete="off"
          phx-debounce="300"
        />
        <.link :if={@filters["q"] not in [nil, ""]} navigate={~p"/browse"} class="sb-filter__clear">
          Clear
        </.link>
      </div>

      <div class="sb-filter__controls">
        <div class="sb-control">
          <label for="filter-press">Press</label>
          <select id="filter-press" name="filters[publisher]">
            <option value="" selected={blank?(@filters["publisher"])}>All presses</option>
            <option
              :for={publisher <- @publishers}
              value={publisher.slug}
              selected={@filters["publisher"] == publisher.slug}
            >
              {publisher.name}
            </option>
          </select>
        </div>

        <div class="sb-control">
          <label for="filter-format">Format</label>
          <select id="filter-format" name="filters[format]">
            <option value="" selected={blank?(@filters["format"])}>All formats</option>
            <option value="paperback" selected={@filters["format"] == "paperback"}>Paperback</option>
            <option value="hardcover" selected={@filters["format"] == "hardcover"}>Hardcover</option>
            <option value="ebook" selected={@filters["format"] == "ebook"}>Ebook</option>
            <option value="audiobook" selected={@filters["format"] == "audiobook"}>Audiobook</option>
          </select>
        </div>

        <div class="sb-control">
          <label for="filter-series">Collection</label>
          <select id="filter-series" name="filters[series]">
            <option value="" selected={blank?(@filters["series"])}>All collections</option>
            <option
              :for={series <- @series}
              value={series.slug}
              selected={@filters["series"] == series.slug}
            >
              {series.title}
            </option>
          </select>
        </div>

        <div class="sb-control">
          <label for="filter-sort">Sort</label>
          <select id="filter-sort" name="filters[sort]">
            <option value="newest" selected={default_sort?(@filters["sort"])}>
              Newest first
            </option>
            <option value="title" selected={@filters["sort"] == "title"}>Title A–Z</option>
            <option value="author" selected={@filters["sort"] == "author"}>Author A–Z</option>
            <option value="recently_added" selected={@filters["sort"] == "recently_added"}>
              Recently added
            </option>
          </select>
        </div>

        <div class="sb-control sb-control--view">
          <span>View</span>
          <div class="sb-view" role="group" aria-label="View">
            <button
              type="button"
              phx-click="view"
              phx-value-view="covers"
              aria-pressed={to_string(@view == "covers")}
            >
              Covers
            </button>
            <button
              type="button"
              phx-click="view"
              phx-value-view="index"
              aria-pressed={to_string(@view == "index")}
            >
              Index
            </button>
          </div>
        </div>
      </div>
    </.form>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :filters, :map, required: true

  defp pager(assigns) do
    assigns = assign(assigns, :pages, page_numbers(assigns.page, assigns.total_pages))

    ~H"""
    <nav id="catalog-pagination" class="sb-pager" aria-label="Catalogue pages">
      <.link
        :if={@page > 1}
        navigate={page_path(@filters, @page - 1)}
        class="sb-pager__step"
        id="catalog-prev-page"
      >
        ← Previous
      </.link>
      <span :if={@page == 1} class="sb-pager__step" aria-disabled="true">← Previous</span>

      <div class="sb-pager__pages">
        <span id="catalog-page-count" class="visually-hidden">Page {@page} of {@total_pages}</span>
        <.link
          :for={number <- @pages}
          navigate={page_path(@filters, number)}
          class={["sb-pager__page", number == @page && "is-current"]}
          aria-current={number == @page && "page"}
        >
          {number}
        </.link>
      </div>

      <.link
        :if={@page < @total_pages}
        navigate={page_path(@filters, @page + 1)}
        class="sb-pager__step sb-pager__step--next"
        id="catalog-next-page"
      >
        Next →
      </.link>
      <span
        :if={@page >= @total_pages}
        class="sb-pager__step sb-pager__step--next"
        aria-disabled="true"
      >
        Next →
      </span>
    </nav>
    """
  end

  defp page_numbers(_current, total) when total <= 7, do: Enum.to_list(1..total)

  defp page_numbers(current, total) do
    first = max(1, current - 2)
    last = min(total, first + 4)

    Enum.to_list(first..last)
  end

  defp page_path(filters, page) do
    params =
      filters
      |> Map.put("page", Integer.to_string(page))
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    "/browse?" <> URI.encode_query(params)
  end

  defp range_text(%{page: page, page_size: size, total_count: total}) do
    from = (page - 1) * size + 1
    to = min(page * size, total)
    "#{format_count(from)}–#{format_count(to)} of #{format_count(total)}"
  end

  defp author_line(book) do
    book
    |> Map.get(:authors, [])
    |> Enum.map(& &1[:name])
    |> Enum.reject(fn name -> is_nil(name) or CatalogText.unknown_contributor?(name) end)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      names -> names
    end
  end

  defp book_year(%{published_on: %Date{} = date}), do: to_string(date.year)
  defp book_year(_book), do: "—"

  defp format_summary(book) do
    book
    |> Map.get(:formats, [])
    |> Enum.map(& &1[:format_label])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp number(index) when index < 10, do: "0#{index}"
  defp number(index), do: to_string(index)

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)

  defp blank?(value), do: value in [nil, ""]

  defp default_sort?(value), do: value in [nil, "", "newest"]

  # Kept for callers that still build filter URLs from a params map.
  def filtered_path(base_path, params), do: CatalogFilterParams.filtered_path(base_path, params)
end
