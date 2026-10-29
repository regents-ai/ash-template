defmodule AshTemplateWeb.PaymentsShowcaseLive do
  @moduledoc """
  How a USDC payment looks on a Regent site: the USDC Balance, the frozen terms,
  the Pay button and the words for each answer, with sample figures and Pay
  switched off (founder, 2026-09-29). The `payments` skill says how a product
  page wires the real thing.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.OnchainSteps
  alias Regent.Primitives, as: P

  # Sample wallets, plainly not anyone's: the one paid, the one signed in with
  # and another the wallet app has open.
  @pay_to "0x1111111111111111111111111111111111111111"
  @signed_in "0x2222222222222222222222222222222222222222"
  @other "0x3333333333333333333333333333333333333333"

  @impl true
  def mount(_params, _session, socket) do
    # The words for each answer `RegentPayments.WalletPayment.pay/4` can give, as
    # parts for `OnchainSteps.note/1`.
    answers = [
      {"success", "Paid", ["1.00 USDC went to ", {:address, @pay_to}, "."]},
      {"info", "Going through",
       ["Your payment is still going through. Check again in a moment."]},
      {"warning", "Expired", ["This price has expired. Start again for a fresh one."]},
      {"warning", "Other wallet", OnchainSteps.mismatch_note([@signed_in], @other)},
      {"error", "Refused", ["Those payment terms have changed since your wallet saw them."]},
      {"error", "Unavailable", ["Payments aren't available right now. Try again shortly."]}
    ]

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/payments"))
     |> assign(pay_to: @pay_to, answers: answers), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="payments-page" class="sc onchain-workshop payments-page">
      <header class="sc-header payments-page-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Example</p>
        <h1>Payments</h1>
        <p>
          Sample figures. Paying is off here.
          <P.tip id="payments-intro-tip" label="About payments">
            Paying looks like this on every Regent site. You pay from your own wallet, straight to
            the person or project you're paying; Regents keeps no balance for you.
          </P.tip>
        </p>
      </section>

      <div class="onchain-workshop-grid">
        <section class="rg-panel rg-panel--surface" aria-labelledby="payments-balance-heading">
          <h2 id="payments-balance-heading">USDC balance</h2>
          <p class="payments-figure">
            24.50 USDC
            <P.status>Sample</P.status>
            <P.tip id="payments-balance-tip" label="About USDC balance">
              The USDC in the wallet you signed in with, on Base. Send USDC to your wallet's address,
              or buy it with a card, to add to it.
            </P.tip>
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="payments-offer-heading">
          <h2 id="payments-offer-heading">Order</h2>
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
              <dd><P.address id="payments-pay-to" address={@pay_to} /></dd>
            </div>
          </dl>
          <div class="payments-press">
            <P.button type="button" disabled aria-describedby="payments-off">Pay 1.00 USDC</P.button>
            <p id="payments-off" class="rg-muted">Paying is off here.</p>
          </div>
          <P.disclosure id="payments-confirm" summary="Confirmation">
            <p>Before you pay, you see exactly this:</p>
            <blockquote>
              Send 1.00 USDC to <P.address id="payments-quote-pay-to" address={@pay_to} />
              as a tip for Pixel Garden.
            </blockquote>
            <p>
              Pressing Pay asks your wallet to sign once, with no network fee. The amount and the
              wallet paid can't change after you see them, and pressing again signs the same
              payment, so it's never taken twice.
            </p>
          </P.disclosure>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="payments-answers-heading">
          <h2 id="payments-answers-heading">Statuses</h2>
          <ul class="payments-answers">
            <li :for={{{tone, word, parts}, index} <- Enum.with_index(@answers)}>
              <P.status tone={tone}>{word}</P.status>
              <span><OnchainSteps.note id={"payments-answer-#{index}"} parts={parts} /></span>
            </li>
          </ul>
        </section>
      </div>
    </main>
    """
  end
end
