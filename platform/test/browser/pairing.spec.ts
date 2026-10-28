import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// Pairing an agent, the way a person does it: from the Account page or the agent
// guide's link, into the side panel, then choosing their agent.
test.use(signedIn)

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

// Keyfleet, 27 Oct 2026: with the panel already open and scrolled away from the
// pairing box, the button did nothing a person could see.
test("Pair New Agent with the panel already open moves to the agent choice", async ({page, isMobile}) => {
  test.skip(isMobile, "on a phone the open panel covers the page, so its button can't be pressed")
  const problems = watch(page)
  await page.goto("/account")
  await ready(page)
  const button = page.locator("#account-agents").getByRole("button", {name: "Pair New Agent"})
  const firstAgent = pairing(page).getByRole("radio").first()
  const picture = firstAgent.locator("xpath=ancestor::label")
  await button.click()
  // A short panel, the way a small screen or a long agents list leaves it.
  await page.locator("#shell-aside").evaluate(aside => {
    aside.style.maxBlockSize = "5rem"
    aside.scrollTop = 0
  })
  await expect(picture).not.toBeInViewport()
  await button.click()
  await expect(firstAgent).toBeFocused()
  await expect(picture).toBeInViewport()
  await problems.expect()
})

test("the agent guide's link lands on the pairing box", async ({page}) => {
  await page.goto("/account#shell-pairing")
  await expect(pairing(page)).toBeInViewport()
})

test("each agent keeps its own code until a new one is asked for", async ({page}) => {
  const problems = watch(page)
  await page.goto("/account")
  await ready(page)
  await page.locator("#account-agents").getByRole("button", {name: "Pair New Agent"}).click()
  await expect(message(page)).toHaveCount(0)

  await choose(page, "Dots")
  // The agent learns it pairs with the person's Regents Labs account, and on which site.
  await expect(message(page)).toContainText(/^Pair with my Regents Labs account on localhost\n/)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  const first = await message(page).innerText()

  await choose(page, "Hermes")
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)

  // Coming back shows the same code, so a message already pasted still works.
  await choose(page, "Dots")
  await expect(message(page)).toHaveText(first)

  await pairing(page).getByRole("button", {name: "Make a new code"}).click()
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  await problems.expect()
})

// A reconnecting page sends the pairing form back with no agent picked, and a
// submit can come before a choice. Neither may crash the side panel (Sentinel,
// 23 Oct 2026, from Patchbay's error mail).
test("the pairing form with nothing chosen leaves the box as it is", async ({page}) => {
  const problems = watch(page)
  const crashes: string[] = []
  page.on("websocket", socket =>
    socket.on("framereceived", frame => {
      if (String(frame.payload).includes('"phx_error"')) crashes.push(String(frame.payload).slice(0, 120))
    }),
  )
  await page.goto("/account")
  await ready(page)
  await page.locator("#account-agents").getByRole("button", {name: "Pair New Agent"}).click()
  const form = page.locator("form#shell-pairing-box")
  await expect(form.getByRole("radio", {checked: true})).toHaveCount(0)

  await form.getByRole("radio").first().dispatchEvent("input")
  await form.evaluate(element => (element as HTMLFormElement).requestSubmit())

  // The box still answers: choosing an agent shows its code.
  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  expect(crashes).toEqual([])
  await problems.expect()
})
