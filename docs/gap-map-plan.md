# Closing the gap map

Sean, 20 Oct 2026 00:01Z: fix and improve everything in the ash-template gap map
(`control/coordination/evidence/ash-template-gap-map.md`, from the regents-cli review at
ee4525c). The rule behind it: ash-template is the golden blueprint, so every function a
site has is either shown here as a general example, or the site changes to match.

The template lead made every naming and design call below (Sean: never ask him to pick
names). Each site copies these rules; regents-cli follows.

## Rules every site follows

1. **Command names.** A command is a noun, then a verb: `notes list`, `rooms post`,
   `account balances`. The noun is plural when it names a collection (`notes`, `rooms`,
   `agents`, `sites`), `account` for the person's own account, and a single word for a
   read of the whole site (`health`, `about`, `docs`).
2. **Tool names follow command names.** A browser tool is its command with spaces and
   hyphens turned into underscores: `notes edit` is `notes_edit`, `notes rate-label` is
   `notes_rate_label`. No site prefix: the browser already knows which site it is on.
   The template refuses to compile when a tool and its command disagree.
3. **One address scheme.** Everything a site offers is under `/api/v1/`. The one shared
   exception is `/api/agents/v1/` (`whoami`, `me`, `pair`): the agent sign-in that
   siwa-server's client and every site already use. It moves only if siwa-server moves
   it. `/healthz` stays as Fly's health check. Nothing lives under `/tools/`.
4. **Every command answers a JSON object**, so regents-cli has one way to read an
   answer. A page also offered as Markdown (About, Docs) answers
   `{"title", "markdown"}` at its `/api/v1/` address.
5. **One API per thing.** Notes have one API at `/api/v1/notes`, for the person or for
   their paired agent; the agent-only extras (search, pins, label ratings) sit beside it.
6. **A signed read with input is a POST.** A signed request takes no query string, so a
   paired read that pages or filters sends `{}` or its input as a JSON body
   (`account credits-history`, `activity list`, `notes search`); a page continues with
   `after`, the previous answer's `pagination.next_cursor`.

## Calls where the map said "needs a decision"

- **`agents pair` has no browser tool, on every site.** Pairing runs where the agent
  keeps its key (`regents auth`, `siwa_agent.py pair`), once. A pairing door in the page
  would be new sign-in work for no new ability. regents-cli lists it as the one
  command-line-only exception.
- **Saved drafts (Autolaunch).** A note is a saved draft; no separate drafts example.
- **Site-specific reads** (regents.sh claims and staking position, Patchbay bench and
  offers, Keyfleet code password, pushes and shards). Each is a public read by id, a
  paired read or a filtered list, which the template shows; nothing extra.

## Stage 1: contract cleanup and the missing doors (no database change)

| Command | Tool | Address | What changed |
| --- | --- | --- | --- |
| `health` | `health` | `GET /api/v1/health` | tool added |
| `about` | `about` | `GET /api/v1/about` | command added; JSON answer |
| `docs` | `docs` | `GET /api/v1/docs` | command added; JSON answer |
| `sites tools <site>` | `sites_tools` | `GET /api/v1/sites/{site}/tools` | replaces the five `show_*_webmcp_tools` |
| `siwa help` | `siwa_help` | `GET /api/v1/siwa/help` | replaces `show_siwa_connection_help` |
| `rooms messages <room> --author-kind` | `rooms_messages` | `GET /api/v1/rooms/{room}/messages` | was `room_read`; `--author-kind person\|agent` (enum), the field's own name and values |
| `rooms message <room> <id>` | `rooms_message` | `GET /api/v1/rooms/{room}/messages/{id}` | new public read by id |
| `rooms post/edit/delete` | `rooms_post/edit/delete` | unchanged | were `room_*` |
| `rooms search` | `rooms_search` | `POST /api/v1/rooms/search` | was under `/tools` |
| `agents whoami/status` | `agents_whoami/status` | unchanged (`/api/agents/v1`) | were `agent_*` |
| `notes list/get/create/delete` | same | `/api/v1/notes` | the `/tools/notes` copies are gone; delete answers `{deleted, id}` |
| `notes edit` | `notes_edit` | `PATCH /api/v1/notes/{id}` | was `notes_update`; title or body required (required_one_of) |
| `notes search` | `notes_search` | `POST /api/v1/notes/search` | was under `/tools` |
| `notes pin-price <id>` | `notes_pin_price` | `GET /api/v1/notes/{id}/pin-price` | new; effect quote |
| `notes pin/unpin <id>` | same | `POST /api/v1/notes/{id}/pin`, `…/unpin` | were under `/tools` |
| `notes rate-label <id>` | `notes_rate_label` | `POST /api/v1/note-labels/{id}/report` | was `notes_report_label`; `--report fits\|does_not_fit` (enum) |
| `account balances/points` | same | `GET /api/v1/account/…` | were under `/tools` |
| `account credits-history` | same | `POST /api/v1/account/credits/history` | was under `/tools` |
| `activity list` | `activity_list` | `GET /api/v1/activity` | was under `/tools` |

Commands also gain `next_steps` where the next move is plain (after `notes create`, read
it; after `rooms post`, read the room).

Moving the pin door touches Credits spending, so this stage's release waits for Sean's
letter naming it.

## Stage 2, first part: no new table (on main 20 Oct 2026)

| Command | Tool | Address | What changed |
| --- | --- | --- | --- |
| `mutes list` | `mutes_list` | `GET /api/v1/mutes` | new; the person's mutes, for their agent |
| `mutes add <message>` | `mutes_add` | `POST /api/v1/mutes` | new; mutes a message's author, as the room page does |
| `mutes remove <id>` | `mutes_remove` | `DELETE /api/v1/mutes/{id}` | new |
| `activity list --after` | `activity_list` | `POST /api/v1/activity` | pages of 50 with a cursor; POST since a signed request takes no query string |

## Stage 2: general examples that need new tables

Each needs a migration, so each release waits for Sean's letter. Wallet transactions
and paid steps are protected as well.

- Agent profiles: done 21 Oct as `agents get <id>` (public, never the wallet), `agents profile`
  and `agents edit-profile` (name and status line).
- Rooms people make: done 21 Oct as `rooms create` and `rooms topic <room>` (open rooms, 3 a
  day for each person). Members-only rooms are dropped (Sean, 21 Oct, decision 13 c): every
  room is open to everyone who can read the site.
- Direct messages: done 21 Oct as `dms list`, `dms blocked`, `dms open <message>`, `dms read`,
  `dms send`, `dms block` and `dms unblock` (opened from a room message the other person wrote;
  300 a person an hour; a block moves only the blocker's list).
- Polls: done 21 Oct as `polls list`, `polls show`, `polls start`, `polls vote` and `polls end`
  (2 to 10 choices, open 1 to 60 minutes, 3 a person a day; one vote a person, never changed;
  counts hidden until it closes or its starter ends it).
- Likes: done 21 Oct on room messages, not notes (Sean, decision 12 a), as `rooms like` and
  `rooms unlike` (one like a person a message; everyone sees the count, not who liked).
- Reports: `reports send` (a general "report this").
- Follows and a change feed: `follows add`, `follows remove`, `follows list`,
  `changes read` with a cursor.
- Archive for notes: done 21 Oct as `notes archive <id>` and `notes unarchive <id>` (free; an
  archived note goes after the others and keeps its pin).
- Account summary and budget: `account show`, `account budget`.
- Jobs: `jobs start`, `jobs result`.
- Paid flow in steps (effect prepare): `payments prepare`, `payments get`.
- A wallet transaction for the agent's own wallet to send: `wallet prepare`.

## What other sites and regents-cli change

Sent as notes through `control/coordination`, never as edits in their checkouts:

- Every site: the rules above (names, `/api/v1/`, JSON answers), and the missing
  `about`, `docs`, `health`, `sites tools`, `siwa help` where the map lists them.
- regents-cli: remove the `"*"` entries in `scripts/webmcp_parity.py` except `agents
  pair`, re-pin ash-template, and make a template gap fail `make check`.
