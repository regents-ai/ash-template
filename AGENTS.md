# Ash Template

<!-- template-only -->
This monorepo is a product template. Keep the placeholder names (`ash_template`,
`AshTemplate`, `ashTemplate`, `ash-template`, `ASH_TEMPLATE_`, "Ash Template",
"ASH TEMPLATE") and the address `template.regents.sh` exactly as they are;
`scripts/init.sh` renames them and writes the new site's address for a real
product. Outside `skills/`, the dated plans and the changelog it rewrites every one
of them, so where a sentence means the template itself, write
regents-ai/ash-template, which it keeps, and name the template's address in
other words. The template's own homepage tracks regents.sh's, and
`scripts/drift.sh` reports when the two differ. "New site" below lists what a new
site still replaces by hand; keep it outside this passage, which the rename drops.
<!-- /template-only -->

- `platform/`: Phoenix/Ash application. Read its instructions for web changes.
- `cli/`: `COMMANDS.md` and `commands.json`, the description of every
  `regents ash-template` command; the code lives in `regents-cli`. Docs first in
  `COMMANDS.md`, then the route, its OpenAPI operation and `commands.json` in one
  commit, then `make check-cli`, then the change note to the regents-cli chief
  (`cli/README.md`).
- `contracts/`: optional Foundry workspace, empty until contracts are needed.
- `plugins/`: home for standalone runtime plugin packages; none exist yet.
- `skills/`: every shared skill Regent writes, as regents-ai/ash-template keeps
  them (each product's own agent skill lives in that product's repository); the
  Regent workspace's `.agents/skills` and `.claude/skills` link to that
  repository's. `regent-workflow` is the entry point
  for Regent work; `regent-notion` covers the Notion data room and `checkpoint`
  a local handoff. For code, load `regent-workflow`, `ash-stack` and
  `elixir-stack` first: `elixir-stack` names the standard Elixir, Phoenix, Ecto
  and Oban tool for each job and runs the design check, and `ash-stack` routes to
  `ash-backend`, `ash-frontend`, `ash-data`, `ash-security`, `ash-testing` and
  `ash-webmcp` (agent readiness and WebMCP tools), and `ash-signals` covers
  one resource reacting to another's action. `animejs` covers Anime.js in
  LiveView hooks, `vgpu-island` every GPU picture (vgpu inside the shared canvas island), `onchain-buttons` wallet and on-chain buttons, and
  `chain-events` watching a chain and saving its events; load `ash-stack` and
  `ash-frontend` before each. Change a shared skill in regents-ai/ash-template,
  never in a copy in another repository. The web app serves the `ash-*`, `animejs`,
  `onchain-buttons` and `chain-events` skills publicly as its build skills
  (`AshTemplateWeb.AgentSkills` names them), so a change to one is published
  with the app's next release.
- Motion: every Regent site shares the kit in `platform/assets/js/hooks/motion/`
  and `platform/assets/js/motion.ts`, with the standard version of each part in
  `AshTemplateWeb.Motion`. Pages join in through markup (`data-press-label` on
  wallet buttons, `data-panel`, `data-cascade`, `data-variant`, and every live
  figure drawn with `Regent.Primitives.figure` inside a part marked
  `phx-hook="MotionCount"`; the shared segmented control and tabs with
  `phx-hook="MotionTravel"`, the breadcrumb with `MotionCrumbs`, an agent's
  activity with `MotionActivity`, the line chart with `MotionChart` and the light and
  dark switch (`Shell.theme_toggle/1`) with `ThemeSwitch`;
  `data-sheet-handle` on the part a window is pulled down by, `data-dismiss` on
  the close control of a `data-panel="drawer"` or a `data-toast` a finger may
  swipe away, `hooks/motion/gestures.ts`), never with their own motion code.
  `/animations` is the lab where every version that was tried sits side by side;
  `skills/animejs/references/liveview-islands.md` explains it.
- There is no `identity/` folder. The shared profile domain comes from the
  `regents/identity` package. It and the `design-system` and `elixir-utils`
  libraries are git dependencies pinned to one commit each in `platform/mix.exs`.
- `security/required-fixes.json` lists every shared library (app, repository and
  folder), including Regent's own copy of ash_postgres, and the security fixes
  every Regent site must carry: a `git` fix is a commit the pin must contain, a
  `hex` fix is a version requirement the locked Hex version must meet
  (`>= 3.34.3`).
  regents-ai/ash-template keeps the list: add an entry there the day such a fix
  is published and push it to its `main`; every site's `make
  check-required-fixes` reads that `main` and fails until the site takes it. A
  new shared library is listed there before any site can use it.
- `make check` runs every gate: the design system's style check (`make check-style`),
  the platform's `mix precommit` (which ends with the
  TypeScript typecheck, the script tests and the browser walk) and `mix test`, the
  required-fixes check, then the command description check against the
  site's OpenAPI documents (regents-cli's checker at the commit the `Makefile` pins).
  `make check-style`, `check-platform`, `check-required-fixes`, `check-cli` and
  `check-contracts` run one component.
- `make release` is the one release path: it refuses uncommitted changes, runs
  `make check`, builds HEAD's `platform/` into an image and starts it against a
  throwaway database (`scripts/release.sh`). It never deploys.
- Follow the workspace's `regent-workflow`; use one integrating owner for this
  repository. Scope verification to observable acceptance and preserve useful
  regression coverage.
- Preserve uncommitted work and public command/API shapes. Every distinct wallet
  press reaches the wallet. No signing, production access, deployment or
  publishing without applicable founder authority. Never read `.env`,
  `.env.local` or `.envrc`.

The public agent entry point is served at `/llms.txt` from
[platform/priv/public/llms.md](platform/priv/public/llms.md); keep it
consistent with the routes in `platform/lib/ash_template_web/router.ex` and the
HTTP contract in `platform/contracts/api-contract.openapiv3.yaml`.

## New site

A site made from regents-ai/ash-template with `scripts/init.sh` has its own
names and address, and replaces these by hand:

1. The homepage's name, the line under it and its product tabs (`products/0`)
   in `platform/lib/ash_template_web/live/home_live.ex`. Also the share picture
   `platform/priv/static/images/og-image.png` (1200 x 630, the product's name
   and one line about it in the left 600 pixels, which is all X shows on a
   phone, and nothing in the bottom-left corner, where X writes the site's
   name); keep its file name. The logo files in `platform/priv/static` (`favicon.svg`,
   `favicon.ico`, `favicon-32.png`, `favicon-192.png`, `apple-touch-icon.png`,
   `mark.png`, `images/brand/mark-flat-dark.svg`,
   `images/brand/mark-flat-dark-clear.svg`, `images/brand/mark-flat-light.svg`)
   are the Regents crown. Keep them.
2. The homepage's theme, which is always dark for the template's artwork:
   `homeThemeLocked` in `platform/assets/js/theme.ts`, `home?` in
   `platform/lib/ash_template_web/components/layouts/root.html.heex` and the
   `data-home-theme-locked` rule in `platform/assets/css/pages/home.css`, which
   hides the theme switch there. Keep it for dark artwork; otherwise take the
   lock out of all three, with the theme test that expects it
   (`platform/assets/test/theme.test.ts`), and the homepage follows the
   visitor's light or dark choice like every other page.
3. The legal operator named in `platform/priv/legal/terms.md` and
   `privacy.md`.
4. The site's Patchbay page (`https://patchbay.help/<domain>`) in
   `platform/priv/public/about.md`. Every contact address stays
   `build@regents.sh`, as on every Regent site.
5. The X and GitHub links in
   `platform/lib/ash_template_web/components/regent_links.ex` and `twitter_site`
   in `platform/lib/ash_template_web/components/layouts/root.html.heex` point at
   the Regents accounts; keep them unless the product has its own.
6. The Fly app names: `app` in `platform/fly.staging.toml`, and the production
   app, which `platform/fly.toml` leaves to the deploy command. The deploy
   example in `platform/README.md` and the opening comment of
   `scripts/deploy.sh` name the template's own app, `template-regents-sh`.
7. The database cluster, hosts and refused identities in
   `platform/lib/ash_template/database_config.ex`.
8. The WebMCP origin trial token, `@webmcp_origin_trial` in
   `platform/lib/ash_template_web/endpoint.ex`. It is issued to the template's
   address and Chrome ignores it on any other host: register the site's own
   address for Chrome's WebMCP origin trial and put its token there, with its end
   date in the comment above it.
9. The compile-connected limit, `--fail-above 48` in the `precommit` alias in
   `platform/mix.exs`. `mix precommit` stops once more files are connected at
   compile time than it allows, and the comment above it says what adds one:
   each resource an Ash domain lists, each generic action's module, each
   signed-agent controller. Raise it in the commit that adds them, by the number
   of new files `mix xref graph --label compile-connected` lists, with a comment
   line naming them.
10. `mix format` and `mix ash_template.route_handoff`, run from `platform/` once
    the shared dependencies are fetched: names of another length rewrap lines,
    and the route catalog digest (`platform/priv/handoff/route-catalog.sha256`)
    includes the display name. `scripts/init.sh` prints both.
11. Outside this repository: elixir-utils' list of Regent sites
    (`RegentAgents.Activity` leaves an agent's days on the site out of its
    activity until the site is there; take the new pin), and the sign-in
    service's settings for the site's audience: its wallet sign-in address and,
    before the Claude connector goes on, its hosted signing key and the requests
    its connector may sign.

<!-- BEGIN REGENT ROLLOUT REVIEW -->
## Code Review Rules

### Human and agent guidance drift

For every code review, read `skills/rollout-guidance-check/SKILL.md` and assess the diff's guidance
impact, even when no prose files changed. Trace affected behavior into public docs,
product/developer Skills, human-to-agent prompts, tooltips and other UI copy,
WebMCP/MCP schemas and descriptions, CLI help/errors/examples, OpenAPI, manifests
and generated or bundled copies. Shared behavior starts in ash-template and its
libraries; inspect affected consumers when available.

Report concrete mismatches introduced or made relevant by this change, with the
failing user/agent action and exact source locations. Distinguish source, packaged,
published and deployed versions; name missing cross-repository or live evidence.
Preserve dated history and avoid cosmetic findings. Do not inflate severity or
claim that no findings proves complete coverage. This is read-only review: never
sign, pay, activate earnings, publish or deploy to test an instruction.
<!-- END REGENT ROLLOUT REVIEW -->
