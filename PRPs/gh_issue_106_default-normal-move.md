# PRP: Default to Normal Move Without Requiring Mode Selection

## Issue Context
**Problem**: When moving a unit during the Movement Phase, players feel they are required to explicitly select a movement type (Normal Move, Advance, Remain Stationary) before they can move their models. The current UI has a "Confirm Movement Mode" button that creates confusion about whether movement mode selection is mandatory.

**User Request**: "Assume that they have selected normal move if nothing is chosen. They should still be able to select 'Advance' or 'Remain Stationary' but if they do not select them before dragging their models in the selected unit assume that a normal move was chosen."

**Impact**:
- Players may feel blocked from moving units until they understand the mode selection UI
- The "Confirm Movement Mode" button creates an unnecessary step for the default case (Normal Move)
- Workflow is slower than necessary for the most common movement type

## Research Findings

### Current Implementation Analysis

**Movement Controller Workflow** (`40k/scripts/MovementController.gd`):

1. **Unit Selection** (lines 551-630):
   ```gdscript
   func _on_unit_selected(index: int) -> void:
       # Line 608-615: Automatically sends BEGIN_NORMAL_MOVE
       var action = {
           "type": "BEGIN_NORMAL_MOVE",
           "actor_unit_id": unit_id
       }
       emit_signal("move_action_requested", action)

       # Lines 622-624: Sets normal radio to selected
       if normal_radio:
           normal_radio.button_pressed = true
   ```
   - ✓ Normal move IS already the default
   - ✓ BEGIN_NORMAL_MOVE is automatically sent when unit is selected
   - ✓ Normal radio button is pre-selected

2. **Mode Selection UI** (lines 320-378):
   ```gdscript
   # Lines 336-362: Radio buttons for mode selection
   normal_radio = CheckBox.new()
   normal_radio.pressed.connect(_on_normal_move_pressed)

   advance_radio = CheckBox.new()
   advance_radio.pressed.connect(_on_advance_pressed)

   stationary_radio = CheckBox.new()
   stationary_radio.pressed.connect(_on_remain_stationary_pressed)

   # Lines 367-370: "Confirm Movement Mode" button
   confirm_mode_button = Button.new()
   confirm_mode_button.text = "Confirm Movement Mode"
   confirm_mode_button.pressed.connect(_on_confirm_mode_pressed)
   ```

3. **Radio Button Handlers** (lines 652-705):
   ```gdscript
   # Lines 652-669: Normal move handler
   func _on_normal_move_pressed() -> void:
       var action = {"type": "BEGIN_NORMAL_MOVE", ...}
       emit_signal("move_action_requested", action)

   # Lines 671-683: Advance handler
   func _on_advance_pressed() -> void:
       var action = {"type": "BEGIN_ADVANCE", ...}
       emit_signal("move_action_requested", action)

   # Lines 696-705: Remain stationary handler
   func _on_remain_stationary_pressed() -> void:
       var action = {"type": "REMAIN_STATIONARY", ...}
       emit_signal("move_action_requested", action)
   ```
   - ⚠️ Radio button .pressed signal fires when button is toggled
   - ⚠️ This includes programmatic toggles (button_pressed = true)
   - ⚠️ Could cause duplicate BEGIN_NORMAL_MOVE actions

4. **"Confirm Movement Mode" Button** (lines 747-772):
   ```gdscript
   func _on_confirm_mode_pressed() -> void:
       # Locks the mode
       emit_signal("move_action_requested", {
           "type": "LOCK_MOVEMENT_MODE",
           "actor_unit_id": active_unit_id,
           "payload": {"mode": selected_mode}
       })

       # Special handling for Advance and Stationary
       match selected_mode:
           "ADVANCE":
               _roll_advance_dice()  # Rolls D6, sets advance bonus
           "REMAIN_STATIONARY":
               _complete_stationary_move()  # Immediately completes

       # Disable mode buttons
       _update_mode_buttons_state(false)
       confirm_mode_button.disabled = true
   ```
   - Serves two purposes:
     1. Locks the mode (prevents changing)
     2. Triggers mode-specific actions (dice roll for Advance)

5. **Model Dragging** (lines 1100-1249):
   - No checks for mode_locked status
   - ✓ Models can be dragged immediately after unit selection
   - Uses active_moves[unit_id] data which is created by BEGIN_NORMAL_MOVE

### Root Cause of Confusion

**The Problem**:
1. Normal Move works fine automatically
2. BUT: For Advance, players need to:
   - Click Advance radio button (sends BEGIN_ADVANCE)
   - Click "Confirm Movement Mode" to roll dice and get movement bonus
   - Without the dice roll, movement cap isn't updated
3. The "Confirm Movement Mode" button suggests it's REQUIRED for all modes
4. Players don't realize they can drag models immediately for Normal Move

**Why "Confirm" Button Exists**:
- For Advance: Need to roll D6 and calculate total movement (M + D6)
- For Remain Stationary: Immediately complete the move (no dragging)
- For Normal/Fall Back: Not actually needed

### Warhammer 40K Movement Rules

From https://wahapedia.ru/wh40k10ed/the-rules/core-rules/:

**Normal Move**:
- Default movement type
- Models can move up to their Movement characteristic (M)
- No restrictions on shooting or charging afterward

**Advance**:
- Opt-in movement type
- Models move M + D6 inches
- Cannot shoot (except Assault weapons) or charge afterward
- Requires dice roll at the time of selection

**Remain Stationary**:
- Opt-in choice
- Models don't move
- Some weapons benefit from standing still (Heavy weapons)
- Immediately completes the unit's movement

**Fall Back**:
- Only available when engaged with enemy
- Move away from engagement range
- Cannot shoot or charge afterward

### Existing Patterns in Codebase

**Similar UI Pattern - Deployment Phase** (`40k/scripts/DeploymentController.gd`):
- Formation selection (Single, Spread, Tight) has radio buttons
- No "Confirm" button needed
- Selecting a formation radio immediately enables that formation
- Models can be placed right away

**Phase Action Pattern** (`40k/scripts/Main.gd`):
- Most phases have a single "End Phase" action button
- Actions are triggered immediately when clicked
- No "confirm your action type" step

## Implementation Blueprint

### Design Decisions

**Primary Goals**:
1. Remove UI confusion about whether mode selection is required
2. Make Normal Move the obvious default (already is internally, but unclear in UI)
3. Streamline Advance workflow to automatically roll dice when selected
4. Keep "Confirm Movement Mode" only visible when actually needed
5. Allow players to drag models immediately after selecting a unit

**Approach**: Auto-trigger Mode Actions + Hide Unnecessary Confirmation

**Key Changes**:
1. When Advance radio is clicked → Automatically trigger BEGIN_ADVANCE and roll dice
2. When Stationary radio is clicked → Automatically trigger REMAIN_STATIONARY and complete
3. Hide "Confirm Movement Mode" button for Normal Move (not needed)
4. Show "Confirm Movement Mode" only for modes that need it (currently none after our changes)
5. Prevent duplicate action triggers when programmatically setting radio buttons

### Phase 1: Auto-trigger Advance Dice Roll

Currently, selecting Advance radio button sends BEGIN_ADVANCE, but doesn't roll the dice. The dice are only rolled when "Confirm Movement Mode" is clicked.

**Goal**: Make clicking "Advance" immediately roll the D6 and update movement cap.

#### File: `40k/scripts/MovementController.gd` (MODIFY)

**Lines 671-683 - Modify _on_advance_pressed():**

Replace:
```gdscript
func _on_advance_pressed() -> void:
	print("Advance button pressed for unit: ", active_unit_id)
	if active_unit_id == "":
		print("No unit selected for advance!")
		return

	var action = {
		"type": "BEGIN_ADVANCE",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	print("Emitting advance action: ", action)
	emit_signal("move_action_requested", action)
```

With:
```gdscript
func _on_advance_pressed() -> void:
	print("Advance button pressed for unit: ", active_unit_id)
	if active_unit_id == "":
		print("No unit selected for advance!")
		return

	# Send BEGIN_ADVANCE action
	var action = {
		"type": "BEGIN_ADVANCE",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	print("Emitting advance action: ", action)
	emit_signal("move_action_requested", action)

	# Automatically roll the advance dice
	# This used to require clicking "Confirm Movement Mode"
	_roll_advance_dice()
```

**Rationale**:
- Combines the radio button click with dice roll
- Eliminates need for "Confirm Movement Mode" button for Advance
- Makes the workflow: Select unit → Click Advance → Drag models
- Dice result is shown immediately in the UI (advance_roll_label)

### Phase 2: Auto-trigger Remain Stationary

Currently, selecting Stationary radio doesn't complete the move - user must click "Confirm Movement Mode".

**Goal**: Make clicking "Remain Stationary" immediately complete the unit's movement.

#### File: `40k/scripts/MovementController.gd` (MODIFY)

**Lines 696-705 - Modify _on_remain_stationary_pressed():**

Replace:
```gdscript
func _on_remain_stationary_pressed() -> void:
	if active_unit_id == "":
		return

	var action = {
		"type": "REMAIN_STATIONARY",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)
```

With:
```gdscript
func _on_remain_stationary_pressed() -> void:
	if active_unit_id == "":
		return

	# Send REMAIN_STATIONARY action
	var action = {
		"type": "REMAIN_STATIONARY",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

	# Mark as completed immediately (no dragging needed)
	# Clear active unit since this unit is done
	active_unit_id = ""
	_update_selected_unit_display()

	# Refresh unit list to show this unit as moved
	if unit_list:
		_populate_unit_list()
```

**Rationale**:
- Remain Stationary means "don't move" - there's no model dragging needed
- Completing immediately makes sense
- Clears the active unit so player can select the next unit
- Unit list updates to show the unit has completed movement

### Phase 3: Prevent Duplicate Actions on Programmatic Radio Button Changes

When a unit is selected, the code sets `normal_radio.button_pressed = true` (line 624). If this triggers the `.pressed` signal, it would send a duplicate BEGIN_NORMAL_MOVE action (one from _on_unit_selected, one from _on_normal_move_pressed).

**Goal**: Prevent radio button signal handlers from triggering when programmatically setting the button state.

#### File: `40k/scripts/MovementController.gd` (MODIFY)

**Add flag to track programmatic changes** (after line 67):

```gdscript
# Flag to prevent duplicate actions when programmatically setting radio buttons
var setting_radio_programmatically: bool = false
```

**Lines 652-669 - Add guard to _on_normal_move_pressed():**

Replace:
```gdscript
func _on_normal_move_pressed() -> void:
	print("Normal move button pressed for unit: ", active_unit_id)
	if active_unit_id == "":
		# ...
```

With:
```gdscript
func _on_normal_move_pressed() -> void:
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

	print("Normal move button pressed for unit: ", active_unit_id)
	if active_unit_id == "":
		# ...
```

**Similar changes for _on_advance_pressed() and _on_remain_stationary_pressed()**:

Add the same guard at the start of each function:
```gdscript
if setting_radio_programmatically:
	return
```

**Lines 622-624 - Wrap radio button setting in _on_unit_selected():**

Replace:
```gdscript
		# Set normal mode as selected
		if normal_radio:
			normal_radio.button_pressed = true
```

With:
```gdscript
		# Set normal mode as selected (programmatically, don't trigger signal)
		if normal_radio:
			setting_radio_programmatically = true
			normal_radio.button_pressed = true
			setting_radio_programmatically = false
```

**Similar change in _reset_mode_selection_for_new_unit()** (lines 879-882):

Wrap the radio button setting:
```gdscript
		# Reset to default (Normal) selection
		active_mode = "NORMAL"  # Set mode variable
		if normal_radio:
			setting_radio_programmatically = true
			normal_radio.button_pressed = true
			setting_radio_programmatically = false
```

**Rationale**:
- Prevents duplicate BEGIN_NORMAL_MOVE actions
- Only user clicks on radio buttons trigger the handlers
- Programmatic state changes (like default selection) don't trigger actions

### Phase 4: Hide "Confirm Movement Mode" Button

Since mode actions now trigger automatically when radio buttons are clicked, the "Confirm Movement Mode" button is no longer needed.

**Goal**: Remove the confusing "Confirm" button from the UI.

#### File: `40k/scripts/MovementController.gd` (MODIFY)

**Lines 367-370 - Remove button creation in _create_section3_mode_selection():**

Delete these lines:
```gdscript
	# Add confirmation button
	confirm_mode_button = Button.new()
	confirm_mode_button.text = "Confirm Movement Mode"
	confirm_mode_button.pressed.connect(_on_confirm_mode_pressed)
	section.add_child(confirm_mode_button)
```

**Lines 747-772 - Keep _on_confirm_mode_pressed() but make it unused:**

Comment out or mark as deprecated:
```gdscript
# DEPRECATED: Mode confirmation now happens automatically when radio buttons are clicked
# func _on_confirm_mode_pressed() -> void:
#     ...
```

Or simply leave it in case we need it for testing, but it won't be called since the button isn't created.

**Lines 852-854, 876-877 - Remove confirm button references:**

In `_reset_mode_selection_for_new_unit()`, delete:
```gdscript
		if confirm_mode_button:
			confirm_mode_button.disabled = true
```

And:
```gdscript
		if confirm_mode_button:
			confirm_mode_button.disabled = false
```

**Rationale**:
- Button serves no purpose after automatic triggering
- Removing it simplifies the UI
- Eliminates confusion about whether confirmation is required

### Phase 5: Update UI Text to Clarify Normal Move is Default

**Goal**: Make it obvious to players that Normal Move is selected by default and they can drag models immediately.

#### File: `40k/scripts/MovementController.gd` (MODIFY)

**Lines 301-318 - Update section 2 labels:**

Replace:
```gdscript
func _create_section2_unit_details(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()
	section.name = "Section2_UnitDetails"

	var label = Label.new()
	label.text = "Selected Unit Details"
	label.add_theme_font_size_override("font_size", 14)
	section.add_child(label)

	selected_unit_label = Label.new()
	selected_unit_label.text = "Unit: None Selected"
	section.add_child(selected_unit_label)

	unit_mode_label = Label.new()
	unit_mode_label.text = "Mode: -"
	section.add_child(unit_mode_label)

	parent.add_child(section)
```

With:
```gdscript
func _create_section2_unit_details(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()
	section.name = "Section2_UnitDetails"

	var label = Label.new()
	label.text = "Selected Unit Details"
	label.add_theme_font_size_override("font_size", 14)
	section.add_child(label)

	selected_unit_label = Label.new()
	selected_unit_label.text = "Unit: None Selected"
	section.add_child(selected_unit_label)

	unit_mode_label = Label.new()
	unit_mode_label.text = "Mode: Normal Move (Default)"
	section.add_child(unit_mode_label)

	# Add helpful hint
	var hint_label = Label.new()
	hint_label.text = "Drag models to move, or select a different mode below"
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.modulate = Color(0.7, 0.7, 0.7)  # Slightly dimmed hint text
	section.add_child(hint_label)

	parent.add_child(section)
```

**Lines 449-460 - Update _update_selected_unit_display():**

Replace:
```gdscript
	if unit_mode_label:
		var mode_text = "Mode: " + active_mode if active_mode != "" else "Mode: -"
		unit_mode_label.text = mode_text
```

With:
```gdscript
	if unit_mode_label:
		var mode_text = "Mode: "
		if active_mode == "NORMAL" or active_mode == "":
			mode_text += "Normal Move (Default)"
		elif active_mode == "ADVANCE":
			mode_text += "Advance"
		elif active_mode == "FALL_BACK":
			mode_text += "Fall Back"
		elif active_mode == "REMAIN_STATIONARY":
			mode_text += "Remain Stationary"
		else:
			mode_text += active_mode
		unit_mode_label.text = mode_text
```

**Rationale**:
- Makes it explicit that Normal Move is the default
- Adds a hint that players can drag models immediately
- Reduces confusion about what to do after selecting a unit

## Implementation Tasks

Execute these tasks in order:

### Task 1: Add Programmatic Flag for Radio Buttons
- [ ] Open `40k/scripts/MovementController.gd`
- [ ] After line 67 (after `advance_roll_label` declaration), add new flag:
  ```gdscript
  var setting_radio_programmatically: bool = false
  ```
- [ ] Save file

### Task 2: Prevent Duplicate Actions - Normal Move Handler
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_on_normal_move_pressed()` function (line 652)
- [ ] At the start of the function, add guard:
  ```gdscript
  # Ignore if we're setting the radio programmatically
  if setting_radio_programmatically:
      return
  ```
- [ ] Save file

### Task 3: Prevent Duplicate Actions - Advance Handler
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_on_advance_pressed()` function (line 671)
- [ ] At the start of the function, add guard:
  ```gdscript
  if setting_radio_programmatically:
      return
  ```
- [ ] Save file

### Task 4: Prevent Duplicate Actions - Stationary Handler
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_on_remain_stationary_pressed()` function (line 696)
- [ ] At the start of the function, add guard:
  ```gdscript
  if setting_radio_programmatically:
      return
  ```
- [ ] Save file

### Task 5: Prevent Duplicate Actions - Fall Back Handler
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_on_fall_back_pressed()` function (line 685)
- [ ] At the start of the function, add guard:
  ```gdscript
  if setting_radio_programmatically:
      return
  ```
- [ ] Save file

### Task 6: Wrap Programmatic Radio Button Setting - Unit Selection
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find lines 622-624 in `_on_unit_selected()` function
- [ ] Replace radio button setting with wrapped version:
  ```gdscript
  # Set normal mode as selected (programmatically, don't trigger signal)
  if normal_radio:
      setting_radio_programmatically = true
      normal_radio.button_pressed = true
      setting_radio_programmatically = false
  ```
- [ ] Save file

### Task 7: Wrap Programmatic Radio Button Setting - Mode Reset
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find lines 879-882 in `_reset_mode_selection_for_new_unit()` function
- [ ] Replace radio button setting with wrapped version:
  ```gdscript
  # Reset to default (Normal) selection
  active_mode = "NORMAL"  # Set mode variable
  if normal_radio:
      setting_radio_programmatically = true
      normal_radio.button_pressed = true
      setting_radio_programmatically = false
  ```
- [ ] Save file

### Task 8: Auto-trigger Advance Dice Roll
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_on_advance_pressed()` function (line 671)
- [ ] After the `emit_signal("move_action_requested", action)` line, add:
  ```gdscript
  # Automatically roll the advance dice
  # This used to require clicking "Confirm Movement Mode"
  call_deferred("_roll_advance_dice")
  ```
- [ ] Use `call_deferred` to ensure the BEGIN_ADVANCE action is processed first
- [ ] Save file

### Task 9: Auto-trigger Remain Stationary Completion
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_on_remain_stationary_pressed()` function (line 696)
- [ ] After the `emit_signal("move_action_requested", action)` line, add:
  ```gdscript
  # Mark as completed immediately (no dragging needed)
  # Clear active unit since this unit is done
  active_unit_id = ""
  call_deferred("_update_selected_unit_display")

  # Refresh unit list to show this unit as moved
  if unit_list:
      call_deferred("_populate_unit_list")
  ```
- [ ] Use `call_deferred` to ensure the REMAIN_STATIONARY action is processed first
- [ ] Save file

### Task 10: Remove "Confirm Movement Mode" Button
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_create_section3_mode_selection()` function (line 320)
- [ ] Find and delete lines 367-370 (button creation):
  ```gdscript
  # Add confirmation button
  confirm_mode_button = Button.new()
  confirm_mode_button.text = "Confirm Movement Mode"
  confirm_mode_button.pressed.connect(_on_confirm_mode_pressed)
  section.add_child(confirm_mode_button)
  ```
- [ ] Save file

### Task 11: Remove Confirm Button References
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_reset_mode_selection_for_new_unit()` function (line 844)
- [ ] Delete confirm button references (around lines 852-854 and 876-877):
  ```gdscript
  if confirm_mode_button:
      confirm_mode_button.disabled = true
  ```
  and
  ```gdscript
  if confirm_mode_button:
      confirm_mode_button.disabled = false
  ```
- [ ] Save file

### Task 12: Update UI Text - Section 2 Details
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_create_section2_unit_details()` function (line 301)
- [ ] Replace default unit_mode_label text from `"Mode: -"` to:
  ```gdscript
  unit_mode_label.text = "Mode: Normal Move (Default)"
  ```
- [ ] After `section.add_child(unit_mode_label)`, add hint label:
  ```gdscript
  # Add helpful hint
  var hint_label = Label.new()
  hint_label.text = "Drag models to move, or select a different mode below"
  hint_label.add_theme_font_size_override("font_size", 11)
  hint_label.modulate = Color(0.7, 0.7, 0.7)  # Slightly dimmed hint text
  section.add_child(hint_label)
  ```
- [ ] Save file

### Task 13: Update UI Text - Mode Display
- [ ] In `40k/scripts/MovementController.gd`
- [ ] Find `_update_selected_unit_display()` function (line 449)
- [ ] Replace the unit_mode_label update logic (around lines 458-460) with:
  ```gdscript
  if unit_mode_label:
      var mode_text = "Mode: "
      if active_mode == "NORMAL" or active_mode == "":
          mode_text += "Normal Move (Default)"
      elif active_mode == "ADVANCE":
          mode_text += "Advance"
      elif active_mode == "FALL_BACK":
          mode_text += "Fall Back"
      elif active_mode == "REMAIN_STATIONARY":
          mode_text += "Remain Stationary"
      else:
          mode_text += active_mode
      unit_mode_label.text = mode_text
  ```
- [ ] Save file

### Task 14: Manual Testing - Default Normal Move Workflow
- [ ] Run game: `godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k`
- [ ] Load armies and enter Movement phase
- [ ] Select a unit from the list
- [ ] Expected: Normal Move radio is selected, mode label shows "Mode: Normal Move (Default)"
- [ ] Expected: Hint text says "Drag models to move, or select a different mode below"
- [ ] Expected: No "Confirm Movement Mode" button visible
- [ ] Drag a model without clicking anything
- [ ] Expected: Model moves successfully
- [ ] Verify movement cap shown correctly (M = unit's Movement stat)

### Task 15: Manual Testing - Advance Workflow
- [ ] Select a unit from the list
- [ ] Click "Advance" radio button
- [ ] Expected: Dice automatically rolls (D6)
- [ ] Expected: advance_roll_label shows result (e.g., "Advance Roll: 4\"")
- [ ] Expected: Movement cap updates to M + D6
- [ ] Drag a model
- [ ] Expected: Can move up to M + D6 inches
- [ ] Expected: Unit marked as "Advanced" (cannot shoot/charge later)

### Task 16: Manual Testing - Remain Stationary Workflow
- [ ] Select a unit from the list
- [ ] Click "Remain Stationary" radio button
- [ ] Expected: Unit immediately completes movement
- [ ] Expected: Unit is deselected (active_unit_id cleared)
- [ ] Expected: Unit list updates to show unit as moved
- [ ] Expected: Unit marked as "Remained Stationary"
- [ ] Expected: Cannot drag models (unit is done)

### Task 17: Manual Testing - Fall Back Workflow
- [ ] Deploy units in Engagement Range of enemy
- [ ] Select an engaged unit
- [ ] Expected: Fall Back radio button is visible
- [ ] Click "Fall Back" radio button
- [ ] Expected: Can move models away from enemy
- [ ] Expected: Movement validation prevents ending in ER

### Task 18: Manual Testing - Mode Switching
- [ ] Select a unit
- [ ] Click "Advance" (dice rolls)
- [ ] Click "Normal Move" radio again
- [ ] Expected: Movement cap resets to M (no advance bonus)
- [ ] Expected: No errors or duplicate actions
- [ ] Drag a model
- [ ] Expected: Moves with normal cap

## Validation Gates

All validation commands must pass:

```bash
# 1. Set Godot path
export PATH="$HOME/bin:$PATH"

# 2. Syntax check - ensure code compiles
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --headless --path . --check-only

# Expected: No syntax errors

# 3. Run movement phase tests
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/phases/test_movement_phase.gd \
  -glog=1 \
  -gexit

# Expected: All tests pass

# 4. Run UI interaction tests
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/ui/test_ui_interactions.gd \
  -glog=1 \
  -gexit

# Expected: All tests pass

# 5. Manual integration test - Normal Move Default
# Run game and verify normal move is automatic
godot --path . &
# In game:
# - Load armies, enter Movement phase
# - Select unit
# - Verify "Normal Move (Default)" shown
# - Verify hint text present
# - Verify no "Confirm" button
# - Drag model without clicking anything
# - Verify move succeeds
kill %1

# 6. Manual integration test - Advance Auto-dice
# Run game and verify advance automatically rolls
godot --path . &
# In game:
# - Select unit
# - Click "Advance" radio
# - Verify dice rolls immediately
# - Verify movement cap updated
# - Drag model with new cap
kill %1

# 7. Manual integration test - Stationary Auto-complete
# Run game and verify stationary completes immediately
godot --path . &
# In game:
# - Select unit
# - Click "Remain Stationary" radio
# - Verify unit deselects immediately
# - Verify unit list shows as moved
kill %1

# 8. Check debug logs for errors
# The debug output is in: ~/Library/Application Support/Godot/app_userdata/40k/logs/
tail -100 ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | grep -i "error\|warning"

# Expected: No errors related to movement, mode selection, or radio buttons
```

## Success Criteria

- [ ] Selecting a unit automatically defaults to Normal Move (already works)
- [ ] "Mode: Normal Move (Default)" is shown in UI
- [ ] Hint text "Drag models to move, or select a different mode below" is visible
- [ ] "Confirm Movement Mode" button is NOT shown
- [ ] Players can drag models immediately after selecting a unit (no extra clicks)
- [ ] Clicking "Advance" radio automatically rolls D6 and updates movement cap
- [ ] Clicking "Remain Stationary" radio immediately completes the unit's movement
- [ ] No duplicate BEGIN_NORMAL_MOVE actions when unit is selected
- [ ] Programmatic radio button changes don't trigger signal handlers
- [ ] Movement mode can be switched (Advance → Normal → Advance) without errors
- [ ] All existing movement tests still pass
- [ ] No errors in debug logs

## Common Pitfalls & Solutions

### Issue: Duplicate BEGIN_NORMAL_MOVE actions
**Solution**: Use `setting_radio_programmatically` flag to prevent signal handlers from firing when button_pressed is set programmatically.

### Issue: Advance dice rolls multiple times
**Solution**: Use `call_deferred("_roll_advance_dice")` instead of direct call. This ensures the BEGIN_ADVANCE action is processed before rolling.

### Issue: Mode switches cause errors
**Solution**: Verify that switching from Advance back to Normal properly resets the movement cap and clears the advance_roll_label.

### Issue: Fall Back radio not visible
**Solution**: Fall Back is only shown when unit is engaged. This is correct behavior. Use `_update_fall_back_visibility()` which checks `_is_unit_engaged()`.

### Issue: Remain Stationary doesn't clear active unit
**Solution**: Ensure `active_unit_id = ""` is called after sending the action, and use `call_deferred()` for UI updates.

### Issue: Unit list doesn't update after Stationary
**Solution**: Verify `_populate_unit_list()` is called with `call_deferred()` after marking unit as stationary.

### Issue: Radio button signals fire too early
**Solution**: CheckBox .pressed signal fires on toggle. Use `setting_radio_programmatically` guard at the start of ALL radio button handlers.

## References

### Code References
- `MovementController.gd` lines 320-378 - Mode selection UI section
- `MovementController.gd` lines 551-630 - Unit selection (BEGIN_NORMAL_MOVE auto-trigger)
- `MovementController.gd` lines 652-705 - Radio button handlers
- `MovementController.gd` lines 747-772 - Confirm mode button handler (will be removed)
- `MovementController.gd` lines 785-808 - Advance dice rolling logic
- `MovementController.gd` lines 844-890 - Mode reset for new unit
- `MovementPhase.gd` lines 403-434 - BEGIN_NORMAL_MOVE processing
- `MovementPhase.gd` lines 436-492 - BEGIN_ADVANCE processing
- `MovementPhase.gd` lines 804-846 - REMAIN_STATIONARY processing

### External Documentation
- Godot CheckBox: https://docs.godotengine.org/en/4.4/classes/class_checkbox.html
- Godot Signal: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
- Godot call_deferred: https://docs.godotengine.org/en/4.4/classes/class_object.html#class-object-method-call-deferred

### Warhammer Rules
- Movement Phase: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Normal Move: Default movement type, M inches
- Advance: M + D6 inches, cannot shoot (except Assault) or charge
- Remain Stationary: Don't move, benefits Heavy weapons

## PRP Quality Checklist

- [x] All necessary context included
- [x] Validation gates are executable commands
- [x] References existing patterns (radio button behavior)
- [x] Clear implementation path with step-by-step tasks
- [x] Error handling documented (duplicate action prevention)
- [x] Code examples are complete and runnable
- [x] Manual test suite provided
- [x] Root cause analysis provided
- [x] Common pitfalls addressed
- [x] External references included

## Confidence Score

**9/10** - Very high confidence in one-pass implementation success

**Reasoning**:
- Changes are localized to MovementController.gd
- No changes needed to MovementPhase.gd (backend already supports this)
- Pattern for preventing duplicate signals is simple (flag guard)
- Auto-triggering logic is straightforward (call existing _roll_advance_dice())
- Removing the "Confirm" button is low risk (just delete UI creation)
- Manual testing is easy (just click radio buttons and drag models)
- Clear visual feedback (dice roll shown, mode label updated)
- Backward compatible (doesn't change game logic, only UI flow)

**Minor Risk**:
- CheckBox .pressed signal behavior when button_pressed is set programmatically might vary by Godot version
- If signal doesn't fire on programmatic set, the guards are unnecessary but harmless
- If signal DOES fire, guards prevent duplicate actions
- Either way, the implementation handles it correctly
