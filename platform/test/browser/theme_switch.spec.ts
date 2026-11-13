import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// The light and dark switch, a row of the account menu (Shell.theme_toggle/1). It is a
// real switch, on for the light theme: a press, Space or Enter turns the page's theme,
// the choice holds over a reload and a live page change, and the menu keeps its size
// whichever way it is turned. Opening the menu moves nothing on the page. The GPU is
// on, as on a visitor's browser, so the grains over the switch draw.
test.use(signedIn)
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

const menu = (page: Page) => page.locator("#account-menu")
const toggle = (page: Page) => menu(page).getByRole("switch", {name: "Light theme"})

// The theme on screen: the page's own once chosen, otherwise the device's.
const showing = (page: Page) =>
  page.evaluate(() => {
    const theme = document.documentElement.dataset.theme
    if (theme === "light" || theme === "dark") return theme
    return matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"
  })

async function openMenu(page: Page) {
  await page.locator("#account-chip").click()
  await expect(menu(page)).toBeVisible()
  await expect.poll(() => menu(page).evaluate(element => element.getAnimations().length)).toBe(0)
}

// The switch says what the page shows: on for light, off for dark.
async function expectTheme(page: Page, theme: "light" | "dark") {
  await expect.poll(() => showing(page)).toBe(theme)
  await expect(toggle(page)).toHaveAttribute("aria-checked", String(theme === "light"))
}

const size = async (page: Page) => {
  const box = (await menu(page).boundingBox())!
  return {width: box.width, height: box.height}
}

test("the theme switch turns the page's theme by press and by key, and the choice holds", async ({page, isMobile}) => {
  const problems = watch(page)
  if (isMobile) await page.setViewportSize({width: 320, height: 640})
  await page.goto("/rooms/general")
  await ready(page)

  const content = page.locator("#route-content")
  const before = await content.boundingBox()
  await openMenu(page)
  expect(await content.boundingBox()).toEqual(before)

  const first = await showing(page)
  const other = first === "light" ? "dark" : "light"
  await expectTheme(page, first)
  const opened = await size(page)

  await toggle(page).click()
  await expectTheme(page, other)
  await expect(menu(page)).toBeVisible()
  expect(await size(page)).toEqual(opened)

  await toggle(page).focus()
  await page.keyboard.press("Space")
  await expectTheme(page, first)
  await page.keyboard.press("Enter")
  await expectTheme(page, other)
  expect(await size(page)).toEqual(opened)

  await page.reload()
  await ready(page)
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.theme)).toBe(other)
  await openMenu(page)
  await expectTheme(page, other)

  // Manage Account is a live page change: the document stays and restates its theme.
  await menu(page).getByRole("link", {name: "Manage Account"}).click()
  await expect(page).toHaveURL(/\/account$/)
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.theme)).toBe(other)
  await openMenu(page)
  await expectTheme(page, other)
  await problems.expect()
})

// Signed out there is no account menu, so the switch sits in the bottom bar: of a
// plain page, which no live view draws (the limit page, sent with 429), and of the
// shell. Each press turns it once.
test.describe("signed out", () => {
  test.use({storageState: {cookies: [], origins: []}})

  for (const [path, status] of [["/too-many-pages", 429], ["/polls", undefined]] as const) {
    test(`the bottom bar's theme switch on ${path} turns the theme with each press`, async ({page}) => {
      const problems = watch(page, status)
      await page.goto(path)
      const bar = page.getByRole("switch", {name: "Light theme"})
      await expect(bar).toHaveCount(1)
      const first = await showing(page)
      const other = first === "light" ? "dark" : "light"
      await expect(bar).toHaveAttribute("aria-checked", String(first === "light"))

      await bar.click()
      await expect.poll(() => showing(page)).toBe(other)
      await expect(bar).toHaveAttribute("aria-checked", String(other === "light"))

      await bar.focus()
      await page.keyboard.press("Space")
      await expect.poll(() => showing(page)).toBe(first)
      await expect(bar).toHaveAttribute("aria-checked", String(first === "light"))
      await problems.expect()
    })
  }
})

// The grains over the bottom bar's switch on /polls, drawn on the GPU: they take
// over from the server's drawing without moving anything, a second press while
// they fly turns them round, and once they rest nothing is drawn. With less
// motion they never draw and the server's switch is the whole of it.
test.describe("the grains", () => {
  test.use({storageState: {cookies: [], origins: []}})

  const control = "#shell-footer-theme-control"
  const field = (page: Page) => page.locator(`${control} .particle-field`)
  const bar = (page: Page) => page.locator(`${control} [role='switch']`)

  /** Where the switch's parts stand: the press, the knob, the grains' box and the drawing showing. */
  const places = (page: Page) =>
    page.evaluate(selector => {
      const root = document.querySelector(selector)!
      const box = (part: string) => {
        const shown = [...root.querySelectorAll(part)].find(element => element.getClientRects().length > 0)!
        const {x, y, width, height} = shown.getBoundingClientRect()
        return {x, y, width, height}
      }
      return {
        press: box("[role='switch']"),
        knob: box(".theme-switch__knob"),
        field: box(".particle-field"),
        drawing: box("svg[data-particle-source]"),
      }
    }, control)

  async function drawn(page: Page) {
    await expect(field(page)).toHaveAttribute("data-particle-ready", "true")
  }

  test("take over from the drawing without moving the switch", async ({page}) => {
    // The places as the page first lays the switch out, before any script has run.
    await page.addInitScript(selector => {
      document.addEventListener("DOMContentLoaded", () => {
        const root = document.querySelector(selector)!
        const box = (part: string) => {
          const shown = [...root.querySelectorAll(part)].find(element => element.getClientRects().length > 0)!
          const {x, y, width, height} = shown.getBoundingClientRect()
          return {x, y, width, height}
        }
        ;(window as unknown as {firstPlaces: unknown}).firstPlaces = {
          press: box("[role='switch']"),
          knob: box(".theme-switch__knob"),
          field: box(".particle-field"),
          drawing: box("svg[data-particle-source]"),
        }
      })
    }, control)
    await page.goto("/polls")
    await drawn(page)
    const first = await page.evaluate(() => (window as unknown as {firstPlaces: unknown}).firstPlaces)
    expect(await places(page)).toEqual(first)
  })

  test("a second press while the grains fly turns them round", async ({page}) => {
    await page.goto("/polls")
    await drawn(page)
    const first = await showing(page)
    const other = first === "light" ? "dark" : "light"
    const shapeOf = (theme: string) => (theme === "light" ? "sun" : "moon")

    await bar(page).click()
    await expect.poll(() => showing(page)).toBe(other)
    await expect(field(page)).toHaveAttribute("data-particle-shape", shapeOf(other))
    // Well inside the half second the grains fly for.
    await page.waitForTimeout(120)
    await bar(page).click()
    await expect.poll(() => showing(page)).toBe(first)
    await expect(bar(page)).toHaveAttribute("aria-checked", String(first === "light"))
    await expect(field(page)).toHaveAttribute("data-particle-shape", shapeOf(first))
  })

  test("draw nothing while they rest", async ({page}) => {
    await page.addInitScript(() => {
      const counted = window as unknown as {frames: number}
      counted.frames = 0
      const submit = GPUQueue.prototype.submit
      GPUQueue.prototype.submit = function (buffers) {
        counted.frames += 1
        return submit.call(this, buffers)
      }
    })
    await page.goto("/polls")
    await drawn(page)
    await bar(page).click()
    // The flight is over in about half a second.
    await page.waitForTimeout(1500)
    await page.evaluate(() => ((window as unknown as {frames: number}).frames = 0))
    await page.waitForTimeout(10_000)
    expect(await page.evaluate(() => (window as unknown as {frames: number}).frames)).toBe(0)
  })

  test.describe("with less motion", () => {
    test.use({reducedMotion: "reduce"})

    test("never draw, and the server's switch still turns the theme", async ({page}) => {
      await page.goto("/polls")
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      await page.waitForTimeout(1500)
      await expect(field(page)).not.toHaveAttribute("data-particle-ready", "true")
      await expect(page.locator(`${control} .particle-field__stage`)).toHaveCSS("visibility", "hidden")
      const drawing = page.locator(`${control} svg[data-particle-source]:visible`)
      await expect(drawing).toHaveCount(1)

      const first = await showing(page)
      await bar(page).click()
      await expect.poll(() => showing(page)).not.toBe(first)
      await expect(drawing).toHaveCount(1)
      await expect(field(page)).not.toHaveAttribute("data-particle-ready", "true")
    })
  })
})
