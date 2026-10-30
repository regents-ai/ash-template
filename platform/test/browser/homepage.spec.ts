import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The homepage's two columns, as regents.sh's: the hero stands top right and stays in
// view while Mission, Products, Staking and How it works scroll past on the left; with
// less motion asked for it scrolls with the page; a phone reads the hero first.
const edges = (page: Page) =>
  page.evaluate(() => {
    const box = (selector: string) => document.querySelector(selector)!.getBoundingClientRect().toJSON()
    return {
      hero: box('[data-home-panel="hero"]'),
      worlds: box("#home-worlds"),
      mission: box("#home-mission"),
      how: box("#home-how"),
    }
  })

const open = async (page: Page, width: number, height: number) => {
  await page.setViewportSize({width, height})
  await page.goto("/")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
}

const scrollBy240 = async (page: Page) => {
  await page.evaluate(() => window.scrollTo(0, 240))
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(240)
}

// Each size has a page of its own: LiveView keeps the window's scroll in the page's
// history 100ms after a scroll and scrolls back to it when that page loads again, so
// a size opened on the page another size scrolled could start scrolled.
for (const [width, height] of [[1280, 720], [1440, 900]]) {
  test(`the hero stays top right while the sheets scroll at ${width}x${height}`, async ({page}) => {
    await open(page, width, height)
    const first = await edges(page)
    expect(first.hero.left, "the hero is the right column").toBeGreaterThanOrEqual(first.mission.right)
    expect(first.hero.top, "level with Mission").toBeCloseTo(first.mission.top, 0)

    await scrollBy240(page)
    const scrolled = await edges(page)
    expect(scrolled.mission.top, "the sheets scroll").toBeCloseTo(first.mission.top - 240, 0)
    expect(scrolled.hero.top, "the hero holds near the top").toBeGreaterThanOrEqual(0)
    expect(scrolled.hero.top).toBeLessThan(first.hero.top)
    expect(scrolled.hero.bottom, "the whole hero is in view").toBeLessThanOrEqual(height)
    expect(scrolled.worlds.bottom, "the worlds too").toBeLessThanOrEqual(height)
  })
}

test("with less motion the hero scrolls with the page", async ({page}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  await open(page, 1440, 900)
  const first = await edges(page)
  await scrollBy240(page)
  expect((await edges(page)).hero.top).toBeCloseTo(first.hero.top - 240, 0)
})

test("a phone reads the hero before the sheets", async ({page}) => {
  for (const [width, height] of [[320, 640], [390, 844]]) {
    await test.step(`${width} wide`, async () => {
      await open(page, width, height)
      const {hero, mission, how} = await edges(page)
      expect(hero.bottom, "the hero comes first").toBeLessThanOrEqual(mission.top)
      expect(mission.bottom, "then the sheets").toBeLessThanOrEqual(how.top)
    })
  }
})
