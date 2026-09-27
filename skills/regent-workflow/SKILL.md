---
name: regent-workflow
description: Complete Regent feature work directly, in Hermes/Astra + Claude pairing or Claude-only mode, with relevant specialist skills.
---

# Regent workflow

There are two development modes; the founder's request says which one applies.

- **Pairing:** Astra in the Hermes desktop app and a Claude thread work one lane
  together, following `docs/agent-pairing-template.md` in the workspace root.
- **Claude only:** a single Claude thread is the sole engineering agent for its lane.
  It reviews its own work and the founder reviews the product. It does not wait for
  a peer, votes, locks or channels.

In both modes the implementing agent owns the requested working result and implements,
reviews and verifies it directly, using ash-stack and the relevant specialist skills.
Delegation is optional, not a prerequisite; an unavailable peer or external coding
agent must not block direct implementation. This skill is workflow guidance, not a launcher.

## Product terminology

Agent token launches with revenue splitting for token stakers are **Revstake tokens**,
both internally and externally. Use Revstake in new plans, documentation and product
copy. Historical code identifiers may still say revshare, revenue-share or SUBJECT;
preserve their literal spelling when referencing source. This naming convention does
not by itself authorize a broad source rename or a change to contract economics.

Revstake token creation is **Base-only**. Robinhood permits **memestock auction
creation only**. This creation policy does not authorize deleting existing auctions
or disabling their withdrawals and claims. For Base Revstake, the approved LP locker
permanently locks the launch-owned position but lets anyone collect its TOKEN and
REGENT fees and deposit both in kind into the launch's fixed splitter. Keep the
existing swap hook and all splitter lanes, including the 2% skim on all three
recognized assets; no fee conversion or denomination redesign is wanted.

## Wallet identity and transaction state — all four products

Apply the same rule in Regents, Autolaunch, Techtree and Patchbay:

- Bind wallet-specific reads, displayed database data and signing authority to the
  Privy-authenticated wallet verified by the server session. A browser extension's
  account change must not select a new product identity or show that wallet's data.
  On-chain buttons are never gated by this: every press reaches the connected
  wallet. On mismatch, show a note beside the button naming both wallets (for
  example "You're signed in as 0x1234..abcd but your wallet is on 0x9a8b..c1d2"; a short
  address is always `0x`, the first four and the last four characters, joined by `..`).
- A signed-in customer never sees a wallet panel ask them to connect, choose or
  sign in again. Each panel reads the signed-in wallet from the server session when
  it mounts (balance, positions, form) and shows it straight away, after page jumps
  and reloads. Privy's browser selection is often empty after navigation, so never
  wait on it: the browser wallet matters only at the press. A press sends from the
  signed-in wallet as the tab has it connected; when it is not connected there, the
  press opens Privy's connect step and the customer presses again. Autolaunch's
  `AutolaunchWeb.SignedInWallet` is the reference.
- Never preserve pending transactions. Do not add browser-storage transaction
  queues, database pending-operation recovery, reload restoration, replay reports,
  recovery inboxes or resend orchestration. The wallet/blockchain owns transaction
  submission and pending state. This supersedes older preservation/recovery advice.
- Show transient feedback for the current interaction and refresh website state
  from verified receipts, canonical events and chain reads where available. Reload
  reads current state; it does not restore pending transactions or resend them.
  Confirmed chain-event indexing and ordinary saved creator drafts are separate
  from pending-transaction persistence and remain legitimate product data.
- Bind each action to the displayed record, chain and authenticated signer. Explain
  known failure conditions and disable the action until they change. A pending
  transaction alone must not serialize or suppress another otherwise valid press.
- Remove existing pending-preservation machinery through scoped product changes;
  do not delete historical database records or change other deployments implicitly.

## Product acceptance before test maintenance

Do not spend substantial time maintaining implementation-level tests before
establishing that the website works the way the founder wants. A large passing
suite is not evidence of an accepted product or working user journeys.

- Prioritize a usable website and the founder's manual functional review. Do not
  make rebuilding, expanding or repairing the broad test suite a prerequisite to
  that review. Report actual behavior and gaps, not test counts as a readiness claim.
- Do not add tests that mirror product-level functionality, smoke tests, or tests
  that merely preserve internal callbacks, mock choreography or component structure.
  Do not invent an automation backlog during implementation or review.
- Keep automated coverage deliberately small and justified by specific costly
  failures that manual review is unlikely to catch. Each retained test must name
  the invariant it protects; an auth/wallet/security filename is not justification
  for retaining a whole file or suite. Keep compilation and typechecking separate
  from the behavioral-test budget.
- When reducing a suite, use an explicit named allowlist and the founder's agreed
  budget. Preserve an archive of dirty/untracked tests before removing them from
  normal discovery. Do not hide the old suite behind default hooks or replace it
  with equally large generated or parameterized coverage.
- Add new automated behavioral coverage only when agreed with the founder for a
  specific accepted requirement or concrete regression. Technical testing recipes
  in task skills apply within that scope; they do not authorize expanding it.

## Shared design-system and showcase work

Before changing a product UI, read [the shared design and showcase contract](references/design-system.md)
and the current working `repos/design-system/STYLE.md`. The reference records source
ownership, Pixel/Sans typography, shared button/card behavior, the distinct homepage
contracts, and the actual-component showcase/build workflow.

Change common primitives in design-system, not in four conflicting app overrides.
Keep page composition and business behavior in the owning monorepo. Coordinate
overlapping writers, preserve uncommitted refinements, and distinguish a local
fixture preview from a real configured product. New founder corrections override
historical rollout reports; delayed agent notifications do not reopen completed or
cancelled work.

## Execute

1. Inspect the assigned repository's instructions, working changes and relevant code.
   State the observable result and relevant checks that define done. Infer reasonable
   criteria from the founder's request. A short task does not need a separate plan.
2. Implement the bounded change directly. If delegating an independent subtask, give
   it the objective, absolute repository/worktree path, owned files or component,
   acceptance checks, relevant context and authority limits. Tell writers they share a workspace and must
   preserve others' edits. Parallel writers use separate Git worktrees and branches;
   serialize work that touches the same surface. Use ordinary Git for branches and integration.
3. Record the changed files, checks actually run, failures and remaining work.
   For delegated work, retain the session/worktree reference and verify the returned
   results before integration.
4. The implementing agent reviews the change against acceptance, resolves integration
   issues, and runs scoped checks on the integrated result within the testing policy above.
   Exercise real or representative user flows; compilation alone does not prove an
   interaction. Fix product failures without expanding into broad test maintenance.
   Use independent security review when protected behavior needs it.
5. Return when the requested feature works, a named missing input blocks correctness,
   or the next consequential action needs authority. Explain what changed, what was
   verified and what remains. Do not call a dispatch or an untested patch completion.

## Project pages in Notion

Regent builds in public in Notion. Before adding plans, open decisions, done-criteria
or proof of finished work there, follow [regent-notion](../regent-notion/SKILL.md).

## Keep coordination light

The founder request and the working conversation are the work record. For a long task,
write a concise handoff in the owning repository with objective, current branch and
worktree, completed work, checks, remaining steps and actual blockers. No mandatory
status files for small edits. Product contracts and meaningful engineering checks
remain binding. Keep coordination in the current assignment and selected sessions.

A single writer may work directly in the assigned checkout after checking its state.
For concurrent writers, use `git worktree add` with a unique branch/path and an
explicit known base. One coordinator integrates per repository. Preserve unrelated
changes and avoid resetting or cleaning existing worktrees. Use isolated test databases
and ports. Follow each component's dependency setup; never clear a shared database.

## Protected work

Investigate and prepare billing, authentication, contracts, wallets and production
changes within scope. Record the relevant invariants and verification for risky work.
External writes, pushes, releases, deployments, destructive operations, production
data changes, signing and value movement need explicit applicable founder authority.
Authority belongs to the explicitly authorized action and actor. Do not repeat
permission questions when the current session already authorizes the exact action.

Never read `.env`, `.env.local` or `.envrc`; `.env.example` is allowed. Never expose
secrets. Only Sean may approve rotation after disclosure. Value transfer remains
user-signed, operator-signed or contract-defined. Every distinct wallet-button press
reaches the wallet, including repeat presses while a transaction is pending.
Preserve historical claims and source evidence before retiring their sole source.
