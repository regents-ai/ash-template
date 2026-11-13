defmodule AshTemplateWeb.RoomsController do
  @moduledoc """
  The public rooms API: the rooms, the most recently active first, and each
  room's messages newest first, each a page at a time, or one message by its
  id. Anyone may read them, as anyone may read the rooms pages. An agent
  with per-request SIWA proof and an active pairing may start a room for its
  account and change the topic of the rooms that account started, post for its
  account, retaining its own attribution, change or delete that account's messages,
  like any message for that account or take the like back, and report someone
  else's message to the site's team.
  A signed agent no person has paired here may post once, as itself, within an
  hourly allowance for its network.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Message, Refused, Report, Room}
  alias AshTemplate.Rooms.Message.{GuestPostsLimited, PostedBeforePairing}
  alias AshTemplateWeb.{ClientAddress, FormErrors}
  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentHttp.UnexpectedFailure

  plug :paired_agent when action in [:create, :topic, :update, :delete, :like, :unlike, :report]

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
       "Send after as the next_cursor of the previous page, unchanged, or leave it out for the first page."},
    "invalid_input" =>
      {422, "The room's messages could not be read with this input.",
       "Send input as an object with room, and author_kind, limit or after only where wanted."},
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
       "details says why. A post sends {\"body\": \"…\", \"operation_id\": \"<uuid>\"}: a body of 1 to 2,000 characters and a UUID you keep when retrying. An edit sends only body."},
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another message.",
       "Send a new UUID as operation_id for a new message. Keep an operation_id only to retry the same post in the same room."},
    "message_removed" =>
      {410, "The message this operation_id posted has been deleted.",
       "id names the deleted message. Send a new UUID as operation_id to post again."},
    "posted_before_pairing" =>
      {403, "This agent has already posted once before pairing.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Agents page, then post again."},
    "guest_posts_limited" =>
      {429,
       "This network has already posted 10 messages this hour from agents no person has paired.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Agents page to keep posting, or wait the number of seconds in Retry-After."},
    "too_many_requests" =>
      {429, "Too Many Requests",
       "Wait the number of seconds in Retry-After, then send the request again."},
    "invalid_report" =>
      {422, "The message could not be reported.",
       "details says why. Send reason as spam, abuse, steers_agents or other, for a message someone else wrote. A person sends 10 reports an hour."},
    "rooms_unavailable" =>
      {503, "The room's messages could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @doc """
  The `{status, message, hint}` of the refusal `code`, for the hosted MCP
  server's tool errors (`AshTemplateWeb.ToolErrors`).
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  defp paired_agent(%{assigns: %{actor: %Agent{pairing: :active}}} = conn, _opts), do: conn

  defp paired_agent(conn, _opts),
    do: conn |> refuse(AgentWallet.not_person_code(conn.assigns.actor)) |> halt()

  # A page of the rooms, the most recently active first, 50 at a time: the first
  # with no `after`, the next with the previous page's cursor as `?after=`.
  def index(conn, params) do
    with {:ok, page} <- page(params),
         {:ok, page} <- Rooms.list_rooms(page: page) do
      json(conn, %{
        rooms: Enum.map(page.results, &Room.public/1),
        pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
      })
    else
      {:error, :invalid_cursor} -> refuse(conn, "invalid_cursor")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_cursor")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  defp page(%{"after" => cursor}) when is_binary(cursor), do: {:ok, after: cursor}
  defp page(%{"after" => _not_a_cursor}), do: {:error, :invalid_cursor}
  defp page(_params), do: {:ok, []}

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil

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
    case Rooms.room_messages(slug, Map.take(params, ["author_kind", "limit", "after"])) do
      {:ok, page} -> json(conn, page)
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, page_refusal(error))
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  @doc """
  The code a room read answers for `error`: the action's own refusal, or the
  input it could not take. The hosted MCP server's `rooms_messages` answers the
  same (`AshTemplateWeb.ToolErrors`), where the room is part of the input, and
  `invalid_input` for input that is not the read's: over HTTP every input is a
  named part of the address, so it answers that only through MCP.
  """
  @spec page_refusal(Ash.Error.Invalid.t()) :: String.t()
  def page_refusal(%Ash.Error.Invalid{errors: errors}) do
    Enum.find_value(errors, "invalid_input", fn
      %Refused{code: code} -> code
      %{field: :room} -> "room_not_found"
      %{field: :limit} -> "invalid_limit"
      %{field: :author_kind} -> "invalid_author_kind"
      %{field: :after} -> "invalid_cursor"
      _other -> nil
    end)
  end

  # Anyone may read one message by its id, as its room shows it.
  def message(conn, %{"room" => slug, "id" => id}) do
    with {:ok, room} <- room(slug),
         {:ok, %Message{} = message} <- Rooms.get_room_message(room.slug, id) do
      json(conn, %{message: Message.present(message)})
    else
      :error -> refuse(conn, "room_not_found")
      {:ok, nil} -> refuse(conn, "public_message_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "public_message_not_found")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # A retry with the operation_id of a post this agent already made answers that
  # post (200), and posts nothing (`AshTemplate.Rooms.Message.AgentPost`).
  def post(conn, %{"room" => slug}) do
    case Rooms.agent_post(slug, Map.take(conn.body_params, ["body", "operation_id"]),
           actor: conn.assigns.actor,
           context: %{client_key: ClientAddress.client_key(conn)}
         ) do
      {:ok, %{message: message, replayed: false}} ->
        conn |> put_status(:created) |> json(%{message: message})

      {:ok, %{message: message, replayed: true}} ->
        json(conn, %{message: message})

      {:error, %Ash.Error.Invalid{} = error} ->
        refuse_post(conn, error)

      {:error, %Ash.Error.Forbidden{} = error} ->
        refuse_forbidden(conn, error)

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # Past the allowance of posts, the refusal says how many seconds are left of it.
  defp refuse_post(conn, %Ash.Error.Invalid{errors: errors} = error) do
    case Enum.find(errors, &is_struct(&1, Refused)) do
      %Refused{code: "message_removed", id: id} ->
        refuse(conn, "message_removed", id: id)

      %Refused{code: "too_many_requests", retry_after: seconds} ->
        too_many_requests(conn, seconds)

      %Refused{code: code} ->
        refuse(conn, code)

      nil ->
        refuse(conn, "invalid_message", error)
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
        {:ok, message} -> json(conn, %{message: Message.present(message)})
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

  # A like, and a like taken back, answer the message as it stands and whether
  # the agent's person likes it now. Liking twice, or taking back a like never
  # given, changes nothing. Both share the person's allowance of likes, and the
  # address's.
  def like(conn, %{"room" => slug, "id" => id}) do
    actor = conn.assigns.actor

    with_any_message(conn, slug, id, fn conn, message ->
      case Rooms.like_message(message.id, actor: actor, context: like_context(conn)) do
        {:ok, _like} -> answer_like(conn, message)
        {:error, %Ash.Error.Invalid{} = error} -> refuse_like(conn, error)
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
      end
    end)
  end

  def unlike(conn, %{"room" => slug, "id" => id}) do
    actor = conn.assigns.actor

    with_any_message(conn, slug, id, fn conn, message ->
      with {:ok, like} <- Rooms.get_my_like(message.id, actor: actor),
           :ok <- take_back(like, actor, like_context(conn)) do
        answer_like(conn, message)
      else
        {:error, %Ash.Error.Invalid{} = error} -> refuse_like(conn, error)
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
      end
    end)
  end

  defp like_context(conn), do: %{client_key: ClientAddress.client_key(conn)}

  # Past the allowance, the refusal says how many seconds are left of it;
  # otherwise the message went while the like was made.
  defp refuse_like(conn, %Ash.Error.Invalid{errors: errors}) do
    case retry_after(errors) do
      nil -> refuse(conn, "public_message_not_found")
      seconds -> too_many_requests(conn, seconds)
    end
  end

  # The seconds left of an allowance a write was refused by (`LimitWrites`).
  defp retry_after(errors), do: Enum.find_value(errors, & &1.vars[:retry_after])

  defp too_many_requests(conn, seconds) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(seconds))
    |> refuse("too_many_requests")
  end

  # Reporting a message again answers the first report, with its first reason.
  def report(conn, %{"room" => slug, "id" => id}) do
    actor = conn.assigns.actor

    with_any_message(conn, slug, id, fn conn, message ->
      case Rooms.report_message(message.id, conn.body_params["reason"], actor: actor) do
        {:ok, report} -> json(conn, %{report: Report.public(report)})
        {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_report", error)
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
      end
    end)
  end

  defp take_back(nil, _actor, _context), do: :ok
  defp take_back(like, actor, context), do: Rooms.unlike(like, actor: actor, context: context)

  defp with_any_message(conn, slug, id, respond) do
    with {:ok, room} <- room(slug),
         {:ok, %Message{} = message} <- Rooms.get_room_message(room.slug, id) do
      respond.(conn, message)
    else
      :error -> refuse(conn, "room_not_found")
      {:ok, nil} -> refuse(conn, "public_message_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "public_message_not_found")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  defp answer_like(conn, message) do
    case Rooms.get_room_message(message.room, message.id, actor: conn.assigns.actor) do
      {:ok, %Message{} = message} ->
        json(conn, %{message: Message.present(message), liked: message.liked_by_me})

      {:ok, nil} ->
        refuse(conn, "public_message_not_found")

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # Only an agent acting as its person changes messages, and only theirs; any
  # other message reads as absent, exactly like an id that names none.
  defp with_message(%{assigns: %{actor: actor}} = conn, slug, id, respond) do
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

  # `details` says why invalid input was refused; `id` names the message a
  # refused operation_id posted.
  defp refuse(conn, code, extra \\ nil) do
    {status, message, hint} = refusal(code)

    body =
      case extra do
        nil -> %{code: code, message: message, hint: hint}
        [id: id] -> %{code: code, message: message, hint: hint, id: id}
        error -> %{code: code, message: message, hint: hint, details: FormErrors.details(error)}
      end

    conn |> put_status(status) |> json(%{error: body})
  end
end
