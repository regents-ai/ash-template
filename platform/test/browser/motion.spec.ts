import {expect, test} from "./support/test"
import {signedIn} from "./support/person"

// Motion that once went wrong. Each test names where it was found. An element is
// at rest when nothing is written in its style and nothing runs on it: the
// browser's own list of running animations covers the stylesheet's as well as
// the script's.
test.use(signedIn)

// Found by the motion pass of 19 Oct, in Patchbay: an item that slid or grew into
// a list kept `translate: none` written on it once it settled.
// The server takes a note away 3.2 seconds after sending it (AnimationsLive), so a
// check that looked at the note from outside could look after it had gone on a busy
// machine. The page itself records, every frame, each item and note that moved and
// then came to rest while still shown, and the check reads that record.
test("a new item in a list, and a new note, settle with nothing left on them", async ({page}) => {
  await page.addInitScript(() => {
    const moved = new Set<string>()
    const settled = {item: new Set<string>(), note: new Set<string>()}
    Object.assign(window, {settled})
    const frame = () => {
      for (const el of document.querySelectorAll<HTMLElement>("#lab-items [data-item-chip], #lab-toasts [data-toast]")) {
        const atRest = !el.getAttribute("style") && el.getAnimations().length === 0 && !el.hidden
        if (!atRest) moved.add(el.id)
        else if (moved.has(el.id)) settled[el.matches("[data-toast]") ? "note" : "item"].add(el.id)
      }
      requestAnimationFrame(frame)
    }
    requestAnimationFrame(frame)
  })
  const settled = (kind: "item" | "note") =>
    page.evaluate(kind => [...(window as unknown as {settled: Record<string, Set<string>>}).settled[kind]], kind)

  await page.goto("/animations")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const items = page.locator("#lab-items [data-item-chip]")
  const count = await items.count()
  await page.getByRole("button", {name: "Add one", exact: true}).click()
  await expect(items).toHaveCount(count + 1)
  const item = await items.first().getAttribute("id")
  await expect.poll(() => settled("item")).toContain(item)
  // The item stays, so it is still at rest now: nothing wrote on it again after it
  // settled. A note leaves by moving, so its record is the check.
  await expect(items.first()).not.toHaveAttribute("style", /./)
  expect(await items.first().evaluate(el => el.getAnimations().length)).toBe(0)

  await page.getByRole("button", {name: "Send a note", exact: true}).click()
  await expect.poll(async () => (await settled("note")).length).toBe(1)
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
