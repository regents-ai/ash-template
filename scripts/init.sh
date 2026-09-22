#!/usr/bin/env bash
# Renames the Ash Template placeholder product to your product, in one pass.
#
#   scripts/init.sh <snake_name> <ModuleName> ["Display Name"]
#
# Example: scripts/init.sh keyfleet KeyFleet
#
# Rewrites every spelling of the placeholder across the monorepo:
#   ash_template  -> keyfleet     (OTP app, Mix tasks, databases, schema, session key)
#   AshTemplate   -> KeyFleet     (Elixir modules)
#   ASH_TEMPLATE  -> KEYFLEET     (environment variables)
#   ash-template  -> keyfleet     (package and Fly names)
#   Ash Template  -> KeyFleet     (public copy; the display name, "KeyFleet" by default)
# and renames the files and directories that carry the app name. Run it once,
# from a clean checkout, before the first commit of the new product.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: scripts/init.sh <snake_name> <ModuleName> [\"Display Name\"]" >&2
  exit 64
fi

snake="$1"
module="$2"
display="${3:-$2}"

if [[ ! "$snake" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "snake_name must be lowercase letters, digits and underscores, starting with a letter" >&2
  exit 64
fi
if [[ ! "$module" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "ModuleName must be CamelCase letters and digits, starting with a capital" >&2
  exit 64
fi

kebab="${snake//_/-}"
upper="$(printf '%s' "$snake" | tr '[:lower:]' '[:upper:]')"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "commit or stash your changes first: init.sh rewrites the whole tree" >&2
  exit 65
fi

# Directories and files named after the app, deepest first so parents move last.
git ls-files -z | tr '\0' '\n' | grep 'ash_template' | awk -F/ '{print NF, $0}' | sort -rn | cut -d' ' -f2- |
  while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    if [[ "$base" == *ash_template* ]]; then
      git mv "$path" "$dir/${base//ash_template/$snake}"
    fi
  done
# Directory names are not listed by git ls-files; rename the ones that remain.
while IFS= read -r dir; do
  git mv "$dir" "$(dirname "$dir")/$(basename "$dir" | sed "s/ash_template/$snake/g")"
done < <(find . -type d -name '*ash_template*' -not -path './.git/*' -not -path '*/_build/*' -not -path '*/deps/*' -not -path '*/node_modules/*' | awk -F/ '{print NF, $0}' | sort -rn | cut -d' ' -f2-)

# Contents: every tracked text file, longest spelling first.
git ls-files -z | while IFS= read -r -d '' path; do
  [[ -f "$path" ]] || continue
  grep -Iq . "$path" || continue
  if grep -q 'ash_template\|AshTemplate\|ASH_TEMPLATE\|ash-template\|Ash Template' "$path"; then
    perl -pi -e "s/ash_template/$snake/g; s/AshTemplate/$module/g; s/ASH_TEMPLATE/$upper/g; s/ash-template/$kebab/g; s/Ash Template/$display/g" "$path"
  fi
done

git rm -q -- scripts/init.sh
cat <<EOF
Renamed Ash Template to $display ($snake / $module).
Review with: git status
Then from platform/, with the shared dependencies in place:
  createdb ${snake}_dev
  mix setup
  mix ${snake}.route_handoff   # the route catalog digest includes the display name
  mix precommit
EOF
