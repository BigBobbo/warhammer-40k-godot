# Movement Phase Audit

**Purpose:** Track multiplayer correctness and rules compliance issues in the Movement Phase.

---

## Issues

### 1. Movement Actions Not Fully Networked for Disembark Placement
**Status:** Open
**Severity:** Medium
**Description:** The `_on_disembark_placement_completed()` handler in MovementPhase.gd calls `TransportManager.disembark_unit()` directly rather than routing through the action system. While the initial DISEMBARK_UNIT action is properly networked, the actual placement confirmation bypasses `NetworkIntegration.route_action()`. In multiplayer, this means model positions after disembark may not be synchronized across clients.
**File:** `phases/MovementPhase.gd` (lines ~1875-1888)

### 2. MovementController Disembark Bypasses Action System
**Status:** Open
**Severity:** Medium
**Description:** `MovementController._on_disembark_completed()` calls `TransportManager.disembark_unit()` directly instead of routing through `NetworkIntegration.route_action()` with a `CONFIRM_DISEMBARK` action. The disembark flow from MovementController runs entirely locally — the DisembarkDialog and DisembarkController operate outside the action system.
**File:** `scripts/MovementController.gd` (line ~1694)

### 3. Embark Action Not Networked (Post-Movement Embark Prompt)
**Status:** FIXED
**Severity:** High
**Description:** The embark prompt that appears after a unit finishes moving created a `ConfirmationDialog` and called `TransportManager.embark_unit()` directly, completely bypassing the action system. In multiplayer, only the active player saw the dialog and the embark happened locally without network validation or synchronization to other clients.
**Fix:** Added `EMBARK_UNIT` action type with full `_validate_embark_unit()` / `_process_embark_unit()` support. The dialog confirmation now routes through `NetworkIntegration.route_action()`, ensuring the embark is validated on the host and state changes are synchronized to all clients.
**File:** `phases/MovementPhase.gd`
**Commit:** See git log for `claude/fix-embark-networking-USzTu`

### 4. `_initialize_movement_for_disembarked_unit()` Applies State Changes Locally
**Status:** Open
**Severity:** Low
**Description:** After disembark, `_initialize_movement_for_disembarked_unit()` calls `get_parent().apply_state_changes()` directly and mutates `game_state_snapshot` manually. This works because it only sets up local tracking (`active_moves`, `move_cap_inches`), but could cause state drift if the snapshot diverges from the authoritative GameState in multiplayer.
**File:** `phases/MovementPhase.gd` (lines ~1902-1960)

### 5. `validate_action_with_transport_check()` is Unused
**Status:** Open
**Severity:** Low
**Description:** `validate_action_with_transport_check()` provides enhanced validation that redirects embarked units to the disembark flow, but it is never called. All action routing goes through `validate_action()` directly. This dead code should either be integrated or removed.
**File:** `phases/MovementPhase.gd` (lines ~1706-1727)

---

## Recommended Next Task

**Item #2 (MovementController Disembark Bypasses Action System)** is the natural follow-up. It is the disembark equivalent of the embark fix: the MovementController handles the entire disembark flow locally via `TransportManager.disembark_unit()`, never routing through `NetworkIntegration.route_action()`. Converting this to use the `CONFIRM_DISEMBARK` action that already exists in MovementPhase would ensure disembark positions are validated on the host and synchronized across all clients. The `CONFIRM_DISEMBARK` validate/process methods are already implemented — only the MovementController call site needs updating.
