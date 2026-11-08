defmodule AshTemplate.Accounts.AgentAccount.Owner do
  @moduledoc """
  Holds for an agent acting as the owner of the account its own wallet opened
  (`AshTemplate.Actors.Human.owner/2`).
  """

  use Ash.Policy.SimpleCheck

  alias AshTemplate.Actors.Human

  @impl true
  def describe(_opts), do: "the actor is an agent that owns its account"

  @impl true
  def match?(%Human{agent_id: agent_id}, _context, _opts), do: is_binary(agent_id)
  def match?(_actor, _context, _opts), do: false
end
