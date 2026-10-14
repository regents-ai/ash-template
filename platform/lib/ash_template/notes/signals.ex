defmodule AshTemplate.Notes.Signals do
  @moduledoc """
  What notes tell the rest of the site, as Ash signals. Each is emitted in the
  save's own transaction, so a listener with the default delivery commits or
  rolls back with it.

    * `:note_created`: a note was written; `changed_by_agent_id` names the agent
      that wrote it for its person, if one did. Points offers an agent's note to
      Regent Points (`AshTemplate.Points.Award`).
    * `:note_saved`: a note was created or edited while the server can ask Jev.
      A label question is created for it (`AshTemplate.Notes.Decision`).
  """

  use Ash.Signals

  signals do
    signal :note_created do
      argument :note_id, :uuid, allow_nil?: false
      argument :changed_by_agent_id, :uuid
    end

    signal :note_saved do
      argument :note_id, :uuid, allow_nil?: false
    end
  end
end
