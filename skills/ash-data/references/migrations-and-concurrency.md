# Migration and concurrency decisions

## Expand, backfill, contract when compatibility matters

For a populated table or rolling deployment, separate introducing a compatible field,
backfilling existing data in bounded resumable batches, switching readers/writers, and
removing the old representation. A small local-only project may need a simpler change;
choose based on real deployment constraints. Do not manufacture a multi-release
migration for an unused table, or assume production tables are empty.

For a new required/unique value, inspect existing nulls/duplicates before adding the
constraint. Define normalization and null semantics. For a rename, preserve data and
references instead of accepting a generated destructive replacement. For a removed
resource, verify code generation does not accidentally drop a table still in use.

### A new required value on a large table

One migration that adds a column, fills it and checks it holds an `ACCESS EXCLUSIVE`
lock on the table for the whole fill. On a bluegreen release the old machine keeps
writing rows without the new value, so a check added in the same release turns its
writes into errors. On a large table that is not pruned (sessions, events, ledgers):

1. Release 1: add the column with no check, and make every write set it.
2. Fill existing rows in bounded batches outside the DDL transaction
   (`@disable_ddl_transaction true`, or a release task), each batch its own commit.
3. Add the check as `NOT VALID`: new and updated rows must pass, existing rows are not
   scanned, and the lock is brief.
4. Release 2: `VALIDATE CONSTRAINT`, which scans under a lock that lets reads and writes
   carry on.

The template's 30-day sign-in change (935fc63) did all of this in one migration because
its sign-in table is small and pruned; a site copying it onto a large table splits it.

### Dropping a column

On a bluegreen release the outgoing machines keep running the old code until the new
ones are healthy, and Ash selects every attribute a resource declares. A migration that
drops a column the old code still declares makes every read on the old machines fail.

1. Release 1: remove the attribute from the resource and every use of it. No migration.
2. Release 2, once release 1 is the only code running: the migration that drops the
   column.

Autolaunch's move from its own runner to Oban (da6cbf58, then d5e7a4c5) did it this way.

Concurrent index creation and constraint validation have PostgreSQL/Ecto-specific
transaction and locking requirements. Inspect the installed migration APIs and DB
version before choosing them. Do not paste a raw SQL pattern from another version
without checking its safety and Ash's representation of the intended index.

## Raw SQL names its schema

Each site keeps its tables in its own schema (the template's is `ash_template_app`,
`Repo.default_prefix/0`), and the release runs migrations with that prefix. `table/2`
and `index/2` pick it up; raw SQL in `execute/1` does not, so a bare `UPDATE assist_runs`
fails in the release command (Patchbay, 2026-09-28) even when it worked locally. Qualify
every table in raw SQL with the repo's schema:
`execute("UPDATE \"#{MyApp.Repo.default_prefix()}\".assist_runs SET ...")`. `prefix()`
inside a migration is `nil` under a plain `mix ecto.migrate`, so it is not a substitute.

`mix ash.codegen` can write `prefix: "public"` into a new table's `references(...)`. That
points the foreign key at the public schema, where the site's tables are not, so the
release migration fails (Patchbay, 2026-09-30). Delete those `prefix:` options from every
generated migration before committing; references then follow the schema the release
migrates into.

## Protected production tables

Since 28 September 2026 the shared production database keeps a founder list of
protected tables: accounts and identity, money, what people wrote or uploaded, and
records that stop a bot sending twice. The list includes the shared
`regent_identity.profiles` and `regent_names.platform_human_users`, which the template
and the sites read. The list lives in the database as `regent_guard.protected_tables`.
On a listed table:

- `TRUNCATE` is refused;
- `DELETE` is refused, except on the few tables where a person removing their own row
  is a site feature (`rows_deletable`);
- a plain `DROP TABLE` fails, because a guard view depends on the table.

Adding or dropping columns still works. A migration or release step that empties,
deletes from or drops a listed table fails in production even when it ran locally.
Plan it as a new table or column, not a rewrite through a delete, and ask the founder
first. Only Sean can lift the lock.

The command guard on the founder's machines refuses the same thing before it reaches any
database. A command that names `DELETE FROM`, `TRUNCATE` or `DROP TABLE` with a listed
table is refused even against a local test database. Reset test data with the Ecto
sandbox or a fresh database, never by emptying a listed table. Agents do not edit the
guard's settings or ask it to allow a command.

## Connections to the shared production database

The template, the five sites, `keyfleet-code` and Sentinel share one production database
(`regents-platform-prod`) with 97 connections for their logins. During a release a site's
old and new machines are both connected, so its connections briefly double. On 27 October
2026 four releases swapped at once and every site lost the database for 20 seconds.

- A site's serving connection holds 5, set in its own database config as
  `AshTemplate.DatabaseConfig.serving/1` does. Never leave `pool_size` unset: Ecto's
  default is 10. The health check reads through that same pool
  (`AshTemplate.Health.database_ready?/0`); a site keeps no second pool for it.
- `keyfleet-code` runs the Twigpine git node, not an Ash site. Its ceiling is 20: 10 in
  its main pool and 10 for push locks (`GITLAWB_DB_MAX_CONNECTIONS=10`,
  `GITLAWB_MAX_CONCURRENT_GIT_PUSHES=2`), the lowest the node starts with.
- One release on the shared database at a time. On the founder's Mac, everything that
  builds, releases or restarts a production app on the shared database runs under one
  lock, which waits its turn: `lockf -k /tmp/regent-shared-db-release.lock <command>`.
  The template's `scripts/deploy.sh` does this, and so does every site's copy; a
  `fly deploy --image`, `fly secrets set` or `fly secrets import` run by hand takes the
  same lock. The lock sees a release that is still building, which Fly's release list
  does not: Fly writes the release only once the build is done.
- A release started anywhere else also reads the newest release of each of the others
  first (`fly releases --app <app> --json`, one call per app: `autolaunch-sh`,
  `keyfleet`, `keyfleet-code`, `patchbay-regents`, `regents-sh-web`, `techtree-sh`,
  `template-regents-sh`, `sentinel-regent`). If any shows `"InProgress": true`, start
  yours after it finishes.
- More connections for one site, or a larger database plan, is the founder's decision.

## Snapshots are generator state

Commit snapshots with their migrations where the project does so.
Let the generator update them. Resolve parallel-branch conflicts by reconciling the
resource model and the real migration history, then regenerating intentionally.
Do not delete snapshots or run snapshots-only generation merely to obtain a green
check. An intentional baseline for an existing schema is a separate reviewed task.

## Four distinct concurrency questions

**Lost update:** two callers read a counter and write the same incremented value.
Use an atomic database expression or an appropriate explicit conflict strategy.

**Duplicate create:** two callers pass a pre-check then both insert. Enforce the
intended identity in the database; return or reconcile the conflicting result.

**Stale transition:** an action uses a status observed before another actor changed
it. Check the relevant current state in the operation itself, using the documented
atomic/filter/locking mechanism appropriate to the invariant.

**Cross-row limit:** individually valid writes exceed a shared capacity or aggregate
constraint. Decide on serialization/locking/constraint design. A per-row atomic
update or ordinary transaction is not by itself proof of this invariant.

**A limit or once-only rule on an update goes in the SQL as an atomic validation**,
never as `change filter(expr(...))`. Ash 3.33.11 drops that filter when a single
record's update runs atomically (`UPDATE ... WHERE id = $1`, reproduced 2026-09-27;
fixed on Ash main, not yet released), so a stale second call still writes. Write a
validation whose `atomic/3` returns the failing condition and its error:

```elixir
@impl true
def atomic(_changeset, _opts, _context) do
  {:atomic, [:free_mints_used, :snapshot_total], expr(free_mints_used >= snapshot_total),
   expr(error(Ash.Error.Changes.InvalidAttribute,
     %{field: :free_mints_used, value: free_mints_used, message: "no free claims are left"}))}
end
```

It runs inside the `UPDATE`, so the second of two racing calls gets the error and
nothing is written. `validate compare(...)` is not a substitute: it checks the record
as it was read. A once-only transition can also rest on a unique index. Prove it by
updating the same stale record twice: the first succeeds, the second errors, and the
row changes once.

Do not disable atomicity globally. A targeted non-atomic action needs a specific
reason; some relationship workflows require one, while row-local arithmetic usually
does not. Test the actual accepted outcome, not simply that no exception occurred.

## External side effects

The database and an HTTP service do not share a transaction. Define the crash windows:
before enqueue, after commit, after remote success but before acknowledgement, and
before persisting completion. Existing transactional job/outbox infrastructure plus
idempotency can address these windows. Do not promise exactly-once delivery from a
retry loop; design for duplicate/unknown outcomes and reconciliation.

## Test database discipline

Resolve test DB configuration without printing secrets. Never derive permission to
reset from a database name alone. Migrate a disposable DB explicitly. Real concurrency
may require independent connections/transactions and careful cleanup outside ordinary
shared sandbox ownership; use the project's established race-test arrangement.

Sources: [index](../../ash-stack/references/source-index.md), S13, S15, S30-S32,
S43, S46-S48. Deployment sequencing and idempotency requirements are pack design
recommendations rather than automatic framework guarantees.
