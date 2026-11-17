# Logging that can replay a visit

Plan, 26 Oct 2026. Requested by Sean on 25 Oct:

1. Plan logging good enough to replay what a person or agent experienced, the
   internal operations that mattered, and what they saw at the end. Build it in
   ash-template first, as the reference for WebMCP and the CLI.
2. Connect it to Sentinel.
3. Then run a daily review of the last 24 hours for Autolaunch and Keyfleet.

Nothing here is built yet. The decisions at the end are Sean's to make.

## What we can see today

- **Sites** write plain text lines (`time request_id [level] message`) at info
  level in production. Each request logs a "GET /path" line and a "Sent 200"
  line. Nothing ties those lines to one visit, and nothing says what the person
  pressed or saw.
- **Measurements** (Peep and telemetry) count database time, chain and wallet
  failures, Oban jobs and agent activity. They are totals, so they can't follow
  one visit.
- **ErrorTracker** keeps crashes at `/admin/errors`.
- **Sentinel** hears every line from every Fly app through Fly's log feed. It
  keeps warning and error lines for 14 days and emails each new kind of error
  once a day. It drops every info line, which includes everything a normal
  visit writes.
- **WebMCP tools and the CLI already use the same server addresses.** Each
  browser tool in
  `/Users/sean/Documents/regent/repos/ash-template/platform/assets/js/public_tools.ts`
  calls an `/api/v1/...` address, and the CLI calls the same addresses with a
  signature. If the server records each call once and says who made it, both
  are covered.

## The shape

### One event line

Every event is one JSON line with a fixed set of fields:

| Field | Meaning |
| --- | --- |
| `event` | What happened, such as `page.open`, `press`, `tool.call`, `action.done`, `job.done`, `shown` |
| `visit` | A random id for one browser visit or one agent session. It is not linked to the account |
| `request` | The request id we already log, so ordinary lines join up with events |
| `surface` | `page`, `webmcp`, `cli`, `agent_http` or `job` |
| `actor` | `person`, `agent` or `anonymous`, plus a one-way hash of the account or agent (decision 1) |
| `where` | The route, LiveView event name, tool name, Ash action or Oban worker |
| `outcome` | `ok`, a refusal code (the same codes the API already returns) or `failed` |
| `shown` | Which message the person or agent was shown, by its key, never its full text |
| `ms` | How long it took |

Only these fields are allowed. A field outside the list never reaches the line,
so free text, message bodies, notes, emails and secrets can't leak through it.

### Where the events come from (standard tools only)

- **The formatter.** LoggerJSON changes the existing log lines to JSON. Sentinel
  already reads a JSON line's `severity`, so its error alerts keep working.
- **Pages:** Phoenix and LiveView already emit `:telemetry` events when a page
  opens, an event is handled or the address changes. One handler turns those
  into `page.open`, `press` and `navigate`.
- **Internal operations:** Ash actions, Oban jobs and outgoing Req calls also
  emit `:telemetry` events. Handlers record which action ran, its result and its
  duration, but not the inputs.
- **WebMCP and the CLI:** one plug on the `/api/v1` and `/api/agents` routes
  writes `tool.call` with the tool name and outcome. Each caller adds a short
  header to say what it is. The browser tool transport sends
  `x-regent-client: webmcp/<tool>`, and the CLI sends
  `regents-cli/<version> <command>` (the CLI lane adds this; the site never
  waits for it).
- **What only the browser knows:** a wallet prompt that was approved or
  declined, a page error, or a tool that never reached the server. The browser
  sends these in small batches to one site address, and the site writes them as
  lines. The site saves nothing to its own database for this (decision 3).
- **What the person saw at the end:** flash messages, notes beside buttons and
  refusal messages already come from a few shared places. Each one logs its key
  as `shown`.

### Sentinel's part

- Keep the event lines at info level in their own events table, indexed by app,
  visit and time. Plain info lines are still dropped.
- Delete old events on a schedule, the same way warning lines are deleted now
  (decision 2).
- Add a page that shows one visit's events in order, joined with that visit's
  warning and error lines. This is the replay.
- Add a read-only export of the last 24 hours for one app. The daily review
  reads it.
- Sentinel's code and releases belong to the Sentinel chief, and each Sentinel
  release needs Sean's letter in that lane.

### The daily review

Once a day it reads the last 24 hours of events and warning lines for Autolaunch
and Keyfleet. It runs Sean's prompt word for word:

"analyze my logs from this program in the past 24h thoroughly, identify broken
behaviors, user friction, inefficiencies, and propose improvements sorted by
estimated impact for the autolaunch and keyfleet codebases".

It writes one report a day and tells Sean where it is (decision 4). It only
reads; it doesn't change any code.

## Order of work

1. **Template.** Add the formatter, the handlers, the API plug, the browser
   batch address and the `shown` keys. Write a property test that throws random
   inputs at the event writer and checks that no field outside the list ever
   appears in a line. Run a browser walk that replays one visit from its lines.
   Release with Sean's template letter.
2. **Sentinel.** Add the events table, deletion of old events, the visit page
   and the export. Release with Sean's Sentinel letter.
3. **Autolaunch and Keyfleet** copy the template's version word for word, each
   in its own queue with its own letter. The other three sites follow later.
4. **Daily review.** Start it once two days of Autolaunch and Keyfleet events
   are in Sentinel, so the first report has real data.

## What it costs

- At the 1,000–2,000 person target, a busy visit writes about 50 events, so a
  busy day is about 100,000 rows per site. That is small for Postgres with one
  index, and the lines already travel through Fly's log feed today.
- No new machines are needed. The site writes nothing new to its own database.
