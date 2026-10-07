defmodule AshTemplate.Actors.Agent do
  @moduledoc """
  A signed-in agent acting as itself: its id, its wallet, lowercased, and the
  name others see beside what it writes, its short wallet address.

  `pairing` says why it does not act as a person: it is not paired with one
  (`:none`), it is paired but not yet backed by World ID (`:not_backed`), or the
  person it is paired with has no account on this site (`:person_not_here`).
  """
  @enforce_keys [:agent_id, :wallet_address, :name]
  defstruct [:agent_id, :wallet_address, :name, pairing: :none, role: :agent]

  def for_agent(agent, pairing \\ :none) do
    %__MODULE__{
      agent_id: agent.id,
      wallet_address: agent.wallet_address,
      name: RegentFormat.short_address(agent.wallet_address),
      pairing: pairing
    }
  end
end
