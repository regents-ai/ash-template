defmodule AshTemplateWeb.PresenceTest do
  # Who comes and goes in a room is worked out once, as it happens, and the pages
  # that list the room's people hear just that, never the whole room:
  # - a person arrives with each tab they open, as `people/1` lists them;
  # - they leave once, when their last tab in the room closes;
  # - nothing is heard about other rooms.
  use ExUnit.Case, async: false

  alias AshTemplate.Actors.Human
  alias AshTemplateWeb.Presence

  test "a room's pages hear each arrival, and a leave only once the person's last tab closes" do
    room = "presence-#{:erlang.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Presence.here_topic(room))
    ada = %Human{human_account_id: 7, person: %{name: "Ada", wallet: "0x" <> String.duplicate("a", 40), ens_name: nil}}
    bea = %Human{human_account_id: 8, person: %{name: nil, wallet: "0x" <> String.duplicate("b", 40), ens_name: "bea.eth"}}

    first = open(room, ada)
    assert_receive {:here, ^room, [%{id: 7, name: "Ada", ens_name: nil}], []}

    second = open(room, ada)
    assert_receive {:here, ^room, [%{id: 7}], []}

    elsewhere = open("presence-elsewhere", bea)
    third = open(room, bea)
    assert_receive {:here, ^room, [%{id: 8, ens_name: "bea.eth"}], []}
    assert [%{id: 7, name: "Ada"}, %{id: 8, ens_name: "bea.eth"}] = Presence.people(room)

    close(first)
    refute_receive {:here, ^room, _arrived, _left}, 200

    close(second)
    assert_receive {:here, ^room, [], [7]}
    assert [%{id: 8}] = Presence.people(room)

    close(elsewhere)
    refute_receive {:here, _room, _arrived, _left}, 200

    close(third)
    assert_receive {:here, ^room, [], [8]}
  end

  # A tab with `room` open for `human`, until it is closed.
  defp open(room, human) do
    test = self()

    tab =
      spawn(fn ->
        {:ok, _ref} = Presence.join(room, human)
        send(test, :open)

        receive do
          :close -> :ok
        end
      end)

    assert_receive :open
    tab
  end

  defp close(tab) do
    ref = Process.monitor(tab)
    send(tab, :close)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
  end
end
