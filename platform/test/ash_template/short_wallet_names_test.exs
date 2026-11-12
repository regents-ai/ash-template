defmodule AshTemplate.ShortWalletNamesTest do
  # Invariant (decision 11a, "names keep their wallet"): after the cleanup, no name
  # that came from a person's account is a short wallet, whichever wallet it was
  # shortened from, on a room post, a mute or a message left for the team. A chosen
  # name, an agent's own name and a row with no wallet to show instead keep theirs.
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias AshTemplate.{Accounts, Agents, Messages, Repo, Rooms}
  alias AshTemplate.Actors.{Agent, Human, System}

  Code.require_file("priv/repo/migrations/20261112153800_clear_short_wallet_names.exs")
  alias AshTemplate.Repo.Migrations.ClearShortWalletNames

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "a person's short wallet goes wherever it was saved; other names stay" do
    person = person()
    muter = person()
    agent = Agent.for_agent(Agents.sign_in_agent!(wallet(), actor: %System{}))
    {paired, _account} = paired_agent()

    earlier = post(person, "Posted under an earlier wallet")
    mixed = post(person, "Posted under a checksummed wallet")
    named = post(person, "Posted with a name")
    longer = post(person, "Posted under a longer name")
    lost = post(person, "Posted by an account that is gone")
    own = agent_post(agent, "Posted by an agent as itself")

    set("room_messages", earlier.id, author_name: "0x1111..2222")
    set("room_messages", mixed.id, author_name: "0xAbCd..Ef01")
    set("room_messages", named.id, author_name: "Ada")
    set("room_messages", longer.id, author_name: "0x1111..2222 fan")
    set("room_messages", lost.id, author_name: "0x1111..2222", author_wallet: nil)
    set("room_messages", own.id, author_name: "0xabcd..ef01")

    person_mute = Rooms.mute_author!(earlier.id, actor: muter)
    agent_mute = Rooms.mute_author!(own.id, actor: muter)
    set("room_mutes", person_mute.id, muted_name: "0x1111..2222")
    set("room_mutes", agent_mute.id, muted_name: "0xabcd..ef01")

    by_person = leave!(person)
    by_paired = leave!(paired)
    by_agent = leave!(agent)
    set("left_messages", by_person.id, sender_name: "0x1111..2222")
    set("left_messages", by_paired.id, sender_name: "0x3333..4444")
    set("left_messages", by_agent.id, sender_name: "0xabcd..ef01")

    clear()

    assert name("room_messages", earlier.id) == nil
    assert name("room_messages", mixed.id) == nil
    assert name("room_messages", named.id) == "Ada"
    assert name("room_messages", longer.id) == "0x1111..2222 fan"
    assert name("room_messages", lost.id) == "0x1111..2222"
    assert name("room_messages", own.id) == "0xabcd..ef01"
    assert name("room_mutes", person_mute.id) == nil
    assert name("room_mutes", agent_mute.id) == "0xabcd..ef01"
    assert name("left_messages", by_person.id) == nil
    assert name("left_messages", by_paired.id) == nil
    assert name("left_messages", by_agent.id) == "0xabcd..ef01"

    # The emptied rows still carry the wallet a page shows in the name's place.
    assert wallet_of("room_messages", earlier.id) == wallet_of("room_messages", named.id)
    assert is_binary(wallet_of("room_messages", earlier.id))
  end

  property "the short form of any wallet the site saved as a person's name goes" do
    person = person()
    message = post(person, "Posted under many wallets")

    check all(bytes <- binary(length: 20), upper <- list_of(boolean(), length: 40), max_runs: 25) do
      wallet = "0x" <> mixed_case(Base.encode16(bytes, case: :lower), upper)
      set("room_messages", message.id, author_name: RegentFormat.short_address(wallet))
      clear()
      assert name("room_messages", message.id) == nil
    end
  end

  defp clear,
    do: Enum.each(ClearShortWalletNames.clear(Repo.default_prefix()), &Repo.query!/1)

  defp person do
    did = "did:privy:short-wallet-" <> Ecto.UUID.generate()
    wallet = wallet()

    did
    |> Accounts.register_verified!(wallet, [wallet], actor: %System{})
    |> Human.for_account()
  end

  defp paired_agent do
    did = "did:privy:short-wallet-" <> Ecto.UUID.generate()
    person_wallet = wallet()
    agent_wallet = wallet()
    account = Accounts.register_verified!(did, person_wallet, [person_wallet], actor: %System{})
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})

    pairing =
      RegentAgents.pair_agent!(code.code, "Agent", :codex,
        actor: %RegentAgents.Agent{wallet: agent_wallet}
      )

    record = Agents.sign_in_agent!(agent_wallet, actor: %System{})
    {Agent.paired(record, account, pairing, Ecto.UUID.generate()), account}
  end

  defp post(person, body),
    do:
      Rooms.post_message!(%{room: "general", body: body},
        actor: person,
        context: %{client_key: Ecto.UUID.generate()}
      )

  defp agent_post(agent, body) do
    %{message: message} =
      Rooms.agent_post!("general", %{body: body, operation_id: Ecto.UUID.generate()},
        actor: agent,
        context: %{client_key: Ecto.UUID.generate()}
      )

    message
  end

  defp leave!(%Human{} = person),
    do:
      Messages.leave_message!(%{topic: "agents", body: "Hello team"},
        actor: person,
        context: %{client_key: Ecto.UUID.generate()}
      )

  defp leave!(%Agent{} = agent) do
    {:ok, %{receipt: %{id: id}}} =
      Messages.agent_leave_message(
        "agents",
        %{body: "Hello team", operation_id: Ecto.UUID.generate()},
        actor: agent,
        context: %{client_key: Ecto.UUID.generate()}
      )

    %{id: id}
  end

  # Writes columns of one row the way an older release saved them.
  defp set(table, id, columns) do
    sets =
      columns |> Enum.with_index(2) |> Enum.map_join(", ", fn {{k, _v}, i} -> "#{k} = $#{i}" end)

    Repo.query!(
      "UPDATE #{Repo.default_prefix()}.#{table} SET #{sets} WHERE id = $1",
      [Ecto.UUID.dump!(id) | Keyword.values(columns)]
    )
  end

  defp name(table, id), do: column(table, id, prefix(table) <> "_name")
  defp wallet_of(table, id), do: column(table, id, prefix(table) <> "_wallet")

  defp column(table, id, column) do
    %{rows: [[value]]} =
      Repo.query!("SELECT #{column} FROM #{Repo.default_prefix()}.#{table} WHERE id = $1", [
        Ecto.UUID.dump!(id)
      ])

    value
  end

  defp prefix("room_messages"), do: "author"
  defp prefix("room_mutes"), do: "muted"
  defp prefix("left_messages"), do: "sender"

  defp mixed_case(hex, upper) do
    hex
    |> String.graphemes()
    |> Enum.zip(upper)
    |> Enum.map_join(fn {char, up} -> if up, do: String.upcase(char), else: char end)
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
