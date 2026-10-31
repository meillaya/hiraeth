defmodule HiraethWeb.Api.V1.CatalogController do
  @moduledoc """
  Versioned JSON read API over the public catalog projections.

  The controller is deliberately thin: it validates query parameters, delegates
  reads to `HiraethWeb.PublicCatalog`, and serializes through
  `HiraethWeb.Api.V1.Serializer`. Every response shape is declared in
  `HiraethWeb.Api.V1.Schemas` and served from `HiraethWeb.Api.Spec`.
  """

  use HiraethWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias HiraethWeb.Api.V1.{Schemas, Serializer}
  alias HiraethWeb.PublicCatalog
  alias OpenApiSpex.Schema

  @default_page 1
  @default_page_size 24
  @max_page_size 100
  @max_page 10_000
  @sort_values ~w(newest title author recently_added)
  @role_values ~w(author translator)
  @book_filter_keys ~w(q publisher role contributor format language subject series year sort)

  tags ["catalog"]

  operation :books,
    summary: "List catalog books",
    description: "Returns a page of work-centric books. Filters match the public browse page.",
    parameters: [
      q: [
        in: :query,
        type: :string,
        description: "Free-text title, author, publisher, series, or ISBN query."
      ],
      publisher: [in: :query, type: :string, description: "Publisher slug or name."],
      role: [
        in: :query,
        schema: %Schema{type: :string, enum: @role_values},
        description: "Contributor role filter."
      ],
      contributor: [in: :query, type: :string, description: "Contributor slug or name."],
      format: [in: :query, type: :string, description: "Edition format such as paperback."],
      language: [in: :query, type: :string, description: "Edition language code."],
      subject: [in: :query, type: :string, description: "Subject term."],
      series: [in: :query, type: :string, description: "Series slug or title."],
      year: [in: :query, type: :integer, description: "Publication year."],
      sort: [
        in: :query,
        schema: %Schema{type: :string, enum: @sort_values},
        description: "Result ordering."
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page},
        description: "1-based page number."
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page_size},
        description: "Entries per page."
      ]
    ],
    responses: [
      ok: {"Book page", "application/json", Schemas.BookPage},
      bad_request: {"Invalid query parameter", "application/json", Schemas.ErrorResponse}
    ]

  def books(conn, params) do
    with {:ok, page} <- pagination_param(params, "page", @default_page, @max_page),
         {:ok, page_size} <-
           pagination_param(params, "page_size", @default_page_size, @max_page_size),
         {:ok, _sort} <- sort_param(params),
         {:ok, _role} <- role_param(params) do
      query = Map.take(params, @book_filter_keys)

      conn
      |> json(Serializer.book_page(PublicCatalog.book_page(query, page, page_size)))
    else
      {:error, message} -> invalid_parameter(conn, message)
    end
  end

  operation :book,
    summary: "Get a book",
    parameters: [
      slug: [in: :path, type: :string, description: "Book or edition slug."]
    ],
    responses: [
      ok: {"Book", "application/json", Schemas.BookResponse},
      not_found: {"Book not found", "application/json", Schemas.ErrorResponse}
    ]

  def book(conn, %{"slug" => slug}) do
    case PublicCatalog.book(slug) do
      nil -> not_found(conn, "book", slug)
      book -> json(conn, %{"data" => Serializer.book(book)})
    end
  end

  operation :edition,
    summary: "Get an edition",
    parameters: [
      slug: [in: :path, type: :string, description: "Edition slug."]
    ],
    responses: [
      ok: {"Edition", "application/json", Schemas.EditionResponse},
      not_found: {"Edition not found", "application/json", Schemas.ErrorResponse}
    ]

  def edition(conn, %{"slug" => slug}) do
    case PublicCatalog.edition(slug) do
      nil -> not_found(conn, "edition", slug)
      edition -> json(conn, %{"data" => Serializer.edition(edition)})
    end
  end

  operation :publishers,
    summary: "List publishers",
    parameters: [
      page: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page},
        description: "1-based page number."
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page_size},
        description: "Entries per page."
      ]
    ],
    responses: [
      ok: {"Publisher page", "application/json", Schemas.PublisherPage},
      bad_request: {"Invalid query parameter", "application/json", Schemas.ErrorResponse}
    ]

  def publishers(conn, params) do
    with {:ok, page} <- pagination_param(params, "page", @default_page, @max_page),
         {:ok, page_size} <-
           pagination_param(params, "page_size", @default_page_size, @max_page_size) do
      publishers_page =
        PublicCatalog.publishers()
        |> PublicCatalog.paginate(page, page_size)

      conn
      |> json(Serializer.publisher_page(publishers_page))
    else
      {:error, message} -> invalid_parameter(conn, message)
    end
  end

  operation :publisher,
    summary: "Get a publisher",
    parameters: [
      slug: [in: :path, type: :string, description: "Publisher slug."]
    ],
    responses: [
      ok: {"Publisher", "application/json", Schemas.PublisherResponse},
      not_found: {"Publisher not found", "application/json", Schemas.ErrorResponse}
    ]

  def publisher(conn, %{"slug" => slug}) do
    case PublicCatalog.publisher(slug) do
      nil -> not_found(conn, "publisher", slug)
      publisher -> json(conn, %{"data" => Serializer.publisher(publisher)})
    end
  end

  operation :series,
    summary: "List series",
    parameters: [
      page: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page},
        description: "1-based page number."
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page_size},
        description: "Entries per page."
      ]
    ],
    responses: [
      ok: {"Series page", "application/json", Schemas.SeriesPage},
      bad_request: {"Invalid query parameter", "application/json", Schemas.ErrorResponse}
    ]

  def series(conn, params) do
    with {:ok, page} <- pagination_param(params, "page", @default_page, @max_page),
         {:ok, page_size} <-
           pagination_param(params, "page_size", @default_page_size, @max_page_size) do
      series_page =
        PublicCatalog.series()
        |> PublicCatalog.paginate(page, page_size)

      conn
      |> json(Serializer.series_page(series_page))
    else
      {:error, message} -> invalid_parameter(conn, message)
    end
  end

  operation :series_show,
    summary: "Get a series",
    parameters: [
      slug: [in: :path, type: :string, description: "Series slug."]
    ],
    responses: [
      ok: {"Series", "application/json", Schemas.SeriesResponse},
      not_found: {"Series not found", "application/json", Schemas.ErrorResponse}
    ]

  def series_show(conn, %{"slug" => slug}) do
    case PublicCatalog.series_by_slug(slug) do
      nil -> not_found(conn, "series", slug)
      series -> json(conn, %{"data" => Serializer.series(series)})
    end
  end

  operation :contributors,
    summary: "List contributors",
    parameters: [
      role: [
        in: :query,
        schema: %Schema{type: :string, enum: @role_values},
        description: "Contributor role filter."
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page},
        description: "1-based page number."
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: @max_page_size},
        description: "Entries per page."
      ]
    ],
    responses: [
      ok: {"Contributor page", "application/json", Schemas.ContributorPage},
      bad_request: {"Invalid query parameter", "application/json", Schemas.ErrorResponse}
    ]

  def contributors(conn, params) do
    with {:ok, page} <- pagination_param(params, "page", @default_page, @max_page),
         {:ok, page_size} <-
           pagination_param(params, "page_size", @default_page_size, @max_page_size),
         {:ok, role} <- role_param(params) do
      contributors_page =
        PublicCatalog.contributors(role)
        |> PublicCatalog.paginate(page, page_size)

      conn
      |> json(Serializer.contributor_page(contributors_page))
    else
      {:error, message} -> invalid_parameter(conn, message)
    end
  end

  operation :contributor,
    summary: "Get a contributor",
    parameters: [
      slug: [in: :path, type: :string, description: "Contributor slug."]
    ],
    responses: [
      ok: {"Contributor", "application/json", Schemas.ContributorResponse},
      not_found: {"Contributor not found", "application/json", Schemas.ErrorResponse}
    ]

  def contributor(conn, %{"slug" => slug}) do
    case PublicCatalog.contributor(slug) do
      nil -> not_found(conn, "contributor", slug)
      contributor -> json(conn, %{"data" => Serializer.contributor_summary(contributor)})
    end
  end

  defp pagination_param(params, key, default, maximum) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, default}

      value when is_integer(value) ->
        bounded(value, key, maximum)

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> bounded(integer, key, maximum)
          _other -> {:error, "#{key} must be an integer"}
        end

      _other ->
        {:error, "#{key} must be an integer"}
    end
  end

  defp bounded(value, _key, maximum) when value >= 1 and value <= maximum, do: {:ok, value}

  defp bounded(_value, key, maximum),
    do: {:error, "#{key} must be between 1 and #{maximum}"}

  defp sort_param(params) do
    case Map.get(params, "sort") do
      value when value in [nil, ""] -> {:ok, "newest"}
      value when value in @sort_values -> {:ok, value}
      _other -> {:error, "sort must be one of #{Enum.join(@sort_values, ", ")}"}
    end
  end

  defp role_param(params) do
    case Map.get(params, "role") do
      value when value in [nil, ""] -> {:ok, nil}
      value when value in @role_values -> {:ok, value}
      _other -> {:error, "role must be one of #{Enum.join(@role_values, ", ")}"}
    end
  end

  defp invalid_parameter(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(Serializer.error("invalid_parameter", message))
  end

  defp not_found(conn, resource, slug) do
    conn
    |> put_status(:not_found)
    |> json(
      Serializer.error("not_found", "#{resource} not found", %{
        "resource" => resource,
        "slug" => slug
      })
    )
  end
end
