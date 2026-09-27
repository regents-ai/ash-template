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
