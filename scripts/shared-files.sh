# shellcheck shell=bash
# The template files the sites share, and how a site names them, for scripts/drift.sh
# and scripts/harvest.sh, which source this file.
# shellcheck disable=SC2034 # the lists are read by the scripts that source this file

# The files every site takes from the template, at the template's paths.
shared=(
  platform/lib/ash_template/access_context.ex
  platform/lib/ash_template/accounts/session_authority.ex
  platform/lib/ash_template/actors/human.ex
  platform/lib/ash_template/actors/system.ex
  platform/lib/ash_template/chain_client.ex
  platform/lib/ash_template/repo.ex
  platform/lib/ash_template_web/client_address.ex
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
  platform/rel/overlays/bin/room-reports
  platform/rel/overlays/bin/remove-room-message
  platform/.tool-versions
  platform/.formatter.exs
  platform/.credo.exs
  platform/.sobelow-conf
)

# The files of the homepage the template copies from regents.sh, compared with
# regents.sh's alone.
homepage=(
  platform/lib/ash_template_web/components/world_cube.ex
  platform/assets/js/hooks/world_cube.ts
  platform/assets/js/hooks/cube_label.ts
  platform/assets/css/pages/home.css
  platform/assets/css/components/world_cube.css
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

# Shared files a site keeps at its own path, which is where they are read: the site,
# the template's path, the site's path.
moved_files=(
  "keyfleet platform/lib/ash_template_web/onchain_steps.ex platform/lib/keyfleet_web/wallet/onchain_steps.ex"
  "autolaunch platform/lib/ash_template/chain_client.ex platform/lib/autolaunch/chain/node_client.ex"
)

# The site's path of a shared file it keeps at its own path, or a failure.
moved() {
  local entry site path site_path
  for entry in "${moved_files[@]}"; do
    read -r site path site_path <<<"$entry"
    if [[ "$site" == "$1" && "$path" == "$2" ]]; then
      echo "$site_path"
      return
    fi
  done
  return 1
}

# Sets app, module, camel, upper, kebab and task_prefix, the site's names for the
# template's ash_template, AshTemplate, ashTemplate, ASH_TEMPLATE, ash-template and its
# Mix task prefix, from the site's platform/mix.exs given as $1, as scripts/init.sh
# derives them.
site_names() {
  app="$(sed -nE 's/^[[:space:]]*app: :([a-z0-9_]+),.*/\1/p' <<<"$1" | head -1)"
  module="$(sed -nE 's/^defmodule ([A-Za-z0-9]+)\.MixProject do$/\1/p' <<<"$1")"
  if [[ -z "$app" || -z "$module" ]]; then
    echo "platform/mix.exs names no OTP app or no MixProject module" >&2
    return 1
  fi
  camel="$(printf '%s' "${module:0:1}" | tr '[:upper:]' '[:lower:]')${module:1}"
  upper="$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')"
  kebab="${app//_/-}"
  task_prefix="$(printf '%s' "$module" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')"
}
