import {expect, test} from "@playwright/test"
import {keepSignedIn, signedIn} from "./support/person"

// Layout rules that once broke. Each test names the page it was found on.
test.use(signedIn)
test.beforeEach(({context}) => keepSignedIn(context))

// Found by the review of 18 Oct: the Account page's two columns also split
// Credits history, whose one panel then filled half the page.
test("a page with one panel gives it the whole width", async ({page}) => {
  await page.goto("/account/credits")
  const panel = await page.locator("#credits-history").boundingBox()
  const grid = await page.locator("#credits-history-page .account-grid").boundingBox()
  expect(panel!.width).toBeCloseTo(grid!.width, 0)
})
