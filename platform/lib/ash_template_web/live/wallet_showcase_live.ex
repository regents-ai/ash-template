defmodule AshTemplateWeb.WalletShowcaseLive do
  @moduledoc """
  The wallet buttons on a real account, with a real wallet, on the `:wallet_chain`
  test network. `AshTemplateWeb.OnchainExample` runs here as on a product page,
  with the signed-in account, whose own wallets are the ones that act.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplate.AccessContext
  alias AshTemplateWeb.Components.Shell
  alias Regent.Primitives, as: P

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/wallet"))
     |> assign(
       mode: AshTemplateWeb.Showcase.privy_mode(),
       chain: Application.fetch_env!(:ash_template, :wallet_chain)
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="wallet-page" class="sc onchain-workshop wallet-page">
      <header class="sc-header wallet-page-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
        <Shell.account_control account_control={@account_control} enabled={@mode == :configured} />
        <Shell.theme_toggle id="wallet-page-theme" />
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Working example</p>
        <h1>Wallet buttons</h1>
        <p>
          Sign in, connect a wallet on your account, and press. Every press goes straight to your
          wallet. The site prepares each step before you press and then reads what happened on the
          network.
        </p>
        <p>
          These buttons use {@chain.name}, a test network, so nothing here moves real money. Record and
          Fail on purpose still need a little {@chain.name} test ETH in the wallet to pay the network
          fee. Sign costs nothing.
        </p>
      </section>

      <div class="onchain-workshop-grid">
        <section class="rg-panel rg-panel--surface" aria-labelledby="wallet-account-heading">
          <h2 id="wallet-account-heading">Your account</h2>
          <p id="wallet-account-state">
            {account_line(@account_control.kind, @access_context)}
          </p>
          <P.button
            type="button"
            disabled={@mode != :configured}
            data-account-target={Shell.account_target(@account_control)}
          >
            {if @account_control.kind == :signed_in,
              do: "Connect or change wallet",
              else: "Sign in"}
          </P.button>
          <p :if={@mode != :configured} role="status">
            Sign-in isn't available on this copy of the site.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="wallet-example-heading">
          <h2 id="wallet-example-heading">The buttons</h2>
          <.live_component
            module={AshTemplateWeb.OnchainExample}
            id="onchain-example"
            lease={@session_lease}
            account={current_account(@access_context)}
            chain={@chain}
          />
        </section>
      </div>
    </main>
    """
  end

  defp current_account(%{principal: {:human, account}}), do: account
  defp current_account(_access_context), do: nil

  defp account_line(:sign_in, _access_context), do: "Signed out. Sign in to use the buttons."

  defp account_line(:signed_in, access_context) do
    case AccessContext.linked_wallets(access_context) do
      [] ->
        "Signed in. Your account has no wallet yet: connect one to use the buttons."

      [_one] ->
        "Signed in with one wallet on your account. Only that wallet sends from here."

      wallets ->
        "Signed in with #{length(wallets)} wallets on your account. Only those send from here."
    end
  end
end
