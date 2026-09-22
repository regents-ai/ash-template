# Ash Template CLI

The command-line workspace for this product. It is a pnpm workspace with one
package, `@ash-template/cli`, which publishes the `ash-template` command.
Today that command only prints its usage and version: add product commands to
`packages/ash-template-cli/src/` as the product grows.

With Node 22+ and the package manager version declared in `package.json`:

```sh
cd cli
pnpm install --frozen-lockfile
pnpm build
node packages/ash-template-cli/dist/index.js --help
```

`make check-cli` from the monorepo root runs the build, typecheck and tests.
