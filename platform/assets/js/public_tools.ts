// Manifest-listed WebMCP operations. SIWA keys stay in the caller’s existing signer.
import manifest from "../../priv/tool_manifest.json" with {type: "json"}
import {signedTools, type SignedOperation, type SignedInput} from "../vendor/regent_agent_access/signed_tools"

function signedTransport() { return signedTools({
  origin: window.location.origin,
  trustedOrigins: [document.querySelector<HTMLMetaElement>('meta[name="agent-request-origin"]')?.content ?? ""],
  audience: manifest.audience,
  proofHeaders: manifest.proof_headers,
  operations: manifest.tools.map(entry => ({...entry,
    input_schema: "operation_input_schema" in entry ? entry.operation_input_schema : entry.input_schema,
  })) as unknown as SignedOperation[],
}) }

type Property = {type: "string"; description: string}

type Schema = {
  type: "object"
  properties: Record<string, Property>
  required: string[]
  additionalProperties: false
}

type Entry = {
  name: string
  title: string
  description: string
  input_schema: Schema
  annotations: Record<string, boolean>
  state_changing: boolean
  scope: string
  authentication: string
}

type Input = Record<string, string>

type Refusal = {code: string; message: string; hint?: string; details?: unknown}

type Reply =
  | {ok: true; status: number; data: unknown}
  | {ok: false; status: number; error: Refusal}

type Request = (input: Input, signal: AbortSignal | undefined) => Promise<Reply>

const requests: Record<string, Request> = {
  about: (_input, signal) => markdown("/about", signal),
  docs: (_input, signal) => markdown("/docs", signal),
  room_read: (input, signal) =>
    call("GET", `/tools/rooms/${encodeURIComponent(input.room)}/messages`, signal),
}

// How to learn whether a write that lost its answer happened, before trying again.
const checks: Record<string, string> = {
  notes_create: "List the notes with notes_list to see whether it was saved before adding it again.",
  room_post: "Read the room with room_read to see whether it was posted before posting again.",
}

// A public document, in the Markdown an agent gets when it asks for that page.
async function markdown(path: string, signal: AbortSignal | undefined): Promise<Reply> {
  const response = await fetch(path, {
    headers: {Accept: "text/markdown"},
    credentials: "omit",
    cache: "no-store",
    redirect: "error",
    signal,
  })
  const body = await response.text()
  if (response.ok) return {ok: true, status: response.status, data: body}
  return {ok: false, status: response.status, error: {code: "unreadable", message: body}}
}

// Public JSON without session authority. Every refusal it sends is
// {"error": {"code", "message", "hint"}}, handed on as it came.
async function call(
  method: "GET" | "POST",
  path: string,
  signal: AbortSignal | undefined,
  body?: Input,
): Promise<Reply> {
  const headers: Record<string, string> = {Accept: "application/json"}
  if (body) headers["Content-Type"] = "application/json"
  const response = await fetch(path, {
    method,
    headers,
    body: body && JSON.stringify(body),
    credentials: "omit",
    cache: "no-store",
    redirect: "error",
    signal,
  })
  const answer = await response.json()
  if (response.ok) return {ok: true, status: response.status, data: answer}
  return {ok: false, status: response.status, error: answer.error}
}

// The browser does not check input against the schema, so each call is
// checked here, and a refusal names the field and what it must be. The server
// checks lengths and everything else again.
function inputProblem(input: unknown, schema: Schema) {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return "Send an object of named fields."
  }
  const unknown = Object.keys(input).find(key => !Object.hasOwn(schema.properties, key))
  if (unknown) {
    const fields = Object.keys(schema.properties)
    return fields.length
      ? `${unknown} is not a field of this tool; its fields are ${fields.join(", ")}.`
      : `${unknown} is not a field of this tool; it takes none.`
  }
  const missing = schema.required.find(key => !Object.hasOwn(input, key))
  if (missing) return `${missing} is required.`
  const values = input as Record<string, unknown>
  const notText = Object.keys(values).find(key => typeof values[key] !== "string")
  return notText ? `${notText} must be text.` : null
}

// A call that ended without an answer. A write may already have reached the
// server, so its outcome is unknown, never cancelled.
function unanswered(entry: Entry, signal: AbortSignal | undefined) {
  if (entry.state_changing) {
    return {
      ok: false,
      outcome: "unknown",
      error: {
        code: "outcome_unknown",
        message: "The answer did not arrive, so it is not known whether this happened.",
        hint: checks[entry.name],
      },
    }
  }
  return signal?.aborted
    ? {ok: false, error: {code: "cancelled", message: "The read was cancelled; nothing changed."}}
    : {ok: false, error: {code: "unreachable", message: "The site could not be reached. Try again."}}
}

// JSON imports widen every literal, so the manifest is read as the shape it is written in.
const entries = manifest.tools as unknown as Entry[]

const tools: ModelContextTool[] = entries.filter(entry => entry.scope === "site").map(entry => ({
  name: entry.name,
  title: entry.title,
  description: entry.description,
  inputSchema: entry.input_schema,
  annotations: entry.annotations,
  async execute(input: unknown, {signal}: {signal?: AbortSignal}) {
    if (entry.name === "prepare_agent_request") {
      try {
        const args = input as {operation: string; input: Input}
        return {ok: true, request: signedTransport().prepare(args.operation, args.input)}
      } catch (error) {
        return {ok: false, error: {code: "invalid_preparation", message: String(error)}}
      }
    }
    if (entry.authentication === "siwa_per_request") {
      try {
        const response = await signedTransport().execute(entry.name, input as SignedInput, signal)
        const data = await response.json()
        return response.ok ? {ok: true, status: response.status, data} : {ok: false, status: response.status, error: data.error}
      } catch (error) {
        return {ok: false, error: {code: "signed_request_failed", message: String(error),
          hint: entry.state_changing
            ? "Keep the logical operation ID. Check the outcome before retrying, and sign fresh proof."
            : "Sign fresh proof for the exact prepared request with your existing SIWA signer. If no supported signer is available, report the blocker."}}
      }
    }
    const problem = inputProblem(input, entry.input_schema)
    if (problem) return {ok: false, error: {code: "invalid_input", message: problem}}
    if (signal?.aborted) {
      return {ok: false, error: {code: "cancelled", message: "The call was cancelled before it was sent; nothing changed."}}
    }
    try {
      return await requests[entry.name](input as Input, signal)
    } catch (_error) {
      return unanswered(entry, signal)
    }
  },
}))

// One registration per shown page: register on pageshow, remove on pagehide,
// so a page restored from the back/forward cache never holds two sets. The
// html element's data-webmcp-status says whether the browser holds them all;
// only the latest registration writes it.
export function installPublicTools(): void {
  const status = document.documentElement.dataset
  if (!("modelContext" in document)) {
    status.webmcpStatus = "unsupported"
    return
  }
  let registration: AbortController | undefined

  window.addEventListener("pageshow", () => {
    const current = new AbortController()
    registration = current
    const {signal} = current
    Promise.all(tools.map(tool => document.modelContext.registerTool(tool, {signal})))
      .then(() => document.modelContext.getTools())
      .then(held => {
        if (registration !== current) return
        const names = new Set(held.map(tool => tool.name))
        status.webmcpStatus = tools.every(tool => names.has(tool.name)) ? "connected" : "error"
      })
      .catch((error: unknown) => {
        current.abort()
        if (registration !== current) return
        status.webmcpStatus = "error"
        console.warn("The browser tools could not be offered.", error)
      })
  })
  window.addEventListener("pagehide", () => registration?.abort())
}
