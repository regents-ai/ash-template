# Feature map

What a person or an agent can do on this site, and the automated check that proves
it. A row without a check is a gap, listed as one. Grow this file as features are
touched: a change to a feature adds or updates its row in the same commit. Sites
copy this file's shape.

`make check` runs every check below. The browser walk (`make check-browser`) runs
headless Chromium at 390 and 1280 wide; WebKit is not run on the Mac.

## Every page and document

| What | Check |
| --- | --- |
| Every page opens, shows what proves its purpose, raises no error, makes no failing request to the site and fits the screen, signed out and signed in | `platform/test/browser/pages.spec.ts` over `platform/test/browser/pages.json` |
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
| Each account shows the name its person set for this site, never one set on another site, in the order asked | `platform/test/ash_template/accounts/display_name_test.exs` (property test) |
| A name saved on the Account page with the person's own sign-in shows there, in the form and as the account's name; a forged sign-in changes nothing | `platform/test/ash_template_web/public_name_test.exs` |
| Save makes the person's profile on their first save, saves only to the profile it read, and says when it did not save | `platform/assets/test/public_name.test.ts` |
| Save on the Account page without the browser's sign-in refuses, sends no change and moves nothing, at both widths | `platform/test/browser/public_name.spec.ts` |
| Pair New Agent opens the pairing box, from the Account page and from an agent guide's link | `platform/test/browser/pairing.spec.ts` |
| Choosing an agent gives a message with a code, and each choice a new code | same |
| A page with one panel gives it the whole width | `platform/test/browser/layout.spec.ts` |
| Buying Credits credits the account with the site listening | `platform/test/ash_template/credits/credited_test.exs` |
| Live figures: a bad reading never replaces a good one, a failed first read shows, pages hear only their own figure | `platform/test/ash_template/site/shared_reading_test.exs` |

## Agents

| What | Check |
| --- | --- |
| A cookie or an unpaired or revoked agent never reaches the account; each signed request counts once | `platform/test/ash_template/agents/signed_tools_test.exs` |
| Two agents spending a person's last Credits at once never spend more than there is; a retried pin pays once; a revoked allowance stops the next spend | `platform/test/ash_template/credits/agent_spend_test.exs` |

## Gaps

- Saving a name in a real browser: the walk's address has no Privy sign-in, so the
  walk proves the refusal and the server check proves the save.
- Writing, pinning and deleting a note; posting in a room; sending a chat message:
  the walk opens these pages but does not use them.
- Connecting X on Connections, copying a wallet, the search dialog and the theme
  switch: not walked.
- Wallet buttons and paying with USDC: only the showcase pages open; no chain is
  attached to the walk.
- Each WebMCP tool an agent sees: built by `mix regent_agent_access.assets`, not
  called by a check.
