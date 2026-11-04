#!/usr/bin/env bash
# Exports the Android APK (debug-signed, arm64) using the "Android" preset in
# 40k/export_presets.cfg. Run tools/android/setup_android_export.sh once first.
#
# Usage:  bash tools/android/build_apk.sh [output.apk]
# Install on a phone: enable "Install unknown apps" for your file manager /
# browser and open the APK, or `adb install -r <apk>` over USB.
set -euo pipefail
export PATH="$HOME/bin:$PATH"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$REPO/40k/exports/android/warhammer40k.apk}"
mkdir -p "$(dirname "$OUT")"

cd "$REPO/40k"
# The import cache must exist for an export (fresh clones don't have it).
if [ ! -f .godot/global_script_class_cache.cfg ]; then
	godot --headless --import >/dev/null 2>&1 || true
fi
# Stamp the APK with the game version (newest entry of data/version_history.json)
# so Android sees each build as a newer release and Settings > Apps shows the
# real version. 1.73.1 -> versionCode 17301. The preset file is restored after
# the export so the repo stays clean.
VER="$(python3 -c 'import json;print(json.load(open("data/version_history.json"))["releases"][0]["version"])')"
CODE="$(python3 -c 'import sys;a,b,c=(int(x) for x in sys.argv[1].split("."));print(a*10000+b*100+c)' "$VER")"
cp export_presets.cfg /tmp/export_presets.cfg.bak
trap 'cp /tmp/export_presets.cfg.bak "$REPO/40k/export_presets.cfg"' EXIT
sed -i -E "/^\[preset\.[0-9]+\.options\]/,/^\[preset/ { s/^version\/code=.*/version\/code=$CODE/; s/^version\/name=.*/version\/name=\"$VER\"/ }" export_presets.cfg
echo "[build_apk] version $VER (versionCode $CODE)"
godot --headless --path . --export-debug "Android" "$OUT" 2>&1 | tee /tmp/android_export.log | tail -20
if [ ! -s "$OUT" ]; then
	echo "[build_apk] FAILED — no APK produced. See /tmp/android_export.log"
	exit 1
fi
apksigner verify "$OUT" && echo "[build_apk] signature OK"
ls -lh "$OUT"
