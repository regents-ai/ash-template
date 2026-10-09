# Signed agent access release

The generic template uses exact-request SIWA proof and current owner pairing for
private reads and product writes. Browser cookies provide no agent authority.
World ID and ERC-8004 are optional; owner security, pairing controls and spending
grants remain owner-only. Native tools prepare manifest operations and forward
signed bytes without retries, redirects or cookies. No signer or proof-import
fixture is included.

## Release prerequisites

The shared source is pinned to elixir-utils commit
`1564d79eb3b653f06ab11b6c422bd4d6283ea199` (published on main).
The production deployment also requires separately approved shared migrations:

- Agents `20261009200000`: archive current and future pairing episodes; preserve
  the active-only table and original DELETE behavior used by existing sites.
- Credits `20261009154205`: indexes for private ledger history.
- Credits `20261009201000`: bind grants and holds to episodes, disable existing
  enabled grants lacking provable episode binding, and revoke grants on unpairing.

Existing settings and historical charges remain. Owners must reapprove unbound
grants with compatible grant controls. Product-site deployment is coordinated separately against the same shared database.
Their old pairing lookups and deletes remain compatible, but older spending code
must not see newly enabled grants during the transition. Keep grant enablement
closed until every serving writer and worker has adopted the reviewed version.
The shared `AgentPermission.set` action refuses enabled grants by default.
`RegentCredits.agent_grants_enabled?/0` reads the explicit
`:regent_credits, :agent_grants_enabled` runtime setting; only `true` opens it.
Disabling grants and settling existing holds remain available. Set it only after
all grant writers and hold creators are verified compatible, including workers.

The template's release command calls the shared libraries' read-only prerequisite
checks before applying its own note-attribution migrations. Other sites reuse
`RegentAgents.Migrator.require_pairing_history!/1` and
`RegentCredits.Migrator.require_pairing_grants!/1` before their own migrations.
These checks never apply shared migrations automatically.
Apply only the approved Agents and Credits migrations, using the direct release
connection; do not run the Points migrator or activate earning rules for this task.
Points `starts_at` and `unified_activity_starts_at` remain nil.

The shared payment guard freezes the verified agent, beneficiary and original
pairing before a new payment. Recovery can finish only its already authorized
effect. The canonical [payment integration](../skills/payments/SKILL.md) documents
the typed actor, private metadata and narrow completion boundary. The template
keeps its existing illustrative showcase; it configures no payable offer. Sites
using `regent_payments` must adopt the required shared fix before release.

## Verification boundaries

Local evidence covers paired private reads/create/readback, single verification
of exact bytes, cookie-only refusal, duplicate logical create refusal, revocation,
old-site wallet lookups and deletes, episode-bound grant revocation, shared
reservation limits across agents/sites, and Points allowance and historical-rule
invariants. Delayed note attribution retains the creation episode after an owner
edit and revocation. Old notes without that evidence are not backfilled by guessing.

The native signed browser protected read/write has **not been verified**. Discovery,
preparation and mocked server verification do not establish native signed success.
The earlier real CLI acceptance is separate historical evidence and does not
establish acceptance of this exact deployment. Live wrong-audience and revoke/
re-pair acceptance remain outstanding. No five-site adoption is claimed.
