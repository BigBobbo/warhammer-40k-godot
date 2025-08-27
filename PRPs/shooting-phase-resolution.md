# 🎯 Shooting Phase Resolution - Implementation PRP

## Problem Statement
GitHub Issue #2: "Once the user has selected a unit to shoot and a target and they click confirm the next steps outlined in the shooting_phase_prd.md should occur. Currently it does not appear that anything happens."

### Root Cause Analysis
After thorough investigation of the codebase:
- **ShootingPhase.gd** has complete shooting logic but requires separate CONFIRM_TARGETS and RESOLVE_SHOOTING actions
- **ShootingController.gd** sends CONFIRM_TARGETS but doesn't trigger RESOLVE_SHOOTING
- The UI flow stops after confirmation, leaving the user without a clear path to complete shooting

## Implementation Blueprint

### Solution Approach
Implement automatic shooting resolution after target confirmation, following the Warhammer 40k 10e rules sequence:
1. Select targets → 2. Confirm targets → 3. **Automatically resolve shooting** → 4. Apply damage → 5. Update UI

### Critical Context for Implementation

#### Existing Code Patterns to Follow

1. **Action Processing Pattern** (from 40k/phases/ShootingPhase.gd:255-268):
```gdscript
func _process_confirm_targets(action: Dictionary) -> Dictionary:
    confirmed_assignments = pending_assignments.duplicate(true)
    pending_assignments.clear()
    
    emit_signal("shooting_begun", active_shooter_id)
    log_phase_message("Confirmed targets, ready to resolve shooting")
    
    # Initialize resolution state
    resolution_state = {
        "current_assignment": 0,
        "phase": "ready"
    }
    
    return create_result(true, [])
```

2. **Signal Connection Pattern** (from 40k/scripts/Main.gd):
```gdscript
if not shooting_controller.shoot_action_requested.is_connected(_on_shooting_action_requested):
    shooting_controller.shoot_action_requested.connect(_on_shooting_action_requested)
```

3. **RulesEngine Integration** (from 40k/phases/ShootingPhase.gd:270-316):
```gdscript
var shoot_action = {
    "type": "SHOOT",
    "actor_unit_id": active_shooter_id,
    "payload": {
        "assignments": confirmed_assignments
    }
}
var rng_service = RulesEngine.RNGService.new()
var result = RulesEngine.resolve_shoot(shoot_action, game_state_snapshot, rng_service)
```

#### Files to Modify

1. **40k/phases/ShootingPhase.gd** - Modify _process_confirm_targets to auto-trigger resolution
2. **40k/scripts/ShootingController.gd** - Add visual feedback during resolution
3. **40k/tests/integration/test_shooting_phase_integration.gd** - Update tests for new flow

#### External Documentation References

- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
  - Shooting sequence: Select targets → Make ranged attacks → Resolve damage
  - Attack sequence: Hit roll → Wound roll → Allocate → Save → Damage

- **Godot 4.4 Signals**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
  - Signal emission pattern: `signal_name.emit(args)`
  - Connection pattern: `signal.connect(callable)`

## Tasks to Complete (In Order)

### Task 1: Modify ShootingPhase to Auto-Resolve After Confirmation
**File**: 40k/phases/ShootingPhase.gd
**Function**: _process_confirm_targets (line 255)

Add automatic resolution trigger:
```gdscript
func _process_confirm_targets(action: Dictionary) -> Dictionary:
    confirmed_assignments = pending_assignments.duplicate(true)
    pending_assignments.clear()
    
    emit_signal("shooting_begun", active_shooter_id)
    log_phase_message("Confirmed targets, ready to resolve shooting")
    
    resolution_state = {
        "current_assignment": 0,
        "phase": "ready"
    }
    
    # AUTO-RESOLVE: Immediately trigger shooting resolution
    var initial_result = create_result(true, [])
    
    # Call resolution directly
    var resolve_result = _process_resolve_shooting({})
    
    # Combine results
    if resolve_result.success:
        initial_result.changes.append_array(resolve_result.get("changes", []))
        initial_result["dice"] = resolve_result.get("dice", [])
        initial_result["log_text"] = resolve_result.get("log_text", "")
    
    return initial_result
```

### Task 2: Add Visual Feedback in ShootingController
**File**: 40k/scripts/ShootingController.gd
**Function**: _on_confirm_pressed (line 613)

Update to show resolution happening:
```gdscript
func _on_confirm_pressed() -> void:
    # Show visual feedback that shooting is resolving
    if dice_log_display:
        dice_log_display.append_text("[color=yellow]Rolling dice...[/color]\n")
    
    emit_signal("shoot_action_requested", {
        "type": "CONFIRM_TARGETS"
    })
    
    # The phase will now auto-resolve after confirmation
```

### Task 3: Ensure Proper Signal Flow
**File**: 40k/phases/ShootingPhase.gd
**Function**: _process_resolve_shooting (line 270)

Ensure signals are emitted during resolution:
```gdscript
# Add at the beginning of _process_resolve_shooting
emit_signal("dice_rolled", {"context": "resolution_start", "message": "Beginning attack resolution..."})

# Keep existing dice signal emissions during resolution
```

### Task 4: Update Unit Visuals After Casualties
**File**: 40k/scripts/Main.gd
**Function**: update_after_shooting_action (line 523)

Ensure dead models are removed from display:
```gdscript
func update_after_shooting_action() -> void:
    # Refresh visuals and UI after a shooting action
    _recreate_unit_visuals()  # This should handle dead model removal
    refresh_unit_list()
    update_ui()
    
    # Update shooting controller state
    if shooting_controller:
        shooting_controller._refresh_unit_list()
```

### Task 5: Fix RulesEngine Damage Application
**File**: 40k/autoloads/RulesEngine.gd

Ensure _resolve_assignment properly removes dead models and creates diffs:
```gdscript
# In _resolve_assignment, after damage is applied:
if target_model.current_wounds <= 0:
    # Model is dead
    result.diffs.append({
        "op": "set",
        "path": "units.%s.models.%d.alive" % [target_unit_id, target_model_index],
        "value": false
    })
    casualties += 1
```

### Task 6: Update Tests for New Flow
**File**: 40k/tests/integration/test_shooting_phase_integration.gd
**Function**: test_complete_shooting_workflow (line 135)

Update test to expect automatic resolution:
```gdscript
# Step 5. Confirm targets (now includes auto-resolution)
result = shooting_phase.execute_action({"type": "CONFIRM_TARGETS"})
assert_true(result.success, "Should confirm and resolve targets")
assert_true(result.has("dice"), "Should have dice results from auto-resolution")
assert_true(result.dice.size() > 0, "Should have rolled dice")

# Step 6 is no longer needed - resolution happens automatically
# Remove the separate RESOLVE_SHOOTING action test
```

## Validation Gates

```bash
# Run Godot tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://40k/tests/integration/test_shooting_phase_integration.gd

# Check specific test
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://40k/tests/integration/test_shooting_phase_integration.gd -gunit_test=test_complete_shooting_workflow

# Verify no syntax errors
godot --check-only
```

## Error Handling Strategy

1. **Null Safety**: Check all dictionary accesses with .get() and provide defaults
2. **Signal Safety**: Use `if not signal.is_connected()` before connecting
3. **State Validation**: Verify confirmed_assignments is not empty before resolution
4. **Dice Roll Validation**: Ensure RNG service is initialized before rolling

## Common Pitfalls to Avoid

1. **Don't forget to emit signals** - UI depends on dice_rolled and shooting_resolved signals
2. **Preserve existing test compatibility** - Some tests may expect separate actions
3. **Handle edge cases** - What if no hits/wounds/damage occurs?
4. **Clean up state** - Reset active_shooter_id and assignments after resolution

## Implementation Verification Checklist

- [ ] User can select a shooting unit
- [ ] User can assign targets to weapons
- [ ] Clicking "Confirm Targets" triggers dice rolls
- [ ] Dice results appear in the log
- [ ] Damage is applied to target models
- [ ] Dead models are removed from the board
- [ ] Unit can't shoot again in the same phase
- [ ] Tests pass without modification

## Confidence Score: 8/10

High confidence due to:
- Complete understanding of existing codebase structure
- Clear identification of the issue (missing auto-resolution)
- Minimal changes required (primarily in _process_confirm_targets)
- Existing test coverage to validate changes
- Well-documented Godot signal patterns

Points deducted for:
- Potential edge cases in damage allocation
- Possible UI state synchronization issues

## Additional Notes

The implementation follows the "call down, signal up" pattern recommended in Godot documentation. The ShootingPhase manages the game state while ShootingController handles UI, with signals connecting them loosely.

This fix makes the shooting phase flow more intuitive by automatically proceeding through the resolution steps once targets are confirmed, matching the expected user experience described in the shooting_phase_prd.md.