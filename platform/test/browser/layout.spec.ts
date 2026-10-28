import {expect, test} from "./support/test"
import {ready, signedIn} from "./support/person"

// Layout rules that once broke. Each test names the page it was found on.
test.use(signedIn)

// Found by the review of 18 Oct: the Account page's two columns also split
// Credits history, whose one panel then filled half the page.
test("a page with one panel gives it the whole width", async ({page}) => {
  await page.goto("/account/credits")
  const panel = await page.locator("#credits-history").boundingBox()
  const grid = await page.locator("#credits-history-page .account-grid").boundingBox()
  expect(panel!.width).toBeCloseTo(grid!.width, 0)
})

// Found by the layers review of 27 Oct: on a phone the bottom bar took the panel
// layer, so it drew over the bottom of the open menu, undimmed and still pressable.
// The open menu and its shade cover the bottom bar.
test("on a phone, the open menu covers the bottom bar", async ({page, isMobile}) => {
  test.skip(!isMobile, "the bottom bar meets the panels only on a phone")
  await page.goto("/rooms/general")
  await ready(page)
  const footer = (await page.locator("#shell-footer").boundingBox())!
  const onTop = (x: number, y: number, id: string) =>
    page.evaluate(([x, y, id]) => document.elementFromPoint(x, y)?.closest(`#${id}`) !== null, [x, y, id] as const)

  // The menu slides in from the left edge; it is measured once it is there.
  await page.locator("#mobile-menu-button").click()
  await expect(page.locator("#shell-drawer")).toBeVisible()
  await expect.poll(async () => (await page.locator("#shell-drawer").boundingBox())!.x).toBeCloseTo(0, 0)
  const drawer = (await page.locator("#shell-drawer").boundingBox())!
  expect(await onTop(drawer.x + 8, footer.y + footer.height / 2, "shell-drawer")).toBe(true)
  // Past the menu's edge, the shade lies over the bottom bar.
  expect(await onTop(drawer.x + drawer.width + 8, footer.y + footer.height / 2, "shell-footer")).toBe(false)
  // Design review of 28 Oct: the page was out of reach behind the open menu, but the
  // bottom bar's links could still take focus. Both are out of reach until it closes.
  for (const behind of ["#app-shell-scroller", "#shell-footer"]) {
    await expect(page.locator(behind)).toHaveJSProperty("inert", true)
  }
  await page.locator("[data-shell-menu-close]").click()
  await expect(page.locator("#shell-drawer")).toBeHidden()
  for (const behind of ["#app-shell-scroller", "#shell-footer"]) {
    await expect(page.locator(behind)).toHaveJSProperty("inert", false)
  }
})
