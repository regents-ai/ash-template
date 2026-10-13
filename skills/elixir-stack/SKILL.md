---
name: elixir-stack
description: Elixir, Phoenix, Ecto, Oban and OTP judgment for Regent's sites. It covers which standard tool does each job, what never to hand-build, the design check that comes before building or reviewing, and how Regent runs Oban. Load it with regent-workflow and ash-stack before any Elixir work, and whenever the work involves background or retried work, schedules, webhooks or calls to other services, polling, queues, leases, GenServers, PubSub, caches, HTTP clients or a shared Elixir library.
---

# Elixir stack

Regent sites are Phoenix and Ash on Postgres. Before you design, build or review
Elixir code, name the standard tool for every moving part. A smaller copy of a
standard tool is a defect, however correct the copy is.

## The standard tool for each job

| Job | Use | Never |
| --- | --- | --- |
| Work that must survive a restart, retry, run later, run on a schedule or call another service | Oban; in an Ash resource, AshOban | GenServer loops, `Process.send_after` polling, `Task.start`, status, attempt or lease columns |
| Record that something happened, in order | A table written in the same transaction as the change (an event log or outbox) | Ash notifiers or PubSub alone: they run after commit and can be lost |
| Tell open pages or other processes that something changed | `Phoenix.PubSub`, paired with Oban or a table when it must not be lost | Polling the database |
| Data, constraints and locks | Ash actions on AshPostgres; Ecto for migrations and justified queries | Uniqueness checked in code without a database constraint |
| Call another website | Req | HTTPoison, `:httpc`; Mint only where Req cannot do it, such as connecting to an address checked in advance |
| Short concurrent work inside one request | `Task.async_stream`, `Task.Supervisor` | Unsupervised `spawn` |
| In-memory state one process owns | A supervised GenServer or Agent, named through `Registry` | A GenServer as a job queue or as a copy of database rows |
| Fast read-mostly lookups | ETS or `:persistent_term` | A `GenServer.call` bottleneck |
| Measurements | `:telemetry` events | Ad hoc log lines |

## Never hand-build

Job queues, claim or lease columns, lock tokens, attempt counters, next-attempt
timestamps, retry and backoff timers, schedulers and cron loops, worker pools,
"rescue stuck work" sweeps and distributed locks. Oban already provides each one:
jobs, unique jobs, `max_attempts` with backoff, `scheduled_at`, `cron:`, queue
limits and `lifeline:`. If Oban truly cannot express a requirement, write down why
and get the lane owner's agreement before building anything.

## Processes that may reread on their own

Two shapes are allowed beside the rules above, because neither is work: nothing is
queued, nothing is retried and nothing they hold must survive a restart. Both write
only through `AshTemplate.SharedReading`, which shares one reading with every open
page (ash-frontend, [public figures](../ash-frontend/references/public-figures.md)).

- **A supervised reader of an outside clock**, such as a chain's newest block
  (`AshTemplate.ChainHead`). It holds no queue and no copy of database rows, and it
  never writes the database. Nothing is retried: a missed read is replaced by the
  next one. The next read is scheduled when the last has finished, never on a fixed
  interval. Its Req call has `retry: false` and gives up well inside one tick. One
  runs per chain per machine, with telemetry for the age of its reading and for each
  failed read.
- **A reread on notice.** The producer of a reading built from the site's own rows
  subscribes to those rows' notices and rereads at most once a second however many
  arrive. It holds nothing but "a reread is due".

The watcher that records chain events keeps its own rules in `chain-events`. Anything
else that loops, polls or schedules itself is Oban's, and a third shape needs the lane
owner's agreement before it is built.

## Design check: before building, and before reviewing

1. List the moving parts: what is stored, what runs later, what retries, what talks
   to the outside world, what must stay in order, what must happen at most once.
2. Name the standard tool for each part from the table above. Only a part with no
   standard tool becomes custom code.
3. When reviewing, do this before checking correctness. Correct code that rebuilds a
   standard tool is a finding ("replace with Oban"), not a list of fixes to it.
4. Durable work justifies adding Oban to a site that lacks it. "The site does not
   have it yet" is never a reason to hand-build it.
5. A shared Regent library holds pure, protocol or security-sensitive code: signing,
   safe outbound HTTP, identities, parsing, error mapping. The site owns its jobs,
   tables and supervision. A shared library never ships its own queue or worker loop.

## Oban at Regent

Read [Oban recipes](references/oban.md) before adding or changing a job. The rules:

- One Oban instance per site, in the site's own Postgres schema through `prefix:`.
  All sites share one production database; Autolaunch uses `prefix: "autolaunch_app"`.
  The Oban migration takes the same prefix.
- From Oban 2.24, configure maintenance with the top-level keys `pruner:`,
  `lifeline:` and `cron:`; the `Oban.Plugins.*` names are deprecated. Always prune
  and always run Lifeline.
- Queue the job in the same transaction as the change it follows: inside
  `Ash.transact`, an action's `after_action`, an `Ecto.Multi` or the AshOban
  `run_oban_trigger` change. A rolled-back change then queues nothing, and a
  committed change always has its job.
- Never make an HTTP or chain call inside a database transaction. A job reads, calls
  out, then writes.
- A job can run twice: after a retry, or when Lifeline rescues it from a node that
  died. Make every effect safe to repeat: advance state with a compare-and-set and
  send a stable id the receiver can use to ignore a repeat.
- Return `:ok` when done; `{:error, reason}` (or raise) to retry with backoff;
  `{:cancel, reason}` to stop for good; `{:snooze, seconds}` to wait without using an
  attempt.
- Set `max_attempts` on purpose (AshOban triggers default to 1) and decide what
  running out of attempts means. With AshOban, the `on_error` update action
  records it.
- One job at a time per key: `unique: [keys: [...], period: :infinity, states:
  :incomplete]`, where `:incomplete` includes executing jobs. AshOban trigger workers
  already do this for each record.
- The queue `limit` bounds concurrency. Give slow outside calls their own queue so
  they cannot hold up other work.
- Tests: `testing: :manual` in `config/test.exs`, `use Oban.Testing, repo: ...`, then
  `perform_job/2` and `assert_enqueued/1`.
- Oban never queues, retries, defers or deduplicates a person's on-chain action;
  every press reaches the wallet (regent-workflow). Server work after a confirmed
  chain event is ordinary Oban work.

## Phoenix, Ecto and OTP

[OTP, Phoenix and Ecto essentials](references/otp-phoenix-ecto.md) covers
supervision, PubSub, transactions and locks, Req, telemetry, and the mistakes that
make these slow or unsafe.
