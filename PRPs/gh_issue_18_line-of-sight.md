# PRP: Line Of Sight Feature Implementation (GitHub Issue #18)

## Core Request
Implement a Line of Sight (LoS) visualization feature that shows all areas of the game board that selected models can see when holding the 'L' key, taking terrain obstacles into account.

## Context and Research

### Existing Codebase Patterns

#### Input Handling (from 40k/scripts/DeploymentController.gd:24-46)
```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_L:
            # Handle L key press
```

#### Visual Overlay Drawing (from 40k/scripts/MeasuringTapeVisual.gd)
- Uses Node2D with `_draw()` method for custom rendering
- Z-index layering for proper display order (15 for overlays)
- Color with transparency: `Color(0.0, 1.0, 1.0, 0.8)`

#### Terrain System (from 40k/scripts/TerrainVisual.gd)
- Terrain stored as polygons with height categories (low/medium/tall)
- TerrainManager maintains terrain_features array
- Each terrain piece has polygon boundary data

#### Model/Token System (from 40k/scripts/TokenVisual.gd)
- Models have position and base_shape
- Base shapes can be circular, rectangular, or oval
- Models belong to units with owner_player

### Godot 4 Raycasting Documentation
Reference: https://docs.godotengine.org/en/4.4/tutorials/physics/ray-casting.html

Key concepts:
- Use RayCast2D for 2D collision detection
- Can check against specific collision layers
- Methods: `is_colliding()`, `get_collision_point()`, `get_collider()`
- Performance: Turn off when not needed

### Warhammer 40k Line of Sight Rules
Reference: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

- True line of sight from any part of the firing model to any part of the target
- Terrain blocks LoS based on height category
- Models cannot see through other models (except their own unit)

## Implementation Blueprint

### Architecture Overview
```
LineOfSightManager (Autoload)
├── Manages LoS calculation state
├── Handles input detection
└── Signals LoS updates

LineOfSightVisual (Node2D)
├── Renders LoS overlay
├── Grid-based visibility map
└── Shader or draw-based visualization

LineOfSightCalculator (Resource)
├── Performs raycasting
├── Checks terrain blocking
└── Returns visibility data
```

### Pseudocode Implementation

```gdscript
# LineOfSightManager.gd
extends Node

signal los_visibility_changed(visible_points: Array)
signal los_calculation_started()
signal los_calculation_ended()

var is_calculating: bool = false
var current_models: Array = []
var visibility_grid: Dictionary = {}  # Vector2 -> bool

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        if event.keycode == KEY_L:
            if event.pressed:
                start_los_calculation()
            else:
                end_los_calculation()

func start_los_calculation() -> void:
    # Get models at mouse position
    var mouse_pos = get_viewport().get_mouse_position()
    current_models = get_models_at_position(mouse_pos)

    if current_models.is_empty():
        return

    is_calculating = true
    emit_signal("los_calculation_started")

    # Calculate visibility
    visibility_grid = calculate_los_grid(current_models)
    emit_signal("los_visibility_changed", visibility_grid)

func calculate_los_grid(models: Array) -> Dictionary:
    var grid = {}
    var grid_size = 10  # pixels per grid cell

    # For each grid point on the board
    for x in range(0, board_width, grid_size):
        for y in range(0, board_height, grid_size):
            var target_pos = Vector2(x, y)
            var has_los = false

            # Check if any model can see this point
            for model in models:
                if check_los(model.position, target_pos):
                    has_los = true
                    break

            if has_los:
                grid[target_pos] = true

    return grid

func check_los(from: Vector2, to: Vector2) -> bool:
    # Cast ray from model to target
    var space_state = get_world_2d().direct_space_state
    var query = PhysicsRayQueryParameters2D.create(from, to)
    query.collision_mask = TERRAIN_LAYER | MODEL_LAYER

    var result = space_state.intersect_ray(query)

    # If no collision, we have LoS
    if result.is_empty():
        return true

    # Check if collision is with terrain that blocks LoS
    if result.collider.is_in_group("terrain"):
        var terrain_height = result.collider.get_meta("height_category")
        # Tall terrain always blocks, medium/low depends on model height
        if terrain_height == "tall":
            return false

    return true
```

## Implementation Tasks

1. **Create LineOfSightManager Autoload**
   - Set up input handling for 'L' key hold
   - Manage LoS calculation state
   - Detect models at mouse position

2. **Create LineOfSightVisual Node2D**
   - Implement grid-based visibility rendering
   - Use semi-transparent overlay (green for visible, dark for blocked)
   - Optimize with viewport texture or shader

3. **Implement Raycasting System**
   - Create collision areas for terrain pieces
   - Set up proper collision layers
   - Implement efficient grid sampling

4. **Integrate with Existing Systems**
   - Connect to TerrainManager for obstacle data
   - Use TokenVisual positions for model locations
   - Respect game state and phase restrictions

5. **Performance Optimization**
   - Use quadtree or spatial partitioning for large boards
   - Cache visibility calculations per frame
   - Implement level-of-detail for distant areas

6. **Visual Polish**
   - Add fade-in/fade-out animation
   - Show LoS indicator near cursor
   - Add configuration for grid resolution

## Validation Gates

```bash
# No external validation commands needed for Godot
# Testing will be done in-engine

# Visual validation checklist:
# [ ] L key press activates LoS visualization
# [ ] L key release deactivates visualization
# [ ] Visible areas shown in semi-transparent green
# [ ] Terrain blocks line of sight correctly
# [ ] Performance remains smooth with multiple models
# [ ] Works correctly with different base shapes
```

## Error Handling Strategy

1. **No Models Selected**
   - Show tooltip: "No models at cursor position"
   - Don't activate LoS visualization

2. **Performance Issues**
   - Reduce grid resolution dynamically
   - Limit calculation to viewport area
   - Use frame spreading for large calculations

3. **Invalid Terrain Data**
   - Fall back to no terrain blocking
   - Log warning but don't crash

## Files to Reference/Modify

### Files to Create:
- `40k/autoloads/LineOfSightManager.gd`
- `40k/scripts/LineOfSightVisual.gd`
- `40k/scripts/LineOfSightCalculator.gd`
- `40k/tests/unit/test_line_of_sight.gd`

### Files to Modify:
- `40k/scripts/TerrainVisual.gd` - Add collision areas
- `40k/scripts/TokenVisual.gd` - Add LoS source markers
- `project.godot` - Register LineOfSightManager autoload

## Implementation Notes

### Collision Layer Setup
```
Layer 1: Models/Tokens
Layer 2: Terrain
Layer 3: LoS Blockers (future)
```

### Performance Targets
- 60 FPS with LoS active
- < 100ms calculation time for full board
- < 50MB memory overhead

### Visual Design
- Visible areas: `Color(0.0, 1.0, 0.0, 0.3)` (semi-transparent green)
- Blocked areas: `Color(0.0, 0.0, 0.0, 0.5)` (semi-transparent black)
- Edge highlighting: 2px white border on visible/blocked boundary

## Quality Checklist
- ✅ All necessary context included (input patterns, visual systems, terrain data)
- ✅ Validation gates are executable (visual checklist)
- ✅ References existing patterns (DeploymentController input, MeasuringTapeVisual drawing)
- ✅ Clear implementation path with tasks in order
- ✅ Error handling documented

## Confidence Score: 8/10

High confidence due to:
- Clear understanding of existing codebase patterns
- Well-documented Godot raycasting system
- Straightforward feature requirements
- Similar visualization systems already exist (MeasuringTape, Terrain)

Minor uncertainties:
- Exact performance characteristics with many rays
- Optimal grid resolution for visibility calculation