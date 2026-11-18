defmodule AshTemplateWeb.OnchainFollowTest do
  # Invariant: a page that joins again meets a fresh wallet-button component. A
  # hash the page reports from the review it held, before it has told the new
  # component which wallet is open, is read once the component builds that same
  # review for the same wallet, chain and form; a review it never builds is never
  # read. A press that asks for its steps before the page has told the component
  # the wallet gets them for the wallet it names, when the account links it.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint AshTemplateWeb.Endpoint
  @moduletag :capture_log

  @wallet "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"

  # The reference component on a page of its own, signed in to an account that
  # links one wallet, on the site's wallet chain. The chain's node here refuses
  # every connection, so a step that is read stays on its way.
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
        client_key="onchain-follow-test"
        account={%{wallet_address: @wallet, wallet_addresses: [@wallet]}}
      />
      """
    end
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    %{chain_id: chain_id} = Application.fetch_env!(:ash_template, :wallet_chain)
    nodes = Application.fetch_env!(:ash_template, :chain_nodes)

    Application.put_env(
      :ash_template,
      :chain_nodes,
      Map.put(nodes, chain_id, "http://127.0.0.1:1")
    )

    on_exit(fn ->
      Application.put_env(:ash_template, :chain_nodes, nodes)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  # A page as it joins: a fresh component that has not heard the wallet yet.
  defp open do
    {:ok, view, _html} =
      build_conn()
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
      |> live_isolated(HostLive,
        session: %{"client_key" => "onchain-follow-test", "wallet" => @wallet}
      )

    view
  end

  defp hook(view, event, params),
    do: view |> with_target("#onchain-example") |> render_hook(event, params)

  # The id of the review the component pushes for `wallet` and the number on screen.
  defp review_id(view, wallet, amount) do
    hook(view, "change", %{"amount" => amount})
    hook(view, "onchain_active_wallet", %{"address" => wallet})

    assert_push_event(view, "onchain-steps:review", %{
      review: %{id: id, inputs: %{"amount" => ^amount}}
    })

    id
  end

  defp sent(view, id) do
    hash = "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
    hook(view, "step_sent", %{"review_id" => id, "step" => "record", "transaction_hash" => hash})
    hash
  end

  # Whether the sent step `hash` shows as `state` ("pending" while it is read,
  # "unknown" for one the component cannot follow).
  defp shown?(view, hash, state),
    do:
      has_element?(
        view,
        ~s(#onchain-example li[data-state="#{state}"] [id="onchain-example-sent-#{hash}"])
      )

  test "a hash reported before the wallet is read once the same review is built again" do
    held = review_id(open(), @wallet, "1")

    view = open()
    hash = sent(view, held)
    assert shown?(view, hash, "unknown")

    assert review_id(view, @wallet, "1") == held
    assert shown?(view, hash, "pending")
  end

  test "a hash is read only against the review it was sent from" do
    held = review_id(open(), @wallet, "2")

    view = open()
    hash = sent(view, held)
    elsewhere = sent(view, "not-built-here")

    review_id(view, @wallet, "1")
    assert shown?(view, hash, "unknown")

    assert review_id(view, @wallet, "2") == held
    assert shown?(view, hash, "pending")
    assert shown?(view, elsewhere, "unknown")
  end

  test "a press that asks before the wallet is reported gets the steps for the wallet it names" do
    view = open()

    hook(view, "prepare_and_send", %{
      "form" => %{"amount" => "3"},
      "step" => "record",
      "address" => @wallet
    })

    assert_reply(view, %{review: %{signer: @wallet, inputs: %{"amount" => "3"}}, send: "record"})

    other = open()

    hook(other, "prepare_and_send", %{
      "form" => %{"amount" => "3"},
      "step" => "record",
      "address" => "0x" <> String.duplicate("1", 40)
    })

    assert_reply(other, reply)
    assert reply == %{}
  end
end
