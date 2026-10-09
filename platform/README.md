# Ash Template platform

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](../LICENSE)
[![Elixir 1.19](https://img.shields.io/badge/elixir-1.19-lightgrey)](https://elixir-lang.org)
[![Phoenix 1.8](https://img.shields.io/badge/phoenix-1.8-lightgrey)](https://www.phoenixframework.org)
[![Ash 3.34](https://img.shields.io/badge/ash-3.34-lightgrey)](https://ash-hq.org)

The Phoenix/Ash web application of Ash Template. It serves the public home
page, Privy wallet sign-in, the signed-in Overview (`/app`) and Account
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

Two shared libraries name another by a sibling folder, which does not exist in a
git checkout, so the site pins that one itself with `override: true` at the same
commit: `regent_identity` names `regent_privy` (see `mix.exs`), and `ens_elixir`
names `siwa`, so a site using ENS adds
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
`regent_mcp_events` from `elixir-utils/mcp_events`. This template has no MCP endpoint
and does not use it. The library is in elixir-utils commits `194896a` and `c1544e5`,
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

## Quickstart

Run these from `platform/`. You need
Erlang, Elixir, Node and PostgreSQL at the versions pinned in `.tool-versions`.

```sh
createdb ash_template_dev
cp .env.example .env
touch .env.local
printf '%s\n' 'source_env .env' 'source_env_if_exists .env.local' > .envrc
mix setup
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

The local server talks to one loopback PostgreSQL database, `ash_template_dev`,
on `127.0.0.1`. The only thing that leaves the machine is sign-in verification
with Privy.

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
| `ASH_TEMPLATE_SIWA_BROKER_URL` | No | The sign-in service that checks agents' signed requests, such as one running on this machine. Unset means `https://siwa.regents.sh` (`config/config.exs`, `config :regent_agents, siwa: [url: ..., audience: "ash-template"]`). |
| `PHX_HOST` | Yes in production | Public hostname the endpoint builds URLs from. |
| `SECRET_KEY_BASE` | Yes in production | Session signing secret; at least 64 bytes. |
| `PORT` | No | HTTP port. Defaults to `4000`. |
| `SENTRY_DSN`, `SENTRY_RELEASE`, `SENTRY_ENVIRONMENT` | No | Error reporting. Unset means no reporting. |
| `ASH_TEMPLATE_DEPLOYMENT_ROLE` | Yes in production | `production` or `staging`. There is no default; each role admits only its own database hosts. |
| `DATABASE_POOLED_URL` | Yes in production | Pooled PostgreSQL connection string for an approved host. |
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
  records, but cannot create, change or drop tables. It holds five connections,
  shows up as `ash-template-web` in `pg_stat_activity`, and gives up on a statement
  after 15 seconds, a lock wait after 5 seconds and an idle open transaction after
  15 seconds (`AshTemplate.DatabaseConfig`).
- **The release login** (`DATABASE_DIRECT_URL`) is a user with the `schema_admin`
  role, used only while a release goes out: the release command runs the
  migrations with it and then exits. The running site never reads it.

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
| `/app`, `/account` | GET | The signed-in shell. |

## Showcase

The showcase pages (`/showcase`, its catalog and preview, `/showcase/privy`, the
wallet page `/showcase/wallet`, the payment example `/showcase/payments`, the funds example `/showcase/funds`), the motion lab (`/animations`) and the build
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
| `sign_in` | `:browser`, `:showcase_browser` | The baseline plus Privy wallet sign-in: Privy's API and frame, Cloudflare Turnstile, WalletConnect's relay, verify frame, wallet list and logos, RPC and event reporting, Coinbase Wallet's relay, and inline style elements for Privy's window. |
| `showcase` | `:framed_preview` | `sign_in` that may frame its own preview page, for `/showcase` and `/showcase/preview`. |

A site that loads something else (an RPC, an image host, an embedded wallet)
adds each exact origin to the one directive in the one profile that needs it:
`@sign_in` for anything the wallet or sign-in pages use, `@baseline` only for
what every page loads. Never add `https:`, `*`, a whole-domain wildcard or
`'unsafe-eval'`. After a change, load each affected page and the sign-in window
and check the browser console for "Content Security Policy" errors.

Rate limits key on the client address from `AshTemplateWeb.ClientAddress`. In
production (`:behind_fly_proxy`, set in `config/prod.exs`) that is the one
`Fly-Client-IP` header Fly's proxy writes, replacing anything a client sent;
everywhere else it is the direct peer. `X-Forwarded-For` is never read. A site
that puts another proxy in front of Fly must change this first.

Prometheus metrics are served only by `AshTemplateWeb.Metrics` on port 9091
(`/metrics`), which `fly.toml` and `fly.staging.toml` declare under
`[metrics]`. Fly sends public traffic only to the `[http_service]` port, so the
metrics port is reachable from the app's private network, where Fly's scraper
reads it, and not from the internet. Locally it listens on loopback, on a port the
system picks (`config/config.exs`), so sites run side by side without sharing 9091.
`/healthz` stays public on the site's own port.

## Repository layout

```text
lib/ash_template/       Ash domains: accounts, sign-in, legal documents
lib/ash_template_web/   Endpoint, router, live pages, controllers, components
lib/mix/tasks/          Local setup, contract sync and route-handoff checks
test/                   The sign-in and Credits tests (see Checks)
contracts/              The OpenAPI contract
config/                 Compile-time and runtime configuration
assets/                 TypeScript and CSS, built with esbuild
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
npm run typecheck
```

`make check` also runs the required-fixes check (see
[Shared dependencies](#shared-dependencies)) and the command description check
(see [cli/README.md](../cli/README.md)).

`mix precommit` compiles with warnings as errors, checks unused dependency
locks, reports packages with security advisories, checks formatting, runs Credo in strict mode and Sobelow, holds the
compile-connected `xref` graph under its limit, and verifies the Ash codegen
and route handoff are current. `npm run typecheck` type-checks the TypeScript
assets. The template carries two automated tests (founder decisions, 2026-09-27 and
2026-10-08; the second assigned by the agent pairing thread on Sean's word, 2026-10-08).
`mix test` signs a person in and back in, because sign-in once failed for three
days unnoticed, and credits a Credits purchase through the site's `on_credited`
module, because a site without one never credits a purchase. It first brings the
local `ash_template_test` database up to date. Check every other change in a browser against the development server.

## Deployment

Deploying runs `/app/bin/migrate` as its release command, so a deploy writes
database migrations. Every deployment names its venue in
`ASH_TEMPLATE_DEPLOYMENT_ROLE`, and each role admits only its own database
hosts. Production boot also fails unless `ASH_TEMPLATE_APP_SURFACES`,
`ASH_TEMPLATE_SHOWCASE`, `PHX_HOST` and a 64-byte `SECRET_KEY_BASE` are set.
`/app/bin/pending-migrations` reports what a deployed database and the release
image disagree about, without applying anything.

The image is built from `Dockerfile` with the repository root as its context:
the app is in `platform/`, and the build skills it serves are read from
`skills/` when it compiles (`.dockerignore` at the root admits only those two
folders). The build fetches every dependency at the version the lockfiles pin.
The shared libraries' repositories are public, so the build takes no
credentials. The Fly configuration lives in `fly.toml` and `fly.staging.toml`;
`fly.toml` names no app, so every site deploys it under its own name.

Deploy from the repository root with the app's name, for the hosted demo:

```sh
scripts/deploy.sh template-regents-sh
```

It refuses a working tree with any change and a commit that is not on
`origin/main`, then runs `fly deploy . --config platform/fly.toml --app <app>
--ha=false --remote-only --image-label <short commit>`, so both folders reach
the build and the image names the commit it came from. Staging deploys with
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
the image from `git archive` of HEAD's `platform/` and `skills/` folders,
reusing no cached layers, so nothing uncommitted or outside the repository
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
