defmodule HiraethWeb.SeriesLive do
  use HiraethWeb, :live_view

  alias HiraethWeb.PublicCatalog
  alias HiraethWeb.SeriesLive.Components

  @impl true
  def mount(_params, _session, socket) do
    publishers = PublicCatalog.publishers()

    {:ok,
     socket
     |> assign(:page_title, "Collections")
     |> assign(:series, [])
     |> assign(:series_empty?, false)
     |> assign(:press_count, length(publishers))
     |> assign(:series_count, length(PublicCatalog.series()))}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    series = PublicCatalog.series_by_slug(slug)

    {:noreply,
     socket
     |> assign(:page_title, if(series, do: series.title, else: "Collection"))
     |> assign(:series, series)
     |> stream(:series_editions, (series && series.editions) || [], reset: true)}
  end

  def handle_params(_params, _uri, socket) do
    series = PublicCatalog.series_with_preview_editions()

    {:noreply,
     socket
     |> assign(:page_title, "Collections")
     |> assign(:series, series)
     |> assign(:series_empty?, series == [])
     |> assign(:series_count, length(series))}
  end

  @impl true
  def render(%{live_action: :show} = assigns), do: render_show(assigns)
  def render(assigns), do: render_index(assigns)

  defp render_index(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      press_count={@press_count}
      series_count={@series_count}
    >
      <Components.index series={@series} series_empty?={@series_empty?} />
    </Layouts.app>
    """
  end

  defp render_show(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      catalog_count={@series && @series.editions_count}
      press_count={@press_count}
      series_count={@series_count}
    >
      <Components.show series={@series} streams={@streams} />
    </Layouts.app>
    """
  end
end
