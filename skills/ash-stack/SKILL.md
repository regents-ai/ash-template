---
name: ash-stack
description: Choose an Ash workflow for cross-layer features or refactors.
---

# Ash Stack

Use the smallest relevant specialist. Product intent and repository authority come
from the current task; this pack supplies Ash-specific judgment, not a delivery ritual.

| Work | Reference |
| --- | --- |
| Resources, actions and domain interfaces | [ash-backend](../ash-backend/SKILL.md) |
| Forms, LiveView and presentation | [ash-frontend](../ash-frontend/SKILL.md) |
| Schema changes, SQL and concurrency | [ash-data](../ash-data/SKILL.md) |
| Policies, actors and data exposure | [ash-security](../ash-security/SKILL.md) |
| Regression design or test cleanup | [ash-testing](../ash-testing/SKILL.md) |
| Agent readiness, shared discovery metadata, and building or adopting WebMCP tools | [ash-webmcp](../ash-webmcp/SKILL.md) |

For uncertain APIs, use the app's actual Mix root, lockfile and installed dependency
usage rules. [Documentation lookup](references/docs-workflow.md) covers version
mismatches; the [inventory helper](scripts/inventory.py) optionally locates projects
without executing them. Do not turn this into a whole-repository scan before an edit.

In Regent, [integration guidance](references/regent-integration.md) resolves shared
libraries, claims and wallet rules. For Privy bridge/session changes, use
[Privy reconciliation](references/privy-reconciliation.md). Consult the
[shared contract](references/shared-contract.md) only when a boundary is unclear.
