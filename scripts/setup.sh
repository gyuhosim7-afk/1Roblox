#!/usr/bin/env bash
# Installs the toolchain in a fresh Linux container (Rust/cargo, clang, cmake, ninja required).
# - rojo, lune, stylua: from crates.io
# - selene: patched to read a local Roblox API dump (the container's TLS proxy breaks its download)
# - luau-lsp: built from source (GitHub release binaries are not reachable here)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${TOOLS_CACHE:-$HOME/.cache/stealaslime-tools}"
mkdir -p "$CACHE" "$HOME/.local/bin"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

have() { command -v "$1" >/dev/null 2>&1; }

have rojo   || cargo install rojo --locked
have lune   || cargo install lune --locked
have stylua || cargo install stylua --locked

API_DUMP="$CACHE/API-Dump.json"
[ -f "$API_DUMP" ] || curl -sSfL -o "$API_DUMP" https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json

if ! have selene || ! SELENE_API_DUMP_PATH="$API_DUMP" selene --version >/dev/null 2>&1; then
  cargo install selene --locked
fi
if [ ! -f "$ROOT/roblox.yml" ]; then
  # Patch selene so `generate-roblox-std` can read a local API dump.
  SRC="$CACHE/selene-src"
  if [ ! -d "$SRC" ]; then
    REG=$(ls -d "$HOME"/.cargo/registry/src/*/selene-0.* 2>/dev/null | tail -1 || true)
    if [ -z "$REG" ]; then cargo install selene --locked; REG=$(ls -d "$HOME"/.cargo/registry/src/*/selene-0.* | tail -1); fi
    cp -r "$REG" "$SRC"
    python3 - "$SRC/src/roblox/generate_std.rs" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='''        let api: ApiDump = ureq::get(API_DUMP)
            .call()
            .context("error when getting API dump")?
            .into_json()
            .context("error when parsing API dump")?;'''
new='''        let api: ApiDump = if let Ok(path) = std::env::var("SELENE_API_DUMP_PATH") {
            let text = std::fs::read_to_string(&path).context("error reading local API dump")?;
            serde_json::from_str(&text).context("error when parsing local API dump")?
        } else {
            ureq::get(API_DUMP).call().context("error when getting API dump")?.into_json().context("error when parsing API dump")?
        };'''
if old in s:
    open(p,'w').write(s.replace(old,new))
PY
    (cd "$SRC" && cargo install --path . --locked --force)
  fi
  (cd "$ROOT" && SELENE_API_DUMP_PATH="$API_DUMP" selene generate-roblox-std)
fi

if ! have luau-lsp; then
  LSP="$CACHE/luau-lsp"
  [ -d "$LSP" ] || GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --recurse-submodules --shallow-submodules https://github.com/JohnnyMorganz/luau-lsp "$LSP"
  (cd "$LSP" && CC=clang CXX=clang++ cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-Wno-error" \
     && cmake --build build --target Luau.LanguageServer.CLI -j "$(nproc)")
  cp "$LSP/build/luau-lsp" "$HOME/.local/bin/"
fi
if [ ! -f "$ROOT/globalTypes.d.luau" ]; then
  curl -sSfL -o "$ROOT/globalTypes.d.luau" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
fi
echo "Toolchain ready: $(rojo --version), $(lune --version), $(selene --version), $(stylua --version), luau-lsp $(luau-lsp --version)"
