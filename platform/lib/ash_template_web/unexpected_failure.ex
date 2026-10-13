defmodule AshTemplateWeb.UnexpectedFailure do
  @moduledoc """
  Logs a failure the site answers only with "try again", with the request it
  ended, so a fault the caller sees as a plain 503 still leaves a trace.
  """

  require Logger

  @doc "Logs `error` against `conn`'s request and returns `conn`."
  def log(conn, error) do
    Logger.error("#{conn.method} #{conn.request_path} answered try again: #{describe(error)}")
    conn
  end

  defp describe(error) when is_exception(error), do: Exception.message(error)
  defp describe(error), do: inspect(error)
end
