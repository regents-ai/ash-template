#!/usr/bin/env bash
# Lists where each site's copies of the template's shared files, and of its build
# and deploy files, differ from the template's own, so drift is seen rather than
# guessed.
#
#   scripts/drift.sh [site ...]      # default: every site in scripts/github.sh
#
# Reads each site's main branch on GitHub at one commit, and this checkout's files
# as they are. The file lists are in scripts/shared-files.sh. A site's copy is
# compared after the template's names are renamed to the site's, the way
# scripts/init.sh renames them: the OTP app and module come from the site's
# platform/mix.exs. `mix format` rewraps some lines after a rename, so a few
# differing lines can be wrapping alone. A file a site has no use for yet is "not
# used", with why; a file a site keeps at its own path is read there. Of
# platform/mix.exs only the aliases are compared, since each site's dependencies are
# its own.
#
# The template's homepage tracks regents.sh's, so for regents two more checks run:
# the homepage files the template copies from regents.sh, and the two live
# homepages' tabs and cube (each tab and link, and every word in the cube's six
# worlds), as visitors see them.
#
# Prints one JSON document:
#
#   {"template": this checkout's commit,
#    "sites": [{"site", "repo", "main", "app", "module",
#               "files": [{"list", "path", "site_path", "status",
#                          "added", "removed", "diff", "why"}],
#               "live_homepage": null or {"status", "added", "removed", "diff"}}]}
#
# list is shared, build or homepage; status is same, differs, missing (GitHub
# answers 404) or not_used. A difference's added and removed lines are counted, and
# the difference itself is written to the file diff names, in a folder of this run's
# own under platform/_build/drift/. Fields that do not apply are null. Needs
# `gh auth login`, jq and curl.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
source scripts/github.sh
source scripts/shared-files.sh
mkdir -p platform/_build/drift
run="$(mktemp -d "platform/_build/drift/$(date -u +%Y%m%dT%H%M%SZ)-XXXX")"

# The part of a file that is compared: the aliases of platform/mix.exs, all of any other.
compared() {
  case "$1" in
    platform/mix.exs) sed -n '/^  defp aliases do$/,/^  end$/p' ;;
    *) cat ;;
  esac
}

# Writes a difference to this run's folder and sets added, removed and kept (its file).
keep_diff() {
  local text="$2" diff_file="$run/$site/$1.diff"
  printf '%s\n' "$text" >"$diff_file"
  added="$(tail -n +3 "$diff_file" | grep -c '^+' || true)"
  removed="$(tail -n +3 "$diff_file" | grep -c '^-' || true)"
  kept="$diff_file"
}

# One file's line: list, path, site path, status, then added, removed, diff and why
# where they apply.
entry() {
  jq -nc --arg list "$1" --arg path "$2" --arg site_path "$3" --arg status "$4" \
    --arg added "${5:-}" --arg removed "${6:-}" --arg diff "${7:-}" --arg why "${8:-}" '
    def blank: if . == "" then null else . end;
    {list: $list, path: $path, site_path: $site_path, status: $status,
     added: ($added | blank | if . then tonumber else . end),
     removed: ($removed | blank | if . then tonumber else . end),
     diff: ($diff | blank), why: ($why | blank)}'
}

# Compares the template's files in the named list with the current site's copies.
compare() {
  local list="$1" path site_path why theirs ours text status added removed kept
  shift
  for path in "$@"; do
    site_path="$(moved "$site" "$path")" || site_path="${path//ash_template/$app}"
    if why="$(not_used "$site" "$path")"; then
      entry "$list" "$path" "$site_path" not_used "" "" "" "$why"
      continue
    fi
    # A file the site lacks (404) is missing; any other failure stops the run.
    theirs="$(site_file "$repo" "$rev" "$site_path")" || {
      status=$?
      [[ "$status" == 44 ]] || exit "$status"
      entry "$list" "$path" "$site_path" missing
      continue
    }
    ours="$(perl -pe "s/ash_template/$app/g; s/AshTemplate/$module/g; s/ashTemplate/$camel/g; s/ASH_TEMPLATE/$upper/g; s/ash-template/$kebab/g" "$path" | compared "$path")"
    theirs="$(compared "$path" <<<"$theirs")"
    status=0
    text="$(diff -u --label "template/$path" --label "$site/$site_path" <(printf '%s\n' "$ours") <(printf '%s\n' "$theirs"))" || status=$?
    case "$status" in
      0) entry "$list" "$path" "$site_path" same ;;
      1)
        keep_diff "$(tr / _ <<<"$site_path")" "$text"
        entry "$list" "$path" "$site_path" differs "$added" "$removed" "$kept"
        ;;
      *) exit "$status" ;;
    esac
  done
}

# A live homepage's tabs and cube as visitors see them: each piece of text and
# each link on its own line, the page's markup dropped and a link within the
# site written with the site's address.
home_words() {
  curl -fsS --max-time 20 "$1/" | ORIGIN="$1" perl -0777 -ne '
    my $nav = m{<nav class="rl-product-tabs".*?</nav>}s ? $& : "";
    my $cube = m{<[^<>]*id="home-worlds".*?</section>}s ? $& : "";
    $_ = "$nav$cube";
    s{<a [^>]*?href="([^"]+)"[^>]*>}{my $href = $1; "\nlink " . ($href =~ m{^/} ? "$ENV{ORIGIN}$href" : $href) . "\n"}ge;
    s{<[^>]+>}{\n}g;
    print map { s/^\s+|\s+$//gr . "\n" } grep { /\S/ } split /\n/;
  '
}

# The two live homepages' tabs and cube compared, as the live_homepage object.
compare_live_homepages() {
  local ours theirs text status=0 added removed kept
  ours="$(home_words https://template.regents.sh)"
  theirs="$(home_words https://regents.sh)"
  text="$(diff -u --label "template.regents.sh" --label "regents.sh" <(printf '%s\n' "$ours") <(printf '%s\n' "$theirs"))" || status=$?
  case "$status" in
    0) jq -nc '{status: "same", added: null, removed: null, diff: null}' ;;
    1)
      keep_diff live-homepage "$text"
      jq -nc --argjson added "$added" --argjson removed "$removed" --arg diff "$kept" \
        '{status: "differs", added: $added, removed: $removed, diff: $diff}'
      ;;
    *) exit "$status" ;;
  esac
}

sites_read=""
for site in "${@:-${sites[@]}}"; do
  repo="regents-ai/$site"
  rev="$(main_commit "$repo")"
  mix_exs="$(site_file "$repo" "$rev" platform/mix.exs)" || {
    status=$?
    [[ "$status" != 44 ]] || echo "$repo has no platform/mix.exs at ${rev:0:7}" >&2
    exit "$status"
  }
  site_names "$mix_exs"
  mkdir -p "$run/$site"

  files="$(compare shared "${shared[@]}")"
  files+=$'\n'"$(compare build "${build[@]}")"
  live_homepage=null
  if [[ "$site" == regents ]]; then
    files+=$'\n'"$(compare homepage "${homepage[@]}")"
    live_homepage="$(compare_live_homepages)"
  fi
  sites_read+="$(jq -sc --arg site "$site" --arg repo "$repo" --arg main "$rev" \
    --arg app "$app" --arg module "$module" --argjson live_homepage "$live_homepage" \
    '{site: $site, repo: $repo, main: $main, app: $app, module: $module,
      files: ., live_homepage: $live_homepage}' <<<"$files")"$'\n'
done
jq -s --arg template "$(git rev-parse HEAD)" '{template: $template, sites: .}' <<<"$sites_read"
