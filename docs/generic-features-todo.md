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
- [x] One small product resource on AshPostgres (for example a note owned by the
      signed-in account), with a migration from `mix ash.codegen`, a policy, and a code
      interface on the domain.
- [x] A LiveView page with an action-bound `AshPhoenix.Form` (validate on change, create
      and update on submit, errors kept on the form) and a stream for the list.
- [x] Open pages hear about changes through `Phoenix.PubSub` (Ash `pub_sub` notifier),
      so a second tab updates without reloading.
- [x] The same action reachable over the JSON API and listed in the OpenAPI contract,
      so page, API and agents share one action.
- Done when: a signed-in person creates, edits and lists their notes; another account
  cannot read them; a second open tab updates live.
- Built 2026-10-02 on branch `feat/notes`: `AshTemplate.Notes.Note`, the `/notes` page
  (`NotesLive` inside `ShellLive`) and `/api/v1/notes` (`NotesController`), all through
  the same actions and policies.

## 2. Background jobs with Oban

Today: Oban and AshOban run in the site's own schema, and saving a note posts the save
to an address the site owner sets (`ASH_TEMPLATE_NOTES_WEBHOOK_URL`). The rules and
recipes are in `skills/elixir-stack/references/oban.md`.

To do:
- [x] Add `oban` and `ash_oban`; one Oban instance in the site's own schema
      (`prefix: "ash_template_app"`), its migration with the same prefix, top-level
      `pruner:` and `lifeline:`. Queues hear of new jobs through `Oban.Notifiers.PG`,
      since the serving connection's pooler drops LISTEN/NOTIFY. The template has no
      test environment, so there is no `testing: :manual` setting.
- [x] One AshOban trigger on the note resource (`send_webhook`): every create and edit
      queues one job in its own transaction while the address is set, with
      `max_attempts 5` and an `on_error` action (`webhook_failed`) that records the final
      failure on the note. Each job carries the save's `revision`, so jobs are unique
      per save rather than per note, and an outcome is recorded only while the note is
      still at that save. No minute sweep: no save can lose its job.
- [x] The call to another website (`AshTemplate.Notes.Webhook`) uses Req in a
      `before_action` of a `transaction? false` action, so it runs outside any
      transaction. A 2xx answer is `:ok`, 429 snoozes for Retry-After, a removed address
      cancels, anything else fails and retries. The `webhook-id` header is the same on
      every attempt at one save, so running twice is harmless at the receiving end.
- [x] A slow-calls queue (`outside_calls`) separate from the default queue; job
      outcomes and run times in the Prometheus metrics.
- Done when: saving a note queues exactly one job in the same transaction, a forced
  failure retries with backoff and then records the failure, and a rolled-back save
  queues nothing. (Met 3 Oct 2026 on `feat/oban`, local: also checked a 429 pause, an
  older job finishing after a newer save, a deleted note, and no address set.)

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
- 2026-10-02: notes are what people wrote, a protected category. If the template ever
  runs against the shared production database, `ash_template_app.notes` goes on
  `regent_guard.protected_tables` first.

## Order

Agreed 2026-10-02: 1 → 2 → 3 → 4, since each later item reuses the earlier ones.
