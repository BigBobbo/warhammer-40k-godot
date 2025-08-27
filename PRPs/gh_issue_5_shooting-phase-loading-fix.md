# 🎯 Shooting Phase Loading Fix - Implementation PRP

## Problem Statement
GitHub Issue #5: "When I load a save that was made in the shooting phase I do not see the shooting options available to me. The bottom area that says what phase it is remains saying 'Loading...' without any changes."

### Root Cause Analysis
After thorough investigation of the save/load system and shooting phase architecture:

1. **Save/Load System Works Correctly**: SaveLoadManager and GameState properly save and restore the shooting phase state
2. **Phase Transition Works**: PhaseManager correctly transitions to the SHOOTING phase on load
3. **Controller Creation Works**: Main.gd successfully creates a new ShootingController and connects signals
4. **Missing State Restoration**: The ShootingController doesn't sync its UI state with the loaded ShootingPhase state
5. **UI Not Refreshed**: After load, shooting UI elements show initial empty state instead of current game state

**The core issue**: ShootingController is recreated during load but doesn't restore its visual state and UI elements to match the loaded shooting phase state.

## Implementation Blueprint

### Solution Approach
Implement proper state restoration for ShootingController after save loading:
1. **Detect when controller is created after load** (not just normal phase transition)
2. **Query the ShootingPhase instance** for current state (active shooter, assignments, targets)
3. **Restore UI elements** to show the current state
4. **Ensure proper signal connections** and visual updates

### Critical Context for Implementation

#### Existing Code Patterns to Follow

1. **Main.gd Load Pattern** (lines 675-699):
```gdscript
# After successful load
current_phase = GameState.get_current_phase()
setup_phase_controllers()  # This creates new ShootingController
refresh_unit_list()
update_ui()
update_ui_for_phase()
_recreate_unit_visuals()
```

2. **ShootingController set_phase() Pattern** (lines 231-249):
```gdscript
func set_phase(phase: BasePhase) -> void:
    current_phase = phase
    if phase and phase is ShootingPhase:
        # Connect signals
        _refresh_unit_list()
        show()
```

3. **ShootingPhase State Tracking** (lines 14-19):
```gdscript
var active_shooter_id: String = ""
var pending_assignments: Array = []
var confirmed_assignments: Array = []  
var units_that_shot: Array = []
```

4. **UI State Update Pattern** (ShootingController lines 671-684):
```gdscript
func _update_ui_state() -> void:
    if confirm_button:
        confirm_button.disabled = weapon_assignments.is_empty()
    # Update UI elements based on current state
```

#### Files to Modify

1. **40k/scripts/ShootingController.gd** - Add state restoration logic
2. **40k/scripts/Main.gd** - Ensure proper controller initialization after load
3. **40k/phases/ShootingPhase.gd** - Add state query methods if needed

#### External Documentation References

- **Godot 4.4 Save/Load Best Practices**: https://docs.godotengine.org/en/4.4/tutorials/io/saving_games.html
  - UI synchronization after state restoration
  - Signal reconnection patterns
  
- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
  - Shooting phase state: unit selection, target assignment, attack resolution
  - What information needs to persist: shooter, targets, weapon assignments

- **Godot 4.4 Autoload/Singleton Pattern**: https://docs.godotengine.org/en/4.4/tutorials/scripting/singletons_autoload.html
  - State management across scene transitions

## Tasks to Complete (In Order)

### Task 1: Add State Query Methods to ShootingPhase
**File**: 40k/phases/ShootingPhase.gd
**Function**: Add new methods after existing getters (line 488)

```gdscript
func get_units_that_shot() -> Array:
    return units_that_shot

func has_active_shooter() -> bool:
    return active_shooter_id != ""

func get_current_shooting_state() -> Dictionary:
    return {
        "active_shooter_id": active_shooter_id,
        "pending_assignments": pending_assignments,
        "confirmed_assignments": confirmed_assignments,
        "units_that_shot": units_that_shot,
        "eligible_targets": {} # Will be populated when targets are queried
    }
```

### Task 2: Add State Restoration to ShootingController
**File**: 40k/scripts/ShootingController.gd  
**Function**: Modify set_phase (line 231) and add restoration logic

```gdscript
func set_phase(phase: BasePhase) -> void:
    current_phase = phase
    
    if phase and phase is ShootingPhase:
        # Connect to phase signals (existing code)
        if not phase.unit_selected_for_shooting.is_connected(_on_unit_selected_for_shooting):
            phase.unit_selected_for_shooting.connect(_on_unit_selected_for_shooting)
        # ... other signal connections
        
        _refresh_unit_list()
        
        # NEW: Restore state if loading from save
        _restore_state_after_load()
        
        show()
    else:
        _clear_visuals()
        hide()

func _restore_state_after_load() -> void:
    """Restore ShootingController UI state after loading from save"""
    if not current_phase or not current_phase is ShootingPhase:
        return
    
    var shooting_state = current_phase.get_current_shooting_state()
    
    # Restore active shooter if there was one
    if shooting_state.active_shooter_id != "":
        active_shooter_id = shooting_state.active_shooter_id
        
        # Query targets for the active shooter
        eligible_targets = RulesEngine.get_eligible_targets(active_shooter_id, current_phase.game_state_snapshot)
        
        # Restore UI elements
        _refresh_weapon_tree()
        _show_range_indicators()
        
        # Update assignment display from phase state
        weapon_assignments.clear()
        for assignment in shooting_state.pending_assignments:
            weapon_assignments[assignment.weapon_id] = assignment.target_unit_id
        
        for assignment in shooting_state.confirmed_assignments:
            weapon_assignments[assignment.weapon_id] = assignment.target_unit_id
        
        _update_ui_state()
        
        # Show feedback in dice log
        if dice_log_display:
            dice_log_display.append_text("[color=blue]Restored shooting state for %s[/color]\n" % 
                current_phase.get_unit(active_shooter_id).get("meta", {}).get("name", active_shooter_id))
    
    # Update unit list to reflect units that have already shot
    _refresh_unit_list()
```

### Task 3: Update Unit List Refresh to Show Shot Status  
**File**: 40k/scripts/ShootingController.gd
**Function**: Modify _refresh_unit_list (line 251)

```gdscript
func _refresh_unit_list() -> void:
    if not unit_selector:
        return
    
    unit_selector.clear()
    
    if not current_phase:
        return
    
    var units = current_phase.get_units_for_player(current_phase.get_current_player())
    var units_shot = current_phase.get_units_that_shot() if current_phase.has_method("get_units_that_shot") else []
    
    for unit_id in units:
        var unit = units[unit_id]
        if current_phase._can_unit_shoot(unit) or unit_id in units_shot:
            var unit_name = unit.get("meta", {}).get("name", unit_id)
            
            # Show status for units that have shot
            if unit_id in units_shot:
                unit_name += " [SHOT]"
            elif unit_id == active_shooter_id:
                unit_name += " [ACTIVE]"
            
            unit_selector.add_item(unit_name)
            unit_selector.set_item_metadata(unit_selector.get_item_count() - 1, unit_id)
```

### Task 4: Fix Loading Notification Persistence
**File**: 40k/scripts/Main.gd
**Function**: Modify _perform_quick_load (line 655)

```gdscript
func _perform_quick_load() -> void:
    # ... existing code until line 697 ...
    
    if success:
        _show_save_notification("Game loaded!", Color.BLUE)
        
        # Update current phase
        current_phase = GameState.get_current_phase()
        print("Loaded phase: ", GameStateData.Phase.keys()[current_phase])
        
        # Sync BoardState with loaded GameState (for visual components)
        _sync_board_state_with_game_state()
        
        # Recreate phase controllers for the loaded phase
        setup_phase_controllers()
        
        # NEW: Give controllers time to initialize before UI refresh
        await get_tree().process_frame
        
        # Refresh all UI elements
        refresh_unit_list()
        update_ui()
        update_ui_for_phase()
        update_deployment_zone_visibility()
        
        # Recreate visual tokens for deployed units
        _recreate_unit_visuals()
        
        # Notify PhaseManager of the loaded state
        if PhaseManager.has_method("transition_to_phase"):
            PhaseManager.transition_to_phase(current_phase)
    else:
        _show_save_notification("Load failed - No save found!", Color.RED)
```

### Task 5: Ensure Proper Signal Flow After Load
**File**: 40k/scripts/Main.gd
**Function**: Modify setup_shooting_controller (line 144)

```gdscript
func setup_shooting_controller() -> void:
    print("Setting up ShootingController...")
    shooting_controller = preload("res://scripts/ShootingController.gd").new()
    shooting_controller.name = "ShootingController"
    add_child(shooting_controller)
    
    # Get the current phase instance from PhaseManager
    var phase_instance = PhaseManager.get_current_phase_instance()
    if phase_instance:
        print("Phase instance found: ", phase_instance.get_class())
        
        # Check if it's a ShootingPhase
        var is_shooting_phase = false
        if phase_instance.has_signal("unit_selected_for_shooting"):
            is_shooting_phase = true
        elif phase_instance.get("phase_type") == GameStateData.Phase.SHOOTING:
            is_shooting_phase = true
        
        if is_shooting_phase:
            shooting_controller.set_phase(phase_instance)
            
            # Connect phase signals to shooting controller (existing code)
            # ... signal connections ...
        else:
            print("WARNING: Phase instance is not a ShootingPhase, skipping signal connections")
    else:
        print("WARNING: No phase instance found!")
    
    # Connect shooting controller signals (existing code)
    # ... existing signal connections ...

    # NEW: Ensure UI is updated after controller setup
    emit_signal("ui_update_requested")
```

### Task 6: Add Load State Validation
**File**: 40k/phases/ShootingPhase.gd
**Function**: Add validation method at the end

```gdscript
func validate_loaded_state() -> bool:
    """Validate that the loaded shooting phase state is consistent"""
    # Check if active shooter is valid
    if active_shooter_id != "":
        var shooter = get_unit(active_shooter_id)
        if shooter.is_empty():
            print("WARNING: Invalid active shooter after load: ", active_shooter_id)
            active_shooter_id = ""
            return false
        
        if not _can_unit_shoot(shooter):
            print("WARNING: Active shooter cannot shoot after load: ", active_shooter_id) 
            active_shooter_id = ""
            return false
    
    # Validate assignments reference valid units and weapons
    for assignment in pending_assignments:
        var target = get_unit(assignment.target_unit_id)
        if target.is_empty():
            print("WARNING: Invalid target in assignments: ", assignment.target_unit_id)
            return false
    
    return true
```

## Validation Gates

```bash
# Test the fix by creating a save during shooting phase
godot --headless --run-main-scene

# In-game: Start shooting phase, select a unit to shoot, save game
# Then load the save and verify:
# 1. Shooting phase UI appears immediately
# 2. Previously selected unit shows as [ACTIVE]  
# 3. Weapon assignments and targets are preserved
# 4. Range indicators and highlights work
# 5. No "Loading..." text persists

# Run existing shooting phase tests to ensure no regressions
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://40k/tests/integration/test_shooting_phase_integration.gd

# Run save/load integration tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://40k/tests/integration/test_save_load.gd

# Check for syntax errors
godot --check-only
```

## Error Handling Strategy

1. **State Validation**: Use `validate_loaded_state()` to ensure loaded state is consistent
2. **Graceful Degradation**: If state is invalid, reset to clean shooting phase start
3. **Signal Safety**: Check signal connections before emitting/connecting
4. **UI Null Checks**: Validate UI elements exist before updating them
5. **Phase Type Validation**: Ensure phase instance is actually ShootingPhase before casting

## Common Pitfalls to Avoid

1. **Don't assume UI elements exist** - Always check if nodes are valid before accessing
2. **Handle timing issues** - Use `await get_tree().process_frame` for proper initialization order
3. **Preserve signal connections** - Ensure signals are properly connected after controller recreation
4. **Validate loaded data** - Check that saved shooter/target IDs still reference valid units
5. **Update all UI elements** - Don't forget weapon tree, target basket, and dice log state

## Implementation Verification Checklist

- [ ] Load a save made during shooting phase selection (no active shooter)
- [ ] Load a save made with an active shooter selected  
- [ ] Load a save made with weapon assignments pending
- [ ] Load a save made during dice rolling/resolution
- [ ] Load a save where some units have already shot
- [ ] Verify UI shows correct state immediately after load
- [ ] Verify range indicators and target highlights work
- [ ] Verify weapon assignments are preserved
- [ ] Verify "Loading..." text disappears quickly
- [ ] Verify normal shooting phase flow works after load

## Confidence Score: 9/10

High confidence due to:
- **Clear root cause identification** - UI state restoration, not save/load system
- **Minimal, targeted changes** - Only affects ShootingController state restoration  
- **Existing patterns to follow** - Similar patterns exist in MovementController
- **Comprehensive understanding** - Full analysis of save/load and phase systems
- **Well-defined validation** - Clear test cases for verification
- **Robust error handling** - Graceful degradation for edge cases

Points deducted for:
- **Timing sensitivity** - May need frame delays for proper initialization order

## Additional Notes

This fix implements the **"restore UI to match loaded state"** pattern recommended in Godot save/load best practices. The approach ensures that when a shooting phase save is loaded, the ShootingController queries the loaded ShootingPhase state and updates its UI elements accordingly.

The implementation follows Godot's autoload singleton pattern where game state is managed centrally (in GameState/ShootingPhase) while UI controllers sync their visual state to match the authoritative game state.

This solution maintains separation of concerns: ShootingPhase manages game logic state, ShootingController manages UI state, and the controller queries the phase to restore its visual state after loads.