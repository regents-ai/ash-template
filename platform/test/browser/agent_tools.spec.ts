import {expect, test} from "./support/test"

// The walk's server answers every site's tools from the fixed lists in
// AshTemplate.WalkOffline: three tools for each site, named after its address.
// Patchbay's card lists all three; the others list the two for their home page.
const sites = ["regents.sh", "patchbay.help", "techtree.sh", "autolaunch.sh", "keyfleet.ai"]

test.use({permissions: ["clipboard-read", "clipboard-write"]})

// Sean, 19 Oct (regents.sh) and 21 Oct (this homepage tracks regents.sh's): the
// Agent Tools window copies every Regent site's tools at once, each site its own
// section, then how an agent signs in.
test("the tools window copies every site's tools", async ({page}) => {
  // The page's live connection waits until the window is open, so it is opened
  // before the page connects, as an early press would, and must stay open
  // through the connection.
  let opened = () => {}
  const open = new Promise<void>(resolve => (opened = resolve))
  await page.routeWebSocket(/\/live\/websocket/, async socket => {
    await open
    socket.connectToServer()
  })
  await page.goto("/")

  await page.locator("#home-agent-tools-button").click()
  const dialog = page.getByRole("dialog", {name: /^\d+ Agent Tools$/})
  await expect(dialog).toBeVisible()
  opened()
  await page.locator(".phx-connected").first().waitFor()
  await expect(dialog).toBeVisible()
  const copyAll = dialog.locator("#home-agent-tools-copy-all")
  await expect(copyAll).toHaveAccessibleName("Copy every site's tools")
  await expect(copyAll).toBeEnabled()
  await expect(dialog.locator("[data-agent-tools-note]")).toHaveText("11 tools from 5 sites")

  await copyAll.click()
  // The button answers "Copied" in place of its words.
  await expect(copyAll).toHaveAccessibleName("Copied")
  const text = await page.evaluate(() => navigator.clipboard.readText())
  expect(text.startsWith("# WebMCP tools on every Regent site\n\n## regents.sh\n\n2 WebMCP tools\n")).toBe(true)
  const headings = [...text.matchAll(/^## (.+)$/gm)].map(match => match[1])
  expect(headings).toEqual([...sites, "siwa-server"])
  for (const site of sites) expect(text).toContain(`\`browse_${site.replace(".", "_")}\``)
  expect(text).toContain("`post_patchbay_help`")
  expect(text).toContain("### Install")

  // The copy of the window's own list stays beside it.
  await expect(dialog.getByRole("button", {name: "Copy as Markdown"})).toBeVisible()
})
