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

An app names itself in one of two ways. Claude's "Use Claude's published
identity" option uses its HTTPS address
(`https://claude.ai/oauth/mcp-oauth-client-metadata`) as the `client_id`; server
metadata says `client_id_metadata_document_supported: true`, and consent reads
and checks that document, records it as an ordinary public client
(`oauth_client_documents`, migration `20261029160000`) and reads it again once
its cache lifetime passes (`RegentOAuth.ClientDocuments`). Other apps still
register themselves at `/oauth/register`. Neither kind is ever taken for the other.

API routes expose resource/server metadata (the resource's also at
`/.well-known/oauth-protected-resource/mcp`, where RFC 9728 places it),
`/oauth/register`, `/oauth/token` and `/oauth/revoke`. Browser routes are GET/POST
`/oauth/authorize`, GET `/oauth/connections` and POST `/oauth/connections/revoke`.
Credential routes disable logging; the existing address limiter bounds registration
and token requests. A connected-app link is present on consent pages. There is no
change to Account's existing social-connections page.

## The Claude connector: one switch

`ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED=true` turns on everything at once, read at
boot by `config/runtime.exs`; anything else leaves all of it off:

- the sign-in above (`AshTemplate.OAuth`, `RegentOAuth.enabled?/0`), with
  `RegentOAuth.Repo` supervised;
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

The one permission is `regent.identity.manage`: the app may keep an identity for
itself, pair it with the account using a code the person gives it, and check in.
It cannot post, spend Credits, make payments or change wallets. The template's
earlier reference scope, `mcp.events.read`, is gone; an app registered for it
connects again.

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
same server offers the room tools (`rooms_messages` and `rooms_post`) to an agent
signing each call, which a connected app neither sees nor runs.

Before any credential is looked at, McpAgent refuses, in the site's
`{"error": {"code", "message", "hint"}}` shape: a query string
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
tells an agent to sign its calls with `regents mcp`. While the switch is off a
token is refused with 401 `delegated_access_not_enabled`, a request with no
credential with 401 `agent_auth_required`, neither with a challenge, and the
connector's tools are not listed. A token beside an agent's signature is refused
as `ambiguous_credentials`. The route is not logged: tool calls carry pairing
codes. AshAi serves each POST as one JSON-RPC message in the version the client
asks for, `initialize`, `ping`, `tools/list` and `tools/call` among them, and keeps
nothing between requests.

Two budgets: the endpoint counts each address first, then McpAgent counts each
connected account under its OAuth subject (`mcp`, 120 a minute), both through
`RegentAgentAccess.RateLimit` and the site's `RequestRateLimiter`. A request with
a Bearer token counts against its address's ceiling of 600 a minute
(`mcp_connected_address`), since Claude's connector calls from Anthropic's shared
servers and one address carries many accounts; any other request counts 120 a
minute (`mcp_address`, the API's figure). A tool's arguments are checked against its action before it
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
(`http://localhost:4000` in development). Nothing names `template.regents.sh` in
code, so a site cut from the template, and its staging, get their own.

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
and tested here, released on template.regents.sh with the switch on only after
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
`WWW-Authenticate` challenge (`claude_connector_test.exs`), initialize and
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
