# 🎯 Allow Multiple Movement Steps - Implementation PRP

## Problem Statement
GitHub Issue #16: "When a model moves it has a maximum distance it can move, currently when a user clicks and drags a model, once they release the model any remaining movement is used up. Instead of this happening the user should be able to move models in a unit multiple times until that overall movement distance is used up or until the user clicks "Confirm Move"."

### Current Behavior
- User drags a model 3 inches → releases → remaining 3 inches of movement are lost
- Each drag-and-drop consumes all remaining movement for that unit
- No way to perform partial movements and continue moving the same unit

### Desired Behavior
- User drags model 3 inches → releases → can drag again for remaining 3 inches
- Movement distance accumulates across multiple drag operations
- Only "Confirm Move" button finalizes the movement and consumes the total distance
- Example: 6" movement → drag 3" → drag another 3" → confirm = total 6" used

## Implementation Blueprint

### Root Cause Analysis
After thorough investigation of the movement system:

**Current MovementPhase.gd behavior** (`phases/MovementPhase.gd:368-401`):
- `SET_MODEL_DEST` immediately commits model position to game state
- Each drag operation creates a permanent model move in `active_moves[unit_id].model_moves`
- No mechanism to track partial/temporary movements before confirmation

**Current MovementController.gd behavior** (`scripts/MovementController.gd:586-640`):
- `_end_model_drag()` immediately sends `SET_MODEL_DEST` action on mouse release
- No concept of "temporary" or "staged" movements
- Distance validation happens per-drag rather than accumulative

### Solution Approach
Implement a **staged movement system** that separates temporary positioning from permanent commitment:

1. **Add temporary movement state** to track partial movements before confirmation
2. **Modify drag operations** to stage movements instead of committing immediately  
3. **Update distance tracking** to accumulate across multiple staged movements
4. **Enhance UI feedback** to show staged vs confirmed movements
5. **Preserve existing confirmation workflow** - only "Confirm Move" finalizes movements

## Critical Context for Implementation

### Files to Modify
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/MovementPhase.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd`

### Existing Patterns to Follow

#### 1. Multi-Step Movement Pattern from ChargeController.gd
The ChargeController already implements multi-step model movement:

```gdscript
# From ChargeController.gd:21-26
var models_to_move: Array = []  # Models that still need to move
var moved_models: Dictionary = {}  # model_id -> new_position  
var dragging_model = null  # Currently dragging model
var confirm_button: Button = null  # Button to confirm charge moves
```

#### 2. Movement State Tracking Pattern from MovementPhase.gd
Current movement tracking structure to extend:

```gdscript
# From MovementPhase.gd:279-284  
active_moves[unit_id] = {
    "mode": "NORMAL",
    "move_cap_inches": move_inches,
    "model_moves": [],
    "dice_rolls": []
}
```

#### 3. Distance Accumulation Pattern from Measurement.gd
Existing distance calculation functions:

```gdscript
# From MovementPhase.gd:392
var distance_inches = Measurement.distance_inches(current_pos, dest_vec)
```

#### 4. Confirmation Pattern from MovementController.gd
Existing confirmation system to preserve:

```gdscript
# From MovementController.gd:413-422
func _on_confirm_move_pressed() -> void:
    var action = {
        "type": "CONFIRM_UNIT_MOVE",
        "actor_unit_id": active_unit_id,
        "payload": {}
    }
    emit_signal("move_action_requested", action)
```

### External References

**Warhammer 40k 10th Edition Movement Rules**:
- Source: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Key principle: "Players move one unit at a time until all units have moved"  
- Movement flexibility: Players can measure and redirect units during their movement
- No restriction on partial movement steps within a single unit's activation

**Godot 4.4 Documentation**:
- Node signals: https://docs.godotengine.org/en/4.4/classes/class_node.html
- UI best practices: https://docs.godotengine.org/en/4.4/tutorials/ui/index.html
- State management through node architecture and custom signals

**Best Practices**:
- Use signals for communication between movement state changes
- Implement staged state that can be reverted before confirmation
- Follow existing MovementController pattern for UI consistency

## Implementation Tasks

### Task 1: Add Staged Movement State to MovementPhase.gd
**Location**: `MovementPhase.gd:279-284` (modify active_moves structure)

**Current structure:**
```gdscript
active_moves[unit_id] = {
    "mode": "NORMAL",
    "move_cap_inches": move_inches,
    "model_moves": [],
    "dice_rolls": []
}
```

**Required changes:**
```gdscript
active_moves[unit_id] = {
    "mode": "NORMAL", 
    "move_cap_inches": move_inches,
    "model_moves": [],  # Confirmed moves (unchanged)
    "staged_moves": [], # NEW: Temporary moves before confirmation  
    "accumulated_distance": 0.0,  # NEW: Total distance across all staged moves
    "dice_rolls": []
}
```

### Task 2: Add New Action Type for Staging Movement
**Location**: `MovementPhase.gd:56-79` (add to validate_action)

**Required implementation:**
1. Add `STAGE_MODEL_MOVE` action type for temporary movement
2. Add validation method `_validate_stage_model_move()`
3. Add processing method `_process_stage_model_move()`
4. Modify `SET_MODEL_DEST` to work with confirmed moves only

**New validation logic:**
```gdscript
func _validate_stage_model_move(action: Dictionary) -> Dictionary:
    # Similar to _validate_set_model_dest but allows accumulative distance
    var total_distance = move_data.accumulated_distance + new_distance
    if total_distance > move_data.move_cap_inches:
        return {"valid": false, "errors": ["Total staged movement exceeds cap"]}
    return {"valid": true, "errors": []}
```

### Task 3: Modify MovementController Drag Behavior
**Location**: `MovementController.gd:586-640` (_end_model_drag method)

**Current behavior:**
```gdscript 
func _end_model_drag(mouse_pos: Vector2) -> void:
    # ... position calculation ...
    var action = {
        "type": "SET_MODEL_DEST",  # Immediately commits
        "actor_unit_id": active_unit_id,
        "payload": {"model_id": selected_model.model_id, "dest": [world_pos.x, world_pos.y]}
    }
    emit_signal("move_action_requested", action)
```

**Required changes:**
```gdscript
func _end_model_drag(mouse_pos: Vector2) -> void:
    # ... position calculation ...
    var action = {
        "type": "STAGE_MODEL_MOVE",  # NEW: Stage instead of commit
        "actor_unit_id": active_unit_id,  
        "payload": {"model_id": selected_model.model_id, "dest": [world_pos.x, world_pos.y]}
    }
    emit_signal("move_action_requested", action)
```

### Task 4: Update Distance Tracking and UI Display
**Location**: `MovementController.gd:846-873` (movement display methods)

**Current display:**
```gdscript
func _update_movement_display() -> void:
    if move_cap_label:
        move_cap_label.text = "Move: %.1f\"" % move_cap_inches
    if inches_used_label:
        inches_used_label.text = "Used: 0.0\""  # Always shows 0
```

**Required changes:**
```gdscript
func _update_movement_display() -> void:
    var accumulated = _get_accumulated_distance()  # NEW: Get staged distance
    if move_cap_label:
        move_cap_label.text = "Move: %.1f\"" % move_cap_inches
    if inches_used_label:
        inches_used_label.text = "Staged: %.1f\"" % accumulated  # Show accumulated
    if inches_left_label:
        inches_left_label.text = "Left: %.1f\"" % (move_cap_inches - accumulated)
```

### Task 5: Add Visual Feedback for Staged Movement
**Location**: `MovementController.gd:790-843` (visual methods)

**Required implementation:**
1. Modify path visualization to show staged movements with different color
2. Add visual distinction between confirmed and staged model positions
3. Update ghost visual to reflect accumulated movement

**Visual enhancement:**
```gdscript
func _update_staged_path_visual() -> void:
    # Show all staged movements as connected path
    # Use different color (e.g., YELLOW) to distinguish from confirmed moves
    staged_path_visual.default_color = Color.YELLOW
```

### Task 6: Enhance Confirmation System  
**Location**: `MovementPhase.gd:442-500` (CONFIRM_UNIT_MOVE processing)

**Required modifications:**
1. Convert all staged_moves to model_moves when confirming
2. Update accumulated distance tracking
3. Clear staged movement state after confirmation

**Confirmation logic:**
```gdscript
func _process_confirm_unit_move(action: Dictionary) -> Dictionary:
    # ... existing logic ...
    
    # NEW: Convert staged moves to permanent moves
    for staged_move in move_data.staged_moves:
        move_data.model_moves.append(staged_move)
    
    # Clear staging area
    move_data.staged_moves.clear()
    move_data.accumulated_distance = 0.0
```

## Implementation Approach

### Step 1: Extend Movement State Structure
```gdscript
# Add to MovementPhase.gd active_moves initialization
"staged_moves": [],
"accumulated_distance": 0.0,
"original_positions": {}  # Track starting positions for reset
```

### Step 2: Create STAGE_MODEL_MOVE Action
```gdscript
# Add to MovementPhase.gd action processing
"STAGE_MODEL_MOVE":
    return _process_stage_model_move(action)

func _process_stage_model_move(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    var payload = action.get("payload", {})
    var model_id = payload.get("model_id", "")
    var dest = Vector2(payload.get("dest", [0, 0])[0], payload.get("dest", [0, 0])[1])
    
    var move_data = active_moves[unit_id]
    
    # Calculate distance for this stage
    var current_pos = _get_current_model_position(unit_id, model_id)  # May be staged position
    var distance = Measurement.distance_inches(current_pos, dest)
    
    # Add to staged moves
    move_data.staged_moves.append({
        "model_id": model_id,
        "from": current_pos,
        "dest": dest,
        "distance": distance
    })
    
    # Update accumulated distance
    move_data.accumulated_distance += distance
    
    # Return visual update (don't modify game state yet)
    return create_result(true, [], "", {"staged": true})
```

### Step 3: Modify Controller Drag Logic
```gdscript
# Update MovementController._end_model_drag()
if valid:
    var action = {
        "type": "STAGE_MODEL_MOVE",  # Changed from SET_MODEL_DEST
        "actor_unit_id": active_unit_id,
        "payload": {
            "model_id": selected_model.model_id,
            "dest": [world_pos.x, world_pos.y]
        }
    }
    emit_signal("move_action_requested", action)
```

### Step 4: Update Reset Functionality
```gdscript
# Modify RESET_UNIT_MOVE to clear staged moves
func _process_reset_unit_move(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    var move_data = active_moves[unit_id]
    
    # Clear staged moves (NEW)
    move_data.staged_moves.clear()
    move_data.accumulated_distance = 0.0
    
    # Reset permanent moves (existing logic)
    # ... existing reset logic ...
```

## Validation Gates

### Pre-Implementation Validation
```bash
# Verify current movement system works
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --check-only

# Run existing movement tests  
godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests/phases -gfile=test_movement_phase.gd
```

### Post-Implementation Validation
```bash
# Test game functionality
godot --debug

# Manual test sequence:
# 1. Start movement phase
# 2. Select unit with 6" movement  
# 3. Drag model 3" → should show "Staged: 3.0\", Left: 3.0\""
# 4. Drag model another 3" → should show "Staged: 6.0\", Left: 0.0\""
# 5. Reset → should clear staged moves
# 6. Drag 3" again → Confirm → should finalize movement
```

### Integration Test Cases
```gdscript
# Add to test_movement_phase.gd
func test_multi_step_movement():
    # Test partial movement staging
    # Test distance accumulation
    # Test reset functionality  
    # Test confirmation finalizes movements
    # Test validation prevents over-movement
```

## Success Criteria

1. **Primary Goal**: Allow multiple drag operations for a single unit before confirmation
2. **Distance Tracking**: Accumulated distance displayed correctly across multiple drags  
3. **Confirmation System**: Only "Confirm Move" finalizes the movement to game state
4. **Reset Functionality**: Reset clears all staged movements back to start position
5. **Validation**: System prevents total staged movement from exceeding movement cap
6. **Visual Feedback**: Clear distinction between staged and confirmed movements
7. **No Regression**: Existing single-drag-confirm workflow continues to work

## Risk Assessment

### Low Risk
- **State Management**: Following established active_moves pattern
- **Distance Calculation**: Reusing existing Measurement utilities
- **UI Patterns**: Following MovementController conventions

### Medium Risk
- **Action Validation**: Need to ensure staged moves don't bypass validation rules
- **Visual Synchronization**: UI must stay synchronized with staged movement state
- **Edge Cases**: Reset/undo interactions with staged movements

### High Risk  
- **Phase State Management**: Staged movements must clear properly on phase exit
- **Save/Load Compatibility**: Staged movements should not persist in saves

### Mitigation Strategies
- Extensive testing of stage→confirm→reset workflows
- Clear staged state on phase transitions  
- Add debug logging for state transitions
- Test save/load to ensure no staged state persistence

## Quality Score: 8/10

**Confidence Level**: High
- **Clear Problem**: Well-defined user experience issue with obvious solution path
- **Established Patterns**: Existing movement system provides solid foundation
- **External Validation**: Warhammer rules support movement flexibility
- **Technical Feasibility**: Staged state pattern is proven approach

**Potential Issues**: 
- State management complexity with staged vs permanent moves (1 point deducted)
- Visual feedback synchronization challenges (1 point deducted)

**Implementation Path**: This PRP provides comprehensive context for one-pass implementation with all necessary patterns, validation gates, and risk mitigation strategies for successfully implementing multi-step movement functionality.