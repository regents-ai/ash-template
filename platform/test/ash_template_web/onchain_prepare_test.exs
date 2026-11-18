defmodule AshTemplateWeb.OnchainPrepareTest do
  # Invariant: a press that asks the wallet-button component for its steps names
  # the open wallet, and the component builds the steps for that wallet when the
  # signed-in account links it, even before the page has reported the wallet. A
  # wallet the account does not link gets no steps.
  use ExUnit.Case, async: false

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
        client_key="onchain-prepare-test"
        account={%{wallet_address: @wallet, wallet_addresses: [@wallet]}}
      />
      """
    end
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  # A fresh component that has not heard the wallet, asked for the steps to record
  # `amount` from `address`.
  defp ask(address, amount) do
    {:ok, view, _html} =
      build_conn()
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
      |> live_isolated(HostLive,
        session: %{"client_key" => "onchain-prepare-test", "wallet" => @wallet}
      )

    view
    |> with_target("#onchain-example")
    |> render_hook("prepare_and_send", %{
      "form" => %{"amount" => amount},
      "step" => "record",
      "address" => address
    })

    view
  end

  test "a press that names the account's wallet gets the steps for it before the wallet is reported" do
    view = ask(@wallet, "3")

    assert_reply(view, %{
      review: %{signer: @wallet, inputs: %{"amount" => "3"}, steps: [%{step: "record"} | _]},
      send: "record"
    })
  end

  test "a press that names a wallet the account does not link gets no steps" do
    view = ask("0x" <> String.duplicate("1", 40), "3")

    assert_reply(view, reply)
    assert reply == %{}
  end
end
