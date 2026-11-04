# Dot War — notes for Claude

Mobile (Android/iOS) neon dot-swarm strategy: colony building on a hex grid + async PvP attacks.
Godot 4.7 (GDScript) client, TypeScript server on Supabase. Owner talks Polish; all game UI text is Polish.

## Layout
- `sim/` deterministic swarm simulation (GDScript). `server/sim/` = 1:1 TypeScript port.
- `battle/` attack setup + match rules; `server/game/` ports them (plus colony, bots, meta).
- `meta/` colony economy (GD); `server/core/` server logic (sync plausibility, matchmaking, finish, profile, shop).
- `server/game/meta_defs.json` — single source for boosters/leagues/quests/chests (read by TS and `meta/meta_defs.gd`).
- `game/` scenes/UI, `net/` backend client, `supabase/` migrations + Edge Functions (wrap `server/http/handlers.ts`).
- Specs/plans: `docs/superpowers/specs/`, `docs/superpowers/plans/` (one plan per stage).

## Hard rules (determinism = anti-cheat)
- `sim/`, `battle/`, `meta/` and their TS ports: **ints only**, no `Time`/`randf`/`Math.random`; randomness only `SimRng`.
- Integer division: GDScript `/` truncates toward zero → TS uses `Math.trunc` (`Fx.idiv`), never `Math.floor`.
  Hash/RNG are uint32: `Math.imul(...) >>> 0`, `>>> 0` after shifts.
- Iterate in sorted id order; never rely on Dictionary/Map order for anything that changes state.
- `canonical()` is a contract: new state may only append segments that are absent in old vectors.
- Any change to sim/battle/meta rules must change GD **and** TS together.
- `tests/vectors/*.json`, `tests/battle_vectors/*.json` are generated (`/regen-vectors`), never hand-edited
  (a hook blocks it). Old hashes must stay unchanged unless the change is intentional and called out.
- Server writes are atomic (one SQL statement/RPC per Repo method; CAS on `colonies.rev`, claim
  `open→settling`). Crystals: `players.crystals` is the truth, mirrored into `colonies.data.crystals`.
- New SQL functions: `revoke ... from public, anon, authenticated` + grant to `service_role` (schema test checks).

## Commands
- `./scripts/install_godot.sh` once; `./scripts/test.sh` — Godot/GUT suite (fails on parse errors).
- `cd server && npm test` — TS suite (vectors, battle vectors, server core) ~1 s.
- `./scripts/prepare_functions.sh && (cd supabase/functions && deno check <fn>/index.ts)` — type-check functions.
- Screenshots: `xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot --path . --rendering-driver opengl3 --resolution 1280x720 res://game/<scene>.tscn -- --shot <png>`.

## Deploy
- Never deploy by hand. `.github/workflows/supabase.yml` (main or manual dispatch) migrates, pushes auth config,
  deploys functions, runs `scripts/smoke_backend.ts` against the live project (practice attacks only).
- APK: workflow `android`; only `main` builds get the backend URL/anon key (online). Use `/ship`.
- Process per stage: brainstorm → plan → TDD tasks → independent whole-branch review → fix pass → live smoke → main.

## Ponytail (always on)
- `.claude/skills/ponytail*` = vendored DietrichGebert/ponytail (MIT). Mode **full** is active every session:
  follow `.claude/skills/ponytail/SKILL.md` (smallest complete change). Hard rules above still win.
- Off: "stop ponytail" / "normal mode". Also `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`.
