# Product Requirements Document: Movement Phase Controls Enhancement

## Issue Reference
GitHub Issue #51: Movement Phase Controls - Enhanced workflow and status indicators

## Feature Description
Enhance the movement phase controls by adding movement mode confirmation workflow, unit status indicators (Yet to move, Currently Moving, Completed Moving), conditional Fall Back visibility based on engagement range, and dice rolling display for Advance moves. This builds upon the 4-section layout implemented in issue #50.

## Requirements

### 1. Unit Status Indicators
- Display status for each unit in the unit list: "Yet to move", "Currently Moving", "Completed Moving"
- Status should update in real-time as units are selected and moved
- Visual distinction for each status (e.g., prefixes or color coding)

### 2. Movement Mode Confirmation Workflow
- Add "Confirm Movement Mode" button in Section 3 (Movement Mode section)
- Once pressed, lock the movement mode for current unit (cannot change)
- User must complete moving the selected unit before selecting another
- Different behaviors based on selected mode:
  - **Normal**: Allow standard movement up to movement characteristic
  - **Advance**: Roll D6, display result, add to movement allowance
  - **Fall Back**: Allow movement away from engagement
  - **Remain Stationary**: Immediately mark unit as moved

### 3. Conditional Fall Back Visibility
- Fall Back option only visible when selected unit is within engagement range (1")
- Dynamically show/hide based on current unit's engagement status

### 4. Advance Dice Rolling
- When Advance is confirmed, automatically roll D6
- Display dice result in Section 3
- Add rolled value to unit's movement allowance

### 5. Movement Completion Enforcement
- "Confirm Move" button finalizes unit movement
- Marks unit as "Completed Moving" 
- Allows selection of next unmoved unit

## Implementation Context

### Current Architecture (Post Issue #50)
The MovementController.gd already implements a 4-section right panel layout:
- **Section 1**: Unit list with eligible units
- **Section 2**: Selected unit details  
- **Section 3**: Movement mode selection (radio buttons)
- **Section 4**: Action buttons and distance tracking

### Key Files to Modify

#### MovementController.gd
**Location**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd`

**Current State**:
- Lines 240-261: `_create_section1_unit_list()` - Creates unit list
- Lines 263-280: `_create_section2_unit_details()` - Shows selected unit
- Lines 282-327: `_create_section3_mode_selection()` - Radio button mode selection
- Lines 329+: `_create_section4_actions()` - Action buttons and distance display

**Key Methods**:
- `_refresh_unit_list()` (line ~460) - Updates unit list display
- `_on_unit_selected()` - Handles unit selection
- Mode button handlers: `_on_normal_move_pressed()`, `_on_advance_pressed()`, etc.
- `_handle_confirm_move()` - Finalizes unit movement

#### MovementPhase.gd  
**Location**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/MovementPhase.gd`

**Movement State Structure**:
```gdscript
active_moves[unit_id] = {
    "mode": "NORMAL|ADVANCE|FALL_BACK|REMAIN_STATIONARY",
    "mode_locked": false,  # NEW - track if mode is confirmed
    "move_cap_inches": float,
    "advance_roll": 0,     # Store advance dice result
    "model_moves": [],      
    "staged_moves": [],
    "original_positions": {},
    "model_distances": {},
    "dice_rolls": []
}
```

**Key Methods**:
- `begin_unit_move()` - Initiates movement for a unit
- `handle_advance_move()` - Processes advance movement
- `confirm_unit_move()` - Finalizes unit movement
- `_check_engagement_range()` - Determines if unit is engaged

### Existing Patterns to Follow

#### Unit Status Display Pattern (from other phases)
```gdscript
# ShootingController shows targeting status
var status_text = "[TARGETING]" if is_targeting else ""
unit_list.set_item_text(idx, unit_display_name + " " + status_text)
```

#### Dice Rolling Pattern (from ChargePhase)
```gdscript
# Roll dice and emit result
var dice_results = dice_roller.roll_dice(2, 6)
var total = dice_results.reduce(func(a, b): return a + b, 0)
emit_signal("dice_rolled", "Advance", dice_results, total)
```

#### Engagement Range Check (from MovementPhase)
```gdscript
func _is_unit_in_engagement(unit: Node2D) -> bool:
    var engagement_range_px = measurement.inches_to_pixels(1.0)
    for enemy in get_enemy_units():
        if unit.global_position.distance_to(enemy.global_position) <= engagement_range_px:
            return true
    return false
```

#### Button State Management
```gdscript
# Enable/disable buttons based on state
confirm_button.disabled = not has_staged_moves
undo_button.disabled = staged_moves.is_empty()
```

## Implementation Blueprint

### Phase 1: Unit Status Indicators

```gdscript
# MovementController.gd - Enhanced _refresh_unit_list()
func _refresh_unit_list() -> void:
    unit_list.clear()
    
    for unit in eligible_units:
        var unit_id = unit.name
        var status = _get_unit_movement_status(unit_id)
        var status_text = ""
        
        match status:
            "not_moved":
                status_text = "[YET TO MOVE]"
            "moving":
                status_text = "[CURRENTLY MOVING]"
            "completed":
                status_text = "[COMPLETED MOVING]"
        
        var display_name = unit.display_name + " " + status_text
        unit_list.add_item(display_name)
        unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)

func _get_unit_movement_status(unit_id: String) -> String:
    if not phase.active_moves.has(unit_id):
        return "not_moved"
    
    var move_data = phase.active_moves[unit_id]
    if move_data.get("completed", false):
        return "completed"
    elif unit_id == current_unit_id:
        return "moving"
    else:
        return "not_moved"
```

### Phase 2: Movement Mode Confirmation

```gdscript  
# MovementController.gd - Add to _create_section3_mode_selection()
func _create_section3_mode_selection(parent: VBoxContainer) -> void:
    # ... existing radio button creation ...
    
    # Add confirmation button
    confirm_mode_button = Button.new()
    confirm_mode_button.text = "Confirm Movement Mode"
    confirm_mode_button.pressed.connect(_on_confirm_mode_pressed)
    section.add_child(confirm_mode_button)
    
    # Add dice result display (hidden initially)
    advance_roll_label = Label.new()
    advance_roll_label.text = "Advance Roll: -"
    advance_roll_label.visible = false
    section.add_child(advance_roll_label)

func _on_confirm_mode_pressed() -> void:
    if not current_unit_id:
        return
        
    var selected_mode = _get_selected_movement_mode()
    
    # Lock the mode
    emit_signal("move_action_requested", {
        "type": "LOCK_MOVEMENT_MODE",
        "actor_unit_id": current_unit_id,
        "payload": {"mode": selected_mode}
    })
    
    # Handle mode-specific actions
    match selected_mode:
        "ADVANCE":
            _roll_advance_dice()
        "REMAIN_STATIONARY":
            _complete_stationary_move()
            
    # Update UI state
    _update_mode_buttons_state(false)  # Disable mode changes
    confirm_mode_button.disabled = true

func _roll_advance_dice() -> void:
    var dice_result = dice_roller.roll_dice(1, 6)[0]
    advance_roll_label.text = "Advance Roll: %d\"" % dice_result
    advance_roll_label.visible = true
    
    # Update movement cap with advance bonus
    emit_signal("move_action_requested", {
        "type": "SET_ADVANCE_BONUS",
        "actor_unit_id": current_unit_id,
        "payload": {"bonus": dice_result}
    })
```

### Phase 3: Conditional Fall Back Visibility

```gdscript
# MovementController.gd - Update when unit selected
func _on_unit_selected(index: int) -> void:
    # ... existing selection logic ...
    
    _update_fall_back_visibility()

func _update_fall_back_visibility() -> void:
    if not current_unit or not fall_back_radio:
        return
        
    var is_engaged = phase._is_unit_in_engagement(current_unit)
    fall_back_radio.visible = is_engaged
    
    # If not engaged and Fall Back was selected, reset to Normal
    if not is_engaged and fall_back_radio.button_pressed:
        normal_radio.button_pressed = true
```

### Phase 4: Movement Phase Integration

```gdscript
# MovementPhase.gd - Enhanced movement state management
func lock_movement_mode(unit_id: String, mode: String) -> void:
    if active_moves.has(unit_id):
        active_moves[unit_id]["mode_locked"] = true
        active_moves[unit_id]["mode"] = mode
        
        # Signal UI to update
        emit_signal("movement_mode_locked", unit_id, mode)

func set_advance_bonus(unit_id: String, bonus: int) -> void:
    if active_moves.has(unit_id):
        active_moves[unit_id]["advance_roll"] = bonus
        var base_move = _get_unit_movement_stat(unit_id)
        active_moves[unit_id]["move_cap_inches"] = base_move + bonus

func complete_stationary_move(unit_id: String) -> void:
    if not active_moves.has(unit_id):
        active_moves[unit_id] = _create_move_entry(unit_id)
    
    active_moves[unit_id]["mode"] = "REMAIN_STATIONARY"
    active_moves[unit_id]["completed"] = true
    
    # Log the action
    _log_movement_action(unit_id, "remained stationary")
    
    emit_signal("unit_move_confirmed", unit_id, {
        "mode": "REMAIN_STATIONARY",
        "distance": 0
    })
```

### Phase 5: Testing Integration

```gdscript
# test_movement_phase.gd - Add test cases
func test_movement_mode_confirmation():
    var phase = preload("res://phases/MovementPhase.gd").new()
    var unit_id = "test_unit"
    
    # Test mode locking
    phase.begin_unit_move(unit_id, "NORMAL")
    phase.lock_movement_mode(unit_id, "NORMAL")
    
    assert(phase.active_moves[unit_id]["mode_locked"] == true)
    assert(phase.active_moves[unit_id]["mode"] == "NORMAL")
    
func test_advance_dice_bonus():
    var phase = preload("res://phases/MovementPhase.gd").new()
    var unit_id = "test_unit"
    
    phase.begin_unit_move(unit_id, "ADVANCE")
    phase.set_advance_bonus(unit_id, 4)
    
    # Assuming base move of 6"
    assert(phase.active_moves[unit_id]["move_cap_inches"] == 10)
    assert(phase.active_moves[unit_id]["advance_roll"] == 4)

func test_engagement_range_fall_back():
    # Test that Fall Back is only available when engaged
    var controller = preload("res://scripts/MovementController.gd").new()
    controller.current_unit = create_test_unit_at(Vector2(100, 100))
    
    # Create enemy within 1" 
    var enemy = create_test_unit_at(Vector2(125, 100))  # ~25px = ~1"
    
    controller._update_fall_back_visibility()
    assert(controller.fall_back_radio.visible == true)
```

## Task Implementation Order

1. **Add Unit Status Tracking**
   - Modify MovementPhase.gd to track movement completion status
   - Update _refresh_unit_list() in MovementController to show status indicators
   - Add _get_unit_movement_status() helper method

2. **Implement Mode Confirmation Button**
   - Add confirm_mode_button to Section 3 UI
   - Create _on_confirm_mode_pressed() handler
   - Add mode_locked flag to active_moves structure

3. **Add Advance Dice Rolling**
   - Add advance_roll_label to Section 3 (initially hidden)
   - Implement _roll_advance_dice() method
   - Update movement cap with dice bonus

4. **Implement Fall Back Visibility Logic**  
   - Add _update_fall_back_visibility() method
   - Call on unit selection and position changes
   - Hide/show Fall Back radio based on engagement

5. **Add Remain Stationary Handling**
   - Implement complete_stationary_move() in MovementPhase
   - Auto-complete unit when Remain Stationary confirmed

6. **Update Movement Workflow**
   - Enforce mode lock after confirmation
   - Prevent unit switching until current move completed
   - Update button states based on workflow stage

7. **Add Visual Feedback**
   - Update unit list colors/styles for different statuses
   - Show/hide UI elements based on state
   - Add confirmation dialogs where appropriate

8. **Testing & Validation**
   - Run existing movement tests
   - Add new test cases for mode locking
   - Test engagement range detection
   - Validate dice rolling integration

## External Documentation References

- **Warhammer 40k Movement Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Movement-Phase
  - Details on Normal Move, Advance, Fall Back, Remain Stationary
  - Engagement range definition (1")
  - Movement restrictions and requirements

- **Godot UI Controls**: https://docs.godotengine.org/en/4.4/classes/class_button.html
  - Button state management
  - Signal connections
  - Dynamic visibility control

- **Godot ItemList**: https://docs.godotengine.org/en/4.4/classes/class_itemlist.html
  - Item metadata for unit IDs
  - Text formatting and styling
  - Selection handling

## Validation Gates

```bash
# Navigate to project directory
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Export Godot to PATH if needed
export PATH="$HOME/bin:$PATH"

# Run Godot syntax check
godot --check-only

# Run movement phase tests
godot --headless --script res://tests/phases/test_movement_phase.gd

# Run integration tests
godot --headless --script res://tests/integration/test_movement_workflow.gd

# Manual testing checklist:
# 1. Start game, enter movement phase
# 2. Verify unit status indicators show correctly
# 3. Select unit, choose mode, click Confirm
# 4. Verify mode is locked (buttons disabled)
# 5. Test Advance - verify dice roll and bonus
# 6. Test Fall Back - only visible when engaged
# 7. Test Remain Stationary - auto-completes
# 8. Verify cannot switch units mid-move
# 9. Complete move, verify status updates
# 10. Check all units can be moved in sequence
```

## Potential Gotchas

1. **State Synchronization**: Movement state is tracked in MovementPhase but displayed in MovementController - ensure proper signal connections

2. **Engagement Range Calculation**: Must account for model bases and exact positioning - use existing _is_unit_in_engagement() method

3. **UI Element References**: Section reorganization from issue #50 means UI elements may have new parents - verify node paths

4. **Dice Integration**: Dice roller expects specific signal format - follow existing ChargePhase pattern

5. **Save/Load Compatibility**: New fields in active_moves must handle missing keys for backward compatibility

6. **Multi-model Units**: Movement completion must consider all models in unit, not just selected model

## Code Patterns to Follow

```gdscript
# Standard action request pattern
emit_signal("move_action_requested", {
    "type": "ACTION_TYPE",
    "actor_unit_id": unit_id,
    "payload": { /* action data */ }
})

# UI state update pattern  
func _update_ui_state() -> void:
    var has_selection = current_unit != null
    var is_locked = _is_mode_locked()
    
    confirm_mode_button.disabled = not has_selection or is_locked
    # ... update other elements

# Status checking pattern
func _can_perform_action() -> bool:
    if not current_unit_id:
        push_error("No unit selected")
        return false
    if not phase:
        push_error("No phase reference")
        return false
    return true
```

## Quality Score: 8/10

### Strengths:
- Comprehensive research of existing codebase
- Clear implementation blueprint with code examples
- Follows established patterns and conventions
- Includes testing approach and validation gates
- References external documentation

### Areas for Improvement:
- Could benefit from more detailed UI mockups
- Edge case handling could be more explicit

### Confidence Level:
High confidence for one-pass implementation. The existing 4-section layout from issue #50 provides a solid foundation, and the movement phase already has robust state management. The main additions are UI workflow enhancements that follow established patterns.