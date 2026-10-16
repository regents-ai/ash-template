#!/usr/bin/env bash
# Lists where each site's copies of the template's shared files, and of its build
# and deploy files, differ from the template's own, so drift is seen rather than
# guessed.
#
#   scripts/drift.sh [site ...]      # default: every site below
#
# Reads each site's main branch on GitHub at one commit, and this checkout's files
# as they are. A site's copy is compared after the template's names are renamed to
# the site's, the way scripts/init.sh renames them: the OTP app and module come
# from the site's platform/mix.exs. `mix format` rewraps some lines after a rename,
# so a few differing lines can be wrapping alone. Each difference is written to
# platform/_build/drift/<site>/ for reading. A file a site has no use for yet is
# listed as "not used", with why, from not_used below; a file a site keeps at its
# own path is read there, from moved below. Of platform/mix.exs only the aliases
# are compared, since each site's dependencies are its own. Needs `gh auth login`.
set -euo pipefail

sites=(keyfleet regents autolaunch patchbay techtree)

# The files every site takes from the template, at the template's paths.
shared=(
  platform/lib/ash_template/access_context.ex
  platform/lib/ash_template/accounts/session_authority.ex
  platform/lib/ash_template/actors/human.ex
  platform/lib/ash_template/actors/system.ex
  platform/lib/ash_template/chain_client.ex
  platform/lib/ash_template/repo.ex
  platform/lib/ash_template_web/client_address.ex
  platform/lib/ash_template_web/components/credits_refund_rules.ex
  platform/lib/ash_template_web/components/pairing_box.ex
  platform/lib/ash_template_web/content_security_policy.ex
  platform/lib/ash_template_web/metrics.ex
  platform/lib/ash_template_web/onchain_steps.ex
  platform/lib/ash_template_web/plugs/canonical_host.ex
  platform/lib/ash_template_web/plugs/launch_gate.ex
  platform/lib/ash_template_web/plugs/parsers.ex
  platform/lib/ash_template_web/read.ex
  platform/assets/js/copy_buttons.ts
  platform/assets/js/hook_composition.ts
  platform/assets/js/hooks/motion/buttons.ts
  platform/assets/js/hooks/motion/moments.ts
  platform/assets/js/hooks/motion/press.ts
  platform/assets/js/hooks/motion/reveals.ts
  platform/assets/js/hooks/motion/shared.ts
  platform/assets/js/hooks/motion/slides.ts
  platform/assets/js/hooks/onchain_steps.ts
  platform/assets/js/motion.ts
  platform/assets/js/wallet_actions/connected_wallet.ts
  platform/assets/js/wallet_actions/send_step.ts
  platform/assets/css/components/motion.css
  scripts/readiness.sh
  scripts/release.sh
)

# The files that build, check and deploy every site, at the template's paths.
build=(
  Makefile
  scripts/deploy.sh
  platform/Dockerfile
  platform/fly.toml
  platform/repo.yaml
  platform/mix.exs
  platform/config/prod.exs
  platform/config/runtime.exs
  platform/rel/overlays/bin/migrate
  platform/rel/overlays/bin/pending-migrations
  platform/rel/overlays/bin/bootstrap-staging
  platform/.tool-versions
  platform/.formatter.exs
  platform/.credo.exs
  platform/.sobelow-conf
)

# Shared files a site has no use for yet, with why. Such a file is listed as "not used"
# rather than missing; the site takes it the day it needs it, and its line goes.
not_used() {
  case "$1:$2" in
    techtree:platform/lib/ash_template_web/plugs/launch_gate.ex) echo "public, no sign-in: never closed" ;;
    techtree:platform/lib/ash_template_web/read.ex) echo "no page reads in the background" ;;
    techtree:platform/lib/ash_template/access_context.ex | \
      techtree:platform/lib/ash_template/accounts/* | \
      techtree:platform/lib/ash_template/actors/*) echo "no one signs in on its pages" ;;
    techtree:platform/lib/ash_template/chain_client.ex | \
      techtree:platform/lib/ash_template_web/onchain_steps.ex | \
      techtree:platform/assets/js/hooks/onchain_steps.ts | \
      techtree:platform/assets/js/wallet_actions/*) echo "no on-chain buttons" ;;
    patchbay:platform/lib/ash_template_web/plugs/launch_gate.ex | \
      autolaunch:platform/lib/ash_template_web/plugs/launch_gate.ex) echo "launched and open to everyone: never closed" ;;
    *) return 1 ;;
  esac
}

# Shared files a site keeps at its own path, which is where they are read.
moved() {
  case "$1:$2" in
    keyfleet:platform/lib/ash_template_web/onchain_steps.ex) echo platform/lib/keyfleet_web/wallet/onchain_steps.ex ;;
    autolaunch:platform/lib/ash_template/chain_client.ex) echo platform/lib/autolaunch/chain/node_client.ex ;;
    *) return 1 ;;
  esac
}

# The part of a file that is compared: the aliases of platform/mix.exs, all of any other.
compared() {
  case "$1" in
    platform/mix.exs) sed -n '/^  defp aliases do$/,/^  end$/p' ;;
    *) cat ;;
  esac
}

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="platform/_build/drift"

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

# Compares the template's files named after the heading with the current site's copies.
compare() {
  local heading="$1" path site_path why theirs ours diff_file added removed
  local same=0 differ=0 missing=0 unused=0
  shift
  echo "  $heading"
  for path in "$@"; do
    site_path="$(moved "$site" "$path")" || site_path="${path//ash_template/$app}"
    if why="$(not_used "$site" "$path")"; then
      printf '    not used %s  (%s)\n' "$site_path" "$why"
      unused=$((unused + 1))
      continue
    fi
    if ! theirs="$(site_file "$repo" "$rev" "$site_path")"; then
      printf '    missing  %s\n' "$site_path"
      missing=$((missing + 1))
      continue
    fi
    ours="$(perl -pe "s/ash_template/$app/g; s/AshTemplate/$module/g; s/ashTemplate/$camel/g; s/ASH_TEMPLATE/$upper/g; s/ash-template/$kebab/g" "$path" | compared "$path")"
    theirs="$(compared "$path" <<<"$theirs")"
    diff_file="$out/$site/$(tr / _ <<<"$site_path").diff"
    if diff -u --label "template/$path" --label "$site/$site_path" <(printf '%s\n' "$ours") <(printf '%s\n' "$theirs") >"$diff_file"; then
      rm "$diff_file"
      printf '    same     %s\n' "$site_path"
      same=$((same + 1))
    else
      added="$(tail -n +3 "$diff_file" | grep -c '^+' || true)"
      removed="$(tail -n +3 "$diff_file" | grep -c '^-' || true)"
      printf '    differs  %s  (+%s -%s)\n' "$site_path" "$added" "$removed"
      differ=$((differ + 1))
    fi
  done
  printf '    %s same, %s differ, %s missing, %s not used\n' "$same" "$differ" "$missing" "$unused"
}

for site in "${@:-${sites[@]}}"; do
  repo="regents-ai/$site"
  rev="$(gh api "repos/$repo/commits/main" --jq .sha)"
  mix_exs="$(site_file "$repo" "$rev" platform/mix.exs)"
  app="$(sed -nE 's/^[[:space:]]*app: :([a-z0-9_]+),.*/\1/p' <<<"$mix_exs" | head -1)"
  module="$(sed -nE 's/^defmodule ([A-Za-z0-9]+)\.MixProject do$/\1/p' <<<"$mix_exs")"
  camel="$(printf '%s' "${module:0:1}" | tr '[:upper:]' '[:lower:]')${module:1}"
  upper="$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')"
  kebab="${app//_/-}"

  echo "$site  ($repo main ${rev:0:7}; app $app, $module)"
  mkdir -p "$out/$site"
  find "$out/$site" -name '*.diff' -delete
  compare "Shared files" "${shared[@]}"
  compare "Build and deploy files" "${build[@]}"
  echo
done
echo "Differences are in $out/<site>/."
