# Version-aware documentation workflow

## Find the project and available tools

Read the applicable `AGENTS.md`, `mix.exs`, `mix.lock`, formatter, toolchain pins, and
CI. In a monorepo locate the app that owns the requested route/resource. In an umbrella,
check where the lockfile and dependencies actually live. The inventory script prints
candidate roots and warns about missing files; it does not choose one for you.

Use the installed dependency checkout for Git/path dependencies. A package's `main`
branch can be ahead of the installed release. A HexDocs default page can describe a
different release from the next page you click. Check the displayed version, not only
the URL. Do not claim a latest-release compatibility matrix from this pack's snapshot.

## Search order

1. Relevant existing implementation and tests, then applicable dependency usage rules.
2. Installed module docs/source and the exact dependency's DSL reference.
3. Official versioned HexDocs; changelog or source tag for a suspected behavior change.
4. Community examples only as leads, checked against the sources above.

Look for both `deps/<package>/usage-rules.md` and the `usage-rules/` directory. Some
packages split nearly all useful content into sub-rules. Read the relevant files;
reading a five-line top-level summary is not sufficient. Avoid loading every rule in
the ecosystem for every task.

If `usage_rules` exists, inspect these commands before choosing syntax:

```sh
mix help usage_rules.search_docs
mix help usage_rules.sync
```

For the documented v1.2.7 search task, these are valid examples:

```sh
mix usage_rules.search_docs "AshPhoenix.Form submit" -p ash_phoenix
mix usage_rules.search_docs "atomic update" -p ash
mix usage_rules.search_docs "scope" -p ash@3.32.3
```

The explicit version above is an example, not a required app version. Substitute the
locked version. From inside a project, the task uses project versions when possible;
outside one, it can fall back to latest. Keep searches to public symbols, not private
code or customer data. Read the actual result, not merely its search summary.

If Tidewave or another development MCP is already connected, inspect its available
tools and use documented read-only documentation/log queries. Do not assume tool names,
start or stop the user's server, or execute data-changing runtime evaluation just to
inspect docs. Fall back to local source and HexDocs when the runtime tool is absent.
No additional plugin is required by this pack.

## Optional maintainer-rule synchronization

`usage_rules` is optional; the pack works with local files and official docs. Adding
it is a project dependency decision, not an automatic first step. Current v1.x uses
project configuration; older blog snippets with CLI-driven sync may not apply.
Consult the installed version's help before editing or running sync.

A minimal v1.x configuration can link maintainer guidance without copying it into the
custom skills. Merge this inside the existing `project/0` keyword list, not as a second
`project/0` function:

```elixir
usage_rules: [
  file: "AGENTS.md",
  usage_rules: [
    {:ash, link: :markdown},
    {~r/^ash_/, link: :markdown},
    {:phoenix, link: :markdown},
    {:phoenix_live_view, link: :markdown}
  ]
]
```

Then review the effects of `mix usage_rules.sync`. Keep the six `ash-*` names reserved
for this authored pack. If composing generated skills, use distinct names such as
`ash-upstream-rules`; never point generation at one of these six names. Review managed
content deletion and changes to `AGENTS.md` before accepting a sync.

## Record only useful evidence

For a disputed API, note the installed version, module/function or DSL section, and
what was verified. Do not archive entire documentation pages in every PR. Refresh
knowledge when the lockfile changes, a missing API appears, or a documented bug fix
matters. An unsuccessful search is a reason to inspect source, not to invent syntax.

Sources: [source index](source-index.md), especially S01, S07, S08, S09, S10.
