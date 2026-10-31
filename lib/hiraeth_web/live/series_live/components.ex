defmodule HiraethWeb.SeriesLive.Components do
  use HiraethWeb, :html

  alias HiraethWeb.CatalogComponents

  attr :series, :list, required: true
  attr :series_empty?, :boolean, required: true

  def index(assigns) do
    assigns =
      assigns
      |> assign(:groups, group_by_press(assigns.series))
      |> assign(:series_total, length(assigns.series))
      |> assign(:volume_total, Enum.sum(Enum.map(assigns.series, &(&1.editions_count || 0))))

    ~H"""
    <div id="series-shell">
      <header class="sb-pagehead">
        <p class="sb-kicker">Collections <span>/</span> {format_count(@series_total)} series</p>
        <div class="sb-pagehead__row">
          <h1>Collections</h1>
          <p class="sb-pagehead__intro">
            Editorial series and imprints inside the catalogue, grouped by the press that
            publishes them. Each collection opens into its records.
          </p>
        </div>
        <p class="sb-pagehead__meta">
          <span><strong>{format_count(@series_total)}</strong> collections</span>
          <span><strong>{format_count(@volume_total)}</strong> volumes</span>
          <span>Grouped by press</span>
        </p>
      </header>

      <div id="series-rows" class="sb-collections">
        <div :if={@series_empty?} class="sb-empty" id="series-empty">
          <h2>No collections yet.</h2>
          <p>Series and collections will appear here as the archive grows.</p>
        </div>

        <section :for={{publisher, series_list} <- @groups} class="sb-collection">
          <div class="sb-collection__press">
            <h2>
              <a
                :if={publisher_slug(series_list)}
                href={~p"/publishers/#{publisher_slug(series_list)}"}
              >
                {publisher || "Independent press"}
              </a>
              <span :if={!publisher_slug(series_list)}>{publisher || "Independent press"}</span>
            </h2>
            <p>{collection_count(length(series_list))}</p>
          </div>

          <div class="sb-collection__list">
            <a
              :for={{series, index} <- Enum.with_index(series_list, 1)}
              href={~p"/series/#{series.slug}"}
            >
              <span class="sb-collection__no">{number(index)}</span>
              <span class="sb-collection__title">{series.title}</span>
              <span class="sb-collection__count">{format_count(series.editions_count)} books</span>
              <span class="sb-collection__arrow">→</span>
            </a>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :series, :map, default: nil
  attr :streams, :map, required: true

  def show(assigns) do
    ~H"""
    <div id="series-detail-shell">
      <%= if @series do %>
        <header class="sb-pagehead">
          <p class="sb-kicker">
            Collection <span>/</span> {@series.publisher || "Independent press"}
          </p>
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
              <p class="sb-kicker">The collection</p>
              <h2>Books in this collection</h2>
            </div>
            <span class="sb-link--plain">{format_count(@series.editions_count)} books</span>
          </div>

          <div id="series-editions-stream" phx-update="stream" class="sb-grid sb-grid--press">
            <CatalogComponents.sb_book_card
              :for={{dom_id, book} <- @streams.series_editions}
              dom_id={dom_id}
              book={book}
              id_prefix="series-detail-edition"
            />
          </div>
        </section>

        <aside id="series-context" class="sb-pressworks">
          <div class="sb-listbar">
            <span>Collection</span>
            <span>{@series.title}</span>
          </div>
          <div class="sb-listbar">
            <span>Publisher</span>
            <span>{@series.publisher || "Unknown"}</span>
          </div>
        </aside>
      <% else %>
        <div id="series-not-found" class="sb-empty">
          <h2>No collection matches.</h2>
          <p>Choose another collection from the index.</p>
          <.link navigate={~p"/series"} class="sb-link">Back to collections</.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp group_by_press(series) do
    series
    |> Enum.group_by(&(&1.publisher || "Independent press"))
    |> Enum.sort_by(fn {publisher, _} -> String.downcase(publisher) end)
  end

  defp publisher_slug([%{publisher_slug: slug} | _]) when is_binary(slug), do: slug
  defp publisher_slug(_series), do: nil

  defp collection_count(1), do: "1 collection"
  defp collection_count(count), do: "#{format_count(count)} collections"

  defp number(index) when index < 10, do: "0#{index}"
  defp number(index), do: to_string(index)

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)
end
