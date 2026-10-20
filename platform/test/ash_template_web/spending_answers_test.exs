defmodule AshTemplateWeb.SpendingAnswersTest do
  # Invariants for what an agent is told about spending its person's Credits:
  # - the refusal and account_balances read the same budget, so while no grant
  #   can be made they say the same thing, and a refused pin pins nothing;
  # - a pairing revoked after the request was let in answers agent_not_paired,
  #   never "unavailable".
  use ExUnit.Case, async: false

  import Plug.Conn
  import Phoenix.ConnTest
  alias AshTemplate.{Accounts, Agents, Notes, Repo}
  alias AshTemplate.Actors.{Agent, Human, System}
  alias AshTemplateWeb.PairedAgentController

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    grants = Application.get_env(:regent_credits, :agent_grants_enabled)

    on_exit(fn ->
      Application.put_env(:regent_credits, :agent_grants_enabled, grants)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "while no grant can be made, a refused pin and the balances note agree" do
    Application.put_env(:regent_credits, :agent_grants_enabled, false)
    %{agent: agent, account: account} = paired()
    note = Notes.create_note!(%{title: "Pin me", operation_id: Ecto.UUID.generate()}, actor: agent)

    balances = agent |> conn_for() |> PairedAgentController.balances(%{}) |> json_response(200)

    refused =
      agent
      |> conn_for(%{"operation_id" => Ecto.UUID.generate()})
      |> PairedAgentController.pin_note(%{"id" => note.id})
      |> json_response(403)

    assert balances["spending_grant"]["grant_approvals_available"] == false
    assert refused["error"]["code"] == "spending_not_allowed"
    assert refused["error"]["hint"] == balances["note"]
    assert %{pinned_at: nil} = Notes.get_my_note!(note.id, actor: Human.for_account(account))
  end

  test "a pairing revoked after the request was let in answers agent_not_paired" do
    %{agent: agent, person: person} = paired()
    [paired_agent] = RegentAgents.list_my_agents!(actor: person)
    :ok = RegentAgents.unpair_agent(paired_agent, actor: person)

    refused = agent |> conn_for() |> PairedAgentController.balances(%{}) |> json_response(403)
    assert refused["error"]["code"] == "agent_not_paired"
  end

  defp conn_for(agent, body \\ %{}) do
    build_conn()
    |> Map.put(:body_params, body)
    |> assign(:actor, agent)
  end

  defp paired do
    did = "did:privy:spending-answers-" <> Ecto.UUID.generate()
    wallet = wallet()
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    person = %RegentAgents.Person{privy_user_id: did}
    agent_wallet = wallet()
    code = RegentAgents.issue_pairing_code!(actor: person)

    RegentAgents.pair_agent!(code.code, "Agent", :codex,
      actor: %RegentAgents.Agent{wallet: agent_wallet}
    )

    record = Agents.sign_in_agent!(agent_wallet, actor: %System{})
    {:ok, pairing} = RegentAgents.Authority.resolve(Repo, agent_wallet)
    %{agent: Agent.paired(record, account, pairing), account: account, person: person}
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
