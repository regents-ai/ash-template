# Ash Template platform

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](../LICENSE)
[![Elixir 1.20](https://img.shields.io/badge/elixir-1.20-lightgrey)](https://elixir-lang.org)
[![Phoenix 1.8](https://img.shields.io/badge/phoenix-1.8-lightgrey)](https://www.phoenixframework.org)
[![Ash 3.34](https://img.shields.io/badge/ash-3.34-lightgrey)](https://ash-hq.org)

The Phoenix/Ash web application of Ash Template. It serves the public home
page, Privy sign-in, the signed-in Overview (`/app`) and Account
(`/account`) pages, the public pages, a health check, the public HTTP API, and
Prometheus metrics on a private port.

## Shared dependencies

The shared Regent libraries are git dependencies, each pinned to one published
commit at the top of `mix.exs`: `regent_ui` from `design-system`, `regent_privy`,
`regent_agent_access`, `regent_format` and `credo_ash` from `elixir-utils`, and
`regent_identity` from `regents`. `mix deps.get` fetches them; `mix.lock`
records the commit. To take a newer version, push the change to that
library's `main`, set the new commit in `mix.exs` and run
`mix deps.update <name>`. Every library from one repository stays on one commit.

Some shared libraries name another by a sibling folder, which does not exist in a
git checkout, so the site pins that one itself with `override: true` at the same
commit: `regent_identity` names `regent_privy` (see `mix.exs`),
`regent_mcp_agents` names `regent_oauth`, `regent_agents` and
`regent_agent_access`, and `ens_elixir` names `siwa`, so a site using ENS adds
`{:siwa, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "siwa/siwa-elixir/apps/siwa", override: true}`.
`ens_elixir` also needs Req 0.7.

`../security/required-fixes.json` lists every shared library with its one
repository and folder, and the security fixes every Regent site must carry.
`make check-required-fixes` fetches that list and `scripts/check_required_fixes.exs`
from this repository's `main` on GitHub and runs the script, printing the
revision it used. It fails when a shared library loads from a local folder or a
vendored copy, names another URL or folder, is not pinned to a full commit, has
no fetched history, or lacks a listed fix, and when a Hex package's locked version
is outside a listed fix's requirement. Library pins never change by themselves; only the list does.
`mix hex.audit` in `mix precommit` stops on a Hex package that is retired or has
a published security advisory (Hex 2.5 reads both).

### MCP events

A site whose MCP endpoint offers events (protocol `2026-07-28`: `server/discover`,
`events/list`, `events/subscribe`, `events/unsubscribe`, delivered by webhook) takes
`regent_mcp_events` from `elixir-utils/mcp_events`. The template's MCP address
(`/mcp`) offers no events and does not use it. The library is in elixir-utils commits `194896a` and `c1544e5`,
which are not yet on GitHub, so no site can pin it until they are pushed; it
then rides the site's one elixir-utils pin like every other library from there:
`{:regent_mcp_events, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "mcp_events"}`.

The library owns subscription ids, the signed callback challenge and one safe,
signed delivery attempt (`deliver/2`). It ships no queue or worker. The site owns:

- The event methods on its existing MCP endpoint, with the subscription owner taken
  from the signed-in connection, never from the request.
- A subscriptions table holding the callback, its encrypted secret, whether it is
  active, and `delivered_seq`, its place in a commit-ordered event feed. No lease,
  attempt or retry columns: Oban keeps those.
- Delivery as an AshOban trigger on that table, following the ordered-delivery
  recipe in the `elixir-stack` skill (`skills/elixir-stack/references/oban.md`): one
  job per subscription, queued in the same transaction as each new event, on
  subscribe and on refresh, and swept every minute. The job sends owed events in
  order outside any transaction, moves `delivered_seq` with a compare-and-set,
  retries a failure that may pass, and on a refusal or the last attempt stops the
  subscription where it is; a refresh resumes it from the same event.

Patchbay is the first site with events: `PatchbayWeb.MCP.Events` serves the
methods, `Patchbay.Forum.EventSubscription` holds the subscriptions (signing secrets
encrypted under `secret_key_base`) and carries the `:deliver` trigger, and
`PatchbayWeb.MCP.EventDelivery` is its delivery action. Its `/mcp` route is declared
with `log: false` so the secret and callback address never reach the request log.

### Hosted MCP tools

The agent access spec's hosted `/mcp` runs on AshAi (`{:ash_ai, "~> 1.4.1"}`). Its
tools are the `tools do` entries in an Ash domain, each naming the same Ash action the
HTTP route, the browser tool and the command already run, so every surface answers the
same words and refusals. The Rooms domain has the first two: `rooms_messages`
(`Message.room_messages`, a public read) and `rooms_post` (`Message.agent_post`, a signed
write). The Agents domain has the Claude connector's four identity tools
(`AshTemplate.Agents.Connection`), which only an app a person connected may run. The chat
assistant lists its own two tools, so it never reaches these.

`forward "/mcp", AshAi.Mcp.Router` serves exactly the tools `priv/capabilities.json`
marks hosted (`AshTemplateWeb.Capabilities.hosted_tools/0`), in every protocol version
AshAi answers, keeping nothing between requests. The `:mcp` pipeline takes JSON only,
then `AshTemplateWeb.Plugs.McpAgent` admits the request and says who is calling, as the
agent access spec (4.3) sets out. Before any credential is looked at it refuses a query
string, any address but `/mcp` and any method but POST, a page from another site (any
`Origin` but the site's own; no `Origin` goes on), a body that is not JSON and a
JSON-RPC batch, so one signature covers one call. Then every request carries exactly
one credential; there is no anonymous MCP, and public reads are on the HTTP API and the
browser tools:

- an agent's signature (`Siwa.AgentAuthPlug.signed_request?/1`) is checked by
  `AshTemplateWeb.Plugs.AgentWallet`, unchanged, and the agent is the actor;
- a Bearer token must be the connector's, for this site's `/mcp`, and the connected app
  is the actor, under its account's budget; any other token gets 401 with the
  challenge that starts sign-in, and while the connector is off 401
  `delegated_access_not_enabled`;
- both together get 401 `ambiguous_credentials`;
- neither gets 401: `connection_required` with the challenge while the connector is on,
  so Claude's first request starts its sign-in, and `agent_auth_required` while it is
  off.

Ash policies decide the rest: a connected app sees and runs only its identity tools,
and `rooms_post` only an agent. Every call carries the client's address key
(`client_key`). Answers are `cache-control: private, no-store`. A tool's own refusal is
its error, whose text is the HTTP refusal's JSON, `{"error": {"code", "message",
"hint"}}` (`AshTemplateWeb.ToolErrors`); an input the action cannot take is checked
before the tool runs (`ToolErrors.check_input/3`) and refused with the code the HTTP
route uses (`invalid_limit`, `invalid_message`, a pairing's `invalid_request`). `[:ash_template, :mcp, :auth]` counts each
request by how it came in and whether it was taken.

`priv/capabilities.json` carries `contract_revision` and, for each operation, its
`surfaces` (`webmcp`, `hosted_mcp`, `http`, `cli`: `true`, or the reason it is left
out), `auth_modes`, `fresh_proof`, `actor`, `context`, `retry` and `lifecycle`.
`AshTemplateWeb.Capabilities` stops the build when these disagree with the browser tool,
the command, the AshAi tools or each other: a hosted tool with no AshAi tool, an AshAi
tool named like a browser tool but not marked hosted, hosted input that differs from the
browser tool's, a public operation that needs proof, an operation-key retry with no
`operation_id` field, or a surface left out with no reason. A tool only the hosted
server has is a row of its own, named after its tool (`getIdentity` is `get_identity`),
with every other surface's reason and its answer's schema among `/openapi.json`'s
components. `/capabilities.json` adds each operation's `output_schema`, its success
answer in `/openapi.json`.

An agent's room post spends its `operation_id` once in `agent_operations`
(`AshTemplate.Agents.Operation`: agent, capability, key, a hash of the room and text,
and the message it posted), in the same transaction as the post and before it, under a
unique index. The same key with the same room and text answers the first post; with
anything else it is refused as `idempotency_conflict` (409); after that message was
deleted, as `message_removed` (410) naming it. Rows are kept, so a key stays spent. The
table's migration (`priv/repo/migrations/20261028154117_agent_operations.exs`) needs
Sean's letter naming the release before it runs in production.

## Quickstart

Run these from `platform/`. You need
Erlang, Elixir, Node and PostgreSQL at the versions pinned in `.tool-versions`.

```sh
cp .env.example .env
touch .env.local
printf '%s\n' 'source_env .env' 'source_env_if_exists .env.local' > .envrc
mix setup
mix ecto.create
# Put the Privy values in .env.local first (docs/local-privy-auth.md).
direnv allow
mix ash_template.setup_local_auth
mix phx.server
```

The site is then at `http://localhost:4000`. Sign-in needs real Privy
credentials; [docs/local-privy-auth.md](docs/local-privy-auth.md) says where
they come from. Put real values only in the ignored `.env.local`, never in
`.env.example`, and commit none of the three.

Without `PRIVY_APP_ID` and `PRIVY_VERIFICATION_KEY` the site refuses to start. A
worktree has no settings files of its own, so start it from the worktree's
`platform` folder with `direnv exec <main checkout>/platform mix phx.server`.

The local server keeps its data in one loopback PostgreSQL database,
`ash_template_dev`, on `127.0.0.1`. It leaves the machine to verify sign-in with
Privy, to read wallets and names through the chain nodes
(`ASH_TEMPLATE_CHAIN_NODE_URL`), to check agents' signed requests with the agent
sign-in service (`ASH_TEMPLATE_SIWA_BROKER_URL`), and for each optional service in
[Configuration](#configuration) whose setting is set. The browser walk runs with
all of them off and fails if anything leaves the machine.

## Configuration

Read at runtime by `config/runtime.exs`. Values come from your ignored
`.env.local` in development and from the deployment's secret store in
production.

| Variable | Required | What it is for |
| --- | --- | --- |
| `PRIVY_APP_ID` | For sign-in | The Privy application that browser sign-in runs against. |
| `PRIVY_VERIFICATION_KEY` | For sign-in | Privy's ES256 verification **public** key, not the app secret: the PEM with real line breaks, for example `fly secrets set PRIVY_VERIFICATION_KEY="$(cat privy-verification-key.pem)"`. |
| `ASH_TEMPLATE_APP_SURFACES` | Yes in production | `on` opens the signed-in pages and `off` closes them. Any other value stops the boot, and so does leaving it unset in production. Development is `on` when unset. |
| `ASH_TEMPLATE_SHOWCASE` | Yes in production | `off` or `public`; see [Showcase](#showcase). Any other value stops the boot in production. Development takes `local`, `public` or `off` and is `local` when unset. |
| `ASH_TEMPLATE_CHAIN_NODE_URL` | No | The node the server reads the wallet chain through, such as a private node whose address carries a key. Wallets are still given the chain's public address. Unset means the node in `config/config.exs` (`:chain_nodes`). |
| `ASH_TEMPLATE_NOTES_WEBHOOK_URL` | No | An `http` or `https` address each saved note is posted to, as `{"event": "note.saved", "note_id": …, "revision": …}` without the note's text. A failed post is retried four more times and then recorded on the note. Unset means saving a note posts nothing. Any other kind of address stops the boot. |
| `ASH_TEMPLATE_INDEXNOW_KEY` | No | This site's IndexNow key, 8 to 128 letters, digits or dashes; make one with `openssl rand -hex 16`, one per site. Set it only where the site serves its public address. It is public: `/indexnow-key.txt` serves it. Each release's public pages are then sent once to IndexNow (Bing, which ChatGPT search reads, and others), and the site can queue `AshTemplate.IndexNow.submit/1` for a page it adds or changes. Unset means nothing is sent and `/indexnow-key.txt` is not found. Any other value stops the boot. |
| `ASH_TEMPLATE_SIWA_BROKER_URL` | No | The sign-in service that checks agents' signed requests, such as one running on this machine. Unset means `https://siwa.regents.sh` (`config/config.exs`, `config :regent_agents, siwa: [url: ..., audience: "ash-template"]`). |
| `ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED` | No | `true` switches the Claude connector on, all of it at once: the sign-in routes under `/oauth` and `/.well-known/oauth-*`, its identity tools at `/mcp`, Claude in the pairing box and the signed pair request, and the Claude guide at `/agents/claude` with its `skill.md`, which `/agents`, the sitemap, `/llms.txt` and `/agents.md` then name. Anything else leaves it all off: the guide is not found, `/mcp` refuses a Bearer token and a request with no signature, and `/llms.txt` names no connector. It needs `SIWA_HOSTED_SIGNING_KEY`, and the migration `20261028120000_oauth_connector_tokens` must have run first. That migration runs with the release that carries it, switch on or off, and rewrites the stored tokens in place, keeping only their hashes: on the shared production database that release waits for Sean's letter naming it. [docs/oauth-reference.md](../docs/oauth-reference.md) has the rest. Before the first release that switches it on, confirm the staged key has the right shape without printing it (its length and characters only), or the boot stops. The browser walk's development server (`ASH_TEMPLATE_WALK=true`) has it on, with a key it makes each time it starts; no other environment can turn it on that way. |
| `SIWA_HOSTED_SIGNING_KEY` | With the connector | This site's own key at the sign-in service, which holds the connector's identities for the `ash-template` audience: 32 or more letters, digits, `-` or `_`. With the connector on and no such key, the boot stops with a message naming this setting. Never shown to a client. The service is the one `ASH_TEMPLATE_SIWA_BROKER_URL` names. |
| `SIWA_ACTIVITY_READ_TOKEN` | No | The reader key for the sign-in service's agent activity, which gives the account menu each agent's last active site and the Agents page each agent's sites by day. `AshTemplate.Agents.ActivityReading` keeps each agent's reading for five minutes. Unset means neither shows activity. |
| `PHX_HOST` | Yes in production | Public hostname the endpoint builds URLs from. The Claude connector's sign-in (its issuer) is `https://PHX_HOST` and its resource is `https://PHX_HOST/mcp`; each code and token records them as it is issued, so moving the site to a new address means its connected apps connect again. |
| `SECRET_KEY_BASE` | Yes in production | Session signing secret; at least 64 bytes. |
| `PORT` | No | HTTP port. Defaults to `4000`. |
| `REGENT_CREDITS_ADMINS` | No | Comma-separated Privy user ids of the Credits admins. Only they can open the saved errors at `/admin/errors`; anyone else gets the not-found page. |
| `STRIPE_SECRET_KEY` | For card payments | Stripe's secret key. Set, the Credits panel offers Card or Link beside USDC on Base; see [Card and Link payments](#card-and-link-payments). A test key (`sk_test_…`) offers it to the Credits admins only. Unset means USDC only, and `/api/stripe/notices` is not found. |
| `STRIPE_WEBHOOK_SECRET` | With `STRIPE_SECRET_KEY` | The signing secret (`whsec_…`) of the Stripe endpoint that sends `/api/stripe/notices`. The boot stops without it once the secret key is set. |
| `STRIPE_PUBLISHABLE_KEY` | With `STRIPE_SECRET_KEY` | Stripe's publishable key (`pk_test_…` or `pk_live_…`), which the page gives Stripe's payment form. The boot stops without it once the secret key is set. |
| `ASH_TEMPLATE_DEPLOYMENT_ROLE` | Yes in production | `production` or `staging`. There is no default; each role admits only its own database hosts. |
| `DATABASE_POOLED_URL` | Yes in production | PostgreSQL connection string the running site uses, for an approved host. Production admits only the database's pooler, `pgbouncer.dzx6qo6xqzvojpv5.flympg.net`. |
| `DATABASE_DIRECT_URL` | Only when migrating | Direct PostgreSQL connection string used by the migration release command. |
| `ASH_TEMPLATE_DATABASE_TARGET_MODE` | Only when migrating | Must be `production` for the production migration command. |
| `ASH_TEMPLATE_DATABASE_CLUSTER_ID` | For a remote target | Must match the approved cluster. Set neither this nor the name to stay on the loopback database. |
| `ASH_TEMPLATE_DATABASE_CLUSTER_NAME` | For a remote target | Must match the approved cluster name. |
| `ASH_TEMPLATE_RELEASE_COMMAND` | Set by the release | `migrate` switches the boot into migration mode. |

### Two database logins

The site signs in to the shared production database under two logins, and never
uses one for the other's work.

- **The serving login** (`DATABASE_POOLED_URL`) is what the running site uses. It
  is a Fly Managed Postgres user with the `writer` role: it reads and changes
  records, but cannot create, change or drop tables. It serves through the
  database's pooler in transaction mode, which many sites share for a few real
  connections, so a release's second machine adds no load on the database's own
  limit. It holds five connections through the pooler, shows up as
  `ash-template-web`, and gives up on a statement after 15 seconds, a lock wait
  after 5 seconds and an idle open transaction after 15 seconds
  (`AshTemplate.DatabaseConfig`). The same login also holds one connection on the
  direct address, `ash-template-listen`, on which Credits and agent changes from
  every site arrive (`AshTemplate.SharedChanges`): the pooler drops listening.
- **The release login** (`DATABASE_DIRECT_URL`) is a user with the `schema_admin`
  role, used only while a release goes out: the release command runs the
  migrations with it and then exits. The running site never reads it.

### Card and Link payments

Credits can be bought by card or Link through Stripe as well as with USDC on Base
(`RegentCredits.CardPurchase` in elixir-utils). The buyer pays the Credits plus the
card fee shown before Continue; Stripe's own form takes the email, card or Link.
The Credits are added once, from Stripe's record of the payment, whichever comes
first: the panel when Stripe says the payment went through, or Stripe's signed
notice. A refund takes them back; a dispute takes them back and pauses card
purchases until the account's Credits are above zero again.

To turn it on for a site:

1. In Stripe, under **Settings → Payment methods**, turn on Cards and Link.
2. Under **Developers → Webhooks**, add an endpoint at
   `https://<site host>/api/stripe/notices` sending `checkout.session.completed`,
   `checkout.session.async_payment_succeeded`, `charge.refunded` and
   `charge.dispute.created`, and copy its signing secret.
3. Set `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` and `STRIPE_WEBHOOK_SECRET`
   (on Fly with `fly secrets set --stage`, then release). Use the test keys first:
   only the Credits admins see the choice, and a test card such as
   `4242 4242 4242 4242` adds real Credits to their account.

Locally, `stripe listen --forward-to localhost:4000/api/stripe/notices` prints a
signing secret for `STRIPE_WEBHOOK_SECRET`; without it the panel still adds the
Credits when Stripe says the payment went through.

## Public HTTP surface

`contracts/api-contract.openapiv3.yaml` is the source of truth for the API and
is served at `/api-contract.openapiv3.yaml` with `x-regents-contract-major` and
`x-regents-contract-digest` headers. The table is a map, not the contract.

| Route | Method | Purpose |
| --- | --- | --- |
| `/healthz` | GET | Liveness check; plain text `ok`. |
| `/api/v1/profile`, `/api/v1/profile/sync` | GET, PATCH, POST | The signed-in person's shared profile, served by the `regent_identity` package with paired Privy proofs. |
| `/auth/csrf`, `/auth/session`, `/auth/privy/session`, `/auth/privy/failure` | GET, POST, DELETE | Browser session start, read and end. |
| `/openapi.json`, `/llms.txt`, `/sitemap.xml`, `/robots.txt` | GET | Discovery documents. |
| `/`, `/docs`, `/about`, `/contact`, `/privacy`, `/terms` | GET | Public pages; `Accept: text/markdown` returns Markdown. |
| `/agents`, `/agents/<agent>` | GET | The agents people pair and a page for each, from `priv/public/agents/`; `Accept: text/markdown` returns Markdown. Open while the site is closed. Claude's page exists only while the Claude connector is on. |
| `/agents/<agent>/skill.md` | GET | That agent's skill: the agent guide with its set-up notes. |
| `/app`, `/account` | GET | The signed-in shell. |
| `/mcp` | POST | The hosted MCP server (`AshAi.Mcp.Router`, after `AshTemplateWeb.Plugs.McpAgent`): an agent signing each call reads a room with `rooms_messages` and posts with `rooms_post`; the Claude connector's Bearer token (`regent.identity.manage`) runs only its identity tools, which keep an identity for the connection, pair it, read the pairing and check in. A bad token, or none, gets 401 with the challenge that starts sign-in; a token or no signature while `ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED` is off, and a token beside a signature, get 401 with none. A query string, a batch, a body that is not JSON and a page from another site are refused before any credential is read. 120 requests a minute from one address for agents' signed requests; requests with a Bearer token share a ceiling of 600 a minute per address, since Claude's connector calls from shared servers, then 120 a minute for each connected account. Other methods answer 405; not logged. |
| `/.well-known/oauth-protected-resource`, `/.well-known/oauth-protected-resource/mcp`, `/.well-known/oauth-authorization-server`, `/oauth/register`, `/oauth/token`, `/oauth/revoke` | GET, POST | The connector's sign-in discovery, app registration, tokens and revocation (`RegentOAuth.Protocol`). Registration (30 a minute) and token and revocation requests (120 a minute) are limited by address and never logged. 404 while the connector is off. |
| `/oauth/authorize`, `/oauth/connections`, `/oauth/connections/revoke` | GET, POST | The consent page under the signed-in browser session, and Connected apps, where a person sees and disconnects their apps (`RegentOAuth.Consent`). They refuse while the connector is off. |
| `/api/stripe/notices` | POST | Stripe's signed notices about card and Link purchases of Credits; found only while `STRIPE_SECRET_KEY` is set. |

## Showcase

The showcase pages (`/showcase`, its catalog and preview, `/showcase/privy`, the
wallet page `/showcase/wallet`, the payment example `/showcase/payments`, the funds example `/showcase/funds`), the motion lab (`/animations` and its pages, such as the ten wonders `/animations/wonders`, the agent harbour `/animations/harbour` and its island pages `/animations/harbour/inn`, `/animations/harbour/forge` and `/animations/harbour/castle`, and the swarm city `/animations/swarm-city` and its district pages `/animations/swarm-city/inn`, `/animations/swarm-city/forge` and `/animations/swarm-city/castle`, each in fourteen looks chosen by `?look=`, four of which follow the light or dark theme) and the build
skills (`/skills`, the agent guide `/skill.md` and
`/.well-known/agent-skills/`) follow one setting, `ASH_TEMPLATE_SHOWCASE`,
which `config/runtime.exs` reads and `AshTemplateWeb.Showcase` enforces:

| Setting | Where | What happens |
| --- | --- | --- |
| `local` | Development (the default when unset) | The showcase pages answer only a visitor on this machine at `localhost` or `127.0.0.1`, and are never cached or indexed. The motion lab is open. The home page links to them. |
| `public` | The hosted demo at template.regents.sh | Every page above is public, listed in the sitemap and `/llms.txt`, and linked from the home page. |
| `off` | A new site's production | None of them exist: each answers 404 and the home page does not link to them. |

Production must set it to `off` or `public`; `fly.toml` leaves it out, so each
deployment says which it is with `fly secrets set ASH_TEMPLATE_SHOWCASE=off` (or
`public`). A new site built from this template chooses `off`.

The wallet page at `/showcase/wallet` runs the wallet buttons with real sign-in
and a real wallet on the chain set as `:wallet_chain` in `config/config.exs`
(Base Sepolia, chain 84532). A press there needs a little Base Sepolia test ETH
for the network fee. The wallet lab at `/showcase/onchain` sends to a lab chain
on this machine, so it exists only in `local`, and only for a visitor on this
machine. The payment example at `/showcase/payments` shows a USDC payment with
sample figures and Pay switched off: the shared payments library takes real USDC
on Base only, so the demo takes none. The funds example at `/showcase/funds`
shows wallet funds, commitments, card purchases, sends and cash-outs the same
way, with sample figures and every money button switched off.
[docs/showcase.md](docs/showcase.md) describes the pages.

The build skills are ten of the repository's `skills/` folders (the Ash, motion
and wallet skills, never the Regent workflow ones), read when the app compiles
by `AshTemplateWeb.AgentSkills`. `/.well-known/agent-skills/index.json` lists
them in the Agent Skills Discovery v0.2.0 format, each as a zip of its folder
with the zip's sha256; every file is also served on its own under
`/.well-known/agent-skills/<skill>/`. `/skill.md` tells an agent how to fetch
and check them, and `/skills` lists them for people.

## Security profiles

`lib/ash_template_web/content_security_policy.ex` holds every page's content
security policy; the router's pipelines choose one.

| Profile | Pipelines | What it allows |
| --- | --- | --- |
| `reading` | `:public_documents` | The strict baseline: scripts, styles, images and fonts from this site, requests and the live connection back to it, inline style attributes (the shared ratio card and Anime.js text splitting), no frames, never framed. |
| `sign_in` | `:browser`, `:showcase_browser` | The baseline plus Privy sign-in: Privy's API and frame, Cloudflare Turnstile, WalletConnect's relay, verify frame, wallet list and logos, RPC and event reporting, Coinbase Wallet's relay, inline style elements for Privy's window, and Stripe's and Link's scripts, frames and API for card payments (the hosts Stripe lists, some as `*.js.stripe.com` and `*.link.com`). |
| `showcase` | `:framed_preview` | `sign_in` that may frame its own preview page, for `/showcase` and `/showcase/preview`. |

A site that loads something else (an RPC, an image host, an embedded wallet)
adds each exact origin to the one directive in the one profile that needs it:
`@sign_in` for anything the wallet or sign-in pages use, `@baseline` only for
what every page loads. Never add `https:`, `*`, a whole-domain wildcard or
`'unsafe-eval'`; the only wildcards are the ones Privy and Stripe publish for
their own hosts (`*.rpc.privy.systems`, `*.js.stripe.com`, `*.stripe.com` and
`*.link.com`).
After a change, load each affected page and the sign-in window
and check the browser console for "Content Security Policy" errors.

Rate limits key on the client address from `AshTemplateWeb.ClientAddress`. In
production (`:behind_fly_proxy`, set in `config/prod.exs`) that is the one
`Fly-Client-IP` header Fly's proxy writes, replacing anything a client sent, on
the proxy's own connection over the machine's private IPv4 address. Another of the
organisation's apps reaching the machine directly over 6PN (IPv6) is keyed by its
own address, whatever header it sends. Everywhere else it is the direct peer. `X-Forwarded-For` is never read. A site
that puts another proxy in front of Fly must change this first.

Prometheus metrics are served only by `AshTemplateWeb.Metrics` on port 9091
(`/metrics`), which `fly.toml` and `fly.staging.toml` declare under
`[metrics]`. Fly sends public traffic only to the `[http_service]` port, so the
metrics port is reachable from the app's private network, where Fly's scraper
reads it, and not from the internet. Locally it listens on loopback, on a port the
system picks (`config/config.exs`), so sites run side by side without sharing 9091.
`/healthz` stays public on the site's own port.

The reporter is Peep (`AshTemplateWeb.Telemetry`). It keeps fixed counters for
each series and holds nothing between scrapes, and it adds every observation to
a running total as a whole number. So times are measured in whole microseconds
(`*_microseconds`) and Jev's charges in billionths of a dollar
(`ash_template_jev_cost_nanodollars`), and every total is exact. Histogram
buckets count observations at or below their bound
(`AshTemplateWeb.Telemetry.Buckets`).

## Repository layout

```text
lib/ash_template/       Ash domains: accounts, sign-in, legal documents
lib/ash_template_web/   Endpoint, router, live pages, controllers, components
lib/mix/tasks/          Local setup, contract sync and route-handoff checks
test/                   The sign-in and Credits tests (see Checks)
contracts/              The OpenAPI contract
config/                 Compile-time and runtime configuration
assets/                 TypeScript and CSS, built with esbuild; the hashed
                        script pieces go in priv/static/assets/js/chunks,
                        which browsers keep for a year
priv/                   Migrations, public and legal Markdown, static assets
docs/                   Local setup guides
scripts/                Release helpers
rel/                    Release overlays, including the migrate command
```

## Checks

From the monorepo root, `make check-platform` runs this component's gate and
`make check` runs every component's:

```sh
mix precommit
mix test
```

`mix precommit` ends by copying the shared libraries' assets, then runs `npm run
typecheck`, `npm test` and the browser walk (`npm run test:browser`). `make
check-browser` runs the walk alone. Start either with the site's settings loaded,
as the walk's server needs them.

`make check` also runs the required-fixes check (see
[Shared dependencies](#shared-dependencies)) and the command description check
(see [cli/README.md](../cli/README.md)).

`mix precommit` compiles with warnings as errors, checks unused dependency
locks, reports packages with security advisories, checks formatting, runs Credo in strict mode and Sobelow, holds the
compile-connected `xref` graph under its limit, and verifies the Ash codegen
and route handoff are current. `npm run typecheck` type-checks the TypeScript
assets, the browser walk's included. Every change proves itself (Sean, 18 Oct
2026); [docs/feature-map.md](../docs/feature-map.md) lists what a person or agent
can do and the check that proves it. Among them:

- `mix test` signs a person in and back in, because sign-in once failed for three
  days unnoticed, and walks a new person from an email sign-in without a wallet,
  through the wallet Privy gives them, to the same account at every sign-in.
- It credits a Credits purchase with the site listening to Credits' signals,
  because a listener that fails rolls the credit back.
- It checks that a paired agent's tools accept only signed proof, never a cookie.
- It races two agents on two sites for a person's last Credits, retries a lost
  pin answer, and revokes an allowance mid-session: an agent never spends more
  than its person has, never pays twice, and stops the moment its allowance
  is off. These run on real separate connections, so their rows stay in the test
  database.
- `npm test` checks that after Disconnect, a Privy session the browser still
  remembers never signs the previous person back in.
- A property test checks that each account shows the name its person set for this
  site, never one set on another site.
- It saves a Public Display Name with Privy-signed test proof, the way the Account
  page does, and checks the name then shows on that page; a forged proof changes
  nothing.
- The browser walk (`test/browser`) opens every page and document in headless
  Chromium as a desktop 1280 wide and as a touch phone 390 wide, signed out and signed
  in, opens every page again 320 wide to check it fits the narrowest phones, checks every address on each page shows its copy icon, gets a pairing code the
  way a person does, opens a paired agent's window and renames the agent, opens and
  copies the wallets a wallet note names, and opens the agent harbour's cards from its
  list and from its ships on the sea, with WebGPU turned on for that check alone.
  It builds the pages' scripts and styles, starts its own server on a free port and a
  database made for the run, `ash_template_browser_<port>_dev`, which it drops at the
  end whatever happens, even when its server never starts (`test/browser/walk.sh`),
  and signs in a local person with three agents first. Its server runs without the
  code reloader, built into `_build/walk`. Every page it opens
  is listed in `test/browser/pages.json`; `mix test` fails when the router serves one
  that is not.

`SIWA_AGENT_HOME=<the agent's key folder> SIWA_CLIENT=<its siwa_agent.py> make
live-check`, from the monorepo root, checks the live site the way a paired agent does
and writes only the agent's own row there (when it was last seen, added the first
time): `regents ash-template doctor` and `agents whoami` as
the agent whose key is in `SIWA_AGENT_HOME`, then, in headless Chromium at both widths,
the health page, the live commit from `/capabilities.json`, every public page and
document in `test/browser/pages.json` (except `local_only` labs), and every read-only
WebMCP tool that takes no input, the signed ones signed with the agent's own key through
`SIWA_CLIENT` (`../scripts/live-check.sh`, `test/live`). The signer signs only the one
request this checkout's manifest names for the tool being called. Set both, as full
paths, in the session's environment (`env` in `.claude/settings.local.json`) so `make
live-check` runs without a prompt. Run it after every release, from a checkout of the
live commit: it checks the site against this checkout's page map and manifest, and
fails first when the live commit is another.

`mix test` first creates the local `ash_template_test` database when it is missing
and brings it up to date, so a fresh copy needs only `mix setup` before `make check`.

## Deployment

Deploying runs `/app/bin/migrate` as its release command, so a deploy writes
database migrations. Every deployment names its venue in
`ASH_TEMPLATE_DEPLOYMENT_ROLE`, and each role admits only its own database
hosts. Production boot also fails unless `ASH_TEMPLATE_APP_SURFACES`,
`ASH_TEMPLATE_SHOWCASE`, `PHX_HOST` and a 64-byte `SECRET_KEY_BASE` are set.
`/app/bin/pending-migrations` reports what a deployed database and the release
image disagree about, without applying anything: `pending:`,
`applied-without-file:`, and `shared-pending:` for each shared Identity, Agents,
Credits, Points or Payments change the release carries that is not applied yet
(a deployment is refused while one is listed), or `none`.
`/app/bin/migrate-shared` applies those shared changes, and only those. Every
site carries the same command; after the founder's go, the site whose release
first carries a shared change runs it from the new image before deploying.

The image is built from `Dockerfile` with the repository root as its context:
the app is in `platform/`, and when it compiles it reads the build skills it
serves from `skills/` and the commands its capability list names from
`cli/commands.json` (`.dockerignore` at the root admits only those). The build fetches every dependency at the version the lockfiles pin.
The shared libraries' repositories are public, so the build takes no
credentials. The Fly configuration lives in `fly.toml` and `fly.staging.toml`;
`fly.toml` names no app, so every site deploys it under its own name.

Deploy from the repository root with the app's name, for the hosted demo:

```sh
scripts/deploy.sh template-regents-sh
```

It refuses a working tree with any change, a commit that is not on
`origin/main`, and a commit that does not contain the commit already live (the
live image's label, read with `fly image show`), so two crossing releases never
take live work back out. Then it runs `fly deploy . --config platform/fly.toml --app <app>
--ha=false --remote-only --image-label <short commit>`, so both folders reach
the build and the image names the commit it came from. The site serves through the
shared database's pooler, so its release needs no turn on the database. Staging deploys with
`fly deploy . --config platform/fly.staging.toml`.

A new staging database is empty and has no copy of the shared
`regent_names.platform_human_users` table, so `bin/migrate` fails on it. Its
first deploy runs `/app/bin/bootstrap-staging` once as the release command
instead (it makes that table and runs every migration); later deploys use
`bin/migrate` as `fly.staging.toml` says. Staging database URLs name
`regents-staging-db.flycast` or `.internal` on port 5432 with no query
options; Fly's `postgres attach` adds `?sslmode=disable`, which must be removed.

## Release

From the monorepo root, with Docker running and this site's Privy settings configured:

```sh
direnv exec platform make release
```

The release check requires `PRIVY_APP_ID` and `PRIVY_VERIFICATION_KEY` before
building. It passes those settings to the disposable server by environment name,
without adding them to the image or printing their values. After startup it checks
that the home page renders a nonempty Privy app id. This verifies configuration,
not a completed Privy sign-in.

It stops unless every change is committed, then runs `make check`; a failing
gate stops it before anything is built. `../scripts/release.sh` then builds
the image from `git archive` of HEAD's `platform/` and `skills/` folders and
`cli/commands.json`, reusing no cached layers, so nothing uncommitted or outside the repository
enters it, and tags it `ash-template:<commit>`. The smoke check starts a throwaway PostgreSQL 17 on
its own Docker network, answering to the staging database hostname, and runs
the image as staging with the showcase `public` against it:
`bin/bootstrap-staging`, `bin/migrate` and `bin/pending-migrations` (which must
print `none`), then the server, whose `/healthz`, home page, fingerprinted
stylesheet, build skills index and own database connection it checks. It removes the database and the network afterwards, keeps the image,
and prints the app commit, the shared-library commits from `mix.lock` and the
image digest. It never deploys.

## License

MIT, see [LICENSE](../LICENSE).
