import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// Message on someone's room message opens the walk's person's conversation with
// them (sign_in.exs has a friend write in General), and a message sent there shows
// in it at once, as the person's own.
test.use(signedIn)

test("Message on a room message opens the conversation, and a sent message shows in it", async ({page, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const said = page.locator(".rooms-message", {hasText: "Hello from the walk."}).first()
  await press(said.getByRole("button", {name: "Options for this message"}))
  await press(said.getByRole("button", {name: "Message", exact: true}))
  await expect(page).toHaveURL(/\/dms\/[0-9a-f-]{36}$/)
  await expect(page.locator("#dms-conversation")).toBeVisible()

  const words = `Sent from the ${info.project.name} walk.`
  await page.locator("#dms-message-body").fill(words)
  await press(page.locator("#dms-message-form").getByRole("button", {name: "Send"}))
  const mine = page.locator('#dms-messages .rooms-message[data-mine]', {hasText: words})
  await expect(mine).toBeVisible()
  await expect(mine.locator(".rooms-message__author")).toHaveText("You")
  await expect(page.locator("#dms-message-body")).toHaveValue("")
  await problems.expect()
})
