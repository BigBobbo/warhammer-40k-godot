# Product Requirements Document: Clear Movement Phase UI Entries When Shooting Phase Begins

## Issue Reference
GitHub Issue #54: When the Shooting phase begins, clear all of the movement phase entries in the right hand pannel. Only have the shooting phase specific nodes

## Feature Description
Ensure complete removal of all Movement Phase UI elements from the right-hand panel when transitioning to the Shooting Phase, leaving only shooting-specific UI components visible to prevent UI overlap and confusion.

## Problem Statement
Currently, when transitioning from Movement Phase to Shooting Phase, there may be residual UI elements from the movement phase persisting in the right-hand panel (`/root/Main/HUD_Right/VBoxContainer`), causing:
1. **UI Clutter**: Both movement and shooting elements may be visible simultaneously
2. **User Confusion**: Mixed interface elements from different phases create unclear user experience
3. **Functional Conflicts**: Multiple UI systems trying to control the same panel space
4. **Visual Inconsistency**: Phase-specific UI should be exclusive to each phase

## Requirements
1. **Complete UI Clearing**: All movement phase UI elements must be removed before shooting phase UI appears
2. **Shooting-Only Interface**: Only shooting-specific nodes should be visible during shooting phase
3. **Robust Cleanup**: Cleanup must work reliably across all transition scenarios (manual phase advance, loading saves)
4. **Performance**: UI clearing should be fast and not cause visual glitches
5. **Maintainability**: Solution should be easily extendable to other phase transitions

## Implementation Context

### Current Architecture Analysis

#### Right Panel Structure
- **Container Path**: `/root/Main/HUD_Right/VBoxContainer`
- **Fixed Width**: 400px dedicated right panel in Main.tscn
- **Dynamic Content**: Each phase controller creates its own UI sections

#### Movement Phase UI Elements (Created by MovementController)
From `MovementController.gd:_setup_right_panel()` lines 203-241:
```gdscript
# Four distinct sections created in right panel:
- Section1_UnitList: Units eligible to move with status indicators
- Section2_UnitDetails: Selected unit information and movement mode
- Section3_ModeSelection: Radio buttons for movement types (Normal/Advance/Fall Back)
- Section4_Actions: Action buttons (Undo/Reset/Confirm) and distance tracking
```

#### Shooting Phase UI Elements (Created by ShootingController)
From `ShootingController.gd:_setup_ui()`:
```gdscript
# Single comprehensive panel:
- ShootingPanel: Contains unit selector, weapon assignments, target basket, dice log
```

### Current Cleanup Mechanisms

#### MovementController Cleanup (`_exit_tree()` lines 78-108)
```gdscript
# Cleans up visual elements and UI containers:
- MovementInfo in HUD_Bottom
- MovementButtons in HUD_Bottom  
- MovementActions in HUD_Right (old container)
# NOTE: Does NOT explicitly clean up the 4 sections
```

#### ShootingController Cleanup (`_exit_tree()` lines 48-64)
```gdscript
# Cleans up:
- Visual elements (los_visual, range_visual, target_highlights)
- ShootingControls in HUD_Bottom
- ShootingPanel in HUD_Right
```

#### Main.gd Phase Transition (`_on_phase_changed()` lines 408-416)
```gdscript
# Process:
1. Remove existing controllers (triggers _exit_tree())
2. Wait one frame for cleanup completion
3. Create new phase controller
4. Connect signals and setup UI
```

### Root Cause Analysis

The issue likely stems from:
1. **Incomplete Section Cleanup**: MovementController's `_exit_tree()` doesn't explicitly remove the 4 sections
2. **Timing Issues**: New phase setup may occur before old UI is fully removed
3. **Container State**: VBoxContainer may retain child nodes between phase transitions

### Files Requiring Modification

#### Primary Changes
1. **MovementController.gd**: Enhance `_exit_tree()` to explicitly remove all 4 sections
2. **ShootingController.gd**: Add proactive cleanup before creating shooting UI  
3. **Main.gd**: Add explicit right panel clearing during phase transitions (optional defensive measure)

#### Verification Files
- **Main.tscn**: Right panel structure (no changes needed)
- **PhaseManager.gd**: Phase transition logic (understanding context)

### Documentation References
- **Warhammer Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Documentation**: https://docs.godotengine.org/en/4.4/
- **Godot UI Management**: https://docs.godotengine.org/en/4.4/classes/class_control.html
- **Godot Node Lifecycle**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/nodes_and_scenes.html

## Implementation Blueprint

### Strategy Overview
Implement a multi-layered cleanup approach:
1. **Enhanced MovementController Cleanup**: Explicit removal of all movement sections
2. **Proactive ShootingController Setup**: Clear any residual UI before creating shooting interface
3. **Defensive Main.gd Cleanup**: Optional failsafe for phase transitions

### Step 1: Enhanced MovementController Cleanup

#### Location: `MovementController.gd:_exit_tree()` around line 105
```gdscript
func _exit_tree() -> void:
    # Existing cleanup code for visuals...
    
    # ENHANCEMENT: Explicitly clean up all 4 movement sections
    var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
    if container and is_instance_valid(container):
        # Remove all movement-specific sections
        for section_name in ["Section1_UnitList", "Section2_UnitDetails", 
                            "Section3_ModeSelection", "Section4_Actions"]:
            var section = container.get_node_or_null(section_name)
            if section and is_instance_valid(section):
                print("MovementController: Cleaning up section: ", section_name)
                container.remove_child(section)
                section.queue_free()
    
    # Existing cleanup code for bottom HUD...
```

### Step 2: Proactive ShootingController Cleanup  

#### Location: `ShootingController.gd` - Enhance `_cleanup_existing_ui()` around line 621
```gdscript
func _cleanup_existing_ui() -> void:
    # Existing cleanup code...
    
    # ENHANCEMENT: Proactively clear any movement phase residuals
    if hud_right:
        var container = hud_right.get_node_or_null("VBoxContainer")
        if container:
            # Clear any remaining movement sections
            for section_name in ["Section1_UnitList", "Section2_UnitDetails", 
                                "Section3_ModeSelection", "Section4_Actions"]:
                var section = container.get_node_or_null(section_name)
                if section:
                    print("ShootingController: Cleaning up residual movement section: ", section_name)
                    container.remove_child(section)
                    section.queue_free()
            
            # Clear any other non-shooting UI elements
            var existing_panel = container.get_node_or_null("ShootingPanel")
            if existing_panel:
                existing_panel.queue_free()
```

### Step 3: Defensive Phase Transition Cleanup (Optional)

#### Location: `Main.gd` - New method called during phase transitions
```gdscript
func _clear_right_panel_ui() -> void:
    """Defensive cleanup to ensure right panel is completely clear"""
    var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
    if not container:
        return
    
    # Get list of all children before removal to avoid iteration issues
    var children_to_remove = []
    for child in container.get_children():
        # Skip static elements that should persist (if any)
        if child.name not in ["StaticElement1", "StaticElement2"]:  # Adjust as needed
            children_to_remove.append(child)
    
    # Remove all dynamic UI elements
    for child in children_to_remove:
        print("Main: Clearing right panel element: ", child.name)
        container.remove_child(child) 
        child.queue_free()

# Call this in _on_phase_changed() after line 415
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
    current_phase = new_phase
    print("Phase changed to: ", GameStateData.Phase.keys()[new_phase])
    
    # ENHANCEMENT: Defensive UI cleanup
    _clear_right_panel_ui()
    
    # Wait additional frame to ensure cleanup completion
    await get_tree().process_frame
    
    # Existing controller setup logic...
```

### Error Handling Strategy
1. **Null Safety**: Check node validity before operations using `get_node_or_null()` and `is_instance_valid()`
2. **Graceful Degradation**: If cleanup fails, log warnings but continue with phase setup
3. **Double-Frame Wait**: Ensure sufficient time for node removal before creating new UI
4. **Debug Logging**: Extensive logging for troubleshooting UI cleanup issues

### Testing Approach

#### Manual Testing Scenarios
1. **Normal Transition**: Movement → Shooting phase via "End Movement" button
2. **Save/Load**: Load save file during shooting phase, verify no movement UI persists
3. **Rapid Transitions**: Quick phase changes to test cleanup timing
4. **Multiple Cycles**: Movement → Shooting → Movement → Shooting to test recurring cleanup

#### Visual Validation Points
- Right panel shows only shooting UI elements during shooting phase
- No movement-specific buttons, labels, or sections visible
- Shooting UI functions correctly without interference
- Clean visual transitions without flickering or artifacts

#### Functional Testing
- Shooting phase functionality works correctly
- Target selection, weapon assignment, dice rolling all function
- No conflicting event handlers from movement phase
- UI responsiveness maintained

## Validation Gates

### Syntax & Runtime Checks
```bash
# Godot syntax validation
export PATH="$HOME/bin:$PATH" && godot --check-only

# Runtime validation  
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
export PATH="$HOME/bin:$PATH" && godot --headless --quit-after 3
```

### Manual Testing Checklist
```bash
# Phase Transition Test
# 1. Start new game
# 2. Complete deployment phase
# 3. During movement phase, verify 4 sections are visible
# 4. End movement phase
# 5. Verify only shooting UI is visible in right panel
# 6. No movement sections should remain
```

## Implementation Tasks (In Order)

### Phase 1: Core Cleanup Enhancement
1. **Enhance MovementController._exit_tree()** in `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd`
   - Add explicit cleanup of all 4 movement sections
   - Test cleanup occurs during phase transitions
   - Verify no errors when sections don't exist

2. **Enhance ShootingController._cleanup_existing_ui()** in `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ShootingController.gd`
   - Add proactive cleanup of movement phase residuals
   - Ensure cleanup occurs before creating shooting UI
   - Test handles cases where no residual UI exists

### Phase 2: Testing & Validation
3. **Test basic phase transitions**
   - Movement → Shooting phase transition
   - Verify complete UI clearing occurs
   - Check for any visual artifacts or timing issues

4. **Test edge cases**
   - Save/load during different phases
   - Rapid phase transitions
   - Multiple transition cycles

### Phase 3: Defensive Measures (If Needed)
5. **Implement Main.gd defensive cleanup** (only if issues persist)
   - Add `_clear_right_panel_ui()` method
   - Call during phase transitions
   - Test doesn't break existing functionality

6. **Performance validation**
   - Ensure UI clearing doesn't cause frame drops
   - Verify smooth visual transitions
   - Test memory cleanup is working properly

## Quality Assurance

### Acceptance Criteria
- [ ] Shooting phase UI is exclusive - no movement elements visible
- [ ] Phase transitions are visually clean without artifacts  
- [ ] All movement phase sections (1-4) are completely removed
- [ ] Shooting functionality remains unaffected
- [ ] Solution works across save/load scenarios
- [ ] No console errors during cleanup process

### Edge Cases Coverage
- [ ] Transitioning with unsaved movement data
- [ ] Loading saves during different phases
- [ ] Multiple rapid phase transitions
- [ ] Error conditions (missing nodes, invalid states)
- [ ] Performance under stress (multiple units, complex UI state)

### Regression Testing
- [ ] Movement phase functionality unaffected
- [ ] Other phase transitions still work correctly
- [ ] Deployment and Fight phases not impacted
- [ ] Save/load system maintains compatibility
- [ ] Overall game performance maintained

## Expected Outcome

**Primary Goal**: Crystal clear phase-specific UI transitions
- **Movement Phase**: Shows 4-section movement interface exclusively
- **Shooting Phase**: Shows shooting panel exclusively  
- **Transition**: Clean, instant switch with no UI overlap

**Secondary Benefits**:
- **Reduced Visual Confusion**: Users see only relevant controls
- **Improved Performance**: Less UI node overhead
- **Better Maintainability**: Clear separation of phase UI responsibilities
- **Enhanced User Experience**: Professional, polished interface behavior

## Risk Assessment

**Low Risk Factors**:
- Well-understood codebase architecture
- Existing cleanup patterns to follow
- Clear node hierarchy and naming conventions

**Potential Issues**:
- **Timing Dependencies**: UI creation/destruction timing
- **Save/Load Compatibility**: Ensuring UI state restoration works
- **Performance**: Multiple node operations per frame

**Mitigation Strategies**:
- Multi-layered cleanup approach (primary + defensive)
- Extensive null checking and validation
- Frame-delayed operations for proper sequencing

## Confidence Score: 8/10

**High Confidence Factors**:
- Clear understanding of the issue and current architecture
- Well-defined UI node structure and naming conventions  
- Existing cleanup patterns provide solid foundation
- Multiple implementation layers provide redundancy

**Moderate Risk Factors**:
- Potential timing issues in UI cleanup/creation
- Need to ensure compatibility across all transition scenarios
- Save/load state management complexity

This is a straightforward UI cleanup task with a well-understood problem and clear implementation path. The multi-layered approach ensures robust cleanup while maintaining system stability.