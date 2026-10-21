defmodule AshTemplate.Actors.Agent do
  @moduledoc "A SIWA agent retains its own identity and its current account delegation."
  @enforce_keys [:agent_id, :wallet_address, :name]
  defstruct [
    :agent_id,
    :wallet_address,
    :name,
    :human_account_id,
    :privy_user_id,
    :pairing_id,
    :acting_agent_id,
    wallet_addresses: [],
    pairing: :none,
    role: :agent
  ]

  def for_agent(agent, pairing \\ :none) do
    %__MODULE__{
      agent_id: agent.id,
      acting_agent_id: agent.id,
      wallet_address: agent.wallet_address,
      # What its own room post is signed with: its profile name, never its wallet
      # (Sean, 21 Oct 2026, 11. a).
      name: agent.name || "Unnamed agent",
      pairing: pairing
    }
  end

  def paired(agent, account, pairing) do
    %{
      for_agent(agent)
      | human_account_id: account.id,
        privy_user_id: pairing.privy_user_id,
        pairing_id: pairing.id,
        name: account.display_name || RegentFormat.short_address(account.wallet_address),
        pairing: :active
    }
  end
end
