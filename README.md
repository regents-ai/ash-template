# Ash Template

A monorepo template for a Phoenix/Ash product: a public website with wallet
sign-in and a small account area, a public HTTP API, a command-line tool, and
room for contracts and runtime plugins. It was cut from the Regents product and
stripped back to the parts every product starts with.

The placeholder product is called **Ash Template**. Run the rename script
before building anything on it.

## Components

| Component | What it holds | Check |
| --- | --- | --- |
| [platform/](platform/README.md) | The Phoenix/Ash web application: home page, Privy wallet sign-in, the signed-in Overview and Account pages, public pages, health and metrics, and the served API. | `make check-platform` |
| [cli/](cli/README.md) | A pnpm workspace with one package, `@ash-template/cli`, publishing the `ash-template` command. It only prints usage and version today. | `make check-cli` |
| [contracts/](contracts/README.md) | An optional Foundry workspace. Empty until the product needs contracts. | `make check-contracts` |
| [plugins/](plugins/README.md) | Standalone runtime plugin packages. None yet. | None |

## Start

1. Rename the template to your product:

   ```sh
   scripts/init.sh keyfleet KeyFleet "KeyFleet"
   ```

   `scripts/init.sh <snake_name> <ModuleName> ["Display Name"]` replaces the
   OTP application `ash_template`, the Elixir modules `AshTemplate`, the
   kebab-case name `ash-template`, the environment prefix `ASH_TEMPLATE_` and
   the display name "Ash Template" everywhere they appear, including the CLI
   package and command names. It prints the follow-up commands: format the
   renamed code, regenerate the route catalog digest, run the gate.

2. Follow the [platform quickstart](platform/README.md#quickstart) to create the
   local database, load Privy credentials and start the server.

3. Build the CLI with `cd cli && pnpm install --frozen-lockfile && pnpm build`.

## Shared dependencies

The platform depends on three sibling repositories resolved through
`REGENT_DEPS_ROOT`: `design-system` (the shared UI), `elixir-utils` (Privy
verification, agent access and lint checks) and `regents/identity` (the shared
profile domain served at `/api/v1/profile`). The
[platform README](platform/README.md#shared-dependencies) explains the layout.

## License

MIT, see [LICENSE](LICENSE). Vendored dependencies retain their own licenses.
