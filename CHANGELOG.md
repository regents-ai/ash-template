# Changelog

This file is append-only. Add new dated entries at the end, in chronological order.
Do not edit, reorder, or remove existing entries; append corrections separately.

## 2026-09-22 — Template cut from Regents

- Cut this template from the Regents monorepo at commit `0bbd67c`.
- Kept the Phoenix/Ash platform with the public home page, Privy wallet sign-in,
  the signed-in Overview and Account pages, the public pages, health and
  metrics, `/llms.txt`, `/openapi.json` and the served API, the design-system
  styling, a pnpm CLI skeleton, an empty optional contracts workspace and an
  empty plugins folder.
- Renamed the placeholder product to Ash Template (`ash_template`, `AshTemplate`,
  `ash-template`, `ASH_TEMPLATE_`).
- Removed everything specific to Regents: staking, Redeem, Autolaunch,
  Formation, Regents Club, ENS, OpenSea, the blog, Regent Names and claims,
  public profiles, agent sign-in, sprites, the Base RPC reads, the Regents CLI
  commands and the Solidity contracts.

## 2026-09-22 — PostgreSQL 17 pin

- Pinned `postgres 17.7` in `platform/.tool-versions`, the server every environment runs.

## 2026-09-22 — mint 1.10.1

- Moved the mint HTTP client to 1.10.1, which closes the medium-severity
  EEF-CVE-2026-82672 (HTTP/1 response smuggling through an unvalidated
  chunk-size line). Lockfile-only change.

## 2026-09-22 — Template cleanup

- `scripts/init.sh` also renames the camel-case `ashTemplate` and the
  capitalised display name "ASH TEMPLATE" in the terms.
- Removed browser code no page used: the HomeField, HomeHero, InfoDialog and
  ModalDialog hooks, the background manifest and its images, the bundled font
  copies (the design system serves the fonts), the unused brand images and
  screenshots, the compatibility token file and the unused styles.
- Sign-in errors and warnings no longer name Regent. The Account page no longer
  shows a World ID row, and linked identities accept only X, GitHub and
  Farcaster.
- Removed the unused public-profile read and the picosat solver; `simple_sat`
  is the one solver.
- The route handoff files are `priv/handoff/route-catalog.*`, and test names
  carry no ticket tags.
- The CLI runs Vitest 4.1.11 with Vite 7.3.6 and an esbuild floor; CI takes its
  Node version from `platform/.tool-versions`.
- `make check` runs every component's gate; the platform gate adds the
  TypeScript typecheck and unit tests.

## 2026-09-22 — Placeholder brand, no local acceptance tooling

- The homepage hero shows a still placeholder image; the animated crown, its
  helpers and their tests are gone. The favicons, `mark.png` and the flat marks
  are a neutral placeholder square under the same file names. `AGENTS.md` lists
  what a new site must replace by hand.
- Removed the local acceptance tooling: the setup and reset scripts, their mix
  tasks and guide, and the acceptance branch of the local database fixture.
- `PRIVY_VERIFICATION_KEY` is read as given: the PEM with real line breaks.
- The minimum PostgreSQL version the repository declares stays at 14; at 17
  AshPostgres writes upserts as MERGE statements that lose the schema prefix.

## 2026-09-25 — Skills folder with the Anime.js skill

- New `skills/` folder for agent skills that go with this stack. The first is
  `skills/animejs`: Anime.js 4.5.0 inside LiveView hooks, with a docs lookup
  script and hook rules checked in a browser against LiveView 1.2.11.

## 2026-09-26 — Every Regent skill lives here

- `skills/` now holds every skill Regent writes: `regent-workflow` (the entry
  point), `regent-notion` and `checkpoint` joined the Ash and Anime.js skills.
  The workspace links to them; skills Regent only uses stay in the workspace.

## 2026-09-26 — Commands are described, not built, here

- `cli/` now holds `commands.json`, the description of every `regents ash-template`
  command in the `regents.commands.v1` format. The placeholder `ash-template` command
  package is gone; the code for every Regent site's commands lives in `regents-cli`.
- `make check-cli` checks the description against the format and the site's OpenAPI
  documents, using `regents-cli` beside this repository.

## 2026-09-26 — Skills for on-chain buttons and chain events

- `skills/onchain-buttons`: wallet and on-chain buttons driven by a hook's own click
  listener, sending from the signed-in wallet, with the server checking each result at
  the latest block. Its example hook and tests run against this template's wallet code.
- `skills/chain-events`: watching a chain at the latest block, saving each event once
  with a cursor, and updating pages through Ash notifications after the save.
- `regent-workflow` now says a press sends from the signed-in wallet.

## 2026-09-27 — The server builds every on-chain step

- `onchain-buttons` now has one way to build a step: the server encodes it and pushes
  the review to the page. The browser-built example is gone; sites that still build
  steps in the browser are listed in the skill's backlog.

## 2026-09-27 — One release path, checked end to end

- `make release` refuses uncommitted changes, runs `make check`, builds HEAD's
  `platform/` into an image and starts it against a throwaway PostgreSQL: the staging
  release commands, the health endpoint, a built stylesheet and the server's database
  connection. It prints the app commit, the shared-library commits and the image digest.
- `make check-cli` fetches regents-cli's checker from GitHub at the commit the
  `Makefile` pins, instead of using `regents-cli` beside this repository.

## 2026-09-27 — The best parts of the sites, brought in

- Every page names itself: one table in `PublicDocuments` holds each page's title and
  search description, every page assigns them, and the layout adds the site name once
  (from Regents 7f866f87). The Overview and Account pages no longer show the bare site
  name.
- Error pages say "We can't find that page" or "Something went wrong" (from KeyFleet
  73145ed).
- A visit to the site's www. address moves to the same page at the site's address
  (from Regents c45e7cd5).
- An `/api` request with a body the server can't read is answered in JSON, like every
  other API error (from Regents ee7d1d51).
- `/healthz` reads one of the site's own tables and answers "unavailable" when it
  can't, and is never cached (from Autolaunch e7f296f).
- Reading pages send no referrer (from Techtree bcf47ba). Sign-in pages keep the
  browser's default for Privy.
- The copy button can copy an element on the page by its id, and selects that text
  when the browser refuses the clipboard, saying "Selected" (from Patchbay 45a7c92;
  design-system 0dc5b0a).
- `docs/donor-queue.md` lists each part brought in and each part left out, with why.

## 2026-09-27 — Limits on updates are checked by the database

- Ash 3.33.11 ignores `change filter(expr(...))` when one record's update runs
  atomically, so a second, out-of-date call still writes (reproduced against
  PostgreSQL; fixed on Ash main, not yet released). The `ash-data` skill now says a
  limit or once-only rule on an update is an atomic validation, with the example and
  the stale-record check that proves it.
- The `chain-events` watcher guide's cursor move uses such a validation
  (`CursorUnmoved`) in place of the filter; a stale pass gets `StaleRecord`.

## 2026-09-27 — Copy buttons work on every page

- The copy button now works on plain pages as well as live ones. One page-wide
  listener (`installCopyButtons()` in `assets/js/copy_buttons.ts`, called once from
  `app.ts`) replaces the `CopyText` hook; design-system `4239c53` drops the hook from
  `copy_button` and tells LiveView to keep `data-copy-state` through redraws.
- Checked in a browser: on /docs (no LiveView) a copy button copies and says
  "Copied", and when the clipboard is refused it selects its target and says
  "Selected" (a `text` button says "Couldn't copy"); on /showcase "Copied" and its
  screen-reader status stay through a full reconnect redraw that strips any other
  added attribute.

## 2026-09-27 — Counts that fail say so

- `ash-frontend`'s async-state guide notes that `Ash.count` and `Ash.exists` raise a
  database failure where `Ash.read` returns it (reproduced on Ash 3.33.11), and how a
  page keeps its own error state for them (from Patchbay's P11 report).

## 2026-09-27 — Wallet-button lines stay in place

- The example wallet component's review, "from" and wrong-wallet lines are always in
  the page and shown or hidden with `hidden`, so focus stays on a pressed button (from
  Regents' R02). Checked in a browser: with the old lines focus left the Record button
  when a wallet was picked; now it stays.

## 2026-09-27 — Reads finish instead of being cancelled

- `AshTemplateWeb.Read` no longer cancels a running read on `start` or `clear`. A task
  stopped mid-query drops its database connection (reproduced: the pool logs "client
  exited" and reconnects); the read's generation already drops its late answer (from
  Patchbay's P14 report). Checked in a browser: a slow read that finishes after a
  quicker one, or after Disconnect, does not replace what is shown.

## 2026-09-27 — Wallet buttons stay, and timed steps are rebuilt

- `onchain-buttons`: a button stays on the page after its step is sent, the last one
  included, so a repeat press still reaches the wallet; a step with a deadline or expiry
  is rebuilt by the server before the limit comes (on approval, on revert and on a timer),
  never at the press. From the review of Autolaunch's A02; the template's example already
  keeps its buttons and has no timed step.

## 2026-09-27 — No ignore line for Regent UI images

- `platform/.gitignore` no longer ignores `priv/static/images/regent-ui/`. The pinned
  design system (4239c53) stages only fonts and its vendor CSS; images stopped being
  packaged in design-system 7756eb9, so the line hid files nothing produces (from
  Regents' R14).

## 2026-09-27 — Sign-in pages allow all of Privy's published policy

- The sign-in page policy adds what Privy publishes and the template lacked: its wallet
  RPC (`https://*.rpc.privy.systems`), WalletConnect's `.com` relay and `blob:` images.
  The policy's notes say what a Privy app offering Telegram adds (from Regents' R14, where
  the missing Telegram script stopped Telegram sign-in on the live site for four minutes).
  Checked: every source the template allows is in the policy Regents runs live, where
  Privy's window loads with no refusals; this machine has no Privy app for a sign-in here.
- The "not open yet" page and its JSON answer carry the strict reading policy instead of
  Phoenix's default. Checked in a browser with the gate closed: 503, the strict policy, the
  page styled, no refusals.
- The route catalog drops `content_transition_kind`; nothing read it.

## 2026-09-27 — Drift report

- `make drift` (`scripts/drift.sh`) reads every site's main branch on GitHub and lists,
  for each file the sites take from the template, whether the site's copy is the same
  after renaming, differs (with the difference saved under `platform/_build/drift/`) or
  is missing from the template's path. `scripts/init.sh` removes it from a new product.

## 2026-09-27 — Local metrics on a free port; wallet guide brought to today

- Locally the metrics listener takes a port the system picks, so two sites' local servers
  run side by side; production keeps 9091, which `fly.toml` names (from Techtree's 2c).
  Checked: two listeners started together on loopback, on two different ports.
- `make drift` lists a shared file a site has no use for yet as "not used", with why
  (Techtree: the launch gate, `Read`, hook composition), instead of missing.
- `onchain-buttons` sites-today checked 2026-09-27: KeyFleet builds every step on the
  server and is the closest site to the skill; Regents', Autolaunch's and Patchbay's held
  branches are named; two gaps in `regent_chain` recorded (no zero address in a call, no
  reader for return or log data). `chain-events` notes KeyFleet's 2 s check of sent steps.

## 2026-09-27 — Standardization plan: KeyFleet's wallet buttons are on the standard

- The wallet-transactions entry said KeyFleet's key and fleet actions were built in the
  browser and sat on its backlog. KeyFleet's `main` (8f9629f) builds every step on the
  server, so the entry now names that and points the held Autolaunch, Regents and Patchbay
  work at `skills/onchain-buttons/references/sites-today.md`. Checked against KeyFleet's
  checkout: the browser encoders (`buy_key.ts`, `fleet_action.ts`, `chain_call.ts`) are
  gone, `Keyfleet.WalletSteps.Build` encodes each step, its `LinkedSigner` policy admits
  only a wallet the signed-in account links, and `KeyfleetWeb.OnchainSteps` reads the
  result at `latest` every 2 s without storing it.

## 2026-09-27 — Rising words clip by class; the local server reads PORT

- From Techtree's motion step (124cd0f): words and digits that rise into view sit in a
  `.split-clip` box (`platform/assets/css/components/motion.css`) through the kit's
  `CLIPPED_WORD` and `CLIPPED_CHAR` templates in `hooks/motion/shared.ts`, used by the
  headline in `motion.ts`, the number roll in `moments.ts` and the lab. `splitText`'s
  `wrap` wrote a `style` attribute into the markup, which a strict page policy refuses.
  Checked in headless Chromium on `/about` and `/animations`: the headline rises word by
  word and ends as plain text with no style left, digits roll inside their boxes, nothing
  moves with reduced motion, no console errors. The `animejs` skill says to use them.
- `config/dev.exs` takes its port from `PORT` (4000 when unset), with `check_origin`
  following it, so the template runs beside the sites' local servers, as Techtree's does.
- `make drift` lists `components/motion.css`, and Techtree now uses `hook_composition.ts`.

## 2026-09-28 — Metrics README matches the config; KeyFleet's closed Markdown answer stays its own

- `platform/README.md` said metrics listen locally on `127.0.0.1:9091`; since the free-port
  change they listen on loopback on a port the system picks. Found by KeyFleet (a3e40ec).
- KeyFleet's `launch_gate.ex` adds a Markdown closed answer for its `.md` routes. The
  template serves no Markdown routes, so that clause stays a KeyFleet difference; a site
  that serves Markdown behind the gate adds the same clause.

## 2026-09-28 — From KeyFleet's motion step: back and forward are keyboard changes

- `hooks/motion/shared.ts`: going back or forward in the browser counts as a key press,
  so a menu or dialog it reopens is simply there rather than moving. From KeyFleet
  (b11ffdf).
- The page policy's comment on style attributes names both uses: the ratio card, and an
  element moving under `JS.ignore_attributes(["style"])` (the motion lab's list uses it).
  70c71eb had named the ratio card alone.
- `docs/standardization-plan.md` lists the motion additions KeyFleet keeps as its own, to
  weigh for the kit when a second site needs one.

## 2026-09-28 — release.sh removes the throwaway database's volume

- The cleanup ran `docker rm --force` on the database container, which leaves its
  anonymous data volume (~48 MB) behind on every run; it now passes `--volumes`. Found by
  Techtree (2b164bc).

## 2026-09-28 — The signed-in shell lints like every other file

- `.credo.exs` no longer excludes `live/shell_live.ex` from three complexity checks; the
  shell passes them (Credo strict, no issues). Found by KeyFleet, whose split shell no
  longer needed them.

## 2026-09-28 — A new site scores high on agent readiness from its first deploy

- Every `/healthz` and `/api/v1` answer carries the IETF `RateLimit-Policy` and `RateLimit`
  headers for one budget per client address (120 requests a minute); past it the answer
  is 429 with `Retry-After`. The plug is `RegentAgentAccess.RateLimit` in elixir-utils
  0.2.0 (pinned at 28f6ebc), with Patchbay's header format and Regents' budget-returning
  limiter, which `RequestRateLimiter` now is too.
- JSON errors have one shape, Autolaunch's `{"error": {"code", "message", "hint"}}`, from
  the same elixir-utils release. `openapi.json` gives every error response that schema,
  the rate-limit headers and a 429, plus a `default` answer; the YAML contract declares the
  429 on the profile operations.
- `/docs` gains Errors, Rate limits, and Versioning and deprecation sections (a breaking change
  ships in place, is listed there the same day and moves `info.version` to a new major
  number, with no notice period, per the founder's API-changes decision of 2026-09-26). `llms.txt` and the OpenAPI `externalDocs`
  point to them.
- The sitemap gives each page a `lastmod` (the release time). New
  `/.well-known/security.txt` (RFC 9116, expiring a year after the release) and
  `/.well-known/api-catalog` (RFC 9727). `llms.txt`, `robots.txt`, `openapi.json` and
  both new files carry an ETag and a five-minute public cache, as KeyFleet's agent
  files do.
- The site type is a site setting beside the site name in `PublicDocuments`
  (`business`; a product site sets `app`).
- `make readiness` starts the local server on a free port with the error debugger off
  and checks all of the above; `make drift` runs it, and lists the script as a shared
  file. The WebMCP item of the work order waits on the founder, so nothing here checks
  browser tools.

## 2026-09-28 — Every page offers a browser's agent two read tools

- Founder "1 b": the template ships two read-only WebMCP tools that need no product,
  `about` and `docs`. Each returns the About page or the developer documentation as the
  same Markdown an agent gets when it asks for that page; neither needs a sign-in or
  changes anything. This replaces the earlier "no WebMCP example tool in v0.1.0".
- One `platform/priv/tool_manifest.json` describes both. `AshTemplate.Capabilities` reads it
  when the app compiles and serves it at `/capabilities`; `/docs` and `/llms.txt` gain a
  "Browser tools" section whose table comes from it, and `llms.txt` no longer says the site
  has no tool registry. The Markdown pages can now show tables.
- `assets/js/public_tools.ts` registers the manifest's site tools through
  `document.modelContext.registerTool` on `pageshow`, removes them on `pagehide`, and sets
  `data-webmcp-status` on the page (`connected`, `unsupported` or `error`). The registration
  is Techtree's (a226cd0), as is the manifest reader and the endpoint-wide
  `permissions-policy: tools=(self)` on every answer; the manifest's fields and the tool
  tables in the docs and `llms.txt` follow Autolaunch (3f4fbb0).
- `make readiness` also checks the header on every public page, that `/capabilities`
  parses with WebMCP-valid entries, that the page's script registers exactly the manifest's
  site tools, and that `/docs` and `/llms.txt` list exactly the manifest's tools.

## 2026-09-28 — The command check runs regents-cli's Python checker

- `make check-cli` runs `regents_cli.check_commands` with `uv` straight from GitHub at
  regents-cli `65722c6`, the founder's Python rewrite; no `gh`, `npm` or checkout. Every
  site copies this target.
- `cli/commands.json` points `$schema` at the format's new home,
  `src/regents_cli/schemas/commands.v1.json` (the old address answers 404; Patchbay
  moved first, 08ebd27).
- `cli/README.md` names the `regents-cli` package and drops the shared `regents profile`
  commands, which 1.0 no longer has.

## 2026-09-28 — Every API answer carries the rate-limit headers

- The live scan of the template (scratch deploy of 466c3c6, 100/100) marked rate-limit
  headers partial: an unknown `/api` address answered 404 without them. The budget now
  runs in the endpoint for `/healthz` and every `/api` path, answered or not, before
  anything else can reply; the router's `:rate_limit` pipeline is gone. `make readiness`
  checks an unknown `/api` address too.
- `/docs` shows example requests for creating the profile and changing its name.
- The platform README says how a first staging deploy starts from an empty database
  (`bin/bootstrap-staging` once) and that Fly's attached database URLs lose their query.


## 2026-09-28 — Motion kit: KeyFleet's four additions (Phase 1 item 53)

- The number roll handles decimals and units: 1.75 to 2 rolls up, and "12.5 USDC" to
  "13.0 USDC" rolls only the two digits that changed.
- `MotionCascade`: a card list on a live page settles in the first time it scrolls into
  view; the home page's proof cards use it.
- `MotionRefusal`: a refusal message on a live page shakes when it appears and when it
  changes; the verified-connections error notice uses it.
- `MotionPanels`: drawers, sheets and menus opened by LiveView commands move when they
  appear, when the reader was last using a mouse or a finger.
- Pages the server draws once keep their cascade and alert shake in `motion.ts`.
- Checked in a headless browser with and without reduced motion; nothing moves when
  reduced motion is on.

## 2026-09-28 — Public demo at template.regents.sh: showcase setting, wallet page, build skills

- One setting, `ASH_TEMPLATE_SHOWCASE`, replaces the compile-time local showcase switch
  and its loopback plug. `local` (development's default) is today's behaviour; `public`
  is the hosted demo; `off` is a new site's production, where the showcase, wallet,
  motion lab and skills addresses answer 404 and the home page does not link to them.
  Production must set `public` or `off`, and any other value stops the boot. The wallet
  lab at `/showcase/onchain` stays local only.
- `/showcase/wallet` runs the reference wallet buttons on a real account with Privy's
  active wallet, on Base Sepolia (`:wallet_chain`), and says a press needs a little
  Base Sepolia test ETH. Every press reaches the wallet.
- `AccessContext.linked_wallets/1` (Phase 1 item 22): the signed-in account's own
  wallets, lowercase and each once, or `nil` signed out. The wallet page and the
  `onchain-buttons` skill use it.
- Build skills (Phase 1 item 37): ten skills from `skills/`, read when the app compiles,
  at `/.well-known/agent-skills/index.json` in the Agent Skills Discovery v0.2.0 format
  (a zip per skill with its sha256), each file on its own beside it, the agent guide at
  `/skill.md` and a page for people at `/skills`. `regent-workflow`, `regent-notion` and
  `checkpoint` are never served.
- When public, the sitemap and `/llms.txt` list the showcase pages, the motion lab and
  the skills; the home page links to them unless the setting is `off`.
- The image builds from the repository root (only `platform/` and `skills/` enter it);
  deploy with `fly deploy . --config platform/fly.toml`. `make release` builds from
  `git archive` of both folders and checks the skills index.
- The showcase pages now use plain wording for the public demo: practice pieces are called
  practice, and no file paths, code names or internal terms appear outside the labelled
  code and the component list.
