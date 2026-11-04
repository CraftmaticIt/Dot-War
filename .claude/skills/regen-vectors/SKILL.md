---
name: regen-vectors
description: Regenerate the GDScript<->TypeScript determinism vectors (tests/vectors, tests/battle_vectors, tests/pve_vectors) and prove old hashes are unchanged and both sides agree. Use after any change to sim/, battle/, meta/ or their TS ports, or when adding a vector.
disable-model-invocation: true
---

# Regenerate determinism vectors

1. Snapshot current hashes:
   `for f in tests/vectors/*.json tests/battle_vectors/*.json tests/pve_vectors/*.json; do jq -r --arg f "$f" '"\($f) \(.expected_hash // .expected.hash)"' "$f"; done > /tmp/claude-0/hashes_before.txt`
2. Regenerate (import first so class_names resolve):
   `.tools/godot --headless --path . --import >/dev/null 2>&1`
   `.tools/godot --headless --path . -s tools/gen_vectors.gd`
   `timeout 280 .tools/godot --headless --path . -s tools/gen_battle_vectors.gd`
   `.tools/godot --headless --path . -s tools/gen_pve_vectors.gd`
3. Compare: same command into `/tmp/claude-0/hashes_after.txt`, then `diff` the two files.
   - Only NEW files may appear. A changed hash for an existing vector is a contract break:
     stop and explain why (intentional rule change?) before keeping it.
   - If only formatting/default keys changed in old files (same hash), restore them with `git checkout`.
4. Both sides: `./scripts/test.sh` (GD) and `cd server && npm test` (TS) must pass.
5. Report: new vectors, unchanged hashes, test counts.
