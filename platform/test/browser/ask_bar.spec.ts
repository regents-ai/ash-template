import {expect, test} from "./support/test"

// The ask bar lab (/animations/ask). The question lives in the link, so a shared
// link draws the same answer; a question the bar does not know shows three it does;
// and all of it works from the keyboard alone.

test("a question's link draws the same answer again on reload", async ({page}) => {
  await page.goto("/animations/ask?q=Offers%20under%2050%20USDC")
  await page.locator("[data-phx-main].phx-connected").waitFor()
  const plan = page.locator("#ask-plan")
  await expect(plan.locator(".ask-list__row")).toHaveCount(3)
  const first = await plan.innerText()

  await page.reload()
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await expect(page.locator("#ask-q")).toHaveValue("Offers under 50 USDC")
  await expect(plan.locator(".ask-list__row")).toHaveCount(3)
  expect(await plan.innerText()).toBe(first)
})

test("a question it does not know shows three it does, each one answering", async ({page}) => {
  await page.goto("/animations/ask?q=banana")
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await expect(page.locator("#ask-plan")).toHaveCount(0)
  const examples = page.locator("#ask-none .ask-example")
  await expect(examples).toHaveCount(3)

  await examples.first().click()
  await expect(page).toHaveURL(/q=Credits/)
  await expect(page.locator("#ask-plan [data-chart]")).toBeVisible()
})

test("asking and following an example work from the keyboard alone", async ({page}) => {
  await page.goto("/animations/ask")
  await page.locator("[data-phx-main].phx-connected").waitFor()

  await page.keyboard.press("/")
  await expect(page.locator("#ask-q")).toBeFocused()
  await page.keyboard.type("stake 100")
  await page.keyboard.press("Enter")
  await expect(page).toHaveURL(/q=stake\+100|q=stake%20100/)
  await expect(page.locator("#ask-plan .ask-block--confirm")).toBeVisible()

  await page.locator("#ask-q").fill("banana")
  await page.keyboard.press("Enter")
  await expect(page.locator("#ask-none")).toBeVisible()
  await page.keyboard.press("Tab")
  await expect(page.locator("#ask-none .ask-example").first()).toBeFocused()
  await page.keyboard.press("Enter")
  await expect(page).toHaveURL(/q=Credits/)
  await expect(page.locator("#ask-plan")).toBeVisible()
})

test.describe("at 320 wide", () => {
  test.use({viewport: {width: 320, height: 700}})

  test("every answer fits the screen", async ({page}) => {
    for (const q of ["Credits left", "Offers under 50 USDC", "Stake 100 REGENT", "pira", "banana"]) {
      await page.goto(`/animations/ask?q=${encodeURIComponent(q)}`)
      await page.locator("[data-phx-main].phx-connected").waitFor()
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
      )
      expect(overflow, q).toBe(0)
    }
  })
})
