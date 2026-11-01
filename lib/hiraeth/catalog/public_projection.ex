defmodule Hiraeth.Catalog.PublicProjection do
  @moduledoc """
  Stable typed projections for public catalog reads.

  These structs are the public data boundary. The browser layer renders them and
  the versioned HTTP API serializes them; nothing serializes an Ash resource or a
  SQL row directly. Every builder takes a map and passes it to `struct!/2`, so a
  query column added without a matching struct field fails at the boundary
  instead of leaking into a response. Builders are idempotent: passing an
  already-projected struct returns it unchanged.
  """

  alias __MODULE__.{
    Book,
    Contributor,
    ContributorSummary,
    Cover,
    CoverSample,
    Dimensions,
    Edition,
    Format,
    Grouping,
    Groupings,
    Page,
    Publisher,
    Series,
    SeriesMembership,
    Source
  }

  @doc "Builds a typed public book projection from the bounded public catalog read model."
  @spec book!(map()) :: Book.t()
  def book!(%Book{} = book), do: book

  def book!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:formats, [], &map_list(&1, fn format -> format!(format) end))
      |> Map.update(:sources, [], &map_list(&1, fn source -> source!(source) end))
      |> Map.update(:source, nil, &maybe_struct(&1, fn source -> source!(source) end))
      |> Map.update(:cover, nil, &maybe_struct(&1, fn cover -> cover!(cover) end))
      |> Map.update(:authors, [], &map_list(&1, fn contributor -> contributor!(contributor) end))
      |> Map.update(
        :translators,
        [],
        &map_list(&1, fn contributor -> contributor!(contributor) end)
      )
      |> Map.update(:contributors_by_role, %{}, &contributors_by_role!/1)

    struct!(Book, attrs)
  end

  @doc "Builds a typed edition-format summary."
  @spec format!(map()) :: Format.t()
  def format!(%Format{} = format), do: format

  def format!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:identifiers, [], &List.wrap/1)
      |> Map.update(
        :dimensions,
        nil,
        &maybe_struct(&1, fn dimensions -> dimensions!(dimensions) end)
      )

    struct!(Format, attrs)
  end

  @doc "Builds a typed contributor summary."
  @spec contributor!(map()) :: Contributor.t()
  def contributor!(%Contributor{} = contributor), do: contributor
  def contributor!(attrs) when is_map(attrs), do: struct!(Contributor, attrs)

  @doc "Builds a typed public source provenance summary."
  @spec source!(map()) :: Source.t()
  def source!(%Source{} = source), do: source

  def source!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:field_sources, %{}, &(&1 || %{}))
      |> Map.update(:provider_permissions, %{}, &(&1 || %{}))

    struct!(Source, attrs)
  end

  @doc "Builds a typed publicly renderable cover."
  @spec cover!(map()) :: Cover.t()
  def cover!(%Cover{} = cover), do: cover

  def cover!(attrs) when is_map(attrs) do
    attrs
    |> Map.update(:responsive_variants, [], &List.wrap/1)
    |> then(&struct!(Cover, &1))
  end

  @doc "Builds a typed paged envelope whose entries are already projected."
  @spec page!(map()) :: Page.t()
  def page!(%Page{} = page), do: page
  def page!(attrs) when is_map(attrs), do: struct!(Page, attrs)

  @doc "Builds a typed edition detail projection."
  @spec edition!(map()) :: Edition.t()
  def edition!(%Edition{} = edition), do: edition

  def edition!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:authors, [], &map_list(&1, fn contributor -> contributor!(contributor) end))
      |> Map.update(
        :translators,
        [],
        &map_list(&1, fn contributor -> contributor!(contributor) end)
      )
      |> Map.update(:contributors_by_role, %{}, &contributors_by_role!/1)
      |> Map.update(:cover, nil, &maybe_struct(&1, fn cover -> cover!(cover) end))
      |> Map.update(:source, nil, &maybe_struct(&1, fn source -> source!(source) end))
      |> Map.update(
        :dimensions,
        nil,
        &maybe_struct(&1, fn dimensions -> dimensions!(dimensions) end)
      )

    struct!(Edition, attrs)
  end

  @doc "Builds a typed publisher index row or detail page."
  @spec publisher!(map()) :: Publisher.t()
  def publisher!(%Publisher{} = publisher), do: publisher

  def publisher!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:editions, [], &map_list(&1, fn edition -> edition!(edition) end))
      |> Map.update(
        :cover_sample,
        nil,
        &maybe_struct(&1, fn cover_sample -> cover_sample!(cover_sample) end)
      )
      |> Map.update(
        :groupings,
        nil,
        &maybe_struct(&1, fn groupings -> groupings!(groupings) end)
      )

    struct!(Publisher, attrs)
  end

  @doc "Builds a typed series index row or detail page."
  @spec series!(map()) :: Series.t()
  def series!(%Series{} = series), do: series

  def series!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:editions, [], &map_list(&1, fn edition -> edition!(edition) end))
      |> Map.update(
        :memberships,
        [],
        &map_list(&1, fn membership -> series_membership!(membership) end)
      )
      |> Map.update(:preview_editions, [], &map_list(&1, fn book -> book!(book) end))

    struct!(Series, attrs)
  end

  @doc "Builds a typed series membership entry."
  @spec series_membership!(map()) :: SeriesMembership.t()
  def series_membership!(%SeriesMembership{} = membership), do: membership
  def series_membership!(attrs) when is_map(attrs), do: struct!(SeriesMembership, attrs)

  @doc "Builds a typed contributor index row or detail page."
  @spec contributor_summary!(map()) :: ContributorSummary.t()
  def contributor_summary!(%ContributorSummary{} = summary), do: summary

  def contributor_summary!(attrs) when is_map(attrs) do
    attrs = Map.update(attrs, :books, [], &map_list(&1, fn book -> book!(book) end))
    struct!(ContributorSummary, attrs)
  end

  @doc "Builds a typed publisher cover sample."
  @spec cover_sample!(map()) :: CoverSample.t()
  def cover_sample!(%CoverSample{} = sample), do: sample

  def cover_sample!(attrs) when is_map(attrs) do
    attrs = Map.update(attrs, :cover, nil, &maybe_struct(&1, fn cover -> cover!(cover) end))
    struct!(CoverSample, attrs)
  end

  @doc "Builds typed physical dimensions."
  @spec dimensions!(map()) :: Dimensions.t()
  def dimensions!(%Dimensions{} = dimensions), do: dimensions
  def dimensions!(attrs) when is_map(attrs), do: struct!(Dimensions, attrs)

  @doc "Builds a typed counted facet value."
  @spec grouping!(map()) :: Grouping.t()
  def grouping!(%Grouping{} = grouping), do: grouping
  def grouping!(attrs) when is_map(attrs), do: struct!(Grouping, attrs)

  @doc "Builds the fixed facet groups rendered on a publisher page."
  @spec groupings!(map()) :: Groupings.t()
  def groupings!(%Groupings{} = groupings), do: groupings

  def groupings!(attrs) when is_map(attrs) do
    attrs =
      Enum.reduce(
        [:formats, :languages, :original_languages, :series, :translations, :contributor_roles],
        attrs,
        fn key, acc ->
          Map.update(acc, key, [], &map_list(&1, fn grouping -> grouping!(grouping) end))
        end
      )

    struct!(Groupings, attrs)
  end

  defp contributors_by_role!(contributors_by_role) when is_map(contributors_by_role) do
    Map.new(contributors_by_role, fn {role, contributors} ->
      {role, map_list(contributors, fn contributor -> contributor!(contributor) end)}
    end)
  end

  defp map_list(nil, _fun), do: []
  defp map_list(list, fun) when is_list(list), do: Enum.map(list, fun)

  defp maybe_struct(nil, _fun), do: nil
  defp maybe_struct(value, fun), do: fun.(value)
end
