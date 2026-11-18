import type {Locator, Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {watch} from "./support/person"

// A wallet press is followed to its outcome whatever the page's live connection
// does meanwhile. Every press reaches the wallet; these walks drop the connection,
// hold the wallet's answer, hold LiveView's form recovery as the page joins again,
// and leave the page by live navigation, then check that the server reads each
// sent step against the step it built. The walk's chain is a closed port, so a
// followed step stays on its way: its line is "pending" (or "stalled" once the
// server stops reading). A line marked "unknown" is a hash the server could not
// match to a step it built, so it is not followed.
// The walk's friend presses: the walk's person's long name does not fit the
// wallet page's header yet, and a page wider than a phone's screen moves under a tap.
test.use({storageState: "test/browser/.auth/friend.json"})

// The friend's own wallet (support/sign_in.exs), on the wallet page's chain.
const wallet = `0x${"a".repeat(40)}`
const chainId = 84_532

type StandIn = {asked: number; sent: string[]; hold: boolean; decline: boolean; answers: (() => void)[]}
type Win = {
  liveSocket: {
    disconnect(done?: () => void): void
    connect(): void
    execJS(el: Element, encoded: string): void
    owner(el: Element): {getHook(el: Element): {review?: {id: string}} | undefined} | undefined
  }
  standIn: StandIn
}

// A stand-in wallet app, made Privy's active wallet on this page through the
// page's own module that keeps it. With `hold`, each send waits for `answer` as a
// wallet prompt the person has not answered yet; with `decline`, it is declined.
async function standInWallet(page: Page, {hold = false, decline = false} = {}) {
  await page.evaluate(
    async ({address, chainId, hold, decline}) => {
      const w = window as unknown as Win
      const app = document.querySelector<HTMLScriptElement>('script[type=module][src*="/assets/js/app"]')!.src
      const source = await (await fetch(app)).text()
      const chunks = [...source.matchAll(/from "(\.\/chunks\/[^"]+\.js)"/g)].map(match => new URL(match[1], app).href)
      for (const chunk of chunks) {
        const module = await import(chunk)
        if (typeof module.replaceActiveEthereumWallet !== "function") continue
        const standIn: StandIn = (w.standIn = {asked: 0, sent: [], hold, decline, answers: []})
        const provider = {
          async request({method}: {method: string}) {
            if (method === "eth_chainId") return `0x${chainId.toString(16)}`
            if (method !== "eth_sendTransaction")
              throw Object.assign(new Error(`The stand-in wallet does not answer ${method}.`), {code: 4200})
            standIn.asked += 1
            if (standIn.hold) await new Promise<void>(resolve => standIn.answers.push(resolve))
            if (standIn.decline) throw Object.assign(new Error("User rejected the request."), {code: 4001})
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
    {address: wallet, chainId, hold, decline},
  )
}

const asked = (page: Page) => page.evaluate(() => (window as unknown as Win).standIn.asked)
const answer = (page: Page) => page.evaluate(() => (window as unknown as Win).standIn.answers.shift()?.())

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

// The wallet page, signed in, with the stand-in wallet open on the person's own
// wallet and the steps the server built for it held by the page.
async function open(page: Page, options: Parameters<typeof standInWallet>[1] = {}) {
  await page.goto("/showcase/wallet")
  await connected(page)
  await standInWallet(page, options)
  await expect.poll(() => heldReview(page)).not.toBeNull()
}

const record = (page: Page) => page.locator("#onchain-example [data-onchain-step='record']")
const press = (target: Locator, hasTouch: boolean) => (hasTouch ? target.tap() : target.click())
const sentLine = (page: Page, hash: string) => page.locator(`#onchain-example li[data-state]:has([id="onchain-example-sent-${hash}"])`)
const followed = (page: Page, hash: string) => expect(sentLine(page, hash)).toHaveAttribute("data-state", /^(pending|stalled)$/)

test.describe("the page is offline when the wallet answers", () => {
  test("a hash the wallet returns while the page is offline is followed once it is back", async ({page, hasTouch}) => {
    const problems = watch(page)
    await open(page, {hold: true})

    await press(record(page), hasTouch)
    await expect.poll(() => asked(page)).toBe(1)
    await disconnect(page)
    await answer(page)
    const hash = await sentHash(page)
    await rejoin(page)
    await connected(page)

    await followed(page, hash)
    await expect(page.locator("#onchain-example [data-onchain-unreported]")).toBeHidden()
    await problems.expect()
  })

  test("a press made while the page is offline reaches the wallet and is followed once it is back", async ({page, hasTouch}) => {
    const problems = watch(page)
    await open(page)

    await disconnect(page)
    await press(record(page), hasTouch)
    const hash = await sentHash(page)
    await rejoin(page)
    await connected(page)

    await followed(page, hash)
    await problems.expect()
  })

  test("a decline while the page is offline is told to the server once it is back", async ({page, hasTouch}) => {
    const problems = watch(page)
    await open(page, {hold: true, decline: true})

    await press(record(page), hasTouch)
    await expect.poll(() => asked(page)).toBe(1)
    await disconnect(page)
    await answer(page)
    await rejoin(page)
    await connected(page)

    await expect(page.locator("#onchain-example-press-note")).toBeVisible()
    await expect(page.locator("#onchain-example [data-onchain-lost]")).toBeHidden()
    await problems.expect()
  })
})

test.describe("a wallet prompt is open while the page joins again", () => {
  test("a hash returned just as the page is drawn again is followed", async ({page, hasTouch}) => {
    const problems = watch(page)
    await open(page, {hold: true})

    await press(record(page), hasTouch)
    await expect.poll(() => asked(page)).toBe(1)
    await disconnect(page)
    // The person confirms on the first tick after LiveView marks the page connected.
    await page.evaluate(() => {
      const main = document.querySelector("[data-phx-main]")!
      const observer = new MutationObserver(() => {
        if (!main.classList.contains("phx-connected")) return
        observer.disconnect()
        ;(window as unknown as Win).standIn.answers.shift()?.()
      })
      observer.observe(main, {attributes: true, attributeFilter: ["class"]})
    })
    await rejoin(page)
    const hash = await sentHash(page)

    await followed(page, hash)
    await problems.expect()
  })

  test("a hash returned while LiveView is still recovering the form is followed", async ({page, hasTouch}) => {
    const problems = watch(page)
    const recovery = await holdRecovery(page)
    await open(page, {hold: true})

    await press(record(page), hasTouch)
    await expect.poll(() => asked(page)).toBe(1)
    await disconnect(page)
    recovery.arm()
    await rejoin(page)
    await expect.poll(() => recovery.holding()).toBeGreaterThan(0)
    await answer(page)
    const hash = await sentHash(page)
    recovery.release()
    await connected(page)

    await followed(page, hash)
    await problems.expect()
  })
})

test.describe("a press while LiveView recovers the form", () => {
  test("a press from the steps the page holds is followed", async ({page, hasTouch}) => {
    const problems = watch(page)
    const recovery = await holdRecovery(page)
    await open(page)

    await disconnect(page)
    recovery.arm()
    await rejoin(page)
    await expect.poll(() => recovery.holding()).toBeGreaterThan(0)
    await press(record(page), hasTouch)
    const hash = await sentHash(page)
    recovery.release()
    await connected(page)

    await followed(page, hash)
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

// Not followed yet: the page that pressed is gone when the wallet answers, and the
// page that comes back has a new hook and a new server process. Where an answer
// would be kept across a live navigation is a decision (docs/feature-map.md).
test.fail("a press whose wallet prompt is open across a live navigation away and back is followed", async ({page, hasTouch}) => {
  await open(page, {hold: true})

  await press(record(page), hasTouch)
  await expect.poll(() => asked(page)).toBe(1)
  const navigate = (href: string) =>
    page.evaluate(href => {
      ;(window as unknown as Win).liveSocket.execJS(document.body, JSON.stringify([["navigate", {href, replace: false}]]))
    }, href)
  await navigate("/showcase/figures")
  await expect(page).toHaveURL(/\/showcase\/figures$/)
  await navigate("/showcase/wallet")
  await expect(page).toHaveURL(/\/showcase\/wallet$/)
  await expect.poll(() => heldReview(page)).not.toBeNull()
  // The same page script throughout: both navigations were live.
  expect(await asked(page)).toBe(1)
  await answer(page)
  const hash = await sentHash(page)

  await followed(page, hash)
})
