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

## AI Weapon-Target Efficiency Matching Implementation

**Task:** Implement weapon-target efficiency matching -- match anti-tank to vehicles, anti-infantry to hordes, avoid wasting multi-damage on single-wound models (AI-TACTIC-5, SHOOT-2)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added weapon role classification (`_classify_weapon_role`), target type classification (`_classify_target_type`), efficiency multiplier calculation (`_calculate_efficiency_multiplier`), damage parsing (`_parse_average_damage`), anti-keyword matching, and display helpers; integrated efficiency multiplier into `_estimate_weapon_damage` and `_score_shooting_target`; added efficiency-aware logging to focus fire plan
- `40k/tests/unit/test_ai_weapon_efficiency.gd` - New test file for weapon-target efficiency matching

**Tests to run:**
- Run `test_ai_weapon_efficiency.gd` via `godot --headless --script tests/unit/test_ai_weapon_efficiency.gd`
  - Tests weapon role classification (lascannon as anti-tank, bolt rifle as anti-infantry, heavy bolter as general purpose, anti-keyword weapons, torrent, high-attacks)
  - Tests target type classification (VEHICLE, MONSTER, horde, elite, high-toughness without keyword, various squad sizes)
  - Tests damage string parsing (fixed, D3, D6, D3+1, D6+1)
  - Tests efficiency multiplier calculation (anti-tank vs vehicle, anti-tank vs horde, anti-infantry vs horde, anti-infantry vs vehicle, general purpose, multi-damage penalties, anti-keyword bonus)
  - Tests integration with _estimate_weapon_damage (lascannon prefers vehicle, bolt rifle prefers infantry)
  - Tests focus fire plan assigns lascannon to vehicle target not horde target
  - Tests display name helpers
- Run `test_ai_focus_fire.gd` to confirm no regressions in focus fire system
- Run `test_ai_weapon_range_scoring.gd` to confirm no regressions in range scoring
- Run an AI vs AI game and observe weapon-target matching in the console logs (look for "[Anti-Tank]", "[Anti-Infantry]", "[General]" role labels and efficiency multipliers)
- Run a Human vs AI game and verify the AI directs heavy weapons at vehicles and small arms at infantry

**What to look for:**
- Lascannons, missile launchers, and other S7+ AP-2+ D3+ weapons are classified as Anti-Tank and preferentially target VEHICLE/MONSTER units
- Bolt rifles, shootas, sluggas, and other S4-5 D1 weapons are classified as Anti-Infantry and preferentially target HORDE units
- Weapons with "anti-vehicle" or "anti-monster" special rules are always classified as Anti-Tank
- Weapons with "anti-infantry" special rules are always classified as Anti-Infantry
- Multi-damage weapons (D3+) are penalized when targeting 1-wound models to avoid wasted damage
- Anti-keyword bonuses apply when weapon special rules match target keywords (e.g. anti-infantry vs INFANTRY)
- Console logs show efficiency multipliers for each weapon-target assignment in the focus fire plan
- No regressions in existing AI shooting behavior for scenarios without vehicles/hordes

## AI Invulnerable Save Integration in Target Scoring

**Task:** Add invulnerable save to target scoring -- use min(modified_save, invuln) in shooting target evaluation (AI-GAP-6, SHOOT-3)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added `_get_target_invulnerable_save()` helper to extract best invuln from model, meta stats, and effect flags; updated `_save_probability()` to accept optional invuln parameter; updated `_score_shooting_target()`, `_estimate_weapon_damage()`, and `_estimate_melee_damage()` to pass invuln through
- `40k/tests/unit/test_ai_invulnerable_save_scoring.gd` - New test file for AI invulnerable save scoring logic

**Tests to run:**
- Run `test_ai_invulnerable_save_scoring.gd` via `godot --headless --script tests/unit/test_ai_invulnerable_save_scoring.gd`
  - Tests `_save_probability` with no invuln (unchanged behavior)
  - Tests `_save_probability` when invuln is better than AP-modified armour save
  - Tests `_save_probability` when armour is better than invuln
  - Tests `_save_probability` when invuln rescues from AP-wiped armour
  - Tests `_save_probability` with invuln=0 matches no-invuln behavior
  - Tests `_get_target_invulnerable_save` reads from model, meta stats, effect flags
  - Tests `_get_target_invulnerable_save` picks best (lowest) invuln across sources
  - Tests `_get_target_invulnerable_save` handles string-type invuln values
  - Tests `_score_shooting_target` produces lower scores for invuln-protected targets
  - Tests `_score_shooting_target` unchanged when invuln is worse than armour
  - Tests `_estimate_melee_damage` accounts for invuln saves
  - Tests `_estimate_weapon_damage` accounts for invuln saves
- Run `test_ai_weapon_range_scoring.gd` to confirm no regressions
- Run `test_ai_weapon_efficiency.gd` to confirm no regressions
- Run `test_ai_focus_fire.gd` to confirm no regressions
- Run an AI vs AI game and observe that the AI now correctly evaluates damage against invuln-protected targets

**What to look for:**
- AI correctly reduces expected damage estimates against targets with invulnerable saves
- High-AP weapons still score well against targets without invuln, but score lower against invuln-protected targets
- Low-AP weapons are unaffected by invuln saves (since armour save is better anyway)
- Invulnerable saves from all three sources are detected: model-level, unit-level meta stats, and effect-granted (Go to Ground)
- Effect-granted invuln (e.g., 4++ from a stratagem) overrides worse native invuln (e.g., 6++)
- No regressions in existing AI shooting, melee, or charge evaluation

## AI Weapon Keyword Awareness in Target Scoring (SHOOT-5)

**Task:** Add weapon keyword awareness to target scoring -- Blast, Rapid Fire, Melta, Anti-keyword, Torrent, Sustained/Lethal/Devastating Wounds (SHOOT-5)
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added `_apply_weapon_keyword_modifiers()` central function, keyword parsing helpers (`_parse_rapid_fire_value`, `_parse_melta_value`, `_parse_anti_keyword_data`, `_parse_sustained_hits_value`, `_is_within_half_range`); integrated into `_score_shooting_target()` and `_estimate_weapon_damage()`; added `CRIT_PROBABILITY` and `HALF_RANGE_FALLBACK_PROB` constants
- `40k/tests/unit/test_ai_weapon_keyword_scoring.gd` - New test file for weapon keyword-aware scoring

**Tests to run:**
- Run `test_ai_weapon_keyword_scoring.gd` via `godot --headless --script tests/unit/test_ai_weapon_keyword_scoring.gd`
  - Tests parsing helpers (rapid fire, melta, anti-keyword, sustained hits, half-range detection)
  - Tests Torrent sets p_hit to 1.0 and scores higher than equivalent non-torrent weapon
  - Tests Blast adds bonus attacks vs large units (6-10: +1, 11+: +2), enforces minimum 3, prefers large units
  - Tests Rapid Fire bonus at half range, no bonus beyond half range, fallback probability-weighted bonus
  - Tests Melta bonus damage at half range, no bonus beyond half range
  - Tests Anti-keyword improves wound probability vs matching targets, no effect vs non-matching
  - Tests Sustained Hits increases expected damage
  - Tests Lethal Hits increases expected damage
  - Tests Devastating Wounds increases expected damage vs well-armoured targets
  - Tests combined keywords (anti-infantry + devastating wounds, blast + torrent, rapid fire + sustained hits)
  - Tests integration with `_score_shooting_target()` and `_estimate_weapon_damage()`
- Run `test_ai_weapon_efficiency.gd` to confirm no regressions in weapon-target efficiency matching
- Run `test_ai_weapon_range_scoring.gd` to confirm no regressions in range scoring
- Run `test_ai_focus_fire.gd` to confirm no regressions in focus fire system
- Run `test_ai_invulnerable_save_scoring.gd` to confirm no regressions in invuln scoring
- Run an AI vs AI game and observe that AI weapon targeting now reflects keyword-aware damage estimates

**What to look for:**
- Torrent weapons (e.g. flamers) are valued much higher since they auto-hit (p_hit = 1.0 vs normal BS roll)
- Blast weapons are preferred against large units (6+ models) due to bonus attacks
- Rapid Fire weapons get bonus attacks when targets are within half range
- Melta weapons get bonus damage when targets are within half range
- Anti-keyword weapons (e.g. anti-infantry 4+) score higher against matching targets due to improved wound probability
- Sustained Hits weapons generate higher expected damage from bonus hits on critical rolls
- Lethal Hits weapons score higher especially against tough targets (bypasses wound roll on 6s)
- Devastating Wounds weapons score higher especially against well-armoured targets (bypasses saves on 6s to wound)
- Combined keywords stack correctly (e.g. anti-infantry + devastating wounds + rapid fire)
- No regressions in existing AI shooting behavior, focus fire, or weapon-target efficiency

## AI Unit Ability Awareness Implementation (AI-GAP-4)

**Task:** Implement unit ability awareness -- read abilities, factor leader bonuses, detect "Fall Back and X" abilities
**Files changed:**
- `40k/scripts/AIAbilityAnalyzer.gd` - New static utility class for AI ability awareness: reads unit abilities, detects leader bonuses (+1 hit, reroll hits/wounds, FNP, cover, Fall Back and X, Advance and X), computes offensive/defensive multipliers for scoring
- `40k/scripts/AIDecisionMaker.gd` - Integrated AIAbilityAnalyzer into movement (Fall Back and X awareness in `_decide_engaged_unit`, Advance and X in `_should_unit_advance`), shooting (`_score_shooting_target` and `_estimate_weapon_damage` now factor in target FNP and Stealth, shooter leader bonuses), charge (`_score_charge_target` uses melee leader multiplier and target defensive multiplier, `_evaluate_best_charge` factors in melee leader bonuses), and melee (`_estimate_melee_damage` factors in target FNP)
- `40k/tests/unit/test_ai_ability_awareness.gd` - New test file for AI ability awareness

**Tests to run:**
- Run `test_ai_ability_awareness.gd` via `godot --headless --script tests/unit/test_ai_ability_awareness.gd`
  - Tests ability parsing (string format, dict format, mixed format, Core skipping)
  - Tests unit_has_ability and unit_has_ability_containing
  - Tests leader bonus detection (no leader, +1 hit melee, reroll hits ranged, FNP from leader, cover from leader, multiple effects)
  - Tests Fall Back and X detection (from leader abilities, from effect flags, from description-based fallback)
  - Tests Advance and X detection (from leader, from flags)
  - Tests defensive ability detection (FNP from stats, flags, best-of-both; Stealth from abilities and flags; Lone Operative detection and protection)
  - Tests offensive/defensive multiplier computation
  - Tests comprehensive unit ability profile
  - Tests AIDecisionMaker integration (shooting score reduced by target FNP and Stealth, melee damage reduced by target FNP, charge score boosted by melee leader bonuses)
- Run `test_ai_invulnerable_save_scoring.gd` to confirm no regressions
- Run `test_ai_weapon_keyword_scoring.gd` to confirm no regressions
- Run `test_ai_weapon_efficiency.gd` to confirm no regressions
- Run `test_ai_focus_fire.gd` to confirm no regressions
- Run an AI vs AI game and observe that AI now considers abilities in tactical decisions

**What to look for:**
- AI units with Fall Back and Charge abilities fall back more aggressively (even from objectives) knowing they can charge back in
- AI units with Fall Back and Shoot abilities fall back when engaged, recognizing they can still contribute via shooting
- AI units with Advance and Shoot/Charge abilities advance more eagerly since there is no penalty
- AI shooting scores are lower against targets with FNP (reflecting reduced effective damage)
- AI shooting scores are lower against targets with Stealth (reflecting -1 to hit penalty)
- AI charge evaluations are higher for units with melee leader bonuses (+1 hit, reroll hits)
- AI charge evaluations are lower against targets with high defensive multipliers (FNP, cover from leaders)
- Leader bonus detection correctly reads the UnitAbilityManager ABILITY_EFFECTS lookup table
- Description-based fallback correctly detects "fall back and charge/shoot" from ability descriptions
- No regressions in existing AI movement, shooting, charge, or fight decisions

## AI Stratagem Usage Implementation (AI-GAP-3)

**Task:** Implement basic stratagem usage -- Grenade, Fire Overwatch, Go to Ground, Command Re-roll, Smokescreen
**Files changed:**
- `40k/scripts/AIDecisionMaker.gd` - Added stratagem evaluation section: `evaluate_grenade_usage()`, `_estimate_unit_ranged_strength()`, `_score_grenade_target()` for Grenade heuristics; `evaluate_reactive_stratagem()`, `_score_defensive_stratagem_target()` for Go to Ground/Smokescreen; `evaluate_fire_overwatch()`, `_decline_fire_overwatch()`, `_count_unit_ranged_shots()`, `_estimate_unit_value()` for Fire Overwatch; `evaluate_command_reroll_charge()`, `evaluate_command_reroll_battleshock()`, `evaluate_command_reroll_advance()` for Command Re-roll; `_get_player_cp_from_snapshot()` helper; added `_grenade_evaluated` static flag; updated `_decide_shooting()` to check Grenade before shooting; updated `_decide_charge()` to evaluate Fire Overwatch and Command Re-roll instead of always declining; updated `_decide_command()` to defer to signal handler for reroll context
- `40k/autoloads/AIPlayer.gd` - Added reactive stratagem signal handling: `_connect_phase_stratagem_signals()`, `_disconnect_phase_stratagem_signals()` for phase signal lifecycle; `_on_reactive_stratagem_opportunity()` for Go to Ground/Smokescreen during opponent's shooting; `_on_movement_fire_overwatch_opportunity()` for Fire Overwatch during opponent's movement; `_on_charge_overwatch_opportunity()` for Fire Overwatch during opponent's charge; `_on_command_reroll_opportunity()` for Command Re-roll after any dice roll; `_submit_reactive_action()`, `_execute_reactive_action_deferred()` for deferred action submission
- `40k/tests/unit/test_ai_stratagem_evaluation.gd` - New test file for AI stratagem evaluation heuristics

**Tests to run:**
- Run `test_ai_stratagem_evaluation.gd` via `godot --headless --script tests/unit/test_ai_stratagem_evaluation.gd`
  - Tests grenade target scoring (1W models, multi-wound, characters, dead units)
  - Tests ranged strength estimation (no weapons, basic, multi-weapon)
  - Tests defensive stratagem scoring (Go to Ground without invuln, with invuln, Smokescreen, dead units)
  - Tests Fire Overwatch evaluation (high-volume shooter, low CP decline)
  - Tests Command Re-roll evaluation (charge failed close, succeeded, impossible, advance low/moderate, battle-shock high/low leadership)
  - Tests reactive stratagem integration (Go to Ground on infantry, decline for dead units)
  - Tests helper functions (get_player_cp_from_snapshot)
- Run `test_ai_charge_decisions.gd` to confirm no regressions in charge decisions (now evaluates Fire Overwatch instead of always declining)
- Run an AI vs AI game and observe:
  - AI uses Grenade stratagem during shooting when units with GRENADES keyword are near enemies
  - AI uses Go to Ground / Smokescreen when defending units are targeted by opponent
  - AI uses Fire Overwatch when opponent moves units near high-volume shooters
  - AI uses Command Re-roll on failed charge rolls that are close to succeeding
  - CP is correctly deducted for stratagem usage
- Run a Human vs AI game and verify:
  - AI responds to your shooting with Go to Ground / Smokescreen when appropriate
  - AI fires overwatch at your units when you move near their high-volume shooters
  - AI rerolls charge dice that narrowly missed
  - AI does not waste CP on low-probability rerolls

**What to look for:**
- GRENADE: AI uses Grenade when a unit has weak ranged weapons but GRENADES keyword and an enemy is within 8". Prefers targets with 1W models.
- FIRE OVERWATCH: AI fires overwatch with highest-volume shooter when enemy is valuable and CP >= 2. Does not use overwatch with 1-2 shot units.
- GO TO GROUND: AI uses on INFANTRY targets without existing invuln saves. Factors in save quality, model count, and unit value.
- SMOKESCREEN: AI uses on SMOKE keyword units (stealth -1 to hit is very strong). Prioritized over Go to Ground.
- COMMAND RE-ROLL: AI rerolls failed charges within 2 of the target (good odds). Rerolls failed battle-shock with high leadership. Rerolls advance rolls of 1. Does not reroll when CP is very low or odds are poor.
- No infinite loops from signal-based reactive action submission
- No double-actions from race conditions between signal handlers and _evaluate_and_act
- CP is correctly tracked across all stratagem uses
- All reactive stratagem actions are validated and processed correctly by the phase system
