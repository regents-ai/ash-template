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
- **Rerun what a fix affects**; broaden only for a changed risk or an unresolved
  failure.
- **Report executed checks apart from missing ones** (database, browser, provider).

[Test recipes](references/test-recipes.md) covers fixtures, policy filtering, forms,
concurrency and jobs. Reuse the site's runner and its isolated test environment.
