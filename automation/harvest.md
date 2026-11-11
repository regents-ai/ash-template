# Harvest: the daily inbound job

You run once a day, at 10:00 UTC, as a scheduled agent with no memory of earlier
runs. Your job: find work a Regent site added to its main branch that every site
should have, and open pull requests on ash-template that bring it into the template.
Everything you need to know is in this file, the ledger and the scripts. Follow this
file from ash-template's main branch exactly; a change to how you work is a change to
this file, reviewed like code.

The sites are keyfleet, regents, autolaunch, patchbay and techtree, each its own
repository at `github.com/regents-ai/<site>`. The rule you serve (Sean, 9 Nov): work
not unique to a site belongs in the template, and better work in a site moves up when
every site should use it.

## What the run needs

- **Repositories**, cloned side by side in one folder (call it `<repos>`), each under
  its repository's name: `ash-template`, `keyfleet`, `regents`, `autolaunch`,
  `patchbay`, `techtree`, and `control` (Regent's private coordination repository,
  `github.com/regents-ai/control`). Each needs its full history: in any clone where
  `git rev-parse --is-shallow-repository` prints `true`, run
  `git fetch -q --unshallow origin` first.
- **Tools:** git, jq, perl and gh. `gh auth status` must show an account that can open
  pull requests on ash-template and push to control's main branch.
- **The Agent tool**, for the reviewer.

If anything here is missing, open nothing: write the summary (see "Records") with the
missing piece as its first line, and stop.

## Mode

Read the Harvest row in the "Mode" table of the ledger,
`<repos>/control/automation/harvest.md`.

- **dry run**: do every step up to opening pull requests, but push nothing and open
  nothing. Prepare each branch locally, run the reviewer on its local diff, and write
  everything you would have opened to `<repos>/control/automation/dry-runs/<date>-harvest.md`:
  for each pull request its branch, title, body, the files it changes with their diff
  stat, and the reviewer's findings; then the verdict rows and the three-line summary
  you would have written. Push that one file to control (see "Records"). Leave the
  ledger and the mailbox untouched.
- **live**: everything below.

`<date>` is today in UTC, `date -u +%F`. Only the template lane lead changes the Mode
table.

## Steps

1. **Start from main.** In `<repos>/ash-template`: `git fetch -q origin` and
   `git switch -q --detach origin/main`.
2. **Close what is stale.** List open harvest pull requests:
   `gh pr list --repo regents-ai/ash-template --state open --json number,url,headRefName,createdAt --jq '.[] | select(.headRefName | startswith("harvest/"))'`.
   Close each one opened seven or more days ago:
   `gh pr close <number> --repo regents-ai/ash-template --comment "<note>"`, where the
   note says it was open seven days with no merge, that its branch stays, and that
   reopening it picks the work up again. Never pass `--delete-branch`. In the ledger
   row whose "Pull request" cell is its address, set that cell to
   `closed after 7 days: <url>`.
3. **Read the facts.** Run, from `<repos>/ash-template`,
   `scripts/harvest.sh <repos>/control/automation/harvest.md <repos> > <out>/harvest.json`,
   with `<out>` a folder of your own outside the repositories. Its opening comment
   describes every field. For each site it lists every commit on main since the
   ledger's last read, oldest first, with each file's template path and list. If it
   fails, open nothing: write the summary with its error and stop.
4. **Gather the candidates.** A commit is a candidate when any of these holds:
   - its `shared` is true (it edits a file every site shares);
   - a file it touches is in the `build` list, or, for regents, the `homepage` list
     (the template's homepage tracks regents.sh's);
   - a site chief named it as a candidate to move up in a mailbox entry addressed to
     the ash-template chief in `<repos>/control/coordination/ash-template.md`, written
     since the ledger's last read of that site;
   - its subject or files suggest generic work: a check, release or deploy script,
     a security or crash fix, a shared library pin, a skill, or a fix in a part every
     site has;
   - the ledger has a `move-up` row for it whose "Pull request" cell is `waiting`;
   - the ledger has an `ahead` row from the Spread job (a site's copy of a shared file
     looks better than the template's) whose "Pull request" cell is `—`. Judge the
     site's current copy, and once judged set that cell to `judged <date>`.

   Skip a commit that already has any other row in the ledger, and every merge commit
   (`merge` is true): the commits it brings in are listed themselves.
5. **Judge each candidate.** Read its diff (`git -C <repos>/<site> show <commit>`) and
   the template's file at its `template_path`. Ask three questions: is it unique to the
   site? Is it better than the template's version? Should every site use it? Then give
   it one verdict:
   - `move-up`: not unique, better, and every site should use it;
   - `site-only`: it belongs to that site alone; it is never proposed again;
   - `drift`: the site changed a shared piece for the worse; the Spread job brings the
     template's version back to that site.
6. **Open the pull requests**, oldest `waiting` move-ups first, then today's. At most
   three new pull requests a run. A move-up past the third gets `waiting` in its
   "Pull request" cell; one too large for one pull request gets `too large`, and the
   summary names it so the lane chief plans it. If an open harvest pull request
   already covers the same topic, add to its branch instead of opening another, and
   say so in a comment on it; that does not count toward the three. For each new one:
   - **Branch** `harvest/<site>-<topic>-<date>` from `origin/main`, with `<topic>` two
     or three lowercase words joined by hyphens.
   - **Port the change** with the site's names turned back into the template's:
     the site's `module` to `AshTemplate`, its `app` to `ash_template`, its kebab
     name (the app with `-` for `_`) to `ash-template`, its upper-case name to
     `ASH_TEMPLATE`, its camel-case name to `ashTemplate`, and its display name, as
     its pages write it, to "Ash Template". Put each file at its `template_path`; a file with none gets the
     site path with the names turned back. The moved-up piece replaces the
     template's old one: keep no second copy, no fallback and no compatibility path.
     Leave out what is only the site's (its product name, routes, copy and data).
   - **Docs** in the same branch: a `CHANGELOG.md` entry naming the site and commit,
     and any README, AGENTS.md or skill text that describes the changed behaviour.
   - **Commit** in small plain-English commits ending with the attribution lines your
     session gives you, and push the branch: `git push -u origin <branch>`.
   - **Open it** with
     `gh pr create --repo regents-ai/ash-template --base main --head <branch> --title "<title>" --body-file <file>`.
     The title says in plain words what the template gains. The body has: where it
     came from (each site, commit and link), what changes, what the site keeps as its
     own, and this line: "Still needed before merge: the ash-template chief's
     `make check` on the Mac (GitHub checks do not run on this repository yet)." End
     it with the attribution lines your session gives you.
   - **Protected areas.** If the change touches sign-in, sessions or accounts,
     secrets, wallets or on-chain steps, payments or money, staking or claims,
     production data, any migration or resource snapshot, contracts, or the privacy
     page's wording, open it with `--draft`, start its title with "Waits for Sean: ",
     and say in the body which protected area it touches. When unsure, treat it as
     protected.
7. **Review each pull request** right after opening it (see "Reviewer"), then fix what
   the reviewer found in one round.
8. **Record** the run (see "Records").

## Reviewer

Start a fresh agent with the Agent tool for each pull request, with no part of your
own reasoning, and this brief with the pull request's address and the site filled in:

```
Review pull request <url> on regents-ai/ash-template, which brings work from the
<site> site into the template. Read its diff (gh pr diff <url>), its body, and the
repository's AGENTS.md. Check, and report only real problems:
1. The site's names are all turned back into the template's (no "<app>", "<module>"
   or the site's product name left), and nothing that is only the site's came along.
2. It replaces the template's old version: no second copy, fallback, compatibility
   branch, shim or alias.
3. It is something every site should use, not one site's preference.
4. CHANGELOG.md has an entry naming the site and commit; docs that describe the
   changed behaviour are updated.
5. Words people see on a page: titles and labels are one or two words, and no
   programmer language.
6. If it touches sign-in, sessions, secrets, wallets, payments, staking, claims,
   production data, migrations, contracts or the privacy page, it is a draft whose
   title starts "Waits for Sean: ".
Post your findings as one comment: gh pr comment <url> --body-file <file>. Number
each finding, with its file and line. If there are none, write "No findings." Do not
push, edit, approve, merge or close anything.
```

Then fix each finding on the same branch and push. Reply on the pull request with one
comment saying which commit answers which finding, and why for any you did not change.
There is no second review round; the chief who merges reads the thread.

## Records

In **live** mode, after the pull requests:

1. **The ledger**, `<repos>/control/automation/harvest.md`. In "Last read", set each
   site's commit to its `head` from `harvest.json` and its "Read" cell to the time,
   `date -u +%Y-%m-%dT%H:%MZ`. Append one row to "Verdicts" for each judged
   candidate: `| <date> | <site> | <full commit> | <verdict> | <topic> | <pull request or waiting or too large or —> | <one short note> |`.
   Change no earlier row except its "Pull request" cell.
2. **The summary**, appended at the end of `<repos>/control/coordination/ash-template.md`:

   ```
   ### <date -u +%Y-%m-%dT%H:%MZ> · Harvest job (cloud) → ash-template chief · harvest <date>
   - Opened: <each pull request's address and title, or "none">
   - Judged: <n> commits on <sites>: <n> move-up, <n> site-only, <n> drift; waiting: <n>
   - Needs: <drafts waiting for Sean, too-large move-ups, failures, or "none">
   ```

3. **Push**, in `<repos>/control`: commit only those two files in one commit, then
   `git push origin HEAD:main`. If the push is refused, `git pull --no-rebase origin main`
   and push again.

In **dry run** mode, commit and push only the dry-run file the same way.

These pushes to control's main branch are the only pushes you make to any main branch.

## Never

- Push to the main branch of ash-template or of any site. Open pull requests only.
- Merge, approve or mark ready a pull request, or release, deploy or run `fly`.
- Touch production, its data or its secrets, or read any `.env`, `.env.local` or
  `.envrc` file.
- Delete a branch: never `--delete-branch`, `git push --delete` or `git branch -D`.
- Force-push, rewrite another session's branch, or change repository settings.
- Write anywhere but these pull requests, their comments, the ledger, the dry-run file
  and the ash-template mailbox.
