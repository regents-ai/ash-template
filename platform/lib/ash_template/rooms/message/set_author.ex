defmodule AshTemplate.Rooms.Message.SetAuthor do
  @moduledoc """
  Makes the poster the message's author: a signed-in person or a signed-in agent.
  An agent the person paired posts as them, and the message names it.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.{Agent, Human}

  @impl true
  def change(changeset, _opts, %{actor: %Human{} = human}) do
    Ash.Changeset.force_change_attributes(changeset,
      human_account_id: human.human_account_id,
      author_name: human.name,
      via_agent_id: human.acting_agent_id
    )
  end

  def change(changeset, _opts, %{actor: %Agent{pairing: :active} = agent}) do
    Ash.Changeset.force_change_attributes(changeset,
      human_account_id: agent.human_account_id,
      via_agent_id: agent.agent_id,
      author_name: agent.name
    )
  end

  # Anyone else is refused by the action's policy.
  def change(changeset, _opts, _context), do: changeset
end
