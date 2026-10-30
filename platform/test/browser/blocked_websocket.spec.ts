import type {Page, WebSocketRoute} from "@playwright/test"
import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// Pages connect by websocket only. On a network that refuses websockets, signing in
// and out still work: Sign in starts the sign-in bridge, which then needs one request
// to /auth/privy/session and a reload; the page as served shows the account, and its
// menu holds Sign out. A live form says it is not connected and its buttons are
// disabled until the connection is back (AshTemplateWeb.LiveConnection).
const live = /\/live\/websocket/

const refuseWebsockets = (page: Page) =>
  page.routeWebSocket(live, socket => socket.close({code: 1011, reason: "refused"}))

const bridge = /^\/assets\/js\/privy_bridge(-[0-9a-f]+)?\.js$/

test("with websockets refused, Sign in still starts the sign-in bridge", async ({page, hasTouch}) => {
  await refuseWebsockets(page)
  await page.goto("/notes")
  const loaded = page.waitForRequest(request => bridge.test(new URL(request.url()).pathname))
  const signIn = page.locator("#account-control [data-account-target='sign-in']")
  await (hasTouch ? signIn.tap() : signIn.click())
  await loaded
  await expect(page.locator("[data-phx-main].phx-connected")).toHaveCount(0)
})

test.describe("signed in", () => {
  test.use(signedIn)

  test("with websockets refused, a signed-in page shows the account and its menu holds Sign out", async ({page, hasTouch}) => {
    const problems = watch(page)
    await refuseWebsockets(page)
    await page.goto("/rooms/general")
    await expect(page.locator("#account-control [data-account-target='sign-in']")).toHaveCount(0)
    const chip = page.locator("#account-chip")
    await (hasTouch ? chip.tap() : chip.click())
    await expect(page.locator("#account-menu").getByRole("button", {name: "Sign out"})).toBeVisible()
    await expect(page.locator("[data-phx-main].phx-connected")).toHaveCount(0)
    await problems.expect()
  })

  test("with websockets refused, Send says it is not connected and is disabled", async ({page}) => {
    await refuseWebsockets(page)
    await page.goto("/rooms/general")
    const notice = page.locator("#room-message-offline")
    await expect(notice).toHaveText("Not connected. Trying again…")
    await expect(page.locator("#room-message-form").getByRole("button", {name: "Send"})).toBeDisabled()
    await expect(page.locator("#room-message-body")).toBeEditable()
  })

  test("with websockets refused, the pairing box says it is not connected and its agents are disabled", async ({page}) => {
    await refuseWebsockets(page)
    await page.goto("/account/agents")
    await expect(page.locator("#account-pairing-box-offline")).toHaveText("Not connected. Trying again…")
    await expect(page.locator("#account-pairing").getByRole("radio", {name: "Dots", exact: true})).toBeDisabled()
  })

  // A connection that drops, as in a server restart, and comes back: the note shows
  // while it is down and goes once it is back, and Send works again.
  test("a dropped connection disables Send until it is back", async ({page, hasTouch}) => {
    const problems = watch(page)
    let down = false
    const open: WebSocketRoute[] = []
    await page.routeWebSocket(live, socket => {
      if (down) return socket.close({code: 1011, reason: "restarting"})
      socket.connectToServer()
      open.push(socket)
    })
    await page.goto("/rooms/general")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    const notice = page.locator("#room-message-offline")
    const send = page.locator("#room-message-form").getByRole("button", {name: "Send"})
    await expect(notice).toBeHidden()
    await expect(send).toBeEnabled()

    down = true
    for (const socket of open.splice(0)) await socket.close({code: 1012, reason: "restarting"})
    await expect(notice).toBeVisible()
    await expect(send).toBeDisabled()

    // Enter is Send, so it waits too.
    const words = `Typed while away ${Date.now()}`
    await page.locator("#room-message-body").fill(words)
    if (!hasTouch) await page.locator("#room-message-body").press("Enter")

    down = false
    await expect(notice).toBeHidden({timeout: 15_000})
    await expect(send).toBeEnabled()
    await expect(page.locator(".rooms-message", {hasText: words})).toHaveCount(0)
    await (hasTouch ? send.tap() : send.click())
    await expect(page.locator(".rooms-message", {hasText: words})).toBeVisible()
    await problems.expect()
  })
})
