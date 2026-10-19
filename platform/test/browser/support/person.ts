import {type Page} from "@playwright/test"
import {expect} from "./test"

// The walk's person, signed in by sign_in.exs before the server starts.
export const signedIn = {storageState: "test/browser/.auth/person.json"}

// The shell's buttons answer once its script has wired them, as they do for a
// person by the time they reach for one.
export async function ready(page: Page) {
  await expect(page.locator('[data-behavior-ready="true"]')).toBeAttached()
}

// The run's own server (playwright.config.ts).
const site = `127.0.0.1:${process.env.ASH_TEMPLATE_WALK_PORT}`

// What a broken page shows: an uncaught error, a request to this site that
// failed, or content wider than the screen.
export function watch(page: Page, allowedStatus?: number) {
  const problems: string[] = []
  page.on("pageerror", error => problems.push(`page error: ${error.message}`))
  page.on("response", response => {
    const url = new URL(response.url())
    const status = response.status()
    if (url.host === site && status >= 400 && status !== allowedStatus)
      problems.push(`${status} ${response.request().method()} ${url.pathname}`)
  })
  return {
    expect: async () => {
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
      )
      if (overflow > 0) problems.push(`content is ${overflow}px wider than the screen`)
      expect(problems).toEqual([])
    },
  }
}
