extends Node2D
class_name MovementController

# MovementController - Handles UI interactions for the Movement Phase
# Manages model dragging, path visualization, and movement validation

signal move_action_requested(action: Dictionary)
signal movement_preview_updated(unit_id: String, model_id: String, valid: bool)
signal ui_update_requested()  # Signal to request UI refresh

# Movement state
var current_phase = null  # Can be MovementPhase or null
var active_unit_id: String = ""
var active_mode: String = ""  # NORMAL, ADVANCE, FALL_BACK
var move_cap_inches: float = 0.0
var selected_model: Dictionary = {}
var dragging_model: bool = false
var drag_start_pos: Vector2

# UI References
var board_view: Node2D
var path_visual: Line2D
var staged_path_visual: Line2D  # NEW: Visual for staged movements
var ruler_visual: Line2D
var ghost_visual: Node2D
var model_path_visuals: Dictionary = {}  # Dictionary of model_id -> Line2D for individual paths
var hud_bottom: Control
var hud_right: Control

# UI Elements
var move_cap_label: Label
var inches_used_label: Label
var inches_left_label: Label
var illegal_reason_label: Label
var unit_list: ItemList
var dice_log_display: RichTextLabel

# New UI elements for 4-section layout
var selected_unit_label: Label
var unit_mode_label: Label
var mode_button_group: ButtonGroup
var normal_radio: CheckBox
var advance_radio: CheckBox
var fall_back_radio: CheckBox
var stationary_radio: CheckBox
var confirm_mode_button: Button
var advance_roll_label: Label

# Path tracking
var current_path: Array = []  # Array of Vector2 points
var path_valid: bool = false

# Helper function to get unit movement stat with proper error handling
func get_unit_movement(unit: Dictionary) -> float:
	# Try the expected path first
	if unit.has("meta") and unit.meta.has("stats") and unit.meta.stats.has("move"):
		var movement = float(unit.meta.stats.move)
		return movement
	
	# Try nested get with type safety
	var stats = unit.get("meta", {}).get("stats", {})
	if stats and stats.has("move"):
		var movement = float(stats.get("move"))
		return movement
	
	# Log warning and return default
	var unit_name = unit.get("meta", {}).get("name", "Unknown")
	push_warning("MovementController: Unit %s missing movement stat, using default: 6" % unit_name)
	return 6.0

func _ready() -> void:
	set_process_unhandled_input(true)
	set_process(true)  # Enable process for debugging
	_setup_ui_references()
	_create_path_visuals()
	print("MovementController ready")

func _exit_tree() -> void:
	# Clean up visuals that were added to BoardRoot
	if path_visual and is_instance_valid(path_visual):
		path_visual.queue_free()
	if staged_path_visual and is_instance_valid(staged_path_visual):
		staged_path_visual.queue_free()
	if ruler_visual and is_instance_valid(ruler_visual):
		ruler_visual.queue_free()  
	if ghost_visual and is_instance_valid(ghost_visual):
		ghost_visual.queue_free()
	
	# Clean up individual model path visuals
	for model_id in model_path_visuals:
		var line = model_path_visuals[model_id]
		if line and is_instance_valid(line):
			line.queue_free()
	model_path_visuals.clear()
	
	# Clean up UI containers
	var movement_info = get_node_or_null("/root/Main/HUD_Bottom/HBoxContainer/MovementInfo")
	if movement_info and is_instance_valid(movement_info):
		movement_info.queue_free()
	
	var movement_buttons = get_node_or_null("/root/Main/HUD_Bottom/HBoxContainer/MovementButtons")
	if movement_buttons and is_instance_valid(movement_buttons):
		movement_buttons.queue_free()
	
	var movement_actions = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/MovementActions")
	if movement_actions and is_instance_valid(movement_actions):
		movement_actions.queue_free()
	
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

func _setup_ui_references() -> void:
	# Get references to UI nodes
	board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
	hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	hud_right = get_node_or_null("/root/Main/HUD_Right")
	
	# Get references to existing UI elements instead of creating new ones
	unit_list = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/UnitListPanel")
	
	# Setup movement-specific UI elements
	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()

func _create_path_visuals() -> void:
	# Get references to the proper layers in BoardRoot
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		print("ERROR: Cannot find BoardRoot for visual layers")
		return
	
	# Create path visualization line in BoardRoot space
	path_visual = Line2D.new()
	path_visual.name = "MovementPathVisual"
	path_visual.width = 2.0
	path_visual.default_color = Color.GREEN
	path_visual.add_point(Vector2.ZERO)  # Dummy point
	path_visual.clear_points()
	board_root.add_child(path_visual)
	
	# Create staged path visualization line (yellow for staged moves)
	staged_path_visual = Line2D.new()
	staged_path_visual.name = "StagedMovementPathVisual"
	staged_path_visual.width = 2.0
	staged_path_visual.default_color = Color.YELLOW  # Yellow for staged moves
	staged_path_visual.add_point(Vector2.ZERO)  # Dummy point
	staged_path_visual.clear_points()
	board_root.add_child(staged_path_visual)
	
	# Create ruler line in BoardRoot space
	ruler_visual = Line2D.new()
	ruler_visual.name = "MovementRulerVisual"
	ruler_visual.width = 3.0
	ruler_visual.default_color = Color.WHITE
	ruler_visual.add_point(Vector2.ZERO)  # Dummy point
	ruler_visual.clear_points()
	board_root.add_child(ruler_visual)
	
	# Create ghost visual in BoardRoot space (same as tokens)
	ghost_visual = Node2D.new()
	ghost_visual.name = "MovementGhostVisual"
	board_root.add_child(ghost_visual)

func _setup_bottom_hud() -> void:
	# Get the main HBox container in bottom HUD
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: Cannot find HBoxContainer in HUD_Bottom")
		return
	
	# Remove existing movement containers (MovementInfo and MovementButtons)
	var existing_movement_info = main_container.get_node_or_null("MovementInfo")
	if existing_movement_info:
		print("MovementController: Removing MovementInfo container (moved to right panel)")
		main_container.remove_child(existing_movement_info)
		existing_movement_info.free()
	
	var existing_buttons = main_container.get_node_or_null("MovementButtons") 
	if existing_buttons:
		# Check if End Phase button exists and preserve it
		var end_phase_btn = existing_buttons.get_node_or_null("EndPhaseButton")
		if end_phase_btn:
			print("MovementController: Preserving End Phase button in top panel")
			existing_buttons.remove_child(end_phase_btn)
			
			# Add separator before End Phase button
			main_container.add_child(VSeparator.new())
			main_container.add_child(end_phase_btn)  # Move to main container
		
		print("MovementController: Removing MovementButtons container (moved to right panel)")
		main_container.remove_child(existing_buttons)
		existing_buttons.free()
	else:
		# If MovementButtons doesn't exist, create End Phase button directly
		print("MovementController: Creating End Phase button in top panel")
		# main_container.add_child(VSeparator.new())
		
		# var end_phase_button = Button.new()
		# end_phase_button.name = "EndPhaseButton"
		# end_phase_button.text = "End Movement Phase"
		# end_phase_button.pressed.connect(_on_end_phase_pressed)
		# main_container.add_child(end_phase_button)

func _setup_right_panel() -> void:
	# Main.gd already handles cleanup before controller creation
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer" 
		hud_right.add_child(container)
	
	# Clear existing movement-specific containers
	var existing_actions = container.get_node_or_null("MovementActions")
	if existing_actions:
		print("MovementController: Removing existing MovementActions container")
		container.remove_child(existing_actions)
		existing_actions.free()
	
	# Clear any existing 4-section containers to avoid duplication
	for section_name in ["Section1_UnitList", "Section2_UnitDetails", "Section3_ModeSelection", "Section4_Actions"]:
		var existing_section = container.get_node_or_null(section_name)
		if existing_section:
			container.remove_child(existing_section)
			existing_section.free()
	
	# SECTION 1: Unit List with Status
	_create_section1_unit_list(container)
	# container.add_child(HSeparator.new())
	
	# SECTION 2: Selected Unit Details  
	_create_section2_unit_details(container)
	# container.add_child(HSeparator.new())
	
	# SECTION 3: Movement Mode Selection
	_create_section3_mode_selection(container) 
	# container.add_child(HSeparator.new())
	
	# SECTION 4: Action Buttons & Distance Info
	_create_section4_actions(container)
	
	# Keep dice log at bottom
	# _create_dice_log_display(container)

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

func _create_dice_log_display(parent: VBoxContainer) -> void:
	# Create dice log display only if it doesn't exist
	if not dice_log_display:
		var existing_dice_log = parent.get_node_or_null("DiceLog")
		if not existing_dice_log:
			var dice_label = Label.new()
			dice_label.text = "Dice Log:"
			parent.add_child(dice_label)
			
			dice_log_display = RichTextLabel.new()
			dice_log_display.name = "DiceLog"
			dice_log_display.custom_minimum_size = Vector2(300, 200)  # Increased height to use more space
			dice_log_display.bbcode_enabled = true
			parent.add_child(dice_log_display)

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

func set_phase(phase) -> void:  # Remove type hint to accept any phase
	# Only set if it's actually a MovementPhase
	if phase and phase.has_method("get_class"):
		print("MovementController: Received phase of type ", phase.get_class())
		
		# Check if it's a MovementPhase by checking for movement-specific signals
		if phase.has_signal("unit_move_begun"):
			current_phase = phase
			print("MovementController: Phase set successfully")
			_update_end_phase_button()
			
			# Connect to phase signals
			if not phase.unit_move_begun.is_connected(_on_unit_move_begun):
				phase.unit_move_begun.connect(_on_unit_move_begun)
			if phase.has_signal("model_drop_committed"):
				if not phase.model_drop_committed.is_connected(_on_model_drop_committed):
					phase.model_drop_committed.connect(_on_model_drop_committed)
					print("MovementController: Connected model_drop_committed signal")
				
				# Also ensure Main.gd is connected to the same phase instance
				var main_node = get_node("/root/Main")
				if main_node and main_node.has_method("_on_model_drop_committed"):
					if not phase.model_drop_committed.is_connected(main_node._on_model_drop_committed):
						phase.model_drop_committed.connect(main_node._on_model_drop_committed)
						print("MovementController: Connected Main to model_drop_committed signal")
						
			if phase.has_signal("model_drop_preview"):
				if not phase.model_drop_preview.is_connected(_on_model_drop_preview):
					phase.model_drop_preview.connect(_on_model_drop_preview)
					print("MovementController: Connected model_drop_preview signal")
			if phase.has_signal("unit_move_confirmed"):
				if not phase.unit_move_confirmed.is_connected(_on_unit_move_confirmed):
					phase.unit_move_confirmed.connect(_on_unit_move_confirmed)
			if phase.has_signal("unit_move_reset"):
				if not phase.unit_move_reset.is_connected(_on_unit_move_reset):
					phase.unit_move_reset.connect(_on_unit_move_reset)
			if phase.has_signal("movement_mode_locked"):
				if not phase.movement_mode_locked.is_connected(_on_movement_mode_locked):
					phase.movement_mode_locked.connect(_on_movement_mode_locked)
			
			# Update the game state snapshot reference
			if phase.has_method("get_game_state_snapshot"):
				var snapshot = phase.game_state_snapshot
				print("MovementController: Updated with game state snapshot")
			
			# Ensure UI is set up after phase assignment (especially after loading)
			_setup_ui_references()
			
			_refresh_unit_list()
		else:
			print("MovementController: Ignoring non-movement phase")
			current_phase = null
	else:
		print("MovementController: Clearing phase reference")
		current_phase = null

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
			var status = _get_unit_movement_status(unit_id)
			var status_text = ""
			
			match status:
				"not_moved":
					status_text = " [YET TO MOVE]"
				"moving":
					status_text = " [CURRENTLY MOVING]"
				"completed":
					status_text = " [COMPLETED MOVING]"
			
			unit_list.add_item(unit_name + status_text)
			unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
			added_units[unit_id] = true

func _on_unit_selected(index: int) -> void:
	var unit_id = unit_list.get_item_metadata(index)
	active_unit_id = unit_id
	print("MovementController: Unit selected - ", unit_id)
	_highlight_unit_models(unit_id)
	_update_selected_unit_display()  # NEW: Update section 2
	_update_fall_back_visibility()  # NEW: Update Fall Back visibility based on engagement
	_reset_mode_selection_for_new_unit(unit_id)  # NEW: Reset mode selection for new unit
	emit_signal("ui_update_requested")

func _highlight_unit_models(unit_id: String) -> void:
	# Visual feedback for selected unit
	# This would highlight all models in the unit on the board
	pass

func _get_unit_movement_status(unit_id: String) -> String:
	if not current_phase or not current_phase.active_moves:
		return "not_moved"
	
	if not current_phase.active_moves.has(unit_id):
		return "not_moved"
	
	var move_data = current_phase.active_moves[unit_id]
	if move_data.get("completed", false):
		return "completed"
	elif unit_id == active_unit_id:
		return "moving"
	else:
		return "not_moved"

func _on_normal_move_pressed() -> void:
	print("Normal move button pressed for unit: ", active_unit_id)
	if active_unit_id == "":
		print("No unit selected!")
		# Try to help the user
		if unit_list and unit_list.get_item_count() > 0:
			print("Please select a unit from the list first")
		return
	
	print("Creating BEGIN_NORMAL_MOVE action for unit: ", active_unit_id)
	var action = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	print("Emitting move_action_requested signal with action: ", action)
	emit_signal("move_action_requested", action)
	print("Signal emitted, waiting for phase response...")

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

func _on_fall_back_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "BEGIN_FALL_BACK",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _on_remain_stationary_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "REMAIN_STATIONARY",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _on_undo_model_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "UNDO_LAST_MODEL_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _on_reset_unit_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "RESET_UNIT_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _on_confirm_move_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "CONFIRM_UNIT_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _on_end_phase_pressed() -> void:
	var action = {
		"type": "END_MOVEMENT",
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _on_confirm_mode_pressed() -> void:
	if not active_unit_id:
		return
	
	var selected_mode = _get_selected_movement_mode()
	if selected_mode == "":
		print("No movement mode selected!")
		return
	
	# Lock the mode
	emit_signal("move_action_requested", {
		"type": "LOCK_MOVEMENT_MODE",
		"actor_unit_id": active_unit_id,
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

func _get_selected_movement_mode() -> String:
	if normal_radio and normal_radio.button_pressed:
		return "NORMAL"
	elif advance_radio and advance_radio.button_pressed:
		return "ADVANCE"
	elif fall_back_radio and fall_back_radio.button_pressed:
		return "FALL_BACK"
	elif stationary_radio and stationary_radio.button_pressed:
		return "REMAIN_STATIONARY"
	return ""

func _roll_advance_dice() -> void:
	# Simple dice roll - in a full implementation this would use the game's dice system
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var dice_result = rng.randi_range(1, 6)
	
	advance_roll_label.text = "Advance Roll: %d\"" % dice_result
	advance_roll_label.visible = true
	
	# Update movement cap with advance bonus
	emit_signal("move_action_requested", {
		"type": "SET_ADVANCE_BONUS",
		"actor_unit_id": active_unit_id,
		"payload": {"bonus": dice_result}
	})
	
	# Update the movement display to show the new total
	_update_movement_display_with_advance(dice_result)

func _complete_stationary_move() -> void:
	# Immediately complete the unit's movement for stationary
	emit_signal("move_action_requested", {
		"type": "REMAIN_STATIONARY",
		"actor_unit_id": active_unit_id,
		"payload": {}
	})

func _update_mode_buttons_state(enabled: bool) -> void:
	if normal_radio:
		normal_radio.disabled = not enabled
	if advance_radio:
		advance_radio.disabled = not enabled
	if fall_back_radio:
		fall_back_radio.disabled = not enabled
	if stationary_radio:
		stationary_radio.disabled = not enabled

func _update_fall_back_visibility() -> void:
	if not fall_back_radio or not active_unit_id or not current_phase:
		return
	
	# Check if the selected unit is engaged
	var is_engaged = false
	if current_phase.has_method("_is_unit_engaged"):
		is_engaged = current_phase._is_unit_engaged(active_unit_id)
	
	fall_back_radio.visible = is_engaged
	
	# If not engaged and Fall Back was selected, reset to Normal
	if not is_engaged and fall_back_radio.button_pressed:
		if normal_radio:
			normal_radio.button_pressed = true

func _reset_mode_selection_for_new_unit(unit_id: String) -> void:
	# Check if this unit already has its mode locked
	var mode_is_locked = false
	if current_phase and current_phase.active_moves.has(unit_id):
		mode_is_locked = current_phase.active_moves[unit_id].get("mode_locked", false)
	
	if mode_is_locked:
		# Unit's mode is already locked, disable all controls
		_update_mode_buttons_state(false)
		if confirm_mode_button:
			confirm_mode_button.disabled = true
		
		# Show the locked mode in the UI
		var locked_mode = current_phase.active_moves[unit_id].get("mode", "")
		_set_mode_radio_for_locked_mode(locked_mode)
		
		# Show advance roll if it's an advance move
		if locked_mode == "ADVANCE" and advance_roll_label:
			var advance_roll = current_phase.active_moves[unit_id].get("advance_roll", 0)
			if advance_roll > 0:
				advance_roll_label.text = "Advance Roll: %d\"" % advance_roll
				advance_roll_label.visible = true
				# Also update the movement display to show the total
				_update_movement_display_with_advance(advance_roll)
			else:
				advance_roll_label.visible = false
		else:
			# For non-advance locked modes, update display normally
			_update_movement_display()
	else:
		# Unit's mode is not locked, enable fresh selection
		_update_mode_buttons_state(true)
		if confirm_mode_button:
			confirm_mode_button.disabled = false
		
		# Reset to default (Normal) selection
		if normal_radio:
			normal_radio.button_pressed = true
		
		# Hide advance roll label
		if advance_roll_label:
			advance_roll_label.visible = false
		
		# Update display for fresh unit
		_update_movement_display()

func _set_mode_radio_for_locked_mode(mode: String) -> void:
	# Clear all selections first
	if normal_radio:
		normal_radio.button_pressed = false
	if advance_radio:
		advance_radio.button_pressed = false
	if fall_back_radio:
		fall_back_radio.button_pressed = false
	if stationary_radio:
		stationary_radio.button_pressed = false
	
	# Set the correct radio based on locked mode
	match mode:
		"NORMAL":
			if normal_radio:
				normal_radio.button_pressed = true
		"ADVANCE":
			if advance_radio:
				advance_radio.button_pressed = true
		"FALL_BACK":
			if fall_back_radio:
				fall_back_radio.button_pressed = true
		"REMAIN_STATIONARY":
			if stationary_radio:
				stationary_radio.button_pressed = true

func _on_unit_move_begun(unit_id: String, mode: String) -> void:
	print("MovementController: Unit move begun - ", unit_id, " mode: ", mode)
	active_unit_id = unit_id
	active_mode = mode
	
	# Get move cap from unit
	if current_phase:
		# Try to get unit through the phase
		var unit = null
		if current_phase.has_method("get_unit"):
			unit = current_phase.get_unit(unit_id)
		else:
			# Fallback to GameState
			unit = GameState.get_unit(unit_id)
			
		if unit:
			# Try to get from flags first (set by movement phase), fallback to unit stats
			var move_cap_from_flags = unit.get("flags", {}).get("move_cap_inches", -1.0)
			if move_cap_from_flags > 0:
				move_cap_inches = move_cap_from_flags
				print("Move cap from flags: ", move_cap_inches, " inches")
			else:
				move_cap_inches = get_unit_movement(unit)
				print("Move cap from unit stats: ", move_cap_inches, " inches")
			_update_movement_display()
		else:
			print("ERROR: Could not get unit data!")
	else:
		print("ERROR: No current phase set!")
	
	# Update dice log if it was an advance
	if mode == "ADVANCE" and current_phase:
		if current_phase.has_method("get_dice_log"):
			var dice_log = current_phase.get_dice_log()
			_update_dice_log_display(dice_log)
	
	# Notify Main to update UI
	emit_signal("ui_update_requested")

func _on_model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2) -> void:
	print("MovementController: Model drop committed for ", model_id, " at ", dest_px)
	# Update path visual
	_update_movement_display()
	_refresh_unit_list()
	emit_signal("ui_update_requested")

func _on_model_drop_preview(unit_id: String, model_id: String, path_px: Array, inches_used: float, legal: bool) -> void:
	# Handle staged movement visual updates
	print("MovementController: Model drop preview: ", model_id, " staged at ", path_px[-1] if path_px.size() > 0 else "unknown")
	
	# Update movement display with staged distance
	_update_movement_display()
	_update_staged_moves_visual()
	emit_signal("ui_update_requested")

func _on_unit_move_confirmed(unit_id: String, result_summary: Dictionary) -> void:
	# Clear movement state
	active_unit_id = ""
	active_mode = ""
	move_cap_inches = 0.0
	_clear_path_visual()
	
	# Clear all individual model path visuals
	for model_id in model_path_visuals:
		var line = model_path_visuals[model_id]
		if line and is_instance_valid(line):
			line.queue_free()
	model_path_visuals.clear()
	
	_update_movement_display()
	_refresh_unit_list()
	_update_end_phase_button()
	emit_signal("ui_update_requested")

func _on_unit_move_reset(unit_id: String) -> void:
	_clear_path_visual()
	path_visual.clear_points()  # Clear staged moves visual as well
	
	# Clear all individual model path visuals
	for model_id in model_path_visuals:
		var line = model_path_visuals[model_id]
		if line and is_instance_valid(line):
			line.queue_free()
	model_path_visuals.clear()
	
	_update_movement_display()
	emit_signal("ui_update_requested")

func _on_movement_mode_locked(unit_id: String, mode: String) -> void:
	print("MovementController: Movement mode locked for %s: %s" % [unit_id, mode])
	
	# Update UI state to reflect the locked mode
	_update_mode_buttons_state(false)  # Disable mode buttons
	if confirm_mode_button:
		confirm_mode_button.disabled = true
	
	# Refresh unit list to update status display
	_refresh_unit_list()
	
	emit_signal("ui_update_requested")

func _unhandled_input(event: InputEvent) -> void:
	# In debug mode, let DebugManager handle all input
	if DebugManager and DebugManager.is_debug_active():
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				print("MovementController: Mouse pressed at ", event.position)
				_start_model_drag(event.position)
			else:
				if dragging_model:
					print("MovementController: Mouse released, ending drag")
					_end_model_drag(event.position)
	elif event is InputEventMouseMotion:
		if dragging_model:
			_update_model_drag(event.position)
		else:
			_update_hover_preview(event.position)

func _start_model_drag(mouse_pos: Vector2) -> void:
	print("Starting model drag. Active unit: ", active_unit_id, " Mode: ", active_mode)
	
	if active_unit_id == "" or active_mode == "":
		print("Cannot drag - no active unit or mode")
		return
	
	# Get the board transform from Main
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2
	
	if board_root:
		# Convert screen position to world position using BoardRoot transform
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		# Fallback to simple conversion
		world_pos = get_global_mouse_position()
	
	print("Screen pos: ", mouse_pos, " -> World pos: ", world_pos)
	
	# Check if clicking on a model from the active unit
	var model = _get_model_at_position(world_pos)
	
	if model.is_empty():
		print("No model found at position")
		# Try with a larger search radius in case of precision issues
		model = _get_model_near_position(world_pos, 10.0)  # 10 pixel tolerance
		if model.is_empty():
			return
		print("Found model with tolerance search")
	
	print("Found model: ", model)
	
	if model.unit_id != active_unit_id:
		print("Model belongs to different unit: ", model.unit_id, " vs ", active_unit_id)
		return
	
	selected_model = model
	dragging_model = true
	drag_start_pos = model.position  # Use model's actual position as start
	current_path = [drag_start_pos]
	
	print("Started dragging model ", model.model_id, " from unit ", model.unit_id)
	
	# Update display to show this model's specific movement info
	_update_movement_display()
	# Update path visual to show only this model's path
	_update_staged_moves_visual()
	_show_ghost_visual(model)
	# Set initial ghost position to the cursor position
	_update_ghost_position(world_pos)

func _update_model_drag(mouse_pos: Vector2) -> void:
	if not dragging_model:
		return
	
	# Get the board transform from Main
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2
	
	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()
	
	# Snap to grid if enabled
	if _should_snap_to_grid():
		world_pos = _snap_to_grid(world_pos)
	
	# Update path
	current_path = [drag_start_pos, world_pos]
	
	# Calculate distance
	var distance_inches = Measurement.distance_polyline_inches(current_path)
	
	# Get the model's already accumulated distance
	var already_used = _get_accumulated_distance()
	var total_distance = already_used + distance_inches
	var inches_left = move_cap_inches - total_distance
	
	# Check validity based on total distance
	path_valid = total_distance <= move_cap_inches
	
	# Update visuals
	_update_path_visual()
	_update_ruler_visual()
	_update_ghost_position(world_pos)
	# Show total distance used (already accumulated + current drag)
	_update_movement_display_with_preview(total_distance, inches_left, path_valid)

func _end_model_drag(mouse_pos: Vector2) -> void:
	if not dragging_model:
		return
	
	print("Ending model drag")
	
	# Get the board transform from Main
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2
	
	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()
	
	# Snap to grid if enabled
	if _should_snap_to_grid():
		world_pos = _snap_to_grid(world_pos)
	
	print("Final position: ", world_pos)
	
	# Calculate distance
	var distance_inches = Measurement.distance_polyline_inches([drag_start_pos, world_pos])
	print("Distance moved: ", distance_inches, " inches")
	
	# Get accumulated distance to check against cap
	var accumulated = _get_accumulated_distance()
	var total_distance = accumulated + distance_inches
	var valid = total_distance <= move_cap_inches
	
	if valid:
		print("Move is valid, sending STAGE_MODEL_MOVE action")
		print("  From: ", drag_start_pos, " To: ", world_pos)
		print("  Distance: ", distance_inches, " inches")
		print("  Total staged: ", total_distance, " inches")
		
		# Send STAGE_MODEL_MOVE action instead of SET_MODEL_DEST
		var action = {
			"type": "STAGE_MODEL_MOVE",  # Changed to stage instead of commit
			"actor_unit_id": active_unit_id,
			"payload": {
				"model_id": selected_model.model_id,
				"dest": [world_pos.x, world_pos.y]
			}
		}
		print("  Action: ", action)
		emit_signal("move_action_requested", action)
	else:
		print("Move invalid: total staged movement exceeds cap (", total_distance, " > ", move_cap_inches, ")")
	
	# Clear drag state
	dragging_model = false
	selected_model = {}
	current_path.clear()
	_clear_ghost_visual()
	_clear_path_visual()
	_clear_ruler_visual()
	
	# Update visual to show all staged moves
	_update_staged_moves_visual()

func _update_hover_preview(mouse_pos: Vector2) -> void:
	# Show preview when hovering over models
	pass

func _get_model_near_position(world_pos: Vector2, tolerance: float) -> Dictionary:
	# Find model within tolerance distance
	if not current_phase:
		return {}
	
	var units = current_phase.game_state_snapshot.get("units", {})
	var closest_model = {}
	var closest_distance = INF
	
	for unit_id in units:
		var unit = units[unit_id]
		# Only check units owned by active player
		if unit.get("owner", 0) != GameState.get_active_player():
			continue
			
		var models = unit.get("models", [])
		
		for i in range(models.size()):
			var model = models[i]
			if not model.get("alive", true):
				continue
			
			var pos = model.get("position")
			if pos == null:
				continue
			
			var model_pos: Vector2
			if pos is Dictionary:
				model_pos = Vector2(pos.x, pos.y)
			elif pos is Vector2:
				model_pos = pos
			else:
				continue
			
			var base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
			var distance = world_pos.distance_to(model_pos)
			
			# Check if click is within model's base + tolerance
			if distance <= (base_radius + tolerance):
				if distance < closest_distance:
					closest_distance = distance
					closest_model = {
						"unit_id": unit_id,
						"model_id": model.get("id", "m%d" % (i+1)),
						"position": model_pos,
						"base_mm": model.get("base_mm", 32)
					}
	
	return closest_model

func _get_model_at_position(world_pos: Vector2) -> Dictionary:
	# Find which model is at the given position
	# Returns {unit_id, model_id, position, base_mm} or empty dict
	
	if not current_phase:
		print("No current phase for model detection")
		return {}
	
	var units = current_phase.game_state_snapshot.get("units", {})
	var closest_model = {}
	var closest_distance = INF
	
	for unit_id in units:
		var unit = units[unit_id]
		var models = unit.get("models", [])
		
		# Get staged move data if available
		var move_data = {}
		if current_phase.has_method("get_active_move_data"):
			move_data = current_phase.get_active_move_data(unit_id)
		
		for i in range(models.size()):
			var model = models[i]
			if not model.get("alive", true):
				continue
			
			var model_id = model.get("id", "m%d" % (i+1))
			
			# Check for staged position first
			var model_pos: Vector2
			var staged_pos_found = false
			
			# Look for staged position for this model
			if move_data.has("staged_moves"):
				for staged_move in move_data.staged_moves:
					if staged_move.get("model_id") == model_id:
						model_pos = staged_move.get("dest", Vector2.ZERO)
						staged_pos_found = true
						print("DEBUG: Found staged position for ", model_id, " at ", model_pos)
						break
			
			# Fall back to original position if no staged position
			if not staged_pos_found:
				var pos = model.get("position")
				if pos == null:
					continue
					
				if pos is Dictionary:
					model_pos = Vector2(pos.x, pos.y)
				elif pos is Vector2:
					model_pos = pos
				else:
					continue
			
			var base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
			var distance = world_pos.distance_to(model_pos)
			
			# Check if click is within model's base
			if distance <= base_radius:
				# Use closest model if multiple overlap
				if distance < closest_distance:
					closest_distance = distance
					closest_model = {
						"unit_id": unit_id,
						"model_id": model_id,
						"position": model_pos,
						"base_mm": model.get("base_mm", 32),
						"is_staged": staged_pos_found
					}
	
	if not closest_model.is_empty():
		print("Found model at distance ", closest_distance, " pixels")
		if closest_model.get("is_staged", false):
			print("  - Model is at staged position")
		else:
			print("  - Model is at original position")
	else:
		# Debug: Show all model positions (both staged and original)
		print("No model found at ", world_pos, ". Model positions:")
		for unit_id in units:
			var unit = units[unit_id]
			if unit.get("owner", 0) == GameState.get_active_player():
				var move_data = {}
				if current_phase.has_method("get_active_move_data"):
					move_data = current_phase.get_active_move_data(unit_id)
				
				var models = unit.get("models", [])
				for model in models:
					var model_id = model.get("id", "?")
					var pos = model.get("position")
					
					# Check for staged position
					var staged_pos = null
					if move_data.has("staged_moves"):
						for staged_move in move_data.staged_moves:
							if staged_move.get("model_id") == model_id:
								staged_pos = staged_move.get("dest")
								break
					
					if staged_pos:
						print("  ", unit_id, "/", model_id, " at staged: ", staged_pos)
					elif pos:
						print("  ", unit_id, "/", model_id, " at original: ", pos)
	
	return closest_model

func _validate_move_path(path: Array, distance_inches: float) -> bool:
	if selected_model.is_empty():
		return false
	
	# Check distance cap
	if distance_inches > move_cap_inches:
		illegal_reason_label.text = "Exceeds movement cap"
		return false
	
	# Check end position for engagement range
	if path.size() >= 2:
		var end_pos = path[-1]
		# Simplified check - would call phase validation in real implementation
		# For now just check basic rules
		illegal_reason_label.text = ""
		return true
	
	return false

func _should_snap_to_grid() -> bool:
	# Check settings for grid snap
	return Input.is_key_pressed(KEY_CTRL)

func _snap_to_grid(pos: Vector2) -> Vector2:
	# Snap to 0.5" increments
	var snap_px = Measurement.inches_to_px(0.5)
	return Vector2(
		round(pos.x / snap_px) * snap_px,
		round(pos.y / snap_px) * snap_px
	)

func _update_path_visual() -> void:
	# Use staged_path_visual for current drag
	staged_path_visual.clear_points()
	if current_path.size() < 2:
		return
	
	for point in current_path:
		staged_path_visual.add_point(point)
	
	# Color based on validity - yellow for staged, red for invalid
	staged_path_visual.default_color = Color.YELLOW if path_valid else Color.RED

func _clear_path_visual() -> void:
	staged_path_visual.clear_points()

func _update_staged_moves_visual() -> void:
	# Update individual path visuals for each model that has moved
	if not current_phase or not active_unit_id:
		return
	
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		return
	
	# Get staged moves from phase
	if current_phase != null and "active_moves" in current_phase:
		var active_moves = current_phase.active_moves
		if active_moves.has(active_unit_id):
			var move_data = active_moves[active_unit_id]
			
			# Group staged moves by model to build complete paths
			var models_with_segments = {}
			
			# Collect all segments for each model
			for staged_move in move_data.get("staged_moves", []):
				var model_id = staged_move.get("model_id", "")
				if model_id != "" and staged_move.has("from") and staged_move.has("dest"):
					if not models_with_segments.has(model_id):
						models_with_segments[model_id] = []
					models_with_segments[model_id].append(staged_move)
			
			# Create or update Line2D for each model with segments
			for model_id in models_with_segments:
				var segments = models_with_segments[model_id]
				
				# Get or create Line2D for this model
				var line: Line2D
				if model_path_visuals.has(model_id):
					line = model_path_visuals[model_id]
					line.clear_points()
				else:
					line = Line2D.new()
					line.name = "Path_" + model_id
					line.width = 2.0
					line.default_color = Color.YELLOW
					board_root.add_child(line)
					model_path_visuals[model_id] = line
				
				# Add all segments to create the complete path
				for i in range(segments.size()):
					var segment = segments[i]
					# For the first segment, add the 'from' point
					if i == 0:
						line.add_point(segment.from)
					# Always add the 'dest' point
					line.add_point(segment.dest)
			
			# Remove Line2D for models that no longer have paths
			var models_to_remove = []
			for model_id in model_path_visuals:
				if not models_with_segments.has(model_id):
					var line = model_path_visuals[model_id]
					if line and is_instance_valid(line):
						line.queue_free()
					models_to_remove.append(model_id)
			
			for model_id in models_to_remove:
				model_path_visuals.erase(model_id)

func _update_ruler_visual() -> void:
	ruler_visual.clear_points()
	if current_path.size() < 2:
		return
	
	# Show straight-line ruler
	ruler_visual.add_point(current_path[0])
	ruler_visual.add_point(current_path[-1])
	
	# Add distance text (would need Label3D in real implementation)

func _clear_ruler_visual() -> void:
	ruler_visual.clear_points()

func _show_ghost_visual(model: Dictionary) -> void:
	# Create semi-transparent preview of model
	_clear_ghost_visual()
	
	# Use TokenVisual for consistency
	var ghost_token = preload("res://scripts/TokenVisual.gd").new()
	ghost_token.radius = Measurement.base_radius_px(model.get("base_mm", 32))
	ghost_token.owner_player = GameState.get_active_player()
	ghost_token.is_preview = true
	ghost_token.model_number = 0  # Don't show number for ghost
	
	# Set the token at origin (0,0) relative to ghost_visual
	ghost_token.position = Vector2.ZERO
	ghost_visual.add_child(ghost_token)
	ghost_visual.modulate = Color(1, 1, 1, 0.5)  # Make semi-transparent
	
	print("Created ghost visual with radius: ", ghost_token.radius)

func _update_ghost_position(world_pos: Vector2) -> void:
	if ghost_visual:
		ghost_visual.position = world_pos
		# Debug: Show cursor and ghost positions
		print("Updating ghost position to: ", world_pos)

func _clear_ghost_visual() -> void:
	for child in ghost_visual.get_children():
		child.queue_free()

func _get_accumulated_distance() -> float:
	# Get distance for the currently selected model
	if not current_phase or not active_unit_id or selected_model.is_empty():
		return 0.0
	
	var model_id = selected_model.get("model_id", "")
	if model_id == "":
		return 0.0
	
	# Check if phase has active_moves data
	if current_phase.has_method("get_active_move_data"):
		var move_data = current_phase.get_active_move_data(active_unit_id)
		if move_data and move_data.has("model_distances"):
			# Return the distance for this specific model
			return move_data.model_distances.get(model_id, 0.0)
	elif current_phase != null and "active_moves" in current_phase:
		var active_moves = current_phase.active_moves
		if active_moves.has(active_unit_id):
			var move_data = active_moves[active_unit_id]
			if move_data.has("model_distances"):
				return move_data.model_distances.get(model_id, 0.0)
	
	return 0.0

func _update_movement_display() -> void:
	var accumulated = _get_accumulated_distance()
	if move_cap_label:
		move_cap_label.text = "Move: %.1f\"" % move_cap_inches
	if inches_used_label:
		if selected_model.is_empty():
			inches_used_label.text = "Staged: -"
		else:
			var model_id = selected_model.get("model_id", "")
			inches_used_label.text = "%s Used: %.1f\"" % [model_id, accumulated]
	if inches_left_label:
		if selected_model.is_empty():
			inches_left_label.text = "Left: -"
		else:
			inches_left_label.text = "Left: %.1f\"" % (move_cap_inches - accumulated)

func _update_end_phase_button() -> void:
	# Update End Phase button state based on whether there are active moves
	var end_phase_button = hud_bottom.get_node_or_null("MovementButtons/EndPhaseButton")
	if end_phase_button:
		# Button is disabled if there are active moves
		end_phase_button.disabled = active_unit_id != ""
		if active_unit_id != "":
			end_phase_button.tooltip_text = "Confirm or reset current move first"
		else:
			end_phase_button.tooltip_text = "End the Movement Phase and proceed to Shooting"

func _update_movement_display_with_preview(used: float, left: float, valid: bool) -> void:
	if move_cap_label:
		move_cap_label.text = "Move: %.1f\"" % move_cap_inches
	if inches_used_label:
		if selected_model.is_empty():
			inches_used_label.text = "Used: %.1f\"" % used
		else:
			var model_id = selected_model.get("model_id", "")
			inches_used_label.text = "%s: %.1f\"" % [model_id, used]
		inches_used_label.modulate = Color.WHITE if valid else Color.RED
	if inches_left_label:
		inches_left_label.text = "Left: %.1f\"" % left
		inches_left_label.modulate = Color.WHITE if left >= 0 else Color.RED

func _update_movement_display_with_advance(dice_result: int) -> void:
	# Get the current unit to calculate base movement
	if not current_phase or not active_unit_id:
		return
		
	var unit = current_phase.get_unit(active_unit_id)
	if unit.is_empty():
		return
	
	var base_movement = 6.0  # Default movement
	if unit.has("meta") and unit.meta.has("stats") and unit.meta.stats.has("move"):
		base_movement = float(unit.meta.stats.move)
	
	# Calculate new total movement (base + advance roll)
	var total_movement = base_movement + dice_result
	move_cap_inches = total_movement
	
	# Update the display to show the new total
	if move_cap_label:
		move_cap_label.text = "Move: %.1f\" (Base %d\" + Advance %d\")" % [total_movement, base_movement, dice_result]
	
	# Reset the used/left display since we haven't started moving yet
	if inches_used_label:
		inches_used_label.text = "Used: 0.0\""
		inches_used_label.modulate = Color.WHITE
	if inches_left_label:
		inches_left_label.text = "Left: %.1f\"" % total_movement
		inches_left_label.modulate = Color.WHITE

func _update_dice_log_display(dice_log: Array) -> void:
	if not dice_log_display:
		return
	
	dice_log_display.clear()
	for entry in dice_log:
		var text = "[b]%s[/b]: %s\n" % [entry.get("type", ""), entry.get("result", "")]
		if entry.has("rolls"):
			text += "Rolls: %s\n" % str(entry.rolls)
		text += "\n"
		dice_log_display.append_text(text)
