# PRP: Fix Non-Circular Base Shape Rendering and Measurements

## Issue Reference
GitHub Issue #91: Base shape issue

## Problem Statement
Models with non-circular bases (e.g., Ork Battlewagon, Custodes Caladius) are currently showing as circular even when they should display their actual base shapes. All measurements and distance calculations should respect the actual base shape, not treat everything as circular.

## Context and Research Findings

### Existing Infrastructure
The codebase already has a robust base shape system in place:

1. **Base Shape Classes** (40k/scripts/bases/):
   - `BaseShape.gd`: Abstract base class defining interface
   - `CircularBase.gd`: Circular base implementation
   - `RectangularBase.gd`: Rectangular base implementation
   - `OvalBase.gd`: Oval base implementation

2. **Measurement System** (40k/autoloads/Measurement.gd):
   - `create_base_shape()` function (lines 56-80) already supports creating proper base shapes
   - Shape-aware distance calculations (lines 82-98)
   - Collision detection with `models_overlap()` (lines 100-118)
   - Wall collision detection (lines 121-135)

3. **Current Visual Implementation**:
   - `TokenVisual.gd`: Only draws circles (line 32: `draw_circle()`)
   - `GhostVisual.gd`: Has partial support for non-circular bases but only draws ovals

### Model Base Specifications
Based on research and army data files:

1. **Ork Battlewagon** (40k/armies/orks.json):
   - Current base_mm: 180
   - Should be: Rectangular base (180mm x 110mm)
   - Note: Traditional Battlewagons don't use bases, but for game simulation we need a rectangular approximation

2. **Custodes Caladius Grav-Tank** (40k/armies/adeptus_custodes.json):
   - Current base_mm: 170
   - Should be: Oval base (170mm x 105mm)
   - This matches standard Knight oval bases

### Key Files to Modify

1. **Army Data Files** (40k/armies/):
   - `orks.json`: Add base_type and base_dimensions to Battlewagon
   - `adeptus_custodes.json`: Add base_type and base_dimensions to Caladius

2. **Visual Components**:
   - `TokenVisual.gd`: Update to use BaseShape system for rendering
   - `GhostVisual.gd`: Update to use BaseShape system for rendering

3. **Model Creation**:
   - `Main.gd`: Update `_create_token_visual()` to pass complete model data
   - `DeploymentController.gd`: Update ghost creation to use base shapes

## Implementation Blueprint

### Step 1: Update Army Data Files

```json
// For Battlewagon in orks.json
"models": [{
  "id": "m1",
  "wounds": 16,
  "current_wounds": 16,
  "base_mm": 180,
  "base_type": "rectangular",
  "base_dimensions": {
    "length": 180,
    "width": 110
  },
  "position": null,
  "alive": true,
  "status_effects": []
}]

// For Caladius in adeptus_custodes.json
"models": [{
  "id": "m1",
  "wounds": 14,
  "current_wounds": 14,
  "base_mm": 170,
  "base_type": "oval",
  "base_dimensions": {
    "length": 170,
    "width": 105
  },
  "position": null,
  "alive": true,
  "status_effects": []
}]
```

### Step 2: Update TokenVisual.gd

```gdscript
extends Node2D

var owner_player: int = 1
var is_preview: bool = false
var model_number: int = 1
var debug_mode: bool = false
var base_shape: BaseShape = null
var model_data: Dictionary = {}

func _ready() -> void:
    z_index = 10

func _draw() -> void:
    if not base_shape:
        # Fallback to circular if no shape defined
        base_shape = CircularBase.new(20.0)

    var fill_color: Color
    var border_color: Color
    var border_width: float = 3.0

    # Color logic (existing)
    if debug_mode:
        fill_color = Color(1.0, 0.8, 0.0, 0.9)
        border_color = Color(1.0, 0.5, 0.0, 1.0)
        border_width = 4.0
    elif owner_player == 1:
        fill_color = Color(0.2, 0.2, 0.8, 0.8 if is_preview else 1.0)
        border_color = Color(0.1, 0.1, 0.6, 1.0)
    else:
        fill_color = Color(0.8, 0.2, 0.2, 0.8 if is_preview else 1.0)
        border_color = Color(0.6, 0.1, 0.1, 1.0)

    # Use base shape's draw method
    base_shape.draw(self, Vector2.ZERO, 0.0, fill_color, border_color, border_width)

    # Draw model number
    var font = ThemeDB.fallback_font
    var text = str(model_number)
    var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
    var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)
    draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)

func set_model_data(data: Dictionary) -> void:
    model_data = data
    base_shape = Measurement.create_base_shape(data)
    queue_redraw()
```

### Step 3: Update GhostVisual.gd

```gdscript
extends Node2D

var owner_player: int = 1
var is_valid_position: bool = true
var model_data: Dictionary = {}
var base_rotation: float = 0.0
var base_shape: BaseShape = null

func _ready() -> void:
    z_index = 20
    set_process(true)

func _draw() -> void:
    if not base_shape:
        # Fallback to circular if no shape defined
        base_shape = CircularBase.new(20.0)

    var fill_color: Color
    var border_color: Color

    if not is_valid_position:
        fill_color = Color(0.8, 0.2, 0.2, 0.5)
        border_color = Color(1.0, 0.0, 0.0, 0.8)
    else:
        if owner_player == 1:
            fill_color = Color(0.2, 0.2, 0.8, 0.5)
            border_color = Color(0.3, 0.3, 1.0, 0.8)
        else:
            fill_color = Color(0.8, 0.2, 0.2, 0.5)
            border_color = Color(1.0, 0.3, 0.3, 0.8)

    # Use base shape's draw method
    base_shape.draw(self, Vector2.ZERO, base_rotation, fill_color, border_color, 2.0)

func set_model_data(data: Dictionary) -> void:
    model_data = data
    base_shape = Measurement.create_base_shape(data)
    queue_redraw()

func set_base_rotation(rot: float) -> void:
    base_rotation = rot
    rotation = rot
    queue_redraw()
```

### Step 4: Update Main.gd's _create_token_visual()

```gdscript
func _create_token_visual(unit_id: String, model: Dictionary) -> Node2D:
    var token = preload("res://scripts/TokenVisual.gd").new()

    var unit = GameState.get_unit(unit_id)
    token.owner_player = unit.get("owner", 1)
    token.is_preview = false

    # Pass complete model data for base shape handling
    token.set_model_data(model)

    # Set model number if available
    var model_id = model.get("id", "")
    if model_id.begins_with("m"):
        var num_str = model_id.substr(1)
        if num_str.is_valid_int():
            token.model_number = num_str.to_int()

    return token
```

### Step 5: Update measurement and distance calculations

All existing distance calculations in the codebase should already work correctly since they use the Measurement autoload's shape-aware functions. Key functions that will automatically benefit:

- `Measurement.model_to_model_distance_px()`
- `Measurement.models_overlap()`
- `Measurement.model_overlaps_wall()`

## Testing Strategy

### Unit Tests
Create test file: `40k/tests/unit/test_base_shapes_visual.gd`

```gdscript
extends GutTest

func test_battlewagon_has_rectangular_base():
    var army = ArmyListManager.load_army_list("orks", 2)
    var battlewagon = army.units.get("U_BATTLEWAGON_G")
    assert_not_null(battlewagon)

    var model = battlewagon.models[0]
    assert_eq(model.base_type, "rectangular")
    assert_eq(model.base_dimensions.length, 180)
    assert_eq(model.base_dimensions.width, 110)

func test_caladius_has_oval_base():
    var army = ArmyListManager.load_army_list("adeptus_custodes", 1)
    var caladius = army.units.get("U_CALADIUS_GRAV-TANK_E")
    assert_not_null(caladius)

    var model = caladius.models[0]
    assert_eq(model.base_type, "oval")
    assert_eq(model.base_dimensions.length, 170)
    assert_eq(model.base_dimensions.width, 105)

func test_token_visual_renders_correct_shape():
    var model_rect = {
        "base_mm": 180,
        "base_type": "rectangular",
        "base_dimensions": {"length": 180, "width": 110}
    }

    var token = preload("res://scripts/TokenVisual.gd").new()
    token.set_model_data(model_rect)

    assert_not_null(token.base_shape)
    assert_eq(token.base_shape.get_type(), "rectangular")

func test_distance_calculation_with_shapes():
    var battlewagon = {
        "position": Vector2(0, 0),
        "rotation": 0,
        "base_type": "rectangular",
        "base_dimensions": {"length": 180, "width": 110}
    }

    var infantry = {
        "position": Vector2(300, 0),
        "rotation": 0,
        "base_mm": 32,
        "base_type": "circular"
    }

    var distance = Measurement.model_to_model_distance_inches(battlewagon, infantry)
    # Should measure from edge of rectangle to edge of circle
    assert_gt(distance, 0)
```

### Manual Testing Checklist
1. Load game with Orks vs Custodes
2. Deploy Battlewagon - verify rectangular base is shown
3. Deploy Caladius - verify oval base is shown
4. Move models near each other - verify proper edge-to-edge measurements
5. Test disembarkation from Battlewagon - verify 3" measured from rectangular base edge
6. Test collision detection - models shouldn't overlap
7. Test wall collisions with non-circular bases
8. Rotate vehicles - verify base shape rotates correctly

## Validation Gates

```bash
# Run unit tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_base_shapes_visual.gd

# Run existing base shape tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_base_shapes.gd

# Check for any circular base hardcoding
grep -r "draw_circle" 40k/scripts/ | grep -E "(Token|Ghost)Visual"

# Verify army data has base_type fields
grep -A5 "BATTLEWAGON" 40k/armies/orks.json | grep base_type
grep -A5 "CALADIUS" 40k/armies/adeptus_custodes.json | grep base_type
```

## Implementation Order

1. **Update army JSON files** - Add base_type and base_dimensions to affected units
2. **Update TokenVisual.gd** - Implement BaseShape rendering
3. **Update GhostVisual.gd** - Implement BaseShape rendering
4. **Update Main.gd** - Pass model data to tokens
5. **Update DeploymentController.gd** - Pass model data to ghosts
6. **Create and run tests** - Verify implementation
7. **Manual testing** - Verify visual rendering and gameplay

## Error Handling

- If base_type is missing, default to "circular"
- If base_dimensions are missing for non-circular, calculate from base_mm
- Ensure backwards compatibility with existing save files
- Handle rotation properly for non-circular bases

## References

- BaseShape system: `/40k/scripts/bases/`
- Measurement functions: `/40k/autoloads/Measurement.gd`
- Wahapedia rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Existing test patterns: `/40k/tests/unit/test_base_shapes.gd`

## Confidence Score

**8/10** - High confidence due to:
- Existing robust BaseShape infrastructure
- Clear integration points identified
- Shape-aware distance calculations already implemented
- Well-defined test strategy

Minor uncertainty around:
- Exact dimensions for Battlewagon (using reasonable approximation)
- Potential edge cases in rotation handling