defmodule HiraethWeb.Layouts do
  @moduledoc """
  Application layout for Hiraeth.

  The shell is a single paper sheet on a sage ground: brand and primary
  navigation in a hairline header, the reading surface in the middle, and a
  two-line colophon footer. All measurements come from the Hiraeth tokens in
  `assets/css/tokens.css`.
  """
  use HiraethWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  attr :class, :string, default: "sb-brand__mark"

  @doc """
  The Hiraeth wordmark. The link around it carries the accessible name, so the
  image is decorative.
  """
  def brand(assigns) do
    ~H"""
    <img
      src={~p"/images/logo/logo-wordmark.svg"}
      class={@class}
      alt=""
      width="116"
      height="29"
    />
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :catalog_count, :integer, default: nil, doc: "public catalog count for the colophon"

  attr :press_count, :integer, default: nil, doc: "public publisher count for the colophon"

  attr :series_count, :integer, default: nil, doc: "public collection count for the colophon"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a class="sb-skip" href="#main">Skip to content</a>

    <div class="sb-sheet">
      <header class="sb-header">
        <div class="sb-header__in">
          <.link navigate={~p"/"} class="sb-brand" aria-label="Hiraeth — home">
            <.brand />
          </.link>

          <nav class="sb-nav" aria-label="Primary">
            <.link navigate={~p"/browse"}>Books</.link>
            <.link navigate={~p"/publishers"}>Publishers</.link>
            <.link navigate={~p"/series"}>Collections</.link>
          </nav>

          <div class="sb-tools">
            <a
              class="sb-tool"
              href={~p"/search"}
              data-search-open
              aria-haspopup="dialog"
              aria-controls="search-window"
            >
              Search
            </a>
            <button
              class="sb-tool sb-tool--shelf"
              type="button"
              data-shelf-open
              aria-haspopup="dialog"
              aria-controls="shelf-dialog"
            >
              Shelf <span data-shelf-count>0</span>
            </button>
            <details class="sb-menu">
              <summary class="sb-tool sb-tool--menu">
                <span>Menu</span>
                <span class="sb-menu__indicator" aria-hidden="true"></span>
              </summary>
              <div class="sb-mobile" id="mobile-nav">
                <nav aria-label="Mobile">
                  <.link navigate={~p"/browse"}>Books</.link>
                  <.link navigate={~p"/publishers"}>Publishers</.link>
                  <.link navigate={~p"/series"}>Collections</.link>
                  <.link navigate={~p"/shelf"}>Shelf</.link>
                  <.link navigate={~p"/search"}>Search</.link>
                </nav>
              </div>
            </details>
          </div>
        </div>
      </header>

      <main id="main">
        {render_slot(@inner_block)}
      </main>

      <footer class="sb-footer">
        <div class="sb-footer__in">
          <.link navigate={~p"/"} class="sb-footer__brand" aria-label="Hiraeth — home">
            <.brand class="sb-footer__mark" />
          </.link>

          <nav class="sb-footer__nav" aria-label="Footer">
            <.link navigate={~p"/browse"}>Books</.link>
            <.link navigate={~p"/publishers"}>Publishers</.link>
            <.link navigate={~p"/series"}>Collections</.link>
            <.link navigate={~p"/shelf"}>Shelf</.link>
            <.link navigate={~p"/search"}>Search</.link>
          </nav>

          <p :if={colophon_counts(assigns) != ""} class="sb-footer__counts">
            {colophon_counts(assigns)}
          </p>
        </div>

        <div class="sb-footer__base">
          <span>Hiraeth, {DateTime.utc_now().year}</span>
          <span>An index of independent literary presses</span>
        </div>
      </footer>
    </div>

    <.search_dialog />

    <.shelf_dialog />

    <p id="shelf-live" class="visually-hidden" role="status" aria-live="polite"></p>

    <.flash_group flash={@flash} />
    """
  end

  defp search_dialog(assigns) do
    ~H"""
    <dialog
      class="sb-dialog sb-dialog--search"
      id="search-window"
      aria-labelledby="search-window-title"
      data-search-dialog
    >
      <div class="sb-dialog__head">
        <h2 class="sb-dialog__title" id="search-window-title">Search the catalogue</h2>
        <button class="sb-dialog__close" type="button" data-search-close>Close</button>
      </div>
      <form
        class="sb-searchform"
        id="search-window-form"
        role="search"
        action={~p"/search"}
        method="get"
        data-search-form
      >
        <label class="visually-hidden" for="search-window-input">
          Search by title, author, press, or collection
        </label>
        <input
          id="search-window-input"
          type="search"
          name="q"
          placeholder="Title, author, press"
          autocomplete="off"
          data-search-input
        />
      </form>
      <div
        class="sb-results"
        id="search-window-results"
        aria-live="polite"
        data-search-results
      >
      </div>
      <div class="sb-search__foot">
        <p class="sb-dialog__hint">Search by title, author, press, or collection.</p>
        <a class="sb-link" href={~p"/search"} data-search-all>All books →</a>
      </div>
    </dialog>
    """
  end

  defp shelf_dialog(assigns) do
    ~H"""
    <dialog
      class="sb-dialog sb-dialog--shelf"
      id="shelf-dialog"
      aria-labelledby="shelf-dialog-title"
      data-shelf-dialog
    >
      <div class="sb-dialog__head">
        <h2 class="sb-dialog__title" id="shelf-dialog-title">Your shelf</h2>
        <button class="sb-dialog__close" type="button" data-shelf-close>Close</button>
      </div>
      <div class="sb-shelf-list" id="shelf-list" data-shelf-list></div>
      <a class="sb-shelf-page-link" href={~p"/shelf"}>Open the shelf page →</a>
      <p class="sb-dialog__hint">Saved in this browser.</p>
    </dialog>
    """
  end

  defp colophon_counts(assigns) do
    parts =
      [
        assigns[:catalog_count] && "#{format_count(assigns.catalog_count)} books",
        assigns[:press_count] && "#{format_count(assigns.press_count)} presses",
        assigns[:series_count] && "#{format_count(assigns.series_count)} collections"
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> ""
      parts -> Enum.join(parts, " / ")
    end
  end

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)

  @doc """
  Minimal operator shell for the authenticated candidate-review console.

  It intentionally has no public catalogue navigation beyond a return link:
  the admin console is a write surface and should never be mistaken for a
  public reading page.
  """
  attr :flash, :map, required: true
  attr :page_title, :string, default: "Candidate review"
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div class="admin-shell">
      <header class="admin-bar">
        <a href={~p"/admin"} class="sb-brand" aria-label="Hiraeth admin home">
          <.brand />
        </a>
        <nav class="admin-nav" aria-label="Admin">
          <a href={~p"/admin/candidates"}>Candidates</a>
          <a href={~p"/ops"}>Ops health</a>
          <a href={~p"/"}>Public site</a>
        </nav>
        <p class="admin-bar__title">{@page_title}</p>
      </header>

      <main id="admin-main" class="admin-main">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="sb-flashes">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
