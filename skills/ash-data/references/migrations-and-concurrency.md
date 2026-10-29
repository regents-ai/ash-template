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
(`regents-platform-prod`, Fly Managed Postgres on the Starter plan) with 97 connections
for their logins. During a release a site's old and new machines are both connected, so
its connections briefly double. On 27 October 2026 four releases swapped at once and
every site lost the database for 20 seconds.

A site therefore serves through the database's pooler, as the template does, and keeps
only what needs a session on the direct address:

- **Serving: the pooler.** `DATABASE_POOLED_URL` names
  `pgbouncer.dzx6qo6xqzvojpv5.flympg.net`, the cluster's PgBouncer in transaction mode.
  The pooler's certificate comes from the cluster's own authority
  (`postgres-operator-ca`, valid to July 2036) and names the cluster's internal address,
  not the public one. Copy `platform/priv/certs/regents-platform-prod-pooler-ca.pem`
  and the pooler clause of `AshTemplate.DatabaseConfig.fly_mpg_options/1`: verify the
  peer against that one authority and accept only
  `pgdb-dzx6qo6xqzvojpv5-pgbouncer.pgdb-dzx6qo6xqzvojpv5.svc`. Never turn the check
  off. If Fly replaces the authority, pooler connections fail until the new certificate
  is copied in.
  The pooler has run in transaction mode since 29 October 2026 16:27Z. It opens at most
  45 real connections (plus a reserve of 10) for up to 200 client connections, so a
  release's second machine waits a moment for a connection instead of taking one from
  the database. It closes a client connection idle for 60 seconds and replaces its own
  database connections every 300 seconds; it has no other limit on how long a client
  connection lasts. It keeps at least 5 database connections open for each login it
  serves (Min Pool Size), apparently on each of two pooler processes (the template holds
  10 for 7 clients). Fly's dashboard lets the founder change only the pool mode; these
  limits are fixed.
  Copy `AshTemplate.DatabaseConfig.serving/1`:
  a pool of 5 (never leave `pool_size` unset: Ecto's default is 10),
  `prepare: :unnamed` (named prepared statements do not survive a transaction pooler),
  and `max_lifetime: 540_000..600_000`: when Fly's proxy in front of the database
  restarts it closes any connection still open ten minutes later, and Fly's guide for
  Ecto recycles every nine to ten minutes to stay ahead of it
  (docs.fly.io/mpg/client-configuration); the range spreads the reconnects so they
  never land at once. The pool's idle pings (every second) keep each connection well
  inside the pooler's 60-second idle limit. The health check reads through the same
  pool (`AshTemplate.Health.database_ready?/0`).
- **Limits live on the serving login.** The pooler closes any connection whose startup
  settings name more than `application_name` (template v115 failed on
  `statement_timeout`), so a site's connection sends only its name. The limits that
  keep one site from stalling the others are set once on the serving login itself, by
  that login on the direct address (an ordinary login may set its own defaults), and
  apply to every connection the pooler opens for it:
  `ALTER ROLE CURRENT_USER SET statement_timeout = '15s'`, then `lock_timeout = '5s'`
  and `idle_in_transaction_session_timeout = '15s'`. It is a production database
  change: it needs the founder's go naming it.
- **Listening: one direct connection per machine.** The pooler drops `LISTEN`, so the
  site opens one `Postgrex.Notifications` connection on `direct.<cluster>` with the
  serving login (`AshTemplate.DatabaseConfig.notifications_config!/2`), and
  `RegentCredits.Listener`, `RegentAgents.Listener` and any listener of the site's own
  share it under one `:rest_for_one` supervisor (`AshTemplate.SharedChanges`). Never
  open a second listening connection, and never listen through the repository.
- **Release commands: the direct address.** Migrations take session locks, so they run
  with the release login on `DATABASE_DIRECT_URL`, `direct.dzx6qo6xqzvojpv5.flympg.net`.
- **Everything else works through the pooler.** Oban's notices go over Erlang
  (`Oban.Notifiers.PG`); a lock held for one transaction
  (`pg_advisory_xact_lock`) is fine, and so is sending a notice through the repository
  (`pg_notify`, as `RegentCredits` and `RegentAgents` do): only listening needs the
  direct connection. A session lock (`pg_advisory_lock`), `SET` outside
  a transaction or a temporary table kept between transactions is not: use the
  transaction form.
- `keyfleet-code` runs the Twigpine git node (Rust, sqlx), not an Ash site. It holds at
  most 10 connections (since its v5, c9a59ea). Through the pooler, sqlx keeps no
  prepared statements between transactions: `statement_cache_capacity(0)`.
- Releases take turns until the last site is pooled. The pooler, not a release lock,
  keeps a release's second machine from taking the database's connections, but what
  stays direct still doubles in a release: each machine's listening connection, the
  release command's own connections, and `keyfleet-code` (up to 20). With every release
  at once that peak (55 pooled, about 13 listening, about 16 for release commands, 20,
  plus Sentinel and an admin login: about 114) passes the database's 97; one release at a
  time peaks at about 92. So a site keeps `lockf -k /tmp/regent-shared-db-release.lock`
  in its deploy when it moves to the pooler. The lock is one file on the founder's Mac
  that every site's deploy script takes, so releases started there take turns across
  sites; the template's `scripts/deploy.sh` takes it too. It does not hold back a deploy
  started anywhere else or a restart from a secret set without `--stage`, so nobody
  deploys from another machine while the sites move. The lock goes from every site
  together once the count after the last move, and the founder's pooler limits, leave
  room for the peak (`control/rollouts/2026-10-29-db-pooler.md` in the workspace).
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
