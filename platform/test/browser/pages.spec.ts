import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import map from "./pages.json" with {type: "json"}
import {bareAddresses} from "./support/addresses"
import {unreachableScrollers} from "./support/scrollers"
import {ready, signedIn, watch} from "./support/person"

// Every page in the feature map opens, shows what proves its purpose, raises no
// error, fits the screen, shows every address with its copy icon and lets a keyboard
// scroll every box that scrolls; every document answers with its type. The map lists
// every page route (feature_map_test.exs), so a new page is walked from its first day.
type Entry = {route: string; paths?: string[]; check: string; status?: number}

const paths = (entry: {route: string; paths?: string[]}) => entry.paths ?? [entry.route]

// A chat's or a conversation's address is only known once it exists: open the
// person's first one from its page's list, as they would.
const lists: Record<string, string> = {
  "/chat/{conversation}": "/chat",
  "/dms/{conversation}": "/dms",
  "/polls/{poll}": "/polls"
}

async function open(page: Page, path: string) {
  const list = lists[path]
  if (!list) return page.goto(path, {waitUntil: "load"})
  await page.goto(list)
  const href = await page.locator(`#shell-sidebar-page a[href^="${list}/"]`).first().getAttribute("href")
  return page.goto(href!, {waitUntil: "load"})
}

function walk(entry: Entry, path: string, signedIn: boolean) {
  test(`page ${path}`, async ({page}) => {
    const problems = watch(page, entry.status)
    const response = await open(page, path)
    expect(response?.status()).toBe(entry.status ?? 200)
    await expect(page.locator(entry.check).first()).toBeVisible()
    if (signedIn) {
      await ready(page)
      await expect(page.locator("#account-chip")).toBeVisible()
    }
    expect(await bareAddresses(page)).toEqual([])
    expect(await unreachableScrollers(page)).toEqual([])
    await problems.expect()
  })
}

// A server started without its sign-in settings still answers every page, but
// nobody can sign in.
test("the site starts with its sign-in settings", async ({page}) => {
  await page.goto("/")
  await expect(page.locator('meta[name="privy-app-id"]')).toHaveAttribute("content", /.+/)
})

test.describe("visitor", () => {
  for (const entry of map.pages.filter(entry => !("signed_in" in entry)))
    for (const path of paths(entry)) walk(entry, path, false)
})

test.describe("signed in", () => {
  test.use(signedIn)
    for (const entry of map.pages.filter(entry => "signed_in" in entry))
    for (const path of paths(entry)) walk(entry, path, true)
})

test.describe("documents", () => {
  for (const entry of map.documents) {
    for (const path of paths(entry)) {
      test(`document ${path}`, async ({request}) => {
        const response = await request.get(path)
        expect(response.status()).toBe(200)
        expect(response.headers()["content-type"]).toContain(entry.type)
        expect((await response.body()).length).toBeGreaterThan(0)
      })
    }
  }
})
