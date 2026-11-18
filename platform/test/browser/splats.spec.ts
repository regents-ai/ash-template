import {readFile} from "node:fs/promises"
import {type Download, type Locator, type Page} from "@playwright/test"
import {decodeScene} from "../../assets/js/splats/scene"
import {expect, test} from "./support/test"

// The splats lab (/animations/splats): two small worlds in pixel art, the robot factory
// first and the island second, each drawn with the GPU over a still picture of itself.
// These checks open it with the GPU on and ask that the factory comes first and draws
// and turns by itself; that each scene shows nothing but its own palette's colours;
// that the switch changes the scene without changing the box's size, on a wide screen
// and on a phone, and leaves one scene drawing; that a link opens the island and any
// other link the factory; that without WebGPU the still picture stays; and, with less
// motion, that it holds still, that a drag across turns it and a drag up or down tilts
// it, each stopping where let go, and that the arrow keys turn and tilt it.
// Zoom: the turn stops while a zoom comes in and eases back after, the loop playing on
// and the zoom staying; with less motion, Zoom in and Zoom out step at once up to the
// nearest and back, each saying when it has nothing left to do, and a drag from a button
// moves nothing; a wheel with Ctrl held zooms at the pointer, the point under it near a
// corner staying under it, and a plain wheel is the page's; Reset view, 0 and a
// double-click each bring back the opening picture; on a phone two fingers pinch at
// their midpoint and a double tap goes back. The camera is read from what the page
// hands the graphics card each frame (watchViews).
// Download GIF: it shows at the end of the tabs' row once the scene has drawn, counts
// up in place while it works, takes no second press, and saves the scene's GIF; a
// failure says so beside it; choosing the other scene stops it; without WebGPU it is
// not offered; and with less motion it still saves one, pressed from the keyboard.
// A picture compared after a drag, a key, a zoom or a swipe is taken once two in a row
// agree (steady), so a frame that lands late on a busy machine is waited for.
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

// The scene alone, one pixel inside the box's edge, without the zoom buttons over it. On
// a phone the box's outermost rows of screen pixels blend its border with the picture,
// and on a busy machine the browser can still be repainting them just after the picture
// has drawn, the scene unmoved. Each part of the buttons is hidden, not just their row:
// hiding the row alone left their icons in the picture, drawn one way or another after a
// press, so a picture changed with no change in the scene.
const picture = async (page: Page, scene: Scene) => {
  const canvas = page.locator(`#splats-${scene} [data-splats-canvas]`)
  await canvas.scrollIntoViewIfNeeded()
  const {x, y, width, height} = (await canvas.boundingBox())!
  return page.screenshot({clip: {x: x + 1, y: y + 1, width: width - 2, height: height - 2}, style: ".splat-zoom, .splat-zoom * { visibility: hidden !important; }"})
}

/**
 * The scene's picture once two in a row agree. The page hands a frame to the graphics card
 * a moment before the screen shows it, and on a busy machine a picture taken as soon as
 * the camera has moved can still be the frame before.
 */
const steady = async (page: Page, scene: Scene) => {
  let last = await picture(page, scene)
  await expect
    .poll(async () => {
      const next = await picture(page, scene)
      const same = next.equals(last)
      last = next
      return same
    })
    .toBe(true)
  return last
}

/**
 * The canvas's height in device pixels; the whole CSS pixel on the page about that share
 * of its width and height from its top left (a mouse event's place is in whole pixels);
 * and the canvas pixel under a place on the page.
 */
const stage = async (page: Page, scene: Scene) => {
  const canvas = page.locator(`#splats-${scene} [data-splats-canvas]`)
  await canvas.scrollIntoViewIfNeeded()
  const area = (await canvas.boundingBox())!
  const [width, height] = (await canvas.evaluate((element: HTMLCanvasElement) => [element.width, element.height])) as [number, number]
  return {
    height,
    at: (across: number, down: number) => ({x: Math.round(area.x + across * area.width), y: Math.round(area.y + down * area.height)}),
    pixel: ({x, y}: {x: number; y: number}) => [((x - area.x) / area.width) * width, ((y - area.y) / area.height) * height] as const,
  }
}

/** What the page's camera was in a frame it drew, read from the View the painter hands the graphics card (painter.ts), and when. */
type Seen = {at: number; right: number[]; up: number[]; back: number[]; eye: number[]; distance: number; focal: number; columns: number; rows: number; loop: number}

/**
 * Notes each frame's View as the page writes it to the graphics card. Every frame's
 * uniforms go in one write, each at a 256-byte step; the View is the one whose right
 * axis is level and whose axes are unit length.
 */
const watchViews = (page: Page) =>
  page.addInitScript(() => {
    if (typeof GPUQueue === "undefined") return
    const seen: Seen[] = []
    Object.assign(window, {seenViews: seen})
    const write = GPUQueue.prototype.writeBuffer
    GPUQueue.prototype.writeBuffer = function (this: GPUQueue, ...args: Parameters<GPUQueue["writeBuffer"]>) {
      const [buffer, , data, from = 0, size] = args
      if (buffer.label === "vgpu.frame.uniforms" && data instanceof ArrayBuffer) {
        const end = from + (size ?? data.byteLength - from)
        for (let at = from; at + 96 <= end; at += 256) {
          const f = new Float32Array(data, at, 24)
          const unit = (k: number) => Math.abs(Math.hypot(f[k]!, f[k + 1]!, f[k + 2]!) - 1) < 1e-3
          if (f[1] !== 0 || !unit(0) || !unit(4) || !unit(8) || !(f[16]! >= 1) || !Number.isInteger(f[16]) || !Number.isInteger(f[17])) continue
          const axis = (k: number) => [f[k]!, f[k + 1]!, f[k + 2]!]
          seen.push({at: performance.now(), right: axis(0), up: axis(4), back: axis(8), eye: axis(12), distance: f[15]!, focal: f[3]!, columns: f[16]!, rows: f[17]!, loop: f[20]!})
          break
        }
      }
      return write.apply(this, args)
    }
  })

const views = (page: Page) => page.evaluate(() => (window as unknown as {seenViews: Seen[]}).seenViews)
const yawOf = ({right}: Seen) => Math.atan2(-right[2]!, right[0]!)
/** How far the scene turned from one view to the next, its near side to the right. */
const turned = (from: Seen, to: Seen) => {
  const change = yawOf(from) - yawOf(to)
  return Math.atan2(Math.sin(change), Math.cos(change))
}
const dot = (a: number[], b: number[]) => a[0]! * b[0]! + a[1]! * b[1]! + a[2]! * b[2]!
/** Screen pixels to a side of an art pixel, on a canvas this many device pixels high. */
const artPixel = (view: Seen, height: number) => Math.ceil(height / view.rows)
/** The point of the plane through the target, square to the view, under a canvas pixel (FORMAT.md 5.2 undone). */
const underPixel = (view: Seen, [x, y]: readonly [number, number], height: number) => {
  const q = artPixel(view, height)
  const across = ((x / q - view.columns / 2) * view.distance) / view.focal
  const up = ((view.rows / 2 - y / q) * view.distance) / view.focal
  return view.eye.map((v, k) => v - view.distance * view.back[k]! + across * view.right[k]! + up * view.up[k]!)
}
/** Where a point lands on the canvas, in device pixels from its top left (FORMAT.md 5.1 and 5.2). */
const onCanvas = (view: Seen, point: number[], height: number) => {
  const q = artPixel(view, height)
  const offset = point.map((v, k) => v - view.eye[k]!)
  const depth = -dot(view.back, offset)
  return [(view.columns / 2 + (view.focal * dot(view.right, offset)) / depth) * q, (view.rows / 2 - (view.focal * dot(view.up, offset)) / depth) * q]
}
/** One full turn every thirty seconds (renderer.ts). */
const CRUISE = (Math.PI * 2) / 30

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

/** A saved GIF's signature and its size in pixels. */
const opening = async (download: Download) => {
  const bytes = await readFile((await download.path())!)
  return {signature: bytes.subarray(0, 6).toString(), width: bytes.readUInt16LE(6), height: bytes.readUInt16LE(8)}
}
/** Every GIF: 432 by 288 art pixels, each two pixels square. */
const GIF = {signature: "GIF89a", width: 864, height: 576}

/** The scene's colours, as its baked file lists them. */
const paletteOf = async (scene: Scene) => {
  const file = await readFile(`priv/static/splats/${scene}.bin`)
  return Array.from(decodeScene(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength)).blocks.palette)
}

/** How many colours a screenshot holds that are not in `palette` (0xRRGGBB). */
const strangers = (page: Page, png: Buffer, palette: number[]) =>
  page.evaluate(
    async ([base64, palette]) => {
      const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0))
      const bitmap = await createImageBitmap(new Blob([bytes], {type: "image/png"}))
      const context = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d")!
      context.drawImage(bitmap, 0, 0)
      const {data} = context.getImageData(0, 0, bitmap.width, bitmap.height)
      const known = new Set(palette)
      const found = new Set<number>()
      for (let p = 0; p < data.length; p += 4) {
        const value = (data[p]! << 16) | (data[p + 1]! << 8) | data[p + 2]!
        if (!known.has(value)) found.add(value)
      }
      return found.size
    },
    [png.toString("base64"), palette] as const,
  )

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
  expect(await opening(gif)).toEqual(GIF)
  await expect(button).toHaveAttribute("aria-busy", "false")
  await expect(button).toHaveAccessibleName("Download GIF")
  expect(await places(page, "factory")).toEqual(idle)
  expect(saved).toHaveLength(1)
  expect(await page.evaluate(() => (window as unknown as {devicesAsked: number}).devicesAsked)).toBe(1)
})

test("a GIF that cannot be made says so beside the button, which is ready to try again", async ({page}) => {
  const {button, saved} = await openForGif(page, "factory")
  const failed = page.locator("#splats-factory-gif .splat-gif__failed")
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

test("without WebGPU, the still picture stays and Download GIF is not offered", async ({page, isMobile}) => {
  await page.addInitScript(() => Object.defineProperty(Navigator.prototype, "gpu", {get: () => undefined}))
  await page.goto("/animations/splats")
  await expect(page.locator("#splats-factory")).toHaveAttribute("data-splats-ready", "false")
  const still = page.locator("#splats-factory .splat-stage__still")
  await expect(still).toBeVisible()
  // The wide picture on a wide screen, the square one on a phone, each one art pixel a pixel.
  await expect.poll(() => still.evaluate((image: HTMLImageElement) => [image.complete, image.naturalWidth])).toEqual([true, isMobile ? 360 : 480])
  await expect(page.locator("#splats-factory-stage")).toHaveCSS("opacity", "0")
  const button = page.locator("#splats-factory-gif-button")
  await expect(button).toBeHidden()
  await expect(page.getByRole("button", {name: "Download GIF"})).toHaveCount(0)
  expect(await button.evaluate((element: HTMLElement) => (element.focus(), document.activeElement === element))).toBe(false)
  // Nor are the zoom buttons.
  await expect(page.locator("#splats-factory button[data-splats-zoom]")).toHaveCount(3)
  for (const zoom of await page.locator("#splats-factory button[data-splats-zoom]").all()) await expect(zoom).toBeHidden()
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

for (const scene of ["factory", "island"] as const) {
  test(`the ${scene} shows nothing but its own palette's colours`, async ({page}) => {
    await page.goto(scene === "factory" ? "/animations/splats" : `/animations/splats?scene=${scene}`)
    await drawn(page, scene)
    expect(await strangers(page, await picture(page, scene), await paletteOf(scene))).toBe(0)
  })
}

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

test("the turn stops while zoom comes in and eases back a moment after, the loop playing on and the zoom staying where it is left", async ({page}) => {
  test.setTimeout(30_000)
  await watchViews(page)
  await page.goto("/animations/splats")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await drawn(page, "factory")
  const {at} = await stage(page, "factory")
  const now = () => page.evaluate(() => performance.now())
  await page.waitForTimeout(600)
  const between = (seen: Seen[], from: number, to: number) => seen.filter(view => view.at > from && view.at <= to)
  const speed = (seen: Seen[]) => turned(seen[0]!, seen.at(-1)!) / ((seen.at(-1)!.at - seen[0]!.at) / 1000)

  const middle = at(0.5, 0.5)
  await page.mouse.move(middle.x, middle.y)
  await page.keyboard.down("Control")
  await page.mouse.wheel(0, -10)
  const started = await now()
  for (let step = 2; step <= 8; step++) {
    await page.waitForTimeout(80)
    await page.mouse.wheel(0, -10)
  }
  await page.keyboard.up("Control")
  const stopped = await now()
  await page.waitForTimeout(3_500)
  const seen = await views(page)

  // Before, it turns by itself.
  const before = speed(between(seen, started - 600, started - 50))
  expect(before).toBeGreaterThan(0.3 * CRUISE)
  // From the first zoom to a little after the last, it holds its turn while the zoom comes nearer and the loop plays on.
  const still = between(seen, started, stopped + 600)
  expect(still.length).toBeGreaterThan(5)
  for (const view of still) expect(turned(still[0]!, view)).toBe(0)
  expect(still.at(-1)!.distance).toBeLessThan(still[0]!.distance)
  expect(new Set(still.map(view => view.loop)).size).toBeGreaterThan(1)
  // Then it turns again at about its old speed, the zoom where it was left.
  const after = between(seen, stopped + 3_000, stopped + 3_500)
  expect(speed(after)).toBeGreaterThan(0.6 * before)
  expect(new Set([still.at(-1)!, ...after].map(view => view.distance))).toEqual(new Set([still.at(-1)!.distance]))
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

      // Once its first picture has landed, it stays the same.
      const resting = await steady(page, scene)
      await page.waitForTimeout(400)
      expect((await picture(page, scene)).equals(resting)).toBe(true)

      // Drags across, then down, from the middle of the box; each leaves the picture changed and still.
      const area = (await box.boundingBox())!
      const middle = {x: area.x + area.width / 2, y: area.y + area.height / 2}
      let last = resting
      for (const [dx, dy] of [[15, 0], [0, 12]]) {
        await page.mouse.move(middle.x, middle.y)
        await page.mouse.down()
        for (let step = 1; step <= 4; step++) await page.mouse.move(middle.x + step * dx, middle.y + step * dy)
        const halfway = await steady(page, scene)
        expect(halfway.equals(last)).toBe(false)
        for (let step = 5; step <= 8; step++) await page.mouse.move(middle.x + step * dx, middle.y + step * dy)
        await page.mouse.up()
        const moved = await steady(page, scene)
        // The drag stays the scene's to its end: the browser never takes the still to carry off.
        expect(moved.equals(halfway)).toBe(false)
        await page.waitForTimeout(400)
        expect((await picture(page, scene)).equals(moved)).toBe(true)
        last = moved
      }

      await box.focus()
      for (const key of ["ArrowRight", "ArrowUp"]) {
        await page.keyboard.press(key)
        const pressed = await steady(page, scene)
        expect(pressed.equals(last)).toBe(false)
        last = pressed
      }
    })
  }

  test("Zoom in brings the scene nearer a step at a time up to the nearest, Zoom out takes it back, and each says when it has nothing left to do", async ({page}) => {
    await watchViews(page)
    await page.goto("/animations/splats")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    const box = await drawn(page, "factory")
    const [zoomOut, zoomIn, reset] = ["Zoom out", "Zoom in", "Reset view"].map(name => box.getByRole("button", {name}))
    for (const button of [zoomOut, zoomIn, reset]) await expect(button!).toBeVisible()
    const limits = () => Promise.all([zoomOut, zoomIn, reset].map(button => button!.getAttribute("aria-disabled")))
    expect(await limits()).toEqual(["true", "false", "true"])
    const opening = await steady(page, "factory")
    const first = (await views(page)).at(-1)!
    const zoom = async () => first.distance / (await views(page)).at(-1)!.distance

    // A drag that starts on a button is the button's: the scene neither turns nor zooms.
    const {x, y, width, height} = (await zoomIn!.boundingBox())!
    await page.mouse.move(x + width / 2, y + height / 2)
    await page.mouse.down()
    for (let step = 1; step <= 6; step++) await page.mouse.move(x + width / 2 - step * 20, y + height / 2 - step * 10)
    await page.mouse.up()
    expect((await steady(page, "factory")).equals(opening)).toBe(true)

    // Each press lands at once, held still, one step nearer, the turn as it was.
    let last = opening
    for (let step = 1; step <= 4; step++) {
      await zoomIn!.click()
      await expect.poll(zoom).toBeCloseTo(Math.SQRT2 ** step, 4)
      const nearer = await steady(page, "factory")
      expect(nearer.equals(last)).toBe(false)
      last = nearer
    }
    expect(turned(first, (await views(page)).at(-1)!)).toBe(0)
    expect(await limits()).toEqual(["false", "true", "false"])
    await zoomIn!.click({force: true})
    const held = await steady(page, "factory")
    expect(await zoom()).toBeCloseTo(4, 4)
    expect(held.equals(last)).toBe(true)

    for (let step = 3; step >= 0; step--) {
      await zoomOut!.click()
      await expect.poll(zoom).toBeCloseTo(Math.SQRT2 ** step, 4)
    }
    expect(await limits()).toEqual(["true", "false", "true"])
    expect((await steady(page, "factory")).equals(opening)).toBe(true)

    // The keys step the same way.
    await box.focus()
    for (const [key, near] of [["+", Math.SQRT2], ["=", 2], ["-", Math.SQRT2]] as const) {
      await page.keyboard.press(key)
      await expect.poll(zoom).toBeCloseTo(near, 4)
    }
  })

  test("a wheel with Ctrl held zooms at the pointer: the point under it near a corner stays under it, and a plain wheel is the page's", async ({page}) => {
    await watchViews(page)
    await page.goto("/animations/splats")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await drawn(page, "factory")
    const {height, at, pixel: under} = await stage(page, "factory")
    // How far each wheel turned (a phone's screen scales it), and whether it reached the page with its own scroll or zoom still to come.
    await page.evaluate(() => {
      const wheels: {pixels: number; kept: boolean}[] = []
      Object.assign(window, {wheels})
      window.addEventListener("wheel", event => wheels.push({pixels: event.deltaY, kept: !event.defaultPrevented}), {passive: true})
    })
    const wheels = () => page.evaluate(() => (window as unknown as {wheels: {pixels: number; kept: boolean}[]}).wheels)
    // A wheel with Ctrl held zooms e times nearer for every 100 pixels it turns up (splat_island.ts).
    const wheeled = async () => Math.min(4, Math.exp(-(await wheels()).reduce((sum, {pixels}) => sum + pixels, 0) / 100))
    const pointer = at(0.2, 0.25)
    const pixel = under(pointer)
    const opening = (await views(page)).at(-1)!
    const anchor = underPixel(opening, pixel, height)
    await page.mouse.move(pointer.x, pointer.y)

    await page.keyboard.down("Control")
    for (let step = 1; step <= 8; step++) {
      await page.mouse.wheel(0, -35)
      const near = await wheeled()
      await expect.poll(async () => opening.distance / (await views(page)).at(-1)!.distance).toBeCloseTo(near, 4)
      const view = (await views(page)).at(-1)!
      const [x, y] = onCanvas(view, anchor, height)
      expect(Math.abs(x! - pixel[0])).toBeLessThan(artPixel(view, height))
      expect(Math.abs(y! - pixel[1])).toBeLessThan(artPixel(view, height))
    }
    await page.keyboard.up("Control")

    const zoomed = (await views(page)).at(-1)!
    expect(opening.distance / zoomed.distance).toBeGreaterThan(2)
    await page.mouse.wheel(0, 40)
    await page.waitForTimeout(150)
    expect((await views(page)).at(-1)!.distance).toBe(zoomed.distance)
    expect((await wheels()).map(({kept}) => kept)).toEqual([...Array(8).fill(false), true])
  })

  test("Reset view, 0 and a double-click each go back to the opening picture from any zoom and tilt", async ({page}) => {
    await page.goto("/animations/splats")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    const box = await drawn(page, "factory")
    const [zoomOut, reset] = ["Zoom out", "Reset view"].map(name => box.getByRole("button", {name}))
    const opening = await steady(page, "factory")
    const {at} = await stage(page, "factory")
    const homes = [() => reset!.click(), () => page.keyboard.press("0"), () => page.mouse.dblclick(at(0.5, 0.5).x, at(0.5, 0.5).y)]
    for (const home of homes) {
      const pointer = at(0.3, 0.6)
      await page.mouse.move(pointer.x, pointer.y)
      await page.keyboard.down("Control")
      await page.mouse.wheel(0, -35)
      await page.mouse.wheel(0, -35)
      await page.keyboard.up("Control")
      await box.focus()
      await page.keyboard.press("ArrowUp")
      await expect(reset!).toHaveAttribute("aria-disabled", "false")
      await expect.poll(async () => (await picture(page, "factory")).equals(opening)).toBe(false)

      await home()
      await expect.poll(async () => (await picture(page, "factory")).equals(opening)).toBe(true)
      await expect(reset!).toHaveAttribute("aria-disabled", "true")
      await expect(zoomOut!).toHaveAttribute("aria-disabled", "true")
    }
  })

  test("on a touch screen two fingers pinch the scene nearer at their midpoint, the page staying put, and a double tap goes back", async ({page, isMobile}) => {
    test.skip(!isMobile, "Touch is the phone's.")
    await watchViews(page)
    await page.goto("/animations/splats")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    const box = await drawn(page, "factory")
    const opening = await steady(page, "factory")
    const {height, at, pixel: under} = await stage(page, "factory")
    const first = (await views(page)).at(-1)!
    const middle = at(0.4, 0.4)
    const pixel = under(middle)
    const anchor = underPixel(first, pixel, height)
    const touch = await page.context().newCDPSession(page)
    const fingers = (gap: number) => [
      {x: middle.x - gap, y: middle.y - gap, id: 1},
      {x: middle.x + gap, y: middle.y + gap, id: 2},
    ]

    await touch.send("Input.dispatchTouchEvent", {type: "touchStart", touchPoints: fingers(15)})
    for (let gap = 18; gap <= 30; gap += 3) await touch.send("Input.dispatchTouchEvent", {type: "touchMove", touchPoints: fingers(gap)})
    await touch.send("Input.dispatchTouchEvent", {type: "touchEnd", touchPoints: []})
    await expect.poll(async () => first.distance / (await views(page)).at(-1)!.distance).toBeCloseTo(2, 2)
    const view = (await views(page)).at(-1)!
    const [x, y] = onCanvas(view, anchor, height)
    expect(Math.abs(x! - pixel[0])).toBeLessThan(artPixel(view, height))
    expect(Math.abs(y! - pixel[1])).toBeLessThan(artPixel(view, height))
    expect(turned(first, view)).toBe(0)
    expect(await page.evaluate(() => [window.scrollY, window.visualViewport!.scale])).toEqual([0, 1])
    await expect(box.getByRole("button", {name: "Zoom out"})).toHaveAttribute("aria-disabled", "false")

    const centre = at(0.5, 0.5)
    for (let tap = 0; tap < 2; tap++) {
      await touch.send("Input.dispatchTouchEvent", {type: "touchStart", touchPoints: [centre]})
      await touch.send("Input.dispatchTouchEvent", {type: "touchEnd", touchPoints: []})
      await page.waitForTimeout(60)
    }
    await expect.poll(async () => (await picture(page, "factory")).equals(opening)).toBe(true)
    await expect(box.getByRole("button", {name: "Zoom out"})).toHaveAttribute("aria-disabled", "true")
  })

  test("Download GIF still saves the island's GIF, pressed from the keyboard", async ({page}) => {
    test.setTimeout(30_000 + WHOLE_GIF)
    const {button, saved} = await openForGif(page, "island")
    const download = page.waitForEvent("download", {timeout: WHOLE_GIF})
    await button.focus()
    await page.keyboard.press("Enter")
    const gif = await download
    expect(gif.suggestedFilename()).toBe("regents-island.gif")
    expect(await opening(gif)).toEqual(GIF)
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
    const resting = await steady(page, "factory")
    await swipe(0, -15)
    expect(await page.evaluate(() => window.scrollY)).toBeGreaterThan(0)
    await page.evaluate(() => window.scrollTo(0, 0))
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0)
    expect((await steady(page, "factory")).equals(resting)).toBe(true)

    await swipe(15, 0)
    expect((await steady(page, "factory")).equals(resting)).toBe(false)
  })
})
