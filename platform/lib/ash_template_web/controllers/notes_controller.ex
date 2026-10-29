defmodule AshTemplateWeb.NotesController do
  @moduledoc """
  The notes API: the notes page's own Ash actions and policies, for a caller
  presenting the Privy proof pair `/api/v1/profile` takes, or for an agent the
  person paired, signing its request with its wallet
  (`AshTemplateWeb.Plugs.AgentWallet`), which acts as them. A change made here
  appears at once on every notes page its writer has open.

  Each route runs the note action its browser tool and hosted MCP tool run
  (`AshTemplate.Notes.Note`), and this table holds the words of every notes
  refusal, on each surface.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Notes
  alias AshTemplate.Notes.{Note, Refused}
  alias AshTemplateWeb.{FormErrors, PrivyProof, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet

  plug :authenticate

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "authentication_required" =>
      {401, "Sign in to read or change your notes.",
       "Send the access token as a Bearer token and the identity token in privy-id-token, both from the same sign-in."},
    "account_required" =>
      {403, "This sign-in hasn't been used on this site yet.",
       "Sign in on this site once, then retry."},
    "note_not_found" =>
      {404, "You have no note with that id.", "List your notes and use an id from there."},
    "invalid_note" =>
      {422, "The note could not be saved.",
       "details says why. Send a title of 1 to 120 characters and an optional body of up to 10,000 characters. An agent's new note also needs operation_id, a UUID it keeps when retrying; a person's new note and a change send none."},
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another note.",
       "Send a new UUID as operation_id for a new note. Keep an operation_id only to retry the same note."},
    "note_removed" =>
      {410, "The note this operation_id made has been deleted.",
       "id names the deleted note. Send a new UUID as operation_id to add it again."},
    "label_not_found" =>
      {404, "There is no label of yours with that id.", "Read the note and use its label.id."},
    "invalid_label_report" =>
      {422, "That label could not be rated.",
       "Send report as fits or does_not_fit. Only an answered label can be rated, once. Read the note before retrying."},
    "notes_unavailable" =>
      {503, "Your notes could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @doc """
  The `{status, message, hint}` of the notes refusal `code`, for every surface
  that answers it.
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  @doc """
  The refusal `{code, extra}` a note `action` answers for `error`: the action's own
  refusal, or the input it could not take. A note's or a label's id it cannot
  take reads as one that names none; other input to a save is `invalid_note`
  with `details`, and to a label's rating `invalid_label_report`. The paired
  agent routes and the hosted MCP server answer the same.
  """
  @spec input_refusal(atom(), Ash.Error.Invalid.t()) :: {String.t(), map()}
  def input_refusal(action, %Ash.Error.Invalid{errors: errors} = error) do
    case Enum.find(errors, &match?(%Refused{}, &1)) do
      %Refused{} = refused -> answer(refused)
      nil -> not_taken(action, Enum.any?(errors, &match?(%{field: :id}, &1)), error)
    end
  end

  defp not_taken(:notes_rate_label, true, _error), do: {"label_not_found", %{}}
  defp not_taken(:notes_rate_label, false, _error), do: {"invalid_label_report", %{}}

  defp not_taken(action, false, error) when action in [:notes_create, :notes_edit],
    do: {"invalid_note", %{details: FormErrors.details(error)}}

  defp not_taken(_action, _id?, _error), do: {"note_not_found", %{}}

  @doc "A notes action's own refusal as `{code, extra}`: what the code alone leaves out."
  @spec answer(Refused.t()) :: {String.t(), map()}
  def answer(%Refused{code: "invalid_note", error: error}),
    do: {"invalid_note", %{details: FormErrors.details(error)}}

  def answer(%Refused{code: "note_removed", id: id}), do: {"note_removed", %{id: id}}
  def answer(%Refused{code: code}), do: {code, %{}}

  def index(conn, _params),
    do: respond(conn, :notes_list, Notes.notes_list(actor: conn.assigns.actor))

  def show(conn, %{"id" => id}),
    do: respond(conn, :notes_get, Notes.notes_get(id, actor: conn.assigns.actor))

  # An agent's operation_id is spent once: a retry with it answers the note it
  # made (200) and saves nothing (`AshTemplate.Notes.Note.AgentCreate`).
  def create(%{assigns: %{actor: %Agent{} = actor}} = conn, _params) do
    case Notes.notes_create(conn.body_params, actor: actor) do
      {:ok, %{note: note, replayed: false}} -> conn |> put_status(:created) |> json(%{note: note})
      {:ok, %{note: note, replayed: true}} -> json(conn, %{note: note})
      {:error, error} -> refuse_error(conn, :notes_create, error)
    end
  end

  def create(conn, _params) do
    case Notes.create_note(conn.body_params, actor: conn.assigns.actor) do
      {:ok, note} -> conn |> put_status(:created) |> json(%{note: Note.present(note)})
      {:error, error} -> refuse_error(conn, :notes_create, error)
    end
  end

  def update(conn, %{"id" => id}),
    do:
      respond(
        conn,
        :notes_edit,
        Notes.notes_edit(id, conn.body_params, actor: conn.assigns.actor)
      )

  def delete(conn, %{"id" => id}),
    do: respond(conn, :notes_delete, Notes.notes_delete(id, actor: conn.assigns.actor))

  defp respond(conn, _action, {:ok, answer}), do: json(conn, answer)
  defp respond(conn, action, {:error, error}), do: refuse_error(conn, action, error)

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
      %{assigns: %{actor: %Agent{pairing: :active}}} = conn -> conn
      conn -> conn |> refuse(NotPaired.code(conn.assigns.actor)) |> halt()
    end
  end

  defp authenticate_person(conn) do
    with {:ok, pair} <- PrivyProof.pair(conn),
         {:ok, verified} <-
           RegentPrivy.Session.verify(pair, Application.get_env(:ash_template, :privy, [])),
         {:ok, account} <- VerifiedSession.account(verified) do
      assign(conn, :actor, Human.for_account(account))
    else
      {:error, :account_required} ->
        conn |> refuse("account_required") |> halt()

      {:error, {:configuration, _reason} = error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable") |> halt()

      {:error, {_stage, _reason}} ->
        conn |> refuse("authentication_required") |> halt()

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable") |> halt()
    end
  end

  defp refuse_error(conn, action, %Ash.Error.Invalid{} = error) do
    {code, extra} = input_refusal(action, error)
    refuse(conn, code, extra)
  end

  # The pairing was revoked after this request was let in.
  defp refuse_error(conn, _action, %Ash.Error.Forbidden{errors: [%NotPaired{code: code}]}),
    do: refuse(conn, code)

  defp refuse_error(conn, _action, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable")

  defp refuse(conn, code, extra \\ %{}) do
    {status, message, hint} = refusal(code)

    conn
    |> put_status(status)
    |> json(%{error: Map.merge(%{code: code, message: message, hint: hint}, extra)})
  end
end
