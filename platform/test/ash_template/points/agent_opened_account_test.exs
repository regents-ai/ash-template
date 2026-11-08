defmodule AshTemplate.Points.AgentOpenedAccountTest do
  # Invariant: an account an agent opened for itself, here or on another Regent
  # site, earns none of the one-time awards a script could collect by opening
  # accounts (a new account, a first paired agent, a first note by an agent),
  # neither when they happen nor at the Points start, and each is turned down
  # with its reason. A person's account beside it still earns them.
  use ExUnit.Case, async: false

  import Ecto.Query
  require Ash.Query
  alias AshTemplate.{Accounts, Agents, Notes, Repo}
  alias AshTemplate.Accounts.{AgentAccount, VerifiedSession}
  alias AshTemplate.Actors.{Agent, System}
  alias RegentPoints.{Event, IntakeWorker, Rejection, StartAwards, Store}

  @rules ["account.activated", "agent.activated", "template.first_agent_note"]

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    starts_at = Application.get_env(:regent_points, :starts_at)
    rules = Application.get_env(:regent_points, :approved_rules)

    on_exit(fn ->
      Application.put_env(:regent_points, :starts_at, starts_at)
      Application.put_env(:regent_points, :approved_rules, rules)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "an agent's own account earns no one-time award; a person's account does" do
    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])
    Application.put_env(:regent_points, :approved_rules, @rules)

    opened = opened_by_agent()
    elsewhere = opened_on_another_site()
    signed_in = signed_in_before_opening()
    person = person()
    agent = paired_agent(opened)
    note = note(agent)
    note(paired_agent(person))

    # The account's time is kept to the second, rounded; Points' check waits for it.
    Process.sleep(1_000)
    for rule <- @rules, do: rule |> offers() |> run(IntakeWorker)

    assert earned(opened.account.id) == []
    assert earned(elsewhere.account.id) == []
    assert earned(signed_in.account.id) == []
    assert earned(person.account.id) == @rules

    keys = [to_string(opened.account.id), agent.pairing_id, note.id]
    assert turned_down(keys) == Enum.map(@rules, &{&1, "agent_opened_account"})

    for %{account: account} <- [elsewhere, signed_in] do
      assert turned_down([to_string(account.id)]) ==
               [{"account.activated", "agent_opened_account"}]
    end
  end

  test "at the start, an agent's own account earns nothing" do
    Application.put_env(:regent_points, :starts_at, nil)
    Application.put_env(:regent_points, :approved_rules, [])

    opened = opened_by_agent()
    person = person()
    agent = paired_agent(opened)
    paired_agent(person)

    # Their offers were turned down while nothing was approved.
    for rule <- @rules, do: rule |> offers() |> run(IntakeWorker)

    Process.sleep(1_000)
    Application.put_env(:regent_points, :starts_at, DateTime.utc_now())
    Application.put_env(:regent_points, :approved_rules, @rules)
    assert :ok = StartAwards.perform(%Oban.Job{})

    for rule <- @rules, do: rule |> offers() |> run(IntakeWorker)

    assert earned(opened.account.id) == []
    assert earned(person.account.id) == ["account.activated", "agent.activated"]

    # Before the start each offer was turned down as not yet approved; at the start
    # the agent's own account is turned down for what it is.
    refused = turned_down([to_string(opened.account.id), agent.pairing_id])
    assert {"account.activated", "agent_opened_account"} in refused
    assert {"agent.activated", "agent_opened_account"} in refused
    refute {"account.activated", "agent_opened_account"} in turned_down([to_string(person.account.id)])
  end

  # The agent opens its account as the site's signed request does
  # (AgentAccount.open/1), Privy answering with the user an agent opening made.
  defp opened_by_agent do
    did = "did:privy:agent-opened-" <> Ecto.UUID.generate()
    wallet = wallet()

    Req.Test.stub(RegentPrivy.Users, fn conn ->
      Req.Test.json(conn, %{
        "id" => did,
        "linked_accounts" => [%{"type" => "wallet", "address" => wallet, "chain_type" => "ethereum"}],
        "custom_metadata" => %{"regent_agent" => wallet}
      })
    end)

    {:ok, account} = AgentAccount.open(wallet)
    %{did: did, account: account}
  end

  # Another site's opening recorded it in the shared table; here the account is
  # only signed in to, as any account is.
  defp opened_on_another_site do
    %{account: account} = opened = person()
    RegentAgents.record_opened_account!(account.wallet_address, account.privy_user_id, actor: %System{})
    opened
  end

  # Privy made the agent's user, but the opening never finished; the agent then
  # signs in on the website with its wallet, and Privy's sign-in names the agent
  # that made the user (its `regent_agent` metadata).
  defp signed_in_before_opening do
    did = "did:privy:agent-signed-in-" <> Ecto.UUID.generate()
    wallet = wallet()

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "s-" <> did,
        privy_user_id: did,
        wallet_address: wallet,
        wallet_addresses: [wallet],
        agent_wallet: wallet,
        issued_at: now(),
        expires_at: now() + 3600
      })

    %{did: did, account: account}
  end

  defp person do
    did = "did:privy:person-" <> Ecto.UUID.generate()
    wallet = wallet()
    %{did: did, account: Accounts.register_verified!(did, wallet, [wallet], actor: %System{})}
  end

  # An agent paired with the account, as this site's agent sign-in makes it.
  defp paired_agent(%{did: did, account: account}) do
    wallet = wallet()
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})
    RegentAgents.pair_agent!(code.code, "Helper", :codex, actor: %RegentAgents.Agent{wallet: wallet})

    record = Agents.sign_in_agent!(wallet, actor: %System{})
    {:ok, pairing} = RegentAgents.Authority.resolve(Repo, wallet)
    Agent.paired(record, account, pairing, Ecto.UUID.generate())
  end

  defp note(actor) do
    Notes.create_note!(%{title: "Note", operation_id: Ecto.UUID.generate()}, actor: actor)
  end

  # Oban's job rows are not Ash records, so the queued offers are read straight
  # from its table.
  defp offers(rule) do
    Repo.all(
      from j in Oban.Job,
        where:
          j.worker == "RegentPoints.IntakeWorker" and j.state == "available" and
            fragment("?->>'rule_id'", j.args) == ^rule
    )
  end

  defp run(jobs, worker) do
    for job <- jobs, do: assert(worker.perform(%{job | attempt: 1}) == :ok)

    # The jobs just run are marked done so a later read of the queue skips them.
    Repo.update_all(from(j in Oban.Job, where: j.id in ^Enum.map(jobs, & &1.id)),
      set: [state: "completed"]
    )
  end

  # The rules an account's offers were accepted for, awaiting their award.
  defp earned(account_id) do
    Ash.Query.filter(Event, account_id == ^account_id)
    |> Ash.read!(actor: Store.system())
    |> Enum.map(& &1.rule_id)
    |> Enum.sort()
  end

  # The offers turned down for these sources, each with its rule and reason.
  defp turned_down(keys) do
    Ash.read!(Rejection, actor: Store.system())
    |> Enum.filter(&(&1.source["source_event_key"] in keys))
    |> Enum.map(&{&1.source["rule_id"], &1.reason_code})
    |> Enum.sort()
  end

  defp now, do: Elixir.System.system_time(:second)

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
