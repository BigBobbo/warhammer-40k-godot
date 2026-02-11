# Movement Phase Audit — Warhammer 40k 10th Edition

## Scope
This audit compares the current movement phase implementation (primarily `phases/MovementPhase.gd` and `scripts/MovementController.gd`) against the Warhammer 40,000 10th Edition core rules, with a focus on online multiplayer correctness.

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
| Advanced units cannot shoot (except Assault) | **Implemented** | `ShootingPhase.gd:1026-1031` checks `advanced` flag |
| Fell Back units cannot shoot or charge | **Implemented** | Sets `cannot_shoot` and `cannot_charge` flags |
| Advanced units cannot charge | **Implemented** | Sets `cannot_charge` flag |
| Heavy weapon +1 to hit when stationary | **Implemented** | `remained_stationary` flag consumed by shooting phase |
| Transport Disembark (within 3") | **Implemented** | Full disembark flow with edge-to-edge distance validation |
| Disembark cannot be in ER of enemy | **Implemented** | `_validate_confirm_disembark()` checks ER |
| Transport moved → disembarked unit cannot move | **Implemented** | `cannot_move` flag enforced |
| Embark after movement (within 3") | **Implemented** | `_check_embark_opportunity()` with prompt dialog |
| Attached characters move with bodyguard | **Implemented** | `_move_attached_characters()` applies delta |
| Terrain collision (impassable) | **Implemented** | `_position_intersects_terrain()` |
| Model overlap prevention | **Implemented** | `_position_overlaps_other_models()` with staged position awareness |
| INFANTRY move through ruins | **Implemented** | `TerrainManager.can_unit_move_through_terrain()` |

---

## 2. Missing Rules (Gaps)

### 2.1 CRITICAL — Unit Coherency Enforcement

**Rule:** After a unit moves, each model must be within 2" of at least one other model in the same unit. For units with 7+ models, each model must be within 2" of at least **two** other models.

**Current state:** Coherency checking exists only as a warning in group movement validation (`_check_group_unit_coherency()` in `MovementPhase.gd:1516`), but it is **never enforced** during `_validate_confirm_unit_move()`. A player can confirm a move that breaks coherency with no penalty.

**Impact:** High. This is a fundamental rule that affects game balance. Without enforcement, units can spread models across the entire board.

**Recommendation:** Add coherency validation to `_validate_confirm_unit_move()`. If coherency is broken, the move should be rejected (or at minimum show a prominent warning and require re-confirmation).

### 2.2 CRITICAL — Reinforcements Step

**Rule:** The Movement Phase has two steps: (1) Move Units, and (2) Reinforcements. After all units have moved, reserves/reinforcements can be placed on the battlefield (e.g., Deep Strike must end 9"+ from enemies). Any reserves not placed by end of game count as destroyed.

**Current state:** There is **no Reinforcements step** implemented. No reserves system, no Deep Strike, no ability to bring units onto the battlefield mid-game.

**Impact:** High. Many armies rely on reserves and Deep Strike as core mechanics.

**Recommendation:** Add a Reinforcements sub-phase that activates after all movement is complete but before the phase ends. Track reserve units in GameState, validate placement distances, and enforce the "destroyed if not deployed" rule.

### 2.3 HIGH — FLY Keyword

**Rule:** Units with the FLY keyword can move over enemy models during a Normal Move or Advance (but must still end outside ER). When Falling Back, FLY units can move over enemy models without taking Desperate Escape tests. FLY units also ignore vertical distances and can move over terrain freely.

**Current state:** The `MOVEMENT_PHASE_IMPLEMENTATION.md` explicitly lists "FLY keyword not implemented" as a known limitation. The `TerrainManager.can_unit_cross_wall()` does check for FLY keyword for wall traversal, but `MovementPhase.gd` does not check FLY during Normal Move or Fall Back path validation.

**Impact:** High. Several unit types (e.g., Jump Pack Intercessors, Custodes Vertus Praetors, vehicles with FLY) cannot be played correctly.

**Recommendation:**
- In `_check_engagement_range_at_position()`: Allow FLY units to move through (but not end in) enemy ER during Normal/Advance moves.
- In `_process_desperate_escape()`: Skip Desperate Escape tests for FLY units.
- In terrain checks: Allow FLY units to ignore terrain elevation.

### 2.4 HIGH — TITANIC Keyword

**Rule:** TITANIC models do not take Desperate Escape tests when Falling Back, similar to FLY.

**Current state:** No TITANIC keyword handling in movement. `_process_desperate_escape()` does not check for TITANIC.

**Impact:** Medium-High. Affects large models like Knights and Baneblades.

**Recommendation:** Add TITANIC check alongside FLY in `_process_desperate_escape()`.

### 2.5 HIGH — Moving Through Friendly Models

**Rule:** A model can move through friendly models during its move but cannot end its move on top of another model. Models can also move over other friendly models if they have the FLY keyword.

**Current state:** The current implementation checks for model overlap at the final position (`_position_overlaps_other_models()`), which is correct. However, the **path** is not validated — a model cannot physically walk through enemy models (only FLY or Fall Back allow this). The `_path_crosses_enemy()` function exists for Fall Back, but there's no general check preventing Normal/Advance moves from pathing through enemy models.

**Impact:** Medium. Currently a model could be dragged through an enemy model's base and placed on the other side without penalty, as long as it ends outside ER.

**Recommendation:** Add path validation for Normal and Advance moves to ensure models don't cross enemy bases. Allow crossing friendly bases freely. Add FLY exception.

### 2.6 MEDIUM — Difficult Terrain / Movement Penalties

**Rule:** Certain terrain features (like dense cover, craters, etc.) may apply movement penalties. While the basic 10e rules don't have universal "difficult terrain," terrain traits can affect movement.

**Current state:** The `MOVEMENT_PHASE_IMPLEMENTATION.md` lists "Difficult terrain not implemented" as a known limitation. Terrain is either passable or impassable — no partial movement costs.

**Impact:** Medium. Affects tactical positioning around terrain.

**Recommendation:** Consider adding terrain traits that reduce movement or require extra distance when crossing.

### 2.7 MEDIUM — Scout Moves

**Rule:** Some units have the Scouts X" ability, allowing them to make a pre-game move of X" after deployment but before the first turn. Dedicated Transport units with Scout units embarked also inherit this ability.

**Current state:** No Scout move implementation found.

**Impact:** Medium. Affects specific army builds that rely on early positioning.

**Recommendation:** Add a pre-game Scout phase between Deployment and the first Command phase.

### 2.8 LOW — Overwatch During Movement

**Rule:** The Overwatch stratagem can be used during the opponent's Movement phase when an enemy unit starts or ends a Normal, Advance, or Fall Back move within 24" of an eligible unit.

**Current state:** No Overwatch trigger during movement.

**Impact:** Low for initial release, but this is a commonly used stratagem.

**Recommendation:** Add event hooks in movement confirmation for opponent reactions.

### 2.9 LOW — Rapid Ingress Stratagem

**Rule:** Used at the end of your opponent's Movement phase to bring in a Reserves unit.

**Current state:** Not implemented (no reserves system).

**Impact:** Low until reserves are implemented.

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

### 3.3 MEDIUM — `game_state_snapshot` Manually Refreshed After Disembark

**Location:** `MovementPhase.gd:1972`

```gdscript
game_state_snapshot = GameState.state.duplicate(true)
```

This bypasses the normal snapshot management (handled by `PhaseManager`/`BasePhase`). In multiplayer, directly reading `GameState.state` could return a state that hasn't been fully synchronized yet.

**Recommendation:** Use the proper snapshot refresh mechanism through `PhaseManager` or add synchronization barriers.

### 3.4 MEDIUM — Embark Prompt is UI-Only

**Location:** `MovementPhase.gd:1654-1683`

The `_show_embark_prompt()` creates a `ConfirmationDialog` and directly calls `TransportManager.embark_unit()` — this is not going through the action system. In multiplayer, only the active player sees this dialog and the embark happens locally without network validation.

**Recommendation:** Convert embark into a proper action (`EMBARK_UNIT`) that goes through `validate_action()`/`process_action()` and the network layer.

---

## 4. Quality of Life Improvements

### 4.1 Movement Range Indicator

**Current:** Players must manually judge how far each model can move by watching the distance counter.

**Suggestion:** When a unit is selected for movement, draw a translucent circle (or shape for non-circular bases) showing the maximum movement range around each model. Use green for Normal Move range and blue for Advance range. This is standard in most digital tabletop implementations.

### 4.2 Engagement Range Visualization

**Current:** Players discover they're in engagement range only when they try to place a model and get an error.

**Suggestion:** When a unit is within or near engagement range of enemy models, display a red halo or ring around the enemy models showing the 1" ER zone. This helps players understand their movement constraints before dragging.

### 4.3 Unit Coherency Visualization

**Current:** No visual feedback for coherency.

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

**Current:** Q/E for rotation, Ctrl+A for select all, Ctrl+click for multi-select.

**Suggestion:** Add more shortcuts:
- `Space` — Confirm current unit's move
- `R` — Reset current unit's move
- `Z` / `Ctrl+Z` — Undo last model move
- `Tab` — Cycle to next unmoved unit
- `N` — Normal Move
- `A` (when no unit selected) — Advance
- `F` — Fall Back
- `S` — Remain Stationary

---

## 5. Visual Improvements

### 5.1 Path Visualization Enhancement

**Current:** A simple Line2D with green/red coloring.

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

**Current:** A basic Node2D ghost at the cursor position.

**Suggestion:**
- Make the ghost semi-transparent (50% opacity)
- Color it green when valid, red when invalid
- Show the model's actual base shape (not just a circle)
- Display the remaining movement distance as a label attached to the ghost

### 5.4 Board Edge Warning

**Current:** No indication when a model is near the board edge.

**Suggestion:** When dragging a model near the board edge (within 2"), show a yellow warning border. If the model would leave the board, show a red border. Models cannot be placed off the board.

### 5.5 Opponent's Movement Replay (Multiplayer)

**Current:** In multiplayer, the non-active player sees units teleport to their final positions.

**Suggestion:** When the opponent confirms a unit move, animate the models smoothly from origin to destination over ~0.5 seconds. This helps the non-active player understand what happened.

---

## 6. Code Quality Observations

### 6.1 Duplicate `get_unit_movement()` Function

Both `MovementPhase.gd:24` and `MovementController.gd:80` contain identical `get_unit_movement()` helper functions. This should be consolidated into a single location (e.g., `Measurement.gd` or a shared utility).

### 6.2 `_position_intersects_terrain()` Uses Simplified Bounds

**Location:** `MovementPhase.gd:1235-1273`

The terrain collision uses bounding-box expansion (`_point_in_expanded_polygon`), which is an approximation. The actual terrain polygons support rotation (via `TerrainManager`), but the collision check doesn't use proper polygon intersection.

**Recommendation:** Use `Geometry2D.is_point_in_polygon()` (already used in `TerrainManager.gd:122`) for accurate collision, or at minimum use the rotated polygon vertices.

### 6.3 `_check_terrain_collision()` Is a No-Op

**Location:** `MovementPhase.gd:1568-1572`

```gdscript
func _check_terrain_collision(position: Vector2) -> bool:
    # Implementation depends on terrain system
    # For now, return false (no collision)
    return false
```

This stub is used by `_process_group_movement()` and `_validate_individual_move_internal()`, meaning group movement validation does NOT check terrain collisions. Individual model staging (`_validate_stage_model_move()`) does check via `_position_intersects_terrain()`, so this is inconsistent.

### 6.4 Movement Distance Is Euclidean (Origin-to-Destination)

**Location:** `MovementPhase.gd:319`

```gdscript
var total_distance_for_model = Measurement.distance_inches(original_pos, dest_vec)
```

Distance is calculated as straight-line from origin to final position, not along the actual path taken. In 10e rules, movement is measured along the path the model travels. The current implementation means a model moved in a straight line and a model moved in an arc both measure the same if they end at the same point.

For a 2D digital implementation this is a reasonable simplification, but it could be exploited (e.g., "teleporting" around obstacles by measuring only start-to-end).

### 6.5 Excessive Debug Logging

The codebase has extensive `print()` and `log_phase_message()` calls throughout movement logic. While the `CLAUDE.md` says not to remove debug logs unless asked, the volume of logging (especially in input handling and validation) will impact performance in production. Consider gating debug prints behind a debug flag.

---

## 7. Priority Recommendations

### Must Fix (Before Competitive Play)
1. **Unit coherency enforcement** — Add to `_validate_confirm_unit_move()`
2. ~~**Double advance dice roll** — Remove duplicate roll in controller~~ **FIXED** (commit `41a3891`)
3. **Embark action not networked** — Convert to proper action

### Should Fix (Gameplay Completeness)
4. **FLY keyword support** — Movement through enemies, skip Desperate Escape
5. **TITANIC skip Desperate Escape** — Simple keyword check
6. **Path-through-enemy validation** — Normal/Advance shouldn't cross enemy bases
7. **Reinforcements step** — Add reserves / Deep Strike system

### Nice to Have (QoL / Visual)
8. Movement range indicators
9. Engagement range visualization
10. Auto-select next unit
11. Movement summary before end phase
12. Opponent movement animation in multiplayer
13. Coherency visualization
