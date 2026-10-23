import {expect, test} from "./support/test"
import {watch} from "./support/person"

// Base's newest block is read once an hour; the figures page says when it was
// last read and its read-again icon asks for a reading at once.
test("The figures page shows when Base was last read and reads it again on the icon", async ({page, hasTouch}, info) => {
  const problems = watch(page)
  await page.goto("/showcase/figures")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const lastRead = page.locator("#figures-head-read")
  await expect(lastRead).toHaveText(/Updated \d{1,2} \w{3}, \d{2}:\d{2} UTC|Not read yet/)
  const again = page.getByRole("button", {name: "Read again now", exact: true})
  await expect(again).toBeVisible()
  const box = await again.boundingBox()
  expect(Math.round(box!.width)).toBe(Math.round(box!.height))
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width)

  await (hasTouch ? again.tap() : again.click())
  await expect(page.locator("#figures-head-state")).toBeVisible()
  await page.screenshot({path: info.outputPath(`figures-read-${info.project.name}.png`)})
  await problems.expect()
})
