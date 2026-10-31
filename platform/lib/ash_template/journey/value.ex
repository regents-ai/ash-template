defmodule AshTemplate.Journey.Value do
  @moduledoc """
  Writes the visit-log `step` for this site's value action
  (`AshTemplateWeb.VisitLog.value/2`) once it has committed: in the template, a
  note created (`note_created`, from `AshTemplate.Notes.Signals`
  `:note_committed`), by its person or their agent, on any surface. The value
  names in `AshTemplateWeb.VisitLog.values/0` are one fixed list shared by every
  site; a site maps its own value action to its name there and listens to that
  action's signal here.

  The signal is declared and emitted in the `:after_transaction` phase, which Ash
  emits only when the action answered `{:ok, record}`: a refused, failed or
  rolled-back action writes no line. The line is written in the same process,
  with the visit and surface of the request or page that acted, after the commit,
  and `value/2` answers `:ok` whatever happens, so it never fails the action. Ash's
  own telemetry also writes an `action value.note_created` line for this listener.
  It stores nothing.
  """

  use Ash.Resource,
    domain: AshTemplate.Journey,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplateWeb.VisitLog

  signals_in do
    from AshTemplate.Notes.Signals do
      on :note_committed, :note_created
    end
  end

  actions do
    action :note_created do
      argument :signal, AshTemplate.Notes.Signals.NoteCommitted, allow_nil?: false
      run fn _input, context -> VisitLog.value("note_created", context.actor) end
    end
  end

  policies do
    # Reached only through the signal above, after the action that emitted it was
    # allowed and committed; it writes one log line and changes nothing.
    policy always() do
      authorize_if always()
    end
  end
end
