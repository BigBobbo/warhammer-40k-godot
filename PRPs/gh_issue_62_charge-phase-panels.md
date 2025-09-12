# Product Requirements Document: Charge Phase Panels UI Reorganization

## Issue Reference
GitHub Issue #62: Move everything in the top bar during the charge phase to the right hand panel except "End Charge Phase"

## Feature Description
Reorganize the Charge Phase UI by moving action buttons and status information from the top bar (HUD_Bottom) to the right panel, keeping only the "End Charge Phase" button in the top bar. Additionally, hide the UnitListPanel in the right panel during the charge phase for a cleaner interface.

## Problem Statement
Currently, the Charge Phase displays an overloaded top bar with many UI elements:
1. **Cluttered Top Bar**: Contains 8+ UI elements including buttons, labels, and status displays
2. **Inconsistent Layout**: Charge phase has the most complex top bar compared to other phases
3. **UnitListPanel Visibility**: The standard unit list remains visible but is not needed during charge phase
4. **User Experience**: Important charge controls are scattered across different UI areas
5. **Phase Consistency**: Other phases (shooting, movement) have simpler top bars with most controls in right panel

## Requirements

### Functional Requirements
1. **Simplified Top Bar**: Only "End Charge Phase" button remains in top bar
2. **Enhanced Right Panel**: All charge action buttons and status moved to right panel
3. **Hidden UnitListPanel**: Standard unit list not visible during charge phase
4. **Maintained Functionality**: All existing button behaviors and state management preserved
5. **Consistent Layout**: Follow established right panel patterns from other phases

### UI Elements to Move (From Top Bar to Right Panel)
- "Declare Charge" Button
- "Roll 2D6" Button  
- "Skip Charge" Button
- Charge status details (completed/eligible counts)
- Charge distance tracking labels (when active)
- Charge info/instruction label

### UI Elements to Keep (Top Bar)
- "End Charge Phase" button only

### UI Elements to Hide
- UnitListPanel in right panel during charge phase

## Implementation Context

### Current Architecture Analysis

#### Top Bar Implementation (ChargeController.gd lines 220-308)
```gdscript
func _setup_bottom_hud() -> void:
    # Creates ChargeControls container with 8 UI elements:
    # - charge_info_label (line 241-243)
    # - charge_distance_label (line 246-249)  
    # - charge_used_label (line 251-254)
    # - charge_left_label (line 256-259)
    # - declare_button (line 265-269)
    # - roll_button (line 272-276)
    # - skip_button (line 279-283)
    # - end_phase_button (line 297-300) <- KEEP THIS ONLY
    # - charge_status_label (line 305-308)
```

#### Right Panel Implementation (ChargeController.gd lines 310-370)
```gdscript
func _setup_right_panel() -> void:
    # Currently contains:
    # - Unit selector (lines 337-345)
    # - Target list (lines 347-360)  
    # - Dice log display (lines 362-370)
    # Need to add: Action buttons section
```

#### State Management Integration
```gdscript
func _update_button_states() -> void:
    # Lines 444-482: Button enable/disable logic
    # Must work with new button locations
    
func _update_charge_status() -> void:
    # Lines 1327-1335: Status display logic
    # Must work with moved status label
```

### Reference Pattern: ShootingController

#### UnitListPanel Hiding Pattern (ShootingController.gd lines 280-291)
```gdscript
# Hide UnitListPanel and UnitCard when shooting phase starts
var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
if container:
    var unit_list_panel = container.get_node_or_null("UnitListPanel")
    if unit_list_panel:
        print("ShootingController: Hiding UnitListPanel on phase start")
        unit_list_panel.visible = false
```

#### Right Panel Button Structure (ShootingController.gd lines 233-246)
```gdscript
# Action buttons
var button_container = HBoxContainer.new()

clear_button = Button.new()
clear_button.text = "Clear All"
clear_button.pressed.connect(_on_clear_pressed)
button_container.add_child(clear_button)

confirm_button = Button.new()
confirm_button.text = "Confirm Targets"
confirm_button.pressed.connect(_on_confirm_pressed)
button_container.add_child(confirm_button)

shooting_panel.add_child(button_container)
```

### Files Requiring Modification

#### Primary File
1. **ChargeController.gd** (~1512 lines): Main implementation changes
   - Simplify `_setup_bottom_hud()` method (lines 220-308)
   - Enhance `_setup_right_panel()` method (lines 310-370)
   - Add UnitListPanel hiding logic in `set_phase()` method (lines 372-393)

#### Supporting Files (For Testing)
- **40k/tests/ui/test_button_functionality.gd**: UI button testing patterns
- **40k/tests/phases/test_charge_phase.gd**: Charge phase testing
- **40k/tests/helpers/BaseUITest.gd**: UI testing framework

### Documentation References
- **Warhammer Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot UI Documentation**: https://docs.godotengine.org/en/4.4/classes/class_control.html
- **Godot Container Management**: https://docs.godotengine.org/en/4.4/classes/class_container.html

## Implementation Blueprint

### Strategy Overview
Reorganize UI elements following established patterns while maintaining all existing functionality:
1. **Simplify Top Bar**: Remove all charge-specific UI except End Phase button
2. **Enhance Right Panel**: Add action buttons section using ShootingController pattern
3. **Hide UnitListPanel**: Follow ShootingController visibility control pattern
4. **Preserve Functionality**: Ensure all button handlers and state management continue working

### Implementation Steps

#### Step 1: Simplify Top Bar UI (_setup_bottom_hud method)

**Location**: ChargeController.gd lines 220-308

**Current Implementation (REMOVE MOST OF THIS)**:
```gdscript
func _setup_bottom_hud() -> void:
    # Keep container setup (lines 220-238)
    var container = HBoxContainer.new()
    container.name = "ChargeControls"
    main_container.add_child(container)
    container.add_child(VSeparator.new())
    
    # REMOVE: All charge-specific UI elements (lines 241-307)
    # KEEP ONLY: End phase button setup
```

**New Simplified Implementation**:
```gdscript
func _setup_bottom_hud() -> void:
    # Get the main HBox container in bottom HUD
    var main_container = hud_bottom.get_node_or_null("HBoxContainer")
    if not main_container:
        print("ERROR: Cannot find HBoxContainer in HUD_Bottom")
        return
    
    # Clean up existing charge controls
    var existing_controls = main_container.get_node_or_null("ChargeControls")
    if existing_controls:
        main_container.remove_child(existing_controls)
        existing_controls.free()
    
    var container = HBoxContainer.new()
    container.name = "ChargeControls"
    main_container.add_child(container)
    
    # Add separator before charge controls
    container.add_child(VSeparator.new())
    
    # SIMPLIFIED: Only End phase button in top bar
    end_phase_button = Button.new()
    end_phase_button.text = "End Charge Phase"
    end_phase_button.pressed.connect(_on_end_phase_pressed)
    container.add_child(end_phase_button)
```

#### Step 2: Enhance Right Panel with Action Buttons

**Location**: ChargeController.gd lines 310-370

**Current Implementation Enhancement**:
```gdscript
func _setup_right_panel() -> void:
    # Keep existing setup (lines 310-360)
    # ... unit selector, target list ...
    
    # ADD: Action buttons section after dice log
    charge_panel.add_child(HSeparator.new())
    
    # Charge status display (moved from top bar)
    var status_label = Label.new()
    status_label.text = "Charge Actions:"
    status_label.add_theme_font_size_override("font_size", 14)
    charge_panel.add_child(status_label)
    
    # Charge info label (moved from top bar)
    charge_info_label = Label.new()
    charge_info_label.text = "Step 1: Select a unit from the list above to begin charge"
    charge_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    charge_panel.add_child(charge_info_label)
    
    # Action buttons container
    var action_button_container = VBoxContainer.new()
    action_button_container.name = "ChargeActionButtons"
    
    # First row: Main action buttons
    var main_buttons = HBoxContainer.new()
    
    declare_button = Button.new()
    declare_button.text = "Declare Charge"
    declare_button.disabled = true
    declare_button.pressed.connect(_on_declare_charge_pressed)
    main_buttons.add_child(declare_button)
    
    roll_button = Button.new()
    roll_button.text = "Roll 2D6"
    roll_button.disabled = true
    roll_button.pressed.connect(_on_roll_charge_pressed)
    main_buttons.add_child(roll_button)
    
    action_button_container.add_child(main_buttons)
    
    # Second row: Secondary buttons
    var secondary_buttons = HBoxContainer.new()
    
    skip_button = Button.new()
    skip_button.text = "Skip Charge"
    skip_button.disabled = true
    skip_button.pressed.connect(_on_skip_charge_pressed)
    secondary_buttons.add_child(skip_button)
    
    next_unit_button = Button.new()
    next_unit_button.text = "Select Next Unit"
    next_unit_button.disabled = true
    next_unit_button.visible = false
    next_unit_button.pressed.connect(_on_next_unit_pressed)
    secondary_buttons.add_child(next_unit_button)
    
    action_button_container.add_child(secondary_buttons)
    
    charge_panel.add_child(action_button_container)
    
    # Distance tracking section (moved from top bar, initially hidden)
    var distance_container = VBoxContainer.new()
    distance_container.name = "DistanceTracking"
    
    charge_distance_label = Label.new()
    charge_distance_label.text = "Charge: 0\""
    charge_distance_label.visible = false
    distance_container.add_child(charge_distance_label)
    
    charge_used_label = Label.new()
    charge_used_label.text = "Used: 0.0\""
    charge_used_label.visible = false
    distance_container.add_child(charge_used_label)
    
    charge_left_label = Label.new()
    charge_left_label.text = "Left: 0.0\""
    charge_left_label.visible = false
    distance_container.add_child(charge_left_label)
    
    charge_panel.add_child(distance_container)
    
    # Charge status (moved from top bar)
    charge_status_label = Label.new()
    charge_status_label.text = ""
    charge_status_label.add_theme_font_size_override("font_size", 12)
    charge_panel.add_child(charge_status_label)
    
    # Keep existing dice log at bottom (lines 362-370)
```

#### Step 3: Hide UnitListPanel Following ShootingController Pattern

**Location**: ChargeController.gd `set_phase()` method lines 372-393

**Add After Phase Setup**:
```gdscript
func set_phase(phase_instance) -> void:
    current_phase = phase_instance
    
    # Existing signal connections (lines 375-390)
    # ...
    
    # ADD: Hide UnitListPanel and UnitCard during charge phase
    var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
    if container:
        var unit_list_panel = container.get_node_or_null("UnitListPanel")
        if unit_list_panel:
            print("ChargeController: Hiding UnitListPanel during charge phase")
            unit_list_panel.visible = false
        
        var unit_card = container.get_node_or_null("UnitCard")
        if unit_card:
            print("ChargeController: Hiding UnitCard during charge phase")
            unit_card.visible = false
    
    # Refresh UI with current phase data
    _refresh_ui()
```

#### Step 4: Update Button State Management

**Location**: ChargeController.gd `_update_button_states()` method lines 444-482

**Verification Required**: Ensure all button references work with new locations
```gdscript
func _update_button_states() -> void:
    # Existing logic should work unchanged since button variables remain the same
    # Just verify all is_instance_valid() checks work correctly
    if is_instance_valid(declare_button):
        declare_button.disabled = not can_declare
    if is_instance_valid(roll_button):
        roll_button.disabled = not can_roll
    if is_instance_valid(skip_button):
        skip_button.disabled = not can_skip
    
    # Status updates work with moved label
    _update_charge_status()
    
    # Info label updates work with moved label
    if is_instance_valid(charge_info_label):
        # Existing logic unchanged (lines 472-482)
```

#### Step 5: Cleanup and Integration

**Remove Old UI Creation Code**: 
- Delete lines 241-307 from `_setup_bottom_hud()` (all the removed UI elements)
- Keep only the simplified end phase button setup

**Update Exit Tree Cleanup**:
- Existing cleanup in `_exit_tree()` should continue working
- Button cleanup handled automatically when parent containers are removed

## Implementation Tasks (In Order)

### Task 1: Simplify Top Bar Implementation
1. **Modify `_setup_bottom_hud()` method**
   - Remove all UI elements except "End Charge Phase" button
   - Simplify container structure
   - Test basic functionality

2. **Verify top bar cleanup**
   - Ensure no visual artifacts remain
   - Test "End Charge Phase" button functionality
   - Verify button styling and positioning

### Task 2: Enhance Right Panel with Action Buttons
1. **Add action buttons section to `_setup_right_panel()`**
   - Create button containers with proper layout
   - Move all charge action buttons to right panel
   - Implement button signal connections

2. **Add charge status and info labels**
   - Move charge_info_label from top bar
   - Move charge_status_label from top bar
   - Add distance tracking labels (initially hidden)

3. **Test button functionality**
   - Verify all buttons respond correctly
   - Test button enable/disable states
   - Verify visual layout and spacing

### Task 3: Hide UnitListPanel
1. **Add UnitListPanel hiding logic**
   - Follow ShootingController pattern exactly
   - Add hiding logic to `set_phase()` method
   - Test UnitListPanel is properly hidden

2. **Verify right panel layout**
   - Ensure charge panel occupies correct space
   - Test scrolling behavior if needed
   - Verify no visual conflicts

### Task 4: State Management Verification
1. **Test button state management**
   - Verify `_update_button_states()` works with new locations
   - Test all button enable/disable transitions
   - Verify charge info updates work correctly

2. **Test distance tracking**
   - Verify distance labels show/hide correctly
   - Test distance updates during charge movement
   - Verify visual positioning and readability

### Task 5: Integration Testing
1. **Full charge phase workflow test**
   - Test complete charge sequence from start to finish
   - Verify all UI transitions work smoothly
   - Test edge cases (failed charges, skip, etc.)

2. **Phase transition testing**
   - Test entering charge phase from other phases
   - Test exiting charge phase to other phases
   - Verify UI cleanup and restoration

### Task 6: Performance and Polish
1. **Visual polish**
   - Adjust spacing and sizing as needed
   - Ensure consistent styling with other phases
   - Test with different screen sizes/resolutions

2. **Performance verification**
   - Verify no performance regressions
   - Test UI responsiveness
   - Check memory usage patterns

## Validation Gates

### Automated Syntax Validation
```bash
# Godot syntax validation
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
export PATH="$HOME/bin:$PATH"
godot --headless --check-only

# Runtime validation (no errors)
godot --headless --validate-only
```

### Manual UI Testing Checklist

#### Basic Functionality Test
```bash
# 1. Start new game and transition to charge phase
# 2. Verify top bar shows ONLY "End Charge Phase" button
# 3. Verify right panel shows charge controls section
# 4. Verify UnitListPanel is hidden
# 5. Test all charge buttons function correctly
```

#### Button State Testing
```bash
# For each charge button (Declare, Roll, Skip):
# 1. Verify button exists in right panel
# 2. Test button enable/disable states
# 3. Verify button responses and game state changes
# 4. Test button interactions in correct sequence
```

#### Workflow Integration Test
```bash
# Complete charge sequence test:
# 1. Select unit from charge unit list
# 2. Select targets from target list  
# 3. Click "Declare Charge" button
# 4. Click "Roll 2D6" button
# 5. Complete charge movement (if successful)
# 6. Verify all UI updates correctly throughout process
```

#### Phase Transition Test
```bash
# 1. Enter charge phase from movement phase
# 2. Verify UI switches correctly
# 3. Complete charges or end phase
# 4. Transition to fight phase
# 5. Verify UI cleanup and restoration
```

### Expected UI Layout

#### Top Bar (HUD_Bottom) - After Implementation
- **Only Element**: "End Charge Phase" button
- **Styling**: Consistent with other simple phase layouts
- **Behavior**: Ends charge phase when clicked

#### Right Panel - After Implementation
```
┌─────────────────────────────────┐
│ Charge Panel                    │
├─────────────────────────────────┤
│ Units that can charge:          │
│ [Unit List]                     │
├─────────────────────────────────┤  
│ Eligible targets:               │
│ [Target List]                   │
├─────────────────────────────────┤
│ Dice Log:                       │
│ [Dice Log Display]              │
├─────────────────────────────────┤
│ Charge Actions:                 │
│ Step 1: Select a unit...        │
│ [Declare] [Roll 2D6]            │
│ [Skip]    [Next Unit]           │
│ Charge: 8" Used: 3.2" Left: 4.8"│
│ Charges: 2 completed, 3 eligible│
└─────────────────────────────────┘
```

#### Hidden Elements
- **UnitListPanel**: Not visible during charge phase
- **UnitCard**: Not visible during charge phase

## Quality Assurance

### Acceptance Criteria
- [ ] Top bar contains only "End Charge Phase" button
- [ ] All charge action buttons moved to right panel
- [ ] All charge status/info labels moved to right panel  
- [ ] UnitListPanel hidden during charge phase
- [ ] All existing button functionality preserved
- [ ] Button enable/disable states work correctly
- [ ] Distance tracking appears/disappears correctly
- [ ] Phase transitions work smoothly
- [ ] No visual artifacts or layout issues
- [ ] Performance remains optimal

### Regression Testing
- [ ] All charge phase functionality works as before
- [ ] No impact on other phase UI layouts
- [ ] Save/load works correctly with charge phase
- [ ] Button interactions maintain correct game state
- [ ] UI cleanup works properly on phase exit
- [ ] No memory leaks from UI changes

### Edge Case Testing
- [ ] Rapid button clicking doesn't break UI
- [ ] Phase transitions during active charges
- [ ] Invalid game states handle gracefully  
- [ ] UI works with different screen resolutions
- [ ] Scrolling behavior works correctly
- [ ] Button focus and keyboard navigation
- [ ] Multiple charge attempts in same phase

## Expected Outcome

**Primary Goal**: Clean, organized charge phase UI
- Top bar simplified to essential phase control only
- Right panel contains all charge-specific actions and information
- UnitListPanel hidden for cleaner interface during charge phase
- Consistent with other phase UI patterns

**User Experience Improvements**:
- Less cluttered top bar for better visual clarity
- Logical grouping of charge controls in right panel
- Easier to find and use charge-specific functions
- Consistent interface patterns across phases
- Improved workflow for charge operations

**Technical Improvements**:
- Better separation of concerns between UI areas
- Consistent UI management patterns
- Cleaner code organization
- Reduced top bar complexity
- Following established UI patterns

## Risk Assessment

**Low Risk**:
- No game logic changes, only UI reorganization
- Established patterns to follow from ShootingController
- Clear requirements with specific elements to move
- Well-understood button management system

**Medium Risk**:
- Button state management must work in new locations
- UI layout changes could affect visual appearance
- Need to ensure all button handlers continue working
- Phase transition timing dependencies

**Mitigation Strategies**:
- Test each component individually before integration
- Follow existing patterns exactly from ShootingController
- Maintain comprehensive manual testing checklist
- Implement changes incrementally with validation at each step
- Keep old code commented for quick rollback if needed

## Confidence Score: 9/10

**High Confidence Factors**:
- Clear, specific requirements with exact elements to move
- Established patterns in ShootingController to follow
- No complex game logic changes required
- Comprehensive understanding of current implementation
- Well-defined testing approach with existing test infrastructure
- Low risk of breaking existing functionality

**Minor Risk Factors**:
- Visual layout adjustments may require iteration
- Button state management timing needs verification
- UI spacing and sizing may need fine-tuning

This implementation provides a clean, well-organized charge phase UI that follows established patterns while improving user experience through logical grouping of controls and simplified interface layout.