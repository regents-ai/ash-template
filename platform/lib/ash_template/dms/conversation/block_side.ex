defmodule AshTemplate.Dms.Conversation.BlockSide do
  @moduledoc "Sets whether the actor's side of the conversation blocks the other side (`:blocked`)."

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    me = Map.get(actor || %{}, :human_account_id)

    side =
      case changeset.data do
        %{person_a: ^me} -> :blocked_by_a
        %{person_b: ^me} -> :blocked_by_b
      end

    Ash.Changeset.force_change_attribute(changeset, side, opts[:blocked])
  end
end
