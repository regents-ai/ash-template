#!/usr/bin/env bash
# Deploys the committed tree to one Fly app, and nothing else.
#
#   scripts/deploy.sh <fly-app>        # the hosted demo: scripts/deploy.sh template-regents-sh
#
# It refuses a working tree with any change, and a commit that is not on
# origin/main, so what runs is always what the repository holds. The app is named
# here, never in fly.toml, so the same configuration serves every site built
# from the template. The image is labelled with the short commit it was built
# from. The build runs on Fly's builders from the repository root, where
# .dockerignore admits only platform/ and skills/.
set -euo pipefail

if [[ $# -ne 1 || -z $1 ]]; then
  echo "Usage: scripts/deploy.sh <fly-app>" >&2
  exit 2
fi
app="$1"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Refusing to deploy: commit or remove every change first." >&2
  exit 1
fi

git fetch --quiet origin main
commit="$(git rev-parse HEAD)"
if ! git merge-base --is-ancestor "$commit" origin/main; then
  echo "Refusing to deploy: ${commit:0:7} is not on origin/main. Push it to main first." >&2
  exit 1
fi

echo "==> Deploying ${commit:0:7} to $app"
exec fly deploy . \
  --config platform/fly.toml \
  --app "$app" \
  --ha=false \
  --remote-only \
  --image-label "${commit:0:7}"
