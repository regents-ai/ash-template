import {expect, test} from "./support/test"

// The glow lab (/animations/glow): a light behind the chosen status row, drawn on
// the GPU. These checks open it at both phone widths with the GPU on, choose each
// row, move a pointer over the rows and switch the theme, and ask that the page is
// still alive, still drawn and small. With less motion the picture never draws.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

// The page's script heap after the moves: far above what it needs, far below a leak.
const HEAP_CEILING = 64 * 1024 * 1024

for (const width of [320, 390]) {
  test.describe(`at ${width} wide`, () => {
    test.use({viewport: {width, height: 700}})

    test("the light follows each choice, survives a theme change and fits the screen", async ({page}) => {
      let crashed = false
      page.on("crash", () => { crashed = true })
      await page.goto("/animations/glow")
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      const rows = page.locator("#glow-rows")
      await expect(rows).toHaveAttribute("data-glow-ready", "true")

      for (const status of ["Waiting", "Done", "Running"]) {
        await page.locator("#glow-choice label", {hasText: status}).click()
        await expect(rows).toHaveAttribute("data-glow-lit", status.toLowerCase())
        const box = (await rows.boundingBox())!
        await page.mouse.move(box.x + 4, box.y + 4)
        await page.mouse.move(box.x + box.width - 4, box.y + box.height - 4, {steps: 12})
      }
      await page.evaluate(() => {
        const root = document.documentElement
        root.dataset.theme = root.dataset.theme === "light" ? "dark" : "light"
      })

      expect(crashed).toBe(false)
      await expect(rows).toHaveAttribute("data-glow-ready", "true")
      await expect(page.locator("#glow-row-running")).toHaveAttribute("aria-current", "true")
      const cdp = await page.context().newCDPSession(page)
      const {usedSize} = await cdp.send("Runtime.getHeapUsage")
      expect(usedSize).toBeLessThan(HEAP_CEILING)
      expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
    })
  })
}

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("the light never draws and the chosen row is still the one in full ink", async ({page}) => {
    await page.goto("/animations/glow")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await page.locator("#glow-choice label", {hasText: "Done"}).click()
    await expect(page.locator("#glow-row-done")).toHaveAttribute("aria-current", "true")
    await expect(page.locator("#glow-rows")).not.toHaveAttribute("data-glow-ready", "true")
    await expect(page.locator("#glow-rows-stage")).toHaveCSS("opacity", "0")
  })
})
