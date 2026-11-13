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
  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplate.Notes
  alias AshTemplate.Notes.Note
  alias AshTemplateWeb.{FormErrors, NotesJSON}
  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentHttp.UnexpectedFailure

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
      {404, "You have no note with that id.", "List your notes with POST /api/v1/notes/list."},
    "invalid_cursor" =>
      {422, "That cursor is invalid.",
       "Send {} for the first page of notes, or {\"after\": \"<next_cursor>\"} with the previous page's pagination.next_cursor, unchanged."},
    "invalid_note" =>
      {422, "The note could not be saved.",
       "details says why. Send a title of 1 to 120 characters and an optional body of up to 10,000 characters. Agent creates also require operation_id, a UUID retained when retrying with fresh proof; omit it for updates."},
    "pin_being_paid" =>
      {409, "A pin for this note is being paid for, so it can't be deleted yet.",
       "Try again once the note shows as pinned, or in a few minutes when the pin's terms have run out."},
    "notes_unavailable" =>
      {503, "Your notes could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  # A page of the person's notes, 50 at a time: `{}` for the first, or the
  # previous page's cursor as `{"after": ...}`, since a signed request carries it
  # in its body and takes no query string.
  def index(conn, _params) do
    with {:ok, page} <- page(conn.body_params),
         {:ok, page} <- Notes.list_my_notes(actor: conn.assigns.actor, page: page) do
      json(conn, %{
        notes: Enum.map(page.results, &NotesJSON.note/1),
        pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
      })
    else
      {:error, :invalid_cursor} -> refuse(conn, "invalid_cursor")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_cursor")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable")
    end
  end

  defp page(body) when map_size(body) == 0, do: {:ok, limit: 50}

  defp page(%{"after" => cursor} = body) when map_size(body) == 1 and is_binary(cursor),
    do: {:ok, after: cursor, limit: 50}

  defp page(_body), do: {:error, :invalid_cursor}

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil

  def show(conn, %{"id" => id}), do: with_note(conn, id, &json(&1, %{note: NotesJSON.note(&2)}))

  # A retry with the operation_id of a note already made answers that note (200).
  def create(conn, _params) do
    actor = conn.assigns.actor

    with {:ok, nil} <- earlier_note(conn.body_params["operation_id"], actor),
         {:ok, note} <- Notes.create_note(conn.body_params, actor: actor) do
      conn |> put_status(:created) |> json(%{note: NotesJSON.note(note)})
    else
      {:ok, %Note{} = earlier} -> json(conn, %{note: NotesJSON.note(earlier)})
      {:error, error} -> refuse_change(conn, error)
    end
  end

  # The operation_id is the note's id. A missing or malformed one finds no earlier
  # note; the create refuses a malformed one.
  defp earlier_note(nil, _actor), do: {:ok, nil}

  defp earlier_note(operation_id, actor) do
    case Notes.get_my_note(operation_id, actor: actor) do
      {:error, %Ash.Error.Invalid{}} -> {:ok, nil}
      result -> result
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
        :ok -> json(conn, %{deleted: true, id: note.id})
        {:error, error} -> refuse_delete(conn, error)
      end
    end)
  end

  defp refuse_delete(conn, %Ash.Error.Invalid{errors: errors} = error) do
    if Enum.any?(errors, &is_struct(&1, Note.PinBeingPaid.Refused)),
      do: refuse(conn, "pin_being_paid"),
      else: conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable")
  end

  defp refuse_delete(conn, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable")

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
      conn -> conn |> refuse(AgentWallet.not_person_code(conn.assigns.actor)) |> halt()
    end
  end

  defp authenticate_person(conn) do
    with {:ok, pair} <- RegentPrivy.Proof.pair(conn),
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

  # Another account's note reads as absent, exactly like an id that names none.
  defp with_note(conn, id, respond) do
    case Notes.get_my_note(id, actor: conn.assigns.actor) do
      {:ok, %Note{} = note} -> respond.(conn, note)
      {:ok, nil} -> refuse(conn, "note_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "note_not_found")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable")
    end
  end

  defp refuse_change(conn, %Ash.Error.Invalid{} = error), do: refuse(conn, "invalid_note", error)

  defp refuse_change(conn, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("notes_unavailable")

  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, FormErrors.details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end
end
