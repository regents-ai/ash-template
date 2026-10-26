# Logging that can replay a visit

Requested by Sean on 25 Oct 2026:

1. Plan logging good enough to replay what a person or agent experienced, the
   internal operations that mattered, and what they saw at the end. Build it in
   ash-template first, as the reference for WebMCP and the CLI.
2. Connect it to Sentinel.
3. Then run a daily review of the last 24 hours for Autolaunch and Keyfleet.

Sean's decisions, 26 Oct 2026 ("1a 2a 3a 4a 5a"):

1. **What a line may hold:** event names, pages, tool names, results and timings.
   Accounts and wallets only as a one-way code. Never message text, notes or emails.
2. **How long:** Sentinel keeps visit lines 30 days; warnings and errors stay 14.
3. **The browser** reports only what the server can't see. The site stores nothing new.
4. **The daily review** is a scheduled task on Sean's Mac. Its report goes in
   `/Users/sean/Documents/regent/control/coordination/log-review/`, and Sean gets a
   notification.

The template part is built (below). Sentinel's part, the sites' copies and the
daily review follow, in the order at the end.

## One line

In production every line is one JSON object (LoggerJSON's basic shape):

```json
{"time":"…","severity":"info","message":"press NotesLive:save ok",
 "metadata":{"visit":"9QxA6VnjnEaus6YHMrNArQ","request_id":"GOItfW1pO7ZpVNcAAHPG",
             "actor":"person:5a8162a0e7ba15e1","surface":"page",
             "event":{"name":"press","where":"NotesLive:save","outcome":"ok","ms":3}}}
```

Only five metadata fields can reach a line (`AshTemplateWeb.VisitLog.fields/0`):

| Field | Meaning |
| --- | --- |
| `visit` | A random id for one browser visit, kept in an httpOnly cookie for the browser session. A page's scripts that send no cookies send it in `x-regent-visit`. It is not linked to the account |
| `request_id` | The request id Phoenix already gives every request |
| `surface` | `page`, `webmcp`, `cli`, `agent_http` or `job`. An `/api` call that names no tool or command but carries a visit, in the cookie or the header, is the page's own script, so it is `page` |
| `actor` | `person:`, `agent:` or `anonymous`, then the first 8 bytes of an HMAC of the account or agent id, keyed from the site's secret. The same person always gets the same code; the code can't be turned back into the id |
| `event` | `name`, `where`, `outcome` and `ms` (below) |

An event's `where` and `outcome` must fit a short pattern of plain characters, or
they are written as `other`. Nothing a person typed can reach a line.

| Event | Written when | `where` | `outcome` |
| --- | --- | --- | --- |
| `request` | A page request finishes | The route, such as `/rooms/:room` | `ok` or `status_404` |
| `tool.call` | An `/api` request finishes | The tool name from `x-regent-client`, else the route | `ok`, the error's code, or `status_N` |
| `page` | A connected page opens or changes address | The route | none |
| `press` | A page or component event finishes | `View:event` | `ok`, `failed`, or for wallet steps `sent`, `signed` or the failure reason |
| `action` | An Ash create, update, destroy or generic action finishes during a request, press or job | `resource.action` | none |
| `job` | An Oban job finishes | The worker | Oban's state |
| `outgoing` | A call to another service finishes during a request, press or job | `METHOD host` | The status |
| `page.error` | The browser reports an uncaught error | The route | `error` or `unhandledrejection` |
| `tool.unsent` | A browser tool's call never got an answer | The tool | `unreachable` or `outcome_unknown` |
| `press.unsent` | A wallet step's answer never reached the server | The step | `lost` |

A press line is written when the press finishes, so the actions it caused come
just before it. Phoenix's own request lines are off in production: they repeat
each raw path and its parameters.

"What the person saw" is the outcome. Each outcome code picks the words shown,
so the code is enough to know the message without logging its text.

## Where the lines come from

All standard tools; nothing is queued or stored by the site.

- `AshTemplateWeb.VisitLog` (a plug and a LiveView `on_mount`): sets `visit`,
  `surface` and the caller's tool on the process, and writes lines.
- `AshTemplateWeb.VisitLog.Events`: `:telemetry` handlers for Phoenix endpoint and
  LiveView, Ash, Oban and Finch events.
- `POST /visit-log` (`AshTemplateWeb.VisitLogController`): the browser's reports,
  at most 20 lines a batch, rate limited with the other browser reports. The
  browser sends a batch every 5 seconds or when the page is hidden
  (`assets/js/visit_log.ts`).
- **WebMCP:** each browser tool sends `x-regent-client: webmcp/<tool>` and the
  visit (`assets/js/public_tools.ts`). Signed tools take the same headers through
  the shared transport's required `requestHeaders` setting (elixir-utils
  `agent_access/assets/signed_tools.ts`, from commit `c4fdaae6`).
- **CLI:** sends `x-regent-client: regents-cli/<version> <command>`. The CLI lane
  adds it; the site never waits for it.

## Proof

- `platform/test/ash_template_web/visit_log_test.exs`: property tests that throw
  random headers, events and browser reports at the writer and check that only
  fitting values reach a line.
- `platform/test/browser/visits.spec.ts` (browser walk): the walk's person opens
  Notes and saves a note; the server's lines for that visit, in production's
  shape, replay it in order (request, page, `note.create`, the press), with one
  person code and nothing they wrote.

## Sentinel's part

- Keep the event lines in their own events table, indexed by app, visit and
  time. Plain info lines are still dropped.
- Delete event rows older than 30 days on a schedule.
- A page that shows one visit's events in order, joined with that visit's
  warning and error lines. This is the replay.
- A read-only export of the last 24 hours for one app, which the daily review reads.
- Sentinel's code and releases belong to the Sentinel chief; each Sentinel
  release needs Sean's letter in that lane.

## The daily review

Once a day, on Sean's Mac, it reads the last 24 hours of events and warning
lines for Autolaunch and Keyfleet and runs Sean's prompt word for word:

"analyze my logs from this program in the past 24h thoroughly, identify broken
behaviors, user friction, inefficiencies, and propose improvements sorted by
estimated impact for the autolaunch and keyfleet codebases".

It writes one report a day to
`/Users/sean/Documents/regent/control/coordination/log-review/` and notifies
Sean. It only reads; it changes no code.

## Order of work

1. **Template** (built). Released with Sean's template letter.
2. **Sentinel.** Events table, 30-day deletion, visit page and export. Released
   with Sean's Sentinel letter.
3. **Autolaunch and Keyfleet** copy the template's version word for word, each
   with its own letter. The other three sites follow.
4. **Daily review.** Starts once Sentinel holds two days of Autolaunch and
   Keyfleet events, so the first report has real data.

## What it costs

- At the 1,000–2,000 person target, a busy visit writes about 50 lines, so a
  busy day is about 100,000 rows per site. That is small for Postgres with one
  index, and the lines already travel through Fly's log feed today.
- No new machines. The site writes nothing new to its own database.
