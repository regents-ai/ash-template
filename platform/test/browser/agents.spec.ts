import type {Locator} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// The walk's person has one agent, paired by sign_in.exs. Its window, opened from
// the Account page, says who it is and shows its short address, which opens the
// full address on a press, gives the press back to the address when Escape closes
// it, and copies the full address from its icon. On the touch phone each of the
// address's two targets is at least 44 pixels tall.
test.use({...signedIn, permissions: ["clipboard-read", "clipboard-write"]})

const wallet = `0x${"c".repeat(40)}`

test("an agent's window opens its full address and copies it", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/account")
  await ready(page)
  await press(page.getByRole("button", {name: "See what Walk Agent has done"}))

  const agentWindow = page.getByRole("dialog", {name: "Walk Agent"})
  await expect(agentWindow).toBeVisible()
  const address = agentWindow.getByRole("button", {name: "0xcccc..cccc", exact: true})
  const copy = agentWindow.getByRole("button", {name: "Copy the full address"})
  const full = agentWindow.getByText(wallet, {exact: true})

  if (hasTouch)
    for (const target of [address, copy])
      expect((await target.boundingBox())?.height).toBeGreaterThanOrEqual(44)

  await expect(full).toBeHidden()
  await press(address)
  await expect(full).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(full).toBeHidden()
  await expect(address).toBeFocused()
  await expect(agentWindow).toBeVisible()

  await press(copy)
  await expect(copy).toHaveAttribute("data-copy-state", "copied")
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(wallet)
  await problems.expect()
})
