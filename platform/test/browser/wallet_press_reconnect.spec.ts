import type {Locator, Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {watch} from "./support/person"

// Every wallet press reaches the wallet while the page's live connection drops
// and comes back: with the page offline, while LiveView is still sending the
// form back to the server as the page joins again, and once it is back. A press
// whose steps the server built is then read against them; the walk's chain is a
// closed port, so its line stays "pending" (or "stalled" once the server stops
// reading).
// The walk's friend presses: the walk's person's long name does not fit the
// wallet page's header yet, and a page wider than a phone's screen moves under a tap.
test.use({storageState: "test/browser/.auth/friend.json"})

// The friend's own wallet (support/sign_in.exs), on the wallet page's chain.
const wallet = `0x${"a".repeat(40)}`
const chainId = 84_532

type StandIn = {asked: number; sent: string[]}
type Win = {
  liveSocket: {
    disconnect(done?: () => void): void
    connect(): void
    owner(el: Element): {getHook(el: Element): {review?: {id: string}} | undefined} | undefined
  }
  standIn: StandIn
}

// A stand-in wallet app that sends every step it is asked for, made Privy's
// active wallet on this page through the page's own module that keeps it.
async function standInWallet(page: Page) {
  await page.evaluate(
    async ({address, chainId}) => {
      const w = window as unknown as Win
      const app = document.querySelector<HTMLScriptElement>('script[type=module][src*="/assets/js/app"]')!.src
      const source = await (await fetch(app)).text()
      const chunks = [...source.matchAll(/from "(\.\/chunks\/[^"]+\.js)"/g)].map(match => new URL(match[1], app).href)
      for (const chunk of chunks) {
        const module = await import(chunk)
        if (typeof module.replaceActiveEthereumWallet !== "function") continue
        const standIn: StandIn = (w.standIn = {asked: 0, sent: []})
        const provider = {
          async request({method}: {method: string}) {
            if (method === "eth_chainId") return `0x${chainId.toString(16)}`
            if (method !== "eth_sendTransaction")
              throw Object.assign(new Error(`The stand-in wallet does not answer ${method}.`), {code: 4200})
            standIn.asked += 1
            const bytes = crypto.getRandomValues(new Uint8Array(32))
            const hash = `0x${[...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("")}`
            standIn.sent.push(hash)
            return hash
          },
        }
        module.replaceActiveEthereumWallet({address, provider, switchChain: async () => undefined})
        window.dispatchEvent(new CustomEvent("ash:wallet-state"))
        return
      }
      throw new Error("No page script keeps the active wallet.")
    },
    {address: wallet, chainId},
  )
}

const asked = (page: Page) => page.evaluate(() => (window as unknown as Win).standIn.asked)

async function sentHash(page: Page) {
  await expect.poll(() => page.evaluate(() => (window as unknown as Win).standIn.sent.length)).toBe(1)
  return page.evaluate(() => (window as unknown as Win).standIn.sent[0])
}

// The review the component's hook holds, by id, or null.
const heldReview = (page: Page) =>
  page.evaluate(() => {
    const el = document.getElementById("onchain-example")
    return (el && (window as unknown as Win).liveSocket.owner(el)?.getHook(el)?.review?.id) ?? null
  })

const connected = (page: Page) => expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

async function disconnect(page: Page) {
  await page.evaluate(
    () =>
      new Promise<void>(resolve =>
        (window as unknown as Win).liveSocket.disconnect(() => {
          document.querySelector("[data-phx-main]")!.classList.remove("phx-connected")
          resolve()
        }),
      ),
  )
}

const rejoin = (page: Page) => page.evaluate(() => (window as unknown as Win).liveSocket.connect())

// LiveView sends a page's forms back first when it joins again, and draws the page
// and runs the hooks' `reconnected` only once the server has answered. This holds
// that answer until `release`, as a slow network would.
async function holdRecovery(page: Page) {
  const hold = {armed: false, refs: new Set<string>(), held: [] as (() => void)[]}
  await page.routeWebSocket(/\/live\/websocket/, socket => {
    const server = socket.connectToServer()
    socket.onMessage(message => {
      if (hold.armed && typeof message === "string") {
        const frame = JSON.parse(message)
        if (frame[3] === "event" && frame[4]?.type === "form") hold.refs.add(frame[1])
      }
      server.send(message)
    })
    server.onMessage(message => {
      if (typeof message === "string") {
        const frame = JSON.parse(message)
        if (frame[3] === "phx_reply" && hold.refs.delete(frame[1])) {
          hold.held.push(() => socket.send(message))
          return
        }
      }
      socket.send(message)
    })
  })
  return {
    arm: () => {
      hold.armed = true
    },
    holding: () => hold.held.length,
    release: () => {
      hold.armed = false
      for (const send of hold.held.splice(0)) send()
    },
  }
}

// The wallet page, signed in, with the stand-in wallet open on the friend's own
// wallet and the steps the server built for it held by the page.
async function open(page: Page) {
  await page.goto("/showcase/wallet")
  await connected(page)
  await standInWallet(page)
  await expect.poll(() => heldReview(page)).not.toBeNull()
}

const record = (page: Page) => page.locator("#onchain-example [data-onchain-step='record']")
const press = (target: Locator, hasTouch: boolean) => (hasTouch ? target.tap() : target.click())
const followed = (page: Page, hash: string) =>
  expect(page.locator(`#onchain-example li[data-state]:has([id="onchain-example-sent-${hash}"])`)).toHaveAttribute(
    "data-state",
    /^(pending|stalled)$/,
  )

test("a press while the page is offline reaches the wallet", async ({page, hasTouch}) => {
  const problems = watch(page)
  await open(page)

  await disconnect(page)
  await press(record(page), hasTouch)

  await expect.poll(() => asked(page)).toBe(1)
  await problems.expect()
})

test.describe("a press while LiveView sends the form back", () => {
  test("a press from the steps the page holds reaches the wallet", async ({page, hasTouch}) => {
    const problems = watch(page)
    const recovery = await holdRecovery(page)
    await open(page)

    await disconnect(page)
    recovery.arm()
    await rejoin(page)
    await expect.poll(() => recovery.holding()).toBeGreaterThan(0)
    await press(record(page), hasTouch)
    await expect.poll(() => asked(page)).toBe(1)
    recovery.release()
    await connected(page)

    await problems.expect()
  })

  test("a press after the number changed reaches the wallet and is followed", async ({page, hasTouch}) => {
    const problems = watch(page)
    const recovery = await holdRecovery(page)
    await open(page)

    await disconnect(page)
    await page.locator("#onchain-example-amount").fill("2")
    recovery.arm()
    await rejoin(page)
    await expect.poll(() => recovery.holding()).toBeGreaterThan(0)
    // The page holds the steps for 1 and shows 2, so the press asks the server for
    // the steps for 2 while the server has not yet heard which wallet is open.
    await press(record(page), hasTouch)
    await expect.poll(() => asked(page)).toBe(1)
    const hash = await sentHash(page)
    recovery.release()
    await connected(page)

    await followed(page, hash)
    await problems.expect()
  })
})

test("a press after the number changed, once the page is back, reaches the wallet and is followed", async ({
  page,
  hasTouch,
}) => {
  const problems = watch(page)
  await open(page)

  await disconnect(page)
  await page.locator("#onchain-example-amount").fill("2")
  await rejoin(page)
  await connected(page)
  await press(record(page), hasTouch)
  const hash = await sentHash(page)

  await followed(page, hash)
  await problems.expect()
})
