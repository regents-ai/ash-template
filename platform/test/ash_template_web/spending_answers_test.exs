defmodule AshTemplateWeb.SpendingAnswersTest do
  # Invariant for what an agent is told about spending its person's Credits: a
  # pairing revoked after the request was let in answers agent_not_paired,
  # never "unavailable".
  use ExUnit.Case, async: false

  import Plug.Conn
  import Phoenix.ConnTest
  alias AshTemplate.{Accounts, Agents, Repo}
  alias AshTemplate.Actors.{Agent, System}
  alias AshTemplateWeb.PairedAgentController

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "a pairing revoked after the request was let in answers agent_not_paired" do
    %{agent: agent, person: person} = paired()
    [paired_agent] = RegentAgents.list_my_agents!(actor: person)
    :ok = RegentAgents.unpair_agent(paired_agent, actor: person)

    refused = agent |> conn_for() |> PairedAgentController.balances(%{}) |> json_response(403)
    assert refused["error"]["code"] == "agent_not_paired"
  end

  defp conn_for(agent), do: build_conn() |> Map.put(:body_params, %{}) |> assign(:actor, agent)

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
    %{agent: Agent.paired(record, account, pairing, Ecto.UUID.generate()), person: person}
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
