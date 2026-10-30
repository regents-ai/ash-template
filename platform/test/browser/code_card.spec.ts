import type {Page} from "@playwright/test"
import {copiesShown, recordCopies} from "./support/copies"
import {expect, test} from "./support/test"

// A code cube face's card copies what it lists as Markdown, in the section shape the
// agent tools window copies every site in. The walk's server answers each site's
// tools from AshTemplate.WalkOffline. A face turns with the cube and never rests
// under a finger, so each card is opened from the keyboard.
test.use({permissions: ["clipboard-read", "clipboard-write"]})

const open = async (page: Page, face: string) => {
  await recordCopies(page)
  await page.goto("/animations/twin-cube")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.locator("#twin-code").scrollIntoViewIfNeeded()
  await page.getByRole("button", {name: face}).focus()
  await page.keyboard.press("Enter")
  const card = page.locator("#twin-card")
  await expect(card).toBeVisible()
  return card
}

test("a site's card copies its tools", async ({page}) => {
  const card = await open(page, "regents.sh")
  const copy = card.getByRole("button", {name: "Copy as Markdown"})
  await expect(copy).toBeVisible()
  const names = await card.locator(".code-card__tool code").allTextContents()
  expect(names.length).toBeGreaterThan(0)

  await copy.click()
  await expect.poll(() => copiesShown(copy)).toEqual([{answer: "copied", shown: "Copied", said: "Copied"}])
  const text = await page.evaluate(() => navigator.clipboard.readText())
  expect(text.startsWith(`# regents.sh\n\n${names.length} WebMCP tools\n\n## `)).toBe(true)
  expect([...text.matchAll(/^`(.+)`$/gm)].map(match => match[1])).toEqual(names)
})

test("siwa-server's card copies how an agent connects", async ({page}) => {
  const card = await open(page, "siwa-server")
  const copy = card.getByRole("button", {name: "Copy as Markdown"})
  const commands = await card.locator(".code-card__tool pre").allTextContents()
  expect(commands.length).toBeGreaterThan(0)
  const guide = await card.getByRole("link", {name: /Read the whole guide/}).getAttribute("href")

  await copy.click()
  await expect.poll(() => copiesShown(copy)).toEqual([{answer: "copied", shown: "Copied", said: "Copied"}])
  const text = await page.evaluate(() => navigator.clipboard.readText())
  expect(text.startsWith("# siwa-server\n\n")).toBe(true)
  for (const command of commands) expect(text).toContain("```sh\n" + command + "\n```")
  expect(text.endsWith(`The whole guide: ${guide}\n`)).toBe(true)
})
