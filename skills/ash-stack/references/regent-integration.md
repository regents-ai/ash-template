# Regent integration

`regent-workflow` sets scope, authority and acceptance. This file adds only what the
Ash skills need to know about Regent's shape.

## Product boundaries

Regents, Techtree, Patchbay, Autolaunch and Keyfleet are separate Phoenix/Ash apps with
separate deployments on **one physical PostgreSQL database**. Each product owns its
schema and migration ledger through its own Repo; the Regents-owned `identity/` package
owns the shared identity schema (`agent-docs/product-boundaries.md` in the workspace).

- Presentation primitives come from `design-system/regent_ui`; shared infrastructure
  from `elixir-utils`. Extract only code with real, equivalent consumers.
- Components own no product workflow, authorization, wallet state or database access.
  Named actions and persistence stay in each product.

## Wallet actions

The rules are regent-workflow's "Wallets and transactions"; the button pattern is
`onchain-buttons`. What they mean for engineering patterns:

- Generic outbox, idempotency, locking, retry and duplicate-operation guidance never
  authorises admission state for a user-signed transaction. Nothing blocks, defers,
  queues, serialises or deduplicates a second press. A literal double-fire of one
  browser click is not a second press.
- No recovery inbox, no restore or replay of pending transactions. State refreshes
  from verified receipts, canonical events and chain reads.
- Match the record and the chain as well as the signer.
- Privy login and logout coordination ([Privy reconciliation](privy-reconciliation.md))
  must never become wallet-transaction serialisation.

## Claims and retirement

Historical regent.eth claims must survive in Fly Postgres through Ash before their sole
source or its dependencies retire. Preserve every source column, including fields an
old resource never mapped; compare actual row identities and values, never an old
approximate count. Keep related credit and allowance evidence until it is accounted
for. Accounts and Formation may retire once the retained features are decoupled. This is
preservation and display of existing claims, not authority for new claims or payments.
Keep raw user data out of reports and evaluation fixtures.

## Verification

- Use the checkout's own database, port and pinned dependencies. Never share
  destructive fixtures with another checkout. A verification command must not format
  files or change a lockfile.
- A domain code interface is not wrapper waste. Remove a wrapper only after checking
  its callbacks, external callers, error semantics, actor propagation and any
  computation it does.
- Before removing a test, name the behaviour it protects and whether another test sees
  the same failure. Replace source-text and copy locks; keep ABI, policy,
  data-integrity and user-visible contract checks.
- Reproduce relationship problems on real SQL (ETS hides SQL behaviour), as a minimal
  failing and passing pair before adding forms or other relationships.
- Only one action per type is primary. For many-to-many changes, confirm the locked
  version's `manage_relationship` input shape and join attributes; never copy an old
  example's field names.
