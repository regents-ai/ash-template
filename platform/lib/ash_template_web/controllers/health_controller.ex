defmodule AshTemplateWeb.HealthController do
  @moduledoc """
  Whether the site and its own database answer: `/healthz` in plain text for the
  host's health check, `/api/v1/health` in JSON for the command line.
  """
  use AshTemplateWeb, :controller

  def show(conn, _params) do
    {status, body} =
      if database_ready?(), do: {:ok, "ok"}, else: {:service_unavailable, "unavailable"}

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end

  # The same answer as the hosted `health` tool (`AshTemplate.Site.Info`).
  def status(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case AshTemplate.Site.health() do
      {:ok, status} -> json(conn, status)
      {:error, _unavailable} -> refuse(conn, "unavailable")
    end
  end

  @errors %{
    "unavailable" =>
      {503, "The site is up but its database is not answering.", "Try again in a minute."}
  }

  @doc """
  The `{status, message, hint}` of the refusal `code`, for the hosted MCP
  server's tool errors (`AshTemplateWeb.ToolErrors`).
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  defp refuse(conn, code) do
    {status, message, hint} = refusal(code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end

  defp database_ready?, do: AshTemplate.Health.database_ready?()
end
