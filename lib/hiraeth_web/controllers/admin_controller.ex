defmodule HiraethWeb.AdminController do
  @moduledoc """
  Authenticated write console for ingestion candidate review.

  `/ops` is deliberately read-only health telemetry. This console is the only
  browser surface that writes ingestion state: it approves, rejects, ignores,
  or overrides a `RecordCandidate` and records the operator, timestamp, and
  note on the row through the existing Ash actions.

  Authentication is HTTP Basic Auth from `HIRAETH_ADMIN_USERNAME` and
  `HIRAETH_ADMIN_PASSWORD`. When either is unset the whole console returns 404,
  matching the `/ops` posture. The routes are also marked `noindex`.
  """

  use HiraethWeb, :controller

  require Ash.Query

  alias Hiraeth.Ingestion.{ProviderRun, RecordCandidate}

  plug :put_layout, false
  plug :require_admin_auth
  plug :put_noindex

  @candidate_limit 200

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Overview",
      counts: %{
        pending: count_candidates("pending_review"),
        approved: count_candidates("approved"),
        rejected: count_candidates("rejected"),
        ignored: count_candidates("ignored")
      },
      recent_runs: recent_runs()
    )
  end

  def candidates(conn, params) do
    filters = %{
      "decision" => params["decision"] || "pending_review",
      "diff" => params["diff"] || "all",
      "q" => String.trim(params["q"] || "")
    }

    render(conn, :candidates,
      page_title: "Candidates",
      filters: filters,
      candidates: list_candidates(filters)
    )
  end

  def show(conn, %{"id" => id}) do
    with {:ok, candidate} <- fetch_candidate(id),
         {:ok, candidate} <- Ash.load(candidate, [:provider_run, :source_snapshot]) do
      render(conn, :show,
        page_title: "Candidate #{short_id(candidate.id)}",
        candidate: candidate,
        metadata_json: Jason.encode!(candidate.normalized_metadata, pretty: true),
        raw_json: Jason.encode!(candidate.raw_metadata, pretty: true),
        findings_json: Jason.encode!(candidate.validation_findings, pretty: true)
      )
    else
      _error ->
        conn
        |> put_flash(:error, "Candidate not found.")
        |> redirect(to: ~p"/admin/candidates")
    end
  end

  def approve(conn, %{"id" => id} = params) do
    update_decision(conn, id, :approve_for_apply, note(params), "Candidate approved.")
  end

  def reject(conn, %{"id" => id} = params) do
    update_decision(conn, id, :reject, note(params), "Candidate rejected.")
  end

  def ignore(conn, %{"id" => id} = params) do
    update_decision(conn, id, :ignore, note(params), "Candidate ignored.")
  end

  def override(conn, %{"id" => id} = params) do
    candidate_params = params["candidate"] || %{}
    decision = candidate_params["decision"] || "pending_review"
    note = String.trim(candidate_params["note"] || "")

    with {:ok, metadata} <- decode_metadata(candidate_params["normalized_metadata"]),
         {:ok, candidate} <- fetch_candidate(id),
         {:ok, updated} <- apply_override(candidate, metadata, decision, note, actor(conn)) do
      conn
      |> put_flash(:info, "Candidate override saved.")
      |> redirect(to: ~p"/admin/candidates/#{updated.id}")
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/admin/candidates/#{id}")

      _error ->
        conn
        |> put_flash(:error, "Candidate override could not be saved.")
        |> redirect(to: ~p"/admin/candidates/#{id}")
    end
  end

  defp update_decision(conn, id, action, note, message) do
    attrs = review_attrs(note, actor(conn))

    with {:ok, candidate} <- fetch_candidate(id),
         {:ok, updated} <-
           candidate
           |> Ash.Changeset.for_update(action, attrs)
           |> Ash.update(actor: actor(conn)) do
      conn
      |> put_flash(:info, message)
      |> redirect(to: ~p"/admin/candidates/#{updated.id}")
    else
      _error ->
        conn
        |> put_flash(:error, "Candidate decision could not be saved.")
        |> redirect(to: ~p"/admin/candidates/#{id}")
    end
  end

  defp apply_override(candidate, metadata, decision, note, actor) do
    attrs =
      %{
        normalized_metadata: metadata,
        reviewer_note: blank_to_nil(note),
        review_actor_id: actor.id,
        reviewed_at: DateTime.utc_now(:second)
      }
      |> override_decision(decision)

    candidate
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update(actor: actor)
  end

  defp override_decision(attrs, "approved") do
    Map.merge(attrs, %{
      review_status: "accepted",
      review_decision: "approved",
      quarantine_status: "clear"
    })
  end

  defp override_decision(attrs, "rejected") do
    Map.merge(attrs, %{review_status: "rejected", review_decision: "rejected"})
  end

  defp override_decision(attrs, _pending) do
    Map.merge(attrs, %{review_status: "needs_review", review_decision: "pending_review"})
  end

  defp decode_metadata(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:ok, _not_an_object} -> {:error, "Override payload must be a JSON object."}
      {:error, _reason} -> {:error, "Override payload is not valid JSON."}
    end
  end

  defp decode_metadata(_value), do: {:error, "Override payload is required."}

  defp review_attrs(note, actor) do
    %{
      reviewer_note: blank_to_nil(note),
      review_actor_id: actor.id,
      reviewed_at: DateTime.utc_now(:second)
    }
  end

  defp note(params) do
    params
    |> get_in(["candidate", "note"])
    |> blank_to_nil()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp fetch_candidate(id) do
    Ash.get(RecordCandidate, id, authorize?: false)
  end

  defp count_candidates(decision) do
    RecordCandidate
    |> Ash.Query.filter(review_decision == ^decision)
    |> Ash.count!(authorize?: false)
  end

  defp list_candidates(filters) do
    RecordCandidate
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(@candidate_limit)
    |> filter_decision(filters["decision"])
    |> filter_diff(filters["diff"])
    |> filter_query(filters["q"])
    |> Ash.read!(authorize?: false)
  end

  defp filter_decision(query, value) when value in [nil, "", "all"], do: query

  defp filter_decision(query, value) do
    Ash.Query.filter(query, review_decision == ^value)
  end

  defp filter_diff(query, value) when value in [nil, "", "all"], do: query

  defp filter_diff(query, value) do
    Ash.Query.filter(query, diff_classification == ^value)
  end

  defp filter_query(query, value) when value in [nil, ""], do: query

  defp filter_query(query, value) do
    pattern = "%#{value}%"

    Ash.Query.filter(
      query,
      fragment("? ilike ?", candidate_identity, ^pattern) or
        fragment("? ilike ?", source_uri, ^pattern) or
        fragment("? ilike ?", record_type, ^pattern)
    )
  end

  defp recent_runs do
    ProviderRun
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(8)
    |> Ash.read!(authorize?: false)
  end

  defp actor(conn) do
    %{id: conn.assigns.admin_username, catalog_write?: true}
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_id), do: "unknown"

  defp require_admin_auth(conn, _opts) do
    {username, password} = admin_credentials()

    if username in [nil, ""] or password in [nil, ""] do
      conn |> send_resp(404, "") |> halt()
    else
      conn = Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      if conn.halted do
        conn
      else
        assign(conn, :admin_username, username)
      end
    end
  end

  defp admin_credentials do
    Application.get_env(:hiraeth, :admin_credentials) ||
      {System.get_env("HIRAETH_ADMIN_USERNAME"), System.get_env("HIRAETH_ADMIN_PASSWORD")}
  end

  defp put_noindex(conn, _opts) do
    put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
  end
end
