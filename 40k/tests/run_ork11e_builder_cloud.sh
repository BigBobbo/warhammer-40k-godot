#!/bin/bash
# WP-O5 — Codex: Orks (11e) builder end-to-end, both halves on one relay server:
#   1. server/tests/e2e-orks-codex.mjs drives the browser Army Builder
#      (Playwright) and saves a codex-enhancement army to the cloud
#      (WPO5_E2E_Orks);
#   2. the windowed scenario tests/scenarios/sp/ork11e_enh_builder_cloud_army.json
#      loads it through the Godot main menu (Refresh Cloud Armies -> Start).
# The scenario declares "builder_e2e", so run_scenarios.sh starts the relay
# server, runs the builder half and points res://server_config.json at it for
# this scenario only (removed afterwards) — this script is just a shortcut.
#
# Usage (repo root):  bash 40k/tests/run_ork11e_builder_cloud.sh
# Env: E2E_PORT (default 19690), E2E_SHOT_DIR (builder screenshots),
#      GODOT_MCP_PORT (passed through to the scenario runner).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 2
bash 40k/tests/run_scenarios.sh tests/scenarios/sp/ork11e_enh_builder_cloud_army.json
