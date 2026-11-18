import {createServer, type Server} from "node:http"
import type {AddressInfo} from "node:net"
import {type Locator, type Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The five scenes (/animations/scenes) and each scene's own page (/scenes/<n>), opened
// with the GPU on. On the Scenes page each of the five draws once scrolled to, one
// turns by itself, a drag turns it, Zoom in changes the picture and Reset view brings
// the opening one back, and a scene's traits open, all with nothing raised in the
// console and nothing wider than the screen. A scene's own page draws, turns and zooms
// opened directly and inside another site's frame sandboxed with scripts allowed,
// whose origin is no site's; without WebGPU its still stays and no zoom button shows.
// The site's own address is localhost in development, which a scene's page names its
// files by; the other site is a page served here on 127.0.0.1, on a port of its own.
const site = `http://localhost:${process.env.ASH_TEMPLATE_WALK_PORT}`

test.use({baseURL: site, launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

/** Another site: a page holding the scene its address names in a 600 by 600 frame sandboxed with scripts allowed. */
let otherSite: Server

test.beforeAll(async () => {
  otherSite = createServer((request, response) => {
    const scene = new URL(request.url!, "http://other.site").searchParams.get("scene")
    response.writeHead(200, {"content-type": "text/html"})
    response.end(`<!doctype html><meta name="viewport" content="width=device-width"><body style="margin:0"><iframe sandbox="allow-scripts" src="${site}/scenes/${scene}" width="600" height="600" style="border:0;display:block"></iframe></body>`)
  })
  await new Promise<void>(listening => otherSite.listen(0, "127.0.0.1", listening))
})

test.afterAll(() => new Promise<void>(closed => otherSite.close(() => closed())))

/** Opens the other site's page holding scene `n`, in a window its frame fills; the walk lets the browser reach it, and only it, off the site. */
const frame = async (page: Page, n: number) => {
  const gallery = `http://127.0.0.1:${(otherSite.address() as AddressInfo).port}/`
  await page.route(`${gallery}**`, route => route.continue())
  await page.setViewportSize({width: 600, height: 600})
  await page.goto(`${gallery}?scene=${n}`)
}

/** Everything the page and its frames raise: console errors, uncaught errors and failed requests. */
const watch = (page: Page) => {
  const problems: string[] = []
  page.on("console", message => message.type() === "error" && problems.push(`console: ${message.text()}`))
  page.on("pageerror", error => problems.push(`page error: ${error.message}`))
  page.on("requestfailed", request => problems.push(`failed: ${request.url()}`))
  page.on("response", response => response.status() >= 400 && problems.push(`${response.status()} ${response.url()}`))
  return problems
}

const sideways = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

const drawn = async (box: Locator) => {
  await box.scrollIntoViewIfNeeded()
  await expect(box).toHaveAttribute("data-splats-ready", "true", {timeout: 20_000})
  await expect(box.locator(".splat-stage__live")).toHaveCSS("opacity", "1")
  return box
}

/**
 * The scene above its zoom buttons, one pixel inside the box. The buttons are left out
 * by the clip: a scene's own page admits no style but its own stylesheet.
 */
const picture = async (page: Page, box: Locator) => {
  const {x, y, width, height} = (await box.boundingBox())!
  return page.screenshot({clip: {x: x + 1, y: y + 1, width: width - 2, height: height * 0.75}})
}

/** The scene's picture once two in a row agree. */
const steady = async (page: Page, box: Locator) => {
  let last = await picture(page, box)
  await expect
    .poll(async () => {
      const next = await picture(page, box)
      const same = next.equals(last)
      last = next
      return same
    })
    .toBe(true)
  return last
}

const turns = async (page: Page, box: Locator) => {
  const before = await picture(page, box)
  await page.waitForTimeout(400)
  expect((await picture(page, box)).equals(before)).toBe(false)
}

/** Zoom in changes the picture; Reset view brings the opening one back. With less motion, each lands at once. */
const zooms = async (page: Page, box: Locator) => {
  const [zoomIn, reset] = ["Zoom in", "Reset view"].map(name => box.getByRole("button", {name}))
  await expect(zoomIn!).toBeVisible()
  const opening = await steady(page, box)
  await zoomIn!.click()
  await expect(reset!).toHaveAttribute("aria-disabled", "false")
  expect((await steady(page, box)).equals(opening)).toBe(false)
  await reset!.click()
  await expect.poll(async () => (await picture(page, box)).equals(opening)).toBe(true)
  await expect(reset!).toHaveAttribute("aria-disabled", "true")
}

test("each of the five scenes draws once scrolled to, and the first turns by itself", async ({page}) => {
  test.setTimeout(90_000)
  const problems = watch(page)
  await page.goto("/animations/scenes")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await expect(page.locator(".scenes-lab__card")).toHaveCount(5)
  for (let n = 1; n <= 5; n++) await drawn(page.locator(`#scene-${n}`))

  const first = await drawn(page.locator("#scene-1"))
  await turns(page, first)
  expect(await sideways(page)).toBe(0)
  expect(problems).toEqual([])
})

test("a scene's traits open under it, every row with its tier and share, from the keyboard too", async ({page}) => {
  const problems = watch(page)
  await page.goto("/animations/scenes")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const traits = page.locator("#scene-2-traits")
  const rows = traits.locator("tbody tr")
  await expect(rows.first()).toBeHidden()

  await traits.locator("summary").click()
  await expect(traits).toHaveAttribute("open", "")
  await expect(rows).toHaveCount(31)
  await expect(rows.first()).toBeVisible()
  await expect(rows.first().locator("td")).toHaveText(["Action", "Trainer Battle", "Epic", "0.68%"])

  await traits.locator("summary").press("Enter")
  await expect(traits).not.toHaveAttribute("open", "")
  await traits.locator("summary").press("Enter")
  await expect(rows.last()).toBeVisible()
  expect(await sideways(page)).toBe(0)
  expect(problems).toEqual([])
})

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("on the Scenes page a drag turns a scene, Zoom in brings it nearer and Reset view brings the opening picture back", async ({page}) => {
    const problems = watch(page)
    await page.goto("/animations/scenes")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    const box = await drawn(page.locator("#scene-3"))
    const held = await steady(page, box)

    const {x, y, width, height} = (await box.boundingBox())!
    await page.mouse.move(x + width * 0.4, y + height * 0.4)
    await page.mouse.down()
    for (let step = 1; step <= 6; step++) await page.mouse.move(x + width * 0.4 + step * 20, y + height * 0.4)
    await page.mouse.up()
    expect((await steady(page, box)).equals(held)).toBe(false)

    await page.reload()
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await zooms(page, await drawn(page.locator("#scene-3")))
    expect(problems).toEqual([])
  })

  test("a scene's own page, opened directly, zooms in and back", async ({page}) => {
    await page.setViewportSize({width: 600, height: 600})
    const problems = watch(page)
    await page.goto("/scenes/4")
    await zooms(page, await drawn(page.locator("#scene-4")))
    expect(problems).toEqual([])
  })

  test("a scene's own page, in another site's sandboxed frame, zooms in and back", async ({page}) => {
    const problems = watch(page)
    await frame(page, 5)
    await zooms(page, await drawn(page.frameLocator("iframe").locator("#scene-5")))
    expect(problems).toEqual([])
  })
})

test("a scene's own page fills the page it is opened on, draws and turns, with nothing else on it", async ({page}) => {
  await page.setViewportSize({width: 600, height: 600})
  const problems = watch(page)
  await page.goto("/scenes/1")
  const box = await drawn(page.locator("#scene-1"))
  expect(await box.boundingBox()).toEqual({x: 0, y: 0, width: 600, height: 600})
  await expect(page.locator("body > *:not(script)")).toHaveCount(1)
  await turns(page, box)
  expect(await sideways(page)).toBe(0)
  expect(problems).toEqual([])
})

test("a scene's own page draws and turns inside another site's frame sandboxed with scripts allowed", async ({page}) => {
  const problems = watch(page)
  await frame(page, 1)
  const inside = page.frames().find(child => child !== page.mainFrame())!
  // The frame's origin is no site's: nothing the page asks of the site may lean on it.
  expect(await inside.evaluate(() => self.origin)).toBe("null")
  const box = await drawn(page.frameLocator("iframe").locator("#scene-1"))
  await turns(page, box)
  await expect(box.getByRole("button", {name: "Zoom in"})).toBeVisible()
  expect(problems).toEqual([])
})

test("without WebGPU a scene's own page keeps its still and offers no zoom", async ({page}) => {
  await page.addInitScript(() => Object.defineProperty(Navigator.prototype, "gpu", {get: () => undefined}))
  await page.setViewportSize({width: 600, height: 600})
  const problems = watch(page)
  await page.goto("/scenes/2")
  const box = page.locator("#scene-2")
  await expect(box).toHaveAttribute("data-splats-ready", "false")
  const still = box.locator(".splat-stage__still")
  await expect.poll(() => still.evaluate((image: HTMLImageElement) => [image.complete, image.naturalWidth])).toEqual([true, 480])
  for (const zoom of await box.locator("button[data-splats-zoom]").all()) await expect(zoom).toBeHidden()
  expect(problems).toEqual([])
})
