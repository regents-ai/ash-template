# Release and live checks

The rules are in [regent-workflow](../SKILL.md) ("Release", "Every change proves
itself"); this is the procedure. Read `/Users/sean/Documents/regent/docs/decisions.md`
again before a release.

## Release checklist

1. **Where main and live are.** Read the deployed commit from the site's health endpoint
   before the release and again after it.
2. **Suite against live.** Run the suite and report pass and fail counts beside the live
   commit's counts. A failure live already has gets a named owner before the release
   goes out.
3. **Sites never wait on each other** (Sean, 12 Nov: "I do not want to wait, I want it
   parallelized"). Each site deploys to its own Fly app. The only turns left are these,
   each for something that really is shared:
   - **One deployer per site.** A site's `scripts/deploy.sh` holds
     `/tmp/regent-release-<fly app>.lock` for its whole run, so two deploys of one site
     take turns. Right before pushing a site's main or deploying it, `git fetch origin
     main` in `/Users/sean/Documents/regent/control` and read
     `git show origin/main:coordination/<site>.md | tail -40`: a CLAIM newer than your
     instructions means another thread owns this site's next release; say so and wait
     for its owner. Another site's release or CLAIM never holds yours.
   - **Two production switches at once.** The image build takes no shared lock. The
     switch (`fly deploy --image`: migrations, then a second machine with its own
     connections until the first stops) takes a place on the production database every
     site shares, `/tmp/regent-shared-db-release.lock` if it is free, otherwise
     `/tmp/regent-shared-db-release-2.lock`. The database takes 97 connections, about 64
     to 76 are in use and one switch adds up to 8, so two fit and a third could fill it.
     `scripts/rollback.sh` takes its place as the deploy does; a hand-run `fly deploy`,
     `fly machine restart` or `fly secrets set` without `--stage` takes one the same
     way.
   - **Three full checks at once.** `make check`, `mix precommit` and whole test or
     Playwright suites share the Mac's 48 GB, so each takes one of three places:

     ```bash
     for place in /tmp/regent-cmcp-check.lock /tmp/regent-cmcp-check-2.lock /tmp/regent-cmcp-check-3.lock; do
       lockf -k -s -t 0 "$place" true && break
     done
     MIX_TEST_PARTITION="_$(basename "$PWD" | tr -c 'a-z0-9\n' _)" lockf -k "$place" make check
     ```

     Each run keeps its own worktree, `_build`, `node_modules` and test databases (the
     partition above), and its own browser port: on regents and keyfleet set `PORT`, on
     techtree `TECHTREE_BROWSER_PORT` and `TECHTREE_BROWSER_COPY`, to a free port and the
     partition name; the other sites pick theirs. So checks of different sites, or of
     one site in two worktrees, never meet.

   Always pass `-k` to `lockf`. Never wrap `scripts/deploy.sh` in `lockf`: it takes its
   own locks, and a wrapper on its site lock waits on itself forever.
4. **Push and release only on a passing check**, chained so a failure stops the push:
   `make check && git push origin HEAD:main`. Run the check again when main moved under
   you, on the exact commit the release builds. A failure you believe is old still stops
   the release until you have reproduced it on the live commit and written it in the
   backlog.
5. **Live first, small and reversible** (Sean, 27 Oct: "reducing process and
   accelerating safe but not overengineered code deployment and live testing"). Ship the
   smallest change that works, then test the changed behaviour on the live site,
   read-only, as "Live checks" says. Name the rollback before the release goes out: the
   previous Fly release and image. `scripts/rollback.sh <fly app> <release>` goes back
   to it when its migrations match the live commit's and refuses otherwise, which then
   needs a person; run it with `--dry-run` first to see which.
6. **Sentinel.** Ask Sentinel for a read after every production release, and before a
   protected one. A read is never a reason to hold an ordinary release. Every request
   has one shape: repository, previous released commit, candidate commit, release
   number, migrations (yes or no), protected area (yes or no), who receives the
   verdict. With it goes the evidence: at the top, the commit the checks ran on
   (`git rev-parse HEAD`) and a clean tree; then the behaviour that changed, the
   commands run with their results, and what is not proven.
7. **Changelog, in the deploy step itself.** The public changelog says only what changed
   for people and agents: no release numbers, commits or rollback notes. Those go in the
   release record the site does not show (the template's root `CHANGELOG.md`).
8. **CLI notice.** One notice to the CLI lane per contract change, in one shape: tool or
   route, old shape, new shape, defining commit, live commit.
9. **Holds.** A hold names who lifts it and what the release check looks for.
10. **Release record, straight after.** Once live: read the health endpoint and the logs
    from the release's start (errors, crashes, refusals, real traffic answered), commit
    the record (version, commit, time, what changed, rollback), send Sentinel's
    after-read request, and tell each lane that waits on the release. End the read with
    what has been open for more than an hour, or "none" (4 Nov).

Every site ships `rel/vm.args.eex` with `+sbwt none +sbwtdcpu none +sbwtdio none`, so
idle schedulers sleep instead of spinning; the built release carries it as
`releases/<version>/vm.args`. On Fly's shared CPUs spinning spends the CPU allowance on
no work and makes CPU charts overstate load.

A guard that refuses (the worktree guard, a deploy safety check) ends the attempt: stop
and report what blocked it. Never release from a `git archive` export or a fresh clone.

## Live checks

Sean, 28 Oct: the Mac checks a live site "the way an agent does, through the CLI as a
paired agent and WebMCP in the headless browser, and those go on the allowlist; raw
curl is dropped." This holds on all five sites and the template, for a Mac session, a
Claude Projects thread and every helper either starts.

- **The CLI as a paired agent.** The regents CLI, or the site's SIWA client
  (`uv run siwa_agent.py request`), run from the agent's own folder with its own signer
  and pairing. A check reads: `whoami`, lists and reads.
- **WebMCP in headless Chromium.** Open the live page in Playwright's Chromium, list the
  tools the page registers, call its public reads, and call signed reads through
  `prepare_agent_request` and the SIWA client. The page walk at 390 and 1280 wide, the
  health page and `/capabilities.json` are read in the same browser.
- **Claude threads use the connector.** Once a site's connector switch is on and its
  `/mcp` address is a custom connector on Sean's Claude account, a thread uses the site
  through MCP as a paired agent, with the same pairing, refusals and rate limits as any
  other agent. Until then a thread asks the Mac session to run the check and reports
  what ran.
- **The template's route.**
  `SIWA_AGENT_HOME=<the agent's key folder> SIWA_CLIENT=<its siwa_agent.py> make live-check`
  runs both against template.regents.sh (`scripts/live-check.sh`, `platform/test/live`):
  `doctor` and `whoami` through the CLI, then the health page, `/capabilities.json`,
  every public page and document from the walk's page map, and every read-only tool
  that takes no input, signed ones signed by the agent's own key. Each site keeps the
  same script with its own address and CLI group.
- **The report** names the surface (CLI, WebMCP or MCP), the agent (`type#N`), the live
  commit and the result.

## The allowlist

Each site repository commits `.claude/settings.json` so these checks never prompt. The
template commits its file first; the shape reaches every site as a shared change.

- `permissions.allow`: the CLI's read commands for that site, the repository's checks
  and tests (`make check`, `make check-change`, `mix test`), its live check and its
  headless Chromium scripts.
- `permissions.ask`: deploys, every `fly` command, release functions, sign-in, every CLI
  command that writes, any CLI command given another `--base-url` (its signed request
  could be replayed at the site), and every SIWA-client command, whose arguments no
  pattern can hold to reads.
- Raw `curl` against a live site is not on the list.
