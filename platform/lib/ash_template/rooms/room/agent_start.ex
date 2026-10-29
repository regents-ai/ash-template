defmodule AshTemplate.Rooms.Room.AgentStart do
  @moduledoc """
  A room an agent starts for its person, the same on every surface: `%{room:
  Room.public/1, replayed: boolean}`. A retry, the same name and topic as a room
  that person already started, answers that room (`replayed: true`) and starts
  nothing, so it never spends the day's allowance again; of two such calls at
  once, the second answers the room the first started. A name another room has,
  or one of the person's own rooms with another name or topic, is
  `room_name_taken` and changes nothing; a start the room refuses is
  `invalid_room`, with the refused save; one its pairing no longer allows is
  `agent_not_paired`.
  """

  use Ash.Resource.Actions.Implementation

  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Refused, Room}

  @impl true
  def run(input, _opts, %{actor: actor}) do
    %{name: name, topic: topic} = input.arguments

    with :ok <- NotPaired.check(actor),
         {:ok, nil} <- started(name, actor) do
      start(name, topic, actor)
    else
      {:ok, %Room{} = room} -> retried(room, name, topic)
      error -> error
    end
  end

  defp start(name, topic, actor) do
    case Rooms.create_room(%{name: name, topic: topic}, actor: actor) do
      {:ok, room} ->
        {:ok, %{room: Room.public(room), replayed: false}}

      {:error, %Ash.Error.Invalid{} = error} ->
        if Room.name_taken?(error),
          do: taken(name, topic, actor),
          else: {:error, Refused.exception(code: "invalid_room", error: error)}

      error ->
        NotPaired.ended(error, actor)
    end
  end

  # A call that started the person's room with this name while this one ran.
  defp taken(name, topic, actor) do
    case started(name, actor) do
      {:ok, %Room{} = room} -> retried(room, name, topic)
      {:ok, nil} -> {:error, Refused.exception(code: "room_name_taken")}
      error -> error
    end
  end

  defp retried(%Room{name: name, topic: topic} = room, name, topic),
    do: {:ok, %{room: Room.public(room), replayed: true}}

  defp retried(_room, _name, _topic), do: {:error, Refused.exception(code: "room_name_taken")}

  # A name with no letter or number has no address, so no room was started with it.
  defp started(name, actor) do
    case Room.slug(name) do
      "" -> {:ok, nil}
      slug -> Rooms.get_started_room(slug, actor: actor)
    end
  end
end
