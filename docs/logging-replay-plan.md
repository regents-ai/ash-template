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
| `surface` | `page`, `webmcp`, `cli`, `agent_http`, `mcp` or `job`. An `/api` call that names no tool or command but carries a visit, in the cookie or the header, is the page's own script, so it is `page`. A call to the hosted MCP server at `/mcp` is `mcp` |
| `actor` | `person:`, `agent:` or `anonymous`, then the first 8 bytes of an HMAC of the account or agent id, keyed from the site's secret. The same person always gets the same code; the code can't be turned back into the id |
| `event` | `name`, `where`, `outcome` and `ms` (below); a `tool.call` also has `client` |

An event's `where` and `outcome` must fit a short pattern of plain characters, or
they are written as `other`. Nothing a person typed can reach a line.

| Event | Written when | `where` | `outcome` |
| --- | --- | --- | --- |
| `request` | A page request finishes | The route, such as `/rooms/:room` | `ok` or `status_404` |
| `tool.call` | An `/api` or `/mcp` request finishes, told by its whole path even inside a plug the router forwards to (`RegentAgents.HTTP` under `/api/agents/v1`, AshAi's MCP router) | The tool name from `x-regent-client`, else the route | `ok`, the error's code, or `status_N`; `client` is `webmcp`, `regents-cli/<version>`, another program's `<name>/<version>`, `other` or `none` |
| `page` | A connected page opens or changes address | The route | none |
| `press` | A page or component event finishes | `View:event` | `ok`, `failed`, or for wallet steps `sent`, `signed` or the failure reason |
| `action` | An Ash create, update, destroy or generic action finishes during a request, press or job | `resource.action` | none |
| `job` | An Oban job finishes | The worker | Oban's state |
| `outgoing` | A call to another service finishes during a request, press or job | `METHOD host` | The status |
| `page.error` | The browser reports an uncaught error | The route | `error` or `unhandledrejection` |
| `tool.unsent` | A browser tool's call never got an answer | The tool | `unreachable` or `outcome_unknown` |
| `press.unsent` | A wallet step's answer never reached the server | The step | `lost` |
| `arrival` | The first page of a visit has connected (a crawler that runs no script writes none) | The route | Where the visit came from: `chatgpt`, `perplexity`, `claude`, `gemini`, `copilot`, `google`, `bing`, `duckduckgo`, `x`, `linkedin`, `github`, `hackernews`, `reddit` (from `utm_source`, else the referring site), `site`, `other_site` or `direct`. The referring address is never written |
| `step` | A step of the shared journey, from the product-event vocabulary below | One of `steps/0` | The agent's harness for the two pairing steps; `person` or `agent` for a value step; else none |

Where people stop is read from these alone: per visit, its `arrival`, then how far
it got along `sign_in_opened`, `signed_in`, `pairing_code_shown`, `agent_paired`,
then its first value step. A returning person is an `actor` seen on an earlier day.

A press line is written when the press finishes, so the actions it caused come
just before it. Phoenix's own request lines are off in production: they repeat
each raw path and its parameters.

"What the person saw" is the outcome. Each outcome code picks the words shown,
so the code is enough to know the message without logging its text.

## Product events

The `step` names are the product-event vocabulary
(`AshTemplateWeb.VisitLog.steps/0`): one fixed list, the same on every site, whose
names never change. A site writes only the names it has; its value action is the
one value name that is its own. Each is a `step` line with the visit, actor and
surface of the request or page it happened in, so it needs no field, table or
cookie of its own.

| Name | Written when | Written by | `actor` | `outcome` |
| --- | --- | --- | --- | --- |
| `sign_in_opened` | A Sign in button was pressed: the one step only the browser sees | `POST /visit-log` | The browser's | none |
| `signed_in` | The sign-in exchange (`POST /auth/privy/session`) bound this browser to an account: a 2xx answer saying `x-ash-session-changed: true`; a refresh of the account it already has is not one | `VisitLog.Events`, as the answer is sent | The browser's from before the exchange, usually `anonymous` (see "First touch") | none |
| `pairing_code_shown` | The pairing box issued a pairing code | `AshTemplateWeb.PairingBox` | The person | The harness |
| `agent_paired` | An agent paired with one of the codes the person's pairing box shows | same | The person | The harness |
| `note_created` | The template's value action: a note was created | `AshTemplate.Journey.Value`, on `AshTemplate.Notes.Signals` `:note_created` | The note's account, as `person:`, whoever acted | `person`, or `agent` for the account's agent |
| `contribution_made` | Keyfleet's value action: a contribution was accepted | Keyfleet's own `Journey.Value` | same | same |
| `fix_succeeded` | Patchbay's value action: a fix succeeded | Patchbay's | same | same |
| `eval_completed` | Techtree's value action: an eval completed | Techtree's | same | same |
| `launch_confirmed` | Autolaunch's value action: a launch was confirmed | Autolaunch's | same | same |

A value step comes from the signal the site's own domain emits for its value
action, heard by an Ash signal listener (`AshTemplate.Journey.Value`), and never from
the Ash telemetry the `action` lines use: an action's `:stop` event comes whether
it succeeded or failed, while the signal is emitted only once the action's checks
and its write have passed. The listener runs in the action's own process and
transaction, so the line carries that request's or page's visit and surface (a
note an agent writes through `/mcp` says `mcp`), and it answers `:ok` whatever
happens, so a line never fails the action. One case remains: when a
later listener of the same signal fails and rolls the action back, the line has
already been written.

A value step names the account the value belongs to, so a person whose agent does
the work still activates. A browser that sends Global Privacy Control writes no
step at all, value steps included, exactly as before.

Each site copies `Journey.Value` with its own signal: Keyfleet `contribution_made`,
Patchbay `fix_succeeded`, Techtree `eval_completed`, Autolaunch `launch_confirmed`.
A site whose value action emits no signal yet adds one (`emit` in the action, a
`Signals` module in its domain; `skills/ash-signals`).

## First touch

A visit's `arrival` line says where it came from; its `signed_in` line says the
same visit signed in. The visit id joins them, with no cookie beyond `_visit` and
nothing stored:

- The `signed_in` line is written as the exchange's answer is sent, before that
  request has read the account, and reading it there would mean a database read
  inside the sign-in answer. So the line carries the browser's actor from before
  (`anonymous`), and the account is the first `person:` actor on a later line of
  the same visit. Once the exchange binds, the page reloads signed in, and that
  request and its page each name the account; a sign-in whose page closes first
  names none, and the report counts it apart.
- The source an account is counted under is the `arrival` of the visit in which it
  first signed in. When a person first came on one visit and signs in on a later
  one (the `_visit` cookie ends when the browser closes), the sign-in visit's own
  source counts, often `direct`; their first visit's source is not carried over.
- A visit with no `arrival` line (its first page never connected) has the source
  `unknown`. A Global Privacy Control browser has no visit and writes no `arrival`
  or `signed_in`, so it never reaches a cohort.

## Cohort report

`mix visit_log.cohorts PATH` (or lines on standard input) reads exported visit
lines and prints a plain text table (`AshTemplateWeb.VisitLog.Cohorts`). It reads
Sentinel's export or Fly's JSON log lines, one JSON object a line, and never the
database; it stores nothing. Its window is only what the export holds, 30 days at
most from Sentinel, and it says so at the top of every report.

| Column | Meaning |
| --- | --- |
| Week | The Monday (UTC) of the week each account first signed in, within the export |
| Source | That sign-in visit's `arrival` ("First touch"); a week with several sources ends with an `all` row |
| Accounts | Accounts whose first sign-in in the export fell in that week |
| Activated | Those with at least one value step at or after that first sign-in |
| D1 | Returned/covered: any line from the account 24 to 48 hours after its first sign-in, out of the accounts whose 48 hours the export runs past |
| D7 | The same, 7 to 8 days after |
| Median value | The median number of value steps of an activated account |

An account that signed in before the export began, and signs in again inside it,
counts in the week of that later sign-in. Times are kept to the minute. The report
also counts the sign-ins no later line of their visit names, and leaves them out.

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
