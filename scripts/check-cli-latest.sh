#!/usr/bin/env bash
# Fails unless this site is on the newest published regents-cli (Sean, 28 Oct 2026:
# every site is always on the newest release). The newest release is read from
# PyPI on every run, so a new release stops every site's next gate until its pin,
# its agent guide and its install lines move to it.
#
#   scripts/check-cli-latest.sh <the Makefile's REGENTS_CLI_REV>
#
# Checks that the pin is the release's tag commit, that the agent guide names the
# release, that commit and the wheel's SHA256, that every install line names the
# release, and that capabilities.json does too. Needs `gh auth login` and curl.
set -euo pipefail

pin=$1
read -r latest wheel < <(curl -fsS https://pypi.org/pypi/regents-cli/json | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(d["info"]["version"], next(u["digests"]["sha256"] for u in d["urls"] if u["packagetype"] == "bdist_wheel"))')
tag=$(gh api "repos/regents-ai/regents-cli/commits/v$latest" --jq .sha)

failed=0
fail() {
  printf 'regents-cli %s is the newest release: %s\n' "$latest" "$1" >&2
  failed=1
}

[ "$pin" = "$tag" ] || fail "move REGENTS_CLI_REV in the Makefile from $pin to $tag."
for word in "regents-cli==$latest" "$tag" "$wheel"; do
  grep -qF "$word" platform/priv/public/agents.md || fail "platform/priv/public/agents.md does not name $word."
done
stale=$(grep -rnoE 'regents-cli==[0-9.]+' platform/priv/public cli | grep -vE "==${latest//./\\.}\$" || true)
[ -z "$stale" ] || fail "these install lines name another release:
$stale"
release=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["cli"]["release"])' platform/priv/capabilities.json)
[ "$release" = "$latest" ] || fail "platform/priv/capabilities.json names $release as cli.release."

exit "$failed"
