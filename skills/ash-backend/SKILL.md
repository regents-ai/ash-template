---
name: ash-backend
description: Ash resources, actions, changes, validations, calculations, relationships and domain code interfaces on Regent's sites - where a rule belongs, which built-in expresses it, and how jobs and outside calls attach to an action. Use when adding or changing a resource or action, choosing between a built-in, a custom change and a manual action, wiring an external effect, or removing wrapper code around Ash.
---

# Ash backend

Load `ash-stack` first; its shared rules apply.

- Business rules live in Ash actions and policies; plain computation stays ordinary
  Elixir.
- Prefer a built-in to a custom change, and a custom change to a manual action, when
  each expresses the requirement correctly.
- Named domain interfaces and action-bound forms are the application boundary. A
  one-line interface is not waste: remove a local wrapper only when it adds no
  behaviour, callback contract, actor propagation or error handling.
- Durable, retried or scheduled work is Oban ([elixir-stack](../elixir-stack/SKILL.md)).
  One resource reacting to another's action is an Ash signal
  ([ash-signals](../ash-signals/SKILL.md)).
- A bulk change a person makes with one press sends one notice: run the bulk update
  without `notify?: true` and have its caller publish one notice on that audience's
  topic once it succeeds (`AshTemplate.Activity.mark_all_read/1`). One notice per row
  made every open tab recount once per notification.
- Idempotency, outbox and locking patterns never apply to a person's wallet send: every
  press reaches the wallet. A wallet panel's signer is Privy's active wallet when the
  server finds it among the signed-in account's linked wallets, checked against the
  verified session; any other wallet is ignored (regent-workflow, "Wallets and
  transactions").

## References

- [Action and resource decisions](references/decision-guide.md): accepted inputs,
  relationships, derived values, choosing an implementation boundary.
- [Integrations](references/integrations.md): jobs, external effects, adapters.
