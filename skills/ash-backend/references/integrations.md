# Optional integrations: preserve the Ash boundary

Use only the packages installed or explicitly justified by the task. Resolve each
package version and read its own usage rules/docs; core Ash docs are not enough to
implement an extension correctly.

## Durable jobs: AshOban / Oban

Work that must survive a restart, retry, run later or on a schedule, or call another
service is an Oban job, through AshOban when an Ash resource owns it. That need
justifies adding Oban to a site that lacks it; never hand-build a queue, lease or
polling loop instead. Recipes are in [elixir-stack](../../elixir-stack/references/oban.md).

Inspect existing worker, trigger, queue, retry, scheduler, and test configuration.
Identify how actor and tenant are reconstructed at execution time. A queued user ID
is not a permanent authorization grant. Decide whether the job runs under current
user rights or a narrowly authorized service identity; test revocation semantics.

When state and job enqueueing must be indivisible, verify they share the intended
transaction/repository. Prove rollback does not enqueue phantom work. A retry can
repeat an external call; persist an idempotency key and reconcile unknown outcomes.
Do not assume trigger defaults match the application's authorization or queue policy.

## When one resource's action should make another react

Ash 3.36 signals let a resource announce what happened without knowing who
listens. Choose by what the reaction needs:

| The reaction | Use |
| --- | --- |
| The action needs an answer back to finish | A direct call through the other domain's code interface |
| Other parts of the site react, in the same transaction, and a failure should roll the action back | A signal with the default inline delivery: `emit` in the action, `signals_in` plus a generic action in the listener |
| The reaction is slow or calls another service, after commit, retried | A signal delivered as a job: `on ..., delivery: {AshOban.Signals, queue: ...}` |
| Work on every record matching a condition, now or on a schedule | An AshOban trigger (`run_oban_trigger`, or the trigger's sweep) |
| Tell open pages something changed, at most once, after commit | A notifier: `Ash.Notifier.PubSub` |
| Every subscriber gets every event, in order, never skipping a failed one | The event-log recipe in [Oban recipes](../../elixir-stack/references/oban.md#ordered-delivery-to-subscribers-webhooks-event-feeds); a signal is not an ordered feed |

Adopting signals in a site, the template's signals and listeners, and the rules for
writing one are in [ash-signals](../../ash-signals/SKILL.md).

## Authentication: AshAuthentication / AshAuthenticationPhoenix

Follow the existing generated authentication and session code. Do not install
`phx.gen.auth` alongside AshAuthentication as an incidental feature change. Connect
the project scope after identity/tenant resolution in HTTP and LiveView mount paths.
Review logout, token expiry, reconnect, and membership revocation. Never log tokens.

## HTTP APIs: AshJsonApi / AshGraphql

Expose an explicit supported action set and explicit public fields. Review includes,
loads, pagination, filter/sort input, errors, relationship mutation, and query cost.
The transport must resolve the same actor/tenant boundary as the UI. A new generated
endpoint needs policy and serialization tests, not just a route that returns 200.
Do not make all resource fields public to make a schema generation error disappear.

## Browser and agent tool adapters

Treat browser/agent input as untrusted transport input. Bind each tool to a named
action with bounded, typed arguments and scrubbed results. The server derives its
scope and enforces its policies; never expose an arbitrary module/action dispatcher.
A tool listing or disabled UI element does not confer authorization. Long operations
return durable job/status references. Do not execute client-provided code.

## Reactor / AshStateMachine / other extensions

Use workflow composition for a real multi-step dependency, not a three-line helper.
Distinguish compensation from rollback and database commit from external completion.
For state machines, keep transitions action-bound and verify atomic/current-state
checks. For audit, archive, money, encryption, or admin extensions, inspect their
specific guarantees instead of inferring them from the package name. A history table
is not automatically tamper-proof; an admin screen still needs authorization.

Sources: [index](../../ash-stack/references/source-index.md), S01, S34-S39. Most
requirements above are this pack's engineering choices, not package defaults.
