---
name: payments
description: Taking payments on Regent's Phoenix and Ash sites with the shared RegentPayments library — tips, paid actions and fees paid in USDC from a person's own wallet on Base through x402 or in Regent Credits, their USDC Balance, and paid tools for agents. Use when adding or changing anything a person or agent pays for, an offer, a pay button, the USDC Balance shown on a page, a paid HTTP endpoint or MCP tool, a paid-fix fee forwarded to REGENT staking, or the words shown for a payment's outcome.
---

# Payments

**Load `ash-stack` first, then `onchain-buttons` for the pay button.** Every Regent site
takes payment the same way, through one shared library: `regent_payments`
(`RegentPayments`) in `repos/elixir-utils/ash_components/payments`, pinned like `regent_identity`:

```elixir
{:regent_payments, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ash_components/payments"}
```

Read the library's module docs before building; they are the contract. This skill says how
a site fits around it.

## Rules

1. **Two ways to pay: USDC from the person's wallet, or Regent Credits.** USDC goes
   from the payer's own wallet straight to the wallet the offer names, settled by an
   x402 facilitator; Regents keeps no USDC for anyone, with no top-up or withdrawal.
   Regent Credits are the one balance Regents keeps (`regent_credits`), and they pay
   anywhere the money ends in a Regents wallet: the offer's terms say
   `credits: :accepted`, the site lists that wallet in `credits_pay_to`, and
   `Purchase.pay_with_credits/4` spends the same amount in Credits, one Credit per
   USDC. Terms that pay another person's wallet, or pass the money on to others
   (tips, paid fixes whose fee goes to stakers), answer `credits: :refused` until
   the founder decides how those receivers are paid. Funds committed to a product sit
   in that product's own escrow under its stated rules (Patchbay Offers) and are shown
   apart from wallet funds.
2. **USDC Balance and Credits are two figures, never one.** USDC Balance is what the
   person's signed-in Privy wallet holds in USDC on Base, read live with
   `RegentPayments.Balance.usdc_balance_atomic/1`. Credits is the person's Regent
   Credits, read from `regent_credits`. Call them "USDC Balance" and "Credits" on every
   site, never "credit" or "account balance", and never add them together. The
   template's `/showcase/funds` shows funds on other networks, commitments, card
   purchases and cash-outs; the plan is `docs/wallet-funds-plan.md`.
3. **One offer per paid action.** A site writes a module implementing
   `RegentPayments.Offer` for each thing it sells (a tip, a paid fix, a run) and lists it
   in `config :regent_payments, offers: [...]`. The offer freezes the terms (`freeze/2`:
   amount, the wallet paid, what it is for, the sentence the payer sees, and whether
   Credits may pay it). It then carries
   out what was bought (`carry_out/4`). The library owns everything between.
4. **Terms are frozen, never taken from the request.** Amount and destination are read
   from the stored intent on every call. Nothing a page or agent sends changes them.
5. **What a payment buys is saved once.** `carry_out/4` runs inside the transaction that
   holds the intent's row lock. The site's row for the effect is written through the same
   repository, with a unique index on the intent id. Anything outside the database (a job,
   a runner, a message) starts only after commit: an `after_transaction` hook or an Oban
   job inserted in the same transaction.
6. **Every press reaches the wallet.** The pay button follows `onchain-buttons`. A repeat
   press signs the same authorization (one nonce per intent and wallet), so USDC moves at
   most once. Never block, hide or dedupe the press to get that.
7. **A timed-out settlement is not retried.** It is left `settlement_pending` for a person
   to check on the chain. The facilitator client runs with no retries on purpose.

## Wiring a site

```elixir
config :regent_payments,
  repo: MySite.Repo,
  ash_domains: [RegentPayments],
  site: "mysite",                       # every row this site writes carries it
  offers: [MySite.Payments.Tip],
  base_rpc_url: System.get_env("BASE_RPC_URL"),
  payment_chain: %{name: "Base", rpc_url: "https://mainnet.base.org"},
  wallet_proof: [name: "MySite", version: "1", endpoint: MySiteWeb.Endpoint],
  credits_pay_to: [System.get_env("PAYMENTS_WALLET_ADDRESS")]   # Regents wallets Credits may pay into

config :regent_payments, RegentPayments.Facilitator,
  url: X402.Facilitator.Auth.CDP.facilitator_url(),
  auth: {X402.Facilitator.Auth.CDP, api_key_id: id, api_key_secret: secret}
```

- Start `RegentPayments.Supervisor` after the repository.
- `regent_credits` uses the same repository, since the Credits charge and the settled
  intent are written in one transaction. Pin it from git with `override: true`,
  because `regent_payments` names it by a sibling path.
- The CDP key goes in Fly secrets. `BASE_RPC_URL` may carry a provider key; the library
  never logs it, so don't log it either.
- **No deployment migrates the tables.** Every site carries the same `bin/migrate-shared`,
  which runs `RegentPayments.Migrator.up/1` with the other shared migrators; after the
  founder's go, the site whose release first carries a change runs it. Each site's
  release check refuses to deploy while a payments change is missing. Every site reads
  and writes the one `regent_payments` schema, seeing only the rows its own `site` wrote. The rows are the record of money that moved:
  `payment_intents` and `payment_receipts` are on the production protected-table lock
  (founder, 2026-09-29), so a migration or reset that deletes from, empties or drops them
  fails, and only Sean lifts it. Tests use the Ecto sandbox or a fresh local database.
- Payments are Base mainnet only (`RegentPayments.USDC`): real USDC, no test network.
  The template's `/showcase/payments` shows the payer's view with sample figures
  and Pay switched off.

## The three doors

| Who pays | Call | Notes |
| --- | --- | --- |
| A person on a page | `RegentPayments.WalletPayment.pay/4` | Unsigned, it answers `{:review, intent, review}`: a `RegentChain.Review` with one signature step for the signed-in wallet. The hook signs it and sends back the `review_id` and signature; the same call then settles. `{:wallet_mismatch, id, note}` carries the note to show beside the button. |
| An agent over HTTP | `RegentPayments.Purchase.prepare/3`, then `execute/3` | No payment answers `{:payment_required, intent}`; send `Purchase.terms/3` as the x402 402 body. A signed `payment-signature` then settles. `on_offer/3` answers a repeated request with the purchase already started. |
| An agent over hosted MCP | `Purchase` with `RegentPayments.MCP` | The tool names the wallet (`MCP.wallet/1`); the payment is in `_meta` (`MCP.payment/1`) and must come from that wallet. An action that moves money without a payment proves the wallet with `RegentPayments.WalletProof`. |

Answer each outcome in customer words: paid, still settling (check again), expired
(prepare again), refused (with the reason), or the payment service unavailable. The
WebMCP tool refusal shape is in `ash-webmcp`.

## Paired agent authority

Verify SIWA before resolving the current pairing and canonical beneficiary. Every
agent payment entry point, including hosted MCP, supplies an explicit `role: :agent`
actor. Its `id` and `acting_agent_id` are the same agent profile UUID;
`beneficiary_profile_id` is the site's owner profile UUID; `human_account_id` is the
canonical positive integer account ID. Include the verified `privy_user_id`,
lowercase `wallet_address` and original `pairing_id`. Do not pass an owner actor or
accept these values from request fields.

The library freezes that authority with the payment terms and locks the original
active pairing before preparation and initial settlement. Revocation or re-pairing
cannot authorize a new settlement against the old episode. Facilitator verification
runs outside the database transaction; the locked transition checks authority again.
The reserved `__regent_payments_agent_authority` payload entry is private server data.
Never serialize a whole intent payload or return it as recovery material.

After settlement is authorized, paid effects receive a
`RegentPayments.CompletionActor`. An offer must check
`AgentAuthority.completion_for?(actor, intent, expected_kind)` and bind its product
action to the stored intent's exact target. This actor may finish only that paid
effect; it grants no owner permissions, ordinary private reads, new purchases or
unrelated product actions. Keep its original beneficiary and pairing attribution.

For recovery after unpairing, authenticate the original agent signer, then use
`Purchase.complete(actor, intent_id)`. Accept no payment signature on this route and
return only intent ID, status and receipt. It never starts or retries settlement.
Legacy pending intents without a frozen wallet or receipt are refused by this new
API; legacy settled/applied intents require the receipt payer to match the signer.
Do not guess historical ownership or widen authorization to make recovery succeed.

The template's note pin (`AshTemplate.Payments.NotePin`) is the reference offer: a
paired agent pays 1 USDC from its own wallet over x402, or 1 of its person's Credits
within the limits the person set. Product sites copy its wiring.

## Fees handed on to REGENT staking

A paid fix's fee settles into the site's operator wallet, then
`RegentPayments.FeeForward` hands it to the REGENT revenue staking contract in two
operator-signed transactions: an approval of exactly the fee, then the deposit. The site
decides when to forward. It stops a second forward of one fee under a row lock on its own
forward record. An answer of `:deposit_unknown` means look on the chain before running
the forward again.

## Buying on the chain with Credits

Some things on the chain (a Keyfleet Key) are bought for a person with Regents' own
USDC, after the person pays in purchased Credits, one Credit per USDC.
`AshTemplate.Payments.ChainBuy` is the template's wiring; a site copies it and names its
sale.

- The site writes a module implementing `AshTemplate.Payments.Sale`: `price/1` reads the
  sale and the item's price at the latest block, or answers in a few words why it cannot
  be bought now; `call/3` builds the sale's call for the item, sent to the buyer's wallet.
  Name it as `sale:` in `config :ash_template, AshTemplate.Payments.ChainBuy`.
- The buying wallet is a small wallet on Base. Its key is `BUYING_WALLET_PRIVATE_KEY` and
  its endpoint `BASE_RPC_URL`, both only in Fly secrets. Creating the wallet and setting
  the key are Sean's go.
- `AshTemplate.Payments.buy(item, receiver, actor: credits_actor)`, for a person or a
  paired agent, holds the price in purchased Credits only (`purchased_only?: true`; given
  Credits never pay) under the day's limit (`daily_limit_atomic`, 500 USDC). The item goes
  to one of the buyer's own wallets.
- One send at a time, never twice (`chain_buys` queue, limit 1, one attempt):
  `RegentPayments.BuyingWallet.buy/2` approves exactly the price, then sends the sale's
  call, each at the wallet's next nonce after any still waiting. The limit holds per
  machine: a site with more than one machine runs `chain_buys` on one of them only.
- The send commits its outcome and hashes first; the Credits are settled in their own
  step (`:close_hold`, queued with the outcome). Bought charges them; a refused approval
  or call gives them back; a call that may still land keeps them held while
  `CheckReceipt` reads its receipt.
- A buy left for a person to look up on the chain (a stopped send, a send that began
  ten minutes ago and never finished, a call never answered, Credits that could not be
  settled) keeps its Credits held and logs `Buy left for a person: id=... state=...` for
  Sentinel. A buy still waiting its turn in the queue has not begun, so it is never
  taken for one.
- No Points are earned on a buy.

## Checks

- The library's own suite covers the payment path; a site tests its offers' `freeze/2`
  and `carry_out/4` only where the founder agreed tests.
- A person pays a small real amount from a Privy wallet and from a browser-extension
  wallet before release. Say so in the report rather than claiming it.
- `make check-required-fixes` passes with `regent_payments` pinned to a git commit.
