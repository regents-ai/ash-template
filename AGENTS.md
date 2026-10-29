# Ash Template

<!-- template-only -->
This monorepo is a product template. Keep the placeholder names (`ash_template`,
`AshTemplate`, `ashTemplate`, `ash-template`, `ASH_TEMPLATE_`, "Ash Template",
"ASH TEMPLATE") exactly as they are; `scripts/init.sh` renames them for a real
product.

After renaming, a new site must still replace, by hand:

1. The homepage's name, the line under it and the cube's six worlds
   (`worlds/0`) in `platform/lib/ash_template_web/live/home_live.ex`. On the
   template itself the homepage tracks regents.sh's, and `scripts/drift.sh`
   reports when the two differ. Also the share picture
   `platform/priv/static/images/og-image.png` (1200 x 630, the product's name
   and one line about it in the left 600 pixels, which is all X shows on a
   phone, and nothing in the bottom-left corner, where X writes the site's
   name); keep its file name. The logo files in `platform/priv/static` (`favicon.svg`,
   `favicon.ico`, `favicon-32.png`, `favicon-192.png`, `apple-touch-icon.png`,
   `mark.png`, `images/brand/mark-flat-dark.svg`,
   `images/brand/mark-flat-light.svg`) are the Regents crown. Keep them.
2. The legal operator named in `platform/priv/legal/terms.md` and
   `privacy.md`.
3. The site's Patchbay page (`https://patchbay.help/<domain>`) in
   `platform/priv/public/contact.md`. Every contact address stays
   `build@regents.sh`, as on every Regent site.
4. The X and GitHub links in
   `platform/lib/ash_template_web/components/regent_links.ex` and `twitter_site`
   in `platform/lib/ash_template_web/components/layouts/root.html.heex` point at
   the Regents accounts; keep them unless the product has its own.
5. The Fly app names: `app` in `platform/fly.staging.toml`, and the production
   app, which `platform/fly.toml` leaves to the deploy command.
6. The database cluster, hosts and refused identities in
   `platform/lib/ash_template/database_config.ex`.
<!-- /template-only -->

- `platform/`: Phoenix/Ash application. Read its instructions for web changes.
- `cli/`: `COMMANDS.md` and `commands.json`, the description of every
  `regents ash-template` command; the code lives in `regents-cli`. Docs first in
  `COMMANDS.md`, then the route, its OpenAPI operation and `commands.json` in one
  commit, then `make check-cli`, then the change note to the regents-cli chief
  (`cli/README.md`).
- `contracts/`: optional Foundry workspace, empty until contracts are needed.
- `plugins/`: home for standalone runtime plugin packages; none exist yet.
- `skills/`: every shared skill Regent writes (each product's own agent skill lives in
  that product's repository), linked into the Regent workspace's
  `.agents/skills` and `.claude/skills`. `regent-workflow` is the entry point
  for Regent work; `regent-notion` covers the Notion data room and `checkpoint`
  a local handoff. For code, load `regent-workflow`, `ash-stack` and
  `elixir-stack` first: `elixir-stack` names the standard Elixir, Phoenix, Ecto
  and Oban tool for each job and runs the design check, and `ash-stack` routes to
  `ash-backend`, `ash-frontend`, `ash-data`, `ash-security`, `ash-testing` and
  `ash-webmcp` (agent readiness and WebMCP tools), and `ash-signals` covers
  one resource reacting to another's action. `animejs` covers Anime.js in
  LiveView hooks, `vgpu-island` every GPU picture (vgpu inside the shared canvas island), `onchain-buttons` wallet and on-chain buttons, and
  `chain-events` watching a chain and saving its events; load `ash-stack` and
  `ash-frontend` before each. Change a skill here, never through a copy in
  another repository. The web app serves the `ash-*`, `animejs`,
  `onchain-buttons` and `chain-events` skills publicly as its build skills
  (`AshTemplateWeb.AgentSkills` names them), so a change to one is published
  with the app's next release.
- Motion: every Regent site shares the kit in `platform/assets/js/hooks/motion/`
  and `platform/assets/js/motion.ts`, with the standard version of each part in
  `AshTemplateWeb.Motion`. Pages join in through markup (`data-press-label` on
  wallet buttons, `data-panel`, `data-cascade`, `data-variant`), never with their
  own motion code. `/animations` is the lab where every version that was tried
  sits side by side; `skills/animejs/references/liveview-islands.md` explains it.
- Account: `/account` is the same on every Regent site. Its files (the `account`
  list in `scripts/drift.sh`) are copied from here unchanged, and a site's router
  routes its tabs with `account_routes/1` to the shell, which calls
  `AccountLive.attach/1` and shows `<AccountLive.page>`. A site's own sections and
  tabs go in `platform/lib/ash_template_web/account_site.ex`, its one account
  file, and show before the shared ones. Change the shared files here, never in a
  site. `make account-drift` reads every site's main branch and fails naming each
  site whose `/account` differs.
- There is no `identity/` folder. The shared profile domain comes from the
  `regents/identity` package. It and the `design-system` and `elixir-utils`
  libraries are git dependencies pinned to one commit each in `platform/mix.exs`.
- `security/required-fixes.json` lists every shared library (app, repository and
  folder), including Regent's own copy of ash_postgres, and the security fixes
  every Regent site must carry: a `git` fix is a commit the pin must contain, a
  `hex` fix is a version requirement the locked Hex version must meet
  (`>= 3.34.3`).
  Add an entry the day such a fix is published and push it to `main`; every
  site's `make check-required-fixes` reads `main` and fails until the site takes
  it. A new shared library must be listed before any site can use it.
- `make check` runs every gate: the platform's `mix precommit` (which ends with the
  TypeScript typecheck, the script tests and the browser walk) and `mix test`, the
  required-fixes check, then the command description check against the
  site's OpenAPI documents (regents-cli's checker at the commit the `Makefile` pins).
  `make check-platform`, `check-required-fixes`, `check-cli` and `check-contracts`
  run one component.
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
