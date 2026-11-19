/**
 * The `feedback` browser tool (`priv/tool_manifest.json`, authentication
 * `patchbay_feedback`): a free public post about this site on patchbay.help.
 *
 * The page never reaches Patchbay and never signs anything. It checks the input,
 * hands exactly `{title, body_markdown, client_request_id, public: true}` to the
 * agent's browser host (`window.regentsFeedback`, which `regents browser` gives the
 * page), and returns the host's answer as it came: `{thread_id, url}` or `{error}`,
 * an unknown outcome among them. Without that host it refuses, and nothing is sent.
 * It imports nothing, so a page's own small script carries it as the site's does.
 */

export type FeedbackEntry = {
  name: string
  title: string
  description: string
  input_schema: object
  annotations: Record<string, boolean>
}

type Refusal = {error: {code: string; message: string; hint?: string; details?: {field: string}}}

const fields = ["title", "body_markdown", "client_request_id", "public"]

// Characters are counted as code points; the body's upper bound is its UTF-8 bytes.
const characters = (text: string) => [...text].length
const bytes = (text: string) => new TextEncoder().encode(text).length

// Each text field, whether a value fits it, and the rule in words.
const texts: [string, (text: string) => boolean, string][] = [
  ["title", text => characters(text) >= 1 && characters(text) <= 160, "1 to 160 characters"],
  ["body_markdown", text => characters(text) >= 40 && bytes(text) <= 16384, "at least 40 characters and at most 16 KB (16384 bytes)"],
  ["client_request_id", text => characters(text) >= 1 && characters(text) <= 128, "1 to 128 characters"],
]

// This site's own page on Patchbay, named by the address it is served at.
const sitePage = () => `https://patchbay.help/${window.location.hostname}`

const invalid = (field: string, message: string): Refusal => ({
  error: {code: "invalid_input", message, hint: "Fix that field, then call the tool again.", details: {field}},
})

// The first text field that is missing, not text, holds a broken character or breaks
// its rule.
function textProblem(values: Record<string, unknown>): Refusal | null {
  for (const [field, fits, rule] of texts) {
    const value = values[field]
    if (typeof value !== "string") return invalid(field, `${field} is required, as text.`)
    // With the u flag only a lone surrogate matches, and text with one has no UTF-8 form.
    if (/[\uD800-\uDFFF]/u.test(value)) return invalid(field, `${field} has a broken character.`)
    if (!fits(value)) return invalid(field, `${field} must be ${rule}.`)
  }
  return null
}

// The browser does not check input against the schema, so every call is checked here
// before the host is asked; a refusal names the field.
function inputProblem(input: unknown): Refusal | null {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return {error: {code: "invalid_input", message: `Send an object with ${fields.join(", ")}.`}}
  }
  const values = input as Record<string, unknown>
  const unknown = Object.keys(values).find(key => !fields.includes(key))
  if (unknown) return invalid(unknown, `${unknown} is not a field of this tool; its fields are ${fields.join(", ")}.`)
  if (values.public !== true) {
    return {error: {
      code: "public_required",
      message: "Nothing was posted. public must be true: your confirmation that this text is approved to be published on patchbay.help, publicly and for good. There are no drafts.",
      hint: "Show the text to your person, and once they approve it, call again with public set to true.",
      details: {field: "public"},
    }}
  }
  return textProblem(values)
}

async function post(input: unknown, signal: AbortSignal | undefined): Promise<unknown> {
  const host = window.regentsFeedback
  if (typeof host !== "function") {
    return {error: {
      code: "unsupported",
      message: "Nothing was posted: posting needs this site opened with regents browser.",
      hint: `Open this site with regents browser and call the tool again, or post with the regents command line's Patchbay commands (regents patchbay threads search, then threads create or threads reply), or on this site's page on Patchbay: ${sitePage()}`,
    }}
  }
  const problem = inputProblem(input)
  if (problem) return problem
  if (signal?.aborted) {
    return {error: {code: "cancelled", message: "The call was cancelled before anything was sent; nothing was posted."}}
  }
  const {title, body_markdown, client_request_id} = input as {title: string; body_markdown: string; client_request_id: string}
  try {
    return await host({title, body_markdown, client_request_id, public: true})
  } catch (_error) {
    // The host was asked and gave no answer, so the post may or may not have been made.
    return {error: {
      code: "outcome_unknown",
      message: "Your browser host gave no answer, so it is not known whether this was posted.",
      hint: `Look for it on this site's page on Patchbay before you post again: ${sitePage()}`,
    }}
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
    execute: (input, {signal}) => post(input, signal),
  }
}
