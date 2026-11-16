import {readFile} from "node:fs/promises"
import {type Download, type Locator, type Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The splats lab (/animations/splats): two small worlds in pixel art, the robot factory
// first and the island second, each drawn with the GPU over a still picture of itself.
// These checks open it with the GPU on and ask that the factory comes first and draws
// and turns by itself; that the switch changes the scene without changing the box's
// size, on a wide screen and on a phone, and leaves one scene drawing; that a link
// opens the island and any other link the factory; and, with less motion, that it
// holds still, that a drag across turns it and a drag up or down tilts it, each
// stopping where let go, and that the arrow keys turn and tilt it.
// Download GIF: it shows at the end of the tabs' row once the scene has drawn, counts
// up in place while it works, takes no second press, and saves the scene's GIF; a
// failure says so beside it; choosing the other scene stops it; without WebGPU it is
// not offered; and with less motion it still saves one, pressed from the keyboard.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

type Scene = "factory" | "island"

/** Longer than either scene's GIF takes to make here (about two seconds), with room for a busy machine. */
const WHOLE_GIF = 15_000

const size = (box: Locator) =>
  box.evaluate((element: HTMLElement) => {
    const {width, height} = element.getBoundingClientRect()
    return [width, height]
  })

const drawn = async (page: Page, scene: Scene) => {
  const box = page.locator(`#splats-${scene}`)
  await expect(box).toHaveAttribute("data-splats-ready", "true")
  await expect(page.locator(`#splats-${scene}-stage`)).toHaveCSS("opacity", "1")
  return box
}

// The scene alone, one pixel inside the box's edge. On a phone the box's outermost rows
// of screen pixels blend its border with the picture, and on a busy machine the browser
// can still be repainting them just after the picture has drawn, the scene unmoved.
const picture = async (page: Page, scene: Scene) => {
  const canvas = page.locator(`#splats-${scene} [data-splats-canvas]`)
  await canvas.scrollIntoViewIfNeeded()
  const {x, y, width, height} = (await canvas.boundingBox())!
  return page.screenshot({clip: {x: x + 1, y: y + 1, width: width - 2, height: height - 2}})
}

/** Where the picture, the tabs and Download GIF are on the page. */
const places = (page: Page, scene: Scene) =>
  page.evaluate(
    scene =>
      [`#splats-${scene}`, ".splats-lab__bar .flair-tabs", `#splats-${scene}-gif-button`].map(selector => {
        const {x, y, width, height} = document.querySelector(selector)!.getBoundingClientRect()
        return [x, y, width, height]
      }),
    scene,
  )

/** Opens a scene and waits for it to draw; returns its Download GIF and every file the page saves from then on. */
const openForGif = async (page: Page, scene: Scene) => {
  await page.goto(scene === "factory" ? "/animations/splats" : `/animations/splats?scene=${scene}`)
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await drawn(page, scene)
  const saved: Download[] = []
  page.on("download", download => saved.push(download))
  return {button: page.locator(`#splats-${scene}-gif-button`), saved}
}

const opening = async (download: Download) => (await readFile((await download.path())!)).subarray(0, 6).toString()

test("Download GIF shows at the end of the tabs' row, counts up in place, takes no second press and saves the factory's GIF", async ({page, isMobile}) => {
  test.setTimeout(30_000 + WHOLE_GIF)
  const {button, saved} = await openForGif(page, "factory")
  await expect(button).toBeVisible()
  await expect(button).toHaveAccessibleName("Download GIF")
  const lastTab = (await page.locator(".flair-tabs a").last().boundingBox())!
  const own = (await button.boundingBox())!
  expect(own.x).toBeGreaterThanOrEqual(lastTab.x + lastTab.width)
  if (isMobile) expect(own.height).toBeGreaterThanOrEqual(44)
  const idle = await places(page, "factory")
  // Counts the GPU devices asked for from here on: each GIF asks for its own.
  await page.evaluate(() => {
    const ask = GPUAdapter.prototype.requestDevice
    const counted = window as unknown as {devicesAsked: number}
    counted.devicesAsked = 0
    GPUAdapter.prototype.requestDevice = function (this: GPUAdapter, ...options: Parameters<GPUAdapter["requestDevice"]>) {
      counted.devicesAsked += 1
      return ask.apply(this, options)
    }
  })

  const download = page.waitForEvent("download", {timeout: WHOLE_GIF})
  await button.click()
  await expect(button).toHaveAttribute("aria-busy", "true")
  await expect(button).toHaveAttribute("aria-disabled", "true")
  await expect(button).toHaveAccessibleName(/^Making [1-9]\d?%$/)
  expect(await places(page, "factory")).toEqual(idle)
  await button.click({force: true})

  const gif = await download
  expect(gif.suggestedFilename()).toBe("regents-factory.gif")
  expect(await opening(gif)).toBe("GIF89a")
  await expect(button).toHaveAttribute("aria-busy", "false")
  await expect(button).toHaveAccessibleName("Download GIF")
  expect(await places(page, "factory")).toEqual(idle)
  expect(saved).toHaveLength(1)
  expect(await page.evaluate(() => (window as unknown as {devicesAsked: number}).devicesAsked)).toBe(1)
})

test("a GIF that cannot be made says so beside the button, which is ready to try again", async ({page}) => {
  const {button, saved} = await openForGif(page, "factory")
  const failed = page.locator("#splats-factory-gif .splats-gif__failed")
  await expect(failed).toBeHidden()
  const idle = await places(page, "factory")
  // The scene on the page keeps its device; the GIF's own is refused.
  await page.evaluate(() => {
    GPUAdapter.prototype.requestDevice = () => Promise.reject(new Error("No device for the GIF."))
  })

  await button.click()
  await expect(failed).toBeVisible()
  await expect(failed).toHaveText("Could not make the GIF. Try again.")
  await expect(button).toHaveAttribute("aria-busy", "false")
  await expect(button).toHaveAccessibleName("Download GIF")
  expect(await places(page, "factory")).toEqual(idle)
  expect(saved).toEqual([])
})

test("choosing the other scene while a GIF is being made goes there at once and stops the GIF", async ({page}) => {
  test.setTimeout(30_000 + WHOLE_GIF)
  const {button, saved} = await openForGif(page, "factory")
  await button.click()
  await expect(button).toHaveAccessibleName(/^Making [1-9]\d?%$/)

  await page.getByRole("link", {name: "Island"}).click()
  await expect(page).toHaveURL(/\?scene=island$/, {timeout: 2_000})
  await drawn(page, "island")
  const island = page.locator("#splats-island-gif-button")
  await expect(island).toHaveAccessibleName("Download GIF")
  await expect(island).not.toHaveAttribute("aria-busy", "true")
  await page.waitForTimeout(WHOLE_GIF)
  expect(saved).toEqual([])
})

test("without WebGPU, Download GIF is not offered", async ({page}) => {
  await page.addInitScript(() => Object.defineProperty(Navigator.prototype, "gpu", {get: () => undefined}))
  await page.goto("/animations/splats")
  await expect(page.locator("#splats-factory")).toHaveAttribute("data-splats-ready", "false")
  const button = page.locator("#splats-factory-gif-button")
  await expect(button).toBeHidden()
  await expect(page.getByRole("button", {name: "Download GIF"})).toHaveCount(0)
  expect(await button.evaluate((element: HTMLElement) => (element.focus(), document.activeElement === element))).toBe(false)
})

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

      const resting = await picture(page, scene)
      await page.waitForTimeout(400)
      expect((await picture(page, scene)).equals(resting)).toBe(true)

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
        const moved = await picture(page, scene)
        expect(moved.equals(last)).toBe(false)
        await page.waitForTimeout(400)
        expect((await picture(page, scene)).equals(moved)).toBe(true)
        last = moved
      }

      await box.focus()
      for (const key of ["ArrowRight", "ArrowUp"]) {
        await page.keyboard.press(key)
        await page.waitForTimeout(100)
        const pressed = await picture(page, scene)
        expect(pressed.equals(last)).toBe(false)
        last = pressed
      }
    })
  }

  test("Download GIF still saves the island's GIF, pressed from the keyboard", async ({page}) => {
    test.setTimeout(30_000 + WHOLE_GIF)
    const {button, saved} = await openForGif(page, "island")
    const download = page.waitForEvent("download", {timeout: WHOLE_GIF})
    await button.focus()
    await page.keyboard.press("Enter")
    const gif = await download
    expect(gif.suggestedFilename()).toBe("regents-island.gif")
    expect(await opening(gif)).toBe("GIF89a")
    await expect(button).toBeFocused()
    expect(saved).toHaveLength(1)
  })

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
    const resting = await picture(page, "factory")
    await swipe(0, -15)
    expect(await page.evaluate(() => window.scrollY)).toBeGreaterThan(0)
    await page.evaluate(() => window.scrollTo(0, 0))
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0)
    expect((await picture(page, "factory")).equals(resting)).toBe(true)

    await swipe(15, 0)
    expect((await picture(page, "factory")).equals(resting)).toBe(false)
  })
})
