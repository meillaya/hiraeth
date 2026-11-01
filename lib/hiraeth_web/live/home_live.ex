defmodule HiraethWeb.HomeLive do
  use HiraethWeb, :live_view

  alias HiraethWeb.CatalogComponents
  alias HiraethWeb.CatalogText
  alias HiraethWeb.PublicCatalog

  @impl true
  def mount(_params, _session, socket) do
    catalog = PublicCatalog.book_page(%{"sort" => "recently_added"}, 1, 1)
    selection = PublicCatalog.home_selection(4)
    publishers = PublicCatalog.publishers()
    series = PublicCatalog.series()

    presses =
      publishers
      |> Enum.sort_by(&{-(&1.editions_count || 0), &1.name})
      |> Enum.take(6)

    {:ok,
     socket
     |> assign(:page_title, "Independent literary presses")
     |> assign(:catalog_count, catalog.total_count)
     |> assign(:press_count, length(publishers))
     |> assign(:series_count, length(series))
     |> assign(:spotlight, selection.spotlight)
     |> assign(:spotlight_upcoming?, upcoming?(selection.spotlight))
     |> assign(:presses, presses)
     |> stream(:recent, selection.recent)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      catalog_count={@catalog_count}
      press_count={@press_count}
      series_count={@series_count}
    >
      <main id="home-shell">
        <section :if={@spotlight} class="sb-hero" id="home-spotlight">
          <div class="sb-hero__copy">
            <p class="sb-kicker">
              {if @spotlight_upcoming?, do: "Featured forthcoming", else: "Featured book"}
              <span>/ {@spotlight.publisher || "Independent press"}</span>
            </p>
            <h1 class={hero_title_class(@spotlight.title)}>{@spotlight.title}</h1>
            <p :if={role_names(@spotlight[:authors])} class="sb-hero__byline">
              {role_names(@spotlight.authors)}
            </p>
            <p :if={@spotlight[:description]} class="sb-hero__deck">
              {CatalogText.plain(@spotlight.description, 260)}
            </p>
            <p class="sb-hero__meta">
              {@spotlight.publisher || "Publisher unknown"}, {published_year(@spotlight)}
              <span>/</span> {format_line(@spotlight)}
            </p>
            <.link navigate={~p"/books/#{@spotlight.slug}"} class="sb-button">
              Open the book <span>→</span>
            </.link>
          </div>

          <div class="sb-hero__cover">
            <.link navigate={~p"/books/#{@spotlight.slug}"}>
              <CatalogComponents.catalog_cover
                book={@spotlight}
                variant={:hero}
                loading="eager"
                fetchpriority="high"
              />
            </.link>
            <p class="sb-figcap">
              <span>{@spotlight.title}</span>
              <span>{role_names(@spotlight[:authors]) || @spotlight.publisher}</span>
            </p>
          </div>
        </section>

        <section :if={!@spotlight} class="sb-empty" id="home-empty">
          <h2>No public catalog records</h2>
          <p>
            No public catalog records are available yet. Seed or import sourced editions before opening the archive.
          </p>
          <a href="/browse" class="sb-link">Browse the empty catalogue</a>
        </section>

        <section class="sb-ledger" aria-label="Catalogue counts">
          <.link navigate={~p"/browse"}>
            <strong>{format_count(@catalog_count)}</strong>
            <span>Books in this edition</span>
          </.link>
          <.link navigate={~p"/publishers"}>
            <strong>{format_count(@press_count)}</strong>
            <span>Independent presses</span>
          </.link>
          <.link navigate={~p"/series"}>
            <strong>{format_count(@series_count)}</strong>
            <span>Collections</span>
          </.link>
        </section>

        <section class="sb-shelf" id="recent-acquisitions">
          <div class="sb-shelf__head">
            <div>
              <h2>Four more</h2>
              <p>From the catalogue</p>
            </div>
            <.link navigate={~p"/browse?sort=newest"} class="sb-link">
              All {format_count(@catalog_count)} books →
            </.link>
          </div>

          <div id="recent-books" phx-update="stream" class="sb-shelf__grid">
            <.shelf_book :for={{dom_id, book} <- @streams.recent} dom_id={dom_id} book={book} />
          </div>
        </section>

        <section class="sb-presses">
          <div class="sb-sectionhead">
            <div>
              <p class="sb-kicker">The presses</p>
              <h2>Independent publishers</h2>
            </div>
            <.link navigate={~p"/publishers"} class="sb-link">
              All {format_count(@press_count)} presses →
            </.link>
          </div>

          <div class="sb-presslist">
            <.link
              :for={{press, index} <- Enum.with_index(@presses, 1)}
              navigate={~p"/publishers/#{press.slug}"}
              class="sb-pressrow"
            >
              <span class="sb-pressrow__no">{number(index)}</span>
              <span class="sb-pressrow__name">{press.name}</span>
              <span class="sb-pressrow__count">{format_count(press.editions_count)} books</span>
            </.link>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :dom_id, :string, required: true
  attr :book, :map, required: true

  defp shelf_book(assigns) do
    ~H"""
    <a id={"recent-book-#{@book.work_id}"} class="sb-book" href={~p"/books/#{@book.slug}"}>
      <span class="sb-cover-well">
        <CatalogComponents.catalog_cover book={@book} variant={:card} />
      </span>
      <span class="sb-book__meta">
        <span class="sb-book__title">{@book.title}</span>
        <span :if={role_names(@book[:authors])} class="sb-book__author">
          {role_names(@book.authors)}
        </span>
      </span>
      <span class="sb-book__foot">
        <span>{@book.publisher || "Unknown press"}</span>
        <span>{published_year(@book)}</span>
      </span>
    </a>
    """
  end

  defp upcoming?(%{published_on: %Date{} = published_on}) do
    Date.compare(published_on, Date.utc_today()) == :gt
  end

  defp upcoming?(_book), do: false

  defp role_names(contributors) when is_list(contributors) do
    contributors
    |> Enum.map(& &1[:name])
    |> Enum.reject(fn name -> is_nil(name) or CatalogText.unknown_contributor?(name) end)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      names -> names
    end
  end

  defp role_names(_contributors), do: nil

  defp format_line(book) do
    book
    |> Map.get(:formats, [])
    |> Enum.map(&(&1[:format_label] || &1[:format]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(", ")
    |> case do
      "" -> "Formats unknown"
      line -> line
    end
  end

  defp published_year(%{published_on: %Date{} = date}), do: to_string(date.year)
  defp published_year(_book), do: "Forthcoming"

  defp number(index) when index < 10, do: "0#{index}"
  defp number(index), do: to_string(index)

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)

  defp hero_title_class(title) do
    length = String.length(title || "")

    cond do
      length > 72 -> "sb-hero__title--xlong"
      length > 42 -> "sb-hero__title--long"
      length > 20 -> "sb-hero__title--medium"
      true -> nil
    end
  end
end
