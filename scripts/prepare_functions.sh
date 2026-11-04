#!/usr/bin/env bash
# Copies the pure TS server code into supabase/functions/_shared/server so each Edge
# Function bundle contains it (the CLI only bundles files under supabase/functions).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DST="$ROOT/supabase/functions/_shared/server"
rm -rf "$DST"
mkdir -p "$DST"
cp -r "$ROOT/server/sim" "$ROOT/server/game" "$ROOT/server/core" "$ROOT/server/http" "$DST/"
echo "copied server/ -> $DST"
