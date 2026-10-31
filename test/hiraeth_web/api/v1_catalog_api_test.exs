defmodule HiraethWeb.Api.V1CatalogApiTest do
  @moduledoc """
  Exercises the versioned HTTP API against the committed catalog.

  Every response is validated against the served OpenAPI schema, so the test
  fails when a serializer field is added, removed, or renamed without updating
  the published contract.
  """

  use HiraethWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions

  alias HiraethWeb.Api.Spec

  @moduletag :public_catalog_full

  setup_all do
    Hiraeth.CatalogCleanup.ensure_committed_catalog_fixtures!()
    :ok
  end

  test "GET /api/v1/books returns a schema-valid page", %{conn: conn} do
    body =
      conn
      |> get("/api/v1/books", %{"page_size" => "2"})
      |> json_response(200)

    assert_schema(body, "BookPage", spec())
    assert length(body["data"]) == 2
    assert body["meta"]["page"] == 1
    assert body["meta"]["page_size"] == 2
    assert body["meta"]["total_count"] > 0
  end

  test "GET /api/v1/books/:slug returns a schema-valid book", %{conn: conn} do
    body =
      conn
      |> get("/api/v1/books/deep-vellum-immigrant")
      |> json_response(200)

    assert_schema(body, "BookResponse", spec())
    assert is_list(body["data"]["formats"])
  end

  test "book detail drives valid edition, publisher, and contributor requests", %{conn: conn} do
    book =
      conn
      |> get("/api/v1/books/deep-vellum-immigrant")
      |> json_response(200)
      |> Map.fetch!("data")

    edition_slug = book["formats"] |> List.first() |> Map.fetch!("edition_slug")

    edition_body =
      conn
      |> get("/api/v1/editions/#{edition_slug}")
      |> json_response(200)

    assert_schema(edition_body, "EditionResponse", spec())

    if book["publisher_slug"] do
      publisher_body =
        conn
        |> get("/api/v1/publishers/#{book["publisher_slug"]}")
        |> json_response(200)

      assert_schema(publisher_body, "PublisherResponse", spec())
    end
  end

  test "collection endpoints return schema-valid pages", %{conn: conn} do
    publishers = conn |> get("/api/v1/publishers") |> json_response(200)
    assert_schema(publishers, "PublisherPage", spec())
    assert publishers["data"] != []

    series = conn |> get("/api/v1/series") |> json_response(200)
    assert_schema(series, "SeriesPage", spec())

    contributors =
      conn
      |> get("/api/v1/contributors", %{"role" => "translator"})
      |> json_response(200)

    assert_schema(contributors, "ContributorPage", spec())

    first_publisher = publishers["data"] |> List.first() |> Map.fetch!("slug")

    publisher_body =
      conn
      |> get("/api/v1/publishers/#{first_publisher}")
      |> json_response(200)

    assert_schema(publisher_body, "PublisherResponse", spec())
  end

  test "unknown resources return the typed 404 envelope", %{conn: conn} do
    for path <- [
          "/api/v1/books/no-such-book",
          "/api/v1/editions/no-such-edition",
          "/api/v1/publishers/no-such-publisher",
          "/api/v1/series/no-such-series",
          "/api/v1/contributors/no-such-contributor"
        ] do
      body = conn |> get(path) |> json_response(404)
      assert_schema(body, "ErrorResponse", spec())
      assert body["error"]["code"] == "not_found"
    end
  end

  test "invalid pagination and sort values return the typed 400 envelope", %{conn: conn} do
    for params <- [
          %{"page" => "0"},
          %{"page" => "10001"},
          %{"page_size" => "101"},
          %{"page" => "not-a-number"},
          %{"sort" => "bogus"}
        ] do
      body = conn |> get("/api/v1/books", params) |> json_response(400)
      assert_schema(body, "ErrorResponse", spec())
      assert body["error"]["code"] == "invalid_parameter"
    end
  end

  test "GET /api/v1/openapi.json serves the same document the tests validate", %{conn: conn} do
    body = conn |> get("/api/v1/openapi.json") |> json_response(200)

    assert String.starts_with?(body["openapi"], "3.0")
    assert body["info"]["version"] == "1.0.0"
    assert Map.has_key?(body["paths"], "/api/v1/books")
    refute Map.has_key?(body["paths"], "/browse")
  end

  defp spec, do: Spec.spec()
end
