defmodule AshTemplateWeb.MetricsControllerTest do
  use AshTemplateWeb.ConnCase, async: false

  test "exposes the bounded Privy browser failure counter", %{conn: conn} do
    :telemetry.execute([:ash_template, :privy, :browser_failure], %{count: 1}, %{
      reason: "provider_error"
    })

    conn = get(conn, "/metrics")

    assert response(conn, 200) =~
             ~s(ash_template_privy_browser_failure_total{reason="provider_error"})

    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end
end
