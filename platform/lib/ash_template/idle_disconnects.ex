defmodule AshTemplate.IdleDisconnects do
  @moduledoc """
  Logs a database connection that the database closed while it sat idle at info,
  not error. The pool opens a new one at once and nothing failed, so the line is
  not an error; every other disconnect stays at error.
  """

  @doc "Adds the filter to every log line, once, as the site starts."
  def attach, do: :logger.add_primary_filter(__MODULE__, {&__MODULE__.filter/2, nil})

  @doc false
  def filter(
        %{level: :error, msg: {:string, text}, meta: %{mfa: {DBConnection.Connection, _, _}}} =
          event,
        _
      ) do
    if String.ends_with?(IO.chardata_to_string(text), "recv (idle): closed"),
      do: %{event | level: :info},
      else: event
  end

  def filter(event, _), do: event
end
