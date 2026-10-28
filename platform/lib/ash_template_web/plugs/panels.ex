defmodule AshTemplateWeb.Plugs.Panels do
  @moduledoc """
  Reads whether the visitor last hid the app shell's sidebar, so the first server
  render already draws it that way: shown until they choose otherwise. The
  browser writes the cookie (`assets/js/shell_panels.ts`); only the two values it
  can take are ever accepted, since they reach an HTML attribute.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    assign(
      conn,
      :sidebar,
      if(conn.req_cookies["ash_template_sidebar"] == "hidden", do: "hidden", else: "shown")
    )
  end
end
