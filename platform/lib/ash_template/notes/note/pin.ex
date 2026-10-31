defmodule AshTemplate.Notes.Note.Pin do
  @moduledoc """
  Pins a note to the top of its writer's notes. The note is read again under a
  row lock first, so a note already pinned stays as it is.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn
      %{data: %{pinned_at: nil}} = changeset ->
        Ash.Changeset.force_change_attribute(changeset, :pinned_at, DateTime.utc_now())

      changeset ->
        changeset
    end)
  end
end
