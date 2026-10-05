defmodule AshTemplateWeb.FundsShowcaseLive do
  @moduledoc """
  How a person's money looks on a Regent site, with sample figures and every money
  button switched off (founder, 2026-10-05). Wallet funds, commitments and money on
  its way are shown apart and never added into one spendable amount; the plan is
  `docs/wallet-funds-plan.md`.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Shell
  alias Regent.Primitives, as: P

  # Sample wallets, plainly not anyone's: the one signed in with and one sent to.
  @signed_in "0x2222222222222222222222222222222222222222"
  @send_to "0x4444444444444444444444444444444444444444"

  @impl true
  def mount(_params, _session, socket) do
    [signed_in, send_to] = Enum.map([@signed_in, @send_to], &RegentFormat.short_address/1)

    # What a card purchase can show, in order; only the last means it arrived.
    card_steps = [
      {"info", "Submitted", "Your card payment went to Stripe."},
      {"info", "Confirmed", "Stripe accepted it and is sending the USDC."},
      {"success", "Completed", "50.00 USDC arrived in your wallet."},
      {"neutral", "Not finished",
       "You closed the window. The purchase shows here only once Stripe says it's complete."}
    ]

    cash_out_steps = [
      {"info", "On its way", "Your USDC left your wallet and the bank transfer is under way."},
      {"success", "Paid", "99.00 US dollars reached your bank."},
      {"warning", "Checking",
       "Your USDC left your wallet, but the bank transfer didn't go through. We're checking this with the provider. You don't need to do anything, and there's nothing to send again."}
    ]

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/funds"))
     |> assign(
       signed_in: signed_in,
       send_to: send_to,
       card_steps: card_steps,
       cash_out_steps: cash_out_steps
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="funds-page" class="sc onchain-workshop payments-page funds-page">
      <header class="sc-header payments-page-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
        <Shell.theme_toggle id="funds-page-theme" />
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Example</p>
        <h1>Your funds</h1>
        <p>
          This is how your money looks on every Regent site. Regents does not keep a balance for
          you. Your available funds stay in your own wallet. Funds you commit to a product follow
          that product's stated rules.
        </p>
        <p>
          Every money button is switched off on this copy of the site and the figures are samples,
          so nothing here moves money.
        </p>
      </section>

      <div class="onchain-workshop-grid">
        <section class="rg-panel rg-panel--surface" aria-labelledby="funds-have-heading">
          <h2 id="funds-have-heading">What you have</h2>
          <dl class="funds-rows">
            <div>
              <dt>Ready to use here</dt>
              <dd>
                <p class="payments-figure">
                  140.00 USDC on Base
                  <P.status>Sample</P.status>
                </p>
                <p class="rg-muted">
                  In the wallet you signed in with. Payments on this site use this.
                </p>
              </dd>
            </div>
            <div>
              <dt>On other networks</dt>
              <dd>
                <ul class="funds-list">
                  <li>25.00 USDC on Ethereum</li>
                  <li>10.00 USDG on Robinhood Chain</li>
                </ul>
                <p class="rg-muted">
                  Yours, but not usable here until you move it to Base. All three networks together
                  come to about 175 US dollars. That's an estimate, not an amount you can spend in
                  one go.
                </p>
              </dd>
            </div>
            <div>
              <dt>Committed</dt>
              <dd>
                <p class="payments-figure">60.00 USDC in Patchbay Offers</p>
                <ul class="funds-list">
                  <li>
                    40.00 USDC bid for next period on Pixel Garden. It all comes back if another bid wins.
                  </li>
                  <li>
                    20.00 USDC showing now on Pixel Garden. If someone buys it out, the unused time
                    comes back to you. If a moderator removes it, nothing comes back.
                  </li>
                </ul>
                <p class="rg-muted">
                  Committed USDC sits in the Patchbay Offers escrow on Base, not in your wallet and
                  not with Regents. Anything still unsettled 14 days after it went in, you can take
                  back yourself.
                </p>
              </dd>
            </div>
            <div>
              <dt>On its way</dt>
              <dd>
                <p>
                  50.00 USDC card purchase
                  <P.status tone="info">Processing</P.status>
                </p>
                <p class="rg-muted">It counts once it arrives in your wallet.</p>
              </dd>
            </div>
          </dl>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="funds-ready-heading">
          <h2 id="funds-ready-heading">Ready to pay?</h2>
          <ul class="payments-answers">
            <li>
              <P.status tone="success">Ready</P.status>
              <span>A 30.00 USDC bid on Pixel Garden. You have 140.00 USDC on Base.</span>
            </li>
            <li>
              <P.status tone="warning">20.00 short</P.status>
              <span>
                A 160.00 USDC bid on Pixel Garden. You have 140.00 USDC on Base, and 25.00 USDC on
                Ethereum you could move.
              </span>
            </li>
          </ul>
          <h3>Move USDC to Base</h3>
          <dl class="payments-terms">
            <div>
              <dt>Move</dt>
              <dd>25.00 USDC from Ethereum to Base</dd>
            </div>
            <div>
              <dt>Fee</dt>
              <dd>0.10 USDC</dd>
            </div>
            <div>
              <dt>You receive</dt>
              <dd>24.90 USDC on Base, in about 2 minutes</dd>
            </div>
            <div>
              <dt>Price good until</dt>
              <dd>14:32 UTC</dd>
            </div>
          </dl>
          <div class="payments-press">
            <P.button type="button" disabled aria-describedby="funds-move-off">
              Move 25.00 USDC
            </P.button>
            <p id="funds-move-off" class="rg-muted">
              Moving is switched off on this copy of the site.
            </p>
          </div>
          <p>The bid isn't ready until the USDC arrives on Base.</p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="funds-card-heading">
          <h2 id="funds-card-heading">Add funds with a card</h2>
          <dl class="payments-terms">
            <div>
              <dt>To</dt>
              <dd>Your wallet <code>{@signed_in}</code> on Base</dd>
            </div>
            <div>
              <dt>You get</dt>
              <dd>50.00 USDC</dd>
            </div>
            <div>
              <dt>Card fee</dt>
              <dd>1.50 US dollars</dd>
            </div>
            <div>
              <dt>Network fee</dt>
              <dd>0.01 US dollars</dd>
            </div>
            <div>
              <dt>You pay</dt>
              <dd>51.51 US dollars</dd>
            </div>
          </dl>
          <div class="payments-press">
            <P.button type="button" disabled aria-describedby="funds-card-off">
              Buy 50.00 USDC
            </P.button>
            <p id="funds-card-off" class="rg-muted">
              Buying is switched off on this copy of the site.
            </p>
          </div>
          <p>
            Stripe sells the USDC and handles the card, your identity check and any dispute. It's
            offered in the US, except New York and Hawaii. You finish the purchase yourself: an agent
            can't buy for you.
          </p>
          <ul class="payments-answers">
            <li :for={{tone, word, text} <- @card_steps}>
              <P.status tone={tone}>{word}</P.status>
              <span>{text}</span>
            </li>
          </ul>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="funds-send-heading">
          <h2 id="funds-send-heading">Send to another wallet</h2>
          <dl class="payments-terms">
            <div>
              <dt>From</dt>
              <dd>Your wallet <code>{@signed_in}</code></dd>
            </div>
            <div>
              <dt>To</dt>
              <dd><code>{@send_to}</code></dd>
            </div>
            <div>
              <dt>Amount</dt>
              <dd>10.00 USDC on Base</dd>
            </div>
          </dl>
          <div class="payments-press">
            <P.button type="button" disabled aria-describedby="funds-send-off">
              Send 10.00 USDC
            </P.button>
            <p id="funds-send-off" class="rg-muted">
              Sending is switched off on this copy of the site.
            </p>
          </div>
          <p>
            Sending moves USDC to a wallet address, yours or someone else's. Your wallet shows the
            network fee before you confirm. Check the address and the network: USDC sent to the wrong
            address can't be brought back.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="funds-bank-heading">
          <h2 id="funds-bank-heading">Cash out to a bank</h2>
          <ol class="funds-list">
            <li>Check your identity with Bridge, once.</li>
            <li>Add your bank account.</li>
            <li>Choose the amount and see the fee and arrival time.</li>
          </ol>
          <dl class="payments-terms">
            <div>
              <dt>Amount</dt>
              <dd>100.00 USDC from Base</dd>
            </div>
            <div>
              <dt>Fee</dt>
              <dd>1.00 US dollars</dd>
            </div>
            <div>
              <dt>Your bank gets</dt>
              <dd>99.00 US dollars</dd>
            </div>
            <div>
              <dt>Arrives</dt>
              <dd>In 1 to 3 business days</dd>
            </div>
          </dl>
          <div class="payments-press">
            <P.button type="button" disabled aria-describedby="funds-bank-off">
              Cash out 100.00 USDC
            </P.button>
            <p id="funds-bank-off" class="rg-muted">
              Cashing out is switched off on this copy of the site.
            </p>
          </div>
          <ul class="payments-answers">
            <li :for={{tone, word, text} <- @cash_out_steps}>
              <P.status tone={tone}>{word}</P.status>
              <span>{text}</span>
            </li>
          </ul>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="funds-wallet-heading">
          <h2 id="funds-wallet-heading">Which wallet</h2>
          <p>
            <code>{@signed_in}</code>
            <P.status tone="success">Signed in</P.status>
          </p>
          <p>The wallet you signed in with. Everything above reads from it and sends from it.</p>
          <div class="payments-press">
            <P.button type="button" variant="secondary" disabled aria-describedby="funds-create-off">
              Create a payments wallet
            </P.button>
            <p id="funds-create-off" class="rg-muted">
              Creating a wallet is switched off on this copy of the site.
            </p>
          </div>
          <p>
            A payments wallet is made for you by Privy, the sign-in service, and only you control it.
            It sits beside the wallet you already use. Creating it doesn't let Regents spend from it.
          </p>
        </section>
      </div>
    </main>
    """
  end
end
