# Contracts

An optional Foundry workspace. It is empty: Ash Template ships no Solidity, and
`make check-contracts` only says so.

When the product needs contracts, run `forge init --no-git --force .` here,
commit the project, and replace the `check-contracts` target in the root
Makefile with `cd contracts && forge fmt --check && nice forge build && nice forge test`.
`make check` runs its gates side by side, and the Solidity compiler takes every
core it can, so it runs under `nice` and gives way to the other gates. The
`.gitignore` already covers Foundry's `out/`, `cache/` and dry-run broadcasts.
