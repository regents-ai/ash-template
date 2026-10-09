# Signed agent access release

The generic template uses exact-request SIWA proof and current owner pairing for
private reads and product writes. Browser cookies provide no agent authority.
World ID and ERC-8004 are optional; owner security, pairing controls and spending
grants remain owner-only. Native tools prepare manifest operations and forward
signed bytes without retries, redirects or cookies. No signer or proof-import
fixture is included.

## Release prerequisites

The shared source is pinned to elixir-utils commit
`3397d80c8d5eec7085d003cb7a0e4a0e8605706f`. It must be published before a remote build.
The production deployment also requires separately approved shared migrations:

- Agents `20261009200000`: archive current and future pairing episodes; preserve
  the active-only table and original DELETE behavior used by existing sites.
- Credits `20261009154205`: indexes for private ledger history.
- Credits `20261009201000`: bind grants and holds to episodes, disable existing
  enabled grants lacking provable episode binding, and revoke grants on unpairing.

Existing settings and historical charges remain. Owners must reapprove unbound
grants with compatible grant controls. The five product-site deployments are
outside this release. Their old pairing lookups and deletes remain compatible;
the global grant changes still affect their shared database.

The template's release command checks shared prerequisites before applying its
own note-attribution migrations. It never applies shared migrations automatically.
Apply only the approved Agents and Credits migrations, using the direct release
connection; do not run the Points migrator or activate earning rules for this task.
Points `starts_at` and `unified_activity_starts_at` remain nil.

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
