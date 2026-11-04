#!/usr/bin/env bash
# PostToolUse (Edit|Write): after touching simulation/battle/meta rules on either side, run the
# fast TS suite (vectors + battle vectors + server logic, ~1 s) so GD<->TS drift shows at once.
f="$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')"
case "$f" in
  */sim/*|*/battle/*|*/meta/*|*/ai/*|*/server/sim/*|*/server/game/*|*/server/core/*) ;;
  *) exit 0 ;;
esac
root="${CLAUDE_PROJECT_DIR:-$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null)}"
out="$(cd "$root/server" && npm test 2>&1)"
if echo "$out" | grep -qE '^# fail [1-9]'; then
  fails="$(echo "$out" | grep -E '^not ok' | head -5 | tr '\n' ';')"
  jq -n --arg m "Server/parity tests FAIL after editing $f: $fails" \
    '{decision: "block", reason: $m, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
fi
exit 0
