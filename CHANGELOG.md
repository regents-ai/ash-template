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
