import {expect, test} from "./support/test"

// The icons lab (/animations/icons): fifty-six small diagrams on one GPU picture, each
// above its word. These checks open it at both phone widths with the GPU on, and ask
// that every drawing is drawn and moving, that every word fits its cell, that
// pointing at a cell moves nothing on the page, and that a theme change leaves it
// drawn. With less motion every drawing holds still.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

// The page's script heap after the moves: far above what it needs, far below a leak.
const HEAP_CEILING = 64 * 1024 * 1024

for (const width of [320, 390]) {
  test.describe(`at ${width} wide`, () => {
    test.use({viewport: {width, height: 700}})

    test("every drawing moves, every word fits, and pointing at one moves nothing", async ({page}) => {
      let crashed = false
      page.on("crash", () => { crashed = true })
      await page.goto("/animations/icons")
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      const sheet = page.locator("#icons-sheet")
      await expect(sheet).toHaveAttribute("data-icons-ready", "true")
      await expect(page.locator("#icons-sheet li[data-icon]")).toHaveCount(56)
      await expect(page.locator("#icons-sheet ul")).toHaveCount(7)
      await expect(page.locator("#icons-sheet-stage")).toHaveCSS("opacity", "1")

      // The first section, a moment apart, is a different picture.
      const first = page.locator("#icons-connect")
      const before = await first.screenshot()
      await page.waitForTimeout(400)
      expect((await first.screenshot()).equals(before)).toBe(false)

      // No word runs past its cell.
      const clipped = await page.locator(".icon-cell__word, .icon-cell__number").evaluateAll(words =>
        words.filter(word => word.scrollWidth > word.clientWidth || word.getBoundingClientRect().right > word.parentElement!.getBoundingClientRect().right + 0.5).map(word => word.textContent),
      )
      expect(clipped).toEqual([])

      // Each cell's box on the page, wherever the page is scrolled to.
      const boxes = () => page.locator("#icons-sheet li[data-icon]").evaluateAll(cells => cells.map(cell => {
        const {left, top, width, height} = cell.getBoundingClientRect()
        return [left + scrollX, top + scrollY, width, height].join(" ")
      }))
      const resting = await boxes()
      await page.locator('[data-icon="relay"]').hover()
      expect(await boxes()).toEqual(resting)
      await page.locator('[data-icon="crown"]').focus()
      expect(await boxes()).toEqual(resting)

      await page.evaluate(() => {
        const root = document.documentElement
        root.dataset.theme = root.dataset.theme === "light" ? "dark" : "light"
      })

      expect(crashed).toBe(false)
      await expect(sheet).toHaveAttribute("data-icons-ready", "true")
      const cdp = await page.context().newCDPSession(page)
      const {usedSize} = await cdp.send("Runtime.getHeapUsage")
      expect(usedSize).toBeLessThan(HEAP_CEILING)
      expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
    })
  })
}

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("every drawing holds one still frame", async ({page}) => {
    await page.goto("/animations/icons")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await expect(page.locator("#icons-sheet")).toHaveAttribute("data-icons-ready", "true")
    await expect(page.locator("#icons-sheet-stage")).toHaveCSS("opacity", "1")
    const first = page.locator("#icons-connect")
    const before = await first.screenshot()
    await page.waitForTimeout(400)
    expect((await first.screenshot()).equals(before)).toBe(true)
  })
})
