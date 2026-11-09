defmodule AshTemplate.SavedErrors do
  @moduledoc """
  What ErrorTracker saves of a failure (config/config.exs): only server faults,
  and only where each one happened.

  `ignore?/2` leaves out an exception the site answers below 500, such as not
  found or a bad request. Anyone can raise those by visiting a wrong address, so
  saving them would let anyone fill the table. Server faults, exits and throws
  are all kept.

  A job attempt that Oban will retry is left out too: ErrorTracker reports each
  failed attempt with Oban's `state`, which is `:failure` while attempts remain
  and `:discard` on the last one. A job that recovers on a later attempt saves
  nothing, and one that runs out of attempts is saved once.

  `sanitize/1` keeps only where an error happened before it is saved: the
  request's host, path and method, the page, component and event names, and the
  job's worker, queue and attempt. Headers, addresses, query strings, parameters
  and job arguments can carry a signing key, a session or a person's details, so
  none is kept.
  """

  @behaviour ErrorTracker.Ignorer
  @behaviour ErrorTracker.Filter

  @kept ~w(
    request.host request.path request.method
    live_view.view live_view.component live_view.event
    job.id job.worker job.queue job.attempt job.priority
  )

  @impl ErrorTracker.Ignorer
  def ignore?(_error, %{state: :failure}), do: true

  def ignore?(%ErrorTracker.Error{kind: "Elixir." <> _module = kind}, _context),
    do: kind |> String.to_existing_atom() |> visitors?()

  def ignore?(_error, _context), do: false

  @impl ErrorTracker.Filter
  def sanitize(context), do: Map.take(context, @kept)

  # Ash's four error classes take their status from the errors they wrap, so the
  # class names whose doing it was: bad input or a refusal, or a server fault.
  defp visitors?(class) when class in [Ash.Error.Invalid, Ash.Error.Forbidden], do: true
  defp visitors?(class) when class in [Ash.Error.Unknown, Ash.Error.Framework], do: false

  defp visitors?(exception),
    do:
      Code.ensure_loaded?(exception) and function_exported?(exception, :exception, 1) and
        Plug.Exception.status(exception.__struct__()) < 500
end
