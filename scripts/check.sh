#!/usr/bin/env bash
# Runs every check. Must pass before each commit.
#   scripts/check.sh          -> format check, lint, type check, tests, build
#   scripts/check.sh --fix    -> also auto-format with StyLua first
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/bin:$PATH"
have_rojo() { rojo --version >/dev/null 2>&1; }

if [ "${1:-}" = "--fix" ]; then
  stylua src tests tools
fi

echo "== StyLua (format)"
stylua --check src tests tools

echo "== Selene (lint)"
selene src

echo "== luau-lsp (type check)"
if have_rojo; then rojo sourcemap default.project.json -o sourcemap.json >/dev/null; else lune run tools/sourcemap sourcemap.json; fi
OUT=$(luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json --base-luaurc=.luaurc \
  --ignore="tests/**" --ignore="tools/**" src/ 2>&1 | grep -v -E '^\[(INFO|WARN)\]' || true)
if [ -n "$OUT" ]; then echo "$OUT"; echo "Type check failed"; exit 1; fi
echo "ok"

echo "== Lune tests"
lune run tests/run

echo "== Rojo build"
if have_rojo; then
  rojo build default.project.json -o build/StealASlime.rbxl
else
  lune run tools/build_place build/StealASlime.rbxl
fi
echo "All checks passed."
