# Wallet funds and Credits: the golden plan

Plan, 5 October 2026, ash-template chief. It records Sean's decisions of 5 Oct (with the cloud agent) and how every Regent site will show, add, move and commit money. Nothing here is built yet. Production money flows, provider accounts, server spending and the Offers escrow each need their own go from Sean.

Background survey: `/Users/sean/Documents/regent/docs/handoffs/regent-credits-balances-2026-10-05.md`.

## Decisions of 5 Oct

| Question | Decision |
|---|---|
| What are Credits? | User-owned wallet funds. There is no Regent-kept redeemable balance and no Stripe Checkout top-up ledger. Product commitments, such as Offers bids, are held under disclosed, product-specific rules. |
| Privy wallets | Optional, user-owned embedded wallets alongside external wallets: one shared wallet experience across sites, not one per site. No existing ownership is moved silently. Creating a wallet grants Regent no spending authority. |
| Robinhood Chain | USDG is kept as USDG, and Base and Ethereum USDC stay USDC. They are never added up into one spendable number. Conversion happens only with a quote and confirmed arrival. Bridged "USDC" tokens are not accepted by name. |
| Providers | First check the Privy-managed Stripe path already in use. Look into Bridge eligibility, fees and onboarding now. Defer Privy Enterprise balance webhooks. Account creation, terms and paid plans stay with Sean. |
| 1 Credit = $1 | A pricing convention, not a promise of exactly $1 at a bank. Fees and the amount received are always shown. |
| The word "Credits" | Not used (Sean, 5 Oct, answer 4 b). Pages say USDC. |
| Offers commitments | Sean approved the Offers-only escrow contract on Base (HQ 98 a): revenue to REGENT staking `0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5`, gas paid by Patchbay. |

## The model: three things, never mixed

1. **Wallet funds.** What the person's own wallet holds, per chain and per token, read live. Regent never owes it to them and never spends it without their signature.
2. **Commitments.** Funds a person has moved into a product's contract under that product's disclosed rules, for example a Patchbay Offers bid in its escrow. They are shown separately and never counted as available.
3. **Records.**
   - Payment intents and receipts (today's `regent_payments` tables).
   - Commitment records.
   - Provider operations: card purchase, conversion, bank payout.

   These are evidence of what happened, not a balance anyone is owed. They are reconciled against the chain and the provider.

Worked example: someone has 200 USDC on Base and commits 60 to an Offers bid.
- The wallet now holds 140, and the escrow holds 60.
- The panel shows **Available 140** and **Committed 60**. It never shows 200 as available, and never subtracts the 60 from the 140 a second time.

## Where the code lives

| Piece | Home |
|---|---|
| Token and route registry, balance snapshots, payment readiness, provider-operation records | `RegentPayments` in `repos/regents/payments`, pinned by `@regents_ref` (Regents owns shared production code) |
| Product commitment contracts | The product's own repository (Offers escrow: Patchbay; proposal in `docs/handoffs/offers-commitment-escrow-proposal-2026-10-05.md`) |
| The panel, the dialogs, the words, the showcase and the payments skill | ash-template; each site copies the pattern and pins the library |

## Shared library additions (RegentPayments)

**1. Token and route registry.** Every token is named by chain and contract address, with checked decimals and what it can do. "Privy supports this chain" never stands in for a capability.

| Token | Chain | Address | Can do |
|---|---|---|---|
| USDC | Base (8453) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | balance, pay, card purchase, bank payout |
| USDC | Ethereum (1) | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | balance, pay (KeyFleet), card purchase, bank payout, convert |
| USDG | Robinhood Chain (4663) | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | balance, convert |

The registry replaces today's hard-coded Base in `RegentPayments.USDC`, as a hard cutover. Each capability is switched on only after it is checked end to end.

**2. Balance snapshot and payment readiness.**
- A snapshot carries the wallet, token, chain, amount, block number and read time.
- A payment carries its exact token, chain, amount, recipient and authorization.
- An action is ready to pay only when the snapshot for its own token and chain covers it. A total across chains never authorizes a payment; it is labelled "estimate".

**3. Provider operations.** One Ash resource for card purchases, conversions and bank payouts:
- the provider's id, its state, the amount sent and the amount received;
- an AshOban job checks each one until it finishes, using Oban's own scheduling with no hand-built loop;
- refresh on open and after each action; no paid webhooks to start;
- **a failed bank payout is never sent again automatically.** The crypto may already have left the wallet, so it is marked for a person to check.

## Wallets

- External wallets stay exactly as they are (sign-in, ownership, KeyFleet keys).
- A person may choose **Create a payments wallet**: a user-owned Privy embedded wallet on the same Privy user.
- **One wallet across sites.** Before any site turns this on, prove it on two sites (Regents account page and Patchbay): both must find the same wallet, with no second user and no second default wallet.
- **Privy Global Wallets** is evaluated for this. Its access request is Sean's.
- Knowing a wallet belongs to someone is never permission to spend from it. Agent or server spending is a separate decision. If it is ever approved, it must name the actions, recipients, tokens, chains, limits and expiry it allows.

## Provider facts (checked in the docs, 5 Oct)

**Card purchase through Privy.**
- Stripe (USD, EUR) and MoonPay are on by default, but the app still switches card purchases on in the Privy dashboard and installs `@stripe/crypto`. React-auth 3.33.1 or later is needed; the template has 3.34.0.
- Stripe works in the US (excluding New York) and the EU, by card, Apple Pay, Google Pay, or bank debit in the US.
- It delivers USDC on Base, Ethereum, Arbitrum, Polygon and Solana.
- The result is one of `submitted`, `confirmed`, `address_shown` or `completed`; only `completed` means the money arrived.
- Privy's docs don't say whether this path also needs Stripe's own onramp application, which a direct Stripe integration needs (Stripe reviews most within 48 hours). Sean checks this in the Privy dashboard.
- **Already in use.** Patchbay has this path live: Privy's `useFiatOnramp`, paying in USD for USDC on Base, sent to the signed-in wallet. Privy's newer deposit window replaces that call in later Privy versions. Patchbay's fuller write-up, with sources, is in the section "The fastest card path" of `repos/patchbay/local-only-docs-and-specs/stripe-link-and-mpp-scope-2026-10-05.md` (a local file, not in Patchbay's repository).
- **Where USDC on Base can be bought by card.**
  - Through Stripe: in the US only, excluding New York and Hawaii.
  - Stripe does not offer USDC on Base in the EU, although Privy's page lists the EU for Stripe in general.
  - Outside the US, it goes through MoonPay or Meld. Whether a euro buyer is sent to MoonPay for Base is not documented; a test purchase settles it.
- **Fees.**
  - The buyer pays every fee, shown before paying. Regent pays and earns nothing.
  - Stripe is the seller of record and carries fraud and disputes.
  - Stripe's example: 3.00 on a 100.00 purchase, plus a network fee.
  - MoonPay charges up to 4.5%, with a minimum fee of up to 3.99, plus a network fee. That makes small top-ups expensive.
- **Limits.** Neither publishes a minimum. Stripe's example limit is 3,000 per card purchase per customer, and its test modes cap purchases at 100–200.
- **A person must be there.** Each purchase needs the person in the browser: Link sign-in, an identity check the first time, the card, and any 3D Secure step. An agent can send its person to the window but cannot buy for itself. Privy's server-side funding covers bank transfers (Bridge) and crypto deposits, not cards.
- **Other currencies.** MoonPay covers AUD and BRL by default. Meld covers 50+ currencies in 100+ countries after Regents Labs completes Meld's business check in the Privy dashboard; that check is Sean's.
- **Start with USDC (HQ 95, Sean: "we want to allow cards asap, it can start USDC").** The first card step is the path Patchbay already runs: Stripe through Privy, USDC on Base into the person's own wallet, in the US outside New York and Hawaii. Other countries follow after a test purchase shows which provider and network they get.

**Bank cash-out (Bridge through Privy).**
- Setup: a Bridge account, sandbox and production keys registered in Privy, and server-side flows switched on.
- Bridge runs the identity check.
- Rails:
  - US: ACH, same-day ACH and wire.
  - UK: Faster Payments.
  - Europe (IBAN): SEPA.
  - Brazil: Pix.
  - SWIFT.
- Sources: Base and Ethereum USDC.
- Country list, minimums and fees are not published, so Sean asks Bridge.
- Status is read by checking each payout; payout webhooks in production need Enterprise.
- A payout that fails after the crypto has left must not be retried. If Bridge cannot refund it, the money sits at Bridge until Privy support resolves it.

**Global Wallets.**
- Becoming the shared-wallet provider needs Privy's approval: a "Request access" button in the dashboard, plus a production app, a verified cookie domain and a logo.
- Sites that use the shared wallet need no approval.
- The person confirms every action in a popup on the provider's domain.
- It works with wagmi.

**Embedded wallets.**
- Created only when asked (`useCreateWallet().createWallet()`; automatic creation stays `off`).
- Owned by the user: neither Privy nor Regent sees the key.
- They can sit beside an external wallet on the same Privy user.

**Robinhood Chain.**
- Privy swaps and moves funds between Robinhood Chain and Base or Ethereum. USDC to USDG counts as a like-for-like stablecoin move.
- Fees: up to 0.25% Privy fee, plus pool and bridge fees.
- Quotes expire, though the docs don't say after how long.

**Digital Asset Accounts.**
- Gated (through Privy sales). The balance list doesn't include Robinhood Chain or USDG, and it is a ledger figure that can differ from the chain.
- Not a launch dependency.

**Server spending for a user wallet.**
- Needs a server key, the wallet owner's consent (`addSigners`) and, optionally, a rule set. The owner can revoke it.
- A separate decision, not part of this plan.

Sources: https://docs.privy.io/financial-flows/deposits/configuration, https://docs.privy.io/wallets/funding/use-deposit-funds, https://docs.privy.io/financial-flows/transfers/fiat-payouts/execute-payout, https://docs.privy.io/financial-flows/transfers/fiat-payouts/track-payouts, https://docs.privy.io/wallets/global-wallets/overview, https://docs.privy.io/wallets/wallets/create/create-a-wallet, https://docs.privy.io/wallets/actions/transfer/bridging, https://docs.privy.io/wallets/accounts/overview, https://docs.privy.io/wallets/wallets/server-side-access, https://docs.robinhood.com/chain/contracts, https://docs.stripe.com/crypto/onramp, https://docs.stripe.com/crypto/onramp/embedded, https://docs.stripe.com/crypto/onramp/stripe-hosted.

## Words

Replace "Regent never holds your money" everywhere with:

> Regents does not keep a balance for you. Your available funds stay in your own wallet. Funds you commit to a product follow that product's stated rules.

Amounts are written in USDC (or USDG), with the network beside them. The "Credits" label is not used (Sean, 5 Oct).

## The showcase (ash-template, sample figures, every money button off)

A new `/showcase/funds` page beside `/showcase/payments`, built from real components:

1. **Funds panel.** Each section has its own row:
   - **Available for this action**: Base USDC 140.00.
   - **Other networks**: Ethereum USDC 25.00 and Robinhood USDG 10.00, with an "estimate" total.
   - **Committed**: 60.00 in two Patchbay Offers bids, each with its rule line.
   - **Pending transfers**: a card purchase of 50.00, processing.
2. **Ready to pay.** A 30.00 Offers bid on Base shows as covered. A 180.00 bid shows short on Base, offers "Move 25 USDC from Ethereum" with a quote (fee, expected arrival, expiry), and stays not ready until the funds arrive.
3. **Add funds.** Card through Privy (Stripe or MoonPay). Stripe is offered first in the US outside New York and Hawaii; other countries follow the test purchase above. The dialog says a person must complete the purchase themselves. The dialog names the destination wallet and network, the fees and the amount expected. It moves through Submitted → Confirmed → Completed, and closing the dialog is never shown as a completed payment.
4. **Send to another wallet.** Separate from cashing out.
5. **Cash out to a bank.** Identity check (Bridge), bank account, amount, fee, expected arrival, then pending. It includes the failure state where the crypto left but the bank transfer failed: "We're checking this with the provider", with no resend button.
6. **Wallet choice.** The connected external wallet, plus "Create a payments wallet".

Checked at desktop and phone widths, in light and dark, and with the keyboard, as for the other showcase pages.

## Order of work

1. Done: this plan; the Offers escrow proposal goes to Sean.
2. Done: the showcase page in ash-template, `/showcase/funds` (sample figures, every money button off).
3. Provider checks for Sean: the Privy-managed Stripe path in the Privy dashboard, Bridge eligibility and fees, Global Wallets access.
4. Shared library: token registry, snapshots and readiness, provider operations. These go on a Regents branch, after telling the Regents lane.
5. A two-site wallet proof.
6. Each site adopts, one release at a time, each with Sean's go.
