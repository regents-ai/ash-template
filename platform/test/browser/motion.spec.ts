import {type Locator, type Page} from "@playwright/test"
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

// November bonus, step 2: a live figure rolls only the digits that changed, and
// nothing beside or below it moves while it does; with less motion asked for it
// simply changes. The lab's counter is a figure the server changes on a press.
async function watchFigure(page: Page) {
  await page.evaluate(() => {
    const label = document.querySelector("#lab-count .motion-lab__count-label")!
    const below = document.querySelector("#lab-count + .motion-lab__row")!
    const at = (el: Element) => [el.getBoundingClientRect().left, el.getBoundingClientRect().top]
    const start = [at(label), at(below)]
    const seen = {moved: 0, rolled: false}
    Object.assign(window, {seen})
    const frame = () => {
      ;[label, below].forEach((el, i) => {
        const [left, top] = at(el)
        seen.moved = Math.max(seen.moved, Math.abs(left - start[i][0]), Math.abs(top - start[i][1]))
      })
      if (document.querySelector("#lab-count [data-char]")) seen.rolled = true
      requestAnimationFrame(frame)
    }
    requestAnimationFrame(frame)
  })
  return () => page.evaluate(() => (window as unknown as {seen: {moved: number; rolled: boolean}}).seen)
}

test("a live figure rolls its changed digits and nothing beside or below it moves", async ({page}) => {
  await page.goto("/animations")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const figure = page.locator("#lab-count .rg-figure")
  await figure.scrollIntoViewIfNeeded()
  const seen = await watchFigure(page)

  // From four digits to five and back, so the figure's width is tested too.
  for (const label of ["+1,000", "+1,000", "+1,000", "+1,000", "+1,000", "+1,000", "+1,000", "+1,000", "+1,000", "−12"]) {
    const before = await figure.textContent()
    await page.getByRole("button", {name: label, exact: true}).click()
    await expect(figure).not.toHaveText(before!)
  }
  await expect.poll(async () => (await seen()).rolled).toBe(true)
  await expect(page.locator("#lab-count [data-char]")).toHaveCount(0)
  expect((await seen()).moved).toBe(0)
})

test("with less motion asked for, a live figure changes without rolling", async ({page}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.goto("/animations")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const figure = page.locator("#lab-count .rg-figure")
  await figure.scrollIntoViewIfNeeded()
  const seen = await watchFigure(page)

  const before = await figure.textContent()
  await page.getByRole("button", {name: "+37", exact: true}).click()
  await expect(figure).not.toHaveText(before!)
  expect(await seen()).toEqual({moved: 0, rolled: false})
})

// A finger drag from the middle of `from`, `dy` down and `dx` across over `ms`.
async function drag(page: Page, from: Locator, {dx = 0, dy = 0, ms}: {dx?: number; dy?: number; ms: number}) {
  const box = (await from.boundingBox())!
  const x = box.x + Math.min(box.width / 2, 60)
  const y = box.y + box.height / 2
  const steps = Math.max(8, Math.round(ms / 20))
  await page.mouse.move(x, y)
  await page.mouse.down()
  const start = Date.now()
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(x + (dx * i) / steps, y + (dy * i) / steps)
    const wait = start + (ms * i) / steps - Date.now()
    if (wait > 0) await page.waitForTimeout(wait)
  }
  await page.mouse.up()
}

const shiftY = (el: Locator) =>
  el.evaluate(node => new DOMMatrix(getComputedStyle(node).transform).m42)

async function openAgentTools(page: Page) {
  await page.goto("/polls")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.locator("#shell-footer").getByRole("button", {name: /Agents see/}).click()
  const sheet = page.locator("#shell-agent-tools")
  await expect(sheet).toHaveAttribute("data-settled")
  return sheet
}

// Gestures (November bonus, step 6): a window pulled down by its handle goes back
// from a short slow pull (40px at about 0.03 px/ms, under both the 0.11 px/ms throw
// and a quarter of its height) and closes on a quick 40px flick (about 0.3 px/ms).
// Escape closes it with no drag at all.
test("a window pulled by its handle goes back from a short pull and closes on a flick", async ({page}) => {
  let sheet = await openAgentTools(page)
  const handle = sheet.locator("[data-sheet-handle] h2")

  await drag(page, handle, {dy: 40, ms: 1200})
  await expect.poll(() => shiftY(sheet)).toBe(0)
  await expect(sheet).toHaveJSProperty("open", true)
  await expect(sheet).not.toHaveAttribute("style", /transform/)

  await drag(page, handle, {dy: 40, ms: 120})
  await expect(sheet).toHaveJSProperty("open", false)

  sheet = await openAgentTools(page)
  await page.keyboard.press("Escape")
  await expect(sheet).toHaveJSProperty("open", false)
})

test("with less motion asked for, a pulled window goes straight back, or closes", async ({page}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  const sheet = await openAgentTools(page)
  const handle = sheet.locator("[data-sheet-handle] h2")

  await drag(page, handle, {dy: 30, ms: 1200})
  await expect(sheet).not.toHaveAttribute("style", /transform/)
  await expect.poll(() => shiftY(sheet), {intervals: [50], timeout: 200}).toBe(0)

  const height = (await sheet.boundingBox())!.height
  await drag(page, handle, {dy: height * 0.4, ms: 1200})
  await expect(sheet).toHaveJSProperty("open", false)
})

// A note swiped sideways past 30px, or thrown, is dismissed as its own control does.
test("a note thrown sideways is dismissed", async ({page}) => {
  await page.goto("/animations")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.locator("#lab-toasts").scrollIntoViewIfNeeded()
  await page.getByRole("button", {name: "Send a note", exact: true}).click()
  const note = page.locator("#lab-toasts [data-toast]:not([hidden])").last()
  const id = await note.getAttribute("id")
  await expect(note).not.toHaveAttribute("style", /./)
  await drag(page, note.locator("span"), {dx: -25, ms: 120})
  await expect(page.locator(`#${id}:not([hidden])`)).toHaveCount(0)
})

// Records, each frame until it stops, the smallest scale `panel` is drawn at.
async function smallestScale(page: Page, panel: string) {
  await page.evaluate(panel => {
    const w = window as unknown as {smallest: number}
    w.smallest = 1
    let frames = 0
    const frame = () => {
      const el = document.querySelector(panel)
      if (el && getComputedStyle(el).display !== "none")
        w.smallest = Math.min(w.smallest, new DOMMatrix(getComputedStyle(el).transform).a)
      if (++frames < 40) requestAnimationFrame(frame)
    }
    requestAnimationFrame(frame)
  }, panel)
  return async () => {
    await page.waitForTimeout(700)
    return page.evaluate(() => (window as unknown as {smallest: number}).smallest)
  }
}

// The menu lab (November bonus, step 7): a menu opened by pointer grows from the
// corner of its button and rests where it opened; opened by keyboard it is simply
// there, Escape hands focus back to its button, and a press outside closes it.
test("a menu grows from its button by pointer, and is simply there by keyboard", async ({page}) => {
  await page.goto("/animations/menu")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const more = page.locator("#menu-lab-more")
  const panel = more.locator("[data-panel='menu']")

  const grew = await smallestScale(page, "#menu-lab-more [data-panel='menu']")
  await more.locator("summary").click()
  await expect(more).toHaveAttribute("data-settled")
  expect(await grew()).toBeLessThan(0.98)
  await expect(panel).not.toHaveAttribute("style", /./)
  const box = (await panel.boundingBox())!
  expect(box.x + box.width).toBeLessThanOrEqual(page.viewportSize()!.width)
  await page.locator("h1").click()
  await expect(more).not.toHaveAttribute("open")

  const sort = page.locator("#menu-lab-sort")
  await sort.locator("summary").focus()
  const still = await smallestScale(page, "#menu-lab-sort [data-panel='menu']")
  await page.keyboard.press("Enter")
  await expect(sort).toHaveAttribute("data-settled")
  expect(await still()).toBe(1)
  await page.keyboard.press("Tab")
  await page.keyboard.press("Escape")
  await expect(sort).not.toHaveAttribute("open")
  await expect(sort.locator("summary")).toBeFocused()
})

// The parts lab, built with the design-system 2e839171 parts: a period chosen by pointer slides the segmented indicator, morphs the
// line when the point count holds, and hands both back with nothing written on
// them; chosen by key, both are simply there. The chart's rule and readout follow
// the arrow keys and the latest figure comes back when focus goes.
test("a segmented choice travels by pointer and is simply there by keyboard; the chart reads out by key", async ({page}) => {
  await page.goto("/animations/parts")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const period = page.locator("#parts-period")
  const indicator = period.locator("[data-travel-indicator]")
  const line = page.locator("#parts-chart path[data-chart-line='0']")
  await page.evaluate(() => {
    const w = window as unknown as {kit: number; shapes: Set<string>}
    w.kit = 0
    w.shapes = new Set()
    new MutationObserver(records => {
      for (const r of records) {
        const el = r.target as Element
        if (r.attributeName === "data-travel" && el.getAttribute("data-travel") === "kit") w.kit++
        if (r.attributeName === "d" && el.matches("[data-chart-line='0']")) w.shapes.add(el.getAttribute("d")!)
      }
    }).observe(document.querySelector("#parts-chart")!, {subtree: true, attributes: true, attributeFilter: ["data-travel", "d"]})
  })
  const seen = () => page.evaluate(() => {
    const w = window as unknown as {kit: number; shapes: Set<string>}
    const out = {kit: w.kit, shapes: w.shapes.size}
    w.kit = 0
    w.shapes = new Set()
    return out
  })

  await period.locator("label", {hasText: "1D"}).click()
  await expect(period.locator("input[value='1d']")).toBeChecked()
  await expect(indicator).not.toHaveAttribute("style", /./)
  await expect(period).toHaveAttribute("data-travel", "")
  await expect(line).not.toHaveAttribute("style", /./)
  const byPointer = await seen()
  expect(byPointer.kit).toBeGreaterThan(0)
  expect(byPointer.shapes).toBeGreaterThan(2)

  await period.locator("input[value='1d']").focus()
  await page.keyboard.press("ArrowRight")
  await expect(period.locator("input[value='1w']")).toBeChecked()
  await page.waitForTimeout(400)
  const byKey = await seen()
  expect(byKey.kit).toBe(0)
  expect(byKey.shapes).toBeLessThanOrEqual(1)

  const chart = page.locator("#parts-chart")
  const figure = chart.locator("[data-chart-readout='figure']")
  const latest = (await figure.textContent())!.trim()
  await chart.locator("[data-chart-plot]").focus()
  await page.keyboard.press("Home")
  await expect(chart).toHaveAttribute("data-chart-at", "0")
  await expect(figure).toHaveText((await chart.locator("tr[data-chart-point] td").first().textContent())!.trim())
  await page.keyboard.press("Tab")
  await expect(chart).not.toHaveAttribute("data-chart-at")
  await expect(figure).toHaveText(latest)
})
