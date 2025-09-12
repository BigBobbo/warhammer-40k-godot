# Product Requirements Document: Fight Phase Panels UI Cleanup

## Issue Reference
GitHub Issue #63: Clean up fight phase panels

## Feature Description
Reorganize the Fight Phase UI by moving action buttons and status information from the top bar (HUD_Bottom) to the right panel, keeping only the "End Fight Phase" button in the top bar. Additionally, ensure the UnitListPanel is properly hidden during the fight phase and remove any redundant buttons.

## Problem Statement
Currently, the Fight Phase displays an overloaded top bar with multiple UI elements that creates inconsistency with other phases:

1. **Cluttered Top Bar**: Contains "No active fights" status, "Pile in" button, "Consolidate" button, and "End Fight Phase" button
2. **Inconsistent Layout**: Fight phase has more complex top bar than shooting/charge phases which moved their controls to right panel
3. **UnitListPanel Visibility**: The standard unit list may be visible during fight phase when it should be hidden
4. **Potential Button Redundancy**: Issue mentions possible "End Fight" button that duplicates "End Fight Phase"
5. **refresh_unit_list() Issue**: The method may be re-making the unit_list visible when it shouldn't be

## Requirements

### Functional Requirements
1. **Simplified Top Bar**: Only "End Fight Phase" button remains in top bar
2. **Enhanced Right Panel**: All fight action buttons and status moved to right panel
3. **Hidden UnitListPanel**: Standard unit list not visible during fight phase
4. **Remove Redundant Buttons**: Eliminate duplicate "End Fight" button if it exists
5. **Maintained Functionality**: All existing button behaviors and state management preserved

### UI Elements to Move (From Top Bar to Right Panel)
- "No active fights" status label
- "Pile in" Button
- "Consolidate" Button

### UI Elements to Keep (Top Bar)
- "End Fight Phase" button only

### UI Elements to Hide
- UnitListPanel in right panel during fight phase

### UI Elements to Remove
- Redundant "End Fight" button (if it exists and duplicates "End Fight Phase")

## Implementation Context

### Current Architecture Analysis

#### Fight Phase Top Bar Implementation (FightController.gd lines 116-176)
```gdscript
func _setup_bottom_hud() -> void:
    # Creates FightControls container with multiple UI elements:
    # - phase_label: "FIGHT PHASE" (line 141-143)
    # - sequence_label: "No active fights" (line 149-152) <- MOVE TO RIGHT PANEL
    # - pile_in_button: "Pile In" (line 158-162) <- MOVE TO RIGHT PANEL
    # - consolidate_button: "Consolidate" (line 164-168) <- MOVE TO RIGHT PANEL
    # - end_phase_button: "End Fight Phase" (line 173-176) <- KEEP IN TOP BAR
```

#### Fight Phase Right Panel Implementation (FightController.gd lines 178-283)
```gdscript
func _setup_right_panel() -> void:
    # Currently contains:
    # - Fight sequence display (unit_selector)
    # - Attack assignments tree
    # - Target basket
    # - Action buttons (Clear All, Fight!)
    # - Dice log display
    # Need to add: Status label, Pile In button, Consolidate button
```

#### UnitListPanel Visibility Issue (Main.gd lines 907-930)
```gdscript
func refresh_unit_list() -> void:
    match current_phase:
        GameStateData.Phase.SHOOTING:
            unit_list.visible = false  # Hidden correctly
        GameStateData.Phase.CHARGE:
            unit_list.visible = false  # Hidden correctly
        _:
            unit_list.visible = true   # Fight phase falls into default case!
            # This means fight phase shows UnitListPanel when it shouldn't
```

### Reference Pattern: ChargeController (From Issue #62)

The charge phase cleanup (PRPs/gh_issue_62_charge-phase-panels.md) provides the exact pattern to follow:

#### Simplified Top Bar Pattern
```gdscript
func _setup_bottom_hud() -> void:
    # Clean up existing container
    var existing_controls = main_container.get_node_or_null("FightControls")
    if existing_controls:
        main_container.remove_child(existing_controls)
        existing_controls.free()
    
    var container = HBoxContainer.new()
    container.name = "FightControls"
    main_container.add_child(container)
    container.add_child(VSeparator.new())
    
    # SIMPLIFIED: Only End phase button in top bar
    end_phase_button = Button.new()
    end_phase_button.text = "End Fight Phase"
    end_phase_button.pressed.connect(_on_end_phase_pressed)
    container.add_child(end_phase_button)
```

#### Enhanced Right Panel Pattern
```gdscript
# Add action buttons section to existing right panel setup
fight_panel.add_child(HSeparator.new())

# Fight status display (moved from top bar)
var status_label = Label.new()
status_label.text = "Fight Actions:"
fight_panel.add_child(status_label)

# Fight sequence status (moved from top bar)
fight_sequence_label = Label.new()
fight_sequence_label.text = "No active fights"
fight_sequence_label.name = "SequenceLabel"
fight_panel.add_child(fight_sequence_label)

# Action buttons container
var action_button_container = HBoxContainer.new()

pile_in_button = Button.new()
pile_in_button.text = "Pile In"
pile_in_button.disabled = true
pile_in_button.pressed.connect(_on_pile_in_pressed)
action_button_container.add_child(pile_in_button)

consolidate_button = Button.new()
consolidate_button.text = "Consolidate"
consolidate_button.disabled = true
consolidate_button.pressed.connect(_on_consolidate_pressed)
action_button_container.add_child(consolidate_button)

fight_panel.add_child(action_button_container)
```

### Files Requiring Modification

#### Primary Changes
1. **FightController.gd** (~1137 lines): Reorganize top bar and right panel UI
2. **Main.gd** (~2099 lines): Add explicit FIGHT phase case to refresh_unit_list()

#### Supporting Files (For Testing)
- **40k/tests/ui/test_button_functionality.gd**: UI button testing patterns
- **40k/tests/phases/test_fight_phase.gd**: Fight phase testing
- **40k/phases/FightPhase.gd**: Core fight phase logic (verify no button conflicts)

### Documentation References
- **Warhammer Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot UI Documentation**: https://docs.godotengine.org/en/4.4/classes/class_control.html
- **Godot Container Management**: https://docs.godotengine.org/en/4.4/classes/class_container.html

## Implementation Blueprint

### Strategy Overview
Follow the established charge phase cleanup pattern while maintaining all existing functionality:
1. **Simplify Top Bar**: Remove all fight-specific UI except End Phase button
2. **Enhance Right Panel**: Add action buttons section using established UI patterns
3. **Fix UnitListPanel Visibility**: Add explicit FIGHT phase case to refresh_unit_list()
4. **Remove Redundant Buttons**: Verify and eliminate duplicate "End Fight" button if found
5. **Preserve Functionality**: Ensure all button handlers and state management continue working

### Implementation Steps

#### Step 1: Simplify Top Bar UI (_setup_bottom_hud method)

**Location**: FightController.gd lines 116-176

**Current Implementation (REMOVE MOST OF THIS)**:
```gdscript
func _setup_bottom_hud() -> void:
    # Keep container setup (lines 118-138)
    # REMOVE: All fight-specific UI elements (lines 141-175)
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
    
    # Clean up existing fight controls
    var existing_controls = main_container.get_node_or_null("FightControls")
    if existing_controls:
        main_container.remove_child(existing_controls)
        existing_controls.free()
    
    var container = HBoxContainer.new()
    container.name = "FightControls"
    main_container.add_child(container)
    
    # Add separator before fight controls
    container.add_child(VSeparator.new())
    
    # SIMPLIFIED: Only End phase button in top bar
    var end_phase_button = Button.new()
    end_phase_button.text = "End Fight Phase"
    end_phase_button.pressed.connect(_on_end_phase_pressed)
    container.add_child(end_phase_button)
```

#### Step 2: Enhance Right Panel with Action Buttons

**Location**: FightController.gd lines 178-283

**Enhancement to Existing _setup_right_panel()**:
```gdscript
func _setup_right_panel() -> void:
    # Keep existing setup (lines 178-270)
    # ... unit selector, attack tree, target basket, existing buttons, dice log ...
    
    # ADD: Action buttons section after dice log
    fight_panel.add_child(HSeparator.new())
    
    # Fight status display (moved from top bar)
    var status_section_label = Label.new()
    status_section_label.text = "Fight Status:"
    status_section_label.add_theme_font_size_override("font_size", 14)
    fight_panel.add_child(status_section_label)
    
    # Fight sequence status (moved from top bar)
    var sequence_label = Label.new()
    sequence_label.text = "No active fights"
    sequence_label.name = "SequenceLabel"
    fight_panel.add_child(sequence_label)
    
    # Action buttons container
    var action_section_label = Label.new()
    action_section_label.text = "Movement Actions:"
    action_section_label.add_theme_font_size_override("font_size", 14)
    fight_panel.add_child(action_section_label)
    
    var action_button_container = HBoxContainer.new()
    action_button_container.name = "FightMovementButtons"
    
    # Pile In button (moved from top bar)
    pile_in_button = Button.new()
    pile_in_button.text = "Pile In"
    pile_in_button.pressed.connect(_on_pile_in_pressed)
    pile_in_button.disabled = true
    action_button_container.add_child(pile_in_button)
    
    # Consolidate button (moved from top bar)
    consolidate_button = Button.new()
    consolidate_button.text = "Consolidate"
    consolidate_button.pressed.connect(_on_consolidate_pressed)
    consolidate_button.disabled = true
    action_button_container.add_child(consolidate_button)
    
    fight_panel.add_child(action_button_container)
```

#### Step 3: Fix UnitListPanel Visibility in Main.gd

**Location**: Main.gd lines 907-930 in refresh_unit_list() method

**Current Issue**:
```gdscript
match current_phase:
    GameStateData.Phase.SHOOTING:
        unit_list.visible = false
    GameStateData.Phase.CHARGE:
        unit_list.visible = false
    _:  # Fight phase falls into this default case!
        unit_list.visible = true  # This shows UnitListPanel incorrectly
```

**Fix Implementation**:
```gdscript
match current_phase:
    GameStateData.Phase.SHOOTING:
        # Hide unit list during shooting phase - shooting controller handles its own UI
        unit_list.visible = false
        unit_list.clear()
        print("Refreshing right panel unit list for shooting - unit list hidden")
    
    GameStateData.Phase.CHARGE:
        # Hide unit list during charge phase - charge controller handles its own UI
        unit_list.visible = false
        unit_list.clear()
        print("Refreshing right panel unit list for charge - unit list hidden")
    
    GameStateData.Phase.FIGHT:
        # Hide unit list during fight phase - fight controller handles its own UI
        unit_list.visible = false
        unit_list.clear()
        print("Refreshing right panel unit list for fight - unit list hidden")
    
    _:
        # Default: show all units for active player in right panel
        unit_list.visible = true
        # ... existing default case code
```

#### Step 4: Update Button State Management

**Location**: FightController.gd - verify existing state management methods work with new button locations

**Verification Required**: Ensure existing methods work correctly:
```gdscript
func _refresh_fight_sequence() -> void:
    # Update sequence label in right panel (moved from top bar)
    # Lines 376-390: Update sequence_label reference
    
func _update_ui_state() -> void:
    # Lines 611-623: Ensure button enable/disable logic works with moved buttons
    
func _refresh_available_actions() -> void:
    # Lines 624-646: Verify action button creation works in right panel context
```

#### Step 5: Search for and Remove Redundant Buttons

**Search Pattern**: Look for duplicate "End Fight" buttons that might conflict with "End Fight Phase"

**Verification Steps**:
1. Search codebase for buttons with text "End Fight" (not "End Fight Phase")
2. Check if any duplicate the functionality of the main End Fight Phase button
3. Remove redundant buttons if found
4. Update any references to removed buttons

#### Step 6: Cleanup and Integration

**Remove Old UI Creation Code**: 
- Delete lines 141-175 from `_setup_bottom_hud()` (all the removed UI elements)
- Keep only the simplified end phase button setup

**Update Exit Tree Cleanup**:
- Existing cleanup in `_exit_tree()` lines 54-78 should continue working
- Button cleanup handled automatically when parent containers are removed

**Test Button References**:
- Verify all existing button variable references (pile_in_button, consolidate_button) work in new locations
- Ensure signal connections remain functional
- Test button enable/disable state changes work correctly

## Implementation Tasks (In Order)

### Task 1: Simplify Top Bar Implementation
1. **Modify `_setup_bottom_hud()` method**
   - Remove all UI elements except "End Fight Phase" button
   - Simplify container structure following charge phase pattern
   - Test basic top bar functionality

2. **Verify top bar cleanup**
   - Ensure no visual artifacts remain from removed elements
   - Test "End Fight Phase" button functionality
   - Verify button styling and positioning

### Task 2: Enhance Right Panel with Action Buttons
1. **Add action buttons section to `_setup_right_panel()`**
   - Create status display section for fight sequence info
   - Add movement actions section with Pile In and Consolidate buttons
   - Implement proper button signal connections
   - Follow established UI layout patterns

2. **Test button functionality in new location**
   - Verify Pile In button responds correctly
   - Verify Consolidate button responds correctly
   - Test button enable/disable states work properly
   - Verify visual layout and spacing

### Task 3: Fix UnitListPanel Visibility
1. **Add explicit FIGHT phase case to refresh_unit_list()**
   - Follow exact pattern from SHOOTING and CHARGE phases
   - Hide unit_list and clear its contents
   - Add appropriate debug logging
   - Test UnitListPanel is properly hidden during fight phase

2. **Verify right panel layout**
   - Ensure fight panel has proper space without UnitListPanel
   - Test scrolling behavior if needed
   - Verify no visual conflicts with hidden unit list

### Task 4: Search for and Remove Redundant Buttons
1. **Search for duplicate "End Fight" buttons**
   - Search codebase for buttons with text "End Fight" (excluding "End Fight Phase")
   - Check FightPhase.gd, FightController.gd, and any UI files
   - Document any redundant buttons found

2. **Remove redundant buttons if found**
   - Remove duplicate button creation code
   - Remove any redundant signal handlers
   - Update references and test functionality
   - Verify no broken functionality from removal

### Task 5: State Management Verification
1. **Test button state management**
   - Verify `_update_ui_state()` works with moved button locations
   - Test all button enable/disable transitions work correctly
   - Verify fight sequence updates work correctly with moved status label

2. **Test fight sequence display**
   - Verify sequence label updates correctly in right panel
   - Test status changes during fight progression
   - Verify visual positioning and readability

### Task 6: Integration Testing
1. **Full fight phase workflow test**
   - Test complete fight sequence from start to finish
   - Verify all UI transitions work smoothly
   - Test edge cases (no fights, completed fights, etc.)

2. **Phase transition testing**
   - Test entering fight phase from charge phase
   - Test exiting fight phase to scoring phase
   - Verify UI cleanup and restoration works correctly
   - Test save/load during fight phase

### Task 7: Performance and Polish
1. **Visual polish**
   - Adjust spacing and sizing to match other phase panels
   - Ensure consistent styling with charge/shooting phases
   - Test with different screen sizes/resolutions

2. **Performance verification**
   - Verify no performance regressions from UI changes
   - Test UI responsiveness during combat
   - Check memory usage patterns remain stable

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
# 1. Start new game and transition to fight phase
# 2. Verify top bar shows ONLY "End Fight Phase" button
# 3. Verify right panel shows fight controls section with:
#    - Fight status display ("No active fights")
#    - Pile In button
#    - Consolidate button
# 4. Verify UnitListPanel is hidden
# 5. Test all fight buttons function correctly
```

#### Button State Testing
```bash
# For each fight button (Pile In, Consolidate):
# 1. Verify button exists in right panel
# 2. Test button enable/disable states during fight sequence
# 3. Verify button responses and game state changes
# 4. Test button interactions work correctly with fight mechanics
```

#### UnitListPanel Visibility Test
```bash
# 1. Enter fight phase
# 2. Verify UnitListPanel is hidden
# 3. Verify refresh_unit_list() doesn't re-show it
# 4. Transition to other phases and back
# 5. Verify consistent UnitListPanel hiding behavior
```

#### Redundant Button Search Test
```bash
# 1. Search UI for any buttons with text "End Fight"
# 2. Verify no duplicate buttons exist
# 3. Test that only "End Fight Phase" button ends the phase
# 4. Verify no broken references to removed buttons
```

#### Phase Transition Test
```bash
# 1. Enter fight phase from charge phase
# 2. Verify UI switches correctly to new layout
# 3. Complete fights or end phase
# 4. Transition to scoring phase
# 5. Verify UI cleanup and restoration works properly
```

### Expected UI Layout

#### Top Bar (HUD_Bottom) - After Implementation
- **Only Element**: "End Fight Phase" button
- **Styling**: Consistent with other simplified phase layouts (shooting, charge)
- **Behavior**: Ends fight phase when clicked

#### Right Panel - After Implementation
```
┌─────────────────────────────────┐
│ Fight Controls                  │
├─────────────────────────────────┤
│ [Unit Selector List]            │
├─────────────────────────────────┤  
│ Melee Attacks:                  │
│ [Attack Tree]                   │
├─────────────────────────────────┤
│ Current Targets:                │
│ [Target Basket]                 │
│ [Clear All] [Fight!]            │
├─────────────────────────────────┤
│ Combat Log:                     │
│ [Dice Log Display]              │
├─────────────────────────────────┤
│ Fight Status:                   │
│ No active fights                │
│ Movement Actions:               │
│ [Pile In] [Consolidate]         │
└─────────────────────────────────┘
```

#### Hidden Elements
- **UnitListPanel**: Not visible during fight phase
- **UnitCard**: Not visible during fight phase (if applicable)
- **Redundant "End Fight" buttons**: Removed entirely

## Quality Assurance

### Acceptance Criteria
- [ ] Top bar contains only "End Fight Phase" button
- [ ] All fight action buttons moved to right panel
- [ ] Fight status display moved to right panel  
- [ ] UnitListPanel hidden during fight phase
- [ ] refresh_unit_list() doesn't re-show UnitListPanel during fight phase
- [ ] All existing button functionality preserved
- [ ] Button enable/disable states work correctly
- [ ] Fight sequence display works correctly in new location
- [ ] Phase transitions work smoothly
- [ ] No visual artifacts or layout issues
- [ ] No redundant "End Fight" buttons exist
- [ ] Performance remains optimal

### Regression Testing
- [ ] All fight phase functionality works as before
- [ ] Combat mechanics (pile in, consolidate, fighting) work correctly
- [ ] Fight sequence management works properly
- [ ] Save/load works correctly with fight phase
- [ ] Button interactions maintain correct game state
- [ ] UI cleanup works properly on phase exit
- [ ] No memory leaks from UI changes
- [ ] No impact on other phase UI layouts

### Edge Case Testing
- [ ] Fight phase with no active combats
- [ ] Multiple units in combat sequence
- [ ] Rapid button clicking doesn't break UI
- [ ] Phase transitions during active fights
- [ ] Invalid game states handle gracefully  
- [ ] UI works with different screen resolutions
- [ ] Scrolling behavior works correctly in right panel
- [ ] Save/load during various fight phase states

## Expected Outcome

**Primary Goal**: Clean, organized fight phase UI consistent with other phases
- Top bar simplified to essential phase control only
- Right panel contains all fight-specific actions and information
- UnitListPanel properly hidden for cleaner interface during fight phase
- Consistent with charge and shooting phase UI patterns

**User Experience Improvements**:
- Less cluttered top bar for better visual clarity
- Logical grouping of fight controls in right panel
- Easier to find and use fight-specific functions
- Consistent interface patterns across all phases
- Improved workflow for combat operations

**Technical Improvements**:
- Better separation of concerns between UI areas
- Consistent UI management patterns across phases
- Cleaner code organization
- Reduced top bar complexity
- Proper UnitListPanel visibility management
- Elimination of redundant buttons

## Risk Assessment

**Low Risk**:
- No game logic changes, only UI reorganization
- Established patterns to follow from charge phase cleanup (Issue #62)
- Clear requirements with specific elements to move
- Well-understood button management system

**Medium Risk**:
- Button state management must work in new locations
- UI layout changes could affect visual appearance  
- Need to ensure all button handlers continue working
- UnitListPanel visibility fix might affect other code

**Mitigation Strategies**:
- Follow exact patterns from successful charge phase cleanup
- Test each component individually before integration
- Maintain comprehensive manual testing checklist
- Implement changes incrementally with validation at each step
- Keep old code available for quick rollback if needed

## Confidence Score: 9/10

**High Confidence Factors**:
- Clear, specific requirements with exact elements to move
- Successful precedent in charge phase cleanup (Issue #62)
- Simple UnitListPanel visibility fix with clear pattern to follow
- No complex game logic changes required
- Comprehensive understanding of current implementation
- Well-defined testing approach
- Low risk of breaking existing functionality

**Minor Risk Factors**:
- Need to verify no redundant buttons exist (search required)
- Visual layout adjustments may require iteration
- Button state management timing needs verification
- UI spacing and sizing may need fine-tuning

This implementation provides a clean, well-organized fight phase UI that follows established patterns while improving user experience through logical grouping of controls and simplified interface layout, consistent with the successful charge phase cleanup approach.