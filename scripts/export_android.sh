#!/usr/bin/env bash
# Builds a debug APK to build/dot-war-debug.apk. Needs JDK 17 and an Android SDK
# (ANDROID_HOME). Downloads export templates and creates a debug keystore if missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
MM="${GODOT_VERSION%.*}"                       # 4.7
TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
if [ ! -f "$TPL_DIR/android_debug.apk" ]; then
  mkdir -p "$TPL_DIR"
  curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" -o /tmp/tpl.tpz
  unzip -oq /tmp/tpl.tpz -d /tmp/tpl && cp -r /tmp/tpl/templates/* "$TPL_DIR/" && rm -rf /tmp/tpl /tmp/tpl.tpz
fi
KS="$ROOT/.tools/debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -v -keystore "$KS" -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KS"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
CFG="$HOME/.config/godot"
mkdir -p "$CFG"
cat > "$CFG/editor_settings-${MM}.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
export/android/java_sdk_path = "${JAVA_HOME}"
TRES
mkdir -p "$ROOT/build"
"$ROOT/.tools/godot" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$ROOT/.tools/godot" --headless --path "$ROOT" --export-debug "Android" "$ROOT/build/dot-war-debug.apk"
test -s "$ROOT/build/dot-war-debug.apk"
ls -la "$ROOT/build/dot-war-debug.apk"
