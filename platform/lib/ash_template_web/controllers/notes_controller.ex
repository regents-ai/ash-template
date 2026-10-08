defmodule AshTemplateWeb.NotesController do
  @moduledoc """
  The notes API: the notes page's own Ash actions and policies, for a caller
  presenting the Privy proof pair `/api/v1/profile` takes, or for an agent the
  person paired, signing its request with its wallet
  (`AshTemplateWeb.Plugs.AgentWallet`), which acts as them. A change made here
  appears at once on every notes page its writer has open.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Actors.Human
  alias AshTemplate.Notes
  alias AshTemplate.Notes.Note
  alias AshTemplateWeb.{NotesJSON, PrivyProof}
  alias AshTemplateWeb.Plugs.AgentWallet

  plug :authenticate

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "authentication_required" =>
      {401, "Sign in to read or change your notes.",
       "Send the access token as a Bearer token and the identity token in privy-id-token, both from the same sign-in."},
    "account_required" =>
      {403, "This sign-in has no account here yet.", "Sign in on the website once, then retry."},
    "agent_not_paired" =>
      {403, "Only an agent paired with a person, and backed by World ID, can use their notes.",
       "Ask your person for a pairing code from their account page, then pair with POST /api/agents/v1/pair."},
    "agent_not_backed" =>
      {403, "This agent is paired, but no person verified with World ID backs it yet.",
       "Accept your World ID person with regents auth accept-world-id, then send the request again."},
    "person_not_here" =>
      {403, "The person this agent is paired with has no account on this site yet.",
       "Ask your person to sign in on this website once, then send the request again."},
    "note_not_found" =>
      {404, "You have no note with that id.", "List your notes with GET /api/v1/notes."},
    "invalid_note" =>
      {422, "The note could not be saved.",
       "Send only title (1 to 120 characters) and body (up to 10,000 characters, optional)."},
    "notes_unavailable" =>
      {503, "Your notes could not be reached right now.", "Try again in a moment."}
  }

  def index(conn, _params) do
    case Notes.list_my_notes(actor: conn.assigns.actor) do
      {:ok, notes} -> json(conn, %{notes: Enum.map(notes, &NotesJSON.note/1)})
      {:error, _error} -> refuse(conn, "notes_unavailable")
    end
  end

  def show(conn, %{"id" => id}), do: with_note(conn, id, &json(&1, %{note: NotesJSON.note(&2)}))

  def create(conn, _params) do
    case Notes.create_note(conn.body_params, actor: conn.assigns.actor) do
      {:ok, note} -> conn |> put_status(:created) |> json(%{note: NotesJSON.note(note)})
      {:error, error} -> refuse_change(conn, error)
    end
  end

  def update(conn, %{"id" => id}) do
    with_note(conn, id, fn conn, note ->
      case Notes.update_note(note, conn.body_params, actor: conn.assigns.actor) do
        {:ok, note} -> json(conn, %{note: NotesJSON.note(note)})
        {:error, error} -> refuse_change(conn, error)
      end
    end)
  end

  def delete(conn, %{"id" => id}) do
    with_note(conn, id, fn conn, note ->
      case Notes.destroy_note(note, actor: conn.assigns.actor) do
        :ok -> send_resp(conn, :no_content, "")
        {:error, _error} -> refuse(conn, "notes_unavailable")
      end
    end)
  end

  defp authenticate(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if Siwa.AgentAuthPlug.signed_request?(conn),
      do: authenticate_agent(conn),
      else: authenticate_person(conn)
  end

  # An agent's signed request acts as the person it is paired with, or not at all.
  defp authenticate_agent(conn) do
    case AgentWallet.call(conn, []) do
      %{halted: true} = conn -> conn
      %{assigns: %{actor: %Human{}}} = conn -> conn
      conn -> conn |> refuse(AgentWallet.not_person_code(conn.assigns.actor)) |> halt()
    end
  end

  defp authenticate_person(conn) do
    with {:ok, pair} <- PrivyProof.pair(conn),
         {:ok, verified} <-
           RegentPrivy.Session.verify(pair, Application.get_env(:ash_template, :privy, [])),
         {:ok, account} <- VerifiedSession.account(verified) do
      assign(conn, :actor, Human.for_account(account))
    else
      {:error, :account_required} -> conn |> refuse("account_required") |> halt()
      {:error, {:configuration, _reason}} -> conn |> refuse("notes_unavailable") |> halt()
      {:error, {_stage, _reason}} -> conn |> refuse("authentication_required") |> halt()
      {:error, _account_read} -> conn |> refuse("notes_unavailable") |> halt()
    end
  end

  # Another account's note reads as absent, exactly like an id that names none.
  defp with_note(conn, id, respond) do
    case Notes.get_my_note(id, actor: conn.assigns.actor) do
      {:ok, %Note{} = note} -> respond.(conn, note)
      {:ok, nil} -> refuse(conn, "note_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "note_not_found")
      {:error, _error} -> refuse(conn, "notes_unavailable")
    end
  end

  defp refuse_change(conn, %Ash.Error.Invalid{}), do: refuse(conn, "invalid_note")
  defp refuse_change(conn, _error), do: refuse(conn, "notes_unavailable")

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
