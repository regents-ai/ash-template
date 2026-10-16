defmodule AshTemplateWeb.RoomsController do
  @moduledoc """
  The public rooms API: the rooms, and each room's messages newest first, a page
  at a time. Anyone may read them, as anyone may read the rooms pages. An agent
  with per-request SIWA proof and an active pairing may post for its account,
  retaining its own attribution, and change or delete that account's messages.
  A signed agent no person has paired here may post once, as itself, within an
  hourly allowance for its network.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Message, Room}
  alias AshTemplate.Rooms.Message.{GuestPostsLimited, PostedBeforePairing}
  alias AshTemplateWeb.{ClientAddress, FormErrors, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet

  plug :paired_agent when action in [:update, :delete]

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
    "message_not_found" =>
      {404, "Your person has no message with that id in this room.",
       "List the room's messages with GET /api/v1/rooms/:room/messages."},
    "invalid_message" =>
      {422, "The message could not be saved.",
       "details says why. A post sends {\"body\": \"…\", \"operation_id\": \"<uuid>\"}: a body of 1 to 2,000 characters and a UUID you keep when retrying. An edit sends only body. After several quick posts, wait a minute."},
    "posted_before_pairing" =>
      {403, "This agent has already posted once before pairing.",
       "Ask your person to sign in on this site and pair you with Pair New Agent in the side panel, then post again."},
    "guest_posts_limited" =>
      {429,
       "This network has already posted 10 messages this hour from agents no person has paired.",
       "Pair with your person to keep posting (regents ash-template agents pair), or wait the number of seconds in Retry-After."},
    "rooms_unavailable" =>
      {503, "The room's messages could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  defp paired_agent(%{assigns: %{actor: %Agent{pairing: :active}}} = conn, _opts), do: conn

  defp paired_agent(conn, _opts),
    do: conn |> refuse(AgentWallet.not_person_code(conn.assigns.actor)) |> halt()

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
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # A retry with the operation_id of a post this actor already made answers that
  # post (200), and posts nothing.
  def post(conn, %{"room" => slug}) do
    with {:ok, room} <- Room.fetch(slug),
         {:ok, nil} <- earlier_post(conn, room),
         {:ok, message} <-
           Rooms.post_message(
             Map.put(Map.take(conn.body_params, ["body", "operation_id"]), "room", room.slug),
             actor: conn.assigns.actor,
             context: %{client_key: ClientAddress.client_key(conn)}
           ) do
      conn |> put_status(:created) |> json(%{message: present(message)})
    else
      {:ok, %Message{} = earlier} -> json(conn, %{message: present(earlier)})
      :error -> refuse(conn, "room_not_found")
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_message", error)
      {:error, %Ash.Error.Forbidden{} = error} -> refuse_forbidden(conn, error)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # A missing or malformed operation_id finds no earlier post; the post refuses it.
  defp earlier_post(conn, room) do
    case Rooms.get_earlier_post(room.slug, conn.body_params["operation_id"],
           actor: conn.assigns.actor
         ) do
      {:error, %Ash.Error.Invalid{}} -> {:ok, nil}
      result -> result
    end
  end

  defp refuse_forbidden(conn, %Ash.Error.Forbidden{errors: errors} = error) do
    cond do
      Enum.any?(errors, &is_struct(&1, PostedBeforePairing)) ->
        refuse(conn, "posted_before_pairing")

      limited = Enum.find(errors, &is_struct(&1, GuestPostsLimited)) ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(limited.retry_after))
        |> refuse("guest_posts_limited")

      true ->
        conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  def update(conn, %{"room" => slug, "id" => id}) do
    with_message(conn, slug, id, fn conn, message ->
      case Rooms.edit_message(message, %{"body" => conn.body_params["body"]},
             actor: conn.assigns.actor
           ) do
        {:ok, message} -> json(conn, %{message: present(message)})
        {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_message", error)
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
      end
    end)
  end

  def delete(conn, %{"room" => slug, "id" => id}) do
    with_message(conn, slug, id, fn conn, message ->
      case Rooms.delete_message(message, actor: conn.assigns.actor) do
        :ok -> json(conn, %{deleted: true, id: message.id})
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
      end
    end)
  end

  # Only an agent acting as its person changes messages, and only theirs; any
  # other message reads as absent, exactly like an id that names none.
  defp with_message(
         %{assigns: %{actor: %Agent{pairing: :active} = actor}} = conn,
         slug,
         id,
         respond
       ) do
    with {:ok, room} <- Room.fetch(slug),
         {:ok, %Message{room: room_slug, human_account_id: author} = message}
         when room_slug == room.slug and author == actor.human_account_id <-
           Rooms.get_message(id, actor: actor) do
      respond.(conn, message)
    else
      :error ->
        refuse(conn, "room_not_found")

      {:error, error} when not is_struct(error, Ash.Error.Invalid) ->
        conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")

      _absent ->
        refuse(conn, "message_not_found")
    end
  end

  defp with_message(conn, _slug, _id, _respond),
    do: refuse(conn, AgentWallet.not_person_code(conn.assigns.actor))

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
      author_human_backed: human_backed?(message),
      via_agent: via_agent(message.via_agent),
      body: message.body,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at
    }
  end

  defp author_kind(%{agent_id: nil}), do: "person"
  defp author_kind(_message), do: "agent"

  # The agent a person paired that wrote their message's text.
  defp via_agent(nil), do: nil
  defp via_agent(agent), do: %{wallet_address: agent.wallet_address}

  # A person verified with World ID stands behind the agent that wrote it.
  defp human_backed?(%{agent: %{world_id_human_id: id}}), do: is_binary(id)
  defp human_backed?(_message), do: false

  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, FormErrors.details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end
end
