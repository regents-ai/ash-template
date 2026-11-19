// Invariant: the feedback tool hands the agent's browser host exactly
// {title, body_markdown, client_request_id, public: true} and returns its answer
// unchanged, or refuses before asking it. Without the host it answers unsupported. It
// never sends anything itself, and never turns a host's error, or a host that fails
// to answer, into a post.
import {afterEach, beforeEach, expect, it, vi} from "vitest"
import manifest from "../../priv/tool_manifest.json" with {type: "json"}
import {type FeedbackEntry, feedbackTool} from "../js/feedback_tool"

const entry = manifest.tools.find(tool => tool.name === "feedback") as unknown as FeedbackEntry
const tool = feedbackTool(entry)
const board = "https://patchbay.help/template.example"

const valid = {
  title: "The Notes page loses a draft on reload",
  body_markdown: "I wrote a note, reloaded the page and expected the draft; the box was empty.",
  client_request_id: "6f1c1f43-4b8a-4d3b-9d2f-0c6a2b7e9a10",
  public: true,
}

let network: {fetch: ReturnType<typeof vi.fn>; xhr: ReturnType<typeof vi.fn>}

beforeEach(() => {
  network = {fetch: vi.fn(), xhr: vi.fn()}
  vi.stubGlobal("fetch", network.fetch)
  vi.stubGlobal("XMLHttpRequest", network.xhr)
})

afterEach(() => {
  // Nothing in any case reaches the network itself.
  expect(network.fetch).not.toHaveBeenCalled()
  expect(network.xhr).not.toHaveBeenCalled()
  vi.unstubAllGlobals()
})

function withHost(host?: (input: unknown) => Promise<unknown>) {
  const regentsFeedback = host && vi.fn(host)
  vi.stubGlobal("window", {location: {hostname: "template.example"}, regentsFeedback})
  return regentsFeedback
}

const call = (input: unknown) => tool.execute(input, {}) as Promise<{error?: {code: string; hint: string; details?: {field: string}}}>

it("hands the host exactly the four fields, once, and returns its answer unchanged", async () => {
  const answer = {thread_id: "thr_123", url: "https://patchbay.help/template.example/threads/thr_123"}
  const host = withHost(async () => answer)!

  expect(await call(valid)).toBe(answer)
  expect(host).toHaveBeenCalledTimes(1)
  expect(host.mock.calls[0]).toEqual([valid])
})

it("passes every host error through unchanged and never as a post", async () => {
  const errors = [
    {error: {code: "unknown", message: "Not known.", hint: "Read it back.", details: {status: "unknown"}}},
    {error: {code: "not_signed_in", message: "Sign in.", hint: "regents patchbay sign-in"}},
    {error: {code: "invalid_input", message: "Too long.", hint: "Shorten it.", retry_after_seconds: 30}},
  ]
  for (const refusal of errors) {
    const host = withHost(async () => refusal)!
    expect(await call(valid)).toBe(refusal)
    expect(host).toHaveBeenCalledTimes(1)
  }
})

it("answers unknown when the host throws or rejects, naming the site's page, and never asks again", async () => {
  for (const host of [async () => { throw new Error("gone") }, () => Promise.reject(new Error("gone"))]) {
    const regentsFeedback = withHost(host)!
    const answer = await call(valid)
    expect(answer.error?.code).toBe("unknown")
    expect(answer.error?.hint).toContain(board)
    expect(answer).not.toHaveProperty("thread_id")
    expect(regentsFeedback).toHaveBeenCalledTimes(1)
  }
})

it("without the host answers unsupported, naming the site's page, whatever the input", async () => {
  for (const input of [valid, {...valid, public: false}, {}, null]) {
    withHost()
    const answer = await call(input)
    expect(answer.error?.code).toBe("unsupported")
    expect(answer.error?.hint).toContain(board)
    expect(answer).not.toHaveProperty("thread_id")
  }
})

it("refuses public other than exactly true without asking the host", async () => {
  const host = withHost(async () => ({thread_id: "x", url: "y"}))!
  const {public: _public, ...missing} = valid
  for (const input of [missing, {...valid, public: false}, {...valid, public: "true"}, {...valid, public: 1}]) {
    const answer = await call(input)
    expect(answer.error).toMatchObject({code: "invalid_input", details: {field: "public"}})
  }
  expect(host).not.toHaveBeenCalled()
})

it("refuses each broken field by name without asking the host", async () => {
  const host = withHost(async () => ({thread_id: "x", url: "y"}))!
  const cases: Array<[string, unknown]> = [
    ["colour", {...valid, colour: "blue"}],
    ["page_url", {...valid, page_url: "https://template.example/notes"}],
    ["title", {...valid, title: undefined}],
    ["title", {...valid, title: 7}],
    ["title", {...valid, title: ""}],
    ["title", {...valid, title: "Broken \uD800 text"}],
    ["body_markdown", {...valid, body_markdown: undefined}],
    ["body_markdown", {...valid, body_markdown: ["a list"]}],
    ["body_markdown", {...valid, body_markdown: "a\uDC00"}],
    ["client_request_id", {...valid, client_request_id: undefined}],
    ["client_request_id", {...valid, client_request_id: ""}],
    ["client_request_id", {...valid, client_request_id: 42}],
  ]
  for (const [field, input] of cases) {
    expect((await call(input)).error).toMatchObject({code: "invalid_input", details: {field}})
  }
  for (const input of [null, "text", ["a"], 3]) expect((await call(input)).error?.code).toBe("invalid_input")
  expect(host).not.toHaveBeenCalled()
})

// The host's own units: title in code points, the body and the key in UTF-8 bytes.
it("holds each limit at its edge, in its own unit", async () => {
  const host = withHost(async () => ({thread_id: "x", url: "y"}))!
  const accepted = [
    {title: "t".repeat(160)},
    {title: "😀".repeat(160)}, // 160 code points, 320 UTF-16 units
    {body_markdown: ""},
    {body_markdown: "b".repeat(16384)},
    {body_markdown: "é".repeat(8192)}, // 16384 bytes
    {client_request_id: "k".repeat(128)},
    {client_request_id: "é".repeat(64)}, // 128 bytes
  ]
  const refused: Array<[string, object]> = [
    ["title", {title: "t".repeat(161)}],
    ["title", {title: "😀".repeat(161)}],
    ["body_markdown", {body_markdown: "b".repeat(16385)}],
    ["body_markdown", {body_markdown: "é".repeat(8192) + "b"}],
    ["client_request_id", {client_request_id: "k".repeat(129)}],
    ["client_request_id", {client_request_id: "é".repeat(100)}], // 100 characters, 200 bytes
    ["client_request_id", {client_request_id: "€".repeat(43)}], // 129 bytes
  ]
  for (const change of accepted) expect((await call({...valid, ...change})).error).toBeUndefined()
  expect(host).toHaveBeenCalledTimes(accepted.length)
  for (const [field, change] of refused) {
    expect((await call({...valid, ...change})).error).toMatchObject({code: "invalid_input", details: {field}})
  }
  expect(host).toHaveBeenCalledTimes(accepted.length)
})

// Generated text of 1-, 2-, 3- and 4-byte characters around each edge: the host is
// asked exactly when every field is inside its limits.
it("asks the host exactly when generated text fits every limit", async () => {
  const host = withHost(async () => ({thread_id: "x", url: "y"}))!
  const letters = ["a", "é", "€", "😀"]
  let seed = 7
  const next = () => (seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31
  const text = (length: number) => Array.from({length}, () => letters[Math.floor(next() * letters.length)]).join("")
  const bytes = (value: string) => new TextEncoder().encode(value).length
  const outcomes = {fits: 0, titleOver: 0, keyOverInBytesOnly: 0}
  for (let i = 0; i < 400; i++) {
    // Keys of 40 to 60 characters average 100 to 150 bytes, either side of 128.
    const input = {...valid, title: text(150 + Math.floor(next() * 20)), client_request_id: text(40 + Math.floor(next() * 21))}
    const titleInside = [...input.title].length <= 160
    const keyInside = bytes(input.client_request_id) <= 128
    if (titleInside && keyInside) outcomes.fits++
    if (!titleInside) outcomes.titleOver++
    if (titleInside && !keyInside && input.client_request_id.length <= 128) outcomes.keyOverInBytesOnly++
    expect((await call(input)).error === undefined).toBe(titleInside && keyInside)
  }
  expect(host).toHaveBeenCalledTimes(outcomes.fits)
  // The generated cases reach every side of the edges.
  expect(Object.values(outcomes).every(count => count > 0)).toBe(true)
})
