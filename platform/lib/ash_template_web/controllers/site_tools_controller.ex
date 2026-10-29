defmodule AshTemplateWeb.SiteToolsController do
  @moduledoc """
  The browser tools each Regent site offers on its home page, and how an agent
  connects to siwa-server: what the twin cube's six cards show, for anyone to
  read, as the `sites_tools` and `siwa_help` tools and commands.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Site
  alias AshTemplate.Site.Refused

  @errors %{
    "site_not_found" =>
      {404, "There is no site with that name.",
       "Use regents, patchbay, techtree, autolaunch or keyfleet."},
    "invalid_input" =>
      {422, "The site's tools could not be read with this input.",
       "Send site only: regents, patchbay, techtree, autolaunch or keyfleet."},
    "site_unreachable" =>
      {503, "That site's tools could not be read right now.", "Try again in a minute."}
  }

  @doc """
  The `{status, message, hint}` of the refusal `code`, for the hosted MCP
  server's tool errors (`AshTemplateWeb.ToolErrors`).
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  # The same answers as the hosted tools (`AshTemplate.Site.Info`).
  def siwa_help(conn, _params) do
    {:ok, help} = Site.siwa_help()
    json(conn, help)
  end

  def tools(conn, %{"site" => site}) do
    case Site.sites_tools(site) do
      {:ok, tools} -> json(conn, tools)
      {:error, %Ash.Error.Invalid{errors: [%Refused{code: code}]}} -> refuse(conn, code)
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "site_not_found")
    end
  end

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  defp refuse(conn, code) do
    {status, message, hint} = refusal(code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
