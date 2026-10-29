import type {Locator} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, resting, signedIn, watch} from "./support/person"

// The walk's person has three agents, paired by sign_in.exs. Walk Agent's window, opened from
// the Agents page, says who it is and shows its short address, which opens the
// full address on a press, gives the press back to the address when Escape closes
// it, and copies the full address from its icon. On the touch phone each of the
// address's two targets is at least 44 pixels tall once the window rests.
test.use({...signedIn, permissions: ["clipboard-read", "clipboard-write"]})

const wallet = `0x${"c".repeat(40)}`

test("an agent's window opens its full address and copies it", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/account/agents")
  await ready(page)
  await press(page.getByRole("button", {name: "See Walk Agent’s actions"}))

  const agentWindow = page.getByRole("dialog", {name: "Walk Agent"})
  await expect(agentWindow).toBeVisible()
  await resting(agentWindow)
  const address = agentWindow.getByRole("button", {name: "0xcccc..cccc", exact: true})
  const copy = agentWindow.getByRole("button", {name: "Copy the full address"})
  const full = agentWindow.getByText(wallet, {exact: true})

  if (hasTouch)
    for (const target of [address, copy])
      expect((await target.boundingBox())?.height).toBeGreaterThanOrEqual(44)

  await expect(full).toBeHidden()
  await press(address)
  await expect(full).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(full).toBeHidden()
  await expect(address).toBeFocused()
  await expect(agentWindow).toBeVisible()

  await press(copy)
  await expect(copy).toHaveAttribute("data-copy-state", "copied")
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(wallet)
  await problems.expect()
})

// Found on 21 Oct (Codex handoff): the Account page's list named each agent but not its
// wallet, so two agents with one name read alike. Each row names its own wallet beside
// the name: its short form opens the full address on a press and its icon copies it,
// and the row still fits on one line at both widths, beside an 80-letter name's page.
test("each agent on the Agents page names its own wallet", async ({page, hasTouch}) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  await page.goto("/account/agents")
  await ready(page)

  const list = page.locator("#account-agents")
  for (const [name, digit] of [["Walk Agent", "c"], ["Spare Agent", "f"]]) {
    const row = list.getByRole("listitem").filter({hasText: name})
    const address = row.getByRole("button", {name: `0x${digit.repeat(4)}..${digit.repeat(4)}`, exact: true})
    const full = row.getByText(`0x${digit.repeat(40)}`, {exact: true})
    await expect(address).toBeVisible()
    if (hasTouch) expect((await address.boundingBox())?.height).toBeGreaterThanOrEqual(44)

    await expect(full).toBeHidden()
    await press(address)
    await expect(full).toBeVisible()
    await page.keyboard.press("Escape")
    await expect(full).toBeHidden()

    const copy = row.getByRole("button", {name: "Copy the full address"})
    await press(copy)
    await expect(copy).toHaveAttribute("data-copy-state", "copied")
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(`0x${digit.repeat(40)}`)

    const line = row.locator(".rg-account__agent")
    expect(await line.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    await expect(row.getByText("Last check-in")).toBeVisible()
  }
  await problems.expect()
})

// Each width renames its own agent, so the two never meet. A name with a hidden
// character is refused beside the field and the agent keeps its name; a name with an
// emoji joined by a zero-width joiner saves, and the window and the list show it.
test("an agent's window renames it", async ({page, hasTouch}, testInfo) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  const agent = testInfo.project.name === "phone" ? "Phone Agent" : "Desktop Agent"
  const renamed = `Ada 👩\u200D💻 ${testInfo.project.name}`
  await page.goto("/account/agents")
  await ready(page)
  await press(page.getByRole("button", {name: `See ${agent}’s actions`}))

  const agentWindow = page.getByRole("dialog", {name: agent})
  const name = agentWindow.getByRole("textbox", {name: "Name"})
  const save = agentWindow.getByRole("button", {name: "Save", exact: true})
  await expect(name).toHaveValue(agent)
  await expect(agentWindow.getByText("Only you see this name.")).toBeVisible()
  await resting(agentWindow)
  if (hasTouch)
    for (const target of [name, save])
      expect((await target.boundingBox())?.height).toBeGreaterThanOrEqual(44)

  await name.fill("Ada\u202Egnp.exe")
  await press(save)
  await expect(agentWindow.getByRole("alert")).toHaveText(
    "That name can’t be used. Use 1 to 80 characters with no hidden characters.",
  )
  await expect(name).toHaveAttribute("aria-invalid", "true")
  await expect(agentWindow).toBeVisible()

  await name.fill(renamed)
  await press(save)
  const renamedWindow = page.getByRole("dialog", {name: renamed})
  await expect(
    renamedWindow.getByText(`Saved. This agent is now called ${renamed} on every Regent site.`),
  ).toBeVisible()
  await expect(renamedWindow.getByRole("alert")).toHaveCount(0)
  await expect(page.getByRole("button", {name: `See ${renamed}’s actions`})).toBeAttached()
  await problems.expect()
})
