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
#
# Run it as it is, never inside lockf: it takes its own locks.
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

label="${commit:0:7}"
image="registry.fly.io/$app:$label"

# The running image is labelled with the short commit it was built from. A
# commit that does not contain it would take live work back out, which happens
# when two releases of one app cross; this is read under the app's own lock, so
# two deploys of one app take turns and the second reads the first's image.
release() {
  local live
  live="$(fly image show --app "$app" --json | jq -r '.[0].Tag')"
  if ! git merge-base --is-ancestor "$live" "$commit" 2>/dev/null; then
    echo "Refusing to deploy: $label does not contain the live image's commit \"$live\". Update to origin/main first." >&2
    exit 1
  fi

  echo "==> Building $image from $commit"
  fly deploy . \
    --config platform/fly.toml \
    --app "$app" \
    --build-only \
    --push \
    --remote-only \
    --build-arg SOURCE_COMMIT="$commit" \
    --image-label "$label"

  switch
}

# The switch to the new image runs the release command on the production
# database every site shares, then briefly adds a second machine's connections,
# which fits two switches at once. It takes whichever of the two places is
# free, or waits for the second. The build takes no shared lock.
switch() {
  local place=/tmp/regent-shared-db-release.lock
  lockf -k -s -t 0 "$place" true || place=/tmp/regent-shared-db-release-2.lock
  echo "==> Releasing $image to $app (waits for $place if it is taken)"
  lockf -k "$place" fly deploy \
    --config platform/fly.toml \
    --app "$app" \
    --image "$image" \
    --ha=false
}

# One deploy of this app at a time; other apps' deploys never wait on it.
lock="/tmp/regent-release-$app.lock"
echo "==> Waiting for any other $app deploy holding $lock"
export app commit label image
export -f release switch
exec lockf -k "$lock" bash -euo pipefail -c release
