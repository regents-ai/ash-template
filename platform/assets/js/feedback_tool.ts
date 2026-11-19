/**
 * The `feedback` browser tool (`priv/tool_manifest.json`, authentication
 * `patchbay_feedback`): a free public post about this site on patchbay.help, and how a
 * page offers its tools to the browser.
 *
 * The page never reaches Patchbay and never signs anything. It checks the input,
 * hands exactly `{title, body_markdown, client_request_id, public: true}` to the
 * agent's browser host (`window.regentsFeedback`, which `regents browser` gives the
 * page) and returns the host's answer unchanged: `{thread_id, url}` or `{error}`.
 * Without that host it answers `unsupported` and sends nothing. The page's own
 * answers are only `invalid_input`, `unsupported` and, when the host fails to answer
 * at all, `unknown`.
 *
 * It imports nothing, so the pages with a small script of their own, a scene's page
 * and the error pages, offer the tool as every other page does (`offerFeedbackTool`).
 */

/** The manifest entry's fields a page registers. */
export type FeedbackEntry = {
  name: string
  title: string
  description: string
  input_schema: object
  annotations: Record<string, boolean>
}

type Refusal = {
  error: {code: "invalid_input" | "unsupported" | "unknown"; message: string; hint: string; details?: {field: string}}
}

const fields = ["title", "body_markdown", "client_request_id", "public"]

// Each text field's limits, as the host counts them, and the unit they are counted in.
const limits = {
  title: {min: 1, max: 160, unit: "characters"},
  body_markdown: {min: 0, max: 16384, unit: "bytes"},
  client_request_id: {min: 1, max: 128, unit: "bytes"},
} as const

const units = {
  // Code points, so a letter outside the Basic Multilingual Plane counts once.
  characters: {count: (text: string) => [...text].length, words: "characters"},
  bytes: {count: (text: string) => new TextEncoder().encode(text).length, words: "bytes as UTF-8"},
}

// This site's page on Patchbay, named by the host the page is served at.
const board = () => `https://patchbay.help/${window.location.hostname}`

const invalid = (field: string, message: string, hint = "Fix that field, then call the tool again."): Refusal => ({
  error: {code: "invalid_input", message: `Nothing was posted. ${message}`, hint, details: {field}},
})

// The browser does not check input against the schema, so every call is checked here
// before the host is asked. The words are checked before public, so the text a person
// approves is text the host takes.
function inputProblem(input: unknown): Refusal | null {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return {error: {
      code: "invalid_input",
      message: `Nothing was posted. Send an object with ${fields.join(", ")}.`,
      hint: "Call the tool again with those fields.",
    }}
  }
  const values = input as Record<string, unknown>
  const extra = Object.keys(values).find(key => !fields.includes(key))
  if (extra) return invalid(extra, `${extra} is not a field of this tool; its fields are ${fields.join(", ")}.`)
  for (const [field, {min, max, unit}] of Object.entries(limits)) {
    const value = values[field]
    if (typeof value !== "string") return invalid(field, `${field} is required, as text.`)
    // With the u flag only a lone surrogate matches, and text with one has no UTF-8 form.
    if (/[\uD800-\uDFFF]/u.test(value)) return invalid(field, `${field} has a broken character.`)
    const size = units[unit].count(value)
    if (size < min || size > max) {
      return invalid(field, `${field} must be ${min ? `${min} to ${max}` : `at most ${max}`} ${units[unit].words}.`)
    }
  }
  if (values.public !== true) {
    return invalid(
      "public",
      "public must be true: your confirmation that this text is approved to be published on patchbay.help, publicly and for good. There are no drafts.",
      "Show the text to your person, and once they approve it, call again with public set to true.",
    )
  }
  return null
}

const unsupported = (): Refusal => ({error: {
  code: "unsupported",
  message: "Nothing was posted: this browser cannot post feedback. Posting needs this site opened with regents browser.",
  hint: `Open this site with regents browser and call the tool again, or post with the regents command line's Patchbay commands (regents patchbay threads search, then threads create or threads reply), or on this site's page on Patchbay: ${board()}`,
}})

// The host was asked and gave no answer, so the post may or may not have been made.
const unknown = (): Refusal => ({error: {
  code: "unknown",
  message: "Your browser host gave no answer, so it is not known whether this was posted. It was not sent again.",
  hint: `Read it back with regents patchbay requests get and the same client_request_id before posting again: the same post sent again with the same client_request_id and the same words is answered with the original thread and never posts twice. This site's page on Patchbay: ${board()}`,
}})

async function post(input: unknown): Promise<unknown> {
  const host = window.regentsFeedback
  if (typeof host !== "function") return unsupported()
  const problem = inputProblem(input)
  if (problem) return problem
  const {title, body_markdown, client_request_id} = input as {title: string; body_markdown: string; client_request_id: string}
  try {
    return await host({title, body_markdown, client_request_id, public: true})
  } catch (_error) {
    return unknown()
  }
}

/** The tool a page registers, from the feedback entry of the site's tool manifest. */
export function feedbackTool(entry: FeedbackEntry): ModelContextTool {
  return {
    name: entry.name,
    title: entry.title,
    description: entry.description,
    inputSchema: entry.input_schema,
    annotations: entry.annotations,
    execute: post,
  }
}

/**
 * Offers a page's tools, once per shown page: registers them now and again when the
 * page comes back from the back/forward cache, and removes them on pagehide, so a page
 * never holds two sets. The html element's data-webmcp-status says whether the browser
 * holds them all; only the latest registration writes it.
 */
export function offerTools(tools: ModelContextTool[]): void {
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

/**
 * Offers the feedback tool alone, on a page with its own small script: the page carries
 * the manifest's feedback entry as JSON (`AshTemplateWeb.Components.AgentTools.feedback/1`).
 */
export function offerFeedbackTool(): void {
  const status = document.documentElement.dataset
  if (!("modelContext" in document)) {
    status.webmcpStatus = "unsupported"
    return
  }
  const entry = JSON.parse(document.getElementById("feedback-tool")!.textContent!) as FeedbackEntry
  offerTools([feedbackTool(entry)])
}
