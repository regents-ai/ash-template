defmodule AshTemplate.Agents.RequireOperationId do
  @moduledoc """
  Refuses an agent's create that names no `operation_id`. Each create that uses
  it makes the `operation_id` the new record's id, so an agent's retry answers
  its first create instead of making a second. A person may leave it out.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    if Map.get(actor || %{}, :role) == :agent and
         is_nil(Ash.Changeset.get_argument(changeset, :operation_id)) do
      Ash.Changeset.add_error(changeset,
        field: :operation_id,
        message: "is required for agent creates"
      )
    else
      changeset
    end
  end
end
