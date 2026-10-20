import type {Locator, Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {watch} from "./support/person"

// The agent harbour (/animations/harbour) and its islands' pages, in each theme,
// at 1280 wide and on the touch phone at 390. Everything is found by its role and
// name, as a person using a screen reader finds it.
//
// Where the sea is not drawn, the server's still picture for the theme stays.
// Pressing on the drawn sea: harbour_sea.spec.ts.

const crew = ["Ada", "Basil", "Clio", "Dot", "Ezra", "Fern"]
const islands = [
  {id: "inn", name: "Inn"},
  {id: "forge", name: "Forge"},
  {id: "castle", name: "Castle"},
]

const picture = (page: Page) => page.getByRole("img", {name: "The agent harbour"})
const islandList = (page: Page) => page.getByRole("list", {name: "Islands"})
const crewList = (page: Page) => page.getByRole("list", {name: "Where each agent is"})

// A name pressed before the page is live loads the whole page again, and its card
// opens only once that page is live. The walk presses once the page is live, as
// addresses.spec.ts does.
const live = (page: Page) => expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

// A name under the harbour is a target at least 44 pixels square on the phone. The
// phone's boxes come back a few millionths of a pixel short, so they are rounded.
async function fitsAThumb(targets: Locator) {
  for (const target of await targets.all()) {
    const box = (await target.boundingBox())!
    expect(Math.round(box.width), await target.innerText()).toBeGreaterThanOrEqual(44)
    expect(Math.round(box.height), await target.innerText()).toBeGreaterThanOrEqual(44)
  }
}

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({colorScheme})

    test("the list under the harbour names every agent, and each name opens its card", async ({
      page,
      hasTouch,
    }) => {
      const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
      const problems = watch(page)
      await page.goto("/animations/harbour")
      await live(page)

      const agents = crewList(page).getByRole("link")
      await expect(agents).toHaveText(crew)
      if (hasTouch) await fitsAThumb(agents)

      // Basil's card closes with its X; Fern's with Escape.
      await press(agents.filter({hasText: "Basil"}))
      const basil = page.getByRole("dialog", {name: "Basil"})
      await expect(basil).toBeVisible()
      await expect(page).toHaveURL(/\/animations\/harbour\?agent=basil$/)
      await expect(basil.getByText("Key #204")).toBeVisible()
      const actions = basil.getByRole("list", {name: "Recent actions"}).getByRole("listitem")
      expect(await actions.count()).toBeGreaterThanOrEqual(1)
      expect(await actions.count()).toBeLessThanOrEqual(4)
      const close = basil.getByRole("button", {name: "Close"})
      await expect(close).toBeVisible()
      if (hasTouch) await fitsAThumb(close)
      await press(close)
      await expect(basil).toBeHidden()
      await expect(page).toHaveURL(/\/animations\/harbour$/)

      await press(agents.filter({hasText: "Fern"}))
      const fern = page.getByRole("dialog", {name: "Fern"})
      await expect(fern).toBeVisible()
      await page.keyboard.press("Escape")
      await expect(fern).toBeHidden()
      await expect(page).toHaveURL(/\/animations\/harbour$/)
      await problems.expect()
    })

    test("each island's page marks its own island under the harbour", async ({page, hasTouch}) => {
      const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
      const problems = watch(page)
      for (const island of islands) {
        await page.goto(`/animations/harbour/${island.id}`)
        await live(page)
        await expect(page.getByRole("heading", {level: 1})).toHaveText(island.name)
        for (const other of islands) {
          const link = islandList(page).getByRole("link", {name: other.name, exact: true})
          if (other === island) await expect(link).toHaveAttribute("aria-current", "page")
          else await expect(link).not.toHaveAttribute("aria-current")
        }
      }
      if (hasTouch) await fitsAThumb(islandList(page).getByRole("link"))

      // From the castle, pressing the inn's name opens the inn's page.
      await press(islandList(page).getByRole("link", {name: "Inn", exact: true}))
      await expect(page).toHaveURL(/\/animations\/harbour\/inn$/)
      await expect(page.getByRole("heading", {level: 1})).toHaveText("Inn")
      await expect(islandList(page).getByRole("link", {name: "Inn", exact: true})).toHaveAttribute(
        "aria-current",
        "page",
      )
      await problems.expect()
    })

    test("an island that does not exist is not found", async ({request}) => {
      expect((await request.get("/animations/harbour/lighthouse")).status()).toBe(404)
    })

    // Each agent keeps its own row and stands in its island's column, so the list
    // is as tall with every agent at one island as with them spread out. The page
    // places them with each row's grid area; here every agent is put at the inn the
    // way the page writes it when they all gather there.
    test("the list under the harbour keeps its height when the agents gather", async ({page}) => {
      await page.goto("/animations/harbour")
      const list = crewList(page)
      const footer = page.getByRole("contentinfo")
      const before = {list: (await list.boundingBox())!.height, footer: (await footer.boundingBox())!.y}

      await list
        .getByRole("listitem")
        .evaluateAll(rows => rows.forEach((row, index) => ((row as HTMLElement).style.gridArea = `${index + 1} / 1`)))
      expect((await list.boundingBox())!.height).toBe(before.list)
      expect((await footer.boundingBox())!.y).toBe(before.footer)
    })

    // The page's own clock moves an agent every 7 seconds; over 30 seconds at 1280
    // the page shifts by less than 0.1. Two moves can put the crew back where it
    // started, so a sail is caught as it happens, not by comparing the two ends.
    test("the inn's page barely shifts while the agents sail", async ({page}, testInfo) => {
      test.skip(testInfo.project.name !== "desktop", "measured at 1280 wide")
      test.setTimeout(60_000)
      await page.addInitScript(() => {
        const page = window as unknown as {shift: number}
        page.shift = 0
        new PerformanceObserver(list => {
          for (const entry of list.getEntries() as unknown as {value: number; hadRecentInput: boolean}[])
            if (!entry.hadRecentInput) page.shift += entry.value
        }).observe({type: "layout-shift", buffered: true})
      })
      await page.goto("/animations/harbour/inn")
      const where = () => crewList(page).getByRole("listitem").allTextContents()
      const first = await where()
      const start = Date.now()
      await expect.poll(where, {message: "no agent sailed in 30 seconds", timeout: 30_000}).not.toEqual(first)
      await page.waitForTimeout(Math.max(0, 30_000 - (Date.now() - start)))
      const shift = await page.evaluate(() => (window as unknown as {shift: number}).shift)
      expect(shift).toBeLessThan(0.1)
    })

    // Without WebGPU nothing is drawn and the still picture for the theme stays,
    // filling the harbour.
    test("without WebGPU the harbour shows the still picture for the theme", async ({page}) => {
      await page.addInitScript(() => Object.defineProperty(Navigator.prototype, "gpu", {get: () => undefined}))
      await page.goto("/animations/harbour")
      const harbour = picture(page)
      await expect(harbour).toBeVisible()
      await expect(harbour).toHaveAttribute("data-harbour-ready", "false")
      const still = await harbour.evaluate(root => {
        const box = {width: root.clientWidth, height: root.clientHeight}
        return [...root.children]
          .filter((child): child is HTMLImageElement => child instanceof HTMLImageElement)
          .filter(image => getComputedStyle(image).display !== "none")
          .map(image => {
            const shown = image.getBoundingClientRect()
            return {
              file: new URL(image.currentSrc).pathname.split("/").pop(),
              drawn: image.complete && image.naturalWidth > 0,
              fills: Math.round(shown.width) === box.width && Math.round(shown.height) === box.height,
            }
          })
      })
      expect(still).toEqual([{file: `harbour-${colorScheme}.webp`, drawn: true, fills: true}])
    })
  })
}
