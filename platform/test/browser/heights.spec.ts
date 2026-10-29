import type {Locator} from "@playwright/test"
import {expect, test} from "./support/test"

// Founder rule, 2026-10-07: a choice never changes a box's height. Each box below
// is measured after every choice it offers, and must keep the height it opened at.
const height = (box: Locator) => box.evaluate(element => element.getBoundingClientRect().height)

test("the library views keep one height whichever tab is picked", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  await page.goto("/animations")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const box = page.locator("#lab-tabs")
  const first = await height(box)

  for (const name of ["Saved", "Shared", "Recent"]) {
    const tab = box.getByRole("tab", {name, exact: true})
    await press(tab)
    await expect(tab).toHaveAttribute("aria-selected", "true")
    expect(await height(box), `after ${name}`).toBe(first)
  }
})

test("the slow-read card keeps one height whatever each read answers", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  await page.goto("/showcase")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const box = page.locator("#slow-read-demo")
  const status = page.locator("#slow-read-result .rg-status")
  await box.scrollIntoViewIfNeeded()
  const first = await height(box)
  const same = async (after: string) => expect(await height(box), `after ${after}`).toBe(first)

  for (const wallet of ["Quick wallet", "New wallet", "Slow wallet"]) {
    await press(box.getByRole("button", {name: wallet, exact: true}))
    await same(`${wallet}, reading`)
    await expect(status).toHaveText(/Read at /, {timeout: 10_000})
    await same(`${wallet}, read`)
  }

  await press(page.locator("#slow-read-fail"))
  await press(page.locator("#slow-read-refresh"))
  await expect(status).toHaveText("Old reading", {timeout: 10_000})
  await same("a failed refresh")

  await press(box.getByRole("button", {name: "New wallet", exact: true}))
  await expect(status).toHaveText("Read failed", {timeout: 10_000})
  await same("a failed read")

  await press(page.locator("#slow-read-disconnect"))
  await expect(status).toHaveText("Choose a wallet")
  await same("Disconnect")
})
