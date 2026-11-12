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

  A refused pool checkout is left out as well: saving it would take a
  connection from the pool that just refused one, at the moment it has none to
  spare. `health.db_checkout_refused.total` counts each one instead
  (`AshTemplateWeb.Telemetry`).

  Each error the tracker groups as one (its kind and where it happened) is
  saved at most 10 times a minute on each machine, counted in
  `AshTemplate.Accounts.RequestRateLimiter`, so a fault that repeats on every
  request writes a few rows a minute instead of one per request. A cap on the
  kind alone would let one fault's flood hide a different fault of the same kind.

  `sanitize/1` keeps only where an error happened before it is saved: the
  request's host, path and method, the page, component and event names, and the
  job's worker, queue and attempt. Headers, addresses, query strings, parameters
  and job arguments can carry a signing key, a session or a person's details, so
  none is kept.
  """

  @behaviour ErrorTracker.Ignorer
  @behaviour ErrorTracker.Filter

  alias AshTemplate.Accounts.RequestRateLimiter

  @kept ~w(
    request.host request.path request.method
    live_view.view live_view.component live_view.event
    job.id job.worker job.queue job.attempt job.priority
  )

  @saved_per_minute 10

  @impl ErrorTracker.Ignorer
  def ignore?(_error, %{state: :failure}), do: true

  def ignore?(%ErrorTracker.Error{} = error, _context),
    do: visitors?(error) or checkout_refused?(error) or over_cap?(error)

  defp visitors?(%ErrorTracker.Error{kind: "Elixir." <> _module = kind}),
    do: kind |> String.to_existing_atom() |> visitors_class?()

  defp visitors?(_error), do: false

  # DBConnection's words for a checkout the pool dropped from its queue; Ash
  # carries them inside the error it wraps the refusal in.
  defp checkout_refused?(%ErrorTracker.Error{reason: reason}),
    do: String.contains?(reason, "connection not available and request was dropped from queue")

  defp over_cap?(%ErrorTracker.Error{fingerprint: fingerprint}),
    do:
      match?(
        {:error, :rate_limited, _budget},
        RequestRateLimiter.admit({:saved_error, fingerprint}, @saved_per_minute, 60)
      )

  @impl ErrorTracker.Filter
  def sanitize(context), do: Map.take(context, @kept)

  # Ash's four error classes take their status from the errors they wrap, so the
  # class names whose doing it was: bad input or a refusal, or a server fault.
  defp visitors_class?(class) when class in [Ash.Error.Invalid, Ash.Error.Forbidden], do: true
  defp visitors_class?(class) when class in [Ash.Error.Unknown, Ash.Error.Framework], do: false

  defp visitors_class?(exception),
    do:
      Code.ensure_loaded?(exception) and function_exported?(exception, :exception, 1) and
        Plug.Exception.status(exception.__struct__()) < 500
end
