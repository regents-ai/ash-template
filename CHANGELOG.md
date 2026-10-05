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

## 2026-09-28 — Phase 1 fixes: sign-in, wallet buttons, security and operations

Sign-in
- A sign-in lasts 30 days; after that the next visit starts signed out. The browser
  cookie carries the same limit.
- When sign-in fails, the page says so in plain words and suggests reloading.
- Refused sign-ins are counted by where and why they stopped, and logged without detail.
- Removed code that was never reached: an unused session lease and a wallet fallback
  at sign-in. The Telegram note is gone from the page security policy.

Wallet buttons
- With no wallet open in the wallet app, a press sends nothing and the note names the
  account's own wallets and asks the person to open one. It no longer opens Privy's
  connect window.
- A press made before the page's first review arrives still reaches the wallet: the
  server prepares it on the spot. Choice buttons report the chosen value.
- A press that cannot reach the server shows "This page lost its connection, so
  nothing was sent."
- The wallet skills state the founder's one exception: a button the chain makes
  certain to fail (for example "144/144 Keys sold") stays visible but disabled, with
  the reason beside it. A pending transaction is never a reason to disable.

Security
- Production pages always use HTTPS and send Strict-Transport-Security; Fly's health
  check still gets its answer.
- Stylesheets, icons and images carry the same safety headers as pages.
- The site accepts only the request bodies it uses, up to one megabyte; file uploads
  and form method overrides are off.
- The build image uses fixed Hex and rebar3 versions, and a stale mix.lock stops it.
- A new CI job runs the platform checks; every CI action is pinned to an exact commit.

Operations
- The running site's database connection holds five connections, names itself, and
  gives up on slow statements, lock waits and idle open transactions. The README
  explains the serving login and the release login.
- `scripts/deploy.sh <app>` deploys only a clean commit that is on origin/main.
- The metrics page carries the three health series the site watch reads: database
  waits, chain requests with no answer, and wallet presses that were not sent.
- The page switch takes only "on" or "off"; anything else stops the boot, and the gate
  never assumes open.
- Every release command starts only the database connection through one helper.
- New skill notes: how to add an operator action; page reads, counts that fail
  safely, notify after commit, insert once, keyset pages.
- `make drift` also compares the access, session, actor and repo files with each site.

## 2026-09-28 — Theme, chain reads and guides

Pages
- Until someone picks a theme, pages follow their device: dark, or light when the
  device asks for light. A theme chosen on the site always wins, and the homepage
  stays dark.
- The sign-in dialog shows the site's own logo.

Security
- Mint 1.11.0 is required on every site (three advisories).
- The server reads each chain through its own node, set by
  `ASH_TEMPLATE_CHAIN_NODE_URL` in production, never through the address handed to
  the visitor's wallet.

Operations
- Pins move to elixir-utils 590f6d6 and design-system 42a439b.
- Readiness fetches only fixed paths. The command check job sets up uv. Drift lists
  Techtree's sign-in files as not used.
- Skill notes: when a turn may end, looking before editing, time budgets for
  delegates, named design patterns to avoid, raw SQL naming the site's schema,
  the nested JSON error shape, and the protected production tables with the command
  guard that refuses deletes on them.

## 2026-09-28 — One error shape everywhere

- Sign-in refusals and the closed-site answer now use the same error shape as every
  other JSON error: a code, a message and a hint. The served YAML contract moves to
  2.0.0 and the docs list the change.
- Profile errors from the shared Regents identity code carry a message and hint;
  the regents pin moves to baeffb12.

## 2026-09-28 — Regents faec71a8

- Moved `regent_identity` to Regents `faec71a8`, which pins the same elixir-utils
  commit as the template (`590f6d6`). `regent_privy` no longer needs `override: true`.

## 2026-09-29 — Payments guide

- Added the `payments` skill: how a site takes USDC payments through the shared
  `regent_payments` library in Regents (one offer per paid action, the page, HTTP and MCP
  doors, the USDC Balance, fees handed on to REGENT staking). The site serves it with
  the other build skills. `onchain-buttons`, `ash-webmcp` and the README point to it.

## 2026-09-29 — Pay with USDC example

- `/showcase/payments` shows how a USDC payment looks to the payer: the USDC Balance, what
  is being paid for, the Pay button and the words for each outcome. The figures are samples
  and Pay is switched off (founder, 2026-09-29), since the shared payments library takes
  real USDC on Base only. Linked from the showcase, `/llms.txt`, `/skill.md` and the
  `payments` skill.
- The `payments` skill says the payment tables are on the production protected-table lock
  (founder, 2026-09-29).

## 2026-09-29 — Pins match Regents v106

- Pins move to elixir-utils 5508072 and regents c927cdd0, the pair Regents v106 runs.
  The libraries the template uses are unchanged between the pins; elixir-utils 5508072
  adds smart-wallet signatures to sign-in (`siwa`), which the template does not use.

## 2026-09-29 — About page layout

- `/about` follows one layout for every site: a one-line summary, what the site does,
  what makes it different (with named alternatives), who uses it, the team, how it works,
  a Key facts table, frequently asked questions and who operates the service. Each part
  is a prompt to fill in; Key facts keeps only rows with a true answer, and the token
  rows and risk sentence apply only to a site with a token.
- `/llms.txt` repeats the About page's Key facts, so AI tools read the same facts.

## 2026-09-29 — No GitHub Actions

- GitHub Actions is off on every Regent repository except regents-cli (founder,
  2026-09-29), so the template's `cli-ci.yml` and `platform-ci.yml` workflows are gone and
  a product made with `scripts/init.sh` starts without any. `make check`, `mix precommit`,
  the drift report and the readiness check run on your machine as before.

## 2026-09-29 — About page names no competitors

- The About page describes what makes the site different without naming competitors
  (founder, 2026-09-29), so the Competitors row of Key facts is gone. This replaces
  "with named alternatives" in the About page layout entry above.

## 2026-09-29 — Long values wrap in public page tables

- The last column of a table on a public page wraps a long value, such as the site's web
  address or a contract address in Key facts, so the table fits a phone screen instead of
  scrolling sideways. Other columns keep whole words. Found by the Autolaunch lane.

## 2026-09-29 — Smaller theme button beside larger header icons

- The light/dark button is a small prism box in the middle of its press target instead of
  a bordered cell the full height of the header, with the same space before the X icon as
  between the icons. Pointing at it shows the other theme's colours (founder, 2026-09-29).
- The X and GitHub icons in the headers are 1.5rem, up from 1.25rem; footer icons keep
  their size.
- Pin moves to design-system 322448c, which owns the button's size, border and hover. The
  header no longer sets the button's height, left border or hover colour.

## 2026-09-30 — Theme button corners slightly rounded

- Pin moves to design-system 970b5bc: the light/dark button's box has slightly rounded
  corners on every site (founder, 2026-09-30).

## 2026-09-30 — Discussion thread example and skill

- New example page `/showcase/discussion`: a question with its replies in one column, a
  picture beside each name, the answer that worked quoted under the question, reply
  filters, a Compact replies switch the browser remembers, and a heart on every post. It
  uses `Regent.Discussion`, the shared version of Patchbay's discussion page (founder
  1a, 2026-09-30). The posts are samples and likes are not kept.
- New `discussions` skill: how a site stores its own posts, likes (one per person per
  post) and views (one per reader per thread), shows who liked a post, and gives agents
  the same like and read actions.
- `app.ts` imports `discussion.mjs` from the design system.
- Pin moves to design-system 405b73f.

## 2026-09-30 — Discussion fixes from Patchbay

- Pin moves to design-system 6bc2640: headings quoted in a Solved answer read as bold
  body text, the current reply filter keeps an outline in high-contrast mode, a thread
  takes a site's own attributes, and `Regent.Discussion.posts` lists posts outside a
  thread, such as one person's replies across threads.

## 2026-10-01 — Shared MCP events library listed

- `security/required-fixes.json` lists `regent_mcp_events` (elixir-utils `mcp_events/`),
  the shared helpers for MCP events, before any site adopts it.
- The platform README's new MCP events section says what the library does, what a site
  writes itself (the event methods, an adapter, one worker) and where Patchbay's are. The
  library first appears in elixir-utils `194896a`, not yet on GitHub, so no site can pin
  it until that commit is pushed. The template does not use it.

## 2026-10-01 — Elixir stack skill

- New `elixir-stack` skill: the standard Elixir, Phoenix, Ecto, Oban and OTP tool for
  each job, the list of things never to hand-build (job queues, leases, retry timers,
  polling loops), a design check to run before building and before reviewing, and
  Regent's Oban recipes. Every agent loads it with `regent-workflow` and `ash-stack`
  before Elixir work (founder, 2026-10-01).
- `ash-stack` routes background, retried and scheduled work to it; `ash-backend` says
  that durable work justifies adding Oban to a site that lacks it.
- `regent-workflow` requires the three skills, runs the design check before building
  and at the start of every review, and asks every founder decision to restate what
  changes, what yes and hold mean, and the recommendation.
- The site serves `elixir-stack` with its other build skills.

## 2026-10-02 — MCP events delivered by Oban

- `regent_mcp_events` (elixir-utils `c1544e5`) no longer ships a delivery worker or
  adapter. A site with events delivers them with an AshOban trigger on its
  subscriptions table, as Patchbay now does; the platform README's MCP events
  section describes the pieces.
- The `elixir-stack` skill's Oban recipes now name AshOban 0.9, the `cron:` key
  AshOban needs, the schema setting for sites that choose it at runtime, and the
  trigger rules the Patchbay build turned up: `on_error` runs only for update or
  destroy actions, outside calls run with `transaction?(false)`, retries log only
  their final failure, and a job cannot queue a second run of itself.

## 2026-10-03 — Keyboard and screen reader pieces from KeyFleet

- The app shell opens with a "Skip to content" link, hidden until the keyboard
  reaches it, that jumps past the header and side menu to the page.
- Moving between Overview, Notes and Account inside the app puts focus on the new
  page's title, so a screen reader announces where the person has arrived.
- Editing or deleting a note that the database couldn't answer for now says to try
  again, instead of saying the note is gone.
- The ash-testing skill's test recipes say to wait for a page's reads before a
  browser spec leaves it when specs share one sandbox transaction.

## 2026-10-04 — Chat rooms

- Two fixed rooms, General and Help, at `/rooms/general` and `/rooms/help` inside
  the app. Anyone can read; a signed-in person posts (ten a minute at most), edits
  and deletes their own messages, and can mute someone, which hides that person's
  messages and their place in "Here now" in every room, for the muter only.
- Every post, edit and delete reaches each open page of the room at once, and
  "Here now" lists the signed-in people who have the room open.
- Editing, deleting, muting or unmuting that the database couldn't answer says to
  try again, instead of saying the message is gone.

## 2026-10-04 — Rooms read like a chat app

- Newest message at the bottom, where the room opens; the message box sits under
  the conversation. Enter sends, Shift+Enter starts a new line (on a touch screen
  Enter starts a new line and the Send button sends).
- Messages one person sends within five minutes sit under one name and picture;
  each person has a coloured picture with their initials.
- Edit, Delete and Mute moved into a small "…" menu on each message, which closes
  on Escape or a press anywhere else. Choosing Edit puts the cursor at the end of
  the message in the box.
- Messages over six lines or 280 characters show the opening and a "Show more"
  button that opens the rest in place.
- Saving a message or an edit keeps at most one empty line between lines.
- Added `docs/app-shell-structure-plan.md`, the plan for the app's panel layout.

## 2026-10-04 — Chat with an assistant

- A Chat page at `/chat` inside the app: a signed-in person talks with an
  assistant, keeps a list of their own chats beside the one open, and the first
  message starts a new chat that names itself from that message.
- The assistant is a free stand-in that needs no account or key: it quotes back
  what you wrote, a few words at a time, the way a real assistant's reply
  arrives. Every page with the chat open sees the reply grow, with "The
  assistant is writing…" until it is done.
- The same chat in the look Ash AI's chat generator gives it, at
  `/chat/original`, linked from the Chat page.
- Built with Ash AI's chat generator; switching to a real assistant is a
  one-line change in each of the two places the stand-in is named.

## 2026-10-04 — Rooms to read from the command line

- Anyone can read the chat rooms without signing in: `GET /api/v1/rooms` lists them and
  `GET /api/v1/rooms/{room}/messages` reads one room's messages, newest first, up to 50 a
  page, with a cursor for the next page. The developer documentation, the agent guide and
  both API descriptions list them.
- `GET /api/v1/health` gives the health check's answer as JSON for the command line, which
  could not read the plain-text `/healthz`. `/healthz` is unchanged for the host.
- `cli/` is the worked example of a site's commands: `COMMANDS.md` describes `health`,
  `rooms list` and `rooms messages <room>` before `commands.json` lists them, and
  `cli/README.md` gives the steps for changing a command, docs first.
- The source copy of the YAML API description had fallen behind the served copy (it lacked
  the notes routes); both now match, and `mix precommit` checks that they stay matched.

## 2026-10-04 — Browser tools that act for the signed-in person

- Five new browser tools act as whoever is signed in on the page: `notes_list`,
  `notes_get` and `notes_create` for that person's notes, `room_read` for any room
  (leaving out people the reader muted) and `room_post` to post in one. They call the
  site's `/tools` routes on the page's own session, with the page's form token on every
  write, so a tool can never do more than the person could on the page.
- A write whose answer is lost reports that its outcome is unknown, with how to check
  before trying again; it never reports that it was cancelled.
- The notes API and the tools share one description of a note.

## 2026-10-04 — Agents post in rooms with their own wallet

- An agent signed in with its wallet (`regents auth login --site ash-template`) posts to a
  room with `regents ash-template rooms post <room>`, piping `{"body": "…"}`. The site
  checks each signed request with the shared sign-in service at
  `ASH_TEMPLATE_SIWA_BROKER_URL` (siwa.regents.sh when unset), under the audience
  `ash-template`.
- The agent posts as itself: a new `agents` table holds each wallet that has posted, and
  its messages show its short wallet address with an Agent tag. People may mute an agent
  like anyone else; the posting limit counts per agent; an agent cannot edit or delete.
- Every room message now says who wrote it (`author_kind`: `person` or `agent`) in the API.
  Both API descriptions describe `postRoomMessage` (1.3.0 and 2.3.0), and `cli/` gains its
  first signed command, documented in `cli/COMMANDS.md` first.
- Needs the sign-in service to list `ash-template=https://template.regents.sh` among its
  wallet audiences before live posts are accepted.

## 2026-10-04 — The app frame: rail, sidebars, tabs, side bar, search and activity

- Every signed-in page sits in one frame (`docs/app-shell-structure-plan.md`, decisions
  1–6): a top bar (logo, ⌘K / Ctrl+K search, help, what's new, assistant, bell, side bar
  toggle, person menu), a rail of five sections (Home, Notes, Rooms, Chat, Settings), each
  section's own sidebar list (hideable, remembered), fixed tabs per section, the page, a
  right side bar and a bottom bar (status dot, background jobs running, links, version).
- The right side bar is closed until opened and remembers its state in the cookie
  `ash_template_aside`; the sidebar uses `ash_template_sidebar`. `Plugs.Panels` reads both
  for the first paint, and LiveView never patches them. A light on the side bar's icon
  pulses while the bar holds something not yet seen in this browser.
- The side bar holds a promotional card, a Get started checklist worked out from the
  person's own data and ticked live, the page's own part (rooms' "Here now" and muted
  people), the assistant box (a conversation on the chat stand-in, "Open in Chat") and
  help links.
- New pages: Activity (`/app/activity`), Profile, Wallets and Connections as Settings tabs
  (`/account`, `/account/wallets`, `/account/connections`) and What's new (`/changelog`).
- Notifications: a new `Activity` domain with a `notifications` table (migration
  `20261004235329`). Posting `@name` in a room notifies everyone who has posted under that
  name there, in the post's own transaction, except the author and anyone who muted them.
  Open pages hear it over PubSub; the bell counts unread ones and Activity marks them read.
- Search reads pages and actions from the route catalog and the person's own notes and
  room messages through new `:search` read actions (2–100 characters, five each).
- The background-jobs count comes from Oban's telemetry events (`AshTemplate.JobsRunning`);
  the version shows the deployed image's commit.
- Notes and chat lists moved into the sidebar; rooms' tab row and side column are gone.

## 2026-10-04 — Note labels

- Each saved note is given a label (idea, task, question, reference or other),
  chosen by Jev in the background after the save. The notes page shows "Choosing a
  label…", then the label, live on every open page, and the writer can say once
  whether it fits. Editing a note asks again. The whole site asks at most 500
  questions a day; past that, notes save without a label.
- Each question is stored with the model, tokens and cost, retried up to three
  times when the request does not get through, and counted on the metrics listener.
- The notes API and the notes browser tools return each note's `label`;
  `/openapi.json` moves to 1.4.0 and the YAML contract to 2.4.0.
- Needs the `regent_jev` package from elixir-utils (`feat/jev`, `f9bc17c`) and
  `OPENROUTER_API_KEY`; without the key, notes save without a label.

## 2026-10-05 — Regents apps menu

- A nine-dot button in the app header, labelled "Regents apps", opens a "Regents Labs
  apps" panel linking Patchbay, Autolaunch, KeyFleet, Techtree, Protocol
  (regents.sh/stake) and Account (regents.sh/account) in a new tab. Each app shows the
  13-block crown in its own pair of the four brand colours.
- The panel is a native `popover`: the browser closes it on Escape or a press outside,
  and a LiveView patch leaves it open.
- On phones the header's icon presses narrow to 2.25rem so every tool fits on one row
  down to 360px wide.

## 2026-10-05 — Regents apps button size

- The nine dots fill a 1.5rem box like the X and GitHub marks beside them, and the
  button centres itself in the top bar (it sat at the top before).

## 2026-10-05 — ENS names and pictures

- A signed-in person whose wallet has an ENS name is shown by it, with its picture,
  in the header, the rail and the account page. A display name still comes first;
  a wallet with no name keeps its short address and generated picture.
- Each sign-in upserts the account's row in `account_ens_identities` and queues one
  AshOban job (`:look_up`, queue `outside_calls`, 3 attempts) in the same
  transaction. The job reads Ethereum mainnet outside any transaction through
  `AgentEns.PrimaryName` (elixir-utils `ens`), which keeps a name only when it
  resolves back to the same wallet and a picture only when the ENS avatar service
  answers with one. Open pages hear the result and redraw the header.
- The row records the wallet it was read for, so an account whose wallet changed is
  never shown the old wallet's name. A lookup that keeps failing leaves the last
  name standing.
- Needs `ETHEREUM_READ_RPC_URL` (https); without it, sign-in asks nothing.
  `img-src` allows `https://metadata.ens.domains`. Account pictures scale smoothly
  instead of as pixels, so photos are not jagged.

## 2026-10-05 — Search box redesign

- The search dialog is now a command palette: a full-width field with the
  search mark and an Esc key, results in groups with counts, a kind mark per
  result (page, action, note, room message), the first match marked in each
  label and excerpt, and a footer naming the keys. Phones get a Close word and
  no key hints.
- Search opens with every page and action as suggestions instead of an empty
  list (`ShellLive.unsearched/0`, also used by the showcase frame preview).
- Focus stays in the field (combobox with `aria-activedescendant`); the arrow
  keys move the highlight, Enter opens it, Escape closes the box, and the
  pointer moves the highlight too. Enter pressed before the results for the
  typed text arrive searches instead of opening a stale result.
- Note and room-message excerpts start a little before the first match.
- The field's focus shows as the accent line under it rather than a frame.
