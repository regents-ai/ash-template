# Ash Template

The Ash Template monorepo: a public website with wallet sign-in and a small
account area, a public HTTP API, a command-line tool, and room for contracts
and runtime plugins.

<!-- template-only -->
This is a product template, cut from the Regents product and stripped back to
the parts every product starts with. The placeholder product is called
**Ash Template**; run the rename script before building anything on it:

```sh
scripts/init.sh keyfleet KeyFleet "KeyFleet"
```

`scripts/init.sh <snake_name> <ModuleName> ["Display Name"]` replaces the
OTP application `ash_template`, the Elixir modules `AshTemplate`, the
camel-case name `ashTemplate`, the kebab-case name `ash-template`, the
environment prefix `ASH_TEMPLATE_`, the display name "Ash Template" and its
capitalised form "ASH TEMPLATE" everywhere they appear, including the CLI
package and command names. It drops the passages that describe the template
itself, records the rename in the changelog and removes itself, then prints
the follow-up commands: format the renamed code, regenerate the route catalog
digest, run the gate.
<!-- /template-only -->

## Components

| Component | What it holds | Check |
| --- | --- | --- |
| [platform/](platform/README.md) | The Phoenix/Ash web application: home page, Privy wallet sign-in, the signed-in Overview and Account pages, public pages, health and metrics, and the served API. | `make check-platform` |
| [cli/](cli/README.md) | `commands.json`, the description of every `regents ash-template` command; the code that runs them lives in [regents-cli](https://github.com/regents-ai/regents-cli). | `make check-cli` |
| [contracts/](contracts/README.md) | An optional Foundry workspace. Empty until the product needs contracts. | `make check-contracts` |
| [plugins/](plugins/README.md) | Standalone runtime plugin packages. None yet. | None |
| [skills/](skills/) | Every agent skill Regent writes. `regent-workflow` is the entry point for Regent work; `ash-stack` is the entry point for code and routes to the backend, frontend, data, security, testing and WebMCP skills; `animejs` covers Anime.js animation inside LiveView hooks, `onchain-buttons` wallet and on-chain buttons, and `chain-events` watching a chain and saving its events. The web app serves all of them except `regent-workflow`, `regent-notion` and `checkpoint` as its [build skills](platform/README.md#showcase). | None |

`make check` runs every component's check in turn; the
[platform README](platform/README.md#checks) explains the platform's.
`make release` runs them on the committed tree, then builds and starts the release
image; see [Release](platform/README.md#release).

## Start

1. Follow the [platform quickstart](platform/README.md#quickstart) to create the
   local database, load Privy credentials and start the server.

2. Run `gh auth login` once and install `uv`: `make check` fetches the
   required-fixes list from GitHub, and runs regents-cli's command description
   checker with `uv`.

## Shared dependencies

The platform takes its shared libraries from three Regent repositories, each
pinned to one commit in `platform/mix.exs`: `design-system` (the shared UI),
`elixir-utils` (Privy verification, agent access, formatting and lint checks)
and `regents/identity` (the shared profile domain served at `/api/v1/profile`).
`security/required-fixes.json` lists the shared libraries, where each must come
from, and the security fixes every Regent site must carry. `make check` fails when
a library is not pinned to an inspectable commit of its repository or lacks a fix. The
[platform README](platform/README.md#shared-dependencies) explains both.

## License

MIT, see [LICENSE](LICENSE). Vendored dependencies retain their own licenses.
