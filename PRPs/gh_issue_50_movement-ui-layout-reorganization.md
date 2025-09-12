# Product Requirements Document: Movement Phase UI Layout Reorganization

## Issue Reference
GitHub Issue #50: All of the movement phase specific info and actions should be in the right hand panel, and not the top one

## Feature Description
Reorganize the movement phase UI by moving all movement-specific elements from the top panel to the right-hand panel, except for the "End Movement Phase" button. The right-hand panel should be restructured into 4 distinct vertical sections for better organization and user experience.

## Requirements
1. Move all movement-specific UI elements from top panel to right panel (EXCEPT "End Movement Phase" button)
2. Reorganize right panel into 4 vertical sections:
   - **Section 1**: List of units eligible to move with move status flags  
   - **Section 2**: Selected unit details showing current movement mode
   - **Section 3**: Movement mode selection buttons (consider radio button format)
   - **Section 4**: Movement action buttons and distance remaining display
3. Keep "End Movement Phase" button in the top panel
4. Preserve all existing functionality - only move UI elements, don't create new features
5. Maintain consistent styling and behavior

## Implementation Context

### Current Movement Phase UI Structure

#### Top Panel (HUD_Bottom) - Currently Contains:
**Static Elements (Keep):**
- Phase label, Active Player badge, Status label
- End Movement Phase button ✅ **KEEP THIS**

**Movement-Specific Elements (MOVE TO RIGHT):**  
- Move cap display ("Move: 6\"")
- Inches used display ("Used: 0\"") 
- Inches left display ("Left: 6\"")
- Illegal reason display (red error text)
- Undo Model button
- Reset Unit button
- Confirm Move button

#### Right Panel (HUD_Right) - Currently Contains:
**Existing Elements:**
- Unit list (UnitListPanel) - will become Section 1
- Movement mode buttons (Normal Move, Advance, Fall Back, Remain Stationary) - will become Section 3
- Dice log display

**New Layout (4 Sections Required):**
```
┌─────────────────────────────────┐
│ Section 1: Unit List & Status   │
│ ┌─────────────────────────────┐ │
│ │ □ Intercessors [MOVED]      │ │
│ │ □ Tactical Squad            │ │  
│ │ □ Dreadnought [ADVANCING]   │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────│
│ Section 2: Selected Unit Mode  │
│ Unit: Intercessors              │
│ Mode: Normal Moving             │
├─────────────────────────────────│
│ Section 3: Movement Mode Btns  │
│ ○ Normal Move  ○ Advance        │
│ ○ Fall Back    ○ Stay Still     │
├─────────────────────────────────│
│ Section 4: Action Buttons       │
│ Distance: 3.2\" / 6\" remaining  │
│ [Undo Model] [Reset Unit]       │
│ [Confirm Move]                  │
└─────────────────────────────────┘
```

### File Structure Analysis

#### Primary File: MovementController.gd
**Location:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd`

**Key Methods to Modify:**

1. **`_setup_bottom_hud()` (lines 152-231)**
   - Currently creates: MovementInfo container, MovementButtons container 
   - **CHANGE:** Remove MovementInfo and most MovementButtons, keep only EndPhaseButton

2. **`_setup_right_panel()` (lines 233-294)**
   - Currently creates: MovementActions container with mode buttons, dice log
   - **CHANGE:** Restructure into 4 sections as specified

**Current UI Creation Pattern:**
```gdscript
# Current _setup_bottom_hud() creates:
var container = HBoxContainer.new()
container.name = "MovementInfo" 
move_cap_label = Label.new()      # MOVE TO RIGHT SECTION 4
inches_used_label = Label.new()   # MOVE TO RIGHT SECTION 4  
inches_left_label = Label.new()   # MOVE TO RIGHT SECTION 4
illegal_reason_label = Label.new() # MOVE TO RIGHT SECTION 4
# + MovementButtons container with Undo, Reset, Confirm # MOVE TO RIGHT SECTION 4
```

```gdscript
# Current _setup_right_panel() creates:
unit_list = container.get_node_or_null("UnitListPanel") # KEEP AS SECTION 1
# MovementActions container:
normal_button = Button.new()     # MOVE TO SECTION 3
advance_button = Button.new()    # MOVE TO SECTION 3
fall_back_button = Button.new()  # MOVE TO SECTION 3  
stationary_button = Button.new() # MOVE TO SECTION 3
dice_log_display = RichTextLabel.new() # KEEP AT BOTTOM
```

### Godot UI Container Best Practices

**Container Hierarchy for 4 Sections:**
```gdscript
HUD_Right/VBoxContainer/
├── Section1_UnitList (VBoxContainer)
│   ├── Label ("Units Eligible to Move")
│   └── UnitListPanel (ItemList) 
├── HSeparator
├── Section2_UnitDetails (VBoxContainer)  
│   ├── Label ("Selected Unit Details")
│   ├── UnitNameLabel  
│   └── ModeLabel
├── HSeparator  
├── Section3_ModeSelection (VBoxContainer)
│   ├── Label ("Movement Mode")
│   └── ModeButtonsContainer (HBoxContainer)
│       ├── NormalMoveButton (CheckBox with ButtonGroup)
│       ├── AdvanceButton (CheckBox with ButtonGroup)  
│       ├── FallBackButton (CheckBox with ButtonGroup)
│       └── StationaryButton (CheckBox with ButtonGroup)
├── HSeparator
├── Section4_Actions (VBoxContainer)
│   ├── Label ("Movement Actions") 
│   ├── DistanceInfo (VBoxContainer)
│   │   ├── MoveCapLabel
│   │   ├── InchesUsedLabel  
│   │   ├── InchesLeftLabel
│   │   └── IllegalReasonLabel
│   └── ActionButtons (HBoxContainer)
│       ├── UndoButton
│       ├── ResetButton  
│       └── ConfirmButton
└── DiceLogDisplay (RichTextLabel)
```

**Radio Button Implementation:**
```gdscript
# Create ButtonGroup for radio behavior
var mode_button_group = ButtonGroup.new()

# Create CheckBox controls for radio appearance  
var normal_check = CheckBox.new()
normal_check.text = "Normal Move"
normal_check.toggle_mode = true
normal_check.button_group = mode_button_group

var advance_check = CheckBox.new() 
advance_check.text = "Advance"
advance_check.toggle_mode = true
advance_check.button_group = mode_button_group
# ... etc for Fall Back and Remain Stationary
```

### Current Signal Connections
**Preserve these signal connections:**
- `_on_unit_selected(index: int)` - Unit list selection
- `_on_normal_move_pressed()` - Mode button handlers  
- `_on_advance_pressed()`, `_on_fall_back_pressed()`, `_on_remain_stationary_pressed()`
- `_on_undo_model_pressed()`, `_on_reset_unit_pressed()`, `_on_confirm_move_pressed()`
- `_on_end_phase_pressed()` - Keep in top panel

### Integration Points
**MovementController interfaces with:**
- `Main.gd` via signals: `move_action_requested`, `ui_update_requested`
- `MovementPhase.gd` via phase signals: `unit_move_begun`, `model_drop_committed`, etc.
- Game state updates trigger UI refreshes via `_refresh_unit_list()` and `_update_movement_display()`

## Technical Approach

### Phase 1: Modify Bottom HUD Setup
```gdscript
# _setup_bottom_hud() modification
func _setup_bottom_hud() -> void:
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: Cannot find HBoxContainer in HUD_Bottom")
		return
	
	# Remove existing movement containers
	var existing_movement_info = main_container.get_node_or_null("MovementInfo")
	if existing_movement_info:
		main_container.remove_child(existing_movement_info)
		existing_movement_info.free()
	
	var existing_buttons = main_container.get_node_or_null("MovementButtons") 
	if existing_buttons:
		# Remove action buttons but preserve End Phase button
		var end_phase_btn = existing_buttons.get_node_or_null("EndPhaseButton")
		if end_phase_btn:
			existing_buttons.remove_child(end_phase_btn)
			main_container.add_child(end_phase_btn)  # Move to main container
		
		main_container.remove_child(existing_buttons)
		existing_buttons.free()
```

### Phase 2: Restructure Right Panel 
```gdscript
# _setup_right_panel() complete rewrite
func _setup_right_panel() -> void:
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer" 
		hud_right.add_child(container)
	
	# Clear existing movement-specific containers
	var existing_actions = container.get_node_or_null("MovementActions")
	if existing_actions:
		container.remove_child(existing_actions)
		existing_actions.free()
	
	# SECTION 1: Unit List with Status
	_create_section1_unit_list(container)
	container.add_child(HSeparator.new())
	
	# SECTION 2: Selected Unit Details  
	_create_section2_unit_details(container)
	container.add_child(HSeparator.new())
	
	# SECTION 3: Movement Mode Selection
	_create_section3_mode_selection(container) 
	container.add_child(HSeparator.new())
	
	# SECTION 4: Action Buttons & Distance Info
	_create_section4_actions(container)
	
	# Keep dice log at bottom
	if not dice_log_display:
		_create_dice_log_display(container)
```

### Phase 3: Implement 4 Section Creation Methods
```gdscript
func _create_section1_unit_list(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()
	section.name = "Section1_UnitList"
	
	var label = Label.new()
	label.text = "Units Eligible to Move"
	label.add_theme_font_size_override("font_size", 14)
	section.add_child(label)
	
	# Use existing unit list or create new one
	if not unit_list:
		unit_list = ItemList.new()
		unit_list.name = "UnitListPanel" 
		unit_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unit_list.custom_minimum_size = Vector2(0, 120)
	
	# Connect unit selection signal
	if not unit_list.item_selected.is_connected(_on_unit_selected):
		unit_list.item_selected.connect(_on_unit_selected)
	
	section.add_child(unit_list)
	parent.add_child(section)

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

func _create_section3_mode_selection(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()
	section.name = "Section3_ModeSelection"
	
	var label = Label.new()
	label.text = "Movement Mode"
	label.add_theme_font_size_override("font_size", 14)
	section.add_child(label)
	
	# Create radio button group
	mode_button_group = ButtonGroup.new()
	
	var button_container = HBoxContainer.new()
	button_container.name = "ModeButtons"
	
	# Create radio buttons (CheckBox with ButtonGroup for radio behavior)
	normal_radio = CheckBox.new()
	normal_radio.text = "Normal" 
	normal_radio.toggle_mode = true
	normal_radio.button_group = mode_button_group
	normal_radio.pressed.connect(_on_normal_move_pressed)
	button_container.add_child(normal_radio)
	
	advance_radio = CheckBox.new()
	advance_radio.text = "Advance"
	advance_radio.toggle_mode = true  
	advance_radio.button_group = mode_button_group
	advance_radio.pressed.connect(_on_advance_pressed)
	button_container.add_child(advance_radio)
	
	fall_back_radio = CheckBox.new()
	fall_back_radio.text = "Fall Back"
	fall_back_radio.toggle_mode = true
	fall_back_radio.button_group = mode_button_group  
	fall_back_radio.pressed.connect(_on_fall_back_pressed)
	button_container.add_child(fall_back_radio)
	
	stationary_radio = CheckBox.new()
	stationary_radio.text = "Stay Still" 
	stationary_radio.toggle_mode = true
	stationary_radio.button_group = mode_button_group
	stationary_radio.pressed.connect(_on_remain_stationary_pressed) 
	button_container.add_child(stationary_radio)
	
	section.add_child(button_container)
	parent.add_child(section)

func _create_section4_actions(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()  
	section.name = "Section4_Actions"
	
	var label = Label.new()
	label.text = "Movement Actions"
	label.add_theme_font_size_override("font_size", 14)
	section.add_child(label)
	
	# Distance information (moved from top panel)
	var distance_info = VBoxContainer.new()
	distance_info.name = "DistanceInfo"
	
	move_cap_label = Label.new()
	move_cap_label.text = "Move: 0\""
	distance_info.add_child(move_cap_label)
	
	inches_used_label = Label.new()  
	inches_used_label.text = "Used: 0\""
	distance_info.add_child(inches_used_label)
	
	inches_left_label = Label.new()
	inches_left_label.text = "Left: 0\"" 
	distance_info.add_child(inches_left_label)
	
	illegal_reason_label = Label.new()
	illegal_reason_label.text = ""
	illegal_reason_label.modulate = Color.RED
	distance_info.add_child(illegal_reason_label)
	
	section.add_child(distance_info)
	
	# Action buttons (moved from top panel)
	var button_container = HBoxContainer.new()
	button_container.name = "ActionButtons"
	
	var undo_button = Button.new()
	undo_button.text = "Undo Model"
	undo_button.pressed.connect(_on_undo_model_pressed) 
	button_container.add_child(undo_button)
	
	var reset_button = Button.new()
	reset_button.text = "Reset Unit"
	reset_button.pressed.connect(_on_reset_unit_pressed)
	button_container.add_child(reset_button)
	
	var confirm_button = Button.new()  
	confirm_button.text = "Confirm Move"
	confirm_button.pressed.connect(_on_confirm_move_pressed)
	button_container.add_child(confirm_button)
	
	section.add_child(button_container)
	parent.add_child(section)
```

### Phase 4: Update Display Methods
```gdscript
# Add new methods for section 2 updates
func _update_selected_unit_display() -> void:
	if selected_unit_label:
		var unit_name = "None Selected"
		if active_unit_id != "" and current_phase:
			var unit = current_phase.get_unit(active_unit_id)
			if unit:
				unit_name = unit.get("meta", {}).get("name", active_unit_id)
		selected_unit_label.text = "Unit: " + unit_name
		
	if unit_mode_label:
		var mode_text = "Mode: " + active_mode if active_mode != "" else "Mode: -"
		unit_mode_label.text = mode_text

# Update existing _refresh_unit_list to show move status
func _refresh_unit_list() -> void:
	if not unit_list or not current_phase:
		return
	
	unit_list.clear()
	var actions = current_phase.get_available_actions()
	var added_units = {}
	
	for action in actions:
		var unit_id = action.get("actor_unit_id", "")
		if unit_id != "" and not added_units.has(unit_id):
			var unit = current_phase.get_unit(unit_id)
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var status = ""
			
			# Add move status flags as requested
			if unit.get("flags", {}).get("moved", false):
				status = " [MOVED]"
			elif unit.get("flags", {}).get("advanced", false):
				status = " [ADVANCING]" 
			elif unit.get("flags", {}).get("fell_back", false):
				status = " [FALLING BACK]"
			elif active_unit_id == unit_id:
				status = " [ACTIVE]"
			
			unit_list.add_item(unit_name + status)
			unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
			added_units[unit_id] = true

# Update button handlers to work with radio buttons
func _on_unit_selected(index: int) -> void:
	var unit_id = unit_list.get_item_metadata(index)
	active_unit_id = unit_id
	print("MovementController: Unit selected - ", unit_id)
	_highlight_unit_models(unit_id)
	_update_selected_unit_display()  # NEW: Update section 2
	emit_signal("ui_update_requested")
```

## Implementation Tasks

### 1. Update MovementController._setup_bottom_hud() (Priority: High)
- Remove MovementInfo container (move_cap_label, inches_used_label, inches_left_label, illegal_reason_label)
- Remove action buttons from MovementButtons container (undo, reset, confirm)
- Keep only End Movement Phase button in top panel
- Clean up existing container creation logic

### 2. Restructure MovementController._setup_right_panel() (Priority: High)  
- Replace current structure with 4-section layout
- Implement _create_section1_unit_list() method
- Implement _create_section2_unit_details() method
- Implement _create_section3_mode_selection() method with radio buttons
- Implement _create_section4_actions() method
- Preserve dice log display at bottom

### 3. Create Radio Button Implementation (Priority: Medium)
- Create ButtonGroup for mutual exclusion
- Replace regular buttons with CheckBox + ButtonGroup for radio appearance
- Update button press handlers to work with radio selection
- Ensure proper visual feedback for selected mode

### 4. Update Display Refresh Methods (Priority: High)
- Add _update_selected_unit_display() for Section 2
- Modify _refresh_unit_list() to show move status flags [MOVED], [ADVANCING], etc.
- Update _update_movement_display() to work with new label locations
- Ensure all UI updates work with new layout

### 5. Test Integration & Functionality (Priority: High)
- Verify all existing functionality works unchanged
- Test unit selection updates Section 2 correctly
- Test mode selection with radio buttons
- Test action buttons in new location
- Test End Movement Phase button remains in top panel

### 6. Polish & Visual Consistency (Priority: Low) 
- Add proper spacing with HSeparator between sections
- Ensure consistent font sizes and styling
- Test layout with different window sizes
- Add tooltips or help text if needed

## Validation Gates

```bash
# Run Godot engine to test changes
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --headless --quit-after 3

# Manual Testing Checklist:
# 1. Load game and enter Movement Phase
# 2. Verify top panel only shows: Phase info + End Movement Phase button
# 3. Verify right panel shows 4 sections in order:
#    - Section 1: Unit list with status flags
#    - Section 2: Selected unit details  
#    - Section 3: Radio button mode selection
#    - Section 4: Action buttons + distance info
# 4. Test unit selection updates Section 2
# 5. Test mode selection with radio buttons (only one selected)
# 6. Test all action buttons work (Undo, Reset, Confirm)
# 7. Test End Movement Phase button works in top panel
# 8. Test dice log still displays at bottom of right panel
```

## External Resources

### Godot Documentation
- ButtonGroup: https://docs.godotengine.org/en/stable/classes/class_buttongroup.html
- VBoxContainer: https://docs.godotengine.org/en/stable/classes/class_vboxcontainer.html
- HBoxContainer: https://docs.godotengine.org/en/stable/classes/class_hboxcontainer.html  
- UI Containers Guide: https://docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html
- CheckBox (for radio buttons): https://docs.godotengine.org/en/stable/classes/class_checkbox.html

### Warhammer Rules Reference  
- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

### Code References
- MovementController.gd:152-231 (_setup_bottom_hud)
- MovementController.gd:233-294 (_setup_right_panel)  
- MovementController.gd:375-380 (_on_unit_selected)
- MovementController.gd:482-519 (_on_unit_move_begun)

## Common Pitfalls to Avoid

1. **ButtonGroup Radio Behavior**: CheckBox + ButtonGroup is needed for radio button appearance and behavior
2. **Signal Connection Preservation**: Ensure all existing button press handlers remain connected
3. **Container Cleanup**: Properly remove/free existing containers before creating new layout  
4. **Reference Updates**: Update all label/button references to use new variables
5. **End Phase Button**: Must remain in top panel, don't accidentally move it
6. **Unit List Reuse**: Preserve existing unit list functionality while enhancing with status flags
7. **Display Updates**: Ensure _update_movement_display() and other refresh methods work with new locations

## Success Criteria

1. **Top panel cleanup**: Only shows phase info and End Movement Phase button
2. **Right panel 4 sections**: Clearly organized vertical layout with separators
3. **Section 1**: Unit list shows move status flags ([MOVED], [ADVANCING], etc.)
4. **Section 2**: Shows selected unit name and current movement mode  
5. **Section 3**: Radio button selection for movement modes (mutually exclusive)
6. **Section 4**: Distance info and action buttons work identically to before
7. **Functionality preservation**: All existing movement features work unchanged
8. **Visual consistency**: Clean, organized appearance with proper spacing
9. **No regressions**: No existing functionality broken by UI reorganization

## Confidence Score: 9/10

**Rationale**: Very high confidence due to:
- Clear, specific requirements with detailed layout specification
- Well-understood existing codebase structure and patterns  
- Straightforward UI reorganization (move existing elements, no new functionality)
- Established Godot UI container patterns and radio button implementation
- Existing similar implementations in other phase controllers for reference
- Comprehensive technical approach with specific code examples

**Risk factors** (minimal):
- Radio button styling might need iteration for desired appearance
- Container sizing/spacing may need minor adjustments  
- Potential edge cases with unit selection state management

## Notes for Implementation

- **Start with** Section 4 (actions) as it's the most straightforward move from top to right panel
- **Focus on** preserving all existing functionality - this is purely a UI reorganization
- **Test frequently** during implementation to catch any broken signal connections early  
- **Use HSeparator** between sections for visual clarity
- **Consider** adding section labels/headers for better user understanding
- **Reference** existing phase controllers (ShootingController, ChargeController) for similar UI patterns
- **Maintain** consistent button sizing and spacing throughout the new layout