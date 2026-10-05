defmodule AshTemplateWeb.Plugs.Panels do
  @moduledoc """
  Reads which of the app shell's panels the visitor last opened or hid, so the
  first server render already draws them that way: the right side bar is closed
  and the sidebar shown until they choose otherwise. The browser writes the
  cookies (`assets/js/shell_panels.ts`); only the two values each panel can take
  are ever accepted, since they reach an HTML attribute.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    conn
    |> assign(
      :aside,
      if(conn.req_cookies["ash_template_aside"] == "open", do: "open", else: "closed")
    )
    |> assign(
      :sidebar,
      if(conn.req_cookies["ash_template_sidebar"] == "hidden", do: "hidden", else: "shown")
    )
  end
end
