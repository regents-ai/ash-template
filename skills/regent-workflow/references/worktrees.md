# Two worktrees per continuing agent

Work in an assigned existing checkout whenever possible. Primary repositories are
exempt. Implementation, review and dependency checkouts count together across all
repositories; restarting, changing models or naming a new task does not reset ownership.
Sean controls owner registration. Do not create clones or exports to evade the rule.

Sean may record a larger `limit` on one owner for a named purpose; the guard reads it.
The only one so far is `ui-standardization` (UI-3 b, 11 October 2026): two working
checkouts plus one standing update checkout per site for `scripts/regent-ui-update`.

The laptop registry is `/Users/sean/Documents/regent/.agent-worktrees.json`.
Legacy worktrees are grouped conservatively by repository; each group blocks new
creation while above two. Do not invent ownership for historical sessions or edit
the registry to bypass a refusal. Sean may reassign a proved owner explicitly.
The local tool hook binds a session to its first registered owner and refuses an
owner change. Resume with the same owner; a new conversation is not a new quota.

Inspect current ownership:

```sh
python3 /Users/sean/Documents/regent/repos/ash-template/skills/regent-workflow/scripts/worktrees.py list
```

Create only through the guarded command, using your registered owner and an explicit base:

```sh
python3 /Users/sean/Documents/regent/repos/ash-template/skills/regent-workflow/scripts/worktrees.py add \
  --owner keyfleet --repo /Users/sean/Documents/regent/repos/keyfleet \
  --name example --branch feat/example --ref origin/main --dry-run
```

Inspect the dry run, then omit `--dry-run` to create. One operating-system file lock
spans the actual Git count, creation and registration. Failed creation does not
consume a slot. Unknown registrations block creation until reconciled. Ordinary
Git branch and history reads do not need another checkout.

To retire a clean, inactive checkout with no ignored files or dependent checkouts,
use `retire /absolute/path --dry-run`, then omit `--dry-run`. The command refuses
dirty, ignored, active, nested and dependent checkouts and primary repositories,
including shared Git administration directories and borrowed Git objects.
Before actual retirement it creates and verifies a Git recovery bundle under
`backups/agent-worktrees`, including unpublished or detached source tips.
The general guard never forces removal or evicts automatically. Git branches survive removal.
For the founder-approved 9 October cleanup, Git 2.50's required submodule-removal
option is used only for clean, inactive checkouts after verified source and complete
Git administration backups, including recursive contract-library history, and an
independent recovery check. This exception does not permit removing dirty, active,
external or unpreserved work and does not enable forced retirement in the general guard.

For ignored files or older work, use the reviewed cleanup procedure: verified Git
bundle plus verified source archive outside `worktrees`, preserve settings without
reading them, check running processes and dependency references, including nested
`.git` pointers and borrowed Git objects in `objects/info/alternates`, then ordinary Git
removal of an exact path. Preserve nested Git history or retain the checkout.
For retained Keyfleet audit libraries, the 9 October recovery restored independent
Git metadata under `backups/worktree-prune-2026-10-09/git-admin-recovery`.
That directory is a live dependency: keep it at its recorded path until the libraries
are safely relocated. Do not delete or move it as an ordinary disposable backup.
Keep unfinished changes, chain state, databases and release evidence; generated
build output is not a reason to discard source. Do not stop another agent's server.

Local Claude, Codex and Hermes tool hooks can direct normal creation routes through
this command. Hooks are guardrails, not an operating-system sandbox: unrestricted
shells and specialized tools can bypass them, and cloud hosts require their own
installation. Never claim this laptop configuration enforces the cloud limit.
