# A fast check that still tells the truth

How ash-template took `make check` from about five and a half minutes to about two on a 16-core
Mac (16 Nov 2026, Sean's letter 80 a), and how a site that copied the template's `Makefile` does
the same. Every test still runs; nothing was retried, skipped, removed or given a longer timeout.

## The rules that outrank speed

1. The full check runs on the exact commit before every release. A faster run of part of it is
   feedback, never the gate.
2. Never get faster by hiding a failure: no retries, no wider timeouts, no skipped or deleted
   tests. A check that needs a retry has a bug; find it.
3. Measure first. Read each gate's seconds from `platform/_build/check/results` on two runs and
   fix the largest first. Here the tests' own run time was not the largest part: the walk ran
   three browsers on sixteen cores, and `mix test` waited behind `mix precommit`.
4. One change per commit, with before and after seconds from real runs in its message.
5. A change is proven only by repeats: the walk three times in a row with the same passed and
   skipped counts, the full check three times in a row.

## What changed, largest first

| Change | Before | After |
| --- | --- | --- |
| Browser walk: one browser per two cores, at most twelve (`platform/playwright.config.ts`) | about 4 min | about 1.7 min |
| `mix test` in its own lane beside `mix precommit` (`CHECK_LANES` in the `Makefile`) | 60 s after precommit | 60 s beside it |
| Whole check | about 330 s | 110 to 140 s |

`CHECK_BUDGETS` in the `Makefile` then keeps it fast: a gate over its budget prints
`SLOW: <gate> took N s (budget M s)`. It warns and never fails, so a busy machine cannot turn a
run red.

Not worth doing here, measured: making more ExUnit modules `async: true`. The slow modules are
slow from what they wait for (a stand-in that answers word by word, one-second sleeps), not
from running in turn, and once `mix test` runs beside precommit it is no longer on the longest
path.

## Three walks at once do not fit

The walk's size above was measured with one check running. This Mac allows three full checks at
once, and three walks at half the cores each ask for one and a half machines before their
servers and tests. Seen on 16 Nov 2026 with three walks running: load of 90 to 180 on 16 cores,
`platform-precommit` at 190 to 230 s, and a different failure on each run of an unchanged
commit (a page that stopped drawing for over five seconds, then three server tests that timed
out waiting for a database connection). None of them failed when run alone.

How walks share the machine (one walk at a time, or three smaller walks) is with Sean and not
decided. Until it is:

- the two-minute figure holds only when no other walk is running;
- a failure that appears only while other walks run is the machine, not the commit. Read the
  load (`sysctl -n vm.loadavg`) before hunting it, and run the full check again on a quiet
  machine. That is not a retry: the gate is still one clean full check on the exact commit;
- do not answer it with a retry, a wider timeout or a skipped test.

## Steps for a site

1. **Measure.** Run `make check` twice and note each gate's seconds.
2. **Walk concurrency.** Copy the `workers` lines from the template's
   `platform/playwright.config.ts`. Then run the walk alone at sixteen workers with
   `--repeat-each` on any test that fails, to find tests that race the page. Fix the race in
   the test's waiting, never with a retry:
   - a press before the page listens: wait for `.phx-connected` (or the hook's own ready
     mark) before pressing;
   - a pixel comparison of a box: compare the picture inside its border, since on a phone's
     fractional pixel ratio the border rows blend and can repaint late on a busy machine.
3. **`mix test` beside precommit.** Before moving the lane, find every test that reads or
   writes a folder precommit rewrites (`assets/vendor`, `priv/static/assets`). In the template
   that was one, `platform/test/ash_template_web/script_build_test.exs`: copy it, and add to
   its copied sources any file outside `assets/` that the site's scripts import. Then take the
   template's `CHECK_LANES` line and its comment.
4. **Budgets.** Take the `CHECK_BUDGETS` table and the `SLOW` line; set each budget about 40%
   over the site's own measured time.
5. **Prove it.** The full check three times in a row, with the same test and skip counts as
   before the change. Put the seconds in the commit messages.
6. Update the site's `AGENTS.md` and `platform/README.md` lines that describe the lanes.
   `make drift` in the template flags the `Makefile` until the site has taken it.

## Still slow, and why

- One walk server serves every browser; past twelve browsers it is the limit.
- Waiting for one of the Mac's three shared check places can cost more than the check. Machines
  off the Mac would fix that; it has not been decided.
