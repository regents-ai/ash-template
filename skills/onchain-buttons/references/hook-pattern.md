# The hook pattern

Code here was typechecked with TypeScript `--strict` and its tests run with Vitest 4.1
against the template's `connected_wallet.ts` and viem 2.55. The Elixir compiles against
Ash 3.33 and Phoenix LiveView 1.2.11. `MyApp` stands for the site's own module prefix.

## Files

| File | Holds |
| --- | --- |
| `assets/js/wallet_actions/send_step.ts` | Sending one step: chain switch, account check, the send, why it failed |
| `assets/js/hooks/onchain_steps.ts` | The hook: listens for presses, reports what the wallet said |
| `assets/js/wallet_actions/connected_wallet.ts` | Already in the template: `connectedEthereumWallet(signer)` is the signed-in wallet as this tab has it connected |
| The LiveComponent | Renders the button, owns the words, checks the result on the chain |

Register the hook in the `hooks` passed to `LiveSocket` (compose with `composeHooks` when an
element needs two). The hook element needs an `id`; LiveView skips a hook without one.

## Markup

```heex
<section id={@id} phx-hook="OnchainSteps" phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}>
  <button :if={@next} type="button" data-onchain-step={@next}>
    <span data-press-label>{@label}</span>
    <span data-wallet-wait>Confirm in wallet</span>
  </button>
</section>
```

- `type="button"`, a `data-onchain-step` naming the step, no `phx-click`, no enclosing
  `<form phx-submit>`. A form beside it for the amount is fine; the button is outside it.
- Never `disabled`, never `aria-disabled="true"`: the motion kit shakes an
  `aria-disabled` control instead of pressing it, and the press must still happen.
- `data-press-label` wraps the words so the kit squishes them, never the button itself.
- `JS.ignore_attributes(["data-awaiting-wallet"])` keeps the hook's mark across patches.
- One button per step. Show the next unsent step; a sent step moves the button on at once.

## The server builds the steps

The server encodes every step (founder decision, 2026-09-27), then pushes the review
from the event that built it:

```elixir
push_event(socket, "onchain-steps:review", %{
  component_id: socket.assigns.id,
  signer: wallet,
  chain: %{chain_id: 8453, name: "Base", rpc_url: public_rpc_url},
  steps: [%{step: "approve", to: token, data: approve_calldata}, %{step: "stake", to: pool, data: stake_calldata}]
})
```

The hook keeps the latest review for its own `component_id` and sends the named step on
a press; the browser never encodes calldata. Push the review as soon as the figures it
needs are known and again whenever they change, so it is on the page before the button
is pressed. A press never asks the server for its step while the wallet waits. The
server's check compares the sent transaction with exactly the calldata it built.

## Sending one step

```ts
import {getAddress, type Address, type Hash, type Hex} from "viem"

import type {EthereumProvider, SelectedWallet} from "./connected_wallet"

/** The chain a step goes to, as the server names it for the wallet's prompt. */
export type StepChain = {chain_id: number; name: string; rpc_url: string}

/** One transaction a button sends, whoever built it. */
export type Step = {step: string; to: Address; data: Hex; value?: Hex}

/** Nothing reached the wallet's send; the reason picks the words the server shows. */
export class NothingSent extends Error {
  constructor(readonly reason: "step_unknown" | "wallet_unavailable" | "network_mismatch") {
    super(reason)
  }
}

export type Failure = NothingSent["reason"] | "wallet_declined" | "send_unconfirmed"

/**
 * Sends one step from the signed-in wallet. Chain and account are read again on
 * every press, and `eth_chainId` is the last read before the send, so a wallet
 * that changes network part-way is refused before it sees the transaction.
 */
export async function sendStep(
  chain: StepChain,
  signer: Address,
  step: Step,
  wallet: () => SelectedWallet | null,
  sending: () => void,
): Promise<Hash> {
  const selected = wallet()
  if (!selected) throw new NothingSent("wallet_unavailable")
  const {provider} = selected

  if ((await chainId(provider)) !== chain.chain_id) await switchChain(provider, chain)

  const [account] = await accounts(provider)
  if (!account || getAddress(account) !== getAddress(signer)) throw new NothingSent("wallet_unavailable")
  if ((await chainId(provider)) !== chain.chain_id) throw new NothingSent("network_mismatch")
  // Privy may have swapped the wallet during those reads; this check makes no request.
  if (wallet()?.provider !== provider) throw new NothingSent("wallet_unavailable")

  sending()
  const hash = await provider.request({
    method: "eth_sendTransaction",
    params: [{from: getAddress(signer), to: getAddress(step.to), data: step.data, value: step.value ?? "0x0"}],
  })
  if (typeof hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(hash)) {
    throw new Error("The wallet did not return a transaction hash.")
  }
  return hash as Hash
}

/** Why a press ended without a hash. After `sending`, the wallet may have sent it. */
export function failure(sending: boolean, error: unknown): Failure {
  if (!sending) return error instanceof NothingSent ? error.reason : "wallet_unavailable"
  return hasCode(error, 4001) ? "wallet_declined" : "send_unconfirmed"
}

async function switchChain(provider: EthereumProvider, chain: StepChain): Promise<void> {
  const chainId = `0x${chain.chain_id.toString(16)}`
  try {
    try {
      await provider.request({method: "wallet_switchEthereumChain", params: [{chainId}]})
    } catch (error) {
      if (!hasCode(error, 4902)) throw error
      await provider.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId,
          chainName: chain.name,
          nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
          rpcUrls: [chain.rpc_url],
        }],
      })
      await provider.request({method: "wallet_switchEthereumChain", params: [{chainId}]})
    }
  } catch {
    throw new NothingSent("network_mismatch")
  }
}

async function chainId(provider: EthereumProvider): Promise<number> {
  const value = await provider.request({method: "eth_chainId"})
  return typeof value === "string" && /^0x[0-9a-f]+$/i.test(value) ? Number(BigInt(value)) : -1
}

async function accounts(provider: EthereumProvider): Promise<string[]> {
  const value = await provider.request({method: "eth_accounts"})
  return Array.isArray(value) ? value.filter((a): a is string => typeof a === "string") : []
}

// Wallets wrap the EIP-1193 code in `cause` chains of their own.
function hasCode(error: unknown, code: number): boolean {
  for (let e = error, seen = 0; e && typeof e === "object" && seen < 8; e = (e as {cause?: unknown}).cause, seen++) {
    if ((e as {code?: unknown}).code === code) return true
  }
  return false
}
```

- `sending()` marks the line after which the wallet may have sent. A failure before it
  proves nothing was sent; after it, only a 4001 decline proves that.
- Test chains (31337 local lab or fork, 31338 Robinhood local lab) can be reset between
  review and press. Autolaunch also checks the wallet's copy of the fork holds the
  reviewed block before sending; copy that check when a site sends on a fork.
- `value` is `0x0` unless the step pays native currency.

## The hook

```ts
import type {Address} from "viem"

import {connectedEthereumWallet} from "../wallet_actions/connected_wallet"
import {failure, NothingSent, sendStep, type Step, type StepChain} from "../wallet_actions/send_step"

/** Who sends, on which chain, and the steps the panel's buttons name. */
export type Review = {component_id: string; signer: Address; chain: StepChain; steps: Step[]}

type Push = (event: string, payload: unknown) => void

type OnchainStepsHook = {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: Review) => void): void
  pushEventTo(target: HTMLElement, event: string, payload: unknown): void
  review?: Review
  clicked?: (event: Event) => void
}

export const OnchainSteps = {
  mounted(this: OnchainStepsHook) {
    const push: Push = (event, payload) => this.pushEventTo(this.el, event, payload)

    // Every hook on the page hears this event; keep only this panel's review.
    this.handleEvent("onchain-steps:review", review => {
      if (review.component_id === this.el.id) this.review = review
    })

    this.clicked = event => {
      const button = (event.target as Element | null)?.closest<HTMLElement>("[data-onchain-step]")
      const name = button?.dataset.onchainStep
      if (name) void press(this.el, this.review, name, push)
    }
    this.el.addEventListener("click", this.clicked)
  },

  destroyed(this: OnchainStepsHook) {
    if (this.clicked) this.el.removeEventListener("click", this.clicked)
  },
}

// Every press runs on its own and reaches the wallet, even while an earlier one
// is still there. The panel is marked, never locked, and the hook reports only
// what the wallet answered: the server decides what the hash did.
export async function press(el: HTMLElement, review: Review | undefined, name: string, push: Push) {
  const step = review?.steps.find(candidate => candidate.step === name)
  let sending = false
  el.dataset.awaitingWallet = name

  try {
    if (!review || !step) throw new NothingSent("step_unknown")
    const wallet = () => connectedEthereumWallet(review.signer)
    if (!wallet()) {
      window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
      throw new NothingSent("wallet_unavailable")
    }

    const transaction_hash = await sendStep(review.chain, review.signer, step, wallet, () => {
      sending = true
    })
    push("step_sent", {step: name, transaction_hash})
  } catch (error) {
    push("step_failed", {step: name, reason: failure(sending, error)})
  } finally {
    if (el.dataset.awaitingWallet === name) delete el.dataset.awaitingWallet
  }
}
```

## Pending marks

`data-awaiting-wallet` on the panel means the wallet has a press. Style it and nothing
else:

```css
[data-wallet-wait] { display: none; }
[data-awaiting-wallet] [data-press-label] { display: none; }
[data-awaiting-wallet] [data-wallet-wait] { display: inline-flex; }
```

The button still takes presses; each one opens the wallet again. LiveView's own
`phx-click-loading` classes never appear on an on-chain button, because it has no
`phx-click`.

## The server's check

`MyApp.Chain.Client` is the chain client from `chain-events`: `transaction/1` and
`receipt/1` read at `latest`.

```elixir
defmodule MyApp.Chain.Outcome do
  @moduledoc "What a sent step did, read at `latest`."

  @doc """
  `:pending` until the receipt exists, then `:confirmed` or `:reverted`. A hash
  whose sender, target or calldata is not the step's is not an answer about it.
  """
  def of(client, hash, signer, %{"to" => to, "data" => data}) do
    with {:ok, tx} when is_map(tx) <- client.transaction(hash),
         true <- same_step?(tx, signer, to, data) || {:error, :not_this_step},
         {:ok, receipt} <- client.receipt(hash) do
      {:ok, status(receipt)}
    else
      {:ok, nil} -> {:ok, :pending}
      error -> error
    end
  end

  defp same_step?(tx, signer, to, data),
    do: Enum.map([tx["from"], tx["to"], tx["input"]], &String.downcase/1) == Enum.map([signer, to, data], &String.downcase/1)

  defp status(nil), do: :pending
  defp status(%{"status" => "0x1"}), do: :confirmed
  defp status(%{"status" => "0x0"}), do: :reverted
end
```

In the LiveComponent, from the moment the hash arrives:

```elixir
defmodule MyAppWeb.StakePanel do
  use Phoenix.LiveComponent
  alias Phoenix.LiveView.JS

  @recheck_ms 2_000
  @recheck_limit 90

  @impl true
  def mount(socket), do: {:ok, assign(socket, sent: %{}, notice: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} phx-hook="OnchainSteps" phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}>
      <button :if={@next} type="button" data-onchain-step={@next}>
        <span data-press-label>{@label}</span>
        <span data-wallet-wait>Confirm in wallet</span>
      </button>
      <button :for={name <- stalled(@sent)} type="button" phx-click="check_again" phx-value-step={name} phx-target={@myself}>
        Check again
      </button>
      <p :if={@notice} role="alert">{@notice}</p>
    </section>
    """
  end

  @impl true
  def handle_event("step_sent", %{"step" => name, "transaction_hash" => hash}, socket) do
    sent = Map.put(socket.assigns.sent, name, %{hash: hash, outcome: :pending, reads: 0})
    {:noreply, socket |> assign(sent: sent, notice: nil) |> check(name)}
  end

  def handle_event("step_failed", %{"reason" => reason}, socket),
    do: {:noreply, assign(socket, notice: failure_copy(reason, socket.assigns.chain_name))}

  def handle_event("check_again", %{"step" => name}, socket),
    do: {:noreply, socket |> update(:sent, &put_in(&1[name].reads, 0)) |> check(name)}

  # Read off the page's process; an answer for a hash the page has since left is dropped.
  @impl true
  def handle_async({:check, name}, {:ok, {hash, answer}}, socket) do
    case socket.assigns.sent[name] do
      %{hash: ^hash} = sent -> {:noreply, checked(socket, name, sent, answer)}
      _left -> {:noreply, socket}
    end
  end

  def handle_async({:check, name}, {:exit, _reason}, socket),
    do: {:noreply, checked(socket, name, socket.assigns.sent[name], {:error, :read_failed})}

  defp check(socket, name) do
    %{hash: hash, reads: reads} = socket.assigns.sent[name]
    step = Enum.find(socket.assigns.steps, &(&1["step"] == name))
    %{client: client, signer: signer} = socket.assigns

    start_async(socket, {:check, name}, fn ->
      if reads > 0, do: Process.sleep(@recheck_ms)
      {hash, MyApp.Chain.Outcome.of(client, hash, signer, step)}
    end)
  end

  # A read that failed is no answer about the step; it is read again.
  defp checked(socket, name, sent, answer) do
    outcome = with {:ok, outcome} <- answer, do: outcome, else: (_ -> :pending)
    sent = %{sent | outcome: outcome, reads: sent.reads + 1}
    socket = update(socket, :sent, &Map.put(&1, name, sent))

    cond do
      outcome == :reverted -> assign(socket, notice: "That did not go through and nothing moved. Try again.")
      outcome == :pending and sent.reads < @recheck_limit -> check(socket, name)
      true -> socket
    end
  end

  defp stalled(sent), do: for({name, %{outcome: :pending, reads: reads}} <- sent, reads >= @recheck_limit, do: name)

  defp failure_copy("step_unknown", _chain), do: "This page is out of date. Refresh it and press again."

  defp failure_copy("wallet_unavailable", _chain),
    do: "Nothing was sent. Check the wallet you signed in with is connected and open, then press again."

  defp failure_copy("network_mismatch", chain), do: "Your wallet is on a different network. Switch it to #{chain}, then try again. Nothing was sent."
  defp failure_copy("wallet_declined", _chain), do: "Your wallet declined this. Nothing was sent."
  defp failure_copy("send_unconfirmed", _chain), do: "Your wallet may have sent this. Check your wallet activity."
end
```

- `start_async` keeps the page responsive, and a check for a hash the page has since left
  is dropped by matching `^hash`.
- The sent map lives in assigns only. A reload forgets it; the chain watcher and the
  page's normal reads show what landed.
- When the last step confirms, re-read the figures that moved and say it is done.

## Outcomes and words

| Reason or outcome | Meaning | Words |
| --- | --- | --- |
| `step_unknown` | The page holds no review with that step | "This page is out of date. Refresh it and press again." |
| `wallet_unavailable` | The signed-in wallet is not connected here, or is on another account | "Nothing was sent. Check the wallet you signed in with is connected and open, then press again." |
| `network_mismatch` | The wallet would not move to the chain, or moved away | "Your wallet is on a different network. Switch it to Base, then try again. Nothing was sent." |
| `wallet_declined` | The person said no in the wallet (4001) | "Your wallet declined this. Nothing was sent." |
| `send_unconfirmed` | The wallet failed after the send began | "Your wallet may have sent this. Check your wallet activity." |
| `:pending` | Sent, no receipt yet | "Sent. Waiting for Base." beside the step |
| `:confirmed` | The receipt succeeded | The step shows done; the next one shows |
| `:reverted` | The receipt failed | Say nothing moved and what to try; the step can be pressed again |
| Read limit reached | Still no receipt after 90 reads | A "Check again" button |

Write the reverted words per action (what usually causes it, what to do). The hook sends
only reason codes; every word lives on the server.

## Approvals

An approval is its own step with its own button ("Approve USDC"). Approve exactly the
amount the next step needs. When the approval is sent, the next button shows at once; a
press on it before the approval lands still reaches the wallet, and if it reverts the
words say so. Whether an approval is needed at all is read on the server at `latest` when
the steps are built or rendered.

## Signing instead of sending

The same rules hold for a button that asks the wallet to sign (an x402 payment through
`eth_signTypedData_v4`, as Patchbay does in `platform/assets/js/privy_bridge.jsx`): the
hook's click listener, the signed-in wallet, the chain the typed data names, the
signature reported to the server, which verifies it and does the rest. A declined
signature is `wallet_declined`. Agents sign in with SIWA (`elixir-utils/siwa`), which is
not a button.

## Tests

```ts
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"

import {press, type Review} from "../js/hooks/onchain_steps"
import {replaceConnectedEthereumWallets, type EthereumProvider} from "../js/wallet_actions/connected_wallet"

const signer = "0x1111111111111111111111111111111111111111"
const hash = `0x${"ab".repeat(32)}`

const review: Review = {
  component_id: "stake-panel",
  signer,
  chain: {chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"},
  steps: [{step: "approve", to: "0x2222222222222222222222222222222222222222", data: "0x095ea7b3"}],
}

// A stand-in wallet: answers by method name, and holds every send until released.
function wallet(answers: Record<string, unknown> = {}) {
  const sends: Array<(value: unknown) => void> = []
  const provider: EthereumProvider = {
    request: vi.fn(async ({method}) => {
      if (method === "eth_sendTransaction") return new Promise(resolve => sends.push(resolve))
      const answer = ({eth_chainId: "0x2105", eth_accounts: [signer], ...answers} as Record<string, unknown>)[method]
      if (answer instanceof Error) throw answer
      return answer
    }),
  }
  replaceConnectedEthereumWallets([[signer, {provider, disconnect: () => {}}]])
  return {provider, sends}
}

const methods = (provider: EthereumProvider) =>
  vi.mocked(provider.request).mock.calls.map(([{method}]) => method)

const panel = () => ({id: "stake-panel", dataset: {}}) as unknown as HTMLElement

let pushed: Array<[string, unknown]>
const push = (event: string, payload: unknown) => void pushed.push([event, payload])
const dispatched: string[] = []

beforeEach(() => {
  pushed = []
  dispatched.length = 0
  vi.stubGlobal("window", {
    location: {origin: "https://example.com"},
    localStorage: {getItem: () => null},
    dispatchEvent: (event: Event) => void dispatched.push(event.type),
  })
})

afterEach(() => vi.unstubAllGlobals())

describe("a press on an on-chain button", () => {
  it("reaches the wallet every time, even while the first is still there", async () => {
    const {provider, sends} = wallet()
    const el = panel()

    const first = press(el, review, "approve", push)
    const second = press(el, review, "approve", push)
    await vi.waitFor(() => expect(sends).toHaveLength(2))
    expect(el.dataset.awaitingWallet).toBe("approve")

    sends.forEach(send => send(hash))
    await Promise.all([first, second])
    expect(methods(provider).filter(m => m === "eth_sendTransaction")).toHaveLength(2)
    expect(pushed).toEqual([
      ["step_sent", {step: "approve", transaction_hash: hash}],
      ["step_sent", {step: "approve", transaction_hash: hash}],
    ])
  })

  it("reads the chain last before sending", async () => {
    const {provider, sends} = wallet()
    const sent = press(panel(), review, "approve", push)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    sends[0](hash)
    await sent
    expect(methods(provider).slice(-2)).toEqual(["eth_chainId", "eth_sendTransaction"])
  })

  it("reports a decline", async () => {
    const {provider} = wallet()
    vi.mocked(provider.request).mockImplementation(async ({method}) => {
      if (method === "eth_sendTransaction") throw Object.assign(new Error("no"), {code: 4001})
      return ({eth_chainId: "0x2105", eth_accounts: [signer]} as Record<string, unknown>)[method]
    })
    await press(panel(), review, "approve", push)
    expect(pushed).toEqual([["step_failed", {step: "approve", reason: "wallet_declined"}]])
  })

  it("sends nothing from another account", async () => {
    const {provider} = wallet({eth_accounts: ["0x3333333333333333333333333333333333333333"]})
    await press(panel(), review, "approve", push)
    expect(methods(provider)).not.toContain("eth_sendTransaction")
    expect(pushed).toEqual([["step_failed", {step: "approve", reason: "wallet_unavailable"}]])
  })

  it("sends nothing when the wallet will not switch chain", async () => {
    const {provider} = wallet({
      eth_chainId: "0x1",
      wallet_switchEthereumChain: Object.assign(new Error("no"), {code: 4001}),
    })
    await press(panel(), review, "approve", push)
    expect(methods(provider)).not.toContain("eth_sendTransaction")
    expect(pushed).toEqual([["step_failed", {step: "approve", reason: "network_mismatch"}]])
  })

  it("opens the connect step when the signed-in wallet is not connected here", async () => {
    replaceConnectedEthereumWallets([])
    await press(panel(), review, "approve", push)
    expect(dispatched).toEqual(["ash:wallet-connect"])
    expect(pushed).toEqual([["step_failed", {step: "approve", reason: "wallet_unavailable"}]])
  })

  it("says the page is out of date when it has no such step", async () => {
    wallet()
    await press(panel(), undefined, "approve", push)
    expect(pushed).toEqual([["step_failed", {step: "approve", reason: "step_unknown"}]])
  })
})
```

LiveView tests cover the server: `render_hook(element(view, "#stake-panel"), "step_sent", ...)` against a stub
client that answers `transaction/1` and `receipt/1`, then assert the words and the next
button. They cannot run the hook, so the Vitest file above is the only proof that presses
reach the wallet.
