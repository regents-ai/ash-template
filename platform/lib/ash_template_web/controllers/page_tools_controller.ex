defmodule AshTemplateWeb.PageToolsController do
  @moduledoc """
  The doors behind the browser tools a page offers its own agent
  (`priv/tool_manifest.json`, `assets/js/public_tools.ts`).

  They act as whoever the page's session cookie names, through the same code
  interfaces and policies as the notes and room pages, so a tool can never do
  more than the person could on the page. Writes carry the page's CSRF token.
  Signed out, the notes tools and posting answer 401; reading a room needs no
  sign-in. Every refusal answers `{"error": {"code", "message", "hint"}}`, with
  `details` naming each field a save refused.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Human
  alias AshTemplate.{Notes, Rooms}
  alias AshTemplate.Notes.Note
  alias AshTemplate.Rooms.{Message, Room}
  alias AshTemplateWeb.{ClientAddress, NotesJSON}

  plug :put_actor

  @errors %{
    "authentication_required" =>
      {401, "Nobody is signed in on this page.",
       "Ask the person to sign in on the site, then call the tool again."},
    "note_not_found" =>
      {404, "There is no note of yours with that id.", "List your notes with notes_list."},
    "invalid_note" =>
      {422, "The note could not be saved.",
       "Send a title of 1 to 120 characters and, if you like, a body of up to 10,000 characters."},
    "room_not_found" =>
      {404, "There is no room with that name.",
       "The rooms are #{Enum.map_join(Room.all(), ", ", & &1.slug)}."},
    "invalid_message" =>
      {422, "The message could not be posted.",
       "details says why: a body is 1 to 2,000 characters, and after several quick posts wait a minute."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }

  def notes(conn, _params) do
    signed_in(conn, fn conn, actor ->
      case Notes.list_my_notes(actor: actor) do
        {:ok, notes} -> json(conn, %{notes: Enum.map(notes, &NotesJSON.note/1)})
        {:error, _error} -> refuse(conn, "unavailable")
      end
    end)
  end

  def note(conn, %{"id" => id}) do
    signed_in(conn, fn conn, actor ->
      case Notes.get_my_note(id, actor: actor) do
        {:ok, %Note{} = note} -> json(conn, %{note: NotesJSON.note(note)})
        {:ok, nil} -> refuse(conn, "note_not_found")
        {:error, %Ash.Error.Invalid{}} -> refuse(conn, "note_not_found")
        {:error, _error} -> refuse(conn, "unavailable")
      end
    end)
  end

  def create_note(conn, _params) do
    signed_in(conn, fn conn, actor ->
      case Notes.create_note(conn.body_params, actor: actor) do
        {:ok, note} -> conn |> put_status(:created) |> json(%{note: NotesJSON.note(note)})
        {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_note", error)
        {:error, _error} -> refuse(conn, "unavailable")
      end
    end)
  end

  # The newest 50 messages, without the authors the signed-in reader muted.
  def room_messages(conn, %{"room" => slug}) do
    with_room(conn, slug, fn conn, room ->
      case Rooms.list_room_messages(room.slug, actor: conn.assigns.actor) do
        {:ok, page} ->
          json(conn, %{room: room.slug, messages: Enum.map(page.results, &message/1)})

        {:error, _error} ->
          refuse(conn, "unavailable")
      end
    end)
  end

  def post_message(conn, %{"room" => slug}) do
    with_room(conn, slug, fn conn, room -> signed_in(conn, &post(&1, &2, room)) end)
  end

  defp put_actor(conn, _opts) do
    account = conn.assigns.current_human_account

    conn
    |> put_resp_header("cache-control", "no-store")
    |> assign(:actor, account && Human.for_account(account))
  end

  defp signed_in(%{assigns: %{actor: nil}} = conn, _respond),
    do: refuse(conn, "authentication_required")

  defp signed_in(conn, respond), do: respond.(conn, conn.assigns.actor)

  defp with_room(conn, slug, respond) do
    case Room.fetch(slug) do
      {:ok, room} -> respond.(conn, room)
      :error -> refuse(conn, "room_not_found")
    end
  end

  defp post(conn, actor, room) do
    case Rooms.post_message(Map.put(conn.body_params, "room", room.slug),
           actor: actor,
           context: %{client_key: ClientAddress.client_key(conn)}
         ) do
      {:ok, message} -> conn |> put_status(:created) |> json(%{message: message(message)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_message", error)
      {:error, _error} -> refuse(conn, "unavailable")
    end
  end

  defp message(%Message{} = message),
    do: Map.take(message, [:id, :room, :author_name, :body, :inserted_at, :edited_at])

  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end

  # Each refused field and why, worded as the page's own form shows it.
  defp details(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.filter(&AshPhoenix.FormData.Error.impl_for/1)
    |> Enum.flat_map(&List.wrap(AshPhoenix.FormData.Error.to_form_error(&1)))
    |> Enum.map(fn {field, message, vars} ->
      %{field: field, message: Enum.reduce(vars, message, &interpolate/2)}
    end)
  end

  defp interpolate({key, value}, message),
    do: String.replace(message, "%{#{key}}", fn _placeholder -> to_string(value) end)
end
