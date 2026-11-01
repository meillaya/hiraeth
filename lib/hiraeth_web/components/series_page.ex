defmodule HiraethWeb.SeriesPage do
  @moduledoc "Server-rendered collection detail body."

  use HiraethWeb, :html

  alias HiraethWeb.CatalogComponents

  attr :series, :map, required: true

  def series_detail(assigns) do
    ~H"""
    <div id="series-detail-shell">
      <header class="sb-pagehead">
        <p class="sb-kicker">Collection <span>/</span> {@series.publisher || "Independent press"}</p>
        <div class="sb-pagehead__row">
          <h1 id="series-title">{@series.title}</h1>
          <p class="sb-pagehead__intro">
            A shelf for reading this collection across the archive, grouped from {@series.publisher ||
              "an independent press"}.
          </p>
        </div>
        <p class="sb-pagehead__meta">
          <span><strong>{format_count(@series.editions_count)}</strong> books</span>
          <span :if={@series.publisher}>
            <a href={~p"/publishers/#{@series.publisher_slug}"}>{@series.publisher}</a>
          </span>
          <span>Series shelf</span>
        </p>
      </header>

      <section id="series-editions" class="sb-pressworks">
        <div class="sb-sectionhead">
          <div>
            <p class="sb-kicker">The collection</p><h2>Books in this collection</h2>
          </div>
          <span class="sb-link--plain">{format_count(@series.editions_count)} books</span>
        </div>
        <div id="series-editions-stream" class="sb-grid sb-grid--press">
          <CatalogComponents.sb_book_card
            :for={book <- @series.editions}
            book={book}
            id_prefix="series-detail-edition"
          />
        </div>
      </section>

      <aside id="series-context" class="sb-pressworks">
        <div class="sb-listbar"><span>Collection</span><span>{@series.title}</span></div>
        <div class="sb-listbar">
          <span>Publisher</span><span>{@series.publisher || "Unknown"}</span>
        </div>
      </aside>
    </div>
    """
  end

  defp format_count(count) when is_integer(count) do
    count |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)
end
