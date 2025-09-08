# Product Requirements Document: Right Panel Cleanup on Phase Entry

## Issue Reference
GitHub Issue #58: When a saved game is loaded the right hand panel is not clearing the old information

## Feature Description
Ensure complete cleanup of the right-hand panel UI when entering any phase (either through normal progression or loading a saved game), displaying only the UI elements relevant to the current phase.

## Problem Statement
Currently, when a user loads a saved game or transitions between phases, the right-hand panel may retain UI elements from the previous phase, causing:
1. **UI Overlapping**: Multiple phase-specific UI elements visible simultaneously
2. **State Confusion**: Old UI elements from wrong phase remain interactive
3. **Visual Clutter**: Accumulated UI elements from different phases create confusion
4. **Functional Conflicts**: Event handlers from old UI may interfere with current phase operations
5. **Save/Load Issues**: Loading a game doesn't properly reset the UI to match the loaded phase

## Requirements
1. **Complete UI Reset**: Right panel must be completely cleared when entering any phase
2. **Phase-Specific UI**: Only the current phase's UI elements should be visible
3. **Save/Load Compatibility**: UI cleanup must work when loading saved games
4. **Consistent Behavior**: Same cleanup behavior for normal transitions and save/load
5. **Performance**: Cleanup should be fast and avoid visual glitches
6. **Reliability**: Solution must handle all edge cases (missing nodes, rapid transitions)

## Implementation Context

### Current Architecture Analysis

#### Phase Controller System
Each phase has its own controller that manages phase-specific UI:
- **DeploymentController**: Manages unit deployment UI
- **MovementController**: Creates 4-section movement interface (lines 215-402 in MovementController.gd)
- **ShootingController**: Creates shooting panel with weapon/target UI (lines 155-252 in ShootingController.gd)
- **ChargeController**: Creates charge declaration and movement UI (lines 299-386 in ChargeController.gd)
- **FightController**: Creates fight sequence UI (lines 171-267 in FightController.gd)

#### Right Panel Structure
From Main.gd analysis:
```gdscript
# Right panel path: /root/Main/HUD_Right/VBoxContainer
# Controllers dynamically add their UI to this container
# Each controller has _setup_right_panel() method
# Each controller has _exit_tree() for cleanup
```

#### Phase Transition Flow (Main.gd lines 396-430)
```gdscript
func setup_phase_controllers() -> void:
    # Clean up existing controllers
    if deployment_controller:
        deployment_controller.queue_free()  # Should trigger _exit_tree()
    # ... similar for other controllers
    
    # Wait a frame for cleanup
    await get_tree().process_frame
    
    # Setup new controller based on current phase
    match current_phase:
        # Create appropriate controller
```

#### Save/Load Integration (Main.gd lines 1195-1241)
```gdscript
func _perform_quick_load() -> bool:
    # Load game state
    var success = SaveLoadManager.quick_load()
    if success:
        # Update current phase
        current_phase = GameState.get_current_phase()
        
        # Recreate phase controllers
        await setup_phase_controllers()
        
        # Refresh UI
        refresh_unit_list()
        update_ui()
        update_ui_for_phase()
```

### Root Cause Analysis

The issue stems from multiple factors:

1. **Incomplete Controller Cleanup**: Controllers' `_exit_tree()` methods don't always remove all UI elements from right panel
2. **Save/Load Timing**: When loading, old controllers may not be properly cleaned before new ones are created
3. **Container State Persistence**: VBoxContainer retains children between phase transitions
4. **Missing Cleanup Calls**: Some controllers don't implement comprehensive cleanup
5. **Race Conditions**: New controller setup may begin before old UI is fully removed

### Specific Controller Issues

#### MovementController (lines 89-108)
```gdscript
func _exit_tree() -> void:
    # Cleans up visual elements but NOT the 4 sections in right panel
    # Missing cleanup for: Section1_UnitList, Section2_UnitDetails, 
    #                      Section3_ModeSelection, Section4_Actions
```

#### ShootingController (lines 48-77)
```gdscript
func _exit_tree() -> void:
    # Cleans up ShootingPanel but may miss other elements
    # Restores visibility of UnitListPanel and UnitCard (may be wrong phase)
```

#### ChargeController & FightController
- Similar issues with incomplete cleanup of phase-specific UI elements

### Files Requiring Modification

#### Primary Changes
1. **Main.gd** (~1830 lines): Add comprehensive right panel cleanup method
2. **MovementController.gd** (~1680 lines): Enhance _exit_tree() cleanup
3. **ShootingController.gd** (~1400 lines): Enhance _exit_tree() cleanup  
4. **ChargeController.gd** (~1560 lines): Enhance _exit_tree() cleanup
5. **FightController.gd** (~1150 lines): Enhance _exit_tree() cleanup

#### Supporting Files (For Understanding)
- **PhaseManager.gd**: Phase transition orchestration
- **SaveLoadManager.gd**: Save/load flow
- **GameState.gd**: State management

### Documentation References
- **Warhammer Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Node Lifecycle**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/nodes_and_scenes.html
- **Godot UI Management**: https://docs.godotengine.org/en/4.4/classes/class_control.html
- **Godot Scene Tree**: https://docs.godotengine.org/en/4.4/classes/class_scenetree.html

## Implementation Blueprint

### Strategy Overview
Implement a comprehensive cleanup system with three layers of defense:
1. **Centralized Cleanup**: Main.gd method to clear right panel completely
2. **Enhanced Controller Cleanup**: Each controller properly removes its UI
3. **Proactive Setup Cleanup**: Controllers clear panel before adding their UI

### Phase 1: Centralized Right Panel Cleanup

#### Location: Main.gd - New method around line 1830
```gdscript
func _clear_right_panel_phase_ui() -> void:
    """Completely clear all phase-specific UI from right panel"""
    var container = get_node_or_null("HUD_Right/VBoxContainer")
    if not container:
        print("WARNING: Right panel VBoxContainer not found")
        return
    
    # List of known phase-specific UI elements to remove
    var phase_ui_patterns = [
        # Movement phase sections
        "Section1_UnitList", "Section2_UnitDetails", 
        "Section3_ModeSelection", "Section4_Actions",
        "MovementActions", "MovementPanel",
        
        # Shooting phase elements
        "ShootingPanel", "ShootingScrollContainer",
        "ShootingControls", "WeaponTree", "TargetBasket",
        
        # Charge phase elements
        "ChargePanel", "ChargeScrollContainer",
        "ChargeActions", "ChargeStatus",
        
        # Fight phase elements
        "FightPanel", "FightScrollContainer",
        "FightSequence", "FightActions",
        
        # Generic phase elements
        "PhasePanel", "PhaseControls", "PhaseActions"
    ]
    
    # Remove all matching elements
    for pattern in phase_ui_patterns:
        var node = container.get_node_or_null(pattern)
        if node and is_instance_valid(node):
            print("Main: Removing phase UI element: ", pattern)
            container.remove_child(node)
            node.queue_free()
    
    # Also remove any unknown dynamic children (defensive)
    var children_to_check = container.get_children()
    for child in children_to_check:
        # Keep only persistent UI elements
        if child.name in ["UnitListPanel", "UnitCard"]:
            # These might be shown/hidden based on phase
            continue
        # Remove if it looks like phase-specific UI
        if "Section" in child.name or "Panel" in child.name or "Actions" in child.name:
            print("Main: Removing unrecognized phase UI: ", child.name)
            container.remove_child(child)
            child.queue_free()
```

#### Integration Point 1: setup_phase_controllers() - Line ~396
```gdscript
func setup_phase_controllers() -> void:
    # ENHANCEMENT: Clear right panel before cleanup
    _clear_right_panel_phase_ui()
    
    # Clean up existing controllers
    if deployment_controller:
        deployment_controller.queue_free()
        deployment_controller = null
    # ... rest of existing cleanup code
    
    # Wait TWO frames for complete cleanup
    await get_tree().process_frame
    await get_tree().process_frame
    
    # ENHANCEMENT: Clear again after controller cleanup
    _clear_right_panel_phase_ui()
    
    # Setup controller based on current phase
    match current_phase:
        # ... existing controller setup
```

#### Integration Point 2: _perform_quick_load() - Line ~1205
```gdscript
func _perform_quick_load() -> void:
    # ... existing load code ...
    
    if success:
        _show_save_notification("Game loaded!", Color.BLUE)
        
        # ENHANCEMENT: Clear UI before phase setup
        _clear_right_panel_phase_ui()
        
        # Update current phase
        current_phase = GameState.get_current_phase()
        
        # ... rest of existing code
```

#### Integration Point 3: update_ui_for_phase() - Line ~1553
```gdscript
func update_ui_for_phase() -> void:
    # ENHANCEMENT: Clear right panel at start of phase UI update
    _clear_right_panel_phase_ui()
    
    # Update UI based on current phase
    match current_phase:
        # ... existing phase-specific UI setup
```

### Phase 2: Enhanced Controller Cleanup

#### MovementController.gd - Enhanced _exit_tree() around line 89
```gdscript
func _exit_tree() -> void:
    # Existing visual cleanup...
    
    # ENHANCEMENT: Comprehensive right panel cleanup
    var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
    if container and is_instance_valid(container):
        # Remove all movement-specific sections
        var sections_to_remove = [
            "Section1_UnitList", "Section2_UnitDetails",
            "Section3_ModeSelection", "Section4_Actions",
            "MovementActions", "MovementPanel"
        ]
        
        for section_name in sections_to_remove:
            var section = container.get_node_or_null(section_name)
            if section and is_instance_valid(section):
                print("MovementController: Removing section: ", section_name)
                container.remove_child(section)
                section.queue_free()
    
    # Existing bottom HUD cleanup...
```

#### ShootingController.gd - Enhanced _exit_tree() around line 48
```gdscript
func _exit_tree() -> void:
    # Existing visual cleanup...
    
    # ENHANCEMENT: Comprehensive right panel cleanup
    var shooting_panel = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/ShootingPanel")
    if shooting_panel and is_instance_valid(shooting_panel):
        shooting_panel.get_parent().remove_child(shooting_panel)
        shooting_panel.queue_free()
    
    var shooting_scroll = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/ShootingScrollContainer")
    if shooting_scroll and is_instance_valid(shooting_scroll):
        shooting_scroll.get_parent().remove_child(shooting_scroll)
        shooting_scroll.queue_free()
    
    # DON'T restore UnitListPanel/UnitCard visibility here - let Main.gd handle it
    
    # Existing cleanup...
```

#### ChargeController.gd - Enhanced _exit_tree() around line 65
```gdscript
func _exit_tree() -> void:
    # Existing visual cleanup...
    
    # ENHANCEMENT: Comprehensive right panel cleanup
    var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
    if container and is_instance_valid(container):
        var charge_elements = ["ChargePanel", "ChargeScrollContainer", "ChargeActions"]
        for element in charge_elements:
            var node = container.get_node_or_null(element)
            if node and is_instance_valid(node):
                print("ChargeController: Removing element: ", element)
                container.remove_child(node)
                node.queue_free()
    
    # Clear movement visuals...
    _clear_movement_visuals()
```

#### FightController.gd - Similar enhancement pattern

### Phase 3: Proactive Controller Setup

#### Each Controller's _setup_right_panel() method
Add at the beginning of each controller's _setup_right_panel():
```gdscript
func _setup_right_panel() -> void:
    # ENHANCEMENT: Defensive cleanup before setup
    var main = get_node_or_null("/root/Main")
    if main and main.has_method("_clear_right_panel_phase_ui"):
        main._clear_right_panel_phase_ui()
    
    # Continue with existing setup code...
```

### Error Handling Strategy
1. **Null Safety**: Always use get_node_or_null() and is_instance_valid()
2. **Graceful Degradation**: Continue operation even if cleanup partially fails
3. **Comprehensive Logging**: Log all cleanup operations for debugging
4. **Double Frame Waits**: Ensure complete cleanup before new UI creation
5. **Defensive Cleanup**: Multiple cleanup points to catch all scenarios

## Implementation Tasks (In Order)

### Task 1: Implement Centralized Cleanup in Main.gd
1. Add `_clear_right_panel_phase_ui()` method
2. Integrate into `setup_phase_controllers()`
3. Add to `_perform_quick_load()` after load success
4. Add to `update_ui_for_phase()` at start
5. Test basic functionality

### Task 2: Enhance MovementController Cleanup
1. Update `_exit_tree()` to remove all 4 sections
2. Add defensive cleanup in `_setup_right_panel()`
3. Test movement → other phase transitions
4. Test save/load during movement phase

### Task 3: Enhance ShootingController Cleanup  
1. Update `_exit_tree()` for comprehensive cleanup
2. Remove UnitListPanel/UnitCard visibility restoration
3. Add defensive cleanup in `_setup_right_panel()`
4. Test shooting phase transitions

### Task 4: Enhance ChargeController Cleanup
1. Update `_exit_tree()` for comprehensive cleanup
2. Add defensive cleanup in `_setup_right_panel()`
3. Test charge phase transitions
4. Verify movement visual cleanup

### Task 5: Enhance FightController Cleanup
1. Update `_exit_tree()` for comprehensive cleanup
2. Add defensive cleanup in `_setup_right_panel()`
3. Test fight phase transitions

### Task 6: Integration Testing
1. Test all phase transitions in sequence
2. Test save/load at each phase
3. Test rapid phase transitions
4. Test edge cases (missing nodes, errors)

### Task 7: Performance Validation
1. Profile UI cleanup performance
2. Check for memory leaks
3. Verify no visual artifacts
4. Test with complex game states

## Validation Gates

### Automated Validation
```bash
# Godot syntax validation
cd /Users/robertocallaghan/Documents/claude/godotv2
export PATH="$HOME/bin:$PATH"
godot --check-only

# Runtime validation (headless test)
godot --headless --quit-after 5
```

### Manual Testing Checklist
```bash
# Phase Transition Test Sequence
# 1. Start new game
# 2. Complete deployment, verify deployment UI only
# 3. Enter movement phase, verify 4 movement sections only
# 4. Enter shooting phase, verify shooting panel only
# 5. Enter charge phase, verify charge UI only
# 6. Enter fight phase, verify fight UI only

# Save/Load Test Sequence
# 1. Save during movement phase
# 2. Continue to shooting phase
# 3. Load the movement save
# 4. Verify ONLY movement UI is shown
# 5. Repeat for each phase

# Edge Case Tests
# 1. Rapid phase transitions (spam End Phase button)
# 2. Load corrupted/old save file
# 3. Phase transition with errors in console
```

### Acceptance Criteria Validation
```gdscript
# Add debug method to Main.gd for testing
func _debug_check_right_panel() -> void:
    var container = get_node_or_null("HUD_Right/VBoxContainer")
    if not container:
        print("DEBUG: No VBoxContainer found")
        return
    
    print("DEBUG: Right panel children:")
    for child in container.get_children():
        print("  - ", child.name, " (", child.get_class(), ")")
    
    # Check for wrong phase UI
    var current_phase_name = GameStateData.Phase.keys()[current_phase]
    print("DEBUG: Current phase: ", current_phase_name)
    
    # Flag any mismatched UI
    if current_phase != GameStateData.Phase.MOVEMENT:
        for section in ["Section1_UnitList", "Section2_UnitDetails", 
                       "Section3_ModeSelection", "Section4_Actions"]:
            if container.get_node_or_null(section):
                print("ERROR: Movement UI found in wrong phase!")
    
    if current_phase != GameStateData.Phase.SHOOTING:
        if container.get_node_or_null("ShootingPanel"):
            print("ERROR: Shooting UI found in wrong phase!")
```

## Quality Assurance

### Acceptance Criteria
- [ ] Each phase shows ONLY its specific UI elements
- [ ] No UI elements from previous phases remain visible
- [ ] Save/load properly restores phase-specific UI
- [ ] Phase transitions are visually clean (no flicker)
- [ ] All controllers properly clean up their UI
- [ ] No console errors during cleanup
- [ ] Performance remains smooth during transitions

### Edge Cases Coverage
- [ ] Loading save from different phase
- [ ] Rapid phase transitions
- [ ] Phase transition with active UI interactions
- [ ] Missing or corrupted UI nodes
- [ ] Controllers failing to initialize
- [ ] Memory pressure scenarios
- [ ] Multiple save/load cycles

### Regression Testing
- [ ] All phase functionalities work correctly
- [ ] Save/load system maintains compatibility
- [ ] UI responsiveness maintained
- [ ] No memory leaks introduced
- [ ] Event handlers properly cleaned up
- [ ] Visual elements render correctly

## Expected Outcome

**Primary Goal**: Clean, phase-specific UI at all times
- Each phase displays ONLY its relevant UI elements
- Loading a saved game shows correct phase UI immediately
- No UI overlap or confusion between phases

**User Experience Improvements**:
- Clear visual indication of current phase
- No confusing UI elements from other phases
- Smooth transitions between phases
- Consistent UI state after save/load

**Technical Improvements**:
- Reduced memory usage from cleaned UI nodes
- Better event handler isolation
- Cleaner codebase with explicit cleanup
- More maintainable phase controller system

## Risk Assessment

**Low Risk**:
- Well-understood node hierarchy
- Existing cleanup patterns to follow
- Multiple cleanup points provide redundancy
- Non-destructive changes (adding cleanup)

**Medium Risk**:
- Timing dependencies in UI creation/destruction
- Potential for visual artifacts during cleanup
- Save/load state restoration complexity

**Mitigation**:
- Triple-layer cleanup approach
- Extensive null checking
- Frame delays for proper sequencing
- Comprehensive logging for debugging
- Gradual rollout (test each controller separately)

## Confidence Score: 9/10

**High Confidence Factors**:
- Clear problem identification from code analysis
- Multiple similar issues already solved (Issue #54)
- Well-structured controller system
- Comprehensive cleanup strategy with redundancy
- Clear testing approach

**Risk Factors**:
- Complex interaction between save/load and phase systems
- Potential for undiscovered edge cases
- Performance impact of comprehensive cleanup

This implementation provides a robust solution to ensure the right panel always shows only the current phase's UI elements, whether entering through normal progression or loading a saved game.