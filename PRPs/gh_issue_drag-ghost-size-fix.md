# PRP: Fix Drag Ghost Size and Shape for All Models

## Issue Description

When dragging some models, particularly those with non-circular bases like the Caladius Grav-tank (oval base), the ghost visual does not match the actual model's size, shape, and rotation. The ghost appears as a small circle instead of showing the correct oval shape that matches the model being dragged.

## Root Cause Analysis

After researching the codebase, I've identified the following:

1. **ChargeController** (line 908) uses `TokenVisual.gd` for the drag ghost
2. **MovementController** (line 1831) uses `GhostVisual.gd` for the drag ghost
3. **DeploymentController** (lines 484, 913, 1020) uses `GhostVisual.gd` for the drag ghost
4. **DisembarkController** (line 229) uses `GhostVisual.gd` for the drag ghost

Both `TokenVisual.gd` and `GhostVisual.gd` properly call `Measurement.create_base_shape(data)` to create the correct base shape (circular, oval, or rectangular). However, there may be inconsistencies in how the model data is passed or how the ghost is configured.

### Model Data Structure

For the Caladius Grav-tank (`40k/armies/adeptus_custodes.json:588-601`):
```json
{
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
}
```

### Shape Creation Logic

`Measurement.create_base_shape()` (40k/autoloads/Measurement.gd:56-80):
- Checks `base_type` field ("circular", "oval", "rectangular")
- For oval bases: uses `base_dimensions.length` and `base_dimensions.width`
- Falls back to circular if `base_type` is missing or unknown
- Converts mm measurements to pixels using `mm_to_px()`

### OvalBase Implementation

`40k/scripts/bases/OvalBase.gd` properly handles:
- Drawing ellipses with correct dimensions
- Rotation handling via `to_world_space()`
- Edge point calculations
- Overlap detection

## Research Context

### Godot Documentation
- [Drawing 2D Custom Shapes](https://docs.godotengine.org/en/4.4/tutorials/2d/custom_drawing_in_2d.html)
- [Using Nodes](https://docs.godotengine.org/en/4.4/getting_started/step_by_step/nodes_and_scenes.html)

### Warhammer Rules
- Models have different base sizes (32mm, 40mm, 60mm, etc.)
- Vehicles often use oval bases (e.g., 170mm x 105mm for Caladius Grav-tank)
- Base shape and rotation matter for measurements and positioning

### Key Files

**Ghost Visual Scripts:**
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/GhostVisual.gd` (58 lines)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/TokenVisual.gd` (70 lines)

**Controllers:**
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ChargeController.gd` (lines 889-932: `_start_model_drag()`)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd` (lines 1826-1850: `_show_ghost_visual()` and `_update_ghost_position()`)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/DeploymentController.gd` (lines 484-529, 903-922)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/DisembarkController.gd` (lines 229-240)

**Base Shape Classes:**
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/bases/BaseShape.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/bases/CircularBase.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/bases/OvalBase.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/bases/RectangularBase.gd`

**Measurement System:**
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/Measurement.gd` (create_base_shape function)

## Implementation Plan

### Step 1: Verify ChargeController Ghost Creation
**File:** `40k/scripts/ChargeController.gd`
**Location:** `_start_model_drag()` function (lines 889-932)

**Action:**
1. Ensure `ghost_token.set_model_data(model)` receives complete model data including `base_type` and `base_dimensions`
2. Add debug logging to verify model data contains all necessary fields
3. Verify the ghost is being positioned and sized correctly

**Pattern to follow:** MovementController's `_show_ghost_visual()` (lines 1826-1850)

### Step 2: Standardize on GhostVisual.gd
**Rationale:**
- 3 out of 4 controllers use `GhostVisual.gd`
- `GhostVisual.gd` has simpler, more focused implementation
- Separates preview visuals from regular token rendering

**Action:**
Update ChargeController to use `GhostVisual.gd` instead of `TokenVisual.gd`:

```gdscript
# OLD (line 908):
var ghost_token = preload("res://scripts/TokenVisual.gd").new()
var unit = GameState.get_unit(active_unit_id)
ghost_token.owner_player = unit.get("owner", 1)
ghost_token.is_preview = true
ghost_token.model_number = 0
ghost_token.set_model_data(model)

# NEW (following MovementController pattern):
var ghost_token = preload("res://scripts/GhostVisual.gd").new()
var unit = GameState.get_unit(active_unit_id)
ghost_token.owner_player = unit.get("owner", 1)
ghost_token.set_model_data(model)
# Set initial rotation if model has one
if model.has("rotation"):
    ghost_token.set_base_rotation(model.get("rotation", 0.0))
```

### Step 3: Ensure Rotation Updates
**File:** `40k/scripts/ChargeController.gd`
**Location:** `_rotate_dragging_model()` function (lines 1730-1757)

**Action:**
Update rotation handling to work with GhostVisual's `set_base_rotation()` method:

```gdscript
# Update line 1746-1749 to use GhostVisual's rotation method:
if ghost_visual and ghost_visual.get_child_count() > 0:
    var ghost_token = ghost_visual.get_child(0)
    if ghost_token.has_method("set_base_rotation"):
        ghost_token.set_base_rotation(new_rotation)
```

### Step 4: Verify All Controllers
**Action:**
Audit all other controllers to ensure they handle ghosts consistently:

1. **MovementController** - Already uses GhostVisual ✓
2. **DeploymentController** - Already uses GhostVisual ✓
3. **DisembarkController** - Already uses GhostVisual ✓
4. **ChargeController** - Will be updated ⚠️

### Step 5: Add Debug Logging (Temporary)
**Purpose:** Validate fix during testing

**Action:**
Add temporary debug output in ChargeController `_start_model_drag()`:

```gdscript
func _start_model_drag(model: Dictionary, world_pos: Vector2) -> void:
    var model_id = model.get("id", "")
    print("Starting drag for model ", model_id)

    # DEBUG: Verify model data
    print("DEBUG: Model base_type: ", model.get("base_type", "NOT SET"))
    print("DEBUG: Model base_mm: ", model.get("base_mm", "NOT SET"))
    print("DEBUG: Model base_dimensions: ", model.get("base_dimensions", "NOT SET"))
    print("DEBUG: Model rotation: ", model.get("rotation", 0.0))

    # ... rest of function
```

## Validation Gates

### Manual Testing Steps
1. **Load Test Save:**
   - Load save with Caladius Grav-tank deployed
   - Or deploy Caladius Grav-tank from army selection

2. **Test Charge Movement:**
   - Enter charge phase
   - Select unit with Caladius Grav-tank
   - Declare charge and roll successfully
   - Begin dragging the model
   - **Expected:** Ghost should show large oval (170mm x 105mm), not small circle
   - **Expected:** Ghost should rotate with Q/E keys showing oval rotation

3. **Test Regular Movement:**
   - Enter movement phase
   - Select unit with Caladius Grav-tank
   - Begin dragging the model
   - **Expected:** Ghost should show large oval matching the model
   - **Expected:** Ghost should rotate with Q/E keys

4. **Test Other Base Types:**
   - Test with circular base models (32mm, 40mm, 60mm)
   - Test with rectangular base models if available
   - **Expected:** All shapes should match the actual model base

5. **Check Deployment:**
   - Deploy new unit with various base shapes
   - **Expected:** Deployment ghost shows correct shape

6. **Check Disembark:**
   - Disembark models from transport
   - **Expected:** Disembark ghost shows correct shape

### Debug Log Validation

Run the game and check Godot debug output or log files:

```bash
# Debug output location (from CLAUDE.md):
# /Users/.../Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log

# Or use:
# print(DebugLogger.get_real_log_file_path())

# Check for debug output showing:
# - Model base_type: oval
# - Model base_mm: 170
# - Model base_dimensions: {length: 170, width: 105}
```

### Visual Validation

**Before Fix:**
- Caladius ghost appears as small circle (~20-30px radius)
- Ghost doesn't rotate with Q/E keys (or rotation not visible)

**After Fix:**
- Caladius ghost appears as large oval (170mm x 105mm ≈ 267px x 165px)
- Ghost visibly rotates with Q/E keys showing oval shape
- Ghost matches the size and shape of the actual model token

## Error Handling

**Potential Issues:**

1. **Missing base_type field:** Falls back to circular (default behavior in Measurement.create_base_shape)
2. **Missing base_dimensions:** Uses base_mm with default aspect ratio
3. **Invalid rotation value:** Defaults to 0.0

**Mitigation:**
- Ensure all model data from GameState includes full base information
- Add warnings if base_type is missing but expected
- Validate base_dimensions before creating oval/rectangular bases

## Tasks Checklist

- [ ] Read ChargeController.gd `_start_model_drag()` function
- [ ] Add debug logging to verify model data completeness
- [ ] Change ghost creation from TokenVisual to GhostVisual
- [ ] Update rotation handling to use `set_base_rotation()`
- [ ] Test with Caladius Grav-tank in charge phase
- [ ] Test with Caladius Grav-tank in movement phase
- [ ] Test with circular base models (verify no regression)
- [ ] Test with rectangular base models if available
- [ ] Verify rotation works correctly (Q/E keys)
- [ ] Remove debug logging after validation
- [ ] Test in deployment phase
- [ ] Test in disembark scenarios
- [ ] Check debug logs for any warnings or errors

## Success Criteria

1. ✅ Caladius Grav-tank drag ghost shows correct oval shape during all movement operations
2. ✅ Ghost size matches actual model base (170mm x 105mm)
3. ✅ Ghost rotation visible and matches model orientation
4. ✅ All other base types (circular, rectangular) still work correctly
5. ✅ No console errors or warnings about missing base data
6. ✅ Consistent behavior across all controllers (Charge, Movement, Deployment, Disembark)

## Confidence Score

**8/10** - High confidence for one-pass implementation

**Reasoning:**
- Clear root cause identified (inconsistent ghost visual class usage)
- Simple, well-defined fix (standardize on GhostVisual.gd)
- Existing working patterns in 3 other controllers
- Comprehensive validation plan
- Well-understood base shape system

**Risk Areas:**
- ChargeController may have unique requirements that TokenVisual addressed
- Potential unknown dependencies on TokenVisual features (e.g., model_number display)
- Need to verify rotation handling works identically with GhostVisual

**Mitigation:**
- Follow MovementController pattern closely (it has similar drag/rotation behavior)
- Test rotation thoroughly since it's a known use case in ChargeController
- Keep debug logging in place until all tests pass
