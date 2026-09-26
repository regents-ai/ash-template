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

Concurrent index creation and constraint validation have PostgreSQL/Ecto-specific
transaction and locking requirements. Inspect the installed migration APIs and DB
version before choosing them. Do not paste a raw SQL pattern from another version
without checking its safety and Ash's representation of the intended index.

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
