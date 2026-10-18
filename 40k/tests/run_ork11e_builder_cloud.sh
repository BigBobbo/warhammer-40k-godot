#!/bin/bash
# WP-O5 — Codex: Orks (11e) builder end-to-end, both halves on one relay server:
#   1. server/tests/e2e-orks-codex.mjs drives the browser Army Builder
#      (Playwright) and saves a codex-enhancement army to the cloud
#      (WPO5_E2E_Orks);
#   2. the windowed scenario tests/scenarios/sp/ork11e_enh_builder_cloud_army.json
#      loads it through the Godot main menu (Refresh Cloud Armies -> Start).
# res://server_config.json points CloudStorage at the local relay server for
# this run only (removed on exit).
#
# Usage (repo root):  bash 40k/tests/run_ork11e_builder_cloud.sh
# Env: E2E_PORT (default 19690), E2E_SHOT_DIR (builder screenshots),
#      GODOT_MCP_PORT (passed through to the scenario runner).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${E2E_PORT:-19690}"
DBDIR="$(mktemp -d)"
SHOTS="${E2E_SHOT_DIR:-$HOME/.local/share/godot/app_userdata/40k/test_results/scenarios}"
CFG="$ROOT/40k/server_config.json"
if [ -e "$CFG" ]; then
    echo "refusing to overwrite an existing $CFG" >&2
    exit 2
fi

cd "$ROOT/server" || exit 2
PORT="$PORT" DB_PATH="$DBDIR/e2e.db" node relay-server.js > "$DBDIR/relay.log" 2>&1 &
SRV=$!
cleanup() {
    kill "$SRV" 2>/dev/null
    rm -f "$CFG"
    rm -rf "$DBDIR"
}
trap cleanup EXIT

for _ in $(seq 1 50); do
    if curl -sf "http://localhost:$PORT/api/health" > /dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

echo "== builder half (Playwright) against http://localhost:$PORT"
if ! E2E_BASE="http://localhost:$PORT" E2E_SHOT_DIR="$SHOTS" node tests/e2e-orks-codex.mjs; then
    echo "builder e2e FAILED" >&2
    exit 1
fi

echo "{\"api_url\": \"http://localhost:$PORT\"}" > "$CFG"
echo "== game half (windowed scenario)"
cd "$ROOT" || exit 2
bash 40k/tests/run_scenarios.sh tests/scenarios/sp/ork11e_enh_builder_cloud_army.json
