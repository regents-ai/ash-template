defmodule AshTemplateWeb.PageControllerTest do
  use AshTemplateWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Ash Template"
    assert html =~ ~s(<meta name="privy-bridge-src" content="/assets/js/privy_bridge.js")
  end
end
