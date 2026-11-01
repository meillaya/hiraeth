defmodule HiraethWeb.AdminControllerTest do
  @moduledoc "The candidate-review console authenticates, writes decisions, and audits operators."

  use HiraethWeb.ConnCase, async: false

  alias Hiraeth.Ingestion.RecordCandidate
  alias Hiraeth.TestSupport.IngestionFixtures

  @credentials {"review-admin", "correct horse battery staple"}

  setup do
    previous = Application.get_env(:hiraeth, :admin_credentials)
    Application.put_env(:hiraeth, :admin_credentials, @credentials)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:hiraeth, :admin_credentials)
      else
        Application.put_env(:hiraeth, :admin_credentials, previous)
      end
    end)

    suffix = "admin-#{System.unique_integer([:positive])}"
    candidate = IngestionFixtures.create_candidate!(%{suffix: suffix})

    %{candidate: candidate}
  end

  test "returns 404 when admin credentials are not configured", %{conn: conn} do
    Application.delete_env(:hiraeth, :admin_credentials)

    assert conn |> get("/admin") |> response(404)
  end

  test "requires Basic Auth", %{conn: conn} do
    assert conn |> get("/admin") |> response(401)

    conn =
      conn
      |> put_req_header("authorization", basic_auth("review-admin", "wrong"))
      |> get("/admin")

    assert conn.status == 401

    conn =
      build_conn()
      |> put_req_header(
        "authorization",
        basic_auth("review-admin", "correct horse battery staple")
      )
      |> get("/admin")

    assert conn.status == 200
    assert conn.resp_body =~ "Ingestion review"
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
  end

  test "lists and shows candidates", %{conn: conn, candidate: candidate} do
    conn =
      conn
      |> put_req_header(
        "authorization",
        basic_auth("review-admin", "correct horse battery staple")
      )
      |> get("/admin/candidates")

    assert conn.status == 200
    assert conn.resp_body =~ candidate.candidate_identity

    conn =
      build_conn()
      |> put_req_header(
        "authorization",
        basic_auth("review-admin", "correct horse battery staple")
      )
      |> get("/admin/candidates/#{candidate.id}")

    assert conn.status == 200
    assert conn.resp_body =~ candidate.fingerprint
    assert conn.resp_body =~ "Approve for apply"
  end

  test "approves a candidate with an operator audit trail", %{
    conn: conn,
    candidate: candidate
  } do
    conn = authenticate(conn)

    conn =
      post_decision(conn, candidate, "approve", %{
        "candidate" => %{"note" => "Source metadata verified."}
      })

    assert redirected_to(conn) == "/admin/candidates/#{candidate.id}"

    updated = Ash.get!(RecordCandidate, candidate.id, authorize?: false)
    assert updated.review_decision == "approved"
    assert updated.review_status == "accepted"
    assert updated.reviewer_note == "Source metadata verified."
    assert updated.review_actor_id == "review-admin"
    assert updated.reviewed_at
  end

  test "rejects and ignores candidates", %{conn: conn, candidate: candidate} do
    conn = authenticate(conn)

    conn =
      post_decision(conn, candidate, "reject", %{"candidate" => %{"note" => "Not a book."}})

    assert redirected_to(conn) == "/admin/candidates/#{candidate.id}"

    assert Ash.get!(RecordCandidate, candidate.id, authorize?: false).review_decision ==
             "rejected"

    conn =
      post_decision(conn, candidate, "ignore", %{"candidate" => %{"note" => "Duplicate."}})

    assert redirected_to(conn) == "/admin/candidates/#{candidate.id}"
    assert Ash.get!(RecordCandidate, candidate.id, authorize?: false).review_decision == "ignored"
  end

  test "overrides normalized metadata, recalculates the fingerprint, and can approve",
       %{conn: conn, candidate: candidate} do
    conn = authenticate(conn)
    metadata = %{"title" => "Corrected title", "isbn_13" => "9781646050001"}

    conn =
      post_decision(conn, candidate, "override", %{
        "candidate" => %{
          "normalized_metadata" => Jason.encode!(metadata),
          "decision" => "approved",
          "note" => "Publisher page corrected."
        }
      })

    assert redirected_to(conn) == "/admin/candidates/#{candidate.id}"

    updated = Ash.get!(RecordCandidate, candidate.id, authorize?: false)
    assert updated.normalized_metadata["title"] == "Corrected title"
    assert updated.review_decision == "approved"
    assert updated.review_status == "accepted"
    assert updated.review_actor_id == "review-admin"
    assert updated.fingerprint != candidate.fingerprint
  end

  test "rejects an invalid override payload without changing the candidate", %{
    conn: conn,
    candidate: candidate
  } do
    conn = authenticate(conn)

    conn =
      post_decision(conn, candidate, "override", %{
        "candidate" => %{"normalized_metadata" => "not json", "decision" => "approved"}
      })

    assert redirected_to(conn) == "/admin/candidates/#{candidate.id}"

    updated = Ash.get!(RecordCandidate, candidate.id, authorize?: false)
    assert updated.review_decision == "pending_review"
    assert updated.normalized_metadata == candidate.normalized_metadata
  end

  test "ops stays a read-only GET surface" do
    routes = HiraethWeb.Router.__routes__()

    ops_routes = Enum.filter(routes, &(&1.path == "/ops"))

    assert Enum.map(ops_routes, & &1.verb) == [:get]
  end

  defp authenticate(conn) do
    conn =
      put_req_header(
        conn,
        "authorization",
        basic_auth("review-admin", "correct horse battery staple")
      )

    # Establish the session/CSRF token the same way a browser would.
    conn = get(conn, "/admin")
    assert conn.status == 200
    conn
  end

  defp post_decision(conn, candidate, action, params) do
    token = Plug.Conn.get_session(conn, "_csrf_token")
    assert is_binary(token)

    post(
      conn,
      "/admin/candidates/#{candidate.id}/#{action}",
      Map.put(params, "_csrf_token", token)
    )
  end

  defp basic_auth(username, password) do
    "Basic " <> Base.encode64("#{username}:#{password}")
  end
end
