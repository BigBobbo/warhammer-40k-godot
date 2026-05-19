#!/bin/bash
# Per-scenario visual-regression loop driver.
#
# Runs a single scenario windowed with per-step screenshots enabled,
# invokes the stub critic to validate the I/O contract, and compares
# each per-step screenshot to its golden via PHASH. The real critic +
# fixer are Agent subagents invoked by the cloud Claude session that
# calls this script — they live in critic_prompt.md / fixer_prompt.md.
#
# Usage:
#   bash scripts/loop/run_one_scenario_loop.sh <scenario-json-path>
#   bash scripts/loop/run_one_scenario_loop.sh --bless <scenario-json-path>
#
# In --bless mode, the per-step screenshots replace the goldens. Use
# only after manual sign-off (new scenario, or intentional UI change).
#
# Exit codes:
#   0   scenario green AND golden diff clean (or --bless completed)
#   1   scenario failed, critic stub failed, or golden drift detected
#   2   misuse / preflight failed
#
set -e

BLESS_MODE=0
if [ "$1" = "--bless" ]; then
    BLESS_MODE=1
    shift
fi

SCENARIO_PATH="$1"
if [ -z "$SCENARIO_PATH" ] || [ ! -f "$SCENARIO_PATH" ]; then
    echo "usage: $0 [--bless] <scenario-json-path>"
    echo "  e.g. $0 40k/tests/scenarios/sp/runner_smoke.json"
    exit 2
fi

cd "$(git rev-parse --show-toplevel)"
export PATH="$HOME/bin:$PATH"

SCENARIO_ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$SCENARIO_PATH" \
              | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
USER_DIR="$HOME/.local/share/godot/app_userdata/40k"
RESULTS_DIR="$USER_DIR/test_results/scenarios"
GOLDENS_DIR="40k/tests/scenarios/goldens"
PRESERVE_PATH="${SCENARIO_PATH#40k/}"   # ScenarioRunner CLI flag is relative to 40k/

echo "[loop] scenario:    $SCENARIO_ID"
echo "[loop] scenario fp: $SCENARIO_PATH"
echo "[loop] results dir: $RESULTS_DIR"
echo "[loop] goldens dir: $GOLDENS_DIR"
[ "$BLESS_MODE" = "1" ] && echo "[loop] MODE:        --bless (will overwrite goldens)"

# 1. Headless preflight — non-zero exit short-circuits the loop.
# LOOP_SKIP_PREFLIGHT=1 bypasses; used during harness bringup when the
# audit suite has unrelated reds. Remove once main's audit suite is green.
echo ""
if [ "${LOOP_SKIP_PREFLIGHT:-0}" = "1" ]; then
    echo "[loop] preflight: SKIPPED (LOOP_SKIP_PREFLIGHT=1)"
else
    echo "[loop] preflight: headless audit suite"
    if ! bash 40k/tests/run_pretrigger_tests.sh > /tmp/loop_preflight.log 2>&1; then
        echo "[loop] HALT preflight failed; tail of /tmp/loop_preflight.log:"
        tail -40 /tmp/loop_preflight.log
        echo "[loop] (set LOOP_SKIP_PREFLIGHT=1 to bypass during bringup)"
        exit 2
    fi
    echo "[loop] preflight OK"
fi

# Clear stale per-step screenshots from a previous run of this scenario.
rm -f "$RESULTS_DIR/${SCENARIO_ID}_step_"*.png 2>/dev/null || true
rm -f "$RESULTS_DIR/critique.json" "$RESULTS_DIR/goldens_report.json" 2>/dev/null || true
rm -f "$RESULTS_DIR/${SCENARIO_ID}_selectors_report.json" 2>/dev/null || true

# 2. Selector preflight — run the scenario in dry-run mode and bail if
# any click_node / click_unit / expect_node_* / expect_token_visible
# step has a selector that doesn't resolve. Cheaper than a full xvfb
# run and surfaces "scenario silently no-ops because a button moved"
# before the screenshot loop wastes its turn. Skipped when the
# scenario JSON has no selector-using acts — ~30s saved per scenario.
SCENARIO_HAS_SELECTORS=$(python3 -c "
import json
with open('$SCENARIO_PATH') as f:
    s = json.load(f)
selectors = {'click_node', 'click_unit', 'expect_node_visible',
             'expect_node_property', 'expect_token_visible'}
has = any(step.get('act') in selectors for step in s.get('steps', []))
print('1' if has else '0')
")
if [ "${LOOP_SKIP_SELECTOR_PREFLIGHT:-0}" = "1" ]; then
    echo ""
    echo "[loop] selector preflight: SKIPPED (LOOP_SKIP_SELECTOR_PREFLIGHT=1)"
elif [ "$SCENARIO_HAS_SELECTORS" = "0" ]; then
    echo ""
    echo "[loop] selector preflight: SKIPPED (scenario has no selector-using acts)"
else
    echo ""
    echo "[loop] selector preflight: dry-run scenario for selector resolution"
    SELECTOR_LOG=/tmp/loop_selector_${SCENARIO_ID}.log
    set +e
    SCENARIO_SELECTOR_DRY_RUN=1 \
        xvfb-run -a godot --path 40k --scenario-file="$PRESERVE_PATH" \
            > "$SELECTOR_LOG" 2>&1
    SELECTOR_EXIT=$?
    set -e
    SELECTORS_JSON="$RESULTS_DIR/${SCENARIO_ID}_selectors_report.json"
    if [ ! -f "$SELECTORS_JSON" ]; then
        echo "[loop] HALT selector preflight produced no report; tail of log:"
        tail -30 "$SELECTOR_LOG"
        exit 1
    fi
    NOT_FOUND=$(python3 -c "import json; print(json.load(open('$SELECTORS_JSON'))['summary']['not_found'])")
    RESOLVED=$(python3 -c "import json; print(json.load(open('$SELECTORS_JSON'))['summary']['resolved'])")
    echo "[loop] selector preflight: resolved=$RESOLVED not_found=$NOT_FOUND"
    if [ "$NOT_FOUND" -gt 0 ]; then
        echo "[loop] HALT $NOT_FOUND selectors did not resolve:"
        python3 -c "
import json
report = json.load(open('$SELECTORS_JSON'))
for s in report['steps']:
    if s.get('selector_status') == 'not_found':
        print(f\"  step {s['step']:2d} ({s['act']}): {s.get('selector_kind')}={s.get('selector_value')!r}  err={s.get('error')}\")
"
        exit 1
    fi
fi

# 3. Run the scenario windowed with per-step screenshots enabled.
echo ""
echo "[loop] running scenario windowed (xvfb)"
export SCENARIO_SCREENSHOT_EVERY_STEP=1
RUN_LOG=/tmp/loop_scenario_${SCENARIO_ID}.log

set +e
xvfb-run -a godot --path 40k --scenario-file="$PRESERVE_PATH" 2>&1 \
    | tee "$RUN_LOG" \
    | grep -E "^\[ScenarioRunner\]|PASS|FAIL|===" || true
SCENARIO_EXIT=${PIPESTATUS[0]}
set -e
echo "[loop] scenario exit: $SCENARIO_EXIT"

# 3. Verify the results JSON exists.
RESULTS_JSON="$RESULTS_DIR/$SCENARIO_ID.json"
if [ ! -f "$RESULTS_JSON" ]; then
    echo "[loop] HALT no results JSON at $RESULTS_JSON"
    echo "[loop] tail of run log:"
    tail -40 "$RUN_LOG"
    exit 1
fi

# 4. Stub critic (real critic is an Agent in the cloud session).
echo ""
echo "[loop] invoking critic stub"
CRITIQUE_JSON="$RESULTS_DIR/critique.json"
if ! python3 scripts/loop/critic_stub.py "$RESULTS_JSON" "$USER_DIR" "$CRITIQUE_JSON"; then
    echo "[loop] HALT critic stub failed"
    exit 1
fi

# Determinism check runs as a standalone tool — `bash
# scripts/loop/determinism_check.sh <scenario>` — because it doubles wall
# time and would clobber the per-step screenshots the golden diff needs.
# Run it on demand when a scenario is suspected of flaking.

# 5. Golden PHASH diff. In bless mode, refuse to bless if the scenario
# itself failed — we never want broken-state screenshots as goldens.
if [ "$BLESS_MODE" = "1" ] && [ "$SCENARIO_EXIT" -ne 0 ]; then
    echo ""
    echo "[loop] REFUSE to bless: scenario exit was $SCENARIO_EXIT (not 0)."
    echo "       Blessing now would record a broken state as the visual"
    echo "       baseline. Fix the scenario's failing steps first, then"
    echo "       re-run --bless."
    GOLDEN_EXIT=2
else
    echo ""
    echo "[loop] running golden diff"
    GOLDEN_ARGS=(--results "$RESULTS_JSON" --user-dir "$USER_DIR"
                 --goldens-dir "$GOLDENS_DIR")
    [ "$BLESS_MODE" = "1" ] && GOLDEN_ARGS+=(--bless)
    set +e
    python3 scripts/loop/golden_diff.py "${GOLDEN_ARGS[@]}"
    GOLDEN_EXIT=$?
    set -e
fi

# 6. Summary.
CRITIQUE_COUNT=$(python3 -c "import json; print(len(json.load(open('$CRITIQUE_JSON'))))")
SCREENSHOT_COUNT=$(ls -1 "$RESULTS_DIR/${SCENARIO_ID}_step_"*.png 2>/dev/null | wc -l | tr -d ' ')
GOLDENS_REPORT="$RESULTS_DIR/goldens_report.json"
MISSING_GOLDENS=$(python3 -c "import json; print(json.load(open('$GOLDENS_REPORT'))['summary']['missing_golden'])" 2>/dev/null || echo 0)
MATCH_GOLDENS=$(python3 -c "import json; print(json.load(open('$GOLDENS_REPORT'))['summary']['match'])" 2>/dev/null || echo 0)
echo ""
echo "[loop] === summary ==="
echo "  scenario:          $SCENARIO_ID"
echo "  scenario exit:     $SCENARIO_EXIT"
echo "  per-step shots:    $SCREENSHOT_COUNT"
echo "  results JSON:      $RESULTS_JSON"
echo "  critique JSON:     $CRITIQUE_JSON  ($CRITIQUE_COUNT entries)"
echo "  goldens report:    $GOLDENS_REPORT"
echo "  golden diff exit:  $GOLDEN_EXIT"
echo "  run log:           $RUN_LOG"
if [ "$MISSING_GOLDENS" -gt 0 ] && [ "$BLESS_MODE" != "1" ]; then
    echo ""
    echo "[loop] WARNING $MISSING_GOLDENS step(s) have no golden — scenario has no"
    echo "       visual regression baseline. Re-run with --bless to bootstrap:"
    echo "         bash scripts/loop/run_one_scenario_loop.sh --bless $SCENARIO_PATH"
fi

# Combined exit: any non-zero wins.
if [ $SCENARIO_EXIT -ne 0 ]; then
    exit $SCENARIO_EXIT
fi
exit $GOLDEN_EXIT
