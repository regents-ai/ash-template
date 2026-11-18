import {afterEach, beforeEach, expect, it, vi} from "vitest"

import {OnchainSteps, type Review} from "../js/hooks/onchain_steps"
import {replaceActiveEthereumWallet} from "../js/wallet_actions/connected_wallet"

const chainId = 84_532
const account = `0x${"a".repeat(40)}`
const hash = `0x${"ab".repeat(32)}`

// The steps the server builds for the number on screen.
const reviewFor = (amount: string): Review => ({
  id: `review-${amount}`,
  component_id: "onchain-example",
  signer: account as `0x${string}`,
  chain: {chain_id: chainId},
  steps: [
    {
      kind: "transaction",
      step: "record",
      to: "0x0000000000000000000000000000000000000004",
      data: `0x${amount.padStart(8, "0")}`,
      value: "0x0",
    },
  ],
  inputs: {amount},
})

// The page's number field, as the hook tells one from other inputs.
class Input {
  type = "text"
  constructor(
    public value: string,
    public dataset: Record<string, string>,
  ) {}
}

// A wallet app on the steps' chain that sends whatever it is asked to.
function walletApp() {
  const sent: unknown[] = []
  const provider = {
    request: async ({method, params}: {method: string; params?: unknown[]}) => {
      if (method === "eth_chainId") return `0x${chainId.toString(16)}`
      if (method === "eth_sendTransaction") {
        sent.push(params?.[0])
        return hash
      }
      throw new Error(`unexpected ${method}`)
    },
  }
  replaceActiveEthereumWallet({address: account, provider, switchChain: async () => undefined})
  return sent
}

// The reference component's hook on a page whose number field shows `amount`,
// with the server answering a request for steps with `reply`.
function component(amount: string, reply: (payload: unknown) => unknown) {
  const pushes: [string, unknown][] = []
  const handlers: Record<string, (payload: unknown) => void> = {}
  let clicked: ((event: unknown) => void) | undefined
  const button = {dataset: {onchainStep: "record"} as Record<string, string>, closest: () => button}
  const el = {
    id: "onchain-example",
    addEventListener: (_type: string, listener: (event: unknown) => void) => {
      clicked = listener
    },
    removeEventListener: () => undefined,
    contains: () => true,
    querySelectorAll: () => [new Input(amount, {onchainInput: "amount"})],
    querySelector: () => null,
  }
  const hook = {
    el,
    js: () => ({ignoreAttributes: () => undefined}),
    handleEvent: (event: string, handler: (payload: unknown) => void) => {
      handlers[event] = handler
    },
    pushEventTo: async (_target: unknown, event: string, payload: unknown) => {
      pushes.push([event, payload])
      return [{status: "fulfilled", value: {reply: event === "prepare_and_send" ? reply(payload) : {}}}]
    },
  }
  OnchainSteps.mounted!.call(hook)

  return {
    pushes,
    held: (review: Review) => handlers["onchain-steps:review"]({component_id: "onchain-example", review}),
    rejoined: () => OnchainSteps.reconnected!.call(hook),
    press: () => clicked!({target: button}),
  }
}

beforeEach(() => {
  vi.stubGlobal("window", new EventTarget())
  vi.stubGlobal("HTMLInputElement", Input)
})

afterEach(() => {
  replaceActiveEthereumWallet(null)
  vi.unstubAllGlobals()
})

// Invariant: a press that asks the server for its steps names the open wallet,
// so a page that has just joined again, whose server has not yet heard which
// wallet is open, still gets steps back and the press reaches the wallet.
it("asks for its steps with the open wallet after the page joins again, and sends them", async () => {
  const sent = walletApp()
  const page = component("1", () => ({review: reviewFor("1"), send: "record"}))
  page.held(reviewFor("1"))
  page.rejoined()

  page.press()

  await vi.waitFor(() => expect(sent).toHaveLength(1))
  expect(page.pushes.filter(([event]) => event === "prepare_and_send")).toEqual([
    ["prepare_and_send", {form: {amount: "1"}, step: "record", address: account}],
  ])
  expect(sent[0]).toMatchObject({to: "0x0000000000000000000000000000000000000004", data: "0x00000001"})
  await vi.waitFor(() =>
    expect(page.pushes).toContainEqual(["step_sent", {review_id: "review-1", step: "record", transaction_hash: hash}]),
  )
})

it("asks for the number on screen with the open wallet when the held steps are for another", async () => {
  const sent = walletApp()
  const page = component("2", () => ({review: reviewFor("2"), send: "record"}))
  page.held(reviewFor("1"))

  page.press()

  await vi.waitFor(() => expect(sent).toHaveLength(1))
  expect(page.pushes.filter(([event]) => event === "prepare_and_send")).toEqual([
    ["prepare_and_send", {form: {amount: "2"}, step: "record", address: account}],
  ])
  expect(sent[0]).toMatchObject({data: "0x00000002"})
})

// Invariant: the wallet open at the press is the one that acts for it. A press
// that asks the server for its steps sends them through that wallet, even when
// another wallet is open by the time they arrive.
it("sends the steps it asked for through the wallet open at the press", async () => {
  const sent = walletApp()
  const asked: string[] = []
  const other = {
    address: `0x${"b".repeat(40)}`,
    provider: {
      request: async ({method}: {method: string}) => {
        asked.push(method)
        return null
      },
    },
    switchChain: async () => undefined,
  }
  // The person opens another wallet while the server builds the steps.
  const page = component("1", () => {
    replaceActiveEthereumWallet(other)
    return {review: reviewFor("1"), send: "record"}
  })

  page.press()

  await vi.waitFor(() => expect(sent).toHaveLength(1))
  expect(page.pushes.filter(([event]) => event === "prepare_and_send")).toEqual([
    ["prepare_and_send", {form: {amount: "1"}, step: "record", address: account}],
  ])
  expect(sent[0]).toMatchObject({data: "0x00000001"})
  expect(asked).toEqual([])
})
