import type {Locator, Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, resting, signedIn, watch} from "./support/person"

// Every window the template opens is the design library's frame
// (`Regent.Structure.dialog`, founder 19 Oct: never a default square window), and
// sits whole on the screen, in each theme, at 1280 wide and on the phone at 390.
// Each window is found by its role and name; the press that opens it, by its id.
test.use(signedIn)

type Press = (target: Locator) => Promise<void>

const windows: {name: string; path: string; open: (page: Page, press: Press) => Promise<void>; window: (page: Page) => Locator}[] = [
  {
    // The app shell's buttons answer once its script has wired them.
    name: "search",
    path: "/app",
    open: async (page, press) => {
      await ready(page)
      await press(page.locator("#shell-search-button"))
    },
    window: page => page.getByRole("dialog", {name: "Search"}),
  },
  {
    name: "Buy Credits",
    path: "/app",
    open: async (page, press) => {
      await ready(page)
      await press(page.locator("#shell-credits-button"))
    },
    window: page => page.getByRole("dialog", {name: "Buy Credits"}),
  },
  {
    name: "the agent tools list",
    path: "/",
    open: (page, press) => press(page.locator("#home-agent-tools-button")),
    window: page => page.getByRole("dialog", {name: /^\d+ Agent Tools$/}),
  },
  {
    // siwa-server's face, whose card reads nothing from another site. The cube starts
    // once it is on the screen, below the world cube on a phone. A face turns with the
    // cube and never rests under a finger, so it is opened from the keyboard.
    name: "a code cube face's card",
    path: "/animations/twin-cube",
    open: async page => {
      await page.locator("#twin-code").scrollIntoViewIfNeeded()
      await page.getByRole("button", {name: "siwa-server"}).focus()
      await page.keyboard.press("Enter")
    },
    window: page => page.locator("#twin-card"),
  },
  {
    name: "an agent's card in the harbour",
    path: "/animations/harbour",
    open: (page, press) =>
      press(page.getByRole("list", {name: "Crew"}).getByRole("link", {name: "Basil"})),
    window: page => page.getByRole("dialog", {name: "Basil"}),
  },
]

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({colorScheme})

    for (const entry of windows) {
      test(`${entry.name} opens in the shared frame, whole on the screen`, async ({page, hasTouch}) => {
        const press: Press = target => (hasTouch ? target.tap() : target.click())
        const problems = watch(page)
        await page.goto(entry.path)
        await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

        await entry.open(page, press)
        const window = entry.window(page)
        await expect(window).toBeVisible()
        await resting(window)
        await expect(window).toHaveClass(/\brg-dialog\b/)

        const box = (await window.boundingBox())!
        const screen = page.viewportSize()!
        expect(box.x).toBeGreaterThanOrEqual(0)
        expect(box.y).toBeGreaterThanOrEqual(0)
        expect(box.x + box.width).toBeLessThanOrEqual(screen.width)
        expect(box.y + box.height).toBeLessThanOrEqual(screen.height)
        await problems.expect()
      })
    }
  })
}
