import {expect, test} from "./support/test"
import {bareAddresses} from "./support/addresses"
import {signedIn, watch} from "./support/person"

// Someone with no display or ENS name (sign_in.exs) shows in a room and on their
// poll by their wallet, which opens the full address and copies it, and neither
// page shows an address without its copy icon.
test.use(signedIn)

const wallet = "0x" + "7".repeat(40)

test("a person with no name shows by their wallet, with its copy icon", async ({page}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const message = page.locator("#room-messages > li").filter({hasText: "Hello from a wallet."})
  const author = message.locator(".rooms-message__author.rg-address")
  await expect(author.getByRole("button", {name: "0x7777..7777", exact: true})).toBeVisible()
  await expect(author.locator(".rg-address__full")).toHaveText(wallet)
  await expect(author.getByRole("button", {name: "Copy the full address"})).toBeVisible()
  expect(await bareAddresses(page)).toEqual([])

  // The polls list sits in the side menu, which a phone keeps closed.
  await page.goto("/polls")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const poll = page.locator("#polls-list a").filter({hasText: "Rain or shine?"})
  await page.goto((await poll.getAttribute("href"))!)
  await expect(page.locator("#page-title")).toHaveText("Rain or shine?")
  const starter = page.locator("#poll-starter.rg-address")
  await expect(starter.getByRole("button", {name: "0x7777..7777", exact: true})).toBeVisible()
  await expect(starter.locator(".rg-address__full")).toHaveText(wallet)
  await expect(starter.getByRole("button", {name: "Copy the full address"})).toBeVisible()
  expect(await bareAddresses(page)).toEqual([])
  await problems.expect()
})
