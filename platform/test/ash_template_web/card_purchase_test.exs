defmodule AshTemplateWeb.CardPurchaseTest do
  # Invariants for Credits bought by card or Link, with Stripe answered by the
  # test as it answers with test keys:
  # - only a Credits admin is offered it while the keys are test keys;
  # - a payment Stripe says went through adds its Credits once, whether the panel
  #   or Stripe's signed notice reads it first, and an unsigned notice changes nothing.
  use ExUnit.Case, async: false
  # The panel's USDC side reads Base, which tests never reach.
  @moduletag :capture_log

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.System, as: SystemActor
  alias RegentCredits.{CardPurchase, Stripe}

  @endpoint AshTemplateWeb.Endpoint

  # The panel as the site header holds it for a signed-in account. The page
  # around it trusts only the browser's own cookie, which these tests cannot
  # carry, so the browser walk covers the page itself.
  defmodule Panel do
    use Phoenix.LiveView

    @impl true
    def mount(_params, %{"account" => account}, socket) do
      credits = %{state: :ready, value: RegentCredits.balance(account.privy_user_id)}
      {:ok, assign(socket, account: account, credits: credits)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <.live_component
        module={AshTemplateWeb.CreditsPanel}
        id="credits-panel"
        lease={nil}
        account={@account}
        credits={@credits}
      />
      """
    end
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    admins = Application.fetch_env!(:regent_credits, :admins)
    admin = account("did:privy:card-admin-" <> Ecto.UUID.generate())
    Application.put_env(:regent_credits, :admins, [admin.privy_user_id])
    Req.Test.set_req_test_to_shared()
    stripe()

    on_exit(fn ->
      Req.Test.set_req_test_to_private()
      Application.put_env(:regent_credits, :admins, admins)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    %{admin: admin}
  end

  test "an admin pays by card in the panel and the Credits arrive once", %{admin: admin} do
    {:ok, view, _html} = panel(admin)
    before = purchased(admin)

    view |> form("#credits-panel-form", %{amount: "25", pay: "card"}) |> render_change()
    assert render(view) =~ "$26.06"

    # Stripe's answer and the Credits write run in the panel's own tasks; a busy
    # machine can take longer than render_async's default tenth of a second.
    view |> element("#credits-panel button", "Continue") |> render_click()
    render_async(view, 2_000)
    [purchase] = purchases(admin)
    checkout = "#credits-panel-checkout-#{purchase.id}"
    assert view |> element(checkout) |> render() =~ ~s(data-client-secret="#{purchase.session_id}_secret")

    # The hook's word once Stripe says the payment went through.
    view |> with_target("#credits-panel") |> render_hook("card_paid", %{})
    render_async(view, 2_000)
    assert Decimal.eq?(Decimal.sub(purchased(admin), before), 25)
    refute has_element?(view, checkout)

    # Stripe's own notice of the same payment adds nothing more.
    assert notice(paid(purchase)).status == 200
    assert Decimal.eq?(Decimal.sub(purchased(admin), before), 25)
  end

  test "Stripe's signed notice adds the Credits, and an unsigned one is refused", %{admin: admin} do
    purchase = start(admin, 10)
    before = purchased(admin)

    assert notice(paid(purchase), "t=1,v1=forged").status == 400
    assert Decimal.eq?(purchased(admin), before)

    assert notice(paid(purchase)).status == 200
    assert notice(paid(purchase)).status == 200
    assert Decimal.eq?(Decimal.sub(purchased(admin), before), 10)
  end

  test "with test keys, a person who is not a Credits admin is offered USDC only" do
    person = account("did:privy:card-person-" <> Ecto.UUID.generate())
    {:ok, view, _html} = panel(person)

    assert has_element?(view, "#credits-panel-amount")
    refute has_element?(view, "#credits-panel-pay")
  end

  # Stripe opens a session for each request and says each one is paid in full.
  defp stripe do
    Req.Test.stub(Stripe, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/checkout/sessions"} ->
          conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:urlencoded]))
          id = "cs_test_" <> conn.body_params["client_reference_id"]
          Req.Test.json(conn, %{id: id, client_secret: id <> "_secret", livemode: false})

        {"GET", "/v1/checkout/sessions/cs_test_" <> id} ->
          Req.Test.json(conn, paid(Ash.get!(CardPurchase, id, authorize?: false)))
      end
    end)
  end

  defp start(account, credits) do
    {:ok, %{id: id}} =
      RegentCredits.start_card_purchase(
        account.privy_user_id,
        credits,
        "http://127.0.0.1:4002/account/credits?card={CHECKOUT_SESSION_ID}",
        actor: AshTemplate.Credits.person(account)
      )

    Ash.get!(CardPurchase, id, authorize?: false)
  end

  defp paid(purchase) do
    %{
      "id" => purchase.session_id,
      "object" => "checkout.session",
      "client_reference_id" => purchase.id,
      "payment_status" => "paid",
      "amount_total" => purchase.total_cents,
      "currency" => "usd",
      "livemode" => false,
      "payment_intent" => "pi_" <> purchase.id
    }
  end

  # Through the whole site, as Stripe sends it.
  defp notice(session, signature \\ nil) do
    body = JSON.encode!(%{type: "checkout.session.completed", data: %{object: session}})
    now = System.system_time(:second)

    :post
    |> Plug.Test.conn("/api/stripe/notices", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("stripe-signature", signature || "t=#{now},v1=#{Stripe.sign(now, body)}")
    |> @endpoint.call(@endpoint.init([]))
  end

  defp purchases(account),
    do: RegentCredits.card_purchases!(actor: AshTemplate.Credits.person(account))

  defp purchased(account), do: RegentCredits.balance(account.privy_user_id).purchased

  defp account(did) do
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    Accounts.register_verified!(did, wallet, [wallet], actor: %SystemActor{})
  end

  defp panel(account),
    do: live_isolated(build_conn(), Panel, session: %{"account" => account})
end
