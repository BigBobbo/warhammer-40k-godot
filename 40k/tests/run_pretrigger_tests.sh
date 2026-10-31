#!/bin/bash
# Runs the audit-suite of headless GDScript regression tests:
#   - tutorial multi-input checklist ("'ave a look around" waits for every
#     suggested camera control instead of the first one pressed)
#   - input-mode policy (device resolved + locked at launch instead of
#     following the last input; Steam Deck / PC auto-detection)
#   - 3 pretrigger fixture tests (deferred-action stratagems CO/HI/RI)
#   - audit-fix verification (#329, #336, #338, #356, #359)
#   - T2.M6 base-touching regression (#321/#327)
#   - T2.S4-S6 SUSTAINED/LETHAL/DEVASTATING keyword pipeline
#   - T2.S7 cover save bonus
#   - T1-1 MELTA X keyword pipeline (auto-resolve damage bonus at half range)
#   - T1-2 TWIN-LINKED keyword pipeline (re-roll all failed wound rolls)
#   - T2-1 STEALTH ability pipeline (-1 to hit on ranged attacks vs Stealth target)
#   - modifier provenance (every hit/wound modifier names its source rule)
#   - T5-MP5 dice broadcast sync (NetworkManager re-emits result["dice"] on remote)
#   - T5-MP4-RELIABILITY save broadcast id + retry budget + defender dedupe
#   - T5-MP3 shooting visual broadcast (SELECT_SHOOTER/ASSIGN_TARGET/CONFIRM/COMPLETE)
#   - T5-UX9 shooting phase summary (per-target hits/wounds/casualties aggregation)
#   - shooting-phase keyboard shortcut registration (KeybindingManager + dispatch)
#   - T5-V7 WoundAllocationOverlay priority-pulse Tween lifecycle
#   - TestModeHandler shooting-phase action handler dispatch (multi-peer infra)
#   - TestModeHandler command-file double-execution race fix (in-flight set)
#   - TestModeHandler transition_to_phase action (multi-peer boot-phase advance)
#   - PM-0 wh40k_ai_plan schema validator (verbs, seat-2 mirror, reserves caps)
#   - PM-1 PlanManager storage + plan-to-game matching (game_config / faction)
#   - PM-2a AI deployment from a plan (order, seat-2 mirror, formula fallback)
#   - PM-2b AI formations from a plan (reserves, embarkations, attachments)
#   - the 50% reserves caps bind the AI too (attached leaders are counted)
#   - PM-3 AI earmarks (hold/push/screen/hunt bias, release, fragment layering)
#   - PM-5 deployment recorder + plan round trip (record -> consume, both seats)
#   - Codex: Orks (11e) data layer (curated stratagem rows, window column,
#     apostrophe-folded detachment match, legacy 1.0.19 datasheet kits)
#   - Wahapedia 11e codex import (Custodes + Orks): codex characteristics,
#     unit sizes, points and weapons in every shipped army file; AC codex
#     stratagem rows; pre-codex rosters keep their legacy kits
#   - Codex: Orks (11e) movement stratagems (movement windows, reactive /
#     assault-disembark follow-ups, MOBILE, desperate escape, objectives)
#   - Codex: Orks (11e) OTHER group (MOB MENTALITY, BREAKIN' HEADS, IMPENDING
#     KRUNCH, FLYIN' HEADBUTT, INFESTED WAR ZONE + their window hooks)
#   - core-rules audit e28e4f7: mandatory fights / p.74 pass (12.04), every
#     unit selected in Movement (09.02), selected indirect shooting type
#     (10.07), automatic 11e save allocation (05.04), emergency disembark
#     placement (18.05)
#   - #916 x #917 merge interactions: Fight On Death on SKIP_UNIT, stale
#     END_* no-ops, online Pile In / Consolidate half ownership, AFK timer vs
#     stratagem windows / mid-activation, client Consolidate step close
#   - Codex: Adeptus Custodes (11e) army rules (WP-C3): Martial Ka'tah readied
#     state + the six ka'tah abilities in their windows, Master of Ka'tahs,
#     Aegis of the Emperor, Aquila Commander, Daughters of the Abyss /
#     Psychic Null, Anathema Psykana warlord restriction
#   - Codex: Adeptus Custodes (11e) detachment rules (WP-C46): the 13
#     detachment rules, Favoured Ka'tah riders, BATTLELINE grant, Creeping
#     Dread, AI rule choices; the 10e Custodes detachment code is gone
#   - Codex: Adeptus Custodes (11e) enhancements (WP-C46): all 29 codex
#     enhancements + data-driven army-construction validation
#   - per-model loadout resolution over every army file (MA-LOADOUT; codex
#     kits per role, a weapon's profiles counted as one weapon — WP-O1b) and
#     the transport audit (capacity / exclusions / space multipliers)
#   - secondary deck draw terminates when only round-1 shuffle-back cards are
#     left (was an infinite loop)
#   - 14.02 per-model Objective Control (every model in range adds its OC;
#     attached-unit battle-shock zeroes the group; 14.03 secured tie/break)
#   - 11e charge targets within 12" AND within the roll (11.04 / 15.11)
#   - T01 UIConstants color slots: typed opaque slot constants, slot_name()
#     round trips, striped_pattern() diagonal hatch, autoload registration
#     conflicts, and the design-guidelines doc §9 Constant/Hex table matching
#     the autoload 1:1
#   - T02 visual-harness pixel diff (tests/tools/pixel_diff.gd, the math behind
#     every scenario `pixel_diff` step): identical PNGs = 0%, black vs white
#     > 95%, region clipping, size-mismatch / missing-file errors
#   - T03 movement drag ruler: RulesEngine.movement_drag_budget (M + Advance per
#     move mode), the green / yellow / red path split (spent movement, SHIFT
#     waypoint corners), the BEGIN_MODEL_DRAG action contract and the
#     MovementRangeVisual.DragRuler label / clear
#   - T05 shooting hover forecast: RulesEngine.preview_attack (11e cover = BS
#     worsened by 1, [IGNORES COVER] / [TORRENT], [HEAVY], plunging fire, +1/-1
#     cancelling, re-roll crits, overkill, 10e rules at edition 10), the
#     P3-114 card wrapper, the hover hook + test_hover_target_id seam, and the
#     HoverForecast card rows
#   - T06 weapon-order panel Esc: CANCEL_WEAPON_ORDER backs the weapon-order
#     step out to targeting with the declaration intact (nothing rolled, shooter
#     kept, re-confirm + Start Sequence still work), rejected outside the step
#     and once the targets are locked in (a defender SMOKESCREEN used against
#     them, or an Unpredictable Genius roll)
#   - T07 terrain cover icons: TerrainManager.cover_type_of (11e category ->
#     +1 / +2 / LB, height ignored), TerrainCoverOverlay.centroid_of (polygon
#     area centroid, not the vertex average), one TerrainCoverIcon_<id> per
#     piece of the default layout (label, centroid, alpha, below tokens), names
#     kept across a terrain reload, constant upright on-screen size
#   - T08 two-ring token: FactionRing (the unit's army-data colour from the
#     owner's faction palette, distinct per same-name squad, follows Change
#     Color) inside SlotRing (UIConstants player-slot colour: TEAL P1, MAGENTA
#     P2); SlotRing.scale > FactionRing.scale, both alpha >= 0.9, painted only
#     by the letter style, geometry inside the base / clear of the centre, the
#     MA-20 type ring just inside the slot ring, stop_pulse back to rest alpha
#   - T10 held-key threat overlay: melee-only units get no shooting ring,
#     reserves / embarked / destroyed units no rings, one union outline per
#     unit (attached leader folded in), radius = range + base extent, slots
#     MARGINAL_YELLOW / INVALID_RED on 0.15 / 0.10 CanvasGroup fills clipped to
#     the board; Tab press / echo / release-with-Shift, the Shooting-phase
#     tap (cycle shooter) vs hold (overlay) hand-off, stuck-key + focus-loss
#     release, the viewer's seat against the AI
#   - T12 overlay colours from UIConstants: no Color( / named Color.X in the
#     eleven board-overlay scripts, every Color constant / script variable a
#     slot or neutral chrome and in the slot its meaning calls for (42
#     walked), chrome kept out of the slot table, with_alpha(); the colours
#     the scripts hand out (damage / kill numbers, kill notification, result
#     summary, OVERLAY_SHADOW backdrops, coherency in/out, engagement
#     defaults, drag-ruler outline) and the death debris (slot blend, three
#     randf() per particle as before)
#
# Usage: ./tests/run_pretrigger_tests.sh          # the gated list below
#        ./tests/run_pretrigger_tests.sh --all    # EVERY direct SceneTree test:
#            tests/test_*.gd plus the `extends SceneTree` scripts under
#            tests/unit and tests/integration (most never ran anywhere)
# Exits 0 if all tests pass, 1 otherwise.
#
# Known failures: tests/ci/direct_known_failures.txt lists test FILES that are
# known to fail (each with a reason: a tracked 11e engine bug, or a failure
# that reproduces at both editions). A listed file that fails is XFAIL and
# does not fail the run; a listed file that PASSES fails the run until it is
# delisted (the list may only shrink). Everything else must pass.
#
# A test file also counts as FAILED (not just "M failed > 0") when:
#   - it reports "0 passed, 0 failed" — it ran no checks at all. This is how a
#     preloaded dependency that failed to compile shows up: every check that
#     calls into it aborts with a SCRIPT ERROR before reaching _check()
#     (R5: tests/test_ai_battle_plan.gd ran 0 of its 15 checks and still passed
#     the old gate). No gated file legitimately reports 0/0 (checked 2026-10-13).
#   - it hits "Invalid call. Nonexistent function '<f>' in base 'GDScript'" —
#     the runtime signature of calling a function on a preloaded script that
#     failed to compile.
#   - it has a GDScript Parse Error, or a Compile Error that is NOT the expected
#     pre-autoload noise. Under `godot -s` the test script (and everything it
#     preloads) is compiled once before the autoloads are registered, so
#     "Identifier not found: <AutoloadName>" (+ the "Failed to compile depended
#     scripts" lines it cascades into) is printed by many healthy tests that go
#     on to run every check (12 gated files on 2026-10-13: FactionPalettes ->
#     GameState, DeploymentZoneData -> Measurement, PadRouter ->
#     InputDeviceManager, ...). Any other compile error (an unknown identifier
#     that is not an autoload, a type error, ...) is a real defect and fails.

set -e

cd "$(dirname "$0")/.."

# Add user's local godot to PATH if available
export PATH="$HOME/bin:$PATH"

# Ensure committed test fixtures are present where SaveLoadManager.load_game
# resolves them. The pretrigger tests load co_/hi_/ri_pretrigger via
# load_game(name), which reads res://saves/ (== 40k/saves/, gitignored); the
# fixtures are committed under tests/saves/. Copy any that are missing so the
# suite is reproducible from a fresh checkout. -n never clobbers an existing
# save. Mirrors run_scenarios.sh.
# Ensure committed test fixtures are present AND CURRENT where
# SaveLoadManager.load_game resolves them. This used to be `cp -n`, which
# never overwrites — and that is a rot vector the PM-F3 rot-guard caught in
# the wild: after the 2026-08-21 fixture rebuild, a container restored an
# older user-data snapshot and `cp -n` happily kept the STALE boards in
# saves/ (and SaveLoadManager's non-destructive legacy copy kept them in
# user://saves) while the repo held the rebuilt ones. Checksum-compare and
# copy on difference, into BOTH resolution locations, so the committed
# fixture always wins.
mkdir -p saves
USER_SAVES="$HOME/.local/share/godot/app_userdata/40k/saves"
mkdir -p "$USER_SAVES"
for src in tests/saves/*.w40ksave tests/saves/*.meta; do
    [ -f "$src" ] || continue
    base="$(basename "$src")"
    for dstdir in saves "$USER_SAVES"; do
        if ! cmp -s "$src" "$dstdir/$base" 2>/dev/null; then
            cp "$src" "$dstdir/$base"
        fi
    done
done

TESTS=(
    "tests/test_tutorial_checklist.gd"
    "tests/test_tutorial_confirm_prompt.gd"
    "tests/test_input_mode_policy.gd"
    "tests/test_controller_controls_doc_sync.gd"
    "tests/test_hi_pretrigger.gd"
    "tests/test_ai_reactive_window_guard.gd"
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
    "tests/test_phase_banner_icons.gd"
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
    "tests/test_mp_v1_launch_fixes.gd"
    "tests/test_mp_relay_json_roundtrip.gd"
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
    "tests/test_oc_per_model_14_02.gd"
    "tests/test_iss060_ingress_11e.gd"
    "tests/test_iss061_surge_fly_11e.gd"
    "tests/test_iss057_actions_11e.gd"
    "tests/test_iss058_disembark_11e.gd"
    "tests/test_iss049_charge_11e.gd"
    "tests/test_charge_phase_fixes.gd"
    "tests/test_charge_target_within_roll_11e.gd"
    "tests/test_iss041b_resolution_11e.gd"
    "tests/test_casualty_preference.gd"
    "tests/test_iss016_modifier_stack.gd"
    "tests/test_iss045_allocation_overlay.gd"
    "tests/test_iss048_shooting_types_11e.gd"
    "tests/test_iss050_fight_phase_11e.gd"
    "tests/test_melee_datasheet_kits.gd"
    "tests/test_iss059_attached_units_11e.gd"
    "tests/test_attached_leader_transport_11e.gd"
    "tests/test_attached_char_shoot_gate_11e.gd"
    "tests/test_attached_char_bearer_ids.gd"
    "tests/test_secondary_deck_11e.gd"
    "tests/test_secondary_interactions_11e.gd"
    "tests/test_primary_missions_11e.gd"
    "tests/test_gdm_sourced_11e.gd"
    "tests/test_card_action_prompts_11e.gd"
    "tests/test_mp_scoring_11e.gd"
    "tests/test_iss029_golden_replay.gd"
    "tests/test_iss064_fallback_no_double_hazard.gd"
    "tests/test_iss065_at_half_battleshock.gd"
    "tests/test_iss066_fight_phase_wiring.gd"
    "tests/test_global_consolidation_11e.gd"
    "tests/test_global_consolidation_ai_11e.gd"
    "tests/test_ai_fight_selecting_player_11e.gd"
    "tests/test_global_pile_in_11e.gd"
    "tests/test_iss067_scouts_11e.gd"
    "tests/test_scout_detection_and_visibility.gd"
    "tests/test_iss068_infiltrators_11e.gd"
    "tests/test_iss069_lone_operative_11e.gd"
    "tests/test_iss070_keyword_scoped_abilities.gd"
    "tests/test_iss071_firing_deck_11e.gd"
    "tests/test_iss072_duplicated_abilities.gd"
    "tests/test_iss073_shw_mobile_gamble.gd"
    "tests/test_iss074_aircraft_reserves_11e.gd"
    "tests/test_core_stratagems_11e.gd"
    "tests/test_fire_overwatch_15_08_11e.gd"
    "tests/test_command_phase_start_once.gd"
    "tests/test_ork_codex_11e_data.gd"
    "tests/test_wahapedia_11e_import_data.gd"
    "tests/test_sw11e_codex_data.gd"
    "tests/test_sm11e_codex_data.gd"
    "tests/test_sm11e_detachments_b.gd"
    "tests/test_sw11e_stratagems.gd"
    "tests/test_sw11e_army_rules.gd"
    "tests/test_sw11e_detachments.gd"
    "tests/test_sw11e_enhancements.gd"
    "tests/test_sw11e_abilities.gd"
    "tests/test_sm11e_army_rules.gd"
    "tests/test_sm11e_detachments_a.gd"
    "tests/test_sm11e_stratagems_a.gd"
    "tests/test_sm11e_abilities_b.gd"
    "tests/test_sm11e_abilities_c.gd"  # WP-M4c: Space Marines (11e) M4c datasheet abilities
    "tests/test_sm11e_stratagems_b.gd"
    "tests/test_sm11e_abilities_a.gd"
    "tests/test_ork_codex_framework.gd"
    "tests/test_ork_codex_fight.gd"
    "tests/test_ork_codex_shooting.gd"
    "tests/test_ork_codex_shooting_reactive.gd"
    "tests/test_ork_codex_shooting_fixes.gd"
    "tests/test_ork_codex_movement.gd"
    "tests/test_ork_codex_other.gd"
    "tests/test_ork_codex_framework_fixes.gd"
    "tests/test_custodes_army_rules_11e.gd"
    "tests/test_custodes_detachments_11e.gd"
    "tests/test_custodes_enhancements_11e.gd"
    "tests/test_multi_detachment_11e.gd"
    "tests/test_custodes_codex_framework.gd"
    "tests/test_custodes_codex_fight.gd"
    "tests/test_custodes_codex_shooting.gd"
    "tests/test_custodes_codex_movement.gd"
    "tests/test_custodes_codex_other.gd"
    "tests/test_custodes_abilities_11e.gd"
    "tests/test_ork_codex_turn_flow_fixes.gd"
    "tests/test_ork_abilities_11e.gd"
    "tests/test_ork_enhancements_11e.gd"
    "tests/test_keybinding_chord_no_pan.gd"
    "tests/test_indirect_fire_band_11e.gd"
    "tests/test_t003_indirect_fire_visibility_pin.gd"
    "tests/test_terrain_area_visibility_11e.gd"
    "tests/test_fullauto_faction_rules.gd"
    "tests/test_custodes_lions_silent_hunters.gd"
    "tests/test_modifier_provenance.gd"
    "tests/test_ai_movement_coordination.gd"
    "tests/test_ai_battle_plan.gd"
    "tests/unit/test_plan_validator.gd"
    "tests/unit/test_plan_manager.gd"
    "tests/unit/test_ai_plan_deployment.gd"
    "tests/unit/test_ai_plan_formations.gd"
    "tests/unit/test_reserves_half_army_cap.gd"
    "tests/unit/test_ai_plan_earmarks.gd"
    "tests/unit/test_plan_roundtrip.gd"
    "tests/unit/test_plan_coherency_editions.gd"
    "tests/unit/test_deployment_zone_polygon_guard.gd"
    "tests/unit/test_fixture_boards_current.gd"
    "tests/test_core_rules_audit_e28e4f7.gd"
    "tests/test_merge_916_917_interactions.gd"
    "tests/test_fight_phase_scope_end_fight_11e.gd"
    "tests/test_ork_army_rules_11e.gd"
    "tests/test_ork_detachments_11e.gd"
    "tests/test_loadout_resolution.gd"
    "tests/test_transport_audit_2026_07.gd"
    "tests/test_secondary_draw_shuffle_back_terminates.gd"
    "tests/test_ui_constants_slots.gd"
    "tests/tools/pixel_diff_unit_test.gd"
    "tests/test_drag_ruler_budget.gd"
    "tests/test_phase_bar.gd"
    "tests/test_hover_forecast.gd"
    "tests/test_weapon_order_cancel.gd"
    "tests/test_terrain_cover_overlay.gd"
    "tests/test_two_ring_token.gd"
    "tests/test_unit_exhaustion.gd"
    "tests/test_threat_overlay.gd"
    "tests/test_los_line_visual.gd"
    "tests/test_visual_color_slots.gd"
)

if [ "${1:-}" = "--all" ]; then
    mapfile -t TESTS < <( { ls tests/test_*.gd; grep -l '^extends SceneTree' tests/unit/test_*.gd tests/integration/test_*.gd; } | sort -u )
    echo "--all: ${#TESTS[@]} direct SceneTree test(s)"
    # A few ungated scripts report through their exit code only (e.g.
    # "[OK] all #372 validations passed") — accept exit 0 for those.
    ALLOW_NO_RESULT_LINE=1
fi

KNOWN_FILE="${DIRECT_KNOWN_FAILURES:-tests/ci/direct_known_failures.txt}"
KNOWN_TESTS=" "
if [ -f "$KNOWN_FILE" ]; then
    KNOWN_TESTS=" $(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$KNOWN_FILE" | grep -v '^$' | tr '\n' ' ') "
fi
XFAIL_FILES=()

# Rules edition. The harness defaults to 11e (the edition players get);
# WH40K_TEST_EDITION=10 is the explicit legacy opt-in. Tests that set the
# edition themselves are unaffected either way.
if [ -n "${WH40K_TEST_EDITION:-}" ] && ! [[ "$WH40K_TEST_EDITION" =~ ^1[01]$ ]]; then
    echo "WH40K_TEST_EDITION must be 10 or 11 (got '$WH40K_TEST_EDITION')"
    exit 2
fi
echo "Rules edition: ${WH40K_TEST_EDITION:-11 (harness default)}"
command -v godot >/dev/null || { echo "godot not on PATH"; exit 2; }

# CI sharding: AUDIT_SHARD=i/n keeps every n-th test starting at index i, so
# the suite can be split across parallel jobs (each with its own user://).
if [ -n "${AUDIT_SHARD:-}" ]; then
    if ! [[ "$AUDIT_SHARD" =~ ^[0-9]+/[0-9]+$ ]]; then
        echo "AUDIT_SHARD must look like i/n (got '$AUDIT_SHARD')"
        exit 2
    fi
    SHARD_I=${AUDIT_SHARD%/*}
    SHARD_N=${AUDIT_SHARD#*/}
    SELECTED=()
    for i in "${!TESTS[@]}"; do
        if [ $((i % SHARD_N)) -eq "$SHARD_I" ]; then
            SELECTED+=("${TESTS[$i]}")
        fi
    done
    TESTS=("${SELECTED[@]}")
    echo "Shard $AUDIT_SHARD: ${#TESTS[@]} test(s)"
fi

FAILED=0
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_FILES=()

# Autoload names (project.godot [autoload]) — "Identifier not found: <one of
# these>" during the pre-autoload compile of a `godot -s` run is expected noise.
AUTOLOAD_NAMES=$(sed -n '/^\[autoload\]/,/^\[/p' project.godot | grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' | tr -d '=' | tr '\n' ' ')
FULL_LOG=$(mktemp)
trap 'rm -f "$FULL_LOG"' EXIT

for test in "${TESTS[@]}"; do
    echo ""
    echo "================================================"
    echo "Running: $test"
    echo "================================================"

    # Keep the full output (for the compile/no-checks gates below), print only
    # the result lines. Summary formats vary: "=== Result: N passed, M failed ===",
    # "=== Results: ...", and bare "=== N passed, M failed ===" — match on the
    # counts, not the prefix.
    # Keep the exit status: a test that prints its result line and THEN hangs
    # (timeout -> 124) or crashes (>=128) used to count as a pass.
    RC=0
    timeout 180 godot --headless --path . -s "$test" > "$FULL_LOG" 2>&1 || RC=$?
    OUTPUT=$(grep -E "PASS|FAIL|Result|[0-9]+ passed, [0-9]+ failed|=== test" "$FULL_LOG" || true)
    echo "$OUTPUT"

    # Extract the final result line and parse pass/fail counts
    RESULT_LINE=$(echo "$OUTPUT" | grep -E "[0-9]+ passed, [0-9]+ failed" | tail -1)
    if [ -z "$RESULT_LINE" ]; then
        if [[ "$KNOWN_TESTS" == *" $test "* ]]; then
            echo "  XFAIL: $test — no result line, exit $RC (known failure, $KNOWN_FILE)"
            XFAIL_FILES+=("$test (no result line, exit $RC)")
        elif [ "$RC" -eq 0 ] && [ "${ALLOW_NO_RESULT_LINE:-0}" = "1" ]; then
            echo "  (no 'N passed, M failed' line; exit 0 accepted under --all)"
        else
            echo "  ERROR: no result line found for $test (exit $RC)"
            FAILED=$((FAILED + 1))
            FAILED_FILES+=("$test (no result line, exit $RC)")
        fi
        continue
    fi

    PASS=$(echo "$RESULT_LINE" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
    FAIL=$(echo "$RESULT_LINE" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
    TOTAL_PASSED=$((TOTAL_PASSED + PASS))
    TOTAL_FAILED=$((TOTAL_FAILED + FAIL))

    REASON=""
    if [ "$RC" -eq 124 ]; then
        REASON="timed out after 180s (hang)"
    elif [ "$RC" -ge 128 ]; then
        REASON="crashed (exit $RC)"
    elif [ "$FAIL" -gt 0 ]; then
        REASON="$FAIL check(s) failed"
    elif [ "$PASS" -eq 0 ]; then
        REASON="ran no checks (0 passed, 0 failed) - a preloaded script probably failed to compile"
    fi
    if [ -z "$REASON" ] && grep -qE "Nonexistent function '[^']*' in base 'GDScript'" "$FULL_LOG"; then
        REASON="called into a script that failed to compile ($(grep -m1 -oE "Nonexistent function '[^']*' in base 'GDScript'" "$FULL_LOG"))"
    fi
    # A test that deliberately compiles invalid code (e.g. the MCP bridge's
    # "parse error surfaced" check) declares it with the marker comment
    # "# audit-runner: expects-parse-error" and is exempt from this gate.
    if [ -z "$REASON" ] && grep -q "Parse Error" "$FULL_LOG" && ! grep -q "audit-runner: expects-parse-error" "$test"; then
        REASON="GDScript parse error: $(grep -m1 "Parse Error" "$FULL_LOG")"
    fi
    if [ -z "$REASON" ]; then
        # Compile errors other than "Failed to compile depended scripts" and
        # "Identifier not found: <autoload>" are real defects.
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            ident=$(echo "$line" | sed -nE 's/.*Identifier not found: ([A-Za-z_][A-Za-z0-9_]*).*/\1/p')
            if [ -n "$ident" ] && [[ " $AUTOLOAD_NAMES " == *" $ident "* ]]; then
                continue
            fi
            REASON="compile error: $line"
            break
        done < <(grep -E "Compile Error" "$FULL_LOG" | grep -v "Failed to compile depended scripts" || true)
    fi

    if [[ "$KNOWN_TESTS" == *" $test "* ]]; then
        if [ -n "$REASON" ]; then
            echo "  XFAIL: $test — $REASON (known failure, $KNOWN_FILE)"
            XFAIL_FILES+=("$test ($REASON)")
        else
            echo "  XPASS: $test passes but is listed in $KNOWN_FILE — delist it"
            FAILED=$((FAILED + 1))
            FAILED_FILES+=("$test (XPASS: listed as a known failure but passes — delist it)")
        fi
    elif [ -n "$REASON" ]; then
        echo "  FAILED: $test — $REASON"
        FAILED=$((FAILED + 1))
        FAILED_FILES+=("$test ($REASON)")
    fi
done

echo ""
echo "================================================"
echo "Audit suite: $TOTAL_PASSED passed, $TOTAL_FAILED failed across ${#TESTS[@]} tests"
if [ ${#XFAIL_FILES[@]} -gt 0 ]; then
    echo "Known failures ($KNOWN_FILE): ${#XFAIL_FILES[@]} XFAIL"
    for f in "${XFAIL_FILES[@]}"; do
        echo "  ~ $f"
    done
fi
if [ "$FAILED" -gt 0 ]; then
    echo "Failed files ($FAILED):"
    for f in "${FAILED_FILES[@]}"; do
        echo "  - $f"
    done
fi
echo "================================================"

exit $([ "$FAILED" -eq 0 ] && echo 0 || echo 1)
