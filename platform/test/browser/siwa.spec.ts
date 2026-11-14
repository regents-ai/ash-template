import type {Locator, Page} from "@playwright/test"
import {bridge, expect, standIn, test} from "./support/test"
import {bareAddresses} from "./support/addresses"
import {unreachableScrollers} from "./support/scrollers"
import {ready, watch} from "./support/person"

// SIWA, against the walk's own SIWA stand-in (AshTemplate.WalkControl): each width
// has its own person who has never used it (sign_in.exs), names their company, is
// refused an origin a sandbox site can't list, adds the site, makes a key, sees it
// once, revokes it through the confirm window and opens Settings. With SIWA off,
// the page says it is unavailable.

// The sign-in bridge trades as `did` with the access token `access`.
const trading = (page: Page, did: string, access?: string) =>
  page.route(
    url => bridge.test(url.pathname),
    route => route.fulfill({contentType: "text/javascript", body: standIn(did, access)}),
  )

const connected = (page: Page) => expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

// Every address shows with its copy icon, and every box that scrolls takes the keyboard.
async function tidy(page: Page) {
  expect(await bareAddresses(page)).toEqual([])
  expect(await unreachableScrollers(page)).toEqual([])
}

test.describe("a new SIWA customer", () => {
  test.use({
    storageState: async ({}, use, info) => use(`test/browser/.auth/siwa-${info.project.name}.json`),
  })

  test("names their company, adds a sandbox site, makes and revokes a key, and opens Settings", async ({page, hasTouch}, info) => {
    const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
    const problems = watch(page)
    await trading(page, `did:privy:browser-walk-siwa-${info.project.name}`)
    await page.goto("/siwa/sites")
    await connected(page)
    await ready(page)

    const company = page.locator("#siwa-company-form")
    await page.locator("#siwa-company-name").fill(`Walk Company ${info.project.name}`)
    await press(company.locator("button[type='submit']"))

    const site = page.locator("#siwa-site-form")
    await expect(site).toBeVisible()
    await tidy(page)
    await page.locator("#siwa-site-name").fill("Walk Site")
    await page.locator("#siwa-site-audience").fill(`walk-${info.project.name}`)
    await page.locator("#siwa-site-environment").selectOption("sandbox")
    const origins = page.locator("#siwa-site-origins")
    await origins.fill("https://example.com")
    await press(page.locator("#siwa-site-submit"))
    await expect(origins).toHaveAttribute("aria-invalid", "true")
    await expect(page.locator("#siwa-site-origins-errors p")).toHaveCount(1)
    await expect(page.locator("#siwa-site-audience")).toHaveAttribute("aria-invalid", "false")

    await origins.fill("http://localhost:4000")
    await press(page.locator("#siwa-site-submit"))
    await expect(page).toHaveURL(/\/siwa\/sites\/[0-9a-f-]{36}$/)
    await expect(page.locator("#siwa-audience")).toHaveText(`walk-${info.project.name}`)

    await press(page.locator("#siwa-make-key"))
    await expect(page.locator("#siwa-key-value")).toHaveText(/^siwa_sk_test_[A-Za-z0-9_-]{43}$/)
    const keys = page.locator("#siwa-keys > li")
    await expect(keys).toHaveCount(1)
    await tidy(page)
    await press(page.locator("#siwa-key-done"))
    await expect(page.locator("#siwa-key-reveal")).toHaveCount(0)

    await press(keys.first().locator("button[id^='siwa-revoke-']"))
    const confirm = page.locator("#rg-confirm")
    await expect(confirm).toBeVisible()
    await press(confirm.locator("[data-confirm-accept]"))
    await expect(keys.first().locator("button[id^='siwa-revoke-']")).toHaveCount(0)
    await expect(keys).toHaveCount(1)

    await page.goto("/siwa/settings")
    await connected(page)
    await expect(page.locator("#siwa-company-name")).toHaveValue(`Walk Company ${info.project.name}`)
    await expect(page.locator("#siwa-owner-name")).toBeVisible()
    await expect(page.locator("#siwa-owner-wallet")).toBeVisible()
    await expect(page.locator("#siwa-support")).toBeVisible()
    await tidy(page)

    await page.goto("/siwa/sites")
    await connected(page)
    await expect(page.locator("#siwa-sites > li[id^='siwa-site-']")).toHaveCount(1)
    await tidy(page)
    await problems.expect()
  })
})

test.describe("with SIWA off", () => {
  // Another person's sign-in, so no token kept for the walk's SIWA people is found.
  test.use({storageState: "test/browser/.auth/friend.json"})

  test("the page says SIWA is unavailable and offers to try again", async ({page}) => {
    const problems = watch(page, 503)
    await trading(page, "did:privy:browser-walk-friend", "walk-unavailable")
    await page.goto("/siwa/sites")
    await connected(page)

    const unavailable = page.locator("#siwa-unavailable")
    await expect(unavailable).toBeVisible()
    await expect(unavailable.locator("button[phx-click='retry']")).toBeVisible()
    await problems.expect()
  })
})
