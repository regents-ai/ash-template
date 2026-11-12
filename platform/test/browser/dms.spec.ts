import {randomUUID} from "node:crypto"
import {expect, onThisMachine, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// Message on someone's room message opens the walk's person's conversation with
// them (sign_in.exs has a friend write in General), and a message sent there shows
// in it at once, as the person's own. The friend's reply shows on the person's open
// page at once, in the conversation and at the top of their list.
test.use(signedIn)

test("Message on a room message opens the conversation, and a sent message shows in it", async ({page, browser, baseURL, extraHTTPHeaders, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const said = page.locator(".rooms-message", {hasText: "Hello from the walk."}).first()
  await press(said.getByRole("button", {name: "Options for this message"}))
  await press(said.getByRole("button", {name: /^Message /}))
  await expect(page).toHaveURL(/\/dms\/[0-9a-f-]{36}$/)
  await expect(page.locator("#dms-conversation")).toBeVisible()

  const tag = randomUUID().slice(0, 8)
  const words = `Sent from the ${info.project.name} walk, ${tag}.`
  await page.locator("#dms-message-body").fill(words)
  await press(page.locator("#dms-message-form").getByRole("button", {name: "Send"}))
  const mine = page.locator('#dms-messages .rooms-message[data-mine]', {hasText: words})
  await expect(mine).toBeVisible()
  await expect(mine.locator(".rooms-message__author")).toHaveText("You")
  await expect(page.locator("#dms-message-body")).toHaveValue("")

  const friend = await browser.newContext({
    storageState: "test/browser/.auth/friend.json",
    baseURL,
    extraHTTPHeaders,
  })
  try {
    const outside = await onThisMachine(friend, baseURL!)
    const theirs = await friend.newPage()
    const friendProblems = watch(theirs)
    await theirs.goto(new URL(page.url()).pathname)
    await expect(theirs.locator("[data-phx-main].phx-connected")).toBeAttached()
    await expect(theirs.locator("#dms-messages .rooms-message", {hasText: words})).toBeVisible()

    const reply = `Reply on the ${info.project.name} walk, ${tag}.`
    await theirs.locator("#dms-message-body").fill(reply)
    await theirs.locator("#dms-message-form").getByRole("button", {name: "Send"}).click()
    await expect(theirs.locator('#dms-messages .rooms-message[data-mine]', {hasText: reply})).toBeVisible()

    await expect(page.locator("#dms-messages .rooms-message:not([data-mine])", {hasText: reply})).toBeVisible()
    await expect(page.locator("#dms-conversations > li").first()).toContainText(reply)
    await friendProblems.expect()
    expect(outside, "the friend's requests that left the machine").toEqual([])
  } finally {
    await friend.close()
  }
  await problems.expect()
})
