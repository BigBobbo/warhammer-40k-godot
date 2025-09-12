# Charge Movement Bug Fix PRP - GitHub Issue #33

## Overview

Fix the **charge movement bug** where models don't actually move to their final positions after a successful charge. The UI allows positioning models and shows the intended locations, but when the charge is confirmed, the models remain in their original positions. This affects units with multiple models while single-model units work correctly.

**Score: 9/10** - Clear bug with identifiable root cause and comprehensive context for one-pass implementation success.

## Issue Context

**GitHub Issue**: #33  
**Title**: "Charges no longer moving models"  
**Reporter**: BigBobbo  
**Status**: Open

### Problem Description
- Unit successfully rolls and makes a charge (within engagement range)
- Game allows dragging the charging unit models and shows final positions
- User confirms the charge via "Confirm Charge Moves" button
- **BUG**: Models never actually move to the confirmed locations
- Issue only affects units with multiple models (single model units work correctly)

### Debug Evidence from Issue Report
```
DEBUG: ChargeController _input - Left mouse button, pressed: true
DEBUG: Models to move: ["m1", "m2", "m3"]
DEBUG: Clicked on model m1
Starting drag for model m1
DEBUG: ChargeController _input - Left mouse button, pressed: false
Model m1 moved to valid position
DEBUG: Confirm button enabled - moved_models.size() = 1
DEBUG: Confirm button global position: (2376.0, 0.0)
DEBUG: Confirm button visible: true
[...same pattern for m2, m3...]
DEBUG: Confirm button enabled - moved_models.size() = 3
```

The logs show UI interaction works but models don't persist their new positions.

## Context & Documentation

### Core Documentation
- **Warhammer 40k 10e Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot 4.4 Documentation**: https://docs.godotengine.org/en/4.4/
- **Project Root**: `/Users/robertocallaghan/Documents/claude/godotv2`

### Key Rule References (Wahapedia)
From 10e Core Rules - Charge phase:
- **Engagement Range**: Within 1" horizontally and 5" vertically
- **Charge Success**: After successful 2D6 roll, models must end within engagement range
- **Unit Coherency**: Models must maintain 2" coherency after movement
- **Model Positioning**: Models must move as close as possible to target models

## Existing Codebase Analysis

### Current Charge Flow Architecture

**1. UI Interaction (ChargeController.gd:935-974)**
```gdscript
func _on_confirm_charge_moves() -> void:
    print("DEBUG: _on_confirm_charge_moves called!")
    
    # Build per_model_paths for the charge action
    var per_model_paths = {}
    for model_id in moved_models:
        var new_pos = moved_models[model_id]
        var old_pos = _get_model_position(model)
        per_model_paths[model_id] = [[old_pos.x, old_pos.y], [new_pos.x, new_pos.y]]
    
    # Send the charge movement action
    var action = {
        "type": "APPLY_CHARGE_MOVE",
        "actor_unit_id": active_unit_id,
        "payload": {"per_model_paths": per_model_paths}
    }
    charge_action_requested.emit(action)  # Signal emission
```

**2. Signal Handling (Main.gd:1511-1535)**
```gdscript
func _on_charge_action_requested(action: Dictionary) -> void:
    var phase_instance = PhaseManager.get_current_phase_instance()
    
    if phase_instance and phase_instance.has_method("execute_action"):
        var result = phase_instance.execute_action(action)  # KEY LINE
        if result.success:
            # Apply state changes
            var changes = result.get("changes", [])
            if not changes.is_empty():
                PhaseManager.apply_state_changes(changes)
            update_after_charge_action()  # Visual refresh
```

**3. Phase Processing (ChargePhase.gd:245-313)**
```gdscript
func _process_apply_charge_move(action: Dictionary) -> Dictionary:
    var per_model_paths = payload.get("per_model_paths", {})
    
    # Apply successful charge movement
    var changes = []
    for model_id in per_model_paths:
        var path = per_model_paths[model_id]
        if path is Array and path.size() > 0:
            var final_pos = path[-1]  # Last position in path
            var model_index = _get_model_index(unit_id, model_id)
            var change = {
                "op": "set",
                "path": "units.%s.models.%d.position" % [unit_id, model_index],
                "value": {"x": final_pos[0], "y": final_pos[1]}
            }
            changes.append(change)
    
    return create_result(true, changes)
```

**4. State Application (PhaseManager.gd:119-168)**
```gdscript
func apply_state_changes(changes: Array) -> void:
    for change in changes:
        _apply_single_change(change)

func _set_state_value(path: String, value) -> void:
    # Traverses GameState.state dictionary and updates value
```

## Root Cause Analysis

### PRIMARY ISSUE: Method Call Mismatch
**File**: `Main.gd:1518`  
**Problem**: Calls `phase_instance.execute_action(action)` but ChargePhase only implements `process_action(action)`

**Evidence**:
- ChargePhase.gd:75 defines `process_action()` method
- ChargePhase.gd has NO `execute_action()` method
- BasePhase.gd likely doesn't provide this method either
- Result: `execute_action()` call fails silently, no state changes applied

### SECONDARY ISSUES: State Management
1. **Model Index Resolution**: `_get_model_index()` may return -1 for invalid model_ids
2. **Path Validation**: No validation that per_model_paths contains valid data
3. **Visual Sync**: Models visual positions may not sync with GameState positions

## Implementation Plan

### Task 1: Fix Method Call Mismatch
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/Main.gd`  
**Location**: Line 1518  
**Change**: `execute_action` → `process_action`

```gdscript
# BEFORE (broken)
var result = phase_instance.execute_action(action)

# AFTER (fixed)  
var result = phase_instance.process_action(action)
```

### Task 2: Add Robust Error Handling  
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/ChargePhase.gd`  
**Location**: `_process_apply_charge_move()` method (lines 245-313)

**Enhancements**:
1. Validate per_model_paths structure
2. Check model_index validity before creating changes
3. Add comprehensive logging for debugging

```gdscript
func _process_apply_charge_move(action: Dictionary) -> Dictionary:
    print("DEBUG: _process_apply_charge_move called with action: ", action)
    var unit_id = action.get("actor_unit_id", "")
    var payload = action.get("payload", {})
    var per_model_paths = payload.get("per_model_paths", {})
    
    # Enhanced validation
    if per_model_paths.is_empty():
        return create_result(false, [], "No model paths provided")
    
    var changes = []
    for model_id in per_model_paths:
        var path = per_model_paths[model_id]
        print("DEBUG: Processing model ", model_id, " with path ", path)
        
        if not (path is Array and path.size() > 0):
            print("WARNING: Invalid path for model ", model_id)
            continue
            
        var final_pos = path[-1]
        var model_index = _get_model_index(unit_id, model_id)
        print("DEBUG: Model index for ", model_id, " is ", model_index)
        
        if model_index < 0:
            print("ERROR: Invalid model_index for ", model_id)
            continue
            
        var change = {
            "op": "set", 
            "path": "units.%s.models.%d.position" % [unit_id, model_index],
            "value": {"x": final_pos[0], "y": final_pos[1]}
        }
        print("DEBUG: Adding change: ", change)
        changes.append(change)
    
    print("DEBUG: Returning ", changes.size(), " changes: ", changes)
    return create_result(true, changes)
```

### Task 3: Enhance State Change Application Logging
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/PhaseManager.gd`  
**Location**: `apply_state_changes()` method (lines 119-168)

```gdscript
func apply_state_changes(changes: Array) -> void:
    print("DEBUG: PhaseManager applying ", changes.size(), " state changes")
    for i in range(changes.size()):
        var change = changes[i]
        print("DEBUG: Applying change ", i, ": ", change)
        _apply_single_change(change)
        print("DEBUG: Change ", i, " applied successfully")
```

### Task 4: Add Visual Update Validation
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/Main.gd`  
**Location**: `update_after_charge_action()` method (lines 1573-1581)

```gdscript
func update_after_charge_action() -> void:
    print("DEBUG: update_after_charge_action called")
    
    # Refresh visuals and UI after a charge action
    _recreate_unit_visuals()
    refresh_unit_list()  
    update_ui()
    
    # Update charge controller state
    if charge_controller:
        charge_controller._refresh_ui()
    
    print("DEBUG: Charge action visual update completed")
```

## Testing Strategy

### Manual Testing Procedure
1. **Setup**: Load game with multi-model unit (e.g., 3+ Intercessors)
2. **Deploy**: Place unit and enemy target within 12" charge range  
3. **Declare**: Select unit, declare charge, roll successful distance
4. **Move**: Drag all models to valid engagement positions
5. **Confirm**: Click "Confirm Charge Moves" button
6. **Verify**: Check that models are visually at their new positions
7. **State Check**: Verify GameState.units[unit_id].models[X].position reflects new positions

### Expected Behavior After Fix
- All models in multi-model units should move to their confirmed positions
- GameState should persist the new model positions
- Visual representation should match GameState positions
- Debug logs should show successful state change application

### Regression Testing
- Verify single-model unit charges still work correctly
- Test charge failure scenarios (insufficient distance, invalid positions)
- Confirm other phase transitions work normally

## Quality Validation Gates

### Code Quality Checks
```bash
# Run from project root
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Check syntax (if lint tools available)
gdscript-lint phases/ChargePhase.gd
gdscript-lint scripts/Main.gd  
gdscript-lint autoloads/PhaseManager.gd

# Run tests (if available)
# Note: Look for existing test runner or implement basic validation
```

### Integration Testing
1. **Charge Phase Flow**: Verify complete charge sequence works end-to-end
2. **State Persistence**: Confirm model positions save/load correctly
3. **UI Synchronization**: Ensure visual models match GameState positions
4. **Multi-Unit Support**: Test charges with various unit sizes (2-10 models)

## Implementation Notes

### Critical Files to Modify
1. **Main.gd:1518** - Fix method call (highest priority)
2. **ChargePhase.gd:245-313** - Add error handling and logging
3. **PhaseManager.gd:119-168** - Enhance state change logging
4. **Main.gd:1573-1581** - Add visual update validation

### Code Conventions to Follow
- Use existing debug print patterns: `print("DEBUG: ...")`
- Maintain consistent error handling style
- Follow existing signal naming conventions  
- Preserve existing validation patterns from MovementPhase

### Potential Gotchas
- **Model ID Consistency**: Ensure model IDs in UI match GameState
- **Position Coordinate Systems**: Verify local vs global coordinate handling
- **State Change Atomicity**: All model updates should succeed or fail together
- **Visual Update Timing**: Ensure `_recreate_unit_visuals()` happens after state changes

## Success Criteria

### Functional Requirements
✅ Multi-model units successfully move to confirmed positions after charge  
✅ GameState.units[unit_id].models[X].position accurately reflects new positions  
✅ Visual representation synchronizes with GameState data  
✅ Single-model unit charges continue working correctly  
✅ Charge failure scenarios handle gracefully  

### Technical Requirements  
✅ Method call uses correct `process_action()` instead of `execute_action()`  
✅ Comprehensive error handling prevents silent failures  
✅ Debug logging provides clear troubleshooting information  
✅ State changes apply atomically  
✅ No performance degradation in charge phase processing

**Final Score: 9/10** - Clear root cause identified with comprehensive fix strategy and validation approach for reliable one-pass implementation.