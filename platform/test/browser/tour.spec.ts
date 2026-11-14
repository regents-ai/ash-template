import type {Page} from "@playwright/test"
import {watch} from "./support/person"
import {expect, test} from "./support/test"
import {card, next, open, standing, title} from "./support/tour"

// The homepage's guided tour (AshTemplateWeb.Components.Tour): a first visit plays
// it by itself, Next rings each part in turn, Skip, Escape and Done end it for good,
// and Tour plays it again. The tour only points: a button under the dimming takes
// its press whatever step is on show. Every other walk starts with the tour marked
// seen (playwright.config.ts); these start with nothing kept.
test.use({storageState: {cookies: [], origins: []}})

const steps: [string, string][] = [
  ["App", "#home-enter-app"],
  ["Tools", "#home-agent-tools-button"],
  ["Agents", "#home-agents-link"],
  ["Products", ".rl-product-tabs"],
  ["Tour", "#home-tour-start"],
]

const seen = (page: Page) => page.evaluate(() => localStorage.getItem("ash-template:tour:home"))

const frames = (page: Page) =>
  page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))))

// Walks the tour from its first step to Done, checking each step as it goes.
async function walk(page: Page, {still = false} = {}) {
  for (const [index, [name, selector]] of steps.entries()) {
    await expect(title(page)).toHaveText(name)
    // With less motion asked for, the ring is round its part on the next frame,
    // with no glide to it.
    if (still) {
      await frames(page)
      expect((await standing(page, selector)).ringOff).toBeLessThanOrEqual(1.5)
    }
    await expect.poll(async () => (await standing(page, selector)).ringOff).toBeLessThanOrEqual(1.5)
    const now = await standing(page, selector)
    expect(now.covers).toBe(false)
    expect(now.onScreen).toBe(true)
    expect(now.overflow).toBe(false)
    expect(now.blocked).toEqual([])
    await expect(next(page)).toHaveText(index === steps.length - 1 ? "Done" : "Next")
    await next(page).click()
  }
  await expect(card(page)).toBeHidden()
}

test("a first visit plays the tour once, ringing each part in turn, and Done ends it for good", async ({page}) => {
  const problems = watch(page)
  await open(page)

  await expect(card(page)).toBeVisible()
  await expect(next(page)).toBeFocused()
  await walk(page)
  expect(await seen(page)).toBe("seen")
  // The tour hands focus to the button that plays it again.
  await expect(page.locator("#home-tour-start")).toBeFocused()

  await page.reload()
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await frames(page)
  await expect(card(page)).toBeHidden()
  await problems.expect()
})

test("Skip and Escape end the tour, a reload leaves it ended, and Tour plays it again", async ({page}) => {
  await open(page)
  await expect(title(page)).toHaveText("App")
  await next(page).click()
  await expect(title(page)).toHaveText("Tools")
  await page.locator(".tour [data-tour-skip]").click()
  await expect(card(page)).toBeHidden()
  expect(await seen(page)).toBe("seen")

  await page.reload()
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await frames(page)
  await expect(card(page)).toBeHidden()

  const tour = page.locator("#home-tour-start")
  await tour.click()
  await expect(card(page)).toBeVisible()
  await expect(title(page)).toHaveText("App")
  await expect(next(page)).toBeFocused()
  await next(page).click()
  await page.locator(".tour [data-tour-back]").click()
  await expect(title(page)).toHaveText("App")
  await page.keyboard.press("Escape")
  await expect(card(page)).toBeHidden()
  await expect(tour).toBeFocused()
})

test("a button under the dimming takes its press while the tour shows", async ({page}) => {
  await open(page)
  await expect(title(page)).toHaveText("App")

  // WebMCP Tools lies under the dimming at the first step, and opens its window.
  const tools = page.locator("#home-agent-tools-button")
  await tools.click()
  const window = page.locator("dialog#home-agent-tools")
  await expect(window).toBeVisible()
  // Escape closes the window, not the tour under it.
  await page.keyboard.press("Escape")
  await expect(window).toBeHidden()
  await expect(title(page)).toHaveText("App")

  // At its own step, ringed, it takes its press just the same.
  await next(page).click()
  await expect(title(page)).toHaveText("Tools")
  await tools.click()
  await expect(window).toBeVisible()
  await expect(card(page)).toBeAttached()
})

test("with less motion asked for, and on a 320 wide phone, the card stays on the screen and the ring is simply there", async ({
  page,
}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.setViewportSize({width: 320, height: 640})
  await open(page)

  await expect(card(page)).toBeVisible()
  await walk(page, {still: true})
  // Less motion keeps the light off: the ring is the page's own lines.
  await expect(page.locator(".tour")).not.toHaveAttribute("data-tour-ready", "true")
})
