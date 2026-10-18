import {expect, test, type Page} from "@playwright/test"
import {keepSignedIn, ready, signedIn, watch} from "./support/person"

// Pairing an agent, the way a person does it: from the Account page or the agent
// guide's link, into the side panel, then choosing their agent.
test.use(signedIn)
test.beforeEach(({context}) => keepSignedIn(context))

const pairing = (page: Page) => page.locator("#shell-pairing")
const message = (page: Page) => page.locator("#shell-pairing-box pre")

// A person presses the agent's picture: the radio's label, whose name only
// screen readers hear.
async function choose(page: Page, agent: string) {
  const radio = pairing(page).getByRole("radio", {name: agent, exact: true})
  await radio.locator("xpath=ancestor::label").click()
  await expect(radio).toBeChecked()
}

test("Pair New Agent on the Account page opens the pairing box", async ({page}) => {
  const problems = watch(page)
  await page.goto("/account")
  await ready(page)
  await page.locator("#account-agents").getByRole("button", {name: "Pair New Agent"}).click()
  await expect(pairing(page)).toBeInViewport()
  await problems.expect()
})

test("the agent guide's link lands on the pairing box", async ({page}) => {
  await page.goto("/account#shell-pairing")
  await expect(pairing(page)).toBeInViewport()
})

test("choosing an agent gives a message with a code, and each choice a new code", async ({page}) => {
  const problems = watch(page)
  await page.goto("/account")
  await ready(page)
  await page.locator("#account-agents").getByRole("button", {name: "Pair New Agent"}).click()
  await expect(message(page)).toHaveCount(0)

  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  const first = await message(page).innerText()

  await choose(page, "Hermes")
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  await problems.expect()
})
