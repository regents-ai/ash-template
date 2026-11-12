#!/usr/bin/env bash
# Lists where each site's shared-library pins stand, so a site left behind is seen
# rather than guessed: every elixir-utils commit it locks (a site may lock several),
# its design-system and ash_postgres commits, the SIWA library it builds and the
# regents-cli its Makefile checks commands with. Each pin says how far it is behind
# the template's own pin and behind the library's main branch.
#
#   scripts/pins.sh [site ...]      # default: every site in scripts/github.sh
#
# Reads each site's platform/mix.lock and Makefile from its main branch on GitHub, at
# one commit, and this checkout's for the template. Commits are counted in a copy of
# each library's history (its branches, tags and pull requests; commits and trees, no
# file contents), kept in platform/_build/drift/libraries and fetched again on every
# run. Each copy is read only through its own --git-dir, so a damaged copy stops the
# run and never reaches the checkout around it.
#
# Prints one JSON document:
#
#   {"read_at",
#    "library_main": {"elixir-utils", "design-system", "ash_postgres", "regents-cli"},
#    "pins": [{"site", "commit", "library", "pin", "tag", "hex", "version", "apps",
#              "on_github", "behind_template", "behind_main"}]}
#
# site is "template" for this checkout's own pins, and commit is the commit read: the
# site's main, or this checkout's HEAD. library is elixir-utils, design-system,
# ash_postgres, siwa or regents-cli. pin is the commit locked (null for a Hex release,
# whose version is in hex, or for a library the site does not use); tag is a release
# tagged at the pin; version is the SIWA library's at the pin; apps are the apps the
# lock pins there; on_github says the pin is in the library's history.
# behind_template (null on the template's rows) and behind_main are
#
#   {"target", "on_github", "lacking", "ahead", "days"}
#
# for the template's pin (null when the template pins none of that library) and the
# library's main: lacking is the number of the target's commits the pin lacks, ahead
# the number of the pin's commits the target lacks, and days runs from the pin's own
# commit to the newest commit it lacks. For siwa only the commits that changed its
# folder count. The counts are null when the pin or the target is not on GitHub. A
# library a site does not use has every field after apps null. Needs `gh auth login`,
# git and jq.
set -euo pipefail

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

# Brings the local copy of each library's branches, tags and pull requests up to
# date, so a pin on a pull request's commit is found.
fetch_history() {
  local url dir
  for url in "$@"; do
    dir="$(history "$url")"
    [[ -d "$dir" ]] || git clone -q --bare --filter=blob:none "$url" "$dir"
    git --git-dir="$dir" fetch -q --prune origin \
      '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' '+refs/pull/*/head:refs/pull/*/head'
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

# Whether commit $2 is in the history of library $1.
on_github() {
  git --git-dir="$(history "$1")" cat-file -e "$2^{commit}" 2>/dev/null
}

# How far commit $2 is behind commit $3 in the history of library $1, as a JSON
# object, counting only commits that changed path $4 when one is given. An empty $3
# is a target nobody pins.
behind() {
  local dir ref="$2" target="$3" lacking ahead newest since days=0
  local -a only=()
  dir="$(history "$1")"
  [[ -z "${4:-}" ]] || only=(-- "$4")
  if [[ -z "$target" ]]; then
    jq -nc '{target: null, on_github: null, lacking: null, ahead: null, days: null}'
    return
  fi
  if ! on_github "$1" "$target"; then
    jq -nc --arg target "$target" '{target: $target, on_github: false, lacking: null, ahead: null, days: null}'
    return
  fi
  if ! on_github "$1" "$ref"; then
    jq -nc --arg target "$target" '{target: $target, on_github: true, lacking: null, ahead: null, days: null}'
    return
  fi
  lacking="$(git --git-dir="$dir" rev-list --count "$ref..$target" ${only[@]+"${only[@]}"})"
  ahead="$(git --git-dir="$dir" rev-list --count "$target..$ref" ${only[@]+"${only[@]}"})"
  if [[ "$lacking" != 0 ]]; then
    newest="$(git --git-dir="$dir" log -1 --format=%ct "$ref..$target" ${only[@]+"${only[@]}"})"
    since="$(git --git-dir="$dir" log -1 --format=%ct "$ref")"
    days=$(((newest > since ? newest - since : 0) / 86400))
  fi
  jq -nc --arg target "$target" --argjson lacking "$lacking" --argjson ahead "$ahead" --argjson days "$days" \
    '{target: $target, on_github: true, lacking: $lacking, ahead: $ahead, days: $days}'
}

# A release tagged at a commit of a library, or nothing.
tag_at() {
  git --git-dir="$(history "$1")" tag --points-at "$2" 2>/dev/null | head -1
}

# The SIWA library's version at a commit of elixir-utils.
siwa_version() {
  git --git-dir="$(history "$elixir_utils")" show "$1:$siwa_path/mix.exs" 2>/dev/null |
    sed -nE 's/^.*(@version|version:) "([^"]+)".*$/\2/p' | head -1
}

# Behind the template's pin, or null on the template's own rows.
vs_template() {
  if [[ "$site" == template ]]; then
    echo null
  else
    behind "$@"
  fi
}

main_of() {
  git --git-dir="$(history "$1")" rev-parse refs/heads/main
}

# One row, from the library, pin, hex, version, apps (one per line), and then, for a
# pin, the library's URL, the template's pin and the folder that counts.
row() {
  local library="$1" pin="$2" hex="$3" version="$4" apps="$5" url="${6:-}" theirs="${7:-}" path="${8:-}"
  local tag="" found=null vs=null main=null library_main
  if [[ -n "$pin" ]]; then
    tag="$(tag_at "$url" "$pin")"
    found=false
    if on_github "$url" "$pin"; then
      found=true
    fi
    vs="$(vs_template "$url" "$pin" "$theirs" "$path")"
    library_main="$(main_of "$url")"
    main="$(behind "$url" "$pin" "$library_main" "$path")"
  fi
  jq -nc --arg site "$site" --arg commit "$commit" --arg library "$library" --arg pin "$pin" \
    --arg tag "$tag" --arg hex "$hex" --arg version "$version" --arg apps "$apps" \
    --argjson on_github "$found" --argjson behind_template "$vs" --argjson behind_main "$main" '
    def blank: if . == "" then null else . end;
    {site: $site, commit: $commit, library: $library, pin: ($pin | blank), tag: ($tag | blank),
     hex: ($hex | blank), version: ($version | blank),
     apps: ($apps | split("\n") | map(select(. != ""))),
     on_github: $on_github, behind_template: $behind_template, behind_main: $behind_main}'
}

# Every row for one site, from its mix.lock and Makefile.
site_rows() {
  local raw="$1" makefile="$2" lock url name rev pins hex siwa cli
  lock="$(git_pins <<<"$raw")"
  for url in "$elixir_utils" "$design_system" "$ash_postgres"; do
    name="$(basename "$url" .git)"
    pins="$(repo_pins "$lock" "$url")"
    if [[ -z "$pins" ]]; then
      hex=""
      [[ "$url" != "$ash_postgres" ]] ||
        hex="$(sed -nE 's/^  "ash_postgres": \{:hex, :ash_postgres, "([^"]+)".*/\1/p' <<<"$raw")"
      if [[ -n "$hex" ]]; then
        row "$name" "" "$hex" "" ash_postgres
      else
        row "$name" "" "" "" ""
      fi
      continue
    fi
    for rev in $pins; do
      row "$name" "$rev" "" "" "$(apps_at "$lock" "$url" "$rev")" \
        "$url" "$(repo_pins "$template_lock" "$url" | head -1)"
    done
  done

  siwa="$(app_pin "$lock" siwa)"
  if [[ -n "$siwa" ]]; then
    row siwa "$siwa" "" "$(siwa_version "$siwa")" siwa \
      "$elixir_utils" "$(app_pin "$template_lock" siwa)" "$siwa_path"
  fi

  cli="$(sed -nE 's/^REGENTS_CLI_REV := ([0-9a-f]{40})$/\1/p' <<<"$makefile")"
  if [[ -n "$cli" ]]; then
    row regents-cli "$cli" "" "" "" "$regents_cli" "$template_cli"
  fi
}

mkdir -p "$out/libraries"
fetch_history "$elixir_utils" "$design_system" "$ash_postgres" "$regents_cli"

template_lock="$(git_pins <platform/mix.lock)"
template_cli="$(sed -nE 's/^REGENTS_CLI_REV := ([0-9a-f]{40})$/\1/p' Makefile)"

site=template
commit="$(git rev-parse HEAD)"
rows="$(site_rows "$(cat platform/mix.lock)" "$(cat Makefile)")"

for site in "${@:-${sites[@]}}"; do
  repo="regents-ai/$site"
  commit="$(main_commit "$repo")"
  lock="$(site_file "$repo" "$commit" platform/mix.lock)" || {
    status=$?
    [[ "$status" != 44 ]] || echo "$repo has no platform/mix.lock at ${commit:0:7}" >&2
    exit "$status"
  }
  # A site with no Makefile has no regents-cli row; any other failure stops the run.
  makefile="$(site_file "$repo" "$commit" Makefile)" || {
    status=$?
    [[ "$status" == 44 ]] || exit "$status"
    makefile=""
  }
  rows+=$'\n'"$(site_rows "$lock" "$makefile")"
done

jq -s --arg read_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg elixir_utils "$(main_of "$elixir_utils")" --arg design_system "$(main_of "$design_system")" \
  --arg ash_postgres "$(main_of "$ash_postgres")" --arg regents_cli "$(main_of "$regents_cli")" '
  {read_at: $read_at,
   library_main: {"elixir-utils": $elixir_utils, "design-system": $design_system,
                  "ash_postgres": $ash_postgres, "regents-cli": $regents_cli},
   pins: .}' <<<"$rows"
