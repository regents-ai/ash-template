#!/usr/bin/env bash
# The live check (skills/regent-workflow, "Live checks"): template.regents.sh read
# the way an agent reads it, never with raw curl.
#
#   SIWA_AGENT_HOME=<the agent's key folder> SIWA_CLIENT=<its siwa_agent.py> make live-check
#
# SIWA_AGENT_HOME is the folder holding the agent's key.json, as the regents CLI and
# the SIWA client both read it; SIWA_CLIENT is that client's siwa_agent.py. Give both
# as full paths.
# 1. The CLI as the paired agent: regents ash-template doctor, then agents whoami;
#    the agent must be paired.
# 2. WebMCP in headless Chromium (platform/test/live): the public pages and
#    documents at 1280 and 390 wide, the live commit from /capabilities.json, and
#    every read-only tool the home page offers that takes no input, the signed ones
#    signed with the agent's key through SIWA_CLIENT.
# It runs from a checkout of the live commit, after a release: the browser half
# checks the site against this checkout's page map and tool manifest. It writes only
# the agent's own row on the site, when the agent was last seen (added the first
# time), and the pages start no visit (Global Privacy Control). The CLI signs the
# agent in again when its sign-in is about to end, as it does for any command. A site
# copying this script sets its own address and CLI group below and keeps every check
# the same.
set -euo pipefail

live_url="https://template.regents.sh"
cli_site="ash-template"

: "${SIWA_AGENT_HOME:?Set SIWA_AGENT_HOME to the folder holding the key of the agent this check runs as.}"
: "${SIWA_CLIENT:?Set SIWA_CLIENT to the SIWA client (siwa_agent.py) that signs as that agent.}"
[ -f "$SIWA_AGENT_HOME/key.json" ] || { echo "$SIWA_AGENT_HOME holds no key.json. Give its full path." >&2; exit 1; }
[ -f "$SIWA_CLIENT" ] || { echo "$SIWA_CLIENT is not a file. Give its full path." >&2; exit 1; }
# Full paths, as the browser half runs the client from another folder.
SIWA_AGENT_HOME="$(CDPATH='' cd -- "$SIWA_AGENT_HOME" && pwd)"
SIWA_CLIENT="$(CDPATH='' cd -- "$(dirname -- "$SIWA_CLIENT")" && pwd)/$(basename -- "$SIWA_CLIENT")"
root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
CHECKOUT_COMMIT="$(git -C "$root" rev-parse HEAD)"
export SIWA_AGENT_HOME SIWA_CLIENT CHECKOUT_COMMIT

echo "==> CLI: regents $cli_site doctor"
regents "$cli_site" doctor --base-url "$live_url"

echo "==> CLI: regents $cli_site agents whoami"
answer="$(regents "$cli_site" agents whoami --json --base-url "$live_url")" || { echo "$answer" >&2; exit 1; }
status="$(printf '%s' "$answer" | python3 -c 'import json, sys; d = json.load(sys.stdin)["data"]; print(d["status"], d["agent"]["wallet"])')"
echo "$status"
case "$status" in
  "paired "*) ;;
  *) echo "The agent with the key in $SIWA_AGENT_HOME is not paired on $live_url." >&2; exit 1 ;;
esac

echo "==> WebMCP and pages in headless Chromium"
cd "$root/platform"
LIVE_URL="$live_url" npx playwright test --config playwright.live.config.ts
