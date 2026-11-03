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

GitHub Actions → workflow **android** → artifact `dot-war-debug-apk`. Install the APK, tap **Benchmark** in the bottom-right corner to measure FPS.

## Layout

- `sim/` deterministic simulation (ints only, 20 Hz): `SimGraph`, `SimWorld`, `SimTowers`, `SimReplay`
- `ai/` bots
- `game/` rendering (MultiMesh neon dots), input, scenes
- `tests/vectors/` determinism vectors — the contract for the TypeScript server verifier
