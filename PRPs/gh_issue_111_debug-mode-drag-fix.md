# PRP: Fix Debug Mode Model Dragging with Multiplayer Sync

## Issue Information
- **Issue Number**: #111
- **Title**: Fix debug mode model dragging and add multiplayer synchronization
- **Priority**: High
- **Confidence Score**: 9/10

## Executive Summary
Debug mode (activated by pressing 9) is not allowing users to drag models freely as intended. The issue stems from missing ghost visual creation in the DebugManager and lack of multiplayer synchronization for debug movements. This PRP addresses both issues by implementing proper ghost visual handling and integrating with the NetworkManager for state synchronization.

## Problem Analysis

### Current State
1. **Debug Mode Activation Works**: KEY_9 in `Main.gd:1221` correctly calls `DebugManager.toggle_debug_mode()`
2. **Input Handling Exists**: `DebugManager._unhandled_input()` (lines 83-98) processes mouse events
3. **Visual Overlay Works**: Debug mode shows "DEBUG MODE ACTIVE" overlay properly
4. **MovementController Defers**: Correctly returns early when debug mode is active (line 1059)

### Root Causes Identified

#### Issue 1: Missing Ghost Visual Creation
**Location**: `40k/autoloads/DebugManager.gd:100-141`

The debug drag system tries to update ghost visuals but never creates them:
```gdscript
# Line 100: _start_debug_drag() is called
# Line 110: _highlight_dragged_model(model) is called but is empty (line 283)
# Line 119: _update_ghost_position(world_pos) tries to find ghost but it doesn't exist
# Line 287-296: _update_ghost_position() looks for ghost in GhostLayer but none exists
```

**Evidence**:
- `_highlight_dragged_model()` at line 283 is a stub with just `pass`
- `_update_ghost_position()` at line 287 tries to access `ghost_layer.get_child(0)` but no ghost was created
- Recent commit a8038d8 improved ghost visual creation in MovementController/ChargeController but DebugManager wasn't updated

#### Issue 2: No Multiplayer Synchronization
**Location**: `40k/autoloads/DebugManager.gd:174-191`

Debug mode updates GameState directly without network sync:
```gdscript
func _update_model_position_debug(unit_id: String, model_id: String, new_position: Vector2) -> void:
    # ... directly modifies GameState.state.units[unit_id]["models"][i]["position"]
    # No NetworkManager.submit_action() call
```

**Evidence**:
- `40k/autoloads/NetworkManager.gd` shows all other model movements use `submit_action()` pattern
- Debug movements bypass the network layer entirely
- Opponent in multiplayer won't see debug position changes

#### Issue 3: No Visual Refresh After Drag
**Location**: `40k/autoloads/DebugManager.gd:139-140`

After updating model position, visual refresh is called but may not work properly:
```gdscript
# Line 137: _clear_drag_visuals() removes ghost (if it existed)
# Line 140: _refresh_board_visuals() calls Main._recreate_unit_visuals()
```

The refresh might not work if Main scene isn't set up properly.

## Requirements

### Functional Requirements
1. **FR1**: Press 9 to toggle debug mode (ALREADY WORKS)
2. **FR2**: Click and drag any model from either army without restrictions
3. **FR3**: Show ghost visual during drag operation
4. **FR4**: Update model position on mouse release
5. **FR5**: Sync position changes to opponent in multiplayer games
6. **FR6**: Visual feedback that drag is occurring
7. **FR7**: Exit debug mode with 9 key (ALREADY WORKS)

### Technical Requirements
1. **TR1**: Create GhostVisual instance when starting debug drag
2. **TR2**: Use proper model data for ghost shape/size
3. **TR3**: Integrate with NetworkManager for multiplayer sync
4. **TR4**: Ensure visual updates on both host and client
5. **TR5**: Clean up ghost visuals properly
6. **TR6**: Don't interfere with normal phase operations

## Implementation Design

### Architecture Overview

```
User presses 9 → DebugManager.toggle_debug_mode()
                      ↓
                 Debug overlay shown
                 Tokens get debug styling
                      ↓
User clicks model → DebugManager._start_debug_drag()
                      ↓
                 Create GhostVisual (NEW)
                 Show at model position
                      ↓
User moves mouse → DebugManager._update_debug_drag()
                      ↓
                 Update ghost position
                      ↓
User releases → DebugManager._end_debug_drag()
                      ↓
                 NetworkManager.submit_action() (NEW)
                      ↓
                 Clear ghost visual
                 Refresh board visuals
```

### Key Changes Required

#### Change 1: Implement Ghost Visual Creation
**File**: `40k/autoloads/DebugManager.gd`

Add ghost visual creation to `_start_debug_drag()`:
```gdscript
func _start_debug_drag(screen_pos: Vector2) -> void:
    var world_pos = _screen_to_world_position(screen_pos)
    var model = _find_model_at_position_debug(world_pos)

    if not model.is_empty():
        debug_drag_active = true
        debug_selected_model = model
        DebugLogger.debug("Started dragging %s from unit %s" % [model.model_id, model.unit_id])

        # NEW: Create ghost visual
        _create_debug_ghost(model)

func _create_debug_ghost(model_data: Dictionary) -> void:
    """Create a ghost visual for the dragged model"""
    var main_node = get_node_or_null("/root/Main")
    if not main_node:
        return

    var ghost_layer = main_node.get_node_or_null("BoardRoot/GhostLayer")
    if not ghost_layer:
        return

    # Clear any existing ghosts
    for child in ghost_layer.get_children():
        child.queue_free()

    # Get full model data from GameState for proper shape
    var full_model = _get_full_model_data(model_data.unit_id, model_data.model_id)
    if full_model.is_empty():
        return

    # Create GhostVisual instance
    var ghost_scene = load("res://scenes/GhostVisual.tscn")
    var ghost = ghost_scene.instantiate()

    # Get unit for player ownership
    var unit = GameState.state.units.get(model_data.unit_id, {})
    ghost.owner_player = unit.get("owner", 1)

    # Set model data for proper shape/size
    ghost.set_model_data(full_model)

    # Position at model's current location
    ghost.position = model_data.position
    ghost.set_validity(true)  # Debug mode allows any position

    ghost_layer.add_child(ghost)

func _get_full_model_data(unit_id: String, model_id: String) -> Dictionary:
    """Get complete model data including base_type and dimensions"""
    if not GameState.state.units.has(unit_id):
        return {}

    var unit = GameState.state.units[unit_id]
    for model in unit.get("models", []):
        if model.get("id") == model_id:
            return model

    return {}
```

#### Change 2: Add Multiplayer Synchronization
**File**: `40k/autoloads/DebugManager.gd`

Integrate with NetworkManager for state sync:
```gdscript
func _end_debug_drag(screen_pos: Vector2) -> void:
    if not debug_drag_active or debug_selected_model.is_empty():
        return

    var world_pos = _screen_to_world_position(screen_pos)

    # Update model position via NetworkManager if in multiplayer
    if NetworkManager and NetworkManager.is_networked():
        _update_model_position_networked(debug_selected_model.unit_id, debug_selected_model.model_id, world_pos)
    else:
        # Single-player: update directly
        _update_model_position_debug(debug_selected_model.unit_id, debug_selected_model.model_id, world_pos)

    DebugLogger.debug("Moved model %s to %s" % [debug_selected_model.model_id, world_pos])

    # Clear drag state
    debug_drag_active = false
    debug_selected_model.clear()

    # Clear visual feedback
    _clear_drag_visuals()

    # Trigger visual refresh
    _refresh_board_visuals()

func _update_model_position_networked(unit_id: String, model_id: String, new_position: Vector2) -> void:
    """Update model position via NetworkManager for multiplayer sync"""
    # Create a DEBUG_MOVE action
    var action = {
        "type": "DEBUG_MOVE",
        "unit_id": unit_id,
        "model_id": model_id,
        "position": [new_position.x, new_position.y],
        "player": GameState.get_active_player(),  # Use current player for validation
        "timestamp": Time.get_ticks_msec()
    }

    # Submit through NetworkManager
    NetworkManager.submit_action(action)
```

#### Change 3: Add DEBUG_MOVE Action Handler
**File**: `40k/autoloads/GameManager.gd`

Add handler for debug move actions:
```gdscript
func apply_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    # ... existing action handlers ...

    if action_type == "DEBUG_MOVE":
        return _handle_debug_move(action)

    # ... rest of function ...

func _handle_debug_move(action: Dictionary) -> Dictionary:
    """Handle debug mode model movement"""
    var unit_id = action.get("unit_id", "")
    var model_id = action.get("model_id", "")
    var position = action.get("position", [])

    if unit_id == "" or model_id == "" or position.size() != 2:
        return _error_result("Invalid DEBUG_MOVE action data")

    # Validate unit exists
    if not GameState.state.units.has(unit_id):
        return _error_result("Unit not found: " + unit_id)

    var unit = GameState.state.units[unit_id]
    var models = unit.get("models", [])

    # Find and update model
    var model_found = false
    for i in range(models.size()):
        if models[i].get("id") == model_id:
            var old_pos = models[i].get("position", {})
            models[i]["position"] = {
                "x": position[0],
                "y": position[1]
            }
            model_found = true

            # Create diff for network sync
            var diff = {
                "path": ["units", unit_id, "models", i, "position"],
                "old_value": old_pos,
                "new_value": models[i]["position"]
            }

            return _success_result(action, [diff])

    if not model_found:
        return _error_result("Model not found: " + model_id)

    return _success_result(action, [])
```

#### Change 4: Add Debug Move Validation
**File**: `40k/phases/BasePhase.gd` (or create DebugPhase.gd)

Add validation for debug moves:
```gdscript
# In BasePhase or any phase's validate_action
func validate_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    # Debug mode bypasses normal validation
    if action_type == "DEBUG_MOVE":
        # Only check if debug mode is active
        if DebugManager and DebugManager.is_debug_active():
            return {"valid": true}
        else:
            return {"valid": false, "reason": "Debug mode not active"}

    # ... existing validation ...
```

## Implementation Tasks

### Task 1: Fix Ghost Visual Creation
**Files**: `40k/autoloads/DebugManager.gd`
1. Implement `_create_debug_ghost()` method
2. Implement `_get_full_model_data()` helper
3. Update `_start_debug_drag()` to call `_create_debug_ghost()`
4. Test ghost appears with correct shape/size

### Task 2: Add Multiplayer Synchronization
**Files**: `40k/autoloads/DebugManager.gd`, `40k/autoloads/GameManager.gd`
1. Implement `_update_model_position_networked()` method
2. Add `_handle_debug_move()` to GameManager
3. Update `_end_debug_drag()` to check for multiplayer
4. Test in both single-player and multiplayer

### Task 3: Add Action Validation
**Files**: `40k/phases/BasePhase.gd`
1. Add DEBUG_MOVE validation case
2. Check debug mode is active
3. Test validation passes in debug mode

### Task 4: Improve Visual Feedback
**Files**: `40k/autoloads/DebugManager.gd`
1. Enhance `_highlight_dragged_model()` to add visual indicator
2. Ensure `_clear_drag_visuals()` properly cleans up
3. Test visual feedback is clear

### Task 5: Integration Testing
**Files**: Test files
1. Test single-player debug drag
2. Test multiplayer debug drag (both host and client)
3. Test ghost visual appearance
4. Test position sync across network
5. Test exit from debug mode cleans up properly

## Validation Gates

### Manual Testing
```bash
# Start game in single-player
export PATH="$HOME/bin:$PATH"
godot 40k/project.godot

# Test sequence:
# 1. Load a game or start new game
# 2. Press 9 to enter debug mode
# 3. Click and drag a model
# 4. Verify ghost appears during drag
# 5. Release to drop model
# 6. Verify model moves to new position
# 7. Verify visual updates properly
# 8. Press 9 to exit debug mode
```

### Multiplayer Testing
```bash
# Host game (Terminal 1)
godot 40k/project.godot
# -> Go to multiplayer lobby
# -> Host game
# -> Load armies
# -> Start game
# -> Press 9 to enter debug mode
# -> Drag a model

# Join game (Terminal 2)
godot 40k/project.godot
# -> Go to multiplayer lobby
# -> Join game
# -> Verify you see debug mode activate when host presses 9
# -> Verify you see model move when host drags it
# -> Press 9 to activate debug mode on client
# -> Drag a model
# -> Verify host sees the movement
```

### Automated Testing
```bash
# Run debug mode tests
export PATH="$HOME/bin:$PATH"
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/integration/test_debug_mode_integration.gd

# Check for errors
grep -i "error\|failed" test_results/test_debug_mode_integration.log
```

## External References

### Godot Documentation
- Input Handling: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html
- Multiplayer RPCs: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- Node2D Transform: https://docs.godotengine.org/en/4.4/classes/class_node2d.html#class-node2d-property-transform

### Existing Code Patterns
- Ghost Visual Creation: `40k/scripts/MovementController.gd:1450-1520` (recent fix in commit a8038d8)
- Network Action Submission: `40k/autoloads/NetworkManager.gd:103-143`
- Action Handling: `40k/autoloads/GameManager.gd:apply_action()`
- Model Finding: `40k/scripts/MovementController.gd:1300-1350`

### Related PRPs
- PRP gh_issue_14_debug-mode.md: Original debug mode implementation
- PRP gh_issue_89_multiplayer.md: Multiplayer synchronization architecture
- PRP gh_issue_drag-ghost-size-fix.md: Recent ghost visual improvements

## Success Criteria

- [ ] Press 9 activates debug mode with visual overlay
- [ ] Click and drag any model shows ghost visual during drag
- [ ] Ghost visual has correct shape and size (circular, oval, etc.)
- [ ] Mouse release updates model position in GameState
- [ ] Position change syncs to opponent in multiplayer
- [ ] Both host and client can use debug mode
- [ ] Visual updates properly on both host and client
- [ ] Ghost visual clears after drag completes
- [ ] Press 9 exits debug mode and restores normal operation
- [ ] No interference with normal phase operations
- [ ] Debug movements logged properly

## Risk Assessment

**Low Risk**:
- Ghost visual creation (well-established pattern exists)
- Network action submission (existing pattern works well)
- Input handling (already implemented, just needs ghost)

**Medium Risk**:
- Visual synchronization timing in multiplayer
- Ghost visual cleanup edge cases
- Interaction with other systems during debug mode

**Mitigation Strategies**:
1. Follow existing ghost creation pattern from MovementController
2. Use same network action pattern as other movements
3. Extensive multiplayer testing with both host and client
4. Add comprehensive logging for troubleshooting
5. Ensure proper cleanup in all code paths

## Implementation Order

1. **Ghost Visual Creation** - Fix the immediate drag issue
2. **Visual Updates** - Ensure ghost updates during drag
3. **Multiplayer Integration** - Add network synchronization
4. **Action Validation** - Add DEBUG_MOVE handler
5. **Testing** - Comprehensive single and multiplayer tests
6. **Polish** - Visual feedback and edge case handling

## Technical Notes

### Ghost Visual Requirements
- Must use `GhostVisual.tscn` scene
- Must call `set_model_data()` with complete model dictionary
- Must include: `base_type`, `base_dimensions`, `position`, `rotation`
- Must be added to `BoardRoot/GhostLayer` node

### Network Synchronization
- Use `NetworkManager.submit_action()` for all position changes
- Action must include `type`, `unit_id`, `model_id`, `position`, `player`
- Host validates via `BasePhase.validate_action()`
- Result broadcasts via `_broadcast_result.rpc()`
- Client applies via `GameManager.apply_result()`

### Debug Mode State
- `DebugManager.debug_mode_active` tracks activation state
- `DebugManager.debug_drag_active` tracks drag operation
- `DebugManager.debug_selected_model` stores current drag target
- All state cleared on exit or drag completion

## Confidence Score: 9/10

**High Confidence Factors**:
- Clear root causes identified (missing ghost creation, no network sync)
- Existing patterns to follow (MovementController ghost, NetworkManager actions)
- Well-structured existing code to integrate with
- Comprehensive research completed

**Risk Factors**:
- Multiplayer timing edge cases (mitigated by existing patterns)
- Visual cleanup in all scenarios (mitigated by testing)

The implementation is straightforward with clear examples to follow. The main complexity is ensuring proper cleanup and network synchronization, both of which have well-established patterns in the codebase.
