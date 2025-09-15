# PRP: Non-Circular Model Bases Implementation

## Issue Reference
GitHub Issue #71: Non Circular models

## Summary
Implement support for non-circular model bases (rectangular and oval) in the Warhammer 40k game, including proper rotation tracking, pivot movement costs, and save/load persistence.

## Context & Requirements

### Core Requirements
1. Support rectangular and oval bases in addition to circular bases
2. Track model rotation in game state
3. Implement pivot movement costs (2" for non-circular vehicles/monsters)
4. Update specific models:
   - Caladius Grav-tank: oval base (170mm x 105mm)
   - Ork Battlewagon: rectangular base (9" x 5")
5. Persist rotation state in save games

### Warhammer 40k Rules Context
- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Distance Measurement**: "When measuring the distance between models, measure between the closest points of the bases"
- **Pivot Rules**: Vehicles and monsters on non-circular bases have a pivot value of 2", meaning any pivot during movement costs 2" of their movement allowance
- **Pivot Definition**: Rotating the model around the centre of its base

## Current Implementation Analysis

### Existing Model Structure
Models currently have:
```gdscript
{
  "id": "m1",
  "wounds": 14,
  "current_wounds": 14,
  "base_mm": 170,  # Currently assumes circular
  "position": Vector2(x, y),
  "alive": true,
  "status_effects": []
}
```

### Current Visualization
- `TokenVisual.gd`: Draws circular bases only using `draw_circle()`
- `Measurement.gd`: Has `base_radius_px()` function assuming circular bases
- Movement system tracks position but not rotation

### Save System
- Uses `StateSerializer.gd` for JSON serialization
- Model positions are saved but rotation is not tracked

## Architecture Design

### 1. Model Data Structure Enhancement
```gdscript
# Enhanced model structure
{
  "id": "m1",
  "wounds": 14,
  "current_wounds": 14,
  "base_type": "oval",  # New: "circular", "rectangular", "oval"
  "base_mm": 170,       # For circular (diameter)
  "base_dimensions": {  # New: For non-circular bases
    "length": 170,      # mm
    "width": 105        # mm
  },
  "position": Vector2(x, y),
  "rotation": 0.0,     # New: Rotation in radians
  "alive": true,
  "status_effects": []
}
```

### 2. Base Shape Classes
```gdscript
# BaseShape.gd - Abstract base class
class_name BaseShape
extends Resource

func get_type() -> String:
    return ""

func get_bounds() -> Rect2:
    return Rect2()

func draw(canvas: CanvasItem, position: Vector2, rotation: float, color: Color):
    pass

func contains_point(point: Vector2, position: Vector2, rotation: float) -> bool:
    return false

func get_edge_point(from: Vector2, to: Vector2, position: Vector2, rotation: float) -> Vector2:
    return Vector2.ZERO

# CircularBase.gd
class_name CircularBase
extends BaseShape

var radius: float

# RectangularBase.gd  
class_name RectangularBase
extends BaseShape

var length: float
var width: float

# OvalBase.gd
class_name OvalBase
extends BaseShape

var length: float  # Major axis
var width: float   # Minor axis
```

### 3. Enhanced Measurement System
Update `Measurement.gd`:
```gdscript
func model_to_model_distance(model1: Dictionary, model2: Dictionary) -> float:
    var base1 = create_base_shape(model1)
    var base2 = create_base_shape(model2)
    # Calculate edge-to-edge distance considering shapes and rotations
```

### 4. Visual Updates
Enhance `TokenVisual.gd`:
```gdscript
func _draw():
    var base_shape = model_data.get("base_type", "circular")
    match base_shape:
        "circular":
            _draw_circular_base()
        "rectangular":
            _draw_rectangular_base()
        "oval":
            _draw_oval_base()
```

### 5. Movement System Enhancement
Update `MovementController.gd`:
```gdscript
var pivot_cost_paid: bool = false
var remaining_movement: float

func apply_pivot(model: Dictionary, new_rotation: float) -> bool:
    if needs_pivot_cost(model) and not pivot_cost_paid:
        remaining_movement -= 2.0 * Measurement.PX_PER_INCH
        pivot_cost_paid = true
    model.rotation = new_rotation
    return remaining_movement >= 0
```

## Implementation Tasks

### Phase 1: Core Data Structure
1. Update model data structure in `GameState.gd`
2. Create base shape classes in `40k/scripts/bases/`
3. Update army JSON files for Caladius and Battlewagon

### Phase 2: Visualization
1. Enhance `TokenVisual.gd` to draw different base shapes
2. Add rotation visual indicator
3. Update ghost/preview visuals during movement

### Phase 3: Measurement System
1. Update `Measurement.gd` with shape-aware distance calculations
2. Implement edge-to-edge distance for different shape combinations
3. Update line of sight checks for non-circular bases

### Phase 4: Movement & Rotation
1. Add rotation controls to `MovementController.gd`
2. Implement pivot cost calculation
3. Add visual feedback for pivot costs

### Phase 5: Persistence
1. Update save/load to include rotation field
2. Ensure backward compatibility with existing saves
3. Update autosave system

### Phase 6: Testing & Polish
1. Create unit tests for base shapes
2. Test movement with pivot costs
3. Verify save/load with rotated models
4. Update UI to show rotation info

## File Changes

### Files to Create
- `40k/scripts/bases/BaseShape.gd`
- `40k/scripts/bases/CircularBase.gd`
- `40k/scripts/bases/RectangularBase.gd`
- `40k/scripts/bases/OvalBase.gd`
- `40k/tests/unit/test_base_shapes.gd`
- `40k/tests/unit/test_pivot_movement.gd`

### Files to Modify
- `40k/autoloads/GameState.gd` - Add rotation and base_type fields
- `40k/scripts/TokenVisual.gd` - Support drawing different shapes
- `40k/autoloads/Measurement.gd` - Shape-aware distance calculations
- `40k/scripts/MovementController.gd` - Rotation controls and pivot costs
- `40k/autoloads/EnhancedLineOfSight.gd` - Consider non-circular bases
- `40k/armies/adeptus_custodes.json` - Update Caladius base
- `40k/armies/orks.json` - Update Battlewagon base
- `40k/autoloads/StateSerializer.gd` - Handle rotation field

## Validation Gates

```bash
# Run after implementation
cd 40k

# Check Godot syntax
godot --headless --script scripts/validate_syntax.gd

# Run unit tests for new base shape system
godot --headless -s tests/unit/test_base_shapes.gd

# Run pivot movement tests
godot --headless -s tests/unit/test_pivot_movement.gd

# Test save/load with rotation
godot --headless -s tests/integration/test_save_load.gd

# Full test suite
godot --headless -s tests/run_all_tests.gd
```

## Implementation Order

1. **Data Structure** (Priority: High)
   - Update model structure with base_type and rotation
   - Create BaseShape class hierarchy
   - Update army JSON files

2. **Visualization** (Priority: High)
   - Update TokenVisual to draw different shapes
   - Add rotation rendering
   - Test visual appearance

3. **Movement System** (Priority: High)
   - Add rotation controls (right-click drag or keyboard)
   - Implement pivot cost deduction
   - Update movement validation

4. **Measurement** (Priority: Medium)
   - Update distance calculations
   - Test edge-to-edge measurements
   - Verify LoS with rotated models

5. **Persistence** (Priority: Medium)
   - Save/load rotation state
   - Maintain backward compatibility
   - Test with existing saves

6. **Polish** (Priority: Low)
   - UI indicators for rotation
   - Movement preview with pivot cost
   - Help text for controls

## Success Criteria

1. Caladius Grav-tank displays as 170mm x 105mm oval
2. Ork Battlewagon displays as 9" x 5" rectangle
3. Models can be rotated during deployment and movement
4. Pivoting costs 2" movement for applicable units
5. Rotation state persists in save games
6. Distance measurements work correctly with all shape combinations
7. Backward compatibility maintained with existing saves

## Risk Mitigation

1. **Performance Impact**: Use simple collision shapes, cache calculations
2. **Backward Compatibility**: Default missing fields, version migration
3. **Complex Interactions**: Thorough testing of shape combinations
4. **UI Complexity**: Start with keyboard rotation, add mouse later

## External Resources

- Godot Collision Shapes: https://docs.godotengine.org/en/4.4/tutorials/physics/collision_shapes_2d.html
- Godot Custom Drawing: https://docs.godotengine.org/en/4.4/tutorials/2d/custom_drawing_in_2d.html
- Warhammer Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

## Confidence Score: 8/10

High confidence due to:
- Clear requirements and rule references
- Existing pattern of shape drawing (terrain polygons)
- Well-defined data structure changes
- Incremental implementation approach

Minor concerns:
- Complex edge-to-edge calculations for oval shapes
- UI/UX for rotation controls needs testing