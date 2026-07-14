#!/bin/bash
# Run a single scenario file via the ScenarioRunner autoload.
#
# Usage:
#   bash 40k/tests/run_scenario.sh tests/scenarios/sp/<id>.json
#
# The scenario path is interpreted RELATIVE TO 40k/ (i.e. res://).
# Exit code: 0 if all asserts pass, non-zero otherwise.

set -e

SCENARIO_RES_PATH="${1:-}"
if [ -z "$SCENARIO_RES_PATH" ]; then
    echo "Usage: $0 <scenario_path_relative_to_40k>"
    echo "  e.g. $0 tests/scenarios/sp/iss050_fight_11e.json"
    exit 2
fi

cd "$(dirname "$0")/.."

# Add user's local godot to PATH if available
export PATH="$HOME/bin:$PATH"

ABS_SCENARIO="$(pwd)/$SCENARIO_RES_PATH"
if [ ! -f "$ABS_SCENARIO" ]; then
    echo "ERROR: scenario file not found: $ABS_SCENARIO"
    exit 2
fi

# Resolve scenario ID for grepping result lines later
SCENARIO_ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$ABS_SCENARIO" | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')

echo "================================================"
echo "Scenario: $SCENARIO_ID"
echo "Path:     $ABS_SCENARIO"
echo "================================================"

# Pre-flight: macOS window-activation. On Linux CI (Xvfb) this is a no-op.
if [ "$(uname)" = "Darwin" ]; then
    osascript -e 'tell application "System Events" to set frontmost of every process whose unix id is (do shell script "echo $$") to true' 2>/dev/null || true
    osascript -e 'tell application "Godot" to activate' 2>/dev/null || true
fi

# Run scenario. Engine flag '--scenario-file=' is forwarded; ScenarioRunner
# parses it from cmdline on _ready.
godot --path . --scenario-file="$SCENARIO_RES_PATH" 2>&1 | tee /tmp/scenario_run.log | grep -E "^\[ScenarioRunner\]|^\[Scenario [^]]+\]|PASS|FAIL|ERROR|=== |passed, .* failed"
EXIT_CODE=${PIPESTATUS[0]}

echo "================================================"
echo "Exit code: $EXIT_CODE"
echo "================================================"
exit $EXIT_CODE
