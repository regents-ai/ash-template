---
name: ash-data
description: AshPostgres persistence on Regent's shared production database - migrations and generated snapshots, constraints and identities, atomic updates, transactions, locks, races, imports and SQL diagnosis. Use when changing a schema or migration, enforcing a limit or once-only rule, diagnosing a constraint error, deadlock or slow query, importing or backfilling rows, or touching a site's database connections.
---

# Ash data

Load `ash-stack` first. State the persistence invariant the change must keep, then:

- **Generate, then inspect.** Use the installed AshPostgres generator and read what it
  wrote; never replay archived migration history, and never assume code generation
  only writes files.
- **A limit or once-only rule on an update is an atomic validation**, never
  `change filter(expr(...))`: Ash 3.33.11 drops that filter from single-record atomic
  updates ([details](references/migrations-and-concurrency.md#four-distinct-concurrency-questions)).
  Do not switch off atomic requirements to get past an error.
- **A race test needs independent transactions**, not two processes sharing one
  sandbox connection.
- **One production database for every site.** Every site and the template serve on
  the direct address with a pool of 5, never through the pooler, and releases take
  turns
  ([connections](references/migrations-and-concurrency.md#connections-to-the-shared-production-database)).
  The template's `template-runtime` login still stores the 15 s, 5 s and 15 s limits
  set on it on 27 October 2026, the same values its startup settings send; leave
  them, since resetting them is a production database change.
- **Imports keep the whole source record**, unmapped columns included. An identical
  reimport is harmless; a conflicting identity or value needs
  reconciliation. A historical row count does not prove completeness. Rehearse on
  disposable data; the production run is a protected action (regent-workflow).
- Retry and locking patterns never apply to a person's wallet send.

[Migrations and concurrency](references/migrations-and-concurrency.md) covers schema
snapshots, constraints, atomic actions, transaction boundaries and SQL evidence.
