import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// The walk's person likes a room message from its menu: a pressed heart with its
// count shows under it, and pressing the heart takes the like back.
test.use(signedIn)

test("Like on a room message shows a pressed heart, and pressing it takes the like back", async ({page, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const words = `Liked on the ${info.project.name} walk.`
  await page.locator("#room-message-body").fill(words)
  await press(page.locator("#room-message-form").getByRole("button", {name: "Send"}))
  const said = page.locator(".rooms-message", {hasText: words})
  await expect(said).toBeVisible()
  await expect(said.locator(".rg-discussion__heart")).toHaveCount(0)

  await press(said.getByRole("button", {name: "Options for this message"}))
  await press(said.getByRole("button", {name: "Like", exact: true}))
  const heart = said.locator(".rg-discussion__heart")
  await expect(heart).toHaveAttribute("aria-pressed", "true")
  await expect(heart).toContainText("1")

  await press(said.getByRole("button", {name: "Options for this message"}))
  await expect(said.getByRole("button", {name: "Remove like"})).toBeVisible()
  await page.keyboard.press("Escape")

  await press(heart)
  await expect(said.locator(".rg-discussion__heart")).toHaveCount(0)
  await problems.expect()
})
