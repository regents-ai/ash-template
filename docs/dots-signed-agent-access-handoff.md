# Dots handoff: prove signed agent access

> **Superseded 11 October 2026; kept as history.** Its source versions,
> unreleased-CLI claims and dependency-override steps are obsolete. Do not rerun
> its setup. For the current agent steps, see the public guide `/agents.md`
> (`platform/priv/public/agents.md`). For what has and has not been accepted, see
> `docs/signed-agent-access-release.md`.

Date: 9 October 2026. From Sean's local Codex implementation.

## Your task and what done means

Use your existing SIWA agent signer and a real paired test account to exercise
the new ash-template reference through **native WebMCP and the existing Regents
CLI runner separately**. Complete one protected private read and one private,
nonfinancial write in each interface. Record the first failure, assistance and
limitations. A passing mocked broker test, JavaScript function call or discovered
tool list is not native WebMCP acceptance.

This is a local acceptance handoff, not a claim that the five products are done.
Sean chose Dots for the web-agent demonstration. Do not create replacement keys,
use the account owner's browser session as agent authority, publish a room post,
spend Credits, move wallet funds or enable Points earning for this test.

## Required Skills

Sean requires these eight Skills for this work. Read them before making changes,
then follow the references relevant to the assigned task:

- [ash-regents](/Users/sean/.claude/skills/ash-regents/SKILL.md)
- [ash-data](/Users/sean/Documents/regent/repos/ash-template/skills/ash-data/SKILL.md)
- [ash-stack](/Users/sean/Documents/regent/repos/ash-template/skills/ash-stack/SKILL.md)
- [ash-webmcp](/Users/sean/Documents/regent/repos/ash-template/skills/ash-webmcp/SKILL.md)
- [ash-backend](/Users/sean/Documents/regent/repos/ash-template/skills/ash-backend/SKILL.md)
- [ash-frontend](/Users/sean/Documents/regent/repos/ash-template/skills/ash-frontend/SKILL.md)
- [ash-security](/Users/sean/Documents/regent/repos/ash-template/skills/ash-security/SKILL.md)
- [ash-framework](/Users/sean/.agents/skills/ash-framework/SKILL.md)

Also load the workspace's [regent-workflow](/Users/sean/Documents/regent/repos/ash-template/skills/regent-workflow/SKILL.md)
and [elixir-stack](/Users/sean/Documents/regent/repos/ash-template/skills/elixir-stack/SKILL.md).
These are local paths; a cloud runtime needs the corresponding Skill files supplied
with the handoff. Keep shared changes in the shared libraries first, then the
working template, then product adoption. Use Ash domain interfaces and policies,
generated schema changes, PostgreSQL constraints and transactions, Oban for durable
work and Req for service calls. Dots findings guide fixes within Sean's approved
scope; they do not independently authorize deployment or expand that scope.

## Source you need

The implementation is **uncommitted local work**, not available by cloning main.
On Sean's machine use these existing checkouts and preserve their unrelated edits:

| Checkout | Base HEAD | Work relevant to you |
| --- | --- | --- |
| `/Users/sean/Documents/regent/repos/elixir-utils` | `e1b2463d2f6d` | Shared pairing, Credits, Points and signed transport changes |
| `/Users/sean/Documents/regent/repos/ash-template` | `1493cb79c65c` | Reference integration and the two scripts below |
| `/Users/sean/Documents/regent/repos/regents-cli` | `fa35985b561b` | Existing SIWA signer and command runner; source version 1.8.1 |
| `/Users/sean/Documents/regent/repos/siwa-server` | `343c0eedd015` | Existing verifier; no new signing protocol |

Do not copy only ash-template. The default shared dependency pins still point to
older published code. The local `REGENT_ELIXIR_UTILS_PATH` override is required
for this acceptance build and is deliberately refused in production builds.
No new client release or deployment was made. Released and deployed versions
remain unverified for the new contract.

If you run in another machine/cloud runtime, first obtain the reviewed local
source changes through Sean's normal source-transfer process. This file is not
a source bundle. Do not deploy this checkout with old pins or copy Sean's local
credentials. A cloud host needs the shared Privy application correctly configured for its
allowed origin, the SIWA audience, a trusted HTTPS origin and an isolated database. The provided signing
bridge is intentionally local-only. Resolve those prerequisites before treating
cloud hosting as an alternative; no production migration is part of this handoff.

## Prepare an isolated local reference

Follow `/Users/sean/Documents/regent/AGENTS.md` and the repository instructions.
No `.env`, `.envrc` or `.env.local` file reads, dumps or credential copying. Use
the site's existing settings loader, and never restart somebody else's server.

Use `http://localhost:4070` and `ASH_TEMPLATE_DEV_PARTITION=_dots_access`.
Port 4070 was free when this handoff was updated; check again before starting:
`lsof -nP -iTCP:4070 -sTCP:LISTEN`. Privy allows localhost ports 4000, 4010,
4020, 4030, 4050, 4060, 4061, 4070 and 4097. If 4070 is occupied, choose a
free port from that list and update `PORT`, the browser URL, signer origin and
CLI base URL consistently. Other localhost ports may serve pages but fail sign-in.
This selects the new local database `ash_template_dots_access_dev`; do not use
the ordinary shared development database or reset any database. The development
database must be local: do not inherit remote cluster targeting variables.

From the template's `platform` directory, the preparation commands are:

```sh
export REGENT_ELIXIR_UTILS_PATH=/Users/sean/Documents/regent/repos/elixir-utils
export ASH_TEMPLATE_DEV_PARTITION=_dots_access
export PORT=4070
unset ASH_TEMPLATE_DATABASE_CLUSTER_ID ASH_TEMPLATE_DATABASE_CLUSTER_NAME FLY_APP_NAME
mix deps.get
mix ecto.create
mix ash_template.setup_local_auth
mix assets.build
```

Load the site's own Privy settings before starting the server. On Sean's machine,
the canonical loader is `direnv exec /Users/sean/Documents/regent/repos/ash-template/platform`.
Unset `ASH_TEMPLATE_DATABASE_CLUSTER_ID`, `ASH_TEMPLATE_DATABASE_CLUSTER_NAME`
and `FLY_APP_NAME` after loading settings to select the isolated local database.
For this private-note fixture also unset `OPENROUTER_API_KEY` and
`ASH_TEMPLATE_NOTES_WEBHOOK_URL` so notes cause no paid label call or external webhook.
Retain the three nonsecret exports above. Start `mix phx.server` through that
loader with those overrides. Check that the rendered `privy-app-id` meta has
nonzero length; report only its length, never its value.

Open **http://localhost:4070/**, using `localhost` consistently. The trusted
origin comes from Phoenix's configured endpoint, not from agent input. If the
browser opens `127.0.0.1` instead, preparation will intentionally refuse it.

The verifier needs the `ash-template` audience configured. Follow the maintained
SIWA guide at https://siwa.regents.sh/skill.md for your existing signer and receipt.
Do not bypass an absent audience, expired receipt or unavailable signer. Record
that exact prerequisite as blocked. Sign in to the local site's normal Privy
flow, obtain a pairing code through the account-owner panel and pair your existing
agent to that local account. A pairing on another database does not establish a
pairing in this isolated fixture. Never fake the owner mapping in SQL.

## Native WebMCP exercise

1. Record runtime/browser name and version and whether native WebMCP is present.
   Discover `prepare_agent_request`, `notes_list`, `notes_get` and `notes_create`
   through the runtime's actual tool interface. Do not substitute DevTools calls
   or a polyfill and describe them as native support.
2. Call `prepare_agent_request` with
   `{"operation":"notes_list","input":{}}`. This must not read private data.
3. Sign the exact returned request with your existing SIWA signer. The local
   adapter below reuses Regents CLI's signer; it implements no new cryptography.
   Pass only `{ "input": {}, "request": <returned request> }` on stdin:

   ```sh
   cd /Users/sean/Documents/regent/repos/regents-cli
   uv run python /Users/sean/Documents/regent/repos/ash-template/scripts/agent-access-sign-prepared.py --origin http://localhost:4070
   ```

   The adapter permits only local `notes_list`, `notes_get` and `notes_create`.
   It checks the prepared bytes before signing and sends no product request.
   It uses `regents_cli.siwa.current` and `regents_cli.siwa.sign`; a missing signer
   or receipt stays an error. If Dots cannot invoke it or another existing SIWA
   signer from its runtime, record **signer unavailable**, without a cookie fallback.
4. Supply its `{input, request, proof}` result to native `notes_list`. Expect 200.
   Keep proof/receipt values private and out of the returned report.
5. Choose a fresh UUID. Prepare `notes_create` with a harmless title such as
   `Dots local access check` and that UUID as `operation_id`. Sign and invoke the
   named native tool. Expect 201, note ID equal to the UUID and non-null acting-agent
   attribution. Prepare/sign `notes_get` for that ID and expect 200.
6. A logical retry keeps that UUID but gets a fresh proof. Expect duplicate create
   refusal (422), with the original note still readable and only one stored note.
   Do not create another UUID to hide a failed retry.

The bridge only helps a runtime that can reach its existing signer. It does not
provide a signer to a browser-only agent by itself. Report any human copy/paste
between browser and signer as assistance, with the exact step and reason.

## CLI exercise, independently

The released CLI does not carry ash-template. This reference launcher feeds the
source command description into the existing CLI runner without changing the
released package or its registry:

```sh
cd /Users/sean/Documents/regent/repos/regents-cli
uv run python /Users/sean/Documents/regent/repos/ash-template/scripts/agent-access-reference-cli.py agents whoami --base-url http://localhost:4070 --json
uv run python /Users/sean/Documents/regent/repos/ash-template/scripts/agent-access-reference-cli.py notes list --base-url http://localhost:4070 --json
```

For `notes create`, pipe a JSON object with `title` and a **different fresh**
`operation_id` UUID into the same launcher, with `notes create --base-url
http://localhost:4070 --json`. Then use `notes get <uuid>` with the same base URL.
Do not advertise these as available in the released CLI. Record the runner source
revision, source manifest revision and actual server revision separately.

The local launcher exposes the source description; the authorized exercise is
limited to identity, private notes and account reads. Do not invoke room posting,
payment or wallet operations. The owner may delete the fixture notes afterward.

## Refusal and revocation evidence

Use only your test account and fixture notes:

- Cookie alone, no SIWA proof: private tool access must be refused.
- Change the prepared body/path/operation: the tool/bridge must refuse before
  sending. Change bytes after signing in a controlled HTTP test: SIWA must refuse.
- Reuse an already accepted proof unchanged: SIWA must refuse it. Do not spend
  the proof on a separate verification call before submitting its intended action.
- Wrong audience: refuse. Never change the server's expected audience to make a
  receipt pass.
- Owner unpairs the test agent: a fresh signed request must lose private access.
  Owner re-pairs through a new code: the episode ID changes and spending stays off.
- The agent must retain its own identity throughout, with the canonical user as
  beneficiary. Do not convert it into a human actor.

Queued-work, 100-agent concurrency, shared spending and Points caps already have
local regression evidence. Do not seed 100 real accounts, spend money or enable
earning programs to repeat those checks in a live runtime.

## Return this evidence

For each WebMCP and CLI attempt record UTC time, source/client/deployed versions,
runtime/browser, operation, sanitized request shape, status/error code, first
failure, retries, assistance and final result. Include proof **presence and
verification outcome**, never signatures, receipts, tokens, keys or private data.
Distinguish native discovery, native execution, local bridge and released CLI.

Update the compatibility matrix supplied with this handoff, leaving untouched
runtime/site combinations as not run. Do not mark all five sites supported because
ash-template passes. The five products still need adoption in the approved order:
Regents/Patchbay, Autolaunch, Techtree hosted operations, then Keyfleet's available
operations. Preserve Techtree proof ownership, Keyfleet rights and wallet approval.

Report back to Sean. Do not publish a Patchbay repair report as part of this
handoff; any later report must be authorized, sanitized and retested after release
before a failure is marked resolved.

## Known release blockers

- Real Dots/native and desktop signer demonstrations are outstanding.
- Product adoption, deployed `/agents.md` routes, cross-site account reconciliation
  and committed-outcome Points adapters remain outstanding.
- Shared reviewed commits/pins, coordinated CLI release and deployment are outstanding.
- Existing `rooms delete` uses 204 with no JSON body, while the existing CLI command
  checker demands JSON success. The same failure occurs on unchanged HEAD; reconcile
  that contract in the CLI release work, without changing it silently here.
- New rules are configured off. Pick and record a future UTC midnight only after
  compatible services are deployed; preserve old awards, grants evidence and bonuses.
