#!/bin/bash
# Runs the audit-suite of headless GDScript regression tests:
#   - 3 pretrigger fixture tests (deferred-action stratagems CO/HI/RI)
#   - audit-fix verification (#329, #336, #338, #356, #359)
#   - T2.M6 base-touching regression (#321/#327)
#   - T2.S4-S6 SUSTAINED/LETHAL/DEVASTATING keyword pipeline
#   - T2.S7 cover save bonus
#   - T1-1 MELTA X keyword pipeline (auto-resolve damage bonus at half range)
#   - T1-2 TWIN-LINKED keyword pipeline (re-roll all failed wound rolls)
#   - T2-1 STEALTH ability pipeline (-1 to hit on ranged attacks vs Stealth target)
#   - T5-MP5 dice broadcast sync (NetworkManager re-emits result["dice"] on remote)
#   - T5-MP4-RELIABILITY save broadcast id + retry budget + defender dedupe
#   - T5-MP3 shooting visual broadcast (SELECT_SHOOTER/ASSIGN_TARGET/CONFIRM/COMPLETE)
#   - T5-UX9 shooting phase summary (per-target hits/wounds/casualties aggregation)
#   - shooting-phase keyboard shortcut registration (KeybindingManager + dispatch)
#   - T5-V7 WoundAllocationOverlay priority-pulse Tween lifecycle
#   - TestModeHandler shooting-phase action handler dispatch (multi-peer infra)
#   - TestModeHandler command-file double-execution race fix (in-flight set)
#   - TestModeHandler transition_to_phase action (multi-peer boot-phase advance)
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
    "tests/test_stealth_keyword_pipeline.gd"
    "tests/test_dice_broadcast_sync.gd"
    "tests/test_save_broadcast_reliability.gd"
    "tests/test_shooting_visual_broadcast.gd"
    "tests/test_shooting_phase_summary.gd"
    "tests/test_shooting_phase_shortcuts.gd"
    "tests/test_wound_allocation_priority_pulse.gd"
    "tests/test_test_mode_handler_shooting.gd"
    "tests/test_test_mode_handler_command_dedupe.gd"
    "tests/test_test_mode_handler_transition.gd"
    "tests/test_rng_determinism_extended.gd"
    "tests/test_roll_off_first_turn_applied.gd"
    "tests/test_roll_off_dialog.gd"
    "tests/test_new_game_reaches_rolloff.gd"
    "tests/test_two_rolloffs.gd"
    "tests/test_t011_designate_warlord_pin.gd"
    "tests/test_iss001_pipeline_mutations.gd"
    "tests/test_iss002_game_constants.gd"
    "tests/test_iss003_ability_schema.gd"
    "tests/test_iss004_rng_seeding.gd"
    "tests/test_iss012_attack_goldens.gd"
    "tests/test_iss013_signal_registry.gd"
    "tests/test_iss014_shared_ai_math.gd"
    "tests/test_iss015_mp_seed_sync.gd"
    "tests/test_iss020_public_api.gd"
    "tests/test_iss017_state_schema.gd"
    "tests/test_iss021_action_replay.gd"
    "tests/test_iss022_undo_roundtrip.gd"
    "tests/test_iss019_unit_abilities.gd"
    "tests/test_iss032_ai_cache_policy.gd"
    "tests/test_iss026_load_sync_block.gd"
    "tests/test_iss028_save_migrations.gd"
    "tests/test_iss037_schema2.gd"
    "tests/test_iss039_engagement_range_11e.gd"
    "tests/test_iss044_hazard_rolls.gd"
    "tests/test_iss043_battleshock_11e.gd"
    "tests/test_iss038_turn_hooks.gd"
    "tests/test_iss042_coherency_11e.gd"
    "tests/test_iss040_move_types.gd"
    "tests/test_iss041_allocation_groups.gd"
    "tests/test_iss046_mortal_wounds_11e.gd"
    "tests/test_iss047_weapon_abilities_11e.gd"
    "tests/test_iss056_stratagem_per_unit.gd"
    "tests/test_iss051_terrain_model_11e.gd"
    "tests/test_iss052_hidden_11e.gd"
    "tests/test_iss053_cover_plunging_11e.gd"
    "tests/test_iss055_objectives_11e.gd"
    "tests/test_iss060_ingress_11e.gd"
    "tests/test_iss061_surge_fly_11e.gd"
    "tests/test_iss057_actions_11e.gd"
    "tests/test_iss058_disembark_11e.gd"
    "tests/test_iss049_charge_11e.gd"
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
    OUTPUT=$(timeout 180 godot --headless --path . -s "$test" 2>&1 | grep -E "PASS|FAIL|Result|=== test" || true)
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
