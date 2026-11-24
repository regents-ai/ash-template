# Ash Template

This repository is Regents Labs' standalone open-source starter and reference architecture for **Elixir + Phoenix LiveView 1.2 + Ash Framework 3.x + Agent-Ready Web Apps** (WebMCP, Hosted MCP, OAuth 2.1, SIWA, `/llms.txt`, Agent Skills Discovery, Anime.js v4, and WebGPU islands).

Keep the placeholder names (`ash_template`, `AshTemplate`, `ashTemplate`, `ash-template`, `ASH_TEMPLATE_`, "Ash Template", "ASH TEMPLATE") and default address `template.regents.sh` intact in this template repository so `scripts/init.sh` can rename them cleanly for anyone starting a new app.

## Structure

- `platform/`: Phoenix/Ash application. Read `platform/AGENTS.md` (synced via `mix usage_rules.sync`) and `platform/README.md` before web changes.
- `cli/`: `COMMANDS.md` and `commands.json`, a declarative command catalog aligned with the app's OpenAPI contract.
- `contracts/`: optional Foundry workspace, empty until contracts are needed.
- `plugins/`: optional standalone runtime plugin packages.
- `skills/`: 16 public engineering skills for coding with this stack:
  - Core backend/frontend: `ash-stack`, `ash-backend`, `ash-data`, `ash-frontend`, `ash-security`, `ash-signals`, `ash-webmcp`, `elixir-stack`.
  - Motion & graphics: `animejs`, `vgpu-island`, `splat-scenes`, `splat-scenes-phoenix`.
  - Web3 & social patterns: `onchain-buttons`, `chain-events`, `payments`, `discussions`.
  - `skills/third-party/`: unmodified third-party skills under their own licenses (never served).
  - The web app serves its build skills at `/.well-known/agent-skills/` (`AshTemplateWeb.AgentSkills`).

## Motion & Account patterns

- **Motion:** Pages participate in the Anime.js v4 kit in `platform/assets/js/hooks/motion/` and `platform/assets/js/motion.ts` via declarative attributes (`data-press-label`, `data-panel`, `data-cascade`, `data-variant`, `phx-hook="MotionCount"`, `MotionTravel`, `MotionCrumbs`, `MotionActivity`, `MotionChart`, `ThemeSwitch`, `data-sheet-handle`, `data-dismiss`). Inspect interactive demos at `/animations`.
- **Account:** `/account` and its tabs (`Account`, `Agents`, `Points`, `Wallets`, `Connections`, plus optional `Settings` via `AshTemplateWeb.AccountSite.settings/0`) are declared once in `platform/lib/ash_template_web/account_routes.ex` so the router, route catalog, and titles stay in sync.
- **Public agent surface:** `/llms.txt` is rendered from [platform/priv/public/llms.md](platform/priv/public/llms.md); keep it consistent with `platform/lib/ash_template_web/router.ex` and `platform/contracts/api-contract.openapiv3.yaml`.

## Checks & Releases

- `make check` runs all self-contained gates in parallel (`check-style`, `check-platform` / `mix precommit`, `check-required-fixes` against local `security/required-fixes.json`, and `check-contracts`).
- `make check-cli` optionally validates `cli/commands.json` against the OpenAPI specs using `uv`.
- `make release` verifies a clean tree, runs `make check`, builds the container image from `HEAD`, and boots it against a throwaway database (`scripts/release.sh`).
- Never commit secrets or read `.env` / `.env.local` / `.envrc`.

## New site

After running `scripts/init.sh <snake_name> <ModuleName> <host> ["Display Name"]`, customize these items by hand:

1. **Homepage & brand assets:** Replace `@name`, `@mission`, `@tour`, and `products/0` in `platform/lib/ash_template_web/live/home_live.ex`, plus `platform/priv/static/images/og-image.png`, favicons, and `platform/priv/static/images/brand/*`.
2. **Homepage theme lock:** By default the homepage stays dark for the datascape artwork (`homeThemeLocked` in `platform/assets/js/theme.ts`, `home?` in `root.html.heex`, and `data-home-theme-locked` in `home.css`). Remove all three if your homepage supports light mode.
3. **Legal & contact pages:** Replace the operator and `[FILL IN: …]` placeholders in `platform/priv/legal/terms.md`, `platform/priv/legal/privacy.md`, and `platform/priv/public/about.md`.
4. **Social links:** Update `platform/lib/ash_template_web/components/regent_links.ex` and `twitter_site` in `root.html.heex`.
5. **Deployment & database:** Set your Fly app name in `platform/fly.toml` / `platform/fly.staging.toml` and supply `DATABASE_POOLED_URL` (or `DATABASE_URL`), `DATABASE_DIRECT_URL`, `ASH_TEMPLATE_DEPLOYMENT_ROLE`, `PHX_HOST`, and `SECRET_KEY_BASE` (optionally pinning hosts via `ASH_TEMPLATE_ALLOWED_DB_HOSTS`).
6. **WebMCP origin trial token:** Replace `@webmcp_origin_trial` in `platform/lib/ash_template_web/endpoint.ex` with a token issued for your domain (or remove it).
7. **Compile-connected limit:** Adjust `--fail-above` in `platform/mix.exs` as you add Ash resources and controllers.
8. **Format & handoff digest:** Run `mix format` and `mix <your_app>.route_handoff` from `platform/`.
9. **Account Settings:** Implement `settings/0` in `platform/lib/<your_app>_web/account_site.ex` to add an `/account/settings` tab.
