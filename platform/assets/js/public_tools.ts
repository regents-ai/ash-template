// Manifest-listed WebMCP operations. SIWA keys stay in the caller’s existing signer.
import manifest from "../../priv/tool_manifest.json" with {type: "json"}
import {signedTools, type SignedOperation, type SignedInput} from "../vendor/regent_agent_access/signed_tools"

function signedTransport() { return signedTools({
  origin: window.location.origin,
  trustedOrigins: [document.querySelector<HTMLMetaElement>('meta[name="agent-request-origin"]')?.content ?? ""],
  audience: manifest.audience,
  proofHeaders: manifest.proof_headers,
  // Only the signed tools are operations; each is sent with its operation's own inputs.
  operations: manifest.tools.flatMap(entry =>
    "operation_input_schema" in entry ? [{...entry, input_schema: entry.operation_input_schema}] : [],
  ) as unknown as SignedOperation[],
}) }

type Property = {type: "string" | "integer" | "object"; description?: string}

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

type Input = Record<string, string | number>

type Refusal = {code: string; message: string; hint?: string; details?: unknown}

type Reply =
  | {ok: true; status: number; data: unknown}
  | {ok: false; status?: number; outcome?: "unknown"; error: Refusal}

type Request = (input: Input, signal: AbortSignal | undefined) => Promise<Reply>

// The public reads. Every other tool except prepare_agent_request is signed.
const requests: Record<string, Request> = {
  about: (_input, signal) => markdown("/about", signal),
  docs: (_input, signal) => markdown("/docs", signal),
  rooms_list: (_input, signal) => call("/api/v1/rooms", signal),
  room_read: ({room, ...page}, signal) => {
    const query = new URLSearchParams(Object.entries(page).map(([key, value]) => [key, String(value)])).toString()
    const path = `/api/v1/rooms/${encodeURIComponent(String(room))}/messages`
    return call(query ? `${path}?${query}` : path, signal)
  },
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
async function call(path: string, signal: AbortSignal | undefined): Promise<Reply> {
  const response = await fetch(path, {
    headers: {Accept: "application/json"},
    credentials: "omit",
    cache: "no-store",
    redirect: "error",
    signal,
  })
  return reply(response)
}

async function reply(response: Response): Promise<Reply> {
  const answer = response.status === 204 ? null : await response.json()
  if (response.ok) return {ok: true, status: response.status, data: answer}
  return {ok: false, status: response.status, error: answer.error}
}

// The browser does not check input against the schema, so each public call is
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
  const wrong = Object.keys(values).find(key =>
    schema.properties[key].type === "integer" ? !Number.isInteger(values[key]) : typeof values[key] !== "string")
  if (!wrong) return null
  return schema.properties[wrong].type === "integer" ? `${wrong} must be a whole number.` : `${wrong} must be text.`
}

// A call that ended without an answer. A write may already have reached the
// server, so its outcome is unknown, never cancelled.
function unanswered(entry: Entry, signal: AbortSignal | undefined): Reply {
  if (entry.state_changing) {
    return {
      ok: false,
      outcome: "unknown",
      error: {
        code: "outcome_unknown",
        message: "The answer was lost, so it is not known whether this happened.",
        hint: "Read it back by its operation_id or id before you try again.",
      },
    }
  }
  return signal?.aborted
    ? {ok: false, error: {code: "cancelled", message: "The read was cancelled; nothing changed."}}
    : {ok: false, error: {code: "unreachable", message: "The site could not be reached. Try again."}}
}

// The signing transport refuses with a reason such as "missing_field:title".
// The agent reads it in words; the reason itself stays in details.
const invalid = (error: unknown): Reply => {
  const reason = error instanceof Error ? error.message : String(error)
  return {ok: false, error: {
    code: "invalid_request",
    message: explain(reason),
    hint: "Check the input against this tool's schema, then prepare and sign the request again.",
    details: {reason},
  }}
}

function explain(reason: string): string {
  const [kind, field] = reason.split(":", 2)
  switch (kind) {
    case "missing_field": return `${field} is required.`
    case "invalid_field": return `${field} is not a field of this tool, or is not the kind of value it takes.`
    case "invalid_path_field": return `${field} must be a name, not empty.`
    case "operation_unavailable": return "No signed tool has that name. Use a name from this page's tools."
    case "operation_id_required": return "operation_id is required. Use a new one for each change and keep it when retrying."
    case "body_too_large": return "The input is too large."
    case "input_complexity_exceeded": return "The input has too many parts or is nested too deeply."
    case "prepared_request_mismatch": return "The signed request is not the one prepared for this input. Prepare it again with the same input, then sign it."
    case "signed_request_required": return "Send the prepared request as request, with its proof."
    case "proof_required":
    case "invalid_proof":
    case "incomplete_proof":
    case "body_proof_required":
    case "unexpected_body_proof":
      return "The proof is missing or incomplete. Sign the prepared request with your SIWA signer and send every header it returns."
    case "untrusted_origin":
    case "insecure_origin":
      return "This page can't send signed requests."
    default: return "The input doesn't fit this tool's schema."
  }
}

// fetch fails with a TypeError when the network fails and an AbortError when
// cancelled; the transport's own refusals, made before anything is sent, are
// plain Errors.
const lost = (error: unknown) =>
  error instanceof TypeError || (error instanceof DOMException && error.name === "AbortError")

async function signed(entry: Entry, input: SignedInput, signal: AbortSignal | undefined): Promise<Reply> {
  if (signal?.aborted) {
    return {ok: false, error: {code: "cancelled", message: "The call was cancelled before it was sent; nothing changed."}}
  }
  let response: Response
  try {
    response = await signedTransport().execute(entry.name, input, signal)
  } catch (error) {
    return lost(error) ? unanswered(entry, signal) : invalid(error)
  }
  try {
    return await reply(response)
  } catch (_error) {
    return unanswered(entry, signal)
  }
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
        const args = input as {operation: string; input: Record<string, unknown>}
        return {ok: true, request: signedTransport().prepare(args.operation, args.input)}
      } catch (error) {
        return invalid(error)
      }
    }
    if (entry.authentication === "siwa_per_request") return signed(entry, input as SignedInput, signal)
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
