# The hook pattern

The template carries the working reference. Copy these files and replace the example's
steps; the paths are under `platform/` in ash-template. They compile against
`regent_chain` 0.2.0 (elixir-utils 7a876e8), Phoenix LiveView 1.2 and viem 2.55, and
were run in a browser against a lab chain at `/showcase/onchain`.

## Files

| File | Holds |
| --- | --- |
| `lib/ash_template_web/components/onchain_example.ex` | The example component: builds the review, renders the buttons, owns the words |
| `lib/ash_template_web/onchain_steps.ex` | `AshTemplateWeb.OnchainSteps`: the server half every wallet component shares |
| `lib/ash_template/chain_client.ex` | Reads at `latest` for the review's chain: `transaction/2`, `receipt/2`, `balance/2` |
| `assets/js/hooks/onchain_steps.ts` | The hook: presses, the review, reports what the wallet said |
| `assets/js/wallet_actions/send_step.ts` | One send or signature: chain switch, account check, why it failed |
| `assets/js/wallet_actions/connected_wallet.ts` | `activeEthereumWallet()`: Privy's active wallet in this tab |
| `lib/ash_template_web/live/onchain_showcase_live.ex`, `assets/js/hooks/onchain_lab.ts` | The local workshop and its stand-in wallet |

Register `OnchainSteps` in the `hooks` passed to `LiveSocket`. The hook element needs an
`id`; LiveView skips a hook without one.

## Markup

```heex
<section id={@id} phx-hook="OnchainSteps">
  <form phx-change="change" phx-submit="change" phx-target={@myself}>
    <input name="amount" value={@amount} data-onchain-input="amount" />
  </form>
  <p aria-live="polite" hidden={!@review}>{@review && review_line(@review)}</p>
  <P.button data-onchain-step="record">Record</P.button>
</section>
```

- Lines above the buttons (the review, the "from" line, the wrong-wallet note) are always
  in the page and shown or hidden with `hidden`, never added with `:if`. A line appearing
  above a pressed button otherwise makes the page update replace that button, and focus
  leaves it (Regents 65b20d87).

- Whenever a person types an amount, a line beside the button says what the press sends,
  read from the review itself (founder decision, 2026-09-27: a review screen, not
  browser-built steps). The example's is "Record and Sign use the number 42."; a money
  flow shows "You pay / You get" the same way.
- A button names its step with `data-onchain-step`. It has no `phx-click` and sits
  outside any form (rule 2). Never `disabled`, never `aria-disabled="true"`.
- Every field the review depends on carries `data-onchain-input="name"`, matching the
  review's `inputs`.
- The hook marks a button `data-awaiting-wallet="true"` while the wallet has any of its
  presses, and only removes it when the last one is answered. Style it; never block with
  it.

## The server builds the steps

```elixir
alias RegentChain.{Call, Review}

review =
  Review.new(socket.assigns.id, signer, chain, [
    Review.step("approve", token, Call.encode("approve(address,uint256)", [pool, amount])),
    Review.step("stake", pool, Call.encode("stake(uint256)", [amount])),
    Review.signature("sign", typed_data)
  ], %{"amount" => amount_as_typed})

OnchainSteps.put_review(socket, review)
```

- `chain` is `%{chain_id:, name:, rpc_url:}`; `rpc_url` is https, or http on this
  machine for a lab chain.
- `Call.encode/2` takes the exact function signature and raises on an argument that
  does not fit, so a step that cannot be built never reaches the page. `Review.step/4`
  takes wei as a fourth argument when the step pays native currency.
- `Review.signature/2` takes EIP-712 typed data as `eth_signTypedData_v4` takes it. The
  server keeps its copy; the page reports only the signature.
- A review never changes. Its `id` comes from everything in it, so a new signer, chain,
  step or input is a new review. `put_review/2` pushes it only when the id changes, and
  pushes `nil` when no wallet may act.
- Build the review whenever the signer or a figure changes (`update/2`, the form's
  `change`, the active-wallet event), so it is on the page before anyone presses.

## Which wallet sends

Founder decision "1 a", 2026-09-27: Privy's active wallet is the only wallet that acts,
and only when the signed-in account links it.

- The hook pushes `onchain_active_wallet` with the address (or `nil`) when it mounts and
  on every `ash:wallet-state`.
- `OnchainSteps.active_wallet/1` reads it; `OnchainSteps.signer(linked, active)` is the
  wallet that may act, or `nil` when signed out, when none is active, or when the account
  does not link it.
- With no signer there is no review. `OnchainSteps.mismatch_note/2` names both short
  addresses when the wallet app has another wallet open.

## A press

The hook's own click listener runs every press on its own:

1. **No active wallet**: it opens Privy's connect step and reports `wallet_unavailable`.
2. **The form differs from the review's `inputs`** (the person typed and pressed before
   the new review arrived): it sends `prepare_and_send` with the form and the step. The
   component takes the form as the page's own, builds the review and replies
   `%{review: review, send: name}`, and the hook sends that. An empty reply is
   `step_unknown`.
3. **Otherwise** it sends the step from the review it holds, if the active wallet is the
   review's signer.

Before any send or signature, `send_step.ts` switches the wallet to the step's chain
(adding it on 4902), checks the account is the signer, makes `eth_chainId` the last read,
and checks Privy has not swapped the wallet meanwhile. The hook then reports:

- `step_sent` `{review_id, step, transaction_hash}`
- `step_signed` `{review_id, step, signature}`
- `step_failed` `{step, reason}`

## The server's check

`OnchainSteps` keeps the page's last 32 reviews and 8 sent steps in a
`RegentChain.Presses`, in assigns only. A reload forgets them; the chain watcher
(`chain-events`) and the page's normal reads show what landed.

- `OnchainSteps.sent/2` finds the review by `review_id` and starts reading at once, then
  every 2 s, with `start_async({:onchain_step, hash}, …)`. Each read is
  `RegentChain.Outcome.of(ChainClient, review, step, hash)` at `latest`.
- `Outcome.of/4` answers `:pending` until the receipt exists, then `:confirmed` or
  `:reverted`. A hash whose chain, sender, target, calldata or value is not the step's
  as that review built it is `{:error, :not_this_step}`.
- After 90 reads with no receipt the step is stalled; the page offers "Check again",
  which calls `OnchainSteps.check_again/2`.
- A report for a review the page no longer holds is never checked against a later
  review; it shows the "not this step" words.
- `OnchainSteps.signed/2` returns the review's own typed data with the signature, for
  the component to verify and use.

The component forwards `handle_async({:onchain_step, hash}, result, socket)` to
`OnchainSteps.checked/3`.

## Outcomes and words

The hook sends only reason codes; the words live in `OnchainSteps.failure_note/4` and
`describe/2`.

| Reason or outcome | Meaning | Words |
| --- | --- | --- |
| Signed out | No account | "Sign in to send this. Nothing was sent." |
| `wallet_unavailable`, none active | The press opened Privy's connect step | "Connect your wallet, then press again. Nothing was sent." |
| Active wallet not linked | Another wallet is open in the wallet app | "Switch to a wallet on your account in your wallet app, then press again. Nothing was sent." |
| `step_unknown` | No step by that name for these figures | "This can't be sent as it stands. Check the details above, then press again. Nothing was sent." |
| `wallet_unavailable`, mid-press | Privy swapped the wallet during the press | "Your wallet changed during the press, so nothing was sent. Press again." |
| `network_mismatch` | The wallet would not move to the chain, or moved away | "Your wallet is on a different network. Switch it to Base, then press again. Nothing was sent." |
| `wallet_declined` | The person said no (4001) | "Your wallet declined this. Nothing was sent." |
| `insufficient_funds` | The wallet refused for lack of fees | "Your wallet doesn't have enough on Base to pay the network fee. Nothing was sent." |
| `send_unconfirmed` | The wallet failed after the send began | "Your wallet may have sent this. Check your wallet activity." |
| `:pending` | Sent, no receipt yet | "Sent. Waiting for Base." |
| `:confirmed` | The receipt succeeded | "Done." |
| `:reverted` | The receipt failed | "This did not go through and nothing moved." |
| Stalled | 90 reads, no receipt | "Base has not confirmed this yet. Check again, or look in your wallet activity." |
| Not this step | The hash is not what the review built | "This transaction is not the one this page prepared, so it can't be followed here. Check it in your wallet activity." |

A component names its steps and writes its own reverted words per action (what usually
causes it, what to do).

## Approvals

An approval is its own step with its own button ("Approve USDC"). Approve exactly the
amount the next step needs. When the approval is sent, the next button shows at once; a
press on it before the approval lands still reaches the wallet, and if it reverts the
words say so. Whether an approval is needed is read on the server at `latest` when the
review is built.

## Signing instead of sending

A `Review.signature/2` step asks for `eth_signTypedData_v4` after the same chain and
account checks. The server verifies the signature against its own typed data and does
the rest. A declined signature is `wallet_declined`. Agents sign in with SIWA
(`elixir-utils/siwa`), which is not a button.

## Checks

- The template has no test suite. Its proof is the workshop: run `anvil --port 58600`,
  then `mix phx.server`, and open `/showcase/onchain`. The stand-in wallet has lab
  accounts A and B (linked) and C (not linked), a network choice, a refusal to switch, a
  decline and a slow mode. Run every row of the table above there before changing the
  pattern.
- Sites keep their own test policy. A site that keeps a Vitest suite proves with a
  stand-in wallet that two presses in a row both reach `eth_sendTransaction`, that a
  decline reports `wallet_declined`, and that nothing is sent on the wrong chain or
  account.
- LiveView tests do not run hooks.
