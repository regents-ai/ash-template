import {type Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The splats lab (/animations/splats): a floating island in pixel art, drawn with the
// GPU over a still picture of itself. These checks open it with the GPU on and ask
// that the box keeps its size from the first paint, that the island draws and turns by
// itself, and that the page fits the screen. With less motion it holds one still
// frame, a drag turns it and it stops where let go, and the arrow keys turn it.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

const size = (page: Page) =>
  page.locator("#splats-island").evaluate((box: HTMLElement) => {
    const {width, height} = box.getBoundingClientRect()
    return [width, height]
  })

test("the island draws in its box and turns by itself", async ({page}) => {
  await page.goto("/animations/splats", {waitUntil: "domcontentloaded"})
  const first = await size(page)
  const island = page.locator("#splats-island")
  await expect(island).toHaveAttribute("data-splats-ready", "true")
  await expect(page.locator("#splats-island-stage")).toHaveCSS("opacity", "1")
  expect(await size(page)).toEqual(first)

  const before = await island.screenshot()
  await page.waitForTimeout(400)
  expect((await island.screenshot()).equals(before)).toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
})

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("the island holds still, turns under a drag and stops, and turns with the arrow keys", async ({page}) => {
    await page.goto("/animations/splats")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    const island = page.locator("#splats-island")
    await expect(island).toHaveAttribute("data-splats-ready", "true")
    await expect(page.locator("#splats-island-stage")).toHaveCSS("opacity", "1")

    const resting = await island.screenshot()
    await page.waitForTimeout(400)
    expect((await island.screenshot()).equals(resting)).toBe(true)

    const box = (await island.boundingBox())!
    const y = box.y + box.height / 2
    await page.mouse.move(box.x + box.width / 2 - 60, y)
    await page.mouse.down()
    for (let step = 1; step <= 8; step++) await page.mouse.move(box.x + box.width / 2 - 60 + step * 15, y)
    await page.mouse.up()
    await page.waitForTimeout(100)
    const dragged = await island.screenshot()
    expect(dragged.equals(resting)).toBe(false)
    await page.waitForTimeout(400)
    expect((await island.screenshot()).equals(dragged)).toBe(true)

    await island.focus()
    await page.keyboard.press("ArrowRight")
    await page.waitForTimeout(100)
    expect((await island.screenshot()).equals(dragged)).toBe(false)
  })
})
