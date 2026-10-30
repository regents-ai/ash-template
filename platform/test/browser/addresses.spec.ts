import type {Locator} from "@playwright/test"
import {expect, test} from "./support/test"
import {bareAddresses} from "./support/addresses"
import {copiesShown, recordCopies} from "./support/copies"
import {watch} from "./support/person"

// The on-chain lab's account links wallets A and B. With wallet C open in the lab's
// wallet app, C is ignored: nothing on the page asks the person to switch, and a press
// sends nothing and names A and B, each opening and copying its full address. Nothing
// on the page shows an address without one.
test.use({permissions: ["clipboard-read", "clipboard-write"]})

const walletA = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"

test("a wallet note opens and copies each wallet it names", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await recordCopies(page)
  await page.goto("/showcase/onchain")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await press(page.locator('[data-lab-wallet="C"]'))
  await expect(page.locator("#onchain-example")).not.toContainText("0x3c44..93bc")
  await expect(page.getByText("isn't linked", {exact: false})).toHaveCount(0)

  await press(page.locator("#onchain-example").getByRole("button", {name: "Record"}))
  const note = page.locator(".onchain-example-note").filter({hasText: "in your wallet app"})
  // The words run straight on from each address, with no space before the full stop.
  expect(await note.evaluate(element => [...element.querySelector("span")!.childNodes].filter(node => node.nodeType !== Node.COMMENT_NODE).map(node =>
    node instanceof HTMLElement ? node.querySelector("button")!.textContent!.trim() : node.textContent,
  ))).toEqual([
    "You're signed in with ",
    "0xf39f..2266",
    " and ",
    "0x7099..79c8",
    ". Open ",
    "0xf39f..2266",
    " or ",
    "0x7099..79c8",
    " in your wallet app, then press again. Nothing was sent.",
  ])
  await expect(note.getByRole("button", {name: "Copy the full address"})).toHaveCount(4)

  await press(note.getByRole("button", {name: "0xf39f..2266", exact: true}).first())
  await expect(note.getByText(walletA, {exact: true}).first()).toBeVisible()
  await page.keyboard.press("Escape")

  const copy = note.getByRole("button", {name: "Copy the full address"}).first()
  await press(copy)
  await expect.poll(() => copiesShown(copy)).toEqual([{answer: "copied", shown: "", said: "Copied"}])
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(walletA)

  expect(await bareAddresses(page)).toEqual([])
  await problems.expect()
})
