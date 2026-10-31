defmodule AshTemplate.Notes.Signals do
  @moduledoc """
  What notes tell the rest of the site, as Ash signals. Each but
  `:note_committed` is emitted in the save's own transaction, so a listener with
  the default delivery commits or rolls back with it; `:note_committed` comes
  after the transaction has committed.

    * `:note_created`: a note was written; `changed_by_agent_id` names the agent
      that wrote it for its person, if one did. Points offers an agent's note to
      Regent Points (`AshTemplate.Points.Award`).
    * `:note_saved`: a note was created or edited while the server can ask Jev.
      A label question is created for it (`AshTemplate.Notes.Decision`).
    * `:note_committed`: a note was created and its transaction has committed;
      emitted only for a create that succeeded. The visit log writes the
      template's value step, `note_created` (`AshTemplate.Journey.Value`).
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

    signal :note_committed do
      phase :after_transaction
      argument :note_id, :uuid, allow_nil?: false
    end
  end
end
