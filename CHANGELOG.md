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

