import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The value card lab (/animations/value). Its first version crashed the browser as
// the page loaded at phone width: a rule that hid part of a card by the card's own
// width kept the layout from settling (CHANGELOG, 12 Nov). These checks open it at
// both phone widths with the GPU picture on, move a pointer over every card, and
// ask that the page is still alive, drew its picture, and stayed small.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

// The page's script heap after the moves, far above what it needs (a few MB) and
// far below the gigabyte the crash reached.
const HEAP_CEILING = 64 * 1024 * 1024

async function sweep(page: Page) {
  for (const card of await page.locator("[data-value-card]").all()) {
    const box = (await card.boundingBox())!
    await card.scrollIntoViewIfNeeded()
    const at = (await card.boundingBox())!
    await page.mouse.move(at.x + 4, at.y + 4)
    await page.mouse.move(at.x + box.width - 4, at.y + box.height - 4, {steps: 12})
  }
}

for (const width of [320, 390]) {
  test.describe(`at ${width} wide`, () => {
    test.use({viewport: {width, height: 700}})

    test("the cards draw their light, stay alive after the pointer moves, and fit the screen", async ({page}) => {
      let crashed = false
      page.on("crash", () => { crashed = true })
      await page.goto("/animations/value")
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      const grid = page.locator("#value-cards")
      await expect(grid).toHaveAttribute("data-value-ready", "true")

      await sweep(page)
      await sweep(page)

      expect(crashed).toBe(false)
      await expect(grid).toHaveAttribute("data-value-ready", "true")
      const cdp = await page.context().newCDPSession(page)
      const {usedSize} = await cdp.send("Runtime.getHeapUsage")
      expect(usedSize).toBeLessThan(HEAP_CEILING)
      expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
      // Every figure is real text whatever the picture does.
      await expect(page.locator("#value-balance .rg-figure")).toHaveText("3,482.50")
    })
  })
}

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("the picture never draws and each card keeps its own surface", async ({page}) => {
    await page.goto("/animations/value")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await sweep(page)
    await expect(page.locator("#value-cards")).not.toHaveAttribute("data-value-ready", "true")
    const card = page.locator("#value-points")
    expect(await card.evaluate(el => getComputedStyle(el).backgroundColor)).not.toBe("rgba(0, 0, 0, 0)")
  })
})
