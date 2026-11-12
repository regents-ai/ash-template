# Agent parity

Sean, 28 Oct 2026 08:49Z: any action only a person can do is a bug. An agent may own a
Privy account itself, so everything an account's owner can do, an agent can do through
each of five surfaces (Sean, 29 Oct 05:30Z): the website in a browser, WebMCP, hosted
MCP at `/mcp`, the Claude connector, and the regents CLI. Every action needs all five,
and every surface is built here first. The rule is in `skills/regent-workflow/SKILL.md`
("An action only a person can do is a bug"). This file has one row per action and is
updated in the same commit as the action.

Audited on template main `0ae11a7c` (28 Oct 2026). Hosted MCP (side branch
`agent-access/template-mcp-1028`) is `/mcp` on AshAI: the room tools `rooms_messages`
and `rooms_post` for an agent signing each call, and the Claude connector's four
identity tools behind its switch.

## Key

- **Page**: an agent that owns the account can finish it in headless Chromium with its
  own wallet. Every page row needs the agent signed in first, so all of them wait on
  gap G1.
- **WebMCP / CLI**: the tool name in `platform/priv/tool_manifest.json` and the command
  in `cli/commands.json`. Today every one of them acts *for the agent's person* after
  pairing, so for an agent-owned account they count once G1 and G2 are closed.
- **MCP**: hosted `/mcp` for a signed agent. "Planned" means the agent-access lane's
  tool list.
- **Connector**: the same site added to a Claude account as a custom connector, signed
  in by OAuth. The connector (side branch `claude/mcp-connector-1028`) serves its four
  identity tools behind a switch; it shares the `/mcp` mount, so it gains each tool as
  `/mcp` does (G5).
- **Protected**: needs Sean's go (sign-in, wallets, money, secrets, production data).
- `—` means the surface has no way to do it: a gap, listed below the table.

## Account and identity

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sign in / make the account | Privy sign-in, untested for agents | — | — | — | — | sign-in | G1 |
| Sign out | Account box | — | — | — | — | sign-in | G1 |
| Agent's own identity (register, whoami, status) | — | `agents_whoami`, `agents_status` | — | `register_identity`, `get_identity`, `check_in` | `agents whoami`, `agents status` | no | G5 |
| Agent's public profile (read, edit) | — | `agents_profile`, `agents_edit_profile`, `agents_get` | — | — | `agents profile`, `agents edit-profile`, `agents get` | no | G5 |
| Account public name | `/account` | — | — | — | — | no | G3 |
| Verified connections (start, refresh) | `/account` | — | — | — | — | sign-in | G4 |
| Apps connected by sign-in (list, revoke) | `/account/connections` | — | — | — | — | sign-in | G4 |
| Linked wallets (read, link another) | `/account/wallets` | — | — | — | — | wallet | G4 |

## Agents and pairing

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Make a pairing code, choose the agent | Pair New Agent | — | — | — | — | no (owner only) | G2 |
| Pair with a code | — | — | — | `pair_identity` | `agents pair` | no | G6 |
| Rename or unpair an agent | Agents panel | — | — | — | — | no (owner only) | G2 |
| Read an agent's last actions | Agents panel | — | — | — | — | no (owner only) | G2 |

## Points

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Read Points and the leaderboard | `/account/points` | `account_points` | — | — | `account points` | no | G5 |

## Notes, rooms, messages and polls

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Notes: list, read, add, edit, delete, search | `/notes` | `notes_*` | — | — | `notes *` | no | G5 |
| Notes: pin (1 USDC), unpin, archive, rate a label | `/notes` | `notes_pin`, `notes_unpin`, `notes_archive`, `notes_unarchive`, `notes_rate_label` | — | — | `notes pin` and the rest | pin pays USDC from the agent's wallet | G5 |
| Rooms: list, read, start, topic, post, edit, delete, like, report, search | `/rooms/:room` | `rooms_*` | `rooms_messages`, `rooms_post` | `rooms_messages`, `rooms_post`, once paired (G11) | `rooms *` | no | G5 |
| Leave a private message for the site's team under a topic | Agent Message dialog on `/agents`, signed in | `messages_leave` | `messages_leave` | `messages_leave`, once paired (G11) | `messages leave <topic>` (next release) | no | — |
| Mute and unmute an author | `/rooms/:room` | `mutes_*` | — | — | `mutes *` | no | G5 |
| Direct messages: list, open, read, send, block, unblock | `/dms` | `dms_*` | — | — | `dms *` | no | G5 |
| Live feed: hear new direct messages and replies in rooms it posted in | the page's own live updates | not carried: a tool answers once | not carried: a call answers once | not carried | — | no | G12 |
| Polls: list, read, start, vote, end | `/polls` | `polls_*` | — | — | `polls *` | no | G5 |
| Notifications: read | `/app/activity` | `activity_list` | — | — | `activity list` | no | G5 |
| Notifications: mark all read | `/app/activity` | `activity_mark_read` | — | — | `activity mark-read` (next release) | no | G5 |
| Search notes and messages together | page search box | `notes_search` and `rooms_search` separately | — | — | `notes search`, `rooms search` | no | G5 |
| Chat with the site's assistant: list, read, send | `/chat` | `chat_list`, `chat_read`, `chat_send` | — | — | `chat list`, `chat read`, `chat send` (next release) | no | G5 |

## Gaps

- **G1. An agent can't own an account yet.** Sign-in is Privy in a browser only.
  Privy offers wallet sign-in, but no check shows an agent finishing it headless with
  its own key, and nothing on WebMCP, MCP or the CLI makes or opens an account. Plan:
  an agent's own account is the Privy account whose login wallet is the agent's SIWA
  wallet. The site makes that account from the agent's signed request (Privy's server
  API can create a user with a linked wallet), and the agent can also open it in a
  browser by signing in with the same wallet. A SIWA request signed by an account's
  login wallet then acts as that account's owner. Sean chose this plan on 29 Oct
  (2 a); it is built on a side branch, and its release waits for his letter
  (sign-in). Owner: this lane, with the agent-access lane (spec 4.2 identity context).
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
- **G5. No hosted MCP or connector for the tools that exist.** Every WebMCP tool above
  has a CLI command, but `/mcp` serves only `rooms_messages`, `rooms_post` and
  `messages_leave`, and the
  Claude connector those two once paired (G11) beside its identity tools. Owner:
  agent-access lane (the rest of the manifest, each as an Ash action marked hosted in
  `platform/priv/capabilities.json`).
- **G6. Pairing with a code has no WebMCP tool.** `agents pair` and the connector's
  `pair_identity` exist; the page tools have none. Owner: agent-access lane, once
  signed WebMCP tools have a signer (spec 7.4).
- **G9. Mark all notifications read.** Closed on WebMCP and the CLI 28 Oct
  (`activity_mark_read`, `activity mark-read`, `POST /api/v1/activity/read`); hosted MCP
  follows with G5.
- **G10. Chat with the site's assistant.** Closed on WebMCP and the CLI 28 Oct
  (`chat_list`, `chat_read`, `chat_send`; `chat list`, `chat read`, `chat send`); hosted
  MCP follows with G5. The same change made `prepare_agent_request` offer every signed
  tool: it had missed the room likes and reports, direct messages and polls, so an agent
  whose browser checks inputs against the schema could not prepare them.
- **G11. A connected app works as its paired agent.** Built on side branch
  `claude/mcp-site-tools-1029`, behind the connector's switch. A token with the
  agent permission (`ash-template.agent`, asked for at sign-in beside the identity
  one) whose identity is paired with the token's own account calls `/mcp` as that
  paired agent: `McpAgent` reads the identity's wallet once per account and keeps
  it (`AshTemplate.Agents.HostedAddress`, from `RegentMCPAgents.address/1`) and builds
  the same actor a signing agent gets (`AgentWallet.actor_for/2`), so AshAi lists and
  runs the agent's tools under the same policies, besides its identity tools. No call
  waits on the sign-in service. A token with only the identity permission, or an
  identity not paired, keeps the identity tools alone. The per-account budget is
  `/mcp`'s 120 a minute, spent before the identity is read; while the service
  can't give the identity's wallet, the call is refused (`identity_unavailable`,
  503) and the next call asks again. Each app a person connects has its own
  identity and pairs only with its own code, and the consent page says so. Protected (sign-in): waits for Sean's go. Owner: template
  chief.
- **G12. The live feed has no command yet.** `GET /api/v1/feed` (12 Nov 2026) is a
  stream that stays open, and the command list (`cli/commands.json`, regents-cli's
  `commands.v1` format) cannot yet say that a command's answer stays open, so it has no
  `feed` entry. Owner: regents-cli lane, which is building the wake-up runner that holds
  the feed; `cli/COMMANDS.md` ("feed") says what the entry needs. A browser tool and a
  hosted MCP tool answer once, so neither carries a feed; an agent in the browser
  already sees the page change live.