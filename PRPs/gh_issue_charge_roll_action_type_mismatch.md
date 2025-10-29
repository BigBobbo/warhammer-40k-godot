# Charge Roll Action Type Mismatch Fix PRP

## Overview

Fix the **charge roll action type mismatch** where Units declare a charge and click the button to roll 2D6, but no dice rolls are displayed and the action fails silently with "Unknown action type: CHARGE_ROLL". This affects both host and client in multiplayer mode and prevents the charge phase from progressing properly.

**Score: 10/10** - Simple naming mismatch with clear root cause, comprehensive context, and straightforward one-line fix for immediate success.

## Issue Context

**Problem Description**:
- User declares a charge successfully
- User clicks "Roll Charge" button to roll 2D6
- **BUG**: Nothing happens - no dice roll is shown, no UI update occurs
- Error in logs: "Unknown action type: CHARGE_ROLL"
- The action fails silently and charge cannot proceed

### Debug Evidence from User Report
```
NetworkManager: ⚠️ PHASE SYNC CHECK
NetworkManager: GameState.meta.phase: CHARGE
NetworkManager: PhaseManager instance script: res://phases/ChargePhase.gd
NetworkManager: Phase class: Node
NetworkManager: Phase has validate_action: true
NetworkManager: current_phase_instance = @Node@2125:<Node#735295048968>
NetworkManager: Calling phase.validate_action()
NetworkManager: Phase validation result = { "valid": true, "errors": [] }
NetworkManager: Validation result: { "valid": true, "errors": [] }
NetworkManager: Action VALIDATED, applying via GameManager
NetworkManager: Host applied client action, result.success = false
NetworkManager: GameManager returned failure: Unknown action type: CHARGE_ROLL
Requesting charge roll: { "type": "CHARGE_ROLL", "actor_unit_id": "U_WARBOSS_IN_MEGA_ARMOUR_D" }
Main: Received charge action request: CHARGE_ROLL
[NetworkIntegration] Using local player ID for action: peer=650382619 -> player=2
[NetworkIntegration] Routing action through NetworkManager: CHARGE_ROLL
NetworkManager: submit_action called for type: CHARGE_ROLL
NetworkManager: is_networked() = true
NetworkManager: Client mode - sending to host
Main: Charge action submitted to network
```

**Key Evidence**:
- Action validates successfully in ChargePhase
- GameManager rejects it with "Unknown action type: CHARGE_ROLL"
- This indicates a naming mismatch between sender and receiver

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

## Existing Codebase Analysis

### Root Cause: Action Type Naming Mismatch

**The Problem**: Two different action type names are used for the same action:
- **ChargeController & ChargePhase use**: `"CHARGE_ROLL"`
- **GameManager expects**: `"ROLL_CHARGE"`

This mismatch causes GameManager to reject the action in multiplayer mode, breaking the signal chain and preventing dice display.

### Complete Action Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. USER INTERACTION                                                 │
│    ChargeController.gd:1301-1311                                    │
│    User clicks "Roll Charge" button                                 │
│    _on_roll_charge_pressed() creates action:                        │
│    { "type": "CHARGE_ROLL", "actor_unit_id": "..." }  ← SENDS THIS │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 2. SIGNAL EMISSION                                                  │
│    ChargeController.gd:1311                                         │
│    charge_action_requested.emit(action)                             │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 3. SIGNAL HANDLING                                                  │
│    Main.gd:2890 - _on_charge_action_requested(action)              │
│    Routes to NetworkIntegration.route_action(action)                │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 4. NETWORK ROUTING                                                  │
│    NetworkIntegration.gd:73-88                                      │
│    - Single-player: → PhaseManager → ChargePhase (WORKS)           │
│    - Multiplayer: → NetworkManager → GameManager (FAILS!)          │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 5. GAMEMANAGER PROCESSING (MULTIPLAYER ONLY)                       │
│    GameManager.gd:24-115 - process_action()                        │
│    Line 81-82: match action["type"]:                                │
│        "ROLL_CHARGE":  ← EXPECTS THIS (WRONG!)                     │
│            return process_roll_charge(action)                       │
│                                                                      │
│    ❌ ERROR: "CHARGE_ROLL" doesn't match "ROLL_CHARGE"             │
│    Returns: {"success": false, "error": "Unknown action type"}     │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 6. WHAT SHOULD HAPPEN (IF FIX IS APPLIED)                          │
│    GameManager.gd:389-390 - process_roll_charge()                  │
│    Delegates to: _delegate_to_current_phase(action)                │
│                                                                      │
│    PhaseManager gets current_phase_instance (ChargePhase)           │
│    Calls: ChargePhase.execute_action(action)                       │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 7. CHARGE PHASE PROCESSING                                         │
│    ChargePhase.gd:83-102 - process_action()                        │
│    Line 91: "CHARGE_ROLL":  ← HANDLES THIS                         │
│        return _process_charge_roll(action)                          │
│                                                                      │
│    ChargePhase.gd:284-313 - _process_charge_roll()                 │
│    - Rolls 2D6 using RNGService                                     │
│    - Stores distance in pending_charges                             │
│    - Emits signals: charge_roll_made, dice_rolled                  │
│    - Returns success with dice data                                 │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 8. UI UPDATE                                                        │
│    ChargeController.gd:1536-1569 - _on_charge_roll_made()          │
│    - Updates dice_log_display with roll results                     │
│    - Shows: "[color=orange]Charge Roll:[/color] ... = X (Y + Z)"   │
│    - Checks if charge is successful                                 │
│    - Enables charge movement or shows failure message               │
└─────────────────────────────────────────────────────────────────────┘
```

### Key File Locations and Current State

#### 1. ChargeController.gd
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd`

**Line 1306**: Creates action with type **"CHARGE_ROLL"**
```gdscript
func _on_roll_charge_pressed() -> void:
    if active_unit_id == "":
        return

    var action = {
        "type": "CHARGE_ROLL",  # ← SENDS THIS
        "actor_unit_id": active_unit_id
    }

    print("Requesting charge roll: ", action)
    charge_action_requested.emit(action)
```

**Lines 1536-1569**: Handles charge_roll_made signal (never fires due to bug)
```gdscript
func _on_charge_roll_made(unit_id: String, distance: int, dice: Array) -> void:
    print("Charge roll made: ", unit_id, " rolled ", distance, " (", dice, ")")

    charge_distance = distance
    awaiting_roll = false

    # Update dice log
    var dice_text = "[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
        unit_id, distance, dice[0], dice[1]
    ]
    if is_instance_valid(dice_log_display):
        dice_log_display.append_text(dice_text)

    # ... success/failure handling
```

#### 2. ChargePhase.gd
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/ChargePhase.gd`

**Lines 70, 91**: Validates and processes **"CHARGE_ROLL"**
```gdscript
func validate_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    match action_type:
        "SELECT_CHARGE_UNIT":
            return _validate_select_charge_unit(action)
        "DECLARE_CHARGE":
            return _validate_declare_charge(action)
        "CHARGE_ROLL":  # ← EXPECTS THIS
            return _validate_charge_roll(action)
        # ...

func process_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    match action_type:
        # ...
        "CHARGE_ROLL":  # ← PROCESSES THIS
            return _process_charge_roll(action)
        # ...
```

**Lines 284-313**: Rolls dice and emits signals
```gdscript
func _process_charge_roll(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    var charge_data = pending_charges[unit_id]

    # Roll 2D6 for charge distance
    var rng = RulesEngine.RNGService.new()
    var rolls = rng.roll_d6(2)
    var total_distance = rolls[0] + rolls[1]

    # Store rolled distance
    charge_data.distance = total_distance
    charge_data.dice_rolls = rolls

    # Add to dice log
    var dice_result = {
        "context": "charge_roll",
        "unit_id": unit_id,
        "unit_name": get_unit(unit_id).get("meta", {}).get("name", unit_id),
        "rolls": rolls,
        "total": total_distance
    }
    dice_log.append(dice_result)

    emit_signal("charge_roll_made", unit_id, total_distance, rolls)
    emit_signal("charge_path_tools_enabled", unit_id, total_distance)
    emit_signal("dice_rolled", dice_result)

    log_phase_message("Charge roll: 2D6 = %d (%d + %d)" % [total_distance, rolls[0], rolls[1]])

    return create_result(true, [], "", {"dice": [dice_result]})
```

#### 3. GameManager.gd (THE BUG LOCATION)
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameManager.gd`

**Lines 78-84**: Charge action registration (CONTAINS THE BUG)
```gdscript
func process_action(action: Dictionary) -> Dictionary:
    match action["type"]:
        # ... other actions ...

        # Charge actions
        "DECLARE_CHARGE":
            return process_declare_charge(action)
        "ROLL_CHARGE":  # ← BUG: EXPECTS THIS (WRONG NAME!)
            return process_roll_charge(action)
        "END_CHARGE":
            return process_end_charge(action)

        # ... other actions ...

        _:
            return {"success": false, "error": "Unknown action type: " + str(action.get("type", "UNKNOWN"))}
```

**Lines 389-390**: Delegates to ChargePhase
```gdscript
func process_roll_charge(action: Dictionary) -> Dictionary:
    return _delegate_to_current_phase(action)
```

### Why Single-Player Works But Multiplayer Fails

**Single-Player Flow**:
```
NetworkIntegration.route_action()
  ↓
is_networked() = false
  ↓
PhaseManager.current_phase_instance.execute_action()
  ↓
ChargePhase.execute_action() → process_action()
  ↓
Handles "CHARGE_ROLL" ✅ WORKS
```

**Multiplayer Flow**:
```
NetworkIntegration.route_action()
  ↓
is_networked() = true
  ↓
NetworkManager.submit_action()
  ↓
GameManager.apply_action() → process_action()
  ↓
match "CHARGE_ROLL":  ← NOT FOUND!
  ↓
Default case: "Unknown action type" ❌ FAILS
```

### Other Missing Charge Actions in GameManager

These action types are handled by ChargePhase but NOT registered in GameManager:
- `SELECT_CHARGE_UNIT` (line 66)
- `APPLY_CHARGE_MOVE` (line 72)
- `COMPLETE_UNIT_CHARGE` (line 74)
- `SKIP_CHARGE` (line 76)

**Note**: All these actions also delegate to the current phase, so they should work once the naming is consistent. However, they're likely not reaching GameManager due to different routing paths.

## Implementation Plan

### Task 1: Fix Action Type Name in GameManager (CRITICAL FIX)
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameManager.gd`
**Location**: Line 81
**Change**: Rename `"ROLL_CHARGE"` to `"CHARGE_ROLL"`

```gdscript
# BEFORE (line 81 - BROKEN)
"ROLL_CHARGE":
    return process_roll_charge(action)

# AFTER (line 81 - FIXED)
"CHARGE_ROLL":
    return process_roll_charge(action)
```

**Rationale**:
- ChargeController and ChargePhase both use "CHARGE_ROLL"
- GameManager should match the existing naming convention
- One-line change with zero side effects
- Maintains consistency with other phases (e.g., ShootingPhase uses verb_noun pattern)

### Task 2: Add Missing Charge Action Types to GameManager (RECOMMENDED)
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameManager.gd`
**Location**: Lines 78-84 (in the match statement)

Add the missing action types that ChargePhase handles:

```gdscript
# Charge actions (ENHANCED)
"SELECT_CHARGE_UNIT":
    return _delegate_to_current_phase(action)
"DECLARE_CHARGE":
    return process_declare_charge(action)
"CHARGE_ROLL":  # ← FIXED NAME
    return process_roll_charge(action)
"APPLY_CHARGE_MOVE":
    return _delegate_to_current_phase(action)
"COMPLETE_UNIT_CHARGE":
    return _delegate_to_current_phase(action)
"SKIP_CHARGE":
    return _delegate_to_current_phase(action)
"END_CHARGE":
    return process_end_charge(action)
```

**Rationale**:
- Ensures all charge actions work in multiplayer mode
- Follows the pattern used by MovementPhase and ShootingPhase
- Uses delegation for actions that modify phase-local state
- Prevents future "Unknown action type" errors

### Task 3: Verify Signal Chain in Multiplayer (VALIDATION)
**File**: Test in running game
**Purpose**: Ensure dice_rolled signal propagates to both host and client

**Test Steps**:
1. Start multiplayer game (host + client)
2. Enter charge phase
3. Declare charge
4. Click "Roll Charge" button
5. Verify both host AND client see dice results
6. Check that ChargeController._on_charge_roll_made() fires on both instances

**Expected Behavior**:
- Host rolls dice (RNG on host side)
- GameManager.apply_result() includes dice data in result
- NetworkManager re-emits dice_rolled signal to client
- Both host and client see identical dice results in UI

## Testing Strategy

### Pre-Fix Validation
1. Run multiplayer game
2. Try to roll charge
3. Confirm error: "Unknown action type: CHARGE_ROLL"
4. Verify no dice are displayed

### Post-Fix Validation
1. Apply fix to GameManager.gd line 81
2. Run multiplayer game with host and client
3. Declare charge for a unit
4. Click "Roll Charge" button
5. **Verify**: Dice roll appears in both host and client UI
6. **Verify**: Charge distance is set correctly
7. **Verify**: Can proceed with charge movement
8. **Verify**: No errors in logs

### Manual Testing Procedure
```bash
# 1. Start Godot with multiplayer enabled
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# 2. Launch two instances (or use network test mode)
# Host: Click "Host Game" in main menu
# Client: Click "Join Game" with host IP

# 3. Load armies and start game
# Both players should see DEPLOYMENT phase

# 4. Progress to CHARGE phase
# Host: End Deployment → End Command → End Movement → End Shooting → CHARGE

# 5. Test charge roll
# Host: Select unit → Declare charge → Click "Roll Charge"
# EXPECTED: Dice results show on BOTH host and client screens

# 6. Verify dice synchronization
# Both players should see identical dice values (e.g., "Rolled 9 (4 + 5)")

# 7. Check logs for success
# Look for:
#   - "GameManager: Setting units.X.Y.Z = ..."
#   - "ChargePhase: Charge roll: 2D6 = X (Y + Z)"
#   - NO "Unknown action type: CHARGE_ROLL" errors
```

### Debug Log Validation
After fix, logs should show:
```
NetworkManager: submit_action called for type: CHARGE_ROLL
NetworkManager: is_networked() = true
NetworkManager: Host mode - validating and applying
NetworkManager: Phase validation result = { "valid": true, "errors": [] }
GameManager: Delegating CHARGE_ROLL to current phase  ← NEW LINE
ChargePhase: Rolling 2D6 for charge
ChargePhase: Rolled 9 (4 + 5)
ChargePhase: Emitting charge_roll_made signal
ChargeController: Charge roll made: U_XXX rolled 9 ([4, 5])
ChargeController: Updating dice log display
```

### Regression Testing
- ✅ Single-player charge rolls continue working
- ✅ Other charge actions (DECLARE_CHARGE, END_CHARGE) still work
- ✅ Charge movement and completion work correctly
- ✅ Other phases (Movement, Shooting, Fight) unaffected
- ✅ Deployment and scoring phases unaffected

## Quality Validation Gates

### Code Quality Checks
```bash
# Run from project root
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# 1. Verify syntax
grep -n "CHARGE_ROLL" autoloads/GameManager.gd
grep -n "ROLL_CHARGE" autoloads/GameManager.gd  # Should return 0 results after fix

# 2. Verify all charge actions are registered
grep -A 20 "# Charge actions" autoloads/GameManager.gd

# 3. Test game loads without errors
# Launch Godot and check console for startup errors
```

### Integration Testing
1. **Multiplayer Sync**: Verify both host and client see dice rolls
2. **State Persistence**: Confirm charge distance is stored correctly
3. **UI Synchronization**: Ensure dice log updates on both instances
4. **Action Flow**: Test complete charge sequence from declaration to movement

## Additional Charge Actions Analysis

### Currently Missing from GameManager

Based on ChargePhase.gd lines 65-79, these actions exist but aren't in GameManager:

1. **SELECT_CHARGE_UNIT** (line 66)
   - Used to mark a unit as actively charging
   - Should delegate to phase

2. **APPLY_CHARGE_MOVE** (line 72)
   - Applies the final charge movement
   - Should delegate to phase (contains validation logic)

3. **COMPLETE_UNIT_CHARGE** (line 74)
   - Marks charge as complete and allows selecting next unit
   - Should delegate to phase

4. **SKIP_CHARGE** (line 76)
   - Allows player to skip charging with a unit
   - Should delegate to phase

**Impact**: If these actions are used in multiplayer, they will also fail with "Unknown action type". Adding them now prevents future bugs.

## Success Criteria

### Functional Requirements
✅ Charge rolls display dice results in both host and client UI
✅ Dice values are synchronized across multiplayer instances
✅ Charge distance is set correctly after roll
✅ Players can proceed with charge movement after successful roll
✅ Failed charges show appropriate feedback message
✅ No "Unknown action type" errors in multiplayer mode

### Technical Requirements
✅ GameManager.gd uses "CHARGE_ROLL" to match ChargePhase and ChargeController
✅ All charge action types registered in GameManager match statement
✅ Signal chain (charge_roll_made, dice_rolled) fires correctly in multiplayer
✅ NetworkManager propagates dice data to all clients
✅ No regression in single-player mode
✅ No regression in other game phases

### Network Requirements (Multiplayer Specific)
✅ Host validates and processes charge roll
✅ Client receives dice results via network sync
✅ Both host and client update UI identically
✅ RNG determinism maintained (host-side rolls)
✅ Action validation works on both host and client

## Implementation Notes

### Critical Files to Modify
1. **GameManager.gd:81** - Change "ROLL_CHARGE" to "CHARGE_ROLL" (HIGHEST PRIORITY)
2. **GameManager.gd:78-84** - Add missing charge action types (RECOMMENDED)

### Code Conventions to Follow
- Match existing action naming pattern: `VERB_NOUN` (e.g., "CHARGE_ROLL", "DECLARE_CHARGE")
- Use `_delegate_to_current_phase()` for phase-specific actions
- Maintain alphabetical or logical grouping in match statement
- Follow existing comment style for action groups

### Potential Gotchas
- **Action Type Consistency**: Ensure all references use "CHARGE_ROLL" not "ROLL_CHARGE"
- **Network Sync**: Verify dice results sync properly in multiplayer
- **Signal Timing**: Ensure dice_rolled signal fires before UI tries to read results
- **RNG Determinism**: Confirm rolls happen on host side only to maintain consistency

### Why This is a 10/10 Score
1. **Root Cause Crystal Clear**: Simple typo/naming mismatch
2. **One-Line Fix**: Change line 81 in GameManager.gd
3. **Zero Side Effects**: No logic changes, just name alignment
4. **Comprehensive Context**: Full signal flow documented
5. **Easy Validation**: Immediate visual feedback when working
6. **No Dependencies**: Fix is self-contained
7. **Follows Existing Patterns**: Matches other phase action handling
8. **Well-Tested Codebase**: Charge system works in single-player (validation that logic is sound)

## Related Documentation

### Godot Networking
- https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- RPC and signal synchronization patterns

### Game Architecture References
- **BasePhase.gd**: Lines 78-109 - execute_action() and process_action() pattern
- **MovementPhase.gd**: Similar delegation pattern for movement actions
- **ShootingPhase.gd**: Example of phase with multiple delegated actions
- **NetworkManager.gd**: Lines 108-194 - Action submission and validation flow

### Warhammer 40k Charge Rules
- https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Charge-Phase
- Charge declaration, rolling, and movement rules

**Final Score: 10/10** - Trivial fix with comprehensive documentation and guaranteed one-pass implementation success.
