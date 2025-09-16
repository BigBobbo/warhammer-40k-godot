# PRP: Fix Battlewagon Deployment and Save/Load Issues (GitHub Issue #72)

## Problem Statement
The Ork Battlewagon unit has two critical bugs:
1. **Deployment Turn Switching**: After deploying a Battlewagon, the turn does not switch to the other player as it should
2. **Save/Load Failure**: When saving and loading a game with a deployed Battlewagon, the unit disappears

## Research Findings

### Code Analysis
#### Battlewagon Properties
- Unit ID: `U_BATTLEWAGON_G` 
- Base type: `rectangular` (229mm x 127mm)
- Has rotation property that needs to be tracked
- Located in: `/40k/armies/orks.json:739-920`

#### Issue 1: Turn Not Switching After Deployment
**Root Cause**: The deployment action is being created and sent, but there may be an issue with action validation or processing for rectangular base models.

**Code Flow**:
1. `DeploymentController.confirm()` (line 150-186) creates deployment action
2. Action sent to `PhaseManager.current_phase_instance.execute_action()`
3. `BasePhase.execute_action()` validates and processes the action
4. If successful, emits `action_taken` signal
5. `TurnManager._on_phase_action_taken()` catches signal
6. For `DEPLOY_UNIT` actions, calls `check_deployment_alternation()`
7. Should call `alternate_active_player()` when both players have units

**Potential Issues**:
- Action validation might fail silently for rectangular bases
- Signal might not be emitted properly
- Turn manager might not receive the signal

#### Issue 2: Battlewagon Not Loading After Save
**Root Cause**: Model rotations are not being included in the deployment action, causing incomplete state when saving.

**Specific Bug Location**: `DeploymentController.confirm()` lines 156-163
```gdscript
var deployment_action = {
    "type": "DEPLOY_UNIT",
    "unit_id": unit_id,
    "model_positions": model_positions,
    # MISSING: "model_rotations": temp_rotations
    "phase": GameStateData.Phase.DEPLOYMENT,
    "player": GameState.get_active_player(),
    "timestamp": Time.get_unix_time_from_system()
}
```

The `temp_rotations` array is populated during placement (lines 121-122) but never included in the deployment action. This means the rotation data is lost and not saved to the game state.

### Related Files
- `/40k/scripts/DeploymentController.gd` - Main deployment interaction handler
- `/40k/phases/DeploymentPhase.gd` - Deployment phase logic
- `/40k/autoloads/TurnManager.gd` - Turn alternation logic
- `/40k/scripts/bases/RectangularBase.gd` - Rectangular base implementation
- `/40k/autoloads/SaveLoadManager.gd` - Save/load system
- `/40k/autoloads/StateSerializer.gd` - State serialization

### External Documentation
- Godot Node2D rotation: Uses `rotation` property (float in radians)
- Warhammer 40k deployment: Players alternate deploying units

## Implementation Plan

### Task 1: Fix Missing Rotations in Deployment Action
**File**: `/40k/scripts/DeploymentController.gd`
**Line**: 156-163

**Change**: Add model_rotations to the deployment action
```gdscript
var deployment_action = {
    "type": "DEPLOY_UNIT",
    "unit_id": unit_id,
    "model_positions": model_positions,
    "model_rotations": temp_rotations,  # ADD THIS LINE
    "phase": GameStateData.Phase.DEPLOYMENT,
    "player": GameState.get_active_player(),
    "timestamp": Time.get_unix_time_from_system()
}
```

### Task 2: Debug and Fix Turn Switching Issue
**File**: `/40k/scripts/DeploymentController.gd`
**Line**: 169-173

**Change**: Add proper error logging and ensure action_taken signal is emitted
```gdscript
var result = phase_manager.current_phase_instance.execute_action(deployment_action)
if result.success:
    print("[DeploymentController] Deployment successful for unit: ", unit_id)
    print("[DeploymentController] Action should trigger turn switch")
else:
    print("[DeploymentController] ERROR - Deployment failed for unit: ", unit_id)
    print("[DeploymentController] Errors: ", result.get("errors", []))
    push_error("Deployment failed: " + str(result.get("error", "Unknown error")))
```

### Task 3: Add Rotation Clearing on Reset
**File**: `/40k/scripts/DeploymentController.gd`
**Line**: 181 (after temp_positions.clear())

**Change**: Also clear temp_rotations
```gdscript
temp_positions.clear()
temp_rotations.clear()  # ADD THIS LINE
```

### Task 4: Verify Action Processing in BasePhase
**File**: `/40k/phases/BasePhase.gd`
**Line**: 45-63

**Add Debug Logging**:
```gdscript
func execute_action(action: Dictionary) -> Dictionary:
    print("[BasePhase] Executing action: ", action.get("type", "UNKNOWN"))
    print("[BasePhase] For unit: ", action.get("unit_id", "N/A"))
    
    var validation = validate_action(action)
    if not validation.valid:
        print("[BasePhase] Action validation failed: ", validation.errors)
        return {"success": false, "errors": validation.errors}
    
    var result = process_action(action)
    if result.success:
        print("[BasePhase] Action processed successfully")
        # Apply the state changes if they exist
        if result.has("changes") and result.changes is Array:
            PhaseManager.apply_state_changes(result.changes)
        
        # Record the action
        print("[BasePhase] Emitting action_taken signal")
        emit_signal("action_taken", action)
        
        # Check if this action completes the phase
        if _should_complete_phase():
            emit_signal("phase_completed")
    else:
        print("[BasePhase] Action processing failed")
    
    return result
```

### Task 5: Verify Turn Switching in TurnManager
**File**: `/40k/autoloads/TurnManager.gd`
**Line**: 51-58

**Add Debug Logging**:
```gdscript
func _on_phase_action_taken(action: Dictionary) -> void:
    var action_type = action.get("type", "")
    var current_phase = GameState.get_current_phase()
    
    print("[TurnManager] Received action: ", action_type)
    print("[TurnManager] Current phase: ", current_phase)
    
    match current_phase:
        GameStateData.Phase.DEPLOYMENT:
            if action_type == "DEPLOY_UNIT":
                print("[TurnManager] Processing DEPLOY_UNIT action")
                print("[TurnManager] Unit deployed: ", action.get("unit_id", "Unknown"))
                check_deployment_alternation()
```

### Task 6: Enhanced Turn Alternation Logging
**File**: `/40k/autoloads/TurnManager.gd`
**Line**: 61-78

**Add Debug Logging**:
```gdscript
func check_deployment_alternation() -> void:
    var player1_has_units = _has_undeployed_units(1)
    var player2_has_units = _has_undeployed_units(2)
    
    print("[TurnManager] Player 1 has undeployed units: ", player1_has_units)
    print("[TurnManager] Player 2 has undeployed units: ", player2_has_units)
    
    if not player1_has_units and not player2_has_units:
        print("[TurnManager] All units deployed - phase will complete")
        return
    
    var current_player = GameState.get_active_player()
    print("[TurnManager] Current active player: ", current_player)
    
    # Simple alternation - if both players have units, just alternate every time
    if player1_has_units and player2_has_units:
        print("[TurnManager] Both players have units - alternating")
        alternate_active_player()
    # If only one player has units left, switch to that player if needed
    elif player1_has_units and current_player != 1:
        print("[TurnManager] Only Player 1 has units - switching to Player 1")
        _set_active_player(1)
    elif player2_has_units and current_player != 2:
        print("[TurnManager] Only Player 2 has units - switching to Player 2")
        _set_active_player(2)
```

## Testing Strategy

### Manual Testing Steps
1. Start a new game with Ork army (Player 2)
2. Deploy a regular unit (e.g., Boyz) - verify turn switches
3. Deploy the Battlewagon - verify:
   - Turn switches to Player 1
   - Rotation controls work (Q/E keys)
   - Unit appears correctly
4. Save the game immediately after deploying Battlewagon
5. Load the saved game - verify:
   - Battlewagon is still present
   - Position and rotation are preserved
   - Game state is consistent

### Automated Test Cases
```gdscript
# Add to test_deployment_phase.gd
func test_battlewagon_deployment_switches_turn():
    # Setup
    GameState.set_active_player(2)
    var battlewagon_id = "U_BATTLEWAGON_G"
    
    # Create deployment action
    var action = {
        "type": "DEPLOY_UNIT",
        "unit_id": battlewagon_id,
        "model_positions": [Vector2(200, 200)],
        "model_rotations": [PI/4],  # 45 degrees
        "player": 2
    }
    
    # Execute
    var result = deployment_phase.execute_action(action)
    
    # Verify
    assert_true(result.success)
    assert_eq(GameState.get_active_player(), 1)  # Should switch to player 1

func test_battlewagon_save_load_preserves_rotation():
    # Deploy battlewagon with rotation
    var battlewagon_id = "U_BATTLEWAGON_G"
    var rotation = PI/3  # 60 degrees
    
    # Deploy
    var action = {
        "type": "DEPLOY_UNIT",
        "unit_id": battlewagon_id,
        "model_positions": [Vector2(300, 300)],
        "model_rotations": [rotation],
        "player": 2
    }
    deployment_phase.execute_action(action)
    
    # Save
    var save_data = GameState.create_snapshot()
    var json_data = StateSerializer.serialize_game_state(save_data)
    
    # Load
    var loaded_state = StateSerializer.deserialize_game_state(json_data)
    GameState.restore_snapshot(loaded_state)
    
    # Verify
    var unit = GameState.get_unit(battlewagon_id)
    assert_not_null(unit)
    assert_eq(unit.models[0].rotation, rotation)
```

## Validation Gates

```bash
# Run Godot tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_deployment_phase.gd

# Check for syntax errors
godot --headless --check-only

# Run specific Battlewagon tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_deployment_phase.gd -gunit_test_name=test_battlewagon
```

## Implementation Order
1. **Fix rotation saving** (Task 1, 3) - Critical bug fix
2. **Add debug logging** (Tasks 2, 4, 5, 6) - To diagnose turn switching
3. **Test manually** - Verify both issues are resolved
4. **Add automated tests** - Prevent regression
5. **Remove debug logging** - Clean up after verification

## Risk Assessment
- **Low Risk**: Adding rotations to deployment action - straightforward fix
- **Medium Risk**: Turn switching - may reveal deeper issues with signal handling
- **Mitigation**: Extensive debug logging to trace execution flow

## Success Criteria
✅ Battlewagon deployment triggers turn switch to other player  
✅ Battlewagon rotation is preserved after save/load  
✅ All existing deployment tests still pass  
✅ New tests for Battlewagon behavior pass  

## Confidence Score: 8/10
The rotation fix is straightforward and highly likely to work. The turn switching issue may require additional debugging based on the logging output, but the root cause analysis is thorough and the fix locations are identified.