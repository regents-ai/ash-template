// Manifest-listed WebMCP operations. A signed tool takes only its input; the agent's
// browser host signs the exact request (window.regentsSign), so no key, signature or
// receipt passes through the page.
import manifest from "../../priv/tool_manifest.json" with {type: "json"}
import {Refused, signedTools, type SignedOperation} from "../vendor/regent_agent_access/signed_tools"
import {report, visitId} from "./visit_log"

function signedTransport() { return signedTools({
  origin: window.location.origin,
  trustedOrigins: [document.querySelector<HTMLMetaElement>('meta[name="agent-request-origin"]')?.content ?? ""],
  audience: manifest.audience,
  proofHeaders: manifest.proof_headers,
  requestHeaders: client,
  // Only the signed tools are operations.
  operations: manifest.tools.filter(entry => entry.authentication === "siwa_per_request") as unknown as SignedOperation[],
}) }

type Refusal = {code: string; message: string; hint?: string; [more: string]: unknown}

type Entry = {
  name: string
  title: string
  description: string
  input_schema: {properties: Record<string, unknown>}
  annotations: Record<string, boolean>
  route: string
  scope: string
  authentication: string
  // What the site answers input this read cannot send: `input` for input that is
  // not an object, and each address field's for that field missing or not a name.
  refusals?: Record<string, Refusal>
}

// A tool's answer is the site's own: the HTTP body, or {error: {code, message,
// hint, ...}} with anything more, such as the seconds to wait, inside error.
type Answer = unknown

// Every call names its tool and this visit, so the site's log can put the call
// beside the rest of the visit (AshTemplateWeb.VisitLog). Neither is a credential.
function client(tool: string): Record<string, string> {
  const visit = visitId()
  return {"x-regent-client": `webmcp/${tool}`, ...(visit && {"x-regent-visit": visit})}
}

async function answer(response: Response): Promise<Answer> {
  const body = await response.json()
  if (response.ok) return body
  // Past a limit the agent is told how many seconds to wait.
  const retryAfter = Number(response.headers.get("retry-after"))
  return retryAfter > 0 ? {error: {...body.error, retry_after: retryAfter}} : body
}

// A value as the site reads it from the address, where everything is text.
const text = (value: unknown) => typeof value === "string" ? value : JSON.stringify(value)

// A public read's address is its manifest route: each {field} of the path is
// that input, and every other input goes in the query, so the site checks it
// as it checks the same input over HTTP and hosted MCP. Only input that cannot
// be an address is answered here, in the site's own words for it.
function address(entry: Entry, input: unknown): string | Refusal {
  const refusals = entry.refusals!
  if (input === null || typeof input !== "object" || Array.isArray(input)) return refusals.input
  const values = {...input} as Record<string, unknown>
  const [, route] = entry.route.split(" ")
  const fields = [...route.matchAll(/\{(\w+)\}/g)].map(([, field]) => field)
  // URL parsing drops "." and ".." segments even when their dots are percent-encoded.
  const unsendable = fields.find(field =>
    values[field] === undefined || values[field] === null || ["", ".", ".."].includes(text(values[field])))
  if (unsendable) return refusals[unsendable]
  const path = route.replace(/\{(\w+)\}/g, (_match, field: string) => encodeURIComponent(text(values[field])))
  for (const field of fields) delete values[field]
  // A null is sent empty, which the site reads as left out.
  const query = new URLSearchParams(Object.entries(values).map(([key, value]) => [key, value === null ? "" : text(value)]))
  return query.toString() ? `${path}?${query}` : path
}

// Public JSON without session authority. Every refusal it sends is
// {"error": {"code", "message", "hint"}}, handed on as it came.
async function read(entry: Entry, input: unknown, signal: AbortSignal | undefined): Promise<Answer> {
  const path = address(entry, input)
  if (typeof path !== "string") return {error: path}
  if (signal?.aborted) return {error: {code: "cancelled", message: "The call was cancelled before it was sent; nothing changed."}}
  let response: Response
  try {
    response = await fetch(path, {
      headers: {Accept: "application/json", ...client(entry.name)},
      credentials: "omit",
      cache: "no-store",
      redirect: "error",
      signal,
    })
  } catch (_error) {
    return unanswered(entry, signal)
  }
  try {
    return await answer(response)
  } catch (_error) {
    return unanswered(entry, signal)
  }
}

// A call that ended without an answer. Anything but a read may already have
// reached the server, so its outcome is unknown, never cancelled. The site never
// heard it, so the page reports it.
function unanswered(entry: Entry, signal: AbortSignal | undefined): Answer {
  if (!entry.annotations.readOnlyHint) {
    report({name: "tool.unsent", where: entry.name, outcome: "outcome_unknown"})
    return {error: {
      code: "outcome_unknown",
      message: "The answer was lost, so it is not known whether this happened.",
      hint: "Read it back by its operation_id or id before you try again.",
    }}
  }
  if (signal?.aborted) return {error: {code: "cancelled", message: "The read was cancelled; nothing changed."}}
  report({name: "tool.unsent", where: entry.name, outcome: "unreachable"})
  return {error: {code: "unreachable", message: "The site could not be reached. Try again."}}
}

// Reasons that mean the tool itself is set up wrongly, not the agent's input.
const siteFaults = new Set(["invalid_operation", "invalid_path", "invalid_request_header", "unsupported_field_type"])

// The signing transport refuses with a reason such as "missing_field:title".
// The agent reads it in words; the reason itself stays in details.
const invalid = (error: unknown): Answer => {
  const reason = error instanceof Error ? error.message : String(error)
  return {error: {
    code: "invalid_request",
    message: explain(reason),
    hint: siteFaults.has(reason.split(":", 1)[0])
      ? "Use another way in, such as the API, and tell the site's team."
      : "Check the input against this tool's schema, then call the tool again.",
    details: {reason},
  }}
}

function explain(reason: string): string {
  const [kind, field] = reason.split(":", 2)
  switch (kind) {
    case "invalid_input": return "Send an object of named fields."
    case "missing_field": return `${field} is required.`
    case "invalid_field": return `${field} is not a field of this tool, or is not the kind of value it takes.`
    case "invalid_path_field": return `${field} must be a name: not empty, "." or "..".`
    case "unexpected_read_body": return "This tool reads only. Send only the fields its address names."
    case "invalid_raw_body": return "Send the body as JSON text, and nothing else."
    case "invalid_operation":
    case "invalid_path":
    case "invalid_request_header":
    case "unsupported_field_type":
      return "This tool is set up wrongly on the site, so nothing was sent."
    case "operation_unavailable": return "No signed tool has that name. Use a name from this page's tools."
    case "operation_id_required": return "operation_id is required. Use a new one for each change and keep it when retrying."
    case "body_too_large": return "The input is too large."
    case "input_complexity_exceeded": return "The input has too many parts or is nested too deeply."
    case "invalid_signer_answer":
    case "proof_required":
    case "invalid_proof":
    case "incomplete_proof":
    case "body_proof_required":
    case "unexpected_body_proof":
      return "Your agent's signer gave an incomplete answer, so nothing was sent. Update regents-cli and open this site again with regents browser."
    case "untrusted_origin":
    case "insecure_origin":
      return "This page can't send signed requests."
    default: return "The input doesn't fit this tool's schema."
  }
}

// fetch fails with a TypeError when the network fails and an AbortError when
// cancelled. Before anything is sent, the transport refuses with a plain Error, or
// with Refused when there is no agent signer, it fails or says no, or the call was
// cancelled while it signed; Refused carries the words for the agent.
const lost = (error: unknown) =>
  error instanceof TypeError || (error instanceof DOMException && error.name === "AbortError")

async function signed(entry: Entry, input: Record<string, unknown>, signal: AbortSignal | undefined): Promise<Answer> {
  if (signal?.aborted) {
    return {error: {code: "cancelled", message: "The call was cancelled before it was sent; nothing changed."}}
  }
  let response: Response
  try {
    response = await signedTransport().execute(entry.name, input, signal)
  } catch (error) {
    if (error instanceof Refused) return {error: error.refusal}
    return lost(error) ? unanswered(entry, signal) : invalid(error)
  }
  try {
    return await answer(response)
  } catch (_error) {
    return unanswered(entry, signal)
  }
}

// JSON imports widen every literal, so the manifest is read as the shape it is written in.
// Every page offers the site's tools; a page's own tools are offered by that page.
const entries = (manifest.tools as unknown as Entry[]).filter(entry => entry.scope === "site")

const tools: ModelContextTool[] = entries.map(entry => ({
  name: entry.name,
  title: entry.title,
  description: entry.description,
  inputSchema: entry.input_schema,
  annotations: entry.annotations,
  execute: (input: unknown, {signal}: {signal?: AbortSignal}) =>
    entry.authentication === "siwa_per_request"
      ? signed(entry, input as Record<string, unknown>, signal)
      : read(entry, input, signal),
}))

// One registration per shown page: register now and again when the page comes
// back from the back/forward cache, remove on pagehide, so a page never holds
// two sets. The html element's data-webmcp-status says whether the browser
// holds them all; only the latest registration writes it.
export function installPublicTools(): void {
  const status = document.documentElement.dataset
  let registration: AbortController | undefined

  const register = () => {
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
  }

  register()
  window.addEventListener("pageshow", event => { if (event.persisted) register() })
  window.addEventListener("pagehide", () => registration?.abort())
}
