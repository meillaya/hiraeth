defmodule HiraethWeb.BookLive.Components do
  use HiraethWeb, :html

  alias HiraethWeb.CatalogComponents
  alias HiraethWeb.CatalogText

  attr :book, :map, default: nil

  def detail(assigns) do
    ~H"""
    <div id="book-detail-shell">
      <%= if @book do %>
        <nav class="sb-crumbs" aria-label="Breadcrumb">
          <.link navigate={~p"/browse"}>Books</.link>
          <span aria-hidden="true">/</span>
          <.link :if={@book[:publisher_slug]} navigate={~p"/publishers/#{@book.publisher_slug}"}>
            {@book.publisher}
          </.link>
          <span :if={@book[:publisher_slug]} aria-hidden="true">/</span>
          <span>{@book.title}</span>
        </nav>

        <article class="sb-record">
          <div class="sb-record__cover">
            <CatalogComponents.softbound_cover
              book={@book}
              variant={:record}
              loading="eager"
              fetchpriority="high"
            />
            <p :if={!@book[:cover]} id="missing-cover-note" class="visually-hidden">
              Cover unavailable; typographic fallback shown.
            </p>
          </div>

          <div class="sb-record__body">
            <p class="sb-record__kicker">
              {@book.publisher || "Publisher unknown"}
              <span>/</span> {format_summary(@book[:formats]) || "Format unknown"}
            </p>

            <h1 id="book-title" class={record_title_class(@book.title)}>{@book.title}</h1>
            <p :if={@book[:subtitle]} class="sb-record__translators">{@book.subtitle}</p>

            <p :if={role_names(@book[:authors])} id="book-authors" class="sb-record__byline">
              <span class="visually-hidden">by </span>{role_names(@book.authors)}
            </p>

            <p
              :if={role_names(@book[:translators])}
              id="book-translators"
              class="sb-record__translators"
            >
              translated by {role_names(@book.translators)}
            </p>

            <div id="book-identifiers" class="visually-hidden">
              {Enum.join(@book.identifiers, " ")}
            </div>

            <section :if={@book[:description]} id="book-description" class="sb-description">
              <p>{CatalogText.plain(@book.description)}</p>
            </section>

            <div class="sb-record__actions">
              <.link
                :if={@book[:storefront_url]}
                id="book-storefront-cta"
                href={@book.storefront_url}
                class="sb-button"
                target="_blank"
                rel="noopener"
              >
                Publisher page <span>→</span>
              </.link>
              <.link
                :if={@book[:publisher_slug]}
                navigate={~p"/browse?publisher=#{@book.publisher_slug}"}
                class="sb-link"
              >
                More from this press →
              </.link>
            </div>

            <dl class="sb-facts">
              <div class="sb-fact">
                <dt>Publisher</dt>
                <dd>
                  <.link
                    :if={@book[:publisher_slug]}
                    navigate={~p"/publishers/#{@book.publisher_slug}"}
                  >
                    {@book.publisher || "Unknown"}
                  </.link>
                  <span :if={!@book[:publisher_slug]}>{@book.publisher || "Unknown"}</span>
                </dd>
              </div>
              <div class="sb-fact">
                <dt>Publication</dt>
                <dd id="publication-date">{published_date(@book)}</dd>
              </div>
              <div class="sb-fact">
                <dt>Formats</dt>
                <dd id="book-format-summary">{format_summary(@book[:formats]) || "Not listed"}</dd>
              </div>
              <div class="sb-fact">
                <dt>ISBN-13</dt>
                <dd>{identifier_line(@book) || "Not listed"}</dd>
              </div>
              <div :if={@book[:original_title]} class="sb-fact">
                <dt>Original title</dt>
                <dd id="book-original-title">{@book.original_title}</dd>
              </div>
              <div :if={original_language_line(@book)} class="sb-fact">
                <dt>Original language</dt>
                <dd id="book-original-language">{original_language_line(@book)}</dd>
              </div>
              <div :if={series_line(@book)} class="sb-fact">
                <dt>Collection</dt>
                <dd>{series_line(@book)}</dd>
              </div>
            </dl>

            <section
              :if={Enum.any?(@book[:editorial_praise] || [])}
              id="book-editorial-praise"
              class="sb-subjects"
            >
              <h2>Editorial praise</h2>
              <blockquote :for={praise <- @book.editorial_praise}>
                <p class="sb-description sb-description--tight">
                  “{CatalogText.plain(praise["quote"] || praise[:quote])}”
                </p>
                <p class="sb-record__translators">{praise["source"] || praise[:source]}</p>
              </blockquote>
            </section>

            <section
              :if={Enum.any?(@book[:review_links] || [])}
              id="book-review-links"
              class="sb-subjects"
            >
              <h2>Reviews</h2>
              <article :for={review <- @book.review_links}>
                <.link
                  href={review["source_uri"] || review[:source_uri]}
                  class="sb-link"
                  target="_blank"
                  rel="noopener"
                >
                  {review["source"] || review[:source]}
                </.link>
                <p
                  :if={review["excerpt"] || review[:excerpt]}
                  class="sb-description sb-description--tight"
                >
                  “{CatalogText.plain(review["excerpt"] || review[:excerpt])}”
                </p>
              </article>
            </section>

            <section id="book-formats" class="sb-editions">
              <h2>Editions</h2>
              <div class="sb-edition sb-edition--head">
                <span>Format</span>
                <span>ISBN-13</span>
                <span>Publication</span>
              </div>
              <div
                :for={format <- @book.formats}
                id={"book-format-#{format.edition_slug}"}
                class="sb-edition"
              >
                <span>{format.format_label}</span>
                <span>
                  {format_identifiers(format)}
                  <span :if={format_detail_text(format)} class="sb-edition__detail">
                    {format_detail_text(format)}
                  </span>
                </span>
                <span>{if format.published_on,
                  do: Calendar.strftime(format.published_on, "%Y-%m-%d"),
                  else: "Date unknown"}</span>
              </div>
            </section>

            <section :if={subject_list(@book)} id="book-subjects" class="sb-subjects">
              <h2>Subjects</h2>
              <p>{subject_list(@book)}</p>
            </section>
          </div>
        </article>
      <% else %>
        <div id="book-not-found" class="sb-empty">
          <h2>No book matches.</h2>
          <p>Choose another title from the catalogue.</p>
          <.link navigate={~p"/browse"} class="sb-link">Back to books</.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp record_title_class(title) do
    length = String.length(title || "")

    cond do
      length > 72 -> "sb-record__title--xlong"
      length > 42 -> "sb-record__title--long"
      length > 24 -> "sb-record__title--medium"
      true -> nil
    end
  end

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

  defp format_summary(formats) when is_list(formats) do
    formats
    |> Enum.map(& &1[:format_label])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(", ")
    |> case do
      "" -> nil
      summary -> summary
    end
  end

  defp format_summary(_formats), do: nil

  defp format_detail_text(format) do
    [
      format[:language_code],
      page_count_text(format[:page_count]),
      dimensions_text(format[:dimensions])
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
    |> blank_to_nil()
  end

  defp page_count_text(nil), do: nil
  defp page_count_text(page_count), do: "#{page_count} pages"

  defp dimensions_text(nil), do: nil

  defp dimensions_text(%{height_mm: height, width_mm: width, depth_mm: depth}) do
    [height, width, depth]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dimensions -> Enum.join(dimensions, " × ") <> " mm"
    end
  end

  defp dimensions_text(_dimensions), do: nil

  defp format_identifiers(format) do
    case format.identifiers do
      [] -> "ISBN not listed"
      identifiers -> Enum.join(identifiers, ", ")
    end
  end

  defp published_date(%{published_on: %Date{} = date}), do: Calendar.strftime(date, "%Y-%m-%d")
  defp published_date(_book), do: "Not listed"

  defp identifier_line(%{identifiers: identifiers}) when is_list(identifiers),
    do: identifiers |> Enum.reject(&is_nil/1) |> Enum.join(", ") |> blank_to_nil()

  defp identifier_line(_book), do: nil

  defp original_language_line(%{original_language_code: code})
       when is_binary(code) and code != "",
       do: code

  defp original_language_line(_book), do: nil

  defp series_line(%{series_titles: titles}) when is_list(titles),
    do: titles |> Enum.reject(&is_nil/1) |> Enum.join(", ") |> blank_to_nil()

  defp series_line(_book), do: nil

  defp subject_list(%{subjects: subjects}) when is_list(subjects) do
    subjects
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
    |> blank_to_nil()
  end

  defp subject_list(_book), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value
end
