#!/bin/bash
# Batch-run scenarios. By default runs every *.json under tests/scenarios/sp/.
#
# Usage:
#   bash 40k/tests/run_scenarios.sh                # all sp scenarios
#   bash 40k/tests/run_scenarios.sh --all          # sp + mp scenarios
#   bash 40k/tests/run_scenarios.sh --visual       # only design-guidelines visual scenarios
#   bash 40k/tests/run_scenarios.sh --e11          # the 11e windowed suite (ISS-063)
#   bash 40k/tests/run_scenarios.sh --changed-only # only scenarios whose
#                                                  # 'covers' tags overlap
#                                                  # with files changed since
#                                                  # main (used by pre-commit)
#   bash 40k/tests/run_scenarios.sh path/to/x.json [path/to/y.json ...]
#
# Exit codes:
#   0 — all scenarios passed
#   1 — at least one assertion failed
#   2 — infra error (no scenarios found, etc.)
#   3 — regression detected: passing-count fell below tests/scenarios/visual/_baseline.json
#       (only emitted when at least one visual/* scenario was in the batch)

set -e

cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"

MODE="${1:---sp}"
SCENARIOS=()
FULL_SUITE_RUN=0  # only set to 1 when running a documented full-suite mode

if [ "$MODE" = "--all" ]; then
    SCENARIOS=($(find tests/scenarios/sp tests/scenarios/mp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
    FULL_SUITE_RUN=1
elif [ "$MODE" = "--sp" ] || [ -z "$MODE" ]; then
    SCENARIOS=($(find tests/scenarios/sp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
    FULL_SUITE_RUN=1
elif [ "$MODE" = "--mp" ]; then
    SCENARIOS=($(find tests/scenarios/mp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
elif [ "$MODE" = "--e11" ]; then
    # ISS-063: the 11e windowed suite — every scenario that drives the
    # edition-11 rules templates through the real UI (these also run in
    # the default --sp batch; this mode is the focused gate).
    SCENARIOS=($(grep -l '"edition": 11' tests/scenarios/sp/*.json 2>/dev/null | sort))
elif [ "$MODE" = "--visual" ]; then
    SCENARIOS=($(find tests/scenarios/visual -maxdepth 1 -name "T*_*.json" 2>/dev/null | sort))
    FULL_SUITE_RUN=1
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

# ----------------------------------------------------------------------------
# Visual-scenario post-processing (T02)
#
# If any tests/scenarios/visual/T##_*.json was in this batch:
#   1) Copy captured screenshots from the user:// results dir into
#      40k/test_results/design_guidelines/T##/ for stable review locations.
#   2) Compare PASSED against _baseline.json.count and exit 3 if it dropped.
# ----------------------------------------------------------------------------

VISUAL_RAN=0
for s in "${SCENARIOS[@]}"; do
    if [[ "$s" == *"tests/scenarios/visual/T"*"_"*".json" ]]; then
        VISUAL_RAN=1
        break
    fi
done

if [ $VISUAL_RAN -eq 1 ]; then
    USER_RESULTS_DIR="$HOME/.local/share/godot/app_userdata/40k/test_results/scenarios"
    if [ ! -d "$USER_RESULTS_DIR" ]; then
        # macOS
        USER_RESULTS_DIR="$HOME/Library/Application Support/Godot/app_userdata/40k/test_results/scenarios"
    fi

    DEST_BASE="test_results/design_guidelines"
    mkdir -p "$DEST_BASE"

    for s in "${SCENARIOS[@]}"; do
        if [[ "$s" != *"tests/scenarios/visual/T"*"_"*".json" ]]; then
            continue
        fi
        SCENARIO_ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$s" | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
        TASK_ID=$(echo "$SCENARIO_ID" | grep -oE '^T[0-9]+')
        if [ -z "$TASK_ID" ]; then
            continue
        fi
        TASK_DIR="$DEST_BASE/$TASK_ID"
        mkdir -p "$TASK_DIR"
        if [ -d "$USER_RESULTS_DIR" ]; then
            # Copy this scenario's PNGs + results JSON
            for f in "$USER_RESULTS_DIR/${SCENARIO_ID}"_*.png "$USER_RESULTS_DIR/${SCENARIO_ID}.json"; do
                if [ -f "$f" ]; then
                    cp "$f" "$TASK_DIR/" 2>/dev/null || true
                fi
            done

            # Extract pixel_diff entries to a dedicated diff_report.json for
            # reviewers who want the numbers without the full step transcript.
            RESULT_JSON="$USER_RESULTS_DIR/${SCENARIO_ID}.json"
            if [ -f "$RESULT_JSON" ] && command -v python3 >/dev/null 2>&1; then
                python3 - "$RESULT_JSON" "$TASK_DIR/diff_report.json" <<'PY' 2>/dev/null || true
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)
diffs = [s for s in data.get("steps", []) if s.get("act") == "pixel_diff"]
report = {
    "scenario_id": data.get("scenario_id"),
    "pixel_diff_steps": diffs,
    "summary": {
        "step_count": len(diffs),
        "all_passed": all(s.get("pass", False) for s in diffs),
    }
}
with open(dst, "w") as f:
    json.dump(report, f, indent=2)
PY
            fi

            echo "[run_scenarios] copied artifacts to $TASK_DIR/"
        else
            echo "[run_scenarios] WARNING: user-results dir not found ($USER_RESULTS_DIR); skipping copy for $SCENARIO_ID"
        fi
    done

    # Baseline regression check. Only meaningful on full-suite runs — an
    # individual-scenario invocation runs N < baseline by construction and
    # would always trip the check.
    if [ $FULL_SUITE_RUN -eq 1 ]; then
        BASELINE_FILE="tests/scenarios/visual/_baseline.json"
        if [ -f "$BASELINE_FILE" ]; then
            BASELINE_COUNT=$(grep -oE '"count"[[:space:]]*:[[:space:]]*[0-9]+' "$BASELINE_FILE" | head -1 | grep -oE '[0-9]+')
            if [ -n "$BASELINE_COUNT" ]; then
                echo "[run_scenarios] baseline count: $BASELINE_COUNT  passing: $PASSED"
                if [ "$PASSED" -lt "$BASELINE_COUNT" ]; then
                    echo "[run_scenarios] REGRESSION: passing ($PASSED) < baseline ($BASELINE_COUNT)"
                    exit 3
                fi
            fi
        fi
    else
        echo "[run_scenarios] (skipping baseline regression check — not a full-suite run)"
    fi
fi

exit $([ $FAILED -eq 0 ] && echo 0 || echo 1)
