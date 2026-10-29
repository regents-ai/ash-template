#!/usr/bin/env bash
# Lists where each site's shared-library pins stand, so a site left behind is seen
# rather than guessed: every elixir-utils commit it locks (a site may lock several),
# its design-system and ash_postgres commits, the SIWA library it builds and the
# regents-cli its Makefile checks commands with. Each pin says how far it is behind
# the template's own pin and behind the library's main branch.
#
#   scripts/pins.sh [site ...]      # default: every site below
#
# Reads each site's platform/mix.lock and Makefile from its main branch on GitHub, at
# one commit, and this checkout's for the template. Commits are counted in a copy of
# each library's history (commits and trees, no file contents), kept in
# platform/_build/drift/libraries and fetched again on every run. "Behind" is the
# number of commits on the other side that the pin lacks, and the days from the pin's
# own commit to the newest of them; for SIWA only the commits that changed its folder
# count. The table is printed and written to platform/_build/drift/pins.md. Needs
# `gh auth login` and git.
set -euo pipefail

sites=(keyfleet regents autolaunch patchbay techtree)

elixir_utils=https://github.com/regents-ai/elixir-utils.git
design_system=https://github.com/regents-ai/design-system.git
ash_postgres=https://github.com/ash-project/ash_postgres.git
regents_cli=https://github.com/regents-ai/regents-cli.git
siwa_path=siwa/siwa-elixir/apps/siwa

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="platform/_build/drift"
source scripts/github.sh

# The local copy of a library's history.
history() {
  printf '%s/libraries/%s\n' "$out" "$(basename "$1")"
}

# Brings the local copy of each library's branches and tags up to date.
fetch_history() {
  local url dir
  for url in "$@"; do
    dir="$(history "$url")"
    if [[ -d "$dir" ]]; then
      git -C "$dir" fetch -q --prune origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
    else
      git clone -q --bare --filter=blob:none "$url" "$dir"
    fi
  done
}

# "app repository commit" for each git dependency of a mix.lock on stdin.
git_pins() {
  sed -nE 's/^  "([a-z0-9_]+)": \{:git, "([^"]+)", "([0-9a-f]{40})".*/\1 \2 \3/p'
}

# The commit a lock pins for one app, or nothing.
app_pin() {
  awk -v app="$2" '$1 == app { print $3 }' <<<"$1"
}

# The commits a lock pins of one repository, each once, in the order first locked.
repo_pins() {
  awk -v repo="$2" '$2 == repo && !seen[$3]++ { print $3 }' <<<"$1"
}

# The apps a lock pins at one commit of one repository.
apps_at() {
  awk -v repo="$2" -v rev="$3" '$2 == repo && $3 == rev { print $1 }' <<<"$1"
}

days() {
  case "$1" in
    0) echo "under a day" ;;
    1) echo "1 day" ;;
    *) echo "$1 days" ;;
  esac
}

# How far commit $2 is behind commit $3 in the history of library $1, and how many
# commits it has that $3 lacks, named by $4 ("ahead", "not on main"), counting only
# commits that changed path $5 when one is given.
behind() {
  local dir ref="$2" target="$3" extra="$4" lacking ahead newest since text
  local -a only=()
  dir="$(history "$1")"
  [[ -z "${5:-}" ]] || only=(-- "$5")
  if ! git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null; then
    echo "not on GitHub"
    return
  fi
  if ! git -C "$dir" cat-file -e "$target^{commit}" 2>/dev/null; then
    echo "${target:0:7} not on GitHub"
    return
  fi
  lacking="$(git -C "$dir" rev-list --count "$ref..$target" ${only[@]+"${only[@]}"})"
  ahead="$(git -C "$dir" rev-list --count "$target..$ref" ${only[@]+"${only[@]}"})"
  if [[ "$lacking" == 0 && "$ahead" == 0 ]]; then
    echo "same"
    return
  fi
  if [[ "$lacking" == 0 ]]; then
    echo "$ahead $extra"
    return
  fi
  newest="$(git -C "$dir" log -1 --format=%ct "$ref..$target" ${only[@]+"${only[@]}"})"
  since="$(git -C "$dir" log -1 --format=%ct "$ref")"
  text="$lacking commit$([[ "$lacking" == 1 ]] || echo s), $(days $(((newest > since ? newest - since : 0) / 86400)))"
  [[ "$ahead" == 0 ]] || text="$text; $ahead $extra"
  echo "$text"
}

# A pin as the table shows it: the short commit, and its release when one is tagged there.
shown() {
  local tag
  tag="$(git -C "$(history "$1")" tag --points-at "$2" 2>/dev/null | head -1)"
  printf '`%s`%s\n' "${2:0:7}" "${tag:+ ($tag)}"
}

# The SIWA library's version at a commit of elixir-utils.
siwa_version() {
  git -C "$(history "$elixir_utils")" show "$1:$siwa_path/mix.exs" 2>/dev/null |
    sed -nE 's/^.*(@version|version:) "([^"]+)".*$/\2/p' | head -1
}

row() {
  printf '| %s | %s | %s | %s | %s | %s |\n' "$@" >>"$table"
}

# Every row for one site: its mix.lock and Makefile, and the site's name as the table
# shows it.
site_rows() {
  local raw="$1" makefile="$2" site="$3" lock url name rev pins count apps hex siwa cli
  lock="$(git_pins <<<"$raw")"
  for url in "$elixir_utils" "$design_system" "$ash_postgres"; do
    name="$(basename "$url" .git)"
    pins="$(repo_pins "$lock" "$url")"
    if [[ -z "$pins" ]]; then
      if [[ "$url" == "$ash_postgres" ]] &&
        hex="$(sed -nE 's/^  "ash_postgres": \{:hex, :ash_postgres, "([^"]+)".*/\1/p' <<<"$raw")" &&
        [[ -n "$hex" ]]; then
        row "$site" "$name" "Hex $hex" "ash_postgres" "not a commit" "not a commit"
      else
        row "$site" "$name" "none" "" "" ""
      fi
      continue
    fi
    count="$(wc -l <<<"$pins" | tr -d ' ')"
    for rev in $pins; do
      apps="$(apps_at "$lock" "$url" "$rev")"
      if [[ "$count" == 1 && "$(wc -l <<<"$apps" | tr -d ' ')" -gt 1 ]]; then
        apps="$(wc -l <<<"$apps" | tr -d ' ') apps"
      else
        apps="$(tr '\n' ' ' <<<"$apps" | sed 's/ $//; s/ /, /g')"
      fi
      row "$site" "$name" "$(shown "$url" "$rev")" "$apps" \
        "$(vs_template "$url" "$rev" "$(repo_pins "$template_lock" "$url" | head -1)")" \
        "$(behind "$url" "$rev" "$(main_of "$url")" "not on main")"
    done
  done

  siwa="$(app_pin "$lock" siwa)"
  if [[ -n "$siwa" ]]; then
    row "$site" "siwa" "$(shown "$elixir_utils" "$siwa") $(siwa_version "$siwa")" "siwa" \
      "$(vs_template "$elixir_utils" "$siwa" "$(app_pin "$template_lock" siwa)" "$siwa_path")" \
      "$(behind "$elixir_utils" "$siwa" "$(main_of "$elixir_utils")" "not on main" "$siwa_path")"
  fi

  cli="$(sed -nE 's/^REGENTS_CLI_REV := ([0-9a-f]{40})$/\1/p' <<<"$makefile")"
  if [[ -n "$cli" ]]; then
    row "$site" "regents-cli" "$(shown "$regents_cli" "$cli")" "Makefile" \
      "$(vs_template "$regents_cli" "$cli" "$template_cli")" \
      "$(behind "$regents_cli" "$cli" "$(main_of "$regents_cli")" "not on main")"
  fi
}

# Behind the template's pin, or a dash on the template's own rows.
vs_template() {
  if [[ "$current" == template ]]; then
    echo "-"
  elif [[ -z "$3" ]]; then
    echo "not pinned by the template"
  else
    behind "$1" "$2" "$3" "ahead" "${4:-}"
  fi
}

main_of() {
  git -C "$(history "$1")" rev-parse refs/heads/main
}

mkdir -p "$out/libraries"
fetch_history "$elixir_utils" "$design_system" "$ash_postgres" "$regents_cli"

template_lock="$(git_pins <platform/mix.lock)"
template_cli="$(sed -nE 's/^REGENTS_CLI_REV := ([0-9a-f]{40})$/\1/p' Makefile)"

table="$out/pins.md"
{
  echo "# Shared-library pins"
  echo
  echo "Read $(date -u +%Y-%m-%dT%H:%MZ) from each site's main branch on GitHub, and from this"
  echo "checkout for the template. Library main: elixir-utils \`$(main_of "$elixir_utils" | cut -c1-7)\`,"
  echo "design-system \`$(main_of "$design_system" | cut -c1-7)\`, ash_postgres \`$(main_of "$ash_postgres" | cut -c1-7)\`, regents-cli"
  echo "\`$(main_of "$regents_cli" | cut -c1-7)\`. Behind: the commits the pin lacks, and the days from the pin's"
  echo "commit to the newest of them; for siwa, only changes to \`$siwa_path\`."
  echo
  echo "| Site | Library | Pin | Apps | Behind template | Behind main |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >"$table"

current=template
site_rows "$(cat platform/mix.lock)" "$(cat Makefile)" "template (this checkout)"

for current in "${@:-${sites[@]}}"; do
  repo="regents-ai/$current"
  rev="$(main_commit "$repo")"
  lock="$(site_file "$repo" "$rev" platform/mix.lock)"
  makefile="$(site_file "$repo" "$rev" Makefile)" || makefile=""
  site_rows "$lock" "$makefile" "$current \`${rev:0:7}\`"
done

cat "$table"
