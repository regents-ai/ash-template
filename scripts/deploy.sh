#!/usr/bin/env bash
# Deploys the committed tree to one Fly app, and nothing else.
#
#   scripts/deploy.sh <fly-app>        # the hosted demo: scripts/deploy.sh template-regents-sh
#
# It refuses a working tree with any change, a commit that is not on
# origin/main, and a commit that does not contain the one already live, so what
# runs is always what the repository holds and never takes live work out. The
# app is named here, never in fly.toml, so the same configuration serves every
# site built from the template. The image is labelled with the short commit it
# was built from and carries the full commit, which /capabilities.json names.
# The build runs on Fly's builders from the repository root, where
# .dockerignore admits only platform/, skills/ and cli/commands.json.
set -euo pipefail

if [[ $# -ne 1 || -z $1 ]]; then
  echo "Usage: scripts/deploy.sh <fly-app>" >&2
  exit 2
fi
app="$1"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Refusing to deploy: commit or remove every change first." >&2
  exit 1
fi

git fetch --quiet origin main
commit="$(git rev-parse HEAD)"
if ! git merge-base --is-ancestor "$commit" origin/main; then
  echo "Refusing to deploy: ${commit:0:7} is not on origin/main. Push it to main first." >&2
  exit 1
fi

# The running image is labelled with the short commit it was built from (the
# --image-label below). A commit that does not contain it would take live work
# back out, which happens when two releases cross: bring this checkout up to
# origin/main and deploy again.
live="$(fly image show --app "$app" --json | jq -r '.[0].Tag')"
if ! git merge-base --is-ancestor "$live" "$commit" 2>/dev/null; then
  echo "Refusing to deploy: ${commit:0:7} does not contain the live image's commit \"$live\". Update to origin/main first." >&2
  exit 1
fi

# Every site shares one production database, and until every site serves through
# the pooler a release's direct connections still add up, so releases from this
# machine take turns: the build and release run under one lock that every site's
# deploy takes, and wait for it.
lock=/tmp/regent-shared-db-release.lock
echo "==> Deploying ${commit:0:7} to $app (waits for any other release holding $lock)"
exec lockf -k "$lock" fly deploy . \
  --config platform/fly.toml \
  --app "$app" \
  --ha=false \
  --remote-only \
  --build-arg SOURCE_COMMIT="$commit" \
  --image-label "${commit:0:7}"
