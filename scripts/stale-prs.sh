#!/usr/bin/env bash
# Sorts a repository's open pull requests from one daily job into the ones to close
# and the ones waiting for Sean's letter, for automation/harvest.md and
# automation/spread.md.
#
#   scripts/stale-prs.sh <owner/repo> <branch prefix>     # e.g. regents-ai/keyfleet spread/
#
# Prints one JSON document:
#
#   {"repo", "close": [{"number", "url", "title", "days_open"}],
#    "waiting": [{"number", "url", "title", "days_open"}]}
#
# close lists those open seven or more days. waiting lists every draft whose title
# starts "Waits for Sean: ", at any age: it waits for his letter and is never closed,
# so the day's summary names it instead. Needs `gh auth login` and jq.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/stale-prs.sh <owner/repo> <branch prefix>" >&2
  exit 64
fi
repo="$1"
prefix="$2"

gh pr list --repo "$repo" --state open --limit 200 \
  --json number,url,title,headRefName,createdAt,isDraft |
  jq --arg repo "$repo" --arg prefix "$prefix" --argjson now "$(date -u +%s)" '
    [.[] | select(.headRefName | startswith($prefix))
     | {number, url, title,
        days_open: ((($now - (.createdAt | fromdateiso8601)) / 86400) | floor),
        waiting: (.isDraft and (.title | startswith("Waits for Sean: ")))}] as $prs
    | {repo: $repo,
       close: [$prs[] | select((.waiting | not) and .days_open >= 7) | del(.waiting)],
       waiting: [$prs[] | select(.waiting) | del(.waiting)]}'
