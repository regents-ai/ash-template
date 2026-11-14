#!/usr/bin/env bash
# Deploys the committed tree to one Fly app, and nothing else.
#
#   scripts/deploy.sh <fly-app>             # the hosted demo: scripts/deploy.sh template-regents-sh
#   scripts/deploy.sh --dry-run <fly-app>   # every check, then the commands it would run
#
# It refuses a working tree with any change, a commit that is not on
# origin/main, and a commit that does not contain the one already live, so what
# runs is always what the repository holds and never takes live work out. The
# live commit is the label of the app's running image, read from Fly
# (scripts/release-lib.sh). The app is named here, never in fly.toml, so the
# same configuration serves every site built from the template. The image is
# labelled with the short commit it was built from and carries the full commit,
# which /capabilities.json names. The build runs on Fly's builders from the
# repository root, where .dockerignore admits only platform/, skills/ and
# cli/commands.json. A dry run makes every check and reads what is live, then
# prints the build and the switch instead of running them.
#
# Run it as it is, never inside lockf: it takes its own locks. To go back to an
# earlier release, use scripts/rollback.sh.
set -euo pipefail

dry_run=""
if [[ ${1:-} == --dry-run ]]; then
  dry_run=1
  shift
fi
if [[ $# -ne 1 || -z $1 ]]; then
  echo "Usage: scripts/deploy.sh [--dry-run] <fly-app>" >&2
  exit 2
fi
app="$1"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck source=scripts/release-lib.sh
source scripts/release-lib.sh

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

# A commit that does not contain the live one would take live work back out,
# which happens when two releases of one app cross; this is read under the
# app's own lock, so two deploys of one app take turns and the second reads
# the first's image.
release() {
  local live
  live="$(live_commit)"
  if ! git merge-base --is-ancestor "$live" "$commit"; then
    echo "Refusing to deploy: $label does not contain $live, which is live. Update to origin/main first." >&2
    exit 1
  fi
  echo "==> $app runs $live, which $label contains"

  echo "==> Building $image from $commit"
  run fly deploy . \
    --config platform/fly.toml \
    --app "$app" \
    --build-only \
    --push \
    --remote-only \
    --build-arg SOURCE_COMMIT="$commit" \
    --image-label "$label"

  switch_to "$image" platform/fly.toml
}

# One deploy or rollback of this app at a time; other apps' never wait on it.
lock="/tmp/regent-release-$app.lock"
export app dry_run commit label image
export -f release run live_commit switch_to

if [[ -n $dry_run ]]; then
  echo "==> Dry run: nothing is built or switched. A deploy would first wait for any other $app deploy holding $lock."
  release
  exit
fi

echo "==> Waiting for any other $app deploy holding $lock"
exec lockf -k "$lock" bash -euo pipefail -c release
