# Donor queue

Parts a site does better than the template, brought in as small shared changes (task
S11, 2026-09-27). Each names where it came from, where it lives now, the promise it
keeps, and the step each site takes. The template lane is the one writer for every
entry. Product rules (auction economics, staking accounting, forum ownership, research
evidence) never come in.

## Brought in

| Part | From | Now in | Keeps | Site step |
| --- | --- | --- | --- | --- |
| Signed-in wallet shown at once | Autolaunch `SignedInWallet` (e3ab1e5) | `OnchainSteps.signer/2`, `mismatch_note/2` and the example's "from" line (template 5702314, 345b9f1) | A wallet panel shows the signed-in wallet on mount; only Privy's active wallet acts, and only when the account links it | Adopt the wallet standard (template-standard-adoption.md section 3) and delete the site's own version |
| Health that checks the database | Autolaunch `health_controller.ex` (e7f296f) | `HealthController` | `/healthz` answers "ok" only when a read of the site's own table succeeds, within 1 s, never cached, with no error detail | Point the read at one of the site's own tables |
| Page titles and descriptions | Regents `public_documents.ex` (7f866f87) | `PublicDocuments.page/1`, `metadata/3`, the root layout | Every page names itself; the site name is added once; the layout fails to render a page that sets no title | One `@pages` table; every page and controller assigns `PublicDocuments.page/1` |
| Friendly error pages | KeyFleet `error_html.ex` (73145ed) | `ErrorHTML` | "We can't find that page" / "Something went wrong", with recovery links | Take the two headlines |
| www to the site's address | Regents `canonical_host.ex` (c45e7cd5) | `Plugs.CanonicalHost`, first in the endpoint | A www. visit moves with its path and query in one 301 | Copy the plug |
| JSON for unreadable API bodies | Regents `parsers.ex` (ee7d1d51) | `Plugs.Parsers`, with `RegentAgentAccess.Plug` moved before it | A malformed `/api` body gets a JSON 400, not an HTML page | Copy the plug and the endpoint order |
| No referrer from reading pages | Techtree `router.ex` (bcf47ba) | The `public_documents` pipeline | Reading pages send `referrer-policy: no-referrer`; sign-in pages keep the default | Add the header to the reading pipeline |
| Copy from the page, select when refused | Patchbay `copy_prompt.js` (45a7c92) | design-system `copy_button` `target` (0dc5b0a); template `installCopyButtons()` (`copy_buttons.ts`), on every page | A refused clipboard selects the target and says "Selected" instead of claiming a copy | Patchbay: move onto `copy_button` with `target`, delete `copy_prompt.js` |
| Copy says "Copied" to screen readers | KeyFleet `copy_text.ts` (c68ff12) | design-system `copy_button` (95785ab) | A polite status beside the button; the button keeps its width | Take `copy_button` and `installCopyButtons()` |
| Relative time | KeyFleet `Time.ago` (c9c0f97) | `RegentFormat.relative_time/2` (elixir-utils a034f91) | "3 minutes ago" and "in 2 hours", with `now` passed in | Delete local `ago` helpers |
| Client address behind Fly | Regents `client_address.ex` (cc795b0a) | `ClientAddress` (template 163ecba) | `Fly-Client-IP` is read only behind Fly's proxy | Already in the template; take it where weaker |
| Content security policy | Techtree `router.ex` (bcf47ba) | `ContentSecurityPolicy` reading, sign-in and showcase profiles (template 163ecba) | Each page names the one profile it needs; no wildcard origins | Keep a stricter site policy as it is |
| Browser tools (WebMCP) | Techtree `public_tools.ts`, `capabilities.ex` and the endpoint's `permissions-policy: tools=(self)` (a226cd0); Autolaunch's tool manifest and its docs and `llms.txt` tables (3f4fbb0) | `priv/tool_manifest.json`, `AshTemplate.Capabilities`, `public_tools.ts`, the endpoint, `/capabilities` | One manifest: every page registers its site tools from it, and `/capabilities`, `/docs` and `/llms.txt` list them from it; `make readiness` checks they agree | Keep the manifest, reader, registration and header; add the site's own tools to the manifest and its reads to `public_tools.ts` |

## Left out

| Part | From | Why |
| --- | --- | --- |
| ENS names and avatars | Regents `ens.ex` and `ens_identity.ex` (c213f40b) | The template was cut without ENS (2026-09-22 changelog); a site that shows ENS names uses elixir-utils `ens` directly |
| Session authority clean-up | Regents `session_authority.ex` (82bdc370) | The template never had the Regents Club code it removed; the template's version already has everything else |
| Amount and number parsing | Regents `staking*.ex`, `stake_live.ex` | Staking's own rules |
| `Time.moment/2` ("Today 14:03 UTC") | KeyFleet `time.ex` (c9c0f97) | One site uses it |
| Techtree's `api.github.com` and `form-action 'none'` | Techtree `router.ex` | Techtree's own pages |
| Metrics listener | Autolaunch `metrics.ex` (8706e24) | The template's own listener on a private port is at least as strict |
