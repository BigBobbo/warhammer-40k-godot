#!/bin/bash
# Batch-run scenarios. By default runs every *.json under tests/scenarios/sp/.
#
# Usage:
#   bash 40k/tests/run_scenarios.sh                # all sp scenarios
#   bash 40k/tests/run_scenarios.sh --all          # sp + mp scenarios
#   bash 40k/tests/run_scenarios.sh --changed-only # only scenarios whose
#                                                  # 'covers' tags overlap
#                                                  # with files changed since
#                                                  # main (used by pre-commit)
#   bash 40k/tests/run_scenarios.sh path/to/x.json [path/to/y.json ...]
#
# Exit code: 0 if all scenarios pass, 1 if any fail, 2 on infra error.

set -e

cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"

MODE="${1:---sp}"
SCENARIOS=()

if [ "$MODE" = "--all" ]; then
    SCENARIOS=($(find tests/scenarios/sp tests/scenarios/mp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
elif [ "$MODE" = "--sp" ] || [ -z "$MODE" ]; then
    SCENARIOS=($(find tests/scenarios/sp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
elif [ "$MODE" = "--mp" ]; then
    SCENARIOS=($(find tests/scenarios/mp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
elif [ "$MODE" = "--changed-only" ]; then
    # Pre-commit / changed-files mode: pick scenarios whose `covers` tags
    # overlap with any path-fragment in the changed file list. Crude but
    # sufficient — we lean on coverage tags being descriptive.
    CHANGED=$(git diff --cached --name-only 2>/dev/null)
    if [ -z "$CHANGED" ]; then
        CHANGED=$(git diff --name-only 2>/dev/null)
    fi
    if [ -z "$CHANGED" ]; then
        echo "[run_scenarios] no changes detected; running full sp suite"
        SCENARIOS=($(find tests/scenarios/sp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
    else
        # Build a lowercase changed-files string to grep against `covers` tags
        CHANGED_LC=$(echo "$CHANGED" | tr '[:upper:]' '[:lower:]')
        for s in $(find tests/scenarios -maxdepth 2 -name "*.json"); do
            COVERS_LINE=$(grep -E '"covers"' "$s" | head -1)
            # If any covers tag's primary segment (before first .) matches any
            # changed-file path fragment, include this scenario.
            INCLUDE=0
            for tag in $(echo "$COVERS_LINE" | grep -oE '"[a-zA-Z0-9_.]+"' | tr -d '"'); do
                segment=$(echo "$tag" | cut -d. -f1)
                if echo "$CHANGED_LC" | grep -qF "$segment"; then
                    INCLUDE=1
                    break
                fi
            done
            if [ $INCLUDE -eq 1 ]; then
                SCENARIOS+=("$s")
            fi
        done
        if [ ${#SCENARIOS[@]} -eq 0 ]; then
            echo "[run_scenarios] no scenarios match changed files; nothing to run"
            exit 0
        fi
    fi
else
    # Treat all positional args as scenario paths
    SCENARIOS=("$@")
fi

if [ ${#SCENARIOS[@]} -eq 0 ]; then
    echo "[run_scenarios] no scenarios found"
    exit 2
fi

echo "================================================"
echo "Batch scenario run: ${#SCENARIOS[@]} scenario(s)"
echo "================================================"

PASSED=0
FAILED=0
FAILED_IDS=()

for s in "${SCENARIOS[@]}"; do
    SCENARIO_ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$s" | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
    echo ""
    echo "------------------------------------------------"
    echo "[$((PASSED + FAILED + 1))/${#SCENARIOS[@]}] $SCENARIO_ID"
    echo "    $s"
    echo "------------------------------------------------"

    # Macros activate window once per run on Mac
    if [ "$(uname)" = "Darwin" ]; then
        osascript -e 'tell application "Godot" to activate' 2>/dev/null || true
    fi

    if godot --path . --scenario-file="$s" 2>&1 | tee /tmp/scenario_run_${SCENARIO_ID}.log | grep -E "^\[ScenarioRunner\]|PASS|FAIL|=== "; then
        EXIT_CODE=${PIPESTATUS[0]}
    else
        EXIT_CODE=${PIPESTATUS[0]}
    fi

    if [ $EXIT_CODE -eq 0 ]; then
        PASSED=$((PASSED + 1))
        echo "  -> PASS"
    else
        FAILED=$((FAILED + 1))
        FAILED_IDS+=("$SCENARIO_ID")
        echo "  -> FAIL (exit $EXIT_CODE)"
    fi
done

echo ""
echo "================================================"
echo "Scenario suite: $PASSED passed, $FAILED failed across ${#SCENARIOS[@]} scenarios"
if [ $FAILED -gt 0 ]; then
    echo "Failed: ${FAILED_IDS[*]}"
fi
echo "================================================"

exit $([ $FAILED -eq 0 ] && echo 0 || echo 1)
