defmodule HiraethWeb.OpsController do
  use HiraethWeb, :controller

  alias Hiraeth.Catalog.PublicWorkProjection
  alias Hiraeth.Covers
  alias Hiraeth.ServiceRole

  plug :require_ops_auth

  def index(conn, _params) do
    state = PublicWorkProjection.state()

    data = %{
      role: ServiceRole.current(),
      state: state,
      projection_count: projection_count(),
      cursor_count: 0,
      covers:
        Enum.reduce(Covers.audit_cache(), %{missing_cache: 0}, fn row, acc ->
          %{acc | missing_cache: acc.missing_cache + row.missing_cache}
        end),
      pending_candidates: pending_candidates(),
      failed_jobs: failed_jobs()
    }

    render(conn, :index, data)
  end

  defp require_ops_auth(conn, _opts) do
    username = System.get_env("HIRAETH_OPS_USERNAME")
    password = System.get_env("HIRAETH_OPS_PASSWORD")

    if username in [nil, ""] or password in [nil, ""] do
      conn |> send_resp(404, "") |> halt()
    else
      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    end
  end

  defp projection_count do
    Hiraeth.Repo.query!("select count(*) from catalog_public_works").rows
    |> List.first()
    |> List.first()
  rescue
    _ -> 0
  end

  defp pending_candidates do
    Hiraeth.Repo.query!(
      "select count(*) from record_candidates where review_decision = 'pending_review'"
    ).rows
    |> List.first()
    |> List.first()
  rescue
    _ -> 0
  end

  defp failed_jobs do
    Hiraeth.Repo.query!("select count(*) from oban_jobs where state = 'discarded'").rows
    |> List.first()
    |> List.first()
  rescue
    _ -> 0
  end
end
