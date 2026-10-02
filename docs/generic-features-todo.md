# Generic features to add to the template

Founder request, 2026-10-02: the template must show, simply and in the standard way,
how a page reaches the server and the database, how background jobs run, how chat
rooms work, and how agents use the site through WebMCP and Jev model decisions. This list
records what the template has today and what each feature still needs. Every item
follows `skills/elixir-stack` (standard tool for each part) and `skills/ash-stack`.

## 1. Page to server to database, end to end

Today: sign-in and the account page go LiveView → `AshTemplateWeb.Read` (`start_async`)
→ Ash code interface → AshPostgres, and the session controller goes through
`SessionAuthority`. The showcase's `Sample` resource uses the Simple data layer, so no
example saves anything a person types.

To do:
- [ ] One small product resource on AshPostgres (for example a note owned by the
      signed-in account), with a migration from `mix ash.codegen`, a policy, and a code
      interface on the domain.
- [ ] A LiveView page with an action-bound `AshPhoenix.Form` (validate on change, create
      and update on submit, errors kept on the form) and a stream for the list.
- [ ] Open pages hear about changes through `Phoenix.PubSub` (Ash `pub_sub` notifier),
      so a second tab updates without reloading.
- [ ] The same action reachable over the JSON API and listed in the OpenAPI contract,
      so page, API and agents share one action.
- Done when: a signed-in person creates, edits and lists their notes; another account
  cannot read them; a second open tab updates live.

## 2. Background jobs with Oban

Today: Oban is not a dependency. The rules and recipes exist
(`skills/elixir-stack/references/oban.md`); Autolaunch runs Oban in production and is
the donor.

To do:
- [ ] Add `oban` and `ash_oban`; one Oban instance in the site's own schema
      (`prefix: "ash_template_app"`), its migration with the same prefix, top-level
      `pruner:` and `lifeline:`, `testing: :manual` in test config.
- [ ] One AshOban trigger on the note resource (for example "summarise after save")
      queued in the same transaction as the change, with `max_attempts`, an `on_error`
      action that records the final failure, and `unique` per record.
- [ ] One plain worker that calls another website with Req outside any transaction,
      returns `:ok`, `{:error, _}`, `{:cancel, _}` or `{:snooze, _}`, and is safe to run twice.
- [ ] A slow-calls queue separate from the default queue; `:telemetry` on job outcomes.
- Done when: saving a note queues exactly one job in the same transaction, a forced
  failure retries with backoff and then records the failure, and a rolled-back save
  queues nothing.

## 3. Chat rooms

Today: `/showcase/discussion` renders the shared `Regent.Discussion` component from
sample data. Nothing is saved, nothing is live, and there is no presence. KeyFleet
(`keyfleet/rooms`) and Patchbay (`patchbay/room.ex`) both have Ash room resources and
are the donors.

To do:
- [ ] `Room` and `Message` resources on AshPostgres with policies (who may read, post,
      edit their own message), an identity for room slugs, and paging by insertion time.
- [ ] A LiveView room page: messages as a stream, a post form bound to the create
      action, new messages pushed to every open page through `Phoenix.PubSub`, and
      `Phoenix.Presence` for who is here.
- [ ] Posting rate limit through the existing limiter, and moderation (hide a message)
      as an Ash action with its own policy.
- [ ] Agents can read a room and post (with sign-in) through the WebMCP tools in item 4.
- Done when: two browsers in one room see each other's messages and presence at once,
  a signed-out visitor can read but not post, and reloads show the saved history.

## 4. Agents: WebMCP and Jev decisions

Today: WebMCP ships two read-only tools (`about`, `docs`) from `priv/tool_manifest.json`
through `assets/js/public_tools.ts`. The template makes no model calls. OpenAI's own
decisions API is not public yet, so model decisions use Jev, the classifier Patchbay
already runs: OpenRouter's decisions endpoint (`/api/alpha/decisions`, model
`~typesafe/jev-latest`), which answers each question with one of the keys it was given
and a confidence. Patchbay's version (`repos/patchbay/platform/lib/patchbay/forum/jev.ex`,
`assist/known_fix_pick.ex`, `assist/judge.ex`) is the donor.

To do:
- [ ] WebMCP tools that act for the signed-in person (create a note, post in a room),
      declared in the manifest with `readOnlyHint: false`, going through the same Ash
      actions and policies as the page, and refusing clearly when signed out.
- [ ] A Jev client in elixir-utils (decided below): one function that sends `{model, state, questions}` and returns
      `{:ok, %{choice, confidence, usage}}` only when the choice is one of the offered keys,
      otherwise `{:error, :unexpected_answer}`. Req through `regent_http` (telemetry and
      secret redaction), endpoint, model and `OPENROUTER_API_KEY` read once in
      `config/runtime.exs`, a short receive timeout, no Req retries (Oban retries).
- [ ] One decision example on the note resource ("which label fits this note?"), held in
      a `Decision` resource: subject, question, offered keys, choice, confidence, model,
      tokens, cost, state, inserted_at. The decision row is created in the same
      transaction as the change that asks for it, and an AshOban trigger runs the Jev call
      outside any transaction (`max_attempts: 3`, an `on_error` action that records the
      failure, unique per decision). The page hears the answer through PubSub.
- [ ] Spending limits as Ash rules, not plain functions: a daily model-call budget counted
      from decision rows (every Jev question counts, not every run), checked by a policy
      on the create action, with the counting index in the migration.
- [ ] Feedback: one "worked / didn't" report per decision, stored on the row; a second
      report is refused.
- [ ] `:telemetry` on every Jev call (duration, outcome, tokens, cost) feeding the
      existing Prometheus reporter.
- Done when: saving a note queues exactly one Jev job, a browser agent can read the
  chosen label through WebMCP while signed in, the decision row shows the model, tokens
  and cost, a forced failure retries and then records the failure, and a rolled-back
  save queues nothing.

What this improves on Patchbay (also worth taking back there): Patchbay runs Jev from a
hand-built in-memory queue (`assist/runner.ex`) that loses queued paid runs on a deploy
and a polling GenServer (`forum/jev_reader.ex`); it records no cost or tokens and emits
no telemetry; its help caps are counted without a lock and its model budget counts one
run as one call although a run can ask up to 14 questions; endpoint and model are
hard-coded and the key is read with `System.get_env` at call time; a decision's report
can be overwritten by anyone holding its id; `assist_decisions` has no indexes for the
counts it runs on every request.

## Decided

- 2026-10-02: the Jev client is a small shared package in elixir-utils beside
  `regent_http` (request, answer checks, telemetry); each site keeps its own jobs,
  tables and limits. Patchbay can switch to it.

## Order

Agreed 2026-10-02: 1 → 2 → 3 → 4, since each later item reuses the earlier ones.
