defmodule HiraethWeb.BookLive do
  use HiraethWeb, :live_view

  alias HiraethWeb.BookLive.Components
  alias HiraethWeb.PublicCatalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Book")}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    book = PublicCatalog.book(slug)

    {:noreply,
     socket
     |> assign(:book, book)
     |> assign(:related, PublicCatalog.more_from_publisher(book, 4))
     |> assign(:page_title, if(book, do: book.title, else: "Book not found"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <Components.detail book={@book} related={@related} />
    </Layouts.app>
    """
  end
end
