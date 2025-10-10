# PRP: Fix Movement Confirmation Bug - `flags.moved` Not Being Set

## Issue Description

Users report that after moving all units and confirming their movement during the Movement Phase, the game still reports "There are active moves that need to be confirmed or reset" and blocks phase progression. The debug logs show:

```
[2][INFO] Checking active_move for unit U_CALADIUS_GRAV-TANK_E (Caladius Grav-tank)
[2][INFO]   - flags.moved: false
[2][INFO]   - staged_moves: 0
[2][INFO]   - model_moves: 1
[2][INFO]   - completed flag: true
[2][INFO]   → BLOCKING: Unit has uncommitted moves!
```

Even though the unit has model_moves and completed flag set to true, the `flags.moved` field remains `false`, preventing phase completion.

## Root Cause Analysis

### Flow of Movement Confirmation

1. User clicks "Confirm Move" button in MovementController
2. MovementController emits `move_action_requested` signal with `CONFIRM_UNIT_MOVE` action
3. Main.gd routes action through NetworkIntegration.route_action()
4. GameManager.apply_action() calls GameManager.process_action()
5. GameManager.process_confirm_move() delegates to current phase via _delegate_to_current_phase()
6. BasePhase.execute_action() validates then processes the action
7. MovementPhase._process_confirm_unit_move() creates state changes including:
   ```gdscript
   changes.append({
       "op": "set",
       "path": "units.%s.flags.moved" % unit_id,
       "value": true
   })
   ```
8. BasePhase.execute_action() applies changes via PhaseManager.apply_state_changes()

### The Bugs (Three-Part Issue)

#### Bug #1: PhaseManager doesn't create missing keys

The first bug is in `PhaseManager._set_state_value()` at lines 209-236 in `40k/autoloads/PhaseManager.gd`.

When navigating the path `units.U_ID.flags.moved`:
- The code checks if each path segment exists: `current.has(part)`
- If a segment doesn't exist (e.g., the unit doesn't have a `flags` dictionary yet), it **returns early** without setting the value (line 227)
- This prevents the creation of missing intermediate dictionaries in the path

```gdscript
# PhaseManager.gd lines 224-227
else:
    if current is Dictionary and current.has(part):
        current = current[part]
    else:
        return  # <-- BUG: Returns without creating missing keys!
```

#### Why GameManager Works But PhaseManager Doesn't

GameManager.set_value_at_path (lines 233-244 in 40k/autoloads/GameManager.gd) handles this correctly by **creating missing keys**:

```gdscript
# GameManager.gd lines 242-244
if not current.has(key):
    current[key] = {}  # Creates missing intermediate dictionaries
current = current[key]
```

The GameManager.set_value_at_path() implementation is more permissive and creates the full path as needed, which is the correct behavior for a state management system.

#### Bug #2: Phase snapshot not refreshed after state changes

The second bug is in `BasePhase.execute_action()` at lines 77-91 in `40k/phases/BasePhase.gd`.

After applying state changes via `PhaseManager.apply_state_changes()`, the phase's `game_state_snapshot` is **never refreshed**!

```gdscript
# BasePhase.gd lines 81-82
PhaseManager.apply_state_changes(result.changes)
# <-- BUG: game_state_snapshot is now stale!
```

Later when validation code calls `get_unit()`, it reads from the stale snapshot:

```gdscript
# BasePhase.gd lines 121-123
func get_unit(unit_id: String) -> Dictionary:
    var units = game_state_snapshot.get("units", {})  # OLD DATA!
    return units.get(unit_id, {})
```

This means:
1. `flags.moved` IS set correctly in GameState
2. But the phase's snapshot still has the old data without the flag
3. So validation checks see `flags.moved = false` even though it's actually true

#### Bug #3: MovementPhase auto-completes when all units move

The third bug is in `MovementPhase._should_complete_phase()` at lines 1338-1349.

After fixing Bug #2 (refreshing snapshots), a NEW problem emerged: the phase now auto-completes when the last unit confirms movement!

Here's why:
1. User confirms movement for last unit
2. BasePhase.execute_action() applies changes → `flags.moved = true`
3. BasePhase.execute_action() refreshes snapshot (Bug #2 fix)
4. BasePhase.execute_action() calls `_should_complete_phase()` (line 94)
5. MovementPhase._should_complete_phase() checks if all units moved
6. Returns TRUE because all units now have `flags.moved = true` in fresh snapshot
7. Emits `phase_completed` signal → phase advances automatically!

This causes two problems:
1. **User Experience**: Player loses control - can't use stratagems or review before ending phase
2. **Multiplayer Desync**: Phase transition happens on host/client that confirmed last unit, but NOT synchronized to other clients via action system

The fix: Phases should only complete via explicit END_PHASE actions, never auto-complete.

## Solution

Three fixes are needed:

1. **Fix Bug #1**: Update `PhaseManager._set_state_value()` to create missing dictionary keys in the path
2. **Fix Bug #2**: Update `BasePhase.execute_action()` to refresh the phase's snapshot after applying changes
3. **Fix Bug #3**: Update `MovementPhase._should_complete_phase()` to always return false (no auto-complete)

## Implementation Plan

### Task 1: Fix PhaseManager._set_state_value() (Bug #1)

**File**: `40k/autoloads/PhaseManager.gd`
**Lines**: 209-236

**Current Code**:
```gdscript
func _set_state_value(path: String, value) -> void:
	var parts = path.split(".")
	if parts.is_empty():
		return

	var current = GameState.state
	for i in range(parts.size() - 1):
		var part = parts[i]
		if part.is_valid_int():
			var index = part.to_int()
			if current is Array and index >= 0 and index < current.size():
				current = current[index]
			else:
				return
		else:
			if current is Dictionary and current.has(part):
				current = current[part]
			else:
				return  # <-- BUG HERE

	var final_key = parts[-1]
	if final_key.is_valid_int():
		var index = final_key.to_int()
		if current is Array and index >= 0 and index < current.size():
			current[index] = value
	else:
		if current is Dictionary:
			current[final_key] = value
```

**Fixed Code**:
```gdscript
func _set_state_value(path: String, value) -> void:
	var parts = path.split(".")
	if parts.is_empty():
		return

	var current = GameState.state
	for i in range(parts.size() - 1):
		var part = parts[i]
		if part.is_valid_int():
			var index = part.to_int()
			if current is Array and index >= 0 and index < current.size():
				current = current[index]
			else:
				return
		else:
			if current is Dictionary:
				# Create missing keys in the path
				if not current.has(part):
					current[part] = {}
				current = current[part]
			else:
				return

	var final_key = parts[-1]
	if final_key.is_valid_int():
		var index = final_key.to_int()
		if current is Array and index >= 0 and index < current.size():
			current[index] = value
	else:
		if current is Dictionary:
			current[final_key] = value
```

**Changes Summary**:
- Lines 224-227: Replace the early return with automatic creation of missing dictionary keys
- This matches the behavior in GameManager.set_value_at_path()

### Task 2: Fix BasePhase.execute_action() to refresh snapshot (Bug #2)

**File**: `40k/phases/BasePhase.gd`
**Lines**: 77-91

**Current Code**:
```gdscript
var result = process_action(action)
if result.success:
    print("[BasePhase] Action processed successfully")
    # Apply the state changes if they exist
    if result.has("changes") and result.changes is Array:
        PhaseManager.apply_state_changes(result.changes)

    # Record the action
    print("[BasePhase] Emitting action_taken signal")
    emit_signal("action_taken", action)
```

**Fixed Code**:
```gdscript
var result = process_action(action)
if result.success:
    print("[BasePhase] Action processed successfully")
    # Apply the state changes if they exist
    if result.has("changes") and result.changes is Array:
        PhaseManager.apply_state_changes(result.changes)

        # CRITICAL: Update our local snapshot after applying changes
        # Otherwise get_unit() will read stale data from the old snapshot
        game_state_snapshot = GameState.create_snapshot()
        print("[BasePhase] Refreshed game_state_snapshot after applying changes")

    # Record the action
    print("[BasePhase] Emitting action_taken signal")
    emit_signal("action_taken", action)
```

**Changes Summary**:
- Lines 84-87: Add snapshot refresh after applying state changes
- This ensures get_unit() and other methods read fresh data with the updated flags

### Task 3: Fix MovementPhase._should_complete_phase() to prevent auto-complete (Bug #3)

**File**: `40k/phases/MovementPhase.gd`
**Lines**: 1338-1349

**Current Code**:
```gdscript
func _should_complete_phase() -> bool:
	# Check if all units have moved or been marked as stationary
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			if not unit.get("flags", {}).get("moved", false):
				return false

	return true
```

**Fixed Code**:
```gdscript
func _should_complete_phase() -> bool:
	# Movement phase should NOT auto-complete
	# Phase completion must be explicit via END_MOVEMENT action for:
	# 1. User control - player may want to use stratagems before ending phase
	# 2. Multiplayer sync - phase transitions must be synchronized via actions
	return false
```

**Changes Summary**:
- Lines 1338-1349: Replace auto-complete logic with explicit false return
- Phases must only complete via END_MOVEMENT action, ensuring user control and multiplayer sync

## Validation

### Manual Testing Steps

1. Start a new game and deploy all units
2. Transition to Movement Phase
3. Select a unit that has never moved before (no `flags` dict exists yet)
4. Move the unit's models by dragging them
5. Click "Confirm Move" button
6. **Expected Result**: Unit's `flags.moved` should be set to `true`
7. Try to end the movement phase by clicking "End Movement Phase"
8. **Expected Result**: Phase should transition to Shooting Phase without errors

### Validation with Debug Logs

Run the game with DebugLogger enabled and check the movement confirmation logs:

```bash
# Find the latest log file
ls -lt ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | head -1

# Monitor the log during testing
tail -f ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | grep -E "flags.moved|END_MOVEMENT"
```

Expected log output after confirming movement:
```
GameManager: Setting units.U_UNIT_ID.flags.moved = true
[BasePhase] Refreshed game_state_snapshot after applying changes
[2][INFO] Checking active_move for unit U_UNIT_ID (Unit Name)
[2][INFO]   - flags.moved: true  <-- Should be true now (was false before fix)
[2][INFO]   - staged_moves: 0
[2][INFO]   - model_moves: 1
[2][INFO]   - completed flag: true
[2][INFO]   → Unit has completed its move
[2][INFO] === END_MOVEMENT VALIDATION PASSED ===
```

### Edge Cases to Test

1. **Unit with existing flags dict**: Confirm that units that already have a `flags` dictionary still work correctly
2. **Multiple units**: Move and confirm multiple units in succession, ensuring phase doesn't auto-advance
3. **Remain Stationary**: Test that "Remain Stationary" also sets `flags.moved` correctly
4. **All units moved but phase not ended**: Confirm all units, verify "End Movement Phase" button appears, verify phase does NOT auto-advance
5. **Network multiplayer**: If multiplayer is enabled, test that both host and client apply the flag correctly and phase transition is synchronized

## References

### Key Files

- `40k/autoloads/PhaseManager.gd`: Lines 209-236 (_set_state_value) - Bug #1
- `40k/phases/BasePhase.gd`: Lines 77-91 (execute_action) - Bug #2
- `40k/phases/MovementPhase.gd`: Lines 1338-1349 (_should_complete_phase) - Bug #3
- `40k/autoloads/GameManager.gd`: Lines 222-259 (set_value_at_path - reference implementation)
- `40k/phases/MovementPhase.gd`: Lines 746-846 (_process_confirm_unit_move)
- `40k/scripts/MovementController.gd`: Lines 774-783 (_on_confirm_move_pressed)

### Related Issues

- Movement Phase: https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/gdscript_basics.html
- Dictionary manipulation: https://docs.godotengine.org/en/4.4/classes/class_dictionary.html

## Confidence Score

**9.5/10** - All three fixes are straightforward and well-understood:
1. Bug #1 fix matches the working GameManager implementation
2. Bug #2 fix follows the pattern used in NetworkManager._update_phase_snapshot()
3. Bug #3 fix follows the pattern used in CommandPhase and FightPhase (explicit phase completion only)

The fixes address the root causes identified through debug log analysis and testing.

## Additional Notes

### Why These Bugs Were Introduced

**Bug #1**: The PhaseManager._set_state_value() implementation was likely written to be "safe" by not creating unexpected keys. However, this defensive approach breaks the expected behavior when setting nested properties that don't exist yet.

**Bug #2**: The snapshot refresh was missing because it's not immediately obvious that the phase's snapshot becomes stale after applying changes. The execute_action() method applies changes to GameState but doesn't update the local snapshot, creating an inconsistency.

**Bug #3**: The auto-complete logic was written before multiplayer support was added. In single-player, auto-completing when all units move seems convenient, but in multiplayer it causes desync because phase transitions must be synchronized via the action system.

### Future Improvements

1. **State Manipulation Consolidation**: Consider consolidating state manipulation logic into a single utility class to avoid code duplication between PhaseManager and GameManager. Both have similar path-based state manipulation methods that could be unified.

2. **Automatic Snapshot Sync**: Consider adding automatic snapshot refresh hooks whenever GameState is modified, to prevent snapshot staleness issues from occurring in the future. This could be implemented as a signal/observer pattern on GameState.

3. **Phase Completion Audit**: Review ALL phases to ensure they follow the explicit completion pattern (return false from _should_complete_phase). ShootingPhase and MoralePhase currently auto-complete, which may cause similar issues.

