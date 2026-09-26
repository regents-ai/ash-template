---
name: ash-data
description: Change AshPostgres schemas or diagnose SQL and concurrency behavior.
---

# Ash Data

State the persistence invariant that the change must preserve. Use installed
AshPostgres generation and migration behavior; inspect generated changes rather than
replaying archived migration history or assuming code generation only writes files.

[Migrations and concurrency](references/migrations-and-concurrency.md) covers
schema snapshots, constraints, atomic actions, transaction boundaries and SQL evidence.

Preserve full source records during imports, including unmapped columns. Identical
reimports must be harmless; conflicting identities or values need reconciliation.
A historical row count cannot prove present-day completeness. Rehearse on disposable
data before the separately authorized production operation.

Do not disable atomic requirements reflexively. A race test needs independent
transactions, not two processes sharing one sandbox connection. Persistent retry or
locking guidance never authorizes admission state for user-signed Regent wallet sends.
