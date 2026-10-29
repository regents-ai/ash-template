defmodule AshTemplateWeb.RoomsController do
  @moduledoc """
  The public rooms API: the rooms, and each room's messages newest first, a page
  at a time, or one by its id. Anyone may read them, as anyone may read the rooms pages. An agent
  with per-request SIWA proof and an active pairing may start a room for its
  account and change the topic of the rooms that account started, post for its
  account, retaining its own attribution, change or delete that account's messages,
  like any message for that account or take the like back, and report someone
  else's message to the site's team.
  A signed agent no person has paired here may post once, as itself, within an
  hourly allowance for its network.

  Each route runs the rooms action its browser tool and hosted MCP tool run, and
  this table holds the words of every rooms refusal, its person's mutes
  included, on each surface.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Message.{GuestPostsLimited, PostedBeforePairing}
  alias AshTemplate.Rooms.Refused
  alias AshTemplateWeb.{ClientAddress, FormErrors, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet

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
       "Send after as the next_cursor of the previous page, unchanged, or leave it out for the newest messages."},
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
       "details says why. A post sends {\"body\": \"…\", \"operation_id\": \"<uuid>\"}: a body of 1 to 2,000 characters and a UUID you keep when retrying. An edit sends only body. After several quick posts, wait a minute."},
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another message.",
       "Send a new UUID as operation_id for a new message. Keep an operation_id only to retry the same post in the same room."},
    "message_removed" =>
      {410, "The message this operation_id posted has been deleted.",
       "id names the deleted message. Send a new UUID as operation_id to post again."},
    "posted_before_pairing" =>
      {403, "This agent has already posted once before pairing.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Account page, then post again."},
    "guest_posts_limited" =>
      {429,
       "This network has already posted 10 messages this hour from agents no person has paired.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Account page to keep posting, or wait the number of seconds in Retry-After."},
    "mute_not_found" =>
      {404, "Your person has no mute with that id.",
       "List your person's mutes and use an id from there."},
    "invalid_mute" =>
      {422, "That author could not be muted.",
       "details says why. Send message_id, the id of a room message by the author to mute, from rooms messages."},
    "invalid_report" =>
      {422, "The message could not be reported.",
       "details says why. Send reason as spam, abuse, steers_agents or other, for a message someone else wrote. A person sends 10 reports an hour."},
    "rooms_unavailable" =>
      {503, "The room's messages could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @doc """
  The `{status, message, hint}` of the rooms refusal `code`, for every surface
  that answers it.
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  # Each input a change names, and the refusal an input it cannot take gets:
  # the room and the record the address names, then the save's own.
  @input %{
    rooms_create: {nil, "invalid_room"},
    rooms_topic: {nil, "invalid_room"},
    rooms_message: {"public_message_not_found", "public_message_not_found"},
    rooms_edit: {"message_not_found", "invalid_message"},
    rooms_delete: {"message_not_found", "message_not_found"},
    rooms_like: {"public_message_not_found", "public_message_not_found"},
    rooms_unlike: {"public_message_not_found", "public_message_not_found"},
    rooms_report: {"public_message_not_found", "invalid_report"},
    mutes_add: {nil, "invalid_mute"},
    mutes_remove: {"mute_not_found", "mute_not_found"}
  }

  # The refusals of a save, which say why in `details`.
  @saves ~w(invalid_room invalid_message invalid_report invalid_mute)

  @doc """
  The refusal `{code, extra}` a rooms `action` answers for `error`: the action's
  own refusal, or the input it could not take. A room it cannot take reads as
  one that names none, and so does a message's or a mute's id; other input is
  the save's refusal, with `details` where it has them. The paired agent routes
  and the hosted MCP server answer the same.
  """
  @spec input_refusal(atom(), Ash.Error.Invalid.t()) :: {String.t(), map()}
  def input_refusal(action, %Ash.Error.Invalid{errors: errors} = error) do
    {missing, other} = Map.fetch!(@input, action)

    cond do
      refused = Enum.find(errors, &match?(%Refused{}, &1)) -> answer(refused)
      Enum.any?(errors, &match?(%{field: :room}, &1)) -> {"room_not_found", %{}}
      missing && Enum.any?(errors, &match?(%{field: :id}, &1)) -> {missing, %{}}
      other in @saves -> {other, details(error)}
      true -> {other, %{}}
    end
  end

  @doc "A rooms action's own refusal as `{code, extra}`: what the code alone leaves out."
  @spec answer(Refused.t()) :: {String.t(), map()}
  def answer(%Refused{code: "message_removed", id: id}), do: {"message_removed", %{id: id}}

  def answer(%Refused{code: code, error: %Ash.Error.Invalid{} = error}),
    do: {code, details(error)}

  def answer(%Refused{code: code}), do: {code, %{}}

  defp details(error), do: %{details: FormErrors.details(error)}

  defp paired_agent(%{assigns: %{actor: %Agent{pairing: :active}}} = conn, _opts), do: conn

  defp paired_agent(conn, _opts),
    do: conn |> refuse(NotPaired.code(conn.assigns.actor)) |> halt()

  def index(conn, _params) do
    case Rooms.rooms_list() do
      {:ok, rooms} -> json(conn, rooms)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")
    end
  end

  # A retry with the name of a room this agent's person already started answers
  # that room (200), and starts nothing (`AshTemplate.Rooms.Room.AgentStart`).
  def create(conn, _params) do
    case Rooms.rooms_create(conn.body_params, actor: conn.assigns.actor) do
      {:ok, %{room: room, replayed: false}} -> conn |> put_status(:created) |> json(%{room: room})
      {:ok, %{room: room, replayed: true}} -> json(conn, %{room: room})
      {:error, error} -> refuse_error(conn, :rooms_create, error)
    end
  end

  def topic(conn, %{"room" => slug}),
    do:
      respond(
        conn,
        :rooms_topic,
        Rooms.rooms_topic(slug, addressed(conn), actor: conn.assigns.actor)
      )

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
  def message(conn, %{"room" => slug, "id" => id}),
    do: respond(conn, :rooms_message, Rooms.rooms_message(slug, id))

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

  defp refuse_post(conn, %Ash.Error.Invalid{errors: errors} = error) do
    case Enum.find(errors, &is_struct(&1, Refused)) do
      %Refused{} = refused -> refuse_with(conn, answer(refused))
      nil -> refuse(conn, "invalid_message", details(error))
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

  def update(conn, %{"room" => slug, "id" => id}),
    do:
      respond(
        conn,
        :rooms_edit,
        Rooms.rooms_edit(slug, id, addressed(conn), actor: conn.assigns.actor)
      )

  def delete(conn, %{"room" => slug, "id" => id}),
    do: respond(conn, :rooms_delete, Rooms.rooms_delete(slug, id, actor: conn.assigns.actor))

  def like(conn, %{"room" => slug, "id" => id}),
    do: respond(conn, :rooms_like, Rooms.rooms_like(slug, id, actor: conn.assigns.actor))

  def unlike(conn, %{"room" => slug, "id" => id}),
    do: respond(conn, :rooms_unlike, Rooms.rooms_unlike(slug, id, actor: conn.assigns.actor))

  def report(conn, %{"room" => slug, "id" => id}),
    do:
      respond(
        conn,
        :rooms_report,
        Rooms.rooms_report(slug, id, addressed(conn), actor: conn.assigns.actor)
      )

  # The address names the room and the message: a room or an id in the body
  # never chooses another.
  defp addressed(conn), do: Map.drop(conn.body_params, ["room", "id"])

  @doc """
  A rooms action's answer over HTTP, or its refusal as every surface gives it
  (`input_refusal/2`); the paired agent routes answer the mutes with it.
  """
  def respond(conn, _action, {:ok, answer}), do: json(conn, answer)
  def respond(conn, action, {:error, error}), do: refuse_error(conn, action, error)

  defp refuse_error(conn, action, %Ash.Error.Invalid{} = error),
    do: refuse_with(conn, input_refusal(action, error))

  # The pairing was revoked after this request was let in.
  defp refuse_error(conn, _action, %Ash.Error.Forbidden{errors: [%NotPaired{code: code}]}),
    do: refuse(conn, code)

  defp refuse_error(conn, _action, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("rooms_unavailable")

  defp refuse_with(conn, {code, extra}), do: refuse(conn, code, extra)

  defp refuse(conn, code, extra \\ %{}) do
    {status, message, hint} = refusal(code)

    conn
    |> put_status(status)
    |> json(%{error: Map.merge(%{code: code, message: message, hint: hint}, extra)})
  end
end
