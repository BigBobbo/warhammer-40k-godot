#!/usr/bin/env bash
# Local parallel driver for the visual-regression loop.
#
# Runs scripts/loop/run_one_scenario_loop.sh against N scenarios
# concurrently, with bounded concurrency. Each scenario gets its own
# Godot process (independent xvfb DISPLAY via xvfb-run -a) and its
# own log file. Final summary table.
#
# This is the LOCAL fallback for the cloud-session-per-scenario
# architecture documented in scripts/loop/kickoff_parallel.md. It does
# not invoke critic or fixer agents — for those, use the per-session
# cloud workflow. This driver is for:
#   - Pre-push: "run the whole library before opening a PR"
#   - Re-bless sweeps with --bless
#   - Diagnosing parallelism / determinism issues locally
#
# Usage:
#   bash scripts/loop/run_parallel_local.sh [--bless] [--concurrency N] \
#        [--top M] [<scenario.json>...]
#
# If no scenarios are listed, runs the full library
# (40k/tests/scenarios/sp/*.json).
#
# Flags:
#   --bless           pass --bless through to the underlying driver
#   --concurrency N   max simultaneous Godot processes (default: 4)
#   --top M           only run the top-M scenarios from
#                     list_scenarios_by_priority.py (ignored if explicit
#                     scenarios are given)
#
# Output:
#   /tmp/loop_parallel_<scenario_id>.log per scenario
#   Final summary table to stdout with pass/fail/exit-code per scenario.
#
# Exit: 0 if all scenarios exit 0, 1 if any failed.

set -u

CONCURRENCY=4
TOP=""
BLESS_FLAG=""
SCENARIOS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bless)
            BLESS_FLAG="--bless"
            shift ;;
        --concurrency)
            CONCURRENCY="$2"
            shift 2 ;;
        --top)
            TOP="$2"
            shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# *//'
            exit 0 ;;
        *)
            SCENARIOS+=("$1")
            shift ;;
    esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Resolve the scenario list
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
    if [[ -n "$TOP" ]] && [[ -x scripts/loop/list_scenarios_by_priority.py ]]; then
        mapfile -t SCENARIOS < <(python3 scripts/loop/list_scenarios_by_priority.py --paths | head -n "$TOP")
    else
        mapfile -t SCENARIOS < <(ls 40k/tests/scenarios/sp/*.json)
    fi
fi

echo "[parallel] scenarios:    ${#SCENARIOS[@]}"
echo "[parallel] concurrency:  $CONCURRENCY"
echo "[parallel] mode:         ${BLESS_FLAG:---diff (default)}"
echo

# Function to run one scenario and emit a status line
run_one() {
    local scenario="$1"
    local sid
    sid=$(basename "$scenario" .json)
    local logfile="/tmp/loop_parallel_${sid}.log"
    local start_ts
    start_ts=$(date +%s)
    if LOOP_SKIP_PREFLIGHT=1 bash scripts/loop/run_one_scenario_loop.sh $BLESS_FLAG "$scenario" > "$logfile" 2>&1; then
        local end_ts=$(date +%s)
        local elapsed=$((end_ts - start_ts))
        echo "OK ${elapsed}s ${sid}"
    else
        local code=$?
        local end_ts=$(date +%s)
        local elapsed=$((end_ts - start_ts))
        echo "FAIL ${elapsed}s ${sid} (exit=${code}, log=${logfile})"
    fi
}

export -f run_one
export BLESS_FLAG

# Use xargs for bounded parallelism
RESULTS_FILE="/tmp/loop_parallel_results.txt"
: > "$RESULTS_FILE"
SWEEP_START=$(date +%s)

printf "%s\n" "${SCENARIOS[@]}" \
  | xargs -P "$CONCURRENCY" -I {} bash -c 'run_one "$@"' _ {} \
  | tee "$RESULTS_FILE"

SWEEP_END=$(date +%s)
SWEEP_ELAPSED=$((SWEEP_END - SWEEP_START))

echo
echo "============================================================"
echo "Parallel sweep complete: $(date)"
echo "Wall clock: ${SWEEP_ELAPSED}s across ${#SCENARIOS[@]} scenarios (concurrency=$CONCURRENCY)"
echo "============================================================"

OK_COUNT=$(grep -c "^OK " "$RESULTS_FILE" || true)
FAIL_COUNT=$(grep -c "^FAIL " "$RESULTS_FILE" || true)
echo "passed: $OK_COUNT  failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo
    echo "Failures:"
    grep "^FAIL " "$RESULTS_FILE" | sed 's/^/  /'
    exit 1
fi
exit 0
