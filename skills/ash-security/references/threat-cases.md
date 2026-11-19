# Threat cases

Select cases relevant to the actual feature and check each against the real actions,
policies and error contracts of the target project.

| Attempt | Must hold |
| --- | --- |
| Anonymous caller invokes protected action directly | No unauthorized read/write, safe documented result |
| User edits another user's record | Real action denies; persisted state unchanged |
| Member of tenant A supplies tenant B's ID | Tenant membership checked, not just a query filter |
| Valid parent references a child from another tenant | Nested relationship operation cannot link or reveal the child |
| Allowed UI button is followed by membership revocation | Action reevaluates intended current permission |
| Caller passes owner/role/tenant attributes through a form | Privileged fields remain server-controlled |
| Wrapper adds `actor: nil` to a valid scope | The unintended override is found and removed |
| User lists records, counts, and exports | Protected records/fields do not leak in alternate read shapes |
| An update is sent directly without rendering the page | Policy still enforced |
| A worker retries after a user's access is revoked | Explicit user/service execution contract upheld |
| A shared PubSub topic announces another tenant's update | No private payload leakage; scoped reread stays authorized |
| API asks for sensitive fields through includes/relationships | Serialization and field-level access remain correct |
| An action request is replayed | No duplicate irreversible effect where idempotency is required |

For read filtering, a successful response with fewer records can be correct: forbidden
IDs and data are absent and authorized data remains visible. Not every authorization
failure is `Ash.Error.Forbidden`.

For writes, check what was persisted, not just a status code or a flash message, and
check a direct backend call separately from the UI guard.

## Version-sensitive policy details

For policies over to-many relationships, distinguish a condition on the same related
row from separate existential conditions. Inspect documented `exists/2` support and
check the intended combinations; a plausible-looking relationship filter can be too
restrictive or refer to a different business condition.

In the Ash 3.32.3 docs, create filter checks can authorize after insertion and after
`after_action` hooks, within a transaction. An eventual denial rolls back database
work, not an already sent HTTP request. Do not infer “finally authorized” from reaching
an action hook. Inspect the locked version's transaction requirements and any
`allow_post_action_authorization?` opt-in before changing this behavior. Never add that
opt-in merely to silence a preflight error. Check the denied path and that no side
effect happened.

Sources: [index](../../ash-stack/references/source-index.md), S04-S06, S14, S28.
