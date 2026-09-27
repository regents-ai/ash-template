# Ash Template

<!-- template-only -->
This monorepo is a product template. Keep the placeholder names (`ash_template`,
`AshTemplate`, `ashTemplate`, `ash-template`, `ASH_TEMPLATE_`, "Ash Template",
"ASH TEMPLATE") exactly as they are; `scripts/init.sh` renames them for a real
product.

After renaming, a new site must still replace, by hand:

1. Brand files in `platform/priv/static`: `favicon.svg`, `favicon.ico`,
   `favicon-32.png`, `favicon-192.png`, `apple-touch-icon.png`, `mark.png`,
   `images/brand/mark-flat-dark.svg`, `images/brand/mark-flat-light.svg`, and
   the homepage art `images/home/hero-bg-dark.svg`. Keep the file names.
2. The legal operator named in `platform/priv/legal/terms.md` and
   `privacy.md`.
3. Every `example.com` contact address in `platform/priv/legal`,
   `platform/priv/public/contact.md` and
   `platform/lib/ash_template_web/public_documents.ex`.
4. The `x.com/example` and `github.com/example` links in
   `platform/lib/ash_template_web/components/regent_links.ex`.
5. The Fly app names: `app` in `platform/fly.staging.toml`, and the production
   app, which `platform/fly.toml` leaves to the deploy command.
6. The database cluster, hosts and refused identities in
   `platform/lib/ash_template/database_config.ex`.
<!-- /template-only -->

- `platform/`: Phoenix/Ash application. Read its instructions for web changes.
- `cli/`: `commands.json`, the description of every `regents ash-template`
  command. The code lives in `regents-cli`; change the description in the same
  commit as the route it describes.
- `contracts/`: optional Foundry workspace, empty until contracts are needed.
- `plugins/`: home for standalone runtime plugin packages; none exist yet.
- `skills/`: every skill Regent writes, linked into the Regent workspace's
  `.agents/skills` and `.claude/skills`. `regent-workflow` is the entry point
  for Regent work; `regent-notion` covers the Notion data room and `checkpoint`
  a local handoff. For code, start with `ash-stack`, which routes to
  `ash-backend`, `ash-frontend`, `ash-data`, `ash-security`, `ash-testing` and
  `ash-webmcp` (agent readiness and WebMCP tools). `animejs` covers Anime.js in
  LiveView hooks, `onchain-buttons` wallet and on-chain buttons, and
  `chain-events` watching a chain and saving its events; load `ash-stack` and
  `ash-frontend` before each. Change a skill here, never through a copy in
  another repository.
- Motion: every Regent site shares the kit in `platform/assets/js/hooks/motion/`
  and `platform/assets/js/motion.ts`, with the standard version of each part in
  `AshTemplateWeb.Motion`. Pages join in through markup (`data-press-label` on
  wallet buttons, `data-panel`, `data-cascade`, `data-variant`), never with their
  own motion code. `/animations` is the lab where every version that was tried
  sits side by side; `skills/animejs/references/liveview-islands.md` explains it.
- There is no `identity/` folder. The shared profile domain comes from the
  `regents/identity` package. It and the `design-system` and `elixir-utils`
  libraries are git dependencies pinned to one commit each in `platform/mix.exs`.
- `security/required-fixes.json` lists every shared library (app, repository and
  folder) and the security fixes every Regent site must carry: a `git` fix is a
  commit the pin must contain, a `hex` fix is the lowest allowed Hex version.
  Add an entry the day such a fix is published and push it to `main`; every
  site's `make check-required-fixes` reads `main` and fails until the site takes
  it. A new shared library must be listed before any site can use it.
- `make check` runs every gate: the platform's `mix precommit` and TypeScript
  typecheck, the required-fixes check, then the command description check against the
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
