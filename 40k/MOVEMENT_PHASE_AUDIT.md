# Movement Phase Action System Audit
**Date:** 2026-02-11
**Status:** In Progress

## Overview

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
**File:** `phases/MovementPhase.gd` (line ~1878)
**Severity:** Critical

**Problem:** `MovementPhase._on_disembark_placement_completed()` calls `TransportManager.disembark_unit()` directly. This is a second code path for disembark that bypasses the CONFIRM_DISEMBARK action validation/processing. There are now two disembark paths:
- Path 1: MovementController → CONFIRM_DISEMBARK action → MovementPhase._process_confirm_disembark() → TransportManager (FIXED above)
- Path 2: MovementPhase._on_disembark_placement_completed() → TransportManager (still bypasses action system)

**Recommendation:** Consolidate into one path. `_on_disembark_placement_completed()` should build and execute a CONFIRM_DISEMBARK action instead of calling TransportManager directly.

### 3. MovementPhase._initialize_movement_for_disembarked_unit() Bypasses BEGIN_NORMAL_MOVE
**Status:** TODO
**File:** `phases/MovementPhase.gd` (lines ~1902-1960)
**Severity:** Moderate

**Problem:** After disembark, `_initialize_movement_for_disembarked_unit()` sets up movement state directly (modifying `active_moves`, applying state changes, emitting `unit_move_begun`) instead of routing through a `BEGIN_NORMAL_MOVE` action. This means the movement initialization for disembarked units takes a different code path than normal movement initialization.

**Recommendation:** After disembark completes, create and process a BEGIN_NORMAL_MOVE action for the disembarked unit.

### 4. TransportManager Modifies GameState Directly
**Status:** TODO
**File:** `autoloads/TransportManager.gd`
**Severity:** Moderate (by design, but worth noting)

**Problem:** `TransportManager.disembark_unit()` and `embark_unit()` directly modify `GameState.state.units` (positions, flags, status, embarked_in, transport_data). While this is called from within `MovementPhase._process_confirm_disembark()` (which is in the action system), the TransportManager itself doesn't go through any validation layer.

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
| BEGIN_NORMAL_MOVE | MovementController (line 587) | _validate_begin_normal_move | _process_begin_normal_move |
| BEGIN_ADVANCE | MovementController (line 710) | _validate_begin_advance | _process_begin_advance |
| BEGIN_FALL_BACK | MovementController (line 729) | _validate_begin_fall_back | _process_begin_fall_back |
| SET_MODEL_DEST | MovementController (line 805) | _validate_set_model_dest | _process_set_model_dest |
| STAGE_MODEL_MOVE | MovementController (line 848) | _validate_stage_model_move | _process_stage_model_move |
| UNDO_LAST_MODEL_MOVE | MovementController (line 859) | _validate_undo_last_model_move | _process_undo_last_model_move |
| RESET_UNIT_MOVE | MovementController (line 1287) | _validate_reset_unit_move | _process_reset_unit_move |
| CONFIRM_UNIT_MOVE | Main.gd (line 1939) | _validate_confirm_unit_move | _process_confirm_unit_move |
| REMAIN_STATIONARY | MovementController (line 744) | _validate_remain_stationary | _process_remain_stationary |
| LOCK_MOVEMENT_MODE | MovementController (line 764) | _validate_lock_movement_mode | _process_lock_movement_mode |
| SET_ADVANCE_BONUS | MovementController | _validate_set_advance_bonus | _process_set_advance_bonus |
| END_MOVEMENT | Main.gd (line 2798) | _validate_end_movement | _process_end_movement |
| DISEMBARK_UNIT | MovementPhase (internal) | _validate_disembark_unit | _process_disembark_unit |
| CONFIRM_DISEMBARK | MovementController (line 1700) | _validate_confirm_disembark | _process_confirm_disembark |

---

## Suggested Next Task

**Item #2: Consolidate MovementPhase disembark paths** — `MovementPhase._on_disembark_placement_completed()` still calls `TransportManager.disembark_unit()` directly (line ~1878). This should be refactored to route through the CONFIRM_DISEMBARK action, eliminating the duplicate code path. This is the natural follow-up since it addresses the same disembark bypass pattern from the phase side.
