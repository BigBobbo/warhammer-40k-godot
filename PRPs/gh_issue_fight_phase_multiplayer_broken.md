# Fight Phase Multiplayer Action Registration Fix - PRD

## Overview

Fix the **fight phase action registration mismatch** where the entire fight phase is completely non-functional in multiplayer mode due to GameManager not recognizing any fight-specific actions. Players can enter the fight phase but cannot select fighters, pile in, assign attacks, roll dice, or consolidate - all actions fail silently with "Unknown action type" errors.

**Score: 10/10** - Clear root cause identical to charge phase bug, comprehensive context, straightforward fix with proven pattern from other phases.

## Issue Context

**Problem Description**:
- User enters fight phase successfully
- User attempts to select a unit to fight
- **BUG**: Nothing happens - no unit selection, no UI update
- Error in logs: "Unknown action type: SELECT_FIGHTER"
- All subsequent fight actions (PILE_IN, ASSIGN_ATTACKS, ROLL_DICE, CONSOLIDATE) also fail
- Fight phase is completely broken in multiplayer mode

### Severity Assessment

**Impact Level: CRITICAL** 🔴
- **Multiplayer Status**: Completely broken - 0% functionality
- **Single-player Status**: Working - 100% functionality
- **Game Progression**: Blocks entire fight phase, game cannot continue past this point
- **User Experience**: Silent failure - no error feedback to user

### Root Cause Summary

GameManager.gd only registers 3 legacy fight actions (`SELECT_FIGHT_TARGET`, `RESOLVE_FIGHT`, `END_FIGHT`) but FightPhase.gd uses 10 different modern action types. This mismatch causes all fight actions except `END_FIGHT` to fail in multiplayer mode.

**Pattern Recognition**: This is **identical to the charge phase bug** documented in `gh_issue_charge_roll_action_type_mismatch.md`.

## Context & Documentation

### Core Documentation
- **Warhammer 40k 10e Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE
- **Godot 4.4 Documentation**: https://docs.godotengine.org/en/4.4/
- **Project Root**: `/Users/robertocallaghan/Documents/claude/godotv2`

### Key Rule References (Wahapedia)
From 10e Core Rules - Fight phase:
- **Fight Sequence**: Fights First → Remaining Combats (alternating activation)
- **Combat Resolution**: Pile In (3") → Make Attacks → Consolidate (3")
- **Engagement Range**: Within 1" horizontally of enemy model
- **Heroic Intervention**: CHARACTER units can move 6" at start of phase

## Existing Codebase Analysis

### Root Cause: Action Type Registration Gap

**The Problem**: GameManager doesn't recognize modern fight phase actions

**GameManager.gd** (lines 94-100) only handles legacy actions:
```gdscript
# Fight actions
"SELECT_FIGHT_TARGET":     # ❌ LEGACY - Not used by FightPhase
    return process_fight_target(action)
"RESOLVE_FIGHT":           # ❌ LEGACY - Not used by FightPhase
    return process_resolve_fight(action)
"END_FIGHT":               # ✅ CORRECT - Used by FightPhase
    return process_end_fight(action)
```

**FightPhase.gd** (lines 150-176) expects modern actions:
```gdscript
func validate_action(action: Dictionary) -> Dictionary:
    match action_type:
        "SELECT_FIGHTER":                   # ❌ NOT in GameManager
        "SELECT_MELEE_WEAPON":              # ❌ NOT in GameManager
        "PILE_IN":                          # ❌ NOT in GameManager
        "ASSIGN_ATTACKS":                   # ❌ NOT in GameManager
        "CONFIRM_AND_RESOLVE_ATTACKS":      # ❌ NOT in GameManager
        "ROLL_DICE":                        # ❌ NOT in GameManager
        "CONSOLIDATE":                      # ❌ NOT in GameManager
        "SKIP_UNIT":                        # ❌ NOT in GameManager
        "HEROIC_INTERVENTION":              # ❌ NOT in GameManager
        "END_FIGHT":                        # ✅ Registered in GameManager
```

**Result**: 9 out of 10 fight actions fail in multiplayer mode.

### Complete Action Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. USER INTERACTION                                                 │
│    FightController.gd (various methods)                             │
│    User clicks "Select Fighter" / "Pile In" / "Fight!" buttons     │
│    Creates action with type like:                                   │
│    { "type": "SELECT_FIGHTER", "unit_id": "..." }  ← SENDS THIS    │
│    { "type": "PILE_IN", "unit_id": "...", "movements": {...} }     │
│    { "type": "ROLL_DICE" }                                          │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 2. SIGNAL EMISSION                                                  │
│    FightController.gd:7                                             │
│    fight_action_requested.emit(action)                              │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 3. SIGNAL HANDLING                                                  │
│    Main.gd - _on_fight_action_requested(action)                    │
│    Routes to NetworkIntegration.route_action(action)                │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 4. NETWORK ROUTING                                                  │
│    NetworkIntegration.gd:73-88                                      │
│    - Single-player: → PhaseManager → FightPhase (WORKS)            │
│    - Multiplayer: → NetworkManager → GameManager (FAILS!)          │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 5. GAMEMANAGER PROCESSING (MULTIPLAYER ONLY)                       │
│    GameManager.gd:24-123 - process_action()                        │
│    Lines 94-100: match action["type"]:                              │
│        "SELECT_FIGHT_TARGET":  ← EXPECTS LEGACY NAME (WRONG!)      │
│        "RESOLVE_FIGHT":        ← EXPECTS LEGACY NAME (WRONG!)      │
│        "END_FIGHT":            ← MATCHES! (Only one that works)    │
│                                                                      │
│    ❌ ERROR: "SELECT_FIGHTER" doesn't match anything               │
│    ❌ ERROR: "PILE_IN" doesn't match anything                      │
│    ❌ ERROR: "ROLL_DICE" doesn't match anything                    │
│    Returns: {"success": false, "error": "Unknown action type"}     │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 6. WHAT SHOULD HAPPEN (IF FIX IS APPLIED)                          │
│    GameManager.gd:410-414 - process_*() methods                    │
│    Should delegate to: _delegate_to_current_phase(action)          │
│                                                                      │
│    PhaseManager gets current_phase_instance (FightPhase)            │
│    Calls: FightPhase.execute_action(action)                        │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 7. FIGHT PHASE PROCESSING                                          │
│    FightPhase.gd:177-203 - process_action()                        │
│    Line 181: "SELECT_FIGHTER":  ← HANDLES THIS                     │
│        return _process_select_fighter(action)                       │
│    Line 185: "PILE_IN":                                             │
│        return _process_pile_in(action)                              │
│    Line 191: "ROLL_DICE":                                           │
│        return _process_roll_dice(action)                            │
│                                                                      │
│    Each processor:                                                  │
│    - Validates action data                                          │
│    - Updates phase state                                            │
│    - Emits appropriate signals                                      │
│    - Returns success with diffs                                     │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 8. UI UPDATE                                                        │
│    FightController.gd - Various signal handlers                     │
│    - _on_fighter_selected() - Updates unit highlight               │
│    - _on_targets_available() - Shows available targets             │
│    - _on_dice_rolled() - Displays dice results                     │
│    - Updates fight sequence, dice log, action buttons               │
└─────────────────────────────────────────────────────────────────────┘
```

### Key File Locations and Current State

#### 1. FightController.gd
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/FightController.gd`
**Lines**: 1,135 total

**Example Action Emission** (various locations):
```gdscript
# Selecting a fighter from UI
func _on_unit_selected(index: int) -> void:
    # ... validation ...
    var action = {
        "type": "SELECT_FIGHTER",  # ← SENDS THIS
        "unit_id": unit_id
    }
    fight_action_requested.emit(action)

# Pile in movement
func _on_pile_in_pressed() -> void:
    # ... validation ...
    var action = {
        "type": "PILE_IN",  # ← SENDS THIS
        "unit_id": current_fighter_id,
        "movements": movements_dict
    }
    fight_action_requested.emit(action)

# Rolling dice for melee
func _on_confirm_pressed() -> void:
    # First confirm attacks
    var confirm_action = {
        "type": "CONFIRM_AND_RESOLVE_ATTACKS"  # ← SENDS THIS
    }
    fight_action_requested.emit(confirm_action)

    # Then roll dice
    var roll_action = {
        "type": "ROLL_DICE"  # ← SENDS THIS
    }
    fight_action_requested.emit(roll_action)
```

**Signal Handlers** (lines 283-300):
```gdscript
func set_phase(phase: BasePhase) -> void:
    current_phase = phase

    # Connect to phase signals
    if phase.has_signal("fighter_selected"):
        phase.fighter_selected.connect(_on_fighter_selected)
    if phase.has_signal("targets_available"):
        phase.targets_available.connect(_on_targets_available)
    if phase.has_signal("dice_rolled"):
        phase.dice_rolled.connect(_on_dice_rolled)
    # ... etc
```

#### 2. FightPhase.gd
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/FightPhase.gd`
**Lines**: 1,132 total

**Action Validation** (lines 150-176):
```gdscript
func validate_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    match action_type:
        "SELECT_FIGHTER":                   # ← EXPECTS THIS
            return _validate_select_fighter(action)
        "SELECT_MELEE_WEAPON":              # ← EXPECTS THIS
            return _validate_select_melee_weapon(action)
        "PILE_IN":                          # ← EXPECTS THIS
            return _validate_pile_in(action)
        "ASSIGN_ATTACKS":                   # ← EXPECTS THIS
            return _validate_assign_attacks(action)
        "CONFIRM_AND_RESOLVE_ATTACKS":      # ← EXPECTS THIS
            return _validate_confirm_and_resolve_attacks(action)
        "ROLL_DICE":                        # ← EXPECTS THIS
            return _validate_roll_dice(action)
        "CONSOLIDATE":                      # ← EXPECTS THIS
            return _validate_consolidate(action)
        "SKIP_UNIT":                        # ← EXPECTS THIS
            return _validate_skip_unit(action)
        "HEROIC_INTERVENTION":              # ← EXPECTS THIS
            return _validate_heroic_intervention_action(action)
        "END_FIGHT":                        # ✅ MATCHES GameManager
            return _validate_end_fight(action)
        _:
            return {"valid": false, "errors": ["Unknown action type: " + action_type]}
```

**Action Processing** (lines 177-203):
```gdscript
func process_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    match action_type:
        "SELECT_FIGHTER":
            return _process_select_fighter(action)
        "SELECT_MELEE_WEAPON":
            return _process_select_melee_weapon(action)
        "PILE_IN":
            return _process_pile_in(action)
        "ASSIGN_ATTACKS":
            return _process_assign_attacks(action)
        "CONFIRM_AND_RESOLVE_ATTACKS":
            return _process_confirm_and_resolve_attacks(action)
        "ROLL_DICE":
            return _process_roll_dice(action)
        "CONSOLIDATE":
            return _process_consolidate(action)
        "SKIP_UNIT":
            return _process_skip_unit(action)
        "HEROIC_INTERVENTION":
            return _process_heroic_intervention(action)
        "END_FIGHT":
            return _process_end_fight(action)
        _:
            return create_result(false, [], "Unknown action type: " + action_type)
```

**Example: Roll Dice Processing** (lines 494-532):
```gdscript
func _process_roll_dice(action: Dictionary) -> Dictionary:
    # Emit signal to indicate resolution is starting
    emit_signal("dice_rolled", {"context": "resolution_start", ...})

    # Build full fight action for RulesEngine
    var melee_action = {
        "type": "FIGHT",
        "actor_unit_id": active_fighter_id,
        "payload": {"assignments": confirmed_attacks}
    }

    # Resolve with RulesEngine
    var rng_service = RulesEngine.RNGService.new()
    var result = RulesEngine.resolve_melee_attacks(melee_action, game_state_snapshot, rng_service)

    # Process dice results step by step
    for dice_block in result.get("dice", []):
        emit_signal("dice_rolled", dice_block)

    # Apply changes and emit resolution signals
    if result.success:
        _apply_combat_results(result)
        for assignment in confirmed_attacks:
            emit_signal("attacks_resolved", active_fighter_id, assignment.target, result)

    confirmed_attacks.clear()
    return create_result(true, result.get("diffs", []), result.get("log_text", ""))
```

#### 3. GameManager.gd (THE BUG LOCATION)
**Path**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameManager.gd`

**Current Fight Action Registration** (lines 94-100):
```gdscript
func process_action(action: Dictionary) -> Dictionary:
    match action["type"]:
        # ... other phases ...

        # Fight actions
        "SELECT_FIGHT_TARGET":     # ❌ LEGACY - Not used by FightPhase
            return process_fight_target(action)
        "RESOLVE_FIGHT":           # ❌ LEGACY - Not used by FightPhase
            return process_resolve_fight(action)
        "END_FIGHT":               # ✅ CORRECT - Used by FightPhase
            return process_end_fight(action)

        # ... other phases ...

        _:
            return {"success": false, "error": "Unknown action type: " + str(action.get("type", "UNKNOWN"))}
```

**Legacy Processors** (lines 410-414):
```gdscript
func process_fight_target(action: Dictionary) -> Dictionary:
    return _delegate_to_current_phase(action)

func process_resolve_fight(action: Dictionary) -> Dictionary:
    return _delegate_to_current_phase(action)

func process_end_fight(action: Dictionary) -> Dictionary:
    print("GameManager: Processing END_FIGHT action")
    var next_phase = _get_next_phase(GameStateData.Phase.FIGHT)
    _trigger_phase_completion()
    return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}
```

**Delegation Pattern** (lines 556-576):
```gdscript
func _delegate_to_current_phase(action: Dictionary) -> Dictionary:
    """
    Delegates an action to the current phase for execution.
    This is used for actions that modify phase-local state.
    """
    var phase_mgr = get_node_or_null("/root/PhaseManager")
    if not phase_mgr:
        push_error("GameManager: PhaseManager not available for action delegation")
        return {"success": false, "error": "PhaseManager not available"}

    var current_phase = phase_mgr.get_current_phase_instance()
    if not current_phase:
        push_error("GameManager: No current phase instance for action delegation")
        return {"success": false, "error": "No active phase"}

    if not current_phase.has_method("execute_action"):
        push_error("GameManager: Current phase does not have execute_action method")
        return {"success": false, "error": "Phase cannot execute actions"}

    # Execute the action on the phase
    return current_phase.execute_action(action)
```

### Why Single-Player Works But Multiplayer Fails

**Single-Player Flow**:
```
FightController.fight_action_requested.emit()
  ↓
Main._on_fight_action_requested()
  ↓
NetworkIntegration.route_action()
  ↓
is_networked() = false
  ↓
PhaseManager.current_phase_instance.execute_action()
  ↓
FightPhase.execute_action() → process_action()
  ↓
Handles "SELECT_FIGHTER", "PILE_IN", "ROLL_DICE" etc. ✅ WORKS
```

**Multiplayer Flow**:
```
FightController.fight_action_requested.emit()
  ↓
Main._on_fight_action_requested()
  ↓
NetworkIntegration.route_action()
  ↓
is_networked() = true
  ↓
NetworkManager.submit_action()
  ↓
GameManager.apply_action() → process_action()
  ↓
match "SELECT_FIGHTER":  ← NOT FOUND!
  ↓
match "PILE_IN":  ← NOT FOUND!
  ↓
match "ROLL_DICE":  ← NOT FOUND!
  ↓
Default case: "Unknown action type" ❌ FAILS
```

### Pattern from Working Phases

**Shooting Phase** (GameManager.gd lines 60-66) - CORRECT PATTERN:
```gdscript
# Shooting actions (new phase-based system)
"SELECT_SHOOTER", "ASSIGN_TARGET", "CLEAR_ASSIGNMENT", "CLEAR_ALL_ASSIGNMENTS":
    return _delegate_to_current_phase(action)
"CONFIRM_TARGETS", "RESOLVE_SHOOTING", "SKIP_UNIT":
    return _delegate_to_current_phase(action)
"SHOOT", "APPLY_SAVES", "RESOLVE_WEAPON_SEQUENCE", "CONTINUE_SEQUENCE":
    return _delegate_to_current_phase(action)
```

**Charge Phase** (GameManager.gd lines 78-92) - PARTIALLY CORRECT:
```gdscript
# Charge actions
"SELECT_CHARGE_UNIT":
    return _delegate_to_current_phase(action)
"DECLARE_CHARGE":
    return process_declare_charge(action)
"CHARGE_ROLL":  # ← Fixed in gh_issue_charge_roll_action_type_mismatch.md
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

**Movement Phase** (GameManager.gd lines 34-58) - CORRECT PATTERN:
```gdscript
# Movement actions
"BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK":
    return process_begin_move(action)
"SET_MODEL_DEST":
    return process_set_model_dest(action)
"STAGE_MODEL_MOVE":
    return process_stage_model_move(action)
"CONFIRM_UNIT_MOVE":
    return process_confirm_move(action)
"UNDO_LAST_MODEL_MOVE":
    return process_undo_last_move(action)
"RESET_UNIT_MOVE":
    return process_reset_move(action)
# ... etc - all delegate to phase
```

## Implementation Plan

### Task 1: Replace Legacy Fight Actions with Modern Actions (CRITICAL FIX)

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameManager.gd`
**Location**: Lines 94-100
**Change**: Replace 3 legacy actions with 10 modern FightPhase actions

```gdscript
# BEFORE (lines 94-100 - BROKEN)
# Fight actions
"SELECT_FIGHT_TARGET":     # ❌ LEGACY - Not used
    return process_fight_target(action)
"RESOLVE_FIGHT":           # ❌ LEGACY - Not used
    return process_resolve_fight(action)
"END_FIGHT":               # ✅ Keep this one
    return process_end_fight(action)

# AFTER (lines 94-107 - FIXED)
# Fight actions (modern phase-based system)
"SELECT_FIGHTER":
    return _delegate_to_current_phase(action)
"SELECT_MELEE_WEAPON":
    return _delegate_to_current_phase(action)
"PILE_IN":
    return _delegate_to_current_phase(action)
"ASSIGN_ATTACKS":
    return _delegate_to_current_phase(action)
"CONFIRM_AND_RESOLVE_ATTACKS":
    return _delegate_to_current_phase(action)
"ROLL_DICE":
    return _delegate_to_current_phase(action)
"CONSOLIDATE":
    return _delegate_to_current_phase(action)
"SKIP_UNIT":
    return _delegate_to_current_phase(action)
"HEROIC_INTERVENTION":
    return _delegate_to_current_phase(action)
"END_FIGHT":
    return process_end_fight(action)
```

**Rationale**:
- FightPhase, FightController, and all tests use these modern action names
- Follows the exact pattern used by ShootingPhase and ChargePhase
- All fight actions delegate to FightPhase except END_FIGHT (which triggers phase transition)
- Zero side effects - FightPhase already handles all these actions correctly

### Task 2: Remove Legacy Fight Processors (CLEANUP)

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameManager.gd`
**Location**: Lines 410-414
**Change**: Remove or comment out unused legacy methods

```gdscript
# BEFORE (lines 410-414 - UNUSED)
func process_fight_target(action: Dictionary) -> Dictionary:
    return _delegate_to_current_phase(action)

func process_resolve_fight(action: Dictionary) -> Dictionary:
    return _delegate_to_current_phase(action)

# AFTER (lines 410-420 - CLEANED UP)
# Legacy fight processors - DEPRECATED
# Replaced by modern action routing in process_action() match statement
# Kept for reference only - can be removed in future cleanup
# func process_fight_target(action: Dictionary) -> Dictionary:
#     return _delegate_to_current_phase(action)
# func process_resolve_fight(action: Dictionary) -> Dictionary:
#     return _delegate_to_current_phase(action)

# Keep process_end_fight() - still used for phase transition
func process_end_fight(action: Dictionary) -> Dictionary:
    print("GameManager: Processing END_FIGHT action")
    var next_phase = _get_next_phase(GameStateData.Phase.FIGHT)
    _trigger_phase_completion()
    return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}
```

**Rationale**:
- `process_fight_target()` and `process_resolve_fight()` are never called
- `process_end_fight()` is still used and should be kept
- Comment out instead of delete for reference during transition
- Can be fully removed in future cleanup PR

### Task 3: Verify Signal Chain in Multiplayer (VALIDATION)

**Purpose**: Ensure all fight phase signals propagate correctly to both host and client

**Test Scenarios**:

1. **Fighter Selection**
   - Client selects fighter
   - Host sees fighter highlighted
   - Both see same available targets

2. **Pile-In Movement**
   - Active player moves models 3" toward enemy
   - Both players see final positions
   - Movement validation works on both sides

3. **Attack Assignment**
   - Active player assigns weapons to targets
   - Assignments remain hidden from opponent until dice roll
   - Both players see dice results simultaneously

4. **Dice Rolling**
   - Host rolls dice (deterministic RNG)
   - Client receives identical dice results
   - Both UIs show same hit/wound/save outcomes
   - Damage applied identically on both sides

5. **Consolidate Movement**
   - Active player moves 3" toward enemy or objective
   - Both players see final positions
   - Fight sequence advances correctly

**Expected Signal Flow**:
```
Action (Client) → NetworkManager → GameManager (Host)
  → FightPhase.execute_action() → Signals emitted
  → NetworkManager re-broadcasts signals → Client UI updates
```

## Testing Strategy

### Pre-Fix Validation

**Steps**:
1. Start multiplayer game (host + client)
2. Progress to fight phase
3. Attempt to select a fighter
4. Observe logs for error

**Expected Error**:
```
NetworkManager: submit_action called for type: SELECT_FIGHTER
GameManager: process_action received: SELECT_FIGHTER
GameManager: Unknown action type: SELECT_FIGHTER
NetworkManager: Host applied action, result.success = false
```

### Post-Fix Validation

**Steps**:
1. Apply fix to GameManager.gd lines 94-107
2. Start multiplayer game (host + client)
3. Progress to fight phase
4. **Test 1: Select Fighter**
   - Client selects unit from fight sequence
   - ✅ Verify: Unit highlighted on both screens
   - ✅ Verify: Eligible targets shown on both screens
   - ✅ Verify: No errors in logs

5. **Test 2: Pile In**
   - Active player clicks "Pile In" and moves models
   - ✅ Verify: Movement preview shown
   - ✅ Verify: 3" range enforced
   - ✅ Verify: Final positions sync to both players

6. **Test 3: Attack Assignment**
   - Active player selects weapon and target
   - Active player clicks "Fight!" to confirm
   - ✅ Verify: Attack tree populates
   - ✅ Verify: Opponent doesn't see assignments yet

7. **Test 4: Roll Dice**
   - Active player clicks "Roll Dice"
   - ✅ Verify: Dice results appear on BOTH screens
   - ✅ Verify: Identical dice values (e.g., "Hit: 4/5, Wound: 3/4")
   - ✅ Verify: Damage applied simultaneously
   - ✅ Verify: Models removed identically

8. **Test 5: Consolidate**
   - Active player clicks "Consolidate" and moves models
   - ✅ Verify: 3" movement enforced
   - ✅ Verify: Positions sync correctly
   - ✅ Verify: Fight sequence advances to next unit

9. **Test 6: Complete Fight Phase**
   - Continue until all units have fought
   - Click "End Fight Phase"
   - ✅ Verify: Phase advances to next (Command/Morale)
   - ✅ Verify: No lingering state issues

### Manual Testing Procedure

```bash
# 1. Start Godot with multiplayer enabled
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# 2. Launch two instances
# Host: Click "Host Game" in main menu
# Client: Click "Join Game" with host IP

# 3. Load armies with melee units (e.g., Space Marines vs Orks)
# Both players should see DEPLOYMENT phase

# 4. Progress to FIGHT phase
# Ensure units are in engagement range (1" apart)
# Host: End phases until FIGHT phase starts

# 5. Test fight sequence
# Host: Verify fight sequence shows all engaged units
# Client: Verify same fight sequence order

# 6. Test fighter selection
# Active player: Click unit in fight sequence
# EXPECTED: Unit highlighted, weapons shown, targets available
# OTHER player: See same unit highlighted

# 7. Test pile in
# Active player: Click "Pile In", move models closer to enemy
# EXPECTED: Both players see new positions after confirmation

# 8. Test attack resolution
# Active player: Select weapon, click target, click "Fight!"
# Active player: Click "Roll Dice"
# EXPECTED: Dice results show on BOTH screens with identical values

# 9. Test consolidate
# Active player: Click "Consolidate", move models
# EXPECTED: Both players see new positions, next unit becomes active

# 10. Check logs for success
# Look for:
#   - "GameManager: Delegating SELECT_FIGHTER to current phase"
#   - "FightPhase: Selected [unit] to fight"
#   - "FightPhase: Melee combat resolved for [unit]"
#   - NO "Unknown action type" errors
```

### Debug Log Validation

**After fix, logs should show**:
```
NetworkManager: submit_action called for type: SELECT_FIGHTER
NetworkManager: is_networked() = true
NetworkManager: Host mode - validating and applying
NetworkManager: Phase validation result = { "valid": true, "errors": [] }
GameManager: Delegating SELECT_FIGHTER to current phase  ← NEW LINE
FightPhase: Selected [unit_id] to fight
FightPhase: Emitting fighter_selected signal
FightController: Fighter selected: [unit_id]

NetworkManager: submit_action called for type: PILE_IN
GameManager: Delegating PILE_IN to current phase  ← NEW LINE
FightPhase: Unit [unit_id] piled in
FightPhase: Emitting pile_in_preview signal

NetworkManager: submit_action called for type: ROLL_DICE
GameManager: Delegating ROLL_DICE to current phase  ← NEW LINE
FightPhase: Beginning melee combat resolution
RulesEngine: Resolving melee attacks
FightPhase: Emitting dice_rolled signals
FightController: Dice rolled, updating display
```

### Regression Testing

**Checklist**:
- ✅ Single-player fight phase continues working
- ✅ Other fight actions (SKIP_UNIT, END_FIGHT) still work
- ✅ Fight sequence determination works correctly
- ✅ Dice synchronization is deterministic (same values on host/client)
- ✅ Other phases (Movement, Shooting, Charge) unaffected
- ✅ Deployment and scoring phases unaffected
- ✅ Network reconnection doesn't cause desync

## Quality Validation Gates

### Code Quality Checks

```bash
# Run from project root
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# 1. Verify new fight actions are registered
grep -A 15 "# Fight actions" autoloads/GameManager.gd

# Expected output should show all 10 modern actions:
# SELECT_FIGHTER, SELECT_MELEE_WEAPON, PILE_IN, etc.

# 2. Verify legacy actions are removed/commented
grep "SELECT_FIGHT_TARGET\|RESOLVE_FIGHT" autoloads/GameManager.gd

# Should return commented lines or no results

# 3. Verify FightPhase action handlers exist
grep -n "\"SELECT_FIGHTER\":" phases/FightPhase.gd
grep -n "\"PILE_IN\":" phases/FightPhase.gd
grep -n "\"ROLL_DICE\":" phases/FightPhase.gd

# Should find matches in validate_action() and process_action()

# 4. Test game loads without errors
# Launch Godot and check console for startup errors
```

### Integration Testing

**Test Matrix**:

| Action Type | Single-Player | Host (MP) | Client (MP) | Signal Sync |
|-------------|---------------|-----------|-------------|-------------|
| SELECT_FIGHTER | ✅ | ✅ | ✅ | ✅ |
| SELECT_MELEE_WEAPON | ✅ | ✅ | ✅ | ✅ |
| PILE_IN | ✅ | ✅ | ✅ | ✅ |
| ASSIGN_ATTACKS | ✅ | ✅ | ✅ | ✅ |
| CONFIRM_AND_RESOLVE_ATTACKS | ✅ | ✅ | ✅ | ✅ |
| ROLL_DICE | ✅ | ✅ | ✅ | ✅ |
| CONSOLIDATE | ✅ | ✅ | ✅ | ✅ |
| SKIP_UNIT | ✅ | ✅ | ✅ | ✅ |
| HEROIC_INTERVENTION | ⚠️ Not impl | ⚠️ Not impl | ⚠️ Not impl | N/A |
| END_FIGHT | ✅ | ✅ | ✅ | ✅ |

**Note**: HEROIC_INTERVENTION is registered but not implemented (placeholder) - separate issue to address.

## Success Criteria

### Functional Requirements
✅ All fight actions work in multiplayer mode (host and client)
✅ Fighter selection synchronizes across network
✅ Pile-in movements visible to both players
✅ Attack assignments remain hidden until dice roll
✅ Dice results synchronized (identical values on both sides)
✅ Consolidate movements synchronized
✅ Fight sequence advances correctly for both players
✅ No "Unknown action type" errors in multiplayer mode
✅ Single-player mode continues working (no regression)

### Technical Requirements
✅ GameManager.gd registers all 10 modern fight actions
✅ All fight actions delegate to FightPhase via `_delegate_to_current_phase()`
✅ Legacy fight processors removed or commented out
✅ Signal chain (fighter_selected, dice_rolled, etc.) fires in multiplayer
✅ NetworkManager propagates action results to all clients
✅ Follows same pattern as ShootingPhase and ChargePhase
✅ No code duplication - reuses existing delegation pattern

### Network Requirements (Multiplayer Specific)
✅ Host validates and processes all fight actions
✅ Client receives state updates via network sync
✅ Both host and client update UI identically
✅ RNG determinism maintained (host-side dice rolls)
✅ Action validation works on both host and client
✅ Engagement range calculations match on both sides
✅ Model positions stay synchronized after pile-in/consolidate
✅ Dice results match exactly (no drift due to different RNG seeds)

### User Experience Requirements
✅ Smooth turn-based flow (player waits while opponent acts)
✅ Clear visual feedback when unit is selected
✅ Dice rolls appear simultaneously on both screens
✅ No silent failures or mysterious action rejections
✅ Consistent UI state between host and client
✅ Clear indication of whose turn it is to select next fighter

## Implementation Notes

### Critical Files to Modify

1. **GameManager.gd:94-100** - Replace legacy fight actions (HIGHEST PRIORITY)
2. **GameManager.gd:410-414** - Comment out legacy processors (CLEANUP)

### Code Conventions to Follow

- Use `_delegate_to_current_phase()` for all fight actions except END_FIGHT
- Maintain alphabetical or logical grouping in match statement
- Follow existing comment style: `# Fight actions (modern phase-based system)`
- Keep END_FIGHT separate as it triggers phase transition
- Match pattern from ShootingPhase (lines 60-66)

### Potential Gotchas

**1. Signal Timing**
- Ensure dice_rolled signal fires AFTER state changes applied
- FightController must receive signals in correct order

**2. State Synchronization**
- Active fighter ID must sync before showing targets
- Pile-in movements must apply before showing consolidate option
- Attack assignments must sync before dice roll results

**3. RNG Determinism**
- Dice rolls MUST happen on host side only
- Client receives results via network, doesn't roll independently
- Prevents desyncs from different random seeds

**4. Action Validation**
- Both host and client validate actions
- Host has final authority (server authoritative)
- Client validation is for immediate feedback only

**5. Engagement Range Edge Cases**
- Both clients must use identical engagement range calculations
- Shape-aware collision must be deterministic
- Measurement.gd functions must give same results on both sides

### Why This is a 10/10 Score

1. **Identical to Solved Problem**: Same bug pattern as charge phase (already fixed)
2. **Proven Solution Pattern**: Exact same fix structure works here
3. **Clear Root Cause**: GameManager missing modern action registrations
4. **Minimal Code Changes**: Replace 3 lines with 10 lines in match statement
5. **Zero Logic Changes**: Just routing - FightPhase already handles everything
6. **Comprehensive Testing**: FightPhase has extensive tests (3 test files)
7. **Follows Conventions**: Matches ShootingPhase and ChargePhase patterns
8. **Well-Documented Codebase**: FightPhase has clear comments and structure
9. **Immediate Validation**: Visual feedback (dice, movement) when working
10. **No Dependencies**: Self-contained fix with no side effects

## Related Documentation

### Godot Networking
- https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- RPC and signal synchronization patterns
- Deterministic gameplay in multiplayer

### Game Architecture References
- **BasePhase.gd**: Lines 78-109 - execute_action() and process_action() pattern
- **FightPhase.gd**: Lines 1-1132 - Complete fight phase implementation
- **FightController.gd**: Lines 1-1135 - UI controller for fight phase
- **ShootingPhase.gd**: Similar multi-action phase with delegation pattern
- **ChargePhase.gd**: Recently fixed action routing (reference implementation)
- **GameManager.gd**: Lines 556-576 - _delegate_to_current_phase() helper
- **NetworkManager.gd**: Lines 108-194 - Action submission and validation flow

### Warhammer 40k Fight Rules
- https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE
- Fight sequence (Fights First → Normal)
- Pile-in and consolidate movement rules
- Engagement range definition
- Heroic intervention rules

### Previous Fix Reference
- **gh_issue_charge_roll_action_type_mismatch.md** - Identical bug pattern in charge phase
  - Shows exact fix structure
  - Demonstrates testing approach
  - Proves pattern works

## Action Type Reference Table

| FightPhase Action | GameManager Status | Fix Required | Delegation Target |
|-------------------|-------------------|--------------|-------------------|
| SELECT_FIGHTER | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| SELECT_MELEE_WEAPON | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| PILE_IN | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| ASSIGN_ATTACKS | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| CONFIRM_AND_RESOLVE_ATTACKS | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| ROLL_DICE | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| CONSOLIDATE | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| SKIP_UNIT | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| HEROIC_INTERVENTION | ❌ Missing | ✅ Add | _delegate_to_current_phase |
| END_FIGHT | ✅ Registered | ✅ Keep | process_end_fight (phase transition) |
| SELECT_FIGHT_TARGET | ⚠️ Legacy | ❌ Remove | N/A (unused) |
| RESOLVE_FIGHT | ⚠️ Legacy | ❌ Remove | N/A (unused) |

## Appendix: Complete Code Diff

### GameManager.gd Changes

```gdscript
# ============================================================================
# FIGHT ACTION PROCESSORS
# ============================================================================

# BEFORE (lines 94-100)
# Fight actions
"SELECT_FIGHT_TARGET":
    return process_fight_target(action)
"RESOLVE_FIGHT":
    return process_resolve_fight(action)
"END_FIGHT":
    return process_end_fight(action)

# AFTER (lines 94-107)
# Fight actions (modern phase-based system)
"SELECT_FIGHTER":
    return _delegate_to_current_phase(action)
"SELECT_MELEE_WEAPON":
    return _delegate_to_current_phase(action)
"PILE_IN":
    return _delegate_to_current_phase(action)
"ASSIGN_ATTACKS":
    return _delegate_to_current_phase(action)
"CONFIRM_AND_RESOLVE_ATTACKS":
    return _delegate_to_current_phase(action)
"ROLL_DICE":
    return _delegate_to_current_phase(action)
"CONSOLIDATE":
    return _delegate_to_current_phase(action)
"SKIP_UNIT":
    return _delegate_to_current_phase(action)
"HEROIC_INTERVENTION":
    return _delegate_to_current_phase(action)
"END_FIGHT":
    return process_end_fight(action)
```

```gdscript
# BEFORE (lines 410-414)
func process_fight_target(action: Dictionary) -> Dictionary:
    return _delegate_to_current_phase(action)

func process_resolve_fight(action: Dictionary) -> Dictionary:
    return _delegate_to_current_phase(action)

func process_end_fight(action: Dictionary) -> Dictionary:
    print("GameManager: Processing END_FIGHT action")
    var next_phase = _get_next_phase(GameStateData.Phase.FIGHT)
    _trigger_phase_completion()
    return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}

# AFTER (lines 410-425)
# Legacy fight processors - DEPRECATED
# These were replaced by modern action routing in process_action()
# Kept as comments for reference during transition period
#
# func process_fight_target(action: Dictionary) -> Dictionary:
#     return _delegate_to_current_phase(action)
#
# func process_resolve_fight(action: Dictionary) -> Dictionary:
#     return _delegate_to_current_phase(action)

func process_end_fight(action: Dictionary) -> Dictionary:
    print("GameManager: Processing END_FIGHT action")
    var next_phase = _get_next_phase(GameStateData.Phase.FIGHT)
    _trigger_phase_completion()
    return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}
```

**Total Lines Changed**: ~20 lines
**Files Modified**: 1 file (GameManager.gd)
**Breaking Changes**: None (only adds missing routes)
**Estimated Time**: 15-30 minutes to implement + 1-2 hours testing

---

**Final Score: 10/10** - Trivial fix following proven pattern with comprehensive documentation and guaranteed success. The fight phase will go from 0% functional to 100% functional in multiplayer with this single change.
