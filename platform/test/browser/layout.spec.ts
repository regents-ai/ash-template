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

// Found on Patchbay on 21 Oct: its side panel slid in beside a tall header, so the
// line under the panel's short top bar stopped partway down the header. The header
// runs the whole width, over the panel; the panel opens under the header's bottom
// line, and the line under its top bar meets the line under the sidebar's title row.
test("the side panel opens under the header, its top bar in line with the sidebar's", async ({
  page,
  isMobile,
}) => {
  for (const width of isMobile ? [390] : [1280, 2000]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/rooms/general")
    await ready(page)
    const aside = page.locator("#shell-aside")
    if (!(await aside.isVisible())) await page.locator("[data-aside-toggle]:visible").last().click()
    await expect(aside).toBeVisible()
    // Measured once the panel has finished sliding in.
    const sliding = () =>
      page.evaluate(() => document.getAnimations().filter(a => a instanceof CSSTransition).length)
    await expect.poll(sliding).toBe(0)

    const header = (await page.locator("#shell-header").boundingBox())!
    const panel = (await aside.boundingBox())!
    // Below the header, never beside it; on a phone it may reach past the page's margins.
    expect(panel.y).toBeCloseTo(header.y + header.height, 0)
    expect(panel.x).toBeLessThan(header.x + header.width)
    expect(panel.x + panel.width).toBeGreaterThan(header.x)

    const sidebarHead = page.locator(".shell-sidebar__head")
    if (await sidebarHead.isVisible()) {
      const bar = (await page.locator(".shell-aside__head").boundingBox())!
      const title = (await sidebarHead.boundingBox())!
      expect(bar.y + bar.height).toBeCloseTo(title.y + title.height, 0)
    }
  }
})

// Found by the layers review of 27 Oct: on a phone the bottom bar took the panel
// layer, so it drew over the bottom of the open menu and side panel, undimmed and
// still pressable. Open panels and their shade cover the bottom bar.
test("on a phone, the open menu and side panel cover the bottom bar", async ({page, isMobile}) => {
  test.skip(!isMobile, "the bottom bar meets the panels only on a phone")
  await page.goto("/rooms/general")
  await ready(page)
  const footer = (await page.locator("#shell-footer").boundingBox())!
  const onTop = (x: number, y: number, id: string) =>
    page.evaluate(([x, y, id]) => document.elementFromPoint(x, y)?.closest(`#${id}`) !== null, [x, y, id] as const)
  const sliding = () =>
    page.evaluate(() => document.getAnimations().filter(a => a instanceof CSSTransition).length)

  // The menu slides in from the left edge; it is measured once it is there.
  await page.locator("#mobile-menu-button").click()
  await expect(page.locator("#shell-drawer")).toBeVisible()
  await expect.poll(async () => (await page.locator("#shell-drawer").boundingBox())!.x).toBeCloseTo(0, 0)
  const drawer = (await page.locator("#shell-drawer").boundingBox())!
  expect(await onTop(drawer.x + 8, footer.y + footer.height / 2, "shell-drawer")).toBe(true)
  // Past the menu's edge, the shade lies over the bottom bar.
  expect(await onTop(drawer.x + drawer.width + 8, footer.y + footer.height / 2, "shell-footer")).toBe(false)
  await page.locator("[data-shell-menu-close]").click()
  await expect(page.locator("#shell-drawer")).toBeHidden()

  await page.locator("[data-aside-toggle]:visible").last().click()
  await expect(page.locator("#shell-aside")).toBeVisible()
  await expect.poll(sliding).toBe(0)
  expect(await onTop(footer.x + footer.width / 2, footer.y + footer.height / 2, "shell-aside")).toBe(true)
})
