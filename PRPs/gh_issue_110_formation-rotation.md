# PRP: Formation Rotation During Deployment

## Issue Context

**Problem**: When deploying units with multiple models in formation mode (SPREAD or TIGHT), players cannot rotate the formation before deploying. The Q and E keys only work in SINGLE mode.

**Impact**: Players cannot orient multi-model formations to fit deployment zones efficiently or to face toward objectives/enemy positions. They must either:
- Deploy models individually (losing formation benefits)
- Accept the default horizontal orientation
- Manually reposition each model after placement

**User Requirement**: "I should be able to use Q and E to rotate before deploying. NOTE THAT IF a formation is selected then THE FORMATION ROTATES NOT THE MODELS"

## Research Findings

### Current Implementation Analysis

**DeploymentController.gd** - Lines 83-100:
```gdscript
# Handle rotation controls during deployment (single mode only)
if formation_mode == "SINGLE" and ghost_sprite and event is InputEventKey and event.pressed:
    if event.keycode == KEY_Q:
        # Rotate left
        if ghost_sprite.has_method("rotate_by"):
            ghost_sprite.rotate_by(-PI/12)  # 15 degrees
    elif event.keycode == KEY_E:
        # Rotate right
        if ghost_sprite.has_method("rotate_by"):
            ghost_sprite.rotate_by(PI/12)  # 15 degrees
```

**Key Issue**: The condition `formation_mode == "SINGLE"` prevents rotation in SPREAD and TIGHT modes.

**Formation Calculation Functions** - Lines 833-899:
- `calculate_spread_formation(anchor_pos, model_count, base_mm)` - Creates grid with 2" spacing
- `calculate_tight_formation(anchor_pos, model_count, base_mm)` - Creates grid with bases touching
- Both functions arrange models in a 5-column grid pattern
- **No rotation parameter** - formations are always horizontal

**Formation Mode State** - Lines 17-20:
```gdscript
var formation_mode: String = "SINGLE"  # SINGLE, SPREAD, TIGHT
var formation_size: int = 5  # Models per formation group
var formation_preview_ghosts: Array = []  # Ghost visuals for formation
var formation_anchor_pos: Vector2  # Where user clicks to place formation
```

**Missing**: No `formation_rotation` variable to track rotation angle for formations.

### Root Cause Analysis

**Why Formation Rotation Doesn't Work**:
1. **Input Handler Blocks Formation Rotation**: Line 84 explicitly checks `formation_mode == "SINGLE"`
2. **No Rotation State for Formations**: No variable to store formation rotation angle
3. **No Rotation Transform in Calculations**: Formation calculation functions don't accept or apply rotation
4. **Individual Model Rotation**: The system tracks rotation per model, not per formation

**Architecture Gap**: The current system is designed for:
- Individual model rotation (for vehicles with facing)
- Formation placement without rotation

**What Needs to Change**:
1. Add `formation_rotation` variable to track formation angle
2. Modify formation calculation functions to accept and apply rotation
3. Update input handler to allow Q/E keys in formation modes
4. Apply 2D rotation transform to all formation positions around anchor point
5. Ensure ghosts show rotated formation preview

### Existing Codebase Patterns

**2D Rotation Pattern** (from Godot Vector2):
```gdscript
# Rotate a point around an origin
func rotate_point(point: Vector2, origin: Vector2, angle: float) -> Vector2:
    var offset = point - origin
    var rotated_offset = offset.rotated(angle)
    return origin + rotated_offset
```

**Formation Ghost Management** - Lines 902-958:
```gdscript
func _create_formation_ghosts(count: int) -> void:
    _clear_formation_ghosts()
    # Creates multiple GhostVisual instances
    for i in range(models_to_place):
        var ghost = preload("res://scripts/GhostVisual.gd").new()
        ghost.set_model_data(model_data)
        formation_preview_ghosts.append(ghost)

func _update_formation_ghost_positions(mouse_pos: Vector2) -> void:
    # Calculates positions based on formation mode
    var positions = calculate_spread_formation(...) # or calculate_tight_formation(...)
    # Updates each ghost's position and validity
    for i in range(formation_preview_ghosts.size()):
        ghost.position = positions[i]
        ghost.set_validity(is_valid)
```

**GhostVisual Rotation** (from system reminder):
```gdscript
# GhostVisual.gd has these methods:
func set_base_rotation(rot: float) -> void
func get_base_rotation() -> float
func rotate_by(angle: float) -> void
```

### Technical Research

**Godot 2D Rotation**:
- Reference: https://docs.godotengine.org/en/4.4/classes/class_vector2.html#class-vector2-method-rotated
- `Vector2.rotated(angle)` returns vector rotated by angle (radians) around origin
- Rotation is counter-clockwise for positive angles
- `atan2(y, x)` returns angle of vector from origin

**Formation Rotation Strategy**:
1. Calculate base formation positions (as currently done)
2. Apply rotation transform to each position around the anchor point
3. Individual models maintain 0.0 rotation (formations deploy models upright)
4. The formation shape itself rotates, not the facing of individual models

**Why Not Rotate Individual Models?**:
- User requirement: "THE FORMATION ROTATES NOT THE MODELS"
- Infantry (circular bases) don't need individual facing
- Vehicles in formation would need separate facing control
- Simpler UX: rotate formation as a unit, then adjust individual models later if needed

## Implementation Blueprint

### Design Decisions

**Primary Goals**:
1. Enable Q/E keys to rotate formations in SPREAD and TIGHT modes
2. Rotate the formation pattern around the anchor point
3. Individual models within formation deploy with 0.0 rotation
4. Show rotated formation in ghost preview
5. Maintain all existing validation (deployment zone, overlaps, coherency)

**Approach**: Add Formation Rotation State + Transform Positions
- Add `formation_rotation` variable to track current formation angle
- Modify formation calculation functions to apply rotation transform
- Update input handler to allow rotation in all formation modes
- Apply rotation to ghost positions in preview
- Keep individual model rotations at 0.0 (formation rotates as unit)

**Why This Approach**:
- Minimal changes to existing code
- Reuses existing rotation input handling
- Formations remain coherent during rotation
- Clear separation: formation rotation vs. model rotation
- Preserves all existing validation logic

### Phase 1: Add Formation Rotation State

#### File: `40k/scripts/DeploymentController.gd` (MODIFY)

**After line 20 - Add formation rotation variable**:

```gdscript
# Formation deployment state
var formation_mode: String = "SINGLE"  # SINGLE, SPREAD, TIGHT
var formation_size: int = 5  # Models per formation group
var formation_preview_ghosts: Array = []  # Ghost visuals for formation
var formation_anchor_pos: Vector2  # Where user clicks to place formation
var formation_rotation: float = 0.0  # Rotation angle for formation (radians)
```

**Rationale**: Tracks the current rotation angle of the formation. Separate from individual model rotations.

### Phase 2: Update Input Handler for Formation Rotation

#### File: `40k/scripts/DeploymentController.gd` (MODIFY)

**Lines 83-100 - Modify rotation controls to support formations**:

Replace:
```gdscript
# Handle rotation controls during deployment (single mode only)
if formation_mode == "SINGLE" and ghost_sprite and event is InputEventKey and event.pressed:
    if event.keycode == KEY_Q:
        # Rotate left
        if ghost_sprite.has_method("rotate_by"):
            ghost_sprite.rotate_by(-PI/12)  # 15 degrees
    elif event.keycode == KEY_E:
        # Rotate right
        if ghost_sprite.has_method("rotate_by"):
            ghost_sprite.rotate_by(PI/12)  # 15 degrees
elif event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
        # Rotate with mouse wheel
        if ghost_sprite.has_method("rotate_by"):
            ghost_sprite.rotate_by(PI/12)
    elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
        if ghost_sprite.has_method("rotate_by"):
            ghost_sprite.rotate_by(-PI/12)
```

With:
```gdscript
# Handle rotation controls during deployment
if event is InputEventKey and event.pressed:
    if event.keycode == KEY_Q:
        # Rotate left
        if formation_mode == "SINGLE":
            # Rotate individual model ghost
            if ghost_sprite and ghost_sprite.has_method("rotate_by"):
                ghost_sprite.rotate_by(-PI/12)  # 15 degrees
        else:
            # Rotate formation
            formation_rotation -= PI/12  # 15 degrees counter-clockwise
    elif event.keycode == KEY_E:
        # Rotate right
        if formation_mode == "SINGLE":
            # Rotate individual model ghost
            if ghost_sprite and ghost_sprite.has_method("rotate_by"):
                ghost_sprite.rotate_by(PI/12)  # 15 degrees
        else:
            # Rotate formation
            formation_rotation += PI/12  # 15 degrees clockwise
elif event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
        # Rotate with mouse wheel
        if formation_mode == "SINGLE":
            if ghost_sprite and ghost_sprite.has_method("rotate_by"):
                ghost_sprite.rotate_by(PI/12)
        else:
            formation_rotation += PI/12
    elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
        if formation_mode == "SINGLE":
            if ghost_sprite and ghost_sprite.has_method("rotate_by"):
                ghost_sprite.rotate_by(-PI/12)
        else:
            formation_rotation -= PI/12
```

**Rationale**:
- Supports rotation in all modes (SINGLE, SPREAD, TIGHT)
- SINGLE mode: rotates ghost (existing behavior)
- SPREAD/TIGHT modes: updates formation_rotation angle
- Mouse wheel also supports formation rotation
- Both Q/E keys and mouse wheel work consistently

### Phase 3: Update Formation Calculation Functions

#### File: `40k/scripts/DeploymentController.gd` (MODIFY)

**Lines 833-866 - Add rotation parameter to calculate_spread_formation**:

Replace:
```gdscript
func calculate_spread_formation(anchor_pos: Vector2, model_count: int, base_mm: int) -> Array:
	"""Calculate positions for maximum spread (2 inch coherency)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()
	var spacing_inches = 2.0  # Maximum coherency distance
	var spacing_px = Measurement.inches_to_px(spacing_inches)

	# For spacing, use the maximum dimension of the base
	var base_extent = max(bounds.size.x, bounds.size.y)
	var total_spacing = spacing_px + base_extent

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
```

With:
```gdscript
func calculate_spread_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0) -> Array:
	"""Calculate positions for maximum spread (2 inch coherency)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()
	var spacing_inches = 2.0  # Maximum coherency distance
	var spacing_px = Measurement.inches_to_px(spacing_inches)

	# For spacing, use the maximum dimension of the base
	var base_extent = max(bounds.size.x, bounds.size.y)
	var total_spacing = spacing_px + base_extent

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * total_spacing
		var y_offset = row * total_spacing
		var base_pos = Vector2(x_offset, y_offset)

		# Apply rotation around origin, then translate to anchor
		var rotated_pos = base_pos.rotated(rotation)
		positions.append(anchor_pos + rotated_pos)

	return positions
```

**Lines 868-899 - Add rotation parameter to calculate_tight_formation**:

Replace:
```gdscript
func calculate_tight_formation(anchor_pos: Vector2, model_count: int, base_mm: int) -> Array:
	"""Calculate positions for tight formation (bases touching)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()

	# For tight formation, use actual dimensions plus minimal gap
	var base_extent = max(bounds.size.x, bounds.size.y)
	var spacing_px = base_extent + 1  # 1px gap to prevent overlap

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

With:
```gdscript
func calculate_tight_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0) -> Array:
	"""Calculate positions for tight formation (bases touching)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()

	# For tight formation, use actual dimensions plus minimal gap
	var base_extent = max(bounds.size.x, bounds.size.y)
	var spacing_px = base_extent + 1  # 1px gap to prevent overlap

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * spacing_px
		var y_offset = row * spacing_px
		var base_pos = Vector2(x_offset, y_offset)

		# Apply rotation around origin, then translate to anchor
		var rotated_pos = base_pos.rotated(rotation)
		positions.append(anchor_pos + rotated_pos)

	return positions
```

**Rationale**:
- Adds optional `rotation` parameter (defaults to 0.0 for backward compatibility)
- Applies rotation transform using Vector2.rotated()
- Rotation happens around origin (0,0) before translating to anchor position
- This rotates the formation pattern while keeping models centered on anchor

### Phase 4: Update Formation Ghost Position Updates

#### File: `40k/scripts/DeploymentController.gd` (MODIFY)

**Lines 928-958 - Pass formation_rotation to calculation functions**:

Replace:
```gdscript
func _update_formation_ghost_positions(mouse_pos: Vector2) -> void:
	"""Update positions of all formation ghosts"""
	if formation_preview_ghosts.is_empty():
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	if remaining_models.is_empty():
		return

	var model_data = unit_data["models"][remaining_models[0]]
	var base_mm = model_data["base_mm"]

	var positions = []
	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(mouse_pos, formation_preview_ghosts.size(), base_mm)
		"TIGHT":
			positions = calculate_tight_formation(mouse_pos, formation_preview_ghosts.size(), base_mm)

	# Update ghost positions and validity
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
	for i in range(formation_preview_ghosts.size()):
		var ghost = formation_preview_ghosts[i]
		if i < positions.size():
			ghost.position = positions[i]
			ghost.visible = true

			# Check validity for each ghost position
			var is_valid = _validate_formation_position(positions[i], model_data, zone)
			ghost.set_validity(is_valid)
```

With:
```gdscript
func _update_formation_ghost_positions(mouse_pos: Vector2) -> void:
	"""Update positions of all formation ghosts"""
	if formation_preview_ghosts.is_empty():
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	if remaining_models.is_empty():
		return

	var model_data = unit_data["models"][remaining_models[0]]
	var base_mm = model_data["base_mm"]

	var positions = []
	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation)
		"TIGHT":
			positions = calculate_tight_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation)

	# Update ghost positions and validity
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
	for i in range(formation_preview_ghosts.size()):
		var ghost = formation_preview_ghosts[i]
		if i < positions.size():
			ghost.position = positions[i]
			ghost.visible = true

			# Check validity for each ghost position
			var is_valid = _validate_formation_position(positions[i], model_data, zone)
			ghost.set_validity(is_valid)
```

**Rationale**: Passes current `formation_rotation` to formation calculation functions so ghosts preview the rotated formation.

### Phase 5: Update Formation Placement Function

#### File: `40k/scripts/DeploymentController.gd` (MODIFY)

**Lines 201-268 - Pass formation_rotation when placing models**:

Find these lines (~217-223):
```gdscript
	var positions = []

	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(world_pos, models_to_place, base_mm)
		"TIGHT":
			positions = calculate_tight_formation(world_pos, models_to_place, base_mm)
```

Replace with:
```gdscript
	var positions = []

	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(world_pos, models_to_place, base_mm, formation_rotation)
		"TIGHT":
			positions = calculate_tight_formation(world_pos, models_to_place, base_mm, formation_rotation)
```

**Rationale**: Applies formation rotation when actually placing models, ensuring placed models match the ghost preview.

### Phase 6: Reset Formation Rotation on Mode Change

#### File: `40k/scripts/DeploymentController.gd` (MODIFY)

**Lines 808-822 - Reset rotation when changing formation mode**:

Replace:
```gdscript
# Formation mode management
func set_formation_mode(mode: String) -> void:
	formation_mode = mode
	print("[DeploymentController] Formation mode set to: ", mode)

	# If we're currently placing, update the ghosts
	if is_placing():
		if mode == "SINGLE":
			_clear_formation_ghosts()
			if not ghost_sprite:
				_create_ghost()
		else:
			_remove_ghost()
			var remaining = _get_unplaced_model_indices()
			if not remaining.is_empty():
				_create_formation_ghosts(min(formation_size, remaining.size()))
```

With:
```gdscript
# Formation mode management
func set_formation_mode(mode: String) -> void:
	formation_mode = mode
	formation_rotation = 0.0  # Reset rotation when changing modes
	print("[DeploymentController] Formation mode set to: ", mode)

	# If we're currently placing, update the ghosts
	if is_placing():
		if mode == "SINGLE":
			_clear_formation_ghosts()
			if not ghost_sprite:
				_create_ghost()
		else:
			_remove_ghost()
			var remaining = _get_unplaced_model_indices()
			if not remaining.is_empty():
				_create_formation_ghosts(min(formation_size, remaining.size()))
```

**Rationale**: Reset formation rotation to 0.0 when switching modes to avoid confusion. Each mode starts with default orientation.

### Phase 7: Reset Formation Rotation When Starting Deployment

#### File: `40k/scripts/DeploymentController.gd` (MODIFY)

**Lines 102-130 - Reset rotation at start of deployment**:

Find line ~110:
```gdscript
	temp_rotations.fill(0.0)
```

After this line, add:
```gdscript
	temp_rotations.fill(0.0)
	formation_rotation = 0.0  # Reset formation rotation for new unit
```

**Rationale**: Each unit deployment starts with default formation orientation. Previous unit's rotation shouldn't carry over.

## Implementation Tasks

Execute these tasks in order:

### Task 1: Add Formation Rotation State
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] After line 20, add: `var formation_rotation: float = 0.0  # Rotation angle for formation (radians)`
- [ ] Save file

### Task 2: Update Input Handler for Formation Rotation
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] Find lines 83-100 (rotation input handling)
- [ ] Replace with new code that supports formation rotation (see Phase 2 blueprint)
- [ ] Verify Q/E and mouse wheel work for both SINGLE and formation modes
- [ ] Save file

### Task 3: Update Formation Calculation Functions
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] Find `calculate_spread_formation()` function (~line 833)
- [ ] Add `rotation: float = 0.0` parameter
- [ ] Add rotation transform: `var rotated_pos = base_pos.rotated(rotation)`
- [ ] Update position calculation to use `rotated_pos`
- [ ] Repeat for `calculate_tight_formation()` function (~line 868)
- [ ] Save file

### Task 4: Update Formation Ghost Position Updates
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] Find `_update_formation_ghost_positions()` function (~line 928)
- [ ] Pass `formation_rotation` parameter to both `calculate_spread_formation()` and `calculate_tight_formation()` calls
- [ ] Save file

### Task 5: Update Formation Placement Function
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] Find `try_place_formation_at()` function (~line 201)
- [ ] Find the match statement with formation calculations (~line 217-223)
- [ ] Pass `formation_rotation` parameter to both formation calculation calls
- [ ] Save file

### Task 6: Reset Formation Rotation on Mode Change
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] Find `set_formation_mode()` function (~line 808)
- [ ] After setting `formation_mode = mode`, add: `formation_rotation = 0.0`
- [ ] Save file

### Task 7: Reset Formation Rotation When Starting Deployment
- [ ] Open `40k/scripts/DeploymentController.gd`
- [ ] Find `begin_deploy()` function (~line 102)
- [ ] After `temp_rotations.fill(0.0)` line, add: `formation_rotation = 0.0`
- [ ] Save file

### Task 8: Update Formation Tests
- [ ] Open `40k/tests/ui/test_deployment_formations.gd`
- [ ] Update `test_spread_formation_calculation()` to test with rotation parameter
- [ ] Update `test_tight_formation_calculation()` to test with rotation parameter
- [ ] Add new test: `test_formation_rotation()` to verify rotation works
- [ ] Save file

## Validation Gates

All validation commands must pass:

```bash
# 1. Set Godot path
export PATH="$HOME/bin:$PATH"

# 2. Syntax check - ensure code compiles
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --headless --path . --check-only

# Expected: No syntax errors

# 3. Run formation tests (regression + new rotation tests)
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/ui/test_deployment_formations.gd \
  -glog=1 \
  -gexit

# Expected: All tests pass

# 4. Run deployment phase tests
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/phases/test_deployment_phase.gd \
  -glog=1 \
  -gexit

# Expected: All tests pass, no regressions

# 5. Manual integration test - Formation rotation
godot --path . &

# In game:
# 1. Start new game
# 2. Select unit to deploy
# 3. Click "Spread (2\")" formation button
# 4. Press Q key multiple times - formation should rotate counter-clockwise
# 5. Press E key multiple times - formation should rotate clockwise
# 6. Try mouse wheel up/down - formation should rotate
# 7. Click to place - models should deploy in rotated formation
# 8. Switch to "Tight" formation
# 9. Repeat rotation test
# 10. Switch to "Single" mode
# 11. Verify individual model rotation still works (Q/E rotates ghost)

# Kill game when done
kill %1

# Expected:
# - Q/E keys rotate formation preview in SPREAD and TIGHT modes
# - Mouse wheel rotation works for formations
# - Formation ghosts show correct rotated positions
# - Placed models match rotated formation preview
# - Individual model rotation still works in SINGLE mode
# - No errors or crashes

# 6. Check debug logs for errors
tail -50 ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log

# Expected: No errors related to rotation or formation
```

## Success Criteria

- [ ] Q key rotates formation counter-clockwise (15 degrees) in SPREAD mode
- [ ] E key rotates formation clockwise (15 degrees) in SPREAD mode
- [ ] Q key rotates formation counter-clockwise (15 degrees) in TIGHT mode
- [ ] E key rotates formation clockwise (15 degrees) in TIGHT mode
- [ ] Mouse wheel rotates formations in both SPREAD and TIGHT modes
- [ ] Formation ghost preview shows rotated positions
- [ ] Placed models match the rotated formation preview
- [ ] Individual model rotation still works in SINGLE mode (no regression)
- [ ] Formation rotation resets to 0.0 when changing modes
- [ ] Formation rotation resets to 0.0 when starting new unit deployment
- [ ] All existing formation tests pass
- [ ] No errors in debug logs
- [ ] Formation validation (zone boundaries, overlaps) works with rotated formations

## Common Pitfalls & Solutions

### Issue: Rotation not working in formation mode despite changes
**Solution**: Verify the input handler checks `formation_mode != "SINGLE"` for formation rotation branch. The logic should be inverted from the original.

### Issue: Formation rotates around wrong point
**Solution**: Ensure rotation is applied BEFORE translating to anchor position. Formula: `anchor_pos + base_pos.rotated(rotation)`, not `(anchor_pos + base_pos).rotated(rotation)`.

### Issue: Ghosts show rotation but placed models don't
**Solution**: Verify `try_place_formation_at()` passes `formation_rotation` to the formation calculation functions, not just `_update_formation_ghost_positions()`.

### Issue: Rotation persists between different units
**Solution**: Ensure `formation_rotation = 0.0` is set in `begin_deploy()` function so each unit starts fresh.

### Issue: Rotation accumulates incorrectly with repeated key presses
**Solution**: Use `formation_rotation += PI/12` not `formation_rotation = PI/12`. The += operator accumulates the angle correctly.

### Issue: Formation validation fails after rotation
**Solution**: Validation functions receive rotated positions from the calculation functions. No changes needed to validation logic - it should work automatically with rotated positions.

### Issue: Individual model rotation broken after changes
**Solution**: Verify the SINGLE mode branch in input handler still calls `ghost_sprite.rotate_by()`. Both branches should exist: one for SINGLE mode (individual), one for formation modes.

### Issue: Mouse wheel rotation conflicts with zoom
**Solution**: If mouse wheel is used for camera zoom, this could conflict. Consider whether to keep mouse wheel rotation or remove it. The PRP includes it for consistency, but it's optional.

## References

### Code References
- `DeploymentController.gd` lines 17-21 - Formation state variables
- `DeploymentController.gd` lines 83-100 - Rotation input handling (to be modified)
- `DeploymentController.gd` lines 833-899 - Formation calculation functions (to be modified)
- `DeploymentController.gd` lines 928-958 - Ghost position updates (to be modified)
- `DeploymentController.gd` lines 201-268 - Formation placement (to be modified)
- `test_deployment_formations.gd` - Existing formation tests (to be extended)

### External Documentation
- Godot Vector2.rotated(): https://docs.godotengine.org/en/4.4/classes/class_vector2.html#class-vector2-method-rotated
- Godot 2D Transforms: https://docs.godotengine.org/en/4.4/tutorials/math/matrices_and_transforms.html
- Godot Input Handling: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html

### Warhammer Rules
- Deployment: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Deployment
- Unit Coherency: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Unit-Coherency
- Formations help maintain coherency during deployment

### Related PRPs
- `gh_issue_79_deployment-formations.md` - Original formation system implementation
- `gh_issue_105_rotation-keys-fix.md` - Fixed Q/E rotation for individual models

## PRP Quality Checklist

- [x] All necessary context included (current code, formation system, rotation patterns)
- [x] Validation gates are executable commands
- [x] References existing patterns (Vector2.rotated, formation calculations)
- [x] Clear implementation path with step-by-step tasks
- [x] Error handling documented (reset on mode change, validation preserved)
- [x] Code examples are complete and runnable
- [x] Manual test suite provided
- [x] Root cause analysis provided (input handler blocks formations)
- [x] Common pitfalls addressed (rotation order, state persistence)
- [x] External references included (Godot docs, Warhammer rules)

## Confidence Score

**10/10** - Very high confidence in one-pass implementation success

**Reasoning**:
- Simple, focused change: add rotation parameter and apply transform
- Existing rotation system for SINGLE mode provides proven pattern
- Formation calculation functions are well-structured and easy to modify
- Godot's `Vector2.rotated()` handles 2D rotation elegantly
- No complex math or edge cases - just geometric transformation
- Clear separation of concerns: formation rotation vs. model rotation
- All validation logic works automatically with rotated positions
- Easy to test: press Q/E and visually see rotation
- No changes to existing validation, collision, or deployment zone logic
- Minimal code changes: 5 small modifications to existing functions
- No risk of breaking existing functionality (separate code paths)
- Formation system is already mature and tested

**Risk**: Minimal - This is an additive feature that extends existing rotation capabilities to formations without modifying core deployment or validation logic.
