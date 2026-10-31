defmodule HiraethWeb.PublishersLive do
  use HiraethWeb, :live_view

  alias HiraethWeb.CatalogComponents
  alias HiraethWeb.CatalogText
  alias HiraethWeb.PublicCatalog

  @impl true
  def mount(_params, _session, socket) do
    publishers = PublicCatalog.publishers()

    {:ok,
     socket
     |> assign(:publishers, publishers)
     |> assign(:publisher_count, length(publishers))
     |> assign(:series_count, length(PublicCatalog.series()))
     |> assign(:publisher, nil)}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    publisher = PublicCatalog.publisher(slug)

    {:noreply,
     socket
     |> assign(:page_title, if(publisher, do: publisher.name, else: "Publisher"))
     |> assign(:publisher, publisher)
     |> assign(:publisher_index, index_for(socket.assigns.publishers, slug))
     |> stream(:publisher_editions, (publisher && publisher.editions) || [], reset: true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "Publishers")
     |> assign(:publisher, nil)
     |> stream(:publishers, socket.assigns.publishers,
       reset: true,
       dom_id: &"publisher-#{&1.slug}"
     )}
  end

  @impl true
  def render(%{live_action: :show} = assigns), do: render_show(assigns)
  def render(assigns), do: render_index(assigns)

  defp render_index(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      press_count={@publisher_count}
      series_count={@series_count}
    >
      <div id="publishers-shell">
        <header class="sb-pagehead">
          <p class="sb-kicker">
            The presses <span>/</span> {format_count(@publisher_count)} imprints
          </p>
          <div class="sb-pagehead__row">
            <h1>Publishers</h1>
            <p class="sb-pagehead__intro">
              An index of the independent presses represented in Hiraeth: fiction, poetry,
              essays, and criticism, catalogued from their official sources.
            </p>
          </div>
          <p class="sb-pagehead__meta">
            <span><strong>{format_count(@publisher_count)}</strong> presses</span>
            <span><strong>{format_count(@series_count)}</strong> collections</span>
          </p>
        </header>

        <div id="publishers-grid" phx-update="stream" class="sb-pressindex">
          <.press_row
            :for={{dom_id, publisher} <- @streams.publishers}
            dom_id={dom_id}
            publisher={publisher}
            index={index_for(@publishers, publisher.slug)}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :dom_id, :string, required: true
  attr :publisher, :map, required: true
  attr :index, :integer, default: nil

  defp press_row(assigns) do
    ~H"""
    <a
      id={@dom_id}
      class="sb-pressitem"
      href={~p"/publishers/#{@publisher.slug}"}
      aria-label={"Open #{@publisher.name}"}
    >
      <span class="sb-pressitem__no">{number(@index)}</span>
      <span class="sb-pressitem__name">{@publisher.name}</span>
      <span class="sb-pressitem__count">{format_count(@publisher.editions_count)} books</span>
      <span class="sb-pressitem__thumb">
        <CatalogComponents.softbound_cover
          :if={sample_book(@publisher)}
          book={sample_book(@publisher)}
          variant={:thumb}
        />
        <span :if={!sample_book(@publisher)} class="sb-pressmark">{initial(@publisher.name)}</span>
      </span>
    </a>
    """
  end

  defp render_show(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      catalog_count={@publisher && @publisher.editions_count}
      press_count={@publisher_count}
      series_count={@series_count}
    >
      <div id="publisher-detail-shell">
        <%= if @publisher do %>
          <header id="publisher-masthead" class="sb-presshead">
            <div class="sb-presshead__cover">
              <div :if={!sample_book(@publisher)} class="sb-pressmark">
                {initial(@publisher.name)}
              </div>
              <CatalogComponents.softbound_cover
                :if={sample_book(@publisher)}
                book={sample_book(@publisher)}
                variant={:record}
              />
              <p class="sb-figcap">
                <span>{@publisher.name}</span>
                <span>{format_count(@publisher.editions_count)} books</span>
              </p>
            </div>

            <div class="sb-presshead__body">
              <p class="sb-kicker">
                Publisher dossier
                <span>/</span> {format_count(length(@publisher.groupings.series))} collections
              </p>
              <h1 id="publisher-title">{@publisher.name}</h1>
              <p :if={@publisher.description} class="sb-presshead__intro">
                {CatalogText.plain(@publisher.description, 420)}
              </p>

              <div class="sb-pressledger">
                <span><strong>{format_count(@publisher.editions_count)}</strong> books</span>
                <span><strong>{format_count(length(@publisher.groupings.series))}</strong> collections</span>
                <span><strong>{format_count(length(@publisher.groupings.formats))}</strong> formats</span>
              </div>

              <div class="sb-presshead__actions">
                <.link
                  id="publisher-browse-cta"
                  navigate={~p"/browse?publisher=#{@publisher.slug}"}
                  class="sb-button"
                >
                  Browse this press <span>→</span>
                </.link>
                <.link navigate={~p"/publishers"} class="sb-link">All presses →</.link>
              </div>
            </div>
          </header>

          <section id="publisher-editions" class="sb-pressworks">
            <div class="sb-sectionhead">
              <div>
                <p class="sb-kicker">The catalogue</p>
                <h2>Books from this press</h2>
              </div>
              <span class="sb-link--plain">{format_count(@publisher.editions_count)} books</span>
            </div>

            <%= if @publisher.editions_count == 0 do %>
              <div id="publisher-no-editions" class="sb-empty sb-empty--press">
                <h2>No books are attached.</h2>
                <p>This publisher shelf is empty for now.</p>
                <.link navigate={~p"/publishers"} class="sb-link">Back to publishers</.link>
              </div>
            <% else %>
              <div
                id="publisher-editions-stream"
                phx-update="stream"
                class="sb-grid sb-grid--press"
              >
                <CatalogComponents.sb_book_card
                  :for={{dom_id, book} <- @streams.publisher_editions}
                  dom_id={dom_id}
                  book={book}
                  id_prefix="publisher-edition"
                />
              </div>
            <% end %>
          </section>

          <.press_nav index={@publisher_index} publishers={@publishers} />
        <% else %>
          <div id="publisher-not-found" class="sb-empty">
            <h2>No publisher matches.</h2>
            <p>No publisher matches that slug. Choose another press from the index.</p>
            <.link navigate={~p"/publishers"} class="sb-link">Back to publishers</.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp press_nav(assigns) do
    previous = neighbour(assigns.publishers, assigns.index, -1)
    following = neighbour(assigns.publishers, assigns.index, 1)

    assigns = assign(assigns, previous: previous, following: following)

    ~H"""
    <nav :if={@previous || @following} class="sb-pressnav" aria-label="Presses">
      <.link :if={@previous} navigate={~p"/publishers/#{@previous.slug}"}>
        <span>← Previous press</span>
        <b>{@previous.name}</b>
      </.link>
      <span :if={!@previous}></span>
      <.link :if={@following} navigate={~p"/publishers/#{@following.slug}"} class="sb-pressnav__next">
        <span>Next press →</span>
        <b>{@following.name}</b>
      </.link>
    </nav>
    """
  end

  defp neighbour(_publishers, nil, _offset), do: nil

  defp neighbour(publishers, index, offset) do
    Enum.at(publishers, index + offset)
  end

  defp index_for(publishers, slug) do
    Enum.find_index(publishers, &(&1.slug == slug))
  end

  defp sample_book(%{slug: slug, cover_sample: %{title: title, cover: cover}})
       when is_binary(title) and not is_nil(cover) do
    %{
      slug: "press-sample-#{slug}",
      title: title,
      publisher: nil,
      authors: [],
      published_on: nil,
      cover: cover
    }
  end

  defp sample_book(_publisher), do: nil

  defp initial(name) when is_binary(name) do
    name |> String.first() |> Kernel.||("H") |> String.upcase()
  end

  defp number(nil), do: "—"
  defp number(index), do: String.pad_leading(Integer.to_string(index + 1), 2, "0")

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)
end
