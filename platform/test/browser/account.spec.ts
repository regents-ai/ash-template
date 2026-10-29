import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// /account is the same on every Regent site (AshTemplateWeb.AccountLive). A person
// moves through its five tabs with the tab row, in order, without the page
// reloading; each tab is marked as the current one and shows its own content, and
// the page fits the screen, in each theme, at 1280 wide and on the phone at 390
// and 320.
test.use(signedIn)

const tabs = [
  {label: "Account", path: "/account", check: "#account-agents"},
  {label: "Points", path: "/account/points", check: "#points-earn"},
  {label: "Credits", path: "/account/credits", check: "#credits-history"},
  {label: "Wallets", path: "/account/wallets", check: "#account-embedded-wallet-copy"},
  {label: "Connections", path: "/account/connections", check: "#account-verified-connections"},
]

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({colorScheme})

    test("the tab row moves through every Account tab in place", async ({page, isMobile, hasTouch}, testInfo) => {
      for (const width of isMobile ? [390, 320] : [1280]) {
        await page.setViewportSize({width, height: 900})
        const problems = watch(page)
        await page.goto("/account")
        await ready(page)
        const row = page.locator("#shell-tabs")
        await expect(row.getByRole("link")).toHaveText(tabs.map(tab => tab.label))
        await page.evaluate(() => ((window as unknown as {accountVisit: string}).accountVisit = "same"))

        for (const tab of tabs) {
          const link = row.getByRole("link", {name: tab.label})
          await (hasTouch ? link.tap() : link.click())
          await expect(page).toHaveURL(tab.path)
          await expect(link).toHaveAttribute("aria-current", "page")
          await expect(page.locator(tab.check).first()).toBeVisible()
          await page.screenshot({path: testInfo.outputPath(`${width}-${tab.label.toLowerCase()}.png`), fullPage: true})
        }

        expect(await page.evaluate(() => (window as unknown as {accountVisit?: string}).accountVisit)).toBe("same")
        await problems.expect()
      }
    })
  })
}
