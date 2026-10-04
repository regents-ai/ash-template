defmodule AshTemplateWeb.RoomsController do
  @moduledoc """
  The public rooms API: the rooms, and each room's messages newest first, a page
  at a time. Anyone may read them, as anyone may read the rooms pages. An agent
  signed in with its wallet (`AshTemplateWeb.Plugs.AgentWallet`) may post, as
  itself.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Room

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "room_not_found" =>
      {404, "There is no room with that name.", "List the rooms with GET /api/v1/rooms."},
    "invalid_cursor" =>
      {422, "That page could not be found.",
       "Send after as the next_cursor of the previous page, unchanged, or leave it out for the newest messages."},
    "invalid_limit" =>
      {422, "limit must be a whole number from 1 to 50.", "Leave it out for pages of 50."},
    "invalid_message" =>
      {422, "The message could not be posted.",
       "Send {\"body\": \"…\"} of 1 to 2,000 characters; after several quick posts, wait a minute."},
    "rooms_unavailable" =>
      {503, "The room's messages could not be reached right now.", "Try again in a moment."}
  }

  def index(conn, _params) do
    json(conn, %{
      rooms: Enum.map(Room.all(), &%{slug: &1.slug, name: &1.name, about: &1.about})
    })
  end

  def messages(conn, %{"room" => slug} = params) do
    with {:ok, room} <- Room.fetch(slug),
         {:ok, limit} <- limit(params),
         {:ok, page} <- Rooms.list_room_messages(room.slug, page: page(params, limit)) do
      json(conn, %{
        messages: Enum.map(page.results, &present/1),
        pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
      })
    else
      :error -> refuse(conn, "room_not_found")
      {:error, :invalid_limit} -> refuse(conn, "invalid_limit")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_cursor")
      {:error, _error} -> refuse(conn, "rooms_unavailable")
    end
  end

  def post(conn, %{"room" => slug}) do
    with {:ok, room} <- Room.fetch(slug),
         {:ok, message} <-
           Rooms.post_message(%{"room" => room.slug, "body" => conn.body_params["body"]},
             actor: conn.assigns.actor
           ) do
      conn |> put_status(:created) |> json(%{message: present(message)})
    else
      :error -> refuse(conn, "room_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_message")
      {:error, _error} -> refuse(conn, "rooms_unavailable")
    end
  end

  defp limit(%{"limit" => text}) do
    case Integer.parse(text) do
      {limit, ""} when limit in 1..50 -> {:ok, limit}
      _other -> {:error, :invalid_limit}
    end
  end

  defp limit(_params), do: {:ok, 50}

  defp page(%{"after" => cursor}, limit), do: [after: cursor, limit: limit]
  defp page(_params, limit), do: [limit: limit]

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil

  defp present(message) do
    %{
      id: message.id,
      room: message.room,
      author_name: message.author_name,
      author_kind: author_kind(message),
      body: message.body,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at
    }
  end

  defp author_kind(%{agent_id: nil}), do: "person"
  defp author_kind(_message), do: "agent"

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
