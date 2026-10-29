import type {Page, Request} from "@playwright/test"
import manifest from "../../priv/tool_manifest.json" with {type: "json"}
import {expect, test} from "./support/test"

// The page's browser tools as an agent's browser host sees them. Chromium here has
// no WebMCP, so a stand-in document.modelContext holds what the page registers; a
// stand-in window.regentsSign plays the agent's signer (regents browser in use).
// A signed tool takes only its input: the host signs the exact request the page
// built, and the page sends those bytes, or nothing at all.
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

// A signed tool sends only from the site's own address (its agent-request-origin),
// which is localhost in development; the rest of the walk opens 127.0.0.1.
test.use({baseURL: `http://localhost:${process.env.ASH_TEMPLATE_WALK_PORT}`})

type Signer = "none" | "signs" | "refuses"

const proof = {
  "x-siwa-signature": "sig1=:c2ln:",
  "x-siwa-signature-input": "sig1=(\"@method\");created=1",
  "x-siwa-receipt": "receipt",
  "x-key-id": "0x2222222222222222222222222222222222222222",
  "x-timestamp": "1",
  "x-agent-wallet-address": "0x2222222222222222222222222222222222222222",
  "x-agent-chain-id": "8453",
  "content-digest": "sha-256=:ZGlnZXN0:",
}

async function open(page: Page, signer: Signer) {
  await page.addInitScript(withPageTools)
  await page.addInitScript(([signer, proof]) => {
    const asked: unknown[] = []
    ;(window as unknown as {signerAsked: unknown[]}).signerAsked = asked
    if (signer === "signs") {
      Object.assign(window, {regentsSign: async (request: unknown) => (asked.push(request), {headers: proof})})
    } else if (signer === "refuses") {
      Object.assign(window, {regentsSign: async (request: unknown) => (asked.push(request), {
        error: {code: "call_mismatch", message: "This is not the call your agent made.", hint: "Call the tool again."},
      })})
    }
  }, [signer, proof] as const)
  await page.goto("/")
  await expect(page.locator("html[data-webmcp-status='connected']")).toBeAttached()
}

const call = (page: Page, name: string, input: unknown) =>
  page.evaluate(([name, input]) => {
    const tools = (window as unknown as {pageTools: Map<string, {execute: Function}>}).pageTools
    return tools.get(name)!.execute(input, {})
  }, [name, input] as const)

const toApi = (page: Page) => {
  const sent: Request[] = []
  page.on("request", request => { if (new URL(request.url()).pathname.startsWith("/api/")) sent.push(request) })
  return sent
}

const post = {room: "general", body: "Hello from the page", operation_id: "6f1c1f43-4b8a-4d3b-9d2f-0c6a2b7e9a10"}

test("a signed tool lists only its own input", async ({page}) => {
  await open(page, "none")
  const tools = await page.evaluate(() =>
    [...(window as unknown as {pageTools: Map<string, {name: string; inputSchema: {properties: object}}>}).pageTools.values()]
      .map(tool => ({name: tool.name, fields: Object.keys(tool.inputSchema.properties).sort()})))
  expect(tools.find(tool => tool.name === "rooms_post")!.fields).toEqual(["body", "operation_id", "room"])
})

test("with no agent signer a signed tool sends nothing and says how to get one", async ({page}) => {
  await open(page, "none")
  const sent = toApi(page)
  const answer = await call(page, "rooms_post", post)
  expect(answer).toMatchObject({error: {code: "agent_auth_required"}})
  expect((answer as {error: {hint: string}}).error.hint).toContain("regents browser --site ash-template")
  expect(sent).toEqual([])
})

test("a signer's refusal is the tool's answer, and nothing is sent", async ({page}) => {
  await open(page, "refuses")
  const sent = toApi(page)
  const answer = await call(page, "rooms_post", post)
  expect(answer).toEqual({error: {code: "call_mismatch", message: "This is not the call your agent made.", hint: "Call the tool again."}})
  expect(sent).toEqual([])
})

test("the page sends exactly the request the signer signed, with its proof and no cookie", async ({page, baseURL}) => {
  await open(page, "signs")
  const sent = toApi(page)
  await call(page, "rooms_post", post)

  const asked = await page.evaluate(() => (window as unknown as {signerAsked: Array<Record<string, string>>}).signerAsked)
  expect(asked).toHaveLength(1)
  const [signed] = asked
  expect(signed).toMatchObject({operation: "rooms_post", audience: "ash-template", origin: new URL(baseURL!).origin, method: "POST", path: "/api/v1/rooms/general/messages"})
  expect(JSON.parse(signed.body)).toEqual({body: post.body, operation_id: post.operation_id})

  expect(sent).toHaveLength(1)
  const [request] = sent
  expect(request.method()).toBe("POST")
  expect(new URL(request.url()).pathname).toBe(signed.path)
  expect(request.postData()).toBe(signed.body)
  const headers = await request.allHeaders()
  for (const [name, value] of Object.entries(proof)) expect(headers[name]).toBe(value)
  expect(headers.cookie).toBeUndefined()

  // An input the tool does not take is refused before the signer is asked.
  const refused = await call(page, "rooms_post", {...post, colour: "blue"})
  expect(refused).toMatchObject({error: {code: "invalid_request"}})
  expect(await page.evaluate(() => (window as unknown as {signerAsked: unknown[]}).signerAsked.length)).toBe(1)
  expect(sent).toHaveLength(1)
})

type Public = {name: string; route: string; authentication: string; refusals: Record<string, unknown>}
const reads = (manifest.tools as unknown as Public[]).filter(tool => tool.authentication === "public")

// What each public read asks the site for: the tool's input, and the same read over HTTP.
function asks(id: string): Record<string, [Record<string, unknown>, string]> {
  const missing = "0f4c2b9e-3c6a-4f7e-9a51-2a7b8c9d0e1f"
  return {
    health: [{}, "/api/v1/health"],
    about: [{}, "/api/v1/about"],
    docs: [{}, "/api/v1/docs"],
    sites_tools: [{site: "regents"}, "/api/v1/sites/regents/tools"],
    siwa_help: [{}, "/api/v1/siwa/help"],
    rooms_list: [{}, "/api/v1/rooms"],
    rooms_messages: [{room: "general", limit: 2}, "/api/v1/rooms/general/messages?limit=2"],
    rooms_message: [{room: "general", id}, `/api/v1/rooms/general/messages/${id}`],
    agents_get: [{id: missing}, `/api/v1/agents/${missing}`],
    polls_list: [{}, "/api/v1/polls"],
    polls_show: [{poll: missing}, `/api/v1/polls/${missing}`],
  }
}

test("every public read answers exactly as its HTTP read, from its manifest route", async ({page}) => {
  await open(page, "none")
  const sent = toApi(page)
  const posted = await page.request.get("/api/v1/rooms/general/messages?limit=1").then(response => response.json())
  const examples = asks(posted.messages[0]?.id ?? "0f4c2b9e-3c6a-4f7e-9a51-2a7b8c9d0e1f")
  expect(Object.keys(examples).sort()).toEqual(reads.map(tool => tool.name).sort())

  for (const tool of reads) {
    const [input, path] = examples[tool.name]
    const over_http = await page.request.get(path).then(response => response.json())
    expect(await call(page, tool.name, input), tool.name).toEqual(over_http)
  }
  expect(sent.map(request => new URL(request.url()).pathname + new URL(request.url()).search).sort())
    .toEqual(reads.map(tool => examples[tool.name][1]).sort())
})

test("a public read hands on the site's refusal unchanged, and refuses only what it cannot send", async ({page}) => {
  await open(page, "none")
  const sent = toApi(page)
  const http = (path: string) => page.request.get(path).then(response => response.json())

  for (const [input, path] of [
    [{room: "general", limit: "x"}, "/api/v1/rooms/general/messages?limit=x"],
    [{room: "general", limit: [5]}, "/api/v1/rooms/general/messages?limit=%5B5%5D"],
    [{room: "general", colour: "blue"}, "/api/v1/rooms/general/messages?colour=blue"],
    [{room: "nowhere"}, "/api/v1/rooms/nowhere/messages"],
    [{room: "general", limit: null}, "/api/v1/rooms/general/messages?limit="],
  ] as const) {
    expect(await call(page, "rooms_messages", input), path).toEqual(await http(path))
  }
  expect(sent).toHaveLength(5)

  // Input with no address is answered as hosted MCP answers it, and nothing is sent.
  const messages = reads.find(tool => tool.name === "rooms_messages")!
  for (const input of ["general", null, {}, {room: ""}, {room: ".."}]) {
    const field = input !== null && typeof input === "object" ? "room" : "input"
    expect(await call(page, "rooms_messages", input), JSON.stringify(input)).toEqual({error: messages.refusals[field]})
  }
  expect(sent).toHaveLength(5)
})

test("a refusal carries the seconds to wait, and a read that gets no answer says so", async ({page}) => {
  await open(page, "none")
  await page.route("**/api/v1/rooms", route => route.fulfill({
    status: 429,
    headers: {"retry-after": "30"},
    contentType: "application/json",
    body: JSON.stringify({error: {code: "rate_limited", message: "Too Many Requests", hint: "Wait, then try again."}}),
  }))
  expect(await call(page, "rooms_list", {})).toEqual({
    error: {code: "rate_limited", message: "Too Many Requests", hint: "Wait, then try again.", retry_after: 30},
  })

  await page.route("**/api/v1/polls", route => route.abort("connectionfailed"))
  expect(await call(page, "polls_list", {})).toEqual({error: {code: "unreachable", message: "The site could not be reached. Try again."}})
})
