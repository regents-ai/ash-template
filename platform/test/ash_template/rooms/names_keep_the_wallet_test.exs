defmodule AshTemplate.Rooms.NamesKeepTheWalletTest do
  # Invariant: the cleanup clears every person's stored short wallet, including one
  # saved under a wallet they no longer sign in with, and never a real name or an
  # agent's name.
  use ExUnit.Case, async: false

  alias AshTemplate.{Repo, Rooms}
  alias AshTemplate.Actors.{Agent, Human, System}

  Code.require_file("priv/repo/migrations/20261029104549_names_keep_the_wallet.exs")
  alias AshTemplate.Repo.Migrations.NamesKeepTheWallet

  @person "0x6666666666666666666666666666666666666666"
  @muter "0x7777777777777777777777777777777777777777"
  @agent "0x8888888888888888888888888888888888888888"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "short wallets go, under any wallet; names and agents stay" do
    person = human("did:privy:cleanup-person", @person)
    muter = human("did:privy:cleanup-muter", @muter)
    agent = Agent.for_agent(AshTemplate.Agents.sign_in_agent!(@agent, actor: %System{}))

    earlier = post(person, "Posted under an earlier wallet")
    named = post(person, "Posted with a name")
    by_agent = post(agent, "Posted by an agent", %{operation_id: Ecto.UUID.generate()})

    stored("room_messages", "author_name", earlier.id, "0x1111..2222")
    stored("room_messages", "author_name", named.id, "Ada")
    stored("room_messages", "author_name", by_agent.id, "0xabcd..ef01")

    person_mute = Rooms.mute_author!(earlier.id, actor: muter)
    agent_mute = Rooms.mute_author!(by_agent.id, actor: muter)
    stored("room_mutes", "muted_name", person_mute.id, "0x1111..2222")
    stored("room_mutes", "muted_name", agent_mute.id, "0xabcd..ef01")

    Enum.each(NamesKeepTheWallet.clear_short_wallets(Repo.default_prefix()), &Repo.query!/1)

    assert name("room_messages", "author_name", earlier.id) == nil
    assert name("room_messages", "author_name", named.id) == "Ada"
    assert name("room_messages", "author_name", by_agent.id) == "0xabcd..ef01"
    assert name("room_mutes", "muted_name", person_mute.id) == nil
    assert name("room_mutes", "muted_name", agent_mute.id) == "0xabcd..ef01"
  end

  defp human(did, wallet),
    do:
      AshTemplate.Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
      |> Human.for_account()

  defp post(actor, body, extra \\ %{}),
    do:
      Rooms.post_message!(Map.merge(%{room: "general", body: body}, extra),
        actor: actor,
        context: %{client_key: body}
      )

  defp stored(table, column, id, value),
    do:
      Repo.query!("UPDATE #{Repo.default_prefix()}.#{table} SET #{column} = $2 WHERE id = $1", [
        Ecto.UUID.dump!(id),
        value
      ])

  defp name(table, column, id) do
    %{rows: [[value]]} =
      Repo.query!("SELECT #{column} FROM #{Repo.default_prefix()}.#{table} WHERE id = $1", [
        Ecto.UUID.dump!(id)
      ])

    value
  end
end
