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
# its own, and the Makefile is compared without the template's own passages, which
# scripts/init.sh drops.
#
# The template's homepage tracks regents.sh's, so for regents two more checks run:
# the homepage files the template shares with regents.sh (the still picture compared
# by its git blob id), and the two live homepages' tabs, glass panel and copyright
# (each tab and its link, every link in the panel, then the copyright), as visitors
# see them.
#
# Prints one JSON document:
#
#   {"template": this checkout's commit,
#    "sites": [{"site", "repo", "main", "app", "module",
#               "files": [{"list", "path", "site_path", "status",
#                          "added", "removed", "diff", "why"}],
#               "live_homepage": null or {"status", "added", "removed", "diff", "why"}}]}
#
# list is shared, build or homepage; status is same, differs, missing (GitHub
# answers 404) or not_used; a live homepage is missing, with why, when a page has no
# glass panel. A difference's added and removed lines are counted, and the
# difference itself is written to the file diff names, in a folder of this run's own
# under platform/_build/drift/; a picture that differs has neither. Fields that do
# not apply are null. Needs `gh auth login`, jq and curl.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
source scripts/github.sh
source scripts/shared-files.sh
mkdir -p platform/_build/drift
run="$(mktemp -d "platform/_build/drift/$(date -u +%Y%m%dT%H%M%SZ)-XXXX")"

# The part of a file that is compared: the aliases of platform/mix.exs, the Makefile
# as scripts/init.sh leaves it, all of any other.
compared() {
  case "$1" in
    platform/mix.exs) sed -n '/^  defp aliases do$/,/^  end$/p' ;;
    Makefile) perl -0777 -pe 's/^# template-only\n.*?^# \/template-only\n//gms' ;;
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

# Prints the git blob id of a file in a site's repository at a commit, so a picture is
# compared without its bytes passing through the shell; exits 44 when it is absent.
site_blob() {
  local repo="$1" rev="$2" path="$3" body
  if body="$(gh api "repos/$repo/contents/$path?ref=$rev" --jq .sha 2>&1)"; then
    printf '%s\n' "$body"
  elif [[ "$body" == *"HTTP 404"* ]]; then
    return 44
  else
    echo "$repo $path: $body" >&2
    exit 1
  fi
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
    if [[ "$path" == *.webp ]]; then
      theirs="$(site_blob "$repo" "$rev" "$site_path")" || {
        status=$?
        [[ "$status" == 44 ]] || exit "$status"
        entry "$list" "$path" "$site_path" missing
        continue
      }
      if [[ "$theirs" == "$(git hash-object "$path")" ]]; then
        entry "$list" "$path" "$site_path" same
      else
        entry "$list" "$path" "$site_path" differs
      fi
      continue
    fi
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

# A live homepage's tabs, glass panel and copyright as visitors see them: each
# tab's words and link, then every other link in the panel, then the copyright that
# stands outside the panel, each on its own line, the page's markup dropped and a
# link within the site written with the site's address.
home_words() {
  curl -fsS --max-time 20 "$1/" | ORIGIN="$1" perl -0777 -ne '
    my $glass = m{<section[^>]*id="home-glass".*?</section>}s ? $& : "";
    my $copyright = m{<p class="home__copyright">.*?</p>}s ? $& : "";
    my $nav = $glass =~ s{<nav[^>]*class="home__foot".*?</nav>}{}s ? $& : "";
    my @links = $glass =~ m{<a [^>]*?href="([^"]+)"}g;
    $_ = $nav . join("", map { "<a href=\"$_\">" } @links) . $copyright;
    s{<!--.*?-->}{}gs;
    s{<a [^>]*?href="([^"]+)"[^>]*>}{my $href = $1; "\nlink " . ($href =~ m{^/} ? "$ENV{ORIGIN}$href" : $href) . "\n"}ge;
    s{<[^>]+>}{\n}g;
    print map { s/^\s+|\s+$//gr . "\n" } grep { /\S/ } split /\n/;
  '
}

# The two live homepages' tabs, glass panel and copyright compared, as the
# live_homepage object.
compare_live_homepages() {
  local ours theirs text status=0 added removed kept
  ours="$(home_words https://template.regents.sh)"
  theirs="$(home_words https://regents.sh)"
  local bare=()
  [[ -n "$ours" ]] || bare+=(template.regents.sh)
  [[ -n "$theirs" ]] || bare+=(regents.sh)
  if ((${#bare[@]})); then
    jq -nc --arg why "no glass panel on ${bare[*]}" \
      '{status: "missing", added: null, removed: null, diff: null, why: $why}'
    return
  fi
  text="$(diff -u --label "template.regents.sh" --label "regents.sh" <(printf '%s\n' "$ours") <(printf '%s\n' "$theirs"))" || status=$?
  case "$status" in
    0) jq -nc '{status: "same", added: null, removed: null, diff: null, why: null}' ;;
    1)
      keep_diff live-homepage "$text"
      jq -nc --argjson added "$added" --argjson removed "$removed" --arg diff "$kept" \
        '{status: "differs", added: $added, removed: $removed, diff: $diff, why: null}'
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
