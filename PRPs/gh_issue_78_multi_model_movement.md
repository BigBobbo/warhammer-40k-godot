# PRP: Multi-Model Movement System
**GitHub Issue:** #78
**Feature Name:** Multi Move
**Author:** Claude Code AI
**Date:** 2025-09-16

## Problem Statement

Currently, users can only move one model at a time during the Movement Phase. When moving units with multiple models, this becomes tedious as each model must be individually selected and moved. Users need the ability to select and move multiple models within a unit simultaneously while maintaining individual movement tracking and the flexibility for post-move adjustments.

## Requirements Analysis

### Core Requirements (from GitHub Issue #78):
1. **Multi-Model Selection**: Users must be able to select multiple models within a unit
2. **Batch Movement**: Selected models should move together as a group
3. **Individual Tracking**: Movement should count against each model's individual movement maximum
4. **Flexible Selection**: Users should be able to choose which models to include/exclude from group movement
5. **Post-Move Adjustment**: After group movement, remaining movement should be available for individual fine-tuning

### Warhammer 40k Rules Context:
- **Unit Coherency**: Models must maintain formation (2" horizontal, 5" vertical distances)
- **Individual Movement**: Each model can use different amounts of the unit's movement allowance
- **Movement Caps**: Each model respects the same movement cap but can use it independently
- **Formation Integrity**: Units move as cohesive groups but allow tactical positioning

## Current System Analysis

### Existing Movement Architecture:
- **MovementController.gd**: Handles UI interactions and single-model dragging (/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd:955-1127)
- **MovementPhase.gd**: Manages movement validation and state tracking (/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/MovementPhase.gd:512-580)
- **Staged Movement System**: Uses `staged_moves` array to preview before committing movements
- **Individual Distance Tracking**: `model_distances` dictionary tracks per-model movement usage

### Current Selection Pattern:
```gdscript
# From MovementController.gd:986-997
selected_model = model
dragging_model = true
drag_start_pos = model.position
current_path = [drag_start_pos]
```

### Current Movement Validation:
```gdscript
# From MovementPhase.gd:276-281
var total_distance_for_model = Measurement.distance_inches(original_pos, dest_vec)
if total_distance_for_model > move_data.move_cap_inches:
    return {"valid": false, "errors": ["Model exceeds movement cap"]}
```

## Technical Research

### Multi-Selection Patterns (Godot Best Practices):
From external research on Godot RTS-style selection:
```gdscript
# Rectangle-based selection using physics queries
var space = get_world_2d().direct_space_state
var query = PhysicsShapeQueryParameters2D.new()
query.shape = select_rect
query.collision_mask = 2
query.transform = Transform2D(0, (drag_end + drag_start) / 2)
selected = space.intersect_shape(query)
```

### Existing Test Expectations:
The codebase already has test expectations for multi-selection:
- `test_multi_model_selection()`: Ctrl+click pattern (/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/ui/test_model_dragging.gd:112-138)
- `test_drag_selection_box()`: Drag-box selection (/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/ui/test_model_dragging.gd:139-166)

## Implementation Strategy

### Phase 1: Multi-Selection System

#### 1.1 Selection State Management
Add to MovementController.gd:
```gdscript
# Multi-selection state
var selected_models: Array = []  # Array of model dictionaries
var selection_mode: String = "SINGLE"  # SINGLE, MULTI, DRAG_BOX
var drag_box_active: bool = false
var drag_box_start: Vector2
var drag_box_end: Vector2
var selection_visual: NinePatchRect
```

#### 1.2 Input Event Handling Enhancement
Modify `_unhandled_input()` in MovementController.gd:
```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                if Input.is_key_pressed(KEY_CTRL):
                    _handle_ctrl_click_selection(event.position)
                elif _should_start_drag_box():
                    _start_drag_box_selection(event.position)
                else:
                    _handle_single_model_selection(event.position)
            else:
                if drag_box_active:
                    _complete_drag_box_selection(event.position)
                elif len(selected_models) > 0:
                    _start_group_movement(event.position)
```

#### 1.3 Visual Selection Indicators
```gdscript
func _create_selection_visual() -> void:
    selection_visual = NinePatchRect.new()
    selection_visual.name = "MultiSelectionBox"
    selection_visual.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    selection_visual.modulate = Color(0.5, 0.8, 1.0, 0.3)  # Light blue transparent
    board_root.add_child(selection_visual)
    selection_visual.visible = false
```

### Phase 2: Group Movement System

#### 2.1 Group Movement Data Structure
Extend the staged_moves system:
```gdscript
# Add to MovementPhase.gd active_moves structure
"group_moves": [],  # Track group movement operations
"group_selection": [],  # Current multi-selected models
"group_formation": {}  # Relative positions within group
```

#### 2.2 Group Movement Calculation
```gdscript
func _process_group_movement(selected_models: Array, drag_vector: Vector2) -> Dictionary:
    var group_validation = {"valid": true, "errors": [], "individual_distances": {}}

    for model_data in selected_models:
        var model_id = model_data.model_id
        var original_pos = move_data.original_positions.get(model_id, model_data.position)
        var new_pos = model_data.position + drag_vector

        # Calculate individual distance
        var total_distance = Measurement.distance_inches(original_pos, new_pos)
        group_validation.individual_distances[model_id] = total_distance

        # Validate against movement cap
        if total_distance > move_data.move_cap_inches:
            group_validation.valid = false
            group_validation.errors.append("Model %s exceeds movement cap" % model_id)

    return group_validation
```

#### 2.3 Formation Preservation
```gdscript
func _calculate_formation_offsets(selected_models: Array) -> Dictionary:
    if selected_models.is_empty():
        return {}

    var formation_center = _calculate_group_center(selected_models)
    var offsets = {}

    for model_data in selected_models:
        var offset = model_data.position - formation_center
        offsets[model_data.model_id] = offset

    return offsets
```

### Phase 3: UI Enhancement

#### 3.1 Selection Visual Feedback
```gdscript
func _update_model_selection_visuals() -> void:
    # Clear existing selection indicators
    _clear_selection_indicators()

    # Create selection indicators for each selected model
    for model_data in selected_models:
        var indicator = _create_selection_indicator(model_data)
        board_root.add_child(indicator)
```

#### 3.2 Distance Display Enhancement
Modify the distance display to show group totals:
```gdscript
func _update_group_movement_display() -> void:
    if selected_models.size() > 1:
        var min_remaining = INF
        var max_used = 0.0

        for model_data in selected_models:
            var model_id = model_data.model_id
            var used = move_data.model_distances.get(model_id, 0.0)
            var remaining = move_cap_inches - used

            min_remaining = min(min_remaining, remaining)
            max_used = max(max_used, used)

        inches_used_label.text = "Group Max Used: %.1f\"" % max_used
        inches_left_label.text = "Group Min Left: %.1f\"" % min_remaining
```

## Validation & Error Handling

### Movement Validation Pipeline
1. **Individual Distance Checks**: Each model must not exceed movement cap
2. **Formation Coherency**: Group must maintain unit coherency rules
3. **Collision Detection**: No model overlaps with other units
4. **Terrain Validation**: All models avoid impassable terrain

### Error Recovery
```gdscript
func _validate_group_movement(group_moves: Array) -> Dictionary:
    var validation_result = {"valid": true, "errors": [], "warnings": []}

    for move in group_moves:
        # Individual validations
        if not _validate_individual_move(move):
            validation_result.valid = false
            validation_result.errors.append("Invalid move for model %s" % move.model_id)

        # Coherency check
        if not _maintains_unit_coherency(move):
            validation_result.warnings.append("May break unit coherency")

    return validation_result
```

## Integration Points

### 1. MovementController.gd Integration
- **Lines 955-1127**: Extend existing drag system to support multi-selection
- **Lines 16-24**: Add multi-selection state variables
- **Lines 919-954**: Modify input handling for group operations

### 2. MovementPhase.gd Integration
- **Lines 512-580**: Extend staged movement system for group moves
- **Lines 1200-1205**: Enhance active move data structure
- **Lines 992-1044**: Extend overlap detection for group validation

### 3. Visual System Integration
- **TokenVisual.gd**: Add selection state and visual indicators
- **GhostVisual.gd**: Support multi-ghost preview for group movement
- **Board rendering**: Selection overlays and group formation guides

## Implementation Tasks

### Task 1: Core Multi-Selection Infrastructure
1. Add multi-selection state variables to MovementController
2. Implement Ctrl+click model selection/deselection
3. Create selection visual indicators system
4. Add keyboard shortcuts (Ctrl+A for select all, Escape to clear)

### Task 2: Drag-Box Selection
1. Implement drag-box visual (NinePatchRect)
2. Add physics-based model detection within box
3. Integrate with existing model collision system
4. Handle edge cases (partial model overlap, zoom levels)

### Task 3: Group Movement System
1. Extend staged_moves to support group operations
2. Implement formation preservation logic
3. Add group movement validation pipeline
4. Create group preview system with multi-ghost visuals

### Task 4: UI Enhancement & Polish
1. Update movement distance displays for groups
2. Add group-specific action buttons (Move Group, Clear Selection)
3. Implement visual feedback for invalid group moves
4. Add tooltips and help text for multi-selection

### Task 5: Validation & Testing
1. Implement comprehensive group movement validation
2. Add unit coherency checking for groups
3. Create automated tests for multi-selection scenarios
4. Performance testing for large model groups

## Testing Strategy

### Unit Tests
```gdscript
func test_multi_model_selection_ctrl_click():
    # Verify Ctrl+click adds models to selection
    _simulate_ctrl_click_model("test_unit_1", "m1")
    _simulate_ctrl_click_model("test_unit_1", "m2")
    assert_eq(movement_controller.selected_models.size(), 2)

func test_group_movement_distance_tracking():
    # Verify individual distance tracking in group moves
    var initial_distances = _get_model_distances()
    _perform_group_movement(Vector2(60, 0))  # 2" movement
    var final_distances = _get_model_distances()
    # Each model should have 2" added to their distance
```

### Integration Tests
- **Coherency Validation**: Groups maintain unit coherency rules
- **Distance Limits**: No model exceeds movement cap in group moves
- **Mixed Movement**: Combination of group and individual moves
- **Save/Load**: Multi-selection state persistence

### UI Tests
- **Visual Feedback**: Selection indicators appear/disappear correctly
- **Drag Box**: Selection box appears and selects correct models
- **Performance**: Smooth interaction with 10+ selected models

## Acceptance Criteria

### ✅ Core Functionality
- [ ] User can select multiple models using Ctrl+click
- [ ] User can select multiple models using drag-box
- [ ] Selected models move together maintaining formation
- [ ] Individual movement distances tracked correctly
- [ ] Remaining movement available for individual adjustment

### ✅ User Experience
- [ ] Clear visual feedback for selected models
- [ ] Intuitive selection/deselection interactions
- [ ] Helpful distance displays for group movements
- [ ] Responsive performance with multiple selections

### ✅ Game Rules Compliance
- [ ] Unit coherency maintained during group moves
- [ ] Individual movement caps respected
- [ ] Integration with existing movement modes (Normal, Advance, Fall Back)
- [ ] Proper validation and error messaging

### ✅ Technical Quality
- [ ] No performance degradation with existing single-model movement
- [ ] Clean integration with existing codebase patterns
- [ ] Comprehensive test coverage for new functionality
- [ ] Robust error handling and edge case management

## Risk Assessment & Mitigation

### High Risk: Performance Impact
- **Risk**: Large selections could cause frame drops
- **Mitigation**: Implement selection size limits (max 20 models), optimize physics queries

### Medium Risk: UI Complexity
- **Risk**: Multi-selection UI might confuse users
- **Mitigation**: Progressive disclosure, tooltips, clear visual feedback

### Low Risk: Rules Compliance
- **Risk**: Group moves might violate Warhammer 40k rules
- **Mitigation**: Extensive validation, coherency checking, individual caps

## External Dependencies

### Godot Engine Features
- **PhysicsDirectSpaceState2D**: For drag-box collision detection
- **Input Event System**: For multi-selection input handling
- **Control Nodes**: For selection box visual feedback

### Documentation References
- **Godot Multi-Selection Recipe**: https://kidscancode.org/godot_recipes/4.x/input/multi_unit_select/index.html
- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Input Events**: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html

## Success Metrics

### Functionality Metrics
- **Selection Speed**: Users can select 5+ models in under 2 seconds
- **Movement Efficiency**: Group movement 3x faster than individual model movement
- **Accuracy**: 100% correct distance tracking for all models in group

### Quality Metrics
- **Bug Rate**: Zero critical bugs affecting movement validation
- **Performance**: No frame drops with up to 15 selected models
- **User Satisfaction**: Positive feedback on ease of use and intuitiveness

## Confidence Score: 8/10

This PRP provides comprehensive context for implementing multi-model movement with:
- ✅ **Clear Requirements**: Well-defined user needs and technical specifications
- ✅ **Complete Research**: Thorough analysis of existing systems and external patterns
- ✅ **Detailed Implementation**: Step-by-step technical approach with code examples
- ✅ **Integration Strategy**: Clear connection points with existing codebase
- ✅ **Risk Mitigation**: Identified challenges with concrete solutions
- ✅ **Validation Plan**: Comprehensive testing strategy and acceptance criteria

The implementation follows established Godot patterns and maintains compatibility with existing Warhammer 40k rules while providing the requested multi-model movement functionality.