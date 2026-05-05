#!/bin/bash
# Runs the audit-suite of headless GDScript regression tests:
#   - 3 pretrigger fixture tests (deferred-action stratagems CO/HI/RI)
#   - audit-fix verification (#329, #336, #338, #356, #359)
#   - T2.M6 base-touching regression (#321/#327)
#   - T2.S4-S6 SUSTAINED/LETHAL/DEVASTATING keyword pipeline
#   - T2.S7 cover save bonus
#   - T1-1 MELTA X keyword pipeline (auto-resolve damage bonus at half range)
#   - T1-2 TWIN-LINKED keyword pipeline (re-roll all failed wound rolls)
#
# Usage: ./tests/run_pretrigger_tests.sh
# Exits 0 if all tests pass, 1 otherwise.

set -e

cd "$(dirname "$0")/.."

# Add user's local godot to PATH if available
export PATH="$HOME/bin:$PATH"

TESTS=(
    "tests/test_co_pretrigger.gd"
    "tests/test_hi_pretrigger.gd"
    "tests/test_ri_pretrigger.gd"
    "tests/test_audit_fixes_verification.gd"
    "tests/test_m6_base_touching_regression.gd"
    "tests/test_keyword_pipeline.gd"
    "tests/test_s7_cover_save_bonus.gd"
    "tests/test_melta_keyword_pipeline.gd"
    "tests/test_twin_linked_pipeline.gd"
)

FAILED=0
TOTAL_PASSED=0
TOTAL_FAILED=0

for test in "${TESTS[@]}"; do
    echo ""
    echo "================================================"
    echo "Running: $test"
    echo "================================================"

    # Capture output, filter for test result lines
    OUTPUT=$(godot --headless --path . -s "$test" 2>&1 | grep -E "PASS|FAIL|Result|=== test" || true)
    echo "$OUTPUT"

    # Extract the final result line and parse pass/fail counts
    RESULT_LINE=$(echo "$OUTPUT" | grep -E "Result:" | tail -1)
    if [ -z "$RESULT_LINE" ]; then
        echo "  ERROR: no result line found for $test"
        FAILED=$((FAILED + 1))
        continue
    fi

    PASS=$(echo "$RESULT_LINE" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
    FAIL=$(echo "$RESULT_LINE" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
    TOTAL_PASSED=$((TOTAL_PASSED + PASS))
    TOTAL_FAILED=$((TOTAL_FAILED + FAIL))

    if [ "$FAIL" -gt 0 ]; then
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "================================================"
echo "Audit suite: $TOTAL_PASSED passed, $TOTAL_FAILED failed across ${#TESTS[@]} tests"
echo "================================================"

exit $([ "$FAILED" -eq 0 ] && echo 0 || echo 1)
