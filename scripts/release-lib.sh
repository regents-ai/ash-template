# shellcheck shell=bash
# Shared by scripts/deploy.sh and scripts/rollback.sh, which source it from the
# repository root with $app and $dry_run set. Never run on its own.
# shellcheck disable=SC2154 # $app and $dry_run are set by the script that sources this file

# Runs a command, or with --dry-run prints it exactly as it would run.
run() {
  if [[ -n $dry_run ]]; then
    printf 'Would run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# Prints the full commit $app runs: the label of its running image, which
# scripts/deploy.sh sets to the short commit it builds. It is read from Fly,
# which answers whether the site is up or not, so a site too broken to answer
# can still be rolled back. Refuses a label that names no commit this checkout
# holds.
live_commit() {
  local tag live
  tag="$(fly image show --app "$app" --json | jq -r '.[0].Tag')"
  if [[ ! $tag =~ ^[0-9a-f]{7,40}$ ]] || ! live="$(git rev-parse --verify --quiet "$tag^{commit}")"; then
    echo "Refusing: $app runs the image labelled \"$tag\", which names no commit this checkout holds." >&2
    return 1
  fi
  echo "$live"
}

# Switches $app to the image $1 with the Fly configuration $2. The switch runs
# the release command on the production database every site shares, then
# briefly adds a second machine's connections. Two switches fit at once across
# all sites, so this takes the first shared place if it is free and otherwise
# waits for the second. A build takes no shared place.
switch_to() {
  local place=/tmp/regent-shared-db-release.lock
  lockf -k -s -t 0 "$place" true || place=/tmp/regent-shared-db-release-2.lock
  echo "==> Switching $app to $1 (waits for $place if it is taken)"
  run lockf -k "$place" fly deploy \
    --config "$2" \
    --app "$app" \
    --image "$1" \
    --ha=false
}
