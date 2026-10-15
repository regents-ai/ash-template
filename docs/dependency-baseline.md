# Shared package versions

Ash-template owns the tested shared package baseline. Sites retain product-only
packages, but every package they share with the template must have the same
locked version and source. Update the template first, verify it, then adopt that
exact candidate in each site. A newer registry version alone is not proof that
an upgrade works.

Mix and npm resolve dependencies and write their lockfiles. Do not copy a whole
template lockfile over a site's product dependencies, force incompatible peers,
or silently relax a security hold to make resolution succeed.

Compare explicitly selected checkouts from the template root:

```sh
make check-dependency-parity SITES="../regents ../autolaunch ../patchbay ../keyfleet ../techtree"
```

The read-only check compares complete common Mix lock entries (including Git
source and commit), and common direct npm dependencies (exact declaration,
resolved version and integrity). It supports browser packages in either
`platform/` or `platform/assets/`. It fails on stale declarations, unreadable
locks or mismatches. It does not install, edit, fetch, push or deploy anything.
Supply the actual candidate checkouts, not stale primary checkouts. Nested Mix
projects used by a site still need their own compatible resolution and checks.
Site-only packages and the full transitive npm graph remain outside this
comparison; each site's compiler, typecheck, audit and product checks still apply.

`security/required-fixes.json` separately enforces security provenance and known
safe version requirements. Keep Bandit's fixed Git source until a proven fixed
release replaces it. Keep the AshPostgres 2.13.0 schema-prefix hold until a newer
version passes an isolated real upsert check using the Repo's default prefix.
An upgrade must never enable Points earning or change production data as a
side effect of package alignment.

The release prerequisite checks every carried Agents, Credits and Points
migration against its separate shared ledger. A site moving from an older
shared-library pin may need separately authorized migrations, including
`regent_agents` version `20261014150000` for agent pictures. The prerequisite
only reports/refuses missing migrations; it never applies them.

`ex_hash_ring` is held at 6.0.4: Cachex 4.1.1 in consuming sites requires 6.x,
while the template's Nebulex Distributed 3.0.0 accepts 6.x or 7.x. The explicit
constraint keeps the shared baseline compatible with both, without an override.
