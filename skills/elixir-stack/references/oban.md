# Oban recipes

Versions current in Regent: `oban` 2.24, `ash_oban` 0.10 (with Ash 3.36: it
understands Oban 2.24's top-level `cron:`, `pruner:` and `lifeline:` keys, and adds
`AshOban.Signals`, which runs a signal's listener in a job). Check the site's lockfile
and read the installed version's docs before relying on an option.

## Add Oban to a site

1. Add `{:oban, "~> 2.24"}`, and `{:ash_oban, "~> 0.10"}` when Ash resources will
   own jobs. The `oban.install` and `ash_oban.install` Igniter tasks set up the same
   pieces when the site uses Igniter.
2. Migration, in the site's own schema (Autolaunch:
   `priv/repo/migrations/20260924081420_add_oban.exs`):

   ```elixir
   def up, do: Oban.Migrations.up(prefix: "mysite_app")
   def down, do: Oban.Migrations.down(prefix: "mysite_app")
   ```

3. Configuration:

   ```elixir
   # config/config.exs
   config :my_app, Oban,
     repo: MyApp.Repo,
     prefix: "mysite_app",
     queues: [default: 10, webhooks: 20],
     # Required with AshOban, even empty: it adds each trigger's sweep here.
     cron: [crontab: []],
     pruner: [max_age: {7, :days}],
     lifeline: [rescue_after: {10, :minutes}]

   # config/test.exs
   config :my_app, Oban, testing: :manual

   # config/runtime.exs, when the site's schema is set at runtime (Patchbay)
   config :my_app, Oban, prefix: database_schema
   ```

   The migration takes the same schema the repo migrates into:
   `Oban.Migrations.up(prefix: prefix() || "public")`.

   The top-level `pruner:`, `lifeline:` and `cron:` keys are what start Oban's
   maintenance: `Oban.Config` turns each into its plugin (`Oban.Pruner`,
   `Oban.Lifeline`, `Oban.Cron`), and `AshOban.config/2` keeps them and their leader
   (checked in Oban 2.24.2 and AshOban 0.10.1 to 0.10.3). Never write the old
   `plugins: [{Oban.Plugins.Pruner, ...}]`, and never `plugins: false`, which turns all
   three off. The baseline every site keeps:

   - `pruner: [max_age: {7, :days}]`. The pruner deletes completed, cancelled and
     discarded jobs older than that, up to 10,000 every 30 seconds, from the leader.
     Always give `max_age`: a bare `pruner: Oban.Pruner` keeps jobs 60 seconds. A job
     that is unique with `states: :all` is unique only until it is pruned.
   - `lifeline: [rescue_after: {10, :minutes}]`, longer than the slowest single run of
     any job, or Lifeline takes a job still running for one whose machine stopped and
     runs it again (Autolaunch keeps 20 minutes, above its 15-minute volume reads).
   - `cron: [crontab: [...]]`, even empty, with AshOban.

4. Supervision, after the repo. With AshOban, wrap the config so triggers and
   scheduled actions get their queues and cron entries:

   ```elixir
   {Oban, AshOban.config(Application.fetch_env!(:my_app, :ash_domains),
                         Application.fetch_env!(:my_app, Oban))}
   ```

## Queues

Every queue holds one class of work, so a slow or failing outside service holds up
only the jobs that wait on it, never a person's other work:

| Class | Holds | Template queues |
| --- | --- | --- |
| Database | Work on the site's own rows: sweeps, pruning, rereads, jobs that only queue other jobs | `default`, `points` |
| Chain reads | Reads through a chain node | `ens`, `purchase_checks`, `points_chain` |
| Model calls | Questions to a model (OpenRouter, Anthropic) | `chat_responses`, `conversations`, `note_labels` |
| Other outside calls | Every other request to another website: webhooks, IndexNow, an image or video service | `outside_calls` |

- A chain read, a model call or another outside call never runs in `default`, and two
  classes never share a queue. A job that only queues others (a cron dispatcher, a
  sweep) is database work, whatever the jobs it queues do.
- Within a class, a kind gets its own queue when a burst of it must not hold up the
  rest of its class: every sign-in looks up one ENS name, so `ens` is apart from the
  other chain reads. Otherwise kinds share their class's queue.
- Choose the limit by what the job waits on. A database job holds a connection for
  most of its run, so the database queues' limits together stay near the Repo's pool
  (5 on the shared database; ash-data, "Connections"). An outside-call job holds a
  connection only to read before and write after the call, so its limit is what the
  other service and the budget allow: its rate limit, a daily cap such as Jev's
  `daily_questions`, and how long one call takes. Start at 1 to 3.
- Raise a limit when `[:ash_template, :jobs, :oldest_unfinished]` shows that queue's
  jobs waiting, and lower it when the other service answers 429.
- Moving a job to another queue needs no migration: a job already queued stays in
  its old queue and runs there while that queue is still configured, so keep the old
  queue in the list until it is empty.

## One job per thing, and effects safe to repeat

Every job that can be queued twice for the same thing (a refresh, a sync, a sweep, a
notice) says what "the same" is, explicitly:

- `keys:` the args that name the thing: an id, a kind, a release
  (`unique: [keys: [:kind], ...]`). A job with no args names its worker:
  `fields: [:worker]`.
- `period: :infinity`: unique by state, not by a time window. A window lets a second
  copy in once it passes, while the first may still be running.
- `states:`, by what a second copy would add:
  - `:incomplete` (available, scheduled, executing, retryable, suspended): one at a
    time. Refreshes, syncs, sweeps, pruners (`AshTemplate.SharedReading.Heal`,
    `AshTemplate.ErrorPruner`, `AshTemplate.Credits.CheckPurchase`).
  - `[:available, :scheduled, :retryable]`: a notice of change. A copy queued while
    one waits adds nothing, but a change after sending began must be sent again
    (`AshTemplate.IndexNow.submit/1`).
  - `:all`: once, for as long as the job's row is kept. The pruner deletes finished
    jobs after `max_age`, and the same args can then be queued again: the template's
    once-per-release sitemap goes to IndexNow again after a week on one release.
- Oban 2.24 merges a worker's `unique:` with one passed to `new/2` key by key
  (`Oban.Worker.merge_opts/2`; its docs still say the second replaces the first), so
  a call that overrides names every key it means.
- AshOban triggers are already one job per record while incomplete, unique over all
  their args, so `extra_args` (a note's `revision`) gives each value its own job.
- A cron entry is queued only by the leader, once per tick; it still needs uniqueness
  when a slow run or a busy queue could leave the last tick's job waiting.

Uniqueness stops a duplicate job, not a repeated effect: a job can still run twice
(a retry, or Lifeline rescuing it from a stopped machine). Give each effect a stable
operation key, the same args the uniqueness names, and let the receiver ignore a
repeat of it: the event id in ordered delivery (below), a note webhook's `note_id` and
`revision`, a Credits purchase's `tx_hash`, which Regent Credits credits once however
often it is reported. A request from outside does the same with a key the caller
chooses: Patchbay's `client_request_id` on `post_reply` returns the first reply for a
repeat and refuses the same key with different words (`Patchbay.Forum.Reply`, unique on
the session and the key, with a digest of the body).

## A plain worker

```elixir
defmodule MyApp.Workers.SendReceipt do
  use Oban.Worker, queue: :webhooks, max_attempts: 8,
    unique: [keys: [:order_id], period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => id}}) do
    with {:ok, order} <- MyApp.Orders.get(id),
         :ok <- MyApp.Receipts.send(order) do
      :ok
    end
  end
end
```

Args are JSON: string keys, ids rather than structs, and never secrets (jobs are
stored in plain text and shown on dashboards). Read the current record inside
`perform`; it may have changed since the job was queued.

## Queue a job with the change, in one transaction

```elixir
Ash.transact(MyApp.Orders.Order, fn ->
  order = MyApp.Orders.place!(params)
  Oban.insert!(MyApp.Workers.SendReceipt.new(%{order_id: order.id}))
  order
end)
```

Inside an Ash action, queue it from `after_action`, which runs inside the action's
transaction. For a job on the same record, use the AshOban change:
`change run_oban_trigger(:send_receipt)`.

## AshOban trigger: work on every record that matches

A trigger runs an action on each record matching `where`, one job per record at a
time. The scheduler sweeps on `scheduler_cron` (every minute by default; `false`
turns it off), and `AshOban.run_trigger(record, :name)` or `run_oban_trigger` queues
one record straight away.

```elixir
oban do
  triggers do
    trigger :finish do
      action :finish
      where expr(state == :running)
      queue :auction_finishing
      max_attempts 5
      on_error :mark_failed
      worker_module_name MyApp.Auction.Workers.Finish
      scheduler_module_name MyApp.Auction.Schedulers.Finish
    end
  end
end
```

Name the worker and scheduler modules so renaming the trigger does not orphan
queued jobs. `max_attempts` defaults to 1. After the last failed attempt, the
`on_error` update action runs with the error as its `error` argument; make it
change the record so `where` stops matching, or the scheduler keeps re-queuing it.
Autolaunch's `AuctionFinish` and Patchbay's `EventSubscription` are working examples.

- The trigger's action must be an update (or destroy) for `on_error` to run; a
  generic action trigger never calls it.
- An action that calls another service sets `transaction?(false)`, so the call is
  not made inside a database transaction, and `lock_for_update?(false)` on the
  trigger, since the one-job-per-record rule is the lock.
- AshOban logs every failed attempt by default. For outside calls that fail for a
  while as a matter of course, set `log_errors?(false)`: Oban keeps each attempt's
  error on the job, and the final failure is still logged.
- The trigger's uniqueness includes executing jobs, so a job cannot queue a second
  run of itself for the same record: that insert is dropped. Do all the record's
  work in one run (bounded), and let the sweep take up the rest.
- To wake a trigger from another resource's change, queue its sweep with
  `AshOban.schedule(Resource, :trigger)` in that change's `after_action`; the sweep
  is one job however many changes land.

### A timer loop becomes a sweep

A process that wakes on a timer to call another service for each waiting row (a
chain read, a model call) becomes an AshOban trigger whose `where` matches those rows
and whose `scheduler_cron` is the old interval. Patchbay's escrow Base reads and its
agent repairs are worked examples.

- When the next sweep is the retry, set `max_attempts 1` and let the sweep offer the
  row again, rather than Oban's backoff. Give it no `on_error` that moves the row out
  of `where`; that would end the retries.
- The action makes its outside call with `transaction?(false)`, as above, so no
  database transaction stays open across the network.
- The trigger's one job per record (available, scheduled or executing) keeps a slow
  call from running twice for the same row.
- A guard that declines on purpose (a switch turned off, a daily cap spent) returns
  the record unchanged without an error, so the job ends `:ok`, nothing is logged as
  a failure, and the row waits for the next sweep.
- The release note gives the outside-call rate, for example "one Base read per held
  bounty every 5 minutes".
- The same change deletes the old loop, its supervisor entry and its poll setting.

## Ordered delivery to subscribers (webhooks, event feeds)

The pattern for "send each subscriber every event, in order, never skipping one
that failed":

1. **Event log.** Each event is a row written in the same transaction as the change
   that caused it, with a sequence number that is safe to read in commit order.
2. **Subscriber cursor.** Each subscription stores the last sequence number its
   receiver acknowledged, and whether it is active.
3. **One job per subscription.** An AshOban trigger on the subscription with
   `where` "active, unexpired and behind an event of its kind" (an `exists` over the
   event table), or a plain worker unique on the subscription id. The job reads the
   first owed event after the cursor, sends it outside any transaction, and on
   success advances the cursor with a compare-and-set from the value it read. It
   repeats until nothing is owed or a per-run limit is reached.
4. **Wake-up.** When an event row is written, queue the trigger's sweep in the same
   transaction (`AshOban.schedule`), and run the trigger on subscribe and refresh
   (`run_oban_trigger`). The minute sweep catches an event that lands while a job
   for that subscription is already running.
5. **Failure.** Return `{:error, reason}` to retry the same event with backoff.
   When attempts run out, `on_error` stops the subscription and keeps its cursor.
   A refresh switches it back on, and delivery resumes at the same event.
6. **Repeats.** A job can run twice, so the event id is stable and the receiver
   uses it to ignore a repeat. The compare-and-set stops a double run from moving
   the cursor twice.

Oban's job table holds the attempt count, retry time and running state. The
subscription table holds only the cursor, its settings and whether it is active.
There are no lease, attempt or next-attempt columns.

## Testing

```elixir
use Oban.Testing, repo: MyApp.Repo, prefix: "mysite_app"

assert_enqueued worker: MyApp.Workers.SendReceipt, args: %{order_id: order.id}
assert :ok = perform_job(MyApp.Workers.SendReceipt, %{order_id: order.id})
```

For AshOban, `use AshOban.Test, repo: MyApp.Repo` and
`AshOban.Test.schedule_and_run_triggers(MyResource, actor: actor)` run the
scheduler and the jobs it queues.

## Seeing what happens

Oban emits `:telemetry` events for job start, stop and exception; attach them to
the site's metrics (queue depth, failures, run time). Oban Web is a dashboard of
queued, retrying and failed jobs; mount it behind founder-only access.
