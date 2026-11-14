#!/usr/bin/env bash
# Puts one Fly app back on an earlier release's image, and nothing else.
#
#   scripts/rollback.sh <fly-app> <release>             # scripts/rollback.sh template-regents-sh v249
#   scripts/rollback.sh --dry-run <fly-app> <release>   # every check, then the switch it would run
#
# It refuses a release Fly does not list as complete for the app, a release
# whose image label names no commit this checkout holds, and a release whose
# commit holds other migrations (platform/priv/repo/migrations) than the live
# commit: the database would no longer match the older code, so that rollback
# needs a person. The live commit is read from Fly as scripts/deploy.sh reads
# it (scripts/release-lib.sh), so a site too broken to answer can still be
# rolled back. Otherwise it switches the app to that release's image with that
# commit's own platform/fly.toml, as scripts/deploy.sh switches, then reads the
# site's /capabilities.json at <fly-app>.fly.dev until build.commit names that
# commit. A dry run makes every check, then prints the switch instead of
# running it.
#
# The shared libraries' migrations are not compared: no release applies them
# (/app/bin/migrate-shared does, on its own go), and the sites already run
# different library pins against the one shared schema.
#
# Run it as it is, never inside lockf: it takes the same locks as
# scripts/deploy.sh, the app's own and a place on the shared database.
set -euo pipefail

dry_run=""
if [[ ${1:-} == --dry-run ]]; then
  dry_run=1
  shift
fi
if [[ $# -ne 2 || -z $1 || ! $2 =~ ^v[0-9]+$ ]]; then
  echo "Usage: scripts/rollback.sh [--dry-run] <fly-app> <release, such as v249>" >&2
  exit 2
fi
app="$1"
version="$2"
site="https://$app.fly.dev/capabilities.json"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck source=scripts/release-lib.sh
source scripts/release-lib.sh

git fetch --quiet origin main

rollback() {
  local image tag target live changed answer
  image="$(fly releases --app "$app" --image --json |
    jq -r --argjson version "${version#v}" \
      '.[] | select(.Version == $version and .Status == "complete") | .ImageRef')"
  if [[ -z $image ]]; then
    echo "Refusing to roll back: $version is not a completed release of $app." >&2
    exit 1
  fi
  tag="${image##*:}"
  if [[ ! $tag =~ ^[0-9a-f]{7,40}$ ]] || ! target="$(git rev-parse --verify --quiet "$tag^{commit}")"; then
    echo "Refusing to roll back: $version ran $image, which names no commit this checkout holds." >&2
    exit 1
  fi

  live="$(live_commit)"
  changed="$(git diff --name-only "$live" "$target" -- platform/priv/repo/migrations)"
  if [[ -n $changed ]]; then
    echo "Refusing to roll back: $version ($target) and the live commit $live hold different migrations:" >&2
    echo "$changed" >&2
    echo "A rollback across a migration is not automatic. It needs a person." >&2
    exit 1
  fi
  echo "==> $app runs $live; $version ran $image, commit $target, with the same migrations"

  # The switch uses the Fly configuration that release ran with.
  folder="$(mktemp -d)"
  trap 'rm -f "$folder/fly.toml"; rmdir "$folder"' EXIT
  git show "$target:platform/fly.toml" >"$folder/fly.toml"
  switch_to "$image" "$folder/fly.toml"

  if [[ -n $dry_run ]]; then
    echo "Would then read $site until build.commit is $target"
    return
  fi
  for _ in {1..24}; do
    answer="$(curl -fsS --max-time 20 "$site" | jq -r '.build.commit' 2>/dev/null)" || answer=""
    if [[ $answer == "$target" ]]; then
      echo "==> Rolled back to $version: $site names $target"
      return
    fi
    sleep 5
  done
  echo "The switch to $version finished, but $site still names \"${answer:0:80}\", not $target." >&2
  exit 1
}

# One deploy or rollback of this app at a time; other apps' never wait on it.
lock="/tmp/regent-release-$app.lock"
export app dry_run version site
export -f rollback run live_commit switch_to

if [[ -n $dry_run ]]; then
  echo "==> Dry run: nothing is switched. A rollback would first wait for any other $app deploy holding $lock."
  rollback
  exit
fi

echo "==> Waiting for any other $app deploy holding $lock"
exec lockf -k "$lock" bash -euo pipefail -c rollback
