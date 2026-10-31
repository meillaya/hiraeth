defmodule HiraethWeb.CatalogFilterParams do
  @moduledoc false

  @filter_params ~w(q publisher role contributor format language subject series year sort)

  def blank do
    Map.new(@filter_params, &{&1, ""})
  end

  def from_request(params) do
    filters =
      params
      |> Map.take(@filter_params)
      |> Map.filter(fn {_key, value} -> scalar?(value) end)

    query = Map.get(filters, "q", "")

    %{
      filters: filters,
      form_params: blank() |> Map.merge(filters) |> Map.put("q", query),
      page: Map.get(params, "page", "1"),
      query: query
    }
  end

  def filtered_path(base_path, params) do
    params =
      params
      |> Map.take(@filter_params)
      |> Enum.filter(fn {_key, value} -> scalar?(value) and value not in [nil, ""] end)
      |> Map.new()

    case params do
      map when map == %{} -> base_path
      map -> base_path <> "?" <> URI.encode_query(map)
    end
  end

  # Query params arrive as strings for normal requests and as maps or lists for
  # bracketed shapes such as `?q[a]=b`. Only scalars can be filtered or re-encoded.
  defp scalar?(value), do: is_binary(value) or is_number(value)
end
