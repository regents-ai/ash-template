#!/usr/bin/env bash
# Lists every commit each site has added to its main branch since the commit the
# harvest ledger last read, with the files each touched named as the template names
# them, so the inbound job (automation/harvest.md) judges facts rather than guesses.
#
#   scripts/harvest.sh <ledger> <repos> [site ...]   # default: every site in scripts/github.sh
#
# <ledger> is the harvest ledger, control's automation/harvest.md: its "Last read"
# table gives each site's last commit read, in full. <repos> is the folder holding a
# clone of each site under the site's name (<repos>/keyfleet, <repos>/regents, ...).
# Each clone's main is fetched from its origin first, and the commits are those on
# origin/main that the last commit read lacks, oldest first.
#
# A file is named as the template names it the way scripts/init.sh renames the
# template's files for the site (the OTP app, module and Mix task names come from the
# site's platform/mix.exs), and a shared file a site keeps at its own path
# (scripts/shared-files.sh) is named by the template's path. A file the template has
# no copy of has no template path.
#
# Prints one JSON document:
#
#   {"template": this checkout's commit,
#    "sites": [{"site", "app", "module", "since", "head",
#               "commits": [{"commit", "date", "subject", "merge", "shared",
#                            "files": [{"status", "path", "template_path", "list"}]}]}]}
#
# since is the ledger's last commit read and head the site's main now. date is the
# commit date, in UTC. A merge commit lists no files of its own: the commits it
# brings in are listed themselves. status is git's A, M or D; a renamed file is a D
# and an A. template_path is null for a file the template has no copy of. list names
# the scripts/shared-files.sh list the template's file is in: shared, build,
# homepage (regents only, as in scripts/drift.sh) or null. shared is true for a
# commit that touches a file in the shared list. Needs git and jq.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: scripts/harvest.sh <ledger> <repos> [site ...]" >&2
  exit 64
fi
ledger="$1"
repos="$2"
shift 2

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/github.sh"
source "$root/scripts/shared-files.sh"

# The commit the ledger last read for a site: the second cell of the site's row in the
# "Last read" table.
last_read() {
  awk -v site="$1" '
    /^## / { in_table = ($0 == "## Last read") }
    in_table && $0 ~ "^\\| *" site " *\\|" { split($0, cells, "|"); gsub(/[ `]/, "", cells[3]); print cells[3]; exit }
  ' "$ledger"
}

# A JSON array of the lines on stdin.
lines() {
  jq -R -s 'split("\n") | map(select(. != ""))'
}

# The JSON object of a site's path for every template file: each of the template's
# files renamed the way scripts/init.sh renames it (a file in skills/ or a dated plan,
# docs/*-plan.md, keeps its name), and each shared file the site keeps at its own path.
names() {
  local entry site_name path site_path moved_here=()
  for entry in "${moved_files[@]}"; do
    read -r site_name path site_path <<<"$entry"
    [[ "$site_name" != "$site" ]] || moved_here+=("$site_path $path")
  done
  git -C "$root" ls-files | jq -R -s --arg app "$app" --arg kebab "$kebab" \
    --arg prefix "$task_prefix" --arg tasks "$tasks" \
    --argjson moved "$(printf '%s\n' ${moved_here[@]+"${moved_here[@]}"} | lines)" '
    def renamed:
      if test("^ash_template\\.(" + $tasks + ")\\.ex$") then sub("^ash_template"; $prefix)
      else gsub("ash_template"; $app) | gsub("ash-template"; $kebab) end;
    def site_path:
      if test("^skills/|^docs/.*-plan\\.md$") then . else split("/") | map(renamed) | join("/") end;
    (split("\n") | map(select(. != "")) | map({key: site_path, value: .}))
    + ($moved | map(split(" ") | {key: .[0], value: .[1]}))
    | from_entries'
}

# The JSON object of the list each listed template file is in.
lists() {
  {
    printf 'shared %s\n' "${shared[@]}"
    printf 'build %s\n' "${build[@]}"
    [[ "$site" != regents ]] || printf 'homepage %s\n' "${homepage[@]}"
  } | jq -R -s 'split("\n") | map(select(. != "") | split(" ") | {key: .[1], value: .[0]}) | from_entries'
}

# The Mix tasks the template defines, as scripts/init.sh reads them.
tasks="$(cd "$root/platform/lib/mix/tasks" && ls ash_template.*.ex | sed -E 's/^ash_template\.(.*)\.ex$/\1/' | paste -sd '|' -)"

sites_read=""
for site in "${@:-${sites[@]}}"; do
  dir="$repos/$site"
  git_dir="$dir/.git"
  since="$(last_read "$site")"
  if [[ ! "$since" =~ ^[0-9a-f]{40}$ ]]; then
    echo "$ledger has no full last-read commit for $site in its \"Last read\" table" >&2
    exit 1
  fi
  git --git-dir="$git_dir" fetch -q origin '+refs/heads/main:refs/remotes/origin/main'
  if ! git --git-dir="$git_dir" cat-file -e "$since^{commit}" 2>/dev/null; then
    echo "$dir lacks $since, the last commit read for $site: fetch its full history" >&2
    exit 1
  fi
  head="$(git --git-dir="$git_dir" rev-parse refs/remotes/origin/main)"
  mix_exs="$(git --git-dir="$git_dir" show "$head:platform/mix.exs")"
  site_names "$mix_exs"

  site_paths="$(names)"
  site_lists="$(lists)"
  sites_read+="$(git --git-dir="$git_dir" -c core.quotePath=false log --reverse --no-renames \
    --name-status --format='%x1e%H%x1f%P%x1f%ct%x1f%s' "$since..$head" |
    jq -R -s -c --arg site "$site" --arg app "$app" --arg module "$module" \
      --arg since "$since" --arg head "$head" \
      --argjson names "$site_paths" --argjson lists "$site_lists" '
      def file: split("\t") | ($names[.[1]] // null) as $t
        | {status: .[0], path: .[1], template_path: $t, list: (if $t then $lists[$t] // null else null end)};
      {site: $site, app: $app, module: $module, since: $since, head: $head,
       commits: (split("\u001e")[1:] | map(
         split("\n") as $lines | ($lines[0] | split("\u001f")) as $h
         | {commit: $h[0], date: ($h[2] | tonumber | todate), subject: $h[3], merge: ($h[1] | split(" ") | length > 1),
            files: [$lines[1:][] | select(. != "") | file]}
         | .shared = any(.files[]; .list == "shared")))}')"$'\n'
done
jq -s --arg template "$(git -C "$root" rev-parse HEAD)" '{template: $template, sites: .}' <<<"$sites_read"
