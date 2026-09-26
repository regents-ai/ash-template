# Build WebMCP tools into an Ash site

WebMCP lets a page hand the browser's own agent a set of tools. The agent calls them
inside the signed-in customer's tab, so every call is the customer acting. It is not
a remote MCP server; a hosted `/mcp` endpoint is a separate surface with its own auth.

Checked against the WebMCP Editor's Draft at webmachinelearning/webmcp `729ae01`
(2026-09-26) and Chrome's WebMCP docs (updated 2026-09-21). The API changed several
times in 2026; re-read the draft before relying on anything below.

## The browser API today

```ts
const scope = new AbortController()
await document.modelContext.registerTool(
  {
    name: "search_threads",          // 1–128 chars of [A-Za-z0-9_.-], unique per page
    title: "Search threads",
    description: "Search public threads by words. Reads only; needs no sign-in.",
    inputSchema: {type: "object", properties: {q: {type: "string"}}, required: ["q"], additionalProperties: false},
    annotations: {readOnlyHint: true, untrustedContentHint: true},
    async execute(input, {signal}) { /* returns any JSON-serializable value */ },
  },
  {signal: scope.signal},
)
scope.abort() // the only way to remove it
```

- The entry point is `document.modelContext` (secure pages only). It moved there
  from `navigator` on 2026-05-27. Detect it with `"modelContext" in document`; use
  nothing else. No `navigator` branch and no polyfill.
- `registerTool` returns a promise. It rejects on a duplicate name, a bad name, an
  empty description, a denied `tools` permission or a page that is not origin-keyed.
- `provideContext`, `clearContext`, `unregisterTool` and `requestUserInteraction`
  are gone from the draft. Remove a tool by aborting the signal it was registered with.
- Annotations are `readOnlyHint`, `untrustedContentHint`, `consequentialHint` and
  `debugging`, all default false. MCP's `destructiveHint`, `idempotentHint` and
  `openWorldHint` are not WebMCP; do not send them. There is no `outputSchema`.
- `execute(input, {signal})` gets the parsed input and the agent's abort signal.
  Whatever it returns is JSON-stringified for the agent. A rejected promise reaches
  the agent as a bare failure, so return a result that says what went wrong and
  how to fix the call instead of throwing.
- The browser does not validate input against the schema (JSON Schema 2020-12).
  Validate in `execute` and again on the server.
- `document.modelContext` fires `toolchange`, `toolactivated` and `toolcancel`.
  `getTools()` lists what the browser holds; use it to confirm registration.
- Declarative forms (`toolname`, `tooldescription`, `toolparamdescription` on a
  `<form>`) are still a TODO in the draft. Use the imperative API.

Headers and browsers:

- Send `Permissions-Policy: tools=(self)`. Never send `Origin-Agent-Cluster: ?0`.
- Chrome runs WebMCP as an origin trial ("WebMCP", Chrome 149–156). The token is
  public, tied to one host and expires; keep it beside a comment naming its host and
  expiry, and send it as an `Origin-Trial` response header next to the
  Permissions-Policy, so Chrome knows it before reading `tools`. Locally, turn on
  `chrome://flags/#enable-webmcp-testing` instead. Edge 150 has a trial too;
  ChatGPT's in-app browser supports it; Firefox and Safari do not.

## How the pieces fit in an Ash site

```
priv/tool_manifest.json ──► MyApp.Capabilities (compile time)
        │                      ├─► /capabilities JSON, developers table, hosted MCP list
        │                      └─► llms.txt and docs pages
        └─► assets/js/webmcp/tools.ts ──► document.modelContext.registerTool
                                              │ execute(input, {signal})
                                              ▼
                     fetch JSON route (same-origin cookie, CSRF, signal)
                     or LiveView pushEvent with a reply (page-scoped tools)
                                              ▼
                     controller / LiveView ──► Domain code interface (actor: from session)
                                              ▼
                                         Ash policies decide
```

### 1. One manifest is the source of truth

Keep every tool the site registers in one JSON file, read by Elixir at compile time
and imported by the browser code. Registration, docs and machine lists are derived
from it; nothing is typed twice. Patchbay's `platform/priv/tool_manifest.json` with
`Patchbay.Forum.Capabilities` is the working reference.

Each entry: `name`, `title`, `description`, `input_schema`, `annotations`, plus the
facts docs need: `requires` (`none`, `session`, `profile`, `wallet_signed`),
`state_changing`, `payment` (`none`, `moves_usdc`), the HTTP route behind it, and
`scope` (`site` or the page that registers it). Include page-scoped tools and the
shared profile tools too, so the published list never denies a tool a page registers.

```elixir
defmodule MyApp.Capabilities do
  # Read once at compile time from the project tree.
  @manifest_path "priv/tool_manifest.json"
  @external_resource @manifest_path
  @manifest Jason.decode!(File.read!(@manifest_path))
  def manifest, do: @manifest
  def tools, do: @manifest["tools"]
  def site_tools, do: Enum.filter(tools(), &(&1["scope"] == "site"))
end
```

The browser side keeps only the `execute` functions; the definition comes from the
manifest:

```ts
import manifest from "../../../priv/tool_manifest.json" with {type: "json"}
const tools = manifest.tools.filter(tool => tool.scope === "site").map(tool => ({
  name: tool.name, title: tool.title, description: tool.description,
  inputSchema: tool.input_schema, annotations: tool.annotations, execute: executors[tool.name],
}))
```

### 2. A tool is a thin door to an Ash action

- `execute` calls the same route or LiveView event the page's own buttons use. The
  controller calls the domain's code interface with the actor from the session
  (`MyApp.Forum.post_reply(input, actor: actor)`); Ash policies decide. A tool never
  gets its own authorization path.
- Identity never comes from tool input. The server reads it from the session; the
  page learns who is signed in from server-rendered markup.
- `fetch(url, {credentials: "same-origin", headers: {"x-csrf-token": token}, signal})`.
  Pass the agent's `signal` through.
- A write cancelled after the request left returns `{outcome: "unknown"}` with how to
  check, never "cancelled".
- Keep results small and bounded. Refuse rather than truncate data into a lie.

### 3. Mark what a tool does, truthfully

- `readOnlyHint: true` only when the action changes nothing, whatever the HTTP method.
- `untrustedContentHint: true` whenever the result carries text customers or agents
  wrote. Put that text under a field the result labels as data, never as instructions.
- `consequentialHint: true` for anything that moves money, publishes, or cannot be
  undone, so the agent asks the customer first.
- The description says when to use the tool, what it needs (sign-in, profile,
  wallet) and whether money moves. Schemas are typed with `additionalProperties: false`.

### 4. Wallets and payments

A tool that signs goes through the same wallet step as the button: the server issues
the challenge, the customer's wallet signs exactly what it states, the server admits
it. Nothing signs automatically, a refused signature never retries unsigned, and
every call reaches the wallet (the same rule as on-chain buttons: no gating,
deferring or deduplicating a press).

### 5. Register once, remove cleanly

- Site-wide tools: register once per document from the app entry, on `pageshow`,
  and abort on `pagehide`, so the back/forward cache cannot leave duplicates. LiveView
  navigation keeps the document, so they stay registered.
- Page-scoped tools: a LiveView hook with `phx-update="ignore"` registers in `mounted`
  and aborts in `destroyed`. `reconnected` re-registers.
- Give each group one `AbortController`. If any registration in the group fails,
  abort the group so the page never holds half a set.
- After registering, read `getTools()` and show the result in a quiet status
  attribute (`data-webmcp-status`: `connected`, `unsupported`, `error`), not in
  customer copy.

### 6. The shared profile tools

`regents/identity/assets/profile_tools.mjs` defines `profile_get`, `profile_sync` and
`profile_update`; `mix regent_identity.assets` copies it into each product's
gitignored `vendor/regent_identity/`, and the page calls `installProfileTools`.
They use the Privy session and return `authentication_required` when signed out.
List them in the manifest with `scope: "site"`.

## Checks

1. Compile and typecheck. Tests only where the founder agreed them; a fake
   `modelContext` proves the adapter, not the browser.
2. The HTTP routes behind each tool: real requests signed out and signed in, and a
   refused write returns a fixable error.
3. Native discovery: Chrome with the flag (or the trial token on the real host) and
   the Model Context Tool Inspector extension. The tools appear with the manifest's
   names and annotations; run each read-only one; run one write as a test customer
   on a local server only.
4. Report which of the three you proved: the manifest and adapter, the adapter against
   the site, or the browser's own discovery and execution.

## Reference code

Patchbay, relative to `repos/patchbay/platform`:

| What | Where |
| --- | --- |
| Manifest and its Elixir reader | `priv/tool_manifest.json`, `lib/patchbay/forum/capabilities.ex` |
| Site-wide tools and executors | `assets/js/webmcp/forum_tools.js`, `forum_lifecycle.js` |
| Scoped registration with rollback | `assets/js/webmcp/webmcpify.js` (`createToolScope`) |
| Page-scoped tools in a LiveView hook | `assets/js/webmcp/room_hook.js`, `invocation_bridge.js` |
| Permissions-Policy and trial header | `lib/patchbay_web/plugs/browser_policy.ex` |
| Paid tools | `assets/js/webmcp/paid_actions.js` |

Patchbay predates parts of the current draft and of this guide: it still falls back
to `navigator.modelContext`, sends MCP-only annotations, marks site-wide tools with
`doors.page` instead of `scope`, and leaves its room and profile tools out of the
manifest. Follow this guide where they differ. Autolaunch (`platform/assets/js/public_tools.ts`) is a smaller example
with five read-only public tools.
