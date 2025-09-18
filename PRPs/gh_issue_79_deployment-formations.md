# PRP: Deployment Formations System
**GitHub Issue:** #79
**Feature Name:** Deployment Formations
**Author:** Claude Code AI
**Date:** 2025-09-17
**Confidence Score:** 9/10

## Problem Statement

Users currently must deploy models individually by clicking and placing each one separately. For units with 5, 10, or more models, this becomes tedious and time-consuming. Users need the ability to deploy multiple models at once in pre-defined formations while maintaining the flexibility to adjust individual models afterward.

## Requirements Analysis

### Core Requirements (from GitHub Issue #79):
1. **Formation Options**: Provide at least two formation patterns:
   - Maximum spread formation (models at maximum coherency distance - 2" apart)
   - Tight formation (models with bases touching but not overlapping)
2. **Batch Deployment**: Deploy sets of 5 models at once in selected formation
3. **Ghost Preview**: Show ghost previews for all models in the formation before placement
4. **Formation Toggle**: Allow users to enable/disable formation mode
5. **Mixed Deployment**: Support using formations for some models and manual placement for others

### Warhammer 40k Context:
- **Unit Coherency**: Models must stay within 2" horizontal distance from at least one other model
- **Base Sizes**: Common base sizes: 25mm, 32mm, 40mm, 50mm, 60mm
- **Deployment Zones**: All models must be wholly within the player's deployment zone
- **No Overlapping**: Model bases cannot overlap with any other models

## Current System Analysis

### Deployment Architecture:
- **DeploymentPhase.gd** (/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/DeploymentPhase.gd)
  - Validates deployment positions (lines 99-123)
  - Checks deployment zone boundaries (lines 275-341)
  - Manages unit deployment state (lines 144-189)

- **DeploymentController.gd** (/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/DeploymentController.gd)
  - Handles individual model placement (lines 83-128)
  - Creates ghost visuals (lines 194-216)
  - Validates positions and overlaps (lines 275-300, 366-394)

- **GhostVisual.gd** (/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/GhostVisual.gd)
  - Displays preview of model placement
  - Shows validity indicators (red/blue coloring)
  - Supports rotation for non-circular bases

### Key Code Patterns:

#### Current Single Model Placement:
```gdscript
# DeploymentController.gd:93-128
func try_place_at(world_pos: Vector2) -> void:
    if model_idx >= temp_positions.size():
        return

    # Validate position
    if not is_in_zone:
        _show_toast("Must be wholly within your deployment zone")
        return

    # Store position and move to next model
    temp_positions[model_idx] = world_pos
    temp_rotations[model_idx] = rotation
    model_idx += 1
```

#### Coherency Check Pattern:
```gdscript
# DeploymentController.gd:301-337
func _check_coherency_warning() -> void:
    for pos in placed_positions:
        var has_neighbor = false
        for other_pos in placed_positions:
            if pos != other_pos:
                var dist_inches = Measurement.distance_inches(pos, other_pos)
                if dist_inches <= 2.0:
                    has_neighbor = true
```

## Technical Research

### UI Pattern from Movement Phase:
The MovementPhase already implements group selection and formation tracking:
```gdscript
# MovementPhase.gd:382-384
"group_moves": [],  # Track group movement operations
"group_selection": [],  # Current multi-selected models
"group_formation": {}  # Relative positions within group
```

### Button Creation Pattern from Main.gd:
```gdscript
# Main.gd pattern for dynamic UI
var button = Button.new()
button.text = "Formation: Spread"
button.pressed.connect(_on_formation_button_pressed.bind("spread"))
container.add_child(button)
```

### Distance Calculations:
```gdscript
# Measurement.gd utilities
func distance_inches(pos1: Vector2, pos2: Vector2) -> float
func base_radius_px(base_mm: int) -> float
func edge_to_edge_distance_inches(...) -> float
```

## Implementation Strategy

### Phase 1: Formation System Core

#### 1.1 Formation Mode State
Add to DeploymentController.gd:
```gdscript
# Formation deployment state
var formation_mode: String = "SINGLE"  # SINGLE, SPREAD, TIGHT
var formation_size: int = 5  # Models per formation group
var formation_preview_ghosts: Array = []  # Ghost visuals for formation
var formation_anchor_pos: Vector2  # Where user clicks to place formation
```

#### 1.2 Formation Calculation Functions
```gdscript
func calculate_spread_formation(anchor_pos: Vector2, model_count: int, base_mm: int) -> Array:
    """Calculate positions for maximum spread (2" coherency)"""
    var positions = []
    var base_radius = Measurement.base_radius_px(base_mm)
    var spacing_inches = 2.0  # Maximum coherency distance
    var spacing_px = Measurement.inches_to_px(spacing_inches)
    var total_spacing = spacing_px + (base_radius * 2)

    # Arrange in rows of 5
    var cols = min(5, model_count)
    var rows = ceil(model_count / 5.0)

    for i in range(model_count):
        var col = i % cols
        var row = floor(i / cols)
        var x_offset = (col - cols/2.0) * total_spacing
        var y_offset = row * total_spacing
        positions.append(anchor_pos + Vector2(x_offset, y_offset))

    return positions

func calculate_tight_formation(anchor_pos: Vector2, model_count: int, base_mm: int) -> Array:
    """Calculate positions for tight formation (bases touching)"""
    var positions = []
    var base_radius = Measurement.base_radius_px(base_mm)
    var spacing_px = base_radius * 2 + 1  # 1px gap to prevent overlap

    # Arrange in rows of 5
    var cols = min(5, model_count)
    var rows = ceil(model_count / 5.0)

    for i in range(model_count):
        var col = i % cols
        var row = floor(i / cols)
        var x_offset = (col - cols/2.0) * spacing_px
        var y_offset = row * spacing_px
        positions.append(anchor_pos + Vector2(x_offset, y_offset))

    return positions
```

### Phase 2: UI Integration

#### 2.1 Formation Mode UI
Add formation selection buttons to unit card in Main.gd:
```gdscript
func _setup_formation_ui(unit_card: VBoxContainer) -> void:
    var formation_container = HBoxContainer.new()
    formation_container.name = "FormationControls"

    var formation_label = Label.new()
    formation_label.text = "Deploy Formation:"
    formation_container.add_child(formation_label)

    # Single mode button
    var single_btn = Button.new()
    single_btn.text = "Single"
    single_btn.toggle_mode = true
    single_btn.button_pressed = true
    single_btn.pressed.connect(_on_formation_mode_changed.bind("SINGLE"))
    formation_container.add_child(single_btn)

    # Spread formation button
    var spread_btn = Button.new()
    spread_btn.text = "Spread (2\")"
    spread_btn.toggle_mode = true
    spread_btn.pressed.connect(_on_formation_mode_changed.bind("SPREAD"))
    formation_container.add_child(spread_btn)

    # Tight formation button
    var tight_btn = Button.new()
    tight_btn.text = "Tight"
    tight_btn.toggle_mode = true
    tight_btn.pressed.connect(_on_formation_mode_changed.bind("TIGHT"))
    formation_container.add_child(tight_btn)

    # Add below unit name
    unit_card.add_child(formation_container)
    unit_card.move_child(formation_container, 1)
```

### Phase 3: Ghost Preview System

#### 3.1 Multiple Ghost Management
Enhance DeploymentController.gd:
```gdscript
func _create_formation_ghosts(count: int) -> void:
    """Create multiple ghost visuals for formation preview"""
    _clear_formation_ghosts()

    var unit_data = GameState.get_unit(unit_id)
    var remaining_models = _get_unplaced_model_indices()
    var models_to_place = min(count, remaining_models.size())

    for i in range(models_to_place):
        var model_idx = remaining_models[i]
        var model_data = unit_data["models"][model_idx]
        var ghost = preload("res://scripts/GhostVisual.gd").new()
        ghost.name = "FormationGhost_%d" % i
        ghost.radius = Measurement.base_radius_px(model_data["base_mm"])
        ghost.owner_player = unit_data["owner"]
        ghost.set_model_data(model_data)
        ghost.modulate.a = 0.6  # Slightly transparent for formation ghosts
        ghost_layer.add_child(ghost)
        formation_preview_ghosts.append(ghost)

func _update_formation_ghost_positions(mouse_pos: Vector2) -> void:
    """Update positions of all formation ghosts"""
    if formation_preview_ghosts.is_empty():
        return

    var unit_data = GameState.get_unit(unit_id)
    var model_data = unit_data["models"][model_idx]
    var base_mm = model_data["base_mm"]

    var positions = []
    match formation_mode:
        "SPREAD":
            positions = calculate_spread_formation(mouse_pos, formation_preview_ghosts.size(), base_mm)
        "TIGHT":
            positions = calculate_tight_formation(mouse_pos, formation_preview_ghosts.size(), base_mm)

    # Update ghost positions and validity
    for i in range(formation_preview_ghosts.size()):
        var ghost = formation_preview_ghosts[i]
        if i < positions.size():
            ghost.position = positions[i]
            ghost.visible = true

            # Check validity for each ghost position
            var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
            var is_valid = _validate_formation_position(positions[i], model_data, zone)
            ghost.set_validity(is_valid)
```

### Phase 4: Formation Placement

#### 4.1 Batch Model Placement
Modify try_place_at() in DeploymentController.gd:
```gdscript
func try_place_formation_at(world_pos: Vector2) -> void:
    """Place multiple models in formation at once"""
    if formation_mode == "SINGLE":
        try_place_at(world_pos)
        return

    var unit_data = GameState.get_unit(unit_id)
    var remaining_indices = _get_unplaced_model_indices()
    var models_to_place = min(formation_size, remaining_indices.size())

    if models_to_place == 0:
        return

    # Calculate formation positions
    var model_data = unit_data["models"][remaining_indices[0]]
    var base_mm = model_data["base_mm"]
    var positions = []

    match formation_mode:
        "SPREAD":
            positions = calculate_spread_formation(world_pos, models_to_place, base_mm)
        "TIGHT":
            positions = calculate_tight_formation(world_pos, models_to_place, base_mm)

    # Validate all positions
    var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
    var all_valid = true
    var error_msg = ""

    for i in range(positions.size()):
        var pos = positions[i]
        var idx = remaining_indices[i]
        var model = unit_data["models"][idx]

        if not _validate_formation_position(pos, model, zone):
            all_valid = false
            error_msg = "Formation would place models outside deployment zone or overlapping"
            break

    if not all_valid:
        _show_toast(error_msg)
        return

    # Place all models
    for i in range(positions.size()):
        var idx = remaining_indices[i]
        temp_positions[idx] = positions[i]
        temp_rotations[idx] = 0.0
        _spawn_preview_token(unit_id, idx, positions[i], 0.0)

    # Update model_idx to next unplaced model
    model_idx = remaining_indices[models_to_place] if models_to_place < remaining_indices.size() else temp_positions.size()

    _check_coherency_warning()
    emit_signal("models_placed_changed")

    # Update or clear ghosts
    if model_idx < temp_positions.size():
        if formation_mode == "SINGLE":
            _update_ghost_for_next_model()
        else:
            _create_formation_ghosts(formation_size)
    else:
        _clear_formation_ghosts()
        _remove_ghost()
```

### Phase 5: Input Handling

#### 5.1 Mouse Input Updates
Modify _unhandled_input() in DeploymentController.gd:
```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if not is_placing() or (not ghost_sprite and formation_preview_ghosts.is_empty()):
        return

    # Handle clicks for formation placement
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            var mouse_pos = _get_world_mouse_position()
            if formation_mode != "SINGLE":
                try_place_formation_at(mouse_pos)
            else:
                try_place_at(mouse_pos)
```

## Validation Plan

### Unit Tests:
```gdscript
# test_deployment_formations.gd
func test_spread_formation_calculation():
    var dc = DeploymentController.new()
    var positions = dc.calculate_spread_formation(Vector2(400, 400), 5, 32)

    # Check we get 5 positions
    assert_eq(positions.size(), 5)

    # Check spacing is correct (2" + base diameter)
    for i in range(1, positions.size()):
        var dist = Measurement.distance_inches(positions[0], positions[i])
        assert_true(dist >= 2.0, "Models should be at least 2\" apart")

func test_tight_formation_calculation():
    var dc = DeploymentController.new()
    var positions = dc.calculate_tight_formation(Vector2(400, 400), 5, 32)

    # Check positions don't overlap
    for i in range(positions.size()):
        for j in range(i+1, positions.size()):
            var dist_px = positions[i].distance_to(positions[j])
            var min_dist = Measurement.base_radius_px(32) * 2
            assert_true(dist_px >= min_dist, "Models should not overlap")

func test_formation_zone_validation():
    # Test that formations respect deployment zone boundaries
    var validation_result = phase.validate_formation_placement(positions, zone)
    assert_false(validation_result.valid, "Formation outside zone should fail")
```

### Integration Tests:
```bash
# Run after implementation
godot --headless -s 40k/tests/phases/test_deployment_phase.gd
godot --headless -s 40k/tests/ui/test_deployment_formations.gd
```

## Implementation Tasks

1. **Add Formation State Management** (DeploymentController.gd)
   - Add formation mode variables
   - Create formation calculation functions
   - Add helper functions for unplaced models

2. **Implement Formation UI Controls** (Main.gd)
   - Add formation mode buttons to unit card
   - Connect button signals to deployment controller
   - Style buttons to match existing UI

3. **Create Multi-Ghost Preview System** (DeploymentController.gd)
   - Manage array of ghost visuals
   - Update ghost positions based on formation
   - Show validity for entire formation

4. **Implement Batch Placement Logic** (DeploymentController.gd)
   - Modify try_place_at to handle formations
   - Validate all positions before placing
   - Update model tracking after batch placement

5. **Update Input Handling** (DeploymentController.gd)
   - Handle formation placement on click
   - Update mouse movement to show formation preview
   - Support switching between modes

6. **Add Formation Validation** (DeploymentPhase.gd)
   - Validate entire formation fits in zone
   - Check no overlaps for all models
   - Ensure coherency is maintained

7. **Create Unit Tests** (test_deployment_formations.gd)
   - Test formation calculations
   - Test validation logic
   - Test UI interactions

8. **Integration Testing**
   - Test with different unit sizes
   - Test zone boundary cases
   - Test mixing formation and manual placement

## External Documentation References

- Warhammer 40k Core Rules (Unit Coherency): https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Unit-Coherency
- Godot UI Controls: https://docs.godotengine.org/en/4.4/classes/class_button.html
- Godot Input Handling: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html

## Risk Mitigation

1. **Performance with Large Units**: Pre-calculate formations and cache results
2. **Complex Deployment Zones**: Use Geometry2D utilities for accurate boundary checking
3. **Mixed Base Sizes**: Calculate formations per-model rather than assuming uniform sizes
4. **UI Complexity**: Keep formation controls simple and intuitive

## Success Criteria

1. Users can deploy 5+ models with a single click
2. Formation previews show before placement
3. All models respect deployment zone boundaries
4. No model overlapping occurs
5. Users can mix formation and manual deployment
6. UI controls are intuitive and responsive

## Confidence Assessment: 9/10

High confidence due to:
- Clear existing patterns in codebase
- Similar multi-model system already implemented for movement
- Well-defined validation logic already present
- Clear UI patterns to follow

Minor uncertainty around:
- Exact UI/UX flow preferences
- Performance with very large formations (20+ models)