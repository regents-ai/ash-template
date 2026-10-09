defmodule AshTemplate.Notes.Note.AgentNotePoints do
  @moduledoc """
  When an agent acting as its person writes a note, asks Regent Points to
  consider it, inside the note's transaction, so a note that rolls back asks
  nothing. Points decides whether it earns (`template.first_agent_note`, once per
  person); while that rule is off nothing is queued.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.System

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, note ->
      reference = %{
        rule_id: "template.first_agent_note",
        source_app: "template",
        source_kind: "note",
        source_event_key: note.id
      }

      {:ok, _} = RegentPoints.record_event(reference, actor: %System{})
      {:ok, note}
    end)
  end
end
