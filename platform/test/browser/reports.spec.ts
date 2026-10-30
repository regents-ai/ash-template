import {randomUUID} from "node:crypto"
import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// Report on someone's room message opens the reasons in the menu's place; choosing
// one closes both and thanks the walk's person. Their own messages offer no Report.
// The message reported is in a room only sign_in.exs's friend writes in: a menu is
// hidden once its message leaves the room's scrolling area, and in General the rest
// of the walk's messages can push a message out while its menu is open.
test.use(signedIn)

test("Report on someone's room message asks why, then thanks the reader", async ({page, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/rooms/walk-reports")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const said = page.locator(".rooms-message", {hasText: "Report this one."})
  await press(said.getByRole("button", {name: "Options for this message"}))
  await press(said.getByRole("button", {name: "Report", exact: true}))
  const reasons = said.getByRole("group", {name: "Report reason"})
  await expect(reasons).toBeVisible()
  await expect(said.getByRole("button", {name: "Mute", exact: false})).toBeHidden()

  await press(reasons.getByRole("button", {name: "Spam"}))
  await expect(reasons).toBeHidden()
  await expect(said.getByRole("group", {name: "Message options"})).toBeHidden()
  await expect(page.getByText("Thanks. The site’s team will read your report.")).toBeVisible()

  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const words = `Not reported on the ${info.project.name} walk, ${randomUUID().slice(0, 8)}.`
  await page.locator("#room-message-body").fill(words)
  await press(page.locator("#room-message-form").getByRole("button", {name: "Send"}))
  const mine = page.locator(".rooms-message", {hasText: words})
  await expect(mine).toBeVisible()
  await press(mine.getByRole("button", {name: "Options for this message"}))
  await expect(mine.getByRole("button", {name: "Delete"})).toBeVisible()
  await expect(mine.getByRole("button", {name: "Report", exact: true})).toHaveCount(0)
  await page.keyboard.press("Escape")
  await problems.expect()
})
