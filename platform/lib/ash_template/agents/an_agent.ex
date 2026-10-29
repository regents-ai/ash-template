defmodule AshTemplate.Agents.AnAgent do
  @moduledoc """
  Holds for an agent: one a person paired (`AshTemplate.Actors.Agent`), or one
  that owns its account (`AshTemplate.Actors.Human.owner/2`, which names it in
  `agent_id`). A person signed in on the site is neither; the pages are theirs.
  Each hosted tool's action checks the rest (`AshTemplate.Agents.NotPaired`).
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the actor is an agent"

  @impl true
  def match?(%{role: :agent}, _context, _opts), do: true
  def match?(%{role: :human, agent_id: agent_id}, _context, _opts), do: not is_nil(agent_id)
  def match?(_actor, _context, _opts), do: false
end
