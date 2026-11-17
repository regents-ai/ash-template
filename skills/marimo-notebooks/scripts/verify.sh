#!/usr/bin/env bash
# The gate a marimo notebook passes before it is handed back.
#
#   verify.sh notebook.py            lint, run top to bottom as a script, run its tests
#   verify.sh notebook.py --wasm     the same, plus the browser (WebAssembly) lint rules
#   verify.sh notebook.py -- --n 10  the same, passing arguments to the script run (mo.cli_args)
#
# Everything runs in one throwaway environment built from the notebook's own
# `# /// script` header, so a package the header forgets fails here, not on the
# reader's machine. Needs `uv`. Exits non-zero on the first failure.
set -euo pipefail

notebook="${1:?usage: verify.sh notebook.py [--wasm] [-- script arguments]}"
shift
wasm=false
script_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --wasm) wasm=true; shift ;;
    --) shift; script_args=("$@"); break ;;
    *) echo "verify.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

if ! grep -q '^# /// script' "$notebook"; then
  echo "verify.sh: $notebook has no '# /// script' header; add one listing every package it imports." >&2
  exit 1
fi

requirements="$(mktemp)"
trap 'rm -f "$requirements"' EXIT
uv export --quiet --script "$notebook" --no-hashes > "$requirements"

export PYTHONDONTWRITEBYTECODE=1
in_env() { uv run --quiet --no-project --with-requirements "$requirements" --with pytest "$@"; }

echo "== lint (marimo check --strict)"
in_env marimo check --strict "$notebook"

if [ "$wasm" = true ]; then
  echo "== browser lint (marimo check --select MW)"
  in_env marimo check --strict --select MW "$notebook"
fi

echo "== run as a script"
in_env python "$notebook" ${script_args[@]+"${script_args[@]}"} > /dev/null

if grep -qE '^\s+def test_|^def test_' "$notebook"; then
  echo "== tests (pytest)"
  in_env pytest -q -p no:cacheprovider "$notebook"
fi

echo "ok: $notebook"
