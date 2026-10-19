import type {Locator} from "@playwright/test"
import {expect, test} from "./support/test"
import {bareAddresses} from "./support/addresses"
import {watch} from "./support/person"

// The on-chain lab's account links wallets A and B. With wallet C open in the lab's
// wallet app, the note beside the buttons names C, then A and B, each opening and
// copying its full address, and nothing on the page shows an address without one.
test.use({permissions: ["clipboard-read", "clipboard-write"]})

const walletC = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"

test("a wallet note opens and copies each wallet it names", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/showcase/onchain")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await press(page.locator('[data-lab-wallet="C"]'))

  const note = page.locator(".onchain-example-note").filter({hasText: "isn't linked to this account"})
  // The words run straight on from each address, with no space before the comma.
  expect(await note.evaluate(element => [...element.querySelector("span")!.childNodes].filter(node => node.nodeType !== Node.COMMENT_NODE).map(node =>
    node instanceof HTMLElement ? node.querySelector("button")!.textContent!.trim() : node.textContent,
  ))).toEqual([
    "Your wallet is on ",
    "0x3c44..93bc",
    ", which isn't linked to this account. Switch to ",
    "0xf39f..2266",
    " or ",
    "0x7099..79c8",
    ".",
  ])
  await expect(note.getByRole("button", {name: "Copy the full address"})).toHaveCount(3)

  await press(note.getByRole("button", {name: "0x3c44..93bc", exact: true}))
  await expect(note.getByText(walletC, {exact: true})).toBeVisible()
  await page.keyboard.press("Escape")

  const copy = note.getByRole("button", {name: "Copy the full address"}).first()
  await press(copy)
  await expect(copy).toHaveAttribute("data-copy-state", "copied")
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(walletC)

  expect(await bareAddresses(page)).toEqual([])
  await problems.expect()
})
