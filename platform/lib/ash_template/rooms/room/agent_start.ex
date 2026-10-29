defmodule AshTemplate.Rooms.Room.AgentStart do
  @moduledoc """
  A room an agent starts for its person, the same on every surface: `%{room:
  Room.public/1, replayed: boolean}`. A retry with the name of a room that person
  already started answers that room (`replayed: true`) and starts nothing, so it
  never spends the day's allowance again; of two calls with one name at once,
  the second answers the room the first started. A name another room has is
  `room_name_taken`; a start the room refuses is `invalid_room`, with the refused
  save; one its pairing no longer allows is `agent_not_paired`.
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
      {:ok, %Room{} = room} -> {:ok, %{room: Room.public(room), replayed: true}}
      error -> error
    end
  end

  defp start(name, topic, actor) do
    case Rooms.create_room(%{name: name, topic: topic}, actor: actor) do
      {:ok, room} ->
        {:ok, %{room: Room.public(room), replayed: false}}

      {:error, %Ash.Error.Invalid{} = error} ->
        if Room.name_taken?(error),
          do: taken(name, actor),
          else: {:error, Refused.exception(code: "invalid_room", error: error)}

      error ->
        NotPaired.ended(error, actor)
    end
  end

  # A call with the same name that started the room while this one ran: the
  # person's own room answers as a retry.
  defp taken(name, actor) do
    case started(name, actor) do
      {:ok, %Room{} = room} -> {:ok, %{room: Room.public(room), replayed: true}}
      {:ok, nil} -> {:error, Refused.exception(code: "room_name_taken")}
      error -> error
    end
  end

  # A name with no letter or number has no address, so no room was started with it.
  defp started(name, actor) do
    case Room.slug(name) do
      "" -> {:ok, nil}
      slug -> Rooms.get_started_room(slug, actor: actor)
    end
  end
end
