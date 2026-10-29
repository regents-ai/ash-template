# Reading the sites' repositories on GitHub, for scripts/drift.sh and scripts/pins.sh,
# which source this file. Needs `gh auth login`.

# The commit a repository's main branch is at.
main_commit() {
  gh api "repos/$1/commits/main" --jq .sha
}

# Prints a file from a site's repository at a commit; exits 44 when it is absent.
site_file() {
  local repo="$1" rev="$2" path="$3" body
  if body="$(gh api -H "Accept: application/vnd.github.raw" "repos/$repo/contents/$path?ref=$rev" 2>&1)"; then
    printf '%s\n' "$body"
  elif [[ "$body" == *"HTTP 404"* ]]; then
    return 44
  else
    echo "$repo $path: $body" >&2
    exit 1
  fi
}
