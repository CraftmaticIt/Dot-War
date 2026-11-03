#!/usr/bin/env bash
# Installs Godot (headless-capable linux build) to .tools/ and GUT to addons/gut. Idempotent.
set -euo pipefail
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GUT_VERSION="${GUT_VERSION:-v9.7.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.tools"
if [ ! -x "$ROOT/.tools/godot" ] || ! "$ROOT/.tools/godot" --version 2>/dev/null | grep -q "^${GODOT_VERSION}"; then
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  curl -fsSL "$url" -o "$ROOT/.tools/godot.zip"
  (cd "$ROOT/.tools" && unzip -oq godot.zip && mv -f "Godot_v${GODOT_VERSION}-stable_linux.x86_64" godot && rm godot.zip)
  chmod +x "$ROOT/.tools/godot"
fi
if [ ! -f "$ROOT/addons/gut/.version-${GUT_VERSION}" ]; then
  rm -rf "$ROOT/.tools/gut-src" "$ROOT/addons/gut"
  git clone -q --depth 1 --branch "$GUT_VERSION" https://github.com/bitwes/Gut "$ROOT/.tools/gut-src"
  mkdir -p "$ROOT/addons"
  cp -r "$ROOT/.tools/gut-src/addons/gut" "$ROOT/addons/gut"
  touch "$ROOT/addons/gut/.version-${GUT_VERSION}"
  rm -rf "$ROOT/.tools/gut-src"
fi
# Import project once so class_name globals are registered.
"$ROOT/.tools/godot" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
echo "godot: $("$ROOT/.tools/godot" --version)"
