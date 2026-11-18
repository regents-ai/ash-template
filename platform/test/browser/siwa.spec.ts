import type {Locator, Page} from "@playwright/test"
import {bridge, expect, standIn, test} from "./support/test"
import {bareAddresses} from "./support/addresses"
import {unreachableScrollers} from "./support/scrollers"
import {ready, watch} from "./support/person"

// SIWA, against the walk's own SIWA stand-in (AshTemplate.WalkControl): each width
// has its own person who has never used it (sign_in.exs), names their company, sees
// the handle follow the name and gives it their own, is refused a localhost address
// on the New site form, turns it into a practice site and adds it, finds the command
// its agent reaches the site with, makes a key, sees it once, revokes it through the confirm window, opens Settings, on Overview finds
// billing not started and sets, is refused and removes a cap, then follows its link
// to Billing, subscribes on Stripe, comes back to Manage and a first invoice, and
// goes to Stripe and back again with Manage. Each width also has a person whose
// company is billed, who reads the period on Overview, lists more of its agents, is
// refused a cap below the fee so far, on its proven production site adds an origin,
// which sets the proof back, and checks it, and on Billing lists more invoices; and
// one whose SIWA has billing off, whose Billing page offers nothing to press. With
// SIWA off, the page says it is unavailable.

// The sign-in bridge trades as `did` with the access token `access`.
const trading = (page: Page, did: string, access?: string) =>
  page.route(
    url => bridge.test(url.pathname),
    route => route.fulfill({contentType: "text/javascript", body: standIn(did, access)}),
  )

// Stripe's pages, which the walk never reaches: each sends the person straight back
// to Billing, as Stripe does once they are done there.
const stripe = /^(checkout|billing)\.stripe\.com$/

const fromStripe = (page: Page) =>
  page.route(
    url => stripe.test(url.host),
    route =>
      route.fulfill({status: 303, headers: {location: new URL("/siwa/billing", page.url()).href}}),
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

  test("names their company, adds a practice site, makes and revokes a key, and opens Settings", async ({page, hasTouch}, info) => {
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
    const panel = page.locator("#siwa-new-site")
    await expect(site).toBeVisible()
    await expect(panel).toHaveAttribute("data-kind", "live")
    await tidy(page)

    // The handle follows the name; the walk then gives it one of its own, unique to the width.
    const handle = page.locator("#siwa-site-audience")
    await page.locator("#siwa-site-name").fill("Walk Site")
    await expect(handle).toHaveValue("walk-site")
    await handle.fill(`walk-${info.project.name}`)

    // The New site form takes only an https address; a practice site takes this one.
    const address = page.locator("#siwa-site-origins")
    await address.fill("http://localhost:4000")
    await press(page.locator("#siwa-site-submit"))
    await expect(address).toHaveAttribute("aria-invalid", "true")
    await expect(page.locator("#siwa-site-origins-errors p")).toHaveCount(1)
    await expect(handle).toHaveAttribute("aria-invalid", "false")

    await press(page.locator("#siwa-site-kind"))
    await expect(panel).toHaveAttribute("data-kind", "practice")
    await expect(address).toHaveAttribute("aria-invalid", "false")
    await expect(handle).toHaveValue(`walk-${info.project.name}`)
    await tidy(page)
    await press(page.locator("#siwa-site-submit"))
    await expect(page).toHaveURL(/\/siwa\/sites\/[0-9a-f-]{36}$/)
    await expect(page.locator("#siwa-audience")).toHaveText(`walk-${info.project.name}`)
    await expect(page.locator("#siwa-practice")).toBeVisible()
    await expect(page.locator("#siwa-agent-request")).toContainText(
      `GET http://localhost:4000/ --handle walk-${info.project.name}`,
    )
    await expect(page.locator("#siwa-proof")).toHaveCount(0)

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

    await page.goto("/siwa")
    await connected(page)
    await expect(page.locator("#siwa-period-panel")).toBeVisible()
    await expect(page.locator("#siwa-usage")).toHaveCount(0)
    await expect(page.locator("#siwa-agents-panel")).toHaveCount(0)
    await capRefusedThenSaved(page, press, "50", "$99.00", "250")
    await expect(page.locator("#siwa-cap-amount")).toHaveValue("250.00")
    await removeCap(page, press)
    await expect(page.locator("#siwa-cap-amount")).toHaveValue("")
    await tidy(page)

    // Overview's link to Billing, where the company subscribes on Stripe and comes back.
    await fromStripe(page)
    await press(page.locator("#siwa-period-billing"))
    await expect(page).toHaveURL(/\/siwa\/billing$/)
    const plan = page.locator("#siwa-plan")
    await expect(plan).toHaveAttribute("data-plan", "subscribe")
    await expect(page.locator("#siwa-manage")).toHaveCount(0)
    await expect(page.locator("#siwa-invoices-panel")).toHaveCount(0)
    await tidy(page)

    await throughStripe(page, "checkout.stripe.com", () => press(page.locator("#siwa-subscribe")))
    await expect(plan).toHaveAttribute("data-plan", "active")
    await expect(page.locator("#siwa-subscribe")).toHaveCount(0)
    const invoices = page.locator("#siwa-invoices > li")
    await expect(invoices).toHaveCount(1)
    await expect(invoices.first().locator("a[target='_blank']")).toBeVisible()
    await expect(page.locator("#siwa-invoices-more")).toHaveCount(0)
    await tidy(page)

    await throughStripe(page, "billing.stripe.com", () => press(page.locator("#siwa-manage")))
    await expect(plan).toHaveAttribute("data-plan", "active")
    await expect(invoices).toHaveCount(1)
    await problems.expect()
  })
})

// A press that opens Stripe's `host`, and Billing loaded again once Stripe sends the
// person back.
async function throughStripe(page: Page, host: string, pressed: () => Promise<void>) {
  const left = page.waitForRequest(request => new URL(request.url()).host === host)
  const back = page.waitForEvent("load")
  await pressed()
  await left
  await back
  await expect(page).toHaveURL(/\/siwa\/billing$/)
  await connected(page)
}

// A cap below the least the service takes is refused beside the field, in the
// page's words with the least it takes; one above it is saved.
async function capRefusedThenSaved(
  page: Page,
  press: (target: Locator) => Promise<void>,
  low: string,
  least: string,
  enough: string,
) {
  const amount = page.locator("#siwa-cap-amount")
  const save = page.locator("#siwa-cap-form button[type='submit']")
  await amount.fill(low)
  await press(save)
  await expect(amount).toHaveAttribute("aria-invalid", "true")
  await expect(page.locator("#siwa-cap-amount-errors p")).toHaveText(new RegExp(`at least \\${least}`))
  await amount.fill(enough)
  await press(save)
  await expect(page.locator("#siwa-cap-notice")).toHaveText("Saved.")
  await expect(amount).toHaveAttribute("aria-invalid", "false")
}

async function removeCap(page: Page, press: (target: Locator) => Promise<void>) {
  await press(page.locator("#siwa-cap-remove"))
  const confirm = page.locator("#rg-confirm")
  await expect(confirm).toBeVisible()
  await press(confirm.locator("[data-confirm-accept]"))
  await expect(page.locator("#siwa-cap-notice")).toHaveText("Cap removed.")
  await expect(page.locator("#siwa-cap-remove")).toHaveCount(0)
}

test.describe("a billed SIWA customer", () => {
  test.use({
    storageState: async ({}, use, info) =>
      use(`test/browser/.auth/siwa-billed-${info.project.name}.json`),
  })

  test("reads the period, lists more agents, sets a cap no lower than the fee so far and checks its site's proof", async ({page, hasTouch}, info) => {
    const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
    const problems = watch(page)
    await trading(page, `did:privy:browser-walk-siwa-billed-${info.project.name}`)
    await page.goto("/siwa")
    await connected(page)
    await ready(page)

    // 1,204 agents: 204 past the 1,000 included, each $0.099 on the $99 base.
    await expect(page.locator("#siwa-agents-count")).toHaveText("1,204")
    await expect(page.locator("#siwa-fee")).toHaveText("$119.196")
    await expect(page.locator("#siwa-period")).toHaveText(/^\d{1,2}–\d{1,2} [A-Z][a-z]{2} \d{4}$/)

    const agents = page.locator("#siwa-agents > li")
    await expect(agents).toHaveCount(50)
    await expect(agents.filter({hasText: "Archived site"}).first()).toBeVisible()
    await expect(agents.filter({hasText: "Ethereum"}).first()).toBeVisible()
    await press(page.locator("#siwa-agents-more"))
    await expect(agents).toHaveCount(100)
    await tidy(page)

    await capRefusedThenSaved(page, press, "100", "$119.20", "500")
    await expect(page.locator("#siwa-cap")).toHaveText("$500.00")
    await expect(page.locator("#siwa-usage")).toContainText("Up to 5,050 agents")
    await removeCap(page, press)
    await expect(page.locator("#siwa-cap")).toHaveText("None")
    await tidy(page)

    // The production site is proven. A new origin sets its proof back, and a check
    // then finds no file at its first origin: the walk publishes none.
    await page.goto("/siwa/sites")
    await connected(page)
    await press(page.locator("#siwa-sites > li[id^='siwa-site-'] a"))
    const proof = page.locator("#siwa-proof")
    const files = page.locator("#siwa-proof-files > li")
    await expect(proof).toHaveAttribute("data-state", "verified")
    await expect(page.locator("#siwa-proof-token")).toHaveText(/^siwa_site_[0-9a-f]{32}$/)
    await expect(files).toHaveCount(1)
    await expect(page.locator("#siwa-proof-proven")).toBeVisible()
    await tidy(page)

    await page.locator("#siwa-details-origins").fill("https://example.com\nhttps://www.example.com")
    await press(page.locator("#siwa-details-form button[type='submit']"))
    await expect(proof).toHaveAttribute("data-state", "unverified")
    await expect(files).toHaveCount(2)
    await expect(page.locator("#siwa-proof-proven")).toHaveCount(0)

    await press(page.locator("#siwa-proof-check"))
    await expect(page.locator("#siwa-proof-failure")).toHaveAttribute("data-reason", "not_found")
    await expect(page.locator("#siwa-proof-checked")).toBeVisible()
    await tidy(page)

    // Fifteen months of invoices, twelve to a page, newest first.
    await page.goto("/siwa/billing")
    await connected(page)
    await expect(page.locator("#siwa-plan")).toHaveAttribute("data-plan", "active")
    await expect(page.locator("#siwa-manage")).toBeVisible()
    const invoices = page.locator("#siwa-invoices > li")
    await expect(invoices).toHaveCount(12)
    await expect(invoices.first()).toHaveId(`siwa-invoice-in_walk_${info.project.name}_1`)
    await tidy(page)
    await press(page.locator("#siwa-invoices-more"))
    await expect(invoices).toHaveCount(15)
    await expect(invoices.last()).toHaveId(`siwa-invoice-in_walk_${info.project.name}_15`)
    await expect(page.locator("#siwa-invoices-more")).toHaveCount(0)
    await tidy(page)
    await problems.expect()
  })
})

test.describe("a SIWA customer whose SIWA has billing off", () => {
  test.use({
    storageState: async ({}, use, info) =>
      use(`test/browser/.auth/siwa-billing-off-${info.project.name}.json`),
  })

  test("finds billing unavailable, with nothing to press", async ({page}, info) => {
    const problems = watch(page)
    await trading(page, `did:privy:browser-walk-siwa-billing-off-${info.project.name}`)
    await page.goto("/siwa/billing")
    await connected(page)

    const plan = page.locator("#siwa-plan")
    await expect(plan).toHaveAttribute("data-plan", "off")
    await expect(plan.locator("button")).toHaveCount(0)
    await expect(page.locator("#siwa-invoices-panel")).toHaveCount(0)
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
