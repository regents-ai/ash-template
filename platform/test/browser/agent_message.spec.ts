import type {Locator} from "@playwright/test"
import {copiesShown, recordCopies} from "./support/copies"
import {signedIn, watch} from "./support/person"
import {expect, test} from "./support/test"

// The Agent Message button opens its dialog at both widths, on a plain page
// (/agents, topic agents) and inside the app's live shell (/app, topic app): each
// of its three texts fits the screen and copies exactly what it shows, and Escape
// closes it. The walk's person, signed in by sign_in.exs, leaves a message from its
// form and sees the receipt, after an empty message is refused when the field is left.
test.use({...signedIn, permissions: ["clipboard-read", "clipboard-write"]})

for (const {path, topic, dialogId} of [
  {path: "/agents", topic: "agents", dialogId: "agents-message"},
  {path: "/app", topic: "app", dialogId: "app-message"},
]) {
  test(`on ${path}, an agent's texts copy, and a signed-in person leaves a message`, async ({page, hasTouch}) => {
    const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
    const problems = watch(page)
    await recordCopies(page)
    await page.goto(path)

    const open = page.getByRole("button", {name: "Agent Message"})
    const dialog = page.getByRole("dialog", {name: "Agent Message"})
    await expect(dialog).toBeHidden()
    await press(open)
    await expect(dialog).toBeVisible()

    const texts = dialog.locator(".agent-message__text")
    await expect(texts).toHaveCount(3)
    for (const text of await texts.all()) {
      const code = text.locator("pre")
      expect(await code.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    }

    const cli = texts.first()
    const copy = cli.getByRole("button", {name: "Copy"})
    await press(copy)
    await expect.poll(() => copiesShown(copy)).toContainEqual(expect.objectContaining({answer: "copied"}))
    const copied = await page.evaluate(() => navigator.clipboard.readText())
    expect(copied).toBe(await cli.locator("code").textContent())
    expect(copied).toContain(`regents ash-template messages leave ${topic}`)

    await page.keyboard.press("Escape")
    await expect(dialog).toBeHidden()
    await press(open)
    await expect(dialog).toBeVisible()

    const form = dialog.locator(`#${dialogId}-person-form`)
    await expect(page.locator(`.phx-connected:has(#${dialogId}-person-form)`).first()).toBeAttached()
    const body = form.getByRole("textbox", {name: "Message", exact: true})
    await body.fill("x")
    await body.fill("")
    await form.getByRole("textbox", {name: "Reply to"}).focus()
    await expect(body).toHaveAttribute("aria-invalid", "true")

    await body.fill("The Watchdog page shows an old height.")
    await form.getByRole("textbox", {name: "Reply to"}).fill("walk@example.com")
    await press(form.getByRole("button", {name: "Send"}))
    const receipt = dialog.locator(`#${dialogId}-person-receipt`)
    await expect(receipt).toBeVisible()
    await expect(receipt.locator("code")).toHaveText(/^[0-9a-f-]{36}$/)
    await expect(body).toHaveValue("")
    await expect(dialog).toBeVisible()
    await problems.expect()
  })
}
