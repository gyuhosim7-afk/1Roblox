#!/usr/bin/env bash
# Runs every check. Must pass before each commit.
#   scripts/check.sh          -> format check, lint, type check, tests, build
#   scripts/check.sh --fix    -> also auto-format with StyLua first
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

if [ "${1:-}" = "--fix" ]; then
  stylua src tests tools
fi

echo "== StyLua (format)"
stylua --check src tests tools

echo "== Selene (lint)"
selene src

echo "== luau-lsp (type check)"
rojo sourcemap default.project.json -o sourcemap.json >/dev/null
OUT=$(luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json --base-luaurc=.luaurc \
  --ignore="tests/**" --ignore="tools/**" src/ 2>&1 | grep -v -E '^\[(INFO|WARN)\]' || true)
if [ -n "$OUT" ]; then echo "$OUT"; echo "Type check failed"; exit 1; fi
echo "ok"

echo "== Lune tests"
lune run tests/run

echo "== Rojo build"
rojo build default.project.json -o build/StealASlime.rbxl
echo "All checks passed."
