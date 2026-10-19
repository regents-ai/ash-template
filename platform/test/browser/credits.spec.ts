import type {Locator} from "@playwright/test"
import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// The Credits panel's "Where to spend" opens a window naming each Regents Product
// and what Credits buy there, and the panel's "Paying from" wallet carries its copy icon.
test.use(signedIn)

const nothingYet = "Nothing to spend on yet."
const sites = [
  ["Patchbay", "Bid for Agent Offer slots.", "https://patchbay.help"],
  ["Autolaunch", nothingYet, "https://autolaunch.sh"],
  ["Keyfleet", nothingYet, "https://keyfleet.ai"],
  ["Techtree", nothingYet, "https://techtree.sh"],
  ["$REGENT Staking", nothingYet, "https://regents.sh/stake"],
]

test("Where to spend lists each site and what Credits buy there", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/showcase/credits")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const panel = page.locator("#credits-panel")
  await expect(panel.locator(".credits-panel__wallet").getByRole("button", {name: "Copy the full address"})).toBeVisible()

  const open = panel.getByRole("button", {name: "Where to spend"})
  const window = page.getByRole("dialog", {name: "Where to spend Credits"})
  await press(open)
  await expect(window).toBeVisible()
  const rows = window.getByRole("listitem")
  await expect(rows).toHaveCount(sites.length)
  for (const [index, [name, words, url]] of sites.entries()) {
    await expect(rows.nth(index)).toContainText(name)
    await expect(rows.nth(index)).toContainText(words)
    await expect(rows.nth(index).getByRole("link")).toHaveAttribute("href", url)
  }

  // The whole window sits on the screen.
  const box = (await window.boundingBox())!
  const screen = page.viewportSize()!
  expect(box.x).toBeGreaterThanOrEqual(0)
  expect(box.y).toBeGreaterThanOrEqual(0)
  expect(box.x + box.width).toBeLessThanOrEqual(screen.width)
  expect(box.y + box.height).toBeLessThanOrEqual(screen.height)

  await press(window.getByRole("button", {name: "Close"}))
  await expect(window).toBeHidden()
  await press(open)
  await expect(window).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(window).toBeHidden()
  await problems.expect()
})
