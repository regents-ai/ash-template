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
- Command lines (founder "2 a 3 a 4 a"): the published `@regentslabs/cli` moves out of
  Regents into its own `regents-cli` repository and becomes the one package, with every
  platform's commands in it. Each site's `cli/` keeps only a description of its commands:
  names, inputs, the server address each calls and what comes back; the code moves into
  `regents-cli`. Techtree's Python `techtree` package retires once its commands work there.
  This replaces the 2026-09-07 plan for the Python `regents-cli-v2` host.
- API changes (founder "1 a"): a breaking change is listed on the changelog the day it
  ships; no notice period.
- Chrome's WebMCP trial (founder "5 a"): the founder registers a token for autolaunch.sh;
  Patchbay's expires 2026-11-17 and needs renewing before then.
- Wallet transactions (founder "4 a 5 a 6 a", 2026-09-27): the server builds every step
  before the press and the press goes straight to the wallet. The building and checking
  live in one shared package, `regent_chain` in elixir-utils (0.2.0 at `7a876e8`), taken from
  Autolaunch's version; `skills/onchain-buttons` shows how to use it. KeyFleet's `main`
  does this for every wallet button (8f9629f); Autolaunch's remaining press gates,
  Regents' redeem encoder and Patchbay's browser-signed payment are on branches held for
  the founder, listed in `skills/onchain-buttons/references/sites-today.md`.
- Server or browser (founder "1 a 2 a 3 a", 2026-09-27, after both sides were argued): the
  template teaches server-built steps only, with a review screen whenever a person types an
  amount. Regents staking and Autolaunch move onto it. The next customer-facing improvement is
  one wallet prompt for approve-and-send and gas paid by Regent. A research brief for the
  skill rewrite, with every reason on both sides, is in the workspace at
  `docs/handoffs/server-built-transactions-research-2026-09-27.md`.
- Wallet journeys (founder "1 a 2 a 3 a", 2026-09-27): after listing all 87 wallet journeys by
  user type (workspace `docs/handoffs/wallet-user-journeys-2026-09-27.md`), the standard is the
  server building every step, one press path straight to the wallet, every outcome recovered
  even when the page never reports back, and agent routes served from the same builder. The
  command line's broken staking and ENS routes are added by Regents from that builder;
  KeyFleet moves before it launches.

- Template chief engineer's review (founder, 2026-09-27: "1a 2a 3 you can invent your own
  way whatever is standard for production codebases 4a , yes and is related to security
  fixes 5 daily sweep 6a 7a 8. delete 100% of the tests right now 9. a 10 b 11 b"):
  1. Order: template fixes first, then bring the sites' best parts in, then send out.
  2. The Autolaunch lane takes the keccak fix for SIWA and ENS and ships it.
  3. Shared libraries are git dependencies pinned to one commit each in `mix.exs`,
     recorded in `mix.lock`; the release image fetches them at that commit. This
     replaces sibling checkouts, `release-inputs.json`, `shared-libs.lock` and vendored
     copies in every site.
  4. `security/required-fixes.json` lists security fixes to shared libraries; every
     site's `make check` fails when a pin lacks one. Third-party packages are checked by
     `mix hex.audit` in `mix precommit`.
  5. A daily scheduled sweep reads every repository's new commits for fixes to share and
     writes its report to the workspace's `artifacts/sweeps/`.
  6. The five 2026-09-22 template branches are closed (kept in the workspace archive
     `artifacts/ash-template-closed-branches-2026-09-27/`).
  7. The template's `--ash-*` colour aliases are gone; it uses the design system's names.
  8. The template has no automated tests.
  9. Autolaunch's leftover launch countdown is removed.
  10. v0.1.0 is for Regent's own sites first; a public launch comes later.
  11. No WebMCP example tool in v0.1.0. Superseded 2026-09-28 by founder "1 b" (below).
- WebMCP in the template (founder "1 b", 2026-09-28): the template ships two read tools
  that need no product, `about` and `docs`, from one `platform/priv/tool_manifest.json`;
  `make readiness` checks them. This replaces item 11 above.

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
| Layout | `platform/`, `cli/` (the site's command descriptions; the code lives in `regents-cli`), `plugins/`, `contracts/`, `skills/`, a `Makefile` whose `make check` runs every gate |
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
| Regents | Client address parsing, ENS identity, search titles, canonical host redirect, input parsers; the session authority clean-up | Each is tidier or missing in the template |
| Patchbay | The copy-prompt control | Better than the template's copy text |
| Techtree | Its strict content security policy | The template sets none |

Done 2026-09-27: what came in, what was left out and why is in `docs/donor-queue.md`.

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
| Techtree | Far | After its v0.3.0 release: JavaScript to TypeScript; a full `mix precommit`; remove the stale 365-line `platform/AGENTS.md` and the tracked `.beads/` folder; drop the alias token layer; its commands move into `regents-cli` |

Each site's list goes into its `docs/backlogs/<site>.md` as small steps, each one
shippable and checked in a browser.

## Stage 3: keep them in step

- A change to a shared part is made in the template, then listed on every site's
  backlog.
- A short script in the template compares each site's copies of shared files with
  the template's and lists the differences, so drift is visible rather than guessed.

Done 2026-09-27: `make drift` (`scripts/drift.sh`) is that script.

Motion kit additions KeyFleet keeps as its own (b11ffdf), to weigh for the kit when a
second site needs one; until then each stays a KeyFleet difference:

1. Drawers and panels move when they become visible (a watcher in `slides.ts`) rather
   than on the press, so drawers opened by LiveView commands, or by another control
   such as "Get a key", move too. The template's own drawer opens from its page script
   before the press reaches the document, so its press-time step is right for it.
2. Drawers that come in from the right.
3. A menu opened by a button rather than a summary element pops.
4. New items arriving in a chosen list (`Arrivals`).
5. A number roll for figures with units and decimals ("12.5 USDC").
6. A refusal shake and a first-scroll cascade on live pages.

The options and recommendations behind each decision are in this file's history.
