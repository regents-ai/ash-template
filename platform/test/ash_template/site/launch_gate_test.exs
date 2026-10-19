defmodule AshTemplate.LaunchGateTest do
  # Invariant: closing the site never closes the page a new agent starts from.
  # Changes the site-wide gate, so it never runs beside another test.
  use ExUnit.Case, async: false
  import Plug.Test

  setup do
    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    on_exit(fn -> Application.put_env(:ash_template, :app_surfaces, open?) end)
    Application.put_env(:ash_template, :app_surfaces, false)
  end

  defp get(path),
    do: :get |> conn(path) |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))

  test "the agent pages stay open while the rest of the site is closed" do
    assert %{status: 200, resp_body: page} = get("/agents/dots")
    assert page =~ "Pair as <code>dots</code>"

    # The gate really was closed for this request.
    assert %{status: 503} = closed = get("/account")
    assert Plug.Conn.get_resp_header(closed, "retry-after") == ["3600"]
  end
end
