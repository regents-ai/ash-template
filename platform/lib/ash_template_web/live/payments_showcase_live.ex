defmodule AshTemplateWeb.PaymentsShowcaseLive do
  @moduledoc """
  How a USDC payment looks on a Regent site, with sample figures and Pay
  switched off (founder, 2026-09-29).

  The shared `RegentPayments` library takes real USDC on Base only, so this
  page takes nothing: no offer, no intent, no wallet request. It shows the
  USDC Balance, the frozen terms a payer sees, the Pay button and the words
  for each answer `RegentPayments.WalletPayment.pay/4` can give. The
  `payments` skill says how a product page wires the real thing.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Shell
  alias Regent.Primitives, as: P

  # Sample wallets, plainly not anyone's: the one paid, the one signed in with
  # and another the wallet app has open.
  @pay_to "0x1111111111111111111111111111111111111111"
  @signed_in "0x2222222222222222222222222222222222222222"
  @other "0x3333333333333333333333333333333333333333"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/payments"))
     |> assign(
       local?: AshTemplateWeb.Showcase.mode() == :local,
       pay_to: RegentFormat.short_address(@pay_to),
       signed_in: RegentFormat.short_address(@signed_in),
       other: RegentFormat.short_address(@other)
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="payments-page" class="sc onchain-workshop payments-page">
      <header class="sc-header payments-page-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
        <Shell.theme_toggle id="payments-page-theme" />
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Example</p>
        <h1>Pay with USDC</h1>
        <p>
          This is how paying looks on every Regent site. You pay from your own wallet, straight to
          the person or project you're paying. Regent never holds your money.
        </p>
        <p>
          Paying is switched off on this copy of the site and the figures are samples, so nothing
          here moves money.
        </p>
      </section>

      <div class="onchain-workshop-grid">
        <section class="rg-panel rg-panel--surface" aria-labelledby="payments-balance-heading">
          <h2 id="payments-balance-heading">Your USDC Balance</h2>
          <p class="payments-figure">
            24.50 USDC
            <P.status>Sample</P.status>
          </p>
          <p>
            Your USDC Balance is the USDC in the wallet you signed in with, on Base. Add to it by
            sending USDC to your wallet's address or by buying it with MoonPay.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="payments-offer-heading">
          <h2 id="payments-offer-heading">What you're paying for</h2>
          <dl class="payments-terms">
            <div>
              <dt>For</dt>
              <dd>A tip for Pixel Garden</dd>
            </div>
            <div>
              <dt>Amount</dt>
              <dd>1.00 USDC</dd>
            </div>
            <div>
              <dt>Paid to</dt>
              <dd><code>{@pay_to}</code></dd>
            </div>
          </dl>
          <p>Before you pay, you see exactly this:</p>
          <blockquote>Send 1.00 USDC to {@pay_to} as a tip for Pixel Garden.</blockquote>
          <div class="payments-press">
            <P.button type="button" disabled aria-describedby="payments-off">Pay 1.00 USDC</P.button>
            <p id="payments-off" class="rg-muted">Paying is switched off on this copy of the site.</p>
          </div>
          <p>
            Pressing Pay asks your wallet to sign once, with no network fee. The amount and the
            wallet paid can't change after you see them, and pressing again signs the same payment,
            so it's never taken twice.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="payments-answers-heading">
          <h2 id="payments-answers-heading">What you might see next</h2>
          <ul class="payments-answers">
            <li>
              <P.status tone="success">Paid</P.status>
              <span>1.00 USDC went to {@pay_to}.</span>
            </li>
            <li>
              <P.status tone="info">Going through</P.status>
              <span>Your payment is still going through. Check again in a moment.</span>
            </li>
            <li>
              <P.status tone="warning">Expired</P.status>
              <span>This price has expired. Start again for a fresh one.</span>
            </li>
            <li>
              <P.status tone="warning">Other wallet</P.status>
              <span>You're signed in as {@signed_in}, but your wallet app has {@other} open.</span>
            </li>
            <li>
              <P.status tone="error">Refused</P.status>
              <span>Those payment terms have changed since your wallet saw them.</span>
            </li>
            <li>
              <P.status tone="error">Unavailable</P.status>
              <span>Payments aren't available right now. Try again shortly.</span>
            </li>
          </ul>
        </section>
      </div>
    </main>
    """
  end
end
