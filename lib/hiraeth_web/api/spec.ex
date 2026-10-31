defmodule HiraethWeb.Api.Spec do
  @moduledoc """
  OpenAPI 3.0 document for the versioned public catalog API.

  The document is generated from the controller operations and the schema
  modules, so the served contract and the serializers cannot drift apart without
  a failing test. Browser routes are excluded; only `/api/v1` appears here.
  """

  @behaviour OpenApiSpex.OpenApi

  alias HiraethWeb.Endpoint
  alias OpenApiSpex.{Info, OpenApi, Paths, Server, Tag}

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "Hiraeth Catalog API",
        version: "1.0.0",
        description: "Read-only, versioned access to the curated independent-publisher catalog."
      },
      tags: [
        %Tag{
          name: "catalog",
          description: "Books, editions, publishers, series, and contributors."
        }
      ],
      paths: api_paths()
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp api_paths do
    HiraethWeb.Router
    |> Paths.from_router()
    |> Map.filter(fn {path, _path_item} -> String.starts_with?(path, "/api/v1") end)
  end
end
