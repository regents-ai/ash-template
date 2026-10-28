import {chromium} from "@playwright/test"
import {onThisMachine} from "./test"
import {signedIn} from "./person"

// The walk's first page load, before any check, once and never retried. A freshly
// started server answers its first pages slowly while it warms, and the first
// signed-in checks timed out on a cold run (28 Oct). One signed-in room is opened
// until its shell is wired; a page that still cannot get there fails the walk.
export default async function warmUp() {
  const baseURL = `http://127.0.0.1:${process.env.ASH_TEMPLATE_WALK_PORT}`
  const browser = await chromium.launch()
  try {
    const context = await browser.newContext({...signedIn, baseURL})
    await onThisMachine(context, baseURL)
    const page = await context.newPage()
    await page.goto("/rooms/general")
    await page.locator('[data-behavior-ready="true"]').first().waitFor({state: "attached", timeout: 120_000})
  } finally {
    await browser.close()
  }
}
