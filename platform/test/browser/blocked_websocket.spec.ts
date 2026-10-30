import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// Pages connect by websocket only. On a network that refuses websockets, signing in
// and out still work: Sign in starts the sign-in bridge, which then needs one request
// to /auth/privy/session and a reload; the page as served shows the account, and its
// menu holds Sign out. Choosing an agent to pair and Send in a room need the live
// connection.
const refuseWebsockets = (page: Page) =>
  page.routeWebSocket(/\/live\/websocket/, socket => socket.close({code: 1011, reason: "refused"}))

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
})
