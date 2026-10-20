defmodule AshTemplateWeb.SiteToolsController do
  @moduledoc """
  The browser tools each Regent site offers on its home page, and how an agent
  connects to siwa-server: what the twin cube's six cards show, for anyone to
  read, as the `sites_tools` and `siwa_help` tools and commands.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.SiteTools

  @errors %{
    "site_not_found" =>
      {404, "There is no site with that name.",
       "Use regents, patchbay, techtree, autolaunch or keyfleet."},
    "site_unreachable" =>
      {503, "That site's tools could not be read right now.", "Try again in a minute."}
  }

  def siwa_help(conn, _params) do
    json(conn, %{site: "siwa-server", connection: SiteTools.connection_help()})
  end

  def tools(conn, %{"site" => site}) do
    case SiteTools.tools(site) do
      {:ok, tools} -> json(conn, %{site: SiteTools.name(site), tools: tools})
      {:error, :unknown_site} -> refuse(conn, "site_not_found")
      {:error, :unreachable} -> refuse(conn, "site_unreachable")
    end
  end

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
