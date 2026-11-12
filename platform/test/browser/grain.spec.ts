import {expect, test} from "./support/test"

// The grain lab (/animations/grain): a banner of harbour water drawn on the GPU
// every frame while it is on screen. These checks open it at both phone widths
// with the GPU on, let the water run, move a pointer over it and switch the theme,
// and ask that the page is still alive, drawn and small. With less motion the
// water never draws.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

// The page's script heap after the water has run: far above what it needs, far below a leak.
const HEAP_CEILING = 64 * 1024 * 1024

for (const width of [320, 390]) {
  test.describe(`at ${width} wide`, () => {
    test.use({viewport: {width, height: 700}})

    test("the water runs, survives a theme change and fits the screen", async ({page}) => {
      let crashed = false
      page.on("crash", () => { crashed = true })
      await page.goto("/animations/grain")
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      const banner = page.locator("#grain-banner")
      await expect(banner).toHaveAttribute("data-grain-ready", "true")

      const box = (await banner.boundingBox())!
      for (let i = 0; i < 3; i++) {
        await page.mouse.move(box.x + 4, box.y + 4)
        await page.mouse.move(box.x + box.width - 4, box.y + box.height - 4, {steps: 12})
      }
      await page.evaluate(() => {
        const root = document.documentElement
        root.dataset.theme = root.dataset.theme === "light" ? "dark" : "light"
      })
      // A few seconds of water after the change.
      await page.waitForTimeout(2000)

      expect(crashed).toBe(false)
      await expect(banner).toHaveAttribute("data-grain-ready", "true")
      const cdp = await page.context().newCDPSession(page)
      const {usedSize} = await cdp.send("Runtime.getHeapUsage")
      expect(usedSize).toBeLessThan(HEAP_CEILING)
      expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
    })
  })
}

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("the water never draws and the heading stands on the plain ground", async ({page}) => {
    await page.goto("/animations/grain")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await expect(page.getByRole("heading", {name: "Harbour"})).toBeVisible()
    await expect(page.locator("#grain-banner")).not.toHaveAttribute("data-grain-ready", "true")
    await expect(page.locator("#grain-banner-stage")).toHaveCSS("opacity", "0")
  })
})
