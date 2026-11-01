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
            Hiraeth<span class="sb-brand__dot">.</span>
          </.link>

          <nav class="sb-nav" aria-label="Primary">
            <.link navigate={~p"/browse"}>Books</.link>
            <.link navigate={~p"/publishers"}>Publishers</.link>
            <.link navigate={~p"/series"}>Collections</.link>
          </nav>

          <div class="sb-tools">
            <.link navigate={~p"/search"} class="sb-tool">Search</.link>
            <button
              type="button"
              class="sb-tool sb-tool--menu"
              phx-click={JS.toggle_attribute({"hidden", "hidden"}, to: "#mobile-nav")}
              aria-controls="mobile-nav"
            >
              Menu
            </button>
          </div>
        </div>

        <div class="sb-mobile" id="mobile-nav" hidden>
          <nav aria-label="Mobile">
            <.link navigate={~p"/browse"}>Books</.link>
            <.link navigate={~p"/publishers"}>Publishers</.link>
            <.link navigate={~p"/series"}>Collections</.link>
            <.link navigate={~p"/search"}>Search</.link>
          </nav>
        </div>
      </header>

      <main id="main">
        {render_slot(@inner_block)}
      </main>

      <footer class="sb-footer">
        <div class="sb-footer__in">
          <.link navigate={~p"/"} class="sb-footer__brand" aria-label="Hiraeth — home">
            Hiraeth<span class="sb-brand__dot">.</span>
          </.link>

          <nav class="sb-footer__nav" aria-label="Footer">
            <.link navigate={~p"/browse"}>Books</.link>
            <.link navigate={~p"/publishers"}>Publishers</.link>
            <.link navigate={~p"/series"}>Collections</.link>
            <.link navigate={~p"/search"}>Search</.link>
          </nav>

          <p class="sb-footer__counts">{colophon_counts(assigns)}</p>
        </div>

        <div class="sb-footer__base">
          <span>Hiraeth, {DateTime.utc_now().year}</span>
          <span>{colophon_volumes(@catalog_count)}</span>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
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
      [] -> "Independent literary presses"
      parts -> Enum.join(parts, " / ")
    end
  end

  defp colophon_volumes(nil), do: "An index of independent literary presses"
  defp colophon_volumes(count), do: "#{format_count(count)} volumes indexed"

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)

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
