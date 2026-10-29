import {execFile} from "node:child_process"
import {readFileSync} from "node:fs"
import {promisify} from "node:util"
import {type Page, expect, test} from "@playwright/test"

// The live site, read as an agent's browser reads it (skills/regent-workflow, "Live
// checks"). The pages are the signed-out ones, and the tools called are this
// checkout's read-only tools that take no input. The only row the check writes is the
// agent's own: the site records when the agent was last seen, adding the row the
// first time.
//
// A stand-in document.modelContext holds what the page registers, as
// test/browser/page_tools.spec.ts does locally, so the check reads exactly the page's
// own tools. window.regentsSign plays the agent's browser host: from the page's own
// frame, it signs with the agent's key (SIWA_AGENT_HOME, through the SIWA client
// SIWA_CLIENT) only the one request this checkout's manifest says the tool being
// called makes.
const client = process.env.SIWA_CLIENT
const checkout = process.env.CHECKOUT_COMMIT
if (!process.env.SIWA_AGENT_HOME || !client || !checkout)
  throw new Error("Set SIWA_AGENT_HOME, SIWA_CLIENT and CHECKOUT_COMMIT. Run it through make live-check.")

const run = promisify(execFile)

type Page_ = {route: string; paths?: string[]; check: string; status?: number; signed_in?: boolean; local_only?: boolean}
type Document_ = {route: string; paths?: string[]; type: string}
const read = (path: string) => JSON.parse(readFileSync(new URL(path, import.meta.url), "utf8"))
const map: {pages: Page_[]; documents: Document_[]} = read("../browser/pages.json")
type Entry = {
  name: string
  route: string
  scope: string
  authentication: string
  annotations: {readOnlyHint?: boolean}
  input_schema: {required: string[]}
}
const manifest: {audience: string; tools: Entry[]} = read("../../priv/tool_manifest.json")
// The reads the home page offers that take no input, and the one request each makes.
const reads = new Map(
  manifest.tools
    .filter(tool => tool.scope === "site" && tool.annotations.readOnlyHint && !tool.input_schema.required.length)
    .map(tool => [tool.name, tool]),
)

const each = <T extends {route: string; paths?: string[]}>(entry: T) =>
  (entry.paths ?? [entry.route]).map(path => ({...entry, path}))

// Every signed-out page the walk opens, at its own address, except the labs that
// answer only on a developer's machine.
const pages = map.pages.filter(page => !page.signed_in && !page.local_only).flatMap(each)
const documents = map.documents.flatMap(each)

const withPageTools = `
  const held = new Map()
  Object.defineProperty(document, "modelContext", {value: {
    registerTool: async (tool, {signal}) => {
      held.set(tool.name, tool)
      signal.addEventListener("abort", () => held.delete(tool.name))
    },
    getTools: async () => [...held.values()],
  }})
  window.pageTools = held
`

type Prepared = {operation: string; audience: string; origin: string; method: string; path: string; body?: string}
type Reply = {ok: boolean; status?: number; data?: unknown; error?: {code: string; message: string}}
type Tool = {name: string; annotations?: {readOnlyHint?: boolean}; inputSchema?: {required?: string[]}}

// The one request a signed read makes: the live site, this site's audience, the
// manifest's method and address, and no body for a GET or an empty object for a POST.
function expected(prepared: Prepared, tool: Entry, origin: string) {
  const [method] = tool.route.split(" ")
  return (
    tool.authentication === "siwa_per_request" &&
    prepared.operation === tool.name &&
    prepared.origin === origin &&
    prepared.audience === manifest.audience &&
    `${prepared.method} ${prepared.path}` === tool.route &&
    prepared.body === (method === "GET" ? undefined : "{}")
  )
}

// Watches one page for script errors and the site's own failed answers.
function watch(page: Page, allowedStatus: number) {
  const site = new URL(test.info().project.use.baseURL!).host
  const problems: string[] = []
  page.on("pageerror", error => problems.push(`page error: ${error.message}`))
  page.on("response", response => {
    const url = new URL(response.url())
    if (url.host === site && response.status() >= 400 && response.status() !== allowedStatus)
      problems.push(`${response.status()} ${response.request().method()} ${url.pathname}`)
  })
  return problems
}

test("the site answers and names the commit it runs", async ({page}) => {
  const health = await page.goto("/healthz")
  expect(health?.status()).toBe(200)
  expect((await health!.text()).trim()).toBe("ok")

  const capabilities = await page.goto("/capabilities.json")
  expect(capabilities?.status()).toBe(200)
  const {build} = (await capabilities!.json()) as {build: {commit: string; release: string}}
  console.log(`live commit ${build.commit}, release ${build.release}`)
  // The pages and tools are checked against this checkout's page map and manifest.
  expect(build.commit, "Run the live check from a checkout of the live commit.").toBe(checkout)
})

for (const {path, type} of documents) {
  test(`${path} answers as ${type}`, async ({page}) => {
    const answer = await page.request.get(path)
    expect(answer.status()).toBe(200)
    expect(answer.headers()["content-type"]).toContain(type)
  })
}

for (const {path, check, status} of pages) {
  test(`${path} opens and fits the screen`, async ({page}) => {
    const problems = watch(page, status ?? 200)
    const answer = await page.goto(path)
    expect(answer?.status()).toBe(status ?? 200)
    await expect(page.locator(check).first()).toBeVisible()
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    if (overflow > 0) problems.push(`content is ${overflow}px wider than the screen`)
    expect(problems).toEqual([])
  })
}

// The tools are the same at every width, so they are called once, from the desktop.
test("the home page's WebMCP tools answer every read, public and signed", async ({page}, info) => {
  test.skip(info.project.name !== "desktop", "The tools are called once, from the desktop.")
  // Each signed read starts the SIWA client once, one after another, about a second each.
  test.setTimeout(120_000)
  let calling: Entry | undefined
  const origin = new URL(info.project.use.baseURL!).origin

  await page.exposeBinding("regentsSign", async ({frame}, prepared: Prepared) => {
    if (frame !== page.mainFrame() || !calling || !expected(prepared, calling, origin))
      return {error: {code: "call_mismatch", message: "The live check signs only the read it is making."}}
    const args = ["run", "--quiet", client, "headers", prepared.method, `${prepared.origin}${prepared.path}`]
    if (prepared.body !== undefined) args.push("--body", prepared.body)
    // The page answers signer_unavailable when this throws; the client's own words go here.
    const {stdout} = await run("uv", args).catch((error: {stderr?: string; message: string}) => {
      console.error(`The SIWA client could not sign ${prepared.method} ${prepared.path}: ${error.stderr || error.message}`)
      throw error
    })
    return {headers: JSON.parse(stdout) as Record<string, string>}
  })
  await page.addInitScript(withPageTools)
  await page.goto("/")
  await expect(page.locator("html[data-webmcp-status='connected']")).toBeAttached()

  const tools: Tool[] = await page.evaluate(() =>
    [...(window as unknown as {pageTools: Map<string, Tool>}).pageTools.values()].map(
      ({name, annotations, inputSchema}) => ({name, annotations, inputSchema}),
    ),
  )
  // The live page offers the same reads this checkout does, no more and no fewer.
  const offered = tools.filter(tool => tool.annotations?.readOnlyHint && !tool.inputSchema?.required?.length)
  expect(offered.map(tool => tool.name).sort()).toEqual([...reads.keys()].sort())

  const answers: Record<string, string> = {}
  for (const tool of reads.values()) {
    calling = tool
    const reply: Reply = await page.evaluate(
      name => (window as unknown as {pageTools: Map<string, {execute: Function}>}).pageTools.get(name)!.execute({}, {}),
      tool.name,
    )
    answers[tool.name] = reply.ok ? `${reply.status}` : `${reply.status ?? "-"} ${reply.error?.code}`
  }
  console.log(`WebMCP: ${tools.length} tools registered, ${reads.size} reads called`)
  console.log(JSON.stringify(answers))
  expect(Object.entries(answers).filter(([, answer]) => !answer.startsWith("2"))).toEqual([])

  calling = reads.get("agents_whoami")
  const whoami: Reply = await page.evaluate(
    () => (window as unknown as {pageTools: Map<string, {execute: Function}>}).pageTools.get("agents_whoami")!.execute({}, {}),
  )
  const {data} = whoami.data as {data: {status: string; agent: {wallet: string}}}
  console.log(`agent ${data.agent.wallet}: ${data.status}`)
  expect(data.status).toBe("paired")
})
