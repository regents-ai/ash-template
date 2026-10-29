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
- Error pages say "We can't find that page" or "Something went wrong" (from Keyfleet
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
- `onchain-buttons` sites-today checked 2026-09-27: Keyfleet builds every step on the
  server and is the closest site to the skill; Regents', Autolaunch's and Patchbay's held
  branches are named; two gaps in `regent_chain` recorded (no zero address in a call, no
  reader for return or log data). `chain-events` notes Keyfleet's 2 s check of sent steps.

## 2026-09-27 — Standardization plan: Keyfleet's wallet buttons are on the standard

- The wallet-transactions entry said Keyfleet's key and fleet actions were built in the
  browser and sat on its backlog. Keyfleet's `main` (8f9629f) builds every step on the
  server, so the entry now names that and points the held Autolaunch, Regents and Patchbay
  work at `skills/onchain-buttons/references/sites-today.md`. Checked against Keyfleet's
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

## 2026-09-28 — Metrics README matches the config; Keyfleet's closed Markdown answer stays its own

- `platform/README.md` said metrics listen locally on `127.0.0.1:9091`; since the free-port
  change they listen on loopback on a port the system picks. Found by Keyfleet (a3e40ec).
- Keyfleet's `launch_gate.ex` adds a Markdown closed answer for its `.md` routes. The
  template serves no Markdown routes, so that clause stays a Keyfleet difference; a site
  that serves Markdown behind the gate adds the same clause.

## 2026-09-28 — From Keyfleet's motion step: back and forward are keyboard changes

- `hooks/motion/shared.ts`: going back or forward in the browser counts as a key press,
  so a menu or dialog it reopens is simply there rather than moving. From Keyfleet
  (b11ffdf).
- The page policy's comment on style attributes names both uses: the ratio card, and an
  element moving under `JS.ignore_attributes(["style"])` (the motion lab's list uses it).
  70c71eb had named the ratio card alone.
- `docs/standardization-plan.md` lists the motion additions Keyfleet keeps as its own, to
  weigh for the kit when a second site needs one.

## 2026-09-28 — release.sh removes the throwaway database's volume

- The cleanup ran `docker rm --force` on the database container, which leaves its
  anonymous data volume (~48 MB) behind on every run; it now passes `--volumes`. Found by
  Techtree (2b164bc).

## 2026-09-28 — The signed-in shell lints like every other file

- `.credo.exs` no longer excludes `live/shell_live.ex` from three complexity checks; the
  shell passes them (Credo strict, no issues). Found by Keyfleet, whose split shell no
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
  both new files carry an ETag and a five-minute public cache, as Keyfleet's agent
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


## 2026-09-28 — Motion kit: Keyfleet's four additions (Phase 1 item 53)

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

## 2026-10-03 — Keyboard and screen reader pieces from Keyfleet

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
  apps" panel linking Patchbay, Autolaunch, Keyfleet, Techtree, Protocol
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

## 2026-10-05 — Your funds example

- `/showcase/funds` shows how a person's money looks on every Regent site, from
  the wallet funds plan (`docs/wallet-funds-plan.md`): USDC ready to use on
  Base, funds on other networks with an estimate that is never spendable as one
  amount, USDC committed to Patchbay Offers bids with each bid's rule, a card
  purchase on its way, a quoted move to Base for a bid that is short, adding
  funds by card (Stripe through Privy, in the US except New York and Hawaii),
  sending, cashing out to a bank with a failure that is checked, never resent,
  and the wallet choice. Sample figures; every money button is switched off.
- The payment example now says "Regents does not keep a balance for you" and
  that USDC can be bought with a card.
- Amounts stay in USDC; the "Credits" label is not used (founder, 2026-10-05).

## 2026-10-06 — ash_postgres held at 2.13.0

- `platform/mix.exs` pins `{:ash_postgres, "== 2.13.0"}`. From 2.13.1 (through
  at least 2.14.2) upserts name the schema only from the resource's own
  setting and skip the Repo's default prefix, which is how every Regent site
  picks its schema in the shared production database.
- A `hex` entry in `security/required-fixes.json` now carries `requirement`, an
  Elixir version requirement, instead of `minimum`: existing entries read
  `>= x.y.z`, and the new `2026-10-06-ash-postgres-upsert-schema` entry reads
  `== 2.13.0`. `check_required_fixes.exs` reports a locked version outside the
  requirement. Sites fetch the script and the list from the same commit.

## 2026-10-06 — Pins follow Regents v128

- `@regents_ref` is Regents `004307e65ffcf9cc9b3034d7cc2b015dcd45011b` (live
  as regents.sh v128).
- Every elixir-utils library, siwa and the Jev client included, is pinned to
  one commit, `467cba652f975f8ddbc169dac499d696bcb24248`; the separate siwa and
  Jev pins are gone.
- Ash is `~> 3.34 and >= 3.34.3` (locked 3.34.4), so `mix hex.audit` and the
  required-fixes check are both clean.

## 2026-10-06 — Package rules for coding agents

- `usage_rules` 1.2.8 is a development dependency. `mix usage_rules.sync` keeps
  a marked block at the end of `platform/AGENTS.md`: how to read the locked
  versions' docs (`mix usage_rules.docs`, `mix usage_rules.search_docs`), plus
  links to the Ash, Ash extension, Phoenix, LiveView, ReqLLM, Elixir and OTP
  rule files in `deps/`. The config lives under `usage_rules:` in
  `platform/mix.exs`.
- `mix precommit` runs `usage_rules.sync --check`, so a dependency change that
  adds or drops a rule file fails until the block is synced.
- The required-fixes registry asks for `usage_rules` 1.2.8 or later
  (EEF-CVE-2026-82710).
- `ash-stack`'s docs guide now treats usage_rules as standard. Inside a project,
  search without `-p`: on 1.2.8, `-p ash` searches the newest Hex release and
  `-p ash@<version>` finds nothing.

## 2026-10-06 — Ash review fixes

- The notes, rooms and showcase forms are built from their domain's code
  interface (`form_to_*` from the `AshPhoenix` domain extension) instead of
  naming the resource and action in the LiveView.
- `AshTemplateWeb.FormErrors.messages/1` replaces three identical copies of the
  field-error helper in the chat, rooms and notes pages.
- The showcase sample form shows the plain message under each field instead of
  the full internal error text, and marks the field invalid for screen readers.
- The session lookup sets who is acting when the query is built, not when it
  runs. A comment records why that module keeps `Repo.transaction`: an
  exhausted session lineage is revoked and must stay revoked while the call
  still answers with an error, which `Ash.transact` would roll back.

## 2026-10-06 — Regent Credits

- Adds `regent_credits` from elixir-utils at `f3cfb29`: one prepaid Credits
  balance per Privy account, shared by every Regent site (1 Credit = $1).
  It is listed in `security/required-fixes.json`.
- The site's Oban checks each purchase: USDC on Base (approve, then a deposit
  into REGENT staking), counted at the first block, and USDC on Ethereum (a
  transfer to the Treasury Safe), counted after 12 blocks.
- Parts any site can show: the Buy Credits panel and the balance in the
  header, the account-page notice pointing to regents.sh/account, agent
  spending limits (shown on regents.sh only), the admin page (gifts, purchases,
  refunds) and the refund rules Sean approved.
- `/showcase/credits` (local only) tries every part against local copies of
  Base and Ethereum; the stand-in wallet now serves more than one network.
- Credits balances update on open pages at once: a purchase, a gift, a hold or
  a spend on any Regent site reaches the header and the Buy Credits panel
  without a reload, and a gift to a wallet a signed-in account holds lands on
  the account straight away. Regent Credits pinned to elixir-utils bf4aed7.

## 2026-10-07 — Buy Credits layout

- The Buy Credits close button sits flush in the dialog's top right corner and
  stays there while the dialog scrolls. Its styles moved out of the product
  layer, so the shared button's padding no longer shrinks the icon.
- Regents Credits and Active Bids (was In Bids) show as one two-by-two table,
  labels and figures at one size.
- Approve and Buy take the place of the tick boxes, on the left of each step.

## 2026-10-07 — Wallet presses reach the signed-in wallet

- A signed-in account whose wallet Privy holds but has not marked active now
  sends from that wallet: the bridge selects the one connected wallet the
  account is linked to. Two such wallets stay a choice for the customer.
- A press with no wallet opens Privy's connect window. Privy's active-wallet
  dialog is gone from the bridge: no page rendered it, so those presses did
  nothing.

## 2026-10-07 — The Credits panel keeps its height on every chain

- Picking Ethereum no longer shortens the panel: the Approve row and the Switch
  Chain button keep their space, unseen, when the chain does not use them.
- The UI review checklist now says choosing an option never changes a panel's
  height (design-system STYLE.md).

## 2026-10-07 — Human-backed agents (World ID)

- Each signed agent request keeps the sign-in service's `agentBook` answer on the agent:
  the anonymous World ID number of the person who stands behind its wallet in World's
  AgentBook, and how many agents they back (`world_id_human_id`, `world_id_agent_count`).
  The answer is there only after the wallet accepts that person with
  `regents auth accept-world-id`. A request whose answer is empty clears both.
- In a room, such an agent's name shows a Human-backed tag, with a tip saying a person
  verified with World ID stands behind it and how many agents they back. The number
  itself is never shown.
- Room messages in the API say so too (`author_human_backed`): the public description
  moves to 1.5.0 and the full contract to 2.5.0. The docs, the agent guide and
  `cli/COMMANDS.md` describe it.
- Agents sign in with the sign-in server's own agent client
  (https://siwa.regents.sh/skill.md): the refusal hint, the docs, the agent guide, both API
  descriptions and the command notes point there instead of `regents auth login`, which
  does not carry this site. The docs and agent guide post with the client's own
  `request POST`, `cli/` says its commands are the pattern sites copy, and `rooms post` no
  longer names the page's `room_post` tool, which posts as the signed-in person.

## 2026-10-07 — An agent's World ID person stays for good

- The first person an agent accepts with `regents auth accept-world-id` stays linked to its
  wallet for good, so its Human-backed tag never goes away. A later answer naming nobody,
  or someone else, changes nothing; one naming the same person updates how many agents
  they back. This replaces "a request whose answer is empty clears both" above. Only the
  agent's signed request records it (`Agents.record_backing`), and the World ID number is
  checked there. The docs and the public API description say so.

## 2026-10-07 — Credits help is a link

- When the Buy Credits panel can't match a sent payment to a purchase, it says so and
  links to Credits help (https://patchbay.help/credits-help) to post the transaction.
  The refund rules link to it wherever they name it. support@regents.sh now exists.

## 2026-10-07 — One person cannot use up the day's note labels

- Each person's saves may ask Jev for at most `person_daily_questions` labels a
  day (50), inside the site's `daily_questions` (500). A save past either limit
  still saves, with no label.

## 2026-10-07 — Rooms pages no longer show account numbers

- Each message's author tag on a room page is now random for that page, instead
  of the writer's account or agent number. It still groups one person's
  messages, and matches nothing on any other page.

## 2026-10-07 — Names come from the shared Regent profile

- A person's name is the one set in their shared Regent profile through
  `/profile`, so it shows on this site as soon as it is saved, the same as on
  every Regent site signing in with this Privy app. The old name column in the
  shared accounts table is no longer read.
- Local setup now creates the shared profile table.

## 2026-10-07 — Pair an agent with your account

- The Account page has an Agents panel: Pair an agent makes a one-time code that
  works for ten minutes, the panel lists every agent paired with the account on
  any Regent site, and Unpair ends a pairing at once. The template issues its own
  codes through the agent pairing every Regent site shares (`regent_agents`), at
  `POST /api/agents/v1/pair` and `GET /api/agents/v1/me`.
- An agent paired with a person, and backed by World ID, acts as them: its signed
  requests read and change their notes, and post, change and delete their room
  messages (`PATCH` and `DELETE /api/v1/rooms/{room}/messages/{id}`). It never
  uses their wallet. Every change is marked as the agent's: a room message shows
  Via agent (`via_agent`), and a note says which agent saved it last
  (`changed_by_agent`). Anyone who muted the agent no longer sees what it writes
  for its person.
- An agent that is not paired, or not backed yet, posts as itself as before; the
  notes API and message changes refuse it with 403 naming what it is missing:
  `agent_not_paired`, `agent_not_backed` or `person_not_here`.
- API 1.6.0, contract 2.6.0.

## 2026-10-07 — Keyfleet is spelled Keyfleet

- The apps menu, documents, skills and code comments write Keyfleet, never
  KeyFleet, as its brand spells it (design-system `STYLE.md`, Product names).
- The rename example in `README.md` and `scripts/init.sh` is now a made-up
  two-word product, `night_owl` / `NightOwl` / "Night Owl", so it still shows how
  each spelling of a two-word name is written.

## 2026-10-08 — Sign-in works again

- Signing in raised an error from 5 October: after sign-in saves the account it
  loads the name and picture again, and the account had no primary read to load
  them through. The account now has one, open only to the site itself.

## 2026-10-08 — Components act on the account as it is now

- A component's session check now hands it the account as it reads at that
  moment, and each component rebuilds the wallets and actor it acts with from
  it (`Session.check_component_events/2`), so a wallet taken off the account in
  another tab no longer counts on an open page until it reloads.
- The Credits panel, the wallet buttons, the agents panel, notes, chat and rooms
  do this; the Credits admin and agent-spending parts now take `account` and
  build their actor from it, as regents.sh hands them.
- The Credits and wallet labs act for stand-in accounts, so they pass no session
  lease.

## 2026-10-08 — One sign-in test

- `mix test` signs a person in, then back in with a wallet added, on the local
  `ash_template_test` database, and fails if sign-in raises again. It is the
  template's only automated test.
- `mix ash_template.setup_local_auth` now prepares the test database as well as
  the development one, starting only the database connection, and `mix test`
  runs it first.

## 2026-10-08 — Open account reads in light mode

- The "Open account" button on the signed-in home page showed no words in light
  mode: the app frame gave every link the colour of the text around it, which
  beat the button's own. Links drawn as buttons now keep the button's colour.

## 2026-10-08 — Agents sign with x-siwa-signature

- A signed agent request now carries its signature in `x-siwa-signature` and
  `x-siwa-signature-input`, the names the shared sign-in service checks
  (OpenAPI 1.7.0). The shared libraries move to elixir-utils 1f8670a, which
  changes only those header names.

## 2026-10-08 — Signed headers come from the shared library

- The template no longer names any signed agent header or reads a signed body
  itself. The shared sign-in plug forwards only the signed headers, refuses one
  sent twice, refuses a query string, and refuses a body it did not capture
  whole (`Siwa.AgentAuthPlug.read_body/3`). It also tells an agent's request
  from a person's (`Siwa.AgentAuthPlug.signed_request?/1`). The template keeps
  its own wording for each refusal and one rule of its own: a signed body is JSON.
- The shared libraries move to elixir-utils fe3aa1d, whose signing contract
  (id 53180b09…6060) is the one every SIWA client and verifier follows. It also
  brings Credits' notice that a purchase was credited; the template answers it
  with nothing to add (`AshTemplate.Credits.Credited`).
- `@regents_ref` moves to Regents 81d6200e. An agent's check-in
  (`GET /api/agents/v1/me`) now checks the signature before anything else, so a
  request with a query string is refused (`unsupported_query`) rather than told
  it is not paired. Pairing and check-in answer the shared plug's refusals with
  the same codes as the rest of the site. A person may also hold several live
  pairing codes at once.

## 2026-10-08 — A Credits test

- `mix test` now also credits a Credits purchase through the site's
  `on_credited` module. Without that setting a site never credits a purchase,
  and nothing shows it until a person pays. The template now has two tests.

## 2026-10-08 — Pairing names the right audience and setting

- The OpenAPI description of `POST /api/agents/v1/pair` told agents to sign for
  the audience `regents`. This site checks pairing signatures for
  `ash-template`, so it now says that.
- The README named a setting that does not exist (`:agent_sign_in`) as the place
  the sign-in service's address lives; it is `config :regent_agents, siwa:`.

## 2026-10-08 — regent_points joins the required-fixes registry

- `regent_points` (elixir-utils, sparse `points`) is listed under `managed` in
  `security/required-fixes.json`, so every site that uses Regent Points can pass
  `make check-required-fixes`.

## 2026-10-08 — The sign-in library turns away an answer that is not a verdict

- The shared libraries move to elixir-utils f8a9385. When the sign-in service
  answers a signed request with something other than a refusal or a verdict (a
  200 without one, a redirect or a 1xx), the shared plug now treats it as a failed
  request, so the site answers 503 `siwa_request_failed` instead of repeating the
  service's status. Every site gets this by moving its pin; the template keeps no
  rule of its own for it. The signing contract is unchanged (id 53180b09…6060).
  The move also brings `regent_chain`'s signing with a key the app holds, which
  the template does not use.
- `@regents_ref` moves to Regents ba23ceee, whose `regent_agents` and
  `regent_identity` take the same elixir-utils commit. Agent pairing and
  check-in (`RegentAgents.HTTP`) now answer the library's failed-request refusal
  with `verification_unavailable`, as they did for an unreachable service;
  `regent_identity` is unchanged.

## 2026-10-09 — Regent Points on the Account page, earning off

- The template hosts Regent Points (elixir-utils 8cbd69c, sparse `points`) as the
  reference consumer: configuration with no start time and no approved rules, the
  verified account callbacks (`AshTemplate.Points.Accounts`), the wallet refresh after
  linking, and the `points` and `points_chain` queues. Regents runs the migrations and
  the NFT transfer watcher; the template only reads and awards.
- Credits purchases are Points' first source. `AshTemplate.Credits.Credited` records
  `credits.purchase_settled` inside the credit's transaction, and
  `AshTemplate.Points.CreditsPurchase` checks the committed purchase. Both name the
  source `regents`, because Credits is one Regents ledger on every site.
- `/account/points` shows the person's points, NFT bonus and recent awards, and lists
  only the rules the site has a source for (`RegentPoints.Rules.tracked/0`): today
  Credits bought and the NFT bonus tiers. The `@elixir_utils_ref` move to 8cbd69c
  brings `Rules.tracked/0` and `Rules.daily_apps/1`; nothing else changes for other
  packages.

## 2026-10-09 — Credits are bought on Base only

- The Buy Credits panel buys on Base alone: no chain picker and no Switch Chain
  button. The wallet line shows the paying wallet's USDC on Base, and Buy waits
  on "Not enough USDC on Base" or "Approve first", read from the chain.
- The Credits lab at `/showcase/credits` runs against one local copy of Base
  (`ASH_TEMPLATE_BASE_NODE_URL`). Its stand-in account now carries an id, so
  picking a lab wallet reads its funds instead of stopping the page.
- The wallet hook's Switch Chain handling is gone. A root marked
  `data-refresh-funds` asks for `refresh_funds` when the wallet changes, when the
  page comes back into view and after each press. Each send names its chain
  (`chainId`), so a wallet that checks it refuses one that moved off Base.

## 2026-10-09 — Points NFT bonus at the end of each 30-day period

- Sean, HQ thread, 2026-10-09 04:56Z, item 6: the NFT bonus is no longer saved
  with each award. `/account/points` shows the tier the account's linked wallets
  hold now, read from Base once per page open ("3 NFTs now · +45% at the end of
  this period"), and lists each period's bonus once Regents tallies it.
  Awards show points only. Tiers are 1–2, 3–6 and 7+, adding 20%, 45% and 75%.
- Sean, Points thread, 2026-10-09 ~05:30Z: "1 a 2 at the end of a period, which
  lasts for 30 days. 3 a". The bonus is tallied at the end of each 30-day period
  counted from the program start, not each calendar month; the percentages stay.
- Removed the sign-in holdings refresh (`AshTemplate.Points.TrackWallets`), the
  `points_wallet_holders` account read, wallets in the Credits purchase facts and
  `nft_tracking_enabled`. Regents alone runs the tally; the template adds no cron.

## 2026-10-09 — Points for an agent's first note

- `template.first_agent_note` (10 points, once per person, "First note written by
  your agent") now has a source: when a paired agent acting as its person creates
  a note, the create action asks Regent Points, inside its transaction, to consider
  it (`source_app` `template`, `source_kind` `note`, the note's id). Points'
  check (`AshTemplate.Points.AgentNote`) counts it only while the agent that saved
  it is still paired with the note's writer, and marks the award as that agent's.
  Nothing earns until the rule is approved and the program starts.

## 2026-10-09 — Credits deposits read from Base

- `@elixir_utils_ref` moves to 58acbc4, which reads USDC sent straight to the
  Treasury on Base and keeps each purchase's USDC to the millionth. The site's
  chain client answers the reader's log requests (`logs/2`, `eth_getLogs`), and
  the Points Credits source counts micro-USDC from the exact amount.
- The Credits admin shows each amount as paid ("4.123456 USDC"). A deposit from a
  wallet no account has signed in with yet reads "credited, waiting for an
  account", names no account and offers no Refund until someone signs in with it.
- Locally, `RegentCredits.Migrator.up/1` adds the deposit tables; in production
  Regents runs them.

## 2026-10-09 — Wallet panels keep the account's wallet and ask to switch

- While the wallet app has open a wallet the account does not link, or none, the
  Credits panel and the wallet example keep showing the account's own wallet and
  its figures (`OnchainSteps.shown_wallet/3`, `AccessContext.own_wallet/1`), as
  the onchain-buttons rule says. The note now asks the person to switch: "Your
  wallet is on 0x3c44..93bc, which isn't linked to this account. Switch to
  0xf39f..2266 or 0x7099..79c8." A press from that wallet still sends nothing.
- The Points page's NFT check on Base counts against the same per-account
  `wallet_read` allowance as the Buy panel's reads.
- The wallet example's balance reads count against the visitor's address
  allowance, signed in or out, and run when the wallet changes or a step lands
  rather than on every check. Past the allowance the figure shown stays; one not
  read yet, there and in the Buy panel, reads "unavailable" instead of waiting.
- A confirmed approval fills in the Buy panel's allowance only when the wallet
  shown is the one that approved.
- The wallet line says "Paying from" or "Sending from" only for the wallet that
  can send; the account's wallet shown beside a switch note reads "Wallet".

## 2026-10-09 — A signed-in page re-checks the sign-in before every push

- A page held open past the 30-day sign-in no longer reads or shows fresh
  private figures when a notification (a points award, a Credits change, an
  agent update) or a background read arrives. The session re-reads the sign-in
  before each one; when it has lapsed, what arrived is dropped and the page
  says the sign-in ended. While current, the page continues with the account
  as it reads now.
- Components check the same before each background result as well as each
  event (`Session.check_component_lease/2`, renamed from
  `check_component_events/2`).
- The running jobs count in the bottom bar is the one message that skips the
  check: it says nothing about any account and reaches every open page on each
  job start and stop.

## 2026-10-12 — Review fixes before the template release

- Buy is held back only by a figure read at the latest block for the wallet
  shown. A new read, a read past the allowance or a failed read leaves the shown
  figures on screen but lets Buy be pressed until a new read lands. Opening Buy
  Credits reads the funds again.
- The bottom bar no longer shows the background-jobs count or the version.
  `AshTemplate.JobsRunning`, its broadcast and the session's pass-through for it
  are gone, so every message a signed-in page receives is re-checked.
- `/developers` no longer redirects to `/docs`. Note jobs no longer carry an
  authority version; the pairing check stays. Only signed tools are passed to the
  signed-request client.
- The route handoff names the account tab "Account".
- The header's Credits figure and the Buy panel's figures show only a balance
  just read. While it is read again, or when a read fails after an earlier one
  worked, they show a dash; the button and the panel stay.
- elixir-utils `1f6ce01` (the ENS avatar check no longer follows redirects) and
  design-system `57d2f98` (Credits summary slot, the account heading once).
- The account page's Agents section is the one on regents.sh, and the template
  owns it now. A person chooses their agent from thirteen with logos, copies a
  message holding the pairing code and pastes it to the agent; "Make a new code"
  makes another. Each agent has "See what it has done": when it paired, its last
  contact, its address, whether a verified person stands behind it, its registry
  listing and every request it signed on a Regent site, read from the sign-in
  service with this site's `SIWA_ACTIVITY_READ_TOKEN`, then Unpair. The agent
  guides and refusal hints describe the pasted message.

## 2026-10-12 — Errors reach Sentry

- Crashed processes and failed requests now go to Sentry through its logger
  handler, which the application attaches at start (`config :ash_template,
  :logger`). Nothing is sent until `SENTRY_DSN` is set. Before, only the Privy
  sign-in failure message reached Sentry (Sean, 42 a: every site reports errors
  to Sentry).

## 2026-10-12 — Arrivals play on sight; Points shows ways to earn

- On /animations, the Arriving headline and cards play once, the first time
  they scroll into view, instead of when the page opens; one already in view
  when the page opens is simply there, and Replay still plays it. Lists the
  server draws once (`data-cascade`) settle in the same way. `MotionCascade`,
  the lab entrances and `motion.ts` share `onFirstSight` in
  `hooks/motion/reveals.ts` (Sean, 45 a).
- Until earning opens, the Points page names the ways to earn with no points,
  limits or bonus tiers (Sean, 46 a).

## 2026-10-12 — Sentry events leave without arguments or process state

- `AshTemplate.SentryScrub`, Sentry's `before_send`, clears every stack frame's
  arguments (exceptions and threads) and drops a crashed process's state, last
  message and sender before an event is sent, so a crash in a signing call or a
  page cannot carry a key or the page's assigns. Each site takes it before its
  `SENTRY_DSN` is set (security chief request).

## 2026-10-12 — Errors are kept on the site; Sentry removed

- Failed requests, pages and jobs are saved in the site's own schema by
  ErrorTracker 0.9 (`error_tracker_*` tables in `ash_template_app`) and shown at
  `/admin/errors` to Credits admins only (REGENT_CREDITS_ADMINS); anyone else
  gets the ordinary not-found page. The page runs under its own content
  security policy with a per-request nonce (Sean, 51 and 80 a).
- `AshTemplate.ErrorFilter` keeps only where an error happened: the request's
  host, path and method, the page, component and event names, and the job's
  id, worker, queue, attempt and priority. Headers, addresses, query strings,
  parameters and job arguments are never saved. Stack frames carry no
  arguments. ErrorTracker's pruner clears resolved errors after a week.
- Sentry is gone: the dependency, its logger handler, `AshTemplate.SentryScrub`,
  the Privy sign-in failure capture and the `SENTRY_*` settings. The sign-in
  failure log line and telemetry stay.

## 2026-10-12 — Only server faults are saved

- `AshTemplate.ErrorIgnorer` leaves out every exception the site answers below
  500, such as not found or a bad request, so visiting wrong addresses cannot
  fill the error table. Ash's Invalid and Forbidden errors count as the
  visitor's; Unknown and Framework errors, other server faults, exits and throws
  are saved (security chief request).

## 2026-10-12 — Account page: Credits beside Profile

- Profile and Credits share a row and the agents take the row below, so no
  card stands alone. Sign out lives in the side panel only, so the account
  page no longer has a Session card. The Points page calls its card "Balance"
  under the page's own Points title, and the pairing box asks "Choose the agent
  to pair". Pins design-system `a97eb2b` (Sean, UI-POLISH-1 b).

## 2026-10-12 — Saved errors cleared by age

- `AshTemplate.ErrorPruner`, an Oban cron job at 04:17 UTC, clears every
  occurrence older than a week and every error not seen for a week, whatever
  its status. ErrorTracker's own pruner, now removed, only cleared resolved
  errors, so a fault that kept happening would have grown the tables without
  end (security chief request).
- The motion page ignores a dismiss for a note that is not on screen; a
  non-number id used to crash the page.

## 2026-10-13 — The Regents crown is back

- The favicons, `mark.png` (the picture in the sign-in window) and the flat
  marks in the header are the Regents crown again, the same files Regents and
  Keyfleet serve. The plain square from 2026-09-22 is gone, and `AGENTS.md` no
  longer asks a new site to replace the logo (Sean, 13 Oct: "do not change the
  logo").
- The account card engraves the crown again, as on regents.sh.

## 2026-10-13 — Agent guide on regents-cli 1.9.3, Regents links

- `/agents.md`, `/llms.txt`, `cli/COMMANDS.md`, `cli/README.md` and the tool manifest name
  regents-cli 1.9.3 (source commit `e3b779c1ab0a7314e031ba282d56f6952ab58608`, wheel SHA256
  `64ecda7954bd76e2741e737ac6604ae1b882d471c20c7adf6729cf8122546f34`). The template's
  command list is the same in 1.9.3.
- Pairing keeps the code out of every command line and shell history: the agent writes
  `~/pair.json` (home folder, never inside a project) with its file tool, runs
  `agents pair --json < ~/pair.json`, then deletes the file. This works on 1.9.3 today and every site copies it.
- The X and GitHub icons point at x.com/regents_sh and github.com/regents-ai; every contact
  address on the Contact, Terms and Privacy pages is build@regents.sh (Sean, 13 Oct).
- regent-workflow carries the founder rule that ash-template is the golden generic baseline.

## 2026-10-13 — Agent guide on regents-cli 1.9.4

- `/agents.md`, `/llms.txt`, `cli/COMMANDS.md`, `cli/README.md` and the tool manifest name
  regents-cli 1.9.4 (source commit `e66027f2ba7784f674481c3778c671cc3f1108e2`, wheel SHA256
  `55a1fe2915231cfd27b5ad2725b4236c3bbad0171c2f02f7c3a182464fba2f7f`). The template's
  command list is the same in 1.9.4, and pairing still reads `~/pair.json`.

## 2026-10-13 — Pairing checked again before an agent's answer leaves

- A paired agent's pairing is read again just before the site answers it. If the person
  unpaired it, or paired it again, while the request ran, the answer becomes 403
  `agent_not_paired` and none of the person's data is sent. Copied from Regents
  (`RegentsWeb.Plugs.PairedAgent`).

## 2026-10-13 — Pairing has its own budget

- `POST /api/agents/v1/pair` counts against a `"pair"` budget of 10 a minute per client
  address as well as the default 120, both named in the `RateLimit` headers. Past it, 429
  with `Retry-After`. Copied from Regents (`RegentsWeb.Plugs.AgentRateLimit`).

## 2026-10-13 — Agent refusals say the same thing everywhere

- `agent_not_paired` and `person_not_here` carry one message and hint on every signed
  door (rooms, notes, browser tools, the pairing re-check), from `AgentWallet`.
- `invalid_note` and `invalid_message` also carry `details`: one `{"field", "message"}`
  per rule the input broke, worded as the page's own form shows it. Both contracts list
  `details` as optional on the error.
- An unknown address answered as JSON says "There is nothing at this address." and points
  to the rooms list and `/openapi.json`.
- The browser tools hand back `retry_after` in seconds on a 429, and `room_read` refuses
  `.` and `..` as a room. Copied from Autolaunch (`public_tools.ts`).

## 2026-10-13 — Agent guide on regents-cli 1.10.1

- `/agents.md`, `/llms.txt`, `cli/COMMANDS.md`, `cli/README.md` and the tool manifest name
  regents-cli 1.10.1 (source commit `aab300eed326d1cc37bcc25d03f98ae256fd2638`, wheel SHA256
  `2029c4f63e84aefb4d2df5442c9b0bfa5d8dafd5900fdc726342953b3983db3e`). Its copy of the
  template's command list is the same as this one.
- What to do when a command fails now points at `next_steps`, which ends every answer and
  every refusal from 1.10.0: run it again only after changing what the message names,
  otherwise take the refusal as the answer.
- `make check-cli` checks the command list with regents-cli `aab300e`.

## 2026-10-13 — An agent may post once before it is paired

- An agent signed in with its own wallet, that no person has paired here, may post one room
  message as itself (`author_kind` `agent`). A second answers 403 `posted_before_pairing`
  until a person pairs it; pairing is still needed for notes, Credits, Points and changing or
  deleting messages (PB-GAP-1-TABLE, Sean 13 Oct).
- The site's agent record (`agents`) is the record of a signed-in agent, paired or not: its
  wallet, when it was first and last seen, and when it used its one post. Its pairing is found
  by the same wallet, so the record stays the agent's after pairing. Agents that posted as
  themselves from 4 to 9 October have used their post.
- Posts from agents no person has paired also count against 10 an hour from one network
  (`guest_post_address`), so one network cannot post through many new wallets; past that,
  429 `guest_posts_limited` with `Retry-After`. A refused post leaves the agent's one post
  unused.
- The database fills `last_seen_at` itself, so the release before this one keeps adding
  agents while both run, and after a rollback.
- A lost answer: the `posted_before_pairing` hint and `/agents.md` say to read the room for
  the post's `operation_id` first. The post's API description no longer lists `403` twice.
- `/agents.md`, `/llms.txt`, `/docs`, the API description, the command list and the
  `room_post` browser tool say so.

## 2026-10-13 — Connect your agent at /start

- `/start` gives a person the steps to hand their agent, one tab per agent (Hermes, Codex,
  Grok Bot, Muse, Dots, other), with a Copy button, and serves the same steps as Markdown.
  Copied from Regents v165 (`RegentsWeb.AgentStart`, `AgentStartLive`), with the template's
  commands and the pairing file in the home folder.
- Grok Bot, Muse and Dots pair with the SIWA client reading `~/pair.json` on stdin
  (siwa-agent-client 2.10, served by the sign-in service since 13 Oct).
- The page stays open while the site is closed, is in the Account menu and search, and the
  "Pair your agent" card, `/agents.md` and `/llms.txt` link to it.
- The command-line steps install regents-cli 1.10.1 and tell the agent to follow the "Next"
  step every answer ends with.

## 2026-10-13 — The side bar opens on a phone only when opened there

- On a phone or tablet, where the side bar covers the page, it opens only when the person
  opens it on that page. Opening it on a wide screen no longer covers the next page on a
  narrow one; on a wide screen it still stays open from page to page.

## 2026-10-13 — /start stands on its own while the site is closed

- `/start` is now its own page in the documentation pages' frame, outside the signed-in
  frame, so while the site is closed it shows the steps and nothing else: no search, chat,
  notifications or Credits. It is still in the Account menu and search.
- While the site is closed, a product page left open from before, or reached by live
  navigation, now refuses every event it handles itself, as well as every navigation
  (the `:launch_gate_events` hook, carried from Regents).
- Where the side bar covers the page (below 64rem), a page link inside it closes it and
  opening it moves focus into it; before, that held only below 48rem.

## 2026-10-13 — One capability list for agents

- `/capabilities.json` lists every operation in the API description, one row each: who may
  run it (anyone, a signed agent, a paired agent, the person signed in, or the person's
  wallet), what it needs, whether it is open now and why not, its browser tool, its
  regents-cli command and the earliest release with it, the page where the person sees it,
  and what an agent does with it (runs it, hands it to its person, or waits while it is
  closed). It names the commit the site was built from. `/capabilities`, the old browser
  tool list, is gone.
- The rows come from `priv/capabilities.json`, checked against the API description, the
  browser tool list and `cli/commands.json` when the site compiles; a row that disagrees
  with any of them stops the build. The tool list keeps only what the pages register.
- `/llms.txt` draws its "What an agent may do" table from the same rows, and `/docs` its
  browser tool table.
- "Where you run" is one section, kept in `priv/public/supported-host.md` and the same on
  every Regent site: a shell uses regents-cli, a page with browser tools uses them, and an
  agent with neither tells its person what to do. `/llms.txt`, `/agents.md` and `/skill.md`
  carry it.
- `scripts/deploy.sh` builds the image with its commit (`SOURCE_COMMIT`); a build without
  one stops. `make readiness` checks the new list against the API description, `/docs`,
  `/llms.txt` and the page's script.

## 2026-10-13 — A retry answers the first note or post

- An agent or page tool that sends a new note or a room post again with the same
  `operation_id` now gets the first one back (200) instead of a refusal; nothing new
  is made. Only the actor's own note or post answers: another person's id is still
  refused.
- The OpenAPI documents, agent guide, skill, docs page, tool list and command notes
  say so.

## 2026-10-13 — Home sections say each thing once

- Each home section now has its number, its name, its heading and its three cards. The
  extra line and button under each heading repeated the hero card above, so they are gone;
  the hero cards keep the buttons. The page's Markdown uses the hero card line.

## 2026-10-13 — Small page fixes

- Overview: Notes says "Private notes, just for you"; it never saved as you typed.
- The side assistant says "Not sent. Wait a moment and try again." when a question is
  refused, instead of nothing.
- Chat: when the assistant's reply fails for good, the reply ends with a line saying so;
  the page no longer shows "The assistant is writing…" forever.
- Activity: "Mark all as read" says when some stayed unread.
- The notes notice, the Buy Credits press notes and the wallet lab's press notes sit in
  room kept for them, so nothing below moves when one appears.
- Page links in the shell, the overview and the footer are checked against the router.

## 2026-10-13 — Buy Credits buttons never move

- The amount problem, the wallet line and the wallet-mismatch note above the Buy
  Credits buttons keep their room whether or not they show, so the buttons stay put.

## 2026-10-13 — Each command says who may run it, from the capability list

- `cli/commands.json` gives each command its operation's authority from
  `/capabilities.json`: `signed_agent` for `agents whoami`, `agents pair` and
  `rooms post`, `paired_agent` for the rest, and `notes pin` adds the
  `spending_allowed` condition. `wallet-proof` is gone.
- `make check-cli` runs regents-cli 41da314, which also checks that each
  command sends exactly its operation's body fields.

## 2026-10-13 — An agent's view says what it may do and what it cost

- The account page's agent view answers the questions every Regent site asks
  in the same words: "What may happen next" lists what a paired agent may do
  here, from the capability rows' own words for a person, and "What it cost"
  shows the Credits it has spent for its person on Regent sites.
- The agents list's tip says what a paired agent may do, and each agent row
  has Unpair beside "See what it has done".
- Needs the design-system commit with `agent_detail`'s `may` and `spent`.

## 2026-10-13 — An agent's activity says what each request did

- The agent view's recent activity names each request to this site the way its
  person would say it ("Read your Credits history", "Pinned a note"), from the
  capability rows' own words. A read sent as POST no longer shows as a change.
- A request to another Regent site is worded from its method until that site
  carries the same change. Nothing new is stored, and the sign-in service is
  unchanged.
- Needs elixir-utils with `RegentAgents.Activity.recent/3`.

## 2026-10-13 — An agent's "try again" leaves a trace

- Every agent request the site answers only with "try again" (a 503 from notes,
  rooms, the `/tools` doors or agent sign-in) now logs the request and what failed
  first, through `AshTemplateWeb.UnexpectedFailure`. Nothing the agent sees changes.
- Each trace is one line with its cause on it, and a refused room post logs the
  refusal alone, never what was posted or who posted it.

## 2026-10-13 — Dead code removed

- The second chat page at `/chat/original` is gone, with its link on the Chat page, its
  layout, and the Tailwind, DaisyUI and Heroicons packages only it used. `/chat` is the
  one chat page.
- The unused `AshTemplate.Agents.Pairing` resource is gone; pairing is read through
  `RegentAgents`, as before.
- `assets/js/privy_bridge.tsx` exports only what another file imports.
- The Points settings are written once in `config/config.exs`.
- The README no longer calls the serving database connection pooled.

## 2026-10-13 — The database version is the true one

- The site tells Ash the database is PostgreSQL 17, which it is, instead of 14.
  Upserts keep their current statement through AshPostgres's own setting
  (`upsert_with_merge?: false`), because its newer one leaves out the site's schema.
  Nothing a visitor or an agent sees changes.

## 2026-10-13 — A person's details that cannot be saved no longer fail an agent's request

- When the sign-in service names the World ID person behind an agent and saving
  that fails, the agent's signed request goes on as before instead of answering
  "try again" (a 503). Nothing decides what an agent may do from that saved copy,
  and the agent's next request saves the same thing.
- The failure is logged by its kind alone, never its words, which could hold the
  person's number.

## 2026-10-13 — Closing the sign-in window says nothing

- A person who closes the sign-in window chose to, so no line appears under the
  Sign in button. Before, it read "Sign-in closed before completion. No account
  was connected." The button stays ready for another press, as it did.
- A sign-in that fails for any other reason still says so and offers "Retry
  sign-in".

## 2026-10-13 — Signed-in pages stop re-reading the session for every background update

- A signed-in page read the same session and account rows from the database again
  for every background result and every live notice it received, three reads each
  time. It now reads them when the page opens, on every navigation and on every
  press, which is when a person acts. In a trial, five results and five notices on a
  page and five results in a panel cost 45 reads before and none after.
- Background results and notices are held against the instant the sign-in ends,
  read when the page opened. From that instant each one is re-read as before, and a
  sign-in that has ended drops it and the page shows signed out.
- Signing out still closes that browser's open pages at once, through the notice
  the site already sends them. So this rule is for a site whose servers all
  receive that notice: a site running one server does, and a site joins its
  servers together before it runs a second one.
- A sign-in elsewhere that changes or withdraws the account's wallets now reaches
  the account's other open pages at once, and each reads the session again.
- `SessionAuthority.resolve/1` answers `{lineage, account, lapses_at}`.
- The shared note `skills/ash-security/references/component-session-check.md`
  describes the rule every site copies.

## 2026-10-13 — Figures every visitor sees alike are read once and shared

- New rule for all five sites, in `skills/ash-frontend/references/public-figures.md`:
  a figure that is the same for every visitor is read once and handed to every open
  page, instead of each page reading it again on every notice. A public saved row
  sends its public fields, named one by one, through its own publication. A figure
  no saved row carries, or one built from many rows, goes through the new
  `AshTemplate.SharedReading`. Anything that differs by viewer is still reread for
  that viewer, as before.
- `AshTemplate.SharedReading` holds one copy of each such figure with when it was
  read and whether the last attempt failed, and wakes a page only when the figure
  or that mark changes. Each kind of figure is a reviewed entry stating why
  everyone may see it, how many it may hold and how large one may be. It never
  disables or delays a wallet button.
- `AshTemplate.ChainHead` reads Base's newest block every two seconds, once for
  everyone, and `/showcase/figures` ("Live figures") shows it as the worked
  example. It reads "Live" with the block number, or "Behind" with the last block
  it had while Base cannot be read. The readers run only where the site serves
  pages, and the site starts whether or not Base answers.
- The same guide sets the memory budget for an open page (0.5 MB, so 2,000 pages
  fit a 2 GB machine with half kept free), how to measure it and what fills it;
  the rule for pages that ignore notices not meant for them; and what a second
  machine needs first.
- `skills/elixir-stack` names the two processes that may reread on their own: a
  supervised reader of an outside clock, and a reread on notice at most once a
  second.
- `AshTemplate.ChainClient.rpc/4` takes the caller's own time limits. As before,
  it never retries.
- New measurements: `health.shared_reading.oldest.seconds` and
  `health.shared_reading.degraded.total` by kind, and
  `ash_template.shared_reading.keys`, `.table.bytes` and `.refused.total`.
- The template's own room messages still send the whole message to open pages;
  the guide says so and that it is not the example to copy.

## 2026-10-13 — Shared figures: five faults from Fly Sentinel's read, fixed before any site copies it

- A measurement taken in the instant the shared figures' table is being restarted
  is skipped, where before it would have stopped being measured for good.
- New measurement `health.shared_reading.never_read.keys`, by kind: keys that have
  had no reading since the site started. Their age read as 0, which looked
  healthy. Every kind is now reported every ten seconds, so a kind whose keys are
  all gone reads 0 instead of keeping its last number.
- A reading is checked where its producer hands it over, so a reading that cannot
  be checked stops its own producer and never the table everyone reads.
- A failed read of the newest block is counted under its own name, `chain_head`,
  where before it counted as wallet trouble. `AshTemplate.ChainClient.rpc/5`
  takes the caller's name.
- A page that subscribes with a key the site does not have is refused at once,
  the same as a fetch.
- The guide adds: a kind built from rows names the resource and the read a
  signed-out visitor is allowed; and the first figure that is reread on notice
  lands in the template before any site builds one.

## 2026-10-13 — Each open page's connection gives its memory back

- The site's live-page connection now sets Phoenix's `fullsweep_after: 0`. The
  process behind each open page's connection kept the memory it used to send the
  page for as long as the page stayed open. On Autolaunch's practice site with 50
  pages open, that process went from 1.67 MB to 0.09 MB and a whole open page
  from 2.94 MB to 1.43 MB, with no processor cost that could be told from noise
  (its chief's measurement, 13 October 2026). Nothing a visitor sees changes.
- `skills/ash-frontend/references/public-figures.md` names it as the standard for
  every site's endpoint.

## 2026-10-13 — How long the oldest background job has waited

- New measurement `health.job.oldest_age.seconds`, by queue: the age of the
  oldest waiting, running or retrying background job in each running queue, 0
  when there is none, taken every ten seconds. A paused queue is left out,
  because it holds its jobs on purpose. It is the row Fly Sentinel's site watch
  reads on every site, in the same name and shape Autolaunch already sends.
- The site's own periodic measurements (this one and the shared figures') run in
  one poller started after the background jobs. A tick the database or the table
  cannot answer is skipped, and the next tick measures again.

## 2026-10-13 — The site's own measurements can no longer stop for good

- The background-job age was dropped until the next restart when a queue was too
  busy to answer within five seconds, or when the database pool was restarting,
  and its row then kept its last number: the alarm went blind when it mattered.
  Whatever stops a reading now is logged and that reading is skipped; the next
  one, ten seconds later, measures again. Fly Sentinel found it.
- The shared figures' measurement is skipped the same way when its table goes
  away between its two reads.
- `AshTemplate.ChainClient.rpc/5` refuses a caller's name that is not text, so
  timeouts handed over in its place cannot end up as a measurement label.
- The job-age row's description says the age counts from when the job was added,
  so a job waiting out a long retry reads as old.

## 2026-10-13 — An ENS picture no longer goes missing after a quiet hour

- A person's ENS picture was replaced by the generated one whenever the ENS
  picture service was slow to answer at sign-in, which it is for any name it has
  not been asked about in the last hour (4.3 seconds measured for one picture;
  the check gave up at two). The shared ENS library now waits ten seconds, and a
  service that does not answer counts as "ask again" instead of "no picture", so
  the stored picture stays and the sign-in's background job tries again.
- No change to the site's own code beyond the note on the lookup; the fix is in
  the shared library this release pins.

## 2026-10-13 — Shared figures: four things from Autolaunch's first use

- Measuring the shared figures every ten seconds no longer copies them: it reads
  each key's kind and when it was read, nothing else. With thousands of large
  readings the copy was the cost.
- New measurement `ash_template.shared_reading.woken.total`, by kind: wake-ups
  sent to open pages.
- The guide adds: a producer that records what it reads writes its rows before
  it stores the reading; a producer's cost is keys times passes whether or not
  anyone is looking, and is bounded on purpose; and a field that only says when
  a reading was taken is compared out by the producer so it wakes nobody.

## 2026-10-13 — ENS lookups run in their own queue

- A person's ENS lookup at sign-in now runs in its own queue, `ens`
  (three at a time), instead of sharing `outside_calls` with the site's other
  slow calls. A crowd signing in at once, each lookup taking seconds for a name
  with a picture, no longer makes those other jobs wait behind it. Lookups
  already waiting in `outside_calls` at release still run from there.

## 2026-10-13 — Guides: three lessons from Autolaunch and Keyfleet

- Shared figures guide: measure a producer at a production provider's pace and
  pin each pass to one block by its hash; a kind's size limit is also a cost
  for every page showing it; Autolaunch's pass numbers corrected.
- On-chain buttons skill, rule 10: a step that names several items names only
  the ones the contract will take, since one refused item reverts the whole
  call.

## 2026-10-14 — Shared libraries moved up; a release refuses while a shared database change is missing

- The site now uses the shared libraries as pushed on 14 October: the ENS
  picture fix (a slow or refusing picture service is a failed read that is
  tried again, never "no picture"), Credits history as one entry for each
  thing that happened, the Credits team's view of one person, and Sean's
  13 October Points rules.
- A release now refuses to start while the shared Credits or Points tables are
  behind the code it carries, and names every missing change. Before this, a
  site could go live on new library code against old tables and fail every
  Credits hold. Regents applies those shared changes; every other site only
  checks. This release needs Credits change 20261013202732 in production first.
- Points page, "Daily limits": one row, "You and your agents", with the one
  shared daily limit, in place of the two rows for the old separate limits.
- Credits team page: the sentence for a refund refused because the account had
  used Credits is gone; the library no longer gives that reason.
- The ENS lookup queue is named `ens`, the name Keyfleet already runs.

## 2026-10-14 — A page can leave out the "Sending from" line

- Under wallet buttons, the line naming the wallet a press is sent from, with
  its balance, is still shown by default. A page that already says which
  wallet acts can now leave it out (`names_sender={false}` on the wallet
  example), as Keyfleet does on its Key pages; the balance is then not read
  either. Sean's decision of 14 October: on by default, off for a page.

## 2026-10-14 — Your picture's place is never empty while an ENS picture arrives

- In the top bar, the side rail and on the account page, the coloured squares
  drawn from your wallet now show the moment the page does. Your ENS picture
  arrives from another website (a large one can take seconds) and covers the
  squares when it is there. Before, the place stayed empty until it arrived.
- A see-through ENS picture never shows the squares behind it: they are hidden
  once the picture has arrived.

## 2026-10-14 — One connection can hold 40 live pages open

- Every open page of the site keeps a little of the server's memory for as
  long as its tab stays connected. One internet address can now hold 40 open
  at a time. The next one is sent to a plain page that says "Too many pages
  open from this connection. Close one and try again." Closing a tab frees its
  place at once. Sean's decision of 14 October (40, with these words).
- Before this, one address could open pages without end and take the server's
  memory from everyone else.
- The count is kept on each server, so an address spread across two servers
  can hold 40 on each. Each refusal is counted
  (`health.open_pages.refused.total`).
- Every live page now carries the visitor's address key from its first
  render; the homepage, the agent start page and the motion lab did not
  before. A page added without it fails to open rather than going uncounted.

## 2026-10-14 — A failed ENS lookup leaves a saved record of why

- When the ENS name or picture cannot be read after three tries, the reason
  now reaches the site's saved errors. Before, it was filed the way a visitor's
  bad input is, which saved errors leave out, so a lookup could end as failed
  with nothing saying why. Found by Sentinel; the same fix Keyfleet made for
  its close-up pictures.

## 2026-10-14 — An agent's Credits history pages like every other read

- An agent reading its person's Credits history now gets
  `{"entries": […], "pagination": {"has_more", "next_cursor"}}`, the same
  paging as the rooms read, in place of `more?` and `next`. It sends the
  previous page's `next_cursor` as `after` for older entries, as before.
  Agents meet one paging shape on every read. Pages for people are unchanged.
- In the command tool the cursor is now a flag, `--after CURSOR`, in place of a
  field typed on standard input, so the tool can offer the next page itself.

## 2026-10-14 — Room activity: a live figure counted from the site's own rows

- The Live figures page (`/showcase/figures`) now shows each chat room's
  message count and the time of its newest message. One counter counts a room
  again within a second of a post or a delete, once for everyone; every open
  page shows that one copy. Sean's decision of 14 October.
- It is the worked example of the second way to keep a shared figure: counted
  again when the site's own rows change. Before, the template only had the
  first way (a figure read from outside on a timer).
- A change notice can be lost, so once a minute the site's schedule asks for
  every room to be counted again. The same pass keeps a quiet room's figure
  fresh, so a quiet room never looks like a stopped counter.
- Every kind of shared figure now states how soon a working reader refreshes
  it, and `health.shared_reading.late.keys` counts the figures older than
  that, so one alarm serves every kind.
- The count is of every message in the room, as a signed-out visitor could
  count them. It does not change with what one reader has muted.
- A live view drawn inside another is not counted as an open page of its own
  (the 40-page limit); one drawn inside a plain page is.

## 2026-10-14 — The pre-release listing names shared changes that are not applied yet

- `/app/bin/pending-migrations` now also prints `shared-pending:` with each
  shared Credits or Points change the release needs that the shared database
  does not hold yet, as schema and version. Before, the listing could print
  `none` and the release would then be refused for a shared change it had not
  mentioned.
- The listing and the refusal read one list, so they cannot disagree. `none`
  now means the release has nothing to apply and nothing to wait for.

## 2026-10-14 — The local release rehearsal builds again

- `make release` stopped at the image build since the capability list began
  reading the command list when the app compiles and naming the commit and
  image it runs: the rehearsal handed the build the app and the skills but not
  that one file, not the commit, and started the server without an image
  name. It now hands over what a real release (`scripts/deploy.sh` on Fly)
  does. A real release was never affected.

## 2026-10-14 — Chat rooms publish named fields, and a late notice never overwrites a newer one

- A room's posts and edits are now published as a short list of named fields,
  the ones a signed-out visitor can read, on a topic whose name starts with
  `public:`. Before, the whole saved message went out. Nothing private was in
  it, but a field added later would have been published without anyone
  deciding so. Sean's decision of 14 October.
- Two changes to one message can reach an open page in either order. The page
  now keeps the newer: an older edit arriving late changes nothing, a message
  deleted stays gone, and an edit that arrives before its own post is shown at
  the bottom of the room.
- A message written by an agent the reader muted, on its person's behalf, is
  now left out as it arrives. Before, it showed until the page was reloaded.
- Sites that copy the template's rooms take the topic name
  (`public:room:<room>`) and the page together.

## 2026-10-14 — Shared figures: a page can stop listening, and a producer can see what it holds

- `AshTemplate.SharedReading.unsubscribe/1`: a page that stays open while it
  moves between lists stops being woken for a figure it no longer shows.
- `AshTemplate.SharedReading.ids/1`: the keys held for one kind, so a producer
  whose keys come and go deletes the ones that ended without keeping its own
  list. Before, a producer that restarted alone could leave a key behind for
  good, counted as late.
- The rule page now says how a figure in words that age with the clock is
  shared: the producer writes the words, and pages wake when they change.
  Asked for by Keyfleet's chief for its fleet pages.

## 2026-10-14 — The privacy page names the ENS picture service

- When a wallet has an ENS name with a picture, the visitor's browser loads it
  from the ENS avatar service, which can see their internet address and ENS
  name. The privacy page now says so (version 1.2). Sean's decision of 14
  October.

## 2026-10-14 — Measurements: a reporter that holds nothing between reads, and exact totals

- The site's measurements now go through Peep, which keeps a fixed set of
  counters for each series. Before, the reporter kept every timing in memory
  until something read the measurements, so a site nobody read grew without
  limit. Sentinel's finding; Sean's decision of 14 October.
- Four series are renamed to whole-number units so their running totals are
  exact: `health_db_queue_seconds` is now `health_db_queue_microseconds`,
  `ash_template_jobs_duration_seconds` is `ash_template_jobs_duration_microseconds`,
  `ash_template_jev_duration_seconds` is `ash_template_jev_duration_microseconds`,
  and `ash_template_jev_cost_usd` is `ash_template_jev_cost_nanodollars`
  (billionths of a dollar). A $0.50042 total reads 500420000. Bucket bounds are
  the same amounts in the new units. Every other series keeps its name and value.
- A bucket counts an observation equal to its bound, as Prometheus defines it.
- A label holding a line break is now written as `\n`. Before, it broke the line.
- Sites that copy this take all four renames together and update any alarm or
  chart that reads them.

## 2026-10-14 — The apps menu hangs from its button, and "$REGENT Staking"

- The Regents Labs apps panel now opens straight under the nine-dot button,
  its right edge lined up with the button's; on a phone it spans the screen,
  still under the button. Before, it sat at a fixed spot near the corner and
  looked detached wherever the button was not there. Sean's word of 14 October.
- The tile that read "Protocol" now reads "$REGENT Staking". Its link is
  unchanged.

## 2026-10-14 — Sign in with Google and the other choices the Privy dashboard offers

- Someone who signs in with Google, email, a phone number, another social
  account or a passkey now gets a Privy Ethereum wallet of their own at once,
  linked to their account, so they can do everything a wallet sign-in can. The
  site never limited the choices; this makes sure every account has a wallet,
  whatever the dashboard's own wallet setting says. Sean's decision of
  14 October ("1. a").
- It is an ordinary wallet, never a Privy smart wallet, so SIWA checks its
  signatures without asking the chain.
- Sites that copy this drop any `loginMethods: ["wallet"]` they pass to Privy
  and add the same `embeddedWallets.ethereum.createOnLogin`.

## 2026-10-14 — Each site chooses which name a person is shown by

- A person with both a chosen display name and an ENS name is shown by the one
  the site's `:name_first` setting puts first: `:chosen` (the template's
  choice) or `:ens`. With only one of them, that one; with neither, the short
  wallet address. Sean's word of 14 October: both, and each site chooses.

## 2026-10-14 — Credits history, for each person and for the team

- A new Credits tab under Account (/account/credits) lists everything that
  changed the person's Credits on every Regent site, newest first: purchases,
  gifts, Credits set aside, spent and returned (each with the site's name), and
  refunds, each with its date and time. Fifty show at first; "Show older"
  adds the next fifty. The list follows every change as it lands. Sean's
  decision of 14 October ("3. a").
- The Credits admin page has a new part, "A person's Credits history": a Credits
  admin enters a Privy account id and reads that person's history exactly as
  the person sees it.
- The entries and their words come from Regent Credits, so every site that
  copies the page shows the same thing the same way.

## 2026-10-14 — A component's own button and field styles always apply

- The site's default look for buttons and text fields (a box with a border)
  now sits in the lowest style layer, `regents-base`, declared first in
  `platform/assets/css/app.css`. Before, it sat outside every layer and beat
  every component rule in `regents-product`, so some buttons lost their own
  colours.
- Plain buttons look exactly as before. These now show their own design:
  the motion lab's choice strips (the chosen one is filled in), its tabs,
  menu, close and notice buttons; the showcase's "Reset this palette" and
  "Use automatic color" text buttons; the account panel's other-sign-in
  links; and the "Retry sign-in" button.
- A page that set colour variables on a button only to get past the default
  look can use plain colours instead. Sites copy the two changes in
  `app.css`.
## 2026-10-13 — Three worked examples on vgpu 0.6

- `/animations/cube`: a slowly turning cube with a room behind each of its six sides, one
  per world. Drag to turn it, click a side to step in, and follow the room's link in a new
  tab. It keeps turning while the pointer rests and holds still only while pressed.
- Each of the cube's rooms holds three panes of frosted glass, each with a few words about
  that world, shown one at a time for where the visitor looks: the first for a look to the
  left, the third for a look to the right, the second for a look up that is held. A tap
  looks where it lands and stays there. A pane carries no link and no status words; it
  describes the world. A world lists its panes as `cards`; a world without them has an
  empty room.
- The room's own card is a bar along the foot of the stage with the world's link, and
  stays for as long as the visitor is in the room.
- With the cube drawn, Tab still reaches every world's link; the card of the link in focus
  shows over the stage.
- The Patchbay room is a great hall: a switchboard filling the far wall with cords slung
  across it, rows of desks facing it, and a planet in the night beyond the glass above.
- `/animations/foil`: five foil cards side by side, each catching the light as the pointer
  crosses it.
- `/animations/crown`: the glass crown every site shares, in `platform/assets/js/crown/`.
  A site copies that folder, the `Crown` hook and component, and keeps one file of its own
  (`platform/assets/js/crown_looks.ts`) for where the crown sits, its glass, its beams and
  what is drawn behind it.
- The crown's beams lean a little toward a colour of their own for the quarter of the stage
  the pointer is in, and ease back when it leaves. A look names the four colours; a look
  without them keeps one colour.
- A visitor who asked for less motion gets the crown as one composed shot, drawn once and
  left alone. Where the browser cannot draw it, the still picture stays.
- The motion lab links the cube, foil and crown pages, and the sitemap lists them wherever
  it lists the motion lab.
- `vgpu` and `@vgpu/wgsl` are 0.6.0.

## 2026-10-14 — Twin cubes

- `/animations/twin-cube`: the world cube on the left of the stage and a code cube beside it
  on the right. Each of the code cube's six sides runs its own falling code, in its own
  colours, glyphs and background: regents.sh, patchbay.help, techtree.sh, autolaunch.sh,
  keyfleet.ai and siwa-server.
- A click on a side opens a card that scrolls: the browser tools that site offers on its
  home page (every Patchbay tool), or, for siwa-server, the four steps to connect an agent.
  The X or Escape closes it.
- While the pointer is on either cube, "Human Browsing" and "Agentic WebMCP" show over
  them. Where nothing hovers, both names stay shown.
- The page offers six browser tools, `show_<site>_webmcp_tools` for the five sites and
  `show_siwa_connection_help`, each opening the same card a click would.
- Each tool in `priv/tool_manifest.json` now carries a `scope`: `site` for the tools every
  page offers, `/animations/twin-cube` for the six that only that page offers. Every page
  registers only the `site` tools; the twin-cube page registers its own six.
- `GET /api/v1/site-tools/:site` answers with a site's tool list, read from that site's
  capabilities and kept for 24 hours, or with the siwa-server steps. Only one read of a site
  is ever under way; requests that arrive meanwhile wait for its answer, so a burst of
  requests asks each site once. A read still under way after 10 seconds is stopped and
  counts as a failed one. The address is in `/openapi.json`, the API contract and
  `priv/capabilities.json` (`getSiteTools`, a public read), with its `site_not_found` (404)
  and `site_unreachable` (503) answers.
- The world cube can sit off the stage's centre: `--world-cube-centre` on `.world-cube`.
- Either cube can draw smaller than its stage: `--world-cube-size` on `.world-cube` and
  `--code-cube-size` on `.code-cube`, 1 by default. regents.sh draws both at .85, and at .66
  on wide screens, to leave room for their names above them.
- A site that shows the code cube copies `CodeCube` (the cube, its six faces and their card),
  `code_cube.css`, `platform/assets/js/code_cube/`, the `CodeCube` and `TwinCube` hooks and
  `SiteTools` with its `SiteTools.Reads` task supervisor, and lists the six tools in its own tool list with the scope of the page that
  shows them. The page places the cubes and owns the read behind the card.

## 2026-10-14 — A room post shows its author's picture, and its menu is never cut off

- Each post in a room shows the same picture as its author's account: the
  squares drawn from their wallet, and their ENS picture over them once it has
  arrived. An agent's posts show its own wallet's squares. Only the picture
  leaves a person's account, but every reader of the room, signed in or not,
  now receives the address of the author's ENS picture with each post, and
  that address names their ENS name, which anyone can look up to their wallet.
  Sean asked for the account picture on posts in his room check of 14 October.
- A post's "…" menu now opens above everything else on the page, hanging from
  its button, so the bottom edge of the conversation no longer cuts off Edit
  and Delete. When the window has no room below, it opens upward. It closes on
  Escape, on a press anywhere else, and when a choice is made.
- The account picture now takes its squares and picture directly
  (`Shell.account_picture`), so a site can draw any account's picture with it.
  Sites copy the four changes in `rooms_live.ex`, `rooms.css`,
  `conversation.ts` and `Rooms.Message`.

## 2026-10-14 — The foil cards draw on vgpu 0.6

- The design system pin moves from `10a05c4` to `8ecffe8`. Its foil card
  (`holographic_card.mjs`) now prepares its shader the way vgpu 0.6 asks, so the
  five cards on `/animations/foil` draw again; at `10a05c4` they quietly kept
  their still picture. The pin also lets the design system's own showcase run
  locally. Sites that move to vgpu 0.6 and use the foil card need this pin or
  later in the same release.

## 2026-10-14 — A twin-cube card names its count in its title and opens the site's guide

- A code-cube card's title is now the site and its count in one line, for
  example "techtree.sh : 11 WebMCP Tools" ("siwa-server : Connect an agent" for
  siwa-server); the small line above the title is gone.
- Beside the close button, a small "Open agents.md ↗" opens that site's agent
  guide (for example https://techtree.sh/agents.md) in a new tab; siwa-server's
  says "Open GitHub ↗" and opens https://github.com/regents-ai/siwa-server.
  Each face carries the page its card opens (`CodeCube.faces/0`, `:link`).
- The card is a little wider (46rem) so the title stays on one line beside the
  two buttons; on a phone the title sits under them. Sean's notes of 14 October.

## 2026-10-14 — Ash 3.36, AshOban 0.10, and site events as Ash signals

- Ash moves to 3.36 and AshOban to 0.10. Oban stays on 2.24.
- What one part of the site tells the rest is now an Ash signal, and each part
  that cares listens for it, inside the same transaction, so something that
  rolls back tells nobody:
  - a room post is `:message_posted` (`AshTemplate.Rooms.Signals`), and
    Activity writes the mention notifications;
  - a note save is `:note_saved` and a new note `:note_created`
    (`AshTemplate.Notes.Signals`); a label question listens to the first and
    Points to the second;
  - Credits purchases reach Points through `RegentCredits.Signals`
    (`:purchase_credited`, `:purchase_attributed`) instead of the
    `on_credited` setting, which is gone.
- Points listens through `AshTemplate.Points.Award`, in its own small domain.
- The dev server reloads signal changes (`reloadable_compilers`).
- The build skills (`skills/ash-backend`) carry a table for choosing a direct
  call, a signal, a signal run as a job, an AshOban trigger or a PubSub notice,
  with the rules for each.
- The template now needs the shared Elixir libraries at their Ash 3.36 commit.
  Sites copy this after the template is released.

## 2026-10-14 — An `ash-signals` skill: how a site moves onto signals

- `skills/ash-signals` is the guide a site follows to adopt Ash signals as the
  template has: the template's signals and who hears each, the order to adopt
  them in (versions, the compiler, Credits' signals in place of
  `on_credited`, each site event, policies, the walk that checks them), a
  listener copied from `AshTemplate.Points.Award`, and the rules for writing
  one. Sean's ask of 14 October.
- The rules for writing a signal move there from `ash-backend`'s
  integrations guide, which keeps the table for choosing between a signal, a
  direct call, a trigger, a notifier and an event log.
- `ash-stack` routes to it, and the site serves it with the other build skills.
- The template's shared libraries move from a844a83 to elixir-utils 9db13eb,
  where they run on Ash 3.36 and Credits sends its signals.

## 2026-10-14 — A Buy Credits button on the Credits page

- The Credits page (`/account/credits`) shows a "Buy Credits" button beside its
  title while signed in. It opens the header's own Buy Credits panel, the same
  one the header balance opens, so there is one way to buy. Sean's ask of 14
  October, from the Regents Credits page.
- Any button marked `data-credits-open` opens that panel (`shell_panels.ts`).

## 2026-10-14 — A Design section in the left column

- The left column has a Design section, before Account. Its page (`/design`)
  and its sidebar list the design pages: Components (`/showcase`), the motion
  lab (`/animations`), World cube, Twin cubes, Foil cards and Crown. Each opens
  its own full page. Sean's ask of 14 October ("they should be in the sidebar
  under 'Design'"); the motion lab is the "animation studio" he meant.
- The section is there while the design pages are: a site with the showcase
  off (`ASH_TEMPLATE_SHOWCASE=off`) shows no Design entry, and `/design` is
  the site's 404.
- `AshTemplateWeb.RouteCatalog.design_pages/0` holds the list, and the route
  handoff (`priv/handoff/route-catalog.json`) carries the new route.

## 2026-10-14 — What Credits buy, on the Credits page

- The Credits page lists what Credits buy, for everyone: Patchbay, a bid for
  an Agent Offer (linked to Patchbay's how-it-works page), and on this site a
  note your agent pins. Each row names its site and links to where it happens.
  Sean's ask of 14 October, and his choice that the list lives on the
  template's page (CREDITS-USES-HOME b).
- A site copying the page keeps the other sites' rows and puts its own uses
  in place of the template's pinned note.

## 2026-10-14 — A balanced footer

- The home page footer sits on one line: the site links on the left, the social
  links centred on the page, © on the right, all on the same middle line, with
  slightly larger text (15px). On a phone the three stack, each centred, with
  even gaps. Sean's ask of 14 October ("the footer looks off in its spacing /
  symmetry. the text can be larger"). The markup is unchanged; the rules are in
  `platform/assets/css/pages/home.css`, and regents.sh copies them as they are.

## 2026-10-14 — A View link on each Credits purchase

- On the Credits page, each Credits purchase in the history has a "View" link
  after its time. It opens that payment on its chain's explorer (Basescan or
  Etherscan) in a new tab. Sean's choice of 14 October (CREDITS-PAGE-MOVE a),
  so regents.sh can take this page whole.
- `AshTemplateWeb.CreditsHistoryLive.transaction_url/2` builds the address from
  the purchase's chain and its saved payment hash, and the operator Credits
  panel uses the same function.
- The link shows once the shared account history (design-system `ba76912`,
  "a row may carry one link") is pinned; until then the rows read as before.

## 2026-10-14 — No View link on a purchase without a saved payment

- Credits bought before signing in, and a purchase whose payment record is
  missing, have no chain or payment hash. Their history rows now show without a
  View link, where before the Credits page failed for that account. Found by the
  orchestrator's check of the View link before release.

## 2026-10-14 — The shared account history carries the View link

- The template uses design-system `ba76912` ("Account history: a row may carry
  one link"), so each Credits purchase with a saved payment now shows its View
  link.

## 2026-10-14 — Compact world cube on phones

- Bound the phone world-cube stage to 32–38rem using the stable viewport height.
- Keep fallback links in a scrollable list within the same stage; retain desktop sizing.

## 2026-10-15 — A sign-in ends 30 days after it was made

- A sign-in now ends 30 days after the person signed in, however often they come
  back in between. Before, each visit that refreshed the sign-in started the 30 days
  again, so an account used every week stayed signed in indefinitely (Sean, 15 Oct,
  decision 2a: every site follows this rule).
- Sign-ins already open when this ships count from their most recent refresh.

## 2026-10-16 — Agents see N WebMCP Tools

- The app's bottom bar, and the home page beside "Open the app", now say "Agents see
  24 WebMCP Tools", counted from the site's own tool list (Sean, 16 Oct). Pressing it
  opens a list of every tool with its description and a "Copy as Markdown" button,
  closed with its X, Escape or a press beside it. A phone shows "24 WebMCP Tools".

## 2026-10-16 — Regents Products

- The menu behind the nine dots is now headed "Regents Products", and its button
  says the same (Sean, 16 Oct; it was "Regents Labs apps").

## 2026-10-16 — The home cubes no longer show their list after 2.5 seconds

- The home cubes' lists no longer appear on their own after 2.5 seconds while the
  page is still deciding whether the cube draws (Sean's call on regents.sh, which
  shipped without it in v188). The list still fades in where the cube cannot draw,
  and shows from the start without scripts or for a visitor who asked for less motion.

## 2026-10-16 — The side panel pairs agents and slides in

- The right side panel now holds the box to pair an agent, the same one the Account
  page shows: choose the agent, copy the message with its code, "Make a new code",
  and the agent's name in place of the code as soon as it pairs, on any Regent site.
  Below it, "Manage Agents" opens the Regents account page at its agents (Sean, 16 Oct).
  The link carries no wallet or sign-in, so Regents asks the person to sign in there.
- The Help section and the "Pair your agent / How it works" card are gone from the
  panel; Help stays in the bottom bar.
- On a wide screen the panel slides in beside the page, which narrows to make room,
  and slides out the same way. On a narrower screen it slides in over the page's edge.
  A visitor who asked for less motion sees it open and close at once.
- The Account and Sign out buttons in the panel no longer break mid-word.

## 2026-10-16 — One footer, at the foot of the screen

- The home page and every public page share one footer, Autolaunch's (Sean, 16 Oct):
  X and GitHub, Buy $REGENT, Docs, About, Contact, Privacy, Terms and "© 2026 Regents
  Labs" (`Layouts.product_links/1`, class `regent-footer`). Public pages keep the theme
  switch beside the social links; the home page, always dark, has none. The home page's
  own footer and the old "Project links" footer are gone.
- On a short public page the footer sat just below the screen, because the page above
  it was a full screen tall by itself. The page and its footer now fill the screen
  together and the page grows to meet the footer, so it sits at the bottom of the screen
  however short the page is. The app's bottom bar is unchanged.

## 2026-10-16 — Regents Products lists products only

- Account is no longer in the Regents Products menu: it is not a product, and the
  signed-in side panel already has Account beside Sign out, and Manage Agents.

## 2026-10-16 — Dependency wave 1: Bandit from Hex

- Bandit comes from Hex again, `{:bandit, "~> 1.13"}` at 1.13.1, which carries the
  HTTP/2 fix (EEF-CVE-2026-105659) the template had pinned from upstream Git. The
  required-fixes registry now asks every site for Hex Bandit 1.13.0 or later and no
  longer lists Bandit's Git source, so a site still on the Git pin fails
  `make check-required-fixes` until it copies this change.
- ash 3.36.1, ash_oban 0.10.1, thousand_island 1.6.0, spitfire 0.4.3,
  @privy-io/react-auth 3.49.1 and vitest 5.0.5. ash_postgres, ex_hash_ring and puid
  stay where they are.

## 2026-10-16 — Footer labels, Agent guide and help by email

- The footer reads Buy $REGENT, About, Developer docs, Agent guide, Contact, then
  Privacy policy and Terms of use together after a hairline, on their own line on a
  phone. Agent guide is a button that opens the browser's popover with `/agents.md`
  and `/llms.txt`; Escape or a click outside closes it.
- `/contact` starts with a Help section: build@regents.sh for help with an account,
  agents or anything else, or the Regents page at Patchbay. Its description and the
  About page's pointer to it say so too. Security reports already went to
  build@regents.sh on `/contact`, in `/.well-known/security.txt` and in the Privacy
  Policy. The Credits refund rules keep support@regents.sh, Sean's 13 October wording,
  and the versioned Terms of Use are unchanged.
- The public changelog keeps its released "One footer" bullet and adds "Clearer
  footer" for the new labels.

## 2026-10-16 — Commands name their WebMCP tool; agents status

- Each command in `cli/commands.json` that a WebMCP tool also runs names that tool in
  `webmcp` (21 of 23; `health` and `agents pair` have none). `Capabilities` checks
  the name against `priv/tool_manifest.json` when it compiles.
- New command `agents status` for `checkInAgent` (`GET /api/agents/v1/me`, the
  `agent_status` tool). It is marked `cli_pending` until regents-cli releases it.

## 2026-10-16 — Shared libraries: Patchbay palette, hosted signing, ChatGPT opt-in

- regent_ui is pinned to design-system `c59303b`: Phoenix 1.8.15, LiveView 1.2.12
  and PubSub 2.4.1 (`d45f054`), Patchbay's own Porcelain and cobalt palette
  (`a9bed5f`, `6224b50`; only `data-brand="patchbay"` changes, so the template and
  the other sites keep their colours), and pairing words that say "<name> paired with your
  account." without pointing at a list, since the side panel has none above it.
- The elixir-utils packages are pinned to `59784c1`: ChatGPT identities through
  shared OAuth and SIWA, hosted signing with the site's own key, the MCP door on
  2026-07-28 only, the wave 1 dependency updates, ChatGPT offered only where a site
  sets `chatgpt_pairing: true`, and a consent page in the site's own words.
- The pairing box (side panel and Account) lists `RegentAgents.Harness.offered/0`.
  ChatGPT pairs through a plugin and identity tools the template does not serve, so
  the template leaves `chatgpt_pairing` off and ChatGPT is not offered. Making a code
  for an agent that is not offered does nothing.
- The reference OAuth settings carry a `consent_note`: the connection only reads
  updates and cannot post, spend Credits, make payments or change wallets.

## 2026-10-16 — Pair request takes only offered agents; plain consent wording

- The elixir-utils packages are pinned to `5235a54`: the agent pair request
  (`POST /api/agents/v1/pair`) accepts only the harnesses the site offers, and its
  `harness_unknown` hint lists only those, so the template refuses `chatgpt` there too.
- The consent page asks to "watch updates for your account on this site", without
  naming the connection's protocol.

## 2026-10-16 — Side panel takes focus on opening; Agent guide gets its edge

- The side panel was still hidden at the moment it opened, because its visibility
  waited out the same transition used for closing, so focus stayed on the button and
  Escape did nothing. It now shows at once on opening (on a narrow screen only its
  slide is animated), and hides only once it has slid shut.
- Opening it moves focus into it at every width; Escape closes it and returns focus
  to the side panel button. Found by Autolaunch while porting the panel.
- The footer's Agent guide popover sat outside the shared tip, so the tip's colours
  were never defined there and its border dropped out. It now sits inside `.rg-tip`
  and shows its edge on both themes.
- The Agent guide button no longer squishes on press: it reads as one of the footer
  links beside it, which keep still. Both found by Sentinel on Techtree.

## 2026-10-16 — One pairing box on the Account page

- The Account page has its own pairing box, so the side panel no longer draws a
  second one beside it there; the side panel's "Pair your agent" section shows only
  when a page gives it a box. Found by Sentinel on the template and Autolaunch.

## 2026-10-16 — Note: button paint changed with the design-system c59303b pin

- The design-system pin moved from fb0542f to c59303b (live since v85) carries three
  button paint changes, measured per brand from those commits' stylesheets:
  - 2c99787 (15 Oct, CTA restyle): in dark mode every brand's main button is now
    near-white (#F5F5F5) with a charcoal label, in place of the brand's own colour.
    Light mode keeps each brand's colour.
  - 16ecdff (15 Oct, account and recovery presentation): on the platform brand
    (template, Regents, Keyfleet), main buttons on account and recovery surfaces are
    charcoal with a white label in light mode, where they were white before.
  - a9bed5f (15 Oct, approved): Patchbay only, cobalt in light mode.
- No founder approval was found for 2c99787 or 16ecdff. Both wait on the button shape
  decision (BTN-SHAPE); the template keeps the pin until Sean answers.

## 2026-10-16 — Agent check-in without an account on this site is refused

- Pins elixir-utils d1b35a2: the agent check-in's account callback may return nil, and
  the check-in then answers `account_missing` (404) instead of crashing.
  `AshTemplate.Agents.PairedAccount.account/1` returns nil when this site has no
  account for the person. Found by Sentinel on Techtree.
- The pin also carries a1f6721 (mcp_agents drops its Bandit git pin), which the
  template does not use.

## 2026-10-16 — Refused check-in leaves last contact alone

- Pins elixir-utils 695a824: the agent check-in looks up the account before it
  records contact, so an `account_missing` refusal no longer marks the agent as in
  contact. Asked for by Sentinel.

## 2026-10-16 — Check-in touches only the pairing it read

- Pins elixir-utils 97cc964: the check-in records contact only when the agent is
  still paired with the person whose account it looked up, and answers `not_paired`
  otherwise. Asked for by Sentinel.

## 2026-10-16 — Check-in asks for the person's first sign-in

- Pins elixir-utils b77ad77: a check-in before the person's first sign-in on the site
  answers `person_sign_in_needed` (409), "Your person has one step left on this site
  before you can check in.", in place of `account_missing` (404). Every account exists
  on every site; the person may only need to sign in once. Sean, 16 Oct: never say the
  account is not on this site.
- `AshTemplate.Agents.PairedAccount.account/1` comment reworded to match. The entries
  above that name `account_missing` describe the earlier code.

## 2026-10-16 — Main buttons cut two corners again

- Pins design-system 9e93f14 (Sean, 16 Oct 13:26Z, BTN-SHAPE "a"): main buttons cut
  top-left and bottom-right with Powder Blue and Tangerine marks, in each site's own
  colour in light and dark, and keep the hover arrow and the press. This undoes the
  rectangular near-white button (2c99787) and the charcoal account button (16ecdff)
  noted above; the `--rg-cta-*` and `--utility-action-*` tokens are gone.
- The home page's product tabs keep their muted square paint under their own
  `--rl-tab-fill`.

## 2026-10-16 — Keyfleet home hero in the Motion Lab

- New Motion Lab page `/animations/keyfleet` (`AshTemplateWeb.KeyfleetHeroLive`): the
  Keyfleet home hero with the next Key's card centred in the right half, over one hex
  field drawn by a vgpu island (`hooks/keyfleet_hero.ts`, `keyfleet_hero/`).
- The five tiles nearest a mouse stand up over 0.3 s, the nearest highest, and sink
  over 0.3 s as the mouse moves on (Anime.js on the tile heights; the shader draws up
  to 24 raised or sinking tiles). Touch screens and Less motion keep the field flat.
- The same field sits behind the Club map lower on the page. Presentation only: no
  resources, routes outside the lab, or data changes.

## 2026-10-16 — Agents are never told the account is missing

- Pins elixir-utils 3ae5c7d: the check-in before a person's first sign-in answers
  `person_not_here` (403), the code the rest of the site already gives, in place of
  `person_sign_in_needed` from "Check-in asks for the person's first sign-in". One code, one meaning.
- Every account exists on every site; a person may only need to sign in once (Sean,
  16 Oct). So `person_not_here` now says "The person this agent is paired with hasn't
  signed in on this site yet.", `account_required` says "This sign-in hasn't been used
  on this website yet.", and the API descriptions say the person has not signed in on
  this site yet, never that they have no account here.

## 2026-10-16 — Side panel: account, Pair Agent and agents only

- The side panel holds, in order: the account's name and picture, Sign out,
  Manage Account (regents.sh/account, in a new tab), Pair Agent and the agents
  paired with the account. The Get started checklist, the assistant box, the Account
  link and the page slot (`#shell-aside-page`) are gone, with the light that
  pulsed on the panel button.
- Pair Agent offers the five agents in `RegentAgents.Harness.featured/0` (any
  agent, Codex, Grok Bot, Muse, Hermes) as pictures (`Regent.Account.pairing`
  `layout={:icons}`), each with its own message. The pairing box is on every page,
  Account included; the Account page's agents list opens it with Pair Agent
  (`data-aside-open`) instead of holding its own.
- The panel's agents list is `AshTemplateWeb.PanelAgents`, the shared agents list
  with no actions; Unpair and each agent's activity stay on the Account page.
- Between a phone and a wide screen the open panel now sits beside the page, and
  the section's list makes way while it is open; only on a phone does it cover
  the page.
- A room's "Here now" and "People you've muted" moved from the panel to below the
  room.
- Sign out and Manage Account sit one above the other. Manage Account opens in a
  new tab, so its arrow points up and to the right (design-system styles every
  `rg-button` with `target="_blank"` this way).
- Each picture's name shows above it on hover or keyboard focus, and the chosen
  agent's name shows below the pictures ("Pairing Hermes") for touch.
- The motion kit names the main-button selector once (`CTA` in
  `assets/js/hooks/motion/buttons.ts`), and the press handler uses it.
- Pins elixir-utils `a8b83589c5e348cb2b3d23ceec8b04317c1dede1` and design-system
  `e97099285c20186fae5f6b4340b589168a4d122a` (which also gives Patchbay's main
  button its tangerine marks back in light mode).
- The agent guides, the build skill and the CLI command list (`cli/commands.json`,
  `cli/COMMANDS.md`) say the pairing code is made with Pair Agent in the side panel.

## 2026-10-16 — One test keeps agents from hearing the account is missing

- `test/ash_template/agents/signed_tools_test.exs` adds one test (Sean agreed, 16 Oct):
  an agent paired with a person who has not signed in on this site yet checks in and
  gets `person_not_here`, saying the person hasn't signed in here yet and asking the
  agent to have them sign in, never that the account is missing; once the person
  signs in, the same check-in succeeds with their account.

## 2026-10-16 — Keyfleet home: light raised tiles

- In light mode the tiles that rise under a mouse on `/animations/keyfleet` now turn
  shades of a darker off-white (`--kf-field-deep` is `light-dark()`: the page ground
  mixed 22% toward charcoal in light, the near black unchanged in dark), the highest
  the darkest (Sean, 16 Oct 15:05Z). On a light ground their sides fall into shade
  instead of catching the light, so the pale tiles still read as standing.

## 2026-10-16 — Header and footer in the Motion Lab

- New Motion Lab pages `/animations/header-footer` and `/animations/header-footer/long`
  (`AshTemplateWeb.HeaderFooterLive`): one header for every public page, with the brand,
  a Products menu of every Regents product and Docs, over the shared footer
  (`Layouts.product_links/1`).
- `AshTemplateWeb.Components.SiteHeader.header/1` and the `ProductsMenu` hook
  (`hooks/products_menu.ts`): a mouse opens the menu by resting on Products for 70 ms
  and closes it 160 ms after leaving, with a short fade through the motion kit's
  `play()`. A tap or a key toggles it; Escape, a press elsewhere and tabbing out close
  it. Keys and Less motion open it with no motion.
- `Shell.regents_products/0` lists the products in the order every menu shows them, and
  `Shell.crown/1` is public, so the header and the apps menu read one list.
- On the short page the footer sits at the foot of the screen; on the long page it
  follows the content. The page keeps one root (`.hf-page`, rows `auto 1fr`) inside
  `[data-phx-main]`'s single `1fr` row. Presentation only: no resources, routes outside
  the lab, or data changes.

## 2026-10-16 — CLI 1.10.12, and Pair Agent named in every pairing hint

- Names regents-cli 1.10.12 (source `6dacddd52797115125738177a3a0dee914724ab1`, wheel
  SHA256 `8d4058c83381cd2a99e78547fa4a95b2c130b44bd418d3fb494e54c5d3f9e2fd`) in
  `agents.md`, `llms.md`, `/start`'s steps (`AgentStart`), `cli/COMMANDS.md`,
  `cli/README.md` and `priv/capabilities.json`. `REGENTS_CLI_REV` moves to `6dacddd`, so
  `make check-cli` runs that release's checker.
- `agents status` is released: `checkInAgent` carries `cli_release` 1.10.12 in place of
  `cli_pending`, `cli/COMMANDS.md` describes it, and the check-in step after pairing runs
  it. `agents whoami` stays the look-only check.
- Both API documents give `GET /api/agents/v1/me` its 403 `person_not_here`.
- The `agent_not_paired` and `posted_before_pairing` hints, the 403 descriptions and
  examples in both API documents, the site tools' pairing step and `/start`'s steps say
  the code comes from Pair Agent in the side panel, not the account page (Sentinel's v93
  notes).
- The `/me` 403 in both YAML API documents carries a `personNotHere` example with the
  shared check-in's own message and hint. `llms.md` says public documentation needs no
  sign-in, and the Credits admin and agent-spending lines say nobody has signed in with
  a wallet yet, or that an agent is paired with Pair Agent, instead of naming a missing
  account (Sentinel's v95 notes).
- Removes the side panel's leftover pulsing-light comment in `components/shell.ex`;
  `docs/standardization-plan.md` and `docs/app-shell-structure-plan.md` describe the
  panel as it is.

## 2026-10-16 — Workflow guide: push to GitHub main with notes

- `skills/regent-workflow/SKILL.md` adds Sean's rule of 16 Oct to its rules in force:
  checked work goes up to GitHub main with no finished commit left on a local head,
  every commit message says what changed and why, every commit or release adds its
  changelog entry, and a change to behaviour, setup, settings or commands updates the
  README or the folder's own README in the same commit. It covers every site
  repository, ash-template, elixir-utils and design-system.

## 2026-10-16 — Side panel: your agents, then Pair New Agent

- The side panel opens on one short row, Sign out and Manage Account; the name row and
  the close button are gone, since the header's panel button closes it. The `:close`
  shell icon and the `[data-aside-close]` handler go with them.
- "Your agents" lists every agent paired with the account (`PanelAgents`, through the
  shared `Regent.Account.agents_brief`), each with its picture, name, the Regent site
  it was last active on ("Active on Patchbay") and how long ago
  (`RegentFormat.short_relative_time`). The list takes at most a quarter of the panel
  and scrolls: `#shell-aside` is a size container and the list is `25cqb`.
- Where each agent was last active is asked for only while the panel is open: the new
  `PanelAgents` hook asks on arrival with the panel open and on each opening, four
  agents at a time with an 8-second limit, and an opening while a read is still out
  asks nothing. A pairing, check-in or unpairing updates the list at once; the lines
  follow on the next opening.
- `AshTemplate.Agents.ActivityReading` (a Nebulex local cache, now a direct
  dependency with `nebulex_local`, supervised beside `SharedReading`) keeps each
  agent's reading from the sign-in service for five minutes, under its wallet and
  pairing time, shared by every page on the machine: the side panel and the Account
  page read the service at most once per agent in that time, well inside its 600 reads
  a minute per site machine. A failed read is not kept.
- The sign-in service now answers with a line per site and day, so
  `RegentAgents.Activity.recent/1` reads that (hard cutover): the Account page's agent
  view lists each site and day with the hours of its first and last request, newest
  first, and Load more is gone with its paging. `Capabilities.requests/0` and every
  operation's `done` words in `priv/capabilities.json` go with the request-by-request
  wording.
- The button and every hint, guide and command note say "Pair New Agent", the side
  panel's heading: the refusal hints, the agent start page, `/agents.md`, `/llms.txt`,
  the developer docs, the skill guide, the three API documents, the capabilities list,
  `cli/commands.json` and `cli/COMMANDS.md`, and the Account page's button.
- "Pair New Agent" puts the message first, in a short box that scrolls, with a copy
  icon and a new-code icon in its corner (`Regent.Primitives.copy_icon`), then the
  expiry line, then ten agents to choose from, five to a row, each named on hover:
  Dots, NemoClaw, OpenClaw, Claude Code and Pi join the five before
  (`RegentAgents.Harness.featured/0`). The box no longer renders every agent's
  stand-in message.
- Pins elixir-utils `1b73b6c2eb42e4691c67b5bd9f12682201c08eeb` and design-system
  `df44fc3416df05cdbf8116523447f19f1a38b6db`.
- Every refusal and guide says "this site": the `person_not_here` hint on signed tool
  routes, `account_required` on the notes API, the 403 descriptions in all three API
  documents, `llms.md` and `docs.md`. `/openapi.json`'s `/me` 403 carries the same
  `personNotHere` example as the YAML documents (Sentinel's v95 after-read notes).
- `platform/README.md` lists `SIWA_ACTIVITY_READ_TOKEN`, the sign-in service reader key
  behind both activity views, and says neither shows activity without it.

## 2026-10-16 — Keyfleet home: raised tiles keep their border

- In light mode a raised tile on `/animations/keyfleet` keeps a darker hairline rim, the
  field's line at the strength of the rims lit around the pointer, over its off-white
  face, and its top edge is no longer lightened (Sean, 16 Oct 15:42Z). Dark is unchanged.

## 2026-10-16 — Keyfleet home: Blueprint colours

- `/animations/keyfleet` gains a Blueprint switch beside Less motion. It gives the page
  and its hex field the agent harbour's colours (`dm/agent-harbour-1016`,
  `assets/js/harbour/shaders.ts`): blue lines on near white in light (paper `#f2f5f7`,
  ink `#1f4d9e`) and pale blue lines on navy in dark (paper `#12264d`, ink `#a8d6ff`),
  set as `--kf-blueprint-paper` and `--kf-blueprint-ink` on `.kf-lab[data-palette]`.
  The field retones when the switch changes (Sean, 16 Oct 16:06Z). No glowing borders
  (Sean, 16 Oct 16:07Z).

## 2026-10-16 — Header and footer: Docs on every phone

- On phones Docs stays in the header beside Products, with tighter link padding; below
  360 px wide the crown stands for "Ash Template", which screen readers still hear
  (`.site-header__name`). Docs no longer waits in the footer.
- The lab's lede is one line shorter, so the short page fits a 320 × 844 phone without
  scrolling (Sentinel's v94 read, 16 Oct).

## 2026-10-16 — Agents' activity: the Regents mobile app, one read a minute while the service is down, closing filter pills

- Pins elixir-utils `583e2c60c930167a323ae752d50511705a2c5c01`, whose
  `RegentAgents.Activity` names the sign-in service's `regents-mobile` audience
  "Regents mobile app": an agent's requests through it show in the side panel line
  and the Account page's days instead of being skipped (Sentinel's v96 note f).
- `AshTemplate.Agents.ActivityReading` keeps a failed read for one minute, so while the
  sign-in service is down each agent is asked again at most once a minute however often
  the panel opens (Sentinel's v96 note a). It reads with `get!` and `put!`, giving each
  answer its own time.
- Pins design-system `288888391e47f5becd86a38c0a53c7b11a6599b3` and imports its
  `pill_select.mjs` in `app.ts`: an open `details` filter pill closes on Escape and on
  a press or tap outside it, iPhones included, the same on every site (Patchbay's R5 read).

## 2026-10-16 — A bad activity day ends only its own read; /start opens Pair New Agent

- Pins elixir-utils `03433b80e7b8b0d7fa0ae5d58cdfab6cbf8af668`, whose
  `RegentAgents.Activity.recent/1` answers `{:error, :bad_day}` for a day from the
  sign-in service with a missing field or an unreadable value, instead of raising
  (Sentinel's regents.sh v193 finding F2).
- `AshTemplateWeb.PanelAgents` reads each agent through
  `Task.Supervisor.async_stream_nolink` under the new `AshTemplate.Agents.Reads`
  supervisor. A read that crashes ends only itself and that agent's line stays empty;
  before, its crash reached the page, which closed. Walked locally with a stand-in
  sign-in service sending a bad day to half the agents: on the old library the four
  crashing reads left the page open and the other four lines in place, and on the new
  one nothing crashed.
- `/start`'s first step links "Pair New Agent" (was "Open Account") to
  `/account#shell-pairing`, and the shell opens the side panel on arrival when the
  address names its Pair New Agent section, on a phone too. `/start` has no side panel
  of its own, so a panel-opening button there could not do it (Sentinel's v193 N2).

## 2026-10-16 — Failed agent activity reads are counted

- Pins elixir-utils `72ccfea10551436a9b7aaad29d3ec6b5462d423f`, whose
  `RegentAgents.Activity.recent/1` answers `{:error, :bad_days}` for a 200 answer
  without a list of days, where it said `{:unexpected_status, 200}` (Sentinel's note a
  on `03433b80`).
- `AshTemplate.Agents.ActivityReading` counts each read that gives no reading in
  `health.agent_activity_unread.total`, tagged by reason (`bad_day`, `bad_days`,
  `registration_unreadable`, `not_configured`, `unexpected_status` or `unanswered`), so
  a bad answer from the sign-in service is no longer silent (Sentinel's note b). A
  local walk with four bad-day agents counted `bad_day` 4.

## 2026-10-16 — Workflow guide: side branches are a handoff only

- `skills/regent-workflow/SKILL.md` adds Sean's ruling 2 of 16 Oct under "Rules in
  force": a cloud thread may build a fix on a side branch for Sean's Mac session to test
  and ship; the Mac session runs the suites, pushes main and deploys, Sentinel reads
  every head, main stays production and nothing ships from a branch. The "No feature
  branches" rule names it as its one exception.

## 2026-10-18 — Workflow guide: verification standard

- `skills/regent-workflow/SKILL.md` adds a "Verification" section from Sean's 18 Oct
  direction. It points every agent to the shared standard in
  `control/verification/standard.md` and names its rules: a `verification/features.yml`
  feature map in each repo, a breaker agent's finding counts only with a failing test,
  every bug becomes a permanent regression test, each release candidate carries an
  evidence summary, and protected work waits for Sean's go by letter.

## 2026-10-18 — Slimmer buttons; the phone menu and header fit a phone

- `platform/mix.exs` pins design-system `54500eb`: every shared button is about 40px
  tall (8px by 16px inside, down from 58px) with its label on one line, and at least
  44px each way on touch screens. Cut corners, colours, the hover arrow and the press
  motion are unchanged. Sean, 18 Oct: "all sites need a slimmer button".
- The page paints under the notch and the home bar (`viewport-fit=cover`) and the body
  keeps its content clear of them; the phone drawer, its backdrop, the side panel, the
  Regents Products panel and the search and Buy Credits boxes sit below the header and
  above the home bar.
- Every press in the phone header is 44px (search, activity, Regents Products, side
  panel, the brand and the account picture were 32 to 42px), and on touch screens the
  rail's profile picture, the list's links and the side panel's Sign out are too. The
  header still fits one row at 320px.
- The open phone menu is a named modal dialog (`role="dialog"`, `aria-modal`, "Menu"),
  a scroll that reaches the end of its list stops there instead of carrying on to the
  page, and a screen that widens past 48rem closes it, where the page behind used to
  stay frozen and unclickable.
- Site buttons lab: a step whose words are wider than a narrow row wraps inside the
  button instead of being cut off.
- Evidence · level ordinary · features: app shell, shared buttons · proved by headless
  Chromium checks at 320 to 430px and screenshots at 375 and 1440px · WebKit not run
  on the Mac; no browser test harness in this repo yet.

## 2026-10-19 — Buttons are back to their normal size on desktop

- Buttons are back to their normal size on desktop; 44px stays for touch targets
  only. The template pins design-system 54500eb1 again, and the side panel's Sign
  out and Manage Account keep their own 32px height. Sean, 19 Oct 04:30Z: "Normal
  desktop size".

## 2026-10-19 — Speed pass

- Script pieces esbuild names by their contents now live in
  `platform/priv/static/assets/js/chunks` (`--chunk-names` and `--asset-names` in
  `platform/config/config.exs`), served by their own `Plug.Static` in
  `platform/lib/ash_template_web/endpoint.ex` with
  `public, max-age=31536000, immutable`. A return visit to a public page now makes
  one request (the page) where it made twelve; a signed-in page makes twenty where it
  made sixty-eight.
- The first-load script no longer carries the lab hooks (`Crown`, `CodeCube`,
  `TwinCube`, `WorldCube`, `KeyfleetField`, `KeyfleetKeyCard`, `KeyfleetReplay`):
  `platform/assets/js/lab_pages.ts` loads them on `/animations/*` only. The site's
  WebMCP tools (`platform/assets/js/public_tools.ts`) load only in a browser that has
  `document.modelContext`; any other browser records `webmcpStatus = "unsupported"`
  as before. The home page's script drops from 224 KiB to 175 KiB compressed.
- PROTECTED (wallet): `platform/assets/js/wallet_actions/send_step.ts` imports
  `getAddress` from `viem/utils` and its types with `import type`, so the first-load
  script no longer pulls in viem's whole entry point. Same function, same checks.
- `AshTemplateWeb.Read.now/4` runs a read of the site's own database inside the
  callback, so the first, unconnected render already shows it. Credits history,
  Chat, Notes, Rooms, Notifications, Points and verified connections use it; chain
  reads keep `Read.start`. The "Loading…" lines and their CSS are gone from those
  pages. Credits history shows its table after 1.8 s instead of 6.9 s on an emulated
  low-end phone over slow 4G. `skills/ash-frontend/references/async-state.md` says
  when to use each.
- `/sitemap.xml` is sent like the other public documents (`public, max-age=300` and
  an ETag) instead of as private.
- PROTECTED (migration, sign-in table):
  `20261019044403_unread_and_linked_account_indexes` adds, concurrently so neither
  table stops taking writes while it builds,
  `linked_identities (human_account_id)`, read on every sign-in (0.73 ms to 0.03 ms
  at 40,000 rows), and a partial index `notifications_unread_index` on
  `notifications (human_account_id) WHERE read_at IS NULL`, read by the bell on every
  page (0.56 ms to 0.08 ms for a person with 5,000 read notifications).
- The header logo (`platform/lib/ash_template_web/components/shell.ex`) uses `~p`, so
  it is sent by its digested name with the year-long cache; a signed-in return visit
  makes 18 requests instead of 20.
- A fresh copy's first `make check` passes: `mix test` creates the local test
  database before migrating it.
- New checks, each failing when its change is undone:
  `platform/test/ash_template_web/script_build_test.exs` builds the scripts as
  `mix assets.build` does and reads esbuild's account of the build: every shared
  piece lands under `/assets/js/chunks/` and is sent for a year, and the script
  every page loads first holds no lab hooks, WebMCP tools or viem's whole entry
  point and stays under 1,200,000 bytes unminified (1,149,694 today).
  `first_render_test.exs` (a person's notes and chat are in the first render),
  `digested_logo_test.exs`, `platform/test/ash_template/read_indexes_test.exs`
  (both indexes exist), `read_test.exs` (`Read.now`) and the sitemap check in
  `static_cache_test.exs`.
## 2026-10-16 — A page for each agent; /agents replaces /start

- `/agents` lists the ten agents the side panel offers, after three steps to pair one.
  Each has its own page at `/agents/<agent>` (`grok_bot` is `grok-bot`, "Any agent" is
  `other`): how it pairs, its set-up notes, common questions and troubleshooting ending
  with its Patchbay help link, `https://patchbay.help/<agent>/troubleshooting`. Sean,
  16 Oct: "each harness needs a custom page / skill / faq / link to its patchbay.help
  for troubleshooting".
- `/agents/<agent>/skill.md` is that agent's skill: the agent guide with its set-up
  notes added under "On <Agent>".
- Each agent is one Markdown file in `platform/priv/public/agents/`, read when the code
  compiles (`AshTemplateWeb.AgentGuides`). The build stops if the files and
  `RegentAgents.Harness.featured/0` name different agents. The files are the same
  shape on every Regent site, so Keyfleet copies them as they are.
- The pages answer `Accept: text/markdown` like the other reading pages and stay open
  while the rest of the site is closed.
- `/start` is retired: `/agents` does its job, and the route catalog, `llms.md` and
  `agents.md` point there. `AshTemplateWeb.AgentStart`, `AgentStartLive` and their
  stylesheet are deleted.
- The side panel's pairing box shows a help icon under the copy and new-code icons once
  an agent is chosen, linking to that agent's page (design-system 14a2b78, which also
  underlines the "Your agents" heading link at rest). The heading leads to the Account
  page.
- Every pairing hint now reads "Ask your person to sign in on this site and pair you
  with Pair New Agent in the side panel, then send the request again." (`posted_before_pairing`
  ends "then post again."), in the plug, the rooms controller and both copies of the API
  contract.

## 2026-10-17 — Form security tokens stay out of the logs

- `_csrf_token` joins `:filter_parameters` in `platform/config/config.exs`, so the
  form security token that rides on every form post is logged as `[FILTERED]` like
  the other secrets. Sentinel's v98 after-read follow-up.
- Sentinel's other v98 note, one Safari "Refused to apply a stylesheet … style-src"
  line per screen size, did not come back: 48 Safari page loads of `/`, `/start`,
  `/account` (with sign-in opened) and `/docs` at 390 and 1440 showed none, and Chrome
  showed none. The template's reading pages carry no inline style element; the only
  one, Privy's in the sign-in pages, is allowed there. Nothing changed.

## 2026-10-17 — Agent pages: two wording fixes from Sentinel

- Every agent page's `agent_not_paired` line now reads "you aren't paired with your
  person on this site. Ask them for a new code and pair again." It no longer says the
  person unpaired the agent, which was only one of the reasons.
- Grok Bot's answer to "Can my other Bots use this agent's key?" no longer invites
  sharing one identity: "Every Bot on your account can read its workspace folder, so
  any of them could act as this agent; keep only Bots you trust on that account."
- Dots' "Settings, Personalization, Custom rules" path matches OpenAI's own Dots help
  page (learn.chatgpt.com/docs/dots/controls), so it stays.

## 2026-10-18 — Account panels in a sensible order; a cleaner Pair New Agent

- /account: the account card and Your agents run the full width at the top. Below
  them, on a wide page, Credits sits in the left column and Profile in the right, and
  each column stacks its own panels, so a tall panel never leaves a gap beside a short
  one. A narrow page shows one column in that same order. The page is a size
  container and the columns start at 46rem of its width, as on regents.sh (Sean, 17
  Oct: "the ordering of the containers on the account site is very bad").
- Pair New Agent in the side panel (design-system 347a370; Sean, 18 Oct): before an
  agent is chosen the box reads "Choose type of agent below to get pairing message.";
  each picture has one frame, and every agent picture sits on white in both themes,
  so NVIDIA's lettering reads in dark mode; the copy, new-code and help icons have
  their own column beside the message; the pictures follow the box more closely,
  "The code works once, until …" moves under them, and a picture's name on hover
  never covers that line.
- Sign-out was checked against Sean's ruling that it must start the browser fresh:
  it already throws the whole session away (the browser's cookie is cleared, and the
  signed-in claim is revoked on the server), and a guest's posting allowance belongs
  to the network address, not to the browser, so nothing of the signed-in person
  survives. No change was needed.

## 2026-10-18 — The two cube labs: "Visit" stays on one line, the code cube's faces in mono

- /animations/cube: where the six worlds show as a grid of cards (before the cube
  draws, or where it can't), each card's button now says "Visit" alone under the
  world's name, as on a phone. Between 48rem and 64rem "Visit Autolaunch" broke onto
  two lines inside the button. The single card shown beside the drawn cube still
  says "Visit Autolaunch".
- /animations/twin-cube: the six face buttons now show in the mono font their code
  screens were drawn with. The design system's base and the template's both give a
  button the font of what holds it, unlayered, so the font a component set on the
  button itself never applied, and the template's own "controls use the interface
  font" rule then forced the interface font on top. The cube now sets its font on
  the list that holds the buttons, and that template rule is gone: everywhere else
  it only repeated the font the controls already took from the page. Every other
  button, link and field on 18 pages, at phone and desktop width, kept exactly the
  font it had.

## 2026-10-18 — A person's shared name is read by the shared library

- The name a person sets in their shared Regent profile is now read by
  `RegentIdentity.ProfileName` from elixir-utils (e8c3e43), the same calculation
  every site can put on its account resource. The template's own copy of the
  profiles table (`AshTemplate.Accounts.SharedProfile`) and its calculation
  (`AshTemplate.Accounts.HumanAccount.ProfileName`) are gone. Nothing changes on
  screen: checked against the local database in a rolled-back transaction, a name
  set for this site's Privy app shows, and one set for another app does not.

## 2026-10-18 — Account page sections match

- The Profile heading on the Account page is the same size as Agents and Credits
  beside it (it was a fifth larger), and so are the section headings on the
  Wallets and Connections pages. A details list draws its rules between rows
  only, so Profile no longer has a second rule under its heading. Checked
  headless at desktop and phone width, light and dark.

## 2026-10-18 — Every change proves itself

- Sean, 18 Oct 22:35Z: "Give your agent a way to verify its work." `make check` now
  runs a browser walk (`make check-browser`, `platform/test/browser`): headless
  Chromium at 390 and 1280 wide opens every page signed out and signed in and every
  document, then pairs an agent the way a person does. It starts its own server on
  its own database (`ash_template_browser_dev`, port 4098) and signs in a local
  person first (`platform/test/browser/support/sign_in.exs`). WebKit is not run on
  the Mac.
- `platform/test/ash_template_web/feature_map_test.exs` fails when the router serves
  a page or document the walk does not open, or the walk names one the router has
  dropped, and when an agent in the side panel has no guide page or skill in it.
- `docs/feature-map.md` lists what a person or agent can do, the check that proves
  it, and the gaps.
- A property test (StreamData) checks that each account shows the name its person
  set for this site's Privy app, never one set for another app, in the order asked.
  `stream_data` is now named in `platform/mix.exs`; Ash already shipped it.
- Fixed: the Account page's two columns also split the Credits history page, whose
  one panel filled half the width. The two columns now belong to the Account page
  alone (`.account-layout`); Notes, Points and Credits history keep the shared grid.
  `platform/test/browser/layout.spec.ts` checks it and failed on the old rule. Found
  by the separate review of this release. The 18 Oct heading size applies to every
  page with account panels (Notes, Rooms, Chat, Activity, Points, Credits history),
  not only the three named in the entry before.
- `regent-workflow` carries the rule for every lane ("Every change proves itself"),
  replacing the rule that each new test needed Sean's agreement; the site standard
  (`docs/standardization-plan.md`) has the matching Checks row.

## 2026-10-18 — Public Display Name on the Account page

- Sean, 18 Oct 22:36Z: "1. yes, in account 'Public Display Name'". The Account
  page's Profile section is now one field, **Public Display Name**, with Save. It
  saves to the shared Regents profile (`/api/v1/profile`) from the browser with the
  person's own Privy proof; nothing on the server writes the name without it. The
  first save makes the profile from the sign-in. After a save, the name at the top
  of the page and in the shell updates.
- The form is design-system `Regent.Profile.panel` and `mountProfile` (pin
  `f82c4a74`, branch `tpl/ds-public-name-1018`). It no longer offers sign-in, a
  wallet choice, Connect X or account details: wallets and connections have their
  own Account tabs. The form takes its spacing from the Account panel around it.
- One save is one person's: each Save opens its own profile client
  (`openProfile` in `auth_lazy.ts` and `privy_bridge.tsx`), and `oneSignIn` hands on
  only proofs for the person the save started with, so a switch of account part way
  through sends nothing more (security review). Saves run one after another, so two
  quick presses keep the name pressed last, and a save that fails outright never
  stays on "Saving…" (breaker review).
- A long name ends in "…" in the top bar instead of pushing the page sideways
  (breaker review: an 80-letter name made the page 690px too wide at 1280).
- Checks: `platform/test/ash_template_web/public_name_test.exs` saves a name with
  Privy-signed test tokens and reads it back on `/account`, and a forged token is
  refused; `platform/assets/test/public_name.test.ts` covers a first save, a later
  save, refusals, a switch of account part way through (against a profile service
  that follows the server's rules), two quick saves and a save that fails outright;
  the walk's person now has an 80-letter name, so every signed-in page proves a long
  name fits; `platform/test/browser/public_name.spec.ts` presses Save at 390 and 1280
  wide without the browser's sign-in and checks it finishes, sends no change and
  moves nothing. Each regression check was run once without its fix and failed.
  `docs/feature-map.md` lists them.
- `skills/regent-workflow/SKILL.md`: the two verification sections are now one,
  pointing at `control/verification/standard.md`, with Sean's 18 Oct 23:34Z rule that
  agents add meaningful tests without asking.
- After Sentinel's read of 9434c19 (HOLD): the account-switch check now goes through
  the page's own save path (the account loader's `openProfile`), and fails when the
  loader opens a new client on every call. The browser walk never leaves the machine:
  `platform/test/browser/support/test.ts` answers for Privy with a stand-in that
  holds no sign-in and fails any check that reaches another address; `keepSignedIn`
  is gone, since only the real bridge asked the site to sign out.
- `make check` now builds all three shared library copies (`regent_ui`, `regent_identity`,
  `regent_agent_access`) before the type check. It built only the last, so the type check
  failed on a fresh clone and only ran clean in a folder that already held the others.
- The design-system pin moves to `e4440c78`: the same four profile commits replayed on
  Techtree's Canopy palette head `e14b7f30`, which lands on design-system main first
  (coordinator ruling, 19 Oct). The `regent_ui` changes are line for line the ones in
  `f82c4a74`; only the design-system changelog kept both entries.
- After Sentinel's read of 65dd744 (HOLD): a save pressed before a switch of account,
  still waiting behind another save, now belongs to the person who pressed it, so it
  saves to neither account. The page's profile client is opened at the press of Save
  in three places: the design-system form, the account loader's `openProfile` and the
  bridge's `oneSignIn`, which hands on a proof only for the person signed in when the
  save was opened. `platform/assets/test/public_name.test.ts` covers it; it failed
  before the fix, and so did each of two weakened versions of it.
- The browser walk's server never leaves the machine either. It starts with every
  outside service's setting cleared, reads its chains and the agent sign-in service
  from a closed port on the machine, and refuses any other outside request
  (`platform/test/browser/support/server/walk_offline.ex`); one refusal fails the walk
  (`platform/test/browser/support/outside_teardown.mjs`). Pointing one chain back at
  Base's public node made the walk fail, as it should.
- Names with a control or text-direction character are refused when saved, with
  "That name can't be used. Remove any hidden characters." (Sean, 19 Oct, decision 2 a;
  elixir-utils `regent_identity`).
- The holographic cards no longer tilt toward the pointer (Sean, 19 Oct); only the light
  follows it. The foil showcase's two tilt samples are now two light samples.
- The agent's address in its window shows its short form with an icon that copies the
  full address, the shared `Regent.Primitives.address` every address will use (Sean,
  19 Oct).
- Pins: design-system `ec561f9d` (tpl/ds-address-1019, on `e4440c78`), elixir-utils
  `46ae1898` (tpl/eu-rename-1019, on `e8c3e432`), which also lets a person rename an
  agent they paired; the template does not offer it yet.
- After the coordinator's rulings of 19 Oct on `eb2c5ec2`:
  - The elixir-utils pin moves to `35532d74` (tpl/eu-name-1019d), two `regent_identity`
    commits on elixir-utils main `9de2012`: names refuse hidden characters, and
    property checks that any name holding one inside it is refused and any other name
    saves as typed. The agent rename in `46ae1898`, named in the pins above, is left
    out until the template offers it. The other elixir-utils packages move to
    `9de2012` with it, which declares the bodies `Siwa.AgentAuthPlug` accepts.
  - The design-system pin moves to `edf0bb27` (tpl/ds-address-1019c, on `ec561f9d`):
    an address's words open the full address on a click, tap or Enter, not only on
    hover, and on a touch screen the words and the copy icon each take a 44 px target.
  - The browser walk's server runs on a port nothing else on the machine is using,
    chosen when the walk starts, not always 4098, so two walks at once never reach
    each other's server (Sentinel, 19 Oct). The outside-request check is
    `platform/test/browser/support/outside_teardown.ts` again, with `@types/node`
    26.6.5 for the walk's own files.
  - A moving picture whose graphics card never starts now stops listening to the page
    as well as showing its still picture (`platform/assets/js/canvas_island.ts`), as
    Keyfleet `ff1146e1` found; `platform/assets/test/canvas_island.test.ts` fails
    without it.
- After the coordinator's ruling of 19 Oct 01:42Z on `feef62af`:
  - The elixir-utils pin moves to `384fbb00` (tpl/eu-name-1019e, on `35532d74`): a name
    refuses every hidden character, not only controls and text-direction marks. Line
    and paragraph separators and all format characters are refused, among them
    zero-width spaces, the byte-order mark, the word joiner and the soft hyphen. A
    zero-width joiner or non-joiner stays allowed between two visible characters, and
    tag characters inside a complete flag. Taking out any one of these rules fails a
    check.
  - Each browser walk makes its own database, named after its port, and drops it when
    it ends, passed or failed (`platform/test/browser/support/drop.exs`, run by
    `platform/test/browser/support/teardown.ts`, which now also holds the
    outside-request check). Two walks at once no longer share data.
  - The walk builds the pages' scripts and styles before its server starts, and its
    server runs no file watcher, so no page is reloaded under a check and the first run
    from a fresh copy passes.
  - The walk's phone is a touch phone at 390 wide (Playwright's Pixel 7 with its width
    set to 390), not a desktop browser made narrow.
  - The walk's person has an agent, paired with a code the way the Account page and
    the agent do it, and the walk opens its window at both widths: the address opens
    the full address on a tap or click, Escape closes it and gives the press back to
    the address, the icon copies the full address, and on the phone each target is at
    least 44 px tall (`platform/test/browser/agents.spec.ts`).

## 2026-10-19 — An agent's name says where it comes from, and its person can change it

- Founder, 19 Oct 00:16Z: make clearer where agents' names come from and who sees
  them, and let the person edit them, in one shared piece for every account page.
- The design-system pin moves to `f7b4c66c` (tpl/ds-name-1019a): the agents list's tip
  says each agent chose its own name when it paired and only the person and the agent
  see it, and the agent's window has a Name field with Save, a line saying only the
  person sees it and a tip on where it comes from. The Public Display Name's tip says
  people see it beside what the person posts, the same on every Regent site.
- The elixir-utils pin moves to `9c580f45` (tpl/eu-rename-1019a): the person may rename
  their agent, and an agent's name follows the same rule as a Public Display Name (1
  to 80 characters, no hidden characters). A pairing whose name breaks it is refused
  with `invalid_name` (400), and the same code still works; `cli/COMMANDS.md` and
  `platform/priv/public/openapi.json` list it.
- `regent_format` is now pinned with `override: true`, since `regent_identity` and
  `regent_agents` name it by path.
- The Account page's agent window saves a new name
  (`platform/lib/ash_template_web/components/agents_panel.ex`); a refused name is said
  beside the field and the agent keeps its name. The browser walk pairs two more
  agents and renames one at each width (`platform/test/browser/agents.spec.ts`); taking
  out the refusal or the save fails it.
- The Public Display Name walk finds the name field by its role, since the new tip
  beside it is also labelled with the name (`platform/test/browser/public_name.spec.ts`).

## 2026-10-19 — Every address on the site has its copy icon

- Founder, 19 Oct 00:17Z: "make a standing rule where anywhere an ens name or a
  0xaddress or abbreviated 0xaddress is shown , to show a copy icon to get the full
  address". The rule is in `skills/regent-workflow/SKILL.md`.
- The design-system pin moves to `30d50d8c` (tpl/ds-identity-1019b): one account card
  for every Account page (`Regent.Account.identity`), which says the person's name
  once, and their wallet beneath it only when the name is not the wallet's own ENS
  name or short address, so an ENS name is never shown twice. An address's words
  default to its short address.
- The Account page uses that card, and its Wallets page, a room post's agent, a
  note's agent, the Credits panel and its agent spending, the Credits admin page, the
  on-chain example and every showcase draw each address with
  `Regent.Primitives.address`. The template's own card styles are gone.
- A wallet note (`OnchainSteps.failure_note/4`, `mismatch_note/2`) is now its words and
  the wallets it names, drawn by `<OnchainSteps.note>`, so each wallet in a note opens
  and copies its full address.
- The browser walk fails a page that shows an address without its icon
  (`platform/test/browser/support/addresses.ts`), and opens and copies the wallets a
  wallet note names (`platform/test/browser/addresses.spec.ts`); a note drawn without
  the icons, or with a space before the comma after an address, fails it.

## 2026-10-19 — The foil cards shine only on a thick frame

- Founder, 19 Oct 00:51Z: "5. a , but only shine on a thick border not the whole
  card." The design-system pin moves to `c0a83f4a` (tpl/ds-holo-frame-1019a): the
  foil cards stay flat, and the light that follows the pointer shows only on a 12px
  frame round each card; inside it the face stays still graphite with the crown's
  outline. The home page's foil drawing still lights wherever it is.

## 2026-10-19 — Sentinel's four fixes to the name work

- The browser walk is started by `platform/test/browser/walk.sh`, which takes the
  run's port, makes its database and drops it when the walk ends, whatever happens:
  passed, failed, stopped, or a server that never started, when Playwright skips its
  own teardown. It prints the database's name first. A drop that cannot reach the
  database names the database it leaves.
- `mix test` creates the local `ash_template_test` database when it is missing, so a
  fresh copy needs only `mix setup` before `make check`. The Quickstart, the local
  sign-in notes and the rename script's last steps make the development database
  with `mix ecto.create` after `mix setup`.
- The agent window's 44px checks measure once the window has risen into place
  (`resting` in `platform/test/browser/support/person.ts`); measured while it was
  still rising, a target came out a fraction of a pixel short. The design-system pin
  moves to `3599ae97` (tpl/ds-address-44-1019a): an address's words and copy icon are
  at least 44px tall on a touch screen whatever the root font size.
- The elixir-utils pin moves to `f8f36fd1` (tpl/eu-rename-1019c): six more names with
  hidden characters are refused in its HTTP check, each one a looser rule let through.

## 2026-10-19 — A window says when it has settled

- A dialog or header menu that opens carries `data-settled` once it rests where it
  opens, after its rise or at once when it does not move (`platform/assets/js/motion.ts`).
  Redraws keep the mark, as they keep `open`.
- The browser walk measures the agent window's 44px touch targets once it carries
  `data-settled`, instead of watching its inline style.

## 2026-10-19 — The name work on the slimmer buttons

- The name work joins main after the slimmer buttons and their desktop size.
- The design-system pin moves to `fb26ac3a` (tpl/ds-names-on-lime-1019): the profile
  and address work replayed on Techtree's Canopy palette, its lime buttons' outline in
  light and the plainer Touch ID page, after the slimmer buttons.

## 2026-10-16 — Agent harbour

- `/animations/harbour`: an isometric sea drawn with vgpu, with three islands and one ship
  for each agent. The inn is a chat, the forge is work and the castle is a proposal. Each
  ship sails to the island of its agent's last action and circles it slowly.
- The six agents are samples. While the page is connected, one of them does something new
  every seven seconds; the legend under the sea lists who is where. A crew is a list of
  `%{id, place, color}`, so real activity can feed the same page later.
- Reduced motion draws one calm frame; a hidden tab draws nothing. Listed in the Motion
  lab, the Design page and the route catalog.

## 2026-10-16 — Harbour art styles

- `/animations/harbour` has six looks for the water and the buildings, picked from a row of
  tabs above the sea and linkable with `?look=`: Toy (the first look), Studio (soft light,
  long shadows and glossy water, like vgpu's robot dogs), Cartoon (inked outlines, flat
  bands and curling foam), Paper (cut-paper layers stepping out from each beach), Blueprint
  (drafting lines on a grid with depth rings) and Pixel (chunky dithered pixels).
- Each look has its own still pictures for light and dark, shown until the first frame is
  drawn and wherever the sea cannot be drawn live.

## 2026-10-16 — Harbour drawn as a blueprint

- `/animations/harbour` now shows only the Blueprint look: blue ink lines on pale drafting
  paper by day, pale ink on navy by night, with a grid on the sea, depth rings rolling out
  from each beach, hatched shade and coloured sails. The row of style tabs and the
  `?look=` link are gone.
- One pair of still pictures, light and dark, stands in until the first frame is drawn and
  wherever the sea cannot be drawn live.

## 2026-10-16 — Harbour ripples and agent cards

- Pressing the sea at `/animations/harbour` sends out a ripple: inked rings spread from the
  spot and a low swell rocks the ships as it passes. A visitor who asked for less motion
  gets no ripples.
- A mouse over a ship shows its agent's name above the mast. Pressing a ship, or an agent's
  name under the harbour, opens that agent's card: its Key and its last few actions, newest
  first, kept up to date while it is open. `?agent=` names the agent, so each card has its
  own link, and the browser's back button closes it.

## 2026-10-16 — Harbour ripples stop at the islands

- Ripples at `/animations/harbour` now move like water: each press sends out a short train of
  rings that runs into the islands instead of through them. A beach soaks a ripple up, so
  the water behind an island stays still apart from what bends round it, and ships rise,
  fall and lean as the rings pass under them.

## 2026-10-16 — Harbour islands have their own pages

- A mouse over the inn, the forge or the castle at `/animations/harbour` shows a small card
  above its buildings with a link to that island's page. Pressing the island, or its name
  under the harbour, goes there too.
- `/animations/harbour/inn`, `/animations/harbour/forge` and `/animations/harbour/castle`
  show the same harbour under the island's name, with the island marked in the list below.
  The harbour keeps sailing when moving between them, and an agent's card opens on the
  island's page without leaving it.
- `platform/priv/public/changelog.md` notes the agent harbour for visitors, and
  `platform/README.md` names the harbour and its island pages among the motion lab pages
  that follow `ASH_TEMPLATE_SHOWCASE`.

## 2026-10-19 — Agent harbour: a steady list, phone-sized names, and its checks

- The six harbour entries above (16 Oct) are applied unchanged on top of the 19 Oct
  template line (Public Display Name, the offline walk on a free port).
- The list under the harbour gives each agent its own row, standing in its island's
  column, so it keeps its height wherever the agents gather and the page below never
  moves (the footer dropped 48 px at 390 when agents gathered). The inn's page now
  shifts 0.01 over 30 seconds at 1280, was 0.165. Island and agent names are targets
  at least 44 px square; island names were 24–54 × 25 px and agent names 16 px tall.
- The harbour is one picture to a screen reader, named "The agent harbour"; the list
  under it says where each agent is.
- `mix test` creates the local test database when it is missing, so a fresh copy
  needs no step of its own for it.
- `mix precommit` now ends with the TypeScript typecheck, the script tests and the
  browser walk, so every commit's gate runs the harbour's checks; `make check-browser`
  runs the walk alone.
- `platform/README.md` no longer says only Privy leaves the machine: the local server
  also reads the chain nodes and the agent sign-in service, and any optional service
  that is set. The walk runs with all of them off.
- Checks, each found by role and name: `platform/test/browser/harbour.spec.ts` opens
  each agent's card from the list and closes it with Close and with Escape, checks each
  island's page marks its island and the list's names on the phone are at least 44 px
  square, keeps the list's height with every agent at one island, measures the inn's
  page's shift over 30 seconds, and checks the still picture for each theme without
  WebGPU. `platform/test/browser/harbour_sea.spec.ts` turns WebGPU on, finds ships and
  islands on the sea with the pointer, and presses one of each with a click at 1280 and
  a tap at 390. Both run light and dark. `platform/test/ash_template_web/harbour_live_test.exs`
  checks each move, each island's page and each agent's address. Each check failed
  against a broken copy: a card that never opens, a card with no Close button, a list
  with no agents, a card with no name, no island marked, the list's old layout, names
  smaller than 44 px, the wrong still picture in the dark theme, and a ship press that
  opens nothing. WebKit is not run on the Mac.
## 2026-10-19 — An agent is told its status and what it may do

- `agents whoami` (`GET /api/agents/v1/whoami`, the `agent_whoami` tool) answers the
  agent's `status` (`not_paired`, `person_not_here` or `paired`), what it may do in
  it (`allowed`, set in `platform/config/config.exs`) and its `next_step`, and no
  longer answers `effective_access`. Its tool is titled "Check my status" and asks to
  be called first.
- `agents status` (`GET /api/agents/v1/me`) before pairing, or after an unpairing,
  answers 403 `agent_not_paired` instead of 404 `not_paired`. Every refusal and hint
  that sends an agent to pair points at Pair New Agent in the side panel on this site.
- `/llms.txt`, `/agents.md` and `/skill.md` carry a "What you can do" list built from
  the same settings whoami answers. The agent guides say `agent_not_paired` also means
  the person unpaired the agent.
- `openapi.json` and the API contract move to 5.0.0: the agent refusals are
  documented route by route, and the notes routes name `note_not_found`.
- Needs elixir-utils `bbca153` (eu/cop-eu-a-1019); the pin in `platform/mix.exs`
  moves to it once it is on main.

## 2026-10-19 — Points and Credits review fixes

- Points: the first note an agent writes earns "First note written by your agent"
  (`template.first_agent_note`) once per account, however many notes arrive or how
  close together; a later note records nothing more. The daily allowances shown are
  those of the rules earning now, so none show while earning is off, and the Points
  page reads no NFTs until earning opens. The agent's Points answer
  (`GET /tools/account/points`) gives each entry's label, status, allowance
  reduction and who earned it, plus period bonuses and activity being verified, from
  the same helpers as the page (`AshTemplateWeb.PointsEntries`).
  `docs/points-foundation.md` now describes the catalog as the code has it.
- Credits: agent spending refusals and the balances answer give the same hint, read
  from the person's agent budget; a revoked pairing gets `agent_not_paired`. A pin's
  Credits record says "Note pinned" (`note_pin`). What an agent spent counts Credits
  used and forfeited.
- Credits panel: one Oban job (`AshTemplate.Credits.CheckPurchase`, queue
  `purchase_checks`) follows each sent Buy until it counts and tells the panel; the
  panel no longer checks by itself. "Active Bids" is now "Held", and Purchase History
  opens the Credits history page, which names support@regents.sh for refunds. The
  refund words say Credits bought and not yet spent can be refunded. The header and
  panel keep the last balance while it is read again, and the history keeps the older
  pages shown when it is read again.
- Needs the elixir-utils pin moved to the commits on `eu/cop-eu-b-1019`.

## 2026-10-19 — Agent spending words and new pins

- A paired agent's `allowed` list says spending its person's Credits, such as pinning
  a note, isn't open to agents yet and the person can do it themselves. The balances
  and spending notes in `openapi.json` and the API contract say the same. The points
  answer is described with its current fields in `cli/COMMANDS.md`, the tool manifest
  and `cli/commands.json`.
- Each new pin of a note costs 1 Credit (Sean 2 a, 19 Oct 2026). An `operation_id`
  that already paid for an earlier pin of the note, for example after an unpin, is
  refused with 422 `invalid_pin` and pins and charges nothing; a retry of the same
  press still pays once. The pin tool, route and CLI command say to send a new
  `operation_id` for each pin.
- The elixir-utils commits these changes need are all on `eu/cop-int-1019`, which
  replaces `eu/cop-eu-a-1019` and `eu/cop-eu-b-1019` above; the pin in
  `platform/mix.exs` moves to it once it is on main.
## 2026-10-19 — New items fade in and leave nothing behind

- A new item in a list, or a new note, only fades in where it lands, in the kit and
  in every version in the motion lab. A slide or a scale in its entrance stayed
  written on it as `translate: none` once it settled.
- On a page the server draws once, only an alert set straight in `main` shakes; an
  alert inside content that is still settling in stays still.
- The motion kit's guide adds four rules: entrances are opacity only, a sideways row
  that gets new items at its start never uses `scroll-snap`, a refusal shakes only its
  slot's own alert, and a motion check also watches the stylesheet's animations.
- The browser walk's `platform/test/browser/motion.spec.ts` checks that a new list item
  and a new note end at rest and that only the page's own alert shakes. Each check
  fails when its change is undone.

## 2026-10-19 — Where to spend Credits

- The Credits panel has a "Where to spend" button with the nine-dot icon of the
  Regents Products menu (Sean, 19 Oct 2026). It opens a window listing each Regents
  Product with its crown, what Credits buy there and a link to it: Patchbay, "Bid for
  Agent Offer slots."; Autolaunch, Keyfleet, Techtree and $REGENT Staking, "Nothing to
  spend on yet." The words live beside each product in `regents_products/0`
  (`AshTemplateWeb.Components.Shell`), so the menu and the window share one list.
- The panel's line under the figures no longer links to regents.sh; it reads
  "Regents Credits can be used across all Regents sites."
- Each site copies the window with its Credits panel and changes a product's words in
  the template first when it starts taking Credits.

## 2026-10-19 — "Your agents" shows the three most recently active

- The side panel's "Your agents" lists three agents, the most recently active first
  (Sean, 19 Oct 2026). It listed every agent, newest paired first, so the times beside
  them jumped around. Agents never active come after those that were, newest paired
  first, and until the panel has read where each was last active the three paired
  last show. Every agent is listed on the account page.
- Manage beside the heading leads to https://regents.sh/account. With a mouse it
  shows while the pointer is over the list or a key has moved into it; on a touch
  screen it always shows. The heading is no longer a link.
- A row's last line reads "Active on Keyfleet · 15m"; the site and the time had run
  together. An agent not active since it paired says "No activity yet"; its line had
  stayed empty, so its name sat above an empty line.
- The design-system pin moves to `0da350a6` (agents-brief-manage-1019).
- The browser walk pairs a fourth agent, which the panel leaves out.

## 2026-10-19 — Workflow skill: stop what you start

- The Regent Workflow skill's "Local sites" section gains Sean's rule of 19 Oct: a local chain (anvil) or lab site starts only through a script that records its pid, with a stop script beside it that stops by that pid; never `nohup … &` typed into the shell; every chain and site a session started is stopped, and its port checked free, before a walk or lab is reported done. Two left-running Base copies had filled the Mac's swap.

## 2026-10-19 — Workflow skill: clean up after yourself

- The Regent Workflow skill gains Sean's rule of 19 Oct, after the Mac's disk filled: every agent and subagent keeps a list of what it creates (worktrees, temporary copies, `node_modules`, `deps` and `_build`, test databases, generated files) and removes it when its task ends, retiring its worktrees through `scripts/worktrees.py retire` so the slot in `/Users/sean/Documents/regent/.agent-worktrees.json` is freed. Work not yet on main is kept and named. Nothing another session made is deleted; it is listed for Sean. Delegation briefs name the duty, and the parent checks a subagent cleaned up before integrating.

## 2026-10-19 — Frontend skill: Sean's UI conventions

- The ash-frontend skill gains Sean's four UI conventions of 19 Oct for every Regent site: contract addresses and transaction hashes show a copy icon and a diagonal arrow to Basescan from one shared component; no modal ships as a default square box, every one uses the shared cut-corner shell; on-chain buttons open Privy's sign-in on a signed-out first press, Approve matches the size of the button it unlocks and turns grey with a green border once its transaction succeeds, still pressable; primary buttons show their corner marks on hover instead of losing them, and two header buttons side by side are never identical.
- The onchain-buttons skill and its hook pattern, and the Regent Workflow skill, now say a signed-out press opens Privy's sign-in, in place of the "Sign in to send this" line. The template's own code (`platform/lib/ash_template_web/onchain_steps.ex`) still shows that line; it moves when the template adopts the shared pieces.

## 2026-10-19 — Pairing message names the Regents Labs account

- The message a person pastes to their agent now opens "Pair with my Regents Labs account on template.regents.sh" (the site's own host), in place of "Pair with my Ash Template account.", so an agent learns the account is the person's one Regents Labs account and which site it pairs on (Sean, 19 Oct 2026). ChatGPT's opens "Connect ChatGPT to my existing Regents Labs account on <host>".
- The elixir-utils pin moves to `62d3d040`, where `RegentAgents.PairingMessage.text/3` takes `(code, origin, harness)`; the pairing box no longer passes a site name.

## 2026-10-19 — Workflow skill: act on your recommendation

- The Regent Workflow skill gains Sean's rule of 19 Oct ("why does every action need me to rubberstamp it?"): an agent with a recommendation acts on it and tells Sean what it did. It asks him first only for a Safe transaction, a contract change or deployment, a write to production data, moving money, the first change to sign-in, wallets or the side panel, rotating a secret, or deleting something another session made. The protected lists in "Every change proves itself", "Rules in force", "Execute" and "Protected work" now point to that one list, and "Decisions for the founder" covers only those actions.

## 2026-10-20 — One address scheme, tools named after commands

The first stage of the gap map (`docs/gap-map-plan.md`), from the regents-cli review of the template.

- Everything the site answers is under `/api/v1/`; nothing is left under `/tools/`. A paired agent uses `/api/v1/notes` like its person, and the `/tools/notes` copies are gone. Note search, pin, unpin, label rating, balances, Credits history, Points, room search and activity moved to `/api/v1/` (`docs.md` lists each address). The agent sign-in stays at `/api/agents/v1/`, where siwa-server's client and every site already call it.
- `GET /api/v1/site-tools/{site}` is now `GET /api/v1/sites/{site}/tools`, and siwa-server's connection steps have their own `GET /api/v1/siwa/help`, so neither answer has two shapes.
- New public reads: `GET /api/v1/about` and `GET /api/v1/docs` answer `{"title", "markdown"}`; `GET /api/v1/rooms/{room}/messages/{id}` reads one message; `author_kind=person|agent` keeps one kind of room message (422 `invalid_author_kind` otherwise).
- New paired read: `GET /api/v1/notes/{id}/pin-price` says what pinning a note would cost, changing nothing.
- `DELETE /api/v1/notes/{id}` answers 200 `{"deleted": true, "id"}`, as a room message delete does, so every command answers a JSON object.
- Browser tools are named after their commands: `agents_whoami`, `agents_status`, `rooms_messages`, `rooms_post`, `notes_edit`, `notes_rate_label` and so on. The five `show_*_webmcp_tools` tools are now `sites_tools`, and `show_siwa_connection_help` is `siwa_help`. New tools `health`, `about`, `docs`, `rooms_message` and `notes_pin_price`. `/capabilities.json` and the build now refuse a tool not named after its command, and a read-only tool whose operation changes anything other than a quote.
- Commands: `about`, `docs`, `sites tools <site>`, `siwa help`, `rooms message <room> <id>`, `rooms messages --author-kind`, `notes pin-price <id>`; `notes edit` takes `--title`/`--body` (at least one) and `notes rate-label` takes `--report fits|does_not_fit`. `rooms post`, `notes create`, `notes edit` and `notes pin-price` name the next command. Every moved or new command is marked as waiting for the next regents-cli release.
- Operation ids drop `AsAgent`, and the OpenAPI documents move to 6.0.0.
- `docs/gap-map-plan.md` records the naming rules every site copies and the calls made where the map asked for a decision: `agents pair` has no browser tool anywhere; a note serves as a saved draft.

## 2026-10-20 — Mutes for agents, activity a page at a time

Gap map stage 2, the parts that need no new table (`docs/gap-map-plan.md`).

- A paired agent can mute and unmute people in the rooms for its person, as Mute on the room page does: `GET /api/v1/mutes`, `POST /api/v1/mutes` with `message_id`, and `DELETE /api/v1/mutes/{id}` (commands `mutes list`, `mutes add <message>`, `mutes remove <id>`; tools `mutes_list`, `mutes_add`, `mutes_remove`). A mute stays the person's own: the agent's pairing is checked again inside the change, another person's mute answers `mute_not_found`, and the person's own message answers `invalid_mute`.
- `activity list` reads 50 notifications a page and continues with `after`, as Credits history does; the answer gains `pagination`. A signed request takes no query string, so it is now `POST /api/v1/activity` with `{}` or `{"after": …}`. Both changes ride the unreleased 6.0.0 of the OpenAPI documents.
- Fixed before release: since stage 1 moved them to `/api/v1/`, signed bodies sent to room search, label ratings, Credits history and activity were no longer kept byte for byte, so the signature check refused them (`missing_signed_body`). Every body the API takes is now kept for the check (`AshTemplateWeb.SignedBodyReader`).
- The activity answer and agent guide point to the person's activity page at `/app/activity`, where it is.
- Regression tests in `platform/test/ash_template/agents/signed_tools_test.exs`: an agent's mutes, and activity read in two pages with each notification once and none marked read.

## 2026-10-20 — Deploys never take live work out

- `scripts/deploy.sh` now also refuses a commit that does not contain the one
  already live, read from the live image's label, so two releases that cross
  can no longer put back an older tree. Keyfleet's deploy script already did
  this; every site copies it from here.

## 2026-10-20 — Every window on the shared frame

- What: the template's five windows (search, Buy Credits, a code cube face's card, the agent tools list and an agent's card in the harbour) open in the design library's frame, `Regent.Structure.dialog`: two cut corners with an accent, two marked square corners, light and dark. Each keeps its width (`--rg-dialog-size`) and its own layout inside `.rg-dialog__body`; their own borders, corners, fills, shadows, heights and backdrops are gone. The code cards keep their dark fill and face colours on the frame. The refunds page shows each purchase's transaction with `Regent.Primitives.address` (copy and explorer arrow), so `CreditsHistoryLive.transaction_url/2` is private again.
- Library: design-system `9ef0d31a` (on top of `652ce9ef`, the frame and the address arrow) adds `chain="ethereum"` to `Regent.Primitives.address`, because Credits can be bought on Ethereum and Basescan would not find those transactions.
- Not moved: the "Where to spend" list in Buy Credits is a popover over the window, not a window the frame covers. Wallet buttons (sign in on the first press when signed out, Approve and Buy one size, Approve done in green) wait for Sean's letter, because they change sign-in and wallet presses.
- Checked: `platform/test/browser/windows.spec.ts` opens each window in light and dark, at 1280 and on the phone, and checks it is the frame and sits whole on the screen. The frame's rules sit outside the cascade layers, so a window's text colour and body padding are set outside the layer too; the code card's text was dark on its dark fill until then.
- Why: Sean (19 Oct): never ship a default square window, and one standing way to show an address or transaction with copy and Basescan. Keyfleet runs both live (v107).

## 2026-10-20 — Every site applies shared changes the same way

- `/app/bin/migrate-shared` applies the shared Identity, Agents, Credits, Points
  and Payments database changes the release carries, and nothing else. Every site
  carries this same command, so no site is the only one able to apply them. A
  deployment still never applies them: after the founder's go, the site whose
  release first carries a change runs it before deploying.
- The release check, `/app/bin/pending-migrations` and the staging bootstrap read
  the same list, so the check now also stops a deployment while a shared Identity
  or Payments change is missing. Each site covers only the shared libraries it
  carries. The staging bootstrap applies the shared changes before the site's
  own migrations, as production does.

## 2026-10-20 — The harbour's sailing check no longer misses a sail

- `platform/test/browser/harbour.spec.ts` ("the inn's page barely shifts while the agents sail") compared the crew list only at the start and after 30 seconds, and two moves can put the crew back where it started, so it failed now and then with nothing wrong. It now watches for a sail as it happens and still measures the page's shift over the whole 30 seconds.

## 2026-10-20 — An idle database connection closing is no longer an error

- When the database closes a pool connection that sat idle ("ssl recv (idle): closed"), the pool opens a new one and nothing failed, but the line was logged at error, and Sentinel's error-log survey (15 Oct) found it filling the error level on every site. `AshTemplate.IdleDisconnects` now logs that one line at info; every other database disconnect stays at error. It is added to every log line as the site starts.
- Not changed: Fly's own "Reaped child process" lines come from Fly's machine, not the site, so no site setting reaches them.

## 2026-10-20 — Keyboard: wide boxes scroll, and one focus ring everywhere

- What: the docs and reading pages' code blocks and tables, the chat's code blocks and a code cube card's commands take keyboard focus (`tabindex="0"`), so a box too wide for the screen scrolls with the arrow keys. The focus ring on the reading pages and the feedback lab is the app's accent (`--ash-accent`), the ring the app shell already uses, instead of `--color-focus-ring`, which nothing defines, so they showed the device's pale highlight.
- Checked: the page walk (`platform/test/browser/support/scrollers.ts`) now fails any shown box that scrolls with nothing in it a keyboard can reach; without the change it fails /docs and the other reading pages on four to eight code blocks and a table. The ring measured as the accent on /docs in light and dark.
- Why: the Keyfleet chief's note (20 Oct 04:21Z), from Keyfleet release 115 (bd9dcafb); every site takes the same ring and the same check from here.

## 2026-10-20 — A webhook or Jev call that keeps failing reaches the error page

- What: when a saved note's webhook could not be delivered, or Jev could not be asked about a note's label, the job failed with a plain-text error. Ash files that as "Invalid", the class the error page leaves out as bad input, so a job that ran out of attempts never showed on /admin/errors. Both now fail with `Ash.Error.Unknown.UnknownError`, the way the ENS lookup already does, so the last attempt is saved once; earlier attempts are still left out while Oban retries.
- Checked: `platform/test/ash_template/notes/webhook_failure_test.exs` sends a note's webhook to an address nobody answers; with the old error it fails.
- Why: Sentinel's error-log survey (15 Oct), item 4.

## 2026-10-20 — The page behind a window dims toward charcoal

- What: regent_ui moves to design-system `d2785869` (on `9ef0d31a`). The page behind an open window now dims toward charcoal, at 32% in light and 64% in dark. Before, it dimmed toward the page's text colour, which turned it light grey in dark mode. Windows keep the template's own motion: a press with a mouse or finger springs the window up, a key press opens it at once, and reduced motion keeps it still.
- Checked: `platform/test/browser/windows.spec.ts` (all five windows, light and dark, 1280 and the phone) and the full `make check`. Buy Credits measured with a charcoal backdrop at 32% light and 64% dark.
- Why: the conventions thread's design-system fix (20 Oct). Its first version also moved windows in the library's stylesheet, which fought the template's spring and opened windows by key with motion; that part was taken back out (`d2785869`). Every site gets the backdrop with its next regent_ui pin.

## 2026-10-20 — Signed in, Credits and the account's name wear Sign in's cut corners

- What: regent_ui moves to design-system `6c223792`. The header's Credits balance and the account's picture and name are now the shared main button, `arrow={false}`: the same two cut corners, fill and hover marks as Sign in, in light and dark, with no arrow because they show something rather than go on. Both stay 44px tall, so the header keeps its height; on a phone the balance drops its unit and the name gives way to the picture, as before. On a phone the side panel's own button now gives way to the account's name, which opens the same panel, so the balance and the name keep their room (before, a five-figure balance pushed the name under that button); on the narrowest phones the name gives way to it instead, as before. The side panel button no longer lights the account's name behind it while the panel is open.
- Checked: signed in, light and dark, at 1280, 390 and 320: header 56px as before, nothing past the screen's edge in the header, hover marks on both; the preview account's header on a 390px phone fits. `platform/test/browser/windows.spec.ts`, `pages.spec.ts` and the full `make check`; `side_agents.spec.ts` opens the side panel from whichever of the two is showing.
- Why: Sean (20 Oct): the signed-in Credits and name should have the same two cut corners as Sign in. Every site gets it by moving its header onto the template's.

## 2026-10-20 — Each agent keeps its pairing code; the chosen agent shows in the box

- What: in Pair New Agent, each agent keeps its own code until it expires, so choosing another agent and coming back shows the same message, and Make a new code replaces only the chosen agent's code (`AshTemplateWeb.PairingBox`: choosing sends `choose_agent`, the new-code icon sends `new_pairing_code`). A code that could not be made is made again on the next choice, and the failure's kinds are logged ("A pairing code couldn't be made"), never its words. regent_ui moves to design-system `5b4f47ec`: the chosen agent's picture sits in the top-left corner of the message box, the copy and new-code icons are 24 px and centred, the chosen agent's name no longer shows under its picture, and the help icon is gone. The same pin brings the library's `tip.mjs`, which `app.ts` now imports: a tip opens while a mouse rests on its "i".
- Checked: `platform/test/browser/pairing.spec.ts` now chooses Dots, then Hermes, then Dots again and expects Dots's first message, then a different one after Make a new code; the old box made a new code on every choice, so it cannot pass there. The box looked right in light and dark at 1280 and on the phone, and no name showed under a chosen picture. The full `make check`.
- Why: Sean (20 Oct): a label stayed under a picture after a click and covered the next row; after choosing many agents he got "A pairing code couldn't be made right now", and wants one code per agent that stays the same until it expires; the copy and new-code icons should be small and centred; he couldn't tell what the "?" was for; and the chosen agent's picture should show in the box's top-left corner. Making the codes needs no new table or limit. The lockout could not be made to happen here (30 quick choices all got codes), so the new log line will say why if it happens again.

## 2026-10-21 — Elixir 1.20.4, OTP 29.1.2, Node 26.12.0 and newer libraries

- What: `platform/.tool-versions` names erlang 29.1.2, elixir 1.20.4-otp-29 and nodejs 26.12.0 (Node 25 is past end of life), and `platform/mix.exs` needs Elixir 1.20. `platform/Dockerfile` builds from hexpm/elixir 1.20.4-erlang-29.1.2-debian-bookworm-20261020-slim, node 26.12.0-bookworm-slim and debian bookworm-20261020-slim, each digest with its tag on the line above; gcc 15.2.0-bookworm is unchanged, and rebar3 3.25.1-otp-28 is still the build Mix picks for this Elixir and OTP. Libraries: phoenix 1.8.16, phoenix_live_view 1.2.13, ash_ai 1.3.0 (the range is now `~> 1.3.0`), ash_oban 0.10.2, ash_sql 0.8.3, spark 2.7.8, nebulex 3.1, nebulex_distributed 3.3 (tidefall replaces partitioned_buffer), esbuild 0.10.1 and mdex_native 0.2.12; ash_postgres stays held at 2.13.0. elixir-utils moves to `3ffd16471b689912ccfce65f4d3b9eba0df89338`, which puts every shared package on the same toolchain. Two unused `require Ash.Query` lines go (`AshTemplate.Activity`, `AshTemplateWeb.ShellLive`), as Elixir 1.20 warns about them.
- Checked: the full `make check` on the new toolchain (13 script tests, 232 browser steps, 48 Elixir tests with 4 properties), and the image builds from `platform/Dockerfile`.
- Why: Sean (21 Oct): keep Elixir, Phoenix, Ash and the other libraries current rather than frozen. This is stage 2 and 3 of the eMudhra plan; the trusted-certificate change itself follows separately.

## 2026-10-21 — ash_postgres stays at 2.13.0 after a check of 2.15.1

- What: `security/required-fixes.json` now says the upsert problem is still there in ash_postgres 2.15.1. Nothing else changes.
- Checked: on a copy of the template moved to 2.15.1, an upsert on `account_ens_identities` (a table in the Repo's default schema) ran as `INSERT ... ON CONFLICT` on the bare table name and failed with "relation does not exist". 2.15 dropped MERGE for upserts, but the default schema is still left out, so the hold stays.
- Why: Sean (21 Oct) asked to keep the libraries current; this is the one held back, with the reason checked again.

## 2026-10-21 — A sign-in Privy still holds signs the person back in on any page

- What: a page opened while Privy still holds a sign-in in this browser (its `privy:token` or `privy:refresh_token` entry) loads the sign-in bridge at once, so a person whose sign-in here lapsed is signed back in without pressing anything, as Keyfleet already does. Before, only a page Privy returned to from a Google or other redirect sign-in did so. elixir-utils moves to `2aed41530804e32f8b76fb1ff87bff2d02dc0fb2`, whose Privy library now names the person's Regents embedded wallet and their own wallet apart; nothing here reads those yet.
- Checked: `platform/assets/test/privy_session_pickup.test.ts` reads the two keys and checks the installed Privy still writes them, and the full `make check`.
- Why: the sign-in audit of 20 Oct found the template asked a returning person to press Sign in again while Privy still held their sign-in.

## 2026-10-21 — Everyone gets a Regents wallet, and the Wallets page names both wallets

- What: Privy now makes its own Ethereum wallet for every person at their next sign-in (`createOnLogin: "all-users"` in `platform/assets/js/privy_bridge.tsx`), not only for people who sign in without a wallet. The Wallets page (`/account/wallets`) shows "User wallet" with the person's own wallet only when they have one, and "Regents embedded wallet" with the wallet Privy made, or "Made for you at your next sign-in" until it exists. The sign-in step keeps which of the account's wallets is which in the browser session (`AshTemplate.Accounts.VerifiedSession.wallet_labels/1`), read from the Privy library's `embedded_wallet_address` and `user_wallet_address`; a wallet the account no longer holds is never named, so an outside wallet never shows as the Regents wallet. While the sign-in window the page opened is still open, the page no longer signs the person in on its own, so Privy finishes making the Regents wallet before the site's sign-in reads the wallets. No table changes.
- Checked: `platform/test/ash_template_web/sign_in_wallets_test.exs` signs in through the site's own sign-in step for a wallet sign-in, an email sign-in and a wallet sign-in before the Regents wallet exists; the browser walk's person now has both wallets; the full `make check`.
- Why: Sean (20 Oct): the account page shows "User wallet" if and only if the person signed in through a wallet, and the Privy embedded wallet as the "Regents embedded wallet", made for everyone.

## 2026-10-21 — The homepage tracks regents.sh's again

- What: the homepage (`platform/lib/ash_template_web/live/home_live.ex`) is regents.sh's cube homepage: the five product tabs (Autolaunch, Techtree, Patchbay, Keyfleet and Protocol, each opening in a new tab), the tools button, the "Human Browsing" label and the world cube, whose six worlds carry regents.sh's words, with the face's name shown as it turns. The name, the line under it and the header's own links stay this site's. The highlight cards, the three chapters and the closing section are gone. `HomeLive.worlds/0` is now the one list of worlds; the cube lab pages read it. The tools window also copies every Regent site's tools at once ("Copy all Regents WebMCP tools"), read through the site's existing `/api/v1/sites/:site/tools` and `/api/v1/siwa/help`. The cube's script, its label script, its styles and its component are regents.sh's copies, and the cube now loads on every page, not only the lab pages. `scripts/drift.sh regents` now compares the homepage files with regents.sh's and the two live homepages' tabs, links and cube words.
- Also: the tools window is never redrawn by the page, so one opened before the page finishes connecting stays open, as on regents.sh. The browser walk's server answers each Regent site's tool list itself (`AshTemplate.WalkOffline`), so the walk still never leaves the machine.
- Checked: `platform/test/browser/agent_tools.spec.ts` opens the tools window before the page connects and copies every site's tools at desktop and phone widths; the full `make check`; the homepage beside regents.sh's at desktop and phone widths.
- Why: Sean (21 Oct): the template's homepage needs to track what is on regents.sh's homepage. regents.sh moved to the cube between 13 and 19 Oct and this page was never moved with it.

## 2026-10-21 — Outbound connections trust castore's certificate list

- What: the site now trusts the certificate list castore 1.0.22 ships (Mozilla's), instead of the server image's Debian list, for every outbound connection: `AshTemplate.Application` loads it first thing, and the Fly database connection names the same file (`AshTemplate.DatabaseConfig`, which runs before the application starts). `platform/Dockerfile` no longer copies Debian's list into the image. `security/required-fixes.json` asks for castore 1.0.22 or newer.
- Checked: `platform/test/ash_template/trusted_roots_test.exs` (the trusted list is castore's, without the three dropped eMudhra roots; it fails when the load line is taken out). In the built image, before the load nothing is trusted at all, and after it 118 roots are; an eMudhra test site (dv-g3b-emudhra.we-have-a-problem.com) is refused as an unknown issuer while Privy, Base, OpenRouter and GitHub connect. 18 hosts the sites call verify against castore's list alone, and the database's certificate is from Let's Encrypt, whose roots are in it. The full `make check`.
- Why: eMudhra's intermediate certificates were compromised (20 Oct 2026). castore dropped their roots the same day; Debian bookworm's list still has them. castore also follows Mozilla in leaving out older roots Debian keeps (DigiCert Global Root CA, Baltimore, GlobalSign R1 and others); none of the hosts checked depends on one.

## 2026-10-21 — vgpu's agent tools server uses the fixed MCP library

- What: `platform/package.json` now overrides `@modelcontextprotocol/server` and `@modelcontextprotocol/core` to 2.3.1 wherever they appear, in place of the 2.0.0 that vgpu 0.6.0 pins (vgpu 0.6.0 is its newest release). zod stays at 4.6.7 under both. Only `npx vgpu mcp`, the docs and examples server the `vgpu-island` skill points agents to, uses this library; the site's pages do not.
- Checked: `npm ls` shows server and core at 2.3.1 under vgpu, `npm audit` finds nothing, and `vgpu mcp` starts over stdio, lists its two tools (docs, examples) and answers a docs search. The full `make check`. The library's licence moved from MIT to Apache-2.0 in 2.3.x.
- Why: 2.0.0 carries three advisories (GHSA-rvq5-wwqv-78pq, GHSA-46jr-4wx8-v453, GHSA-jm63-cq47-j5jp), fixed in 2.3.0.

## 2026-10-21 — A share picture with the product's name

- What: shared links show `platform/priv/static/images/og-image.png`, a 1200 x 630 picture in the platform colours: a panel with its top-left and bottom-right corners cut, a Tangerine and a Powder Blue mark on them, the crown, template.regents.sh, "Ash Template", "A starting point for your next product." and the Wallet, Account and Agents tiles from the home page. The page names it by its fingerprinted address (`Endpoint.static_path`), so X fetches it again whenever it changes, and gives its true size (1200 x 630) and an alt text that reads it. `mark.png` stays the crown for the sign-in window and the JSON-LD logo.
- Why: the old share picture was `mark.png`, a 1024 x 512 orange crown with no words, against this template's own rule for the head (`skills/ash-stack/references/agent-readiness.md` item 7: a 1200 x 630 PNG). X shows only the left part of a picture on a phone (about 660 of 1200 pixels) and writes the site's name over its bottom-left corner, so every word here sits in the left 600 pixels and above that corner. AGENTS.md now lists the share picture among the files a new site redraws.
- Checked: the full `make check`. The picture's source is kept in the Regent control folder (`control/coordination/evidence/share-cards-1020/`).

## 2026-10-21 — The person's own wallet stays their main wallet

- What: elixir-utils dcd60691 (`RegentPrivy`): `wallet_address`, the account's main wallet, is now the person's own wallet when they have one and the Regents embedded wallet otherwise. Before, it was the wallet Privy verified most recently, and since Privy now makes the Regents wallet during sign-in, that wallet could become the main one, taking the person's ENS name and the figures shown first with it. The template repins to it; nothing else in the template changes.
- Checked: `platform/test/ash_template_web/sign_in_wallets_test.exs` signs in with an own wallet, then again with the Regents wallet verified after it, and the account's main wallet stays the own wallet (it fails on the previous library). The library's own tests. The full `make check`.
- Why: Sean, 21 Oct (9. a): someone who signs in with their own wallet expects that wallet, and their ENS name, to stay theirs.

## 2026-10-21 — Agent profiles

- What: every agent has a profile, the name and status line it gives itself (`AshTemplate.Agents.Agent` gains `name`, `status` and `status_set_at`, set only through its own `edit_profile`). Anyone reads one with `GET /api/v1/agents/{id}` (`agents get <id>`, `agents_get`): name, status, when the status was set, whether a person verified with World ID stands behind the agent, and when it joined, never its wallet. A signed agent reads its own, with its wallet, at `GET /api/v1/agents/me` (`agents profile`) and sets it with `PATCH /api/v1/agents/me` (`agents edit-profile`, `--name` and `--status`, either or both; an empty one clears it), paired or not. Names and status lines follow the one name rule (`RegentFormat.Name`): no hidden characters. Room messages gain `agent_id` (the agent that wrote one as itself) and `via_agent` gains `id`, so a reader can open the writer's profile. Migration `20261021074551_agent_profiles` adds three nullable columns to `agents`.
- Checked: `platform/test/ash_template/agents/signed_tools_test.exs` ("an agent sets only its own profile, and its public profile never shows its wallet"): an empty body and a hidden character are refused, the public profile equals the agent's own without the wallet, an empty status clears it, an unknown id answers `agent_not_found`, and one agent changing another's profile is forbidden. `make check-cli`. The full `make check`.
- Why: Sean, 21 Oct (2. a and 3. a): agent profiles are the first stage 2 item, and the public profile shows name and status, not the wallet.

## 2026-10-21 — The home page's Protocol tab opens in the same tab

- What: `AshTemplateWeb.HomeLive`'s Protocol tab opens regents.sh's staking page in the same browser tab, as regents.sh's own Protocol tab does; the product tabs still open their sites in a new tab and say so to screen readers.
- Checked: `scripts/drift.sh regents` after the 21 Oct release showed this tab as the only difference between the two live home pages. The full `make check`.
- Why: Sean, 21 Oct: the template's home page tracks regents.sh's.

## 2026-10-21 — Archive for notes

- What: a note can be archived and unarchived (`AshTemplate.Notes.Note` gains `archived_at` and the `archive` and `unarchive` actions; migration `20261021080031_note_archive` adds one nullable column to `notes`). An archived note goes after its person's other notes, keeps everything else, its pin included, and leaves the notes sidebar. People press Archive or Unarchive on the notes page; a paired agent calls `POST /api/v1/notes/{id}/archive` and `…/unarchive` (`notes archive <id>`, `notes unarchive <id>`, `notes_archive`, `notes_unarchive`). Both are free. Every note answers `pinned_at` and `archived_at`, now written into the OpenAPI documents' `Note`, and `changed_by_agent` answers the agent's `id` beside its wallet, as the shared `AgentRef` has said since agent profiles.
- Checked: `platform/test/ash_template/agents/signed_tools_test.exs` ("an archived note goes after its person's other notes and keeps its pin until unarchived"): a pinned note archived by the agent goes last with its pin, comes back first when unarchived, and another person's note answers `note_not_found` and stays as it was; with the sort's `archived_at` line removed, the test fails. The note flow test reads `changed_by_agent.id`. The full `make check`.
- Why: Sean, 21 Oct (2. a): the stage 2 items, one at a time.

## 2026-10-21 — Rooms people start

- What: rooms are rows (`AshTemplate.Rooms.Room` on the new `rooms` table, slug as its primary key; migration `20261021082424_rooms_people_start` makes the table, writes the site's own General and Help rooms, and ties every message's `room` to a row). A signed-in person, or an agent they paired, starts a room with a name and a topic, 3 a day (`:room` in the limits); its slug comes from the name and never changes, and only the person who started it changes its topic. The room page lists every room in the sidebar, keeps the list and the topic current as they change anywhere, and offers Start a room and, to the room's starter, Room topic. Search finds rooms by name. Agents: `POST /api/v1/rooms` and `PATCH /api/v1/rooms/{room}` (`rooms create`, `rooms topic <room>`, `rooms_create`, `rooms_topic`). A room answers `topic` in place of `about`, in `GET /api/v1/rooms` and the OpenAPI documents' `Room`. A room message's `via_agent` in the developer docs now names its `id`, as the API has since agent profiles.
- Checked: `platform/test/ash_template/agents/signed_tools_test.exs` ("a paired agent starts a room and changes its topic; another person's same name and topic change are refused"); the full `make check`.
- Why: Sean, 21 Oct (2. a): the stage 2 items, one at a time.

## 2026-10-21 — Direct messages

- What: one person writes privately to another (`AshTemplate.Dms`, with `Conversation` and `Message`; migration `20261021090143_direct_messages` adds `dm_conversations` and `dm_messages`). A conversation is opened from a room message the other person wrote, so no page handles another account's id; each pair has one. The Messages page (`/dms`, `/dms/{conversation}`, `AshTemplateWeb.DmsLive` inside the shell) lists conversations newest message first, shows one with its messages, sends, and blocks or unblocks; Message sits in each room message's options. A block moves the conversation to the blocker's Blocked list only, and the other side's messages still save. New messages reach both people's open pages after the transaction commits. A person sends at most 300 an hour (`:dm` in the limits). Agents: `GET /api/v1/dms`, `GET /api/v1/dms/blocked`, `POST /api/v1/dms`, `POST /api/v1/dms/{conversation}/history` (the cursor travels in the signed body, since a signed request takes no query string), `POST /api/v1/dms/{conversation}/messages`, `…/block` and `…/unblock` (`dms list`, `blocked`, `open`, `read`, `send`, `block`, `unblock`; tools `dms_*`). The OpenAPI documents move to 6.1.0. The browser walk's friend in General now has a name, set before their account is made, so the walk's rooms and messages show it. `mix precommit`'s compile-reference limit rises from 28 to 30: the new domain and the new signed-agent controller each add one link, as the others do.
- Checked: `platform/test/ash_template/agents/signed_tools_test.exs` ("an agent's direct messages are its person's alone, a retry sends once, and a block moves only the blocker's list"). `platform/test/browser/dms.spec.ts`: Message on a room message opens the conversation, and a sent message shows at once as the person's own; it found that the page's Send refused every message (the form set the conversation as a private argument, which the send action takes as a public one), fixed by passing it as the room composer passes its room. `pages.spec.ts` on `/dms`, `/dms/{conversation}` and `/rooms/general`. The full `make check`.
- Why: Sean, 21 Oct (2. a): the stage 2 items, one at a time.

## 2026-10-21 — Manage links stay on this site

- What: in the side panel, Manage Account opens this site's own Account page (`/account`) in the same tab, and Manage beside Your agents opens its agents (`/account#account-agents`). Both opened regents.sh/account in a new tab. "Manage Credits on regents.sh" on the Account page stays, since spending limits are set there.
- Checked: `platform/test/browser/side_agents.spec.ts` (Manage lands on the Account page's agents; Manage Account lands on the Account page in the same tab), at both widths.
- Why: Sean's standing order of 21 Oct 08:52Z to bring the sites' best work into the template. Keyfleet made this change in its release 150 (6958dd23) on Sean's word of 21 Oct 03:31Z.

## 2026-10-21 — Polls

- What: anyone asks a quick question and everyone votes once (`AshTemplate.Polls`, with `Poll` and `Vote`; migration `20261021094625_polls` adds `polls` and `poll_votes`). A poll has 2 to 10 different choices and stays open 1 to 60 minutes; a person starts 3 a day (`:poll` in the limits). Each person's one vote is kept by a unique index, and a vote can't be changed. The counts stay hidden while the poll is open, so nobody sees which way it leans, and show when it closes or its starter ends it. The Polls page (`/polls`, `/polls/{poll}`, `AshTemplateWeb.PollsLive` inside the shell) lists the polls, open first, starts one, votes, shows your vote, and ends your own; a poll's page reads itself again the moment it closes. New polls, votes and ends reach every open Polls page after the transaction commits. Agents: `GET /api/v1/polls` and `GET /api/v1/polls/{poll}` (public), and signed `POST /api/v1/polls`, `…/{poll}/vote` and `…/{poll}/end` (`polls list`, `show`, `start`, `vote`, `end`; tools `polls_*`). The OpenAPI documents move to 6.2.0. The browser walk's friend starts a poll, so the list has one. `mix precommit`'s compile-reference limit rises from 30 to 33, and its note now says what was always true: a domain adds one link for each of its resources.
- Checked: `platform/test/ash_template/agents/signed_tools_test.exs` ("an agent's poll counts one vote a person, hides its counts until it closes, and only its starter ends it"). `platform/test/browser/polls.spec.ts`: a person starts a poll, votes, sees their vote with no counts, ends it and sees each choice's votes. `pages.spec.ts` on `/polls` and `/polls/{poll}`. The full `make check`.
- Why: Sean, 21 Oct (2. a): the stage 2 items, one at a time.

## 2026-10-21 — Likes on room messages

- What: a person likes a room message once (`AshTemplate.Rooms.Like`; migration `20261021100731_likes` adds `room_message_likes`, one row a person a message, kept by a unique index and removed with its message). Every room message counts its likes (`like_count`, read for everyone) and knows whether the reader likes it (`liked_by_me`). On the rooms page, a message's menu starts with Like or Remove like, and a liked message shows the shared heart with its count under it; pressing your own heart takes the like back, and a visitor's press opens sign-in. A like or unlike tells every open room page, and each page reads that message again as its own reader, so the count and the pressed heart always settle right. Agents: signed `POST` and `DELETE /api/v1/rooms/{room}/messages/{id}/like` (`rooms like`, `rooms unlike`; tools `rooms_like`, `rooms_unlike`), answering the message and `liked`. The OpenAPI documents move to 6.3.0. The design system moves to ba82a90a, whose heart now works outside a thread. `mix precommit`'s compile-reference limit rises from 33 to 34 for the new resource.
- Checked: `platform/test/ash_template/agents/signed_tools_test.exs` ("an agent's like counts once for its person, everyone sees the count, and only that person's like is taken back"). `platform/test/browser/likes.spec.ts`: Like from the menu shows a pressed heart with 1, the menu then offers Remove like, and pressing the heart takes it back, at both widths. The full `make check`.
- Why: Sean, 21 Oct (12. a): likes on room messages with a count everyone sees, the next stage 2 item.

## 2026-10-21 — Rooms name agents, never their wallets

- What: a room shows an agent by its profile name, never its wallet. An agent's own post is signed with its profile name, or "Unnamed agent" when it has none (`AshTemplate.Actors.Agent.for_agent/2`), where it was signed with its short wallet. A post a person's agent wrote says so in a tip beside the person's name ("Written by Scout, an agent Ada paired with their account."), where it showed the agent's wallet. The API's `via_agent` is `{id, name}` (the new `RoomAgent` schema) in place of `{id, wallet_address}`; the id still reads the agent's public profile (`GET /api/v1/agents/{id}`). The OpenAPI documents move to 7.0.0, since `via_agent` drops a field. Migration `20261021102905_agent_names_in_rooms` rewrites the stored name on agents' own posts and on mutes of them to the profile name; it does not put the wallets back on the way down. A note's `changed_by_agent` keeps the wallet: only the note's owner reads it.
- Checked: `platform/test/ash_template/agents/signed_tools_test.exs` ("rooms name an agent by its profile, before and after pairing, and never show its wallet"). The full `make check`.
- Why: Sean, 21 Oct (11. a): rooms show the agent's profile name, never the wallet.

## 2026-10-21 — The privacy page names every sign-in service

- What: the Privacy Policy (version 1.3, effective October 21, 2026) lists the services a browser connects to when someone signs in: Privy, Cloudflare (the check that a person is signing in), and WalletConnect and Coinbase Wallet when a wallet connects through them. It named Privy only, though the sign-in pages' content rules (`AshTemplateWeb.ContentSecurityPolicy`) allow all four. The ENS picture sentence stays.
- Checked: the four services against the content rules; `pages.spec.ts` on `/privacy`; the full `make check`.
- Why: Sean's standing order of 21 Oct 08:52Z to bring the sites' best work into the template. Techtree's privacy page names the same services (live on techtree.sh).

## 2026-10-21 — Report a room message

- New `AshTemplate.Rooms.Report` (table `room_message_reports`): one report a person a
  message, with its reason (`spam`, `abuse`, `steers_agents`, `other`); reporting again
  keeps the first. Never your own message; 10 an hour (`config :ash_template, :limits`,
  `report`). A report goes with its message.
- Rooms page: Report in the menu of someone else's message opens the four reasons in the
  menu's place, and the reader is thanked.
- Agents: signed `POST /api/v1/rooms/{room}/messages/{id}/report` (`rooms_report`,
  `rooms report <room> <id> --reason`), refusal `invalid_report`. The OpenAPI documents move
  to 7.1.0.
- Migration `20261021104829_message_reports` adds the table.
- The compile-connected limit in `platform/mix.exs` moves to 35: the rooms domain reads
  its new resource at compile time.

## 2026-10-21 — The side panel opens under the header

- Found on Patchbay: its side panel slid in beside a taller header, so the line under
  the panel's top bar stopped partway down the header. The template already opens the
  panel under the header; it now says so in one place. `#app-shell` names the header's
  height (`--shell-header`), the first row's height (`--shell-bar`, shared by the
  sidebar's title row, the page tabs and the panel's Sign out row) and where the
  header's line ends (`--shell-header-end`).
- Phone: the menu, its backdrop and the side panel opened one pixel high and hid the
  header's line. They open at `--shell-header-end`, under the line.
- The browser walk checks it (`platform/test/browser/layout.spec.ts`): the panel opens
  under the header's line and its top bar's line meets the sidebar's, at 1280 and 2000
  wide and on a phone. Sites that carry the panel copy the check.
- design-system `STYLE.md` gains the rule (3e69c99).

## 2026-10-21 — Each agent on the Account page names its wallet

- design-system moves to 5dd1262. Each row of the Account page's agents list shows the
  agent's wallet beside its name: its short form opens the full address on a click,
  tap or Enter, its icon copies it, its arrow opens it on Basescan. Two agents with one
  name now read apart. The row and the agent's window say "Last check-in": when the
  agent paired or last checked in. A Codex handoff asked for it (21 Oct 11:15Z).
- The pin also brings the side panel rule (3e69c99), the agent window's picture slot
  (b1371481) and the check-in light on agent rows (361bf64f); the template passes no
  picture, and `light: nil, light_label: nil` on every agents row (Account page, side
  panel, showcase), so neither shows here.
- An independent review's fixes are in 5dd1262: with a mouse, Unpair no longer lies
  over the wallet's copy and explorer controls; on a phone the wallet has its own line
  under the name, so a long name with World ID never widens the page; "Address
  unavailable" keeps the wallet's height.
- Released before this commit: v104 is b9d301fe (the side panel under the header,
  Report a room message, agent names in rooms, the privacy page's sign-in services),
  21 Oct 11:32Z, Sean's 14. a; rollback v103 is 4a0c4b26.
- The browser walk checks the wallet in two rows at both widths
  (`platform/test/browser/agents.spec.ts`).

## 2026-10-21 — Connections starts with its rows; one plain command per call

- Released before this commit: v105 is a993f2d6 (each agent on the Account page names
  its wallet), 21 Oct 16:32Z, Sean's 16. a; rollback v104 is b9d301fe.
- The Account page's Connections tab no longer repeats itself: the panel's own
  "Verified connections" heading and its sentence are gone, so the rows start under
  the page's title, whose tip already says what the tab is for (Sean's 17. a, after
  his 10:16Z "simplify is the guideline"). The showcase's practice panel drops its own
  sentence the same way; its disclosure already says it is practice.
- The regent-workflow skill says to run one plain command per call, with no loops,
  no nested commands and no site check chained with git work, because the Mac's
  auto-allow rules match plain commands only (Sean's 17. a). The skill is now
  reviewed in full with Sean every week, with its log in the workspace's
  `control/hq/regent-workflow-skill-review.md`.

## 2026-10-21 — Sign out lets go of every wallet; the send step loads no wallet library

- Signing out disconnects every wallet Privy holds, a wallet app such as Zerion
  included, before Privy's own sign-out, so the next sign-in, by Google or any other
  way, starts with none of them. A wallet that refuses to let go never holds the
  sign-out open. Signed in, the wallet Privy remembers as active counts only when
  the account is linked to it; otherwise the page uses the account's own wallet in
  this tab. Sean on Keyfleet, 21 Oct 06:46Z: "signing out zerion should 100% drop
  that account"; carried here as his 18. a, following Keyfleet 53ab3d62.
- The wallet send step compares addresses in any letter case itself instead of
  through viem's getAddress, so no page loads viem's code for it (Keyfleet ee4dca34
  cut its homepage script from 183 KB to 100 KB this way). The server's addresses go
  to the wallet as it built them.
- Sign-in and wallet code: these go live only with Sean's letter.
- Checks: `platform/assets/test/privy_bridge.test.ts` (a wallet app left from before
  is never a signed-in account's wallet; sign-out lets go of every wallet first, even
  one that refuses) and `platform/assets/test/send_step.test.ts` (a checksummed
  answer still sends; another account sends nothing).

## 2026-10-21 — IronClaw in the side panel; Hermes keeps the key it pairs with

- Shared library elixir-utils moves from `dcd6069` to `554f15d`. Pair New Agent
  offers IronClaw where NemoClaw was (elixir-utils 7d73e67, as Keyfleet already
  does); an agent on NemoClaw still pairs, as any agent, and `nemoclaw` stays a
  harness value.
- `/agents/ironclaw` and `/agents/ironclaw/skill.md` replace the NemoClaw pages.
  Patchbay has no IronClaw help page yet, so the page points to its page for any
  agent.
- Hermes's pairing message now says "Keep the key you pair with" instead of naming
  regents-cli (elixir-utils 554f15d).

## 2026-10-22 — The workflow skill drops an unlinked wallet; agents read main's skill

- The regent-workflow skill's wallet rule follows Sean's 21 Oct rule ("signing out
  zerion should 100% drop that account"): signed in, only the account's own wallets
  act, a wallet the account is not linked to is ignored with no note asking the person
  to switch, and signing out disconnects every wallet Privy holds (Sean's 2. a of
  22 Oct).
- The copy of the skill agents read held an uncommitted rewrite of 19 Oct; it now
  holds this text. Main's wording on pushing and releasing stands (Sean's 1. a of
  22 Oct), and the rewrite's two lines on disk space and capacity join "Clean up
  after yourself". The rewrite is kept in the workspace's
  `control/hq/regent-workflow-skill-review.md`.

## 2026-10-22 — Sign-out never waits on a wallet that does not answer

- Signing out asks every wallet to disconnect without waiting on its answer, so a
  wallet whose disconnect never finishes no longer holds the sign-out open (Sentinel's
  note N1 on v106). A wallet that refuses already could not.
- Check: `platform/assets/test/privy_bridge.test.ts` (a wallet that never answers its
  disconnect does not hold the sign-out open; it failed on the old code).
- Sign-in code: a later version of the sign-out change Sean released as v106; it goes
  live with the next release.

## 2026-10-23 — plug_crypto 2.2.1 and req_llm 1.29.0

- Moved plug_crypto to 2.2.1, which closes the medium-severity
  EEF-CVE-2026-105963 (a wrong-typed argument could write the secret key base
  into the error log).
- Moved req_llm to 1.29.0, which closes the critical EEF-CVE-2026-107685
  (OpenAI WebSocket sessions did not check the server's certificate). The
  template's chat uses only its local stand-in, so it never opened such a
  session.
- Lockfile-only change; every other pin stays where it was. `mix hex.audit`
  finds no advisories.

## 2026-10-23 — Node's own types for the tests

- Removed the hand-written `node:fs` and `node:zlib` declarations from
  `platform/assets/js/types.d.ts`, left from the Regents import. `@types/node` is a
  direct dev dependency and declares both in full; the narrow copy lacked `readdirSync`
  and the text form of `readFileSync` that `privy_session_pickup.test.ts` calls, so a
  site copying the file failed its typecheck (regents.sh, 23 Oct).

## 2026-10-23 — Connecting a wallet never revives the last person's sign-in

- On a signed-out page, Connect wallet now logs out a Privy session the browser
  still remembers before Privy's connect window opens. Before, if Privy's logout
  failed at sign-out, connecting a wallet afterwards ended the Disconnect and the
  remembered session signed the previous person back in, which matters on a shared
  computer. If that logout fails too, the window does not open, the page says
  "Wallet connection couldn’t start. Try again." and the Disconnect stands.
  Signed in, connecting a wallet keeps the visitor's own session as before.
- `createConnectWalletRequest` in `platform/assets/js/privy_bridge.tsx`, with three
  regression tests in `platform/assets/test/privy_bridge.test.ts` (regents.sh
  security note, 23 Oct).
## 2026-10-23 — Chains read on a slow clock, and again when a person acts

- Sean, 23 Oct: "template does not need to be reading the chain at all, so change it
  to once per hour. But any onchain user action must refresh the cache." Base's
  newest block on `/showcase/figures` is read once an hour instead of every two
  seconds (`config :ash_template, :chain_heads`), about 43,000 node calls a day
  fewer per machine.
- New `AshTemplate.ChainRefresh`: `request(chain_id)` asks every reader named in its
  `:readers` setting to read that chain again. `AshTemplateWeb.OnchainSteps` calls it
  when a step lands, and a page's read-again icon calls it. Each reader keeps at least
  ten seconds between two early reads, so a crowd pressing costs one read.
  `AshTemplate.ChainHead` is the first reader: it wakes on a `Phoenix.PubSub` topic on
  every machine. Every site copies this module; this is the original.
- The figures page shows when Base was last read and the read-again icon, with the new
  `Regent.Primitives.last_read` from design-system `af32c1d3` (was `5dd12626`).
- Skills: `chain-events` gains rule 12 (read the chain on a slow clock), its watcher
  guide runs passes as Oban jobs, as Keyfleet does, every five minutes and brought
  forward by `ChainRefresh`, and "catching up" starts after 420 seconds;
  `elixir-stack` and `ash-frontend`'s public figures point to the rule.
- Checks: `platform/test/ash_template/site/chain_refresh_test.exs` (an ask after a
  quiet spell reads at once; asks close together cost one read; another chain's ask
  leaves the reader alone) and `platform/test/browser/figures.spec.ts` (the page says
  when Base was last read and the icon reads it again, at both widths).

## 2026-10-23 — Credits deposits read every five minutes; design-system on main

- elixir-utils `e600ed34` (was `554f15d7`): the shared Credits deposit reader runs every
  five minutes instead of every minute. A person's own Buy is still credited by its
  purchase check within a minute.
- design-system `30d16360` (was `af32c1d3`): the read-again icon's commits as they
  landed on design-system main, after its tip-figure and plug_crypto 2.2.1 changes.

## 2026-10-23 — The Pair New Agent box never crashes with nothing chosen

- `AshTemplateWeb.PairingBox` keeps the box as it is when the pairing form arrives with
  no agent picked. A page reconnecting restores the form with nothing chosen, and a
  submit can come before a choice; both crashed the side panel before (Sentinel, from
  Patchbay's error mail). Every site copies this clause.
- Checks: `platform/test/browser/pairing.spec.ts` sends the form with nothing chosen,
  then chooses an agent, at both widths, and watches for a crash on the page's socket.

## 2026-10-23 — Skills: a press brings a chain reading forward, never later

- `chain-events` watcher guide: `Watch.refresh/1` inserts the unique reading job without
  `replace:` and, when the job waiting is due later than ten seconds from now, moves it
  there with `Oban.update_job/2`. With `replace:` every press set the time to ten
  seconds away, later as well as sooner, so presses less than ten seconds apart (an
  auction launch crowd) could keep putting the reading off. Found by Autolaunch while
  replacing its hand-built runner (Sentinel D1). Rule 12 in `chain-events` says the same.
- Checked against Oban 2.24.2 with a probe that was not kept: a job waiting five minutes
  comes forward to ten seconds and later presses keep that time; a job due in three
  seconds keeps its time; `replace:` pushes it to ten.

## 2026-10-23 — Fresh builds fetch native code around GitHub's long headers

- Since about 20:30Z on 23 Oct, GitHub's release-download redirect sends a
  content-security-policy header of about 9,200 bytes, which takes the whole header block
  past the 10,240 bytes Erlang's `httpc` accepts. rustler_precompiled 0.10.0 offers no
  way to raise that limit, so any build without a cached deps layer stopped at
  `mix deps.compile` with `header_too_long`. The v108 release was the first to hit it.
- lumis and mdex_native now download from their makers' official mirrors
  (`artifact_source: :cloudflare` in `platform/config/config.exs`). ex_keccak and
  ex_secp256k1 publish only on GitHub, so `platform/Dockerfile` fetches their two files
  with curl into `RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH` before `mix deps.compile`.
  rustler_precompiled checks each file against the package's checksums before using it.
- The two curl lines name the versions mix.lock pins and change with them. Remove the
  step once GitHub or rustler_precompiled fixes the limit (backlog).

## 2026-10-23 — ChatGPT's picture, and CLI 1.10.17

- design-system pin moves to `cbf12f8`, which adds ChatGPT's picture to
  `Regent.Account.agent_mark` (kind `"chatgpt"`). Before, an agent list or pairing box holding a
  ChatGPT agent failed to draw. ChatGPT pairing stays off here
  (`config :regent_agents, chatgpt_pairing:`).
- The command check and every install line move to regents-cli 1.10.17 (`773f8a67`), whose copy
  of this site's `cli/commands.json` is identical to ours. `cli/COMMANDS.md` drops its "next
  release" marks, and `/agents.md`, `/llms.md` and the public changelog name 1.10.17 with its
  published wheel's SHA256.

## 2026-10-23 — Skills: a silent node is a wait, and dropping a column takes two releases

- `chain-events`: the client answers `{:error, :unavailable}` when the node does not answer
  (timeout, refused connection, 429, 5xx), and the reading job logs one warning and returns
  `{:snooze, 60}` instead of `{:error, _}`, so a provider blip is never saved as a crash. Other
  failures still fail the job and retry a minute later. Rule 2 says the same.
- `ash-data` migrations guide: under a bluegreen release, release 1 stops declaring a column
  and release 2 drops it, so the outgoing machines never select a dropped column.
- Both come from Autolaunch's move from its own runner to Oban (da6cbf58, d5e7a4c5).

## 2026-10-23 — A page cannot draw half a side panel

- `AshTemplateWeb.Components.Shell.shell` now requires its `:credits_panel`, `:pairing` and
  `:agents` slots, so a page that draws the shell without one fails
  `mix compile --warnings-as-errors`. Callers still leave each one out for someone signed
  out with `:if`. From regents.sh v225, where two pages drew the shell themselves and,
  signed in, their side panel held only Sign out and Manage Account.
- The showcase preview of the page frame gives a Credits panel too, so its balance opens
  a window saying that buying Credits needs a signed-in account.
- ash-frontend: every page with the side panel is a `ShellLive` action in
  `live_session :product_shell`; a page never draws the shell itself.

## 2026-10-23 — The native-code prefetch follows the building machine's chip

- `platform/Dockerfile` fetches the ex_keccak and ex_secp256k1 files for the chip it builds on
  (`uname -m`): x86_64 on Fly, aarch64 on a Mac running `make release`, which otherwise stopped
  at GitHub's long download headers. Proven by a fresh aarch64 build on the Mac and a
  build-only x86_64 run on Fly (image label prefetchcheck, not released). From Techtree 78c5c5a5.

## 2026-10-23 — The runtime image carries libsctp1

- OTP 29 opens libsctp when it starts. Without it every boot and every `bin/ash_template rpc`
  printed an ESOCK warning first, which put a warning in front of the database name
  `make release` reads, and in front of every rpc answer and release command log on Fly.
  `platform/Dockerfile` installs `libsctp1` in the runtime stage. Proven by starting the image
  on the Mac (no warning) and a build-only run on Fly (label sctpcheck, not released). From
  Techtree fadc820d and regents.sh.

## 2026-10-24 — Two Elixir 1.20 warnings gone

- `platform/mix.exs` sets `test_ignore_filters` for `test/browser/`, the Playwright walk's own
  files, so `mix test` on Elixir 1.20 no longer warns that they match no test pattern (a site that
  runs `mix test --warnings-as-errors` failed on it; Autolaunch b5a53ac4).
- design-system pin 9c2a817: regent_ui asks for Elixir `~> 1.19`, so building it on 1.20.4 no
  longer warns (Keyfleet found it). Nothing else in design-system moved.
- Server checks: 65 passed.

## 2026-10-24 — Ten wonders in the motion lab

- `/animations/wonders`: ten pictures drawn live on the visitor's graphics card, each moved
  by hand: a black hole bending starlight, a warp drive held to light speed, a flight round
  the Mandelbulb, a tesseract turned through its fourth dimension, living coral that grows
  by itself, ink blooming in water, a pane of glass that shatters off a key, northern
  lights with a storm, a ripple pool and a kaleidoscope.
- Each is a vgpu canvas island (`platform/assets/js/hooks/wonder.ts`) whose shader lives in
  `platform/assets/js/wonders/`; Anime.js moves only numbers in the wonder's state (springs,
  timelines, animatables) and the renderer reads them when it draws. Pictures that move
  only when touched draw only then. The coral is a growth simulation run on the GPU
  between two textures.
- Each wonder keeps a painted still picture for a visitor who asked for less motion or
  whose browser cannot draw it, and its buttons appear with the first real frame.
- Checked headless in Chromium with WebGPU: all ten draw and answer their controls, no
  page overflow at 1280, 390 and 320 wide, and reduced motion keeps the ten stills.

## 2026-10-24 — A machine stops in order

- `platform/fly.toml`: `kill_signal = "SIGTERM"`, `kill_timeout = "60s"`. Fly sent SIGINT,
  on which the VM halts at once (it opens its break menu and, with no input, aborts), so
  every stop cut open connections and running jobs; Sentinel counted the proxy's lines at
  machine stops on five sites. On SIGTERM the VM stops its applications in order. Checked
  with a probe application on OTP 29: SIGTERM ran its `stop/1`, SIGINT did not. Patchbay
  has run the same two lines with no such lines in seven days.

## 2026-10-24 — Chain figures that belong to one record are a public row

- `skills/ash-frontend/references/public-figures.md`: a new section says that a
  figure read from a chain but belonging to one record goes in that record's row,
  written by one Oban job per record under the row lock, only ever with a newer
  block unless the chain left the one it holds, and reaches pages
  through the row's publication. A job never writes `SharedReading`. Autolaunch v180
  (`Autolaunch.AuctionMarket`, `Autolaunch.AuctionReading`) is the worked example.
  The bound example that described Autolaunch's old pass now names `ChainHead`.
- Public changelog: ten wonders in the Motion Lab.

## 2026-10-24 — Native code comes straight from GitHub again

- GitHub's download redirect fits Erlang's HTTP client again: its header is about 5.5 KB
  (it was over the 10,240-byte limit), and `:httpc` fetches the ex_keccak, ex_secp256k1
  and lumis release files with certificate checks on. So `platform/Dockerfile` no longer
  curls ex_keccak and ex_secp256k1 into a cache first, and `platform/config/config.exs` no
  longer sends lumis and mdex_native to their Cloudflare mirrors. Checked on the Mac: with
  an empty cache, `mix deps.compile ex_keccak ex_secp256k1 lumis mdex_native --force`
  downloaded all four from GitHub, checksums matched, and server checks were 65.

## 2026-10-25 — When the docs and the code disagree

- `skills/regent-workflow/SKILL.md`, Execute step 1, gains Sean's rule word for word: when a
  repository's documentation and its existing code disagree, follow the conventions used in
  the existing code, and point out each inconsistency in the final reply. Skills only; it
  reaches agents through the served skills at the next release.

## 2026-10-26 — Swarm city in the motion lab

- `/animations/swarm-city`: a new take on the agent harbour, drawn live in 3D in the style
  of a wireframe city. A square plate holds about five thousand buildings, each a dark box
  outlined by a hair-thin line: three downtowns of thin towers (the castle green, the forge
  cyan, the inn lime) rise out of a dense low city outlined in lavender. Blue streets cut
  the plate into irregular blocks, six avenues run out from a central plaza, yellow beacons
  mark the rim, the corners and the avenues, and a red sky grid hangs over the downtowns
  with lines dropped to the roofs and a curtain to the ground; the castle's needle pierces
  it. Each agent is a flat yellow disc ringed in its own colour, trailing a thin yellow tail
  and a small swarm of discs with tails of their own; it circles the towers of the district
  of its last action and climbs over the roofs to cross the city when it acts somewhere
  new. A drag turns the city; a mouse over a disc names its agent, over a district shows a
  card with its link; pressing a disc opens the agent's card.
- `/animations/swarm-city/inn`, `/forge` and `/castle`: the camera flies to that district
  and lights it.
- The city comes from a fixed seed (`platform/assets/js/swarm_city/city.ts`): the plate is
  cut into blocks and each block into lots, downtown lots small and tall, with setbacks
  and rooftop boxes, so every visitor sees the same city.
- The harbour and the swarm city now share one sample crew and agent card,
  `AshTemplateWeb.SampleCrew` (`platform/lib/ash_template_web/sample_crew.ex`); the harbour
  page itself is unchanged.
- The city is a vgpu canvas island (`platform/assets/js/hooks/swarm_city.ts`, drawing in
  `platform/assets/js/swarm_city/`), drawn straight to the page with multisampling: each
  building is one record drawn twice, as dark sides and roof that hide what stands behind
  them and as twelve edge lines. Anime.js eases the camera and each district's light. A
  visitor who asked for less motion gets one composed still city, still turned by a drag;
  a browser that cannot draw it shows `priv/static/images/animations/swarm-city.webp`.
- `/animations/wonders` and the four swarm city pages join the showcase list in
  `public_documents.ex`, which the wonders page had been missing.
- Public changelog: swarm city in the Motion Lab.
- Checked headless in Chromium with WebGPU: the city draws, hovering finds all six agents
  and all three districts, pressing an agent opens its card and Escape closes it, a drag
  turns the city, each district page flies the camera there, an agent that acts crosses
  to its new district, no page overflow at 1280, 390 and 320 wide, reduced motion keeps
  one still city, and without WebGPU the still picture shows.

## 2026-10-26 — Bandit 1.14.0 and Ash 3.37.2

- Bandit 1.13.1 had eleven published advisories, nine high (HTTP/2 flow control and HPACK
  sizes, 1-byte chunked bodies, chunk extension smuggling, Content-Length parsing, WebSocket
  fragments); 1.14.0 fixes them. Ash 3.37.2 fixes a through relationship with a limit of 1
  returning unrelated records, and a multitenancy upsert advisory. `platform/mix.exs` now asks
  for `~> 1.14` and `~> 3.37`, and `security/required-fixes.json` requires `>= 1.14.0` and
  `>= 3.37.2`, so every site's check names the move.
- ash_postgres stays at 2.13.0. 2.15.2 still writes upserts without the Repo's default prefix:
  an `EnsIdentity` upsert went to an unqualified table and failed, and 2.13.0 with Ash 3.37.2
  wrote one row in `ash_template_app`. Its two advisories (EEF-CVE-2026-115635, -115627) need
  attribute multitenancy, which no Regent resource uses, but `mix hex.audit` still names them.

## 2026-10-26 — Six looks for the swarm city

- `/animations/swarm-city` and its three district pages gain a row of tabs above the
  picture, one per look, each with its own link as `?look=<name>`; the first look keeps
  the plain link. Every link on the page keeps the look, and a name the page does not
  know gives the not-found page. Switching tabs repaints the same canvas without
  starting it again.
  - **Neon** is the city as it was.
  - **Blueprint**: a blue drafting sheet ruled to the horizon, buildings in white and
    pale-blue ink with hatched shadow sides, dashed streets, orange pencil agents.
  - **Porcelain**: a pale model city lit by a low sun, pastel downtowns, clay streets
    and ink-dark agents ringed in their colours.
  - **Lamplight**: the city at night, thousands of lit windows that blend into a warm
    glow far away, amber street lamps and teal agents.
  - **Sunset**: violet towers edged from cyan to pink, cyan and gold, a pink grid floor
    under a striped setting sun, gold agents.
  - **Hologram**: see-through glass towers with rainbow edges and scan lines rising up
    them, a floor of dots, a violet sky grid and white agents.
- Each look is one block of WGSL in `platform/assets/js/swarm_city/looks.ts`: the colours
  of the sky, ground, building sides, edges, streets, beacons, agents and tails, and
  whether it draws the sky grid and beacons. `platform/assets/js/swarm_city/shaders.ts`
  builds every draw around that block, and the renderer compiles a look the first time it
  is shown and keeps it. The ground and sky are now one full-screen draw that meets the
  plate, so a look can rule lines to the horizon. Glass looks add their sides and skip
  depth writes.
- The still pictures moved to `platform/priv/static/images/animations/swarm-city/`, one
  per look (`neon.webp` is the old `swarm-city.webp`).
- Public changelog: the swarm city's six looks.
- Checked headless in Chromium with WebGPU: all 44 look shaders pass `vgpu check`; every
  look draws on the overview and on each district page (15 pages); switching through all
  six tabs keeps the same canvas and updates the district cards' links; a district name
  in the list keeps the look; a hover tag reads on the light porcelain city; no page
  overflow at 390 and 320 wide, where the tabs wrap to two rows; reduced motion draws
  one still city; `?look=nope` is not found; each still picture is served.

## 2026-10-26 — Five mixed looks for the swarm city

- Five more tabs on `/animations/swarm-city` and its district pages, each mixing Neon,
  Hologram and Porcelain:
  - **Afterglow** (`?look=afterglow`): Hologram's glowing glass towers and scan lines in
    Neon's castle green, forge cyan and inn lime, with a lavender dot floor, blue streets,
    the red sky grid and yellow agents.
  - **Showroom** (`?look=showroom`): pale porcelain models at night, lit by one light and
    darker low down, with Neon's bright outlines, streets, grid and agents.
  - **Glasshouse** (`?look=glasshouse`): Porcelain's paper with towers of tinted glass that
    deepen where they are seen edge-on, outlines with a rainbow sheen, an ink dot floor,
    clay streets and ink agents with rainbow tails.
  - **Opal**: white porcelain towers with a pearly rainbow sheen that shifts as the city
    turns, Neon's colours deepened to read on white, blue streets, a pale red sky grid and
    gold agents.
  - **Obsidian**: glossy black towers lit by one light, with a glint, a neon rim where seen
    edge-on and scan lines, dim neon outlines, the red sky grid and white agents.
- Glass now comes in two kinds (`glass: "glow" | "tint" | null` in
  `platform/assets/js/swarm_city/looks.ts`): glowing glass adds its light, as before;
  tinted glass multiplies what is behind it, so a light look can have glass too.
  Far-off glass fades to clear instead of to the haze. The rainbow helper moved from the
  hologram look into the shared shader code.
- Still pictures for the five new looks in
  `platform/priv/static/images/animations/swarm-city/`.
- Public changelog: five more looks.
- Checked headless in Chromium with WebGPU: all 81 look shaders pass `vgpu check`; all 11
  looks switch in place on one canvas and keep their links; all 30 district pages draw;
  no console errors; no overflow at 390 and 320 wide, where the tabs wrap to four rows;
  reduced motion draws; `?look=nope` is not found.

## 2026-10-26 — ash_postgres from Regent's copy of 2.15.2

- `platform/mix.exs` takes ash_postgres from `https://github.com/regents-ai/ash_postgres.git`
  at `cc886ab3efc8b05d51b7b1f57e609341fb6a0873` with `override: true`: the 2.15.2 release
  plus ash-project/ash_postgres#910, which makes upserts and `Ash.update_many` use the Repo's
  `default_options/1` prefix again (upstream issue ash-project/ash_postgres#909). That prefix
  is how each site picks its schema on the shared database. The override stands in for the
  Hex release ash_money and ash_double_entry ask for. It clears EEF-CVE-2026-115635 and
  EEF-CVE-2026-115627, the two advisories on 2.13.0. ash_sql moves to 0.8.4.
- elixir-utils moves to `56fa86bd6aee5efe7ac7c8b7b698e82d8fdcfe29`, where every shared Ash
  package uses the same copy.
- The dead `config :ash_postgres, upsert_with_merge?: false` line goes from
  `platform/config/config.exs` (2.15.2 has no such setting; upserts are always
  `INSERT ... ON CONFLICT`), and the `AshTemplate.Repo` comment says where the prefix comes
  from.
- 2.15.2 ships ash-functions 7. Its `ash_required` raises its own error instead of calling
  `ash_raise_error`, which the function's empty search path cannot find, so a missing
  required value failed with "function does not exist". Migration
  `20261026194117_ash_functions_v7_extensions_1` replaces the function, in the same place
  the first migration created it; the snapshot moves to version 7. It runs with the
  release's migrations, so the release that carries it needs Sean's go for a migration.
- `security/required-fixes.json` lists the copy as a managed library (whole repository, so
  `sparse` is null) and replaces the `== 2.13.0` hold with the git fix
  `2026-10-26-ash-postgres-upsert-schema`. A site still on Hex ash_postgres now fails
  `make check-required-fixes` with "ash_postgres comes from Hex.SCM, not its shared
  repository". `AGENTS.md`, `docs/dependency-baseline.md` and the check script's comment
  say the same.
- Move back to Hex once a release carries #910 and passes the isolated upsert check.

## 2026-10-26 — Visit lines

- Production writes one JSON object a line (LoggerJSON's basic shape) carrying only five
  fields: `visit`, `request_id`, `surface`, `actor` and `event` (`name`, `where`,
  `outcome`, `ms`), so a visit can be replayed from its lines alone
  (`docs/logging-replay-plan.md`, Sean's decisions of 26 Oct). Phoenix's own request lines
  are off in production.
- `AshTemplateWeb.VisitLog` gives each browser visit a random id in an httpOnly session
  cookie (the page's `regent-visit` meta tag hands it to the page's scripts), reads the
  caller's kind from `x-regent-client`, and writes accounts and agents only as a one-way
  code keyed from the site's secret. `AshTemplateWeb.VisitLog.Events` writes requests,
  tool calls, pages, presses, Ash actions, Oban jobs and outgoing calls from their
  `:telemetry` events.
- `POST /visit-log` takes what only the browser knows: a page error, a browser tool that
  never got an answer, and a wallet step whose answer never reached the server, at most
  20 a batch, rate limited with the browser's other reports. The site stores nothing new.
- Browser tools send `x-regent-client: webmcp/<tool>` and the visit. elixir-utils moves to
  `c4fdaae6e9bdb2dd7b09e9792aecdde2109c385d`, where the signed tool transport takes the
  same headers through its new required `requestHeaders` setting.
- Checks: property tests over the line writer, the plug and the browser's reports, and a
  browser walk check that replays a saved note from the server's lines; the walk's server
  writes its lines in production's shape to `platform/tmp/walk-lines.jsonl`.

## 2026-10-26 — jose 1.11.13; a page's API calls keep their visit

- Moved jose (through regent_privy and joken) to 1.11.13, which fixes the eight advisories
  published 26 Oct, one high (EEF-CVE-2026-65625 to -65632). Lockfile-only change.
  `security/required-fixes.json` adds `EEF-CVE-2026-65629` with `>= 1.11.13`, so a site
  still on 1.11.12 fails `make check-required-fixes`.
- An `/api` call that names no tool or command but carries a visit, in the `_visit` cookie
  or in `x-regent-visit`, is the page's own script: its line keeps that visit and says
  surface `page`, not `agent_http`. The agent tools list sends no cookies, so it now sends
  the visit in `x-regent-visit`. Found by the Autolaunch port of visit lines.
- Checks: a unit test for the header, cookie and neither cases, and a browser walk check
  that the agent tools list's reads land in the page's visit.

## 2026-10-26 — Glass looks in brand colours, light and dark

- Added five glass looks to the swarm city (`?look=regent`, `tangerine`, `powder`,
  `smoke`, `cobalt`), versions of Glasshouse in the design system's colours with no
  rainbow: tangerine, charcoal, platinum and powder blue, and Patchbay's cobalt palette.
- Each follows the page's theme: tinted glass on the light page ground (`#F6F4EA`),
  glowing glass on the dark one (`#0B0B0B`). The theme switch and the device's setting
  repaint the city in place; a still picture for each theme shows before it draws.
- `LOOKS` now holds each look for both themes (`ThemedLook`); the renderer's `setLook`
  takes the look and the theme, and keeps one painting for a look that is the same in both.

## 2026-10-26 — The shared ash_required helper, fixed in public

- Version 6 of ash_postgres's `ash_required`, the copy in `public` that every site on the
  shared database calls, runs with an empty search path and cannot find
  `ash_raise_error`, so a missing required value raised "function ash_raise_error does not
  exist" instead of Ash's error. Migration `20261026194117_ash_functions_v7_extensions_1`
  now names `public.ash_required`, so it replaces that one copy whichever login runs it
  (agreed with Patchbay, whose production read found the sites resolve it to `public`).
  Version 7 keeps the same arguments and raises the same `ash_error:` message.
- elixir-utils moves to `e796a9d527b839121145d2515da9f4d5689fe80b`: Credits' first
  migration installs version 6, and on a fresh database it ran after the site's and put
  that copy back; its new migration `20261026220000` installs version 7 in `public` too.
  jose 1.11.13 in the libraries' own locks. `security/required-fixes.json` adds
  `2026-10-26-ash-required-v7`, so a site on an older regent_credits fails
  `make check-required-fixes`.
- Check: `platform/test/ash_template/required_value_test.exs` on a database built from
  every migration. It fails with the "does not exist" error on version 6.

## 2026-10-26 — Neon in four site palettes, light and dark

- Added four neon looks to the swarm city (`?look=regents-neon`, `techtree-neon`,
  `autolaunch-neon`, `patchbay-neon`), built by one `neonIn` recipe from each site's light
  and dark palette in the design system's site colour sheets.
- Dark keeps Neon's glowing outlines; light draws the same outlines as coloured ink on the
  site's page colour. Each agent's disc keeps its own colour as its rim.
- Themed looks now name their stage colour in each theme through `--swarm-light` and
  `--swarm-dark`, read by one rule under `data-swarm-themed`.

## 2026-10-26 — Public posts under Sean's name need their own decision

- `skills/regent-workflow/SKILL.md` (Protected work): nothing is posted in public under
  Sean's name or accounts (issues, pull requests, comments, reviews, edits, reactions
  outside regents-ai; X, forums, email) without a decision that shows the account, the
  place and the full final text. A plan approval never approves a post. Git without
  asking now reads "inside regents-ai repositories".

## 2026-10-26 — Swarm city: glass looks removed

- Removed Glasshouse and the five brand glass looks (`?look=glasshouse`, `regent`,
  `tangerine`, `powder`, `smoke`, `cobalt`) and their stills, on Sean's call now that
  the four site-palette neon looks replace them. Fourteen looks remain; their addresses
  now answer not found. Glass is a yes/no on a look again (glowing glass only), since
  no look tints any more.

## 2026-10-26 — ash_postgres from upstream main; ash_phoenix and ash_oban up to date

- `platform/mix.exs` takes ash_postgres from `https://github.com/ash-project/ash_postgres.git`
  at `55db7d449aad351d200c5f300fca2a83e0a8734c`, upstream main with #910 merged (upserts and
  `Ash.update_many` keep the Repo's default prefix), still with `override: true` until a Hex
  release carries it. It also brings #907 (snapshot hashes from the sorted encoding) and two
  unique-error mapping fixes. The regents-ai copy is no longer used.
- `security/required-fixes.json`: the shared-library entry and fix
  `2026-10-26-ash-postgres-upsert-schema` now name ash-project/ash_postgres at 55db7d44.
  Every site on the regents-ai copy fails the check until it moves to the same commit.
- ash_phoenix 2.3.25 → 2.3.26 and ash_oban 0.10.2 → 0.10.3, their newest Hex releases
  (Keyfleet main dc1f8140 has the same two). Ash stays at 3.37.2, the newest.
- `docs/dependency-baseline.md` names the new source.

## 2026-10-26 — Swarm city: haze follows the camera

- The city's haze starts just short of the city however far the camera stands
  back, so on a tall, narrow phone screen the city no longer fades to blank.
  At the usual distance it looks the same as before. Keyfleet's copy carries the
  same change.

## 2026-10-27 — Released v111

- Released before this commit: v111 is 33c5cd1 (visit lines for replay, jose 1.11.13, the
  shared ash_required fixed in public, ash_postgres from ash-project main 55db7d44,
  ash_phoenix 2.3.26, ash_oban 0.10.3, the swarm city looks up to e69c1d8), 27 Oct
  01:24Z, Sean's 1. a; rollback v110 is 0d713c8.
- Before the deploy, from the v111 image on temporary machines that removed themselves:
  `/app/bin/pending-migrations` listed `pending: 20261026194117` and
  `shared-pending: regent_credits 20261026220000`; `/app/bin/migrate-shared` applied
  regent_credits 20261026220000. The deploy's release command migrated 20261026194117.
- Read-only check on the live machine: `public.ash_required` has the version 7 body, both
  ledgers hold their version, a missing value raises "ash_error: {}" and a present one
  comes back. Version 6 copies remain in `patchbay_app` and `techtree_app`.

## 2026-10-27 — Every page writes its page line

- Sentinel's first read of v111 found request lines but no `page` lines: the page line
  came from LiveView's `handle_params` telemetry, which fires only for a view that
  defines `handle_params/3`, and most of the template's views (the home page among them)
  do not. `AshTemplateWeb.VisitLog.on_mount/4` now attaches a `handle_params` hook on
  every page the router opens, so each one writes `page <route>` when it connects and
  each time its address changes; `AshTemplateWeb.VisitLog.Events` no longer listens for
  that telemetry event. A view drawn inside another page attaches nothing.
- Check: `platform/test/browser/visits.spec.ts` now expects the home page's `page /`
  line; it failed with the old listener (the visit held only its request and API reads)
  and succeeds with the hook. Each walked page writes exactly one page line.

## 2026-10-27 — One address per page: a slash at the end is not found

- Sentinel found `/account/` and `/notes/` answering 500 on template.regents.sh. The router
  matches every route with a slash at the end too, and the signed-in shell then looked up
  the page's title under the slash address and raised. `AshTemplateWeb.Plugs.NoTrailingSlash`,
  in the endpoint right after `RegentAgentAccess.Plug` has chosen the error format, answers
  any address ending in a slash other than `/` as an address that names nothing: the
  not-found page for a page, the API's `not_found` answer for an `/api` address. `/about/`,
  `/llms.txt/` and every other slash address now get that same answer, so each page and API
  call has one address. Files served before the endpoint's own plugs are unchanged.
- Check: `platform/test/ash_template_web/trailing_slash_test.exs` (failed without the plug
  with the same `"/account/" not found` crash, succeeds with it).

## 2026-10-27 — Swarm city: the sky grid clears the tallest tower

- The red grid over the city now hangs one step above the tallest roof instead
  of at a fixed height, so the castle's needle no longer rises through it.
- The city's overview aims a little higher and stands a little further back,
  so the raised grid stays whole inside the picture on a wide screen.
  Keyfleet's copy carries the same change.

## 2026-10-27 — Released v112

- Fly v112, image f76f138 (Sean's letter TEMPLATE-V112), live 02:32Z; rollback v111 (33c5cd1).
  Carries every page's `page` line (7fec82e), one address per page (9dd2237, be54337) and the
  swarm city sky grid above the tallest tower (f76f138). No database change: a temporary
  machine's `pending-migrations` printed `none` and the release step migrated nothing new.
- Before: full check 74 ExUnit, 23 JS, 274 browser steps (2 skipped); required fixes clean.
- After: `/capabilities.json` reports f76f138; `/healthz` 200; the old machine stopped on
  SIGTERM with exit 0. `/about/`, `/contact/`, `/account/`, `/notes/`, `/skills/` and
  `/llms.txt/` answer 404 and `/api/v1/rooms/` the JSON `not_found`; the plain addresses
  answer 200. A headless Chromium visit to `/` wrote `request / ok` then `page /`.

## 2026-10-27 — Skills: the shared database's connections

- ash-data now says how sites share the production database's 97 connections, after four
  releases swapping at once used them all for 20 seconds (02:48Z): each site serves with a
  pool of 5, as the template does, and starts a release only when no other app's newest
  release is still in progress. More connections or a larger plan is Sean's decision.

## 2026-10-27 — Skills: health checks share the pool; keyfleet-code's ceiling

- ash-data: a site's health check reads through its serving pool of 5, as the template's
  does, with no second pool beside it (Keyfleet kept one extra connection per process
  group for it). `keyfleet-code`, the Twigpine git node, is capped at 20 connections, the
  lowest it starts with; it was able to open up to 88.

## 2026-10-27 — Header lab: the crown has no frame

- The crown beside the site name in the header lab (`/animations/header-footer`) drew a
  1px frame that showed as a light ring on a dark page. It now stands alone, the same
  size. From Keyfleet's header (Keyfleet 3a37be86, after Sean asked for the ring to go).
  Keyfleet's other two header fixes do not apply here: the nine-dot button is already
  44×44, and icon names are hidden below 48rem and end inside the screen above it.

## 2026-10-27 — Releases on the shared database take turns

- `scripts/deploy.sh` now runs the build and release under
  `lockf -k /tmp/regent-shared-db-release.lock`, the lock every site's deploy takes on
  the founder's Mac, so a release waits for any other to finish. Keyfleet found the gap:
  Fly lists a release only once its build is done, so at 03:39Z Patchbay v275 was
  building unseen when Keyfleet's check found nothing in progress, and the two swaps
  overlapped by about a minute. ash-data says the same for releases, secrets changes and
  restarts run by hand; the release-list check stays for releases started elsewhere.

## 2026-10-27 — The site serves through the database's pooler

- The running site connects to the shared database's pooler
  (`pgbouncer.dzx6qo6xqzvojpv5.flympg.net`, transaction mode) instead of its direct
  address, with `prepare: :unnamed` and each connection replaced after nine to ten
  minutes. The pooler opens at most 50 real connections (plus a reserve of 10) for every
  site together, so a release's second machine no longer adds load on the database's own
  limit. Production admits only the pooler for `DATABASE_POOLED_URL`; release commands
  stay on the direct address. Sean's decision RELEASE-NO-WAIT (27 Oct, "1. a").
- Credits and agent changes from other sites arrive on one connection of the site's own
  on the direct address (`AshTemplate.SharedChanges`, shown as `ash-template-listen`),
  which both listeners share; the pooler drops listening. elixir-utils 85d05a7: the
  listeners take the required `notifications:` setting instead of opening their own.
- ash-data describes the standard for every site. The one-release-at-a-time rule stays
  until every app serves through the pooler.

## 2026-10-27 — keyfleet-code's connections

- ash-data: `keyfleet-code` holds at most 10 connections since its v5 (c9a59ea), not 20,
  and turns off sqlx's statement cache when it serves through the pooler.

## 2026-10-27 — Homepage hero: Enter App and WebMCP Tools

- The homepage hero's main button is Enter App, opening `/app`. At rest it shows the
  marks a main button shows on hover in dark (Powder Blue corners, Tangerine cuts), and
  on hover the Powder Blue runs on into two full L-edges. WebMCP Tools beside it is the
  secondary button and opens the same tools list. `AgentTools.button` takes its own words
  and classes for it; the footer's count button is unchanged. Copied from regents.sh
  572230a1 (v229, Sean 27 Oct: "add this as the primary CTA in the hero 'Enter App', and
  'WebMCP Tools' as secondary").

## 2026-10-27 — Agent list and agent window: clearer words and layout

- design-system 18a3c65 and 0c72c96: each agent row shows the whole name, with the address, its
  copy and explorer controls, See Actions and Unpair on the line under it. The agent
  window explains the agent address (made with SIWA; where its key lives depends on the
  app running the agent), names its parts Allowed Agent Actions, Spending and Activity,
  sets "It never uses your wallet." as a quote, links Spending to the Account page and
  says "Your agent’s actions will appear here." while there are none.
- The row's button is now See Actions (was See what it has done). Sean, 27 Oct.

## 2026-10-27 — A wallet press certain to fail is never handed to the wallet

- Credits: a Buy pressed before its steps reached the page asks the server for them.
  The reply now leaves out a Buy that the fresh build finds certain to fail (no USDC,
  or no approval on the chain yet); the button shows why instead of opening the wallet.
  From Keyfleet 1f4049bc (Sean, 27 Oct: Mark present opened a Privy wallet holding no
  Keys, and the chain refused it). The onchain example blocks nothing, so it is unchanged.
- onchain-buttons skill (hook-pattern): the press path says the same. New property check
  `platform/test/ash_template_web/credits_press_test.exs` (fails on the old reply), listed in
  `docs/feature-map.md`.

## 2026-10-27 — A refused sign-in reloads the page once

- When the server refuses a sign-in and drops the browser's session, the page
  reloads once and lands signed out. Before, the old page's live connection,
  told by the server to drop, could ask for a new session while the reload was
  already on its way. That late answer replaced the reloaded page's cookie, its
  connection was refused as stale, and the page loaded a third time.
- `holdAdoptionWhileLeaving` in `platform/assets/js/auth_lazy.ts`, installed in
  `platform/assets/js/app.ts`: from `beforeunload` on, a page's held live
  connection asks the server for nothing; the page that replaces it reads its own
  session. Ported from Keyfleet b19ab5be, where the rejected-bearer browser test
  failed 3 of 17 runs alone before and passed 40 of 40 after. New check
  `platform/assets/test/session_leaving.test.ts` (fails without the change),
  listed in `docs/feature-map.md`.

## 2026-10-27 — Swarm city: room for 24 agents

- The swarm city now draws up to 24 agents, each with its swarm and trail, up
  from 16 (Sean, 27 Oct: "do 24"). With 24 the districts still read clearly on a
  wide screen and at 390 and 320 wide. Keyfleet's copy carries the same change.

## 2026-10-27 — Swarm city: agents keep their size on phones

- An agent's smallest size now follows the shorter side of the picture, so on
  a tall phone the agents are as small beside the city as on a wide screen
  instead of covering it. Keyfleet's copy carries the same change.

## 2026-10-27 — Pooler trusted by its own authority; releases no longer take turns

- The shared database's pooler presents a certificate from the cluster's own
  authority (`postgres-operator-ca`, valid to July 2036) issued to the cluster's
  internal name, which is why the 27 October release (v113) could not connect.
  Pooler connections now verify against that one authority
  (`platform/priv/certs/regents-platform-prod-pooler-ca.pem`) and accept only
  `pgdb-dzx6qo6xqzvojpv5-pgbouncer.pgdb-dzx6qo6xqzvojpv5.svc`. The direct address
  keeps its public certificate check. Proven from the template's machine before
  release: a connection through the pooler with these settings succeeds.
- The listening connection hands Postgrex.Notifications the login's parts instead
  of a URL, which it does not read (v113's "missing the :database key").
- Removed the take-turns release lock from `scripts/deploy.sh`, the README and the
  ash-data skill (Sean, POOLER-CERT c): the pooler, not a lock, protects the
  database's connections. Sites still on the direct address drop the lock as they
  move to the pooler.

## 2026-10-27 — The pooler hears only the connection's name

- v115 (d615f81) connected through the pooler with the pinned authority, then the
  pooler closed every connection: it refuses any startup setting but
  `application_name` ("unsupported startup parameter: statement_timeout"). Rolled
  back as v116 (f76f138) within about two minutes.
- The serving connection now sends only its name. The three limits (statement 15 s,
  lock wait 5 s, idle open transaction 15 s) move onto the serving login itself
  (`ALTER ROLE CURRENT_USER SET …`, run by that login on the direct address), which
  the ash-data skill now describes; that database change waits for Sean's go.
- Proven on the template's machine with this commit's own settings: through the
  pooler a query and a transaction lock succeed, and the listening connection on the
  direct address hears a notice.

## 2026-10-27 — Amounts shown the one Regent way

- elixir-utils 78f92d5 (RegentFormat 4187ef2, Points and Credits c6b520c, Anthropic
  error message 78f92d5). Sean: at 1 and above, the number with exactly 2 decimals;
  below 1, 3 significant digits; digits are cut, never rounded up.
- The Credits window's USDC balance, the Credits admin page's amounts and the
  example wallet's ETH balance use `RegentFormat`; the showcase's sample figures read
  "1,250.00". Amounts people type and on-chain titles stay exact.

## 2026-10-27 — Refunds ask for the exact amount again

- The Credits admin's refund lock and "Send exactly" line went through the shared
  amount format and read "4.12" for a 4.123456 USDC deposit; a refund is matched to
  its purchase to the millionth on chain, so an admin sending that would never
  close it. Both lines show the amount as exact as it was paid again; the purchase
  row keeps the shared format. Found by the regents.sh chief (f6930c94).
- credits_admin_test.exs locks and renders a 4.123456 refund (failed with "4.12"
  before, succeeds now).

## 2026-10-27 — Where visits come from and where they stop

- Two new visit lines, the same on every site (docs/logging-replay-plan.md):
  `arrival` (the first page of a visit once its page connects, by route and where
  it came from: chatgpt, perplexity, claude, gemini, copilot, google, bing,
  duckduckgo, x, linkedin, github, hackernews, reddit, site, other_site or direct,
  from utm_source else the referring site, never the address itself) and `step`
  (sign_in_opened, signed_in, pairing_code_shown, agent_paired, with the agent's
  harness for the pairing steps).
- A `tool.call` line names the program that called in `client`: webmcp,
  regents-cli/<version>, another program's <name>/<version>, other or none
  (Sentinel's request after two unexplained refused notebook calls on Keyfleet).
- The privacy page says what the visit count records.
- arrivals.spec.ts: a visit from a ChatGPT link writes one `arrival /notes chatgpt`
  before its first page line, a Sign in press writes `step sign_in_opened`, and a
  second page in the visit adds no arrival; visit_log_test.exs covers every source
  name and the client names.

## 2026-10-27 — Pages tell search engines what they hold, and when they change

- Design system bca0f09: `Regent.StructuredData` shapes the schema.org node a page
  adds beside the site graph (blog post, question or forum thread, data table).
  Pages pass it as `page_data`; the root layout joins it to the site graph
  (`PublicDocuments.structured_data/1`). The discussion showcase is a QAPage with
  its marked answer accepted.
- IndexNow (`AshTemplate.IndexNow`, Oban, `outside_calls` queue): with
  `ASH_TEMPLATE_INDEXNOW_KEY` set, an hourly job queues the sitemap once per release
  and `/indexnow-key.txt` serves the key; a site queues `submit/1` for a page it adds
  or changes. Refused lists stop for good; a busy answer waits ten minutes.
- Patchbay's AI-search requests 1 and 3 (control coordination/ash-template.md).
- index_now_test.exs; structured_data.spec.ts reads the rendered head on /docs and
  the discussion showcase; the walk opens /indexnow-key.txt.

## 2026-10-27 — Bring your agent to one page

- `/pair?to=<path>` (`AshTemplateWeb.PairLive`, inside the app frame): the side panel's
  pairing box with `start`, so the pasted message ends "Once paired, start at
  <origin><path>" (elixir-utils 6773781, `RegentAgents.PairingMessage.text/4`). `to`
  must be a page on this site: one leading "/", never "//" or "/\\", no spaces or
  control characters, at most 512 characters; anything else opens plain pairing.
  Signed out, the page shows the page the agent will start on and Sign in.
- The side panel's pairing box is unchanged: it passes no `start`.
- The agent guide (llms.txt) names the link and the closing line.
- A site's own "Bring your agent" button links to `/pair?to=` with its page's path,
  URL-encoded.
- pair_live_test.exs covers which links are taken; pair_link.spec.ts pairs from a link,
  from a link to another site, and as a visitor; the walk opens /pair.

## 2026-10-27 — Bring your agent: the pairing box fits the page

- On `/pair` the pairing box keeps the width it has on a phone (24rem), so the ten
  agents' pictures stay together on a wide screen instead of spreading across it.
- The page the agent starts at wraps rather than running off a narrow screen.
- Below 22rem wide the pictures shrink to 2rem so all five in a row fit; at 320 the
  box ran 28px past the page's edge before.
- Styles only (`.pair-page` in pages/account.css); the words, the flow and the side
  panel's pairing box are unchanged. Checked headless at 1280, 390 and 320 in light
  and dark; pair_link and account walks pass.

## 2026-10-27 — A site's own pairing lines come before the start line

- elixir-utils `20ee197`: `PairingMessage.text/4` takes `setup:` (a site's own
  lines for that agent) and `start:` (the page from a pairing link), and always
  ends with the start line. The pairing box passes `start:`; the template adds
  no lines of its own. Keyfleet passes its check-in lines as `setup:`.

## 2026-10-27 — Browsers that send Global Privacy Control write no arrival or step lines

- `AshTemplateWeb.VisitLog` reads `Sec-GPC: 1`: such a visit gets no `arrival`, and
  `VisitLog.step/2` writes nothing for it, in the request (sign-in exchange, the
  browser's `sign_in_opened` report) and on its pages (the render context carries
  `gpc` into the LiveView's process, so the pairing box's steps are skipped too).
  Its other lines are written as before. Sean VISIT-SOURCES-PRIVACY a.
- The privacy policy's cookies section says so; its effective date is now 27 October 2026.
- New walk in `test/browser/arrivals.spec.ts` and a unit test in `visit_log_test.exs`.

## 2026-10-27 — Credits by card or Link through Stripe

- elixir-utils `2386ef9` (`RegentCredits.CardPurchase`, new table
  `regent_credits.card_purchases`, migration `20261027170554`): a Checkout Session in
  Stripe's Elements mode for the Credits plus the card fee the buyer sees
  (Sean CARD-FEE-RULES a); the Credits are added once from Stripe's record of the
  payment; a refund takes them back; a dispute takes them back and pauses card
  purchases while the account is below zero (Sean CARD-DISPUTE-KEYS a). Test keys
  open it to the Credits admins only, and their test payments add real Credits.
- The Credits panel's "Pay with" choice offers Card or Link while `STRIPE_SECRET_KEY`
  is set and the account may use it. Continue opens a purchase; the
  `CardCheckout` hook loads `@stripe/stripe-js` 10.0.0 only then and mounts Stripe's
  Contact Details and Payment Elements. Pay calls `confirm` on every press; on
  success the panel settles the purchase. Stripe's WebMCP tools come with its
  Elements.
- `POST /api/stripe/notices` (`AshTemplateWeb.StripeController`) checks the
  `Stripe-Signature` against the exact body and hands it to
  `RegentCredits.card_notice/3`; 404 without keys, 400 for a bad signature, 500 to
  have Stripe send it again.
- `sign_in` security profile: Stripe.js and Link's scripts, frames, images and API,
  from Stripe's published list.
- Stripe's return address is `/account/credits`; card and Link finish on the page,
  and Stripe's notice adds the Credits for any payment that leaves it.
- `lazy_html` (test only) so LiveView tests can read pages.
- New `test/ash_template_web/card_purchase_test.exs`: the panel's Continue and paid
  flow adds the Credits once, alongside the notice; a forged notice is refused; a
  person who is not an admin sees USDC only under test keys. Stripe itself is not
  reached by any check; the browser walk cannot load Stripe's form.
- Release needs the migration above (new table) and, to switch it on, the three
  Stripe secrets staged on the app. The public changelog gets its line when live
  keys are set; until then only the Credits admins see the choice.

## 2026-10-27 — Released v117: serving through the pooler, Credits by card ready

- Fly v117, image be65b7d (Sean's letters STRIPE-TEMPLATE-RELEASE a and POOLER-LIMITS a),
  live 20:18Z; rollback v116 (f76f138). Carries the pooler change and everything since
  f76f138 on main (24 commits), including visit lines with the Global Privacy Control
  rule and Credits by card or Link. Card payments stay off until Stripe's keys are set.
- Before the deploy, on the template's own login (`template-runtime`, used only by
  `ash-template-web`): statement 15 s, lock wait 5 s and idle open transaction 15 s are
  stored on the login (`ALTER ROLE CURRENT_USER SET …`), read back from `pg_roles`.
- From the be65b7d image on temporary machines that removed themselves: a connection
  through the pooler with the release's own certificate settings answered as
  `template-runtime` with 15s / 5s / 15s; `pending-migrations` printed only
  `shared-pending: regent_credits 20261027170554`; `migrate-shared` printed
  `applied: regent_credits 20261027170554` (table `regent_credits.card_purchases`).
  The release step migrated nothing new.
- Settings: `DATABASE_POOLED_URL` now names the pooler host (same login and database,
  changed on the server without showing it); `ASH_TEMPLATE_INDEXNOW_KEY` set. Both staged,
  then applied by the deploy.
- Before: full check on be65b7d 92 ExUnit, 24 JS, 292 browser steps (2 skipped).
- After: `/capabilities.json` reports be65b7d; the running site's database host is the
  pooler and its connections carry the three limits; `/`, `/account`,
  `/account/credits`, `/skill.md`, `/healthz` and `/api/v1/health` answer 200;
  `/indexnow-key.txt` serves the key; a Stripe notice answers 404 "takes no card
  payments" while the keys are unset. The only errors are the health check's refusals
  in the two seconds the single machine restarted.

## 2026-10-27 — Credits bought by card earn Points

- elixir-utils 9a015f8: a card or Link purchase tells the site when its Credits are
  added (`RegentCredits.Signals`, `:card_purchase_credited`). The Points listener
  (`AshTemplate.Points.Award`) records `credits.purchase_settled` from it with source
  kind `card_purchase`, and Points' check (`AshTemplate.Points.CreditsPurchase`) reads
  the card purchase: one Point per Credit, as for USDC, and nothing for the card fee
  (Sean, CARD-POINTS a). Credits a test card paid for earn no Points
  (`card_test_payment`). Points stay off until Sean approves the rule and start time.
- `platform/.env.example` names the three Stripe settings.

## 2026-10-27 — Ordinary work ships without asking

- Regent Workflow skill: "Act on your recommendation" now lists only protected work
  (sign-in, secrets, production data writes or migrations that change or delete
  existing rows or columns, wallets, staking, claims, money, contract changes).
  The side panel, pairing box and additive migrations are ordinary. An ordinary
  release is never a question or a "Blocked decisions" line: it is shipped, tested
  on the live site and reported afterwards with its rollback (Sean, 27 Oct 22:31Z,
  "the agents need more autonomy"; approved 22:49Z, AUTONOMY-RULE a).
- Release checklist: live first, small and reversible, every release names its
  rollback; Sentinel reads after release and before protected releases only;
  regression tests follow Sean's one-hour live confirmation (Sean, 27 Oct 22:28Z).

## 2026-10-27 — Layers: one stacking place per layer, and the grammar page

- Six layers name what sits on what: Ground, Sheet, Card, Panel, Window and Tip.
  The tokens come from design-system d53b8f1 (regent_ui's
  `design_system_tokens.css`): one stacking place per floating layer
  (`--rg-layer-card` 1, `-shade` 10, `-panel` 20, `-header` 30, `-tip` 50,
  `-skip` 60) and one shadow each for panel and tip, both `none`. Windows need
  no number: the browser lifts them above the page. Layers stay flat (Sean, LAYERS-DEPTH a): height shows in the edge,
  the fill and how a thing arrives.
- Hard cutover in product CSS: the shell's skip link, header, rail, side panels,
  footer, phone menu and its shade, the rail's tips, the Regents Products menu,
  the account popover and the Credits dialog's close button take their place
  from the tokens. The bottom bar never floats (card layer), so on a phone the
  open menu, the side panel and the shade cover it. The left column states no
  number of its own. The phone header sits above the phone panels, which start
  below it, so the account menu now opens over an open panel instead of behind
  it.
- Credits' "Where to spend" is a shared window (`Regent.Structure.dialog`
  opened as a popover): cut corners in place of its rounded box and soft shadow.
  The rooms menu loses its soft shadow too.
- With less motion asked for, a page's headline and its cards now fade in
  (`fadeIn` in the motion kit) instead of appearing with no change at all;
  windows, panels and menus are simply there, as before. A window opened as a
  popover now carries `data-settled` once it rests, like a modal one.
- `/showcase/grammar` has three views, each its own address: Nouns (the shared
  pieces by name), Verbs (`/verbs`: arrive, settle, open, press, leave, played by
  the motion kit, with a fade when less motion is asked for) and Layers
  (`/layers`: the six layers drawn in Regent's look, square with cut corners
  and hairlines, beside a table of each layer's edge, fill and arrival).
- Artwork that orders its own pieces (cubes, crown, hero, lab pages) keeps its
  numbers; they never meet the page's layers.

## 2026-10-27 — Released v118: layers, one stacking place each

- Fly v118, image e8ed190, live 23:18Z; rollback v117 (be65b7d). Ordinary work, shipped
  under AUTONOMY-RULE a after the template chief's review. Carries everything since
  be65b7d on main: card purchases earn Points (304fdac, CARD-POINTS a), the workflow skill
  text (88a6929) and the layers change (e8ed190, design-system d53b8f1). No migrations.
- Before: full check on e8ed190: 94 ExUnit (9 properties), 24 JS, 298 browser steps passed,
  1 failed (visits.spec.ts:89 on the phone, a known timing gap; 4/4 when run alone), 3 skipped.
- After, headless on template.regents.sh: `/capabilities.json` reports e8ed190; the home page,
  a room and the three grammar pages answer at 1280 and 390 with no page errors; header 30,
  rail 20 and footer 1 read from the layer tokens; a header tool's name shows at the tip
  layer; on a phone the open menu covers the bottom bar; with less motion asked for, the
  home headline settles fully visible.

## 2026-10-27 — Agents keep their own key; check-ins stop warning; amounts of any size render

- elixir-utils 7794682, all fourteen pins: every pairing message but ChatGPT's adds
  "If other agents share your computer, use your own key: begin every shell with export
  SIWA_AGENT_HOME=~/.siwa-agent/<runtime>", the folder named after the agent's runtime
  (`claude-code`, `codex`, `muse` and so on, `YOUR-RUNTIME` for any agent), so
  agents sharing one computer pair as separate agents (Sean, AGENT-KEY-HOME a). Grok Bot
  is told `/workspace/.siwa-agent`, the folder its guide here already names, because only
  `/workspace` survives its restarts. The template's pairing box adds no setup lines of
  its own, so nothing here repeated it.
- The same version stops every agent check-in logging "Missed 1 notifications in action
  RegentAgents.PairedAgent.touch": pairing, check-in and making a code run in
  `Ash.transact/2`. Listed in `docs/feature-map.md`.
- The same version shows amounts of any size exactly: 1e32 and above no longer crash a
  page (`RegentFormat.amount/1` and `token_amount/2` raised past 34 digits; Autolaunch
  report).
- The same version shows Points amounts exactly at any size.
- With codes out for two agents at once, an agent that pairs now shows under the code
  it used, and the other agent keeps its code. Before, the newest agent showed under
  whichever agent was on screen and the spent code was offered again (Autolaunch
  report). The pairing box asks the library which agent each code paired.

## 2026-10-27 — Addresses keep their own letters

- design-system 804c752: an address, ENS name or short address shows in its own letters
  wherever it sits. A row or button style that sets capitals, small capitals or wide
  letter-spacing no longer reaches it, and it always reads left to right. The shared
  address also gains a full form, every character and wrapping, for an address a person
  must check, and a compact form, the words and the copy icon only, for beside a small
  control in a narrow row. No template page uses those two yet.

## 2026-10-27 — Released v119 and v120: own agent keys, the right agent under each code, addresses in their own letters

- Fly v119, image 2933931, live 23:50Z; rollback v118 (e8ed190). Carries e6e100b (elixir-utils
  7794682: own agent keys, Grok Bot's key in /workspace, check-ins stop missing notifications,
  amounts of any size, the pairing box names the agent each code paired) and 2933931 (the
  visits walk waits for the page's line). No migrations.
- Fly v120, image 7de32ab, live 23:55Z; rollback v119 (2933931). Carries 7de32ab (design-system
  804c752: addresses keep their own letters; full and compact forms). No migrations.
- Ordinary work, shipped under AUTONOMY-RULE a, under the shared release lock after reading
  that no release was running.
- Before: full check on 2933931's tree and on 7de32ab's tree: 94 ExUnit (9 properties), 24 JS,
  299 browser steps passed, 3 skipped, at 1280 and 390 (Chromium; WebKit not run on the Mac).
- After, headless on template.regents.sh: `/capabilities.json` reports each commit in turn; the
  home page, Account, Notes and llms.txt answer 200 at 1280 and 390 with no page errors and no
  sideways scroll; Grok Bot's skill and the pairing line both name `/workspace/.siwa-agent`;
  the live stylesheet carries the address letter reset; the health check passes.

## 2026-10-27 — Motion lab panels take their layers

- The motion lab's sample drawer, sheet, shade, note, Share menu and sparks
  (`assets/css/pages/animations.css`) take the tip layer instead of their own numbers
  (30, 60, 65, 70, 80). On a site that shows the lab inside its shell, they now cover
  the header and sit under the skip link, which a keyboard reaches on top of them.
  Techtree found the skip link dimmed under the open drawer once it moved to the skip
  layer. Their shadows are the tip's, which is none.
- The header and footer lab's sample header sits at the card layer
  (`assets/css/pages/header_footer_lab.css`), enough to keep its Products menu over
  the page below it.
- Checked: a page check with a stand-in header and focused skip link around the lab
  at 1280 and 390 (drawer over the header, skip link on top for every panel), and the
  motion, windows, layout and pages walks, 299 steps passed (Chromium; WebKit not run
  on the Mac).

## 2026-10-27 — Released v121: motion lab panels take their layers

- Fly v121, image 1395f42, live 00:09Z on 28 October; rollback v120 (7de32ab). Carries
  1395f42 (the motion lab's panels and sparks at the tip layer; the header and footer lab's
  sample header at the card layer). CSS only; no migrations.
- Ordinary work, shipped under AUTONOMY-RULE a, under the shared release lock after reading
  that no release was running.
- Before: the motion, windows, layout and pages walks, 299 steps passed at 1280 and 390
  (Chromium; WebKit not run on the Mac).
- After, headless on template.regents.sh: `/capabilities.json` reports 1395f42; with a
  stand-in header and a focused skip link around /animations at 1280 and 390, the drawer,
  sheet, note and Share menu each sit at the tip layer with no shadow, the skip link stays on
  top and each closes again; the header and footer lab's header sits at the card layer; no
  page errors and no sideways scroll.

## 2026-10-27 — Pair New Agent always lands on the agent choice

- A page's Pair New Agent button now moves focus to the chosen agent (or the first) in the
  side panel's pairing box and scrolls its picture into view. With the panel already open,
  the press used to change nothing a person could see (Keyfleet report).
- `platform/test/browser/pairing.spec.ts` shortens the open panel so the agents are out of
  view, presses again, and checks the agent is focused and in view; it fails against the old
  button. Listed in `docs/feature-map.md`.

## 2026-10-28 — Released v122: Pair New Agent lands on the agent choice

- Fly v122, image 3df1d08, live about 00:25Z; rollback v121 (1395f42). Carries the Pair New
  Agent fix and 3df1d08, which restores v121's motion lab files and changelog on main after
  8b1e3b4 was committed from an older tree. No migrations.
- Ordinary work, shipped under AUTONOMY-RULE a, under the shared release lock after reading
  that no release was running.
- Before: full check on the fix: 94 ExUnit (9 properties), 24 JS, 301 browser steps passed, 3
  skipped, at 1280 and 390 (Chromium; WebKit not run on the Mac). The new pairing check fails
  against the old button.
- After, headless on template.regents.sh: `/capabilities.json` reports 3df1d08; the home
  page, Account, Notes and the motion lab answer 200 at 1280 and 390 with no page errors and
  no sideways scroll; the live script carries the new Pair New Agent step; the health check
  passes.

## 2026-10-28 — Shared changes: template first, Sean signs off, all sites at once

- Sean's rule of 28 Oct 06:40Z is in `skills/regent-workflow/SKILL.md` ("Shared changes"),
  replacing "Shared work across the five Ash sites": a shared change is built and tested
  here and released on template.regents.sh, Sean signs off the template's version, then it
  goes to all five sites at once and each go-live is watched. Signing off a shared change
  joins the list of things that wait for Sean. `skills/ash-stack/SKILL.md` and
  `skills/ash-signals/SKILL.md` say the same.
- The rollout files and the live check that reads each site's live commit are in the
  workspace's `control/rollouts/`.

## 2026-10-28 — Design and animation work uses the stacked layers, vgpu and Anime.js skills

- The Regent workflow skill now says every design, layout or animation task follows the
  stacked design language (the Layers section of the design system's style guide) and
  loads the vgpu-island and animejs skills.

## 2026-10-28 — No W-word openings in on-screen words

- Regent Workflow and ash-frontend skills: Sean's 28 Oct rule that headings, labels,
  tips, buttons, empty states and page titles never open with who, what, where, why or
  when. It had only been written into the local skills checkout; it is now on main for
  every session.

## 2026-10-28 — Sign-in stops missing notifications

- `AshTemplate.Accounts.SessionAuthority` runs sign-in, refresh, switching person and
  signing out in `Ash.transact/2` instead of `Repo.transaction/1`, so the updates
  inside send their notifications once the transaction commits instead of logging
  "Missed 1 notifications". A refused transition still keeps what it wrote (the
  first row of a new sign-in, and the revocation of a lineage whose count ran out),
  so its answer leaves the transaction wrapped and the answers callers see are
  unchanged.
- The test settings raise on a missed notification
  (`config :ash, :missed_notifications, :raise`).
  `platform/test/ash_template/accounts/session_authority_test.exs` walks sign-in,
  refresh, switching and signing out, and checks a lineage whose count ran out stays
  signed out; both tests fail against the old transactions. Listed in
  `docs/feature-map.md`. Sean gave the go on 28 October ("3. a").

## 2026-10-28 — Released v123

- template.regents.sh v123 runs `5a1fe29e` (the sign-in transaction fix), released at
  07:27Z after Sentinel's clear pre-read. Rollback: v122, `3df1d084`.

## 2026-10-28 — regents-cli 1.10.19, and always the newest

- Moved to regents-cli 1.10.19 (tag commit `02f89615c4d8ceaf4c6f597f07112e41f001adc6`,
  wheel SHA256 `935c21569a740d90ea7d6951584ab6de3757af8fa07e2302f5c01ef69e959080`):
  `REGENTS_CLI_REV`, the agent guide, `llms.txt`, `cli/COMMANDS.md`, `cli/README.md`
  and `cli.release` in `platform/priv/capabilities.json`. 1.10.19 carries this site's
  `commands.json`, OpenAPI document and tool manifest byte for byte.
- Sean, 28 October: every site is always on the newest regents-cli. The new
  `make check-cli-latest` (`scripts/check-cli-latest.sh`, part of `make check`) reads
  the newest release from PyPI and fails until the pin, the guide (release, commit and
  wheel SHA256), every install line and `cli.release` name it.
- The 44 operations still marked as waiting for a release now name the first release
  whose command matches today's (1.10.17 for all of them, read from each release's
  copy), so the agent guide no longer calls them not yet released. Dropped the four
  stale "next release" notes from `cli/COMMANDS.md`.

## 2026-10-28 — The newest SIWA on both sides

- `make check-cli-latest` became `make check-siwa-latest` (`scripts/check-siwa-latest.sh`):
  Sean's rule names SIWA, so besides the newest regents-cli it now also fails until the
  pinned elixir-utils commit contains the newest change to the SIWA library
  (`siwa/siwa-elixir/apps/siwa`, today `48a2e1c`). The template's pin `7794682` does.

## 2026-10-28 — Chiefs keep moving, improve Skills and review their threads

- The Regent workflow skill now says every chief keeps its threads moving, improves the
  Skills it uses and uses them itself, reviews the code it ships, and checks each
  thread's claims against evidence.

## 2026-10-28 — Workflow skill: release gate, second review, release record

- `skills/regent-workflow/SKILL.md` (Sean, 28 Oct 08:47Z, "1. a" in the siwa-server thread):
  a push or release runs only when the check passed, chained so a failure stops it; a
  sign-in, signing, keys, single-use or money change gets a reviewer who sees the code, not
  the author's conclusion, and every fix made during review or release gets its own review;
  each release ends with its record (health, logs from the release start, record commit,
  Sentinel's after-read, the lanes told). Release checklist renumbered.

## 2026-10-28 — An action only a person can do is a bug

- `skills/regent-workflow/SKILL.md` (Sean, 28 Oct 08:49Z): an agent may own a Privy
  account, so every action an account's owner can do is open to an agent through the
  website in a browser, WebMCP, hosted MCP and the regents CLI. Value transfer stays
  signed by the owner, and an agent owner signs with its own key.
- `skills/ash-webmcp/SKILL.md`: the agent inventory covers every owner action, with
  missing surfaces listed as gaps.
- `docs/agent-parity.md`: one row per action on its four surfaces, audited on
  `0ae11a7c`, with ten gaps and who closes each.

## 2026-10-28 — The SIWA check, after its review

An adversarial review of the two commits above found five things, all fixed here:
- The script names its three site-specific places at the top (the agent guide, the
  folders holding install lines, `capabilities.json`), so each site copying it sets
  those and keeps every check the same; the sites keep their guides at other paths.
- An install line ending a sentence (`regents-cli==1.10.19.`) no longer reads as another
  release; a `@elixir_utils_ref` line the script cannot read now says so instead of
  failing with a blank commit.
- The 44 operations name 1.10.16 as their first release, not 1.10.17: the release's copy
  of the commands is the same from 1.10.16 to 1.10.19. Where the entry above says the CLI
  carries this site's tool manifest byte for byte, it is the YAML API contract.

## 2026-10-28 — Claude as an agent on every site

- design-system moves to `cda974f` (from `804c752`, one commit): `Regent.Account` gains
  the picture for the `claude` harness. Pairings are shared across sites, so once anyone
  pairs a Claude through Keyfleet's connector, a site whose pin lacks it raised in the
  agents list and side panel for that person (`agent_mark` reads pictures with
  `Map.fetch!`).
- Every elixir-utils package moves to `14013e4` (from `7794682`): the agents library as on
  elixir-utils main, so it knows Claude as a kind of agent, with nothing of the Claude
  connector's sign-in changes, which wait for their own decision. Without it, a Claude
  pairing made on another site could not be read here at all. The template sets no
  pairing option, so nothing else changes.
- A test draws the picture for every agent kind the library knows
  (`platform/test/ash_template_web/agent_pictures_test.exs`), so the next new kind fails
  the checks here before it reaches a person's agents list.

## 2026-10-28 — Released v124

- template.regents.sh v124 runs `0b11a68e` (the SIWA check after its review, and Claude
  as an agent on every site), released at 12:33Z. The first try at 08:30Z was cut off
  mid-build and never went live. Live check: `/capabilities.json` names the commit and
  `cli.release` 1.10.19, `/healthz` answers 200, `/agents.md` names 1.10.19 and its
  source commit, and the home, agents, docs, account, connections, chat and discussion
  pages open at 1280 and 390 with no page errors and nothing wider than the screen. The
  logs since the release show only the machine's few seconds of restart. Sentinel's
  after-read is asked. Rollback: v123, `5a1fe29e`.

## 2026-10-28 — Asking not to be tracked starts no visit; questions read as questions

- A browser that sends Global Privacy Control (`Sec-GPC: 1`) starts no visit
  (`AshTemplateWeb.VisitLog`): it gets no `_visit` cookie and loses one it was given
  before, the page carries no `regent-visit` tag, and its requests and API calls carry
  no visit, even one the browser sends itself. It still writes no `arrival` or `step`
  line. Before, it kept the cookie and its visit id was on every page, tool and request
  line, so its visit could still be pieced together, which the privacy policy rules out.
  The same change regents.sh made (its 35ec4dc and 012b9cbf); the server checks in
  `platform/test/ash_template_web/visit_log_test.exs` and the walk in
  `platform/test/browser/arrivals.spec.ts` prove it, and the new cookie check fails on the
  old line. Listed in `docs/feature-map.md`.
- design-system moves to `6dcd85e` (from `cda974f`, one commit): a forum question with no
  replies and no marked answer is described to search engines as a discussion until it
  has an answer, instead of a question page with nothing to show
  (`Regent.StructuredData.discussion/1`, used by `/showcase/discussion`).
- `/capabilities.json` `build.release` names only the Fly image's tag (for example
  `0b11a68`), not the registry path and app name before it
  (`platform/config/runtime.exs`). A release still refuses to start without
  `FLY_IMAGE_REF`.

## 2026-10-28 — Released v125

- template.regents.sh v125 runs `14a8a3e4` (asking not to be tracked starts no visit;
  forum questions; the release tag alone), released at 12:53Z. Live check:
  `/capabilities.json` names the commit and `build.release` reads `14a8a3e`; `/healthz`
  answers 200; a browser sending Global Privacy Control, even with an old `_visit`
  cookie, leaves with no cookie and its page has no visit tag, while one without it
  gets both; home, agents, docs, account, connections, chat, notes and the discussion
  page open at 1280 and 390 with no page errors and nothing wider than the screen. The
  logs since the release show only the machine's six seconds of restart. Sentinel's
  after-read is asked. Rollback: v124, `0b11a68e`.

## 2026-10-28 — Agents mark their person's activity read

- First fix under "an action only a person can do is a bug" (`docs/agent-parity.md`, G9):
  "Mark all read" on `/app/activity` was the page's alone. A paired agent now does the same
  with signed `POST /api/v1/activity/read` and an empty body (`markActivityRead`), the
  browser tool `activity_mark_read` and the command `activity mark-read`, which arrives in
  the next regents-cli release. It runs the page's own Ash action
  (`AshTemplate.Activity.mark_all_read/1`), so it marks the person's notifications and no
  one else's, the person's open pages hear it as when they press the button, and it
  answers `{"marked_read": true}`; any other body is refused with
  `invalid_mark_read_request`. The OpenAPI documents move to 7.2.0.
- `cli/README.md` no longer says muting and chat stay on the website: muting has commands,
  and every action still missing one is a gap row in `docs/agent-parity.md`.

## 2026-10-28 — Released v126

- template.regents.sh v126 runs `4ca06873` (Agents mark their person's activity read),
  released 13:05Z. Checks on that exact tree: `make check` exit 0 (100 server tests, 9 of
  them properties; 24 script tests; the browser walk 301 passed and 3 skipped at 1280 and
  390 in headless Chromium; WebKit is not run on the Mac). The reviewer passed it.
- Live check 13:07Z: `/healthz` 200; `/capabilities.json` build.commit `4ca06873` and the
  `markActivityRead` row open; `openapi.json` 7.2.0 lists `/api/v1/activity/read`; an
  unsigned `POST /api/v1/activity/read` answers 401 `http_headers_missing`; home, agents,
  docs, account, connections, chat, notes and the discussion page open at 1280 and 390
  with no page errors and nothing wider than the screen. Sentinel's after-read is asked.
  Rollback: v125, `14a8a3e4`.

## 2026-10-28 — Bandit 1.14.1

- Moved the Bandit web server to 1.14.1, which closes EEF-CVE-2026-116078 (HTTP/2 DATA
  frames of one byte each make the server hold far more memory than the request body).
  Lockfile-only change: `platform/mix.exs` already allows it with `~> 1.14`, and the lock
  is what decides the version a release runs. Patchbay, Keyfleet and Techtree took the
  same line earlier today in their own repositories.

## 2026-10-28 — The card purchase check waits long enough on a busy machine

- `test/ash_template_web/card_purchase_test.exs` waits up to two seconds for the Credits
  panel's own tasks (Stripe's answer, then the Credits write) instead of
  `render_async`'s default tenth of a second. On a busy machine it failed about one run
  in three on main and on live v126 alike, with nothing wrong in the panel; eight runs
  in a row succeed with the longer wait.

## 2026-10-28 — The account menu replaces the side panel; pairing moves to the Account page

- Sean, 28 Oct 07:54Z: "instead of a sidepanel, do a upper right modal. and then the
  account route on all sites handles that privy user . and all account routes should be
  the exact same, with some local site versions shown first".
- The account's button at the top right opens the account menu (`Regent.Account.menu`,
  design-system side branch): a browser popover hanging under the button on the Tip
  layer, with the person's picture, name and wallet, their three most recently active
  agents (`AshTemplateWeb.MenuAgents`, was `PanelAgents`; the `MenuAgents` hook reads
  where each was last active each time the menu opens), Pair New Agent, Manage Account
  and Sign out. It hangs from the button by name (`anchor-name: --rg-account-menu` on
  `#account-chip`). Following a link in it closes it (`shell_panels.ts`); Escape or a
  press outside it does too.
- Any link to a #fragment of the page already open, and a page opened at one, bring
  what it names into view every press (`arriveAt` in `shell_panels.ts`). The pairing
  box still gives focus to the chosen agent, or the first, as v122 did, now from the
  menu, the Account page and the agent guides' link alike.
- The right side panel is gone: `#shell-aside`, its button, its grid column and slide,
  the `ash_template_aside` cookie, `<html data-aside>` and `data-aside-here`, the
  `data-aside-toggle`/`data-aside-open` handlers and the `#shell-pairing` hash. On the
  narrowest phones the account's button shrinks to its picture instead of giving way
  to the panel's button.
- The Account page uses the shared `Regent.Account.layout`: any parts only this site
  has first, then the account card and the agents full width, then Pair New Agent
  (`AshTemplateWeb.PairingBox`, `#account-pairing-box`) beside Credits and the public
  name. The page's own `.account-layout`/`.account-column` rules are gone. Pair New
  Agent under the agents moves down to it.
- Every word that sent people or agents to "Pair New Agent in the side panel" now says
  "on their Account page": the refusal hints (`plugs/agent_wallet.ex`,
  `rooms_controller.ex`), `:regent_mcp_agents` in `config.exs`, `capabilities.json`, the
  agent guides (link `/account#account-pairing`), `llms.md`, `agents.md` and each agent's
  page, `docs.md`, `about.md`, `build-skill.md`, `site_tools.ex`, the API contract and
  `openapi.json`, and `cli/COMMANDS.md` and `cli/commands.json`. The matching
  elixir-utils `regent_agents` hints change on their own side branch.
- Walks: `account_menu.spec.ts` replaces `side_agents.spec.ts` (three agents and Manage,
  placement under the button at 1280, 2000, 390 and 320, Escape, Manage Account and
  Pair New Agent closing the menu, the bottom bar covered on a phone); `pairing.spec.ts`
  works on the Account page's box; `layout.spec.ts` drops the side panel's checks.
  The walk's server gets ten minutes to start (`playwright.config.ts`), since a busy
  machine can take more than the old three for its three mix starts.
- When the person's agents can't be read, the account menu and the Account page log a
  warning naming the kinds of failure (never its words, which can hold the person's id),
  so the live site's logs show it instead of only a quiet "unavailable".

## 2026-10-28 — The phone menu covers the bottom bar too; two lab shadows on the Tip layer

- On a phone, while the menu is open, the bottom bar is out of reach as well as the page
  (`#shell-footer` goes inert with `#app-shell-scroller` in `app.ts`), so Tab and a
  press can no longer land on its links behind the menu. The walk in
  `test/browser/layout.spec.ts` checks both while the menu is open and after it closes.
- The motion lab's toast (`animations.css`) and the header-and-footer lab's product list
  (`header_footer_lab.css`) use `--rg-layer-tip-shadow` instead of shadows of their own,
  as the Layers rules ask.
- Carried from the design chief's `dm/page-behind-1028` (`d328dc2a`); its side-panel half
  is moot now the side panel is gone. The account menu needs no such step: it is a
  browser popover in the top layer, so nothing on the page can draw over it, and a press
  outside it closes it.

## 2026-10-28 — regents-cli 1.10.20

- Sean, 28 Oct 07:16Z: every site always on the newest. `REGENTS_CLI_REV` in the `Makefile`
  moves to `0e3768f5b92fe8210fb00fea0053bcb5e9c2afaf` (tag v1.10.20); the agent guide names
  1.10.20, that commit and wheel SHA256
  `55b242b41a86e4bd1952e1edb93e31e5cd718186e735867d4b276243f96179ad`; `capabilities.json`
  `cli.release` is 1.10.20; every install line (`agents.md`, `llms.md`, `cli/COMMANDS.md`)
  reads `uv tool install --python 3.14 regents-cli==1.10.20`, since 1.10.20 needs Python 3.14
  (one of its engines has no Python 3.15 wheel yet). `activity mark-read` is still marked
  for the next CLI release. `scripts/check-siwa-latest.sh` failed on main from the moment
  1.10.20 reached PyPI, as it should, and passes again with these pins.

## 2026-10-28 — Released v127

- template.regents.sh v127 runs `b204e320` (Bandit 1.14.1), released 15:46Z under Sean's
  TEMPLATE-V127 "8 a" (15:37Z). The reviewer passed it at 15:30Z.
- Live check 15:47Z: `/capabilities.json` build.commit `b204e320`; home, agents, docs,
  account, connections, chat, notes, the discussion page and `/api/v1/rooms` open with 200
  at 1280 and 390 in headless Chromium with no page errors and nothing wider than the
  screen (WebKit is not run on the Mac). Sentinel's after-read is asked. Rollback: v126,
  `4ca06873`.

## 2026-10-28 — Claude Duet's picture

- Sean, 28 Oct 15:37Z, answered the picture decision with the Claude Duet logo.
  `@design_system_ref` moves to design-system `b7a34d89`, where the `claude` harness (Claude,
  the connected app) draws `claude-duet.png`; Claude Code keeps its own picture.
  `test/ash_template_web/agent_pictures_test.exs` still draws every agent kind.

## 2026-10-28 — The tools card reads Techtree's and Keyfleet's new addresses

- Techtree (v201) and Keyfleet moved their browser tools list to `/capabilities.json`, and
  the old `/capabilities` answers 404, so the template's tools card showed neither site's
  tools. `AshTemplate.SiteTools` and the walk's offline answers
  (`test/browser/support/server/walk_offline.ex`) now read
  https://techtree.sh/capabilities.json and https://keyfleet.ai/capabilities.json. Reported
  by the Techtree chief, 28 Oct 14:50Z. regents.sh, Patchbay and Autolaunch still answer at
  their old addresses.

## 2026-10-28 — Released v128

- template.regents.sh v128 runs `2848406d` (the account menu replaces the side panel;
  regents-cli 1.10.20; Claude Duet's picture; the tools card reads Techtree's and Keyfleet's
  new addresses), released 17:35Z. Checks on that exact tree: `make check` exit 0 (100
  server tests, 9 of them properties; 24 script tests; the browser walk 310 passed and 4
  skipped at 1280 and 390 in headless Chromium; WebKit is not run on the Mac). The reviewer
  passed the account menu (`d7ead6ae`).
- Live check 17:36Z: `/capabilities.json` build.commit `2848406d` and `cli.release` 1.10.20;
  `agents.md` names 1.10.20 and `0e3768f5…`; `claude-duet.png` answers 200; the tools of
  Techtree, Keyfleet, Patchbay and Autolaunch load (15, 91, 55 and 18); home, agents, docs,
  account, connections, chat, notes, the discussion page and `/api/v1/rooms` open at 1280
  and 390 with no page errors and nothing wider than the screen. Sentinel's after-read is
  asked. Rollback: v127, `b204e320`.

## 2026-10-28 — The tools card reads regents.sh's new address

- regents.sh (`206f8c1f`, live 17:36Z) moved its browser tools list to `/capabilities.json`,
  as Techtree and Keyfleet did, and its old `/capabilities` answers 404, so v128's tools
  card could not read it. `AshTemplate.SiteTools` and the walk's offline answers now read
  https://regents.sh/capabilities.json. Patchbay and Autolaunch still answer at their old
  addresses.

## 2026-10-28 — Claude Duet's picture on the white tile

- `@design_system_ref` moves to design-system `99c99d14`: the paper around Claude Duet's
  picture and three stray corner marks are transparent, so it sits cleanly on the agent
  mark's white tile (reviewer, 28 Oct 17:38Z).

## 2026-10-28 — Released v129

- template.regents.sh v129 runs `b9d8ef1c` (the tools card reads regents.sh's new address;
  Claude Duet's picture on the white tile, design-system `99c99d14`), released 17:53Z.
  Checks on that exact tree: `make check` exit 0 (100 server tests, 9 of them properties;
  24 script tests; the browser walk 310 passed and 4 skipped at 1280 and 390 in headless
  Chromium; WebKit is not run on the Mac).
- Live check 18:05Z: `/capabilities.json` build.commit `b9d8ef1c` and `cli.release`
  1.10.20; the tools of all five sites load (Regents 25, Patchbay 55, Techtree 15,
  Autolaunch 18, Keyfleet 91); `claude-duet.png` answers 200; home, agents, docs, account,
  connections, chat, notes, the discussion page and `/api/v1/rooms` open at 1280 and 390
  with no page errors and nothing wider than the screen. Rollback: v128, `2848406d`.

## 2026-10-28 — The walk opens one page before its first check

- The first signed-in checks of a cold run sometimes timed out waiting for the page's
  buttons to be wired (rooms, messages and the harbour, on one run of 28 Oct). The server
  log of every run that day shows no failed agents read and no page crash or rejoin, so
  the cause was the newly started server's slow first pages. The walk now opens one
  signed-in room once before any check (`test/browser/support/warm_up.ts`, Playwright's
  global setup, which runs after the server answers), never retried; a page that still
  cannot wire itself fails the walk. The routing that keeps the browser on this machine
  is shared with it (`onThisMachine` in `test/browser/support/test.ts`). Reviewer, 28 Oct
  17:52Z.

## 2026-10-28 — Refusals link to their help page

- An agent refused as `agent_not_paired` or `person_not_here`, at check-in or at any door
  that needs its person, reads "Help: https://patchbay.help/errors/<code>" after the
  hint, Patchbay's page for that refusal (live since Patchbay v286, `80ea2e9b`).
  `RegentAgents.HTTP` carries the check-in refusals (elixir-utils `9539469f`, the change
  on `9da44bdc`, merged into elixir-utils main `4295e7ce`);
  `AshTemplateWeb.Plugs.AgentWallet` carries the others. The six examples in
  `openapi.json` and both contract copies say the same. Rebuilt on main from the held
  side branches (elixir-utils `34e87a7`, template `109b91ec`), which predate the Account
  page wording. Rollout: control `rollouts/2026-10-28-patchbay-help-links.md`.

## 2026-10-28 — Released v130

- template.regents.sh v130 runs `cc74b3f3` (the walk's warm-up page load and the v129
  record; test code only), released 18:06Z. Checks on that exact tree: `make check` exit 0
  (100 server tests, 9 of them properties; 24 script tests; the browser walk 310 passed
  and 4 skipped at 1280 and 390 in headless Chromium, no misses; WebKit is not run on the
  Mac). Live check 18:07Z: `/capabilities.json` build.commit `cc74b3f3`; the eighteen page
  loads at 1280 and 390 with no page errors and nothing wider than the screen; all five
  sites' tools load. Sentinel's after-read is asked (control `d52d6609`). Rollback: v129,
  `b9d8ef1c`.


## 2026-10-28 — Titles are one or two words

- New founder copy rule beside the W-word one: every heading, eyebrow, tab, column
  header, `<dt>`, field label, step title and guide heading is one or two words, never a
  phrase (Sean, 22:34Z: "instead of 'Work that cites it' , write 'Citation'"). Written into
  `skills/regent-workflow/SKILL.md` and `skills/ash-frontend/SKILL.md`; the counterexample
  list, 89 real titles from Keyfleet and this template with their replacements, is
  `skills/regent-workflow/references/short-titles.md`. Skills only; the template's own
  titles in that list still need their sweep.

## 2026-10-28 — Credits balance in the account menu on the narrowest phones

- At 320px the header's Credits balance ("10.00 Credits", shortened to "10.00") pushed
  the header 15px past the screen (design reviewer, measured on `/showcase/preview`).
  Design chief's choice (b): narrower than 22.5rem the header leaves the balance out
  (`#shell-credits-button`, `assets/css/components/shell.css`) and the account menu shows
  it as one row under the wallet, in the header's words, through design-system's new
  `balance` slot (`3134bab0`). The row opens the same Buy Credits panel; the menu closes
  first, so focus returns to the account button when the panel closes
  (`assets/js/shell_panels.ts`). The phone header's rule that drops the word "Credits" now
  applies to the header's button only, so the row keeps it.
- Walk checks in `platform/test/browser/account_menu.spec.ts`: at 320 the header has no
  balance, the menu row reads "10.00 Credits", is 44px tall, opens Buy Credits, and the
  page fits the screen with the menu open; at 390 and 1280 the header keeps the balance
  and the row is hidden. Feature map and public changelog updated.

## 2026-10-28 — Skills: a timer loop becomes an AshOban sweep

- `skills/elixir-stack/references/oban.md` gains "A timer loop becomes a sweep", proposed
  by the Patchbay chief from its escrow Base reads and agent repairs: the next sweep is
  the retry (`max_attempts 1`, no `on_error` that leaves `where`), outside calls with
  `transaction?(false)`, one job per row, a declining guard ends `:ok`, the release note
  states the outside-call rate, and the old loop goes in the same change.

## 2026-10-28 — Agents chat with the assistant for their person

- G10 under "an action only a person can do is a bug" (`docs/agent-parity.md`): the chat
  with the site's assistant on `/chat` was the page's alone. A paired agent now lists its
  person's chats (`GET /api/v1/chat`, `listChatConversations`, `chat_list`, `chat list`),
  reads one 50 messages a page (`POST /api/v1/chat/{conversation}/history`,
  `listChatMessages`, `chat_read`, `chat read`) and sends a message in one or in a new chat
  (`POST /api/v1/chat/messages`, `sendChatMessage`, `chat_send`, `chat send`). The commands
  arrive in the next regents-cli release. The send runs the page's own Ash action
  (`AshTemplate.Chat.create_message`), so the person's allowance of 10 a minute, the
  assistant's streamed reply (the `:respond` trigger, now carrying an agent actor through
  `AshTemplate.Chat.ActorPersister`) and the person's open chat page all work as when they
  type it. Its `operation_id` becomes the message's id, so a retry answers the first
  message with 200 (`:earlier_send`). Another person's chat answers 404 `chat_not_found`,
  like one that does not exist. The message shows as the person's own: the chat is theirs
  alone. The OpenAPI documents move to 7.3.0.
- An agent unpaired after sending, before the assistant answers, may no longer read or
  answer its message, so its reply job gives up; the job reads its message with
  `:job_read` and ends the reply with `:fail_response`, both open to AshOban alone
  (`AshOban.Checks.AshObanInteraction`), and the reply is read and written as the assistant.
  The person's chat shows the failed reply instead of "The assistant is writing…" for good.
- `operation_id` is a private argument of `Chat.Message.create`, set only by the agent
  route, so the chat page cannot choose its messages' ids.
- `prepare_agent_request` now offers every signed browser tool. It had missed the room
  likes and reports, direct messages and polls; the list is now checked against the
  manifest when `AshTemplateWeb.Capabilities` compiles.
- An API refusal or form error from a rule that carries a value that is not text, such as
  the pattern behind "cannot be empty", no longer crashes while it is worded
  (`AshTemplateWeb.FormErrors`): only the values its words name are filled in.
- The compile-connected limit in `platform/mix.exs` moves to 36: `AshTemplateWeb.ChatController`
  is one more signed-agent controller reading AgentWallet's refusals at compile time.
- `cli/COMMANDS.md` leads each command with **Does:** in place of **What:**, under the rule
  that no bold lead opens with a W-word.

## 2026-10-28 — Agent access: AshAi tools, capability fields and operation keys

- AshAi moves to 1.4.1 (`~> 1.4.1`), which brings ash_json_api 1.8.0, websock_adapter
  0.7.0 and llm_db 2026.10.7. The chat assistant now names its own two
  tools, so it never reaches another domain's.
- The Rooms domain hands AshAi two tools, `rooms_messages` and `rooms_post`. They run
  `Message.room_messages` and `Message.agent_post`, the same actions `GET` and
  `POST /api/v1/rooms/{room}/messages` now call, so the browser tool, the command, the
  route and hosted MCP answer alike. The `/mcp` route is not mounted yet.
- `priv/capabilities.json` gains `contract_revision` and, per operation, `surfaces`
  (with a reason for each surface left out), `auth_modes`, `fresh_proof`, `actor`,
  `context`, `retry` and `lifecycle`; `/capabilities.json` adds each operation's
  `output_schema` from `/openapi.json`. The build stops on a hosted tool with no AshAi
  tool, an AshAi tool named like a browser tool but not hosted, hosted input that
  differs from the browser tool's, a public operation that needs proof, an
  operation-key retry with no `operation_id` field, or a surface left out with no
  reason. The agent guide's operations table gains Surfaces and Proof columns, and its
  heading is now "Agent operations".
- An agent's room post spends its `operation_id` once in the new `agent_operations`
  table, in the same transaction as the post. The message's id is no longer the key.
  The same key with another room or other text answers 409 `idempotency_conflict`, and
  after its message was deleted 410 `message_removed` with that message's `id`; two
  calls with one key at once post one message. `read :earlier_post` is gone. The
  OpenAPI documents move to 8.0.0. The migration
  `20261028154117_agent_operations` needs Sean's letter naming the release before it
  runs in production.
- The compile-connected limit in `mix precommit` moves from 35 to 39: the new resource,
  the two actions' modules, and the capability check naming the chat domain whose tools
  are never hosted.
- Review fixes: the key's fingerprint is taken from the text as the message stores it
  (blank lines squashed), so a retry with the text the first answer gave back replays
  instead of answering 409; the property test now always sends text with blank lines,
  and fails on the earlier fingerprint. `agent_post` takes the client address from
  every caller's context, never optionally. The build now stops unless `hosted_mcp`
  is marked on exactly the operations whose browser tool is an AshAi tool, both ways;
  the chat assistant's own tools are never hosted. `interfaces.hosted_mcp` names the
  hosted tool. The agent guide's "Who may" column is now "Allowed", and the three
  profile rows say "Not for agents yet." where they said only the person does this.
- This change releases together with the `/mcp` mount (agent access work item 5),
  never before it: until then two operations would be marked hosted on a route that
  is not there.

## 2026-10-28 — Claude connector, behind one switch (side branch, not released)

- The elixir-utils packages are pinned to `aa5512f4` (branch `claude/mcp-self-calls-1028`:
  main `9da44bdc` merged with the connector's oauth and mcp_agents work).
  `regent_mcp_agents` joins as a dependency: `RegentMCPAgents.Plug` answers at `/mcp`
  with Claude's handshake, the 401 sign-in challenge, each connected account's own budget
  and the identity tools. `regent_oauth` and `regent_agent_access` carry `override: true`,
  since `regent_mcp_agents` names them by sibling paths. No new Hex package.
- One switch, `ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED`, off unless `true`, turns on the
  sign-in under `/oauth` and `/.well-known/oauth-*`, `/mcp`, Claude in the pairing box
  and the pair request, and the Claude guide at `/agents/claude`. With the switch on, the
  boot stops unless `SIWA_HOSTED_SIGNING_KEY` is well formed. With it off, an agent's
  sign-in, pairing and rate limits are as before: the endpoint only adds a budget for
  `/mcp` paths (600 a minute from one address) and the `/api` budget is unchanged.
- The connector's sign-in signs, through the sign-in service, only `whoami`, `me` and
  `pair` for the account's one hosted identity, asked with the site's own key; the
  connection's Bearer token never leaves the site. Connecting again or refreshing keeps
  that identity and its one agent, a pairing code must be the authorizing account's own,
  only `check_in` moves when the agent was last in touch, unpairing on the Account page
  holds, and disconnecting at Connected apps revokes the app's access and refresh tokens
  at once. `platform/test/ash_template_web/claude_connector_test.exs` checks each through
  this site's endpoint; `docs/feature-map.md` lists them and the gaps left.
- Pairing and checking in when asked in a chat are supported. A check-in from a scheduled
  Claude task has not been tried, and Claude's guide says so.
- Claude's guide and the connector's refusal send people to Pair New Agent on their
  Account page. The pairing box uses the library's `Harness.offered/0`; its own copy is
  gone.
- Migrations: `20261014170000_add_oauth_provider` now calls `RegentOAuth.Migration.up()`
  (the shape a new database gets; production already ran it).
  `20261028120000_oauth_connector_tokens` (up only, `SET LOCAL lock_timeout = '5s'`) runs
  `RegentOAuth.Migration.V2`: it drops the token table's issuer and resource defaults
  (each code and token now has them written as it is issued) and rewrites every stored
  access token row in place as hashes. The template has OAuth rows on the shared
  production database, so the release that carries it waits for Sean's letter naming it.
  Tokens issued for the old resource stay refused and their apps connect again.
- Lifetimes stay the library's: a Bearer token lives at most an hour, a refresh token 30
  days, and a refresh token reused within 30 seconds of its rotation is only refused
  (`config/config.exs` notes where each is set).
- Not yet: the sign-in service's hosted signing allows the `patchbay` and `keyfleet`
  audiences only, so with the switch on here every signed tool call would be refused
  until siwa-server allows `ash-template`. Shared change: Sean signs off the template's
  version before any site takes it.

## 2026-10-28 — Hosted MCP on AshAi

- `/mcp` is now the site's hosted MCP server, `forward "/mcp", AshAi.Mcp.Router`, serving
  exactly the tools `platform/priv/capabilities.json` marks hosted: `rooms_messages` and
  `rooms_post`, the same Ash actions, inputs, answers and refusals as the browser tools and
  the CLI, and the Claude connector's four identity tools.
- `AshTemplateWeb.Plugs.McpAgent` says who is calling (agent access spec 4.3): an agent's
  signature is checked by `AgentWallet` unchanged and the agent is the actor; the
  connector's Bearer token makes the connected app the actor, under its account's budget,
  and runs only the identity tools; both together get 401 `ambiguous_credentials`; neither
  may list the tools and read a room, and a call to a tool that needs a sign-in gets 401
  `agent_auth_required`. Every call carries the client's address key; answers are
  `cache-control: private, no-store`; a page from another site is refused.
- The identity tools are Ash actions on `AshTemplate.Agents.Connection`, over the
  library's `RegentMCPAgents` functions; the template no longer mounts
  `RegentMCPAgents.Plug`. A connected app can no longer read a room.
- Refusals are the tool's error, whose text is the HTTP refusal's JSON
  (`AshTemplateWeb.ToolErrors`). `[:ash_template, :mcp, :auth]` counts requests by how
  they came in and whether they were taken.
- The capabilities check allows a hosted-only operation, named after its tool, with its
  answer among the OpenAPI components (`ConnectedIdentity`, `ConnectedIdentityStatus`,
  `ConnectedIdentityPairing`, `ConnectedIdentityCheckIn`), and the `connected_app`
  authority with the `site_oauth` proof.
- While the connector switch is off, `/mcp` serves the room tools and refuses a Bearer
  token with 401 `delegated_access_not_enabled`, where it answered 404 before.

## 2026-10-28 — Hosted MCP review fixes

- Every `/mcp` request carries an agent's signature or a connected app's token; there is
  no anonymous MCP. With the Claude connector switch on, a request with neither gets 401
  `connection_required` with the `WWW-Authenticate` challenge, so Claude's first request
  starts its sign-in; with it off, 401 `agent_auth_required`. Reading a room without
  signing in is the HTTP API and the browser tools, which replace the spec's anonymous
  `/mcp` read (C02).
- `AshTemplateWeb.Plugs.McpAgent` refuses, before any credential is read and in the
  site's `{"error": {"code", "message", "hint"}}` shape: a query string (400
  `unsupported_query`), any address but `/mcp` (404) and any method but POST (405), a
  page on another site, `null` included (403 `origin_not_allowed`; no `Origin` goes on),
  a body that is not JSON (415) and a JSON-RPC batch (400 `batch_not_supported`), so one
  signature covers one call. The `:mcp` pipeline takes JSON only again. A signature is
  told apart with `Siwa.AgentAuthPlug.signed_request?/1`.
- A tool's input is checked against its action before it runs
  (`AshTemplateWeb.ToolErrors.check_input/3`, AshAi's `tool_argument_transformer`), so a
  bad input gets the HTTP route's code and words: `invalid_limit`, `invalid_author_kind`,
  `invalid_message`, `room_not_found`, and `identity_request_refused` for the identity
  tools. `RoomsController.page_refusal/1` is shared with it.
- `pair_identity` lists the harness the library takes (`claude`) and limits the name to
  100 characters and the code to 128.
- `/mcp` takes 120 requests a minute from one address, the API's figure, where it took
  600. A body over the limit and a form body point to the guide's Hosted MCP section.
- The router's MCP instructions are written in place, so it no longer depends on McpAgent
  at compile time; the compile-connected limit is 41 (the tools list and the input check).
  `Capabilities.sign_in_needed?/1` and `proof_headers/0`, and the context keys nothing
  read, are gone.

## 2026-10-28 — Hosted MCP: identity tools as listed, room read input, connector budget

- A tool listed with no inputs (`register_identity`, `get_identity`, `check_in`) runs
  when called as its schema says, with empty `arguments` or none: the input check reads
  a missing `input` as AshAi does. Before this, Claude's first call was refused.
- `rooms_messages` answers `invalid_input` for input that is not an object or names
  something the read does not take, where it answered `invalid_cursor`. A bad `after`
  still answers `invalid_cursor`.
- `/mcp` requests with a Bearer token share 600 a minute per address
  (`mcp_connected_address`), since Claude's connector calls from Anthropic's shared
  servers; other requests keep 120 a minute per address. Each connected account keeps
  its own 120 a minute.
- The batch test sends a JSON array, as clients do.

## 2026-10-28 — Signed browser tools take only their input

- elixir-utils moves to `5d6ccf6`: a signed browser tool now builds its request, asks
  the browser host's `window.regentsSign` to sign it, and sends exactly those bytes
  with the proof and no cookie. With no signer it sends nothing and answers
  `agent_auth_required`, naming `regents browser --site`; a signer's refusal is the
  tool's answer.
- Hard cutover in `platform/priv/tool_manifest.json`: each signed tool's
  `input_schema` is its own input (the former `operation_input_schema`, now gone), and
  `prepare_agent_request` is removed. `Capabilities` reads `input_schema`.
- `platform/assets/js/public_tools.ts` answers a refusal in the site's error shape, and
  explains a signer's incomplete answer.
- The public guide and the supported-host page say a signed tool takes only its input
  and the browser host signs it; the supported-host heading is now "Agent setups".
- `platform/test/browser/page_tools.spec.ts` proves the four cases at both widths.

## 2026-10-28 — Signed browser tools: review fixes

- elixir-utils moves to `6d0d40e`: a signer that fails (its browser host went away)
  answers `signer_unavailable`, and a call cancelled while the signer works answers
  `cancelled`; neither sends anything, so neither is reported as an unknown outcome.
- `public_tools.ts` names the site's own faults (`invalid_operation`, `invalid_path`,
  `invalid_request_header`, `unsupported_field_type`) as the site's, with their own
  hint, and explains a read sent a body, a bad raw body, and `.` or `..` as a name.
- `/agents.md` gains a Browser tools section on `regents browser`, which `/docs` links
  to; `/docs` lists the signed-tool change under Breaking changes, and the public
  changelog says it in plain words.
- The page tools walk no longer checks for the removed tool or the removed input
  shape; an unknown field (`colour`) proves an input is refused before signing.
- Released only with the regents-cli release that carries `regents browser`.

## 2026-10-29 — Hosted MCP: every read

- Fifteen reads are now hosted agent tools at `/mcp`, each one Ash action that its HTTP
  route, browser tool and regents-cli command also call: `health`, `about`, `docs`,
  `sites_tools` and `siwa_help` (the new `AshTemplate.Site` domain), `rooms_list`,
  `rooms_message`, `rooms_search` and `mutes_list`, `agents_get` and `agents_profile`,
  `account_balances`, `account_credits_history` and `account_points` (the new
  `AshTemplate.Accounts.Holdings`), and `activity_list`.
- A tool's refusal has the code, message and hint the same request gets over HTTP,
  read from the answering controller's table (`ToolErrors.text/3`); not-paired
  answers come from `AshTemplate.Agents.NotPaired` for every door. Input a read cannot
  take is refused before it runs with the HTTP code (`invalid_cursor`,
  `invalid_activity_request`, `invalid_search`, `agent_not_found`, `site_not_found`,
  `room_not_found`, `public_message_not_found`), and input to a tool that takes none
  answers `invalid_request`.
- The points answer moves from `AshTemplateWeb.PointsEntries` to
  `AshTemplate.Points.Entries`, so the action owns it; a page cursor's refusal is read
  by `AshTemplate.PageCursor`.
- `capabilities.json` marks the fifteen as hosted; the `/mcp` instructions say the
  tools share the browser tools' and regents-cli's names, input and answers.
- `mcp_agent_test.exs` proves each read answers through `/mcp` exactly as over HTTP,
  and each refusal with the same code and words.
- `docs/feature-map.md` and `docs/agent-parity.md` fill the MCP column for these
  reads. Gaps kept: `sites_tools` success is not compared (it reads the other site
  live), `getAgentIdentity` is not hosted yet, and the three Privy-session profile rows
  stay off `/mcp`.

## 2026-10-29 — Hosted MCP: notes

- Every notes tool but the pin is now a hosted agent tool at `/mcp`, each one Ash action
  its HTTP route and browser tool also call: `notes_list`, `notes_get`, `notes_search`,
  `notes_create`, `notes_edit`, `notes_delete`, `notes_pin_price`, `notes_unpin`,
  `notes_archive` and `notes_unarchive` on `AshTemplate.Notes.Note`, and
  `notes_rate_label` on `AshTemplate.Notes.Decision`. `Note.present/1` replaces
  `NotesJSON`, and the controllers shrink to one action call each.
- An agent's new note (`Note.AgentCreate`) spends its `operation_id` in
  `agent_operations` (capability `note_create`, fingerprint title and text) in the same
  transaction as the note, as a room post does; the key still becomes the note's id.
  A retry with the same title and text answers the note (HTTP 200, `replayed: true`),
  other text answers 409 `idempotency_conflict`, and a retry after a delete answers 410
  `note_removed` naming it. `Notes.earlier_note` and the create action's
  `operation_id` argument are gone; a person's new note sends none. The shared
  `Operation.key_spent?/1` replaces the room post's own copy.
- `AshTemplate.Notes.Refused` carries each refusal's code; its words live in
  `NotesController`, which now also owns `note_not_found`, `label_not_found` and
  `invalid_label_report` for the paired-agent routes, with one `note_not_found`
  wording. `NotPaired.check/1` answers `:ok` for a person.
- Both OpenAPI documents add the 409 and 410 answers and move to 9.0.0; `/docs` lists
  the change under Breaking changes, the agent guide and skill name `note_removed`, and
  the public changelog says it in plain words.
- From the review: an edit that sends neither title nor body is refused as
  `invalid_note` in `notes_edit` itself (`Note.SendsAChange`, which reads the keys
  sent, so a body sent empty still clears the text), so it never saves the note, asks
  for a label or counts a write; a key that is already another note's id
  (another agent's, or another person's) answers 409 `idempotency_conflict` with no
  details instead of 422 `invalid_note` naming the id; and a write by an agent whose
  pairing ended after its request was let in answers `agent_not_paired` on every
  surface (`NotPaired.ended/2`, for an agent only) instead of 503 over HTTP. The
  address names the note or label: an `id` in the body of `PATCH /api/v1/notes/{id}`
  or of a label's report is not read, where it had chosen the note the action changed.
  A tool input a validation refuses is gathered into its error class
  (`ToolErrors.check_input/3`), so `/mcp` gives the same `details` as HTTP.
- `mcp_agent_test.exs` proves each notes tool answers and refuses through `/mcp` as
  over HTTP, that a reused key answers the same both ways, the three review fixes, a
  text cleared both ways and a body `id` that chooses nothing; each of their checks
  fails on the code before them. `mix xref`'s
  compile-connected limit moves to 45 for the action module the create runs.
- Not changed: `notes_pin` (spends Credits) waits for Sean's letter. A note an agent
  made before this change has no `agent_operations` row, so retrying its old
  `operation_id` is refused as `idempotency_conflict` (the id is taken) instead of
  answering the note.

## 2026-10-29 — Hosted MCP: rooms and mutes

- Every rooms and mutes change is now a hosted agent tool at `/mcp`, each one Ash action
  its HTTP route and browser tool also call: `rooms_create` and `rooms_topic` on
  `AshTemplate.Rooms.Room`, `rooms_edit`, `rooms_delete`, `rooms_like`, `rooms_unlike`
  and `rooms_report` on `AshTemplate.Rooms.Message`, and `mutes_add` and `mutes_remove`
  on `AshTemplate.Rooms.Mute`. The controllers shrink to one action call each, and the
  mutes routes answer through `RoomsController.respond/3`.
- A room an agent starts (`Room.AgentStart`) answers a retry with the name of a room
  its person already started as that room (HTTP 200, `replayed: true`), as before, and
  now also when two calls with one name run at once. The room's name is its retry key,
  so it declares no `operation_id`; the earlier-room read moves from the controller
  into the action.
- `RoomsController` keeps every rooms word, the mutes' included, and maps each action's
  refusal in one place (`input_refusal/2`, `answer/1`), so `/mcp` and HTTP give the same
  code, status, words and `details`. `ToolErrors` reads it for every rooms tool.
- Over HTTP the address alone names the record: a `room` or `id` in the body of a
  topic, an edit or a report is not read, since the code interface's arguments would
  let it choose the room or message the action changed. A field a route does not take
  is refused with that route's code (`invalid_room`, `invalid_message`,
  `invalid_report`, `invalid_mute`), as the API contract already said, where it had
  been ignored.
- An unexpected failure on `POST /api/v1/mutes` or `DELETE /api/v1/mutes/{id}` answers
  503 `rooms_unavailable`, the rooms' word, instead of 503 `unavailable`.
- `mcp_agent_test.exs` proves each rooms and mutes tool answers and refuses through
  `/mcp` as over HTTP (twenty refusals, each with its status and code), and one body
  check per route; the topic, edit and report checks each fail when the body is read
  again, and a removal refuses any body before it runs.
- A report's reason is its own enum type (`AshTemplate.Rooms.Report.Reason`), which the
  report and `rooms_report` both take, so the message no longer reads the report
  resource at compile time; `Report.reasons/0` is gone. `mix xref`'s compile-connected
  limit moves to 46 for the action module a room start runs.
- Not proven by a check: two starts of one room at once (the race needs two
  transactions to meet).

## 2026-10-29 — Hosted MCP: room retries and mute removals

- A room's name sent again answers the room only when its topic matches too
  (`Room.AgentStart`). The same name with another topic, or another spelling of the
  name, is 409 `room_name_taken` and changes nothing; before, it answered the room as a
  retry and left the agent thinking its topic was saved. The same rule holds when two
  starts run at once.
- A mute removed by two calls at once answers the second with 404 `mute_not_found`
  (`Mute.lift/2`). A refused removal now reads the mute again: gone means another call
  removed it; still there means the agent's pairing, rechecked inside the transaction,
  ended (403 `agent_not_paired`). Before, every refused removal said `agent_not_paired`.
- `mcp_agent_test.exs` checks both ways that another topic under a name is refused and
  the room keeps its topic, twenty races of two starts of one room (one room, both
  answer it), and nine races of two removals of one mute (one `removed: true`, one
  `mute_not_found`). The topic and removal checks fail on the earlier code; the race
  check fails when the start that finds the name taken refuses instead of answering.
- The tool descriptions, `/docs`, the API contract, the CLI's command list, the public
  changelog and the feature map say a retry is the same name and topic.

## 2026-10-29 — Hosted MCP: direct messages

- `/mcp` serves the seven direct-messages tools (`dms_list`, `dms_blocked`, `dms_open`,
  `dms_read`, `dms_send`, `dms_block`, `dms_unblock`). Each is a generic action on
  `Conversation` or `Message` that `DmsController`, WebMCP and the AshAi tool all call, so
  every surface gives the same answer, code, status, words and `details`. `DmsController`
  keeps the words and maps each refusal in one place (`input_refusal/2`, `answer/1`);
  `ToolErrors` reads it for every DMs tool, and `AshTemplate.Dms.Refused` names a refusal.
- An agent's send spends its `operation_id` in `agent_operations` (`Message.AgentSend`, the
  `dm_send` capability) in the same transaction as the message, which still takes the key as
  its id. A retry answers the first message only in the same conversation with the same
  words; another conversation or other words, or a key that is already another message's
  id, is 409 `idempotency_conflict`, where it had answered the first message (or 422
  `invalid_message`). The `:earlier_send` read and the `operation_id` argument on `:send` are
  gone.
- Over HTTP the address alone names the conversation: a `conversation` in a send's body is
  not read, and a block or unblock reads no body. A field a send, an open or a page does not
  take is refused (`invalid_message`, `invalid_open`, `invalid_cursor`), where it had been
  ignored.
- `mcp_agent_test.exs` proves each tool answers and refuses through `/mcp` as over HTTP
  (eighteen refusals, each with its status and code), the key rule across both surfaces,
  twelve races of two sends with one key (one message, both answer it), and that a call
  after the pairing ended changes nothing. Five planted faults (the body or the conversation
  left out of the key's check, the taken-id branch removed, the race answered as a
  conflict, the body choosing the conversation) each fail a check.
- `mix xref`'s compile-connected limit moves to 47 for the action module a send runs.

## 2026-10-29 — Hosted MCP: chat

- `/mcp` serves the three chat tools (`chat_list`, `chat_read`, `chat_send`). Each is a
  generic action on `Conversation` or `Message` that `ChatController`, WebMCP and the AshAi
  tool all call, so every surface gives the same answer, code, status, words and `details`.
  `ChatController` keeps the words and maps each refusal in one place (`input_refusal/2`,
  `answer/1`); `ToolErrors` reads it for every chat tool, and `AshTemplate.Chat.Refused`
  names a refusal.
- The assistant's own tools (`chat_list_conversations`, `chat_message_history`) stay its
  own: `AshTemplate.Chat.assistant_tools/0` names them for the reply and for the capability
  check, which no longer leaves the whole Chat domain off `/mcp`.
- An agent's send spends its `operation_id` in `agent_operations` (`Message.AgentSend`, the
  `chat_send` capability) in the same transaction as the message, which still takes the key
  as its id. A retry answers the first message only with the same text and
  `conversation_id` (a new chat's retry included); other text or another chat, or a key that
  is already another message's id, is 409 `idempotency_conflict`, where it had answered the
  first message (or 422 `invalid_message`). The `:earlier_send` read, `get_earlier_message`
  and the `operation_id` argument on `:create` are gone.
- Over HTTP a field a send does not take is refused (`invalid_message`), where it had been
  ignored, and a `conversation` in a page's body is not read: the address names the chat.
- `mcp_agent_test.exs` proves each tool answers and refuses through `/mcp` as over HTTP
  (fourteen refusals, each with its status and code), the key rule across both surfaces,
  twelve races of two new-chat sends with one key (one chat, one message, both answer it),
  and that a call after the pairing ended saves nothing. Five planted faults (the text or
  the chat left out of the key's check, the taken-id branch removed, the race answered as a
  conflict, the body choosing the chat) each fail a check.
- `mix xref`'s compile-connected limit moves to 48 for the action module a send runs.

## 2026-10-29 — Hosted MCP: polls

- `/mcp` serves the five polls tools (`polls_list`, `polls_show`, `polls_start`,
  `polls_vote`, `polls_end`). Each is a generic action on `Poll` or `Vote` that
  `PollsController`, WebMCP and the AshAi tool all call, so every surface gives the same
  answer, code, status, words and `details`. `PollsController` keeps the words and maps each
  refusal in one place (`input_refusal/2`, `answer/1`); `ToolErrors` reads it for every
  polls tool, and `AshTemplate.Polls.Refused` names a refusal.
- An agent's start spends its `operation_id` in `agent_operations` (`Poll.AgentStart`, the
  `poll_start` capability) in the same transaction as the poll, which still takes the key as
  its id. A retry answers the first poll only with the same question, choices and minutes;
  any of them changed, or a key that is already another poll's id, is 409
  `idempotency_conflict`, where it had answered the first poll (or 422 `invalid_poll`). The
  `:started_by_actor` read, `get_started_poll` and the `operation_id` argument on `:start`
  are gone.
- Over HTTP a field a start or vote does not take is refused (`invalid_poll`,
  `invalid_vote`), where it had been ignored; a `poll` in a vote's body is not read and an
  end reads no body: the address names the poll.
- `mcp_agent_test.exs` proves each tool answers and refuses through `/mcp` as over HTTP
  (twenty-two refusals, each with its status and code), the key rule across both surfaces,
  twelve races of two starts with one key (one poll, both answer it), and that a call after
  the pairing ended changes nothing. Five planted faults (the minutes left out of the key's
  check, the taken-id branch removed, the race answered as a conflict, the body choosing the
  poll, the starter check removed) each fail a check.
- `mix xref`'s compile-connected limit moves to 49 for the action module a start runs.

## 2026-10-29 — Hosted MCP: the agent's own profile and marking activity read

- `/mcp` serves `agents_edit_profile` and `activity_mark_read`, each a generic action
  (`Agent.agents_edit_profile`, `Notification.activity_mark_read`) that its HTTP route,
  WebMCP and the AshAi tool all call. `AgentsController` keeps the profile words and maps
  each refusal once (`input_refusal/1`, `answer/1`); `AshTemplate.Agents.Refused` carries the
  refused save for `invalid_profile`.
- `PATCH /api/v1/agents/me` refuses a field it does not take (`invalid_profile` with
  `details`), where it had been ignored. `POST /api/v1/activity/read` still refuses any body
  but `{}`; a body that is not an object, which Phoenix hands on as `_json` and Ash skips, is
  refused by the route before the action.
- Marking read checks the agent's pairing again in the change itself
  (`RegentAgents.Checks.Paired` on `:mark_read`), as every other agent write does, so a
  request let in before its person unpaired the agent marks nothing and answers
  `agent_not_paired`.
- The check-in (`GET /api/agents/v1/me`) and whoami stay off `/mcp`: they are
  `RegentAgents.HTTP`'s routes, and hosting them needs the library to offer each as a
  function. The note pin waits for Sean's letter.
- Chat conversations and messages lose the unused `:destroy` action, so a chat and its
  messages are never deleted, as `Message.AgentSend` relies on.
- `mix xref`'s comment names each generic action's module that adds a compile-connected
  file; the limit stays 49.
- `mcp_agent_test.exs` proves both tools answer and refuse through `/mcp` as over HTTP
  (eight refusals, with their `details`), and that marking read after the pairing ended
  marks nothing. Five planted faults (the non-object body let through, the pairing check
  removed, an empty change saved, the mark-read input refusal dropped, the profile
  `details` dropped) each fail a check.

## 2026-10-29 — Five agent surfaces, and agents own accounts by their wallet

- Sean, 29 Oct 05:30Z, answered the agent-parity rule: every action needs all five
  surfaces (the website, WebMCP, hosted MCP, the Claude connector and the regents CLI),
  each built in ash-template first, and an agent owns its account through its own wallet
  (its SIWA wallet is the Privy login wallet; the site makes the account from its signed
  request). `skills/regent-workflow/SKILL.md` and `skills/ash-webmcp/SKILL.md` say so.
- `docs/agent-parity.md` gains a Connector column. The connector's identity tools move
  there from the MCP column, and two rows with a missing surface but no gap now name G5.

## 2026-10-29 — Released v131

- template.regents.sh v131 runs `65c6e26c`, released 05:53Z: refusals that say an agent is
  not paired or its person is not here link to their help page, the Credits balance moves
  into the account menu on the narrowest phones, and a paired agent chats with the site's
  assistant for its person. Checks on that tree: `make check` exit 0 (100 server tests,
  24 script tests, the browser walk at 1280 and 390 in headless Chromium; WebKit is not
  run on the Mac). Live check 05:56Z in headless Chromium: `/capabilities.json`
  build.commit `65c6e26c`; home, agents, account, rooms and pair pages answer 200 at 390
  and 1280 with the sign-in settings present, no page errors and nothing wider than the
  screen. The machine's health check passes; the boot log shows no crash. `bab38804`
  (docs and skills only) is on main and rides the next release. Rollback: v130,
  `cc74b3f3`.

## 2026-10-29 — Signed-tools tests start with their own request budget

- Every test request comes from 127.0.0.1, so the whole server suite shared one /api
  budget of 120 a minute, and a late signed-tools test was now and then refused with
  429 (seen once in four runs on the connector merge). `signed_tools_test.exs`, the
  file that sends most of the suite's /api requests, clears the limiter's counters in
  its setup. The limit itself is unchanged. Test-only; nothing to release.

## 2026-10-29 — WebMCP trial runs to Chrome 162

- `skills/ash-webmcp/references/build.md` says Chrome's WebMCP origin trial runs Chrome
  149–162, as Chrome's trial registration page now says (reported by the Autolaunch
  release lead, 29 Oct; Autolaunch's token expires 29 Mar 2027). Docs only.

## 2026-10-29 — Sign out closes the account menu

- Sign out closes the account menu, so when the site can't be reached the note "Sign out couldn’t finish. Try again." shows under the account button with nothing over it. Before, the open menu covered it. Found by regents.sh's walk.
- The account menu walk aborts the sign-out request, presses Sign out and checks the menu is closed and the note is on top; it fails on the old code.

## 2026-10-29 — Public browser tools answer as their HTTP reads (WM-1 to WM-3)

- Each public browser tool builds its address from its manifest `route`, so the
  page's own path table is gone. Its input goes in the address: the named parts in
  the path, the rest as the query.
- The server is the one checker. A public read over HTTP takes just its hosted MCP
  tool's input (`AshTemplateWeb.Plugs.ToolInput` on the new `:public_read` pipeline,
  each route naming its tool), so a query field it does not take is refused with the
  status, code and words that tool gives (`ToolErrors.http_refusal/2`), instead of
  ignored. The page refuses only input it cannot put in an address, with refusals
  `priv/tool_manifest.json` carries from `ToolErrors`, which a server test pins.
- A browser tool's result is the HTTP body and its refusal `{"error": …}`, with
  `retry_after` and `outcome_unknown` inside `error`; `ok`, `status`, `data` and
  `outcome` are gone (hard cutover). `/docs` "Browser tools", "Hosted MCP" and a
  breaking change say so; OpenAPI 10.0.0 lists the new 422 answers.
- The build fails on a public browser tool that is not a GET read with a refusal
  for each input it cannot send (`AshTemplateWeb.Capabilities`).
- Checks: `page_tools.spec.ts` calls every public tool once against HTTP, hands on
  refusals and the wait, at 1280 and 390; `mcp_agent_test.exs` matches HTTP and
  `/mcp` refusals for every public read.

## 2026-10-29 — One description per operation (WM-4)

- Each operation's words are written once, as `description` on its row in
  `platform/priv/capabilities.json`. Every surface takes them from there with the
  same few words added (who may run it, whether it changes anything, and on a browser
  tool how it is signed): the browser tool in `priv/tool_manifest.json`, the command
  in `cli/commands.json`, the operation in `priv/public/openapi.json` and the hosted
  MCP tool, whose domain `tools` blocks call `AshTemplate.Descriptions.hosted/1`.
  A connected app's identity tools keep the shared library's words.
- `mix ash_template.sync_descriptions` writes the three files; `--check`, in
  `mix precommit`, fails while any of them has other words. Command descriptions no
  longer repeat the stdin hint, which the CLI's help adds itself.
- The build fails on a browser tool whose input fields differ from its OpenAPI
  operation's (path, query and body together), on a hosted tool with words of its
  own, and on a missing or extra `description` row (`AshTemplateWeb.Capabilities`).

## 2026-10-29 — Room search by name on every surface (WM-5)

- `rooms_list` takes `text`, and with it runs the same read as the page's search box
  (`Rooms.search_rooms`): up to 5 rooms whose name holds it, in any case. It reaches
  `GET /api/v1/rooms?text=`, the browser tool, the hosted MCP tool (and so the Claude
  connector, which shares `/mcp`) and `rooms list --text`. Text that is not 2 to 100
  characters, or another query field, is refused as `invalid_search` everywhere, in
  the room search's words; the read no longer answers `invalid_request`.
- `docs/agent-parity.md` corrected: pinning a note is for agents only (a person has no
  Pin button, and none is added), room search by name has its row, and the Credits
  admin reads join the G8 row.
