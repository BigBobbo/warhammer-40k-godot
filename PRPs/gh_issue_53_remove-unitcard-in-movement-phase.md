# Product Requirements Document: Remove UnitCard Creation During Movement Phase

## Issue Reference
GitHub Issue #53: Remove HUD_Right/VBoxContainer/UnitCard

## Feature Description
Remove the display of the legacy UnitCard component during the movement phase, as it creates redundant UI elements that conflict with the new movement-specific UI sections created by MovementController.

## Problem Statement
During the movement phase, both the legacy UnitCard (from Main.tscn/Main.gd) and the new MovementController UI sections are displayed simultaneously in HUD_Right/VBoxContainer, creating:
1. UI redundancy and visual clutter
2. Conflicting button functionality
3. Confusing user experience with duplicate unit information

## Requirements
1. Prevent UnitCard from being shown during movement phase unit selection
2. Maintain UnitCard functionality for other phases (deployment, shooting, etc.)
3. Preserve all movement-specific functionality in MovementController's custom sections
4. Ensure clean transition between phases without UI artifacts

## Implementation Context

### Current Codebase Structure

#### UnitCard Definition
- **Location**: `40k/scenes/Main.tscn` lines 86-117
- **Components**:
  - UnitNameLabel
  - KeywordsLabel 
  - ModelsLabel
  - ButtonContainer with UndoButton, ResetButton, ConfirmButton

#### UnitCard Control Logic
- **File**: `40k/scripts/Main.gd`
- **@onready references**: lines 17-23
- **Key methods**:
  - `show_unit_card()`: line 965 - Makes UnitCard visible
  - `update_movement_card_buttons()`: lines 1004-1044 - Controls visibility during movement
  - `_on_unit_selected()`: line 910, 935 - Triggers UnitCard display

#### MovementController UI Sections
- **File**: `40k/scripts/MovementController.gd`
- **Created in**: `_setup_right_panel()` lines 203-241
- **Sections**:
  - Section1_UnitList: Unit selection with status
  - Section2_UnitDetails: Selected unit information  
  - Section3_ModeSelection: Movement mode buttons
  - Section4_Actions: Movement action buttons and distance info

### Current Flow Analysis

#### Movement Phase Unit Selection Flow
```gdscript
# Main.gd:_on_unit_selected() line 905-922
elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
    movement_controller.active_unit_id = unit_id
    print("Selected unit for movement: ", unit_id)
    # PROBLEM: This shows the old UnitCard
    show_unit_card(unit_id)  # line 910
    update_movement_card_buttons()  # line 911
```

#### UnitCard Visibility Control
```gdscript
# Main.gd:update_movement_card_buttons() lines 1038-1041  
if movement_controller.active_unit_id != "":
    # ... unit info updates ...
    unit_card.visible = true  # line 1038 - PROBLEM: Shows UnitCard
else:
    unit_card.visible = false  # line 1041
```

### MovementController Replacement Functionality

MovementController already provides superior replacement UI:

1. **Section2_UnitDetails** (lines 265-282): Shows unit name and mode
2. **Section4_Actions** (lines 344-396): Contains action buttons (Undo/Reset/Confirm)
3. **Distance tracking**: More detailed than UnitCard's basic labels

### Files to Modify

#### Primary Changes
1. **Main.gd**:
   - `_on_unit_selected()` - Skip `show_unit_card()` call during movement phase
   - `update_movement_card_buttons()` - Prevent UnitCard visibility during movement

#### Verification Files
2. **MovementController.gd**: Ensure complete functionality coverage
3. **Main.tscn**: No changes needed (UnitCard preserved for other phases)

### Documentation References
- **Warhammer Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Documentation**: https://docs.godotengine.org/en/4.4/

## Implementation Blueprint

### Step 1: Modify Unit Selection Logic
```gdscript
# In Main.gd:_on_unit_selected() around line 905
elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
    movement_controller.active_unit_id = unit_id
    print("Selected unit for movement: ", unit_id)
    # REMOVE: show_unit_card(unit_id)  # Don't show legacy card
    # REMOVE: update_movement_card_buttons()  # Don't update legacy card
    # MovementController handles its own UI updates
```

### Step 2: Modify Movement Card Button Logic  
```gdscript  
# In Main.gd:update_movement_card_buttons() around line 1004
func update_movement_card_buttons() -> void:
    if not movement_controller:
        return
    
    # EARLY EXIT: Don't show UnitCard during movement phase
    if current_phase == GameStateData.Phase.MOVEMENT:
        unit_card.visible = false
        return
    
    # ... existing logic for other phases ...
```

### Step 3: Update Phase-Specific UI Logic
```gdscript
# In Main.gd:update_unit_card_buttons() around line 1001
GameStateData.Phase.MOVEMENT:
    # CHANGE: Don't call update_movement_card_buttons()  
    # MovementController manages its own UI
    pass  # or explicit: unit_card.visible = false
```

### Error Handling Strategy
1. **Null checks**: Verify movement_controller exists before accessing
2. **Phase validation**: Ensure current_phase is properly set
3. **State consistency**: Hide UnitCard on phase transitions
4. **Fallback behavior**: If MovementController fails, don't break other phases

### Testing Approach
1. **Movement phase**: Verify UnitCard is hidden, MovementController UI works
2. **Other phases**: Verify UnitCard still appears and functions normally  
3. **Phase transitions**: Ensure clean UI state changes
4. **Unit selection**: Confirm selection works without showing UnitCard
5. **MovementController functionality**: Verify all movement actions work

## Validation Gates
```bash
# Syntax check
export PATH="$HOME/bin:$PATH" && godot --check-only

# Runtime validation
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
export PATH="$HOME/bin:$PATH" && godot --headless --quit-after 3
```

## Implementation Tasks (In Order)

1. **Modify unit selection logic** in `Main.gd:_on_unit_selected()` 
   - Skip `show_unit_card()` call during movement phase
   - Skip `update_movement_card_buttons()` call during movement phase

2. **Update movement card button logic** in `Main.gd:update_movement_card_buttons()`
   - Add early exit for movement phase to hide UnitCard
   - Preserve functionality for other phases

3. **Update phase-specific UI logic** in `Main.gd:update_unit_card_buttons()`
   - Ensure movement phase doesn't trigger UnitCard visibility
   - Consider explicit `unit_card.visible = false` for clarity

4. **Test phase transitions**
   - Verify UnitCard appears/disappears correctly when switching phases
   - Ensure no UI artifacts remain

5. **Verify MovementController functionality**  
   - Confirm all movement actions work without UnitCard
   - Test unit selection, mode selection, and movement execution

## Quality Assurance

### Test Cases
- [ ] Movement phase: UnitCard remains hidden when selecting units
- [ ] Deployment phase: UnitCard appears normally when selecting units  
- [ ] Other phases: UnitCard functions as before
- [ ] Phase transitions: Clean UI state changes
- [ ] Movement actions: All functionality preserved via MovementController

### Edge Cases
- [ ] Rapid phase switching doesn't cause UI glitches
- [ ] Loading saves in movement phase maintains correct UI state
- [ ] MovementController failure doesn't break other phases

## Expected Outcome
- Clean, single-purpose UI during movement phase
- Reduced visual clutter and user confusion
- Preserved functionality across all game phases
- No regression in existing features

## Confidence Score: 9/10
This is a straightforward UI cleanup task with clear requirements, well-understood codebase structure, and simple implementation path. The MovementController already provides all necessary functionality to replace the UnitCard during movement phase.