defmodule AshTemplate.Messages.LeaveTest do
  # Leaving a message for the site's team, through the actions every surface calls:
  # - a signed-in person, an agent no person paired and a paired agent each leave
  #   one, recorded as themselves, and get its receipt;
  # - who left it comes from the actor alone: no input can name a sender;
  # - the topic, the text and reply_to are bounded, and nothing is kept when refused;
  # - an operation_id answers its first message again, and refuses any other use;
  # - each sender leaves 10 an hour, and an agent past that is told the seconds
  #   to wait;
  # - only the site's admins read messages.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Agents, Messages, Repo}
  alias AshTemplate.Actors.{Agent, Human, System}
  alias AshTemplate.Messages.{Message, Refused}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{key: Ecto.UUID.generate()}
  end

  test "a person, an agent and a paired agent each leave a message as themselves", %{key: key} do
    {person, account} = person()

    assert {:ok, %Message{} = left} =
             Messages.leave_message(
               %{topic: "agents", body: "Hello team", reply_to: "me@example.com"},
               actor: person,
               context: %{client_key: key}
             )

    assert Message.receipt(left) == %{id: left.id, topic: "agents", inserted_at: left.inserted_at}
    assert %{human_account_id: id, agent_id: nil} = left = stored(left.id)
    assert id == account.id
    # Neither chose a name, so each is the wallet others see them by.
    assert Message.sender(left) == %{name: nil, wallet: account.wallet_address, ens_name: nil}

    agent = agent()

    assert {:ok, %{replayed: false, receipt: %{id: id, topic: "watchdog"}}} =
             leave(agent, "watchdog", %{body: "From an agent"}, key)

    assert %{human_account_id: nil, agent_id: agent_id, reply_to: nil} = left = stored(id)
    assert agent_id == agent.agent_id
    assert Message.sender(left) == %{name: nil, wallet: agent.wallet_address, ens_name: nil}

    {paired, account} = paired_agent()
    assert {:ok, %{receipt: %{id: id}}} = leave(paired, "agents", %{body: "For my person"}, key)
    assert %{human_account_id: human, agent_id: agent_id} = stored(id)
    assert {human, agent_id} == {account.id, paired.agent_id}
  end

  test "no input names the sender, so a message is never left as anyone else", %{key: key} do
    {person, _account} = person()
    {_other, other} = person()
    count = count()

    assert {:error, %Ash.Error.Invalid{}} =
             Messages.leave_message(
               %{topic: "agents", body: "Hi", human_account_id: other.id, sender_name: "Other"},
               actor: person,
               context: %{client_key: key}
             )

    assert {:error, %Ash.Error.Invalid{}} =
             leave(agent(), "agents", %{body: "Hi", agent_id: Ecto.UUID.generate()}, key)

    assert count() == count
  end

  test "the topic, the text and reply_to are bounded, and a refusal keeps nothing", %{key: key} do
    agent = agent()
    count = count()

    for {topic, input} <- [
          {"agents", %{body: String.duplicate("a", 2001)}},
          {"agents", %{body: ""}},
          {"agents", %{body: "Hi", reply_to: String.duplicate("a", 201)}},
          {"Agents!", %{body: "Hi"}},
          {String.duplicate("a", 41), %{body: "Hi"}}
        ] do
      assert {:error, %Ash.Error.Invalid{}} = leave(agent, topic, input, key)
    end

    assert {:ok, _} = leave(agent, "agents", %{body: String.duplicate("a", 2000)}, key)
    assert count() == count + 1
  end

  test "an operation_id answers its first message again and refuses any other use", %{key: key} do
    agent = agent()
    operation = Ecto.UUID.generate()
    input = %{body: "Once", reply_to: "a room", operation_id: operation}
    again = fn topic, input -> Messages.agent_leave_message(topic, input, actor: agent, context: %{client_key: key}) end

    assert {:ok, %{replayed: false, receipt: receipt}} = again.("agents", input)
    assert {:ok, %{replayed: true, receipt: ^receipt}} = again.("agents", input)

    for {topic, changed} <- [
          {"agents", %{input | body: "Twice"}},
          {"agents", %{input | reply_to: "elsewhere"}},
          {"watchdog", input}
        ] do
      assert {:error, %{errors: [%Refused{code: "idempotency_conflict"}]}} = again.(topic, changed)
    end

    assert count_by(agent) == 1
  end

  test "each sender leaves 10 messages an hour, then is told how long to wait" do
    agent = agent()

    for n <- 1..10 do
      assert {:ok, _} = leave(agent, "agents", %{body: "Message #{n}"}, Ecto.UUID.generate())
    end

    assert {:error, %Ash.Error.Invalid{errors: [%Refused{code: "too_many_requests", retry_after: seconds}]}} =
             leave(agent, "agents", %{body: "One more"}, Ecto.UUID.generate())

    assert seconds in 1..3600

    assert count_by(agent) == 10

    {person, account} = person()
    left = fn body -> Messages.leave_message(%{topic: "agents", body: body}, actor: person, context: %{client_key: Ecto.UUID.generate()}) end
    assert {:ok, _} = left.("Still free")

    # A person past it is told on the message field itself, as in a room's message box.
    for _ <- 2..10, do: :ok = AshTemplate.Limits.spend(:message, {:human, account.id})
    assert {:error, %Ash.Error.Invalid{errors: [%{field: :body}]}} = left.("One more")
  end

  test "only the site's admins read messages", %{key: key} do
    {person, _account} = person()
    {:ok, left} = Messages.leave_message(%{topic: "agents", body: "Private"}, actor: person, context: %{client_key: key})
    did = "did:privy:admin-" <> Ecto.UUID.generate()
    put_admins([did])

    admin = %RegentAgents.Person{privy_user_id: did, role: :admin}
    assert %{results: results} = Messages.list_messages!(actor: admin)
    assert left.id in Enum.map(results, & &1.id)

    for reader <- [
          person,
          agent(),
          %RegentAgents.Person{privy_user_id: did},
          %RegentAgents.Person{privy_user_id: "did:privy:not-listed", role: :admin},
          nil
        ] do
      assert {:error, %Ash.Error.Forbidden{}} = Messages.list_messages(actor: reader)
      assert {:error, %Ash.Error.Forbidden{}} = Messages.get_message(left.id, actor: reader)
    end
  end

  defp leave(agent, topic, input, key) do
    Messages.agent_leave_message(
      topic,
      Map.put_new(input, :operation_id, Ecto.UUID.generate()),
      actor: agent,
      context: %{client_key: key}
    )
  end

  defp stored(id), do: Ash.get!(Message, id, authorize?: false)
  defp count, do: Message |> Ash.read!(authorize?: false) |> length()

  defp count_by(agent),
    do: Message |> Ash.read!(authorize?: false) |> Enum.count(&(&1.agent_id == agent.agent_id))

  defp put_admins(admins) do
    old = Application.get_env(:regent_agents, :admins)
    Application.put_env(:regent_agents, :admins, admins)

    on_exit(fn ->
      if old,
        do: Application.put_env(:regent_agents, :admins, old),
        else: Application.delete_env(:regent_agents, :admins)
    end)
  end

  defp person do
    did = "did:privy:message-" <> Ecto.UUID.generate()
    wallet = wallet()
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    {Human.for_account(account), account}
  end

  defp agent, do: Agent.for_agent(Agents.sign_in_agent!(wallet(), actor: %System{}))

  defp paired_agent do
    did = "did:privy:message-" <> Ecto.UUID.generate()
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

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
