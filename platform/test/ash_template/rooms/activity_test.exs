defmodule AshTemplate.Rooms.ActivityTest do
  # The room counter counts only the rooms its reading may hold: the first rooms
  # in the list, as many as the kind has keys. It forgets a room that is gone, so
  # a gone room never holds one of those places, and never counts a room past
  # them, however busy.
  use ExUnit.Case, async: false

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Activity, Message, Room}
  alias AshTemplate.SharedReading

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)

    on_exit(fn ->
      Enum.each(SharedReading.ids(:room_activity), &SharedReading.delete(Activity.key(&1)))
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "each pass forgets a room that is gone and counts only the rooms it may hold" do
    # More rooms than the reading has keys.
    n = :erlang.unique_integer([:positive])

    for k <- 1..(SharedReading.keys(:room_activity) + 4) do
      Ash.Seed.seed!(Room, %{slug: "activity-#{n}-#{k}", name: "Activity #{k}", topic: "Count"})
    end

    {:ok, rooms} = Rooms.list_rooms()
    {held, past} = Enum.split(Enum.map(rooms, & &1.slug), SharedReading.keys(:room_activity))
    assert :ok = SharedReading.put(Activity.key("gone"), %{messages: 3, latest_at: nil})
    counter = start_supervised!(Activity)
    counts = count_reads(counter)

    SharedReading.heal(:room_activity)
    send(counter, :count)
    :sys.get_state(counter)

    assert Enum.sort(SharedReading.ids(:room_activity)) == Enum.sort(held)
    assert counts.() == length(held)

    # A post in a room past them is not counted.
    Phoenix.PubSub.broadcast(
      AshTemplate.PubSub,
      Message.every_room_topic(),
      %{event: "post", payload: %{room: List.last(past)}}
    )

    send(counter, :count)
    :sys.get_state(counter)
    assert counts.() == 0
    refute List.last(past) in SharedReading.ids(:room_activity)
  end

  # How many counts of a room's messages the counter has read since last asked.
  defp count_reads(counter) do
    test = self()
    handler = "activity-test-#{:erlang.unique_integer()}"

    :telemetry.attach(handler, [:ash_template, :repo, :query], fn _event, _measure, meta, _ ->
      if self() == counter and meta.query =~ ~r/count\(/i, do: send(test, :counted)
    end, nil)

    on_exit(fn -> :telemetry.detach(handler) end)
    fn -> drain(0) end
  end

  defp drain(n) do
    receive do
      :counted -> drain(n + 1)
    after
      0 -> n
    end
  end
end
