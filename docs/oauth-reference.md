# Connected-app sign-in: local reference

Sean authorized this bounded implementation on 14 October 2026: “Build the shared
Boruta/Privy service locally.” It does not authorize release or change the broader
connected-app backlog. Since 28 October the same sign-in serves the template's
Claude connector (below), which is off until its one switch turns it on.

`RegentOAuth` in `elixir-utils/oauth` supplies the Boruta 2.3.8 protocol adapter,
S256 PKCE, public-client registration, token refresh, consent and connected-app
revocation. The template supplies its verified Privy session and current canonical
account. Consent uses the browser pipeline's session authority and CSRF protection.
No request header or account parameter can establish a person. Nothing here grants
a paired-agent or wallet actor, and no new account store is introduced.

An app names itself in one of two ways. It may use the HTTPS address of its
published identity as the `client_id`, as Claude's "Use Claude's published
identity" option does with `https://claude.ai/oauth/mcp-oauth-client-metadata`;
server metadata says `client_id_metadata_document_supported: true`, and consent
reads and checks that document, records it as an ordinary client
(`oauth_client_documents`, migration `20261111060000`) and reads it again once
its cache lifetime passes (`RegentOAuth.ClientDocuments`). Other apps still
register themselves at `/oauth/register`. Neither kind is ever taken for the other.

A published identity is a public client (`none`, as Claude's is) or signs its
token and revocation requests with its own key (`private_key_jwt`). Such a
document names a `jwks_uri` on its own host, HTTPS on port 443, and no inline
`jwks`; any other method is refused. The app then sends a `client_assertion`
with each token and revocation request: RS256 or ES256 by the key its `kid`
names, `iss` and `sub` its `client_id`, `aud` this site's issuer or its
`/oauth/token` address as the only value, `exp` at most an hour away and a `jti`
used once (`RegentOAuth.ClientAssertion`). Without a valid one the request is
refused `invalid_client` with a 401, and a public client that sends one is
refused too; PKCE is still required. Its keys are read only at the token and
revocation addresses, kept five minutes and read again once for an unknown key
id, at most once a minute (`RegentOAuth.ClientKeys`); when the address does not
answer the request gets a 503. Server metadata lists `none` and
`private_key_jwt` with the algorithms RS256 and ES256. The assertion is spent as
a row of the existing `oauth_tokens` table, so this needs no migration, and
`client_assertion` is among Phoenix's filtered parameter names. The signing
method is checked here only against a stand-in app.

API routes expose resource/server metadata (the resource's also at
`/.well-known/oauth-protected-resource/mcp`, where RFC 9728 places it),
`/oauth/register`, `/oauth/token` and `/oauth/revoke`. Browser routes are GET/POST
`/oauth/authorize`, GET `/oauth/connections` and POST `/oauth/connections/revoke`.
Credential routes disable logging; the existing address limiter bounds registration
and token requests. There is no change to Account's existing social-connections
page.

The Connect page (`/oauth/authorize`) shows one row for each permission the app
asks for, in the words `config/config.exs` gives it as `{lead, detail}`, then the
`never` row, then Allow and Cancel, the host of the address it returns to (never
the full address) and a link to Connected apps. Connected apps
(`/oauth/connections`) lists each app, the most recently connected first, with the
day it connected (`17 Nov 2026`) and Disconnect, which revokes at once without a
second step.

Allow and Cancel answer a short page ("Returning") whose refresh and Continue link
take the browser to the app's callback, never a redirect: Chromium checks every host
a form's redirects pass through against the site's `form-action 'self'`, and an
app's callback may send the browser on to another host. The site's browser policy is
the same on the consent page as on every other page. Opening consent still answers a
refusal with a redirect, and Disconnect still returns to Connected apps with one
(elixir-utils `0a9467f9`, 18 November). Migration `20261118230000` runs the
library's version 4, which lifts the 255-character limit from a code's `state` and
callback and from an app's name, callbacks and keys address, since OpenAI's apps
send a longer `state`.

## The Claude connector: one switch

`ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED=true` turns on everything at once, read at
boot by `config/runtime.exs`; anything else leaves all of it off:

- the sign-in above (`AshTemplate.OAuth`, `RegentOAuth.enabled?/0`), whose rows go
  through the site's `AshTemplate.Repo` and its pool of five;
- the identity tools at `/mcp` and a Bearer token there (below);
- Claude in the pairing box and the signed pair request
  (`config :regent_agents, hosted_pairing: [:claude]`; empty while off);
- the Claude guide at `/agents/claude` and its skill, its line on `/agents` and in
  the sitemap, the connector paragraph in `/agents.md` and the hosted MCP line in
  `/llms.txt`. These are read on each request (`AshTemplate.OAuth.enabled?/0`);
  while off, `/agents/claude` is not found and `/llms.txt` names only the room
  tools at `/mcp`.

With the switch on, the boot stops unless `SIWA_HOSTED_SIGNING_KEY` is this site's
hosted signing key at the sign-in service (32 or more letters, digits, `-` or `_`),
naming that setting. The connector's identities are held by the same sign-in
service that checks agents' signed requests (`ASH_TEMPLATE_SIWA_BROKER_URL`, or
`https://siwa.regents.sh`), for the `ash-template` audience.
`RegentMCPAgents.configure!/0` then checks the rest at boot: the scope, at least one
hosted runtime and the refusal words.

There are two permissions. `regent.identity.manage` lets the app keep an identity
for itself, pair it with the account using a code the person gives it, and check
in. The agent permission, `ash-template.agent` (`AshTemplate.OAuth.agent_scope/0`),
lets it then work as that paired agent, with that agent's rights and nothing more.
Neither lets it sign with the person's wallets or move money: the tools they
reach are the four identity tools, rooms and messages, and none of them does
either. That is what the Connect page's `never` row says ("Never signs with your
wallets or moves money"); a hosted tool that pays or signs with a wallet takes the
row out of `config/config.exs`. The app's own agent identity does sign its
requests to the sign-in service, with its own key, never the person's. The
template's earlier reference
scope, `mcp.events.read`, is gone; an app registered for it connects again.

## The MCP address

`/mcp` is the site's one hosted MCP server, `forward "/mcp", AshAi.Mcp.Router` in
the router, after the sign-in routes and outside the `:api` pipeline. Its own `:mcp`
pipeline takes JSON only, runs the launch gate, so the site's closing closes it
too, then `AshTemplateWeb.Plugs.McpAgent`, which admits the request and says who
is calling (agent access spec 4.3). The connector's four tools,
`register_identity`, `get_identity`, `pair_identity` and `check_in`, are Ash
actions on `AshTemplate.Agents.Connection` that only a connected app may run
(`AshTemplate.Actors.ConnectedApp`); they call `RegentMCPAgents` with the token's
account, and take their titles, words and hints from `RegentMCPAgents.Tools`. The
same server offers the room tools (`rooms_messages` and `rooms_post`) and `messages_leave`
to an agent signing each call. A connected app with the agent permission runs them
as its paired agent once its identity is paired with the token's own account, and
is listed them, in the same order and shapes, from its first request: an MCP client
keeps the list it was first given, so it can use them in the same chat once it
pairs. Until then each answers a tool result with `isError: true` and
`{"error": {"code": "agent_not_paired", …}}`, whose hint says to pair with the
person's code through `pair_identity`, before anything is read
(`AshTemplateWeb.ToolErrors.check_input/3`); their policies refuse the app too,
and allow it only while AshAi lists tools (`AshTemplate.Agents.Connection.Listing`).
A token with the identity permission alone is listed and runs only the four tools
above.

Every refusal at `/mcp` keeps its HTTP status and headers (401 with the
`WWW-Authenticate` challenge, 429 with `Retry-After` and the RateLimit headers,
405 with `Allow`, 503 with `Retry-After` while the site is closed) and answers in
JSON-RPC (`AshTemplateWeb.McpRefusal`):
`{"jsonrpc": "2.0", "id": <the request's id>, "error": {"code": -31000, "message", "data": {"code", "message", "hint"}}}`.
`data` is the site's own refusal, with `retry_after` in seconds past a budget. The
JSON-RPC code is -31000 for every refusal the site makes, outside the range
JSON-RPC and MCP keep for themselves; -32700 for a body that is not JSON and
-32603 for a failure of the site's own. The id is the request's; a request whose
id could not be read (refused before its body was read, a form body, a batch) gets
an error with no `id`, as MCP's error responses allow. A notification gets the
status with no body, since a notification is never answered. When a paired agent's
pairing ends while its call runs, the answer is replaced as it leaves: a
`tools/call` with a tool result, `isError: true` at 200, its text
`{"error": {"code": "agent_not_paired", …}}` as a tool's own refusal is; any other
request with the refusal above.

Before any credential is looked at, McpAgent refuses: a query string
(`unsupported_query`, 400), any address but `/mcp` itself (404) and any method but
POST (405), a page on another site (`origin_not_allowed`, 403: any `Origin` but the
site's own, `null` included; no `Origin`, as MCP clients send, goes on), a body
that is not JSON (415) and a JSON-RPC batch (`batch_not_supported`, 400), so one
signature covers one call.

Every request then carries exactly one credential; there is no anonymous MCP.
Public reads are on the HTTP API and the browser tools. A Bearer token selects the
connector: it must be live, for this site's `/mcp` resource and carry
`regent.identity.manage` (`RegentOAuth.verify/3`); any other is refused with 401
and `WWW-Authenticate: Bearer resource_metadata=…`, which starts Claude's sign-in.
A request with no credential at all gets the same: 401 `connection_required` with
the challenge, so Claude's first request starts the sign-in, and the hint also
tells an agent to sign its calls with `regents mcp --site <this site>`. While the switch is off a
token is refused with 401 `delegated_access_not_enabled`, a request with no
credential with 401 `agent_auth_required`, neither with a challenge, and the
connector's tools are not listed. A token beside an agent's signature is refused
as `ambiguous_credentials`. The route is not logged: tool calls carry pairing
codes. AshAi serves each POST as one JSON-RPC message in the version the client
asks for, `initialize`, `ping`, `tools/list` and `tools/call` among them, and keeps
nothing between requests.

Budgets, all counted by the site's `RequestRateLimiter` with the RateLimit
headers of `RegentAgentAccess.RateLimit`. In the endpoint, before its body is read, a request with no
token counts 120 a minute against its address (`mcp_address`, the API's figure),
and while the switch is on, one with a token counts against its address's ceiling
of 600 a minute (`mcp_connected_address`), since Claude's connector calls from
Anthropic's shared servers and one address carries many accounts. While it is off,
no token is this site's, so every request counts against the 120 alone, whatever
headers it carries, its body read or not. A token `RegentOAuth.verify/3`
accepts then counts against its connected account's own 120 under its OAuth subject
(`mcp`); one that isn't this site's counts against its address's 120 as well when
McpAgent refuses it. Once an address has spent its 120, its next request with a
token is refused 429 in the endpoint, before the token is looked up, so a stream of
made-up tokens costs the sign-in store at most 120 lookups a minute from one
address. Every answer from `/mcp` says `cache-control: private, no-store`, set as it
leaves, over AshAi's own `no-cache` on a streamed answer. A tool's arguments are checked against its action before it
runs (`AshTemplateWeb.ToolErrors.check_input/3`), so bad input is refused with the
codes the HTTP API uses. A refused identity tool call is the tool's error, whose
text is `{"error": {"code", "message", "hint"}}`: the site's own refusal of the
signed request, with `retry_after` when it sent one (`agent_not_paired`, a rate
limit), or the library's refusal made before signing (`pairing_code_unknown`).
When no answer came, the code is `identity_request_refused` with the site's own
words (`config :regent_mcp_agents, :config, refusal:`). `pair_identity` lists the harness and the name and code
lengths the library takes.

## Issuer and resource from the site's host

The issuer is the site's own address and the resource is its `/mcp`, set at
runtime: `https://PHX_HOST` in production, the endpoint's address elsewhere
(`http://localhost:4000` in development). Nothing names the template's own address
in code, so a site cut from the template, and its staging, get their own.

Tokens freeze that binding at issuance: the provider writes the running site's
issuer and resource on each code and token as it is issued
(`oauth_tokens.oauth_issuer` and `mcp_resource`), and `RegentOAuth.verify`
refuses a token whose values differ from the running site's. No migration needs
the site's address: `20261014170000_add_oauth_provider` makes the tables with
`RegentOAuth.Migration.up()`, and `20261028120000_oauth_connector_tokens` runs
`RegentOAuth.Migration.V2`, which drops the old column defaults. Rows already
there keep the values they have, so tokens issued for the old resource (the bare
origin) stay refused and their apps connect again. Moving a site to a new address
works the same way: tokens issued at the old one are refused and their apps
connect again.

## Hashed tokens

Access and refresh tokens are stored only as their SHA-256 hash
(`RegentOAuth.hash_token/1`) and looked up by it; the plain tokens reach the app
once. The same migration runs `RegentOAuth.Migration.V2`, which rewrites every
stored access token row in place (`value`, `refresh_token`, `previous_token`), so
an app connected before it keeps working. It is up only, with
`SET LOCAL lock_timeout = '5s'`, and cannot be undone. The template has live
OAuth rows on the shared production database, so this migration changes
production data: it is protected and runs only with Sean's letter naming it.
Authorization codes stay as Boruta keeps them.

## Rollout to the sites

This is a shared change under the "Shared changes" rule (regent-workflow): built
and checked in the template, released on its hosted demo with the switch on only after
Sean's letter for the migration, then signed off by Sean as a numbered decision
with the template link and the checks below, and only then handed to all five
sites at once in one rollout file. Each site makes its own version (its own
switch name, title, about line, refusal words and guide in its own voice), runs
its own hashing migration on its own schema with its own letter, and records its
commit, release and rollback in its row. Keyfleet's hand-written MCP controller
(branch `claude/claude-connector-fixes-1027`) is replaced by this server and is not
taken. Patchbay keeps `hosted_pairing: [:chatgpt]` and its own refusal words.

Before the switch is turned on anywhere, the site must have completed consent,
callback, refresh, disconnect and host checks, and the `/mcp` checks: a first
request with no token answered 401 `connection_required` with the
`WWW-Authenticate` challenge, initialize and
tools/list with a token, a revoked token refused and the per-account limit. One shared piece is still missing: design-system's `Regent.Account` has no
picture for the `claude` harness (`@agent_pictures`, `Map.fetch!`), so a pairing
box offering Claude, or any list showing a paired Claude, raises until
design-system adds one and the template takes that `regent_ui` pin.

All shared packages use one reviewed `elixir-utils` Git commit, including OAuth.
The template's existing `REGENT_ELIXIR_UTILS_PATH` development override also covers
OAuth and the MCP identity library; production refuses that override. Normal local integration
checks fetch the exact pins from the local shared repository without changing the
recorded URLs. Publish the reviewed shared commit before a separately authorized
consumer release so its builds can fetch the exact pin.
Site-owned migrations create and change the OAuth tables; this change does not run
production migrations.

Use Ash Signals for ordinary resource-change reactions where appropriate. They do
not replace an ordered, replayable MCP event log: write that log in the same
transaction as the domain action and use AshOban for delivery and retries. This
auth service adds no new domain-event producer, queue or polling loop. Patchbay's
existing committed event stream remains canonical. The template's `/mcp` offers
no events.

Local checks use stand-in accounts and an isolated loopback database. They cannot
establish real Privy or Claude acceptance. Money tests and Points activation are
outside this integration. Publishing and deployment require applicable authority;
live consent requires its own verification.

## Integration verified on 14 October

This reference is integrated against template main `905b1bee0c27ba61fafa4261e417fc9d5310a8e7`,
with all shared libraries pinned together at
`edb97f1c1bb7cc9ce1aa02f4646eea18f7f8923d`. The older primary checkout's
uncommitted draft is not the integrated reference.

Compilation, changed-file formatting, usage-rule synchronization, route handoff,
the dependency audit and the proposed required-fixes check passed. The actual
template session/consent routes were exercised against a named loopback database:
caller-supplied account IDs and stale sessions were refused; a current verified
account could consent and exchange its code. The additive migration ran only in
that local fixture. OAuth's default-off configuration and inactive Points were
checked separately.

Independent security review found and closed request-object input leakage,
cross-client revocation, refresh/revoke races and old revoked credentials affecting
fresh consent. Representative local checks covered each failure. The template
retains its existing Signals compiler and supervision; it adds no event producer.
See [the server security update](server-security-2026-10-14.md) for the Bandit fix.

## Consent browser repair — 15 October

The reference now carries shared commit
`28783ed77b4c6f5240f35a77146e06611abb23a6`, on the complete dependency baseline.
All Hex locks, the AshPostgres hold and the Bandit security pin remain unchanged.
OAuth remains off on the template, which has no MCP endpoint.

Consent uses the existing same-origin stylesheet and shared controls, with the
site's configured brand and theme. Only its consent document permits the
preauthorized registered callback origin in form-action; Chromium also checks
the redirect following approval. Other directives and independent browser
policies are preserved. Exact callback/account/scope/PKCE/CSRF/nonce/lifetime
checks remain required. Consumed or expired requests return a readable HTTP401
restart page, never a new grant.

The signed-cookie and actual-browser local exercise reproduced the old blocked
return and verified the corrected return to another origin. Independent security
review closed a combined-policy preservation finding. These are representative
checks, not real Privy/ChatGPT acceptance. Adopters must begin a fresh connection
from their client, then verify consent, token exchange, event subscription,
callback challenge, genuine delivery and unsubscribe separately. This correction
adds no migration, grant, queue or event producer. Money tests and Points stay off.
