defmodule Hiraeth.Catalog.PublicProjection.Groupings do
  @moduledoc "The fixed facet groups rendered on a publisher page."

  @enforce_keys [
    :formats,
    :languages,
    :original_languages,
    :series,
    :translations,
    :contributor_roles
  ]
  defstruct [
    :formats,
    :languages,
    :original_languages,
    :series,
    :translations,
    :contributor_roles
  ]

  @type t :: %__MODULE__{
          formats: [Hiraeth.Catalog.PublicProjection.Grouping.t()],
          languages: [Hiraeth.Catalog.PublicProjection.Grouping.t()],
          original_languages: [Hiraeth.Catalog.PublicProjection.Grouping.t()],
          series: [Hiraeth.Catalog.PublicProjection.Grouping.t()],
          translations: [Hiraeth.Catalog.PublicProjection.Grouping.t()],
          contributor_roles: [Hiraeth.Catalog.PublicProjection.Grouping.t()]
        }
end
