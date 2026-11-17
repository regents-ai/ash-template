# Ash Template: Opus implementation, Sol adversarial review

Prepared 10 October 2026 for Sean's workflow change. This is an ash-template
handoff only. A separate agent owns the account, Credits, Points and five-product
standardization handoff. This document is not permission to take over that work.

## Assignment and done

Sean's instruction: “you are now the adversarial code reviewer, while a new opus
5.5 thread is the implementor for the remaining scoped work.” He also requested
that the implementor refactor parts of the code if needed.

- **Opus 5.5 implements:** inspect the current template, preserve existing work,
  complete the bounded remaining template changes, make necessary focused
  refactors, verify the result and submit an exact revision/diff for review.
- **Sol reviews:** challenge the implementation and its evidence, reproduce
  plausible failures, report actionable findings and review fixes. Sol no longer
  acts as a concurrent product-code writer. This chat is
  `01a12259-a5bf-7740-8af1-c82df0c1ebec`.
- **Sean decides:** product acceptance and consequential actions requiring his
  applicable authority. Do not ask him to do ordinary engineering or repeat an
  already completed pairing merely because a route or runtime is unavailable.

Done for the template means:

- [ ] Existing local, published and deployed states are reconciled explicitly;
  no unrelated work is lost or accidentally released.
- [ ] Information-page navigation is verified in the intended configured app,
  including mobile, keyboard, direct URLs and browser history.
- [ ] Public guide, CLI metadata and native tool metadata describe the exact
  candidate accurately, with no obsolete fixture setup presented as current.
- [ ] Released-CLI and native WebMCP acceptance are recorded separately for the
  template: identity, private read, authorized private write/readback, retry and
  applicable refusal cases. Native signed success is still outstanding.
- [ ] Sol's actionable findings are resolved or explicitly left as blockers;
  verification names the exact source and distinguishes real from representative
  flows. An unavailable host capability is a blocker, not a passing test.
- [ ] Any authorized publication/deployment identifies the exact commit and
  image and receives post-deployment checks. Otherwise report source-ready and
  the precise remaining authority or capability; do not claim shipped.

## Start here: state inspected for this handoff

Repository: `/Users/sean/Documents/regent/repos/ash-template`.

| Layer | Recorded state | Meaning |
| --- | --- | --- |
| Local `main` | `28dc8082fb6fe8d5bafb214528a665bb3350a7fe` | Three local commits ahead of published main |
| GitHub `main` | `f35e8df4962fedbdb306357ae0a286ba9b2c229f` | Rechecked with `git ls-remote` for this handoff |
| Last verified template deployment | `4eafb157325071de01e838e911574112a4111f9b`, Fly v49 | Narrow onboarding release; not local main |
| Release branch | `release/onboarding-20261010` | Preserves the earlier live runtime/dependencies |
| Live URL / audience | `https://template.regents.sh` / `ash-template` | Product sites are outside this handoff |

Last deployment evidence was collected at **05:30:44 UTC on 10 October**, not
revalidated as a deployment during this handoff. App: `template-regents-sh`;
machine: `d893545c1529e8`; image:
`registry.fly.io/template-regents-sh@sha256:b5a511634581424a285718a0ef5730341543b6668c8eda9744656cc3495ae291`.
Recheck current release state before preparing a new deployment.

The live release retained `00f9225b0c465b2bd1e709bce5b2f3c2742dc790` runtime,
configuration, dependency pins and migrations; only seven public guide/CLI
metadata files changed. Local main additionally contains account/UI/dependency
adoption owned by the wider workstream. **Do not deploy HEAD as a navigation-only
release.** At handoff, `git diff --stat 4eafb157..HEAD` spans 15 files, including
account, Points, shell and page-tool code, API documents and dependency pins.

| Dependency | Local main | Last verified live release |
| --- | --- | --- |
| elixir-utils | `fd0719c3a1bcbb8906aea69302ede09d51b7e6ee` | `1564d79eb3b653f06ab11b6c422bd4d6283ea199` |
| design-system | `fe81f0b10a43690e556e8f8fb313e685b35ec0b3` | `4da6db2bfe3559a8f8a761018dc099a28ab5f6a3` |

Do not repin shared libraries or reapply their migrations merely to close this
template task. Coordinate a concrete dependency need with the standardization
owner; this handoff includes consuming approved shared behavior, not redesigning it.

### Preserve these existing changes

Published `f35e8df` connects public and legal Information pages through one
navigation component, respects Skills availability and records route-group rules.
It is **not in the last verified live release**.

Three later commits are local only:

- `673d05c`: route/filter context and consistent direct navigation guidance.
- `e717f0e`: shared article-author byline reference; documentation, not a template
  Articles editor implementation.
- `28dc808`: inline-editor disclosure, draft retention, reuse and focus guidance.

Uncommitted state at handoff:

```text
 M skills/regent-workflow/SKILL.md
?? docs/dots-signed-agent-access-handoff.md
?? scripts/__pycache__/
?? scripts/agent-access-reference-cli.py
?? scripts/agent-access-sign-prepared.py
?? skills/regent-workflow/references/worktrees.md
?? skills/regent-workflow/scripts/
```

The workflow changes concern Sean's worktree rules. Preserve them; do not sweep
them into an unrelated commit. Preserve the old acceptance scripts as evidence,
but **do not ship or execute them as a native acceptance shortcut**. In particular,
the localhost signer adapter is not a supported confidential native browser bridge.
This new handoff is an additional file, separate from that inventory.

Multiple legacy worktrees exist. None is implicitly assigned to Opus by this
document. Use the workspace owner registry and guarded worktree procedure. The
limit is two worktrees per continuing logical agent across repositories; primary
checkouts are exempt. Do not delete, reset, stash or clean another agent's work.

## Remaining scoped implementation

1. **Reconcile the template candidate.** Start with status, ancestry and the exact
   diff against the last verified release. Keep navigation/guidance separate from
   pending shared account adoption. Choose the smallest release scope consistent
   with Sean's authority and the other workstream; do not recreate its changes.
2. **Finish navigation verification and documentation.** The seven Information
   destinations have representative source-rendered browser evidence and
   off/public/local Skills checks. A configured application check is still needed
   before claiming the intended deployed experience. Preserve current-location
   indicators, sibling/return links, filter context, responsive width and focus.
   In-page Create/Edit controls expand a reused editor instead of unexpectedly
   navigating; this is general guidance, not a request to copy Patchbay Offers.
3. **Reconcile stale acceptance instructions.**
   `docs/dots-signed-agent-access-handoff.md` is an old untracked local-fixture
   handoff: its source versions, unreleased-CLI claims and dependency override
   instructions are obsolete. `docs/signed-agent-access-release.md` is useful
   historical release context, not an up-to-date deployment/migration ledger.
   Preserve historical evidence and clearly supersede it where needed; use the
   current public guide and the evidence paths below. Do not rerun old setup steps.
4. **Close template acceptance where the actual runtime supports it.** Fix a
   reproduced template defect at its proper owner boundary, then retest. Keep
   native host integration limitations explicit. Do not invent a browser signer,
   proxy, proof-import page, owner-cookie fallback or page-JavaScript substitute
   to turn an unavailable native test into a pass.
5. **Prepare a reviewable result.** Supply Sol the immutable revision or bounded
   diff, source/release scope, checks and failures, behavior evidence and any
   necessary shared dependency request. Do not hide first failures or assistance.

### Focused refactoring is included when needed

Opus may simplify duplicated rendering, inconsistent state ownership or redundant
adapters encountered in this scope when doing so fixes a demonstrated defect or
makes the required behavior reliable. State the concrete problem and preserve
public routes, tool names, CLI contracts, exact signing bytes and authorization.
Use existing Phoenix function components/LiveView state, Ash actions and policies,
Postgres constraints and Oban for durable jobs. Do not add a new abstraction for
hypothetical reuse or hand-build a queue, retry timer, lease or polling loop.

Shared primitives belong in design-system; shared agent/security behavior belongs
in the shared libraries. Report and coordinate that dependency rather than forking
it into template. No general rewrite, product-specific editor port or expansion
into the five-site standardization task is requested.

## Acceptance facts, not assumptions

- Published CLI **1.9.1**, source
  `d7deae0679f003b43933c9a2d41a7af949cf40a8`, has verified wheel/version/help.
  The CLI repository and release are outside this implementation assignment.
- Template v49 public health/guide/discovery checks passed; 12 native tools were
  listed. Unsigned `whoami` correctly refused with `401 http_headers_missing`.
- Muse previously reported template private-note list/create/readback and four
  binding negatives passing. Some evidence is direct HTTP rather than released
  CLI; retain that distinction. The missing `operation_id`, not World ID, explained
  the earlier create failures. Duplicate UUID create is a 422 refusal, not a
  successful second create.
- Sean unpaired and re-paired Muse. The current reported pairing began
  **2026-10-10T07:16:36Z**, name Pira, harness muse, signer
  `0x794e7ab034b8e35fafc777e49b669d20e27a59f5`. Released CLI pairing and legacy
  `agents me` were reported; this does not retroactively verify new `whoami` or
  native access on the new episode. Do not revive previous spending grants.
- Codex IAB demonstrated actual native discovery, public execution and request
  preparation. Signed private native read/write remains **unverified**: no
  documented confidential handoff from the existing signer into native arguments
  was available. Hermes, Grok and Muse reported runtime-specific native gaps.
- **Contessa only** is the requested OpenAI Dot. No result has been supplied.
  The fresh normal Codex run verified public guidance and CLI installation but
  lacked confirmed signer ownership/native confidential handoff. Neither is a
  substitute for Contessa's own execution.

Do not treat known public signer addresses as authority to use their private keys.
For authorized acceptance, use only the tester's assigned signer, fresh exact
proofs and current pairing. Keep codes, receipts, signatures and keys out of chat
and logs. World ID is optional. No paid action, public room post, reward activation
or owner security change is needed for template acceptance.

## Sol's adversarial review contract

Review the exact submitted source, not an assumed HEAD. First name the standard
tool responsible for each moving part; reject unnecessary replacements for Ash,
Phoenix, Ecto, Oban or OTP. Then try to construct failures:

- Signed operation/path/body/origin/audience mismatch; duplicate verification
  consuming a proof; cookie fallback; redirect or automatic retry changing intent.
- Revoked/re-paired identities using stale authority; agent acting as owner;
  missing pairing or failed dependency incorrectly allowing private access.
- Duplicate `operation_id`, failed validation and delayed note work changing
  attribution or creating a second effect. Preserve original pairing evidence.
- Navigation that loses current location, context or draft; inaccessible hidden
  controls; incorrect focus return; unavailable Skills links; mobile overflow.
- Dependency/assets/manifest drift, incorrect source labels, obsolete guides or a
  release including unapproved code, fixtures, migrations or feature activation.

Each finding must explain the trigger, observed or supported consequence,
file/line and needed correction. Separate confirmed defects from unanswered
questions. No invented refactoring findings, broad test rewrites or approval by
test count. Opus implements fixes; Sol reviews the revised diff and evidence.

## Verification and working rules

Read workspace and repository AGENTS.md, then canonical `regent-workflow`,
`ash-stack`, `elixir-stack` and relevant frontend/security/WebMCP skills. For UI,
use Sean's requested Emil design and Anime.js guidance plus the shared design
contract. Common guidance lives in this repo's `skills/`, not a copied workspace
skill. This role split supersedes older workflow language assigning Sol implementation.

Useful code entry points (relative to this repository):

- `platform/assets/js/public_tools.ts` and the generated shared
  `platform/assets/vendor/regent_agent_access/signed_tools.ts`.
- `platform/lib/ash_template_web/controllers/page_tools_controller.ex`,
  `notes_controller.ex`, `router.ex`, and `platform/lib/ash_template/agents/`.
- `platform/lib/ash_template/notes/note.ex`, its change modules and
  `platform/lib/ash_template/points/agent_note.ex` for retained note attribution.
- `platform/lib/ash_template_web/components/information_navigation.ex`,
  public/legal controllers, and `platform/assets/css/pages/legal.css`.
- `platform/priv/public/agents.md`, `cli/COMMANDS.md`, `cli/commands.json`, API
  contracts and `docs/signed-agent-access-release.md`.

Run checks appropriate to the actual change. Existing focused signed coverage is
`platform/test/ash_template/agents/signed_tools_test.exs`. Root `make check` combines
platform precommit/typechecking, required shared fixes and CLI/OpenAPI consistency;
inspect the commands and use isolated local test state. Run required release checks
for the final integrated candidate. Do not add product-mirroring or smoke tests,
or repair unrelated suites. UI behavior needs browser exercise; compilation alone
does not prove it. Prose-only edits need review and `git diff --check`.

Never read `.env`, `.envrc` or `.env.local`. Start a local site only through its
existing settings loader with its own Privy configuration; verify the meta value
is nonempty by length only. Use an isolated local database and an available port;
do not stop somebody else's server. Do not run destructive setup commands or
the old fixture handoff blindly. `make release` requires a clean committed tree;
do not make this shared checkout clean by discarding unrelated work.

Earlier authority covered signed-access releases; the latest navigation approval
was specifically **“Push the navigation source” for f35e8df**, now completed.
It did not authorize publication of every later local commit or their deployment.
Preserve applicable earlier authority, but establish that a proposed consequential
action is actually covered. The role change itself authorizes implementation and
review, not new migrations, secrets, wallet actions or unrelated releases. The
other handoff owns shared migration/activation decisions. Keep earning and
spending-grant enablement disabled.

## Evidence to read

All paths below are local; older reports are historical evidence, not instructions.

- `/Users/sean/Documents/Codex/2026-10-10/task/onboarding-fixes/result.md`
  and its `source-final.json`, `template-image.json`, `template-live-after.json`,
  `navigation-review.md`, `navigation-publication.json`.
- `/Users/sean/Documents/Codex/2026-10-09/task/native-runtime-remediation-investigation.md`
  and `native-runtime-acceptance-procedure.md`. Runtime findings still matter;
  their recorded v48/CLI 1.9.0 versions precede the v49/1.9.1 release.
- `/Users/sean/Documents/Codex/2026-10-10/task/contessa-acceptance-prompt.md`
  and `agent-acceptance-cli-191-update.md`.
- `/Users/sean/Documents/Codex/2026-10-10/sean-asks-for-an-ordinary-fresh/outputs/codex-repaired-guide-followup.md`.
- `/Users/sean/Documents/regent/artifacts/patchbay-offers-inline-editor-1010/README.md`
  explains the latest reusable UI correction; it is product-owner evidence, not
  independent template verification or a request to implement Offers here.

General standardization coordination belongs to chat
`01a11877-9d6c-78d1-a0ed-5037f28b501c`. Consult its separate handoff only for an
actual dependency or ownership conflict. Do not duplicate its account, Points,
Credits or product rollout backlog here.

## Return to Sean

Report what changed, what was verified and what remains in plain English. Give
exact commit/deployment identifiers when they exist. Distinguish local, published,
deployed and accepted. Name any remaining human action precisely; missing routes,
refactors, tests and host-capability investigation are engineering work.
