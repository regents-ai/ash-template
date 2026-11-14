import {expect, test} from "./support/test"
import {card, open, standing} from "./support/tour"

// With a GPU the homepage's glass panel starts away until a press on the picture. The
// guided tour points at what the panel holds, so it holds the panel open for as long
// as it shows, steering or not, and its ring gives off its light.
test.use({
  storageState: {cookies: [], origins: []},
  launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]},
})

test("the tour holds the glass open and lights its ring", async ({page}) => {
  await open(page)
  await expect(card(page)).toBeVisible()
  await expect(page.locator("#public-home")).toHaveAttribute("data-datascape-ready", "true", {timeout: 20_000})
  const glass = page.locator("#home-glass")
  await expect(glass).toHaveCSS("opacity", "1")
  await expect.poll(async () => (await standing(page, "#home-enter-app")).ringOff).toBeLessThanOrEqual(1.5)
  await expect(page.locator(".tour")).toHaveAttribute("data-tour-ready", "true", {timeout: 20_000})

  // Steering the picture from a corner leaves it open. No press holds it, so without
  // the tour it would be on its way out at once, and gone within 400 ms.
  await page.mouse.move(4, 4)
  await page.mouse.move(6, 6)
  await page.waitForTimeout(1000)
  await expect(glass).toHaveCSS("opacity", "1")
  expect((await standing(page, "#home-enter-app")).ringOff).toBeLessThanOrEqual(1.5)
})
