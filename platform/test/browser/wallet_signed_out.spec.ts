import {expect, test} from "./support/test"
import {watch} from "./support/person"

// Signed out, a wallet button is a sign-in control: pressing it opens sign-in and
// says nothing about wallets, since there is no wallet to reach yet. (Signed in,
// the same buttons carry no sign-in mark and every press goes to the wallet.)
test("signed out, pressing a wallet button asks for sign-in and shows no wallet note", async ({page, hasTouch}) => {
  const problems = watch(page)
  await page.goto("/showcase/wallet")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const example = page.locator("#onchain-example")
  const buttons = example.locator("[data-onchain-step]")
  await expect(buttons).toHaveCount(3)
  for (const button of await buttons.all()) {
    await expect(button).toHaveAttribute("data-account-target", "sign-in")
    await expect(button).toBeEnabled()
  }

  const record = example.locator("[data-onchain-step='record']")
  await (hasTouch ? record.tap() : record.click())

  // The press is not held as a wallet press, and no line about wallets appears.
  await expect(record).not.toHaveAttribute("data-awaiting-wallet", "true")
  await expect(example.locator("#onchain-example-press-note")).toHaveCount(0)
  await expect(example.locator("[data-onchain-lost]")).toBeHidden()
  await expect(example.locator("[data-onchain-unreported]")).toBeHidden()
  await problems.expect()
})
