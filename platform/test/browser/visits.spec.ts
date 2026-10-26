import {randomUUID} from "node:crypto"
import {existsSync, readFileSync} from "node:fs"
import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// A visit can be told again from its lines alone (AshTemplateWeb.VisitLog). The
// walk's person opens Notes and saves a note, and the lines the server wrote for
// that visit (config/runtime.exs) say so in order: the request, the page, the note
// the site created and the press that asked for it. Every line carries the same
// visit and the same one-way code for the person, holds only the visit fields, and
// holds nothing the person wrote.
test.use(signedIn)

type Line = {
  time: string
  severity: string
  message: string
  metadata: {
    visit?: string
    actor?: string
    surface?: string
    request_id?: string
    event?: {name: string; where: string; outcome?: string; ms?: number}
  }
}

// The walk's person (test/browser/support/sign_in.exs).
const wallet = `0x${"b".repeat(40)}`
const embedded = `0x${"9".repeat(40)}`

const fields = ["actor", "event", "request_id", "surface", "visit"]

function lines(visit: string): Line[] {
  const file = "tmp/walk-lines.jsonl"
  if (!existsSync(file)) return []
  return readFileSync(file, "utf8")
    .split("\n")
    .filter(text => text.includes(visit))
    .map(text => JSON.parse(text) as Line)
    .filter(line => line.metadata.visit === visit && line.metadata.event)
}

const step = (line: Line) => `${line.metadata.event!.name} ${line.metadata.event!.where}`

test("opening Notes and saving a note replays in order from the visit's lines", async ({page, context}, info) => {
  const problems = watch(page)
  const title = `Replay ${info.project.name} ${randomUUID().slice(0, 8)}`
  const body = `Plant the pines on the ${info.project.name} walk.`

  await page.goto("/notes")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.locator("#note-title").fill(title)
  await page.locator("#note-body").fill(body)
  await page.locator("#note-form").getByRole("button", {name: "Add note"}).click()
  await expect(page.locator("#notes-list").getByText(title)).toBeVisible()

  const visit = (await context.cookies()).find(cookie => cookie.name === "_visit")!.value
  await expect.poll(() => lines(visit).map(step)).toContain("press NotesLive:save")
  const told = lines(visit)
  const steps = told.map(step)

  expect(steps[0]).toBe("request /notes")
  const order = ["request /notes", "page /notes", "action note.create", "press NotesLive:save"].map(wanted =>
    steps.indexOf(wanted),
  )
  expect(order.every(index => index >= 0)).toBe(true)
  expect([...order].sort((a, b) => a - b)).toEqual(order)
  expect(told.find(line => step(line) === "press NotesLive:save")!.metadata.event!.outcome).toBe("ok")

  const actors = [...new Set(told.map(line => line.metadata.actor))]
  expect(actors).toHaveLength(1)
  expect(actors[0]).toMatch(/^person:[0-9a-f]{16}$/)

  for (const line of told) {
    expect(Object.keys(line).sort()).toEqual(["message", "metadata", "severity", "time"])
    expect(Object.keys(line.metadata).every(key => fields.includes(key))).toBe(true)
    expect(Object.keys(line.metadata.event!).every(key => ["name", "where", "outcome", "ms"].includes(key))).toBe(true)
    const text = JSON.stringify(line)
    for (const written of [title, body, wallet, embedded, "did:privy"]) expect(text).not.toContain(written)
  }
  await problems.expect()
})

// A page's own script reading the API joins its visit: the agent tools list on the
// home page reads each site's tools without cookies, and the reads are the visit's.
test("the agent tools list's reads belong to the page's visit", async ({page, context, hasTouch}) => {
  await page.goto("/")
  const button = page.locator("#home-agent-tools-button")
  await (hasTouch ? button.tap() : button.click())
  await expect(page.getByRole("dialog", {name: /^Agents see/})).toBeVisible()

  const visit = (await context.cookies()).find(cookie => cookie.name === "_visit")!.value
  await expect.poll(() => lines(visit).map(step)).toContain("tool.call /api/v1/sites/:site/tools")
  const read = lines(visit).find(line => step(line) === "tool.call /api/v1/sites/:site/tools")!
  expect(read.metadata.surface).toBe("page")
})
