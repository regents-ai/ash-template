defmodule AshTemplateWeb.WalletRefusedTest do
  # Invariant: a wallet that refused a send or signature outright reports
  # `wallet_refused`, and the wallet-button component takes it like every reason
  # the shared list knows: the person gets a note, the failure is counted under
  # its own reason, and the visit log names it, never `other`.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint AshTemplateWeb.Endpoint
  @moduletag :capture_log

  @wallet "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"

  # The reference component on a page of its own, signed in to an account that
  # links one wallet, on the site's wallet chain.
  defmodule HostLive do
    use AshTemplateWeb, :live_view

    @impl true
    def mount(_params, %{"wallet" => wallet}, socket),
      do: {:ok, assign(socket, wallet: wallet), layout: false}

    @impl true
    def render(assigns) do
      ~H"""
      <.live_component
        module={AshTemplateWeb.OnchainExample}
        id="onchain-example"
        chain={Application.fetch_env!(:ash_template, :wallet_chain)}
        lease={nil}
        client_key="wallet-refused-test"
        account={%{wallet_address: @wallet, wallet_addresses: [@wallet]}}
      />
      """
    end
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    level = Logger.level()
    Logger.configure(level: :info)

    test = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:ash_template, :wallet, :failure],
      fn _event, _measurements, metadata, _config -> send(test, {:counted, metadata}) end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler)
      Logger.configure(level: level)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "a refused send or signature is shown, counted and logged by its reason" do
    for step <- ["record", "sign"] do
      {:ok, view, _html} =
        build_conn()
        |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
        |> live_isolated(HostLive,
          session: %{"client_key" => "wallet-refused-test", "wallet" => @wallet}
        )

      refute has_element?(view, "#onchain-example-press-note")

      {_html, log} =
        with_log(fn ->
          view
          |> with_target("#onchain-example")
          |> render_hook("step_failed", %{"step" => step, "reason" => "wallet_refused"})
        end)

      assert has_element?(view, "#onchain-example-press-note")
      assert_received {:counted, %{flow: :onchain_example, reason: "wallet_refused"}}
      assert log =~ "press OnchainExample:step_failed wallet_refused"
    end
  end
end
