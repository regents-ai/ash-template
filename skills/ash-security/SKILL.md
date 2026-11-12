---
name: ash-security
description: Ash authorization on Regent's sites - policies, where the actor and tenant come from, field exposure, staff pages, release commands that change live data, and LiveComponent session checks. Use when adding or reviewing a policy, an action reachable by a new actor or entry point, a read that could reveal another account's data, an operator or staff action, or any code that passes actor, tenant, scope or authorize? options.
---

# Ash security

Load `ash-stack` first. Follow the operation's actor, tenant and accepted inputs from
its real entry point to the resource action.

- A supplied tenant id is not proof of membership, and browser state is not
  authorization. Reuse the site's trusted scope.
- **Explicit options replace scope-derived values**: `actor: nil` erases the scope's
  actor. Inspect wrapper defaults and keyword merges. In callbacks, pass on the
  supplied context through the installed API, never stale request state.
- **Reads may filter or answer not-found.** Test non-disclosure under the policy's
  actual contract; do not demand Forbidden everywhere.
- **For writes, prove the refused operation changed nothing.**

## References

- [Threat cases](references/threat-cases.md): cross-tenant references, privilege
  changes, nested data, field exposure, background execution.
- [Operator actions](references/operator-actions.md): who an operator is, staff pages,
  release commands that change live data, the record they leave, development tools.
- [Component session check](references/component-session-check.md): LiveComponents,
  whose events skip the page's session re-check.
- [Privy reconciliation](../ash-stack/references/privy-reconciliation.md): Privy
  bridge and session work.
