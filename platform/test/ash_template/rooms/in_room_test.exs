defmodule AshTemplate.Rooms.InRoomTest do
  # A room's messages read by kind of author (`author_kind` on `Rooms.Message`
  # `:in_room`): :person keeps people's messages, with those a paired agent wrote
  # for its person; :agent keeps those agents posted as themselves; with no kind,
  # every message. Each message shows its agents as they stand at the read: the
  # picture of an agent's own wallet, its World ID backing, the agent that wrote
  # for a person.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Agents, PublicIdentity, Rooms}
  alias AshTemplate.Actors.{Agent, Human, System}
  alias AshTemplate.Rooms.Message

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "author_kind keeps people's messages with their agents', or agents' own" do
    {person, account} = person()

    # A room of its own: other tests leave messages in general.
    room =
      Rooms.create_room!(%{name: "Author kinds", topic: "Who wrote it"},
        actor: person,
        context: %{client_key: key()}
      )

    said =
      Rooms.post_message!(%{room: room.slug, body: "From a person"},
        actor: person,
        context: %{client_key: key()}
      )

    %{message: for_person} =
      Rooms.agent_post!(room.slug, %{body: "For my person", operation_id: Ecto.UUID.generate()},
        actor: paired_agent(account),
        context: %{client_key: key()}
      )

    %{message: as_itself} =
      Rooms.agent_post!(room.slug, %{body: "As myself", operation_id: Ecto.UUID.generate()},
        actor: Agent.for_agent(Agents.sign_in_agent!(wallet(), actor: %System{})),
        context: %{client_key: key()}
      )

    read = fn input ->
      room.slug |> Rooms.list_room_messages!(input) |> Map.fetch!(:results) |> ids()
    end

    assert read.(%{author_kind: :person}) == ids([said, for_person])
    assert read.(%{author_kind: :agent}) == ids([as_itself])
    assert read.(%{}) == ids([said, for_person, as_itself])
  end

  test "a room's messages show their agents as they stand at the read" do
    {person, account} = person()

    room =
      Rooms.create_room!(%{name: "Who wrote it", topic: "Agents and people"},
        actor: person,
        context: %{client_key: key()}
      )

    said =
      Rooms.post_message!(%{room: room.slug, body: "From a person"},
        actor: person,
        context: %{client_key: key()}
      )

    agent_wallet = wallet()
    agent = Agents.sign_in_agent!(agent_wallet, actor: %System{})

    %{message: as_itself} =
      Rooms.agent_post!(room.slug, %{body: "As myself", operation_id: Ecto.UUID.generate()},
        actor: Agent.for_agent(agent),
        context: %{client_key: key()}
      )

    # Backed by a World ID person after posting.
    Agents.record_backing!(agent, "0x" <> String.duplicate("a", 64), 2, actor: %System{})

    for_them = paired_agent(account)

    %{message: for_person} =
      Rooms.agent_post!(room.slug, %{body: "For my person", operation_id: Ecto.UUID.generate()},
        actor: for_them,
        context: %{client_key: key()}
      )

    shown =
      room.slug |> Rooms.list_room_messages!() |> Map.fetch!(:results) |> Map.new(&{&1.id, &1})

    assert %{backed_agents: 2, author_squares: squares} = Message.public(shown[as_itself.id])
    assert squares == PublicIdentity.squares(%{wallet_address: agent_wallet})
    assert %{author_human_backed: true, via_agent: nil} = Message.present(shown[as_itself.id])

    via_id = for_them.agent_id
    assert %{via_agent: %{id: ^via_id}} = Message.present(shown[for_person.id])

    assert %{author_human_backed: false, via_agent: nil} = Message.present(shown[said.id])
    assert Message.public(shown[said.id]).author_squares == PublicIdentity.squares(account)
  end

  defp ids(messages), do: messages |> Enum.map(& &1.id) |> Enum.sort()

  defp person do
    did = "did:privy:in-room-" <> Ecto.UUID.generate()
    wallet = wallet()
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    {Human.for_account(account), account}
  end

  # An agent the person paired, posting as them.
  defp paired_agent(account) do
    agent_wallet = wallet()
    person = %RegentAgents.Person{privy_user_id: account.privy_user_id}
    code = RegentAgents.issue_pairing_code!(actor: person)

    pairing =
      RegentAgents.pair_agent!(code.code, "Agent", :codex,
        actor: %RegentAgents.Agent{wallet: agent_wallet}
      )

    record = Agents.sign_in_agent!(agent_wallet, actor: %System{})
    Agent.paired(record, account, pairing, Ecto.UUID.generate())
  end

  defp key, do: "in-room-" <> Ecto.UUID.generate()

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
