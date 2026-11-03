#!/usr/bin/env bash
# Runs all GUT tests headless. Non-zero exit on failure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/.tools/godot" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
exec "$ROOT/.tools/godot" --headless --path "$ROOT" -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit "$@"
