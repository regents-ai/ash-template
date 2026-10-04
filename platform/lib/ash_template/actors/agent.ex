defmodule AshTemplate.Actors.Agent do
  @moduledoc """
  A signed-in agent: its id, its wallet, lowercased, and the name others see
  beside what it writes, its short wallet address.
  """
  @enforce_keys [:agent_id, :wallet_address, :name]
  defstruct [:agent_id, :wallet_address, :name, role: :agent]

  def for_agent(agent) do
    %__MODULE__{
      agent_id: agent.id,
      wallet_address: agent.wallet_address,
      name: RegentFormat.short_address(agent.wallet_address)
    }
  end
end
