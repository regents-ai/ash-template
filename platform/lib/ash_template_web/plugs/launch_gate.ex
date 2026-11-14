defmodule AshTemplateWeb.Plugs.LaunchGate do
  @moduledoc """
  Closes every non-marketing surface while the launch gate is closed.

  The setting is read on each request, so a deploy opens or closes surfaces
  without rebuilding the release. The marketing page, the reading pages (the
  documentation, the changelog, About, the agent pages, the Privacy Policy, the
  Terms of Use and the build skills) and signing out stay open in either state.
  `AshTemplateWeb.Live.LaunchGateHook` keeps the same reading pages open once
  they are on screen.
  """

  import Phoenix.Controller, only: [get_format: 1, json: 2, put_secure_browser_headers: 2]
  import Plug.Conn

  alias AshTemplateWeb.{ContentSecurityPolicy, HoldingController}

  @open_pages [
    [],
    ["agents"],
    ["docs"],
    ["changelog"],
    ["about"],
    ["privacy"],
    ["terms"],
    ["skills"]
  ]

  @not_open_yet %{
    code: "not_open_yet",
    message: "This part of the site isn't open yet.",
    hint: "Ask again after the number of seconds in Retry-After."
  }

  @doc "True while the product surfaces are open."
  def app_surfaces_enabled?, do: Application.fetch_env!(:ash_template, :app_surfaces)

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", path_info: path} = conn, _opts) when path in @open_pages,
    do: conn

  def call(%Plug.Conn{method: "GET", path_info: ["agents", _agent]} = conn, _opts), do: conn

  def call(%Plug.Conn{method: "DELETE", path_info: ["auth", "privy", "session"]} = conn, _opts),
    do: conn

  def call(conn, _opts) do
    if app_surfaces_enabled?(), do: conn, else: conn |> closed(response_format(conn)) |> halt()
  end

  # The session endpoints ride the browser pipeline but answer JSON callers; the
  # MCP address answers in JSON-RPC.
  defp response_format(%Plug.Conn{path_info: ["auth" | _]}), do: "json"
  defp response_format(%Plug.Conn{path_info: ["mcp" | _]}), do: "mcp"
  defp response_format(conn), do: get_format(conn)

  defp closed(conn, "json"), do: conn |> unavailable() |> json(%{error: @not_open_yet})

  defp closed(conn, "mcp"),
    do: conn |> unavailable() |> AshTemplateWeb.McpRefusal.refuse(503, @not_open_yet)

  defp closed(conn, "html"), do: conn |> unavailable() |> HoldingController.call(:show)

  # The closed page is a plain reading page, so it gets the strict policy.
  defp unavailable(conn) do
    conn
    |> put_secure_browser_headers(%{"content-security-policy" => ContentSecurityPolicy.reading()})
    |> put_status(:service_unavailable)
    |> put_resp_header("retry-after", "3600")
    |> put_resp_header("cache-control", "no-store")
  end
end
