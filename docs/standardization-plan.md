# Five sites, one template

Status: decided 2026-09-26 (founder answers "1 a 2 c 3 a 4 a 5 a 6 a 7 a 8 a 9 a",
and for 10 "0x1234..abcd, first four and last four"). Written 2026-09-26.

## Decisions

1. Fix the frozen-motion bug now in each site through its lane, Patchbay first.
2. Shared packages for the parts that are identical everywhere (motion kit, short
   address, relative time, copy button); copies for the app skeleton each site adapts.
3. Patchbay moves onto the design system; Tailwind and daisyUI go.
4. Patchbay and Techtree move from JavaScript to TypeScript, Techtree after v0.3.0.
5. Regents' code is renamed from `ash_platform` to `regents`, in one cutover.
6. Each site's own lane does its refactor from the checklist in its backlog; the
   template lane checks each step against the template.
7. The template lane reviews the four clean unmerged template branches and lands what
   still fits; the owner of `codex/profile-cli` finishes its uncommitted edits.
8. The stack skills (`ash-*`, `animejs`) live in the template's `skills/` with workspace
   links; the workflow skills stay in the workspace.
9. The template's `main` takes the motion work and is pushed to a private
   `regents-ai/ash-template` repository.
10. A short address shows `0x`, the first four and the last four characters, joined by
    two full stops: `0x1234..abcd`.

## Later answers (2026-09-26)

- WebMCP: the build guide is `skills/ash-webmcp/references/build.md`. Patchbay's and
  Autolaunch's gaps against it are on their backlogs (1a). No WebMCP example page in the
  template (2b).
- Patchbay's scan fixes shipped as v98 (`08ab16c`): standard rate-limit headers, a
  published versions policy, Patchbay named on its developer pages (3a). No postal
  address (4a). The Patchbay command line is not published to npm yet (5b).
- Command lines: each repository describes its own commands and how they reach its
  server; one `regents-cli` repository publishes a single package holding every
  platform's commands. Which repository that is, and what each site's `cli/` keeps, is
  still open.

## Goal

The template is the best example of three things: the Regent design system, the
codebase structure, and the agent skills. Regents, Patchbay, Techtree, Autolaunch
and KeyFleet are each built on the template's design and code. What only one site
does (staking, auctions, maps, research trees, pairing) stays in that site; the
parts every site has come from the template, in the template's shape.

Rules for every stage:

- The template is the reference; Regents stops being the "template site". A shared
  change lands in the template first, then goes onto each site's backlog.
- Hard cutover: a site adopting a template part deletes its own version outright.
  No dual shapes, no compatibility branches.
- One writer per repository at a time, in its own worktree and branch. Lanes that
  are writing in a site today keep their work; the refactor waits for or joins it.
- Every site keeps working for its customers throughout: each step is small enough
  to check in a browser and ship on its own.

## What "built on the template" means

| Area | The template's standard |
| --- | --- |
| Layout | `platform/`, `cli/`, `plugins/`, `contracts/`, `skills/`, a `Makefile` whose `make check` runs every gate |
| Design | `regent_ui` components; product CSS in `@layer regents-product` with BEM names on the design-system tokens; page CSS in `assets/css/pages/`, parts in `assets/css/components/` |
| Browser code | TypeScript, strict, typechecked; hooks in `assets/js/hooks/`, combined with `composeHooks`; page-only code lazy-loaded; size budgets (175 KiB script, 60 KiB style, compressed) |
| Motion | The kit in `assets/js/hooks/motion/` and `assets/js/motion.ts`, versions in `Motion.standard/1`, the lab at `/animations` |
| Shell | The shell component, route catalog, launch gate, Privy session and signed-in wallet handling |
| Server | Ash resources behind code interfaces, health and metrics endpoints, `mix precommit` with Credo, Sobelow, xref, format and codegen checks |
| Tests | A small named set that each protects a stated rule, plus browser checks of real flows |
| Skills | `skills/` in the template, linked into the workspace |

## Stage 1: bring the best code into the template

The surveys found places where a site is ahead of the template. Each moves into the
template in the template's shape, then every site takes it from there.

| From | What | Why it is better |
| --- | --- | --- |
| Autolaunch | `SignedInWallet`: wallet panels read the signed-in wallet from the session on mount | The workflow skill already names it the reference; the template has no equivalent |
| Autolaunch | Health and metrics endpoints; newer dependency versions | More complete checks; the template lags on versions |
| KeyFleet | Page titles on every page; friendly error pages; the copy button announcing "Copied" to screen readers; `Time.ago` | Each is missing or weaker in the template |
| KeyFleet | No test wallet in the production bundle | The template ships `__ashTemplateTestWallet` to customers |
| Regents | Client address parsing, ENS identity, search titles, canonical host redirect, input parsers; the session authority clean-up | Each is tidier or missing in the template |
| Patchbay | The copy-prompt control | Better than the template's copy text |
| Techtree | Its strict content security policy | The template sets none |

Also in this stage:

- Remove the route catalog's `content_transition_kind`: the old shell motion was its
  only reader, and nothing reads it now. Regents carries the same leftover.
- Land or close the template's five unmerged branches from 2026-09-22 (product
  profiles, profile actions over the command line and WebMCP, standalone database
  and release). Sites should copy a template that has settled. One of them has
  uncommitted edits by another session (see decision 7).

## Stage 2: bring each site onto the template

Order, closest first, so the checklist is proven on the easy sites:

| Site | Distance | Main work |
| --- | --- | --- |
| KeyFleet | Closest | Add `regent_format` and `skills/`; split the 1,636-line `shell_live.ex` along the template's lines; adopt the motion kit (it has its own) |
| Regents | Near | Delete the leftover `material.css` alias; add the missing ignore line for `priv/static/images/regent-ui/`; take the template's newer parts; rename the app from `ash_platform` (decision 5) |
| Autolaunch | Medium | Adopt the template's sign-in; move `core_tests` into the standard layout; add a `Makefile` and `skills/`; read the theme instead of fixing it; one short-address helper instead of six copies |
| Patchbay | Far | Move from Tailwind and daisyUI onto the design system (decision 3); JavaScript to TypeScript (decision 4); newer Privy session; the full precommit |
| Techtree | Far | After its v0.3.0 release: JavaScript to TypeScript; a full `mix precommit`; remove the stale 365-line `platform/AGENTS.md` and the tracked `.beads/` folder; drop the alias token layer; keep its Python command line |

Each site's list goes into its `docs/backlogs/<site>.md` as small steps, each one
shippable and checked in a browser.

## Stage 3: keep them in step

- A change to a shared part is made in the template, then listed on every site's
  backlog.
- A short script in the template compares each site's copies of shared files with
  the template's and lists the differences, so drift is visible rather than guessed.

The options and recommendations behind each decision are in this file's history.
