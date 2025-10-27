# PRP: Pile-In Step Enhancement for Fight Phase

## Overview
Enhance the existing pile-in implementation in the Warhammer 40k Godot game by adding interactive drag-and-drop UI for model movement during the fight phase. The pile-in logic and validation are already 80% complete - this PRP focuses on making the PileInDialog interactive and providing visual feedback.

## Context & Requirements

### Core Rules (Warhammer 40k 10th Edition)
- **Movement Distance**: Up to 3 inches per model
- **Direction Requirement**: Each model must end closer to the closest enemy model
- **Base Contact Priority**: Models must end in base-to-base contact with enemy if possible
- **Unit Coherency**: Unit must maintain 2" coherency between models
- **Engagement Range**: Unit must remain within 1" of at least one enemy unit
- **No Overlaps**: Models cannot overlap other models or terrain

### Current Implementation Status
**What's Working (in FightPhase.gd):**
- ✅ Pile-in action defined (`PILE_IN` action type)
- ✅ Distance validation (3" limit enforced)
- ✅ Direction validation (toward closest enemy)
- ✅ Coherency checking (2" rule)
- ✅ No overlap validation
- ✅ Signal flow established (`pile_in_required` → dialog → `pile_in_confirmed`)
- ✅ Integration with fight sequence

**What Needs Enhancement:**
- ❌ PileInDialog has no interactive UI (just skip/confirm buttons)
- ❌ No drag-and-drop for model positioning
- ❌ No visual feedback (movement range, valid zones)
- ❌ No path visualization
- ❌ No per-model validation feedback

## Architecture Analysis

### Key Files to Modify
1. **`/40k/dialogs/PileInDialog.gd`** (61 lines) - Primary enhancement target
2. **`/40k/scripts/FightController.gd`** - May need updates for enhanced UI integration
3. **`/40k/phases/FightPhase.gd`** - Validation logic already complete

### Reference Implementations
- **MovementController.gd** - Contains drag-and-drop patterns to adapt:
  - `_start_model_drag()` / `_update_model_drag()` / `_end_drag()`
  - Visual feedback systems (path lines, range indicators)
  - Multi-model selection and movement
- **AttackAssignmentDialog.gd** - Complex dialog with interactive elements
- **Measurement.gd** - Distance and collision utilities already available

### Signal Flow
```
FightPhase.pile_in_required(unit_id, max_distance=3.0)
    ↓
FightController._on_pile_in_required() creates dialog
    ↓
PileInDialog shows UI with interactive movement
    ↓
User drags models (with validation feedback)
    ↓
PileInDialog.pile_in_confirmed(movements: Dictionary)
    ↓
FightController submits PILE_IN action to FightPhase
    ↓
FightPhase validates and applies movements
```

## Implementation Blueprint

### Phase 1: Dialog UI Structure
```gdscript
# PileInDialog.gd enhancement structure
extends AcceptDialog

# UI Components
var viewport_container: SubViewportContainer
var viewport: SubViewport
var camera: Camera2D
var board_view: Node2D  # Container for unit models

# Movement tracking
var unit_id: String
var max_distance: float = 3.0
var original_positions: Dictionary = {}  # model_id -> Vector2
var current_positions: Dictionary = {}   # model_id -> Vector2
var dragging_model: Node2D = null
var drag_offset: Vector2

# Visual indicators
var range_indicators: Dictionary = {}  # model_id -> Node2D (3" circles)
var direction_lines: Dictionary = {}   # model_id -> Line2D
var coherency_lines: Array = []        # Line2D connections
var valid_zone_overlay: Node2D         # Shows valid landing areas

# Validation
var phase_ref: Node  # Reference to FightPhase for validation calls
```

### Phase 2: Interactive Movement System
```gdscript
func _ready():
    # Setup viewport for model display
    _setup_viewport()
    _load_unit_models()
    _create_visual_indicators()
    _connect_input_signals()

func _on_model_input_event(viewport, event, shape_idx, model):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _start_model_drag(model)
            else:
                _end_model_drag(model)
    elif event is InputEventMouseMotion and dragging_model:
        _update_model_drag(event.position)

func _start_model_drag(model: Node2D):
    dragging_model = model
    drag_offset = model.position - get_viewport().get_mouse_position()
    # Show visual feedback
    _show_movement_range(model)
    _highlight_closest_enemy(model)

func _update_model_drag(mouse_pos: Vector2):
    var new_pos = mouse_pos + drag_offset
    var validated = _validate_position_live(dragging_model, new_pos)

    # Update visual feedback
    dragging_model.position = new_pos
    _update_direction_line(dragging_model)
    _update_validity_indicator(validated)

func _validate_position_live(model, new_pos) -> Dictionary:
    # Real-time validation using FightPhase methods
    var validation = {
        "distance_valid": _check_distance(model, new_pos),
        "direction_valid": _check_direction(model, new_pos),
        "coherency_valid": _check_coherency_preview(model, new_pos),
        "no_overlap": _check_overlaps(model, new_pos)
    }
    return validation
```

### Phase 3: Visual Feedback System
```gdscript
func _create_visual_indicators():
    # Movement range circles (3" around each model)
    for model_id in unit_models:
        var circle = _create_range_circle(3.0)
        circle.visible = false
        range_indicators[model_id] = circle

    # Direction indicators (lines to closest enemy)
    for model_id in unit_models:
        var line = Line2D.new()
        line.width = 2
        line.default_color = Color.YELLOW
        direction_lines[model_id] = line

func _show_movement_range(model):
    var circle = range_indicators[model.get_meta("model_id")]
    circle.position = model.position
    circle.visible = true
    circle.modulate = Color(1, 1, 1, 0.3)

func _update_direction_line(model):
    var line = direction_lines[model.get_meta("model_id")]
    var closest_enemy = _find_closest_enemy_position(model.position)
    line.clear_points()
    line.add_point(model.position)
    line.add_point(closest_enemy)
    # Color based on validation
    var closer = _is_moving_closer(original_pos, model.position, closest_enemy)
    line.default_color = Color.GREEN if closer else Color.RED

func _highlight_valid_zones():
    # Overlay showing where model can legally move
    # Green = valid, Red = invalid, considering all constraints
```

### Phase 4: Validation Integration
```gdscript
func _validate_all_movements() -> Dictionary:
    var movements = {}
    for model_id in current_positions:
        if current_positions[model_id] != original_positions[model_id]:
            movements[model_id] = current_positions[model_id]

    # Use FightPhase validation
    return phase_ref._validate_pile_in({
        "unit_id": unit_id,
        "movements": movements
    })

func _on_confirm_pressed():
    var validation = _validate_all_movements()
    if validation.valid:
        pile_in_confirmed.emit(current_positions, unit_id)
    else:
        _show_validation_errors(validation.errors)
```

## Implementation Tasks

### 1. Setup Dialog Structure
- [ ] Create SubViewport for model display
- [ ] Setup Camera2D with proper zoom/pan
- [ ] Load unit models into viewport
- [ ] Add control buttons (Skip, Reset, Confirm)

### 2. Implement Drag System
- [ ] Connect input events to models
- [ ] Implement drag start/update/end handlers
- [ ] Track original and current positions
- [ ] Add drag constraints (max 3" distance)

### 3. Add Visual Indicators
- [ ] Create 3" range circles for each model
- [ ] Add direction lines to closest enemy
- [ ] Show coherency connections between friendly models
- [ ] Implement valid/invalid zone overlay

### 4. Integrate Validation
- [ ] Connect to FightPhase validation methods
- [ ] Real-time validation during drag
- [ ] Show validation errors clearly
- [ ] Prevent invalid confirmations

### 5. Enhance User Experience
- [ ] Add undo/reset functionality
- [ ] Implement smooth animations
- [ ] Add tooltips explaining constraints
- [ ] Support keyboard shortcuts (ESC to cancel, Enter to confirm)

### 6. Testing & Polish
- [ ] Test with various unit sizes
- [ ] Verify all validation rules work
- [ ] Test edge cases (single model units, surrounded units)
- [ ] Add sound effects for feedback

## Validation Gates

```bash
# 1. Run existing fight phase tests to ensure no regression
godot --headless -s res://40k/tests/phases/test_fight_phase.gd

# 2. Test pile-in specific scenarios
godot --headless -s res://40k/tests/unit/test_pile_in_ui.gd  # New test file

# 3. Integration test with full fight sequence
godot --headless -s res://40k/tests/integration/test_fight_phase_integration.gd

# 4. Manual testing checklist
# - [ ] Can drag models up to 3"
# - [ ] Models must move toward closest enemy
# - [ ] Base contact enforced when possible
# - [ ] Unit coherency maintained
# - [ ] No model overlaps
# - [ ] Visual feedback is clear
# - [ ] Validation errors shown properly
# - [ ] Can skip pile-in if no valid moves
```

## External Resources

### Godot Documentation
- [2D Movement Overview](https://docs.godotengine.org/en/4.4/tutorials/2d/2d_movement.html) - Movement patterns
- [Input Handling](https://docs.godotengine.org/en/4.4/tutorials/inputs/index.html) - Drag and drop implementation
- [SubViewport Usage](https://docs.godotengine.org/en/4.4/classes/class_subviewport.html) - For dialog model display
- [Line2D Reference](https://docs.godotengine.org/en/4.4/classes/class_line2d.html) - For visual indicators

### Implementation Examples
- [RTS Multi-Unit Selection](https://kidscancode.org/godot_recipes/4.x/input/multi_unit_select/index.html) - Drag selection patterns
- [Godot RTS Movement](https://gamedevacademy.org/godot-rts-tutorial/) - Unit movement systems

### Warhammer 40k Rules
- [Core Rules - Fight Phase](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE) - Official pile-in rules
- [Movement Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Normal-Moves) - General movement constraints

## Error Handling Strategy

1. **Invalid Movement Attempts**
   - Show red overlay on invalid positions
   - Display tooltip explaining why invalid
   - Snap back to valid position on release

2. **Coherency Breaks**
   - Highlight models breaking coherency in orange
   - Show dotted lines to nearest friendly models
   - Prevent confirmation until fixed

3. **No Valid Moves**
   - Detect when no models can pile in
   - Show informative message
   - Auto-enable skip button

4. **Network/Multiplayer Considerations**
   - Validate on both client and server
   - Handle disconnections during pile-in
   - Sync visual state properly

## Code Patterns to Follow

### From MovementController.gd:
```gdscript
# Drag handling pattern
func _start_model_drag(mouse_pos: Vector2) -> void:
    var model = _get_model_at_position(world_pos)
    if model:
        dragging_model = model
        drag_start_pos = model.position
        # Store offset for smooth dragging
        drag_offset = model.position - world_pos
```

### From FightPhase.gd validation:
```gdscript
# Validation pattern
func _validate_pile_in(action: Dictionary) -> Dictionary:
    var errors = []
    # Check each constraint
    if not _check_distance_limit(movement, 3.0):
        errors.append("Movement exceeds 3 inches")
    # Return structured result
    return {"valid": errors.is_empty(), "errors": errors}
```

## Success Metrics
- **Functional**: All pile-in rules correctly enforced
- **Usability**: Players can complete pile-in within 30 seconds
- **Visual Clarity**: Constraints visible without reading documentation
- **Performance**: Smooth dragging even with 10+ models
- **Reliability**: No crashes or stuck states during pile-in

## Implementation Notes

1. **Reuse Existing Systems**
   - Leverage Measurement.gd for all distance calculations
   - Use BaseShape collision detection from existing code
   - Adapt MovementController drag patterns

2. **Maintain Consistency**
   - Match visual style of other dialogs
   - Use same color coding (green=valid, red=invalid)
   - Follow existing signal naming conventions

3. **Performance Considerations**
   - Cache enemy positions at dialog open
   - Throttle validation during drag (every 3-5 frames)
   - Reuse visual indicators instead of creating new ones

4. **Multiplayer Ready**
   - All movements go through FightPhase validation
   - State changes properly synchronized
   - No client-side only validation

## Confidence Score: 8/10

**Strengths:**
- Clear requirements from game rules
- Existing validation logic works
- Reference implementations available
- Well-defined integration points

**Risks:**
- UI complexity might require iterations
- Performance with many models needs testing
- Edge cases in cramped battlefield positions

This implementation should succeed in one pass with the comprehensive context provided. The main work is enhancing the UI while the core logic is already solid.