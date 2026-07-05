# July 2026 — Still To Fix

Tracking doc for pre-existing test failures observed while validating the
Heroic Intervention freeze fix (branch `claude/game-freeze-heroic-intervention-tzofgp`,
PR #499). **None of these are caused by that change** — they were already
failing in the headless test suite.

## How these were observed

Full headless GUT run on the 11th-edition-only codebase:

```bash
export PATH="$HOME/bin:$PATH"
cd 40k
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_heroic_intervention.gd -gexit
```

> Note: `-gtest=<file>` does **not** scope this project's GUT config to a single
> file — every invocation runs the entire `tests/` tree. So the list below is the
> whole-suite result, reproduced across two separate runs (~109 failing assert
> lines across 29 files, stable between runs).

## Important caveat — triage before fixing

I did **not** root-cause each failure. They fall into three buckets below, and the
bucket assignments for B and C are **hypotheses**, not confirmed diagnoses. In
particular, a large share show the classic signature of **cross-test state
pollution**: autoload singletons (`StratagemManager`, `GameState`) are not fully
reset between test *files*, so state (especially Command Points) leaks from one
file into the next. Symptoms like "Not enough CP (need 2, have 0)" and "Should
deduct exactly 1 CP → got 0" strongly suggest CP was already drained by an
earlier test, not that the feature is broken.

**Recommended first step:** run each failing file on its own (or add a global
`GameState`/`StratagemManager` reset in a suite-level `before_each`) to separate
genuine product/logic regressions from harness isolation bugs, *then* fix the
real ones.

Also note: a live game instance and/or overlapping GUT runs contend for the
`GodotMCP` bridge port 9080 (`Failed to listen on port 9080: Already in use`).
That is a harmless warning for a separate process, but avoid running the game and
the suite simultaneously when triaging.

---

## Bucket A — Confirmed broken (11e migration debt)

### `tests/unit/test_battle_shock.gd` — fails to compile
- **Parse error**: references `MoralePhase` / `preload("res://phases/MoralePhase.gd")`,
  but `40k/phases/MoralePhase.gd` was **deleted** in the 10e→11e migration (the
  Morale phase no longer exists). GUT then reports "does not extend GutTest" and
  skips the whole file, so its battle-shock coverage is silently lost.
- **Fix**: delete Section 4 (MoralePhase Integration, ~lines 338–460) and the
  `morale_phase` field / `_create_morale_phase()` helper, or port those cases to
  the Command-phase battle-shock path that replaced it.

---

## Bucket B — Strongly suspected cross-test state pollution (CP / stratagem state leak)

These use reactive-stratagem / CP flows and fail with "have 0 CP" or "first use
should succeed" style asserts — consistent with CP/usage state leaking in from
earlier test files rather than a real defect. Verify in isolation first.

### `tests/unit/test_counter_offensive.gd` (10 asserts)
- `test_counter_offensive_available_with_cp`: "Should be available with sufficient CP: Not enough CP (need 2, have 0)"
- `test_counter_offensive_not_available_after_use`: "First use should succeed"
- `test_eligible_units_in_engagement_range`: "Should have eligible units in engagement range" (0 found)
- `test_counter_offensive_both_players_can_use_separately`: "Player 1 should succeed" / "Player 2 should still be able to use"
- `test_counter_offensive_full_flow_definition_to_deduction`: "Should be available initially" / "Should have eligible units"
- `test_counter_offensive_does_not_set_unit_flags`: "Use should succeed"
- `test_counter_offensive_active_effect_tracked`: "Should add active effect" (0 vs 1)

### `tests/unit/test_command_reroll_stratagem.gd` (2)
- `test_can_use_command_reroll_with_sufficient_cp`: "Should be able to use with 3 CP"
- `test_is_command_reroll_available_returns_dict`: "Should be available with CP"

### `tests/unit/test_fire_overwatch.gd` (3)
- `test_overwatch_wounds_resolve_normally`: "Overwatch shooting should succeed"
- `test_fire_overwatch_eligible_units_within_24`: "Shooter within range should be eligible"
- `test_fire_overwatch_deducts_1_cp`: "Should deduct exactly 1 CP" (0 vs 1)

### `tests/unit/test_insane_bravery_stratagem.gd` (2)
- `test_insane_bravery_deducts_1_cp`: "CP should be deducted from 4 to 3" (got 2)

### `tests/unit/test_grenade_stratagem.gd` (1)
- `test_apply_mortal_wounds_to_destroyed_unit`: "No wounds applied to destroyed unit" (3 vs 0)

### `tests/unit/test_tank_shock.gd` (1)
- `test_both_players_can_use_separately`: "Player 2 Tank Shock should succeed"

### `tests/unit/test_heroic_intervention.gd` (5)
These are all in the **10e** `get_heroic_intervention_eligible_units` path or CP
deduction — a different code path from the 11e eligibility that PR #499 changed
(the new `test_11e_*` cases pass in isolation).
- `test_no_eligible_units_when_all_excluded`: expected 0, got 1
- `test_eligible_units_within_6_inches`: "U_DEFENDER within 6\" should be eligible"
- `test_walker_vehicle_is_eligible`: "WALKER VEHICLE should be eligible"
- `test_dead_unit_not_eligible`: expected 0, got 2
- `test_heroic_intervention_deducts_1_cp`: "Should deduct exactly 1 CP" (0 vs 1)

---

## Bucket C — Needs triage (possible product/logic bug OR stale test expectation)

### `tests/unit/test_go_to_ground_smokescreen.gd` (8) — save/AP formula mismatch
Tests expect invuln/cover interplay under an older AP formula; current code
caps armour-save improvement at +1 and prefers armour over 6+ invuln. Either the
save-calculation changed intentionally (update tests) or the cover/invuln
interaction regressed (fix code). Examples:
- `test_invuln_save_applied_via_save_calculation`: "Armour save should be 3+ (improvement capped at +1)" (got 7)
- `test_cover_with_ap` / `test_prepare_save_resolution_with_smokescreen_cover`: "save is 2+ (improvement capped)" (got 3)

### `tests/unit/test_blast_keyword.gd` (1) + `tests/unit/test_mathhammer_blast_bonus.gd` (3) — Blast bonus
Tests expect +1 attacks for 10-model targets and none for ≤5; code returns base.
- `test_calculate_blast_bonus_small_unit`: expected 0, got 1
- `test_blast_bonus_10_models`: "10 models should get +1 blast bonus: 2 + 1 = 3" (got 2)
- `test_blast_plus_rapid_fire`, `test_blast_no_bonus_small_unit`

### `tests/unit/test_consolidation_new_fights.gd` (17) — new fighters after consolidation
Consolidating into a new enemy is expected to add the unit to the fight sequence /
newly-eligible list; the suite consistently finds 0 added. High-value to triage —
if real, units that consolidate into a fresh combat never get to fight.
- e.g. `test_consolidation_into_new_enemy_adds_to_fight_sequence`: "Should have 1 newly eligible unit" (0)
- `test_multiple_new_enemies_eligible`, `test_p1_unit_eligible_when_p2_consolidates`, `test_empty_consolidation_movements`, …

### Base-to-base / pile-in enforcement — `test_base_contact_enforcement.gd` (2), `test_pile_in_b2b_enforcement.gd` (5), `test_pile_in_base_contact_locked.gd` (7)
Mix of "could reach b2b but didn't should be invalid" not triggering and
"Model position not found" errors (suggests the test board/model schema drifted).
- `test_model_within_tolerance_is_b2b`: "Model within b2b tolerance should count as b2b"
- `test_pile_in_rejects_movement_of_b2b_model`: "Model 0 position not found"

### `tests/unit/test_terrain_charge_interaction.gd` (4) — terrain charge penalty is 0
- `test_rules_engine_fly_vs_non_fly_terrain_penalty`: "Non-FLY should have a positive terrain penalty" (got 0.0)
- `test_rules_engine_charge_paths_with_terrain_penalty`: "terrain height penalty makes effective distance exceed charge roll" (didn't)

### `tests/unit/test_indirect_fire_keyword.gd` (4)
- `test_indirect_fire_applies_minus_one_to_hit`: "Dice log should have indirect_fire_applied = true"
- `test_indirect_fire_grants_cover_interactive`: "Model should have cover from Indirect Fire even without terrain"

### `tests/integration/test_heavy_keyword_integration.gd` (2) — type error
- `test_heavy_bonus_applied_when_unit_remained_stationary`: "Cannot convert 2 to boolean"
- `test_heavy_bonus_not_applied_to_non_heavy_weapon`: "Cannot convert 0 to boolean"
  (A flag is being read as bool but holds an int — likely a real code or test type bug.)

### `tests/unit/test_formations_phase.gd` (4) — warlord designation
- `test_warlord_auto_designate_single_character`: "captain_a should now be designated as warlord"
- `test_designate_warlord_action` / `test_designate_warlord_clears_previous`

### `tests/unit/test_pivot_cost.gd` (2) — rotation restore on undo/reset
- `test_reset_unit_move_restores_rotation`: "Rotation should be restored to original value (0.0)" (got 1.5)
- `test_undo_last_model_restores_rotation`: "Undo should include rotation restoration change"

### `tests/unit/test_precision_keyword.gd` (1)
- `test_has_precision_returns_true_for_precision_weapon`: "Weapon with 'precision' in special_rules should be detected"

### `tests/unit/test_lance_keyword.gd` (1)
- `test_lance_shooting_auto_resolve_charged`: "Lance ranged on charge should produce more wounds (0) than without charge (0)" (both 0 — likely test setup)

### `tests/unit/test_skip_attacks_target_destroyed.gd` (1)
- `test_overwatch_skips_weapons_after_target_destroyed`: "Should have at least one weapon result"

### `tests/unit/test_mission_selection.gd` (1)
- `test_mission_data_get_unknown_returns_empty`: "Unknown mission should return empty dict"

### Save / load — `test_save19_export_import.gd` (4), `test_save_load_dialog_main_menu.gd` (1)
- `test_export_file_contains_valid_game_data`: "game_data should deserialize to non-empty state" (empty)
- `test_import_exported_file`: "Import should succeed"
- `test_main_menu_button_exists`: "MainMenuButton node should exist in the dialog" (null — UI node renamed/removed)

### `tests/unit/test_unit_ability_manager.gd` (2)
- `test_is_ability_implemented`, `test_get_implemented_abilities` (assert with empty message — inspect directly)

### Integration — active-player / phase-label / MP sync
- `tests/integration/test_e2e_workflow.gd` (9): `test_multi_turn_game_simulation` — active player fails to alternate (P1→P2→P1) and battle round fails to advance across turns; `SELECT_SHOOTER should be valid: "no eligible targets"`.
- `tests/integration/test_full_gameplay_sequence.gd` (3): phase label reads `"DEPLOYMENT PHASE"` but test expects `"DEPLOYMENT"` (stale expectation vs UI string change); "Camera should have moved during controls".
- `tests/integration/test_multiplayer_deployment.gd` (3) + `test_multiplayer_network.gd`: host/client state retrieval + agreement (`host='Formations'` vs `client='First-Turn Roll-Off'`, whose-turn mismatch). Likely MP harness/timing, but worth confirming deployment sync is actually intact.

---

## Suggested order of attack

1. **Bucket A** — trivial, restores lost coverage: fix/trim `test_battle_shock.gd`.
2. **Add suite-level autoload reset**, then re-run — this should clear most of
   Bucket B and shrink the list dramatically, revealing the true Bucket C set.
3. **Triage remaining Bucket C**, prioritising `test_consolidation_new_fights`
   (gameplay-affecting if real), the save/load export, and the Heavy-keyword
   type error.
