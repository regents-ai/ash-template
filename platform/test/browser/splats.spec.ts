import {type Locator, type Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The splats lab (/animations/splats): two small worlds in pixel art, the robot factory
// first and the island second, each drawn with the GPU over a still picture of itself.
// These checks open it with the GPU on and ask that the factory comes first and draws
// and turns by itself; that the switch changes the scene without changing the box's
// size, on a wide screen and on a phone, and leaves one scene drawing; that a link
// opens the island and any other link the factory; and, with less motion, that it
// holds still, that a drag across turns it and a drag up or down tilts it, each
// stopping where let go, and that the arrow keys turn and tilt it.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

const size = (box: Locator) =>
  box.evaluate((element: HTMLElement) => {
    const {width, height} = element.getBoundingClientRect()
    return [width, height]
  })

const drawn = async (page: Page, scene: "factory" | "island") => {
  const box = page.locator(`#splats-${scene}`)
  await expect(box).toHaveAttribute("data-splats-ready", "true")
  await expect(page.locator(`#splats-${scene}-stage`)).toHaveCSS("opacity", "1")
  return box
}

test("the factory comes first, draws in its box and turns by itself", async ({page}) => {
  await page.goto("/animations/splats", {waitUntil: "domcontentloaded"})
  const first = await size(page.locator("#splats-factory"))
  const box = await drawn(page, "factory")
  expect(await size(box)).toEqual(first)
  await expect(page.getByRole("link", {name: "Factory"})).toHaveAttribute("aria-current", "page")

  const before = await box.screenshot()
  await page.waitForTimeout(400)
  expect((await box.screenshot()).equals(before)).toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
})

test("the switch changes the scene, keeps the box's size and leaves one scene drawing", async ({page}) => {
  await page.goto("/animations/splats")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const factory = await size(await drawn(page, "factory"))

  await page.getByRole("link", {name: "Island"}).click()
  await expect(page).toHaveURL(/\?scene=island$/)
  const island = await drawn(page, "island")
  expect(await size(island)).toEqual(factory)
  await expect(page.locator("[data-splats-canvas]")).toHaveCount(1)
  await expect(page.getByRole("link", {name: "Island"})).toHaveAttribute("aria-current", "page")

  await page.getByRole("link", {name: "Factory"}).click()
  await expect(page).toHaveURL(/\/animations\/splats$/)
  expect(await size(await drawn(page, "factory"))).toEqual(factory)
  await expect(page.locator("[data-splats-canvas]")).toHaveCount(1)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
})

test("a link opens the island, and any other link opens the factory", async ({page}) => {
  await page.goto("/animations/splats?scene=island")
  await expect(page.locator("#splats-island")).toBeAttached()
  for (const link of ["?scene=volcano", "?scene[]=island", "?scene[island]=1", "?scene="]) {
    await page.goto(`/animations/splats${link}`)
    await expect(page.locator("#splats-factory")).toBeAttached()
    await expect(page.locator("#splats-island")).toHaveCount(0)
  }
})

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  for (const scene of ["factory", "island"] as const) {
    test(`the ${scene} holds still, turns and tilts under a drag and stops, and turns and tilts with the arrow keys`, async ({page}) => {
      await page.goto(`/animations/splats?scene=${scene}`)
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      const box = await drawn(page, scene)

      const resting = await box.screenshot()
      await page.waitForTimeout(400)
      expect((await box.screenshot()).equals(resting)).toBe(true)

      // Drags across, then down, from the middle of the box; each leaves the picture changed and still.
      const area = (await box.boundingBox())!
      const middle = {x: area.x + area.width / 2, y: area.y + area.height / 2}
      let last = resting
      for (const [dx, dy] of [[15, 0], [0, 12]]) {
        await page.mouse.move(middle.x, middle.y)
        await page.mouse.down()
        for (let step = 1; step <= 8; step++) await page.mouse.move(middle.x + step * dx, middle.y + step * dy)
        await page.mouse.up()
        await page.waitForTimeout(100)
        const moved = await box.screenshot()
        expect(moved.equals(last)).toBe(false)
        await page.waitForTimeout(400)
        expect((await box.screenshot()).equals(moved)).toBe(true)
        last = moved
      }

      await box.focus()
      for (const key of ["ArrowRight", "ArrowUp"]) {
        await page.keyboard.press(key)
        await page.waitForTimeout(100)
        const pressed = await box.screenshot()
        expect(pressed.equals(last)).toBe(false)
        last = pressed
      }
    })
  }

  test("on a touch screen a sideways swipe turns the scene, and an up or down swipe scrolls the page", async ({page, isMobile}) => {
    test.skip(!isMobile, "Touch is the phone's.")
    await page.goto("/animations/splats")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    const box = await drawn(page, "factory")
    const area = (await box.boundingBox())!
    const touch = await page.context().newCDPSession(page)
    // A swipe that stops before the finger lifts, so the page does not fling on.
    const swipe = async (dx: number, dy: number) => {
      const x = area.x + area.width / 2
      const y = area.y + area.height / 2
      const at = (step: number) => ({type: "touchMove" as const, touchPoints: [{x: x + step * dx, y: y + step * dy}]})
      await touch.send("Input.dispatchTouchEvent", {type: "touchStart", touchPoints: [{x, y}]})
      for (let step = 1; step <= 8; step++) await touch.send("Input.dispatchTouchEvent", at(step))
      await page.waitForTimeout(300)
      await touch.send("Input.dispatchTouchEvent", at(8))
      await touch.send("Input.dispatchTouchEvent", {type: "touchEnd", touchPoints: []})
      await page.waitForTimeout(200)
    }

    // Back at the top after the page has scrolled, the scene is as it was: not tilted.
    const resting = await box.screenshot()
    await swipe(0, -15)
    expect(await page.evaluate(() => window.scrollY)).toBeGreaterThan(0)
    await page.evaluate(() => window.scrollTo(0, 0))
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0)
    expect((await box.screenshot()).equals(resting)).toBe(true)

    await swipe(15, 0)
    expect((await box.screenshot()).equals(resting)).toBe(false)
  })
})
