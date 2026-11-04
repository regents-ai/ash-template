import {copiesShown, recordCopies} from "./support/copies"
import {expect, test} from "./support/test"

test.use({permissions: ["clipboard-read", "clipboard-write"]})

// A page too long to carry in the HTML (regents.sh's papers, 1.19 MB) is fetched when
// the button is pressed, and the browser must still allow the write.
test("a copy button with a url fetches its page only when pressed, and copies it whole", async ({page}) => {
  const asked: string[] = []
  page.on("request", request => {
    if (new URL(request.url()).pathname === "/llms.txt") asked.push(request.url())
  })
  await recordCopies(page)
  await page.goto("/showcase/grammar")

  const copy = page.locator("#grammar-noun-copy-page")
  await page.locator(".phx-connected").first().waitFor()
  expect(asked).toEqual([])

  await copy.click()
  await expect.poll(() => copiesShown(copy)).toEqual([{answer: "copied", shown: "Copied", said: "Copied"}])
  expect(asked).toHaveLength(1)
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(await (await page.request.get("/llms.txt")).text())
})

test("a copy button whose url does not answer says it could not copy", async ({page}) => {
  await page.route("**/llms.txt", route => route.fulfill({status: 500, body: "no"}))
  await recordCopies(page)
  await page.goto("/showcase/grammar")

  const copy = page.locator("#grammar-noun-copy-page")
  await copy.click()
  await expect
    .poll(() => copiesShown(copy))
    .toEqual([{answer: "failed", shown: "Couldn't copy", said: "Couldn't copy"}])
})
