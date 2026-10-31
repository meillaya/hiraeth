defmodule Hiraeth.PublicApiContractTest do
  @moduledoc """
  Pins the formally typed public API surface.

  Every module that the browser layer or an external API consumer may call must
  export a typespec for each public function and a `t/0` type for each data
  shape it returns. The test walks compiled modules, so a new public function
  without a spec fails here instead of drifting silently.
  """

  use ExUnit.Case, async: true

  @public_api_modules [
    Hiraeth.Catalog.PublicProjection,
    Hiraeth.Catalog.PublicProjection.Book,
    Hiraeth.Catalog.PublicProjection.Contributor,
    Hiraeth.Catalog.PublicProjection.ContributorSummary,
    Hiraeth.Catalog.PublicProjection.Cover,
    Hiraeth.Catalog.PublicProjection.CoverSample,
    Hiraeth.Catalog.PublicProjection.Dimensions,
    Hiraeth.Catalog.PublicProjection.Edition,
    Hiraeth.Catalog.PublicProjection.Format,
    Hiraeth.Catalog.PublicProjection.Grouping,
    Hiraeth.Catalog.PublicProjection.Groupings,
    Hiraeth.Catalog.PublicProjection.Page,
    Hiraeth.Catalog.PublicProjection.Publisher,
    Hiraeth.Catalog.PublicProjection.Series,
    Hiraeth.Catalog.PublicProjection.SeriesMembership,
    Hiraeth.Catalog.PublicProjection.Source,
    Hiraeth.Ingestion.SidecarClient,
    HiraethWeb.PublicCatalog
  ]

  # Every projection module returns a struct, so it must also declare the type
  # that its callers and the HTTP schema layer compile against.
  @projection_modules @public_api_modules --
                        [
                          Hiraeth.Catalog.PublicProjection,
                          Hiraeth.Ingestion.SidecarClient,
                          HiraethWeb.PublicCatalog
                        ]

  test "every public API function has a typespec" do
    problems =
      Enum.flat_map(@public_api_modules, fn module ->
        case Code.ensure_loaded(module) do
          {:module, ^module} ->
            specs = spec_arities(module)

            module.__info__(:functions)
            |> Enum.reject(fn {name, _arity} -> generated?(name) end)
            |> Enum.filter(fn function -> not MapSet.member?(specs, function) end)
            |> Enum.map(fn {name, arity} ->
              "#{inspect(module)}.#{name}/#{arity} has no @spec"
            end)

          {:error, reason} ->
            ["#{inspect(module)} is not loadable: #{inspect(reason)}"]
        end
      end)

    assert problems == [], "public API typespec gaps:\n" <> Enum.join(problems, "\n")
  end

  test "every public projection declares a t/0 type" do
    problems =
      Enum.flat_map(@projection_modules, fn module ->
        case Code.ensure_loaded(module) do
          {:module, ^module} ->
            if exports_t_type?(module),
              do: [],
              else: ["#{inspect(module)} does not export @type t"]

          {:error, reason} ->
            ["#{inspect(module)} is not loadable: #{inspect(reason)}"]
        end
      end)

    assert problems == [], "public projection type gaps:\n" <> Enum.join(problems, "\n")
  end

  defp generated?(name), do: name |> Atom.to_string() |> String.starts_with?("__")

  defp spec_arities(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        specs
        |> Enum.map(fn {{name, arity}, _spec} -> {name, arity} end)
        |> MapSet.new()

      :error ->
        MapSet.new()
    end
  end

  defp exports_t_type?(module) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        Enum.any?(types, fn
          {:type, {:t, _definition, []}} -> true
          _type -> false
        end)

      :error ->
        false
    end
  end
end
