# Movement Phase Audit — Warhammer 40k 10th Edition

## Scope
This audit compares the current movement phase implementation (primarily `phases/MovementPhase.gd` and `scripts/MovementController.gd`) against the Warhammer 40,000 10th Edition core rules, with a focus on online multiplayer correctness.

**Last updated:** 2026-02-13
**Audit revision:** 3

---

## 1. Rules Compliance Summary

| Rule | Status | Notes |
|------|--------|-------|
| Normal Move (up to M") | **Implemented** | Per-model distance tracking works correctly |
| Advance Move (M + D6") | **Implemented** | D6 rolled with deterministic RNG for multiplayer |
| Fall Back Move (M") | **Implemented** | ER checks on final position enforced |
| Remain Stationary | **Implemented** | Sets `remained_stationary` flag for Heavy weapon bonus |
| Engagement Range (1") | **Implemented** | Shape-aware edge-to-edge checks via Measurement |
| Cannot enter ER on Normal/Advance | **Implemented** | Validated in `_check_engagement_range_at_position()` |
| Fall Back must end outside ER | **Implemented** | Checked per-model in `_validate_confirm_unit_move()` |
| Engaged units can only Fall Back or Remain Stationary | **Implemented** | Enforced in `_validate_begin_normal_move()` and `get_available_actions()` |
| Desperate Escape (D6, 1-2 = model lost) | **Implemented** | `_process_desperate_escape()` handles both normal and Battle-shocked cases |
| FLY units skip Desperate Escape | **Implemented** | FLY keyword check in `_process_desperate_escape()` returns early |
| TITANIC units skip Desperate Escape | **Implemented** | TITANIC keyword check in `_process_desperate_escape()` returns early |
| Advanced units cannot shoot (except Assault) | **Implemented** | `ShootingPhase.gd:1026-1031` checks `advanced` flag |
| Fell Back units cannot shoot or charge | **Implemented** | Sets `cannot_shoot` and `cannot_charge` flags |
| Advanced units cannot charge | **Implemented** | Sets `cannot_charge` flag |
| Heavy weapon +1 to hit when stationary | **Implemented** | `remained_stationary` flag consumed by shooting phase |
| Transport Disembark (within 3") | **Implemented** | Full disembark flow with edge-to-edge distance validation |
| Disembark cannot be in ER of enemy | **Implemented** | `_validate_confirm_disembark()` checks ER |
| Transport moved → disembarked unit cannot move | **Implemented** | `cannot_move` flag enforced |
| Embark after movement (within 3") | **Implemented** | `_check_embark_opportunity()` with prompt dialog |
| Attached characters move with bodyguard | **Implemented** | `_move_attached_characters()` applies delta |
| Terrain collision (impassable) | **Implemented** | `_position_intersects_terrain()` via `_check_terrain_collision()` — consistent across all validation paths |
| Model overlap prevention | **Implemented** | `_position_overlaps_other_models()` with staged position awareness |
| INFANTRY move through ruins | **Implemented** | `TerrainManager.can_unit_move_through_terrain()` |
| Cannot embark and disembark same phase | **Implemented** | `disembarked_this_phase` flag checked in `_validate_embark_unit()` |
| Unit cannot be selected to move more than once | **Implemented** | `flags.moved` checked in all `_validate_begin_*` methods |

---

## 2. Missing Rules (Gaps)

### 2.1 CRITICAL — Unit Coherency Enforcement

**Rule:** After a unit moves, each model must be within 2" of at least one other model in the same unit. For units with 7+ models, each model must be within 2" of at least **two** other models. A unit must finish any type of move in unit coherency. If this is impossible, then that move cannot be made.

**Current state:** Coherency checking exists only as a warning in group movement validation (`_check_group_unit_coherency()` in `MovementPhase.gd:1520`), but it is **never enforced** during `_validate_confirm_unit_move()`. A player can confirm a move that breaks coherency with no penalty. The FightPhase (`FightPhase.gd:1322`) has a proper `_validate_unit_coherency()` function that blocks moves breaking coherency — the movement phase should do the same.

**Impact:** High. This is a fundamental rule that affects game balance. Without enforcement, units can spread models across the entire board.

**Recommendation:** Port the coherency validation from `FightPhase._validate_unit_coherency()` into `MovementPhase._validate_confirm_unit_move()`. If coherency is broken, reject the move.

### 2.2 CRITICAL — Reinforcements Step

**Rule:** The Movement Phase has two steps: (1) Move Units, and (2) Reinforcements. After all units have moved, reserves/reinforcements can be placed on the battlefield:
- **Deep Strike:** Units with the Deep Strike ability can be set up in reserves during deployment and deployed during the Reinforcements step more than 9" horizontally from all enemy models.
- **Strategic Reserves:** Up to 25% of the army can be placed in strategic reserves. They can arrive from the second battle round onwards — from the second round they must be placed within 6" of a board edge and outside the enemy deployment zone; from the third round onwards they can be placed in the enemy deployment zone. Always more than 9" from enemy models.
- **Any reserves not placed by end of game count as destroyed.**

**Current state:** There is **no Reinforcements step** implemented. No reserves system, no Deep Strike, no Strategic Reserves. The archived test file `test_deployment_phase.gd:162-166` has a stub `test_strategic_reserves()` that creates a `PLACE_IN_RESERVES` action, but the action type is not implemented.

**Impact:** High. Many armies rely on reserves and Deep Strike as core mechanics (e.g., Terminators, Drop Pods, jump pack units).

**Recommendation:** Add a Reinforcements sub-phase that activates after all movement is complete but before the phase ends. Requires:
1. A reserves tracking system in GameState (units with status `IN_RESERVES`)
2. A `PLACE_REINFORCEMENT` action type with 9" distance validation
3. Strategic Reserves placement rules tied to battle round
4. "Destroyed if not deployed" enforcement at game end

### 2.3 ~~HIGH — FLY Keyword (Desperate Escape)~~ PARTIALLY FIXED

**Rule:** Units with the FLY keyword:
- Can move over enemy models during a Normal Move or Advance (but must still end outside ER)
- When Falling Back, FLY units can move over enemy models **without taking Desperate Escape tests**
- Ignore vertical distance and terrain height

**Current state:** `_process_desperate_escape()` now checks `unit.meta.keywords` for "FLY" and returns early with no changes/dice if found. The `TerrainManager.gd:181-182` checks for FLY keyword for wall traversal (`if "FLY" in unit_keywords`).

**Remaining work (not yet implemented):**
- Normal Move path validation: FLY units should be exempt from path-through-enemy checks when added (see 2.5)
- FLY units should ignore terrain elevation during movement
- Engagement range path checks for FLY units

**Resolution:** Added FLY keyword check at the top of `_process_desperate_escape()` in `MovementPhase.gd:1055-1063`. If the unit has "FLY" in its keywords, the function logs the skip and returns immediately with no casualties.

**Commit:** `e4364af` — "Skip Desperate Escape tests for FLY and TITANIC units"

### 2.4 ~~HIGH — TITANIC Keyword~~ FIXED

**Rule:** TITANIC models do not take Desperate Escape tests when Falling Back (same as FLY).

**Resolution:** Added TITANIC check alongside FLY in `_process_desperate_escape()` at `MovementPhase.gd:1055-1063`. Both keywords are checked with:
```gdscript
var keywords = unit.get("meta", {}).get("keywords", [])
if "FLY" in keywords or "TITANIC" in keywords:
    return {"changes": [], "dice": []}
```

**Commit:** `e4364af` — "Skip Desperate Escape tests for FLY and TITANIC units"

### 2.5 HIGH — Moving Through Friendly Models / Path Through Enemy Models

**Rule:** A model can move **through** friendly models during its move but cannot end on top of another model. A model **cannot** move through enemy models during a Normal Move or Advance (only FLY or Fall Back allows this). No part of the model's base can be moved across the bases of other models.

**Current state:** The implementation checks for model overlap at the **final position** (`_position_overlaps_other_models()` at `MovementPhase.gd:1185`), which is correct for end-position validation. However:
- **Path validation through enemies is missing for Normal/Advance:** A model can currently be dragged through an enemy model's base and placed on the other side without penalty, as long as it ends outside ER.
- **Path validation through friendlies is incorrectly strict:** The `_path_crosses_enemy()` function at `MovementPhase.gd:1125` checks both enemy and friendly models along the path but is only called during Fall Back. Normal moves have no path checking at all.
- The `_path_crosses_enemy()` function uses engagement range checks along the path (line 1171), which would incorrectly block movement through friendly models too.

**Impact:** Medium. Allows illegal shortcuts through enemy formations.

**Recommendation:**
1. Add path validation for Normal and Advance moves to prevent crossing enemy bases
2. Ensure path validation explicitly **allows** crossing friendly bases
3. Add FLY exception for path-through-enemy checks
4. Separate "crosses enemy" from "crosses engagement range" — moving close to enemies is fine, moving through their bases is not

### 2.6 ~~HIGH — Board Edge Enforcement~~ FIXED

**Rule:** No part of a model (including its base) can cross the edge of the battlefield during any move.

**Current state:** Board edge enforcement is now fully implemented across all movement validation paths.

**Resolution:** Added `_position_outside_board_bounds()` helper in `MovementPhase.gd` that checks the model's base shape bounds against the board dimensions from `game_state_snapshot.board.size`. Board edge checks are enforced in:
- `_validate_stage_model_move()` — blocks individual model staging beyond board edges
- `_validate_set_model_dest()` — blocks model destination placement beyond board edges
- `_validate_confirm_disembark()` — blocks disembark positions beyond board edges

Visual feedback added in `MovementController.gd`:
- `_is_position_outside_board()` helper uses `SettingsService` board dimensions for real-time drag validation
- Individual model drag (`_update_model_drag()`) shows "Cannot move beyond the board edge" error and turns ghost red
- Group drag (`_update_group_drag()`) checks all models in the group and shows the same error
- Error label is cleared when the position becomes valid again

**Commit:** Board edge enforcement for movement phase

### 2.7 MEDIUM — Difficult Terrain / Movement Penalties

**Rule:** Certain terrain features (like dense cover, craters, etc.) may apply movement penalties. While the basic 10e rules don't have universal "difficult terrain," terrain traits can affect movement.

**Current state:** Terrain is either passable or impassable — no partial movement costs.

**Impact:** Medium. Affects tactical positioning around terrain.

**Recommendation:** Consider adding terrain traits that reduce movement or require extra distance when crossing.

### 2.8 MEDIUM — Scout Moves

**Rule:** Some units have the Scouts X" ability, allowing them to make a pre-game move of X" after deployment but before the first turn. Dedicated Transport units with Scout units embarked also inherit this ability. If both players have scout units, the player going first moves their units first.

**Current state:** No Scout move implementation found anywhere in the codebase.

**Impact:** Medium. Affects specific army builds that rely on early positioning (e.g., Space Marine Scout squads, Phobos units).

**Recommendation:** Add a pre-game Scout phase between Deployment and the first Command phase. Requires:
1. Checking unit datasheets for the "Scouts X" ability
2. A dedicated Scout movement step with appropriate distance caps
3. Player ordering (first player moves first)

### 2.9 MEDIUM — Infiltrators Deployment Ability

**Rule:** If every model in a unit has the Infiltrators ability, when you set it up during deployment, it can be set up anywhere on the battlefield that is more than 9" horizontally away from the enemy deployment zone and all enemy models.

**Current state:** Not implemented.

**Impact:** Medium. Affects army building options for certain factions.

**Recommendation:** Add Infiltrators support to the DeploymentPhase, allowing placement outside the normal deployment zone with appropriate distance validation.

### 2.10 LOW — Overwatch During Movement

**Rule:** The Overwatch stratagem can be used during the opponent's Movement phase when an enemy unit starts or ends a Normal, Advance, or Fall Back move within 24" of an eligible unit.

**Current state:** No Overwatch trigger during movement. Archived test stubs exist (`test_shooting_phase.gd:312-324`, `test_charge_phase.gd:141-151`) but the functionality is not implemented.

**Impact:** Low for initial release, but this is a commonly used stratagem.

**Recommendation:** Add event hooks in movement confirmation for opponent reactions.

### 2.11 LOW — Rapid Ingress Stratagem

**Rule:** Used at the end of your opponent's Movement phase to bring in a Reserves unit.

**Current state:** Not implemented (no reserves system).

**Impact:** Low until reserves are implemented.

### 2.12 LOW — Disembarked Units Do Not Count As Remaining Stationary

**Rule:** Units that disembark from a transport do not count as having Remained Stationary, even if they don't move after disembarking.

**Current state:** The `_initialize_movement_for_disembarked_unit()` function at `MovementPhase.gd:1914` sets the mode to "NORMAL" and does not set the `remained_stationary` flag, which is correct. However, if a player selects "Remain Stationary" for a disembarked unit instead of moving it, the `_process_remain_stationary()` function at line 880 **will** set `remained_stationary = true`, which could grant Heavy weapon bonuses the unit shouldn't receive.

**Impact:** Low. Edge case that could affect Heavy weapon accuracy.

**Recommendation:** Track the `disembarked_this_phase` flag on the unit and check it in `_process_remain_stationary()` to prevent setting `remained_stationary` for units that disembarked.

---

## 3. Multiplayer-Specific Issues

### 3.1 CRITICAL — `active_moves` Dictionary Is Not Synced

**Location:** `MovementPhase.gd:20`

The `active_moves` dictionary is a local phase variable that tracks all in-progress movement state (staged moves, original positions, model distances, etc.). This data is **not synchronized** via GameState.

**Problem:** In optimistic execution mode, both host and client independently maintain their own `active_moves`. For deterministic actions like `BEGIN_NORMAL_MOVE` and `STAGE_MODEL_MOVE`, this works because both sides process identically. However, if **any** desync occurs (e.g., a dropped message, or a race condition), the `active_moves` dictionaries will diverge silently.

**Risk areas:**
- `_validate_end_movement()` checks `active_moves` to determine if there are uncommitted moves. If host and client disagree, one side might allow END_MOVEMENT while the other blocks it.
- `_validate_confirm_unit_move()` reads from `active_moves` to check Fall Back validity — desync here could allow illegal moves.

**Recommendation:** Either:
1. Mirror critical `active_moves` state into GameState for validation (higher safety), or
2. Add periodic state checksums between host/client to detect and reconcile desync (lower overhead).

### 3.2 ~~HIGH — Double Advance Dice Roll~~ FIXED

**Location:** `MovementController.gd` and `MovementPhase.gd:495-511`

**Resolution:** Removed the duplicate dice roll from `MovementController`. The D6 is now rolled only in `MovementPhase._process_begin_advance()` (single source of truth). The controller reads the advance roll result from the phase's `active_moves` data in the `_on_unit_move_begun()` callback and updates the UI from there. The `_roll_advance_dice()` function and its callers (`_on_advance_pressed` deferred call, `_on_confirm_mode_pressed` ADVANCE branch) were removed.

**Commit:** `41a3891` — "Fix double advance dice roll causing multiplayer desync"

### 3.3 HIGH — BEGIN_ADVANCE Excluded from Deterministic Actions

**Location:** `NetworkManager.gd:42-59`

The `DETERMINISTIC_ACTIONS` list includes `BEGIN_NORMAL_MOVE`, `BEGIN_FALL_BACK`, `STAGE_MODEL_MOVE`, `CONFIRM_UNIT_MOVE`, `RESET_UNIT_MOVE`, and `REMAIN_STATIONARY` for optimistic execution, but **`BEGIN_ADVANCE` is excluded** because it involves a D6 roll.

**Problem:** While excluding the advance roll from optimistic execution is correct (it's non-deterministic), this means Advance moves have higher latency than Normal moves in multiplayer. The host must roll the dice, send the result, and the client must wait for it before the player can start moving models. This creates a noticeable delay in online play.

**Risk:** If the host-rolled advance result differs from what the client displayed (due to any UI prediction), the move cap shown to the player may be incorrect.

**Recommendation:**
1. Use the `rng_seed` approach already implemented: the host sends the seed with the action, and both sides roll deterministically from that seed
2. This would allow `BEGIN_ADVANCE` to be treated as deterministic, reducing latency
3. The `MovementPhase._process_begin_advance()` already supports seeded RNG (lines 505-513)

### 3.4 MEDIUM — `game_state_snapshot` Manually Refreshed After Disembark

**Location:** `MovementPhase.gd:1984`

```gdscript
game_state_snapshot = GameState.state.duplicate(true)
```

This bypasses the normal snapshot management (handled by `PhaseManager`/`BasePhase`). In multiplayer, directly reading `GameState.state` could return a state that hasn't been fully synchronized yet.

**Recommendation:** Use the proper snapshot refresh mechanism through `PhaseManager` or add synchronization barriers.

### 3.5 MEDIUM — Opponent Has No Movement Visualization

**Location:** `MovementController.gd` (entire file)

**Problem:** The MovementController only builds UI for the active player. The non-active player (opponent) receives `model_drop_committed` signals through `NetworkManager._emit_client_visual_updates()` (line 829-838), which updates model positions, but:
- No path visualization is shown to the opponent
- No distance/movement cap information is displayed
- No ghost previews are shown
- Models appear to "teleport" to their final positions with no animation

**Impact:** The opponent cannot follow what's happening during their opponent's movement phase. This makes the game feel disconnected and reduces strategic understanding.

**Recommendation:** See Section 5 — Visual Improvements (5.5 Opponent's Movement Replay).

### 3.6 MEDIUM — Group Drag Timing Issues

**Location:** `MovementController.gd:2747-2768`

Group movement sends individual `STAGE_MODEL_MOVE` actions with a 0.01s delay between them, then waits 0.1s before verification. In high-latency multiplayer conditions:
- Some moves may not be processed before verification starts
- False negatives in verification can lead to unnecessary retries
- Retry logic (`_verify_staged_moves()`) may cause duplicate moves

**Recommendation:** Add a proper async completion mechanism instead of relying on fixed delays. Use a counter or signal to know when all staged moves have been processed before running verification.

### 3.7 MEDIUM — Embark Prompt is UI-Only (Partially Fixed)

**Location:** `MovementPhase.gd:1658-1695`

The embark flow has been partially fixed — `_show_embark_prompt()` now routes through the action system via `NetworkIntegration.route_action()` (line 1684). However, the `ConfirmationDialog` is still only shown to the active player. In multiplayer, the opponent has no indication that an embark occurred until the board state updates.

**Recommendation:** Emit a notification signal so the opponent's UI can display an embark indicator or log entry.

---

## 4. Quality of Life Improvements

### 4.1 Movement Range Indicator

**Current:** Players must manually judge how far each model can move by watching the distance counter in the right HUD panel.

**Suggestion:** When a unit is selected for movement, draw a translucent circle (or shape for non-circular bases) showing the maximum movement range around each model. Use green for Normal Move range and blue for Advance range. This is standard in most digital tabletop implementations.

### 4.2 Engagement Range Visualization

**Current:** Players discover they're in engagement range only when they try to place a model and get an error.

**Suggestion:** When a unit is within or near engagement range of enemy models, display a red halo or ring around the enemy models showing the 1" ER zone. This helps players understand their movement constraints before dragging.

### 4.3 Unit Coherency Visualization

**Current:** No visual feedback for coherency. The FightPhase dialogs mention "Green dots = unit coherency maintained" (`ConsolidateDialog.gd:67`, `PileInDialog.gd:65`), but no equivalent exists for the movement phase.

**Suggestion:** After each model is placed, draw thin lines between coherent models (green) and highlight models at risk of breaking coherency (yellow/red). This helps players maintain legal formations. For 7+ model units, show the requirement for 2 connections.

### 4.4 Movement History / Breadcrumbs

**Current:** After confirming a model's position, the original position is cleared. Players can't see where models started.

**Suggestion:** Show ghost outlines or small dots at each model's starting position during the movement phase, connected by a dashed line to the current position. This helps both players track what moved where, especially important in multiplayer where the opponent needs to see movement.

### 4.5 Auto-Select Next Unmoved Unit

**Current:** After confirming a unit's move, the player must manually select the next unit from the list.

**Suggestion:** After `_on_unit_move_confirmed()`, automatically select and highlight the next unmoved unit in the list. This speeds up the movement phase significantly.

### 4.6 "Select All" for Single-Model Units

**Current:** Single-model units (characters, vehicles) still require the same click-drag-confirm flow as multi-model units.

**Suggestion:** For single-model units, skip the individual model selection and start drag immediately when the unit is selected, reducing clicks.

### 4.7 Undo Should Work Across Units

**Current:** Undo only works within the currently active unit's staged moves.

**Suggestion:** Allow undoing the last confirmed unit move (before END_MOVEMENT is pressed) to revert it back to uncommitted state. This is especially important in multiplayer where a player might realize they moved units in the wrong order.

### 4.8 Movement Summary Before End Phase

**Current:** When pressing "End Movement Phase," there's a simple validation check but no summary.

**Suggestion:** Before ending the phase, show a summary dialog listing:
- Units that moved (with type: Normal/Advance/Fall Back)
- Units that remained stationary
- Units that haven't acted (with a warning)
- Advance roll results

This prevents accidental phase ending and provides a review step.

### 4.9 Better Advance Roll Display

**Current:** The advance roll is shown in a small label that can be missed.

**Suggestion:** When an Advance roll is made, show a brief animated dice roll overlay in the center of the screen (like a dice rolling animation). This provides clear feedback for both players in multiplayer and adds visual flair.

### 4.10 Keyboard Shortcuts for Common Actions

**Current:** Q/E for rotation, Ctrl+A for select all, Ctrl+click for multi-select, Escape to clear.

**Suggestion:** Add more shortcuts:
- `Space` — Confirm current unit's move
- `R` — Reset current unit's move
- `Z` / `Ctrl+Z` — Undo last model move
- `Tab` — Cycle to next unmoved unit
- `N` — Normal Move
- `A` (when no unit selected) — Advance
- `F` — Fall Back
- `S` — Remain Stationary

### 4.11 Ctrl+Click and Grid Snap Conflict

**Current:** Ctrl is used for both multi-selection (`MovementController.gd:1055`) and grid snapping (`MovementController.gd:1704`). These cannot be used simultaneously.

**Suggestion:** Use a different modifier for grid snapping (e.g., `Alt` or `G` toggle) to avoid conflicting with multi-selection.

### 4.12 Stale Error Message Display

**Current:** The illegal-reason label in the movement controller shows errors in red but is never cleared when a subsequent valid action occurs (`MovementController.gd:2083-2085`).

**Suggestion:** Clear the error label when the player starts a new drag, selects a different model, or performs a valid action.

---

## 5. Visual Improvements

### 5.1 Path Visualization Enhancement

**Current:** A simple Line2D with green/red coloring. Staged path visual is yellow for valid, red for invalid (`MovementController.gd:1724`).

**Suggestion:**
- Use dashed lines for the movement path (more visually distinct from other lines)
- Add arrow heads at the destination to show direction
- Use thicker lines or glow effects for better visibility
- Show distance labels along the path at regular intervals (e.g., every 3")

### 5.2 Model State Indicators

**Current:** Unit list shows text status like `[COMPLETED MOVING]`.

**Suggestion:** Add visual indicators on the board itself:
- Green checkmark above models that have completed movement
- Yellow arrow above models currently being moved
- Grey circle above models that Remained Stationary
- Small "A" badge for units that Advanced
- Small "FB" badge for units that Fell Back

### 5.3 Ghost Preview Improvement

**Current:** A basic Node2D ghost at the cursor position using `GhostVisual.gd`.

**Suggestion:**
- Make the ghost semi-transparent (50% opacity)
- Color it green when valid, red when invalid
- Show the model's actual base shape (not just a circle)
- Display the remaining movement distance as a label attached to the ghost

### 5.4 ~~Board Edge Warning~~ PARTIALLY IMPLEMENTED

**Current:** Board edge enforcement is implemented (see 2.6). When dragging a model beyond the board edge, the ghost turns red and an error message "Cannot move beyond the board edge" is shown. The move is rejected by the phase validation.

**Remaining:** A proximity warning (yellow border when within 2" of the edge) is not yet implemented. Only the hard block (red ghost + rejection) is in place.

### 5.5 Opponent's Movement Replay (Multiplayer)

**Current:** In multiplayer, the non-active player sees units teleport to their final positions with no animation or context. The `NetworkManager._emit_client_visual_updates()` sends `model_drop_committed` signals, but these result in instant position updates.

**Suggestion:** When the opponent confirms a unit move, animate the models smoothly from origin to destination over ~0.5 seconds. This helps the non-active player understand what happened. Also show:
- The movement type (Normal/Advance/Fall Back) as a brief label
- The path taken as a fading trail
- A dice result overlay for Advance moves

---

## 6. Code Quality Observations

### 6.1 Duplicate `get_unit_movement()` Function

Both `MovementPhase.gd:24` and `MovementController.gd:80` contain identical `get_unit_movement()` helper functions. This should be consolidated into a single location (e.g., `Measurement.gd` or a shared utility).

### 6.2 `_position_intersects_terrain()` Uses Simplified Bounds

**Location:** `MovementPhase.gd:1239-1277`

The terrain collision uses bounding-box expansion (`_point_in_expanded_polygon`), which is an approximation. The actual terrain polygons support rotation (via `TerrainManager`), but the collision check doesn't use proper polygon intersection.

**Recommendation:** Use `Geometry2D.is_point_in_polygon()` (already used in `TerrainManager.gd:122`) for accurate collision, or at minimum use the rotated polygon vertices.

### 6.3 ~~`_check_terrain_collision()` Is a No-Op~~ FIXED

**Location:** `MovementPhase.gd:1675-1677`

**Resolution:** `_check_terrain_collision()` now delegates to `_position_intersects_terrain()`, which uses shape-aware bounds to check against impassable terrain polygons. The function signature was updated to accept a `model: Dictionary` parameter (required by `_position_intersects_terrain` for base shape calculation). Both callers were updated:
- `_process_group_movement()` looks up the full model via `_get_model_in_unit()` before calling
- `_validate_individual_move_internal()` passes the already-resolved model dict

Terrain collision checking is now consistent across all three movement validation paths: `_validate_stage_model_move()`, `_process_group_movement()`, and `_validate_individual_move_internal()`.

**Commit:** `37a64a7` — "Fix _check_terrain_collision() stub to use actual terrain checking"

### 6.4 Movement Distance Is Euclidean (Origin-to-Destination)

**Location:** `MovementPhase.gd:323`

```gdscript
var total_distance_for_model = Measurement.distance_inches(original_pos, dest_vec)
```

Distance is calculated as straight-line from origin to final position, not along the actual path taken. In 10e rules, movement is measured along the path the model travels. The current implementation means a model moved in a straight line and a model moved in an arc both measure the same if they end at the same point.

For a 2D digital implementation this is a reasonable simplification, but it could be exploited (e.g., "teleporting" around obstacles by measuring only start-to-end).

### 6.5 Excessive Debug Logging

The codebase has extensive `print()` and `log_phase_message()` calls throughout movement logic. While the `CLAUDE.md` says not to remove debug logs unless asked, the volume of logging (especially in input handling and validation) will impact performance in production. Consider gating debug prints behind a debug flag.

### 6.6 Coherency Check Exists But Only as Warning

**Location:** `MovementPhase.gd:1520`

The `_check_group_unit_coherency()` function correctly implements the 2" / two-connection rules using shape-aware distance and correctly distinguishes between 6-or-fewer and 7+ model units. However, the calling function `_validate_group_movement()` at line 1479 only adds a **warning** — it does not fail validation. This means the coherency logic exists and is correct but is simply not enforced.

### 6.7 Attached Character Movement Uses Only First Model Delta

**Location:** `MovementPhase.gd:2096-2107`

The `_move_attached_characters()` function calculates the movement delta from the first bodyguard model's move and applies it to all character models. If different bodyguard models moved different distances/directions, the character will only follow the first model. This is a reasonable simplification for typical cases but could produce incorrect positioning when a bodyguard unit moves in formation and the character is attached to a different part of the unit.

### 6.8 Pivot Cost Tracking Issue

**Location:** `MovementController.gd:2055-2088`

The `pivot_cost_paid` global flag doesn't reset per drag operation. After paying the pivot cost once, subsequent rotations of the same model in the same drag don't re-apply the cost. While this might be intentional (first pivot costs movement, subsequent pivots are free), the Warhammer rules don't have a pivot cost — pivoting is free. If pivot cost is an intentional design choice for the digital version, it should be documented.

---

## 7. Priority Recommendations

### Must Fix (Before Competitive Play)
1. **Unit coherency enforcement** — Port from FightPhase into `_validate_confirm_unit_move()`
2. ~~**Board edge enforcement** — Add boundary validation to prevent off-board placement~~ FIXED
3. **Embark action notification** — Ensure opponent sees embark actions in multiplayer

### Should Fix (Gameplay Completeness)
4. ~~**FLY keyword support** — Skip Desperate Escape, allow movement through enemies~~ PARTIALLY FIXED (Desperate Escape skip done; path-through-enemy exemption still needed)
5. ~~**TITANIC skip Desperate Escape** — Simple keyword check in `_process_desperate_escape()`~~ FIXED
6. **Path-through-enemy validation** — Normal/Advance shouldn't cross enemy bases
7. **Reinforcements step** — Add reserves / Deep Strike system
8. ~~**`_check_terrain_collision()` stub** — Connect to actual terrain checking~~ FIXED
9. **Disembarked units and Remain Stationary** — Prevent Heavy weapon bonus for disembarked units
10. **BEGIN_ADVANCE latency** — Consider making it deterministic via shared RNG seed

### Nice to Have (QoL / Visual)
11. Movement range indicators
12. Engagement range visualization
13. Auto-select next unit
14. Movement summary before end phase
15. Opponent movement animation in multiplayer
16. Coherency visualization
17. ~~Board edge warning~~ PARTIALLY DONE (hard block implemented; proximity warning remaining)
18. Better advance roll display
19. Keyboard shortcut expansion

---

## 8. Action System Audit (Disembark Focus)


The Movement Phase should route all game state changes through the action system (`NetworkIntegration.route_action()`) to ensure multiplayer synchronization and validation. This audit tracks items where the action system is bypassed.

---

## Completed Fixes

### 1. MovementController Disembark Bypasses Action System
**Status:** FIXED
**Files Changed:** `scripts/MovementController.gd`, `scripts/Main.gd`
**Severity:** Critical (breaks multiplayer sync)

**Problem:** `MovementController._on_disembark_completed()` called `TransportManager.disembark_unit()` directly instead of routing through `NetworkIntegration.route_action()` with the `CONFIRM_DISEMBARK` action type.

**Fix Applied:**
- `MovementController._on_disembark_completed()` now builds a `CONFIRM_DISEMBARK` action (serializing Vector2 positions to `{x, y}` dicts for network transport) and emits `move_action_requested`
- `Main._on_movement_action_requested()` handles `CONFIRM_DISEMBARK` post-action: refreshes board visuals, refreshes unit list, and sets up the disembarked unit for movement if eligible
- The existing `MovementPhase._validate_confirm_disembark()` and `_process_confirm_disembark()` methods handle validation and state changes

---

## Open Items

### 2. MovementPhase._on_disembark_placement_completed() Direct TransportManager Call
**Status:** TODO
**File:** `phases/MovementPhase.gd` (line ~1890)
**Severity:** Critical

**Problem:** `MovementPhase._on_disembark_placement_completed()` calls `TransportManager.disembark_unit()` directly. This is a second code path for disembark that bypasses the CONFIRM_DISEMBARK action validation/processing. There are now two disembark paths:
- Path 1: MovementController → CONFIRM_DISEMBARK action → MovementPhase._process_confirm_disembark() → TransportManager (FIXED above)
- Path 2: MovementPhase._on_disembark_placement_completed() → TransportManager (still bypasses action system)

**Recommendation:** Consolidate into one path. `_on_disembark_placement_completed()` should build and execute a CONFIRM_DISEMBARK action instead of calling TransportManager directly.

### 3. MovementPhase._initialize_movement_for_disembarked_unit() Bypasses BEGIN_NORMAL_MOVE
**Status:** TODO
**File:** `phases/MovementPhase.gd` (lines ~1914-1972)
**Severity:** Moderate

**Problem:** After disembark, `_initialize_movement_for_disembarked_unit()` sets up movement state directly (modifying `active_moves`, applying state changes, emitting `unit_move_begun`) instead of routing through a `BEGIN_NORMAL_MOVE` action. This means the movement initialization for disembarked units takes a different code path than normal movement initialization.

**Recommendation:** After disembark completes, create and process a BEGIN_NORMAL_MOVE action for the disembarked unit.

### 4. TransportManager Modifies GameState Directly
**Status:** TODO
**File:** `autoloads/TransportManager.gd`
**Severity:** Moderate (by design, but worth noting)

**Problem:** `TransportManager.disembark_unit()` and `embark_unit()` directly modify `GameState.state.units` (positions, flags, status, embarked_in, transport_data). While this is called from within `MovementPhase._process_confirm_disembark()` (which is in the action system), the TransportManager itself doesn't go through any validation layer. No diffs are generated for proper replay support.

**Recommendation:** Consider whether TransportManager methods should return state change dicts instead of applying them directly, letting the phase apply them. Lower priority since the action system validates before calling TransportManager.

### 5. Main.gd CONFIRM_DISEMBARK Handler Directly Modifies MovementController State
**Status:** TODO (minor)
**File:** `scripts/Main.gd` (CONFIRM_DISEMBARK handler)
**Severity:** Low

**Problem:** The CONFIRM_DISEMBARK post-action handler in Main.gd directly sets `movement_controller.active_unit_id`, `.active_mode`, `.move_cap_inches` and calls internal methods. This is consistent with how other actions like CONFIRM_UNIT_MOVE work in Main.gd, but ideally the controller would handle its own state via a signal.

**Recommendation:** Consider having MovementController listen for a `disembark_confirmed` signal from Main or the phase, rather than Main reaching into controller internals. Low priority since this follows the existing pattern.

---

## Correctly Implemented Actions

The following movement actions are properly routed through the action system:

| Action | Controller | Phase Validate | Phase Process |
|--------|-----------|---------------|---------------|
| BEGIN_NORMAL_MOVE | MovementController (line 686) | _validate_begin_normal_move | _process_begin_normal_move |
| BEGIN_ADVANCE | MovementController (line 705) | _validate_begin_advance | _process_begin_advance |
| BEGIN_FALL_BACK | MovementController (line 724) | _validate_begin_fall_back | _process_begin_fall_back |
| SET_MODEL_DEST | MovementController (line 805) | _validate_set_model_dest | _process_set_model_dest |
| STAGE_MODEL_MOVE | MovementController (line 1262) | _validate_stage_model_move | _process_stage_model_move |
| UNDO_LAST_MODEL_MOVE | MovementController (line 759) | _validate_undo_last_model_move | _process_undo_last_model_move |
| RESET_UNIT_MOVE | MovementController (line 770) | _validate_reset_unit_move | _process_reset_unit_move |
| CONFIRM_UNIT_MOVE | Main.gd (line 1939) | _validate_confirm_unit_move | _process_confirm_unit_move |
| REMAIN_STATIONARY | MovementController (line 739) | _validate_remain_stationary | _process_remain_stationary |
| LOCK_MOVEMENT_MODE | MovementController (line 805) | _validate_lock_movement_mode | _process_lock_movement_mode |
| SET_ADVANCE_BONUS | MovementController | _validate_set_advance_bonus | _process_set_advance_bonus |
| END_MOVEMENT | Main.gd (line 2798) | _validate_end_movement | _process_end_movement |
| DISEMBARK_UNIT | MovementPhase (internal) | _validate_disembark_unit | _process_disembark_unit |
| CONFIRM_DISEMBARK | MovementController (line 1692) | _validate_confirm_disembark | _process_confirm_disembark |
| EMBARK_UNIT | MovementPhase (line 1684) | _validate_embark_unit | _process_embark_unit |

---

## Suggested Next Tasks

**Priority order for implementation:**

1. **Item #2: Consolidate MovementPhase disembark paths** — `MovementPhase._on_disembark_placement_completed()` still calls `TransportManager.disembark_unit()` directly (line ~1890). This should be refactored to route through the CONFIRM_DISEMBARK action, eliminating the duplicate code path.

2. **Unit coherency enforcement** — The coherency check logic already exists at `MovementPhase.gd:1520` and works correctly. It just needs to be called from `_validate_confirm_unit_move()` and set to reject (not warn) when coherency is broken.

3. ~~**FLY/TITANIC keyword in Desperate Escape** — A small change to `_process_desperate_escape()` to check unit keywords before rolling.~~ DONE (commit `e4364af`)

4. ~~**Board edge enforcement** — Add a simple boundary check using `game_state_snapshot.board.size` in `_validate_stage_model_move()`.~~ DONE

5. ~~**`_check_terrain_collision()` stub** — Replace the no-op with a call to `_position_intersects_terrain()` to fix group movement terrain validation.~~ DONE (commit `37a64a7`)

6. **Disembarked units and Remain Stationary** — Track `disembarked_this_phase` flag and check it in `_process_remain_stationary()` to prevent Heavy weapon bonus for units that disembarked (audit item 2.12).

7. **Path-through-enemy validation** — Add path validation for Normal/Advance moves to prevent models crossing enemy bases, with FLY exemption (audit item 2.5).
