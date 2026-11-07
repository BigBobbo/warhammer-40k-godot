# AI movement intent guide — reader reports (appendix)

Raw reports the guide was synthesised from (2026-11-07, HEAD 1c51d7b). Line numbers drift; re-check before editing.

## A. Movement decision pipeline

# AI movement pipeline: where a new movement intent hooks in

This is a read-only map. Line numbers are as of HEAD `1c51d7b`. File abbreviations: **ADM** = `40k/scripts/AIDecisionMaker.gd` (29,128 lines, all static functions), **AIP** = `40k/autoloads/AIPlayer.gd`, **TM** = `40k/autoloads/TerrainManager.gd`. Units are 40 px per inch (ADM:30) on a 1760×2400 px board (ADM:44-45). Don't use the line numbers in `docs/ai_dossiers/movement.md`: they come from an older 24k-line version of the file.

## 0. Conventions every new intent must follow
- **Tunables:** read through `get_param("NAME", NAME_CONST)` (ADM:1553). The priority order is rule override > profile > `ai_config.json` > constant. Use `get_param_int` (ADM:1576) for integers.
- **Ship OFF by default.** A new weight constant defaults to 0.0, like `WEIGHT_HIDDEN_GAINED` (ADM:2633; the reason is at ADM:2614-2630). A behaviour switch is a `FIX_X` 0/1 constant, read as `>= 0.5`, that prints `[FIX_X] … old=… new=…` (pattern at ADM:1640-2023).
  - Put the opt-in values in a profile under `40k/tests/bench_profiles/` (format example: `yt_findings_on.json`).
  - Compare arms with `40k/tests/run_ai_benchmark.sh`.
- **Score ledger:** add every score contribution with `_t_add` / `_t_mul` (ADM:2374/2379) so that `sum(score_terms) == score`. The decision cards read `score_terms`.
- **Narration:** use `_add_thinking_step` (ADM:2810). Notes about how a move was shaped go to `_move_shape_notes` (ADM:516). Only the normal-move branch turns those notes into `_ai_move_adjustments` (ADM:7640). Lists of scored options go through `_record_choice` (ADM:2341).
- **Static state:** any new static cache that must survive past one `decide()` call has to be added to `_snapshot_planning_state` / `_restore_planning_state` (ADM:3675/3722). `suggest_action` (ADM:3469) and the window previews (ADM:3626) restore that state.
- **Tests to copy:**
  - Headless: `tests/test_ai_movement_coordination.gd` calls `_assign_units_to_objectives` directly (line 78).
  - Windowed: `tests/scenarios/sp/ai_hidden_awareness_11e.json` loads a bench profile to turn on weights that ship off. `ai_coordinated_movement.json` and `ai_objective_race_long_trip.json` are also good models.

## 1. Call order and how a unit is chosen
`decide()` (ADM:3267) calls `_decide_movement` (ADM:6770), which runs these steps in order. The first step that produces an action returns it.

| Step | Line | Effect |
|---|---|---|
| 0 | 6778 | Decline a pending Command Re-roll (fallback) |
| 0.8 | 6792 | Cancel Kunnin' Infiltrator |
| 1 | 6804 | Fallback CONFIRM_UNIT_MOVE |
| 1.5 | 6815 | `_decide_reserves_arrival` |
| 1.75 | 6823 | `_decide_transport_disembark` |
| 2 | 6830-6852 | `_select_movement_action`; attach `_ai_assignment` (6848); `_finalize_movement_decision` (6851) |
| 3 | 6854 | END_MOVEMENT |

`_select_movement_action` (ADM:6857) does the following:
1. **Movable units** are the actors of BEGIN_NORMAL_MOVE, BEGIN_ADVANCE, BEGIN_FALL_BACK and REMAIN_STATIONARY (6861).
2. **Phase plan:** `_build_phase_plan` (6881; ADM:3773) runs once per round per player. It produces `charge_intent`, `lock_targets` and `shooting_lanes` (3776-3946).
3. **Awareness and stratagems:** awareness fallbacks run (6900-6921). Proactive movement stratagems can return early (6924).
4. **Threat data** is rebuilt on every call: `_calculate_enemy_threat_data` (6931; ADM:28695).
5. **Battle plan:** reuse the persistent plan or re-plan (6947-7011); see §2.
6. **Split units:** a unit offered BEGIN_FALL_BACK but not BEGIN_NORMAL_MOVE counts as engaged (7022). Engaged units are decided first, by `_decide_engaged_unit` (7110-7117).
7. **Sort the remaining units** (7123-7146):
   - by tier: disembarked this phase = 0, normal = 1, transport VEHICLE = 2;
   - then front to back, when centroids are more than 80 px apart in y (P1 moves larger y first, P2 smaller y first);
   - then by plan score.
   - `_build_move_order` (ADM:7666) explains the order.
8. **The loop at 7158 returns the first unit's decision.** Every branch ends in a REMAIN_STATIONARY fallback (7646). So exactly one unit acts per `decide()` call; AIPlayer executes it and asks again.

## 2. The persistent battle plan
- **Storage:** `_turn_movement_plan[player] = {round, assignments, consumed, replans, announce}` (7000).
  - It re-plans only when the round changes, when a movable unit is missing from the plan, or when a unit that already acted becomes movable again (6950-6967).
  - It is cleared when the phase ends and when a new round starts (ADM:3371-3388). A unit is marked consumed when it acts (ADM:4038).

### `_evaluate_all_objectives` (ADM:8926-9401)
- **Output** per objective (9355): `{id, position, state, friendly_oc, enemy_oc, priority, vp_value, oc_needed, contest_oc, projected_enemy_oc, enemy_arrivals, friendly_arrivals}`.
- **States** (9170-9208): uncontrolled, contested, enemy_weak, enemy_strong, held_safe, held_threatened.
- **Priority terms:**
  - State weights (9210): UNCONTROLLED 10, CONTESTED 8, ENEMY_WEAK 7, ENEMY_STRONG −5, ALREADY_HELD −3 (constants at ADM:2557-2562).
  - Home objective undefended: +9 (9224).
  - Round urgency (9233; constants ADM:2696-2698).
  - Tempo (9273).
  - Enemy home held strongly: −3 (9287).
  - Denial from round 3 (9289).
  - Retention of held objectives (9302-9320).
  - VP value × `WEIGHT_VP_PER_POINT` 1.2 (9336).

### `_assign_units_to_objectives` (ADM:9834-11952)
- Before the passes:
  - COORD-2 incoming OC (9874-9906): units that already moved this phase and are heading to an objective reduce its OC need.
  - Candidate loop over every (unit, objective) pair (9912-10598). Engaged units are skipped (9920). Units with a SCREEN earmark are withheld (9925).
- Then candidates are sorted (10601) and assigned greedily in passes:

| Pass | Lines | Output |
|---|---|---|
| 1 hold | 10606-10772 (loop 10666) | `hold`, with keeper logic deciding which of several holders stays |
| 2 capture | 10774-11252 (loop 11108) | `move` / `advance` via `apply_capture_assignment` (10999); skips DIM-RETURNS, TOO-LATE, RACE-SKIP, LONE-TRIP, FAR-TRIP and OVERCOMMIT trips; OBJ-ASSIGN-1 swaps in a quicker unit |
| 2.5 attack | 11347-11398 | `_melee_chase_gate` converts hold/move/advance into `attack` and re-opens the OC need |
| backfill | 11400-11436 | Fills the re-opened OC needs |
| 3 | 11438-11753 | `screen` (screen_denial 11525, screen_protect 11579, corridor_block 11611); support via `_find_best_remaining_objective` (11688); otherwise `hold` with objective `"none"` (11747) |
| notes | 11872-11950 | `_last_movement_candidates` and coordination notes |

- **Assignment shape:**
  - The candidate dict (10570-10597) plus `assign_pass`, `oc_consumed` and `reason`, and sometimes `coordination_note`.
  - An attack adds `attack_target_id`, `attack_target_name` and `attack_advance` (11381).
  - A screen stores a pseudo objective id (`screen_denial`, `screen_protect` or `corridor_block`), with `objective_pos` set to the target spot.

### How each plan action becomes a move
| Action | Lines | Executed as |
|---|---|---|
| hold | 7191 | REMAIN_STATIONARY |
| advance | 7203 | BEGIN_ADVANCE at **M+2"** toward `_objective_approach_target` (ADM:13193); threat avoidance on; no weapon-range clamp |
| attack | 7228-7272 | BEGIN_ADVANCE (M+2) or Normal move toward the enemy centroid; no threat avoidance (`[]`); falls back to `move` if no path |
| screen | 7275-7304 | REMAIN_STATIONARY if within Engagement Range of the spot, else a Normal move to the spot; no threat avoidance; falls through to the normal move |
| move / support | 7306-7645 | The normal-move chain below |

The normal-move chain, in order (the first early return wins):
1. Melee unit on an objective keeps moving if an enemy is close (7316).
2. Already in control range of the objective: hold (7347).
3. Pure ranged unit avoids walking into charge threat: hold (7357).
4. `_should_hold_for_shooting` (7410; ADM:13906).
5. Hold for the Heavy +1 to hit (7424; ADM:13618).
6. Lone Operative retreats or holds to stay more than 12" from enemies (7432).
7. A doomed Deadly Demise vehicle rushes the enemy (7466).
8. **Target shaping:** aim at the objective approach point (7501), then blend:
   - toward a planned charge (7491-7548; weights 0.3/0.5/0.7 must end within 9", ADM:2540-2541);
   - toward half range, weight 0.4 (7550);
   - toward a firing position, weight 0.35 (7574).
9. Generate destinations: `_compute_movement_toward_target(..., max_weapon_range, threat_data, objectives)` (7595).
10. If a charge steer no longer ends in charge reach after adjustments, redo the move straight at the objective (7600).
11. Return BEGIN_NORMAL_MOVE (7636).

## 3. How positions are scored and generated

### 3a. Plan-level score for each (unit, objective) pair
Every term is judged at `estimated_dest`: a straight line toward the approach point, capped at M (plus 3.5" when advancing) (10246-10249). It is **not** the position the unit will actually end at.

| Term | Line | Weight / param (default) | What it measures |
|---|---|---|---|
| objective_priority | 10083 | priority × STRATEGY_*_OBJECTIVE (0.95 / 1 / 1.6) | Objective value |
| oc_efficiency | 10087 | WEIGHT_OC_EFFICIENCY 2.0 | Unit OC against the need |
| contest_race / reinforce_race | 10150 / 10177 | ×MOVE_RACE_LOSS_FACTOR 0.5 | Enemy gets there first |
| distance_penalty | 10188 | max(2.0, 0.2×score) per extra turn | Turns to arrive |
| reach_horizon | 10201 | MOVE_REACH_HORIZON 0 (off) | Scoring rounds left |
| stay_on_objective, horde_presence | 10218-10228 | 5 / 6 / 7; 2 / 1 | Already holding |
| reachability | 10233-10239 | +3; −2 if unreachable in round 1 | Arrives this turn |
| firing_position | 10261-10273 | +3×ratio kept / −2.5 lost / +1.5 gained | **Range only, no line of sight** |
| threat_delta | 10285 | threat × survival multiplier (0.7 / 1 / 1.4) | Moving into more danger |
| overwatch_risk | 10304 | OVERWATCH_EXPOSURE_PENALTY **0 (off)** | Newly inside the 24" Overwatch band |
| hidden_gain | 10314 | WEIGHT_HIDDEN_GAINED **0 (off)** | Would be Hidden at the estimate |
| charge_lane / shooting_lane | 10331 / 10349 | 3 / 2×0.5 | Fits the phase plan |
| primary_awareness / quarter_vp / secondary_* | 10359-10498, 10559 | Mission card VP | Primary and secondary missions |
| plan_earmark | 10568 | 8 / 6 (ADM:1263-1264) | Authored-plan earmark |
| vp_after_commitments | 11007 | WEIGHT_VP_PER_POINT | Re-pricing for diminishing returns |

The threat model (ADM:28794-28889) is pure distance:
- Charge zone is enemy M + 12" + Engagement Range, scaled by depth × enemy value × 2.0.
- Within 12" adds a further ×2.0 term.
- Inside enemy weapon range adds ×0.5.
- Melee-focused units take only 5% of the charge penalty. Characters take ×1.5; fragile units ×1.3.

**Nothing in movement checks line of sight.**

### 3b. Destination generation
`_compute_movement_toward_target` (ADM:14212) calls the impl (ADM:14321-14722). It takes one target point and turns it into one vector from the unit's centroid (14341). Attached characters are excluded from the destinations; the engine moves them with the unit (14331). The stages run in this order:
1. **Terrain path:** `_find_unblocked_move_enhanced` (14358; ADM:14724).
   - If the straight line is clear, `_find_cover_path` (14746; ADM:14817) tries ±15° and ±30° to end "in cover". It uses the legacy `_position_has_cover` (ADM:14858): any terrain polygon crossing a line from any enemy centroid counts. This is always on.
   - If blocked, it tries 20 angles × 4 lengths, scored by forward progress.
2. **Two-leg detour** around solid terrain (14364; `_plan_dogleg` at 14285), which produces waypoints.
3. **Climb penalty:** try other angles, then shorten the move (14403-14474).
4. **Weapon-range clamp** (14476; ADM:13780), only when `max_weapon_range > 0`.
5. **Threat dodge:** `_find_safer_position` (14486; ADM:28892).
   - Tries 11 spots: sideways offsets, 75%/50% moves, and both combined.
   - Scores each as `progress×1.5 − threat (+ hidden bonus)` (28964-28970). Progress is measured to the objective nearest the desired spot, not to the assigned objective (28953).
6. **Placement ladder:**
   - Rigid block move (off; ADM:2176).
   - Per-model `_try_move_with_collision_check` at move fractions [1, .75, .5, .25, .15, .1] (14524).
   - `_try_formation_move` (14581).
   - ±45° and ±90° (14606).
   - Shrunken collision radii 0.85 / 0.70 / 0.50 (14635-14720).

Per-model checks in `_try_move_with_collision_check` (ADM:15405-15711):
- Move cap including terrain penalty.
- Outside Engagement Range of enemies (`_is_position_near_enemy`, ADM:15329).
- No base overlaps, walls or solid-terrain sweeps.
- No crossing MONSTER/VEHICLE models.
- Coherency with already-placed models.
- Spiral search to re-place failed models.
- A final engine-exact coherency check (15699).

## 4. Per-unit overrides and special cases
- **Engaged units** (ADM:11958-12182):
  - Assess survival, then hold on an objective if: late game (12048), winning the OC war (12060), or sole holder (12092).
  - Otherwise BEGIN_FALL_BACK using `_compute_fall_back_destinations` (12185).
    - Its target comes from `_pick_fall_back_target` (12429): −distance, +300×alignment away from the enemy, +200 for an objective we control, +100 for an uncontrolled one.
    - It tries 12 directions × 4 fractions and must end outside Engagement Range.
- **Melee chase gate** (ADM:2947-3101):
  - Distance limits for leaving a hold (2970).
  - Chase cap = max(20", M+14") (3026).
  - Returns `{target_id, advance, reason}`.
- **Screening:**
  - Eligible units (ADM:14911): no CHARACTER; at most 100 pts with OC ≤ 2, or at most 150 pts with no ranged weapons. Only units left unassigned after passes 1-2.5 get here.
  - Deep-strike denial runs only when the enemy has reserves (11440). Positions come from home objectives (offset 0.75R toward the board centre, 14959) and gaps on a grid over our deployment zone (ADM:14928-15026).
  - Denial radius (ADM:28452) is 8" in 11e; screener spacing is 2R (ADM:28484).
  - `screen_protect` stands 60% of the way from the protected friendly unit to the nearest enemy (15085).
  - Corridor blocks stand 55% of the way from the enemy toward the objective (15141), although the constant's comment says the reverse.
- **Scouts** (pre-battle, ADM:5831): target from `_find_best_scout_objective` (5969), straight move with shrinking fractions (6063), keeps more than 9" from enemies, hardcoded (6125).
- **Reserves** (ADM:7728-7946): this is the only existing generator that samples candidate spots and then scores them. Deep strike tries rings at 10/12/15" around each objective every 30°, plus a 4" grid (8137). Spots are scored in 8204. The enemy stand-off is hardcoded as 9" + base radius (8029).
- **Transports:** disembark first (8417; scoring 8498; positions 8626). Transports move last. A loaded transport never holds still just to shoot (7399).
- **Advance:**
  - Plan time: `_should_unit_advance` (12650; ADVANCE_MIN_REACH_CHANCE 0.5) and the long-trip check (12946).
  - Execution plans destinations at M+2 (7205). AIP re-plans once the real roll is known (AIP:1657-1694).

## 5. Shape of a dispatched movement action
```
{"type": "BEGIN_NORMAL_MOVE"|"BEGIN_ADVANCE"|"BEGIN_FALL_BACK", "actor_unit_id": id,
 "_ai_model_destinations": {model_id: [x_px, y_px]},  # alive models only
 "_ai_move_adjustments": [...], "_ai_description": str,
 "_ai_assignment": {...},                    # ADM:6848
 "_ai_model_waypoints": {model_id: [x, y]}}  # two-leg detour, ADM:3438
```
- REMAIN_STATIONARY is `{type, actor_unit_id, _ai_description}`.
- **How AIPlayer executes it:**
  1. Routes the whole dict (AIP:2413), then `_execute_ai_movement` (AIP:2733).
  2. Sends `STAGE_MODEL_MOVE {model_id, dest: [x, y], rotation: 0.0}` for each model, staging the waypoint first when there is one (AIP:2893-2915).
  3. Sends `CONFIRM_UNIT_MOVE` (AIP:2952). **If only some models staged, it confirms the partial move** (AIP:2946).
- **If it fails:**
  1. Recompute at 75/50/25% of the move toward the original heading, with no threat or range checks (AIP:2769).
  2. For a fall back, try Desperate Escape (AIP:2847).
  3. Otherwise REMAIN_STATIONARY and `clear_movement_intent` (AIP:2859).
- **Other movement actions:**
  - Scout: `{BEGIN_SCOUT_MOVE, unit_id, _ai_scout_destinations}` (ADM:5893).
  - Reserves: `{PLACE_REINFORCEMENT, unit_id, model_positions, model_rotations, placement_type?}` (ADM:7919).
  - Disembark: `{CONFIRM_DISEMBARK, actor_unit_id, payload: {positions}}` (ADM:8481).

## 6. Where a new intent plugs in
| Option | Touch points | Pros | Cons |
|---|---|---|---|
| A. Plan scoring term | Candidate loop, next to `hidden_gain` (10306-10314) | Small; shows up in the decision cards automatically | Only biases *which* objective; judged at `estimated_dest` |
| B. Target-shaping stage | Normal-move chain 7491-7592, as a sibling of T7-30 / T7-14 | Unit keeps its objective; local change | Later stages (range clamp, threat dodge, ladder) can undo it; lost when AIP re-plans |
| C. Generator stage | `_find_cover_path` (14746) or `_find_safer_position` (14491) | Applies to every caller (advance, attack, Lone Operative…) | Changes every move; adds per-call cost |
| D. Early-return override | The hold chain 7357-7489 | Simplest for "stay put" intents | The plan still says MOVE, so the announced plan is wrong; `_finalize_movement_decision` still credits the objective as incoming OC (4045) |
| E. New plan action | A pass-3 assignment (11519) + a branch after 7304 + plan-log ids (7035, 7097) + card wording (4107) + support ledger (11509) | The announced plan is truthful; full control of the destination | Most plumbing; competes with the OC passes; pass 2.5 only converts hold/move/advance (11349) |

### Pitfalls
1. **There is no candidate-set evaluator.** The generator moves the whole unit toward one point. To compare several spots you must sample and score them yourself; the reserves code (8137-8246) is the pattern to copy.
2. **Advance endpoints are not preserved.** After the roll, destinations are recomputed toward `_advance_heading_target` (AIP:1696-1788) with no threat data, so only the heading survives.
3. **Hidden and cover are per model.** Check the final `_ai_model_destinations`, because spiral re-placement and partial staging can leave models outside the area.
4. **Use engine predicates on probe dicts** (a dict with `position` and `base_mm`). Don't re-derive the rules, and don't build on the legacy `_position_has_cover`.
   - `TM.is_model_hidden` (TM:1001; already wrapped by ADM:28515). It requires no shooting this turn or last turn (TM:1022). Since the errata, light terrain counts as well as dense (TM:1043), so the "dense" wording in the comment at ADM:10306 is stale.
   - `TM.model_visible_11e` (TM:1209).
   - `TM.unit_has_cover_11e` (TM:1388).
   - `TM.area_at` (TM:847).

### Suggested hook for each intent
- **Move into cover / go Hidden:** B (substitute the target with the nearest qualifying area spot within M), plus A (the existing `hidden_gain` term). Optionally switch `_find_cover_path` to the 11e predicates behind a `FIX_` flag.
- **Stage out of line of sight:** B or C, with probe line-of-sight checks against enemy shooters. Use E for units the plan leaves as support.
- **Move to get a shot:** B, as a line-of-sight-aware sibling of T7-14, plus A to refine `firing_position`.
- **Move into charge range:** extend the charge-intent blend (7491) and the attack branch (7228) so the unit stops at a chosen charge distance.
- **Screen against deep strike:** extend pass 3 (11438-11577) and `_calculate_denial_positions` (14928) rather than building a new system.
## B. Conventions and tooling

# Briefing: conventions and tooling for changing AI movement behaviour

All of this was checked at HEAD `dc9d3b0` (v1.73.3). Short names: **AIDM** = `40k/scripts/AIDecisionMaker.gd` (29,128 lines), **AIP** = `40k/autoloads/AIPlayer.gd`, **GEL** = `40k/autoloads/GameEventLog.gd`. I ran only the static Python checks. I did not run the game, any scenario, exam or headless test.

## 0. Traps to know first

1. **The AI has one strength level now.** Difficulty levels were removed on 2026-11-03 (`b419b64`, v1.72.0). The `--bench-difficulty` and lab `--difficulty` flags are ignored (`40k/autoloads/AIBenchmarkRunner.gd:165-168`), and so is the exam `"difficulty"` key. These docs are out of date:
   - `docs/AI_TUNING.md:80-85` points at `AIDifficultyConfig.gd`, which no longer exists.
   - `docs/ai_dossiers/movement.md` is a good map, but its line numbers come from a 24k-line AIDM and it still describes difficulty noise.
   - The `40k/tests/run_exams.sh` header still says "Hard".
2. **Do not copy these scenario templates.** `b419b64` dropped the difficulty argument from `configure()` (AIP:254) and `request_suggestion()` (AIP:820), but some scenarios still pass it:
   - `configure(types, {...})` with two args: `ai_battle_plan_log_integrity`, `ai_coordinated_movement`, `ork11e_ai_attacker_reactive_dialog_shown`, `pm2a_ai_deploys_from_plan`, `pm2b_formations_from_plan`, `pm3_earmarks_bias_assignment`.
   - `request_suggestion(-1, id)`: `ai_move_shape_telemon_gantry`, `ai_suggestion_fight_multi_target`.
   - None of them is in `_known_failures.txt`. I did not run them; they probably fail. Run them before treating them as a baseline. The first two are the battle-plan integrity gates.
3. **The "terms must sum to the score" checks miss two fields.** Since `03ed34d` (2026-10-28), movement candidates put `gap_inches` and `adv_chance` into `score_breakdown` (AIDM:4148-4151). Neither list of non-score fields skips them:
   - exam mv04's `SKIP` list (`40k/tests/exams/mv04_every_mover_is_recorded.json:34`);
   - `NON_ADDITIVE_KEYS` in `tools/ai_lab/validate_records.py:82-89`.
   - Not run, but mv04 is probably failing. (It was: 54 mismatches. Fixed 2026-11-07, EXAM-DET-1: mv04 now asks `AIReasoningGlossary.is_addend`; `NON_ADDITIVE_KEYS` still lacks both keys.)
4. **The word "intent" is already used twice.**
   - The movement intent ledger: `_record_movement_intent` (AIDM:3977-3989).
   - The player-facing word for plan earmarks. `40k/docs/PLAN_FORMAT.md:433-437` says "Do not introduce a third word".
   - Name new behaviours after their planning pass or parameter instead (e.g. `assign_pass: "cover"`, `FIX_MOVE_COVER`).
5. **AIDM is a lock.** Two sessions must not edit it at the same time (`.llm/ai-overhaul-todo.md:107-112`). `tools/ai_lab/ratchet.json` and `40k/data/version_history.json` will also conflict. Work one agent at a time or rebase.
6. **Two AI tests already fail before any change.** `tests/unit/test_ai_cover_scoring.gd` (21 pass / 3 fail) and `tests/unit/test_ai_threat_range_awareness.gd` (34 / 3), per `40k/tests/ci/direct_known_failures.txt:30,35`. Don't blame these on a new change.
7. **The static checks pass right now** (I ran them):
   - `params_manifest.py`: 288 parameters across 399 call sites.
   - `ratchet_check.py`: PASS, 105 hardcoded numbers that no profile can tune.
   - `check_exams.py`: 13 of 13.

## 1. Parameters, profiles, and the ship-OFF rule

**How a parameter is resolved.** `get_param(name, default)` (AIDM:1553-1574) and `get_param_int` (AIDM:1576) check, in order:
1. profile-rule overrides;
2. the current player's profile;
3. `_config_overrides`, loaded from `res://data/ai_config.json` then `user://ai_config.json` (AIDM:613-640);
4. the `const` default.

Every read is recorded in the decision record's `parameters_used` (AIDM:1543-1551, 2402).

**The required shape for a new knob:**
```gdscript
# <what it does, the evidence, "0 = previous behaviour">
const FIX_MOVE_COVER: float = 0.0
const MOVE_COVER_BONUS: float = 2.0
...
if get_param("FIX_MOVE_COVER", FIX_MOVE_COVER) >= 0.5:
    score += _t_add(score_terms, "cover_gain", get_param("MOVE_COVER_BONUS", MOVE_COVER_BONUS))
```
- The default argument must be a bare const name or literal, and the const must be a plain number. Otherwise `params_manifest.py` cannot see it (`CALL_RE` at :38, `CONST_RE` at :40), and `validate_profile.py` rejects any profile that names it (:137-141).
- Don't write bare numbers into scoring (e.g. `score += 3.0`). `ratchet_check.py` (:93-117, run in CI at `.github/workflows/ai-lab.yml:75`) fails if the count of untunable numbers rises or the number of `_t_add` call sites falls.
- With the flag at 0 the AI must play exactly as before (`tools/ai_lab/protocol_v2.md:73-74`; precedent at AIDM:2205-2210).
- Worked example: `FIX_R1_SUPPORT_ADVANCE` is declared at AIDM:1749-1764 and read at AIDM:11696.

**Profiles.**
- Format: `{"format":"wh40k_ai_profile","version":1,"profile_name":"…","description":"…","parameters":{},"rules":[]}` (see `40k/tests/bench_profiles/*.json`).
- Load with `AIDecisionMaker.load_player_profile(player, dict)` (AIDM:642); clear with `clear_player_profile` (AIDM:649).
- `AIPlayer.configure()` wipes all profiles and plans (AIP:323), so load profiles after calling it.
- In a real game, `player{N}_ai_profile` is applied at `Main.gd:725` through `AIP.load_player_profile` (AIP:335).
- Headless tests flip a flag with `AIDecisionMaker._config_overrides["FIX_X"] = v` and erase it at the end (`tests/unit/test_ai_fix_obj_area_hold.gd:99,154`).
- The rule DSL has two silent traps:
  - `multiply`/`add` on a parameter the profile doesn't declare multiplies or adds to 0.0 (AIDM:1518-1528).
  - An unknown condition type counts as met (AIDM:1448).
  - Check profiles with `python3 tools/ai_lab/validate_profile.py <file>`.

**Where the ship-OFF/neutral rule is written down:**
- `40k/tests/bench_baselines/2026-08-06_mirror_new_vs_old.md:126-161`: the five behavioural weights were set to neutral after measuring E = −2.05 VP/game, 95% CI [−7.2, +3.1].
- AIDM:2614-2629: "SHIPPED DEFAULT: OFF (neutral) … Turn them on by default only when a multi-matchup grid clears them."
- AIDM:2160-2175: `MOVE_REACH_HORIZON`, measured at −4.29 VP.
- AIDM:2205-2210 and 2225-2228: "must stay off until run_paired + gate_candidate say otherwise".
- `FIX_*` notes reading "Off: … Kept for a later test": AIDM:1653-1655, 1673-1675, 1710-1712, 1762-1764, 1775-1776.
- `protocol_v2.md:44-45`: if it doesn't ship, the code stays and the `FIX_` parameter stays 0.
- `.llm/ai-overhaul-todo.md:41-62`: "the evaluator is the judge", behaviour-preserving changes must be byte-identical, and the acceptance thresholds.
- Opt-in profiles that turn things on: `yt_findings_on.json`, `rigid_block_move_on.json`, `reach_horizon_on.json`.

**What this means for each new intent:**
- Ship it at 0 (neutral).
- Add a `40k/tests/bench_profiles/<name>_on.json` that turns it on. CI lints every bench profile (`ai-lab.yml:62`).
- Add its rows to `docs/AI_TUNING.md` (that file asks for it at :460-467).

## 2. Decision records

**Record shape** (AIDM:2386-2421):
```
{decision_type, unit_id, unit_name,
 candidates: [{description, score, pos:[x,y]?, key?, score_breakdown{}}],
 chosen_index, parameters_used, context}
```
Helpers:
- `_t_add(terms, key, delta)` and `_t_mul` (AIDM:2374-2383). They keep the rule that the terms sum to the score.
- `_record_choice(type, uid, name, scored, chosen_key, ctx, k=6)` (AIDM:2341-2362), for a brand-new decision type.

**Movement records are written in one place:** `_finalize_movement_decision` (AIDM:3994; the record itself at 4186-4198).
- It runs once per unit per phase, and only if the unit had more than one objective candidate (AIDM:4084).
- If the unit's assignment isn't one of its objective candidates, the chosen row is built from the assignment:
  - the description depends on the action (AIDM:4107-4113);
  - the breakdown is the assignment's `score_terms` plus `assigned_by` (AIDM:4118-4127).
- The context carries `assigned_by`, `assign_action`, `override_reason` and `earmark`.

**So a new intent should be a new planning pass** inside `_assign_units_to_objectives` (AIDM:9834). Pass 3 (screens, blocks, support; AIDM:11440-11753) is the template. Copy the `screen_denial` assignment at AIDM:11542-11557:
```
assignments[uid] = {"objective_id": "<token>", "objective_pos": Vector2,
  "action": "move"|"advance"|"screen"|"hold", "assign_pass": "<name>",
  "score": s, "score_terms": terms, "reason": "<plain English>", "distance": px}
assigned_unit_ids[uid] = true
```
- When it executes, `_select_movement_action` branches on the action: hold :7191, advance :7203, attack :7228, screen :7275, move :7306.
- It returns `{type, actor_unit_id, _ai_description, _ai_model_destinations, _ai_move_adjustments}` (AIDM:7636-7642).
- If the target isn't an objective, add your token to the plan-line special case at AIDM:7097. Add any new action to `action_counts` at AIDM:7035.

**Rules:**
- Only `_t_add`/`_t_mul` values go into `score_terms`. Put descriptive values in the record's `context`. A descriptive key that does go into `score_breakdown` has to be added in two places: `validate_records.py:82-89` and `AIReasoningGlossary.TERMS` with a format other than `"pts"`. (Exam mv04 reads the glossary since EXAM-DET-1, 2026-11-07.)
- **Fire-count tag.** Print `print("AIDecisionMaker: [FIX_<NAME>] <unit> <what> old=… new=…")` once per evaluation in which the fix changes a value. There are 43 such lines already (e.g. AIDM:3015). The counting rule is in `protocol_v2.md:21-24, 105-106`.
- **AI test cases** fingerprint the chosen key, position or description of the first non-side record (`40k/scripts/AISuggestionTestCases.gd:29-57`). A new side-record type must be added to `SIDE_RECORD_TYPES` there (:52) and to AIDM's `_SIDE_RECORD_TYPES` (:3584).
- **Where records go:**
  - `decide()` attaches `_ai_decision_records`, `_ai_thinking_steps` and `_ai_thinking_context` to the decision (AIDM:3438-3453).
  - `AIPlayer._all_decision_records` stores batches of `{round, phase_name, player, records, thinking_steps, actions}` (AIP:2347-2369), capped at 500 (AIP:4138).
  - From there they reach the game record (`40k/scripts/AIGameRecord.gd`) and the F10 export to `user://ai_decision_log.json` (AIP:4142).

## 3. How the AI's reasoning reaches the player

AIDM never calls GameEventLog (I grepped: zero references). All text goes out through the dictionary that `decide()` returns.

| Channel | Write with | Shown as |
|---|---|---|
| Army plan card | `_add_thinking_step()` (AIDM:2810). The header must start with "Movement plan"; per-unit lines start with two spaces and include `reason` (AIDM:7050-7108). | Its own card (AIP:2323-2339) |
| Per-decision card | Thinking steps plus the record narration "X [movement]: chose … / ✗ rejected" (AIDM:2464-2483) and "↳ why not the top score" (AIDM:4199-4200) | "Thinking: <_ai_description>" block (AIP:2340-2344) |
| Action line | `_ai_description` | "P2: …" for BEGIN_NORMAL_MOVE (AIP:2391-2396); for REMAIN_STATIONARY via GEL:130 |
| How the move was shaped | `_move_shape_notes.append("…")` (AIDM:516; example at 14853) | Suggest (K) card section "How this turn's move was shaped" (`AISuggestionBreakdownPanel.gd:576-581`), plus a "<unit> move: …" step (AIDM:7634-7635) |
| Board highlights | Candidate `pos:[x,y]` plus `context.unit_pos` (AIDM:2428-2452) | Highlighted on hover |
| Suggest (K) score breakdown | `score_breakdown` keys, labelled through `AIReasoningGlossary.TERMS` (:29) | One row per term; keys with no label appear under "Developer details" |

- **GameEventLog API**, if you are working in AIPlayer: `add_ai_entry(player, text)` (:478), `add_ai_thinking_entry` (:484), `add_ai_thinking_block(player, header, lines, context)` (:489).
- **Suggest (K) path:** `Main._on_ai_suggestion_pressed` (`Main.gd:2689`) calls `AIPlayer.request_suggestion(focus_unit_id)` (AIP:820), which calls `suggest_action` (AIDM:3469). That preview does not change the live AI's state.
- **Plan/action consistency gate:** `GEL.movement_plan_integrity()` (:758-813) matches plan lines `MOVE|ADVANCE|HOLD|ATTACK <obj>` against action lines "moves toward | advances toward | holds obj…". So make the intent's decision when the plan is built. Adjustments made while the move executes should be explained as move-shape notes.
- **Logging:** `print()` only reaches stdout. GameEventLog entries also reach `debug_*.log` (GEL:472-476). For other lines use `_debug_log_info()` (AIDM:61). Keep the `[FIX_]` tag in `print()` only, or the fire count will double.

## 4. Test tooling

| Tool | Command (from repo root unless noted) | Cost |
|---|---|---|
| Static gates | `python3 tools/ai_lab/params_manifest.py`; `ratchet_check.py`; `check_exams.py`; `validate_profile.py <profile>`; `fixture_check.py` | Seconds |
| One headless test | `cd 40k && godot --headless --path . -s tests/unit/test_ai_fix_<name>.gd` | About 11 s to boot |
| Gated headless suite | `bash 40k/tests/run_pretrigger_tests.sh` (188 files; split with `AUDIT_SHARD=0/4`; `--all` runs every test) | Tens of minutes in series (CI measures ~11 s per boot, `scenarios.yml:66`) |
| Exams | `bash 40k/tests/run_exams.sh [id…]`, `--aspirational`, `--slow` | About 2 min each, 3 lanes (`EXAM_LANES`); Ork exams time out at 720 s |
| Scenarios | `bash 40k/tests/run_scenario.sh tests/scenarios/sp/<id>.json`; batch with `run_scenarios.sh --changed-only`, `--e11`, or paths | Boot time plus the scenario's own waits |
| AI test cases | `bash 40k/tests/run_ai_test_cases.sh [--compare main]` | One windowed run per case; `--compare` imports a git worktree first (minutes) |

**Headless tests that cover AI movement.**
- In the gated list: `tests/test_ai_movement_coordination.gd`, `test_ai_battle_plan.gd`, `unit/test_ai_plan_earmarks.gd`, `test_oc_per_model_14_02.gd`, `test_iss052_hidden_11e.gd`.
- Run by hand: `unit/test_ai_movement_decisions.gd`, `test_ai_multi_phase_planning.gd`, `test_ai_objective_race.gd`, `test_ai_fall_back_positioning.gd`, `test_ai_survival_assessment.gd`, `test_ai_race_army.gd`, `test_ai_plan_diminishing_returns.gd`, plus one `unit/test_ai_fix_<name>.gd` per fix. Also `tests/test_ai_objective_gap_advance.gd` and `test_ai_objective_assignment_fixes.gd`.
- Pattern for a fix test: cases with the fix ON, a `test_param_zero_restores_old_reads`, and `test_guard_*_unchanged` checks (`test_ai_fix_obj_area_hold.gd:85-97`).
- To gate a new test, add it to the TESTS list (`run_pretrigger_tests.sh:184-373`). It must print "N passed, M failed"; a 0/0 result counts as a failure.

**Exams** (`40k/tests/exams/README.md`).
- Keys the runner reads: `id`, `fixture`, `phase` (7 = Movement), `player`, `seed`, `setup` (GDScript with `tree` bound), `assert[{name, script, equals|expect_min|expect_max}]`, `rationale`, `max_seconds`, `max_actions`, `time_scale` (`AIBenchmarkRunner.gd:205-215, 245`). `covers` and `difficulty` are not read.
- An exam runs one phase (`run_exams.sh:101`).
- There is no profile flag, so load your profile inside `setup`. Setup runs after `configure` and profile loading (`AIBenchmarkRunner.gd:407-424, 453-462`).
- Exams play the fixture's legacy Take-and-Hold mission; `--bench-11e` is not passed.
- There are three lists: gated, aspirational (expected to fail until their owning task lands) and slow. The movement exams are mv01-mv04.
- Assert the decision, not the dice. Don't write an exam that an AI could pass by doing nothing.

**Windowed scenarios** (`40k/tests/scenarios/_schema.md`).
- Some keys and step types work but are not in the schema doc: `"edition": 11` and `"disable_ai": true` (`ScenarioRunner.gd:338, 378, 427`), and the acts `wait_for_script`, `click_if_visible`, `expect_phase_property` (:595, 553, 585).
- **Live AI turn:**
  - `AIPlayer.configure({1: "HUMAN", 2: "AI"})`, then `GameState.set_active_player(2)`, then `PhaseManager.transition_to_phase(7)`.
  - Wait with `wait_for_script` (e.g. `return GameState.get_current_phase() != 7`).
  - Then assert on `GameEventLog.has_ai_entry_containing_any([...])` (GEL:744), `GameEventLog.movement_plan_integrity()`, `AIPlayer._all_decision_records`, or `main.game_log_panel.get_ai_card_count()`.
- **Player path through Suggest (K):**
  - Set `"disable_ai": true` and configure both players as HUMAN, then call `main.refresh_ai_suggestion_button()`.
  - Click `/root/Main/HUD_Right/VBoxContainer/AIControlsRow/AISuggestionButton` (or `button_text: "Suggest (K)"`).
  - Assert on `main._ai_suggestion_panel.full_text`. Focus a unit with `main._on_ai_suggestion_unit_focus("U_X")`.
  - Templates: `ai_objective_race_long_trip.json` and `ai_move_shape_telemon_gantry.json`, but use the one-argument `request_suggestion` (trap 2).
- **Template for a feature shipped OFF:** `ai_hidden_awareness_11e.json`, steps 5 and 22-23. It loads the `_on` profile and asserts the behaviour; clears the profile and asserts the shipped default is unchanged; then reloads and asserts the behaviour returns.
- Add a coverage tile to `40k/tests/coverage.json` and run `python3 40k/tests/check_coverage.py`.

**A/B testing and the benchmark.**
- **Quick and directional only:** `bash 40k/tests/run_ai_benchmark.sh N [FIXTURE] [P1_PROFILE] [P2_PROFILE]`. Sides are not swapped and the mission is legacy. The stall count is a hard gate (`bench_baselines/README.md`).
- **Profile A/B, sides swapped, legacy mission:** `run_paired.py` never sets `bench_11e` (`run_paired.py:67-71`, compare `run_lanes.py:141`).
  `python3 tools/ai_lab/run_paired.py --candidate 40k/tests/bench_profiles/<x>_on.json --fixture mirror_custodes_2000_postdeploy --season bench_data/<x> --min-pairs 6 --max-pairs 24 --aa-arm`
- **11e rules, or comparing code against code** (the `protocol_v2` path):
  1. `python3 tools/ai_lab/ai_versions.py extract SHIP=origin/main`
  2. `python3 tools/ai_lab/ai_versions.py run --base SHIP --cand HEAD --cand-profile <x>_on.json --rules11e --fixture <f> --season bench_data/<x>_<f> --seed-base 95000 --pairs N --lanes $(( $(nproc) - 1 )) --max-seconds 1800`
  3. Repeat for each fixture: `mirror_custodes_2000_postdeploy`, `asym_2000_postdeploy`, `mirror_orks_2000_postdeploy` (use 2400 s for the Ork mirror).
  4. Summarise with `ai_versions.py report --season …`.
- **Proving the OFF default changes nothing:** run the same command without `--cand-profile`; E must be 0.00 ± 0.00 (`tools/ai_lab/README.md:312-315`). Alternatively, play two `run_lanes.py` seasons on the same seeds and compare them with `determinism_check.py A B`.
- **Fix gate** (V2-1, `protocol_v2.md:14-28`): play one pair per fixture (seeds 91000/91100/91200, `--rules11e`) and count your `[FIX_]` lines. Under 1.0 per game means the fix is parked: code kept, parameter left at 0.
- **Ship decision** (V2-2, :30-51): looks at 124, 248 and 372 pairs. Ship only if z ≥ 3.710 / 2.512 / 1.993 at those looks and no fixture's 95% CI lies wholly below 0.
- **Older gate:** `python3 tools/ai_lab/gate_candidate.py --candidate <x>_on.json --season bench_data/gate_<x> --pairs 18` (five gates, `gate_candidate.py:9-26`).
- **Cost:**
  - Custodes mirror: roughly 162-244 s per game; Ork mirror ~956 s (about 5 container-minutes) (`gate_candidate.py:56-58`, README:351-353, `tuning_track_proposal.md:244`).
  - One 124-pair look costs about 12 container-hours, or about 1.5 h spread over 11 containers (`tuning_track_proposal.md:150`).
  - Use at most cores − 1 lanes (README:320-326). Per-seed standard deviation is 9-15 VP.
- **Value of a single decision:** `python3 tools/ai_lab/rollout.py run --case <case.json> --alt '[{"kind":"move","unit":"U_X","objective":"obj_center","mode":"advance"}]' --seeds 24 --horizon 2`. The move override only understands an objective plus a mode, not an arbitrary point (AIDM:7164-7178).
- **The benchmark fixtures can't reach some of these intents:**
  - Screening never fires on the Custodes mirror, because no unit is left spare (`tests/exams/slow/README.md:20-25`).
  - The reserve fixtures are opt-in (`tools/ai_lab/README.md:134-160`).
  - The benchmark armies field no [HEAVY] weapons and no attached leaders (`tuning_track_proposal.md:24`).

**Acceptance thresholds** (`.llm/ai-overhaul-todo.md:53-62`):
- Code change: the targeted exam flips from fail to pass, pooled E ≥ −1 VP at 1 SE, no new scenario failures, and the action mix stays within limits.
- Tuned weights: +4 VP at 2 SE across at least two matchups.

## 5. version_history.json and the CLAUDE.md gates

- Prepend `{"version", "date":"YYYY-MM-DD", "summary", "changes":[…]}` to `40k/data/version_history.json`. The newest entry is 1.73.3 (2026-11-07). Bump patch for fixes, minor for features. `40k/scripts/VersionInfo.gd` reads the file.
- An intent shipped at 0 that changes nothing a player can see is internal and needs no entry. If its narration or Suggest (K) text shows up even with the flag off, it is player-facing.
- Precedent for dormant AI work: the 1.28.6 entry's "Under the hood … switched OFF by default".
- Turning a fix ON needs a version entry, a windowed scenario, a live screenshot, and updates to the unit-test checks that assumed it was off (`protocol_v2.md:114-116`).
- CLAUDE.md requires:
  - a windowed scenario for any change visible in the log or the Suggest (K) card;
  - a live MCP-bridge screenshot shown in the end-of-task summary;
  - no treating pin tests (checks that code exists) as proof a feature works;
  - no claiming results that weren't run;
  - debug logs left in place;
  - the Ask / Issue / Change / Screenshot / Flags summary at the end.
- Pre-commit hook: `git config core.hooksPath .githooks`.

## 6. Existing code for each planned intent

| Intent | What already exists | Notes |
|---|---|---|
| Move into cover | `_find_cover_path` (AIDM:14817; note at :14853), `_check_position_has_terrain_cover` (:25089), `COVER_TERRAIN_*` (:25041) | `test_ai_cover_scoring.gd` already fails 21/3 |
| Stage out of line of sight | `_find_safer_position` (:28892) avoids threat by range only, with no line-of-sight check; `_can_shooter_see_target` (:190) only works on current positions | Corpus finding F005 (`research/youtube/ai_learnings.json`) |
| Move to get a shot | `WEIGHT_FIRING_POSITION_*`, `FIRING_POSITION_BLEND` (:2535), `_should_hold_for_shooting` (:13906), weapon-range clamp (:13845) | Earlier design `tools/ai_lab/r5_designs/ranged_hold_vs_centre` |
| Move into charge range | Charge steering (:7500-7622), `_melee_chase_gate` (:2947), the multi-phase plan (:3773) | Earlier design `r5_designs/attack_move`; saved AI case `40k/tests/ai_cases/s7001_r1_p1_movement_2` is marked "bad" |
| Screen against deep strike | Pass 3 `screen_denial` (:11525-11577), `_calculate_denial_positions` (:14929), `_deep_strike_denial_radius_px` (:28452), `_screen_spacing_px` (:28484) | `FIX_SCREEN_VS_OBJECTIVE` was parked at 0.17 fires per game (`tools/ai_lab/results/2026-10-31/STATUS.md:394`; code in `r4_designs/screen_vs_objective`) |
| Go Hidden | `WEIGHT_HIDDEN_GAINED` and related weights, all at 0 (:2633-2647); `_position_would_be_hidden` (:28515); `_hidden_gain_value` (:28578), used at :10312 and :28970 | `dc9d3b0` made TerrainManager treat light terrain as Hidden too, but the AIDM comment quoting rule 13.09 (:2596-2600) still says dense terrain only |
## C. Engine queries

# Movement-intent briefing: engine queries, AI helpers, hook points

This is a read-only map of HEAD `1c51d7b`. Line numbers are as of now.

**File key:**
- AIDM = `/home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd`
- AIP = `/home/user/warhammer-40k-godot/40k/autoloads/AIPlayer.gd`
- TM = `/home/user/warhammer-40k-godot/40k/autoloads/TerrainManager.gd`
- RE = `/home/user/warhammer-40k-godot/40k/autoloads/RulesEngine.gd`
- MP = `/home/user/warhammer-40k-godot/40k/phases/MovementPhase.gd`
- MM = `/home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd`
- MS = `/home/user/warhammer-40k-godot/40k/autoloads/Measurement.gd`
- ELOS = `/home/user/warhammer-40k-godot/40k/autoloads/EnhancedLineOfSight.gd`
- GS = `/home/user/warhammer-40k-godot/40k/autoloads/GameState.gd`
- GC = `/home/user/warhammer-40k-godot/40k/scripts/rules/GameConstants.gd`
- MT/ = `/home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/`

## 0. Pipeline, hook points, conventions

**Flow**
1. `decide` AIDM:3267 calls `_decide_movement` 6770 (reserves 6818, disembark 6826), which calls `_select_movement_action` 6857.
2. Built once per movement phase:
   - phase plan `_build_phase_plan` 3773 (built at 6881);
   - persistent assignment plan: `_evaluate_all_objectives` 8926 + `_assign_units_to_objectives` 9834. Passes: PASS 1 hold 10606, PASS 2 capture 10774, PASS 2.5 attack 11340, PASS 3 screen/block/support 11438.
3. Rebuilt on every decide: `threat_data` 6931.
4. The executor returns ONE unit per call:
   - hold 7191, advance 7203, attack 7228, screen 7275, normal 7307;
   - inside normal: objective hold 7347, threat hold 7362, hold-to-shoot 7409, Heavy 7422, Lone Operative 7436, Deadly Demise 7470;
   - `move_target` blends: charge steer 7491–7548, half range 7553, firing position 7579.
5. Then `_compute_movement_toward_target` 7595, then `_finalize_movement_decision` 3994 (COORD-2 intent ledger 3977, decision card).
6. AIP executes it: `_execute_ai_movement` 2733 → `_try_stage_and_confirm` 2881 (STAGE_MODEL_MOVE per model, then CONFIRM).

**Decision contract:** `{type, actor_unit_id, _ai_model_destinations:{model_id:[x,y]}, _ai_description, _ai_move_adjustments}`. Waypoints are attached by `_attach_move_waypoints` 14263.

**Hook options for a new intent**
- (a) Plan-time score term in the candidate loop, priced at `estimated_dest` 10249. Existing peers: `firing_position` 10261, `threat_delta` 10285, `overwatch_risk` 10304, `hidden_gain` 10312.
- (b) New PASS-3 assignment with a pseudo `objective_id` (patterns 11547 / 11592 / 11633) plus an executor branch. You must also extend `action_counts` 7035, the plan lines 7097, the objective-claim logic 4044 and the synthetic card 4103.
- (c) Executor `move_target` blend before 7595, with a follow-through re-check (pattern 7603).
- (d) Destination re-scoring inside `_find_safer_position` 28892 (the F001 hook is at 28969).

**Conventions**
- Put every behaviour change behind a const read through `get_param("NAME", NAME)` (1553), default OFF, with a rationale comment block (examples: `FIX_MOVE_TERRAIN_11E` 1886–1906, `WEIGHT_HIDDEN_GAINED` 2633). Add a row to `/home/user/warhammer-40k-godot/docs/AI_TUNING.md` (convention at 464–468).
- Record score terms with `_t_add` 2374 (the terms must sum to the score).
- Player-facing notes go through `_move_shape_notes` (516) and `_add_thinking_step` 2810. Log prints use the `[TAG] … old= new=` style (184).
- Decision records: `_add_decision_record` 2386 / `_record_choice` 2341.
- Any new static cache must be added to `reset_caches` 568 and to `_snapshot_planning_state` / `_restore_planning_state` (3675 / 3722).
- Reach autoloads only through the late-bound getters `_terrain_manager` 83, `_rules_engine` 51, `_measurement` 69, `_mission_manager` 22790 (reason at 57–60).
- Windowed scenario template: `/home/user/warhammer-40k-godot/40k/tests/scenarios/sp/ai_hidden_awareness_11e.json`, which loads the profile `/home/user/warhammer-40k-godot/40k/tests/bench_profiles/yt_findings_on.json`.

## 1. Movement legality, pathing, placement

**Engine rules (what STAGE and CONFIRM reject)**, from MP `_validate_stage_model_move` 796:
- **Move cap:** `get_unit_movement(unit)` MP:203 = M plus Bionik, effect_plus_move, Fungus-Fuel Injection, Calistus, Wolf-Touched, Lightning-fast Strike and Ork modifiers.
  - Normal cap 1214; Advance = M + roll 1565; Fall Back = M 2890; take-to-the-skies −2" (1188–1195).
  - Distance is measured from the ORIGINAL position to the destination, plus `_get_movement_terrain_penalty` 7354: FLY and Kustom Shokk Box pay 0; otherwise 2" per non-traversable difficult-ground piece, plus the ascent climb `_get_vertical_climb_cost` 7390. Tolerance 0.02" (50).
- **13.06 dense terrain:** `_check_dense_terrain_gate` 7162 calls TM `can_move_through_11e(kw, from, to, extra_kw=[], model={})` 1257, which returns `{allowed, blockers}`.
  - INFANTRY/BEASTS/SWARM/MOBILE pass immediately.
  - Everything else is blocked by dense FEATURE pieces taller than 2" (4" for Super-Heavy Walker, TM:1326), using a swept base (TM:1345).
  - Endpoint check: MS `model_overlaps_any_wall(model, kw)` 301 → TM `solid_terrain_endpoint_blocker_11e` 1283.
- **Engagement range is tested at the destination only:** MP `_check_engagement_range_at_position` 7080.
- **Paths:** `_path_crosses_enemy_bases` 7422 (Normal/Advance), `_path_crosses_monster_vehicle_bases` 7477. Model overlap 7556. Board edge 7683 (uses `board.size`).
- **CONFIRM:** coherency 1041 → `AttackSequence.check_unit_coherency` (`/home/user/warhammer-40k-godot/40k/scripts/rules/AttackSequence.gd:229`): 2" neighbour + 9" envelope, 0.05" tolerance. Fall Back must end out of engagement range (1011).
- **Templates you can run on a hypothetical board:** `MoveTypes.get_type(id)` MT/MoveTypes.gd:15, then `eligible()` and `after_moving_conditions()` (coherency + unengaged): NormalMove.gd:22, AdvanceMove.gd:28, FallBackMove.gd:116. Fall-back modes: FallBackMove `select_mode` :52 (Desperate Escape is mandatory when battle-shocked or forced; one hazard roll per model, :74).
- **Engagement predicates:** RE `is_unit_engaged` 18470, `is_attached_unit_engaged` 18497; MS `is_in_engagement_range_shape_aware` 362 (2" per GC:32).

**AI placement helper:** `_compute_movement_toward_target(unit, uid, target_pos, move_in, snapshot, enemies, max_weapon_range=0.0, threat_data=[], objectives=[])` AIDM:14212, implementation at 14321. It translates the whole unit from its centroid, in this order:
1. `_find_unblocked_move_enhanced` 14724 (20 angles × 4 fractions). This also auto-applies `_find_cover_path` 14746.
2. Dogleg `_plan_dogleg` 14285; alternate angles to avoid terrain cost 14403–14474.
3. Weapon-range clamp 13780 (only if `max_weapon_range` > 0); threat dodge `_find_safer_position` 14491 (only if `threat_data` is given).
4. Per-model ladder `_try_move_with_collision_check` 15405, then formation `_try_formation_move` 15714, then ±45/90°, then relaxed radii 0.85 / 0.7 / 0.5 at up to 180°.

Per-model checks it runs: `_is_position_near_enemy` 15329, `_position_collides_with_deployed` 24716, `_dest_really_overlaps` 16090, `_dest_overlaps_wall` 15363, `_path_blocked_by_solid_terrain` 15379, `_path_crosses_monster_vehicle` 15957, `_check_formation_coherency` 24829, `_move_terrain_gate_failure` 162.

Cost: 3.08M obstacle iterations for about two unit moves on a 154-model board (16011); one decision ran for minutes in the worst case (2222). `MOVE_LADDER_FAIL_BUDGET` (2231) caps this but ships off.

Other movement helpers:
- Fall back: `_compute_fall_back_destinations` 12185, `_try_fall_back_positions` 12517, `_resolve_fall_back_position` 12585.
- Advance odds: `_advance_reach_chance` 13247, `_should_unit_advance` 12650, `_adv_engine_predicates` 12640.
- Set-up formations: `_generate_formation_positions` 24548, `_resolve_formation_collisions` 24735 (clamps to a rectangle), `_find_in_zone_formation` 24883, `_find_wall_free_center` 24934.
- Scouts: `_decide_scout` 5831, `_compute_scout_movement` 6063.

**Gotchas**
1. The AI uses the raw `meta.stats.move` (7204, 7308). Neither AIDM nor AIP ever calls `get_unit_movement` or uses take-to-the-skies, so movement bonuses go unused and penalties (e.g. Madcap −2") are over-planned.
2. The per-model cap is 0.95 × M (14518). Advances are planned at M+2" (7205, 7244); they are re-planned at the real roll only when the move pauses (AIP 1657–1722).
3. **The returned destinations are not the target you passed in.**
   - The cover nudge (±15/30°) runs whenever `enemies` is non-empty and the direct line is clear. You cannot switch it off without also losing the engagement-range checks, which read the same `enemies` dict.
   - Relaxed rungs can turn the move up to 180°.
   - Always re-check your intent's goal on the RETURNED destinations (`_destinations_centroid` 14181).
4. With `FIX_MOVE_TERRAIN_11E` (1906) at its default 0, `_move_path_blocked` 15244 uses the legacy `_path_blocked_by_terrain` 15267. That blocks EVERY piece, terrain areas included, for any non-INFANTRY, non-FLY unit and forbids ending inside one. The movement penalty falls back to the charge cost (151).
5. The AI never tests crossing through enemy bases; the engine rejects such paths (MP 759–762).
6. Attached CHARACTER models are left out of the destinations (14331–14333). The engine moves them at CONFIRM (MP `_move_attached_characters` 9253, MS 230). Include them in any per-model cover or Hidden check.
7. Board constants are fixed at 44×60" (44–45) with a 30px edge clamp (48), ignoring `board.size`. A base of 61mm or more clamped at 30px hangs off the board.
8. AIP retries recompute toward the old heading with `max_weapon_range=0, threat_data=[]` (2808–2811, 1719–1722). Any intent-specific end condition is lost on retry.

## 2. Visibility and terrain

**TerrainManager.** Reads the live `terrain_features`, never the board passed in. Nothing is cached.
- `category_of(piece)` 792 (static), `cover_type_of` 819.
- Two height functions: `height_inches_of` 831 (explicit value) and `get_height_inches` 468 (label only, defaults to 6.0). The 13.06 gate and the movement penalty therefore read different heights.
- `area_at(point)` 847 returns the first piece containing the point, area or feature.
- `pieces_model_within(model)` 940 / static `pieces_model_within_of` 927 test a base_mm circle.
- `features_crossing` 857, `build_area_group_map` 876, `visibility_exclusions_for` 951.
- `model_visible_11e(obs, tgt)` 1209, `model_fully_visible_11e` 1215, `unit_fully_visible_11e(obs_model, unit)` 1224:
  - lines run from the observer's CENTRE to the target's centre plus 8 rim points;
  - that is 9 lines against about 44 pieces, and the group map is rebuilt on every call;
  - they return true below edition 11.
- `is_obscured_between(p1, p2)` 976: a single centre line; use it as a cheap pre-filter.
- `is_model_hidden(model, unit)` 1001:
  - unit must be INFANTRY/BEASTS/SWARM;
  - its base must overlap an area group containing any light or dense piece (1030–1045);
  - it is false if `flags.shot_recently` is set, or if `cur_idx − flags.last_shot_idx < 2`, where `cur_idx` comes from the LIVE GameState (1024–1029).
- `hidden_model_visible_to(model, unit, observer)` 1055.
- `detection_range_inches_for` 1069:
  - base is `detection_range_base_inches` 1100 (15", or the datasheet value);
  - −3" when a DENSE line blocks (`_obscured_by_dense_11e` 1121);
  - six codex `load()` calls per call; floor 9".
- `unit_has_cover_11e(unit, attacker_model={})` 1388:
  - Stealth and similar rules grant cover outright;
  - otherwise EVERY alive model must either be INFANTRY/BEASTS/SWARM with its CENTRE inside a piece (`area_at`), or be not fully visible to `attacker_model`;
  - about 1.5–3.5 ms per call (RE 17999).
- `plunging_fire_applies` 1433.

**RulesEngine (the rules' own answers)**
- `_check_line_of_sight(from, to, board, sm, tm)` 6849:
  - checks the memo `_los_memo` 6818 first. Key = id + position + base + rotation + elevation (6834). Capped at 200k entries with no eviction (6820, 6859).
  - On a miss it calls ELOS `check_enhanced_visibility` 27: base sample points × base sample points, density at 339, 11e per-line rule at 496.
  - The memo is cleared only when TM emits `terrain_loaded` (TM:73–78 → `clear_los_memo` 6845). AI snapshots keep terrain under `board.board`, so the epoch guard (6825) never fires.
- `unit_sight_line(actor_id, target_id, board, want_block_point=true, max_pairs=0)` 6641 is THE "can these units see each other" predicate: Hidden gate plus LoS, nearest pairs first. Pass `false` for `want_block_point`.
- `_check_target_visibility(actor, target, weapon_id, board)` 6742: range + Hidden + LoS, with the Indirect Fire bypass. The AI already wraps it in `_can_shooter_see_target` AIDM:190.
- `get_eligible_targets(actor, board, first_match_only=false, only_target_ids={})` 7137: the full targeting rules.
  - It reads `flags.in_engagement` (7148), which is only written at shooting-phase entry (`/home/user/warhammer-40k-godot/40k/phases/ShootingPhase.gd:476–492`). On a hypothetical board, override it the way `_snap_board_unengaged` 1399 does.
  - Before the LoS memo existed, a whole-army sweep measured 3–32 s (6807).
- `explain_target_ineligibility` 7314 returns reason codes (`hidden`, `no_los`, `out_of_range`, …). It scans every weapon × model pair, so it is UI-grade cost.
- `snap_shooting_targets_11e(shooter_id, board, pts_cache)` 1475: legality of 11e Fire Overwatch (within 24", eligible, unengaged, visible).
- `max_ranged_weapon_range_inches` 6693, `unit_within_weapon_reach` 6718: edge-to-edge, include attached characters, no LoS.
- 10e-only, do not use at 11e: `check_benefit_of_cover` 6975, `check_unit_has_cover` 7005; `/home/user/warhammer-40k-godot/40k/autoloads/LineOfSightManager.gd` `check_los` 156 and `calculate_visibility_grid_to_target` 340.

**AI side**
- There is no vision map or LoS grid. The only LoS caches are a local `los_cache` in `_build_focus_fire_plan` (17166, keyed shooter::target::weapon) and RE `_los_memo`.
- Hidden wrappers: `_unit_hidden_eligible` 28497, `_position_would_be_hidden(unit, pos, base_mm)` 28515 (tests a single probe), `_unit_is_currently_hidden` 28530, `_hidden_immunity_fraction` 28548, `_hidden_gain_value` 28578, `_hidden_forfeit_cost` 28592 (used at 16779), `_target_regains_hidden_soon` 28612.
- Cover approximations:
  - `_find_cover_path` 14817 / `_position_has_cover` 14858: "any polygon between the enemy centroid and the point";
  - `_target_has_benefit_of_cover` 25044 / `_check_position_has_terrain_cover` 25089: 10e terrain-type rule with a majority-of-models test, used by the damage estimates at 18038 and 25385.

**Gotchas**
1. There are two visibility predicates. RE/ELOS (base-to-base) decides whether a unit can be shot; TM's observer-centre test decides cover. Use RE for "can be shot" and TM `unit_has_cover_11e` per attacking model for "has cover".
2. Everything is per model. A unit is targetable if ANY model is visible (6761–6797), while cover needs EVERY model. Cover uses the model's centre; Hidden uses base overlap. Test every destination, not the centroid.
3. Hidden timing: shooting stamps `last_shot_idx` (ShootingPhase.gd:6079). So in our movement phase, `is_model_hidden` overstates next-turn Hidden for any unit that will shoot this turn. Live shooting never writes `flags.shot_recently` (it is only erased, in `/home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMDetachmentsA.gd:825` and `:1077`), so the AI's checks of it at 28597 and 28615 never fire.
4. `_hidden_immunity_fraction` compares centroid distance with the BASE detection range and has no LoS test. Its comment at 28547, which claims Gone to Ground is respected, is wrong.
5. Hypothetical boards: use the shallow-copy pattern at AIDM 21686–21706. ELOS falls back to the live TM features when the board has none at top level (ELOS 110, 379). Bulk sampling of candidate positions can fill the 200k memo; after that, every real query misses for the rest of the layout.
6. Stale comments:
   - AIDM 2600 and 10307 say "dense"; the errata (TM 990–995) says light or dense.
   - 2653 says overwatch still uses 10e timing; at 11e it is offered once, at movement_phase_end (MP 1746–1752).
   - 28655 says no LoS helper can answer for a destination; the RE predicates work on a hypothetical board.

## 3. Threat and damage

**Threat maps**
- `_calculate_enemy_threat_data(enemies)` 28695 returns per enemy: `unit_id`, `centroid`, `charge_threat_px` = (M + 12 + ER)", `shoot_threat_px` = max weapon range from meta, `has_melee`, `has_ranged`, `unit_value`.
- `_estimate_enemy_threat_level` 28734.
- `_evaluate_position_threat(pos, td, own)` 28794: linear depth on centroid distance, THREAT_* weights 2586–2593, ×1.5 for characters (28809), fragile multiplier (28873).
- `_is_position_in_charge_threat` 28882, `_find_safer_position` 28892.
- Gotchas: no terrain, LoS or Hidden. Also, an 11e charge must roll at least the edge distance (`_charge_roll_needed` 18840; ChargeMove11e.gd:89–107), so adding ER overstates charge reach by 2".

**Damage estimates**
- `_estimate_weapon_damage(w, tgt, snapshot, shooter)` 17984: closest-model range, 10e cover, no LoS.
- `_score_shooting_target` 25336, `_estimate_melee_damage` 19576.
- `_estimate_unit_ranged_strength` 25866: generic target (T4, 50% saves).
- `_estimate_unit_shooting_value` 23954, `_estimate_incoming_melee_damage` 12350, `_assess_engaged_unit_survival` 12373, probability helpers 24992–24998.

**Overwatch**
- `_overwatch_exposure_penalty(unit, from, to, enemies)` 28660: 24" band, no LoS, weight at 2662 is 0 (off).
- `_unit_ranged_shot_volume` 28637, `_snap_expected_damage_11e` 27185.
- Charge-side `_estimate_overwatch_risk` 19422 uses 10e logic (`FIX_CHARGE_OW_11E` 1936).

**Engine-exact estimate:** RE `preview_attack(shooter, target, weapon_id, board, opts)` 17805. It applies 11e cover per firing model (sampling at most 4, constant at 17800) but does not gate on range or LoS. The `opts.cover_cache` key (target|bearer) ignores positions, so never share it across candidate destinations.

## 4. Objectives, zones, reserves

**Engine (MM)**
- `model_in_objective_range` 529: on a terrain-hosted objective, any overlap with the hosting AREA; in the open, base edge within 3.787" of the marker centre (520).
- `model_within_inches_of_objective` 545, `model_gap_to_objective_range_px` 569, `model_distance_to_objective_px` 588, `model_oc` 659.
- `get_level_of_control(objective, units)` 863: side-effect free and accepts hypothetical units.
- `is_objective_secured` 147, `is_objective_contested` 626.
- Never call `_check_objective_control` 878: it mutates contested and sticky state.

**AI**
- `_ai_model_in_objective_range` 13145 looks the objective up in the LIVE GameState via `_objective_at_pos` 13124.
- `_unit_has_model_in_control_range` 13269, `_unit_gap_to_objective_px` 13163, `_objective_approach_target` 13193, `_obj_gap_px` 13322, `_unit_on_objective` 13352.
- `_unit_oc_at_position` 13054, `_get_oc_at_position` 13030, `_unit_alive_oc` 13432, `_reachable_contest_oc` 13449, `_capture_arrival` 13091.
- `_initial_objective_oc_needs` 9405, `_secured_aware_lock` 8899, `_objective_pos_by_id` 414, `_nearest_objective_pos` 13985.
- Each `_evaluate_all_objectives` row (9355–9376) carries `state`, `friendly_oc`, `enemy_oc`, `projected_enemy_oc`, `is_home`, `contest_oc`.
- `OBJECTIVE_CONTROL_RANGE_PX` = 151.5 (47).

**Zones**
- `_get_deployment_zone_bounds` 24510 returns the bounding RECTANGLE, not the polygon. Use `_get_deployment_zone_polygon_pixels` 24856, or GS `get_deployment_zone_poly_px` 365 and `ingress_opponent_dz_ban_applies` 385.
- Quarters: `_get_table_quarter` 24250, `_get_covered_quarters` 24260.

**Engine reserve-arrival rules:** MP `_validate_place_reinforcement` 4209 (round ≥ 2 at 4248, overlap check 4277) hands 11e arrivals to MT/IngressMove.gd `validate_setup(unit_id, board, positions, ctx)` :44:
- wholly within 6" of a battlefield edge, unless Deep Strike;
- more than 8" edge-to-edge from enemy models (:53);
- not in the opponent's deployment zone before round 3, unless Deep Strike;
- Arae-Shrike 12" denial.

GC holds the 8" distances (lines 49 and 60).

**AI reserves**
- `_compute_reinforcement_positions` 8019: its candidate filter hardcodes 9" + base radius + 25px (8029), which is the 10e value.
- Strategic Reserves candidates 8073: 3" off each edge; the opponent-zone ban is checked only when round == 2, and only at the centre point.
- Deep Strike candidates 8137, `_is_candidate_position_valid` 8174.
- `_is_valid_reinforcement_position` 8331: uses 8" from GC, but tests the Strategic Reserves centre within 6" rather than "wholly within".
- `_score_and_sort_reinforcement_candidates` 8204, `_get_enemy_model_positions_from_snapshot` 8249, omni-scrambler positions 8277.

**Screening**
- `_get_enemy_reserves` 14884.
- `_deep_strike_denial_radius_px` 28452: 8" from GC, tightened by any shorter drop parsed from enemy abilities. `_screen_spacing_px` 28484.
- `_calculate_denial_positions` 14929: picks centroid points only and never checks where an enemy drop would actually be legal.
- `_compute_screen_position` 15028, `_calculate_corridor_blocking_positions` 15092, `_screen_max_model_spacing_px` 28380, `_screen_widest_passable_gap_inches` 28388, `_is_screening_candidate` 14911.

## 5. Reuse index per intent (do not duplicate these)

- **Move into cover:** TM `unit_has_cover_11e`, `area_at`, `category_of`. Replace `_find_cover_path` / `_position_has_cover` rather than stacking on top of them. The deployment equivalents `_score_terrain_for_role` 5594 / `_find_terrain_aware_position` 5656 use 10e labels. Roles: `_classify_deployment_role` 5353.
- **Stage out of LoS:** RE `unit_sight_line(enemy, me, hypo, false)` or `get_eligible_targets(enemy, hypo, true, {me: true})`. Use TM `is_obscured_between` as a pre-filter, and `snap_shooting_targets_11e` for end-of-phase overwatch exposure.
- **Move to get a shot:** RE `get_eligible_targets(me, hypo, true)`, `unit_within_weapon_reach`, `get_eligible_shooter_models` 11878, `count_models_in_half_range` 11817. Existing AI helpers:
  - `_get_enemies_in_weapon_range` 13760 (centroid distance, no LoS);
  - `_find_firing_position_toward_objective` 13848, `_clamp_move_for_weapon_range` 13780, `_should_hold_for_shooting` 13906;
  - `_get_unit_half_range_data` 13669, `_find_best_half_range_position` 13702;
  - `_get_max_weapon_range` 13517 reads `meta.weapons` only, so it misses attached-character guns and the range bonuses that RE 6693 includes.
- **Move into charge range:** RE `eligible_to_charge` 12050 (Advance and Fall Back gating), `charge_targets_within_12` 12118, `_charge_min_distance_to_target_rules` 12359 (measures from the whole Attached unit). AI helpers:
  - `_charge_roll_needed` 18840, `_charge_success_probability` 18928, `_charge_odds_with_reroll` 18968, `_charge_has_free_reroll` 18955;
  - `_get_closest_model_distance_inches` 19697 / `_get_closest_model_pair_info` 19703;
  - `_get_nearest_enemy_for_charge` 3114, `_find_flank_around_terrain` 3153, `_estimate_charge_terrain_penalty` 98, `_projected_move_end` 14174;
  - `_get_charge_intent` 3961 plus the blend at 7491–7548 (`CHARGE_BLEND_REACH_INCHES` 2540).
- **Screen against deep strike:** use the §4 helpers. To test where the enemy could actually drop, run `IngressMove.validate_setup` on a board that includes your screening units.
- **Go Hidden:** TM `is_model_hidden` / `hidden_model_visible_to` / `detection_range_inches_for`, and AI `_position_would_be_hidden` applied to every model's destination. Pair it with the shooting-side forfeit cost (16779) so the unit doesn't shoot its Hidden status away.