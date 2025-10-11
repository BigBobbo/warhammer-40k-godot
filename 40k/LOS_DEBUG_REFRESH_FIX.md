# LoS Debug Visualization Refresh Fix

## Issue Summary

The LoS (Line of Sight) debugger was not showing visualizations when toggled ON mid-game. The visualization code only ran when a unit was selected for shooting, so if:

1. User entered shooting phase (debug OFF by default)
2. User selected a unit (visuals didn't draw because debug was OFF)
3. User pressed 'L' to enable debug
4. The `debug_enabled` flag changed to `true` but nothing redrawed

The visualization code had already run and skipped drawing because the flag was `false` at that time.

## Root Cause

In `ShootingController.gd`, the LoS visualization only happens in two scenarios:
- `_on_unit_selected_for_shooting()` (line 763-766)
- `_highlight_enemies_by_range()` (line 635-636)

Both check `if los_debug_visual and los_debug_visual.debug_enabled:` before visualizing. Once this code runs, there's no mechanism to re-trigger it when debug is toggled ON.

## Solution

Added a refresh mechanism that re-visualizes LoS when debug is toggled ON:

### 1. New Method in ShootingController.gd (lines 681-697)

```gdscript
# Public API for refreshing LoS debug visuals
# Called when LoS debug is toggled ON while a shooter is already active
func refresh_los_debug_visuals() -> void:
	if not los_debug_visual or not los_debug_visual.debug_enabled:
		return

	if active_shooter_id == "" or eligible_targets.is_empty():
		return

	print("[ShootingController] Refreshing LoS debug visuals for active shooter: %s" % active_shooter_id)

	# Clear existing visuals first
	los_debug_visual.clear_all_debug_visuals()

	# Re-visualize LoS to all eligible targets
	for target_id in eligible_targets:
		_visualize_los_to_target(active_shooter_id, target_id)
```

### 2. Updated Main.gd Toggle Function (lines 737-754)

```gdscript
func _toggle_los_debug() -> void:
	# Find LoS debug visual
	var los_debug = get_node_or_null("BoardRoot/LoSDebugVisual")
	if los_debug:
		var was_enabled = los_debug.debug_enabled
		los_debug.toggle_debug()
		var is_now_enabled = los_debug.debug_enabled
		print("LoS debug visualization: ", is_now_enabled)
		_show_toast("LoS Debug: " + ("ON" if is_now_enabled else "OFF"))

		# If we just turned debug ON, refresh visuals if shooting phase is active
		if not was_enabled and is_now_enabled:
			var shooting_controller = get_node_or_null("ShootingController")
			if shooting_controller and shooting_controller.has_method("refresh_los_debug_visuals"):
				shooting_controller.refresh_los_debug_visuals()
				print("LoS debug: Refreshed visuals for active shooter")
	else:
		print("LoS debug visual not found")
```

## How It Works

1. User presses 'L' to toggle LoS debug
2. Main.gd's `_toggle_los_debug()` detects the state change from OFF → ON
3. It finds the ShootingController instance
4. Calls `refresh_los_debug_visuals()` on the controller
5. The controller clears existing visuals and re-visualizes LoS to all eligible targets
6. Visuals immediately appear on screen

## Testing Instructions

### Manual Testing

1. Start the game and begin a new match
2. Enter the shooting phase
3. Select a unit for shooting (visuals should NOT appear yet - debug is OFF)
4. Press 'L' to enable LoS debug
5. **Expected**: Toast shows "LoS Debug: ON" and LoS lines/base outlines immediately appear
6. Press 'L' again to disable
7. **Expected**: Toast shows "LoS Debug: OFF" and all visuals disappear
8. Press 'L' to enable again
9. **Expected**: Visuals reappear immediately

### Test Scenarios

**Scenario 1: Enable Before Selecting Unit**
- Enter shooting phase
- Press 'L' to enable debug (debug ON, no unit selected yet)
- Select a unit
- **Expected**: Visuals appear immediately when unit is selected

**Scenario 2: Enable After Selecting Unit** (Main fix)
- Enter shooting phase
- Select a unit (debug OFF, no visuals)
- Press 'L' to enable debug
- **Expected**: Visuals appear immediately

**Scenario 3: Toggle Multiple Times**
- Select a unit
- Press 'L' repeatedly
- **Expected**: Visuals toggle ON/OFF correctly each time

**Scenario 4: Change Units While Debug is ON**
- Enable debug
- Select unit A (visuals appear)
- Select unit B
- **Expected**: Visuals clear and re-draw for unit B

**Scenario 5: No Unit Selected**
- Enter shooting phase
- Press 'L' to enable debug (no unit selected)
- **Expected**: Toast shows ON, but no visuals (nothing to visualize yet)
- Select a unit
- **Expected**: Visuals appear for the selected unit

## Files Modified

1. `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ShootingController.gd`
   - Added `refresh_los_debug_visuals()` method (lines 681-697)

2. `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/Main.gd`
   - Modified `_toggle_los_debug()` function (lines 737-754)
   - Now detects state transition and triggers refresh

## Related Issues

- GitHub Issue #103 (LoS Debug Default State) - Previously fixed
- This fix addresses the visualization refresh when toggled mid-game

## Debug Logging

When the fix is working correctly, you should see these log messages:

```
LoS debug toggle key (L) pressed!
LoS debug visualization: true
ShootingController: Refreshing LoS debug visuals for active shooter: unit_xxx
ShootingController: Enhanced LoS visualization: unit_xxx → unit_yyy
[LoSDebugVisual] Enhanced LoS: CLEAR via center
```

## Validation

The fix has been tested for syntax errors. Manual validation in-game is recommended to confirm:
- Visuals appear when toggled ON with an active shooter
- Visuals clear when toggled OFF
- State transitions work correctly
- No errors in the console

## Implementation Date

2025-10-11

## Related Documentation

- LoSDebugVisual.gd documentation
- ShootingController.gd documentation
- PRPs/gh_issue_103_los-debug-fix.md (previous related fix)
