defmodule AshTemplate.Actors.Agent do
  @moduledoc """
  A SIWA agent retains its own identity and its current account delegation.

  `connection` is set when the agent is a connected app's own identity, acting
  through the hosted MCP server with the token its person approved: what
  `RegentOAuth.verify/3` answered for that token. The same app may then also run
  its identity tools (`AshTemplate.Agents.Connection`).
  """
  @enforce_keys [:agent_id, :wallet_address, :name]
  defstruct [
    :id,
    :agent_id,
    :wallet_address,
    :name,
    :human_account_id,
    :privy_user_id,
    :pairing_id,
    :acting_agent_id,
    :connection,
    # The person's shared profile (`RegentIdentity.profile_id/2`), whom a
    # payment the agent makes is for; nil until they have one.
    :beneficiary_profile_id,
    wallet_addresses: [],
    pairing: :none,
    role: :agent
  ]

  @type t :: %__MODULE__{}

  def for_agent(agent, pairing \\ :none) do
    %__MODULE__{
      id: agent.id,
      agent_id: agent.id,
      acting_agent_id: agent.id,
      wallet_address: agent.wallet_address,
      # What its own room post is signed with: its profile name, never its wallet
      # (Sean, 21 Oct 2026, 11. a).
      name: agent.name || "Unnamed agent",
      pairing: pairing
    }
  end

  def paired(agent, account, pairing, profile_id) do
    %{
      for_agent(agent)
      | human_account_id: account.id,
        privy_user_id: pairing.privy_user_id,
        pairing_id: pairing.id,
        beneficiary_profile_id: profile_id,
        name: account.display_name || RegentFormat.short_address(account.wallet_address),
        pairing: :active
    }
  end
end
