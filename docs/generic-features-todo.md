# Generic features to add to the template

Founder request, 2026-10-02: the template must show, simply and in the standard way,
how a page reaches the server and the database, how background jobs run, how chat
rooms work, and how agents use the site through WebMCP or the OpenAI API. This list
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

## 4. Agents: WebMCP and the OpenAI API

Today: WebMCP ships two read-only tools (`about`, `docs`) from `priv/tool_manifest.json`
through `assets/js/public_tools.ts`. The template does not use the OpenAI API. The
shared `regent_openai` package (elixir-utils `openai/`) wraps the Responses API with
strict JSON-schema replies and the cost of every call; `regent_mcp_events` covers MCP
event delivery with an Oban job owned by the site.

To do:
- [ ] WebMCP tools that act for the signed-in person (create a note, post in a room),
      declared in the manifest with `readOnlyHint: false`, going through the same Ash
      actions and policies as the page, and refusing clearly when signed out.
- [ ] Pin `regent_openai` (and `regent_http`) and add one decision example: an Ash
      generic action that asks the Responses API for a strict-schema answer (for example
      "suggest a title for this note"), run as an Oban job, with the cost saved beside
      the result and the API key read only from runtime config.
- [ ] Decide whether the template also shows MCP events (`regent_mcp_events`) or leaves
      that to Patchbay.
- Done when: a browser agent can list and create notes through WebMCP while signed in,
  and a saved note gets a suggested title from the OpenAI job, with its cost recorded.

## Open questions for the founder

1. Item 4: "OpenAI decisions API" is read here as the Responses API with strict JSON
   answers (what `regent_openai.respond/1` does). Confirm, or name the API meant.
2. Order: recommended 1 → 2 → 3 → 4, since each later item reuses the earlier ones.
