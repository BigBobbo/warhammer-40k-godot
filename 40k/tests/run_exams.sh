#!/bin/bash
# B4 — run the tactical exam suite.
#
# Each exam plays ONE phase from a constructed position with the real AI at
# Hard, then grades machine-checkable assertions over the resulting state and
# the AI's own decision records. Seconds each, not minutes; deterministic at a
# fixed seed.
#
# Usage:
#   bash 40k/tests/run_exams.sh                    # every exam in tests/exams/
#   bash 40k/tests/run_exams.sh <id> [<id> ...]    # named exams
#   bash 40k/tests/run_exams.sh --aspirational     # the fail-by-design list
#   bash 40k/tests/run_exams.sh --all              # both lists
#
# Exit 0 iff every exam in the batch passed. The aspirational list is reported
# but never gates: those exams exist to FAIL until the task that owns each one
# lands, and the report prints which task that is.

set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"

EXAM_DIR="tests/exams"
ASPIRATIONAL_DIR="tests/exams/aspirational"

# Fixtures live in tests/saves but load_game() resolves them from res://saves/.
mkdir -p saves
cp -n tests/saves/*.w40ksave saves/ 2>/dev/null || true
cp -n tests/saves/*.meta saves/ 2>/dev/null || true

MODE="${1:---suite}"
SPECS=()
GATED=1

case "$MODE" in
    --suite) SPECS=($(find "$EXAM_DIR" -maxdepth 1 -name "*.json" | sort)) ;;
    --aspirational) SPECS=($(find "$ASPIRATIONAL_DIR" -maxdepth 1 -name "*.json" | sort)); GATED=0 ;;
    --all) SPECS=($(find "$EXAM_DIR" -maxdepth 2 -name "*.json" | sort)) ;;
    *)
        for id in "$@"; do
            if [ -f "$id" ]; then SPECS+=("$id")
            elif [ -f "$EXAM_DIR/$id.json" ]; then SPECS+=("$EXAM_DIR/$id.json")
            elif [ -f "$ASPIRATIONAL_DIR/$id.json" ]; then SPECS+=("$ASPIRATIONAL_DIR/$id.json")
            else echo "no such exam: $id" >&2; exit 2
            fi
        done
        ;;
esac

if [ ${#SPECS[@]} -eq 0 ]; then
    echo "no exams found in $EXAM_DIR" >&2
    exit 2
fi

USERDATA="$HOME/.local/share/godot/app_userdata/40k"
[ "$(uname)" = "Darwin" ] && USERDATA="$HOME/Library/Application Support/Godot/app_userdata/40k"

echo "================================================================"
echo "TACTICAL EXAMS — ${#SPECS[@]} exam(s)"
echo "================================================================"

# Static pre-flight, ~1 s and no Godot. An exam naming a unit its fixture does
# not contain does not fail loudly — the setup snippet raises, the exam reports
# ERROR with no verdict, and you learn that roughly two minutes later, per
# broken exam. Catch it before spending the wall clock.
if ! python3 ../tools/ai_lab/check_exams.py > /tmp/check_exams.$$ 2>&1; then
    echo "!!! exam pre-flight FAILED — fix these before running the suite:"
    sed 's/^/    /' /tmp/check_exams.$$
    rm -f /tmp/check_exams.$$
    exit 2
fi
rm -f /tmp/check_exams.$$

PASSED=0; FAILED=0; ERRORED=0
FAILED_IDS=()
START=$(date +%s)

# One exam is ~2 minutes, most of it scene setup and one phase of AI thinking.
# Twelve of those in series blows the suite's own "under ten minutes" budget,
# so they run in lanes. Same rule as the benchmark: never more lanes than
# cores minus one, or the timing guardrails start measuring machine load.
LANES="${EXAM_LANES:-3}"
RUNDIR=$(mktemp -d "${TMPDIR:-/tmp}/exams_XXXXXX")

run_one() {
    local spec="$1"
    local id
    id=$(basename "$spec" .json)
    local log="$RUNDIR/$id.log"
    # 240s covers a Custodes movement phase comfortably. The Ork fixture is
    # 77 models against 42 and a single phase there runs several times longer,
    # so the budget is per-exam and overridable rather than one number for all.
    local budget="${EXAM_TIMEOUT:-240}"
    grep -q '"fixture": *"[a-z_]*orks' "$spec" && budget="${EXAM_TIMEOUT_ORKS:-720}"
    timeout "$budget" godot --headless --path . -- --ai-benchmark \
        "--exam=res://${spec}" "--exam-out=test_results/exams/${id}.json" > "$log" 2>&1
    echo $? > "$RUNDIR/$id.rc"
}

pending=0
for spec in "${SPECS[@]}"; do
    run_one "$spec" &
    pending=$((pending + 1))
    if [ "$pending" -ge "$LANES" ]; then wait -n 2>/dev/null || wait; pending=$((pending - 1)); fi
done
wait

for spec in "${SPECS[@]}"; do
    id=$(basename "$spec" .json)
    log="$RUNDIR/$id.log"
    rc=$(cat "$RUNDIR/$id.rc" 2>/dev/null || echo 99)
    line=$(grep -m1 "^\[AIExam\] .*: [0-9]* passed" "$log" 2>/dev/null || true)
    if [ -z "$line" ]; then
        echo "  [ERROR] $id — no verdict (exit $rc)"
        grep -E "^\[AIExam\]|SCRIPT ERROR|Parse Error" "$log" 2>/dev/null | head -5 | sed 's/^/          /'
        ERRORED=$((ERRORED + 1)); FAILED_IDS+=("$id")
    elif [ "$rc" -eq 0 ]; then
        echo "  [PASS]  ${line#\[AIExam\] }"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL]  ${line#\[AIExam\] }"
        grep "^\[AIExam\]   FAIL" "$log" 2>/dev/null | sed 's/^/          /'
        FAILED=$((FAILED + 1)); FAILED_IDS+=("$id")
    fi
done
rm -rf "$RUNDIR"

ELAPSED=$(( $(date +%s) - START ))
echo "================================================================"
echo "  $PASSED passed, $FAILED failed, $ERRORED errored  (${ELAPSED}s)"
[ ${#FAILED_IDS[@]} -gt 0 ] && echo "  not passing: ${FAILED_IDS[*]}"
if [ "$GATED" -eq 0 ]; then
    echo "  (aspirational list — these are EXPECTED to fail until the task"
    echo "   named in each spec's 'owner' field lands; not a gate)"
    echo "================================================================"
    exit 0
fi
echo "================================================================"
[ $((FAILED + ERRORED)) -eq 0 ] || exit 1
