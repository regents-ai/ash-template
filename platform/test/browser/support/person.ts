import {type BrowserContext, type Page, expect} from "@playwright/test"

// The walk's person, signed in by sign_in.exs before the server starts.
export const signedIn = {storageState: "test/browser/.auth/person.json"}

// The page's sign-in bridge asks the site to sign out when the browser holds no
// sign-in of its own, which a walk never has, so that one request is stopped;
// every other request goes through.
export async function keepSignedIn(context: BrowserContext) {
  await context.route("**/auth/privy/session", route =>
    route.request().method() === "DELETE" ? route.abort() : route.continue(),
  )
}

// The shell's buttons answer once its script has wired them, as they do for a
// person by the time they reach for one.
export async function ready(page: Page) {
  await expect(page.locator('[data-behavior-ready="true"]')).toBeAttached()
}

// What a broken page shows: an uncaught error, a request to this site that
// failed, or content wider than the screen.
export function watch(page: Page, allowedStatus?: number) {
  const problems: string[] = []
  page.on("pageerror", error => problems.push(`page error: ${error.message}`))
  page.on("response", response => {
    const url = new URL(response.url())
    const status = response.status()
    if (url.host === "127.0.0.1:4098" && status >= 400 && status !== allowedStatus)
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
