import {expect, test} from "./support/test"

// The ink lab (/animations/ink): one GPU picture in two views, each its own link.
// These checks open it at both phone widths with the GPU on, move between the views
// by their tabs, move a pointer over the picture and switch the theme, and ask that
// the page is still alive, drawn and small; that the view stays in the link over a
// reload; and that with less motion the picture never draws.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

// The page's script heap after the moves: far above what it needs, far below a leak.
const HEAP_CEILING = 64 * 1024 * 1024

for (const width of [320, 390]) {
  test.describe(`at ${width} wide`, () => {
    test.use({viewport: {width, height: 700}})

    test("both views draw, survive a theme change and fit the screen", async ({page}) => {
      let crashed = false
      page.on("crash", () => { crashed = true })
      await page.goto("/animations/ink")
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      const picture = page.locator("#ink-picture")
      await expect(picture).toHaveAttribute("data-ink-ready", "true")

      for (const view of ["Hero", "Lines", "Hero"]) {
        await page.getByRole("link", {name: view, exact: true}).click()
        await expect(picture).toHaveAttribute("data-ink-view", view.toLowerCase())
        const box = (await picture.boundingBox())!
        await page.mouse.move(box.x + 4, box.y + 4)
        await page.mouse.move(box.x + box.width - 4, box.y + box.height - 4, {steps: 12})
      }
      await page.evaluate(() => {
        const root = document.documentElement
        root.dataset.theme = root.dataset.theme === "light" ? "dark" : "light"
      })

      expect(crashed).toBe(false)
      await expect(picture).toHaveAttribute("data-ink-ready", "true")
      const cdp = await page.context().newCDPSession(page)
      const {usedSize} = await cdp.send("Runtime.getHeapUsage")
      expect(usedSize).toBeLessThan(HEAP_CEILING)
      expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
    })
  })
}

test("the view chosen stays in the link over a reload", async ({page}) => {
  await page.goto("/animations/ink")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.getByRole("link", {name: "Hero", exact: true}).click()
  await expect(page).toHaveURL(/\/animations\/ink\?view=hero$/)
  await page.reload()
  await expect(page.locator("#ink-picture")).toHaveAttribute("data-ink-view", "hero")
  await expect(page.getByRole("link", {name: "Hero", exact: true})).toHaveAttribute("aria-current", "page")
})

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("the picture never draws in either view", async ({page}) => {
    await page.goto("/animations/ink?view=hero")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await page.getByRole("link", {name: "Lines", exact: true}).click()
    await expect(page.locator("#ink-picture")).toHaveAttribute("data-ink-view", "lines")
    await expect(page.locator("#ink-picture")).not.toHaveAttribute("data-ink-ready", "true")
    await expect(page.locator("#ink-picture canvas")).toHaveCSS("opacity", "0")
  })
})
