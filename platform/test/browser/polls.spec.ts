import {expect, onThisMachine, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// The walk's person starts a poll, votes in it once, and ends it; the counts
// show only once it has ended. A signed-out visitor watching the same poll sees
// the vote counted as it happens, and the counts only once it has ended.
test.use(signedIn)

test("A person starts a poll, votes once, and sees the counts when they end it", async ({page, browser, baseURL, extraHTTPHeaders, hasTouch}, info) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/polls")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const question = `Which way, ${info.project.name}?`
  await page.locator("#poll-start-question").fill(question)
  await page.locator("#poll-start-choices").fill("North\nSouth")
  await page.locator("#poll-start-minutes").selectOption("5")
  await press(page.locator("#poll-start-form").getByRole("button", {name: "Start poll"}))
  await expect(page).toHaveURL(/\/polls\/[0-9a-f-]{36}$/)
  await expect(page.locator("#page-title")).toHaveText(question)
  await expect(page.locator("#poll-counts")).toHaveCount(0)

  const visitor = await browser.newContext({baseURL, extraHTTPHeaders})
  try {
    const outside = await onThisMachine(visitor, baseURL!)
    const watching = await visitor.newPage()
    const visitorProblems = watch(watching)
    await watching.goto(new URL(page.url()).pathname)
    await expect(watching.locator("[data-phx-main].phx-connected")).toBeAttached()
    await expect(watching.locator("#poll-meta")).toContainText("0 votes")

    await press(page.locator("#poll-vote-form").getByText("North"))
    await press(page.locator("#poll-vote-form").getByRole("button", {name: "Vote"}))
    await expect(page.locator("#poll-my-vote")).toHaveText("You voted for “North”.")
    await expect(page.locator("#poll-vote-form")).toHaveCount(0)
    await expect(page.locator("#poll-counts")).toHaveCount(0)

    await expect(watching.locator("#poll-meta")).toContainText("1 vote")
    await expect(watching.locator("#poll-counts")).toHaveCount(0)

    await press(page.locator("#poll-end"))
    await press(page.locator("#rg-confirm").getByRole("button", {name: "End"}))
    for (const reader of [page, watching]) {
      const counts = reader.locator("#poll-counts .polls-count")
      await expect(counts).toHaveCount(2)
      await expect(counts.first()).toContainText("North")
      await expect(counts.first()).toContainText("1 vote")
      await expect(counts.nth(1)).toContainText("0 votes")
    }
    await expect(page.locator("#poll-end")).toHaveCount(0)
    await visitorProblems.expect()
    expect(outside, "the visitor's requests that left the machine").toEqual([])
  } finally {
    await visitor.close()
  }
  await problems.expect()
})
