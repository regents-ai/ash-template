defmodule AshTemplate.Rooms.ActivityTest do
  # The room counter keeps a count for each room there is and none for a room
  # that is gone, so a gone room never holds one of the kind's sixteen places.
  use ExUnit.Case, async: false

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Activity
  alias AshTemplate.SharedReading

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)

    on_exit(fn ->
      Enum.each(SharedReading.ids(:room_activity), &SharedReading.delete(Activity.key(&1)))
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "each pass forgets a room that is gone and keeps every room there is" do
    {:ok, rooms} = Rooms.list_rooms()
    slugs = Enum.map(rooms, & &1.slug)
    counter = start_supervised!(Activity)

    assert :ok = SharedReading.put(Activity.key("gone"), %{messages: 3, latest_at: nil})
    SharedReading.heal(:room_activity)
    :sys.get_state(counter)

    assert Enum.sort(SharedReading.ids(:room_activity)) == Enum.sort(slugs)
  end
end
