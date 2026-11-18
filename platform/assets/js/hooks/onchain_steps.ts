import type {Address, Hash, Hex} from "viem"

import type {Hook} from "../hook_composition"
import {report} from "../visit_log"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  failure,
  NothingSent,
  sendStep,
  signStep,
  type Failure,
  type Step,
  type StepChain,
} from "../wallet_actions/send_step"

/**
 * Who sends, on which chain, the steps the buttons name, and the on-screen
 * inputs they were built from, all on the server. It never changes: a new
 * figure is a new review with a new id.
 */
export type Review = {
  id: string
  component_id: string
  signer: Address
  chain: StepChain
  steps: Step[]
  inputs: Record<string, string>
}

/** What the wallet answered one press: the hash or signature, or why nothing was sent. */
export type Pressed = {transaction_hash: Hash} | {signature: Hex} | {reason: Failure}

type Push = (event: string, payload: unknown) => void

/** One report of what the wallet answered, and the press it came during. */
export type Answer = {event: string; payload: unknown; during: number}

/** Where a report ended: kept for the rejoin, heard on it, or not heard at all. */
export type Settled = "kept" | "delivered" | "lost"

type OnchainStepsHook = Hook & {
  el: HTMLElement
  js(): {ignoreAttributes(el: HTMLElement, attrs: string[]): void}
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEventTo(target: HTMLElement, event: string, payload?: unknown): Promise<PromiseSettledResult<{reply: unknown}>[]>
  review?: Review
  clicked?: (event: Event) => void
  walletChanged?: () => void
  answers?: Answers
  // How many presses this component has taken, and the line it is showing.
  pressed: number
  shown: Line
}

// How many of a button's presses the wallet still has. The mark comes off when
// the last one is answered.
const presses = new WeakMap<HTMLElement, number>()

/**
 * The wallet buttons of one server component. The component's root carries the
 * hook and a DOM id; each button names its step with `data-onchain-step`, and
 * each form field the review depends on is marked `data-onchain-input="name"`.
 */
export const OnchainSteps: Hook = {
  mounted(this: OnchainStepsHook) {
    // What the wallet answered must reach the server, which reads the step from
    // then on. When the page has no connection it cannot yet: the page says so
    // itself and keeps the answer, in memory only, until the connection is back
    // (`reconnected`), when the server first hears the wallet again and then the
    // answer. Unheard then too, it is let go, and the page says so and reports it.
    this.pressed = 0
    this.shown = null
    // A push can take half a minute to give up, so a line about one press is
    // shown only while no newer press has started: said late, "nothing was sent"
    // beside a newer press that went through would have a person send twice.
    const say = (line: Line, during: number) => {
      if (during !== this.pressed) return
      this.shown = line
      note(this.el, line)
    }
    this.answers = answers(
      async ({event, payload}) => (await this.pushEventTo(this.el, event, payload))[0]?.status === "fulfilled",
      ({event, payload, during}, settled) => {
        if (settled === "delivered") return say(null, during)
        const {step, reason} = payload as {step?: string; reason?: string}
        const answered = event !== "step_failed" || reason === "send_unconfirmed" || reason === "sign_unconfirmed"
        say(answered ? "unreported" : "lost", during)
        if (settled === "lost") report({name: "press.unsent", where: step ?? event, outcome: "lost"})
      },
    )
    const {pass} = this.answers
    const push: Push = (event, payload) => pass({event, payload, during: this.pressed})

    // Every hook on the page hears this event; keep only this component's review.
    // No review means no eligible wallet: a press then sends nothing.
    this.handleEvent("onchain-steps:review", payload => {
      const {component_id, review} = payload as {component_id: string; review: Review | null}
      if (component_id === this.el.id) this.review = review ?? undefined
    })

    // Every press runs on its own and reaches the wallet, even while an earlier
    // one is still there. On a component with review inputs, a press with no
    // review yet, or whose review no longer matches the form on screen, asks the
    // server for the matching review and sends what comes back.
    this.clicked = event => {
      const button = (event.target as Element | null)?.closest<HTMLElement>("[data-onchain-step]")
      const name = button?.dataset.onchainStep
      if (!button || !name || !this.el.contains(button)) return
      // Signed out, the server marks each button as a sign-in control: the press
      // opens Privy's sign-in (auth_lazy.ts), and there is no wallet to reach.
      if (button.dataset.accountTarget === "sign-in") return
      // The mark is this island's own, so a page update while the wallet has the
      // press leaves it on the button.
      this.js().ignoreAttributes(button, ["data-awaiting-wallet"])
      const release = mark(button)
      const form = formInputs(this.el)
      const asks = Object.keys(form).length > 0 && (!this.review || !sameInputs(this.review.inputs, form))
      const wallet = activeEthereumWallet()
      const during = (this.pressed += 1)
      say(null, during)
      // The server never heard the press, so it cannot say why; the page does, and
      // reports it.
      const unheard = () => {
        say("lost", during)
        report({name: "press.unsent", where: name, outcome: "lost"})
      }

      // The ask names the wallet too: a page that has just joined again may ask
      // before the server has heard which wallet is open.
      if (wallet && asks) {
        void this.pushEventTo(this.el, "prepare_and_send", {form, step: name, address: wallet.address})
          .then(async ([result]) => {
            if (result?.status !== "fulfilled") return unheard()
            const reply = result.value.reply as {review?: Review; send?: string}
            if (reply.review && reply.send) await press(reply.review, reply.send, push)
            else push("step_failed", {step: name, reason: "step_unknown"})
          })
          .catch(unheard)
          .finally(release)
      } else {
        void press(this.review, name, push).finally(release)
      }
    }
    this.el.addEventListener("click", this.clicked)

    // The server decides which wallet may act; it hears every change of the
    // wallet Privy has active and pushes a new review, or none. A report the
    // page could not send is not kept: `reconnected` sends the wallet open then.
    this.walletChanged = () =>
      void this.pushEventTo(this.el, "onchain_active_wallet", {address: activeEthereumWallet()?.address ?? null})
    window.addEventListener("ash:wallet-state", this.walletChanged)

    this.walletChanged()
    window.dispatchEvent(new CustomEvent("ash:wallet-sync"))
  },

  // A page that rejoins gets a fresh component on the server, which no longer
  // knows the active wallet or the review this hook holds. The review is let go
  // and the wallet told again, and only then the wallet's answers the server has
  // not heard, so the server rebuilds the steps they were sent from first.
  //
  // The rejoin redraws the component, which hides its lines again; the one this
  // hook was showing is put back, so "your wallet answered" outlives the very
  // reconnect it is about. The next press clears it, and so does the server
  // hearing the answer.
  reconnected(this: OnchainStepsHook) {
    this.review = undefined
    note(this.el, this.shown)
    this.walletChanged?.()
    this.answers?.rejoined()
  },

  // A page left behind cannot pass its answers on: each one kept is reported.
  destroyed(this: OnchainStepsHook) {
    if (this.clicked) this.el.removeEventListener("click", this.clicked)
    if (this.walletChanged) window.removeEventListener("ash:wallet-state", this.walletChanged)
    this.answers?.gone()
  },
}

type Answers = {pass(answer: Answer): void; rejoined(): void; gone(): void}

/**
 * The wallet's answers on their way to the server. `send` pushes one and says
 * whether the server heard it. One the page cannot send is kept until the page
 * joins again (`rejoined`) and then sent once more; one that was still on its way
 * when the page joined again is sent once more straight away. Unheard a second
 * time, or kept when the page is `gone`, it is lost. `settled` hears where each
 * one that was not heard the first time ended.
 */
export function answers(
  send: (answer: Answer) => Promise<boolean>,
  settled: (answer: Answer, end: Settled) => void,
): Answers {
  let joins = 0
  let gone = false
  const kept: Answer[] = []
  const pass = (answer: Answer, again: boolean) => {
    const at = joins
    void send(answer)
      .catch(() => false)
      .then(heard => {
        if (heard) {
          if (again) settled(answer, "delivered")
        } else if (again || gone) {
          settled(answer, "lost")
        } else if (at !== joins) {
          pass(answer, true)
        } else {
          kept.push(answer)
          settled(answer, "kept")
        }
      })
  }

  return {
    pass: answer => pass(answer, false),
    rejoined: () => {
      joins += 1
      for (const answer of kept.splice(0)) pass(answer, true)
    },
    gone: () => {
      gone = true
      for (const answer of kept.splice(0)) settled(answer, "lost")
    },
  }
}

/**
 * Sends or signs the named step through Privy's active wallet, the only wallet
 * that acts. With no wallet active, the press sends nothing and the server's
 * note says why. Reports only what the wallet answered, against the review it
 * sent from: the hash or signature, or why nothing was sent, and returns the
 * same answer. The server decides what the hash did.
 */
export async function press(review: Review | undefined, name: string, push: Push): Promise<Pressed> {
  const step = review?.steps.find(candidate => candidate.step === name)
  let sending = false
  const started = () => {
    sending = true
  }

  try {
    const wallet = activeEthereumWallet()
    if (!wallet) throw new NothingSent("wallet_unavailable")
    if (!review || !step) throw new NothingSent("step_unknown")

    if (step.kind === "signature") {
      const signature = await signStep(review.chain, review.signer, step, wallet, started)
      push("step_signed", {review_id: review.id, step: name, signature})
      return {signature}
    }
    const transaction_hash = await sendStep(review.chain, review.signer, step, wallet, started)
    push("step_sent", {review_id: review.id, step: name, transaction_hash})
    return {transaction_hash}
  } catch (error) {
    const reason = failure(sending, error, step?.kind === "signature")
    push("step_failed", {step: name, reason})
    return {reason}
  }
}

/**
 * The review's inputs as they are on screen now: text as typed, a box as
 * "true" or "false", and a group of choices as the one chosen.
 */
export function formInputs(root: HTMLElement): Record<string, string> {
  const inputs: Record<string, string> = {}
  root.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-onchain-input]").forEach(input => {
    const name = input.dataset.onchainInput
    if (!name) return
    if (input instanceof HTMLInputElement && input.type === "radio") {
      if (input.checked) inputs[name] = input.value
    } else {
      inputs[name] = input instanceof HTMLInputElement && input.type === "checkbox" ? String(input.checked) : input.value
    }
  })
  return inputs
}

function sameInputs(review: Record<string, string>, form: Record<string, string>): boolean {
  const names = new Set([...Object.keys(review), ...Object.keys(form)])
  return [...names].every(name => review[name] === form[name])
}

// The component's own two lines for a page without a connection:
// `data-onchain-lost` when the press never reached the server, and
// `data-onchain-unreported` when the wallet answered and the answer could not
// be passed on. `null` hides both; the next render from the server does too.
type Line = "lost" | "unreported" | null

function note(root: HTMLElement, shown: Line): void {
  for (const name of ["lost", "unreported"] as const) {
    const line = root.querySelector<HTMLElement>(`[data-onchain-${name}]`)
    if (line) line.hidden = name !== shown
  }
}

// Marked with a data attribute and CSS only: the button keeps taking presses.
function mark(button: HTMLElement): () => void {
  presses.set(button, (presses.get(button) ?? 0) + 1)
  button.dataset.awaitingWallet = "true"

  return () => {
    const left = (presses.get(button) ?? 1) - 1
    presses.set(button, left)
    if (left <= 0) delete button.dataset.awaitingWallet
  }
}
