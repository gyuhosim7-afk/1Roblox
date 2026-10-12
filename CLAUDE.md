# CLAUDE.md — Steal a Slime [+1 SPEED]

Roblox game built with Rojo + Luau. Owner does not code: talk to them in short, easy Korean.

## Resume protocol (read first after any interruption)
1. Read `docs/TODO.md` → continue from the first `[~]` or `[ ]` item.
2. Read `docs/DESIGN.md` for the game design. All numbers live in `src/shared/Config.luau`.
3. Run `scripts/setup.sh` if tools are missing (fresh container), then `scripts/check.sh`.
4. Do not ask the owner for confirmation. Only call them for things that need their computer
   or account (installing Studio/plugins, Roblox login, publishing, creating passes/products).

## Owner's rules (must always hold)
- Monetization exists (passes, dev products, gacha, boosts) but free players can keep progressing.
- Robux-bought random items (Royal Egg, luck boosts) show every outcome's odds (%) **before purchase**;
  odds update live while luck is active. Users with `ArePaidRandomItemsRestricted` (or policy lookup
  failure) cannot buy them; the server blocks it too.
- Purchases go through `ProcessReceipt`: record PurchaseId in the profile, save, and only then return
  `PurchaseGranted`. Never grant twice, never lose a purchase.
- Coins, gems, speed, levels, slimes, gacha results are decided **only on the server**.
  Every client request is validated on the server (distance, cooldown, cost, ownership, rate limit).
- Player data is in DataStore with session locking, retries, autosave, BindToClose. A failed load
  must never overwrite saved data.
- Every screen and control must work on mobile (scale-based UI, big buttons, no keyboard-only actions).
- All numbers (prices, odds, rewards) live in `src/shared/Config.luau`.
- Never use Toolbox models made by others. Build everything in code.
- Commit to Git after each finished feature. Keep `docs/TODO.md` progress up to date.

## Layout
- `default.project.json` — Rojo tree. `src/shared` → ReplicatedStorage.Shared,
  `src/server` → ServerScriptService.Server, `src/client` → StarterPlayer.StarterPlayerScripts.Client.
- `src/server/Services/*` — one module per system, started by `src/server/Main.server.luau`.
- `src/server/Logic/*` and `src/shared/*` — pure logic (no Roblox services), unit-tested in Lune.
- `src/client/Controllers/*` — client systems; `src/client/UI/*` — UI built in code.
- `tests/` — Lune test runner (`tests/run.luau`), Roblox module loader + mocks (`tests/harness/`), specs (`tests/specs/`).
- `tools/` — Lune scripts (balance simulation, place inspection).
- `build/StealASlime.rbxl` — built place file (owner can open it directly in Studio).

## Commands
- `scripts/setup.sh` — install toolchain (rojo, lune, selene, stylua via cargo; luau-lsp from source).
- `scripts/check.sh` — format check, selene lint, luau-lsp type check, Lune tests, rojo build. Must pass before commit.
- `lune run tests/run` — tests only. `lune run tools/simulate` — balance simulation.

## Conventions
- Luau, `--!strict` where practical, tabs (StyLua). Modules return a table; services expose `Init()`/`Start()`.
- Client → server: single RemoteFunction `Request(action, payload)`; server → client: RemoteEvents
  `State`, `Notify`, `Effect`. Names in `src/shared/Remotes.luau`.
- Use `Config` for any tunable number; never hardcode prices/odds elsewhere.
- Testing limitation: this cloud container has no Roblox Studio. Verification = static checks +
  Lune tests with mocks + rbxl build + in-Studio `SelfTest` script (prints PASS/FAIL when run in Studio).
