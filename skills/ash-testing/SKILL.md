---
name: ash-testing
description: Choosing and writing tests for Ash behaviour on Regent's sites - which layer proves a change (unit, real action, SQL, browser), fixtures, policy, form, concurrency and Oban job tests, and removing tests that lock wording or structure. Use when adding a regression test, deciding what proof a change needs, cleaning up a suite, or diagnosing a flaky or sandbox-related failure.
---

# Ash testing

Load `ash-stack` first. regent-workflow's "Every change proves itself" sets what a
change must prove and lets you add tests without asking; this skill is how to write
them well.

- **Test at the layer that sees the changed contract.** Pure computation: unit tests.
  Policy and data behaviour: real Ash actions. SQL invariants: the SQL data layer.
  Hooks and layout: a browser.
- **Before removing a test, name what it protects.** Keep ABI, policy, receipt and
  database invariants. Remove duplicate evidence and locks on source names, exact test
  counts or decorative copy; move a useful assertion to the behaviour boundary before
  deleting the old one. No count or deletion quota applies.
- **Inspect an alias before using it as a check**: some format files, unlock
  dependencies or set up databases. Check runner discovery when you change it.
- **A test leaves no rows behind.** Every run reuses the test database, so a test
  that keeps what it committed slows every later test that reads all the rows (the
  template's Points start awards reached 2,317 leftover accounts and ran out of time)
  and hands its jobs to the next test that runs a queue. Keep each test inside the
  sandbox; a race that needs connections that really commit calls
  `AshTemplate.RealCommits.start/0`, which empties the database when the test ends.
  `test_helper.exs` empties it before every run too, so a stopped run's rows go
  first. Emptying keeps only the rows migrations put there: a migration that fills a
  table adds it to `@kept` in `test/support/real_commits.ex`. Since a run's start
  empties its database, two runs at once each take their own (`MIX_TEST_PARTITION`).
- **A test never times the machine.** A wall-clock limit fails on a busy machine and
  says nothing about the code. Assert counts and outcomes; to send a burst, start
  every writer first and release them together.
- **A browser walk waits on a condition, never a fixed time.** Measure a page once
  it has loaded, a window once it rests (`data-settled`) and a menu once its
  animations end: a page measured before its stylesheet arrives is far wider than
  the screen, a state no person ever sees. A LiveView test reads a page the same
  way: a page that hands a notice on to a component (`send_update`) shows it only
  after a second message to itself, so the test waits for the page
  (`:sys.get_state(view.pid)`) before it reads.
- **Rerun what a fix affects**; broaden only for a changed risk or an unresolved
  failure.
- **Report executed checks apart from missing ones** (database, browser, provider).

[Test recipes](references/test-recipes.md) covers fixtures, policy filtering, forms,
concurrency and jobs. Reuse the site's runner and its isolated test environment.
