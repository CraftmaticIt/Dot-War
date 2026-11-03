#!/usr/bin/env bash
# Runs all GUT tests headless. Non-zero exit on failure or on any script/parse error
# (GUT silently skips scripts that fail to parse).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/.tools/godot" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
LOG="$(mktemp)"
"$ROOT/.tools/godot" --headless --path "$ROOT" -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit "$@" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG"; then
  echo "test.sh: script errors detected" >&2; rc=1
fi
rm -f "$LOG"
exit $rc
