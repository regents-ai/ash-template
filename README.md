# Ash Template

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Elixir 1.20](https://img.shields.io/badge/elixir-1.20-lightgrey)](https://elixir-lang.org)
[![Phoenix 1.8](https://img.shields.io/badge/phoenix-1.8-lightgrey)](https://www.phoenixframework.org)
[![Ash 3.37](https://img.shields.io/badge/ash-3.37-lightgrey)](https://ash-hq.org)

**Ash Template** is Regents Labs' open-source starter and reference architecture for building production web applications with **Elixir, Phoenix LiveView 1.2, Ash Framework 3.x, and first-class AI agent interfaces**.

Regents Labs' own products now run in the unified [`regents.sh`](https://regents.sh) monorepo; this repository is maintained as a clean, standalone MIT-licensed showcase of our opinionated stack so anyone in the Ash and Elixir ecosystem can fork, inspect, or bootstrap a new application from it.

## What's in the stack

- **Ash Framework 3.x + AshPostgres + AshOban:** Declarative domains, resources, policies, keyset pagination, idempotent operations, background jobs, and signals (`AshSignals`).
- **Phoenix 1.8 + LiveView 1.2:** Persistent shell navigation, streams, live notifications (`Postgrex.Notifications`), Peep Prometheus metrics on a private port, structured JSON logs, and `ErrorTracker`.
- **Agent-ready by default:**
  - **Hosted MCP (`/mcp`)** via `AshAi` + **OAuth 2.1** connector support (`/.well-known/oauth-*`).
  - **WebMCP** browser tools (`navigator.modelContext`) and live tool catalog (`/capabilities.json`).
  - **SIWA (Sign-In With Agent)** cryptographic HTTP signatures (RFC 9421), pairing codes, and Hello Cards.
  - **Discovery & Markdown negotiation:** `/llms.txt`, `/openapi.json`, `/api-contract.openapiv3.yaml`, `Accept: text/markdown` on public pages, and **Agent Skills Discovery v0.2.0** (`/.well-known/agent-skills/index.json`).
- **Design system, Motion & WebGPU:** Shared `regent_ui` component kit (`/showcase`), Anime.js v4 LiveView motion hooks (`/animations`), and WebGPU / Gaussian splat islands (`/animations/splats`).
- **Optional Web3 & Payments:** Privy wallet sign-in, ENS resolution, Base / Ethereum chain reads, and x402 USDC payment verification.
- **16 Reusable Engineering Skills (`skills/`):** Curated AI coding skills covering Ash domains, LiveView, Postgres concurrency, security, WebMCP, Anime.js, WebGPU islands, and Gaussian splat scenes.

## Quickstart

You need Erlang, Elixir, Node, and PostgreSQL at the versions pinned in `platform/.tool-versions`.

```sh
cd platform
mix setup
mix ecto.create
mix ecto.migrate
mix phx.server
```

Open `http://localhost:4000` (and `/showcase`, `/animations`, `/docs`, `/llms.txt`).

Privy credentials (`PRIVY_APP_ID`, `PRIVY_VERIFICATION_KEY`) are **optional in development** — the server boots with Postgres alone so you can explore the UI, docs, showcase, motion lab, and public APIs immediately. See [platform/docs/local-privy-auth.md](platform/docs/local-privy-auth.md) when you are ready to enable browser wallet sign-in.

## Rename for your own app

Run `scripts/init.sh` once on a clean checkout to rename `ash_template` / `AshTemplate` / `ash-template` and the default hostname across the repository:

```sh
scripts/init.sh night_owl NightOwl night-owl.example "Night Owl"
```

See [AGENTS.md](AGENTS.md#new-site) for the remaining manual items (brand artwork, legal copy, Fly app name, and WebMCP origin trial token).

## Repository layout

| Folder | What it holds | Check |
| --- | --- | --- |
| [platform/](platform/README.md) | Phoenix + Ash web app: homepage, account shell, notes/rooms/chat reference domains, `/mcp`, `/llms.txt`, `/showcase`, and `/animations`. | `make check-platform` |
| [cli/](cli/README.md) | `COMMANDS.md` and `commands.json` schema pattern for paired CLI commands. | `make check-cli` |
| [contracts/](contracts/README.md) | Optional Foundry workspace (empty until contracts are added). | `make check-contracts` |
| [plugins/](plugins/README.md) | Optional standalone runtime plugin packages. | — |
| [skills/](skills/) | 16 public engineering skills (`ash-*`, `elixir-stack`, `animejs`, `vgpu-island`, `splat-scenes*`, `onchain-buttons`, `chain-events`, `payments`, `discussions`). | Served at `/.well-known/agent-skills/` |
| [skills/third-party/](skills/third-party/README.md) | Unmodified third-party skills under their own licenses (never served). | — |

Run `make check` from the repository root to execute all self-contained quality gates (`check-style`, `mix precommit`, `check-required-fixes`, `check-contracts`) in parallel with no GitHub authentication required.

## Shared dependencies

Shared packages (`regent_ui` from `regents-ai/design-system`, `regent_*` and `siwa` from `regents-ai/elixir-utils`) are public Git repositories pinned by commit in `platform/mix.exs`. `security/required-fixes.json` records minimum security commits/versions verified locally by `make check-required-fixes`.

## License

MIT — see [LICENSE](LICENSE). Vendored and third-party files retain their own licenses.
