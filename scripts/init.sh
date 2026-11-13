#!/usr/bin/env bash
# Renames the Ash Template placeholder product to your product, in one pass.
#
#   scripts/init.sh <snake_name> <ModuleName> ["Display Name"]
#
# Example: scripts/init.sh night_owl NightOwl "Night Owl"
#
# Rewrites every spelling of the placeholder across the monorepo:
#   ash_template  -> night_owl    (OTP app, Mix tasks, databases, schema, session key)
#   AshTemplate   -> NightOwl     (Elixir modules)
#   ashTemplate   -> nightOwl     (JavaScript names)
#   ASH_TEMPLATE  -> NIGHT_OWL    (environment variables)
#   ash-template  -> night-owl    (package and Fly names)
#   Ash Template  -> Night Owl    (public copy; the display name, the module name by default)
#   ASH TEMPLATE  -> NIGHT OWL    (capitalised legal copy; the display name in capitals)
# and renames the files and directories that carry the app name. Where a name means
# the template itself it stays as written: everything in skills/, the shared Regent
# skills every site carries as the template's text, names and contents; the dated
# plans (docs/*-plan.md) and CHANGELOG.md's earlier entries, which are records; the
# review rules AGENTS.md copies from skills/rollout-guidance-check; and ash-template
# in the Makefile and platform/scripts/check_required_fixes.exs, where it names the
# template's repository. It drops the Markdown passages fenced by
# <!-- template-only --> and <!-- /template-only --> and the Makefile passages fenced
# by "# template-only" and "# /template-only" that belong to the template itself,
# removes the template's own scripts (its reports on Regent's sites, their daily
# jobs' instructions and scripts/regent-ui-update), and records the rename at the end
# of CHANGELOG.md. Run it once, from a clean checkout, before the first commit of the
# new product.
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
camel="$(printf '%s' "${module:0:1}" | tr '[:upper:]' '[:lower:]')${module:1}"
display_upper="$(printf '%s' "$display" | tr '[:lower:]' '[:upper:]')"
# Mix names a task after its module, so `Mix.Tasks.NightOwl.RouteHandoff` is
# `mix night_owl.route_handoff` whatever the OTP app is called.
task_prefix="$(printf '%s' "$module" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "commit or stash your changes first: init.sh rewrites the whole tree" >&2
  exit 65
fi

# Left as written, names and contents: the shared Regent skills, which every site
# carries as the template's text, and the dated plans and the changelog, which are
# records.
as_written=(skills 'docs/*-plan.md' CHANGELOG.md)
# The template's own scripts, which a new product has no use for: the reports that
# compare Regent's sites with the template, their file lists and tests, the
# instructions of the daily jobs that read them, and scripts/regent-ui-update, which
# moves the five Regent sites onto one design-system commit. They are removed below.
removed=(
  scripts/drift.sh scripts/pins.sh scripts/github.sh scripts/shared-files.sh scripts/harvest.sh
  scripts/stale-prs.sh scripts/tests/test_reports.py automation/harvest.md automation/spread.md
  scripts/regent-ui-update
)
# Every tracked file the rename reads: all but this script and the two lists above.
renaming=(':!scripts/init.sh' "${as_written[@]/#/:!}" "${removed[@]/#/:!}")

renamed() {
  local name="$1"
  # Mix task files are named after the task, which follows the module name.
  if [[ "$name" =~ ^ash_template\.($tasks)\.ex$ ]]; then
    printf '%s' "$task_prefix.${BASH_REMATCH[1]}.ex"
    return
  fi
  name="${name//ash_template/$snake}"
  printf '%s' "${name//ash-template/$kebab}"
}

deepest_first() {
  awk -F/ '{print NF, $0}' | sort -rn | cut -d' ' -f2-
}

# The Mix tasks this repository defines, read before their files move, so that
# `mix ash_template.<task>` follows the module name.
tasks="$(cd platform/lib/mix/tasks && ls ash_template.*.ex | sed -E 's/^ash_template\.(.*)\.ex$/\1/' | paste -sd '|' -)"

# Files named after the app, deepest first so parents move last.
git ls-files -- "${renaming[@]}" | grep -e 'ash_template' -e 'ash-template' | deepest_first |
  while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    base="$(basename "$path")"
    target="$(renamed "$base")"
    [[ "$target" == "$base" ]] || git mv "$path" "$(dirname "$path")/$target"
  done
# Directory names are not listed by git ls-files; rename the ones that remain, outside
# skills/.
while IFS= read -r dir; do
  git mv "$dir" "$(dirname "$dir")/$(renamed "$(basename "$dir")")"
done < <(find . -type d \( -name '*ash_template*' -o -name '*ash-template*' \) -not -path './.git/*' -not -path './skills/*' -not -path '*/_build/*' -not -path '*/deps/*' -not -path '*/node_modules/*' | deepest_first)

# Contents: every text file the rename reads, task names first, then the longest
# spelling first. In the Makefile and platform/scripts/check_required_fixes.exs,
# ash-template names the template's repository, whose required fixes every product
# checks against, so it stays. The review rules between AGENTS.md's REGENT ROLLOUT
# REVIEW markers stay as skills/rollout-guidance-check/scripts/sync_review.py writes
# them.
git ls-files -z -- "${renaming[@]}" | while IFS= read -r -d '' path; do
  [[ -f "$path" ]] || continue
  grep -Iq . "$path" || continue
  case "$path" in
    Makefile | platform/scripts/check_required_fixes.exs) kebab_rule="" ;;
    *) kebab_rule="s/ash-template/$kebab/g;" ;;
  esac
  if grep -q 'ash_template\|AshTemplate\|ashTemplate\|ASH_TEMPLATE\|ash-template\|Ash Template\|ASH TEMPLATE' "$path"; then
    perl -pi -e "next if /^<!-- BEGIN REGENT ROLLOUT REVIEW -->/ .. /^<!-- END REGENT ROLLOUT REVIEW -->/; s/ash_template\.($tasks)\b/$task_prefix.\$1/g; s/ash_template/$snake/g; s/AshTemplate/$module/g; s/ashTemplate/$camel/g; s/ASH_TEMPLATE/$upper/g; $kebab_rule s/Ash Template/$display/g; s/ASH TEMPLATE/$display_upper/g" "$path"
  fi
done

# Passages that belong to the template itself, fenced in Markdown comments and in
# Makefile comments.
git ls-files -z -- '*.md' "${renaming[@]}" | while IFS= read -r -d '' path; do
  grep -q '<!-- template-only -->' "$path" || continue
  perl -0777 -pi -e 's/<!-- template-only -->\n.*?<!-- \/template-only -->\n\n?//gs' "$path"
done
perl -0777 -pi -e 's/^# template-only\n.*?^# \/template-only\n//gms' Makefile
if git grep -q -e 'template-only' -- "${renaming[@]}"; then
  echo "a template-only fence is still open; every passage needs both markers on their own lines" >&2
  exit 70
fi

cat >> CHANGELOG.md <<EOF

## $(date -u +%F) — Renamed to $display

- Renamed the Ash Template placeholder to $display (\`$snake\`, \`$module\`,
  \`$kebab\`, \`${upper}_\`) with \`scripts/init.sh\`, which removed itself,
  the template's reports on Regent's sites, its daily jobs' instructions and
  \`scripts/regent-ui-update\`. The shared skills in \`skills/\`, the dated plans
  in \`docs/\` and the entries above keep the template's names as written.
EOF

git rm -q -- scripts/init.sh "${removed[@]}"
cat <<EOF
Renamed Ash Template to $display ($snake / $module).
Review with: git status
Then from platform/, with the shared dependencies in place:
  mix setup
  mix ecto.create
  mix format                        # shorter or longer names change line wrapping
  mix ${task_prefix}.route_handoff  # the route catalog digest includes the display name
  mix precommit
EOF
