# Feature map

What a person or an agent can do on this site, and the automated check that proves
it. A row without a check is a gap, listed as one. Grow this file as features are
touched: a change to a feature adds or updates its row in the same commit. Sites
copy this file's shape.

`make check` runs every check below. The browser walk (`make check-browser`) runs
headless Chromium as a desktop 1280 wide and as a touch phone 390 wide (Playwright's
Pixel 7 at that width), and opens every page again on a touch phone 320 wide; WebKit is
not run on the Mac. The walk never
leaves the machine. In the browser, Privy is answered by a stand-in that holds no
sign-in, and any other outside request fails the check that made it
(`platform/test/browser/support/test.ts`). The walk's server reads its chains and
sign-in service from a closed port on the machine, starts with every outside
service's setting cleared, and refuses any other outside request, which fails the
walk (`platform/test/browser/support/server/walk_offline.ex`,
`platform/test/browser/support/teardown.ts`). Each walk runs its server on a port
nothing else on the machine is using, on a database made for that run and named after
the port, which it drops when it ends, whatever happens, even when its server never
starts (`platform/test/browser/walk.sh`, `platform/test/browser/support/drop.exs`), so
two walks at once never reach each other's server or data. It builds the pages' scripts and styles before its server
starts, and the server sends no reloads, so no page reloads under a check. Its server
runs without the code reloader, as a release does, built into its own folder
(`platform/_build/walk`), so a busy machine slows its pages less. Before
the first check it opens one signed-in page once, so no check meets a cold server
(`platform/test/browser/support/warm_up.ts`).

## Every page and document

| What | Check |
| --- | --- |
| Every page opens, shows what proves its purpose, raises no error, makes no failing request to the site, fits the screen (320 wide too), shows every ENS name, full address and short address with its copy icon, and lets a keyboard reach every box that scrolls (a wide code block or table takes focus), signed out and signed in | `platform/test/browser/pages.spec.ts` over `platform/test/browser/pages.json` |
| Every machine-readable document answers with its type | same, `documents` |
| No page or document the site serves is left out of the walk, and the walk names none the site has dropped | `platform/test/ash_template_web/feature_map_test.exs` |
| Every agent in the pairing box has a guide page and a skill the walk opens | same |
| The site started with its sign-in settings | `pages.spec.ts`, first test |
| A page asked for JSON gets a refusal, a browser gets the page | `platform/test/ash_template_web/content_negotiation_test.exs` |
| An address with a slash at the end, other than the homepage, is not found: the not-found page for a page, the API's not-found answer for an API address | `platform/test/ash_template_web/trailing_slash_test.exs` |
| Closing the site leaves the agent pages open | `platform/test/ash_template/site/launch_gate_test.exs` |
| A missing required value gets the site's own error, not a database failure, on a database built from every migration, the libraries' included | `platform/test/ash_template/required_value_test.exs` |
| Every answer, a page, a file, a redirect, the MCP server's and every refusal as a page or JSON, tells the browser to read it only as the type it names | `platform/test/ash_template_web/no_sniffing_test.exs` |
| Each address that takes a body reads it up to its limit and refuses one byte more with 413: 64 KB for what an agent signs (the API, `/mcp`, Stripe's notices), 256 KB for the rest (a connected app's registration and token, sign-in, visit reports) | `platform/test/ash_template_web/body_limit_test.exs` |

## People

| What | Check |
| --- | --- |
| Sign in, and sign in again with a wallet added; sign in with email and keep one account | `platform/test/ash_template/accounts/verified_session_test.exs` |
| Sign in, refresh, sign in as someone else and sign out each run in a transaction Ash started, so none leaves an unsent notification; a lineage whose count ran out is refused and stays signed out | `platform/test/ash_template/accounts/session_authority_test.exs` (the test settings raise on a missed notification) |
| On a network that refuses websockets, Sign in still starts the sign-in bridge, and a signed-in page shows the account with Sign out in its menu. With no live connection, from the start or after it drops, the pairing box and a room's Send box say "Not connected. Trying again…" and their buttons and Enter are disabled; once it is back they return and Send works | `platform/test/browser/blocked_websocket.spec.ts` |
| Disconnect stays disconnected; a real return from the wallet signs in | `platform/assets/test/privy_bridge.test.ts` |
| Sign out lets go of every wallet Privy holds before Privy signs out, even one that refuses; signed in, a wallet app left from before, or a wallet picked in Privy's connect window that the account doesn't link, is never the account's wallet, and a pick made before the account's wallets have loaded is neither used nor forgotten | `platform/assets/test/privy_bridge.test.ts` (the sign-out order and the two rules, `accountActiveWallet` and `accountWalletSelection`); the effect that applies them on the page is not walked, since the walk's wallet app sets the active wallet itself |
| After a refused sign-in the page reloads once: a page that has begun to leave never asks the server for a session behind the page replacing it | `platform/assets/test/session_leaving.test.ts` |
| A wallet send goes out when the wallet answers its account in other letter case, and nothing is sent when it answers for another account | `platform/assets/test/send_step.test.ts` |
| Each account shows the name its person saved with this site's sign-in, never a name saved under another sign-in, in the order asked | `platform/test/ash_template/accounts/display_name_test.exs` (property test) |
| A name saved on the Account page with the person's own sign-in shows there, in the form and as the account's name; a forged sign-in changes nothing | `platform/test/ash_template_web/public_name_test.exs` |
| Save makes the person's profile on their first save and saves only to the profile it read; a switch of account part way through the page's own save path saves nothing, and neither does a save pressed before a switch and still waiting its turn; two quick saves keep the name pressed last; a failed save never leaves the form busy | `platform/assets/test/public_name.test.ts` |
| Save on the Account page without the browser's sign-in finishes, says why, sends no change and moves nothing, at both widths | `platform/test/browser/public_name.spec.ts` |
| A name with a hidden character (a control, a line or paragraph separator, or a format character such as a text-direction mark or zero-width space) is refused, and the person is told to remove the hidden characters; a joiner between two visible characters and a complete flag still save; taking out any one rule fails a check | elixir-utils `ash_components/identity/test/http_test.exs` and `profile_test.exs` (property tests); the words in `platform/assets/test/public_name.test.ts` |
| The longest name the site takes, with no spaces, fits every signed-in page at both widths | `pages.spec.ts`; the walk's person has an 80-letter name (`platform/test/browser/support/sign_in.exs`) |
| Pair New Agent moves to the Agents page's pairing box, from the Agents list on every press, from the account menu and from an agent guide's link | `platform/test/browser/pairing.spec.ts` |
| Choosing an agent gives a message with a code; coming back to an agent shows its same code, and Make a new code replaces it | same |
| With codes out for two agents, an agent that pairs shows under the code it used and the other keeps its code | elixir-utils `ash_components/agents/test/regent_agents/pairing_test.exs` (each used code names its agent); gap: the box itself is not walked, because the walk's one person has agents other checks count |
| Every agent's message but ChatGPT's tells it to keep its own key in a folder named after its runtime, so agents sharing one computer pair as separate agents | elixir-utils `ash_components/agents/test/regent_agents/pairing_message_test.exs` |
| Every agent kind the library knows, Claude included, draws its picture in the agents list and the account menu, so an agent paired on another site never breaks a person's list here | `platform/test/ash_template_web/agent_pictures_test.exs` |
| A page with one panel gives it the whole width | `platform/test/browser/layout.spec.ts` |
| The account menu hangs under its button inside the screen at desktop and phone width (320 too), closes on Escape, and on a phone covers the bottom bar; Manage Account and Pair New Agent in it lead to the Account and Agents pages and close it; Sign out closes it, so a note that sign out couldn't finish shows under the account button with nothing over it | `platform/test/browser/account_menu.spec.ts` |
| Narrower than 22.5rem (a 320px phone) the Credits balance leaves the header for a row in the account menu, in the header's words, and the row opens Buy Credits and closes the menu; wider, the balance stays in the header and the row is hidden; the sample account's 10.00 Credits header fits a 320px screen | `platform/test/browser/account_menu.spec.ts` |
| The Credits panel's Where to spend opens a window naming each Regents Product, what Credits buy there and its link; it sits on the screen, and Close or Escape closes it, at both widths; the panel's Paying from wallet shows its copy icon | `platform/test/browser/credits.spec.ts` |
| An address, ENS name or short address opens its full address on a click, tap or Enter and copies it from its icon; its arrow opens Basescan, Etherscan or Blockscout for Robinhood, and on a test network with no explorer (`chain="test"`), or for a long ID such as a pool ID, it copies with no arrow; any other chain raises (the components page shows Base, Ethereum, Robinhood, a test network and a pool ID) | design-system `regent_ui/test/regent/primitives_test.exs`; `/showcase` in `platform/test/browser/pages.json` |
| Each agent on the Agents page names its own wallet beside its name: the short form opens the full address on a press, its icon copies it, and the row fits on one line, at both widths; the contact line says "Last check-in" | `platform/test/browser/agents.spec.ts`, on the agents `platform/test/browser/support/sign_in.exs` pairs; design-system `regent_ui/test/regent/account_test.exs` (a row without a wallet says "Address unavailable") |
| An agent's window opens from the Agents page; its address opens the full address on a tap or click, Escape closes it and gives the press back to the address, its icon copies the full address, and on the phone both targets are at least 44 px tall once the window has risen into place | `platform/test/browser/agents.spec.ts`, on the agent `platform/test/browser/support/sign_in.exs` pairs |
| A wallet the account doesn't link is ignored, and a wallet note names each wallet with its copy icon: with an unlinked wallet open in the on-chain lab, nothing asks the person to switch, and a press sends nothing and names the account's wallets, each opening and copying its full address; the words run straight on from each address, and nothing on the page shows an address without its icon | `platform/test/browser/addresses.spec.ts` |
| An agent's window renames the agent: a name with a hidden character is refused beside the field and the agent keeps its name; a name with an emoji joined by a zero-width joiner saves and shows in the window and the list, at both widths; the field and Save are at least 44 px tall on the phone once the window has risen into place | `platform/test/browser/agents.spec.ts`, on the agents `platform/test/browser/support/sign_in.exs` pairs |
| Only the person renames their agent; a blank name, one over 80 characters or one with a hidden character is refused | elixir-utils `ash_components/agents/test/pairing_test.exs` |
| A moving picture whose graphics card never starts shows the still picture and stops listening to the page | `platform/assets/test/canvas_island.test.ts` |
| Buying Credits credits the account with the site listening | `platform/test/ash_template/credits/credited_test.exs` |
| Live figures: a bad reading never replaces a good one, a failed first read shows, pages hear only their own figure | `platform/test/ash_template/site/shared_reading_test.exs` |
| Chain figures read on a slow clock: a landed on-chain step or the read-again icon reads the chain again at once, asks close together cost one read, and another chain's ask changes nothing; the figures page says when Base was last read, at both widths | `platform/test/ash_template/site/chain_refresh_test.exs`, `platform/test/browser/figures.spec.ts` |
| Sentinel's chain numbers: a chain reader's pass sets its lag in blocks and counts the pass; a site's query of its own unconfirmed sends sets each flow's oldest age, 0 when none waits, and a query that fails is logged and skipped; the template names no such query, so it never publishes that age | `platform/test/ash_template_web/chain_numbers_test.exs` |
| Agent harbour: the list under the harbour names all six agents; each name opens its agent's card, named for the agent, with its Key and four actions at most; the card closes with its Close button and with Escape; each island's page marks its own island, and pressing another island's name opens that page; an island that does not exist is not found; on the phone every name and the Close button are at least 44 px square; light and dark | `platform/test/browser/harbour.spec.ts` |
| Every window opens in the design library's frame, with its cut corners, and sits whole on the screen: search, Buy Credits, the agent tools list, a code cube face's card and an agent's card in the harbour; light and dark, at both widths | `platform/test/browser/windows.spec.ts` |
| A code cube face's card copies what it lists as Markdown: a site's card its tools, siwa-server's card each step's command and the guide | `platform/test/browser/code_card.spec.ts` |
| The homepage reads as regents.sh's: the hero stands top right and stays in view while Mission, Products, Staking and How it works scroll past; with less motion it scrolls with the page; a phone reads the hero first; its Markdown copy reads in the page's order | `platform/test/browser/homepage.spec.ts`, `platform/test/ash_template_web/home_live_test.exs` |
| Agent harbour: the list keeps its height with every agent at one island, the page below it does not move, and the inn's page shifts by less than 0.1 over 30 seconds at 1280 while agents sail | same |
| Agent harbour: without WebGPU the still picture for the theme fills the harbour, light and dark | same |
| Agent harbour: pressing a ship on the sea opens its agent's card, and pressing an island opens its page, with a click at 1280 and a tap at 390, light and dark | `platform/test/browser/harbour_sea.spec.ts` |
| Agent harbour: each move sends one agent to another island, lists it first on its card and keeps four actions at most; an agent's address opens its card and an unknown agent opens none | `platform/test/ash_template_web/harbour_live_test.exs` |
| Message on someone's room message opens the conversation with them, and a message sent there shows at once as the person's own and empties the box, at both widths | `platform/test/browser/dms.spec.ts` |
| A person starts a poll, votes once and sees their vote, with no counts while it is open; ending it shows each choice's votes, at both widths | `platform/test/browser/polls.spec.ts` |
| Like in a room message's menu shows a pressed heart with a count of 1 under it and turns the menu item into Remove like; pressing the heart takes the like back and the heart goes, at both widths | `platform/test/browser/likes.spec.ts` |
| Report in someone's room message menu opens the four reasons in its place; choosing one closes both and thanks the reader, and the reader's own message offers no Report, at both widths | `platform/test/browser/reports.spec.ts` |
| In a busy room an open message menu keeps its message in place while new messages arrive once the room is full and while messages below grow, two in quick succession too, and while one grows as the reader scrolls (checked with the room behaving as Safari's does); opening another message's menu leaves the room where it is, also when the press closes the first menu before its click lands, and Like pressed there lands; a choice after a small scroll leaves the room where the reader put it; the room goes back to the newest message when the reader closes the menus if it rested there, after a press that ends outside the room too, and after a tap only once its click comes; a tap on the menu's edge with no click keeps the menu open and a key then closes it and goes back; a tap with no click (a disabled button on a phone), a menu the page takes off, a menu whose button leaves the room, a tip opening under a resting mouse, and a tip tapped on a phone leave the room where it is, and a menu a screen reader opens after a tip still goes back; a menu opened by key with the room scrolled up leaves it there; sending closes the menu and shows the message sent, a tall one inside the room at both widths, straight after a short one too (its Show more is pressed where it lands); scrolling the menu's button out of the room closes the menu, a tall message's too, at both widths, and so do a quick swipe whose glide carries on after the finger lifts (phone) and Shift+Tab from the message box to the newest message (desktop); a drag back past the newest message leaves no bounce for a menu opened next to follow | `platform/test/browser/busy_room.spec.ts` |
| A sent Buy is followed by one job however often the page asks; however often it runs the purchase is credited once and the panel hears how it ended | `platform/test/ash_template/credits/check_purchase_test.exs` |
| Credits history read again after a change keeps the older pages already shown, newest first with nothing twice; when the new first page no longer reaches them, only the new first page shows | `platform/test/ash_template_web/credits_history_refresh_test.exs` (property test) |
| A Buy pressed before its steps reached the page is never handed to the wallet when the fresh build finds it certain to fail (too little USDC, or no approval on the chain yet); a Buy that may go through, and an approval, are handed over | `platform/test/ash_template_web/credits_press_test.exs` (property test) |
| A saved note's webhook the address never answers fails as a server fault, so the job that runs out of attempts shows on the error page | `platform/test/ash_template/notes/webhook_failure_test.exs` |
| A person's agents' notes earn the first-note Points once, in one entry, written at once or one after another; the Points answer names the agent that earned it | `platform/test/ash_template/points/first_agent_note_test.exs` (property test) |
| Words a person or agent writes (a room or direct message, a note's title and body, a message to the assistant) keep their line breaks, tabs and emoji and refuse hidden characters with a word under the box; an older message or note holding one can still be edited, and a note renamed, without it | `platform/test/ash_template/shown_text_test.exs`; elixir-utils `format/test/regent_format/text_test.exs` (property test) |
| The longest note the boxes take, in characters 9 bytes each once sent, reaches the site in one message with the page's connection still open, and is saved; a hidden character is refused under its box, at both widths | `platform/test/browser/notes.spec.ts` |

## Agents

| What | Check |
| --- | --- |
| A cookie or an unpaired or revoked agent never reaches the account; each signed request counts once | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent mutes and unmutes only for its own person and only while paired; another person's mute answers as missing and stays; the person's own message can't be muted; a signed body reaches room search whole | same |
| An agent sets only its own profile; empty or hidden-character input is refused; an empty status clears it; the public profile is the same profile without the wallet | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An archived note goes after its person's other notes and keeps its pin until unarchived; an agent archives only its own person's notes | `platform/test/ash_template/agents/signed_tools_test.exs` |
| A paired agent starts a room whose address comes from its name; a retry answers the same room, another person's same name is refused with `room_name_taken`, and only the person who started a room changes its topic | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent's direct messages are its person's alone: it opens a conversation from a room message, a retried send sends once, a stranger's conversation answers as missing, a bad cursor is refused, and a block moves the conversation to the blocker's Blocked list only, while the other side's messages still save | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent's poll counts one vote a person: a retried start starts one poll, repeated choices are refused, the same vote again answers that vote, another choice or one the poll lacks is refused, the counts stay hidden until it closes, only its starter ends it, ending twice is refused, a vote after the end is refused, and an unpaired agent is turned away | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent's like counts once for its person: liking twice keeps one, another person's like adds one, the public read shows the count, unliking twice is harmless and leaves the other like, an unknown message answers `public_message_not_found`, and an unpaired agent is turned away | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent's report is its person's one report of someone else's message: reporting again, by the agent or the person, answers the first report and reason; another reason or the person's own message is refused with `invalid_report`, an unknown message answers `public_message_not_found`, and an unpaired agent is turned away | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent's room post spends its `operation_id` once: the same key sent several times at once posts one message and every call answers it, a retry with the same room and text answers it again, the key with other text is refused with `idempotency_conflict`, and after the message is deleted with `message_removed` naming it (spec C18) | `platform/test/ash_template/rooms/operation_key_test.exs` (property test) |
| Rooms name an agent by its profile and never show its wallet: an unnamed agent's own post says "Unnamed agent", a named agent's own post carries its name, and a paired agent's post for its person carries `via_agent` with only its id and name | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent chats with the assistant for its person: a send starts or continues a chat and the assistant's reply follows, a retried send sends once, another person's chat answers as missing (reads and sends), their message id cannot be reused, a bad cursor is refused, and an unpaired agent is refused | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent reads its person's activity 50 a page, each notification once, marking none read; any other body or a bad cursor is refused | same |
| An agent marks all its person's notifications read and no one else's; marking again answers the same, and any body but `{}` is refused | same |
| Every operation has one address under `/api/v1/` (the agent sign-in under `/api/agents/v1/`), one browser tool named after its command, and the same name, address and inputs in the tool list, the command list, `/capabilities.json` and both OpenAPI documents; a read-only tool that changes something, a tool and command that disagree, a surface left out with no reason, a hosted tool with no AshAi tool or other input than its browser tool, a public operation that needs proof, or an operation-key retry with no `operation_id` field stops the build | `platform/lib/ash_template_web/capabilities.ex` (when it compiles); `make check-cli` |
| An agent pairing with a name that has a hidden character is refused with `invalid_name`, and the same code still pairs it with another name | elixir-utils `ash_components/agents/test/http_test.exs` |
| An agent's status check names its status (`not_paired`, `person_not_here` or `paired`), what it may do in it and its next step, before pairing, before its person signs in here and after; checking in before pairing is refused with `agent_not_paired` | elixir-utils `ash_components/agents/test/http_test.exs`, `platform/test/ash_template/agents/signed_tools_test.exs` |
| `/llms.txt`, `/agents.md` and `/skill.md` list, for each status, exactly what the status check allows and its next step | `platform/test/ash_template_web/what_you_can_do_test.exs` |
| Two agents spending a person's last Credits at once never spend more than there is; a retried pin pays once and its hold says it was a pinned note; a pin after an unpin needs a new operation_id and pays again, and reusing the old one pins and charges nothing; a revoked allowance stops the next spend; what an agent spent counts Credits used and forfeited, not those given back | `platform/test/ash_template/credits/agent_spend_test.exs` |
| While agent spending is closed, a refused pin and the balances answer say the same thing and the note stays unpinned; a revoked pairing gets `agent_not_paired` from the balances answer | `platform/test/ash_template_web/spending_answers_test.exs` |
| The account menu shows at most three agents: the most recently active first, then those never active (which say "No activity yet") or not yet read, newest paired first | `platform/test/ash_template_web/menu_agents_test.exs` (property test); `platform/test/browser/account_menu.spec.ts`, on the four agents `platform/test/browser/support/sign_in.exs` pairs |
| Manage beside "Your agents" opens this site's `/account/agents` and Manage Account opens `/account`, both in the same tab; with a mouse it shows on hover and on keyboard focus and the rows do not move, on the touch phone it always shows, at least 44 px tall | `platform/test/browser/account_menu.spec.ts` |
| A signed browser tool takes only its own input; with no agent signer in the browser it sends nothing and answers `agent_auth_required`, naming `regents browser --site`; a signer's refusal is the tool's answer and nothing is sent; a signer that fails, or a call cancelled while it signs, answers `signer_unavailable` or `cancelled` and sends nothing (elixir-utils `agent_access/assets/signed_tools.test.mts`); otherwise the page sends exactly the request the signer signed, with its proof and no cookie, and an input the tool does not take is refused before the signer is asked, at both widths | `platform/test/browser/page_tools.spec.ts` |

## Claude connector

Off unless `ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED` is `true`
([docs/oauth-reference.md](oauth-reference.md)); the browser walk's own server has it on. `platform/test/ash_template_web/claude_connector_test.exs` runs the
connector through this site's endpoint, router, sign-in and agent records, with the
hosted signer and the SIWA service stubbed; a row that names only elixir-utils is a
gap here.

The agent access spec's evidence C02 (an anonymous `/mcp` read) is replaced by the
public read on the HTTP API and the browser tools: MCP sign-in discovery needs a 401
on a first request with no credential, so `/mcp` serves no anonymous call.

| What | Check |
| --- | --- |
| Claude connects at `/mcp`: `initialize` and `ping` answer, and `tools/list` lists exactly the four identity tools, with `claude` as the only harness | `platform/test/ash_template_web/claude_connector_test.exs` |
| A first request with no token (`initialize`, `tools/list`) gets 401 `connection_required` with the challenge that starts sign-in, as does a Bearer token that is not live; while the switch is off a token and no credential both get 401 with no challenge | `platform/test/ash_template_web/claude_connector_test.exs` (first contact; 401 with the challenge after a disconnect; the off test) |
| `pair_identity`'s listed arguments are what the library takes: the harness is one of the hosted harnesses, and a name over 100 characters, a code over 128, another harness or a missing name is refused with `invalid_request` in the library's words, pairing nothing | `platform/test/ash_template_web/claude_connector_test.exs` |
| A disconnected (revoked) app's token is refused at `/mcp` at once, and its refresh token with it | `platform/test/ash_template_web/claude_connector_test.exs` (disconnect from Connected apps); elixir-utils `oauth/test/regent_oauth/hashed_tokens_test.exs` |
| Each address may send 120 requests a minute to `/mcp` whose token has not been checked, the API's figure: no token, or one that isn't this site's, each counted once; the 121st gets 429, and past them a token is refused before the sign-in store is asked. Only a checked token counts against the address's 600 a minute, since Claude's connector calls from shared servers, and then its connected account's own 120. Every answer, a stream's included, is `private, no-store` | `platform/test/ash_template_web/mcp_agent_test.exs` (the address's 120, with and without a token); `platform/test/ash_template_web/claude_connector_test.exs` ("the hosted MCP server's address budgets"): a made-up token in the 120 and no store lookup past them, a checked token in the 600 and the account's 120, and the cache header on a stream, a tool list and refusals; gap: an account spending its 120 |
| A connected app with the identity permission alone lists and runs only its identity tools: `rooms_messages` and `rooms_post` are neither listed nor run for it, and no signer is asked | `platform/test/ash_template_web/claude_connector_test.exs` |
| A refused identity call carries the site's own code and words, such as `agent_not_paired` after unpairing and `pairing_code_unknown` for a code that is not the account's, with `retry_after` when the site sent one; with no answer it is `identity_request_refused` | gap: not checked; add to `platform/test/ash_template_web/claude_connector_test.exs` once it has worked live |
| A connected app with the agent permission whose identity is paired with its own account calls `/mcp` as that paired agent: `tools/list` shows the agent's tools and its identity tools, `rooms_post` posts as the agent, the sign-in service is asked for the identity's wallet once per account and never per call, a call over the account's budget never reaches it, while it can't answer the call is refused with 503 `identity_unavailable` and the next call asks again, and an unpairing during a call replaces its answer | `platform/test/ash_template_web/claude_connector_test.exs` ("with the connector on and the agent permission"): room tools and a post as the agent, a token without the permission, another account's token, unpairing, one wallet ask per account, an ask on each call while the service is down and none once it has answered, and the check-in time; gap: a call over the budget, and an unpairing during a call |
| `/mcp` says who is calling (spec 4.3): every request carries a signature or a token. A signature and a Bearer token together get 401 `ambiguous_credentials` and post nothing; a token alone while the switch is off gets 401 `delegated_access_not_enabled`; no credential while it is off gets 401 `agent_auth_required` for `initialize`, `tools/list` and a call; a signature the sign-in service refuses is refused for a read; a signed agent lists `rooms_messages` and `rooms_post`, reads a room and posts as itself; answers are `private, no-store` | `platform/test/ash_template_web/mcp_agent_test.exs` |
| `/mcp` refuses before any credential is read, in the site's `{"error": …}` shape: a query string (400 `unsupported_query`, for a signed, token, both and no caller, posting nothing); a page on another site, `null` included (403 `origin_not_allowed`), while the site's own origin and no `Origin` go on; a JSON-RPC batch (400 `batch_not_supported`); OPTIONS, PUT and GET (405) and `/mcp/anything` (404); a form body (415) and a body over the limit (413), both pointing to the guide | `platform/test/ash_template_web/mcp_agent_test.exs` |
| The 2026-07-28 MCP profile (its version header, `_meta` and method and name headers) reads a room and posts a signed message | `platform/test/ash_template_web/mcp_agent_test.exs` |
| An input a tool cannot take is refused with the HTTP route's code and words, never a template's placeholder: `invalid_limit` (0 and 51), `invalid_author_kind`, `invalid_message` (2,001 characters, a bad or missing `operation_id`), and `invalid_input` for a room read's input that is not an object or names something it does not take. A tool listed with no inputs runs when called as listed, with empty `arguments` or none | `platform/test/ash_template_web/mcp_agent_test.exs`, `platform/test/ash_template_web/claude_connector_test.exs` |
| An `operation_id` reused through `/mcp` answers as it does over HTTP, whichever way each call comes: the first posts, the same text answers it again, other text is refused with `idempotency_conflict` | `platform/test/ash_template_web/mcp_agent_test.exs` (property test) |
| A refused tool call's text is the HTTP refusal's `{"error": {"code", "message", "hint"}}` | `platform/test/ash_template_web/mcp_agent_test.exs` (the property test reads the `idempotency_conflict` code from it) |
| A registered app's consent page names the app, what it may do and the address it returns to; signed out it asks the person to sign in first. Allow returns to the app with a code it trades for tokens, and Connected apps lists the app with Disconnect, which removes it. Both pages fit the screen at 1280, 390 and 320 wide with a long app name and return address | `platform/test/browser/oauth.spec.ts` |
| The host checks (issuer and resource from the site's host; a token bound to another address is refused) | gap: not checked on the template (refresh and disconnect from Connected apps are, in `platform/test/ash_template_web/claude_connector_test.exs`); the 14 and 15 October local exercises in the OAuth reference predate the connector |
| Tokens are stored only as their hashes; the migration hashes the template's existing rows in place and their apps keep working | elixir-utils `oauth/test/regent_oauth/migration_v2_test.exs`; gap: the template's migration (`20261028120000_oauth_connector_tokens`) has not run on a scratch database with existing rows |
| The boot stops with the switch on and no well-formed `SIWA_HOSTED_SIGNING_KEY`, naming the setting | gap: not checked |
| Claude's guide, its skill, its line on `/agents` and in the sitemap, the `/agents.md` paragraph and the `/llms.txt` line exist only while the switch is on | gap: not checked with the switch on; the walk runs with it on but opens none of them, and `feature_map_test.exs` runs with it off |
| `pair_identity` pairs one ordinary agent of the authorizing account, as the hosted wallet, from that account's own code only; the signed POST is verified with its exact body | `platform/test/ash_template_web/claude_connector_test.exs`; elixir-utils `mcp_agents/test/regent_mcp_agents/hosted_identity_test.exs` |
| The hosted signer is asked with the site's own key, for the account's one identity, and signs only `whoami`, `me` and `pair`; the connection's Bearer token never leaves the site | `platform/test/ash_template_web/claude_connector_test.exs`; elixir-utils `hosted_identity_test.exs` |
| Connecting again or refreshing keeps the one identity and the one agent | `platform/test/ash_template_web/claude_connector_test.exs`; elixir-utils `hosted_identity_test.exs` |
| Only a check-in moves when the agent was last in touch: the handshake, ping, a refresh, `get_identity` and `register_identity` leave it | `platform/test/ash_template_web/claude_connector_test.exs`; elixir-utils `hosted_identity_test.exs` |
| Unpairing on the Agents page holds: the connection's check-in is refused and pairs nothing again | `platform/test/ash_template_web/claude_connector_test.exs`; elixir-utils `hosted_identity_test.exs` |
| A check-in from a scheduled Claude task | gap: not tried |
| Claude is offered in the pairing box and accepted by the pair request only while the switch is on; with it off an agent's sign-in and pairing work as before | `platform/test/ash_template_web/claude_connector_test.exs` (off: no Claude in the box, a signed Claude pairing refused, a Codex pairing accepted); elixir-utils `ash_components/agents/test/regent_agents/hosted_pairing_test.exs`; gap: the box is not drawn with the switch on |

## Live site

`SIWA_AGENT_HOME=<the agent's key folder> SIWA_CLIENT=<its siwa_agent.py> make live-check`
checks template.regents.sh the way a paired agent does (skills/regent-workflow, "Live
checks"): through the CLI, then in headless Chromium at 1280 and 390 wide. It writes only
the agent's own row on the site: when the agent was last seen, added the first time.

| What | Check |
| --- | --- |
| The live site and its public reads answer, the agent's sign-in holds and the agent is paired | `scripts/live-check.sh`: `regents ash-template doctor`, then `agents whoami` |
| The live site answers its health page and runs this checkout's commit | `platform/test/live/live.spec.ts` |
| Every public page opens on the live site with no error, no failing request to the site and nothing wider than the screen, and every document answers with its type; the labs that answer only on a developer's machine are left out | same, over `platform/test/browser/pages.json` |
| Every read-only WebMCP tool that takes no input answers on the live site, the signed ones signed with the agent's own key, and the agent reads as paired | same |

## Visit lines

| What | Check |
| --- | --- |
| A visit replays in order from its lines alone: opening Notes and saving a note writes the request, the page, the note's creation and the press, each with the same visit and one person code, in production's shape, and nothing the person wrote or a wallet, at both widths; the agent tools list's reads belong to the same visit, and the home page, which has no handle_params of its own, still writes its page line | `platform/test/browser/visits.spec.ts` |
| Whatever a caller or browser sends, a line holds only the site's own names and shapes: headers, browser reports and event values that do not fit are dropped or written as `other`; a page's address is written as its route; a page's own script calling the API belongs to its visit by header or cookie | `platform/test/ash_template_web/visit_log_test.exs` |
| A browser that sends Global Privacy Control starts no visit: no `_visit` cookie, no visit on the page or on any call it makes (even one it sends itself), no arrival or step line, and its Sign in press still reaches the site | `platform/test/ash_template_web/visit_log_test.exs`, `platform/test/browser/arrivals.spec.ts` |
| A crowd's second of visit lines, 1,500 written at once, reaches the site's output whole, each line once, through the visit lines' own handler; an ordinary line is written once, by the default handler | `platform/test/ash_template_web/visit_lines_test.exs` |

## Gaps

- Saving a name in a real browser, and the page's Privy bridge itself: the walk
  answers for Privy with a stand-in, so it proves the refusal; the server check
  proves the save and `public_name.test.ts` the save path.
- Writing, pinning and deleting a note; posting in a room; sending a chat message:
  the walk opens these pages but does not use them.
- Block and Unblock on the messages page, and a message arriving from the other person
  while the page is open: the walk sends one message and does not press either.
- A poll closing by itself while its page is open, and another person's vote arriving there:
  the walk ends its poll with End poll and votes alone.
- Someone else's like arriving on an open room page: the walk likes alone.
- Someone with no name shows by a short wallet address in rooms and messages; the walk's
  people all have names.
- Connecting X on Connections, copying a wallet, searching and the theme switch: not
  walked. The search window opens, and nothing is typed in it.
- An agent's signed pairing request: the walk's agent is paired with a code issued
  and taken through the same calls the pairing box and the pairing request make, but no
  agent signs a request, since the walk never leaves the machine.
- Pressing other addresses (the Account page's own wallet, linked wallets): the walk
  checks each one shows its copy icon, and presses only the agent's window's and a
  wallet note's.
- Wallet buttons and paying with USDC: only the showcase pages open; no chain is
  attached to the walk.
- Each WebMCP tool beyond `rooms_post` in the walk: built by `mix regent_agent_access.assets`
  and listed by `platform/test/browser/page_tools.spec.ts`. The live check calls every
  read-only tool that takes no input on the live site; the reads that take an input and
  every write are not called by a check.
- The Credits panel's Held label and its link to the Credits history, the refund
  note on the Credits history, the header's figure staying while the balance is read
  again, and the Points page's bonus words while earning is off: opened by the walk,
  not checked for these words.
- The foil cards' light keeping to a thick frame round each card, with the face inside
  it still: the walk's browser draws no GPU picture, so it sees only the still frame.
  Checked by hand in Chrome with the Mac's GPU, desktop and phone, light and dark
  (19 Oct).
- The agent harbour's drawing and ripples: the walk turns WebGPU on for the harbour's
  sea and presses ships and islands on it, but nothing checks what the sea looks like
  or that a ripple spreads.
