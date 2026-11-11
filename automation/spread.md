# Spread: the daily outbound job

You run once a day, at 11:00 UTC, an hour after the Harvest job, as a scheduled agent
with no memory of earlier runs. Your job: compare each Regent site with ash-template
and open one pull request per site that brings it up to the template's better parts,
within the rule Sean set for what may go before his sign-off. Follow this file from
ash-template's main branch exactly; a change to how you work is a change to this file,
reviewed like code.

The sites are keyfleet, regents, autolaunch, patchbay and techtree, each its own
repository at `github.com/regents-ai/<site>`.

## What may go to a site

Sean, 11 Nov (decision 2a): before Sean signs off, Spread may carry tooling only to
sites: check, release and deploy scripts, security fixes, library bug-fix pins,
toolchain versions and shared skills. Anything a visitor sees waits for his sign-off of
the template version, recorded in a rollout file in `control/rollouts/`.

In practice:

- **May go now:** the `Makefile`; `scripts/*.sh`; `platform/rel/overlays/bin/*`;
  `platform/Dockerfile` and `platform/fly.toml`; `platform/.tool-versions`;
  `platform/.formatter.exs`, `platform/.credo.exs` and `platform/.sobelow-conf`; the
  aliases in `platform/mix.exs`; every fix in `security/required-fixes.json`; a
  library pin whose new commits are bug or security fixes; and the shared skills
  under `skills/`.
- **Waits for a rollout file:** everything else, including every file under
  `platform/lib/` and `platform/assets/`, `platform/config/`, the homepage files,
  and a library pin whose new commits change what a page shows. When unsure, it
  waits.
- **A signed-off change** goes out when a file in `control/rollouts/` records Sean's
  sign-off (its "Sean's sign-off" line) and names the template commits (its
  "Template" line). It goes to every site in the same run, except a site whose row in
  that file already has a commit.

## What the run needs

- **Repositories**, cloned side by side in one folder (call it `<repos>`), each under
  its repository's name: `ash-template`, `keyfleet`, `regents`, `autolaunch`,
  `patchbay`, `techtree`, and `control` (Regent's private coordination repository,
  `github.com/regents-ai/control`).
- **Tools:** git, jq, perl, curl, patch and gh. `gh auth status` must show an account
  that can open pull requests on the five sites and push to control's main branch.
  `scripts/pins.sh` also clones four libraries from github.com, and `scripts/drift.sh`
  reads https://template.regents.sh and https://regents.sh.
- **The Agent tool**, for the reviewer.

If anything here is missing, open nothing: write the summary (see "Records") with the
missing piece as its first line, and stop.

## Mode

Read the Spread row in the "Mode" table of the ledger,
`<repos>/control/automation/harvest.md`.

- **dry run**: do every step up to opening pull requests, but push nothing and open
  nothing. Prepare each site's branch locally, run the reviewer on its local diff, and
  write everything you would have opened to
  `<repos>/control/automation/dry-runs/<date>-spread.md`: for each site its branch,
  title, body, the files it changes with their diff stat, and the reviewer's findings;
  then the verdict rows and the summaries you would have written. Push that one file
  to control (see "Records"). Leave the ledger and the mailboxes untouched.
- **live**: everything below.

`<date>` is today in UTC, `date -u +%F`. Only the template lane lead changes the Mode
table.

## Steps

1. **Start from main.** In `<repos>/ash-template` and each site's clone:
   `git fetch -q origin` and `git switch -q --detach origin/main`.
2. **Close what is stale.** For each site, list its open spread pull requests:
   `gh pr list --repo regents-ai/<site> --state open --json number,url,headRefName,createdAt --jq '.[] | select(.headRefName | startswith("spread/"))'`.
   Close each one opened seven or more days ago:
   `gh pr close <number> --repo regents-ai/<site> --comment "<note>"`, where the note
   says it was open seven days with no merge, that its branch stays, and that
   reopening it picks the work up again. Never pass `--delete-branch`.
3. **Read the facts**, from `<repos>/ash-template`, into a folder of your own outside
   the repositories (`<out>`):
   - `scripts/drift.sh > <out>/drift.json`: for each site, each shared, build and
     homepage file as `same`, `differs`, `missing` or `not_used`, with the path of
     each difference's diff, and for regents the live homepages compared.
   - `scripts/pins.sh > <out>/pins.json`: each site's library pins and how far each is
     behind the template's pin and the library's main.
   - `security/required-fixes.json`: the fixes every site must carry. A `git` fix is a
     commit the pins of its `apps` must contain (true when
     `git --git-dir=<library copy> merge-base --is-ancestor <fix> <pin>` succeeds; the
     library copies are below); a `hex` fix is a version requirement the site's
     locked version of `package` must meet.
   - The rollout files in `<repos>/control/rollouts/`.
   - The ledger's `drift` rows whose "Pull request" cell is `—`: Harvest found the
     site changed a shared piece for the worse, so the template's version goes back.
   Each script's opening comment describes its fields. If one fails, open nothing:
   write the summary with its error and stop.
4. **Judge each difference** (`differs` or `missing` file, pin behind the template's,
   missing required fix):
   - **The template's is better:** carry it, if "What may go to a site" allows it now.
     If it waits, note it in the summary and leave it.
   - **The site keeps its own on purpose:** leave it. A file the site has no use for
     shows as `not_used`, and a file kept at its own path is read there already; if a
     site's choice is deliberate but not yet listed, name it in the summary so the
     template chief adds it to `scripts/shared-files.sh`.
   - **The site is ahead:** append an `ahead` row to the ledger, for Harvest to judge.
5. **Make each site's branch.** At most one pull request per site per run. If the site
   already has an open spread pull request, add today's changes to its branch and say
   so in a comment, instead of opening another. Otherwise:
   - **Branch** `spread/<date>` from the site's `origin/main`.
   - **Files.** Carry only the template's better pieces and keep what is the site's
     own (its own targets, routes, names and words). Each difference's diff runs from
     the template's version, with the site's names, to the site's: apply the parts
     you carry by hand, or, when the whole template file is better, reverse all of it:
     `patch -R --no-backup-if-mismatch <repos>/<site>/<site_path> < <repos>/ash-template/<diff>`.
     A `missing` file is the template's with the site's names applied:
     `perl -pe 's/ash_template/<app>/g; s/AshTemplate/<module>/g; s/ashTemplate/<camel>/g; s/ASH_TEMPLATE/<UPPER>/g; s/ash-template/<kebab>/g' <template path> > <site path>`,
     where the camel name is the module with a lower-case first letter, UPPER the app
     in capitals and kebab the app with `-` for `_`.
   - **Pins.** For a git library pin, change the commit in `platform/mix.exs` and on
     the library's line in `platform/mix.lock` together. Read what the move brings
     first, in the library copies pins.sh keeps, one per library:
     `git --git-dir=<repos>/ash-template/platform/_build/drift/libraries/<library>.git log --oneline <pin>..<target>`.
     Never edit a Hex package's lock line (its checksums come from Hex): list the
     bump in the body for the chief instead.
   - **Docs:** a `CHANGELOG.md` entry naming the template commit each piece comes from.
   - **Commit** in small plain-English commits ending with the attribution lines your
     session gives you, and push: `git push -u origin spread/<date>`.
6. **Open it** with
   `gh pr create --repo regents-ai/<site> --base main --head spread/<date> --title "<title>" --body-file <file>`.
   The body lists each piece with the template commit it comes from, any rollout file
   it follows, what the site keeps as its own, and these lines:
   - "Still needed before merge: the <site> chief's `make check` on the Mac (GitHub
     checks do not run on this repository yet)."
   - When a pin moved: "The lock was edited by hand: run `cd platform && mix deps.get`
     before the check and commit any lock change it makes." List any Hex bumps as
     `mix deps.update <package>` steps.
   - **A release in progress.** Read the site's mailbox in `<repos>/control/coordination/`
     (`keyfleet.md`, `regents-sh.md`, `autolaunch.md`, `patchbay.md`, `techtree.md`).
     If its newest heading with "CLAIM" has no later heading with "RELEASED", add:
     "Release slot claimed: <that heading>. Merge after it posts RELEASED."

   End the body with the attribution lines your session gives you.
   **Protected areas:** if the branch touches sign-in, sessions or accounts, secrets,
   wallets or on-chain steps, payments or money, staking or claims, production data,
   any migration or resource snapshot, contracts, or the privacy page's wording, open
   it with `--draft`, start its title with "Waits for Sean: ", and say in the body
   which protected area it touches. When unsure, treat it as protected.
7. **Review each pull request** right after opening it (see "Reviewer"), then fix what
   the reviewer found in one round.
8. **Record** the run (see "Records").

## Reviewer

Start a fresh agent with the Agent tool for each pull request, with no part of your
own reasoning, and this brief with the pull request's address and the site filled in:

```
Review pull request <url> on regents-ai/<site>, which brings parts of the ash-template
repository to the <site> site. Read its diff (gh pr diff <url>), its body, and the
site's AGENTS.md. Check, and report only real problems:
1. Every change is either tooling (check, release and deploy scripts, security
   fixes, library bug-fix pins, toolchain versions, shared skills) or follows a file
   in control/rollouts/ that records Sean's sign-off. Anything a visitor would see
   without such a file is a problem.
2. The template's names are all turned into the site's (no ash_template, AshTemplate,
   ash-template or "Ash Template" left).
3. Nothing the site keeps as its own was overwritten: its own make targets, routes,
   names, words and settings.
4. No second copy, fallback, compatibility branch, shim or alias was added.
5. CHANGELOG.md has an entry naming the template commits.
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

1. **The ledger**, `<repos>/control/automation/harvest.md`: append one row to
   "Verdicts" for each `ahead` difference:
   `| <date> | <site> | <site's main commit, in full> | ahead | <file> | — | <one short note> |`.
   Set the "Pull request" cell of each `drift` row you carried to your pull request's
   address. Change nothing else in an earlier row.
2. **Each site's chief**, for each site with a new or updated pull request, appended at
   the end of its mailbox in `<repos>/control/coordination/`:

   ```
   ### <date -u +%Y-%m-%dT%H:%MZ> · Spread job (cloud) → <site> chief · spread <date>
   - Pull request: <address and title>
   - Carries: <the pieces, in a few words>; needs your `make check` before merge
   - Waits: <pieces waiting for a rollout file or for Sean, or "none">
   ```

3. **The template chief**, appended at the end of
   `<repos>/control/coordination/ash-template.md`:

   ```
   ### <date -u +%Y-%m-%dT%H:%MZ> · Spread job (cloud) → ash-template chief · spread <date>
   - Opened: <each site's pull request address, or "none">
   - Waiting: <pieces held for a rollout file, site choices to list in shared-files.sh>
   - Needs: <drafts waiting for Sean, failures, or "none">
   ```

4. **Push**, in `<repos>/control`: commit only the files you changed in one commit,
   then `git push origin HEAD:main`. If the push is refused,
   `git pull --no-rebase origin main` and push again.

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
  and the mailboxes named above.
