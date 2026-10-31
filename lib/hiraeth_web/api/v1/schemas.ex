defmodule HiraethWeb.Api.V1.Schemas do
  @moduledoc """
  OpenAPI schemas for the versioned public catalog API.

  These schemas are the machine-readable half of the public contract. The
  response serializer must emit exactly the declared fields, and the API test
  suite validates every response against the spec, so a serializer change that
  is not reflected here fails a test instead of drifting from the doc.
  """

  defmodule Contributor do
    @moduledoc "A contributor slot attached to a book or edition."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Contributor",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "Contributor UUID.", nullable: true},
        name: %Schema{type: :string, description: "Display name."},
        slug: %Schema{type: :string, description: "Contributor page slug.", nullable: true},
        role: %Schema{type: :string, description: "Contribution role.", nullable: true},
        position: %Schema{type: :integer, description: "Source position.", nullable: true}
      },
      required: [:id, :name, :slug, :role, :position],
      additionalProperties: false
    })
  end

  defmodule Cover do
    @moduledoc "A locally cached cover that public clients may render."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Cover",
      type: :object,
      properties: %{
        public_url: %Schema{type: :string, description: "Same-origin cached cover URL."},
        thumbnail_url: %Schema{type: :string, nullable: true},
        source_url: %Schema{type: :string, description: "Provider cover URL, provenance only."},
        provider: %Schema{type: :string},
        rights_basis: %Schema{type: :string},
        attribution_text: %Schema{type: :string, nullable: true},
        attribution_url: %Schema{type: :string, nullable: true}
      },
      required: [
        :public_url,
        :thumbnail_url,
        :source_url,
        :provider,
        :rights_basis,
        :attribution_text,
        :attribution_url
      ],
      additionalProperties: false
    })
  end

  defmodule Source do
    @moduledoc "Public provenance for a catalog record."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Source",
      type: :object,
      properties: %{
        provider: %Schema{type: :string},
        source_type: %Schema{type: :string},
        source_uri: %Schema{type: :string},
        source_identity: %Schema{type: :string, nullable: true},
        license_note: %Schema{type: :string, nullable: true},
        imported_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [
        :provider,
        :source_type,
        :source_uri,
        :source_identity,
        :license_note,
        :imported_at
      ],
      additionalProperties: false
    })
  end

  defmodule Dimensions do
    @moduledoc "Physical dimensions in millimetres."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Dimensions",
      type: :object,
      properties: %{
        height_mm: %Schema{type: :integer, nullable: true},
        width_mm: %Schema{type: :integer, nullable: true},
        depth_mm: %Schema{type: :integer, nullable: true}
      },
      required: [:height_mm, :width_mm, :depth_mm],
      additionalProperties: false
    })
  end

  defmodule Praise do
    @moduledoc "One sourced editorial praise entry."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Praise",
      type: :object,
      properties: %{
        quote: %Schema{type: :string},
        source: %Schema{type: :string, nullable: true},
        source_uri: %Schema{type: :string, nullable: true}
      },
      required: [:quote, :source, :source_uri],
      additionalProperties: false
    })
  end

  defmodule ReviewLink do
    @moduledoc "One link-first review reference."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "ReviewLink",
      type: :object,
      properties: %{
        source: %Schema{type: :string, nullable: true},
        source_uri: %Schema{type: :string, nullable: true},
        rights_basis: %Schema{type: :string, nullable: true},
        excerpt: %Schema{type: :string, nullable: true}
      },
      required: [:source, :source_uri, :rights_basis, :excerpt],
      additionalProperties: false
    })
  end

  defmodule Format do
    @moduledoc "Edition-format summary nested under a book."
    require OpenApiSpex
    alias HiraethWeb.Api.V1.Schemas.Dimensions
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Format",
      type: :object,
      properties: %{
        edition_slug: %Schema{type: :string},
        format: %Schema{type: :string, nullable: true},
        format_label: %Schema{type: :string},
        source_identity: %Schema{type: :string, nullable: true},
        published_on: %Schema{type: :string, format: :date, nullable: true},
        language_code: %Schema{type: :string, nullable: true},
        page_count: %Schema{type: :integer, nullable: true},
        dimensions: %Schema{type: :object, nullable: true, allOf: [Dimensions]},
        identifiers: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [
        :edition_slug,
        :format,
        :format_label,
        :source_identity,
        :published_on,
        :language_code,
        :page_count,
        :dimensions,
        :identifiers
      ],
      additionalProperties: false
    })
  end

  defmodule Book do
    @moduledoc "A work-centric public catalog book."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    alias HiraethWeb.Api.V1.Schemas.{
      Contributor,
      Cover,
      Format,
      Praise,
      ReviewLink,
      Source
    }

    OpenApiSpex.schema(%{
      title: "Book",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "Work UUID."},
        slug: %Schema{type: :string},
        title: %Schema{type: :string},
        subtitle: %Schema{type: :string, nullable: true},
        publisher: %Schema{type: :string, nullable: true},
        publisher_slug: %Schema{type: :string, nullable: true},
        author: %Schema{type: :string, nullable: true},
        description: %Schema{type: :string, nullable: true},
        original_title: %Schema{type: :string, nullable: true},
        original_language_code: %Schema{type: :string, nullable: true},
        published_on: %Schema{type: :string, format: :date, nullable: true},
        year: %Schema{type: :integer, nullable: true},
        isbn: %Schema{type: :string, nullable: true},
        storefront_url: %Schema{type: :string, nullable: true},
        subjects: %Schema{type: :array, items: %Schema{type: :string}},
        praise: %Schema{type: :array, items: Praise},
        review_links: %Schema{type: :array, items: ReviewLink},
        missing_fields: %Schema{
          type: :object,
          description: "Field name to the reason the source did not supply it.",
          additionalProperties: %Schema{type: :string}
        },
        series_titles: %Schema{type: :array, items: %Schema{type: :string}},
        series_slug: %Schema{type: :string, nullable: true},
        identifiers: %Schema{type: :array, items: %Schema{type: :string}},
        formats: %Schema{type: :array, items: Format},
        authors: %Schema{type: :array, items: Contributor},
        translators: %Schema{type: :array, items: Contributor},
        contributors_by_role: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :array, items: Contributor}
        },
        contributor_names: %Schema{type: :array, items: %Schema{type: :string}},
        cover: %Schema{type: :object, nullable: true, allOf: [Cover]},
        source: %Schema{type: :object, nullable: true, allOf: [Source]},
        sources: %Schema{type: :array, items: Source}
      },
      required: [
        :id,
        :slug,
        :title,
        :subtitle,
        :publisher,
        :publisher_slug,
        :author,
        :description,
        :original_title,
        :original_language_code,
        :published_on,
        :year,
        :isbn,
        :storefront_url,
        :subjects,
        :praise,
        :review_links,
        :missing_fields,
        :series_titles,
        :series_slug,
        :identifiers,
        :formats,
        :authors,
        :translators,
        :contributors_by_role,
        :contributor_names,
        :cover,
        :source,
        :sources
      ],
      additionalProperties: false
    })
  end

  defmodule Edition do
    @moduledoc "A concrete edition detail record."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    alias HiraethWeb.Api.V1.Schemas.{
      Contributor,
      Cover,
      Dimensions,
      Praise,
      ReviewLink,
      Source
    }

    OpenApiSpex.schema(%{
      title: "Edition",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        work_id: %Schema{type: :string},
        slug: %Schema{type: :string},
        title: %Schema{type: :string},
        subtitle: %Schema{type: :string, nullable: true},
        format: %Schema{type: :string, nullable: true},
        published_on: %Schema{type: :string, format: :date, nullable: true},
        year: %Schema{type: :integer, nullable: true},
        publisher: %Schema{type: :string, nullable: true},
        publisher_slug: %Schema{type: :string, nullable: true},
        author: %Schema{type: :string, nullable: true},
        isbn: %Schema{type: :string, nullable: true},
        series_slug: %Schema{type: :string, nullable: true},
        cover: %Schema{type: :object, nullable: true, allOf: [Cover]},
        description: %Schema{type: :string, nullable: true},
        storefront_url: %Schema{type: :string, nullable: true},
        original_title: %Schema{type: :string, nullable: true},
        original_language_code: %Schema{type: :string, nullable: true},
        language_code: %Schema{type: :string, nullable: true},
        page_count: %Schema{type: :integer, nullable: true},
        dimensions: %Schema{type: :object, nullable: true, allOf: [Dimensions]},
        source: %Schema{type: :object, nullable: true, allOf: [Source]},
        source_uri: %Schema{type: :string, nullable: true},
        authors: %Schema{type: :array, items: Contributor},
        translators: %Schema{type: :array, items: Contributor},
        contributors_by_role: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :array, items: Contributor}
        },
        contributor_names: %Schema{type: :array, items: %Schema{type: :string}},
        identifiers: %Schema{type: :array, items: %Schema{type: :string}},
        series_titles: %Schema{type: :array, items: %Schema{type: :string}},
        subjects: %Schema{type: :array, items: %Schema{type: :string}},
        praise: %Schema{type: :array, items: Praise},
        review_links: %Schema{type: :array, items: ReviewLink},
        missing_fields: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string}
        }
      },
      required: [
        :id,
        :work_id,
        :slug,
        :title,
        :subtitle,
        :format,
        :published_on,
        :year,
        :publisher,
        :publisher_slug,
        :author,
        :isbn,
        :series_slug,
        :cover,
        :description,
        :storefront_url,
        :original_title,
        :original_language_code,
        :language_code,
        :page_count,
        :dimensions,
        :source,
        :source_uri,
        :authors,
        :translators,
        :contributors_by_role,
        :contributor_names,
        :identifiers,
        :series_titles,
        :subjects,
        :praise,
        :review_links,
        :missing_fields
      ],
      additionalProperties: false
    })
  end

  defmodule Grouping do
    @moduledoc "One counted facet value."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Grouping",
      type: :object,
      properties: %{
        label: %Schema{type: :string},
        count: %Schema{type: :integer},
        slug: %Schema{type: :string, nullable: true}
      },
      required: [:label, :count, :slug],
      additionalProperties: false
    })
  end

  defmodule Groupings do
    @moduledoc "Fixed facet groups on a publisher page."
    require OpenApiSpex
    alias HiraethWeb.Api.V1.Schemas.Grouping
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Groupings",
      type: :object,
      properties: %{
        formats: %Schema{type: :array, items: Grouping},
        languages: %Schema{type: :array, items: Grouping},
        original_languages: %Schema{type: :array, items: Grouping},
        series: %Schema{type: :array, items: Grouping},
        translations: %Schema{type: :array, items: Grouping},
        contributor_roles: %Schema{type: :array, items: Grouping}
      },
      required: [
        :formats,
        :languages,
        :original_languages,
        :series,
        :translations,
        :contributor_roles
      ],
      additionalProperties: false
    })
  end

  defmodule CoverSample do
    @moduledoc "Representative cover on a publisher row."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "CoverSample",
      type: :object,
      properties: %{
        title: %Schema{type: :string},
        cover: HiraethWeb.Api.V1.Schemas.Cover
      },
      required: [:title, :cover],
      additionalProperties: false
    })
  end

  defmodule SeriesMembership do
    @moduledoc "A work slot inside a series."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "SeriesMembership",
      type: :object,
      properties: %{
        work_id: %Schema{type: :string},
        position: %Schema{type: :integer, nullable: true}
      },
      required: [:work_id, :position],
      additionalProperties: false
    })
  end

  defmodule Publisher do
    @moduledoc "A publisher index row or detail page."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    alias HiraethWeb.Api.V1.Schemas.{Book, CoverSample, Groupings}

    OpenApiSpex.schema(%{
      title: "Publisher",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        name: %Schema{type: :string},
        slug: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        editions_count: %Schema{type: :integer},
        cover_sample: %Schema{type: :object, nullable: true, allOf: [CoverSample]},
        groupings: Groupings,
        editions: %Schema{type: :array, items: Book}
      },
      required: [
        :id,
        :name,
        :slug,
        :description,
        :editions_count,
        :cover_sample,
        :groupings,
        :editions
      ],
      additionalProperties: false
    })
  end

  defmodule Series do
    @moduledoc "A series index row or detail page."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    alias HiraethWeb.Api.V1.Schemas.{Book, SeriesMembership}

    OpenApiSpex.schema(%{
      title: "Series",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        title: %Schema{type: :string},
        name: %Schema{type: :string},
        slug: %Schema{type: :string},
        publisher: %Schema{type: :string, nullable: true},
        publisher_slug: %Schema{type: :string, nullable: true},
        editions_count: %Schema{type: :integer},
        unknown_order: %Schema{type: :boolean},
        editions: %Schema{type: :array, items: Book},
        memberships: %Schema{type: :array, items: SeriesMembership},
        preview_editions: %Schema{type: :array, items: Book}
      },
      required: [
        :id,
        :title,
        :name,
        :slug,
        :publisher,
        :publisher_slug,
        :editions_count,
        :unknown_order,
        :editions,
        :memberships,
        :preview_editions
      ],
      additionalProperties: false
    })
  end

  defmodule ContributorSummary do
    @moduledoc "A contributor index row or detail page."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    alias HiraethWeb.Api.V1.Schemas.Book

    OpenApiSpex.schema(%{
      title: "ContributorSummary",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        name: %Schema{type: :string},
        display_name: %Schema{type: :string},
        slug: %Schema{type: :string},
        roles: %Schema{type: :array, items: %Schema{type: :string}},
        books_count: %Schema{type: :integer},
        books: %Schema{type: :array, items: Book}
      },
      required: [:id, :name, :display_name, :slug, :roles, :books_count, :books],
      additionalProperties: false
    })
  end

  defmodule PageMeta do
    @moduledoc "Pagination metadata for a collection response."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "PageMeta",
      type: :object,
      properties: %{
        page: %Schema{type: :integer},
        page_size: %Schema{type: :integer},
        total_count: %Schema{type: :integer},
        total_pages: %Schema{type: :integer}
      },
      required: [:page, :page_size, :total_count, :total_pages],
      additionalProperties: false
    })
  end

  defmodule BookPage do
    @moduledoc "A page of books."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "BookPage",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: HiraethWeb.Api.V1.Schemas.Book},
        meta: HiraethWeb.Api.V1.Schemas.PageMeta
      },
      required: [:data, :meta],
      additionalProperties: false
    })
  end

  defmodule EditionPage do
    @moduledoc "A page of editions."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "EditionPage",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: HiraethWeb.Api.V1.Schemas.Edition},
        meta: HiraethWeb.Api.V1.Schemas.PageMeta
      },
      required: [:data, :meta],
      additionalProperties: false
    })
  end

  defmodule PublisherPage do
    @moduledoc "A page of publishers."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "PublisherPage",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: HiraethWeb.Api.V1.Schemas.Publisher},
        meta: HiraethWeb.Api.V1.Schemas.PageMeta
      },
      required: [:data, :meta],
      additionalProperties: false
    })
  end

  defmodule SeriesPage do
    @moduledoc "A page of series."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "SeriesPage",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: HiraethWeb.Api.V1.Schemas.Series},
        meta: HiraethWeb.Api.V1.Schemas.PageMeta
      },
      required: [:data, :meta],
      additionalProperties: false
    })
  end

  defmodule ContributorPage do
    @moduledoc "A page of contributors."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "ContributorPage",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: HiraethWeb.Api.V1.Schemas.ContributorSummary},
        meta: HiraethWeb.Api.V1.Schemas.PageMeta
      },
      required: [:data, :meta],
      additionalProperties: false
    })
  end

  defmodule BookResponse do
    @moduledoc "A single book."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "BookResponse",
      type: :object,
      properties: %{data: HiraethWeb.Api.V1.Schemas.Book},
      required: [:data],
      additionalProperties: false
    })
  end

  defmodule EditionResponse do
    @moduledoc "A single edition."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "EditionResponse",
      type: :object,
      properties: %{data: HiraethWeb.Api.V1.Schemas.Edition},
      required: [:data],
      additionalProperties: false
    })
  end

  defmodule PublisherResponse do
    @moduledoc "A single publisher."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "PublisherResponse",
      type: :object,
      properties: %{data: HiraethWeb.Api.V1.Schemas.Publisher},
      required: [:data],
      additionalProperties: false
    })
  end

  defmodule SeriesResponse do
    @moduledoc "A single series."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "SeriesResponse",
      type: :object,
      properties: %{data: HiraethWeb.Api.V1.Schemas.Series},
      required: [:data],
      additionalProperties: false
    })
  end

  defmodule ContributorResponse do
    @moduledoc "A single contributor."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "ContributorResponse",
      type: :object,
      properties: %{data: HiraethWeb.Api.V1.Schemas.ContributorSummary},
      required: [:data],
      additionalProperties: false
    })
  end

  defmodule Error do
    @moduledoc "A typed API error."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        code: %Schema{
          type: :string,
          enum: ["not_found", "invalid_parameter", "internal_error"]
        },
        message: %Schema{type: :string},
        details: %Schema{type: :object, additionalProperties: true}
      },
      required: [:code, :message, :details],
      additionalProperties: false
    })
  end

  defmodule ErrorResponse do
    @moduledoc "The error envelope every failure response uses."
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      type: :object,
      properties: %{error: HiraethWeb.Api.V1.Schemas.Error},
      required: [:error],
      additionalProperties: false
    })
  end
end
