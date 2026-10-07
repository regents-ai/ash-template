# One command line: moving to `regents-cli`

Status: decided 2026-09-26 (founder answers "1 a 2 a 3 a 4 a 5 a", then "6 a": join the
history already on GitHub). Steps 1 and 2 are done.
Follows the founder's "2 a 3 a 4 a" of 2026-09-26 (see `standardization-plan.md`).

Superseded in part 2026-09-27: the founder moved `regents` to Python, published on PyPI as
`regents-cli` (regents-cli `65722c6`); the TypeScript `@regentslabs/cli` left `main`. 1.0 keeps
`regents auth`, each site's described commands, `regents <site> doctor` and `regents techtree`;
the shared `regents profile` commands are dropped. The regents-cli chief owns that plan.

## Where things are today

| Command line | Language | Commands | Published |
| --- | --- | --- | --- |
| `@regentslabs/cli` (`repos/regents/cli`) | TypeScript | 135 in 35 groups, 8 of them `techtree …` | npm 0.5.0; local 1.0.0 |
| Patchbay (`repos/patchbay/cli`) | JavaScript | 12 | no |
| Autolaunch (`repos/autolaunch/cli`) | JavaScript | 8 | no |
| Keyfleet, template (`cli/`) | TypeScript | `version`, `help` only | no (private) |
| Techtree (`repos/techtree/cli`) | Python, 56k lines | ~28 | PyPI `techtree` 0.2.1 |
| `repos/regents-cli-v2` | Python host | `status`, `commands` | no; one local commit, no remote |

Patchbay's and Autolaunch's command tables already say, for each command, the server
route it calls, who may call it and whether it changes anything. That is the starting
shape for the command descriptions. The private-profile code is byte-identical in three
places; the Patchbay and Autolaunch runners differ by one branch.

## The target

- `regents-cli` is its own repository, holding the one package `@regentslabs/cli` with the
  `regents` command. Every platform is a namespace: `regents patchbay …`,
  `regents autolaunch …`, `regents techtree …`, `regents keyfleet …`. Nothing product-owned
  sits at the root.
- Each site's `cli/` holds only `commands.json` (every command: name, inputs, the server
  route it calls, who may call it, whether it changes anything, what comes back) and a
  short README. The site changes it in the same commit as the route it describes.
- `regents-cli` pins each site's `commands.json` by commit in `platforms.lock.json`. A sync
  script copies them in; a check fails when a pinned description names a route the site's
  `openapi.json` does not have, or when a described command has no code.
- One way to answer everywhere: readable output by default, `--json` for machines, errors
  as `{"error": {"code", "message"}}`, the same exit codes, one base-address rule
  (`--base-url`, then `<PLATFORM>_BASE_URL`, then the site's address).

## Steps, each shippable

1. **Cut the repository.** Move `repos/regents/cli` into `repos/regents-cli`, keeping its
   history. Point the package's `repository` field at it. Regents' lane deletes `cli/`
   from Regents in the same cutover. *Done:* `regents-ai/regents-cli` `457df04` (joined
   with the 192 commits already published there); Regents `5307bf2`.
2. **Describe the format.** `schemas/commands.v1.json` in `regents-cli`; the template's
   `cli/` becomes a `commands.json` example and loses its placeholder package. *Done:*
   `scripts/check-platform-commands.mjs` checks a description against the format and the
   site's OpenAPI documents; the template's `make check-cli` runs it. Drafts of Patchbay's
   and Autolaunch's full descriptions pass it. The shared profile commands stay
   `regents profile …` with `--base-url`, not in each site's description.
3. **Patchbay and Autolaunch.** Their 20 commands become namespaces, sharing one profile,
   runner and base-address module. Their tests move with them; the tests that reach into
   the site's own folders become checks against the pinned description. Each site's `cli/`
   becomes `commands.json` and a README.
4. **Keyfleet.** Its placeholder package goes; `commands.json` describes its API when it
   has commands.
5. **Techtree.** Its 8 existing `regents techtree` commands and the ~28 Python ones become
   one namespace (they overlap: both have `forge` and `uplift`, with different
   subcommands). The Hermes plugin calls `regents techtree …` instead of `techtree`. Then
   PyPI `techtree` stops being published. How the Python engine travels is decision 1.
6. **Publish** `@regentslabs/cli` 1.0.0 to npm from the new repository (founder go).
7. **Clean up.** Remove `repos/regents-cli-v2` and the Python-host pattern in
   `repos/monorepo-template` (decision 4).

## Decisions

1. **How does Techtree's Python engine (56k lines: runs, climbs, the Verifiers engine,
   signed publication) travel in an npm package?**
   - a) `regents-cli` carries it as a bundled Python runtime and runs it with `uv`, the way
     it already bundles the Verify runtime. Needs Python 3.12 and `uv` on the machine.
   - b) Port it to TypeScript. Weeks of work and a rewrite of the signing and engine code.
   - c) It stays a Python library on PyPI that `regents-cli` installs; only its commands
     move.

   Recommendation: a. It follows the existing Verify precedent and removes the second
   published package, which is what "retire" asked for.
2. **Description format:** a) `commands.json`, grown from Patchbay's table with typed
   inputs; b) YAML like Regents' `shared-cli-contract.yaml`. Recommendation: a; it is
   what `commands list --json` already prints.
3. **Git history:** a) keep Regents' `cli/` history in the new repository; b) start fresh.
   Recommendation: a.
4. **The Python host prototypes** (`regents-cli-v2`, `monorepo-template`, one local commit
   each, no remote): a) delete both folders; b) keep them as they are.
   Recommendation: a, after one last check for anything worth keeping.
5. **GitHub:** a) create `regents-ai/regents-cli`, public like the product repositories;
   b) private until 1.0.0 is published. Recommendation: a.
