defmodule AshTemplateWeb.RoomDeleteTest do
  # A delete does its own work: the author's last message in a room takes them off
  # its posters inside the delete (`AshTemplate.Rooms.Message.ForgetPoster`), so an
  # open page of the room that hears it drops the message and reads nothing.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias AshTemplate.{Accounts, Repo, Rooms}
  alias AshTemplate.Actors.{Human, System}

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "an open room page hears a person's last message deleted and reads nothing" do
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    account = Accounts.register_verified!("did:privy:room-delete", wallet, [wallet], actor: %System{})
    author = Human.for_account(account)

    message =
      Rooms.post_message!(%{room: "general", body: "Here, then gone"},
        actor: author,
        context: %{client_key: "room-delete-test"}
      )

    conn = Plug.Conn.put_private(build_conn(), :live_view_connect_info, %{})
    {:ok, view, _html} = live(conn, "/rooms/general")
    assert has_element?(view, "#messages-#{message.id}")

    test = self()
    handler = "room-delete-test-#{:erlang.unique_integer()}"
    page = view.pid

    :telemetry.attach(
      handler,
      [:ash_template, :repo, :query],
      fn _event, _measure, meta, _ -> if self() == page, do: send(test, {:read, meta.query}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    :ok = Rooms.delete_message(message, actor: author)

    # The page hands the notice on to its messages as a message to itself
    # (`send_update`), so it answers this test only once that one is queued, ahead
    # of the render below.
    :sys.get_state(page)
    refute has_element?(view, "#messages-#{message.id}")
    refute_received {:read, _query}
  end
end
