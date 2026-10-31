defmodule HiraethWeb.SearchLive.Components do
  use HiraethWeb, :html

  alias HiraethWeb.CatalogComponents

  attr :form, :any, required: true
  attr :query, :string, required: true
  attr :filters, :map, required: true
  attr :pagination, :map, required: true
  attr :results_count, :integer, required: true
  attr :streams, :map, required: true

  def search_shell(assigns) do
    ~H"""
    <div id="search-shell">
      <header class="sb-pagehead">
        <p class="sb-kicker">The catalogue <span>/</span> search</p>
        <div class="sb-pagehead__row">
          <h1>Search</h1>
          <p class="sb-pagehead__intro">
            Find a title, contributor, translator, press, collection, or ISBN. Results come
            only from sourced catalogue records.
          </p>
        </div>
      </header>

      <section class="sb-filter" aria-label="Search the catalogue">
        <.form for={@form} id="catalog-search-form" phx-change="search" phx-submit="search">
          <div class="sb-filter__search">
            <label for="catalog-search-input">Search</label>
            <input
              id="catalog-search-input"
              type="search"
              name="search[query]"
              value={@query}
              placeholder="Title, author, press, ISBN"
              autocomplete="off"
              phx-debounce="220"
            />
            <.link :if={@query not in [nil, ""]} navigate={~p"/search"} class="sb-filter__clear">
              Clear
            </.link>
          </div>
        </.form>
      </section>

      <.results
        results_count={@results_count}
        query={@query}
        streams={@streams}
        filters={@filters}
        pagination={@pagination}
      />
    </div>
    """
  end

  attr :results_count, :integer, required: true
  attr :query, :string, required: true
  attr :streams, :map, required: true
  attr :filters, :map, required: true
  attr :pagination, :map, required: true

  defp results(assigns) do
    ~H"""
    <section id="search-results">
      <div class="sb-resultsline">
        <p class="sb-kicker">{results_label(@query)}</p>
        <p><span>{format_count(@results_count)} found</span></p>
      </div>

      <%= if @results_count == 0 do %>
        <div class="sb-empty" id="search-empty">
          <h2>No catalog entries match.</h2>
          <p>{empty_message(@query)}</p>
          <.link navigate={~p"/search"} class="sb-link">Clear search</.link>
        </div>
      <% else %>
        <div id="search-results-body" phx-update="stream" class="sb-grid">
          <CatalogComponents.sb_book_card
            :for={{dom_id, book} <- @streams.results}
            dom_id={dom_id}
            book={book}
            id_prefix="search-result"
          />
        </div>

        <CatalogComponents.pagination
          :if={@pagination.total_pages > 1}
          page={@pagination.page}
          total_pages={@pagination.total_pages}
          base_path="/search"
          params={@filters}
        />
      <% end %>
    </section>
    """
  end

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)

  defp results_label(""), do: "Full index"
  defp results_label(query), do: "Results for “#{query}”"

  defp empty_message(""), do: "The catalogue has no sourced records for this filter set."

  defp empty_message(query),
    do:
      "No sourced record matches \"#{query}\". The archive did not fabricate a placeholder record."
end
