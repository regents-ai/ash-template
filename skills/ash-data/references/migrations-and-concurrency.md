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

### An index on a busy table

Every filter or sort that runs on a growing table has an index declared in
`custom_indexes`, including the filters of pruners, policies, budgets and listeners,
not only page reads. A library's table in the site's own schema that the site's pruner
filters (ErrorTracker's) gets its index in the site's own migration, and prunes use
`return_records?: false`.

A plain `CREATE INDEX` blocks every write to the table until it finishes. On the shared
database that stalls the site, and the serving login's 5-second lock limit then fails
its writes. Build the index concurrently:

1. **Measure first.** Run the read with `EXPLAIN (ANALYZE, BUFFERS)` against rows
   shaped like production's (`ANALYZE` runs the statement, so only ever a read) to
   choose the index's columns, and run it again afterwards to see the index used. Ash's
   keyset "older than" filter is an `OR` of the sort's columns, which no column order
   turns into a range: an index on the first sort column serves it by skipping the rows
   before the cursor, so a page costs what the reader has already scrolled past.
2. **Declare it on the resource** with `concurrently: true` (AshPostgres
   `custom_indexes`). The template's unread-notifications index
   (`AshTemplate.Activity.Notification`) is the example:

   ```elixir
   custom_indexes do
     index([:human_account_id],
       name: "notifications_unread_index",
       where: "read_at IS NULL",
       concurrently: true
     )
   end
   ```

3. **Keep the generated migration as it is.** `mix ash.codegen` puts a run's concurrent
   indexes in a migration of their own that starts with `@disable_ddl_transaction true` and
   `@disable_migration_lock true`: PostgreSQL refuses `CREATE INDEX CONCURRENTLY` inside
   a transaction, and Ecto's migration lock would hold one open. Add nothing else to
   that file. The template's is `20261019044403_unread_and_linked_account_indexes.exs`.
4. **If the build fails** (a unique index meeting a duplicate, a cancelled release) it
   leaves an invalid index that is kept up on every write but never read. Find it with
   `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid`, remove it with
   `DROP INDEX CONCURRENTLY`, fix the cause and release again.

A concurrent build lets reads and writes carry on, but reads the table twice and waits
for older transactions: first those open on the table, then every transaction anywhere
in the database with an older snapshot, whatever table it uses. On the shared database
that includes the other sites' transactions, so another site's long transaction holds
up this release command, and a large table makes it longer still.

Only the owner of a schema adds an index to it. A site's own schema (`ash_template_app`,
`regents_app`, `autolaunch_app`, ...) belongs to that site's migrations. The shared
schemas (`regent_identity`, `regent_agents`, `regent_points`, `regent_payments`) belong
to their library in elixir-utils: an index there is a library migration, built there
first and applied once for every site by `/app/bin/migrate-shared` after Sean's go
(`AshTemplate.Release.migrate_shared/0`). `regent_names.platform_human_users` belongs to
Regents. A site never indexes another site's schema or a shared table from its own
migrations.

Constraint validation has its own steps: `NOT VALID`, then `VALIDATE CONSTRAINT`
(above).

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
(`regents-platform-prod`, Fly Managed Postgres on the Starter plan) with 97 connections
for their logins. During a release a site's old and new machines are both connected, so
its connections briefly double. On 27 October 2026 four releases swapped at once and
every site lost the database for 20 seconds.

Serve through the database's pooler (`pgbouncer.dzx6qo6xqzvojpv5.flympg.net`) nowhere;
Proximal is the one site still on it, and moves to the direct address next.
It keeps at least 5 real connections open for each login on every one of its processes
that holds one of that login's clients (Min Pool Size, fixed in Fly's dashboard), so a
pooled site costs 5 for every pooler process its clients reach, not its pool size. The
template served through it until November 2026: 10 real connections for its 7 clients
on 30 October (two processes), then 15 on 11 November (three), where the same seven
clients on the direct address cost 7 (`control/rollouts/2026-10-29-db-pooler.md` in
the workspace). This holds until the founder changes the database plan.

- **Serving: the direct address.** The serving connection uses
  `direct.dzx6qo6xqzvojpv5.flympg.net` (from `DATABASE_POOLED_URL` in the template,
  Keyfleet, Patchbay, Regents and Techtree; Autolaunch reads `DATABASE_URL`; Proximal's
  `DATABASE_POOLED_URL` still names the pooler)
  with a pool of 5 (never leave `pool_size` unset: Ecto's default is 10), names itself
  with `application_name`, and sends the three limits that keep one site from stalling
  the others as startup settings: `statement_timeout` 15000, `lock_timeout` 5000 and
  `idle_in_transaction_session_timeout` 15000 (`AshTemplate.DatabaseConfig.serving/1`).
  It replaces each connection after nine to ten minutes
  (`max_lifetime: 540_000..600_000`): when Fly's proxy in front of the database
  restarts it closes any connection still open ten minutes later, and Fly's guide for
  Ecto recycles on this schedule to stay ahead of it
  (docs.fly.io/mpg/client-configuration); the range spreads the reconnects so they
  never land at once. Everything a site runs shares this one pool: pages, Oban, the
  health check (`AshTemplate.Health.database_ready?/0`) and the shared libraries,
  which take the site's repository from its configuration and start none of their
  own (the Claude connector's sign-in, `RegentOAuth`, since November 2026). Only
  `/healthz` runs the health query; a page takes whether the database answers from
  its own reads (ash-frontend, public figures, "Quiet pages"). The health query
  never waits for a connection (`queue: false`) and must not mark the machine down
  because the pool is busy: none free within 30 seconds of a query that succeeded
  is a busy, healthy site, and a machine marked down for that is restarted when it
  is serving most. The template holds six connections at rest: five serving and
  one listening.
- **Listening: one connection per machine.** The template opens one
  `Postgrex.Notifications` connection with the serving login, outside the pool
  (`AshTemplate.DatabaseConfig.notifications_config!/2`), and `RegentAgents.Listener`
  and any listener of its own share it under one `:rest_for_one` supervisor
  (`AshTemplate.SharedChanges`). Never open a second listening connection, and never
  listen through the repository.
- **Release commands: the release login.** Migrations run with the release login on
  `DATABASE_DIRECT_URL`, which has none of the serving limits, two connections for as
  long as the command runs (`Ecto.Migrator.with_repo/2`).
- Oban's notices go over Erlang (`Oban.Notifiers.PG`), so Oban needs no listening
  connection of its own.
- `keyfleet-code` runs the Twigpine git node (Rust, sqlx), not an Ash site. It holds at
  most 10 connections (since its v5, c9a59ea) on the direct address: it takes session
  advisory locks and keeps sqlx's named statement cache.
- A release's switch to its new image runs migrations on the release login and then a
  second machine with its own connections until the first stops, so at most two
  switches run at once across all sites (12 Nov). The image build takes no shared
  lock; the switch takes `/tmp/regent-shared-db-release.lock` if it is free, otherwise
  `/tmp/regent-shared-db-release-2.lock` (regent-workflow's release checklist, step 3).
  The places are files on the founder's Mac, so they do not hold back a deploy started
  anywhere else or a restart from a secret set without `--stage`: production releases
  start from that Mac, and secrets are staged.
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
