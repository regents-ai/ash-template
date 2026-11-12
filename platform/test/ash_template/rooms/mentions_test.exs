defmodule AshTemplate.Rooms.MentionsTest do
  # A mention reaches the person it names by the name the room shows them by: the
  # name they chose, else the short wallet a person with no name shows by.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Activity, Rooms}
  alias AshTemplate.Actors.{Human, System}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "someone with no name is told when a message mentions their short wallet" do
    nameless = person("mention-nameless")
    writer = person("mention-writer")
    post!(nameless, "Hello")

    short = RegentFormat.short_address(nameless.wallet_address)
    post!(writer, "Welcome @#{String.upcase(short)}")

    assert [%{path: "/rooms/general"}] = notifications(nameless)
    assert [] = notifications(writer)
  end

  defp person(id) do
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    Accounts.register_verified!("did:privy:" <> id, wallet, [wallet], actor: %System{})
  end

  defp post!(account, body) do
    Rooms.post_message!(%{room: "general", body: body},
      actor: Human.for_account(account),
      context: %{client_key: account.id}
    )
  end

  defp notifications(account) do
    {:ok, page} = Activity.list_my_notifications(actor: Human.for_account(account), page: [limit: 50])
    page.results
  end
end
