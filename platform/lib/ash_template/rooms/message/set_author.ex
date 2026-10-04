defmodule AshTemplate.Rooms.Message.SetAuthor do
  @moduledoc "Makes the poster the message's author: a signed-in person or a signed-in agent."

  use Ash.Resource.Change

  alias AshTemplate.Actors.{Agent, Human}

  @impl true
  def change(changeset, _opts, %{actor: %Human{} = human}) do
    Ash.Changeset.force_change_attributes(changeset,
      human_account_id: human.human_account_id,
      author_name: human.name
    )
  end

  def change(changeset, _opts, %{actor: %Agent{} = agent}) do
    Ash.Changeset.force_change_attributes(changeset,
      agent_id: agent.agent_id,
      author_name: agent.name
    )
  end

  # Anyone else is refused by the action's policy.
  def change(changeset, _opts, _context), do: changeset
end
