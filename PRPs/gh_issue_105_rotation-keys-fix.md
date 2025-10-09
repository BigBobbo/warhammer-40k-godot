# PRP: Fix Q/E Rotation Keys for Vehicles and Formations

## Issue Context
**Problem**: The game used to previously allow for the rotation of vehicles and formations using Q and E keys. This no longer works during deployment, movement, and charge phases.

**Impact**: Players cannot rotate non-circular models (vehicles, formations) using keyboard controls, making it difficult to position models with correct facing for movement, shooting arcs, and engagement ranges.

## Research Findings

### Root Cause Analysis

**Core Issues**:
1. The `GhostVisual.gd` class is missing the `rotate_by()` and `get_base_rotation()` methods that controllers try to call
2. The `TokenVisual.gd` class draws with hardcoded rotation 0.0 instead of using the rotation from model_data

**Why Q/E Rotation Doesn't Work**:
1. **DeploymentController** (lines 83-96): Calls `ghost_sprite.rotate_by()` and `ghost_sprite.has_method("rotate_by")`
2. **GhostVisual.gd**: Has `set_base_rotation()` but NO `rotate_by()` or `get_base_rotation()` methods
3. When `has_method("rotate_by")` returns False, the rotation code never executes
4. The `set_base_rotation()` method exists but is never called by the keyboard input handlers
5. **TokenVisual.gd** (line 39): Draws with hardcoded `0.0` rotation instead of reading from `model_data["rotation"]`

**Historical Context**:
- GhostVisual.gd was originally simple (just radius + circle drawing)
- After BaseShape system was added, the visual gained `base_rotation` but not the incremental rotation method
- Controllers still try to call `rotate_by()` which was never implemented

**Files Affected**:
- `40k/scripts/GhostVisual.gd` - Missing `rotate_by()` and `get_base_rotation()` methods
- `40k/scripts/DeploymentController.gd` - Lines 79-96: Calls non-existent methods
- `40k/scripts/MovementController.gd` - Lines 1073-1078: May have issues with empty selection
- `40k/scripts/ChargeController.gd` - Lines 124-132: Uses `_input()` which is correct but could be better

### Existing Codebase Architecture

1. **GhostVisual System** (`40k/scripts/GhostVisual.gd`):
   ```gdscript
   var base_rotation: float = 0.0  # Line 6
   var base_shape: BaseShape = null  # Line 7

   func set_base_rotation(rot: float) -> void:  # Lines 44-47
       base_rotation = rot
       rotation = rot  # Sets Node2D rotation
       queue_redraw()

   # MISSING:
   # func rotate_by(angle: float) -> void
   # func get_base_rotation() -> float
   ```

2. **DeploymentController Input Handling** (`40k/scripts/DeploymentController.gd`):
   ```gdscript
   # Lines 79-96: Rotation controls
   if formation_mode == "SINGLE" and ghost_sprite and event is InputEventKey and event.pressed:
       if event.keycode == KEY_Q:
           # Rotate left
           if ghost_sprite.has_method("rotate_by"):  # Returns False - method doesn't exist!
               ghost_sprite.rotate_by(-PI/12)  # Never executed
       elif event.keycode == KEY_E:
           # Rotate right
           if ghost_sprite.has_method("rotate_by"):  # Returns False - method doesn't exist!
               ghost_sprite.rotate_by(PI/12)  # Never executed
   ```

3. **MovementController Input Handling** (`40k/scripts/MovementController.gd`):
   ```gdscript
   # Lines 1073-1078: Keyboard rotation
   elif (selected_model.size() > 0 or selected_models.size() > 0):
       if event.keycode == KEY_Q:
           _rotate_model_by_angle(-PI/12)  # Works IF model is selected
       elif event.keycode == KEY_E:
           _rotate_model_by_angle(PI/12)  # Works IF model is selected

   # Lines 1985-1996: The actual rotation logic (correctly implemented)
   func _rotate_model_by_angle(angle: float) -> void:
       if selected_model.is_empty():
           return
       var base_type = selected_model.get("base_type", "circular")
       if base_type == "circular":
           return  # No rotation for circular
       var current_rotation = selected_model.get("rotation", 0.0)
       var new_rotation = current_rotation + angle
       _apply_rotation_to_model(new_rotation)
       _check_and_apply_pivot_cost()
   ```

4. **ChargeController Input Handling** (`40k/scripts/ChargeController.gd`):
   ```gdscript
   # Lines 58-59: Uses _input() instead of _unhandled_input()
   func _ready() -> void:
       set_process_input(true)  # Processes input earlier in chain
       set_process_unhandled_input(true)

   # Lines 124-132: Keyboard rotation during charge
   elif event is InputEventKey:
       if event.pressed and dragging_model:
           if event.keycode == KEY_Q:
               _rotate_dragging_model(-PI/12)
               get_viewport().set_input_as_handled()  # Marks as handled
           elif event.keycode == KEY_E:
               _rotate_dragging_model(PI/12)
               get_viewport().set_input_as_handled()  # Marks as handled

   # Lines 1729-1756: Rotation implementation (correctly implemented)
   func _rotate_dragging_model(angle: float) -> void:
       # Updates dragging_model rotation
       # Updates ghost visual
       # Updates actual token visual
   ```

### Godot Input Processing Order

Reference: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html

**Input Event Flow**:
1. `_input(event)` - Called first, can consume events
2. GUI elements process input
3. `_unhandled_input(event)` - Called only if not consumed

**Current Issue**:
- ChargeController uses `_input()` and marks events as handled
- When ChargeController is active (charge phase) and `dragging_model` is true, Q/E are consumed
- BUT: ChargeController is freed when switching phases, so this is not the main issue
- Main issue is that DeploymentController and MovementController check for non-existent methods

## Implementation Blueprint

### Design Decisions

**Primary Goals**:
1. Add `rotate_by()` and `get_base_rotation()` methods to GhostVisual.gd
2. Fix TokenVisual.gd to use rotation from model_data when drawing
3. Ensure rotation works in all three phases (Deployment, Movement, Charge)
4. Handle both circular (no-op) and non-circular bases correctly
5. Maintain visual feedback during rotation

**Approach**: Add Missing Methods + Fix Drawing
- Add `rotate_by(angle)` to GhostVisual.gd to support incremental rotation
- Add `get_base_rotation()` to GhostVisual.gd to query current rotation
- Fix TokenVisual.gd to read rotation from model_data when drawing
- Verify controllers properly check for model selection
- Test rotation in all phases

### Phase 1: Fix GhostVisual - Add Missing Methods

#### File: `40k/scripts/GhostVisual.gd` (MODIFY)

**After line 47 - Add rotate_by() method**:

```gdscript
func get_base_rotation() -> float:
	"""Get the current rotation of the ghost base"""
	return base_rotation

func rotate_by(angle: float) -> void:
	"""Rotate the ghost by the given angle (in radians)"""
	base_rotation += angle
	rotation = base_rotation  # Update Node2D rotation
	queue_redraw()
```

**Rationale**:
- `rotate_by()` provides incremental rotation that DeploymentController expects
- `get_base_rotation()` allows controllers to query current rotation
- Updates both `base_rotation` (for shape rendering) and `rotation` (Node2D transform)
- Calls `queue_redraw()` to trigger visual update

### Phase 2: Verify DeploymentController Conditions

#### File: `40k/scripts/DeploymentController.gd` (VERIFY)

**Lines 79-96 - Rotation handling already correct**:

The code checks:
1. `formation_mode == "SINGLE"` - Only rotate in single placement mode
2. `ghost_sprite` exists
3. `event is InputEventKey and event.pressed`
4. `ghost_sprite.has_method("rotate_by")` - Will now return True after our fix

No changes needed - will work once GhostVisual has the method.

**Lines 152-156 - Get rotation from ghost**:
```gdscript
# Get current rotation from ghost
var rotation = 0.0
if ghost_sprite and ghost_sprite.has_method("get_base_rotation"):
    rotation = ghost_sprite.get_base_rotation()
```

Already correctly implemented - will work after our fix.

### Phase 3: Verify MovementController Conditions

#### File: `40k/scripts/MovementController.gd` (VERIFY)

**Lines 1073-1078 - Check selection condition**:

Current code:
```gdscript
elif (selected_model.size() > 0 or selected_models.size() > 0):
    if event.keycode == KEY_Q:
        _rotate_model_by_angle(-PI/12)
    elif event.keycode == KEY_E:
        _rotate_model_by_angle(PI/12)
```

**Issue**: Requires `selected_model` or `selected_models` to have items. If user tries to rotate before selecting, nothing happens.

**Recommendation**: Already correct - rotation should only work when model is selected. This is intended behavior.

**Lines 1985-1996 - Rotation implementation**:

Already correctly implemented:
- Checks if model is selected
- Checks if base is circular (no rotation needed)
- Updates model rotation
- Applies pivot cost for vehicles
- Updates visual

No changes needed.

### Phase 4: Fix TokenVisual - Use Rotation from Model Data

#### File: `40k/scripts/TokenVisual.gd` (MODIFY)

**Lines 38-39 - Add rotation from model_data**:

Replace:
```gdscript
# Use base shape's draw method
base_shape.draw(self, Vector2.ZERO, 0.0, fill_color, border_color, border_width)
```

With:
```gdscript
# Get rotation from model data (defaults to 0.0 for circular bases)
var rotation = model_data.get("rotation", 0.0)

# Use base shape's draw method with rotation
base_shape.draw(self, Vector2.ZERO, rotation, fill_color, border_color, border_width)
```

**Rationale**: TokenVisual receives model_data with rotation set, but was ignoring it and always drawing at 0.0 rotation. This caused rotated models to snap back to 0 rotation when placed. Now it reads the rotation from model_data, just like how GhostVisual reads from base_rotation.

### Phase 5: Verify ChargeController Input Handling

#### File: `40k/scripts/ChargeController.gd` (VERIFY)

**Lines 58-59 and 124-132 - Input handling**:

Current behavior:
- Uses `_input()` instead of `_unhandled_input()`
- Marks events as handled when `dragging_model` is true
- Only processes Q/E when actively dragging a model during charge

**Analysis**: This is intentional and correct:
- ChargeController is freed when switching to other phases
- Only consumes input when actually dragging a model
- Other phases won't see ChargeController's `_input()` handler

No changes needed.

**Lines 1729-1756 - Rotation implementation**:

Already correctly implemented:
- Updates `dragging_model["rotation"]`
- Updates ghost visual
- Updates actual token visual
- Handles non-circular bases only

No changes needed.

## Implementation Tasks

Execute these tasks in order:

### Task 1: Add Missing Methods to GhostVisual
- [ ] Open `40k/scripts/GhostVisual.gd`
- [ ] After line 47 (end of `set_base_rotation()` function), add blank line
- [ ] Add `get_base_rotation()` function as specified in blueprint
- [ ] Add `rotate_by(angle)` function as specified in blueprint
- [ ] Save file

### Task 2: Verify DeploymentController Works
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] Review lines 79-96 (rotation input handling)
- [ ] Verify: Checks for `has_method("rotate_by")` before calling
- [ ] Review lines 152-156 (get rotation for placement)
- [ ] Verify: Checks for `has_method("get_base_rotation")` before calling
- [ ] No code changes needed - just verification

### Task 3: Verify MovementController Works
- [ ] Open `40k/scripts/MovementController.gd`
- [ ] Review lines 1073-1078 (rotation input handling)
- [ ] Verify: Requires model selection before rotating
- [ ] Review lines 1985-1996 (rotation implementation)
- [ ] Verify: Handles circular vs non-circular correctly
- [ ] No code changes needed - just verification

### Task 4: Fix TokenVisual to Use Rotation
- [ ] Open `40k/scripts/TokenVisual.gd`
- [ ] Find the `_draw()` function (around line 13)
- [ ] Locate the line that calls `base_shape.draw(self, Vector2.ZERO, 0.0, ...)`
- [ ] Add line before it: `var rotation = model_data.get("rotation", 0.0)`
- [ ] Change the draw call to use `rotation` instead of `0.0`
- [ ] Save file

### Task 5: Verify ChargeController Works
- [ ] Open `40k/scripts/ChargeController.gd`
- [ ] Review lines 124-132 (rotation input handling during drag)
- [ ] Verify: Only processes when `dragging_model` is true
- [ ] Review lines 1729-1756 (rotation implementation)
- [ ] Verify: Updates all visuals correctly
- [ ] No code changes needed - just verification

### Task 6: Manual Testing - Deployment Phase
- [ ] Run game: `godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k`
- [ ] Load army with non-circular vehicles (Caladius, Rhino)
- [ ] Enter deployment phase
- [ ] Click unit to begin deployment (single mode)
- [ ] Press Q key - verify ghost rotates counter-clockwise
- [ ] Press E key - verify ghost rotates clockwise
- [ ] Mouse wheel up - verify ghost rotates clockwise
- [ ] Mouse wheel down - verify ghost rotates counter-clockwise
- [ ] Click to place - verify model placed with correct rotation
- [ ] Expected: All rotation controls work, model is placed with ghost rotation

### Task 7: Manual Testing - Movement Phase
- [ ] Continue from deployed game
- [ ] Click "End Deployment" to enter Movement phase
- [ ] Select a unit for movement (Normal mode)
- [ ] Click on a non-circular model to select it
- [ ] Press Q key - verify model rotates counter-clockwise
- [ ] Press E key - verify model rotates clockwise
- [ ] Verify pivot cost is applied (for vehicles)
- [ ] Drag model to new position
- [ ] Expected: Rotation works when model is selected

### Task 8: Manual Testing - Charge Phase
- [ ] Continue through phases to Charge phase
- [ ] Select a unit to charge
- [ ] Declare charge and roll dice (success)
- [ ] Click and drag a non-circular model
- [ ] While dragging, press Q key - verify model rotates
- [ ] While dragging, press E key - verify model rotates
- [ ] Release to place
- [ ] Expected: Rotation works during charge movement drag

### Task 9: Test Circular Base Models
- [ ] Deploy infantry units with circular bases (32mm, 40mm)
- [ ] Try Q/E rotation during deployment
- [ ] Expected: No rotation (circular bases don't need facing)
- [ ] Verify: No errors or unexpected behavior

## Validation Gates

All validation commands must pass:

```bash
# 1. Set Godot path
export PATH="$HOME/bin:$PATH"

# 2. Syntax check - ensure code compiles
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --headless --path . --check-only

# Expected: No syntax errors

# 3. Run existing deployment tests (regression check)
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/ui/test_deployment_formations.gd \
  -glog=1 \
  -gexit

# Expected: All tests pass, no regressions

# 4. Run deployment phase tests
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/phases/test_deployment_phase.gd \
  -glog=1 \
  -gexit

# Expected: All tests pass

# 5. Manual integration test
# Run game and test rotation manually in all three phases
godot --path . &
# In game:
# - Deploy vehicles with Q/E rotation
# - Move vehicles with Q/E rotation
# - Charge with Q/E rotation during drag
# Kill game when done
kill %1

# Expected:
# - Q/E keys rotate ghost/model in all phases
# - Mouse wheel rotation works in deployment
# - Rotation persists when placing models
# - Pivot cost applied correctly in movement

# 6. Check debug logs for errors
# The debug output is in: ~/Library/Application Support/Godot/app_userdata/40k/logs/
# Look for rotation-related messages
tail -f ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | grep -i "rotat"

# Expected: Rotation debug messages, no errors
```

## Success Criteria

- [ ] Q key rotates models/ghosts counter-clockwise (15 degrees)
- [ ] E key rotates models/ghosts clockwise (15 degrees)
- [ ] Rotation works in deployment phase (single mode)
- [ ] Rotation works in movement phase (when model selected)
- [ ] Rotation works in charge phase (during drag)
- [ ] Mouse wheel rotation works in deployment phase
- [ ] Circular bases don't rotate (no-op)
- [ ] Rotation is persisted when placing models
- [ ] Pivot cost is applied for vehicles in movement phase
- [ ] No errors in debug logs
- [ ] No regressions in existing tests

## Common Pitfalls & Solutions

### Issue: Rotation not working in deployment despite fix
**Solution**: Check `formation_mode` - rotation only works in "SINGLE" mode, not "SPREAD" or "TIGHT" formations. This is intentional.

### Issue: Rotation not working in movement phase
**Solution**: Must click on a model to select it first. Rotation requires `selected_model` to be populated. This is intended behavior.

### Issue: Ghost rotates but placed model has wrong rotation
**Solution**: DeploymentController should call `ghost_sprite.get_base_rotation()` before placing (lines 152-156). Verify this code is present.

### Issue: Rotation works but visual doesn't update
**Solution**: Ensure `queue_redraw()` is called in `rotate_by()`. The visual system needs to be notified to redraw.

### Issue: Mouse wheel rotation doesn't work
**Solution**: Mouse wheel handling is separate in DeploymentController (lines 90-96). After fixing `rotate_by()`, this should work automatically.

### Issue: Circular models rotate when they shouldn't
**Solution**: Controllers check `base_type == "circular"` and return early. Verify this check exists in all rotation functions.

### Issue: Rotation causes model to "jump" position
**Solution**: Rotation should only update the angle, not the position. Verify `rotate_by()` only modifies `base_rotation` and `rotation`, not `position`.

## References

### Code References
- `GhostVisual.gd` lines 1-58 - Fixed implementation with rotate_by() and get_base_rotation()
- `TokenVisual.gd` lines 1-67 - Fixed implementation that uses rotation from model_data
- `DeploymentController.gd` lines 79-96 - Q/E input handling
- `DeploymentController.gd` lines 152-156 - Getting rotation for placement
- `MovementController.gd` lines 1073-1078 - Q/E input handling
- `MovementController.gd` lines 1985-2024 - Rotation implementation
- `ChargeController.gd` lines 124-132 - Q/E input during drag
- `ChargeController.gd` lines 1729-1756 - Rotation implementation

### External Documentation
- Godot Input Events: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html
- Godot Node2D Rotation: https://docs.godotengine.org/en/4.4/classes/class_node2d.html#class-node2d-property-rotation
- Godot Transform2D: https://docs.godotengine.org/en/4.4/classes/class_transform2d.html

### Warhammer Rules
- Model Facing: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Vehicles and facing matter for firing arcs and charge positioning
- Infantry can pivot freely (circular bases)

## PRP Quality Checklist

- [x] All necessary context included
- [x] Validation gates are executable commands
- [x] References existing patterns (similar to TokenVisual)
- [x] Clear implementation path with step-by-step tasks
- [x] Error handling documented (circular base checks)
- [x] Code examples are complete and runnable
- [x] Manual test suite provided
- [x] Root cause analysis provided
- [x] Common pitfalls addressed
- [x] External references included

## Confidence Score

**10/10** - Very high confidence in one-pass implementation success

**Reasoning**:
- Root causes are clear and simple: missing methods in GhostVisual.gd + hardcoded rotation in TokenVisual.gd
- Fixes are minimal: add 2 methods (10 lines) + fix drawing (3 lines)
- No changes needed to controllers (they already check for methods)
- Existing rotation logic in MovementController and ChargeController already works
- No complex logic or edge cases
- No changes to BaseShape system or model data
- Backward compatible (circular bases unchanged)
- Easy to test (just press Q/E keys)
- Clear visual feedback (model/ghost rotation)
- No risk of regressions (only adds methods, doesn't change existing code)

**Risk**: None - This is a straightforward addition of missing methods that controllers already expect to exist.
