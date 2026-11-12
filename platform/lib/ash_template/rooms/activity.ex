defmodule AshTemplate.Rooms.Activity do
  @moduledoc """
  How many messages each room holds and when its newest was posted, counted once
  for every open page and held in `AshTemplate.SharedReading` under `key/1`. One
  runs on each machine.

  This is a reread on notice, the second of the two shapes the `elixir-stack`
  skill lets keep a shared reading. It hears every post and delete in every
  room (`Message.every_room_topic/0`) and counts that room again, at most once a
  second however many arrive.
  It holds nothing but which rooms are due a count: no queue, no copy of rows,
  and it never writes the database.

  A notice is sent at most once and can be lost, so each minute
  `AshTemplate.SharedReading.Heal` asks for every room to be counted again, the
  rooms read afresh so a room started since is among them and a room that is
  gone is forgotten, its key deleted so it never holds one of the kind's places.
  That pass also keeps each key's age under the kind's `within`, so a quiet room
  never reads as a stopped producer.

  The count is every message in the room, as a signed-out visitor could count
  them, never what one reader's mutes leave. A count reads every row of the
  room: fine for a room of thousands, and a site whose rooms grow past that
  keeps the count on a row of its own and publishes that row instead
  (`ash-frontend`, `references/public-figures.md`).

  The first count happens as it starts, so each key holds a reading or its
  degraded mark before the site serves a page.
  """

  use GenServer

  require Ash.Query

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Message
  alias AshTemplate.SharedReading

  @kind :room_activity

  @doc "Where the activity of `room`, a room's slug, is held."
  def key(room) when is_binary(room), do: {@kind, room}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    SharedReading.subscribe_heal(@kind)
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Message.every_room_topic())

    case slugs() do
      {:ok, rooms} -> Enum.each(rooms, &count/1)
      :error -> :ok
    end

    {:ok, MapSet.new()}
  end

  @impl true
  def handle_info(%{event: event, payload: %{room: room}}, due) when event in ~w(post destroy),
    do: {:noreply, due(due, room)}

  # An event added to the topic later is ignored here, so one that changes a
  # figure needs a clause above.
  def handle_info(%{event: _unknown}, due), do: {:noreply, due}

  def handle_info({:shared_reading_heal, @kind}, due) do
    case slugs() do
      {:ok, rooms} ->
        Enum.each(SharedReading.ids(@kind) -- rooms, &SharedReading.delete(key(&1)))
        {:noreply, Enum.reduce(rooms, due, &due(&2, &1))}

      :error ->
        {:noreply, due}
    end
  end

  def handle_info(:count, due) do
    Enum.each(due, &count/1)
    {:noreply, MapSet.new()}
  end

  # The first room to fall due starts the one-second wait; the rest join it.
  defp due(due, room) do
    if MapSet.size(due) == 0, do: Process.send_after(self(), :count, 1_000)
    MapSet.put(due, room)
  end

  # Every room's slug, or `:error` while the database is not answering: then no
  # room is counted, and no room's key is forgotten for want of a read.
  defp slugs do
    case Rooms.list_rooms() do
      {:ok, rooms} -> {:ok, Enum.map(rooms, & &1.slug)}
      {:error, _not_read} -> :error
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> :error
  end

  defp count(room) do
    case counted(room) do
      {:ok, activity} -> SharedReading.put(key(room), activity)
      {:error, _not_read} -> SharedReading.degraded(key(room))
    end
  end

  defp counted(room) do
    Message
    |> Ash.Query.filter(room == ^room)
    |> Ash.aggregate([{:messages, :count}, {:latest_at, :max, field: :inserted_at}],
      actor: nil,
      authorize?: true
    )
  rescue
    # The database not answering raises beneath Ash. It is a count not taken,
    # never a reason for this process, and the site with it, to stop.
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end
end
