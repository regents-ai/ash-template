import type {Page, Request} from "@playwright/test"
import {signedIn} from "./support/person"
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
  expect(answer).toMatchObject({ok: false, error: {code: "agent_auth_required"}})
  expect((answer as {error: {hint: string}}).error.hint).toContain("regents browser --site ash-template")
  expect(sent).toEqual([])
})

test("a signer's refusal is the tool's answer, and nothing is sent", async ({page}) => {
  await open(page, "refuses")
  const sent = toApi(page)
  const answer = await call(page, "rooms_post", post)
  expect(answer).toEqual({ok: false, error: {code: "call_mismatch", message: "This is not the call your agent made.", hint: "Call the tool again."}})
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
  expect(refused).toMatchObject({ok: false, error: {code: "invalid_request"}})
  expect(await page.evaluate(() => (window as unknown as {signerAsked: unknown[]}).signerAsked.length)).toBe(1)
  expect(sent).toHaveLength(1)
})

// The feedback tool on every kind of page: the site's own, a signed-in one, a scene's
// page and an error page, the last two with their own small script. A stand-in
// window.regentsFeedback plays regents browser's host; the page hands it the post and
// returns its answer, and without it the tool answers unsupported. Either way the page
// asks no other host anything. A scene's page names its script at localhost, the site's
// own address in development; the walk's person is signed in at 127.0.0.1.
test.describe("the feedback tool", () => {
  const feedback = {
    title: "The scene page stays dark",
    body_markdown: "I opened the page and waited; I expected the scene to draw and the page stayed dark.",
    client_request_id: "0b7e2a54-61f4-4c1e-9b0e-3f2d8c6a1e77",
    public: true,
  }
  const posted = {thread_id: "thr_walk", url: "https://patchbay.help/127.0.0.1/threads/thr_walk"}

  async function check(page: Page, path: string, status: number, baseURL: string) {
    await page.addInitScript(withPageTools)
    await page.addInitScript(answer => {
      const asked: unknown[] = []
      Object.assign(window, {feedbackAsked: asked, regentsFeedback: async (input: unknown) => (asked.push(input), answer)})
    }, posted)
    expect((await page.goto(path))?.status()).toBe(status)
    await expect(page.locator("html[data-webmcp-status='connected']")).toBeAttached()

    const registered = await page.evaluate(() => {
      const tool = (window as unknown as {pageTools: Map<string, {name: string; title: string}>}).pageTools.get("feedback")
      return tool && {name: tool.name, title: tool.title}
    })
    expect(registered).toEqual({name: "feedback", title: "/feedback"})

    const site = new URL(baseURL).host
    const elsewhere: string[] = []
    page.on("request", request => { if (new URL(request.url()).host !== site) elsewhere.push(request.url()) })

    expect(await call(page, "feedback", feedback)).toEqual(posted)
    expect(await page.evaluate(() => (window as unknown as {feedbackAsked: unknown[]}).feedbackAsked)).toEqual([feedback])

    await page.evaluate(() => delete (window as unknown as {regentsFeedback?: unknown}).regentsFeedback)
    const refused = await call(page, "feedback", feedback)
    expect(refused).toMatchObject({error: {code: "unsupported"}})
    expect(refused).not.toHaveProperty("thread_id")
    expect(elsewhere).toEqual([])
  }

  for (const [name, path, status] of [
    ["an ordinary page", "/", 200],
    ["a scene's page", "/scenes/1", 200],
    ["a page that does not exist", "/no-such-page", 404],
  ] as const) {
    test(`is offered on ${name}`, async ({page, baseURL}) => {
      await check(page, path, status, baseURL!)
    })
  }

  test.describe("signed in", () => {
    test.use({...signedIn, baseURL: `http://127.0.0.1:${process.env.ASH_TEMPLATE_WALK_PORT}`})

    test("is offered on a signed-in page", async ({page, baseURL}) => {
      await check(page, "/notes", 200, baseURL!)
      await expect(page.locator("#note-form")).toBeAttached()
    })
  })
})
