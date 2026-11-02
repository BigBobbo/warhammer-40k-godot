#!/usr/bin/env bash
# Sets up everything Godot 4.4.1 needs to export the Android APK on a Linux
# box (incl. the Claude Code remote container, where dl.google.com is blocked
# so the official Android SDK cannot be downloaded).
#
# Instead of the SDK it uses Ubuntu's packaged apksigner / zipalign / adb and
# lays them out as a minimal "SDK" directory that Godot's non-Gradle Android
# export accepts. Idempotent — safe to re-run.
#
# Usage:  bash tools/android/setup_android_export.sh
# Then:   bash tools/android/build_apk.sh
set -euo pipefail

GODOT_VER="4.4.1"
TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VER}.stable"
SDK_DIR="${ANDROID_SDK_SHIM:-$HOME/android-sdk-shim}"
KEYSTORE="$HOME/.android/debug.keystore"
JDK_DIR="/usr/lib/jvm/java-17-openjdk-amd64"
SETTINGS="$HOME/.config/godot/editor_settings-4.4.tres"

echo "[android-setup] 1/5 apt packages (apksigner, zipalign, adb, JDK 17)"
if ! command -v apksigner >/dev/null || [ ! -d "$JDK_DIR" ]; then
	sudo_cmd=""; [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"
	$sudo_cmd apt-get update -q
	DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -q apksigner zipalign adb openjdk-17-jdk-headless
fi

echo "[android-setup] 2/5 Android export templates -> $TPL_DIR"
if [ ! -f "$TPL_DIR/android_debug.apk" ]; then
	mkdir -p "$TPL_DIR"
	tmp="$(mktemp -d)"
	curl -fSL -o "$tmp/tpl.tpz" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_export_templates.tpz"
	unzip -o -j -q "$tmp/tpl.tpz" templates/android_debug.apk templates/android_release.apk \
		templates/android_source.zip templates/version.txt -d "$TPL_DIR"
	rm -rf "$tmp"
fi

echo "[android-setup] 3/5 SDK shim -> $SDK_DIR"
mkdir -p "$SDK_DIR/platform-tools" "$SDK_DIR/build-tools/34.0.0" "$SDK_DIR/cmdline-tools/latest/bin"
ln -sf "$(command -v adb)" "$SDK_DIR/platform-tools/adb"
ln -sf "$(command -v apksigner)" "$SDK_DIR/build-tools/34.0.0/apksigner"
ln -sf "$(command -v zipalign)" "$SDK_DIR/build-tools/34.0.0/zipalign"

echo "[android-setup] 4/5 debug keystore -> $KEYSTORE"
if [ ! -f "$KEYSTORE" ]; then
	mkdir -p "$(dirname "$KEYSTORE")"
	keytool -genkeypair -v -keystore "$KEYSTORE" -storepass android -alias androiddebugkey \
		-keypass android -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

echo "[android-setup] 5/5 Godot editor settings -> $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
	cat > "$SETTINGS" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
EOF
fi
# Drop any previous android lines, then append the current ones.
sed -i '/^export\/android\//d' "$SETTINGS"
cat >> "$SETTINGS" <<EOF
export/android/java_sdk_path = "$JDK_DIR"
export/android/android_sdk_path = "$SDK_DIR"
export/android/debug_keystore = "$KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF

echo "[android-setup] done. Build with: bash tools/android/build_apk.sh"
