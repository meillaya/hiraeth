defmodule HiraethWeb.BrowseLive do
  use HiraethWeb, :live_view

  alias HiraethWeb.BrowseLive.Components
  alias HiraethWeb.CatalogFilterParams
  alias HiraethWeb.PublicCatalog

  @impl true
  def mount(_params, _session, socket) do
    # handle_params/3 always follows mount/3 with the real query string, so mount
    # only needs the cheap plumbing: an empty page and the filter labels.
    publishers = PublicCatalog.publisher_options()
    series = PublicCatalog.series_options()

    {:ok,
     socket
     |> assign(:page_title, "Books")
     |> assign(:query, "")
     |> assign(:filters, CatalogFilterParams.blank())
     |> assign(:filter_form, to_form(CatalogFilterParams.blank(), as: :filters))
     |> assign(:publishers, publishers)
     |> assign(:press_count, length(publishers))
     |> assign(:series, series)
     |> assign(:view, "covers")
     |> assign(:pagination, PublicCatalog.paginate([], 1))
     |> assign(:page_books, [])
     |> stream(:books, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_catalog(socket, params)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: CatalogFilterParams.filtered_path("/browse", filters))}
  end

  def handle_event("view", %{"view" => view}, socket) when view in ["covers", "index"] do
    {:noreply, assign(socket, :view, view)}
  end

  defp assign_catalog(socket, params) do
    filter_params = CatalogFilterParams.from_request(params)
    pagination = PublicCatalog.book_page(filter_params.filters, filter_params.page)

    socket
    |> assign(:query, filter_params.query)
    |> assign(:filters, filter_params.form_params)
    |> assign(:filter_form, to_form(filter_params.form_params, as: :filters))
    |> assign(:pagination, pagination)
    |> assign(:page_books, pagination.entries)
    |> stream(:books, pagination.entries, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      catalog_count={@pagination.total_count}
      press_count={@press_count}
    >
      <Components.browse_shell
        filter_form={@filter_form}
        filters={@filters}
        pagination={@pagination}
        publishers={@publishers}
        series={@series}
        streams={@streams}
        page_books={@page_books}
        query={@query}
        view={@view}
      />
    </Layouts.app>
    """
  end
end
