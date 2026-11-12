import {randomUUID} from "node:crypto"
import {expect, onThisMachine, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// The walk's person likes a room message from its menu: a pressed heart with its
// count shows under it, and pressing the heart takes the like back. A like from the
// walk's friend shows its count on the person's open page, with the heart left as
// the person last pressed it, and the friend is listed as here while their page is open.
test.use(signedIn)

test("A friend's like shows its count on the person's open page, and the friend is here while their page is open", async ({page, browser, baseURL, extraHTTPHeaders, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  const room = `/rooms/walk-likes-${info.project.name}`
  await page.goto(room)
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const words = `Liked by the friend on the ${info.project.name} walk, ${randomUUID().slice(0, 8)}.`
  await page.locator("#room-message-body").fill(words)
  await press(page.locator("#room-message-form").getByRole("button", {name: "Send"}))
  const said = page.locator(".rooms-message", {hasText: words})
  await expect(said).toBeVisible()
  const people = page.locator("#room-people")
  await expect(people).not.toContainText("Walk Friend")

  const friend = await browser.newContext({storageState: "test/browser/.auth/friend.json", baseURL, extraHTTPHeaders})
  try {
    const outside = await onThisMachine(friend, baseURL!)
    const theirs = await friend.newPage()
    const friendProblems = watch(theirs)
    await theirs.goto(room)
    await expect(theirs.locator("[data-phx-main].phx-connected")).toBeAttached()
    await expect(people).toContainText("Walk Friend")

    const liked = theirs.locator(".rooms-message", {hasText: words})
    await liked.getByRole("button", {name: "Options for this message"}).click()
    await liked.getByRole("button", {name: "Like", exact: true}).click()
    await expect(liked.locator(".rg-discussion__heart")).toHaveAttribute("aria-pressed", "true")

    const heart = said.locator(".rg-discussion__heart")
    await expect(heart).toContainText("1")
    await expect(heart).toHaveAttribute("aria-pressed", "false")

    // The person likes it too: their heart turns, and the friend's page counts both.
    await press(heart)
    await expect(heart).toHaveAttribute("aria-pressed", "true")
    await expect(heart).toContainText("2")
    await expect(liked.locator(".rg-discussion__heart")).toContainText("2")
    await expect(liked.locator(".rg-discussion__heart")).toHaveAttribute("aria-pressed", "true")

    await friendProblems.expect()
    await theirs.close()
    expect(outside, "requests that left the machine").toEqual([])
  } finally {
    await friend.close()
  }
  await expect(people).not.toContainText("Walk Friend")
  await problems.expect()
})

test("Like on a room message shows a pressed heart, and pressing it takes the like back", async ({page, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const words = `Liked on the ${info.project.name} walk, ${randomUUID().slice(0, 8)}.`
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
