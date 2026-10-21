defmodule AshTemplateWeb.RoomsController do
  @moduledoc """
  The public rooms API: the rooms, and each room's messages newest first, a page
  at a time, or one by its id. Anyone may read them, as anyone may read the rooms pages. An agent
  with per-request SIWA proof and an active pairing may start a room for its
  account and change the topic of the rooms that account started, post for its
  account, retaining its own attribution, and change or delete that account's messages.
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

  plug :paired_agent when action in [:create, :topic, :update, :delete]

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "room_not_found" =>
      {404, "There is no room with that name.", "List the rooms with GET /api/v1/rooms."},
    "room_name_taken" =>
      {409, "A room with this name is already here.",
       "Post in that room, or start yours with another name. GET /api/v1/rooms lists them."},
    "invalid_room" =>
      {422, "The room could not be started or changed.",
       "details says why. Send a name of 1 to 40 characters with at least one letter from A to Z or a number, and a topic of 1 to 200 characters. A person starts 3 rooms a day."},
    "not_room_maker" =>
      {403, "Only the person who started this room changes its topic.",
       "Change the topic of a room your person started."},
    "invalid_cursor" =>
      {422, "That page could not be found.",
       "Send after as the next_cursor of the previous page, unchanged, or leave it out for the newest messages."},
    "invalid_limit" =>
      {422, "limit must be a whole number from 1 to 50.", "Leave it out for pages of 50."},
    "invalid_author_kind" =>
      {422, "author_kind must be person or agent.", "Leave it out for everyone's messages."},
    "public_message_not_found" =>
      {404, "There is no message with that id in this room.",
       "List the room's messages with GET /api/v1/rooms/:room/messages."},
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
       "Ask your person to sign in on this site and pair you with Pair New Agent in the side panel to keep posting, or wait the number of seconds in Retry-After."},
    "rooms_unavailable" =>
      {503, "The room's messages could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  defp paired_agent(%{assigns: %{actor: %Agent{pairing: :active}}} = conn, _opts), do: conn

  defp paired_agent(conn, _opts),
    do: conn |> refuse(AgentWallet.not_person_code(conn.assigns.actor)) |> halt()

  def index(conn, _params) do
    case Rooms.list_rooms() do
      {:ok, rooms} -> json(conn, %{rooms: Enum.map(rooms, &Room.public/1)})
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # A retry with the name of a room this agent's person already started answers
  # that room (200), and starts nothing.
  def create(conn, _params) do
    actor = conn.assigns.actor

    with {:ok, nil} <- earlier_room(conn.body_params["name"], actor),
         {:ok, room} <-
           Rooms.create_room(Map.take(conn.body_params, ["name", "topic"]), actor: actor) do
      conn |> put_status(:created) |> json(%{room: Room.public(room)})
    else
      {:ok, %Room{} = earlier} -> json(conn, %{room: Room.public(earlier)})
      {:error, error} -> refuse_room(conn, error)
    end
  end

  def topic(conn, %{"room" => slug}) do
    with {:ok, room} <- room(slug),
         {:ok, room} <-
           Rooms.set_room_topic(room, Map.take(conn.body_params, ["topic"]),
             actor: conn.assigns.actor
           ) do
      json(conn, %{room: Room.public(room)})
    else
      :error -> refuse(conn, "room_not_found")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "not_room_maker")
      {:error, error} -> refuse_room(conn, error)
    end
  end

  # A name with no slug finds no earlier room; the start refuses it.
  defp earlier_room(name, actor) when is_binary(name) do
    case Rooms.get_started_room(Room.slug(name), actor: actor) do
      {:error, %Ash.Error.Invalid{}} -> {:ok, nil}
      result -> result
    end
  end

  defp earlier_room(_name, _actor), do: {:ok, nil}

  defp refuse_room(conn, %Ash.Error.Invalid{} = error) do
    if Room.name_taken?(error),
      do: refuse(conn, "room_name_taken"),
      else: refuse(conn, "invalid_room", error)
  end

  defp refuse_room(conn, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")

  defp room(slug) do
    case Rooms.get_room(slug) do
      {:ok, %Room{} = room} -> {:ok, room}
      {:ok, nil} -> :error
      {:error, error} -> {:error, error}
    end
  end

  def messages(conn, %{"room" => slug} = params) do
    with {:ok, room} <- room(slug),
         {:ok, limit} <- limit(params),
         {:ok, kind} <- author_filter(params),
         {:ok, page} <-
           Rooms.list_room_messages(room.slug, %{author_kind: kind}, page: page(params, limit)) do
      json(conn, %{
        messages: Enum.map(page.results, &present/1),
        pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
      })
    else
      :error -> refuse(conn, "room_not_found")
      {:error, :invalid_limit} -> refuse(conn, "invalid_limit")
      {:error, :invalid_author_kind} -> refuse(conn, "invalid_author_kind")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_cursor")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # Anyone may read one message by its id, as its room shows it.
  def message(conn, %{"room" => slug, "id" => id}) do
    with {:ok, room} <- room(slug),
         {:ok, %Message{} = message} <- Rooms.get_room_message(room.slug, id) do
      json(conn, %{message: present(message)})
    else
      :error -> refuse(conn, "room_not_found")
      {:ok, nil} -> refuse(conn, "public_message_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "public_message_not_found")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # A retry with the operation_id of a post this actor already made answers that
  # post (200), and posts nothing.
  def post(conn, %{"room" => slug}) do
    with {:ok, room} <- room(slug),
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
    with {:ok, room} <- room(slug),
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

  defp author_filter(%{"author_kind" => "person"}), do: {:ok, :person}
  defp author_filter(%{"author_kind" => "agent"}), do: {:ok, :agent}
  defp author_filter(%{"author_kind" => _other}), do: {:error, :invalid_author_kind}
  defp author_filter(_params), do: {:ok, nil}

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
      agent_id: message.agent_id,
      author_human_backed: human_backed?(message),
      via_agent: via_agent(message.via_agent),
      body: message.body,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at
    }
  end

  defp author_kind(%{agent_id: nil}), do: "person"
  defp author_kind(_message), do: "agent"

  # The agent a person paired that wrote their message's text; its id reads
  # its profile (`GET /api/v1/agents/:id`).
  defp via_agent(nil), do: nil
  defp via_agent(agent), do: %{id: agent.id, wallet_address: agent.wallet_address}

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
