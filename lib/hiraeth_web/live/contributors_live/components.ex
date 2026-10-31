defmodule HiraethWeb.ContributorsLive.Components do
  use HiraethWeb, :html

  alias HiraethWeb.CatalogComponents

  attr :role, :string, default: nil
  attr :streams, :map, required: true

  def index(assigns) do
    ~H"""
    <div id="contributors-shell">
      <header class="sb-pagehead">
        <p class="sb-kicker">Role-aware directory <span>/</span> {title(@role)}</p>
        <div class="sb-pagehead__row">
          <h1>{title(@role)}</h1>
          <p class="sb-pagehead__intro">
            Authors, translators, and other sourced contributors represented in the public
            catalogue. Roles come from the publisher's own record, never inferred.
          </p>
        </div>
        <p class="sb-pagehead__meta">
          <span>Directory</span>
          <span>Grouped by sourced role</span>
        </p>

        <nav
          id="contributor-roles"
          class="sb-rolebar"
          aria-label="Contributor role filters"
        >
          <.link navigate={~p"/contributors"} class={role_link_class(@role, nil)}>All</.link>
          <.link navigate={~p"/contributors?role=author"} class={role_link_class(@role, "author")}>
            Authors
          </.link>
          <.link
            navigate={~p"/contributors?role=translator"}
            class={role_link_class(@role, "translator")}
          >
            Translators
          </.link>
        </nav>
      </header>

      <div id="contributors-grid" phx-update="stream" class="sb-pressindex">
        <a
          :for={{dom_id, contributor} <- @streams.contributors}
          id={dom_id}
          class="sb-pressitem"
          href={~p"/contributors/#{contributor.slug}"}
        >
          <span class="sb-pressitem__no">{count_label(contributor.books_count)}</span>
          <span class="sb-pressitem__name">{contributor.name}</span>
          <span class="sb-pressitem__count">{role_list(contributor.roles)}</span>
          <span class="sb-pressitem__thumb"><span class="sb-pressmark">{initial(contributor.name)}</span></span>
        </a>
      </div>
    </div>
    """
  end

  attr :contributor, :map, default: nil
  attr :streams, :map, required: true

  def show(assigns) do
    ~H"""
    <div id="contributor-detail-shell">
      <%= if @contributor do %>
        <header class="sb-presshead">
          <div class="sb-presshead__cover">
            <div class="sb-pressmark">{initial(@contributor.name)}</div>
            <p class="sb-figcap">
              <span>{role_list(@contributor.roles)}</span>
              <span>{@contributor.books_count} books</span>
            </p>
          </div>

          <div class="sb-presshead__body">
            <p class="sb-kicker">Contributor <span>/</span> sourced shelf</p>
            <h1 id="contributor-title">{@contributor.name}</h1>
            <p id="contributor-roles" class="sb-presshead__intro">
              {role_list(@contributor.roles)}
            </p>
            <p class="sb-presshead__intro">
              Related records appear only when the contributor relationship is sourced in the
              catalogue.
            </p>
            <div class="sb-pressledger">
              <span><strong>{@contributor.books_count}</strong> books</span>
              <span><strong>{length(@contributor.roles)}</strong> roles</span>
            </div>
          </div>
        </header>

        <section id="contributor-books" class="sb-pressworks">
          <div class="sb-sectionhead">
            <div>
              <p class="sb-kicker">The catalogue</p>
              <h2>Related sourced books</h2>
            </div>
            <span class="sb-link--plain">{@contributor.books_count} records</span>
          </div>
          <div id="contributor-books-stream" phx-update="stream" class="sb-grid sb-grid--press">
            <CatalogComponents.sb_book_card
              :for={{dom_id, book} <- @streams.contributor_books}
              dom_id={dom_id}
              book={book}
              id_prefix="contributor-book"
            />
          </div>
        </section>
      <% else %>
        <div id="contributor-not-found" class="sb-empty">
          <h2>No contributor matches.</h2>
          <p>No sourced contributor matches that slug. Choose another name from the directory.</p>
          <.link navigate={~p"/contributors"} class="sb-link">Back to contributors</.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp title("author"), do: "Authors"
  defp title("translator"), do: "Translators"
  defp title(_role), do: "Contributors"

  defp role_list(roles) when is_list(roles) do
    roles
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(", ", &to_string/1)
  end

  defp role_list(_roles), do: "Contributor"

  defp count_label(1), do: "01"

  defp count_label(count) when is_integer(count),
    do: String.pad_leading(Integer.to_string(count), 2, "0")

  defp count_label(_count), do: "—"

  defp initial(name) when is_binary(name) do
    name |> String.first() |> Kernel.||("H") |> String.upcase()
  end

  defp role_link_class(current, role) do
    active? = current == role

    [
      "sb-tool",
      "sb-role-link",
      active? && "is-current"
    ]
  end
end
