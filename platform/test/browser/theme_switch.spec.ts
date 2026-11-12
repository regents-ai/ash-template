import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// The light and dark switch, a row of the account menu (Shell.theme_toggle/1). It is a
// real switch, on for the light theme: a press, Space or Enter turns the page's theme,
// the choice holds over a reload and a live page change, and the menu keeps its size
// whichever way it is turned. Opening the menu moves nothing on the page.
test.use(signedIn)

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
// public page, which no live view draws, and of the shell. Each press turns it once.
test.describe("signed out", () => {
  test.use({storageState: {cookies: [], origins: []}})

  for (const path of ["/agents", "/polls"]) {
    test(`the bottom bar's theme switch on ${path} turns the theme with each press`, async ({page}) => {
      const problems = watch(page)
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
