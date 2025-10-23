# Defender Charge Feedback Fix PRP

## Overview

Fix the **defender charge feedback bug** where the active player correctly sees charge success/failure notifications, but the defending player always sees "charge failed" messages even when the charge was successful. The root cause is that ChargeController uses local UI state (`selected_targets`) to determine success, which is only populated on the charging player's client.

**Score: 9/10** - Clear root cause identified, well-understood codebase patterns, straightforward fix with potential for edge cases in multiplayer sync.

## Issue Context

**Problem Description**:
- Active player (charger) rolls 2D6 for charge
- If charge is successful, active player sees: "Success! Rolled X\" - Click models to move them..."
- Defending player sees: "Failed! Rolled X\" - not enough to reach target"
- **BUG**: Defending player gets incorrect feedback even though charge actually succeeded
- Hypothesis: Wrong distances are being checked for defender vs attacker

### User Experience Impact
- **Defender confusion**: Defending player thinks they're safe when they're actually being charged
- **Game state mismatch**: UI shows different information to different players
- **Trust issues**: Players may doubt the game's accuracy and fairness

## Context & Documentation

### Core Documentation
- **Warhammer 40k 10e Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot 4.4 Documentation**: https://docs.godotengine.org/en/4.4/
- **Project Root**: `/Users/robertocallaghan/Documents/claude/godotv2`

### Key Rule References (Wahapedia)
From 10e Core Rules - Charge phase:
- **Charge Declaration**: Units within 12" of enemy can declare charges
- **Charge Roll**: Roll 2D6 to determine charge distance
- **Charge Success**: If rolled distance allows models to reach engagement range (1")
- **Charge Failure**: If rolled distance insufficient, charge fails

**Important**: All players should see the same charge success/failure determination regardless of which player is charging.

## Existing Codebase Analysis

### Root Cause: Local UI State vs Synced Game State

**The Problem**: ChargeController determines charge success using local UI variable `selected_targets`, which is only populated on the active player's client.

### Complete Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. CHARGE DECLARATION (Active Player Only)                      │
│    ChargeController.gd:1280-1305                                 │
│    User selects targets from UI                                  │
│    selected_targets = [target1_id, target2_id, ...]  ← LOCAL!   │
│    Emits DECLARE_CHARGE action                                   │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ 2. PHASE PROCESSES DECLARATION (All Clients)                    │
│    ChargePhase.gd:256-282 - _process_declare_charge()           │
│    pending_charges[unit_id] = {                                  │
│        "targets": target_ids,  ← SYNCED GAME STATE              │
│        "declared_at": timestamp                                  │
│    }                                                             │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ 3. CHARGE ROLL (Active Player)                                  │
│    ChargeController.gd:1306-1316                                 │
│    User clicks "Roll 2D6"                                        │
│    Emits CHARGE_ROLL action                                      │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ 4. PHASE PROCESSES ROLL (All Clients)                           │
│    ChargePhase.gd:284-313 - _process_charge_roll()              │
│    Rolls 2D6, stores distance                                    │
│    Emits charge_roll_made and dice_rolled signals               │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ 5. CONTROLLER RECEIVES SIGNAL (All Clients)                     │
│    ChargeController.gd:1541-1583 (_on_charge_roll_made)         │
│    ChargeController.gd:1584-1646 (_on_dice_rolled)              │
│                                                                   │
│    ❌ BUG HERE:                                                  │
│    var success = _is_charge_successful(unit_id, distance,       │
│                                         selected_targets)        │
│                                           ^^^^^^^^^^^^^^^        │
│    Active Player: selected_targets = [t1, t2] ✅ WORKS          │
│    Defending Player: selected_targets = [] ❌ ALWAYS FAILS      │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ 6. SUCCESS CHECK FUNCTION                                       │
│    ChargeController.gd:1736-1782 - _is_charge_successful()      │
│                                                                   │
│    for target_id in target_ids:  ← IF EMPTY, LOOP NEVER RUNS!   │
│        var target = GameState.get_unit(target_id)                │
│        # Check if any model can reach engagement range...        │
│                                                                   │
│    return false  # Always returns false if target_ids is empty! │
└──────────────────────────────────────────────────────────────────┘
                                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ 7. UI FEEDBACK (Different on Each Client)                       │
│    ChargeController.gd:1560-1580                                 │
│                                                                   │
│    Active Player (success = true):                              │
│      "Success! Rolled X\" - Click models to move..."             │
│                                                                   │
│    Defending Player (success = false):                          │
│      "Failed! Rolled X\" - not enough to reach target"           │
└──────────────────────────────────────────────────────────────────┘
```

### Key File Locations and Current State

#### 1. ChargeController.gd - _on_charge_roll_made() (THE BUG LOCATION #1)
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd`
**Lines**: 1541-1583

```gdscript
func _on_charge_roll_made(unit_id: String, distance: int, dice: Array) -> void:
	print("Charge roll made: ", unit_id, " rolled ", distance, " (", dice, ")")

	charge_distance = distance
	awaiting_roll = false

	# Mark that we've processed this charge roll
	last_processed_charge_roll = {"unit_id": unit_id, "distance": distance}

	# Update dice log...

	# ❌ BUG: Uses local UI variable selected_targets
	# Defending player never selected targets, so this is empty for them!
	var success = _is_charge_successful(unit_id, distance, selected_targets)

	if success:
		# Show success message
		awaiting_movement = true
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Success! Rolled %d\" - Click models to move them..." % distance
		# ... enable movement
	else:
		# Show failure message
		awaiting_movement = false
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Failed! Rolled %d\" - not enough to reach target" % distance
		# ... reset selection
```

#### 2. ChargeController.gd - _on_dice_rolled() (THE BUG LOCATION #2)
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd`
**Lines**: 1584-1646

```gdscript
func _on_dice_rolled(dice_data: Dictionary) -> void:
	"""Handle dice_rolled signal from ChargePhase - critical for multiplayer sync"""
	if not is_instance_valid(dice_log_display):
		return

	print("ChargeController: _on_dice_rolled called with data: ", dice_data)

	# Extract dice data
	var context = dice_data.get("context", "")
	var unit_id = dice_data.get("unit_id", "")
	var unit_name = dice_data.get("unit_name", unit_id)
	var rolls = dice_data.get("rolls", [])
	var total = dice_data.get("total", 0)

	# Only process charge rolls
	if context != "charge_roll" or rolls.size() != 2:
		return

	# Check if already processed (prevent duplicate on host)
	if last_processed_charge_roll.get("unit_id", "") == unit_id and last_processed_charge_roll.get("distance", -1) == total:
		print("ChargeController: Skipping duplicate charge roll processing")
		return

	# Format and display charge roll
	if true:
		var dice_text = "[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
			unit_name, total, rolls[0], rolls[1]
		]
		dice_log_display.append_text(dice_text)

		# Apply the same success/failure logic as _on_charge_roll_made
		charge_distance = total
		awaiting_roll = false

		# ❌ BUG: Uses local UI variable selected_targets
		# Same issue as _on_charge_roll_made!
		var success = _is_charge_successful(unit_id, total, selected_targets)

		if success:
			# Show success message and enable movement
			awaiting_movement = true
			# ... (same as _on_charge_roll_made)
		else:
			# Show failure message
			awaiting_movement = false
			# ... (same as _on_charge_roll_made)

		_update_button_states()
```

#### 3. ChargeController.gd - _is_charge_successful()
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd`
**Lines**: 1736-1782

```gdscript
func _is_charge_successful(unit_id: String, rolled_distance: int, target_ids: Array) -> bool:
	# Check if at least one model can reach engagement range (1") of any target
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return false

	var rolled_px = Measurement.inches_to_px(rolled_distance)
	var engagement_px = Measurement.inches_to_px(1.0)  # 1" engagement range

	# Check each model in the charging unit
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue

		var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))

		# ❌ BUG: If target_ids is empty, this loop never executes!
		# Defending player has empty target_ids, so function always returns false
		for target_id in target_ids:
			var target = GameState.get_unit(target_id)
			if target.is_empty():
				continue

			# Find closest enemy model
			for target_model in target.get("models", []):
				if not target_model.get("alive", true):
					continue

				var target_pos = _get_model_position(target_model)
				if target_pos == null:
					continue

				var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))

				# Calculate edge-to-edge distance
				var edge_distance = model_pos.distance_to(target_pos) - model_radius - target_radius

				# Check if this model could reach engagement range with the rolled distance
				if edge_distance - engagement_px <= rolled_px:
					print("Charge successful: Model can reach engagement range with roll of ", rolled_distance)
					return true

	print("Charge failed: No models can reach engagement range with roll of ", rolled_distance)
	return false
```

**The Logic is Sound**: The function correctly calculates distances and determines success. The problem is the **empty target_ids array** passed by the defending player.

#### 4. ChargePhase.gd - pending_charges Structure (THE SOLUTION SOURCE)
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/ChargePhase.gd`
**Lines**: 21-22, 256-282

```gdscript
# Charge state tracking
var pending_charges: Dictionary = {}    # units awaiting resolution

func _process_declare_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var target_ids = action.get("payload", {}).get("target_unit_ids", [])

	# ✅ Store charge declaration WITH TARGETS
	# This data is synced across all clients via game state!
	pending_charges[unit_id] = {
		"targets": target_ids,  # ← THE SOLUTION: Get targets from here!
		"declared_at": Time.get_unix_time_from_system()
	}

	# Get eligible targets for UI
	var eligible_targets = _get_eligible_targets_for_unit(unit_id)

	emit_signal("unit_selected_for_charge", unit_id)
	emit_signal("targets_declared", unit_id, target_ids)
	emit_signal("charge_targets_available", unit_id, eligible_targets)

	# ... logging ...

	return create_result(true, [])
```

**Lines**: 886-888, 910-913 - Accessor methods

```gdscript
func get_pending_charges() -> Dictionary:
	return pending_charges

# ... other methods ...

func get_charge_distance(unit_id: String) -> int:
	if pending_charges.has(unit_id) and pending_charges[unit_id].has("distance"):
		return pending_charges[unit_id].distance
	return 0
```

### Why Active Player Works But Defending Player Fails

**Active Player Flow**:
```
1. User selects targets in UI
   → selected_targets = [target1, target2, ...]  (LOCAL)

2. Clicks "Declare Charge"
   → Sends DECLARE_CHARGE action with target_ids

3. Phase stores: pending_charges[unit_id] = {"targets": [t1, t2], ...}  (SYNCED)

4. Clicks "Roll 2D6"
   → Rolls dice, emits signals

5. Receives charge_roll_made signal
   → Calls _is_charge_successful(unit_id, distance, selected_targets)
   → selected_targets is NOT EMPTY ✅
   → Function correctly checks distances
   → Returns true/false based on actual distances
   → Shows correct feedback
```

**Defending Player Flow**:
```
1. NEVER selects targets (not their turn)
   → selected_targets = []  (EMPTY LOCAL VARIABLE)

2. Receives DECLARE_CHARGE action via network
   → Phase stores: pending_charges[unit_id] = {"targets": [t1, t2], ...}  (SYNCED)
   → BUT ChargeController.selected_targets stays EMPTY!

3. Receives CHARGE_ROLL action via network
   → Rolls dice, emits signals

4. Receives dice_rolled signal
   → Calls _is_charge_successful(unit_id, distance, selected_targets)
   → selected_targets is EMPTY ❌
   → target_ids loop never executes
   → Always returns false
   → Always shows "Charge failed" message ❌
```

## Implementation Plan

### Task 1: Add Helper Method to Get Targets from Phase
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd`
**Location**: Add after line 1782 (after `_is_charge_successful`)

**Rationale**: Create a clean method to retrieve targets from the synced phase data instead of local UI state.

```gdscript
func _get_charge_targets_from_phase(unit_id: String) -> Array:
	"""Get the declared charge targets from ChargePhase's synced game state.

	This ensures both charging and defending players use the same target list
	when determining charge success, fixing the bug where defending players
	always see "charge failed" due to empty local selected_targets.
	"""
	if not current_phase:
		print("WARNING: No current_phase available to get charge targets")
		return []

	if not current_phase.has_method("get_pending_charges"):
		print("ERROR: current_phase doesn't have get_pending_charges method")
		return []

	var pending = current_phase.get_pending_charges()
	if not pending.has(unit_id):
		print("WARNING: No pending charge found for unit ", unit_id)
		return []

	var charge_data = pending[unit_id]
	var targets = charge_data.get("targets", [])

	print("Retrieved ", targets.size(), " targets from phase for unit ", unit_id, ": ", targets)
	return targets
```

### Task 2: Fix _on_charge_roll_made() to Use Phase Targets
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd`
**Location**: Line 1558

**Change**: Replace local UI variable with synced phase data

```gdscript
# BEFORE (line 1558 - BROKEN)
var success = _is_charge_successful(unit_id, distance, selected_targets)

# AFTER (line 1558 - FIXED)
var targets = _get_charge_targets_from_phase(unit_id)
var success = _is_charge_successful(unit_id, distance, targets)
```

**Rationale**:
- Gets targets from phase's `pending_charges` which is synced across all clients
- Both charging and defending players now use the same target list
- Maintains existing success checking logic - just fixes the input data

### Task 3: Fix _on_dice_rolled() to Use Phase Targets
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd`
**Location**: Line 1622

**Change**: Same fix as Task 2, but in the duplicate logic path

```gdscript
# BEFORE (line 1622 - BROKEN)
var success = _is_charge_successful(unit_id, total, selected_targets)

# AFTER (line 1622 - FIXED)
var targets = _get_charge_targets_from_phase(unit_id)
var success = _is_charge_successful(unit_id, total, targets)
```

**Rationale**:
- `_on_dice_rolled` is called for clients in multiplayer mode
- `_on_charge_roll_made` is called for host
- Both need the same fix to ensure consistent behavior

### Task 4: Verify No Other Uses of Local selected_targets for Game Logic
**Purpose**: Ensure we haven't missed any other places where local UI state affects game logic

**Search for**: `selected_targets` in ChargeController.gd

**Expected Results**:
- UI updates (line 1360, 1516, 1520, etc.) - OK, these are local UI only
- Visual updates (line 1661-1676) - OK, local visuals only
- Button state updates (line 514) - OK, UI control only
- **Only the two fixed locations should affect success determination**

## Testing Strategy

### Pre-Fix Validation (Reproduce the Bug)

1. **Start multiplayer game** with two players (host and client)
2. **Progress to Charge Phase** (complete Deployment, Movement, Shooting)
3. **Host declares charge**:
   - Select a unit
   - Select a target within 12"
   - Click "Declare Charge"
   - Click "Roll 2D6"

4. **Observe host sees**:
   ```
   "Success! Rolled 9\" - Click models to move them into engagement..."
   ```

5. **Observe client (defender) sees**:
   ```
   "Failed! Rolled 9\" - not enough to reach target"
   ```

6. **Confirm bug**: Same roll, different feedback messages

### Post-Fix Validation

#### Test 1: Successful Charge - Both Players See Success

1. Start multiplayer game (host + client)
2. Host charges a nearby enemy unit
3. Roll high enough to reach (e.g., 9" when target is 8" away)
4. **Verify Host sees**: "Success! Rolled 9\" - Click models to move..."
5. **Verify Client sees**: "Success! Rolled 9\" - Click models to move..." (NOT "Failed!")
6. **Verify**: Same message on both clients

#### Test 2: Failed Charge - Both Players See Failure

1. Start multiplayer game (host + client)
2. Host charges a distant enemy unit
3. Roll too low to reach (e.g., 4" when target is 10" away)
4. **Verify Host sees**: "Failed! Rolled 4\" - not enough to reach target"
5. **Verify Client sees**: "Failed! Rolled 4\" - not enough to reach target"
6. **Verify**: Same message on both clients

#### Test 3: Edge Case - Just Enough Distance

1. Start multiplayer game
2. Host charges enemy unit at exactly 7" away
3. Roll exactly 7" (both dice showing 3 and 4, or 2 and 5, etc.)
4. **Verify**: Both players see success (7" roll can reach 7" + 1" engagement = 8" total)
5. **Verify**: Consistent feedback on both clients

#### Test 4: Multiple Targets

1. Start multiplayer game
2. Host declares charge against TWO enemy units
3. Roll charge distance
4. **Verify**: Both players see correct success/failure
5. **Verify**: Success determined by ability to reach ANY declared target

### Manual Testing Procedure

```bash
# 1. Start Godot with multiplayer enabled
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# 2. Launch host instance
# Host: Click "Host Game" in main menu
# Load armies and start game

# 3. Launch client instance (separate terminal or machine)
# Client: Click "Join Game" with host IP
# Load army and join game

# 4. Progress to CHARGE phase
# Host: End Deployment → End Command → End Movement → End Shooting → CHARGE

# 5. Test charge scenarios
# Host: Select unit → Select target → Declare Charge → Roll 2D6

# 6. Compare feedback on both screens
# BEFORE FIX: Different messages
# AFTER FIX: Identical messages

# 7. Check debug logs for both instances
# Look for:
#   - "Retrieved X targets from phase for unit..."  (NEW LOG)
#   - "Charge successful: Model can reach..."  (Should match on both)
#   - "Charge failed: No models can reach..." (Should match on both)
```

### Debug Log Validation

After fix, logs should show on BOTH clients:

```
ChargeController: _on_dice_rolled called with data: {...}
Retrieved 1 targets from phase for unit U_WARBOSS: ["U_INTERCESSOR_SQUAD"]
Charge successful: Model can reach engagement range with roll of 9
ChargeController: Added dice roll to display: Charge Roll: Warboss rolled 2D6 = 9 (4 + 5)
```

Or for failures:

```
ChargeController: _on_dice_rolled called with data: {...}
Retrieved 1 targets from phase for unit U_WARBOSS: ["U_INTERCESSOR_SQUAD"]
Charge failed: No models can reach engagement range with roll of 4
ChargeController: Added dice roll to display: Charge Roll: Warboss rolled 2D6 = 4 (2 + 2)
```

**Key Point**: The "Retrieved X targets" log should appear on BOTH host and client, with the same target list.

### Regression Testing

- ✅ Single-player charge success/failure feedback continues working
- ✅ Host player charge feedback continues working
- ✅ Charge movement and completion work correctly
- ✅ Other charge actions (DECLARE_CHARGE, SKIP_CHARGE) unaffected
- ✅ Other phases (Movement, Shooting, Fight) unaffected
- ✅ UI target selection continues working for active player

## Quality Validation Gates

### Code Quality Checks

```bash
# Run from project root
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# 1. Verify new method exists
grep -n "_get_charge_targets_from_phase" scripts/ChargeController.gd

# 2. Verify both call sites updated
grep -n "_is_charge_successful.*_get_charge_targets_from_phase" scripts/ChargeController.gd

# 3. Verify no remaining direct uses of selected_targets for game logic
# (Should only show UI-related uses)
grep -n "selected_targets" scripts/ChargeController.gd | grep -v "selected_targets ="
```

### Integration Testing

1. **Multiplayer Sync**: Verify both host and client see identical feedback
2. **State Consistency**: Confirm charge phase state matches on all clients
3. **UI Synchronization**: Ensure charge info labels show same text
4. **Dice Log Consistency**: Check dice log display matches on both instances

### Godot Runtime Testing

```bash
# Start Godot with logging
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2
godot --path 40k

# Look for debug output in:
# - Godot console (immediate)
# - Log file: ~/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log
```

## Success Criteria

### Functional Requirements
✅ Charge success feedback is identical for both charging and defending players
✅ Successful charges show "Success!" message on ALL clients
✅ Failed charges show "Failed!" message on ALL clients
✅ Defending player sees accurate feedback matching actual game state
✅ Charge movement only enabled when actually successful
✅ No "ghost charges" where defender thinks it failed but attacker proceeds

### Technical Requirements
✅ ChargeController uses synced phase data instead of local UI state for game logic
✅ `_get_charge_targets_from_phase()` correctly retrieves targets from pending_charges
✅ Both `_on_charge_roll_made()` and `_on_dice_rolled()` use the new method
✅ `_is_charge_successful()` receives correct target list on all clients
✅ No regression in single-player mode
✅ No regression in other game phases

### Network Requirements (Multiplayer Specific)
✅ Host and client use identical target data for success determination
✅ pending_charges data syncs correctly across all clients
✅ Charge feedback messages match on all clients
✅ Dice rolls and success determination are deterministic across network
✅ No race conditions or timing issues in signal handling

## Implementation Notes

### Critical Files to Modify
1. **ChargeController.gd:1558** - Fix _on_charge_roll_made() (HIGHEST PRIORITY)
2. **ChargeController.gd:1622** - Fix _on_dice_rolled() (HIGHEST PRIORITY)
3. **ChargeController.gd:~1783** - Add _get_charge_targets_from_phase() helper (NEW METHOD)

### Code Conventions to Follow
- Follow existing function naming pattern: `_get_*_from_phase()`
- Add comprehensive docstring explaining WHY this method exists (the bug it fixes)
- Include debug logging to help diagnose future issues
- Use same null-checking patterns as other helper methods
- Return empty array on error (safe default that doesn't crash)

### Potential Gotchas
- **Timing**: Ensure pending_charges is populated before _on_dice_rolled fires
  - Solution: DECLARE_CHARGE always happens before CHARGE_ROLL, so data will be there
- **Network Lag**: Ensure phase data syncs before dice roll signal
  - Solution: Godot's signal system is synchronous within a client
- **Edge Case**: What if pending_charges is missing for a unit?
  - Solution: Return empty array, function returns false (safe fallback)
- **Multiple Rolls**: Ensure we don't use stale target data
  - Solution: pending_charges is updated for each new charge declaration

### Why This is a 9/10 Score
1. **Root Cause Identified**: Clear understanding of local vs synced state issue
2. **Minimal Code Changes**: Add one method, change two lines
3. **No Side Effects**: Only affects success determination, not UI or other logic
4. **Comprehensive Context**: Full signal flow and data structures documented
5. **Easy Validation**: Immediate visual feedback when working
6. **Follows Patterns**: Uses existing `get_pending_charges()` accessor
7. **Well-Tested Codebase**: Similar patterns used in other controllers
8. **-1 Point**: Slight complexity in multiplayer sync timing (need to verify)

## Related Documentation

### Godot Networking
- https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- Signal synchronization across clients
- RPCs and state replication patterns

### Game Architecture References
- **ChargePhase.gd**: Lines 256-282 - Charge declaration storage
- **ChargePhase.gd**: Lines 886-888 - pending_charges accessor method
- **ChargeController.gd**: Lines 1736-1782 - Charge success calculation logic
- **ChargeController.gd**: Lines 405-430 - Phase setup and signal connections
- **MovementPhase.gd**: Similar patterns for movement state synchronization

### Similar Patterns in Codebase
- **MovementController**: Uses phase data for movement validation
- **ShootingController**: Uses phase data for target tracking
- **Pattern**: Controllers should use phase state for game logic, local state for UI only

### Warhammer 40k Charge Rules
- https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Charge-Phase
- Charge range: 12" maximum
- Engagement range: 1" (models must get within 1" of enemy)
- Success: Any model can reach engagement range with rolled distance

**Final Score: 9/10** - Clear fix with comprehensive documentation and very high confidence for one-pass implementation success. Minor deduction for multiplayer timing complexity that requires validation.
