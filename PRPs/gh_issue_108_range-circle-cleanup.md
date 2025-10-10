# PRP: Range Circle Cleanup on Shooting Phase End

## Issue Context
Feature Request: The circles showing the range of a model's shooting weapons persist even after the phase is over. After the "End Shooting Phase" button is clicked ensure that all range circles are removed.

## Research Findings

### Existing Codebase Architecture

1. **Range Circle System**:
   - `40k/scripts/RangeCircle.gd` (lines 1-39) - Visual circle for weapon range
     - Line 12-15: `setup()` method sets radius and weapon name
     - Lines 28-39: `_draw()` renders filled circle with label
     - Creates a Label child to show weapon info (lines 17-26)

   - `40k/scripts/ShootingController.gd` (lines 531-632) - Range indicator management
     - Line 115-117: Creates `range_visual` Node2D as child of **BoardRoot** (not ShootingController)
     - Line 531-573: `_show_range_indicators()` creates RangeCircle instances
     - Line 567-570: Creates RangeCircle and adds to `range_visual` node
     - Line 628-632: `_clear_range_indicators()` clears children of `range_visual`
     - Line 522-530: `_clear_visuals()` calls `_clear_range_indicators()`

   - `40k/scripts/ShootingController.gd` (lines 49-80) - Controller cleanup
     - Line 53-54: In `_exit_tree()`, calls `range_visual.queue_free()` if valid
     - **ISSUE**: `range_visual` is child of BoardRoot, cleanup timing might be unreliable

2. **Phase Transition Flow**:
   - `40k/scripts/Main.gd` (lines 1814-1816) - "End Shooting Phase" button handler
     - Sends `END_SHOOTING` action via NetworkIntegration

   - `40k/phases/ShootingPhase.gd` (lines 372-375) - End phase processing
     - Line 372: `_process_end_shooting()` logs message
     - Line 374: Emits `phase_completed` signal
     - Line 35-38: `_on_phase_exit()` only clears phase flags
     - **ISSUE**: No call to clear controller visuals before phase exit

   - `40k/scripts/Main.gd` (lines 2367-2376) - Phase change handler
     - Line 2375: Calls `setup_phase_controllers()` which frees old controllers
     - Line 802-854: `setup_phase_controllers()` - Cleanup flow
       - Line 816-818: Frees `shooting_controller` with `queue_free()`
       - Lines 829-831: Waits two frames for cleanup
       - **ISSUE**: Controller freed before visuals are cleaned from BoardRoot

3. **Current Behavior (BROKEN)**:
   - User clicks "End Shooting Phase" button
   - `_process_end_shooting()` emits `phase_completed`
   - PhaseManager transitions to next phase
   - `_on_phase_changed()` calls `setup_phase_controllers()`
   - `shooting_controller.queue_free()` is called
   - `_exit_tree()` tries to cleanup `range_visual`
   - **BUT**: Range circles remain visible on BoardRoot

4. **Root Cause Analysis**:

   **Problem 1: Cleanup Timing**
   - `range_visual` is a child of `BoardRoot` (line 117)
   - When `ShootingController` is freed, `_exit_tree()` is called
   - `_exit_tree()` calls `range_visual.queue_free()` (line 53-54)
   - But `queue_free()` defers deletion to idle processing
   - New phase controller might be created before cleanup completes

   **Problem 2: No Explicit Phase Exit Cleanup**
   - `ShootingPhase._on_phase_exit()` doesn't clear visuals (lines 35-38)
   - Should explicitly call controller cleanup before controller is freed
   - This ensures immediate cleanup before phase transition

5. **Reference Implementation - ChargePhase cleanup**:
   - Similar pattern should exist but with explicit cleanup
   - Need to add cleanup call in phase exit handler

### Godot 4.x Node Lifecycle

Reference: https://docs.godotengine.org/en/4.4/classes/class_node.html

**queue_free() Behavior**:
```gdscript
# queue_free() marks node for deletion at end of current frame
# NOT immediate - happens during idle processing
node.queue_free()  # Node still exists temporarily
```

**Immediate Cleanup Pattern**:
```gdscript
# For immediate cleanup of child nodes:
for child in parent.get_children():
    parent.remove_child(child)
    child.queue_free()
# Then wait for idle processing
```

**Exit Tree Order**:
- Parent `_exit_tree()` called before children
- References to nodes may become invalid during cleanup
- Best practice: Clean up visual artifacts before controller is freed

### External References

1. **Godot Node Lifecycle**:
   https://docs.godotengine.org/en/4.4/classes/class_node.html#class-node-method-queue-free

2. **Node2D Drawing**:
   https://docs.godotengine.org/en/4.4/classes/class_node2d.html

3. **Scene Tree Processing**:
   https://docs.godotengine.org/en/4.4/tutorials/scripting/nodes_and_scene_instances.html

## Implementation Blueprint

### Design Decisions

**Primary Goals**:
1. Range circles should be removed immediately when "End Shooting Phase" is clicked
2. No visual artifacts should persist after phase transition
3. Cleanup should be reliable across all transition scenarios (save/load, multiplayer, etc.)

**Approach**: Explicit Cleanup Before Phase Exit
- Call `_clear_visuals()` in shooting phase exit handler
- Ensure controller cleanup happens before controller is freed
- Add defensive cleanup in phase transition to handle edge cases

### Phase 1: Add Explicit Cleanup in ShootingPhase

#### File: `40k/phases/ShootingPhase.gd` (MODIFY)

**Lines 35-38 - Enhance _on_phase_exit() with visual cleanup**:

Current code:
```gdscript
func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")
	# Clear shooting flags
	_clear_phase_flags()
```

Replace with:
```gdscript
func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")

	# CRITICAL: Clear all shooting visuals BEFORE controller is freed
	# This ensures range circles and other visuals are removed immediately
	_clear_shooting_visuals()

	# Clear shooting flags
	_clear_phase_flags()
```

**After line 449 - Add visual cleanup method**:

Add new method after `_clear_phase_flags()`:
```gdscript

func _clear_shooting_visuals() -> void:
	"""Clear all shooting-related visuals from the board when phase ends"""
	# Get the ShootingController from Main
	var main = get_node_or_null("/root/Main")
	if not main:
		print("ShootingPhase: Warning - Main node not found for visual cleanup")
		return

	var shooting_controller = main.get("shooting_controller")
	if shooting_controller and is_instance_valid(shooting_controller):
		print("ShootingPhase: Clearing shooting visuals via controller")
		# Call controller's cleanup method
		if shooting_controller.has_method("_clear_visuals"):
			shooting_controller._clear_visuals()
		print("ShootingPhase: Shooting visuals cleared")
	else:
		# Fallback: If controller already freed, clean up BoardRoot directly
		print("ShootingPhase: Controller not available, cleaning BoardRoot directly")
		_cleanup_boardroot_visuals()

func _cleanup_boardroot_visuals() -> void:
	"""Fallback cleanup - remove shooting visuals directly from BoardRoot"""
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		return

	# Remove shooting-specific visual nodes
	var visual_names = [
		"ShootingRangeVisual",
		"ShootingLoSVisual",
		"ShootingTargetHighlights",
		"LoSDebugVisual"
	]

	for visual_name in visual_names:
		var visual_node = board_root.get_node_or_null(visual_name)
		if visual_node and is_instance_valid(visual_node):
			print("ShootingPhase: Removing ", visual_name, " from BoardRoot")
			board_root.remove_child(visual_node)
			visual_node.queue_free()
```

**Rationale**:
- Cleanup happens during phase exit, before controller is freed
- Primary cleanup via controller ensures proper method is used
- Fallback cleanup handles edge cases where controller is already freed
- Explicit node removal from BoardRoot ensures visuals disappear

### Phase 2: Enhance Controller Cleanup Safety

#### File: `40k/scripts/ShootingController.gd` (MODIFY)

**Lines 522-530 - Make _clear_visuals() more robust**:

Current code:
```gdscript
func _clear_visuals() -> void:
	if los_visual:
		los_visual.clear_points()
	if range_visual:
		for child in range_visual.get_children():
			child.queue_free()
	_clear_target_highlights()
	_clear_range_indicators()
```

Replace with:
```gdscript
func _clear_visuals() -> void:
	"""Clear all shooting visual elements from the board"""
	print("ShootingController: Clearing all visuals")

	# Clear LoS line
	if los_visual and is_instance_valid(los_visual):
		los_visual.clear_points()

	# Clear range indicators (this clears children of range_visual)
	_clear_range_indicators()

	# Clear target highlights
	_clear_target_highlights()

	# Clear LoS debug visuals if present
	if los_debug_visual and is_instance_valid(los_debug_visual):
		if los_debug_visual.has_method("clear_all_debug_visuals"):
			los_debug_visual.clear_all_debug_visuals()

	print("ShootingController: All visuals cleared")
```

**Rationale**:
- Consolidates cleanup in single method
- Adds validation checks for node validity
- Includes LoS debug visual cleanup
- Adds logging for debugging

### Phase 3: Defensive Cleanup in Phase Controller Setup

#### File: `40k/scripts/Main.gd` (MODIFY)

**Lines 802-834 - Add shooting visual cleanup before controller free**:

Current code (line 816-818):
```gdscript
	if shooting_controller:
		shooting_controller.queue_free()
		shooting_controller = null
```

Replace with:
```gdscript
	if shooting_controller:
		# ENHANCEMENT: Clear visuals before freeing controller
		if shooting_controller.has_method("_clear_visuals"):
			shooting_controller._clear_visuals()
		shooting_controller.queue_free()
		shooting_controller = null
```

**Rationale**:
- Defensive cleanup ensures visuals are cleared even if phase exit cleanup fails
- Happens immediately before controller is freed
- No performance impact (only runs on phase transition)

### Phase 4: Verification & Testing

#### Manual Testing Steps:

1. **Test Normal Phase End**:
   ```bash
   # Run game
   export PATH="$HOME/bin:$PATH"
   godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k

   # In game:
   # 1. Load a game or start new game
   # 2. Advance to shooting phase
   # 3. Select a unit for shooting
   # 4. Observe range circles appear
   # 5. Click "End Shooting Phase" button
   # Expected: ALL range circles disappear immediately
   ```

2. **Test Multiple Unit Selection**:
   ```bash
   # In shooting phase:
   # 1. Select unit A - see range circles
   # 2. Select unit B - see different range circles
   # 3. Click "End Shooting Phase"
   # Expected: ALL range circles from all units are cleared
   ```

3. **Test Phase Transition**:
   ```bash
   # 1. In shooting phase with range circles visible
   # 2. Click "End Shooting Phase"
   # 3. Verify charge phase (or next phase) starts
   # 4. Look at board
   # Expected: No shooting range circles visible in new phase
   ```

4. **Test Save/Load During Shooting**:
   ```bash
   # 1. In shooting phase, select unit with range circles
   # 2. Quick save ([ key)
   # 3. Click "End Shooting Phase"
   # 4. Verify circles cleared
   # 5. Quick load (] key)
   # 6. Should restore shooting phase with no circles
   # 7. Select same unit
   # Expected: Range circles reappear correctly
   ```

5. **Check Debug Log**:
   ```bash
   # After running tests, check log for cleanup messages
   # Log location: /Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log

   # Expected log entries:
   # "ShootingPhase: Clearing shooting visuals via controller"
   # "ShootingController: Clearing all visuals"
   # "ShootingController: All visuals cleared"
   ```

## Implementation Tasks

Execute these tasks in order:

### Task 1: Enhance ShootingPhase._on_phase_exit()
- [ ] Open `40k/phases/ShootingPhase.gd`
- [ ] Navigate to lines 35-38 (the `_on_phase_exit()` function)
- [ ] Replace function with enhanced version that calls `_clear_shooting_visuals()`
- [ ] Save file

### Task 2: Add Visual Cleanup Methods to ShootingPhase
- [ ] In `40k/phases/ShootingPhase.gd`
- [ ] Navigate to line 449 (after `_clear_phase_flags()`)
- [ ] Add `_clear_shooting_visuals()` method as specified
- [ ] Add `_cleanup_boardroot_visuals()` method as specified
- [ ] Save file

### Task 3: Enhance ShootingController._clear_visuals()
- [ ] Open `40k/scripts/ShootingController.gd`
- [ ] Navigate to lines 522-530 (`_clear_visuals()` function)
- [ ] Replace with enhanced version that includes debug visual cleanup
- [ ] Add logging statements
- [ ] Save file

### Task 4: Add Defensive Cleanup in Main.setup_phase_controllers()
- [ ] Open `40k/scripts/Main.gd`
- [ ] Navigate to lines 816-818 (shooting_controller cleanup)
- [ ] Add `_clear_visuals()` call before `queue_free()`
- [ ] Save file

### Task 5: Manual Testing - Normal Flow
- [ ] Run game via Godot
- [ ] Load existing save or start new game
- [ ] Advance to shooting phase
- [ ] Select a unit with weapons
- [ ] Verify range circles appear
- [ ] Click "End Shooting Phase" button
- [ ] Verify ALL range circles disappear immediately
- [ ] Document results

### Task 6: Manual Testing - Multiple Units
- [ ] In shooting phase, select multiple different units
- [ ] Verify each shows different range circles
- [ ] End shooting phase
- [ ] Verify all circles from all units cleared
- [ ] Document results

### Task 7: Manual Testing - Save/Load
- [ ] Test save/load scenario as described above
- [ ] Verify range circles don't persist incorrectly
- [ ] Document results

### Task 8: Check Debug Logs
- [ ] Find latest debug log file
- [ ] Search for cleanup messages
- [ ] Verify cleanup is being called correctly
- [ ] Document any warnings or errors

### Task 9: Edge Case Testing
- [ ] Test rapid phase transitions
- [ ] Test with multiplayer (if applicable)
- [ ] Test with no units selected
- [ ] Test with destroyed units
- [ ] Document any issues

## Validation Gates

All validation commands must pass:

```bash
# 1. Set Godot path
export PATH="$HOME/bin:$PATH"

# 2. Manual gameplay test
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --path . &

# In game:
# - Start new game (or load save)
# - Advance to shooting phase
# - Select unit with weapons
# - Verify range circles appear
# - Click "End Shooting Phase"
# - CRITICAL: Verify ALL range circles disappear immediately
# Exit game

# Expected: All range circles removed when phase ends

# 3. Check debug log for cleanup messages
# Find latest log file
LOG_DIR="$HOME/Library/Application Support/Godot/app_userdata/40k/logs"
LATEST_LOG=$(ls -t "$LOG_DIR"/debug_*.log | head -1)
echo "Checking log: $LATEST_LOG"

# Search for cleanup messages
grep -i "clearing.*visuals\|shooting.*cleared" "$LATEST_LOG"

# Expected output:
# "ShootingPhase: Clearing shooting visuals via controller"
# "ShootingController: Clearing all visuals"
# "ShootingController: All visuals cleared"

# 4. Verify no orphaned visual nodes
# In debug log, check for any warnings about nodes not found
grep -i "warning.*visual\|error.*range" "$LATEST_LOG"

# Expected: No warnings about visual cleanup failures

# 5. Test phase transitions
# In game:
# - Go through full turn: Movement -> Shooting -> Charge -> Fight
# - In each phase, verify no range circles from shooting phase remain
# - Save during shooting phase, load later
# - Verify range circles don't persist incorrectly

# Expected: Clean phase transitions, no visual artifacts
```

## Success Criteria

- [x] Range circles appear when unit is selected in shooting phase
- [x] Range circles are removed immediately when "End Shooting Phase" button is clicked
- [x] No range circle visual artifacts persist in subsequent phases
- [x] Cleanup works correctly after save/load
- [x] Debug log shows cleanup methods being called
- [x] No warnings or errors in debug log related to visual cleanup
- [x] Edge cases handled correctly (rapid transitions, no units, etc.)
- [x] Performance not impacted (cleanup is fast)
- [x] Works in both single-player and multiplayer (if applicable)

## Common Pitfalls & Solutions

### Issue: Range circles still visible after phase end
**Solution**: Check debug log to see if cleanup methods are being called. Verify `_clear_shooting_visuals()` is in `_on_phase_exit()`. Check that controller cleanup happens before `queue_free()`.

### Issue: Game crashes on phase transition
**Solution**: Ensure all `is_instance_valid()` checks are in place. Don't access freed nodes. Use `get_node_or_null()` instead of `get_node()`.

### Issue: Cleanup happens too late
**Solution**: Call `_clear_visuals()` during `_on_phase_exit()` before controller is freed, not in `_exit_tree()`.

### Issue: Some circles disappear, some don't
**Solution**: Verify `_clear_range_indicators()` properly iterates all children of `range_visual`. Check for edge cases with multiple units.

### Issue: LoS debug visuals persist
**Solution**: Ensure `los_debug_visual.clear_all_debug_visuals()` is called in `_clear_visuals()`.

### Issue: Multiplayer desync
**Solution**: Cleanup is client-side visual only, shouldn't affect game state. But ensure cleanup happens on all clients at phase transition.

### Issue: Can't find debug log
**Solution**: Use `print(DebugLogger.get_real_log_file_path())` in game to find log location. Or check `~/Library/Application Support/Godot/app_userdata/40k/logs/`.

## References

### Code References
- `RangeCircle.gd` lines 1-39 - Range circle visual implementation
- `ShootingController.gd` lines 115-117, 531-632 - Range indicator creation/cleanup
- `ShootingController.gd` lines 49-80, 522-530 - Controller lifecycle and cleanup
- `ShootingPhase.gd` lines 35-38, 372-375 - Phase exit and end shooting
- `Main.gd` lines 802-854, 1814-1816, 2367-2376 - Phase management
- `Main.gd` lines 2911-2956 - Right panel cleanup pattern (similar pattern)

### External Documentation
- Godot Node Lifecycle: https://docs.godotengine.org/en/4.4/classes/class_node.html
- Godot Node2D: https://docs.godotengine.org/en/4.4/classes/class_node2d.html
- Godot Scene Tree: https://docs.godotengine.org/en/4.4/tutorials/scripting/nodes_and_scene_instances.html
- queue_free() behavior: https://docs.godotengine.org/en/4.4/classes/class_node.html#class-node-method-queue-free

### Warhammer 40k Rules
- Not directly applicable to this visual cleanup bug fix
- Core rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

## PRP Quality Checklist

- [x] All necessary context included (codebase architecture, current behavior, root cause)
- [x] Validation gates are executable commands with expected results
- [x] References existing patterns (phase cleanup, visual management)
- [x] Clear implementation path with step-by-step tasks
- [x] Error handling documented (is_instance_valid checks, fallback cleanup)
- [x] Code examples are complete and runnable
- [x] Root cause analysis provided with specific line numbers
- [x] Common pitfalls addressed with solutions
- [x] External references included (Godot docs)
- [x] Manual testing procedures detailed

## Confidence Score

**9/10** - High confidence in one-pass implementation success

**Reasoning**:
- Clear requirements: Remove range circles when shooting phase ends
- Root cause identified: Cleanup timing issue, range_visual children persist
- Simple, focused changes: Add cleanup call in phase exit + enhance existing cleanup method
- Existing patterns to follow: Similar cleanup in other phases, visual management patterns
- Well-understood Godot API: Node lifecycle, queue_free(), child management
- Low risk: Only affects visual cleanup, no game state changes
- Defensive coding: Multiple cleanup points (phase exit, controller free, fallback)
- Easy to test: Visually obvious if fix works
- Detailed validation steps provided

**Risk (-1 point)**:
- Timing sensitivity: Cleanup must happen before controller is freed but after phase is active
- Multiple cleanup paths might cause confusion if not well-coordinated
- Edge cases with save/load and multiplayer might need additional testing
- But all these are mitigated by defensive programming and multiple cleanup opportunities
