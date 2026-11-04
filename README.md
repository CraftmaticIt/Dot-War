# Dot War

Mobile (Android/iOS) async-PvP strategy: neon dot swarms flowing over a node graph, colony building, tower-defense puzzles. Godot 4.7.

- Design: `docs/superpowers/specs/2026-11-03-dot-war-design.md`
- Stage 1 plan: `docs/superpowers/plans/2026-11-03-stage1-swarm-sim.md`

## Dev

```bash
./scripts/install_godot.sh   # Godot + GUT into .tools/ and addons/gut (no manual setup)
./scripts/test.sh            # all unit tests headless
.tools/godot --path . res://game/prototype.tscn   # play (drag from a cyan node)
```

## Phone build

GitHub Actions → workflow **android** → artifact `dot-war-debug-apk`. Install the APK. Colony screen → **Trening** → **Benchmark** (bottom-right) measures FPS. **Atak** fights a bot colony (needs ≥10 dots: build a Generator).

## Layout

- `sim/` deterministic simulation (ints only, 20 Hz): `SimGraph`, `SimWorld`, `SimTowers`, `SimReplay`
- `ai/` bots (`SimpleBot`, `BotColony` generator)
- `battle/` attack setup (entry nodes) and match rules (stars, loot, trophies)
- `meta/` colony + economy (hex grid, buildings, timers, offline accrual, save, snapshot → `SimGraph`)
- `game/` rendering (MultiMesh neon dots), colony screen (main scene), battle prototype
- `tests/vectors/` determinism vectors — the contract for the TypeScript server verifier
