# Tests Needing Local Verification

## AI Charge Declarations Implementation

**Task:** Implement AI charge declarations -- evaluate charge feasibility (distance, probability), declare charges against optimal targets, compute model positions post-charge (AI-GAP-1, CHARGE-1 through CHARGE-3)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added charge evaluation, target scoring, move computation
- `40k/phases/ChargePhase.gd` - Extended `get_available_actions()` with reaction states and APPLY_CHARGE_MOVE; set `current_charging_unit` in DECLARE_CHARGE processing
- `40k/tests/unit/test_ai_charge_decisions.gd` - New test file for AI charge logic

**Tests to run:**
- Run `test_ai_charge_decisions.gd` via `godot --headless --script tests/unit/test_ai_charge_decisions.gd`
  - Tests charge probability calculations (guaranteed, impossible, edges)
  - Tests charge target evaluation (close target, far target, preference)
  - Tests charge roll, complete, and reaction decline actions
  - Tests melee damage estimation
  - Tests charge target scoring
  - Tests melee weapon detection
  - Tests closest model distance calculation
  - Tests charge move computation (model positioning)
- Run an AI vs AI game and observe that AI units now declare and attempt charges instead of always skipping
- Run a Human vs AI game and verify the AI charges your units in the charge phase

**What to look for:**
- AI declares charges against nearby enemy units with good probability
- AI skips charges when targets are too far or when there are no melee weapons
- Charge rolls proceed correctly after declaration
- After successful charge roll, models move into engagement range of targets
- COMPLETE_UNIT_CHARGE is sent to clean up after charge move
- Reaction decisions (Command Re-roll, Fire Overwatch, Heroic Intervention, Tank Shock) are properly declined
- No infinite loops during charge phase
- Human player charge flow still works correctly (no regression from ChargePhase changes)

## AI Pile-In Movement Implementation

**Task:** Implement pile-in movement -- move models up to 3" toward nearest enemy during fight phase (AI-GAP-2, FIGHT-1)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Replaced pile-in hold-position stub with `_compute_pile_in_action()` and `_compute_pile_in_movements()` that compute per-model movements toward nearest enemy; added `_find_model_index_in_unit()` helper
- `40k/tests/unit/test_ai_pile_in.gd` - New test file for AI pile-in logic

**Tests to run:**
- Run `test_ai_pile_in.gd` via `godot --headless --script tests/unit/test_ai_pile_in.gd`
  - Tests model moves toward nearby enemy
  - Tests model in base contact holds position (T4-5 rule)
  - Tests 3" movement limit is respected
  - Tests empty movements when no enemies exist
  - Tests PILE_IN action is returned from `_decide_fight()` with computed movements
  - Tests dead models are skipped
  - Tests multiple models all move toward enemy
  - Tests model index mapping (string keys match array indices)
  - Tests `_find_model_index_in_unit()` helper
  - Tests far model clamps movement to exactly 3"
- Run an AI vs AI game and observe that AI units now pile in toward enemies instead of holding position
- Run a Human vs AI game and verify the AI models move toward your units during pile-in

**What to look for:**
- AI models move up to 3" toward the closest enemy model during pile-in
- Models already in base-to-base contact do not move
- Movement is clamped to 3" even when enemies are further away
- Models do not collide with each other or other deployed models
- AIRCRAFT enemies are ignored unless the pile-in unit has FLY keyword
- The FightPhase validation accepts the AI's computed movements (no validation errors)
- Human player pile-in drag-and-drop still works correctly (no regression)
- No infinite loops during fight phase

## AI Consolidation Movement Implementation

**Task:** Implement consolidation movement -- move models up to 3" toward nearest enemy or objective after fighting (AI-GAP-2, FIGHT-2)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Replaced consolidation hold-position stub with `_compute_consolidate_action()`, `_determine_ai_consolidate_mode()`, and `_compute_consolidate_movements_objective()`; engagement mode reuses existing `_compute_pile_in_movements()`
- `40k/tests/unit/test_ai_consolidation.gd` - New test file for AI consolidation logic

**Tests to run:**
- Run `test_ai_consolidation.gd` via `godot --headless --script tests/unit/test_ai_consolidation.gd`
  - Tests consolidation mode detection (ENGAGEMENT when enemy within 4", OBJECTIVE when enemy far but objectives exist, NONE when neither)
  - Tests engagement mode moves models toward closest enemy (reuses pile-in logic)
  - Tests objective mode moves models toward closest objective marker
  - Tests 3" movement limit is respected in both modes
  - Tests AIRCRAFT units skip consolidation
  - Tests models in base contact hold position during engagement-mode consolidation
  - Tests empty movements when no enemies and no objectives
  - Tests CONSOLIDATE action is returned from `_decide_fight()` with computed movements
  - Tests dead models are skipped
  - Tests multiple models all move toward objective
- Run an AI vs AI game and observe that AI units now consolidate toward enemies or objectives after fighting
- Run a Human vs AI game and verify the AI models move after fighting instead of always holding position

**What to look for:**
- AI models move up to 3" toward the closest enemy model when in engagement reach (within 4")
- When no enemy is reachable, AI models move up to 3" toward the closest objective marker
- Models already in base-to-base contact do not move (engagement mode)
- Movement is clamped to 3" in both modes
- AIRCRAFT units produce empty movements (T4-4 rule)
- Models do not collide with each other or other deployed models
- The FightPhase validation accepts the AI's computed movements (no validation errors in either mode)
- Newly eligible units are properly detected after consolidation moves (T2-6 rule still works)
- Human player consolidation drag-and-drop still works correctly (no regression)
- No infinite loops during fight phase

## AI Fall-Back Model Positioning Implementation

**Task:** Implement fall-back model positioning -- compute valid fall-back destinations away from enemy engagement range (MOV-6)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added `_compute_fall_back_destinations()`, `_get_engaging_enemy_centroid()`, `_pick_fall_back_target()`, `_build_fall_back_directions()`, `_try_fall_back_positions()`, `_resolve_fall_back_position()`; updated `_decide_engaged_unit()` to include `_ai_model_destinations` with computed positions
- `40k/autoloads/AIPlayer.gd` - Extended `_execute_next_action()` to handle `BEGIN_FALL_BACK` and `BEGIN_ADVANCE` with `_ai_model_destinations` (not just `BEGIN_NORMAL_MOVE`)
- `40k/tests/unit/test_ai_fall_back_positioning.gd` - New test file for AI fall-back positioning logic

**Tests to run:**
- Run `test_ai_fall_back_positioning.gd` via `godot --headless --script tests/unit/test_ai_fall_back_positioning.gd`
  - Tests fall-back computes non-empty destinations for engaged units
  - Tests all destinations are outside engagement range of all enemies
  - Tests all destinations are within the unit's movement cap
  - Tests the `_decide_movement()` decision includes `_ai_model_destinations` when falling back
  - Tests retreat direction prefers friendly objectives
  - Tests multi-model fall-back (all 5 models get destinations)
  - Tests fall-back stays within board bounds near edges
  - Tests `_get_engaging_enemy_centroid()` correctly identifies engaging enemies
  - Tests `_build_fall_back_directions()` generates 12 directions
  - Tests surrounded unit gracefully handles no valid path
- Run existing `test_ai_movement_decisions.gd` to confirm no regressions
- Run an AI vs AI game and observe that AI units now physically move when falling back
- Run a Human vs AI game and verify AI models reposition away from your engaged units

**What to look for:**
- AI models physically move to new positions when falling back (not just setting the fell_back flag)
- All fall-back destinations end outside engagement range of all enemy models
- Models stay within their M" movement cap
- Models don't overlap with other models (friendly or enemy)
- Models stay within the board boundaries
- AI prefers retreating toward friendly or uncontrolled objectives
- When completely surrounded and unable to escape, AI remains stationary instead of getting stuck
- The MovementPhase validation accepts the AI's computed fall-back positions
- Human player fall-back still works correctly (no regression from AIPlayer.gd changes)
- No infinite loops during movement phase

## AI Weapon Range Checking in Target Scoring

**Task:** Add weapon range checking to target scoring -- score 0 for out-of-range targets (AI-GAP-5, SHOOT-4)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added `_get_weapon_range_inches()` helper; modified `_score_shooting_target()` to accept shooter_unit and return 0 for out-of-range targets; updated call site in `_decide_shooting()`
- `40k/tests/unit/test_ai_weapon_range_scoring.gd` - New test file for weapon range scoring logic

**Tests to run:**
- Run `test_ai_weapon_range_scoring.gd` via `godot --headless --script tests/unit/test_ai_weapon_range_scoring.gd`
  - Tests `_get_weapon_range_inches()` parsing for standard ranges, melee, zero, and invalid strings
  - Tests `_score_shooting_target()` returns 0 for out-of-range targets
  - Tests `_score_shooting_target()` returns positive score for in-range targets
  - Tests scoring at exact weapon range boundary
  - Tests backward compatibility (no shooter_unit provided skips range check)
  - Tests different weapon ranges (pistol vs lascannon) at same distance
  - Tests `_decide_shooting()` skips unit when all targets are out of range
  - Tests `_decide_shooting()` produces SHOOT action when target is in range
- Run an AI vs AI game and observe that AI units no longer attempt to shoot at targets beyond weapon range
- Run a Human vs AI game and verify the AI shooting decisions are more tactically sound

**What to look for:**
- AI no longer tries to shoot targets that are clearly out of range
- AI correctly identifies in-range targets and assigns weapons to them
- Short-range weapons (e.g., bolt pistol 12") do not get assigned to far targets while long-range weapons (e.g., lascannon 48") still do
- When all enemy units are out of range, the AI skips the shooter unit instead of producing an invalid SHOOT action
- The SHOOT actions produced by AI are accepted by the ShootingPhase validation (no "out of range" errors)
- No regressions in AI shooting for units that have targets in range

## AI Focus Fire System Implementation

**Task:** Implement focus fire system -- coordinate weapon assignments across all shooting units to concentrate on kill thresholds (AI-TACTIC-2, SHOOT-1)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added focus fire plan builder (`_build_focus_fire_plan`, `_calculate_kill_threshold`, `_calculate_target_value`, `_estimate_weapon_damage`); modified `_decide_shooting()` to build and use coordinated plan across all shooting units; added `_get_alive_model_ids()` helper; added `_build_unit_assignments_fallback()` for graceful degradation; fixed model_ids population (was previously empty, causing 0 attacks)
- `40k/tests/unit/test_ai_focus_fire.gd` - New test file for focus fire system

**Tests to run:**
- Run `test_ai_focus_fire.gd` via `godot --headless --script tests/unit/test_ai_focus_fire.gd`
  - Tests kill threshold calculation (single model, multi-model, wounded models)
  - Tests target value scoring (CHARACTER bonus, VEHICLE bonus, below-half-health bonus)
  - Tests expected damage estimation (basic, out-of-range, model count scaling)
  - Tests focus fire plan building (single unit, concentration on killable targets, excess redirection)
  - Tests _decide_shooting integration (uses plan, populates model_ids)
  - Tests plan reset on phase change
  - Tests fallback assignment with model_ids population
  - Tests _get_alive_model_ids helper
- Run `test_ai_weapon_range_scoring.gd` to confirm no regressions in range checking
- Run an AI vs AI game and observe that AI units now concentrate fire on targets they can kill
- Run a Human vs AI game and verify the AI focuses fire more effectively

**What to look for:**
- AI concentrates fire from multiple weapons on targets it can kill (below kill threshold)
- AI redirects excess damage to secondary targets instead of overkilling a single weak unit
- CHARACTERs, VEHICLEs, and wounded units receive higher targeting priority
- model_ids are now properly populated in SHOOT actions (critical fix: was empty before, causing 0 attacks)
- All SHOOT actions produced by AI are accepted by the ShootingPhase (no validation errors)
- Focus fire plan is properly reset between shooting phases
- No infinite loops during shooting phase
- No regressions in AI shooting for single-target scenarios
