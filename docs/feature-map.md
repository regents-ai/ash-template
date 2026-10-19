# Feature map

What a person or an agent can do on this site, and the automated check that proves
it. A row without a check is a gap, listed as one. Grow this file as features are
touched: a change to a feature adds or updates its row in the same commit. Sites
copy this file's shape.

`make check` runs every check below. The browser walk (`make check-browser`) runs
headless Chromium as a desktop 1280 wide and as a touch phone 390 wide (Playwright's
Pixel 7 at that width); WebKit is not run on the Mac. The walk never
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
starts, and the server watches no files, so no page reloads under a check.

## Every page and document

| What | Check |
| --- | --- |
| Every page opens, shows what proves its purpose, raises no error, makes no failing request to the site, fits the screen and shows every ENS name, full address and short address with its copy icon, signed out and signed in | `platform/test/browser/pages.spec.ts` over `platform/test/browser/pages.json` |
| Every machine-readable document answers with its type | same, `documents` |
| No page or document the site serves is left out of the walk, and the walk names none the site has dropped | `platform/test/ash_template_web/feature_map_test.exs` |
| Every agent in the side panel has a guide page and a skill the walk opens | same |
| The site started with its sign-in settings | `pages.spec.ts`, first test |
| A page asked for JSON gets a refusal, a browser gets the page | `platform/test/ash_template_web/content_negotiation_test.exs` |
| Closing the site leaves the agent pages open | `platform/test/ash_template/site/launch_gate_test.exs` |

## People

| What | Check |
| --- | --- |
| Sign in, and sign in again with a wallet added; sign in with email and keep one account | `platform/test/ash_template/accounts/verified_session_test.exs` |
| Disconnect stays disconnected; a real return from the wallet signs in | `platform/assets/test/privy_bridge.test.ts` |
| Each account shows the name its person saved with this site's sign-in, never a name saved under another sign-in, in the order asked | `platform/test/ash_template/accounts/display_name_test.exs` (property test) |
| A name saved on the Account page with the person's own sign-in shows there, in the form and as the account's name; a forged sign-in changes nothing | `platform/test/ash_template_web/public_name_test.exs` |
| Save makes the person's profile on their first save and saves only to the profile it read; a switch of account part way through the page's own save path saves nothing, and neither does a save pressed before a switch and still waiting its turn; two quick saves keep the name pressed last; a failed save never leaves the form busy | `platform/assets/test/public_name.test.ts` |
| Save on the Account page without the browser's sign-in finishes, says why, sends no change and moves nothing, at both widths | `platform/test/browser/public_name.spec.ts` |
| A name with a hidden character (a control, a line or paragraph separator, or a format character such as a text-direction mark or zero-width space) is refused, and the person is told to remove the hidden characters; a joiner between two visible characters and a complete flag still save; taking out any one rule fails a check | elixir-utils `ash_components/identity/test/http_test.exs` and `profile_test.exs` (property tests); the words in `platform/assets/test/public_name.test.ts` |
| The longest name the site takes, with no spaces, fits every signed-in page at both widths | `pages.spec.ts`; the walk's person has an 80-letter name (`platform/test/browser/support/sign_in.exs`) |
| Pair New Agent opens the pairing box, from the Account page and from an agent guide's link | `platform/test/browser/pairing.spec.ts` |
| Choosing an agent gives a message with a code, and each choice a new code | same |
| A page with one panel gives it the whole width | `platform/test/browser/layout.spec.ts` |
| An address, ENS name or short address opens its full address on a click, tap or Enter and copies it from its icon | design-system `regent_ui/test/regent/primitives_test.exs` |
| An agent's window opens from the Account page; its address opens the full address on a tap or click, Escape closes it and gives the press back to the address, its icon copies the full address, and on the phone both targets are at least 44 px tall once the window has risen into place | `platform/test/browser/agents.spec.ts`, on the agent `platform/test/browser/support/sign_in.exs` pairs |
| A wallet note names each wallet with its copy icon: with an unlinked wallet open in the on-chain lab, the note names it and the account's wallets, each opening and copying its full address, the words run straight on from each address, and nothing on the page shows an address without its icon | `platform/test/browser/addresses.spec.ts` |
| An agent's window renames the agent: a name with a hidden character is refused beside the field and the agent keeps its name; a name with an emoji joined by a zero-width joiner saves and shows in the window and the list, at both widths; the field and Save are at least 44 px tall on the phone once the window has risen into place | `platform/test/browser/agents.spec.ts`, on the agents `platform/test/browser/support/sign_in.exs` pairs |
| Only the person renames their agent; a blank name, one over 80 characters or one with a hidden character is refused | elixir-utils `ash_components/agents/test/pairing_test.exs` |
| A moving picture whose graphics card never starts shows the still picture and stops listening to the page | `platform/assets/test/canvas_island.test.ts` |
| Buying Credits credits the account with the site listening | `platform/test/ash_template/credits/credited_test.exs` |
| Live figures: a bad reading never replaces a good one, a failed first read shows, pages hear only their own figure | `platform/test/ash_template/site/shared_reading_test.exs` |

## Agents

| What | Check |
| --- | --- |
| A cookie or an unpaired or revoked agent never reaches the account; each signed request counts once | `platform/test/ash_template/agents/signed_tools_test.exs` |
| An agent pairing with a name that has a hidden character is refused with `invalid_name`, and the same code still pairs it with another name | elixir-utils `ash_components/agents/test/http_test.exs` |
| Two agents spending a person's last Credits at once never spend more than there is; a retried pin pays once; a revoked allowance stops the next spend | `platform/test/ash_template/credits/agent_spend_test.exs` |

## Gaps

- Saving a name in a real browser, and the page's Privy bridge itself: the walk
  answers for Privy with a stand-in, so it proves the refusal; the server check
  proves the save and `public_name.test.ts` the save path.
- Writing, pinning and deleting a note; posting in a room; sending a chat message:
  the walk opens these pages but does not use them.
- Connecting X on Connections, copying a wallet, the search dialog and the theme
  switch: not walked.
- An agent's signed pairing request: the walk's agent is paired with a code issued
  and taken through the same calls the side panel and the pairing request make, but no
  agent signs a request, since the walk never leaves the machine.
- Pressing other addresses (the Account page's own wallet, linked wallets): the walk
  checks each one shows its copy icon, and presses only the agent's window's and a
  wallet note's.
- Wallet buttons and paying with USDC: only the showcase pages open; no chain is
  attached to the walk.
- Each WebMCP tool an agent sees: built by `mix regent_agent_access.assets`, not
  called by a check.
- The foil cards' light keeping to a thick frame round each card, with the face inside
  it still: the walk's browser draws no GPU picture, so it sees only the still frame.
  Checked by hand in Chrome with the Mac's GPU, desktop and phone, light and dark
  (19 Oct).
