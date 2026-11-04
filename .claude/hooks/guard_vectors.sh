#!/usr/bin/env bash
# PreToolUse (Edit|Write): determinism vectors are a GDScript<->TypeScript contract and must
# only be produced by tools/gen_vectors.gd / tools/gen_battle_vectors.gd, never hand-edited.
f="$(jq -r '.tool_input.file_path // empty')"
case "$f" in
  */tests/vectors/*.json|*/tests/battle_vectors/*.json|tests/vectors/*.json|tests/battle_vectors/*.json)
    jq -n --arg f "$f" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
      permissionDecisionReason: ("Vector files are generated: run the regen-vectors skill instead of editing " + $f)}}'
    ;;
esac
exit 0
