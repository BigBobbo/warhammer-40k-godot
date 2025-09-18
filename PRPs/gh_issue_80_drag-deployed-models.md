# PRP: Drag Placed Models in Deployment Phase
**GitHub Issue:** #80
**Feature Name:** Deployment Model Repositioning
**Author:** Claude Code AI
**Date:** 2025-09-18
**Confidence Score:** 8/10

## Problem Statement

When deploying units with multiple models, users may want to reposition some models after initial placement. Currently, once a model is placed during deployment, it cannot be moved until the movement phase. This creates friction when users want to adjust positioning for tactical reasons or to optimize unit coherency before confirming deployment.

## Requirements Analysis

### Core Requirements (from GitHub Issue #80):
1. **Shift+Drag Interaction**: Hold shift and drag on a deployed model within the same squad to reposition it
2. **Ghost Visual Feedback**: Show a ghost visual during dragging (similar to movement phase)
3. **Deployment Rule Validation**: Ensure repositioned models follow deployment rules:
   - Must remain within deployment zone
   - Cannot overlap with other models
   - Must maintain unit coherency
4. **Same Squad Restriction**: Only allow repositioning models within the same unit that's currently being deployed

### Warhammer 40k Context:
- **Deployment Zone**: All models must be wholly within the player's deployment zone
- **Unit Coherency**: Models must stay within 2" horizontal distance from at least one other model in the unit
- **No Overlapping**: Model bases cannot overlap with any other models from any unit
- **Shape Awareness**: Support circular, rectangular, and oval base shapes

## Current System Analysis

### Deployment Architecture:
- **DeploymentController.gd** (/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/DeploymentController.gd)
  - Manages single model placement (lines 109-157)
  - Handles ghost visuals (lines 290-327)
  - Validates positions and overlaps (lines 462-490)
  - Current placement state: `temp_positions[]` and `temp_rotations[]`

- **DeploymentPhase.gd** (/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/DeploymentPhase.gd)
  - Validates deployment actions (lines 59-97)
  - Position validation with zones (lines 99-123)
  - Overlap checking (lines 355-371)

- **GhostVisual.gd** (/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/GhostVisual.gd)
  - Provides visual feedback during placement
  - Shows validity with color coding (lines 15-29)
  - Supports rotation and shape awareness (lines 31-42)

### Key Code Patterns:

#### Current Model Placement System:
```gdscript
# DeploymentController.gd:109-157
func try_place_at(world_pos: Vector2) -> void:
    # Validate position within deployment zone
    var is_in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)

    # Check for overlaps
    if _overlaps_with_existing_models_shape(world_pos, model_data, rotation):
        _show_toast("Cannot overlap with existing models")
        return

    # Store position
    temp_positions[model_idx] = world_pos
    temp_rotations[model_idx] = rotation
    _spawn_preview_token(unit_id, model_idx, world_pos, rotation)
```

#### Existing Ghost Visual Pattern:
```gdscript
# DeploymentController.gd:290-327
func _create_ghost() -> void:
    ghost_sprite = preload("res://scripts/GhostVisual.gd").new()
    var model_data = unit_data["models"][model_idx]
    ghost_sprite.radius = Measurement.base_radius_px(base_mm)
    ghost_sprite.set_model_data(model_data)
    ghost_layer.add_child(ghost_sprite)
```

## Technical Research

### Movement Phase Drag Patterns:
The MovementController.gd demonstrates comprehensive drag mechanics:

```gdscript
# MovementController.gd:1012-1063 (drag start)
func _start_model_drag(mouse_pos: Vector2) -> void:
    selected_model = model
    dragging_model = true
    drag_start_pos = model.position
    _show_ghost_visual(model)

# MovementController.gd:1064-1111 (drag update)
func _update_model_drag(mouse_pos: Vector2) -> void:
    current_path = [drag_start_pos, world_pos]
    _update_ghost_position(world_pos)
    _update_ghost_validity(!overlap_detected)

# MovementController.gd:1112-1181 (drag end)
func _end_model_drag(mouse_pos: Vector2) -> void:
    dragging_model = false
    _clear_ghost_visual()
```

### Shift Key Input Pattern:
```gdscript
# MovementController.gd:961
elif Input.is_key_pressed(KEY_SHIFT) and _should_start_drag_box():
    _start_drag_box_selection(event.position)
```

### Token Click Detection Pattern:
```gdscript
# MovementController.gd:2005-2035
func _is_clicking_on_model(world_pos: Vector2) -> bool:
    var units = GameState.state.get("units", {})
    for unit_id in units:
        var unit = units[unit_id]
        for model in unit["models"]:
            var model_pos = Vector2(model_position.x, model_position.y)
            var distance = world_pos.distance_to(model_pos)
            var model_radius = Measurement.base_radius_px(model["base_mm"])
            if distance <= model_radius:
                return true
```

## Implementation Strategy

### Phase 1: Drag State Management

#### 1.1 Add Drag State Variables
Add to DeploymentController.gd:
```gdscript
# Model repositioning state
var repositioning_model: bool = false
var reposition_model_index: int = -1
var reposition_start_pos: Vector2
var reposition_ghost: Node2D = null
```

#### 1.2 Model Detection Function
```gdscript
func _get_deployed_model_at_position(world_pos: Vector2) -> Dictionary:
    """Find deployed model from current unit at given position"""
    if unit_id == "" or temp_positions.is_empty():
        return {}

    var unit_data = GameState.get_unit(unit_id)
    for i in range(temp_positions.size()):
        if temp_positions[i] != null:  # Model is placed
            var model_pos = temp_positions[i]
            var model_data = unit_data["models"][i]
            var base_mm = model_data.get("base_mm", 32)
            var radius = Measurement.base_radius_px(base_mm)

            if world_pos.distance_to(model_pos) <= radius:
                return {
                    "model_index": i,
                    "position": model_pos,
                    "model_data": model_data
                }

    return {}
```

### Phase 2: Input Handling Integration

#### 2.1 Modify Input Handler
Update _unhandled_input() in DeploymentController.gd:
```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if not is_placing():
        return

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            var mouse_pos = _get_world_mouse_position()

            # Check for shift+click on deployed model for repositioning
            if Input.is_key_pressed(KEY_SHIFT):
                var deployed_model = _get_deployed_model_at_position(mouse_pos)
                if not deployed_model.is_empty():
                    _start_model_repositioning(deployed_model)
                    return

            # Handle repositioning end
            if repositioning_model:
                _end_model_repositioning(mouse_pos)
                return

            # Normal placement logic
            if formation_mode != "SINGLE":
                try_place_formation_at(mouse_pos)
            else:
                try_place_at(mouse_pos)

        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            # Cancel repositioning on right-click
            if repositioning_model:
                _cancel_model_repositioning()

    elif event is InputEventMouseMotion:
        if repositioning_model:
            _update_model_repositioning(event.position)
```

### Phase 3: Repositioning Logic

#### 3.1 Start Repositioning
```gdscript
func _start_model_repositioning(deployed_model: Dictionary) -> void:
    """Begin repositioning a deployed model"""
    repositioning_model = true
    reposition_model_index = deployed_model.model_index
    reposition_start_pos = deployed_model.position

    print("Starting repositioning of model ", reposition_model_index)

    # Create ghost visual for repositioning
    var model_data = deployed_model.model_data
    reposition_ghost = preload("res://scripts/GhostVisual.gd").new()
    reposition_ghost.name = "RepositionGhost"
    reposition_ghost.radius = Measurement.base_radius_px(model_data.get("base_mm", 32))
    reposition_ghost.owner_player = GameState.get_active_player()
    reposition_ghost.set_model_data(model_data)
    ghost_layer.add_child(reposition_ghost)

    # Hide the original token during repositioning
    var token_name = "Token_%s_%d" % [unit_id, reposition_model_index]
    var token = token_layer.get_node_or_null(token_name)
    if token:
        token.modulate.a = 0.3  # Make original semi-transparent
```

#### 3.2 Update Repositioning
```gdscript
func _update_model_repositioning(mouse_pos: Vector2) -> void:
    """Update ghost position during repositioning"""
    if not repositioning_model or not reposition_ghost:
        return

    var world_pos = _get_world_mouse_position()
    reposition_ghost.position = world_pos

    # Validate new position
    var unit_data = GameState.get_unit(unit_id)
    var model_data = unit_data["models"][reposition_model_index]
    var is_valid = _validate_reposition(world_pos, model_data, reposition_model_index)

    reposition_ghost.set_validity(is_valid)
```

#### 3.3 Validation for Repositioning
```gdscript
func _validate_reposition(world_pos: Vector2, model_data: Dictionary, model_index: int) -> bool:
    """Validate if repositioning is allowed at the given position"""
    var active_player = GameState.get_active_player()
    var zone = BoardState.get_deployment_zone_for_player(active_player)
    var base_type = model_data.get("base_type", "circular")

    # Check deployment zone
    var in_zone = false
    if base_type == "circular":
        var radius_px = Measurement.base_radius_px(model_data["base_mm"])
        in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)
    else:
        var rotation = temp_rotations[model_index] if model_index < temp_rotations.size() else 0.0
        in_zone = _shape_wholly_in_polygon(world_pos, model_data, rotation, zone)

    if not in_zone:
        return false

    # Check overlap (excluding the model being repositioned)
    return not _would_overlap_excluding_self(world_pos, model_data, model_index)

func _would_overlap_excluding_self(pos: Vector2, model_data: Dictionary, exclude_index: int) -> bool:
    """Check for overlaps excluding the model being repositioned"""
    var shape = Measurement.create_base_shape(model_data)
    if not shape:
        return false

    # Check overlap with other models in current unit (excluding self)
    var unit_data = GameState.get_unit(unit_id)
    for i in range(temp_positions.size()):
        if i != exclude_index and temp_positions[i] != null:
            var other_model_data = unit_data["models"][i]
            var other_rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0
            var self_rotation = temp_rotations[exclude_index] if exclude_index < temp_rotations.size() else 0.0
            if _shapes_overlap(pos, model_data, self_rotation, temp_positions[i], other_model_data, other_rotation):
                return true

    # Check overlap with all deployed models from other units
    var all_units = GameState.state.get("units", {})
    for other_unit_id in all_units:
        if other_unit_id == unit_id:
            continue  # Skip current unit, already checked above

        var other_unit = all_units[other_unit_id]
        if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
            for model in other_unit["models"]:
                var model_position = model.get("position", null)
                if model_position:
                    var other_pos = Vector2(model_position.x, model_position.y)
                    var other_rotation = model.get("rotation", 0.0)
                    var self_rotation = temp_rotations[exclude_index] if exclude_index < temp_rotations.size() else 0.0
                    if _shapes_overlap(pos, model_data, self_rotation, other_pos, model, other_rotation):
                        return true

    return false
```

#### 3.4 Complete Repositioning
```gdscript
func _end_model_repositioning(mouse_pos: Vector2) -> void:
    """Complete model repositioning"""
    if not repositioning_model:
        return

    var world_pos = _get_world_mouse_position()
    var unit_data = GameState.get_unit(unit_id)
    var model_data = unit_data["models"][reposition_model_index]

    # Validate final position
    if _validate_reposition(world_pos, model_data, reposition_model_index):
        # Update position
        temp_positions[reposition_model_index] = world_pos

        # Update the token position
        var token_name = "Token_%s_%d" % [unit_id, reposition_model_index]
        var token = token_layer.get_node_or_null(token_name)
        if token:
            token.position = world_pos
            token.modulate.a = 1.0  # Restore full opacity

        print("Model ", reposition_model_index, " repositioned to ", world_pos)
        emit_signal("models_placed_changed")
        _check_coherency_warning()
    else:
        # Revert to original position
        var token_name = "Token_%s_%d" % [unit_id, reposition_model_index]
        var token = token_layer.get_node_or_null(token_name)
        if token:
            token.modulate.a = 1.0  # Restore full opacity
        _show_toast("Invalid position for repositioning")

    _cleanup_repositioning()

func _cancel_model_repositioning() -> void:
    """Cancel model repositioning and restore original state"""
    if not repositioning_model:
        return

    # Restore original token opacity
    var token_name = "Token_%s_%d" % [unit_id, reposition_model_index]
    var token = token_layer.get_node_or_null(token_name)
    if token:
        token.modulate.a = 1.0

    _cleanup_repositioning()

func _cleanup_repositioning() -> void:
    """Clean up repositioning state"""
    repositioning_model = false
    reposition_model_index = -1
    reposition_start_pos = Vector2.ZERO

    if reposition_ghost and is_instance_valid(reposition_ghost):
        reposition_ghost.queue_free()
        reposition_ghost = null
```

### Phase 4: Process Integration

#### 4.1 Update Process Loop
Modify _process() in DeploymentController.gd:
```gdscript
func _process(delta: float) -> void:
    if not is_placing():
        return

    var mouse_pos = _get_world_mouse_position()

    # Handle repositioning ghost updates
    if repositioning_model and reposition_ghost:
        reposition_ghost.position = mouse_pos
        var unit_data = GameState.get_unit(unit_id)
        var model_data = unit_data["models"][reposition_model_index]
        var is_valid = _validate_reposition(mouse_pos, model_data, reposition_model_index)
        reposition_ghost.set_validity(is_valid)
        return

    # Handle formation mode ghost updates
    if formation_mode != "SINGLE" and not formation_preview_ghosts.is_empty():
        _update_formation_ghost_positions(mouse_pos)
        return

    # Handle single mode ghost updates (existing code)
    if ghost_sprite != null and model_idx < temp_positions.size():
        # ... existing ghost update logic
```

## Validation Plan

### Unit Tests:
```gdscript
# test_deployment_repositioning.gd
extends "res://tests/helpers/BasePhaseTest.gd"

func test_shift_click_detection():
    """Test that shift+click properly detects deployed models"""
    var dc = setup_deployment_controller()
    dc.begin_deploy("test_unit")

    # Place a model first
    dc.try_place_at(Vector2(400, 400))

    # Test shift+click detection
    Input.set_key_pressed(KEY_SHIFT, true)
    var deployed_model = dc._get_deployed_model_at_position(Vector2(405, 405))
    assert_false(deployed_model.is_empty(), "Should detect deployed model")
    assert_eq(deployed_model.model_index, 0, "Should detect first model")

func test_repositioning_validation():
    """Test that repositioning follows deployment rules"""
    var dc = setup_deployment_controller()
    dc.begin_deploy("test_unit")

    # Place initial model
    dc.try_place_at(Vector2(400, 400))

    # Test valid repositioning
    var valid_pos = Vector2(450, 450)
    var is_valid = dc._validate_reposition(valid_pos, test_model_data, 0)
    assert_true(is_valid, "Valid repositioning should pass")

    # Test invalid repositioning (outside zone)
    var invalid_pos = Vector2(100, 100)  # Outside deployment zone
    var is_invalid = dc._validate_reposition(invalid_pos, test_model_data, 0)
    assert_false(is_invalid, "Invalid repositioning should fail")

func test_overlap_prevention():
    """Test that repositioning prevents overlaps"""
    var dc = setup_deployment_controller()
    dc.begin_deploy("test_unit")

    # Place two models
    dc.try_place_at(Vector2(400, 400))
    dc.try_place_at(Vector2(500, 400))

    # Try to reposition first model to overlap with second
    var overlap_pos = Vector2(505, 405)  # Close to second model
    var would_overlap = dc._would_overlap_excluding_self(overlap_pos, test_model_data, 0)
    assert_true(would_overlap, "Should detect overlap during repositioning")

func test_coherency_maintenance():
    """Test that repositioning maintains unit coherency"""
    var dc = setup_deployment_controller()
    dc.begin_deploy("large_unit")  # Unit with 10 models

    # Place models in tight formation
    for i in range(5):
        dc.try_place_at(Vector2(400 + i * 65, 400))

    # Reposition one model far away
    dc._start_model_repositioning({"model_index": 2, "position": Vector2(465, 400), "model_data": test_model_data})
    dc._end_model_repositioning(Vector2(600, 600))  # Far from others

    # Should trigger coherency warning
    # Note: This tests the warning system, actual deployment validation might prevent this
```

### Integration Tests:
```bash
# Run after implementation
godot --headless -s 40k/tests/ui/test_deployment_repositioning.gd
godot --headless -s 40k/tests/phases/test_deployment_phase.gd
```

## Implementation Tasks

1. **Add Repositioning State Management** (DeploymentController.gd)
   - Add drag state variables for repositioning
   - Create model detection function
   - Add validation function excluding self-overlap

2. **Implement Shift+Click Input Handling** (DeploymentController.gd)
   - Modify _unhandled_input() to detect shift+click
   - Add repositioning start/update/end functions
   - Handle right-click cancellation

3. **Create Repositioning Ghost System** (DeploymentController.gd)
   - Create ghost visual during repositioning
   - Update ghost position and validity
   - Hide/show original token during drag

4. **Update Process Loop** (DeploymentController.gd)
   - Handle repositioning ghost updates in _process()
   - Maintain priority order (repositioning > formation > single)

5. **Add Position Validation** (DeploymentController.gd)
   - Create repositioning-specific validation
   - Exclude repositioned model from overlap checks
   - Maintain deployment zone and coherency rules

6. **Create Unit Tests** (test_deployment_repositioning.gd)
   - Test shift+click detection
   - Test validation logic
   - Test overlap prevention
   - Test coherency maintenance

7. **Integration Testing**
   - Test with different base shapes
   - Test with formation mode enabled
   - Test edge cases (single model units)

## External Documentation References

- Warhammer 40k Deployment Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Deployment
- Godot Input Handling: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html
- Godot Node2D Positioning: https://docs.godotengine.org/en/4.4/classes/class_node2d.html

## Risk Mitigation

1. **Input Conflicts**: Use shift key consistently with existing movement phase patterns
2. **State Management**: Clear repositioning state on phase exit or unit cancellation
3. **Visual Feedback**: Ensure ghost visual is always cleaned up properly
4. **Performance**: Limit repositioning to current unit only to reduce validation overhead
5. **User Experience**: Provide clear visual feedback and error messages

## Success Criteria

1. Shift+click on deployed model starts repositioning mode
2. Ghost visual shows during drag with validity indication
3. Models can only be repositioned within deployment zone
4. Repositioned models cannot overlap with existing models
5. Unit coherency warnings still function after repositioning
6. Right-click cancels repositioning
7. Works with all base shapes (circular, rectangular, oval)
8. Integrates smoothly with existing formation deployment

## Confidence Assessment: 8/10

High confidence due to:
- Clear existing drag patterns in MovementController
- Well-established ghost visual system
- Comprehensive validation logic already present
- Input handling patterns already established

Moderate uncertainty around:
- Exact interaction priority with formation mode
- Performance impact of additional validation checks
- Edge cases with very large units

Minor concerns:
- Complexity of state management with multiple interaction modes
- Potential UI conflicts if users accidentally trigger repositioning