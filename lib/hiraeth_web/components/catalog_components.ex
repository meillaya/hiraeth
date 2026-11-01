defmodule HiraethWeb.CatalogComponents do
  @moduledoc """
  Components for rendering catalog listings, covers, metadata, and state views.
  """
  use HiraethWeb, :html

  @doc """
  Renders a provenance-safe typographic book cover fallback.
  """
  attr :book, :map, required: true
  attr :class, :string, default: ""
  attr :loading, :string, default: "lazy"
  attr :fetchpriority, :string, default: "auto"
  attr :variant, :string, default: "card"

  def book_cover(assigns) do
    assigns = assign(assigns, :cover_image_src, cover_image_src(assigns.book, assigns.variant))

    ~H"""
    <figure :if={@cover_image_src} id={"public-cover-#{@book.slug}"} class={@class}>
      <img
        src={@cover_image_src}
        alt={"Cover for #{@book.title}"}
        loading={@loading}
        decoding="async"
        fetchpriority={@fetchpriority}
        width="400"
        height="600"
        class="qi-cover-frame aspect-[2/3] w-full object-cover transition duration-300 group-hover:-translate-y-1 group-hover:shadow-[var(--hiraeth-cover-shadow-hover)]"
      />
    </figure>
    <div
      :if={!@cover_image_src}
      id={"missing-cover-#{@book.slug}"}
      class={[
        "fallback-cover-grain qi-panel aspect-[2/3] w-full p-4 flex flex-col justify-between shadow-sm relative overflow-hidden transition-all duration-300 hover:-translate-y-1 hover:shadow-md select-none",
        @book[:cover_bg] || "bg-[var(--hiraeth-paper)] text-[var(--hiraeth-ink)]",
        @book[:cover_border] || "border-[var(--hiraeth-line)]",
        @class
      ]}
    >
      <div class="qi-fallback-glow absolute inset-0"></div>
      <div class="relative text-[9px] font-mono uppercase tracking-widest opacity-80 text-center">
        {@book.publisher || "Publisher unknown"}
      </div>
      <div class="relative flex flex-col items-center justify-center text-center flex-grow py-4 px-2">
        <span class="mb-3 h-px w-10 bg-current/20"></span>
        <h3 class="font-serif text-lg md:text-xl font-medium leading-tight tracking-tight">
          {@book.title}
        </h3>
        <p :if={role_names(@book[:authors])} class="font-sans text-xs italic mt-2 opacity-90">
          by {role_names(@book[:authors])}
        </p>
      </div>
      <div class="relative flex items-center justify-between text-[8px] font-mono uppercase tracking-wider border-t border-current/25 pt-2 gap-2">
        <span class="truncate">{List.first(@book[:series_titles] || []) || @book[:series] || "Edition"}</span>
        <span :if={@book[:year]}>{@book.year}</span>
      </div>
      <p class="sr-only">Typographic cover fallback; no cover asset is available.</p>
    </div>
    """
  end

  @doc """
  Renders a Hiraeth catalogue card: cover well, serif title, byline, and a
  press/year footer. `h4` keeps the established catalogue heading contract.
  """
  attr :book, :map, required: true
  attr :dom_id, :string, default: nil
  attr :id_prefix, :string, default: "book"

  def sb_book_card(assigns) do
    assigns =
      assigns
      |> assign(:authors, role_names(assigns.book[:authors]))
      |> assign(:id, assigns.dom_id || "#{assigns.id_prefix}-#{assigns.book.slug}")

    ~H"""
    <article id={@id} class="sb-card">
      <a class="sb-card__well" href={~p"/books/#{@book.slug}"}>
        <.catalog_cover book={@book} variant={:card} />
      </a>
      <div class="sb-card__meta">
        <h4 class="sb-card__title">
          <a href={~p"/books/#{@book.slug}"}>{@book.title}</a>
        </h4>
        <span :if={@authors} class="sb-card__author">{@authors}</span>
        <span class="visually-hidden">
          <span :if={@authors}>by {@authors}</span>
          <span :if={translator_names(@book[:translators])}>
            translated by {translator_names(@book[:translators])}
          </span>
          <span :if={@book[:description]}>
            {HiraethWeb.CatalogText.plain(@book.description, 180)}
          </span>
          <span>{format_summary(@book[:formats])}</span>
          <span :for={format <- @book[:formats] || []}>
            {format[:format]} {Enum.join(format[:identifiers] || [], ", ")}
          </span>
        </span>
      </div>
      <div class="sb-card__foot">
        <span>{@book.publisher || "Unknown press"}</span>
        <span>{book_year(@book)}</span>
      </div>
    </article>
    """
  end

  defp book_year(%{published_on: %Date{} = date}), do: to_string(date.year)
  defp book_year(_book), do: "—"

  @doc """
  Renders a Hiraeth cover: the same-origin cache image when available, or the
  typographic fallback used by the design. The `id` contract stays stable for
  tests and QA (`public-cover-<slug>` / `missing-cover-<slug>`).
  """
  attr :book, :map, required: true
  attr :variant, :atom, default: :card, values: [:hero, :card, :record, :thumb, :result]
  attr :loading, :string, default: "lazy"
  attr :fetchpriority, :string, default: "auto"

  def catalog_cover(assigns) do
    assigns =
      assigns
      |> assign(:cover_image, catalog_cover_image(assigns.book, assigns.variant))
      |> assign(:cover_authors, role_names(assigns.book[:authors]))

    ~H"""
    <figure :if={@cover_image} id={"public-cover-#{@book.slug}"} class="sb-cover-figure">
      <picture>
        <source
          :if={@cover_image.webp_srcset}
          type="image/webp"
          srcset={@cover_image.webp_srcset}
          sizes={@cover_image.sizes}
        />
        <img
          src={@cover_image.src}
          srcset={@cover_image.jpg_srcset}
          sizes={@cover_image.sizes}
          alt={"Cover for #{@book.title}"}
          loading={@loading}
          decoding="async"
          fetchpriority={@fetchpriority}
          width="400"
          height="600"
          class="sb-cover-image"
        />
      </picture>
    </figure>
    <div :if={!@cover_image} id={"missing-cover-#{@book.slug}"} class="sb-fallback">
      <span class="sb-fallback__press">{@book.publisher || "Publisher unknown"}</span>
      <span class="sb-fallback__title">{@book.title}</span>
      <span :if={@cover_authors} class="sb-fallback__author">{@cover_authors}</span>
      <span class="visually-hidden">Typographic cover fallback; no cover asset is available.</span>
    </div>
    """
  end

  defp catalog_cover_image(book, variant) do
    cover = Map.get(book, :cover)

    fallback =
      case variant do
        :hero -> cover_url(cover, [:public_url, :thumbnail_url])
        _ -> cover_url(cover, [:thumbnail_url, :public_url])
      end

    fallback = local_cover_url(fallback)

    variants =
      cover
      |> then(&(&1 && Map.get(&1, :responsive_variants)))
      |> List.wrap()
      |> Enum.filter(fn candidate ->
        candidate[:url] |> local_cover_url() |> is_binary()
      end)

    jpg_srcset = srcset(variants, "jpg")
    webp_srcset = srcset(variants, "webp")

    src =
      preferred_variant_url(variants, 400, "jpg") ||
        preferred_variant_url(variants, 800, "jpg") ||
        fallback

    if is_binary(src) do
      %{
        src: src,
        jpg_srcset: jpg_srcset || fallback_srcset(variants, fallback),
        webp_srcset: webp_srcset,
        sizes: cover_sizes(variant)
      }
    end
  end

  defp srcset([], _format), do: nil

  defp srcset(variants, format) do
    variants
    |> Enum.filter(&(&1[:format] == format))
    |> Enum.map(fn candidate -> "#{candidate[:url]} #{candidate[:width]}w" end)
    |> case do
      [] -> nil
      entries -> Enum.join(entries, ", ")
    end
  end

  defp fallback_srcset([], _fallback), do: nil

  defp fallback_srcset(variants, fallback) do
    width = variants |> Enum.map(& &1[:width]) |> Enum.max(fn -> 400 end)
    "#{fallback} #{width}w"
  end

  defp preferred_variant_url(variants, width, format) do
    variants
    |> Enum.find(fn candidate ->
      candidate[:format] == format and candidate[:width] == width
    end)
    |> case do
      nil -> nil
      candidate -> local_cover_url(candidate[:url])
    end
  end

  defp cover_sizes(:hero), do: "(max-width: 760px) 92vw, 560px"
  defp cover_sizes(:record), do: "(max-width: 760px) 90vw, 420px"
  defp cover_sizes(_variant), do: "(max-width: 760px) 45vw, 320px"

  defp cover_url(nil, _keys), do: nil
  defp cover_url(cover, keys), do: Enum.find_value(keys, &Map.get(cover, &1))

  defp cover_image_src(book, variant) do
    book
    |> Map.get(:cover)
    |> cover_src(variant)
  end

  defp cover_src(nil, _variant), do: nil

  defp cover_src(cover, "hero") do
    local_cover_url(Map.get(cover, :thumbnail_url)) ||
      local_cover_url(Map.get(cover, :public_url))
  end

  defp cover_src(cover, _variant) do
    local_cover_url(Map.get(cover, :thumbnail_url)) ||
      local_cover_url(Map.get(cover, :public_url))
  end

  defp local_cover_url(url) when is_binary(url) do
    if String.starts_with?(url, "/covers/cache/"), do: url
  end

  defp local_cover_url(_url), do: nil

  attr :edition, :map, required: true
  attr :id_prefix, :string, default: "edition-card"
  attr :dom_id, :string, default: nil

  def edition_card(assigns) do
    ~H"""
    <article id={@dom_id || "#{@id_prefix}-#{@edition.slug}"} class="group space-y-3">
      <.link
        navigate={~p"/books/#{@edition.slug}"}
        class="qi-focus block rounded-sm"
      >
        <.book_cover book={@edition} />
      </.link>
      <div class="space-y-1.5">
        <h4 class="font-serif text-base font-normal leading-tight tracking-tight !text-[var(--hiraeth-ink)]">
          <.link
            navigate={~p"/books/#{@edition.slug}"}
            class="qi-focus rounded-sm hover:text-[var(--hiraeth-thread)]"
          >
            {@edition.title}
          </.link>
        </h4>
        <div class="space-y-0.5 text-xs text-[var(--hiraeth-muted)]">
          <p :if={role_names(@edition[:authors])} class="truncate">
            {role_names(@edition[:authors])}
          </p>
          <p
            :if={role_names(@edition[:translators])}
            class="truncate"
          >
            tr. {role_names(@edition[:translators])}
          </p>
        </div>
        <p :if={format_summary(@edition[:formats])} class="qi-muted text-xs">
          {format_summary(@edition[:formats])}
        </p>
        <p class="qi-label truncate text-[10px]">
          {@edition.publisher || "Publisher unknown"}
        </p>
      </div>
    </article>
    """
  end

  defp format_summary(formats) when is_list(formats) do
    formats
    |> Enum.map(& &1[:format_label])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.join(", ")
    |> case do
      "" -> nil
      summary -> summary
    end
  end

  defp format_summary(_formats), do: nil

  defp translator_names(contributors) when is_list(contributors) do
    contributors
    |> Enum.map(& &1[:name])
    |> Enum.reject(fn name ->
      is_nil(name) or HiraethWeb.CatalogText.unknown_contributor?(name)
    end)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      names -> names
    end
  end

  defp translator_names(_contributors), do: nil

  defp role_names(contributors) when is_list(contributors) do
    contributors
    |> Enum.map(& &1[:name])
    |> Enum.reject(fn name ->
      is_nil(name) or HiraethWeb.CatalogText.unknown_contributor?(name)
    end)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      names -> names
    end
  end

  defp role_names(_contributors), do: nil

  attr :book, :map, required: true

  def metadata_table(assigns) do
    ~H"""
    <div class="space-y-4">
      <h3 class="border-b qi-divider pb-2 font-serif text-lg font-medium text-[var(--hiraeth-ink)]">
        Details
      </h3>
      <dl class="divide-y divide-[var(--hiraeth-line)]/60 text-sm">
        <.metadata_row label="Title" value={@book.title} serif />
        <.metadata_row
          :if={present?(@book[:original_title])}
          id="book-original-title"
          label="Original title"
          value={@book.original_title}
          serif
        />
        <.metadata_row
          :if={present?(@book[:original_language_code])}
          id="book-original-language"
          label="Original language"
          value={@book.original_language_code}
          mono
        />
        <.metadata_row
          :if={role_names(@book[:authors])}
          label="Author"
          value={role_names(@book[:authors])}
        />
        <.metadata_row
          :if={role_names(@book[:translators])}
          label="Translator"
          value={role_names(@book[:translators])}
        />
        <.metadata_row :if={@book[:publisher]} label="Publisher" value={@book.publisher} />
        <.metadata_row
          :if={Enum.any?(@book[:series_titles] || [])}
          label="Series"
          value={Enum.join(@book.series_titles, ", ")}
        />
        <.metadata_row :if={@book[:format]} label="Format" value={@book.format} />
        <.metadata_row
          :if={subject_text(@book[:subjects])}
          id="book-subjects"
          label="Subjects"
          value={subject_text(@book[:subjects])}
        />
        <.metadata_row :if={@book[:isbn]} label="ISBN" value={@book.isbn} mono />
        <div id="publication-date" class="grid grid-cols-3 py-3">
          <dt class="qi-label text-xs font-bold">
            Publication Date
          </dt>
          <dd class="col-span-2 font-medium text-[var(--hiraeth-ink)]">
            {if @book[:published_on],
              do: Calendar.strftime(@book.published_on, "%Y-%m-%d"),
              else: "Publication date unknown"}
          </dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :serif, :boolean, default: false
  attr :mono, :boolean, default: false

  def metadata_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-3 py-3">
      <dt class="qi-label text-xs font-bold">
        {@label}
      </dt>
      <dd class={[
        "col-span-2 break-words font-medium text-[var(--hiraeth-ink)]",
        @serif && "font-serif font-medium",
        @mono && "font-mono text-xs"
      ]}>
        {@value}
      </dd>
    </div>
    """
  end

  defp present?(value), do: value not in [nil, "", []]

  defp subject_text(subjects) when is_list(subjects) do
    subjects
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp subject_text(_subjects), do: nil

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :base_path, :string, required: true
  attr :query, :string, default: ""
  attr :params, :map, default: %{}

  def pagination(assigns) do
    assigns = assign(assigns, :has_previous, assigns.page > 1)
    assigns = assign(assigns, :has_next, assigns.page < assigns.total_pages)

    ~H"""
    <nav
      id="catalog-pagination"
      class="qi-muted flex items-center justify-between border-t qi-divider pt-4 text-xs font-mono"
    >
      <.link
        :if={@has_previous}
        navigate={page_path(@base_path, @page - 1, @query, @params)}
        id="catalog-prev-page"
        class="qi-action-link rounded-sm hover:underline"
      >
        ← Previous
      </.link>
      <span :if={!@has_previous} class="qi-muted">← Previous</span>
      <span id="catalog-page-count">Page {@page} of {@total_pages}</span>
      <.link
        :if={@has_next}
        navigate={page_path(@base_path, @page + 1, @query, @params)}
        id="catalog-next-page"
        class="qi-action-link rounded-sm hover:underline"
      >
        Next →
      </.link>
      <span :if={!@has_next} class="qi-muted">Next →</span>
    </nav>
    """
  end

  attr :id, :string, default: "catalog-loading"
  attr :label, :string, default: "Loading catalog records"

  def loading_skeleton(assigns) do
    ~H"""
    <div id={@id} class="animate-pulse space-y-6" role="status" aria-busy="true">
      <span class="sr-only">{@label}</span>
      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-6">
        <div :for={_i <- 1..4} class="space-y-3">
          <div class="aspect-[2/3] w-full rounded-sm bg-[var(--hiraeth-line)]"></div>
          <div class="h-4 w-3/4 rounded bg-[var(--hiraeth-line)]"></div>
          <div class="h-3 w-1/2 rounded bg-[var(--hiraeth-line)]"></div>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :string, default: "No books found matching the current criteria."
  attr :id, :string, default: "catalog-empty"
  attr :title, :string, default: "Nothing on this shelf yet"
  attr :eyebrow, :string, default: "Archive note"
  attr :context, :string, default: nil
  attr :action_label, :string, default: nil
  attr :action_path, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div
      id={@id}
      class="qi-empty mx-auto my-8 max-w-lg space-y-4 p-10 text-center shadow-[inset_0_0_0_1px_var(--hiraeth-sheen-soft)]"
    >
      <div class="flex justify-center">
        <span class="h-px w-12 bg-[var(--hiraeth-line-strong)]"></span>
      </div>
      <p class="qi-label text-[10px]">{@eyebrow}</p>
      <h2 class="font-serif text-2xl font-medium text-[var(--hiraeth-ink)]">
        {@title}
      </h2>
      <p class="qi-muted font-serif">
        {@message}
      </p>
      <p
        :if={@context}
        class="qi-panel-soft qi-muted px-3 py-2 text-xs font-mono"
      >
        {@context}
      </p>
      <.link
        :if={@action_label && @action_path}
        navigate={@action_path}
        class="qi-button-secondary qi-focus"
      >
        {@action_label}
      </.link>
      <p class="qi-label text-xs">HIRAETH EDITORIAL ARCHIVE</p>
    </div>
    """
  end

  attr :message, :string, required: true
  attr :id, :string, default: "catalog-error"
  attr :title, :string, default: "Cataloging Error"

  def error_block(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-sm border-l-4 border-[var(--hiraeth-error-ink)] bg-[var(--hiraeth-error-bg)] p-4"
    >
      <div class="flex gap-3">
        <div class="shrink-0 text-[var(--hiraeth-error-ink)]">
          <.icon name="hero-exclamation-triangle-micro" class="size-5" />
        </div>
        <div>
          <h3 class="text-sm font-semibold text-[var(--hiraeth-error-ink)]">{@title}</h3>
          <p class="mt-1 text-xs text-[var(--hiraeth-error-muted)]">{@message}</p>
        </div>
      </div>
    </div>
    """
  end

  defp page_path(base_path, page, _query, params) when map_size(params) > 0 do
    params
    |> Map.put("page", page)
    |> drop_blank_params()
    |> then(&(base_path <> "?" <> URI.encode_query(&1)))
  end

  defp page_path(base_path, page, "", _params), do: "#{base_path}?page=#{page}"

  defp page_path(base_path, page, query, _params),
    do: "#{base_path}?page=#{page}&q=#{URI.encode(query)}"

  defp drop_blank_params(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  attr :publisher, :map, required: true
  attr :index, :integer, default: nil

  @doc "One row in the static publisher directory."
  def press_row(assigns) do
    ~H"""
    <a
      id={"publisher-#{@publisher.slug}"}
      class="sb-pressitem"
      href={~p"/publishers/#{@publisher.slug}"}
    >
      <span class="sb-pressitem__no">{number(@index)}</span>
      <span class="sb-pressitem__name">{@publisher.name}</span>
      <span class="sb-pressitem__count">{format_count(@publisher.editions_count)} books</span>
      <span class="sb-pressitem__thumb">
        <.catalog_cover
          :if={sample_book(@publisher)}
          book={sample_book(@publisher)}
          variant={:thumb}
        />
        <span :if={!sample_book(@publisher)} class="sb-pressmark">
          {initial(@publisher.name)}
        </span>
      </span>
    </a>
    """
  end

  attr :publishers, :list, required: true
  attr :index, :integer, default: nil

  @doc "Previous/next press navigation for a static press dossier."
  def press_nav(assigns) do
    previous = neighbour(assigns.publishers, assigns.index, -1)
    following = neighbour(assigns.publishers, assigns.index, 1)

    assigns = assign(assigns, previous: previous, following: following)

    ~H"""
    <nav :if={@previous || @following} class="sb-pressnav" aria-label="Presses">
      <a :if={@previous} href={~p"/publishers/#{@previous.slug}"}>
        <span>← Previous press</span>
        <b>{@previous.name}</b>
      </a>
      <span :if={!@previous}></span>
      <a :if={@following} href={~p"/publishers/#{@following.slug}"} class="sb-pressnav__next">
        <span>Next press →</span>
        <b>{@following.name}</b>
      </a>
    </nav>
    """
  end

  defp neighbour(_publishers, nil, _offset), do: nil

  defp neighbour(publishers, index, offset) do
    Enum.at(publishers, index + offset)
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

  defp number(index),
    do: index |> Kernel.+(1) |> Integer.to_string() |> String.pad_leading(2, "0")

  defp format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_count(count), do: to_string(count)
end
