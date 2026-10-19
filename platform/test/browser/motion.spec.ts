import {expect, test} from "./support/test"
import {signedIn} from "./support/person"

// Motion that once went wrong. Each test names where it was found. An element is
// at rest when nothing is written in its style and nothing runs on it: the
// browser's own list of running animations covers the stylesheet's as well as
// the script's.
test.use(signedIn)

const atRest = (el: Element) => ({style: el.getAttribute("style") ?? "", running: el.getAnimations().length})

// Found by the motion pass of 19 Oct, in Patchbay: an item that slid or grew into
// a list kept `translate: none` written on it once it settled.
test("a new item in a list, and a new note, settle with nothing left on them", async ({page}) => {
  await page.goto("/animations")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const items = page.locator("#lab-items [data-item-chip]")
  const count = await items.count()
  await page.getByRole("button", {name: "Add one", exact: true}).click()
  await expect(items).toHaveCount(count + 1)
  await expect.poll(() => items.first().evaluate(atRest)).toEqual({style: "", running: 0})

  await page.getByRole("button", {name: "Send a note", exact: true}).click()
  const note = page.locator("#lab-toasts [data-toast]").first()
  await expect.poll(() => note.evaluate(atRest)).toEqual({style: "", running: 0})
})

// Found by the motion pass of 19 Oct, in Patchbay: a refusal shook an alert inside
// content that was still settling in. On a page the server draws once, only an
// alert set straight in the page's `main` shakes.
test("a refusal shakes the page's own alert, never one inside content settling in", async ({page}) => {
  await page.route("/terms", async route => {
    const response = await route.fetch()
    const alerts =
      '<p role="alert" id="own-alert">Not saved.</p>' +
      '<ul data-cascade><li><p role="alert" id="settling-alert">Not saved.</p></li></ul>'
    await route.fulfill({response, body: (await response.text()).replace(/(<main[^>]*>)/, `$1${alerts}`)})
  })
  await page.addInitScript(() => {
    const moved = new Set<string>()
    Object.assign(window, {moved})
    new MutationObserver(records => records.forEach(({target}) => moved.add((target as Element).id)))
      .observe(document, {attributes: true, attributeFilter: ["style"], subtree: true})
  })

  await page.goto("/terms")
  const moved = () => page.evaluate(() => [...(window as unknown as {moved: Set<string>}).moved])
  await expect.poll(moved).toContain("own-alert")
  expect(await moved()).not.toContain("settling-alert")
})
