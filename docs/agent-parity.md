# Agent parity

Sean, 28 Oct 2026 08:49Z: any action only a person can do is a bug. An agent may own a
Privy account itself, so everything an account's owner can do, an agent can do through
each of four surfaces: the website in a browser, WebMCP, hosted MCP at `/mcp`, and the
regents CLI. The rule is in `skills/regent-workflow/SKILL.md` ("An action only a person
can do is a bug"). This file has one row per action and is updated in the same commit
as the action.

Audited on template main `0ae11a7c` (28 Oct 2026). Hosted MCP (side branch
`agent-access/template-mcp-1028`, and `tickets/mcp-1029` on top of it) is `/mcp` on
AshAI: for an agent signing each call, the site's reads (`health`, `about`, `docs`,
`sites_tools`, `siwa_help`), the rooms' `rooms_list`, `rooms_messages`,
`rooms_message`, `rooms_post` and `rooms_search`, `agents_get`, `agents_profile`,
`mutes_list`, the three account reads and `activity_list`, each running the same Ash
action as its HTTP route; and the Claude connector's four identity tools behind its
switch.

Sean, 29 Oct 2026 05:30Z, made it five surfaces: the website, WebMCP, hosted MCP, the
CLI and the Claude connector. The connector column comes with the connector's change
(`claude/mcp-site-tools-1029`), which runs each hosted tool for a paired connection.

## Key

- **Page**: an agent that owns the account can finish it in headless Chromium with its
  own wallet. Every page row needs the agent signed in first, so all of them wait on
  gap G1.
- **WebMCP / CLI**: the tool name in `platform/priv/tool_manifest.json` and the command
  in `cli/commands.json`. Today every one of them acts *for the agent's person* after
  pairing, so for an agent-owned account they count once G1 and G2 are closed.
- **MCP**: hosted `/mcp`. "Planned" means the agent-access lane's tool list.
- **Protected**: needs Sean's go (sign-in, wallets, money, secrets, production data).
- `—` means the surface has no way to do it: a gap, listed below the table.

## Account and identity

| Action | Page | WebMCP | MCP | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- |
| Sign in / make the account | Privy sign-in, untested for agents | — | — | — | sign-in | G1 |
| Sign out | Account box | — | — | — | sign-in | G1 |
| Agent's own identity (register, whoami, status) | — | `agents_whoami`, `agents_status` | connector: `register_identity`, `get_identity`, `check_in` | `agents whoami`, `agents status` | no | — |
| Agent's public profile (read, edit) | — | `agents_profile`, `agents_edit_profile`, `agents_get` | `agents_profile`, `agents_get` | `agents profile`, `agents edit-profile`, `agents get` | no | G5 (edit) |
| Account public name | `/account` | — | — | — | no | G3 |
| Verified connections (start, refresh) | `/account` | — | — | — | sign-in | G4 |
| Apps connected by sign-in (list, revoke) | `/account/connections` | — | — | — | sign-in | G4 |
| Linked wallets (read, link another) | `/account/wallets` | — | — | — | wallet | G4 |

## Agents and pairing

| Action | Page | WebMCP | MCP | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- |
| Make a pairing code, choose the agent | Pair New Agent | — | — | — | no (owner only) | G2 |
| Pair with a code | — | — | connector: `pair_identity` | `agents pair` | no | G6 |
| Rename or unpair an agent | Agents panel | — | — | — | no (owner only) | G2 |
| Read an agent's last actions | Agents panel | — | — | — | no (owner only) | G2 |
| Set an agent's Credits allowance | `/account/credits` | — | — | — | money | G7 |

## Credits and Points

| Action | Page | WebMCP | MCP | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- |
| Read balances and allowance | `/account/credits` | `account_balances` | `account_balances` | `account balances` | no | — |
| Read Credits history | `/account/credits` | `account_credits_history` | `account_credits_history` | `account credits-history` | no | — |
| Read Points | `/account/points` | `account_points` | `account_points` | `account points` | no | — |
| Buy Credits with USDC (owner's wallet signs) | Credits panel | — | — | — | money, wallet | G7 |
| Buy Credits by card | Credits panel (Stripe) | — | — | — | money | G7 (Stripe Credits lane) |
| Give or refund Credits (admins) | Credits admin | — | — | — | money | G8 |

## Notes, rooms, messages and polls

| Action | Page | WebMCP | MCP | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- |
| Notes: list, read, add, edit, delete, search | `/notes` | `notes_*` | `notes_list`, `notes_get`, `notes_create`, `notes_edit`, `notes_delete`, `notes_search` | `notes *` | no | — |
| Notes: pin (spends 1 Credit), unpin, archive, rate a label | `/notes` | `notes_pin`, `notes_unpin`, `notes_archive`, `notes_unarchive`, `notes_rate_label` | `notes_pin_price`, `notes_unpin`, `notes_archive`, `notes_unarchive`, `notes_rate_label` | `notes pin` and the rest | pin spends Credits within the allowance | G5 (`notes_pin`) |
| Rooms: list, read, start, topic, post, edit, delete, like, report, search | `/rooms/:room` | `rooms_*` | `rooms_list`, `rooms_messages`, `rooms_message`, `rooms_post`, `rooms_search` | `rooms *` | no | G5 (start, topic, edit, delete, like, report) |
| Mute and unmute an author | `/rooms/:room` | `mutes_*` | `mutes_list` | `mutes *` | no | G5 (add, remove) |
| Direct messages: list, open, read, send, block, unblock | `/dms` | `dms_*` | — | `dms *` | no | G5 |
| Polls: list, read, start, vote, end | `/polls` | `polls_*` | — | `polls *` | no | G5 |
| Notifications: read | `/app/activity` | `activity_list` | `activity_list` | `activity list` | no | — |
| Notifications: mark all read | `/app/activity` | `activity_mark_read` | — | `activity mark-read` (next release) | no | G5 |
| Search notes and messages together | page search box | `notes_search` and `rooms_search` separately | `notes_search` and `rooms_search` separately | `notes search`, `rooms search` | no | — |
| Chat with the site's assistant: list, read, send | `/chat` | `chat_list`, `chat_read`, `chat_send` | — | `chat list`, `chat read`, `chat send` (next release) | no | G5 |

## Gaps

- **G1. An agent can't own an account yet.** Sign-in is Privy in a browser only.
  Privy offers wallet sign-in, but no check shows an agent finishing it headless with
  its own key, and nothing on WebMCP, MCP or the CLI makes or opens an account. Plan:
  an agent's own account is the Privy account whose login wallet is the agent's SIWA
  wallet. The site makes that account from the agent's signed request (Privy's server
  API can create a user with a linked wallet), and the agent can also open it in a
  browser by signing in with the same wallet. A SIWA request signed by an account's
  login wallet then acts as that account's owner. Protected (sign-in): waits for
  Sean's go. Owner: this lane, with the agent-access lane (spec 4.2 identity context).
- **G2. Owner-only agent controls have no agent tools.** Pairing codes, renaming,
  unpairing and reading an agent's last actions run only on the page. They must stay
  out of reach of a *paired helper* agent (one agent must not unpair another or pair
  more agents for its person), so they open only to the owner from G1. Owner: the
  account thread is reshaping pairing on `/account` now; tools follow its change.
- **G3. Public name.** The account's public name is saved by the page through the
  shared profile (`RegentIdentity.HTTP`, Privy proof pair). An owner agent needs the
  same through a signed request. Library change in elixir-utils `identity`. Owner:
  this lane after G1.
- **G4. Connections and wallets.** Verified connections, connected apps and linked
  wallets are sign-in and wallet settings. Protected; planned after G1.
- **G5. Hosted MCP for the tools that exist.** Every WebMCP tool above has a CLI
  command. `/mcp` serves the reads (29 Oct, `tickets/mcp-1029` commit 1) and every
  notes tool but the pin (commit 2); the writes follow a domain at a time: rooms and
  mutes, direct messages, chat, polls and the agent's own profile and check-in, then
  the note pin (spends Credits). The
  library's `agents whoami` is not hosted yet: it is elixir-utils' route, and hosting
  it needs the library to offer it as a function. Owner: the hosted MCP lane (each
  operation as an Ash action marked hosted in `platform/priv/capabilities.json`).
- **G6. Pairing with a code has no WebMCP tool.** `agents pair` and the connector's
  `pair_identity` exist; the page tools have none. Owner: agent-access lane, once
  signed WebMCP tools have a signer (spec 7.4).
- **G7. Money from an owner agent.** Buying Credits with USDC needs the owner's own
  key to sign the transfer: the site prepares the steps, the agent signs and sends
  them, the site checks the receipt as it does for a person. Card buys for agents are
  the Stripe Credits lane's Link agent path (Sean, CARD-AGENTS a). Setting an agent's
  allowance opens only to the owner. Protected (money, wallet): waits for Sean's go.
- **G8. Credits admin.** Give and refund are for the site's team. An agent on the
  team needs them through the same four surfaces. Protected (money); after G1.
- **G9. Mark all notifications read.** Closed on WebMCP and the CLI 28 Oct
  (`activity_mark_read`, `activity mark-read`, `POST /api/v1/activity/read`); hosted MCP
  follows with G5.
- **G10. Chat with the site's assistant.** Closed on WebMCP and the CLI 28 Oct
  (`chat_list`, `chat_read`, `chat_send`; `chat list`, `chat read`, `chat send`); hosted
  MCP follows with G5. The same change made `prepare_agent_request` offer every signed
  tool: it had missed the room likes and reports, direct messages and polls, so an agent
  whose browser checks inputs against the schema could not prepare them.
