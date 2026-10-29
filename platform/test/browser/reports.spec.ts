import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// Report on someone's room message (sign_in.exs has a friend write in General)
// opens the reasons in the menu's place; choosing one closes both and thanks the
// walk's person. Their own messages offer no Report.
test.use(signedIn)

test("Report on someone's room message asks why, then thanks the reader", async ({page, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const said = page.locator(".rooms-message", {hasText: "Hello from the walk."}).first()
  await press(said.getByRole("button", {name: "Options for this message"}))
  await press(said.getByRole("button", {name: "Report", exact: true}))
  const reasons = said.getByRole("group", {name: "Reason"})
  await expect(reasons).toBeVisible()
  await expect(said.getByRole("button", {name: "Mute", exact: false})).toBeHidden()

  await press(reasons.getByRole("button", {name: "Spam"}))
  await expect(reasons).toBeHidden()
  await expect(said.getByRole("group", {name: "Message options"})).toBeHidden()
  await expect(page.getByText("Thanks. The site’s team will read your report.")).toBeVisible()

  const words = `Not reported on the ${info.project.name} walk.`
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
