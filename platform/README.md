# Ash Template platform

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](../LICENSE)
[![Elixir 1.19](https://img.shields.io/badge/elixir-1.19-lightgrey)](https://elixir-lang.org)
[![Phoenix 1.8](https://img.shields.io/badge/phoenix-1.8-lightgrey)](https://www.phoenixframework.org)
[![Ash 3.33](https://img.shields.io/badge/ash-3.33-lightgrey)](https://ash-hq.org)

The Phoenix/Ash web application of Ash Template. It serves the public home
page, Privy wallet sign-in, the signed-in Overview (`/app`) and Account
(`/account`) pages, the public pages, health and metrics, and the public HTTP
API.

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
no fetched history, or lacks a listed fix, and when a Hex package is older than a
listed fix. Library pins never change by themselves; only the list does.
Retired Hex packages are checked by `mix hex.audit` in `mix precommit`.

## Quickstart

Run these from `platform/`. You need
Erlang, Elixir, Node and PostgreSQL at the versions pinned in `.tool-versions`.

```sh
createdb ash_template_dev
cp .env.example .env
touch .env.local
printf '%s\n' 'source_env .env' 'source_env_if_exists .env.local' > .envrc
mix setup
mix ash_template.setup_local_auth
mix phx.server
```

The site is then at `http://localhost:4000`. Sign-in needs real Privy
credentials; [docs/local-privy-auth.md](docs/local-privy-auth.md) says where
they come from. Put real values only in the ignored `.env.local`, never in
`.env.example`, and commit none of the three.

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
| `ASH_TEMPLATE_APP_SURFACES` | Yes in production | `on` opens the signed-in pages. Anything else keeps them closed, so a typo closes rather than opens. Boot fails in production if unset. |
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

## Public HTTP surface

`contracts/api-contract.openapiv3.yaml` is the source of truth for the API and
is served at `/api-contract.openapiv3.yaml` with `x-regents-contract-major` and
`x-regents-contract-digest` headers. The table is a map, not the contract.

| Route | Method | Purpose |
| --- | --- | --- |
| `/healthz` | GET | Liveness check; plain text `ok`. |
| `/metrics` | GET | Prometheus metrics. |
| `/api/v1/profile`, `/api/v1/profile/sync` | GET, PATCH, POST | The signed-in person's shared profile, served by the `regent_identity` package with paired Privy proofs. |
| `/auth/csrf`, `/auth/session`, `/auth/privy/session`, `/auth/privy/failure` | GET, POST, DELETE | Browser session start, read and end. |
| `/openapi.json`, `/llms.txt`, `/sitemap.xml`, `/robots.txt` | GET | Discovery documents. |
| `/`, `/docs`, `/about`, `/contact`, `/privacy`, `/terms` | GET | Public pages; `Accept: text/markdown` returns Markdown. |
| `/app`, `/account` | GET | The signed-in shell. |

## Repository layout

```text
lib/ash_template/       Ash domains: accounts, sign-in, legal documents
lib/ash_template_web/   Endpoint, router, live pages, controllers, components
lib/mix/tasks/          Local setup, contract sync and route-handoff checks
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
assets. The template carries no automated tests (founder decision,
2026-09-27); check changes in a browser against the development server.

## Deployment

Deploying runs `/app/bin/migrate` as its release command, so a deploy writes
database migrations. Every deployment names its venue in
`ASH_TEMPLATE_DEPLOYMENT_ROLE`, and each role admits only its own database
hosts. Production boot also fails unless `ASH_TEMPLATE_APP_SURFACES`,
`PHX_HOST` and a 64-byte `SECRET_KEY_BASE` are set.
`/app/bin/pending-migrations` reports what a deployed database and the release
image disagree about, without applying anything.

The image is built from `Dockerfile` with this folder as its context; the build
fetches every dependency at the version the lockfiles pin. The shared
libraries' repositories are public, so the build takes no credentials. The Fly
configuration lives in `fly.toml` and `fly.staging.toml`.

## Release

From the monorepo root, with Docker running:

```sh
make release
```

It stops unless every change is committed, then runs `make check`; a failing
gate stops it before anything is built. `../scripts/release.sh` then builds
the image from `git archive` of HEAD's `platform/` folder, reusing no cached
layers, so nothing uncommitted or outside the repository enters it, and tags it
`ash-template:<commit>`. The smoke check starts a throwaway PostgreSQL 17 on
its own Docker network, answering to the staging database hostname, and runs
the image as staging against it: `bin/bootstrap-staging`, `bin/migrate` and
`bin/pending-migrations` (which must print `none`), then the server, whose
`/healthz`, home page, fingerprinted stylesheet and own database connection it
checks. It removes the database and the network afterwards, keeps the image,
and prints the app commit, the shared-library commits from `mix.lock` and the
image digest. It never deploys.

## License

MIT, see [LICENSE](../LICENSE).
