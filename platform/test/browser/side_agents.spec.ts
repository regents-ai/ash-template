import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// The walk's person has four agents (sign_in.exs) and none has been active, so the
// side panel shows the three paired last and leaves out Spare Agent, paired first.
// Manage beside the heading opens the agents on this site's own Account page. With a mouse
// it shows while the pointer is over the list or a key has moved into it, and the
// rows never move when it does; on the touch phone it always shows, 44 px tall.
test.use(signedIn)

test("the side panel shows three agents and Manage", async ({page, hasTouch}) => {
  const problems = watch(page)
  await page.goto("/account")
  await ready(page)
  const agents = page.locator("#shell-agents")
  // The side panel's own button, or on a phone the account's name, opens it.
  if (!(await agents.isVisible())) await page.locator("[data-aside-toggle]:visible").last().click()
  await expect(agents).toBeVisible()

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
    // Where the rows sit inside the panel, which may still be sliding in.
    const rows = () =>
      agents.getByRole("list").evaluate(list => {
        const box = list.getBoundingClientRect()
        return {top: box.top - list.closest("section")!.getBoundingClientRect().top, height: box.height}
      })
    const before = await rows()
    await page.mouse.move(0, 0)
    await expect.poll(opacity).toBe("0")
    await agents.getByRole("heading", {name: "Your agents"}).hover()
    await expect.poll(opacity).toBe("1")
    expect(await rows()).toEqual(before)

    await page.mouse.move(0, 0)
    await expect.poll(opacity).toBe("0")
    await manage.focus()
    await expect.poll(opacity).toBe("1")
  }
  await manage.click()
  await expect(page).toHaveURL(/\/account#account-agents$/)
  await problems.expect()
})

test("Manage Account opens this site's Account page in the same tab", async ({page}) => {
  const problems = watch(page)
  await page.goto("/rooms/general")
  await ready(page)
  const account = page.locator("#shell-account")
  if (!(await account.isVisible())) await page.locator("[data-aside-toggle]:visible").last().click()
  await account.getByRole("link", {name: "Manage Account"}).click()
  await expect(page).toHaveURL(/\/account$/)
  await expect(page.locator("#account-agents")).toBeVisible()
  await problems.expect()
})
