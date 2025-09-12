# Product Requirements Document: Update Top Bar for Phase-Specific UI

## Issue Reference
GitHub Issue #61: When a user enters a phase the top panel (called the HUD_Bottom) should only show info/buttons related to that specific phase.

## Feature Description
Implement a clean, phase-specific top bar system where each Warhammer 40k game phase displays only the UI elements relevant to that specific phase, eliminating UI clutter and providing clear phase-specific controls.

## Problem Statement
Currently, the top bar (HUD_Bottom) system has several critical issues:

1. **Single Button Reuse**: Only one `EndDeploymentButton` gets repurposed with different text for all phases
2. **Inconsistent UI Elements**: Some phases show complex UI while others show minimal controls
3. **Phase Controller Duplication**: Each controller creates its own UI setup in different ways
4. **Save/Load Issues**: Loading a game may not properly restore the correct phase-specific UI
5. **UI State Confusion**: Players can't clearly see what actions are available in the current phase
6. **Maintenance Complexity**: No consistent pattern for phase UI management

## Requirements

### Functional Requirements
1. **Phase-Specific UI**: Each phase shows only relevant buttons and information
2. **Consistent Layout**: All phases follow the same UI layout pattern
3. **Save/Load Compatibility**: UI correctly restores when loading games
4. **Clear Phase Identity**: Users can immediately identify the current phase
5. **Action Clarity**: Available actions are clearly visible and accessible

### Non-Functional Requirements
1. **Performance**: UI transitions should be smooth and fast
2. **Reliability**: System must handle all edge cases gracefully
3. **Maintainability**: Clear separation of concerns between phases
4. **Consistency**: Uniform visual design across all phases
5. **Accessibility**: Clear button labels and logical layout

## Implementation Context

### Current Architecture Analysis

#### HUD_Bottom Structure (Main.tscn lines 33-61)
```
HUD_Bottom/HBoxContainer:
  - PhaseLabel: Shows current phase name
  - ActivePlayerBadge: Shows player information
  - StatusLabel: Shows current status message
  - EndDeploymentButton: Single button repurposed for all phases
```

#### Phase Management Flow (Main.gd lines 1642-1716)
```gdscript
func update_ui_for_phase() -> void:
    match current_phase:
        GameStateData.Phase.DEPLOYMENT:
            phase_label.text = "Deployment Phase"
            end_deployment_button.text = "End Deployment"
            end_deployment_button.visible = true
        GameStateData.Phase.MOVEMENT:
            phase_label.text = "Movement Phase"  
            end_deployment_button.text = "End Movement"
            end_deployment_button.visible = true
        # ... similar for other phases
```

#### Current Phase Controller UI Management

**MovementController** (lines 175-214):
- Removes `MovementInfo` and `MovementButtons` containers
- Relies on universal "End Phase" button approach
- Minimal top bar footprint

**ShootingController** (lines 112-149):
- Creates `ShootingControls` container
- Adds phase label, separator, "End Shooting Phase" button
- More comprehensive approach

**ChargeController** (lines 220-308): 
- Creates complex `ChargeControls` container
- Multiple buttons: Declare Charge, Roll 2D6, Skip Charge, Next Unit, End Phase
- Distance tracking labels
- Most comprehensive top bar UI

**FightController** (lines 116-176):
- Creates `FightControls` container  
- Specialized buttons: Pile In, Consolidate, End Fight Phase
- Fight sequence status display

### Root Cause Analysis

The inconsistency stems from:

1. **No Standard Pattern**: Each controller implements top bar UI differently
2. **Shared Button Limitation**: Single `EndDeploymentButton` limits functionality
3. **Mixed Responsibilities**: Both Main.gd and controllers manage the same UI space
4. **Cleanup Inconsistency**: No standard cleanup approach
5. **State Management**: Complex logic to show/hide different elements

### Warhammer 40k Phase Requirements Analysis

Based on [Wahapedia Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/):

#### Deployment Phase
- **Actions**: Deploy units, position army
- **UI Needs**: End Deployment button, deployment status
- **Complexity**: Low (single action)

#### Command Phase  
- **Actions**: Gain CP, battle-shock tests, stratagems
- **UI Needs**: Command points display, End Command button
- **Complexity**: Medium (resource management)

#### Movement Phase
- **Actions**: Move units, advance, fall back, remain stationary
- **UI Needs**: End Movement button, movement status
- **Complexity**: Low (managed in right panel)

#### Shooting Phase
- **Actions**: Select targets, resolve shooting
- **UI Needs**: End Shooting button, phase status
- **Complexity**: Low (managed in right panel)

#### Charge Phase
- **Actions**: Declare charges, roll dice, move models
- **UI Needs**: Declare Charge, Roll 2D6, Skip Charge, distance tracking, End Charge
- **Complexity**: High (multiple sequential actions)

#### Fight Phase
- **Actions**: Pile in, fight, consolidate
- **UI Needs**: Pile In, Consolidate, fight sequence status, End Fight
- **Complexity**: High (sequential combat actions)

#### Morale Phase
- **Actions**: Morale tests, remove casualties
- **UI Needs**: End Morale button, test status
- **Complexity**: Low (simple tests)

### Files Requiring Modification

#### Primary Changes
1. **Main.gd** (~2090 lines): Implement phase-specific UI container system
2. **Main.tscn**: Update HUD_Bottom structure for dynamic containers
3. **MovementController.gd** (~1500 lines): Implement standardized top bar setup
4. **ShootingController.gd** (~944 lines): Refactor to use new system
5. **ChargeController.gd** (~1512 lines): Refactor to use new system  
6. **FightController.gd** (~200+ lines): Refactor to use new system

#### Supporting Files
- **CommandController.gd**: Add top bar implementation
- **ScoringController.gd**: Add top bar implementation
- **DeploymentController.gd**: Add top bar implementation

### Documentation References
- **Warhammer Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot UI Documentation**: https://docs.godotengine.org/en/4.4/classes/class_control.html
- **Godot Container Management**: https://docs.godotengine.org/en/4.4/classes/class_container.html

## Implementation Blueprint

### Strategy Overview
Implement a standardized phase-specific UI system with three components:
1. **Dynamic Container System**: Main.gd manages phase-specific containers
2. **Standardized Phase Interface**: Common interface for all phase controllers
3. **Consistent Cleanup**: Reliable cleanup and state management

### Phase 1: Core Infrastructure in Main.gd

#### New UI Container System (Main.gd ~line 2090)
```gdscript
# Phase-specific UI container management
var phase_ui_containers: Dictionary = {}
var current_phase_container: Container = null

func _setup_phase_ui_containers() -> void:
    """Initialize containers for each phase"""
    var hud_bottom = get_node("HUD_Bottom/HBoxContainer")
    
    # Create containers for each phase (hidden initially)
    for phase in GameStateData.Phase.values():
        var container = HBoxContainer.new()
        container.name = "PhaseContainer_%s" % GameStateData.Phase.keys()[phase]
        container.visible = false
        hud_bottom.add_child(container)
        phase_ui_containers[phase] = container
        
        # Add standard elements to each container
        _add_standard_phase_elements(container, phase)

func _add_standard_phase_elements(container: HBoxContainer, phase: GameStateData.Phase) -> void:
    """Add standard UI elements that all phases need"""
    # Separator before phase content
    container.add_child(VSeparator.new())
    
    # Phase-specific content area (empty initially)
    var content_area = HBoxContainer.new()
    content_area.name = "PhaseContent"
    container.add_child(content_area)
    
    # Separator after phase content  
    container.add_child(VSeparator.new())
    
    # Standard end phase button
    var end_button = Button.new()
    end_button.name = "EndPhaseButton"
    end_button.text = _get_end_button_text(phase)
    end_button.pressed.connect(_on_end_phase_pressed.bind(phase))
    container.add_child(end_button)

func _get_end_button_text(phase: GameStateData.Phase) -> String:
    """Get appropriate end button text for each phase"""
    match phase:
        GameStateData.Phase.DEPLOYMENT: return "End Deployment"
        GameStateData.Phase.COMMAND: return "End Command"
        GameStateData.Phase.MOVEMENT: return "End Movement"
        GameStateData.Phase.SHOOTING: return "End Shooting"
        GameStateData.Phase.CHARGE: return "End Charge"
        GameStateData.Phase.FIGHT: return "End Fight"
        GameStateData.Phase.MORALE: return "End Morale"
        GameStateData.Phase.SCORING: return "End Turn"
        _: return "End Phase"

func _switch_to_phase_container(phase: GameStateData.Phase) -> void:
    """Switch visible container to match current phase"""
    # Hide current container
    if current_phase_container:
        current_phase_container.visible = false
    
    # Show phase-specific container
    if phase_ui_containers.has(phase):
        current_phase_container = phase_ui_containers[phase]
        current_phase_container.visible = true
        print("Main: Switched to phase container for ", GameStateData.Phase.keys()[phase])
    else:
        print("ERROR: No container found for phase ", phase)

func _get_phase_content_area(phase: GameStateData.Phase) -> HBoxContainer:
    """Get the content area where controllers can add their UI"""
    if not phase_ui_containers.has(phase):
        return null
    return phase_ui_containers[phase].get_node("PhaseContent")

func _clear_phase_content(phase: GameStateData.Phase) -> void:
    """Clear all controller-added content from a phase container"""
    var content_area = _get_phase_content_area(phase)
    if not content_area:
        return
        
    for child in content_area.get_children():
        content_area.remove_child(child)
        child.queue_free()
    
    print("Main: Cleared content for phase ", GameStateData.Phase.keys()[phase])
```

#### Integration with Existing Systems

**Update _ready() method** (Main.gd ~line 39):
```gdscript
func _ready() -> void:
    # ... existing setup code ...
    
    # Setup phase UI containers before controllers
    _setup_phase_ui_containers()
    
    # Setup phase-specific controllers based on current phase
    current_phase = GameState.get_current_phase()
    await setup_phase_controllers()
    
    # Switch to correct phase container
    _switch_to_phase_container(current_phase)
    
    # ... rest of existing code ...
```

**Update setup_phase_controllers()** (Main.gd ~line 398):
```gdscript
func setup_phase_controllers() -> void:
    # Clear all phase content before setting up new controllers
    for phase in GameStateData.Phase.values():
        _clear_phase_content(phase)
    
    # Clean up existing controllers (existing code)
    # ...
    
    # Setup controller based on current phase (existing code)
    # ...
    
    # Ensure correct container is visible after setup
    _switch_to_phase_container(current_phase)
```

**Update _on_phase_changed()** (Main.gd ~line 1616):
```gdscript
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
    current_phase = new_phase
    print("Phase changed to: ", GameStateData.Phase.keys()[new_phase])
    
    # Switch to new phase container FIRST
    _switch_to_phase_container(new_phase)
    
    # Then setup controllers
    await setup_phase_controllers()
    update_ui_for_phase()
    
    # ... rest of existing code ...
```

**Update load functions** for save/load compatibility:
```gdscript
func _perform_quick_load() -> void:
    # ... existing load code ...
    
    if success:
        # Update current phase
        current_phase = GameState.get_current_phase()
        
        # Switch to correct phase container before controller setup
        _switch_to_phase_container(current_phase)
        
        # Recreate phase controllers
        await setup_phase_controllers()
        
        # ... rest of existing code ...
```

### Phase 2: Standardized Controller Interface

#### Base Controller Interface
```gdscript
# Add to each controller class
func setup_phase_ui() -> void:
    """Setup phase-specific UI elements in the top bar"""
    var main = get_node("/root/Main")
    if not main:
        print("ERROR: Cannot find Main node for UI setup")
        return
    
    var content_area = main._get_phase_content_area(get_controller_phase())
    if not content_area:
        print("ERROR: Cannot find content area for phase")
        return
    
    _add_phase_ui_elements(content_area)

func get_controller_phase() -> GameStateData.Phase:
    """Return the phase this controller manages"""
    # Override in each controller
    return GameStateData.Phase.DEPLOYMENT

func _add_phase_ui_elements(content_area: HBoxContainer) -> void:
    """Add phase-specific UI elements to the content area"""
    # Override in each controller
    pass
```

### Phase 3: Controller-Specific Implementations

#### MovementController Updates
```gdscript
func get_controller_phase() -> GameStateData.Phase:
    return GameStateData.Phase.MOVEMENT

func _add_phase_ui_elements(content_area: HBoxContainer) -> void:
    # Movement phase needs minimal top bar UI
    # Most UI is in the right panel
    var status_label = Label.new()
    status_label.text = "Move units or End Movement"
    content_area.add_child(status_label)
```

#### ShootingController Updates  
```gdscript
func get_controller_phase() -> GameStateData.Phase:
    return GameStateData.Phase.SHOOTING

func _add_phase_ui_elements(content_area: HBoxContainer) -> void:
    # Shooting phase needs minimal top bar UI
    # Most UI is in the right panel
    var status_label = Label.new()
    status_label.text = "Select targets and shoot"
    content_area.add_child(status_label)
```

#### ChargeController Updates (Most Complex)
```gdscript
func get_controller_phase() -> GameStateData.Phase:
    return GameStateData.Phase.CHARGE

func _add_phase_ui_elements(content_area: HBoxContainer) -> void:
    # Charge phase needs comprehensive top bar UI
    
    # Charge info label
    charge_info_label = Label.new()
    charge_info_label.text = "Step 1: Select a unit to begin charge"
    content_area.add_child(charge_info_label)
    
    # Separator
    content_area.add_child(VSeparator.new())
    
    # Declare charge button
    declare_button = Button.new()
    declare_button.text = "Declare Charge"
    declare_button.disabled = true
    declare_button.pressed.connect(_on_declare_charge_pressed)
    content_area.add_child(declare_button)
    
    # Roll charge button
    roll_button = Button.new()
    roll_button.text = "Roll 2D6"
    roll_button.disabled = true
    roll_button.pressed.connect(_on_roll_charge_pressed)
    content_area.add_child(roll_button)
    
    # Skip charge button
    skip_button = Button.new()
    skip_button.text = "Skip Charge"
    skip_button.disabled = true
    skip_button.pressed.connect(_on_skip_charge_pressed)
    content_area.add_child(skip_button)
    
    # Distance tracking (initially hidden)
    _add_distance_tracking_ui(content_area)

func _add_distance_tracking_ui(content_area: HBoxContainer) -> void:
    content_area.add_child(VSeparator.new())
    
    charge_distance_label = Label.new()
    charge_distance_label.text = "Charge: 0\""
    charge_distance_label.visible = false
    content_area.add_child(charge_distance_label)
    
    charge_used_label = Label.new()
    charge_used_label.text = "Used: 0.0\""
    charge_used_label.visible = false
    content_area.add_child(charge_used_label)
    
    charge_left_label = Label.new()
    charge_left_label.text = "Left: 0.0\""
    charge_left_label.visible = false
    content_area.add_child(charge_left_label)
```

#### FightController Updates
```gdscript
func get_controller_phase() -> GameStateData.Phase:
    return GameStateData.Phase.FIGHT

func _add_phase_ui_elements(content_area: HBoxContainer) -> void:
    # Fight sequence status
    var sequence_label = Label.new()
    sequence_label.text = "No active fights"
    sequence_label.name = "SequenceLabel"
    content_area.add_child(sequence_label)
    
    # Separator
    content_area.add_child(VSeparator.new())
    
    # Pile in button
    pile_in_button = Button.new()
    pile_in_button.text = "Pile In"
    pile_in_button.disabled = true
    pile_in_button.pressed.connect(_on_pile_in_pressed)
    content_area.add_child(pile_in_button)
    
    # Consolidate button
    consolidate_button = Button.new()
    consolidate_button.text = "Consolidate"
    consolidate_button.disabled = true
    consolidate_button.pressed.connect(_on_consolidate_pressed)
    content_area.add_child(consolidate_button)
```

### Phase 4: Cleanup and Integration

#### Remove Old UI Management Code

**From Main.gd update_ui_for_phase()**:
```gdscript
func update_ui_for_phase() -> void:
    # NEW: Just update the phase label, containers handle the rest
    phase_label.text = _get_phase_label_text(current_phase)
    
    # Switch to correct phase container (if not already done)
    _switch_to_phase_container(current_phase)
    
    # Update other UI elements
    refresh_unit_list()
    update_ui()
    
    # Remove old button management code - it's now handled by containers
```

**Update all Controllers' _setup_bottom_hud() methods**:
```gdscript
func _setup_bottom_hud() -> void:
    # NEW: Use standardized interface instead of direct UI creation
    setup_phase_ui()
    
    # Remove old UI creation code
```

#### Main.tscn Updates

Remove the hardcoded `EndDeploymentButton` and let the dynamic system handle all buttons:

```xml
<!-- OLD: Single hardcoded button -->
<!-- <node name="EndDeploymentButton" type="Button" parent="HUD_Bottom/HBoxContainer">
    <property name="layout_mode" value="2" />
    <property name="text" value="End Deployment" />
</node> -->

<!-- NEW: Dynamic containers added by code -->
<!-- Phase-specific containers will be added programmatically -->
```

## Implementation Tasks (In Order)

### Task 1: Core Infrastructure Setup
1. **Add container management system to Main.gd**
   - Implement `_setup_phase_ui_containers()`
   - Implement `_switch_to_phase_container()`
   - Implement `_get_phase_content_area()`
   - Implement `_clear_phase_content()`

2. **Update Main.gd integration points**
   - Update `_ready()` to setup containers
   - Update `setup_phase_controllers()` to use new system
   - Update `_on_phase_changed()` to switch containers
   - Update save/load functions for container switching

3. **Test basic container system**
   - Verify containers are created for all phases
   - Test container switching works
   - Verify end phase buttons work correctly

### Task 2: Controller Interface Implementation
1. **Add base interface methods to all controllers**
   - Add `setup_phase_ui()` method
   - Add `get_controller_phase()` method
   - Add `_add_phase_ui_elements()` stub

2. **Update controller initialization**
   - Call `setup_phase_ui()` in controller setup
   - Remove old `_setup_bottom_hud()` calls
   - Test each controller initializes correctly

### Task 3: MovementController Implementation
1. **Implement MovementController phase UI**
   - Add minimal status label
   - Test movement phase shows correct UI
   - Verify end movement button works

2. **Remove old MovementController bottom HUD code**
   - Clean up old `_setup_bottom_hud()` method
   - Remove bottom HUD cleanup from `_exit_tree()`
   - Test transitions to/from movement phase

### Task 4: ShootingController Implementation  
1. **Implement ShootingController phase UI**
   - Add minimal status label
   - Test shooting phase shows correct UI
   - Verify end shooting button works

2. **Remove old ShootingController bottom HUD code**
   - Clean up old `_setup_bottom_hud()` method
   - Remove `ShootingControls` container creation
   - Test transitions to/from shooting phase

### Task 5: ChargeController Implementation
1. **Implement ChargeController comprehensive phase UI**
   - Add charge info label
   - Add action buttons (Declare, Roll, Skip)
   - Add distance tracking UI
   - Wire up all button handlers

2. **Remove old ChargeController bottom HUD code**
   - Clean up old `_setup_bottom_hud()` method  
   - Remove `ChargeControls` container creation
   - Test all charge phase functionality

### Task 6: FightController Implementation
1. **Implement FightController phase UI**
   - Add fight sequence status
   - Add Pile In and Consolidate buttons
   - Wire up button handlers

2. **Remove old FightController bottom HUD code**
   - Clean up old `_setup_bottom_hud()` method
   - Remove `FightControls` container creation
   - Test fight phase functionality

### Task 7: Additional Phase Controllers
1. **Implement CommandController phase UI**
   - Add command points display
   - Add battle-shock test status
   - Test command phase

2. **Implement DeploymentController phase UI**  
   - Add deployment status
   - Test deployment phase

3. **Implement ScoringController phase UI**
   - Add scoring status
   - Test scoring phase

### Task 8: Main.tscn Cleanup
1. **Remove hardcoded EndDeploymentButton**
   - Delete button from scene file
   - Update any references in Main.gd
   - Test all phases still have end buttons

### Task 9: Integration Testing
1. **Test all phase transitions**
   - Test sequential phase progression
   - Verify correct UI shows for each phase
   - Test phase-specific buttons work

2. **Test save/load functionality**
   - Save in each phase
   - Load and verify correct phase UI
   - Test multiple save/load cycles

3. **Test edge cases**
   - Rapid phase transitions
   - Phase transition during UI interaction
   - Loading corrupted saves

### Task 10: Performance and Polish
1. **Performance testing**
   - Measure container switching performance
   - Check for memory leaks
   - Optimize if necessary

2. **Visual polish**
   - Ensure consistent spacing
   - Test with different screen sizes
   - Verify UI doesn't overflow

## Validation Gates

### Automated Validation
```bash
# Godot syntax validation
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
export PATH="$HOME/bin:$PATH"
godot --headless --check-only

# Runtime validation (no errors)
godot --headless --validate-only
```

### Manual Testing Checklist

#### Phase-Specific UI Test
```bash
# For each phase (Deployment, Command, Movement, Shooting, Charge, Fight, Morale, Scoring):
# 1. Start new game
# 2. Progress to target phase
# 3. Verify ONLY phase-specific UI is visible
# 4. Verify all buttons/controls work
# 5. Verify "End [Phase]" button works correctly
```

#### Save/Load Test Sequence
```bash
# 1. Save during each phase
# 2. Continue to next phase  
# 3. Load the saved game
# 4. Verify correct phase UI is displayed
# 5. Verify no leftover UI from other phases
# 6. Test all phase functionality works
```

#### Transition Testing
```bash
# 1. Complete full turn cycle (all phases)
# 2. Verify smooth UI transitions
# 3. Verify no UI overlap or artifacts  
# 4. Test rapid phase transitions (spam end button)
# 5. Verify UI state consistency
```

### Expected Phase UI Elements

#### Deployment Phase
- **Status**: "Deploy units or End Deployment"
- **Buttons**: End Deployment
- **Info**: Deployment progress

#### Command Phase  
- **Status**: "Gain CP, battle-shock tests"
- **Buttons**: End Command
- **Info**: Command points, battle-shock status

#### Movement Phase
- **Status**: "Move units or End Movement" 
- **Buttons**: End Movement
- **Info**: Movement progress

#### Shooting Phase
- **Status**: "Select targets and shoot"
- **Buttons**: End Shooting
- **Info**: Shooting progress

#### Charge Phase
- **Status**: "Step 1: Select a unit to begin charge"
- **Buttons**: Declare Charge, Roll 2D6, Skip Charge, End Charge
- **Info**: Charge distance tracking (when relevant)

#### Fight Phase
- **Status**: "No active fights" / "Fight sequence: X vs Y"
- **Buttons**: Pile In, Consolidate, End Fight
- **Info**: Active combat status

#### Morale/Scoring Phases
- **Status**: Phase-appropriate status message
- **Buttons**: End Phase / End Turn
- **Info**: Relevant phase information

## Quality Assurance

### Acceptance Criteria
- [ ] Each phase displays only phase-relevant UI elements
- [ ] No UI elements from other phases are visible
- [ ] All phase-specific buttons/controls function correctly
- [ ] Save/load correctly restores phase-specific UI
- [ ] Phase transitions are smooth and artifact-free
- [ ] UI layout is consistent across all phases
- [ ] Performance remains smooth during transitions
- [ ] No console errors during normal operation

### Regression Testing  
- [ ] All existing phase functionality continues to work
- [ ] Save/load system maintains full compatibility
- [ ] Right panel UI management remains unaffected  
- [ ] Game logic and rules remain unchanged
- [ ] Visual/audio elements function correctly
- [ ] User interactions work as expected

### Edge Case Coverage
- [ ] Loading saves from different phases
- [ ] Phase transitions during active UI interactions
- [ ] Corrupted or missing UI elements
- [ ] Rapid/repeated phase transitions
- [ ] Multiple save/load cycles
- [ ] UI overflow with very long text
- [ ] Screen resolution changes
- [ ] Controller failures during UI setup

## Expected Outcome

**Primary Goal**: Clean, intuitive phase-specific top bar UI
- Each phase shows only relevant controls and information
- Users can immediately understand available actions
- No confusion from irrelevant UI elements
- Consistent visual design across all phases

**User Experience Improvements**:
- Clear phase identification and available actions
- Reduced cognitive load from focused UI
- Smooth transitions between phases  
- Reliable save/load experience
- Professional, polished interface

**Technical Improvements**:
- Standardized controller interface for maintainability
- Clean separation of concerns between Main.gd and controllers
- Reliable UI state management
- Better code organization and reusability
- Consistent error handling and edge case management

## Risk Assessment

**Low Risk**:
- Well-understood UI container system
- Clear requirements from Warhammer rules
- Existing controller pattern to follow
- Non-destructive changes to game logic

**Medium Risk**:
- Complex interaction between Main.gd and multiple controllers
- Save/load state restoration complexity
- Potential for temporary visual artifacts during transitions
- Need to coordinate changes across multiple files

**High Risk**:
- Breaking existing controller functionality
- Save file compatibility issues
- Performance impact from dynamic UI creation
- User confusion during transition period

**Mitigation Strategies**:
- Implement changes incrementally (one controller at a time)
- Maintain backward compatibility during development
- Extensive testing at each implementation stage
- Keep old code available for rollback if needed
- Document all changes thoroughly

## Confidence Score: 8/10

**High Confidence Factors**:
- Clear problem definition from existing code analysis
- Well-defined requirements from Warhammer 40k rules
- Existing similar implementations to reference (right panel cleanup)
- Structured approach with clear validation steps
- Strong understanding of current architecture

**Risk Factors**:
- Complexity of coordinating multiple controller changes
- Potential for unforeseen edge cases during save/load
- Need to maintain compatibility with existing save files
- Risk of breaking existing functionality during refactor

This implementation provides a comprehensive solution for clean, phase-specific top bar UI that enhances user experience while maintaining system reliability and performance.