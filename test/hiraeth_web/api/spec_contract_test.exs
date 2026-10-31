defmodule HiraethWeb.Api.SpecContractTest do
  @moduledoc """
  Pins the shape of the served OpenAPI document.

  The test fails when a versioned route is added without an operation spec, when
  a browser or health route leaks into the public contract, or when an operation
  loses its success response schema.
  """

  use ExUnit.Case, async: true

  alias HiraethWeb.Api.Spec

  @versioned_paths [
    "/api/v1/books",
    "/api/v1/books/{slug}",
    "/api/v1/contributors",
    "/api/v1/contributors/{slug}",
    "/api/v1/editions/{slug}",
    "/api/v1/publishers",
    "/api/v1/publishers/{slug}",
    "/api/v1/series",
    "/api/v1/series/{slug}"
  ]

  test "the document covers exactly the versioned catalog routes" do
    spec = Spec.spec()

    assert String.starts_with?(spec.openapi, "3.0")
    assert spec.info.title == "Hiraeth Catalog API"
    assert spec.info.version == "1.0.0"
    assert Map.keys(spec.paths) |> Enum.sort() == Enum.sort(@versioned_paths)
  end

  test "browser, health, and spec-render routes stay out of the public contract" do
    paths = Spec.spec().paths |> Map.keys()

    refute "/" in paths
    refute "/browse" in paths
    refute "/search" in paths
    refute "/health" in paths
    refute "/ready" in paths
    refute "/api/v1/openapi.json" in paths
  end

  test "every operation declares an operation id, a success schema, and an error response" do
    for {path, path_item} <- Spec.spec().paths do
      operation = path_item.get

      assert operation, "#{path} has no GET operation"
      assert is_binary(operation.operationId) and operation.operationId != ""

      success = response(operation, 200)
      assert success, "#{path} has no 200 response"

      media_type = success.content["application/json"]
      assert media_type, "#{path} has no application/json success body"
      assert media_type.schema, "#{path} success body has no schema"

      assert response(operation, 400) || response(operation, 404),
             "#{path} declares no 4xx response"
    end
  end

  defp response(operation, status) do
    Map.get(operation.responses, status) ||
      Map.get(operation.responses, Integer.to_string(status))
  end
end
