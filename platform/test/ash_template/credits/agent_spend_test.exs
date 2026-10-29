defmodule AshTemplate.Credits.AgentSpendTest do
  # Invariants for switching agent spending on (Sean 111 a, 12 Oct 2026):
  # - two agents spending one person's last Credits at once, from two sites,
  #   never spend more than the person has;
  # - a pin retried after its answer was lost pays once and pins once;
  # - each new pin of a note costs one Credit: an operation_id that already
  #   paid an earlier pin is refused and pins nothing (Sean 2 a, 19 Oct 2026);
  # - a revoked allowance refuses the agent's next spend at once, keeps what it
  #   already bought, and the person's record says which agent spent, on which
  #   site, for what, under which pairing, and whether the charge completed;
  # - what an agent spent counts the Credits it used and forfeited, never those
  #   given back.
  #
  # The races need separate connections that really commit, as in the Credits
  # library's own concurrency tests: the rows these tests write stay in the test
  # database, and every test uses its own people and agents.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Agents, Notes, Repo}
  alias AshTemplate.Actors.{Agent, System}
  alias RegentCredits.Actor
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    grants = Application.get_env(:regent_credits, :agent_grants_enabled)
    Application.put_env(:regent_credits, :agent_grants_enabled, true)

    on_exit(fn ->
      Application.put_env(:regent_credits, :agent_grants_enabled, grants)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)
  end

  test "two agents on two sites asking 4 Credits each from 5 at once: exactly one is held" do
    person = person(5)
    first = agent(person, ["template"])
    second = agent(person, ["regents"])

    results =
      [{first, "template"}, {second, "regents"}]
      |> Task.async_stream(
        fn {agent, site} ->
          RegentCredits.hold(
            "race-#{agent.wallet}",
            person.did,
            Decimal.new(4),
            "Last Credits",
            actor: Actor.agent(person.did, agent.wallet, site, agent.pairing_id)
          )
        end,
        max_concurrency: 2
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _hold}, &1)) == 1
    assert [{:error, refused}] = Enum.reject(results, &match?({:ok, _hold}, &1))
    assert reason(refused) == NotEnoughCredits

    balance = RegentCredits.balance(person.did)
    assert Decimal.eq?(balance.held, 4)
    assert Decimal.eq?(balance.available, 1)
  end

  test "a pin retried after its answer was lost, from fresh processes, pays once" do
    person = person(5)
    agent = agent(person, ["template"]) |> as_site_agent()
    note = Notes.create_note!(%{title: "Retry"}, actor: agent)
    operation = Ecto.UUID.generate()

    # The first answer never reaches the agent; its process is gone.
    first = Task.async(fn -> Notes.pin_note(note, operation, actor: agent) end)
    assert {:ok, %{pinned_at: %DateTime{}}} = Task.await(first)

    # The agent sends the same request again, three times at once, with the
    # note as it last saw it: unpinned.
    retries =
      1..3
      |> Task.async_stream(fn _ -> Notes.pin_note(note, operation, actor: agent) end,
        max_concurrency: 3
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(retries, &match?({:ok, %{pinned_at: %DateTime{}}}, &1))
    assert Decimal.eq?(RegentCredits.balance(person.did).available, 4)
    assert [%{status: :charged}] = holds(person)
  end

  test "a pin after an unpin needs a new operation_id and pays again" do
    person = person(5)
    agent = agent(person, ["template"]) |> as_site_agent()
    note = Notes.create_note!(%{title: "Again"}, actor: agent)
    first = Ecto.UUID.generate()

    assert {:ok, pinned} = Notes.pin_note(note, first, actor: agent)
    assert {:ok, unpinned} = Notes.unpin_note(pinned, actor: agent)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Notes.pin_note(unpinned, first, actor: agent)

    assert Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidArgument{field: :operation_id}, &1))
    assert Decimal.eq?(RegentCredits.balance(person.did).available, 4)

    assert {:ok, %{pinned_at: %DateTime{}}} =
             Notes.pin_note(unpinned, Ecto.UUID.generate(), actor: agent)

    assert Decimal.eq?(RegentCredits.balance(person.did).available, 3)
    assert [%{status: :charged}, %{status: :charged}] = holds(person)
  end

  test "a revoked allowance refuses the next pin and keeps the pin already bought" do
    person = person(5)
    agent = agent(person, ["template"])
    actor = as_site_agent(agent)
    kept = Notes.create_note!(%{title: "Kept"}, actor: actor)

    later =
      Notes.create_note!(%{title: "Later"}, actor: actor)

    assert {:ok, _pinned} = Notes.pin_note(kept, Ecto.UUID.generate(), actor: actor)

    # The person turns the allowance off while the agent is still signed in.
    allow(person, agent.wallet, ["template"], false)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Notes.pin_note(later, Ecto.UUID.generate(), actor: actor)

    assert Enum.any?(errors, &match?(%Refused{reason: :agent_off}, &1))

    human = AshTemplate.Actors.Human.for_account(person.account)
    assert %{pinned_at: %DateTime{}} = Notes.get_my_note!(kept.id, actor: human)
    assert %{pinned_at: nil} = Notes.get_my_note!(later.id, actor: human)
    assert Decimal.eq?(RegentCredits.balance(person.did).available, 4)

    # What the person's Credits record keeps about the spend.
    assert [hold] = holds(person)
    assert hold.agent_address == agent.wallet
    assert hold.site == "template"
    assert hold.purpose == "note_pin"
    assert hold.pairing_id == agent.pairing_id
    assert hold.status == :charged
  end

  test "what an agent spent counts Credits used and forfeited, not those given back" do
    person = person(5)
    agent = agent(person, ["template"])
    key = "settled-#{agent.wallet}"

    {:ok, _held} =
      RegentCredits.hold(key, person.did, Decimal.new(4), "Settled",
        actor: Actor.agent(person.did, agent.wallet, "template", agent.pairing_id)
      )

    {:ok, _settled} =
      RegentCredits.settle(key, Decimal.new(1), Decimal.new(2), Decimal.new(1),
        actor: Actor.site("template")
      )

    {:ok, spent} =
      AshTemplate.Credits.spent_by(AshTemplate.Credits.person(person.account), agent.wallet)

    assert Decimal.eq?(spent, 3)
  end

  defp person(credits) do
    did = "did:privy:agent-spend-" <> Ecto.UUID.generate()
    wallet = wallet()
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})

    # A paid purchase, recorded and credited as the site's chain check does
    # once the payment lands; there is no chain in tests to check.
    {:ok, purchase} =
      RegentCredits.Purchase
      |> Ash.Changeset.for_create(
        :record,
        %{
          privy_user_id: did,
          wallet: wallet,
          chain: :base,
          amount: credits,
          number: Ecto.UUID.generate(),
          tx_hash: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
        },
        authorize?: false
      )
      |> Ash.create()

    {:ok, _credited} =
      RegentCredits.Purchase
      |> Ash.ActionInput.for_action(:credit, %{id: purchase.id}, authorize?: false)
      |> Ash.run_action()

    %{did: did, wallet: wallet, account: account}
  end

  # A paired agent with an allowance of 4 per spend and 10 a day on `sites`.
  defp agent(person, sites) do
    wallet = wallet()

    code =
      RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: person.did})

    pairing =
      RegentAgents.pair_agent!(code.code, "Agent", :codex,
        actor: %RegentAgents.Agent{wallet: wallet}
      )

    allow(person, wallet, sites, true)
    %{wallet: wallet, pairing_id: pairing.id, person: person}
  end

  defp allow(person, wallet, sites, enabled) do
    RegentCredits.set_agent_permission!(
      %{
        privy_user_id: person.did,
        agent_address: wallet,
        enabled: enabled,
        max_per_spend: 4,
        daily_limit: 10,
        sites: sites
      },
      actor: Actor.person(person.did, [person.wallet], "regents")
    )
  end

  # The agent as this site's agent sign-in makes it.
  defp as_site_agent(agent) do
    record = Agents.sign_in_agent!(agent.wallet, actor: %System{})
    {:ok, pairing} = RegentAgents.Authority.resolve(Repo, agent.wallet)
    Agent.paired(record, agent.person.account, pairing)
  end

  defp holds(person) do
    RegentCredits.holds!(actor: Actor.person(person.did, [person.wallet], "template"))
  end

  defp reason(%Ash.Error.Invalid{errors: [error]}), do: error.__struct__
  defp reason(error), do: error.__struct__

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
