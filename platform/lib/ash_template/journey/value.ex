defmodule AshTemplate.Journey.Value do
  @moduledoc """
  Writes the visit-log `step` for this site's value action
  (`AshTemplateWeb.VisitLog.value/2`) when it succeeds: in the template, a note
  created (`note_created`, from `AshTemplate.Notes.Signals`), by its person or
  their agent, on any surface. A site names its own value action in
  `AshTemplateWeb.VisitLog.values/0` and listens to its own signal here.

  The signal is emitted only once the action's checks and its write have
  passed, so a refused or failed action writes no line, and the line is written
  in the same process, with the visit and surface of the request or page that
  acted. It runs inside the action's transaction, so writing it never fails:
  `value/2` answers `:ok` whatever happens. It stores nothing.
  """

  use Ash.Resource,
    domain: AshTemplate.Journey,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplateWeb.VisitLog

  signals_in do
    from AshTemplate.Notes.Signals do
      on :note_created, :note_created
    end
  end

  actions do
    action :note_created do
      argument :signal, AshTemplate.Notes.Signals.NoteCreated, allow_nil?: false
      run fn _input, context -> VisitLog.value("note_created", context.actor) end
    end
  end

  policies do
    # Reached only through the signal above, after the action that emitted it was
    # allowed; it writes one log line and changes nothing.
    policy always() do
      authorize_if always()
    end
  end
end
