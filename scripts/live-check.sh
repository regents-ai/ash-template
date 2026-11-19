#!/usr/bin/env bash
# The live check (skills/regent-workflow, "Live checks"): template.regents.sh read
# the way an agent reads it, never with raw curl.
#
#   SIWA_AGENT_HOME=<the agent's key folder> make live-check
#
# SIWA_AGENT_HOME is the folder holding the agent's key.json, as the regents CLI
# reads it. Give it as a full path.
# The CLI as the paired agent: regents ash-template doctor, then agents whoami; the
# agent must be paired. It writes only the agent's own row on the site, when the
# agent was last seen (added the first time). The CLI signs the agent in again when
# its sign-in is about to end, as it does for any command. A site copying this
# script sets its own address and CLI group below and keeps every check the same.
set -euo pipefail

live_url="https://template.regents.sh"
cli_site="ash-template"

: "${SIWA_AGENT_HOME:?Set SIWA_AGENT_HOME to the folder holding the key of the agent this check runs as.}"
[ -f "$SIWA_AGENT_HOME/key.json" ] || { echo "$SIWA_AGENT_HOME holds no key.json. Give its full path." >&2; exit 1; }
export SIWA_AGENT_HOME

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
