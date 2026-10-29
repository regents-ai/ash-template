import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// The account menu, opened by the account's button at the top right of every page.
// The walk's person has four agents (sign_in.exs) and none has been active, so the
// menu shows the three paired last and leaves out Spare Agent, paired first.
// Manage beside the heading opens the agents on this site's own Account page. With a
// mouse it shows while the pointer is over the list or a key has moved into it, and
// the rows never move when it does; on the touch phone it always shows, 44 px tall.
test.use(signedIn)

const menu = (page: Page) => page.locator("#account-menu")

// Opened, and done dropping in, so what is measured is where it rests.
async function openMenu(page: Page) {
  await page.locator("#account-chip").click()
  await expect(menu(page)).toBeVisible()
  await expect.poll(() => menu(page).evaluate(element => element.getAnimations().length)).toBe(0)
}

test("the account menu shows three agents and Manage", async ({page, hasTouch}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await ready(page)
  await openMenu(page)
  const agents = page.locator("#shell-agents")

  await expect(agents.getByRole("listitem")).toHaveCount(3)
  await expect(agents).not.toContainText("Spare Agent")

  const manage = agents.getByRole("link", {name: "Manage your agents"})
  await expect(manage).toHaveText("Manage")
  await expect(manage).toHaveAttribute("href", "/account#account-agents")
  const opacity = () => manage.evaluate(link => getComputedStyle(link).opacity)

  if (hasTouch) {
    await expect.poll(opacity).toBe("1")
    expect((await manage.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  } else {
    // Where the rows sit inside the menu.
    const rows = () =>
      agents.getByRole("list").evaluate(list => {
        const box = list.getBoundingClientRect()
        return {top: box.top - list.closest("section")!.getBoundingClientRect().top, height: box.height}
      })
    const before = await rows()
    await agents.getByRole("heading", {name: "Your agents"}).hover()
    await expect.poll(opacity).toBe("1")
    expect(await rows()).toEqual(before)

    // Off the list, still inside the menu, so it stays open.
    await menu(page).locator(".rg-account-menu__name").hover()
    await expect.poll(opacity).toBe("0")
    await manage.focus()
    await expect.poll(opacity).toBe("1")
  }
  await manage.click()
  await expect(page).toHaveURL(/\/account#account-agents$/)
  await problems.expect()
})

test("the account menu hangs under its button and closes on Escape, focus back on the button", async ({page, isMobile}) => {
  const problems = watch(page)
  for (const width of isMobile ? [390, 320] : [1280, 2000]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/rooms/general")
    await ready(page)
    await openMenu(page)

    const chip = (await page.locator("#account-chip").boundingBox())!
    const box = (await menu(page).boundingBox())!
    // Below the button, inside the screen, its right edge near the button's.
    expect(box.y).toBeGreaterThanOrEqual(chip.y + chip.height)
    expect(box.x).toBeGreaterThanOrEqual(0)
    expect(box.x + box.width).toBeLessThanOrEqual(width)
    if (!isMobile) expect(Math.abs(box.x + box.width - (chip.x + chip.width))).toBeLessThan(2)

    await menu(page).getByRole("link", {name: "Manage Account"}).focus()
    await page.keyboard.press("Escape")
    await expect(menu(page)).toBeHidden()
    await expect(page.locator("#account-chip")).toBeFocused()
  }
  await problems.expect()
})

test("the account menu opens from the keyboard, is named for the person, and a press outside closes it", async ({page}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await ready(page)
  await page.locator("#account-chip").focus()
  await page.keyboard.press("Enter")
  await expect(menu(page)).toBeVisible()
  await expect(menu(page)).toHaveRole("region")
  await expect(menu(page)).toHaveAccessibleName(await menu(page).locator(".rg-account-menu__name strong").innerText())
  // A press beside the menu, or below it where it spans a phone's screen.
  const box = (await menu(page).boundingBox())!
  await page.mouse.click(box.x > 40 ? box.x / 2 : box.x + box.width / 2, box.y + box.height + 20)
  await expect(menu(page)).toBeHidden()
  await problems.expect()
})

// An open section on the page behind keeps its place: Escape is the menu's first.
test("Escape closes the account menu before an open section behind it", async ({page}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await ready(page)
  await page.locator("#route-content").evaluate(content => {
    const details = document.createElement("details")
    details.open = true
    details.id = "walk-open-section"
    details.innerHTML = "<summary>Section</summary><p>Inside</p>"
    content.prepend(details)
  })
  await openMenu(page)
  await page.keyboard.press("Escape")
  await expect(menu(page)).toBeHidden()
  await expect(page.locator("#walk-open-section")).toHaveAttribute("open", "")
  await problems.expect()
})

test("asked for less motion, the account menu appears at once", async ({page}) => {
  const problems = watch(page)
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.goto("/rooms/general")
  await ready(page)
  await page.locator("#account-chip").click()
  await expect(menu(page)).toBeVisible()
  expect(await menu(page).evaluate(element => element.getAnimations().length)).toBe(0)
  await problems.expect()
})

test("Manage Account opens this site's Account page and the menu closes", async ({page}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await ready(page)
  await openMenu(page)
  await expect(menu(page).getByRole("button", {name: "Sign out"})).toBeVisible()
  await menu(page).getByRole("link", {name: "Manage Account"}).click()
  await expect(page).toHaveURL(/\/account$/)
  await expect(page.locator("#account-agents")).toBeVisible()
  await expect(menu(page)).toBeHidden()
  await problems.expect()
})

// Sign out closes the menu, so when the site can't be reached the note that it
// couldn't finish shows under the account button with nothing over it.
test("Sign out closes the menu, and the note that it couldn't finish is on top", async ({page}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await ready(page)
  await page.route("**/auth/privy/session", route =>
    route.request().method() === "DELETE" ? route.abort() : route.continue())
  await openMenu(page)
  await menu(page).getByRole("button", {name: "Sign out"}).click()
  await expect(menu(page)).toBeHidden()
  const note = page.locator("#account-auth-status")
  await expect(note).toHaveText("Sign out couldn’t finish. Try again.")
  // The note lets presses through, so for this one look it takes them, and the
  // middle of it is the note unless something is drawn over it.
  const onTop = await note.evaluate(element => {
    element.style.pointerEvents = "auto"
    const box = element.getBoundingClientRect()
    return document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)?.closest("#account-auth-status") === element
  })
  expect(onTop).toBe(true)
  await problems.expect()
})

test("Pair New Agent in the menu lands on the Account page's pairing box", async ({page}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await ready(page)
  await openMenu(page)
  await menu(page).getByRole("link", {name: "Pair New Agent"}).click()
  await expect(page).toHaveURL(/\/account#account-pairing$/)
  await expect(menu(page)).toBeHidden()
  await expect(page.locator("#account-pairing")).toBeInViewport()
  // The keyboard starts on the agent choice.
  await expect(page.locator("#account-pairing").getByRole("radio").first()).toBeFocused()

  // Pressed again from the same address after scrolling away, it moves there again.
  await page.locator("#app-shell-scroller").evaluate(scroller => scroller.scrollTo({top: 0}))
  await expect(page.locator("#account-pairing").getByRole("heading", {name: "Pair New Agent"})).not.toBeInViewport()
  await openMenu(page)
  await menu(page).getByRole("link", {name: "Pair New Agent"}).click()
  await expect(menu(page)).toBeHidden()
  await expect(page.locator("#account-pairing")).toBeInViewport()
  await expect(page.locator("#account-pairing").getByRole("radio").first()).toBeFocused()
  await problems.expect()
})

// On a short phone screen the open menu reaches over the bottom bar, as every open
// panel does, ends inside the screen, and scrolls to Sign out.
test("on a short phone screen, the account menu covers the bottom bar and reaches Sign out", async ({page, isMobile}) => {
  test.skip(!isMobile, "the bottom bar meets the menu only on a phone")
  for (const width of [390, 320]) {
    await page.setViewportSize({width, height: 360})
    await page.goto("/rooms/general")
    await ready(page)
    await openMenu(page)
    const footer = (await page.locator("#shell-footer").boundingBox())!
    const box = (await menu(page).boundingBox())!
    expect(box.y + box.height).toBeLessThanOrEqual(360)
    const x = box.x + box.width / 2
    const y = footer.y + footer.height / 2
    expect(await page.evaluate(([x, y]) => document.elementFromPoint(x, y)?.closest("#account-menu") !== null, [x, y])).toBe(true)
    const signOut = menu(page).getByRole("button", {name: "Sign out"})
    await signOut.scrollIntoViewIfNeeded()
    await expect(signOut).toBeInViewport()
  }
})

// Narrower than 22.5rem the header has no room for the balance, so the account menu
// shows it, in the header's words, and the row opens the same Buy Credits panel. The
// sample account's 10.00 Credits is the balance that once pushed the header 15px past
// a 320px screen.
test("on the narrowest phones the balance is in the account menu and opens Buy Credits", async ({page, isMobile}) => {
  test.skip(!isMobile, "only the narrowest phones move the balance")
  const problems = watch(page)
  await page.setViewportSize({width: 320, height: 900})
  await page.goto("/showcase/preview")
  await ready(page)
  await expect(page.locator("#shell-credits-button")).toBeHidden()
  await openMenu(page)

  const row = page.locator("#account-menu-credits")
  await expect(row).toBeVisible()
  await expect(row).toHaveText("10.00 Credits")
  await expect(row).toHaveAccessibleName("10.00 Credits")
  expect((await row.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320)

  await row.click()
  await expect(menu(page)).toBeHidden()
  await expect(page.locator("#shell-credits")).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(page.locator("#shell-credits")).toBeHidden()
  await expect(page.locator("#account-chip")).toBeFocused()

  // The walk's own person, on a page of the site, the same.
  await page.goto("/rooms/general")
  await ready(page)
  await expect(page.locator("#shell-credits-button")).toBeHidden()
  await openMenu(page)
  await expect(page.locator("#account-menu-credits")).toBeVisible()
  await problems.expect()
})

test("wider than the narrowest phones the balance stays in the header, not the menu", async ({page, isMobile}) => {
  const problems = watch(page)
  const width = isMobile ? 390 : 1280
  await page.setViewportSize({width, height: 900})
  await page.goto("/showcase/preview")
  await ready(page)
  await expect(page.locator("#shell-credits-button")).toBeVisible()
  await openMenu(page)
  await expect(page.locator("#account-menu-credits")).toBeHidden()
  await page.keyboard.press("Escape")
  await page.locator("#shell-credits-button").click()
  await expect(page.locator("#shell-credits")).toBeVisible()
  await problems.expect()
})
