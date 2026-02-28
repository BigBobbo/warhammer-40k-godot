extends Node2D
class_name MovementController

const GameStateData = preload("res://autoloads/GameState.gd")


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

# Rotation and pivot state
var rotating_model: bool = false
var rotation_start_angle: float = 0.0
var model_start_rotation: float = 0.0
var pivot_cost_paid: bool = false
var pivot_cost_inches: float = 2.0  # Standard pivot cost

# Multi-selection state
var selected_models: Array = []  # Array of model dictionaries
var selection_mode: String = "SINGLE"  # SINGLE, MULTI, DRAG_BOX
var drag_box_active: bool = false
var drag_box_start: Vector2
var drag_box_end: Vector2
var selection_visual: Node2D  # Custom drawn selection box
var selection_indicators: Array = []  # Visual indicators for selected models
var group_dragging: bool = false
var group_drag_start_positions: Dictionary = {}  # model_id -> Vector2
var group_formation_offsets: Dictionary = {}  # model_id -> Vector2 (relative to group center)

# UI References
var board_view: Node2D
var path_visual: Line2D
var staged_path_visual: Line2D  # NEW: Visual for staged movements
var ruler_visual: Line2D
var ghost_visual: Node2D
var model_path_visuals: Dictionary = {}  # Dictionary of model_id -> Line2D for individual paths
var hud_bottom: Control
var hud_right: Control
var ui_setup_complete: bool = false  # Flag to prevent duplicate UI creation

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

# Flag to prevent duplicate actions when programmatically setting radio buttons
var setting_radio_programmatically: bool = false

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
	# Add to group so DisembarkController can find us
	add_to_group("movement_controller")

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

	# Clean up multi-selection visuals
	if selection_visual and is_instance_valid(selection_visual):
		selection_visual.queue_free()

	# Clean up selection indicators
	for indicator in selection_indicators:
		if indicator and is_instance_valid(indicator):
			indicator.queue_free()
	selection_indicators.clear()
	
	# Clean up UI containers
	var movement_info = get_node_or_null("/root/Main/HUD_Bottom/HBoxContainer/MovementInfo")
	if movement_info and is_instance_valid(movement_info):
		movement_info.queue_free()

	var movement_buttons = get_node_or_null("/root/Main/HUD_Bottom/HBoxContainer/MovementButtons")
	if movement_buttons and is_instance_valid(movement_buttons):
		movement_buttons.queue_free()

	# Clean up right panel elements (standard pattern)
	var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
	if container and is_instance_valid(container):
		var movement_elements = ["MovementScrollContainer", "MovementPanel"]
		for element in movement_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("MovementController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

	# Reset UI setup flag
	ui_setup_complete = false

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

	# Create selection box visual for drag-box selection (custom drawn)
	selection_visual = _SelectionBoxVisual.new()
	selection_visual.name = "MultiSelectionBox"
	selection_visual.visible = false
	board_root.add_child(selection_visual)

func _setup_bottom_hud() -> void:
	# NOTE: Main.gd now handles the phase action button
	# MovementController only manages movement-specific UI in the right panel
	pass

func _setup_right_panel() -> void:
	# Prevent duplicate UI creation
	if ui_setup_complete:
		print("MovementController: UI already setup, skipping duplicate creation")
		return

	# Main.gd already handles cleanup before controller creation
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)

	# Hide persistent UI elements (UnitListPanel, UnitCard)
	var persistent_unit_list = container.get_node_or_null("UnitListPanel")
	if persistent_unit_list:
		persistent_unit_list.visible = false  # Movement phase has its own unit list

	var unit_card = container.get_node_or_null("UnitCard")
	if unit_card:
		unit_card.visible = false  # Not used in movement phase

	# Check if movement scroll container already exists
	var scroll_container = container.get_node_or_null("MovementScrollContainer")
	if scroll_container:
		# Already exists, shouldn't happen but clean it up and recreate
		print("MovementController: WARNING - Removing existing MovementScrollContainer")
		container.remove_child(scroll_container)
		scroll_container.queue_free()

	# Create scroll container with standard naming
	scroll_container = ScrollContainer.new()
	scroll_container.name = "MovementScrollContainer"
	scroll_container.custom_minimum_size = Vector2(250, 400)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll_container)

	# Create movement panel with standard naming
	var movement_panel = VBoxContainer.new()
	movement_panel.name = "MovementPanel"
	movement_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(movement_panel)

	# SECTION 1: Unit List with Status
	_create_section1_unit_list(movement_panel)

	# SECTION 2: Selected Unit Details
	_create_section2_unit_details(movement_panel)

	# SECTION 3: Movement Mode Selection
	_create_section3_mode_selection(movement_panel)

	# SECTION 4: Action Buttons & Distance Info
	_create_section4_actions(movement_panel)

	# Mark UI setup as complete
	ui_setup_complete = true
	print("MovementController: UI setup complete")

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
	unit_mode_label.text = "Mode: Normal Move (Default)"
	section.add_child(unit_mode_label)

	# Add helpful hint
	var hint_label = Label.new()
	hint_label.text = "Drag models to move, or select a different mode below"
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.modulate = Color(0.7, 0.7, 0.7)  # Slightly dimmed hint text
	section.add_child(hint_label)

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
	WhiteDwarfTheme.apply_to_button(undo_button)
	button_container.add_child(undo_button)

	var reset_button = Button.new()
	reset_button.text = "Reset Unit"
	reset_button.pressed.connect(_on_reset_unit_pressed)
	WhiteDwarfTheme.apply_to_button(reset_button)
	button_container.add_child(reset_button)

	var confirm_button = Button.new()
	confirm_button.text = "Confirm Move"
	confirm_button.pressed.connect(_on_confirm_move_pressed)
	WhiteDwarfTheme.apply_to_button(confirm_button)
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

func set_phase(phase) -> void:  # Remove type hint to accept any phase
	# Only set if it's actually a MovementPhase
	if phase and phase.has_method("get_class"):
		print("MovementController: Received phase of type ", phase.get_class())
		
		# Check if it's a MovementPhase by checking for movement-specific signals
		if phase.has_signal("unit_move_begun"):
			current_phase = phase
			print("MovementController: Phase set successfully")
			
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
			if phase.has_signal("command_reroll_opportunity"):
				if not phase.command_reroll_opportunity.is_connected(_on_command_reroll_opportunity):
					phase.command_reroll_opportunity.connect(_on_command_reroll_opportunity)
			if phase.has_signal("overwatch_opportunity"):
				if not phase.overwatch_opportunity.is_connected(_on_overwatch_opportunity):
					phase.overwatch_opportunity.connect(_on_overwatch_opportunity)
			if phase.has_signal("rapid_ingress_opportunity"):
				if not phase.rapid_ingress_opportunity.is_connected(_on_rapid_ingress_opportunity):
					phase.rapid_ingress_opportunity.connect(_on_rapid_ingress_opportunity)

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
			
			# Show if unit is embarked (special case - can still be selected to disembark)
			if unit.get("embarked_in", null) != null:
				var transport = GameState.get_unit(unit.embarked_in)
				var transport_name = transport.get("meta", {}).get("name", unit.embarked_in) if transport else "Transport"
				status_text = " [Embarked in %s]" % transport_name

			unit_list.add_item(unit_name + status_text)
			unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
			added_units[unit_id] = true

func _on_unit_selected(index: int) -> void:
	var unit_id = unit_list.get_item_metadata(index)
	active_unit_id = unit_id
	print("MovementController: Unit selected - ", unit_id)

	# Check if unit is embarked and needs to disembark
	var unit = GameState.get_unit(unit_id)
	if unit and unit.get("embarked_in", null) != null:
		_handle_embarked_unit_selected(unit_id)
		return

	# Check if this unit already has an active move in the phase (e.g., an advance)
	# If so, don't send BEGIN_NORMAL_MOVE as it would overwrite the existing move data
	# (including advance roll and move cap)
	var has_existing_move = false
	if current_phase and current_phase.has_method("get_active_move_data"):
		var existing_move_data = current_phase.get_active_move_data(unit_id)
		if not existing_move_data.is_empty() and not existing_move_data.get("completed", false):
			has_existing_move = true
			# Restore the correct move cap from the existing active move
			var existing_cap = existing_move_data.get("move_cap_inches", -1.0)
			if existing_cap > 0:
				move_cap_inches = existing_cap
				print("MovementController: Unit %s already has active move (mode=%s, cap=%.1f\")" % [unit_id, existing_move_data.get("mode", "?"), move_cap_inches])
			active_mode = existing_move_data.get("mode", "NORMAL")

	if not has_existing_move:
		# Get unit movement cap
		if unit:
			move_cap_inches = get_unit_movement(unit)
			print("MovementController: Unit %s has movement cap of %.1f inches" % [unit_id, move_cap_inches])

		# Request phase to begin movement (this will trigger _on_unit_move_begun callback)
		if current_phase:
			var action = {
				"type": "BEGIN_NORMAL_MOVE",
				"actor_unit_id": unit_id
			}
			emit_signal("move_action_requested", action)

	_highlight_unit_models(unit_id)
	_update_selected_unit_display()  # NEW: Update section 2
	_update_fall_back_visibility()  # NEW: Update Fall Back visibility based on engagement
	_reset_mode_selection_for_new_unit(unit_id)  # NEW: Reset mode selection for new unit
	emit_signal("ui_update_requested")

# This function has been moved below to avoid duplication

func begin_unit_movement(unit_id: String) -> void:
	"""Begin movement for a unit (called after disembark if transport hasn't moved)"""
	print("MovementController: Beginning movement for unit ", unit_id)

	# Set this unit as active
	active_unit_id = unit_id
	active_mode = "NORMAL"  # Default to normal movement

	# Find unit in list and select it
	for i in range(unit_list.get_item_count()):
		if unit_list.get_item_metadata(i) == unit_id:
			unit_list.select(i)
			unit_list.emit_signal("item_selected", i)  # Ensure selection is processed
			break

	# Get unit data for movement cap
	var unit = GameState.get_unit(unit_id)
	if unit:
		move_cap_inches = get_unit_movement(unit)
		print("MovementController: Unit %s has movement cap of %d inches" % [unit_id, move_cap_inches])

		# Important: Set the unit's status to ensure it can be moved
		if unit.status == GameStateData.UnitStatus.DEPLOYED:
			print("MovementController: Unit status is DEPLOYED, ready to move")

	# Request normal move action from phase to initialize movement state
	if current_phase:
		print("MovementController: Sending BEGIN_NORMAL_MOVE action to phase")
		var action = {
			"type": "BEGIN_NORMAL_MOVE",
			"actor_unit_id": unit_id
		}
		emit_signal("move_action_requested", action)

		# Update UI
		_update_selected_unit_display()
		_update_fall_back_visibility()
		_reset_mode_selection_for_new_unit(unit_id)

		# Set normal mode as selected (programmatically, don't trigger signal)
		if normal_radio:
			setting_radio_programmatically = true
			normal_radio.button_pressed = true
			setting_radio_programmatically = false

		emit_signal("ui_update_requested")
	else:
		print("MovementController: WARNING - No current phase set, cannot begin movement")

		print("MovementController: Movement initiated for unit %s with mode %s" % [unit_id, active_mode])

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
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

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
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

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

	# The advance dice roll is handled by MovementPhase._process_begin_advance()
	# The result is read back in _on_unit_move_begun() to update the UI

func _on_fall_back_pressed() -> void:
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

	if active_unit_id == "":
		return
	
	var action = {
		"type": "BEGIN_FALL_BACK",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _on_remain_stationary_pressed() -> void:
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

	if active_unit_id == "":
		return
	
	var action = {
		"type": "REMAIN_STATIONARY",
		"actor_unit_id": active_unit_id,
		"payload": {}
	}
	emit_signal("move_action_requested", action)

	# Mark as completed immediately (no dragging needed)
	# Clear active unit since this unit is done
	active_unit_id = ""
	call_deferred("_update_selected_unit_display")

	# Refresh unit list to show this unit as moved
	if unit_list:
		call_deferred("_populate_unit_list")

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
			# Advance dice roll is handled by MovementPhase._process_begin_advance()
			# UI is updated in _on_unit_move_begun() from the phase's active_moves data
			pass
		"REMAIN_STATIONARY":
			_complete_stationary_move()
	
	# Update UI state
	_update_mode_buttons_state(false)  # Disable mode changes

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

		# Reset to default (Normal) selection
		active_mode = "NORMAL"  # Set mode variable
		if normal_radio:
			setting_radio_programmatically = true
			normal_radio.button_pressed = true
			setting_radio_programmatically = false

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
		# PRIORITY 1: Read move cap from phase's active_moves (most authoritative)
		# This is critical for advance moves where active_moves is set by _resolve_advance_roll
		# BEFORE the signal fires, but GameState flags aren't applied until after.
		var cap_from_active_moves = -1.0
		if current_phase.has_method("get_active_move_data"):
			var move_data = current_phase.get_active_move_data(unit_id)
			if not move_data.is_empty():
				cap_from_active_moves = move_data.get("move_cap_inches", -1.0)

		if cap_from_active_moves > 0:
			move_cap_inches = cap_from_active_moves
			print("Move cap from active_moves: ", move_cap_inches, " inches")
		else:
			# PRIORITY 2: Try unit flags, then fall back to unit stats
			var unit = null
			if current_phase.has_method("get_unit"):
				unit = current_phase.get_unit(unit_id)
			else:
				unit = GameState.get_unit(unit_id)

			if unit:
				var move_cap_from_flags = unit.get("flags", {}).get("move_cap_inches", -1.0)
				if move_cap_from_flags > 0:
					move_cap_inches = move_cap_from_flags
					print("Move cap from flags: ", move_cap_inches, " inches")
				else:
					move_cap_inches = get_unit_movement(unit)
					print("Move cap from unit stats: ", move_cap_inches, " inches")
			else:
				print("ERROR: Could not get unit data!")
		_update_movement_display()
	else:
		print("ERROR: No current phase set!")

	# Update dice log and advance roll display if it was an advance
	if mode == "ADVANCE" and current_phase:
		if current_phase.has_method("get_dice_log"):
			var dice_log = current_phase.get_dice_log()
			_update_dice_log_display(dice_log)
		# Read the advance roll from the phase's active_moves data and update UI
		if current_phase.has_method("get_active_move_data"):
			var move_data = current_phase.get_active_move_data(unit_id)
			var advance_roll = move_data.get("advance_roll", 0)
			if advance_roll > 0:
				if advance_roll_label:
					advance_roll_label.text = "Advance Roll: %d\"" % advance_roll
					advance_roll_label.visible = true
				# Always update the move cap for advance, regardless of label existence
				_update_movement_display_with_advance(advance_roll)

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
				# Multi-selection input handling
				if Input.is_key_pressed(KEY_CTRL):
					_handle_ctrl_click_selection(event.position)
				elif Input.is_key_pressed(KEY_SHIFT) and _should_start_drag_box():
					# Require Shift key for drag-box selection to avoid conflicts
					_start_drag_box_selection(event.position)
				elif selected_models.size() > 0:
					# Check if we're clicking on a selected model to start group drag
					if _is_clicking_on_selected_model(event.position):
						_start_group_movement(event.position)
					else:
						# Clicking elsewhere clears selection and starts single model selection
						_handle_single_model_selection(event.position)
				else:
					_handle_single_model_selection(event.position)
			else:
				if drag_box_active:
					_complete_drag_box_selection(event.position)
				elif group_dragging:
					_end_group_drag(event.position)
				elif dragging_model:
					print("MovementController: Mouse released, ending drag")
					_end_model_drag(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click for rotation
			if event.pressed:
				_start_model_rotation(event.position)
			else:
				if rotating_model:
					_end_model_rotation(event.position)
	elif event is InputEventMouseMotion:
		if drag_box_active:
			_update_drag_box_selection(event.position)
		elif group_dragging:
			_update_group_drag(event.position)
		elif dragging_model:
			_update_model_drag(event.position)
		elif rotating_model:
			_update_model_rotation(event.position)
		else:
			_update_hover_preview(event.position)
	elif event is InputEventKey and event.pressed:
		# Multi-selection keyboard shortcuts
		if event.keycode == KEY_A and Input.is_key_pressed(KEY_CTRL):
			_select_all_unit_models()
		elif event.keycode == KEY_ESCAPE:
			_clear_selection()
		# Keyboard rotation controls - work during dragging or when model selected
		elif (selected_model.size() > 0 or selected_models.size() > 0):
			if event.keycode == KEY_Q:
				_rotate_model_by_angle(-PI/12)  # Rotate 15 degrees left
			elif event.keycode == KEY_E:
				_rotate_model_by_angle(PI/12)  # Rotate 15 degrees right

func _start_model_drag(mouse_pos: Vector2) -> void:
	print("Starting model drag. Active unit: ", active_unit_id, " Mode: ", active_mode)

	if active_unit_id == "" or active_mode == "":
		print("Cannot drag - no active unit or mode")
		return

	# Sync move_cap_inches from phase's active_moves (authoritative source)
	# This prevents stale cap values from overriding the advance bonus
	if current_phase and current_phase.has_method("get_active_move_data"):
		var move_data = current_phase.get_active_move_data(active_unit_id)
		if not move_data.is_empty():
			var phase_cap = move_data.get("move_cap_inches", -1.0)
			if phase_cap > 0 and abs(phase_cap - move_cap_inches) > 0.01:
				print("MovementController: Syncing move_cap from active_moves: %.1f -> %.1f" % [move_cap_inches, phase_cap])
				move_cap_inches = phase_cap
	
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

	# Add terrain penalty (elevation changes for non-FLY units)
	var terrain_penalty = _get_terrain_penalty_for_move(drag_start_pos, world_pos)
	distance_inches += terrain_penalty

	# Get the model's already accumulated distance
	var already_used = _get_accumulated_distance()
	var total_distance = already_used + distance_inches
	var inches_left = move_cap_inches - total_distance

	# Check validity based on total distance
	path_valid = total_distance <= move_cap_inches

	# Also check for model overlaps, wall collisions, and board edge
	var overlap_detected = false
	var out_of_bounds = false
	var overlap_reason = ""
	if path_valid and current_phase:
		# Check model overlap
		overlap_detected = _check_position_would_overlap(world_pos)
		if overlap_detected:
			path_valid = false
			# Check which type of overlap it is
			var test_model = selected_model.duplicate()
			test_model["position"] = world_pos
			if Measurement.model_overlaps_any_wall(test_model):
				overlap_reason = "Cannot overlap with walls"
			else:
				overlap_reason = "Cannot overlap other models"
			if illegal_reason_label:
				illegal_reason_label.text = overlap_reason

	# Check board edge - no part of model base can extend beyond the battlefield
	if not overlap_detected and selected_model:
		out_of_bounds = _is_position_outside_board(world_pos, selected_model)
		if out_of_bounds:
			path_valid = false
			if illegal_reason_label:
				illegal_reason_label.text = "Cannot move beyond the board edge"
				illegal_reason_label.modulate = Color.RED

	# Clear error label when position is valid
	if not overlap_detected and not out_of_bounds and total_distance <= move_cap_inches:
		if illegal_reason_label:
			illegal_reason_label.text = ""

	# Update visuals
	_update_path_visual()
	_update_ruler_visual()
	_update_ghost_position(world_pos)
	_update_ghost_validity(!overlap_detected and !out_of_bounds and total_distance <= move_cap_inches)
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

	# Add terrain penalty (elevation changes for non-FLY units)
	var terrain_penalty = _get_terrain_penalty_for_move(drag_start_pos, world_pos)
	distance_inches += terrain_penalty
	print("Distance moved: ", distance_inches, " inches (terrain penalty: ", terrain_penalty, ")")

	# Get accumulated distance to check against cap
	var accumulated = _get_accumulated_distance()
	var total_distance = accumulated + distance_inches
	var valid = total_distance <= move_cap_inches

	# Also check for model overlap
	var overlap_detected = false
	if valid and current_phase:
		overlap_detected = _check_position_would_overlap(world_pos)
		if overlap_detected:
			valid = false
			print("Move rejected: position would overlap with another model")

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
				"dest": [world_pos.x, world_pos.y],
				"rotation": selected_model.get("rotation", 0.0)  # Preserve rotation
			}
		}
		print("  Action: ", action)
		emit_signal("move_action_requested", action)
	else:
		if overlap_detected:
			print("Move invalid: position would overlap with another model")
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

	# FIRST: Check visual tokens on the board for actual positions
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if token_layer:
		var closest_model = {}
		var closest_distance = INF

		for child in token_layer.get_children():
			if not child.has_meta("unit_id") or not child.has_meta("model_id"):
				continue

			var unit_id = child.get_meta("unit_id")
			var model_id = child.get_meta("model_id")

			# Get the actual visual position of the token
			var visual_pos = child.position
			var distance = world_pos.distance_to(visual_pos)

			# Check if within tolerance + base radius
			var base_radius = 16.0  # Default 32mm base
			if child.has_method("get_base_radius"):
				base_radius = child.get_base_radius()
			elif child.has_meta("base_mm"):
				base_radius = Measurement.base_radius_px(child.get_meta("base_mm"))

			if distance <= (base_radius + tolerance) and distance < closest_distance:
				closest_distance = distance
				# Fetch complete model data from GameState for proper shape handling
				var unit = GameState.get_unit(unit_id)
				if not unit.is_empty():
					var models = unit.get("models", [])
					for model_data in models:
						if model_data.get("id", "") == model_id:
							# Return complete model data including base_type, base_dimensions, rotation
							closest_model = model_data.duplicate()
							closest_model["unit_id"] = unit_id
							closest_model["model_id"] = model_id
							closest_model["position"] = visual_pos
							print("DEBUG MovementController: Found model via token visual, fetched complete data from GameState")
							print("  base_mm: ", closest_model.get("base_mm", "NOT SET"))
							print("  base_type: ", closest_model.get("base_type", "NOT SET"))
							print("  base_dimensions: ", closest_model.get("base_dimensions", "NOT SET"))
							break

		if not closest_model.is_empty():
			return closest_model

	# FALLBACK: If no visual tokens found, use game state
	# Get units for both players and combine them
	var all_units = {}
	var player1_units = GameState.get_units_for_player(1)
	var player2_units = GameState.get_units_for_player(2)
	for unit_id in player1_units:
		all_units[unit_id] = player1_units[unit_id]
	for unit_id in player2_units:
		all_units[unit_id] = player2_units[unit_id]

	var closest_model = {}
	var closest_distance = INF

	for unit_id in all_units:
		var unit = all_units[unit_id]
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
			
			# Use shape-aware collision detection with tolerance
			var base_shape = Measurement.create_base_shape(model)
			var model_rotation = model.get("rotation", 0.0)
			var distance = world_pos.distance_to(model_pos)

			# For tolerance, we'll expand the shape check or use distance as fallback
			var within_shape = base_shape.contains_point(world_pos, model_pos, model_rotation)
			var within_tolerance = distance <= tolerance

			if within_shape or within_tolerance:
				if distance < closest_distance:
					closest_distance = distance
					# Return complete model data for proper shape handling
					closest_model = model.duplicate()
					closest_model["unit_id"] = unit_id
					closest_model["model_id"] = model.get("id", "m%d" % (i+1))
					closest_model["position"] = model_pos
	
	return closest_model

func _get_model_at_position(world_pos: Vector2) -> Dictionary:
	# Find which model is at the given position
	# Returns {unit_id, model_id, position, base_mm} or empty dict

	if not current_phase:
		print("No current phase for model detection")
		return {}

	# FIRST: Check visual tokens on the board for actual positions
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if token_layer:
		var closest_model = {}
		var closest_distance = INF

		for child in token_layer.get_children():
			if not child.has_meta("unit_id") or not child.has_meta("model_id"):
				continue

			var unit_id = child.get_meta("unit_id")
			var model_id = child.get_meta("model_id")

			# Get the actual visual position of the token
			var visual_pos = child.position
			var distance = world_pos.distance_to(visual_pos)

			# Get base size from the model data or use default
			var base_radius = 16.0  # Default 32mm base
			if child.has_method("get_base_radius"):
				base_radius = child.get_base_radius()
			elif child.has_meta("base_mm"):
				base_radius = Measurement.base_radius_px(child.get_meta("base_mm"))

			# Check if position is within the model's base
			if distance <= base_radius:
				if distance < closest_distance:
					closest_distance = distance
					# Fetch complete model data from GameState for proper shape handling
					var unit = GameState.get_unit(unit_id)
					if not unit.is_empty():
						var models = unit.get("models", [])
						for model_data in models:
							if model_data.get("id", "") == model_id:
								# Return complete model data including base_type, base_dimensions, rotation
								closest_model = model_data.duplicate()
								closest_model["unit_id"] = unit_id
								closest_model["model_id"] = model_id
								closest_model["position"] = visual_pos
								print("DEBUG MovementController._get_model_at_position: Fetched complete data from GameState")
								print("  base_mm: ", closest_model.get("base_mm", "NOT SET"))
								print("  base_type: ", closest_model.get("base_type", "NOT SET"))
								print("  base_dimensions: ", closest_model.get("base_dimensions", "NOT SET"))
								break

		if not closest_model.is_empty():
			return closest_model

	# FALLBACK: If no visual tokens found, use game state (for initialization)
	# Get units for both players and combine them
	var all_units = {}
	var player1_units = GameState.get_units_for_player(1)
	var player2_units = GameState.get_units_for_player(2)
	for unit_id in player1_units:
		all_units[unit_id] = player1_units[unit_id]
	for unit_id in player2_units:
		all_units[unit_id] = player2_units[unit_id]

	var closest_model = {}
	var closest_distance = INF

	for unit_id in all_units:
		var unit = all_units[unit_id]
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
			
			# Use shape-aware collision detection
			var base_shape = Measurement.create_base_shape(model)
			var model_rotation = model.get("rotation", 0.0)

			# Check if click is within model's base using proper shape
			if base_shape.contains_point(world_pos, model_pos, model_rotation):
				var distance = world_pos.distance_to(model_pos)
				# Use closest model if multiple overlap
				if distance < closest_distance:
					closest_distance = distance
					closest_model = model.duplicate()  # Copy all model data
					# Add movement-specific fields
					closest_model["unit_id"] = unit_id
					closest_model["model_id"] = model_id
					closest_model["position"] = model_pos
					closest_model["is_staged"] = staged_pos_found
	
	if not closest_model.is_empty():
		print("Found model at distance ", closest_distance, " pixels")
		if closest_model.get("is_staged", false):
			print("  - Model is at staged position")
		else:
			print("  - Model is at original position")
	else:
		# Debug: Show all model positions (both staged and original)
		print("No model found at ", world_pos, ". Model positions:")
		for unit_id in all_units:
			var unit = all_units[unit_id]
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
	
	# Check terrain traversal
	if not _validate_terrain_traversal(path):
		# Error message set by the traversal function
		return false
	
	# Check end position for engagement range
	if path.size() >= 2:
		var end_pos = path[-1]
		# Simplified check - would call phase validation in real implementation
		# For now just check basic rules
		illegal_reason_label.text = ""
		return true
	
	return false

func _validate_terrain_traversal(path: Array) -> bool:
	# Check if the movement path can traverse terrain based on unit type
	if path.size() < 2:
		return true
	
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		return true
	
	var keywords = unit.get("meta", {}).get("keywords", [])
	var is_infantry = "INFANTRY" in keywords
	var is_vehicle = "VEHICLE" in keywords
	var is_monster = "MONSTER" in keywords
	
	# Check each segment of the path
	for i in range(path.size() - 1):
		var start_pos = path[i]
		var end_pos = path[i + 1]
		
		# Check if path segment crosses terrain
		for terrain_piece in TerrainManager.terrain_features:
			if TerrainManager.check_line_intersects_terrain(start_pos, end_pos, terrain_piece):
				# Check if unit can move through this terrain
				if not TerrainManager.can_unit_move_through_terrain(keywords, terrain_piece):
					if is_vehicle:
						illegal_reason_label.text = "Vehicles cannot move through ruins"
					elif is_monster:
						illegal_reason_label.text = "Monsters cannot move through ruins"
					else:
						illegal_reason_label.text = "Cannot move through terrain"
					return false

			# Check walls within this terrain piece
			var walls = terrain_piece.get("walls", [])
			for wall in walls:
				if TerrainManager.check_line_intersects_wall(start_pos, end_pos, wall):
					if not TerrainManager.can_unit_cross_wall(keywords, wall):
						if is_vehicle:
							illegal_reason_label.text = "Vehicles cannot move through walls"
						elif is_monster:
							illegal_reason_label.text = "Monsters cannot move through walls"
						else:
							illegal_reason_label.text = "Cannot move through wall"
						return false

	return true

func _handle_embarked_unit_selected(unit_id: String) -> void:
	"""Handle selection of an embarked unit - show disembark dialog"""
	var unit = GameState.get_unit(unit_id)
	if not unit:
		return

	print("MovementController: Unit %s is embarked, showing disembark dialog" % unit_id)

	# Create and show disembark dialog
	var dialog_script = load("res://scripts/DisembarkDialog.gd")
	var dialog = dialog_script.new()
	dialog.setup(unit_id)
	dialog.disembark_confirmed.connect(_on_disembark_confirmed.bind(unit_id))
	dialog.disembark_canceled.connect(_on_disembark_canceled.bind(unit_id))

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_disembark_confirmed(unit_id: String) -> void:
	"""Handle disembark confirmation - start placement controller"""
	print("MovementController: Starting disembark placement for unit %s" % unit_id)

	# Create disembark controller for model placement
	var controller = preload("res://scripts/DisembarkController.gd").new()
	controller.disembark_completed.connect(_on_disembark_completed)
	controller.disembark_canceled.connect(_on_disembark_canceled)

	# Add to scene
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if board_root:
		board_root.add_child(controller)
	else:
		get_tree().root.add_child(controller)

	# Start disembark placement
	controller.start_disembark(unit_id)

func _on_disembark_completed(unit_id: String, positions: Array) -> void:
	"""Handle successful disembark - route through action system for multiplayer sync"""
	print("MovementController: Disembark completed for unit %s with %d positions" % [unit_id, positions.size()])

	# Serialize positions for action payload (Vector2 -> dict for network transport)
	var serialized_positions = []
	for pos in positions:
		serialized_positions.append({"x": pos.x, "y": pos.y})

	# Route through action system instead of calling TransportManager directly
	var action = {
		"type": "CONFIRM_DISEMBARK",
		"actor_unit_id": unit_id,
		"payload": {
			"positions": serialized_positions
		}
	}
	print("MovementController: Routing CONFIRM_DISEMBARK through action system")
	emit_signal("move_action_requested", action)

func _on_disembark_canceled(unit_id: String) -> void:
	"""Handle canceled disembark"""
	print("MovementController: Disembark canceled for unit %s" % unit_id)

	# Clear selection
	active_unit_id = ""
	_update_selected_unit_display()

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

	# Use GhostVisual for preview
	var ghost_token = preload("res://scripts/GhostVisual.gd").new()
	ghost_token.owner_player = GameState.get_active_player()
	ghost_token.is_valid_position = true  # Start as valid
	# Set the complete model data for shape handling (this sets up the base shape)
	ghost_token.set_model_data(model)

	# Set initial rotation if model has one
	if model.has("rotation"):
		ghost_token.set_base_rotation(model.get("rotation", 0.0))

	# Set the token at origin (0,0) relative to ghost_visual
	ghost_token.position = Vector2.ZERO
	ghost_visual.add_child(ghost_token)
	ghost_visual.modulate = Color(1, 1, 1, 0.8)  # Slightly transparent

	print("Created ghost visual for model")

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
	if move_cap_label:
		move_cap_label.text = "Move: %.1f\"" % move_cap_inches

	# Handle group selection display
	if selected_models.size() > 1:
		_update_group_movement_display()
	elif selected_models.size() == 1:
		# Single model from multi-selection
		var model_data = selected_models[0]
		var model_id = model_data.get("model_id", "")
		var accumulated = _get_model_accumulated_distance(model_id)

		if inches_used_label:
			inches_used_label.text = "%s Used: %.1f\"" % [model_id, accumulated]
		if inches_left_label:
			inches_left_label.text = "Left: %.1f\"" % (move_cap_inches - accumulated)
	elif not selected_model.is_empty():
		# Original single model selection
		var accumulated = _get_accumulated_distance()
		var model_id = selected_model.get("model_id", "")

		if inches_used_label:
			inches_used_label.text = "%s Used: %.1f\"" % [model_id, accumulated]
		if inches_left_label:
			inches_left_label.text = "Left: %.1f\"" % (move_cap_inches - accumulated)
	else:
		# No selection
		if inches_used_label:
			inches_used_label.text = "Staged: -"
		if inches_left_label:
			inches_left_label.text = "Left: -"

func _get_model_accumulated_distance(model_id: String) -> float:
	"""Get accumulated distance for a specific model"""
	if not current_phase or not active_unit_id or model_id == "":
		return 0.0

	# Check if phase has active_moves data
	if current_phase.has_method("get_active_move_data"):
		var move_data = current_phase.get_active_move_data(active_unit_id)
		if move_data and move_data.has("model_distances"):
			return move_data.model_distances.get(model_id, 0.0)
	elif current_phase != null and "active_moves" in current_phase:
		var active_moves = current_phase.active_moves
		if active_moves.has(active_unit_id):
			var move_data = active_moves[active_unit_id]
			if move_data.has("model_distances"):
				return move_data.model_distances.get(model_id, 0.0)

	return 0.0


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

# Rotation functions
func _start_model_rotation(mouse_pos: Vector2) -> void:
	if selected_model.is_empty():
		return

	# Check if model has a non-circular base
	var base_type = selected_model.get("base_type", "circular")
	if base_type == "circular":
		return  # No rotation needed for circular bases

	rotating_model = true
	var model_pos = selected_model.get("position", Vector2.ZERO)
	var to_mouse = mouse_pos - model_pos
	rotation_start_angle = to_mouse.angle()
	model_start_rotation = selected_model.get("rotation", 0.0)

	print("Starting rotation for model with base type: ", base_type)

func _update_model_rotation(mouse_pos: Vector2) -> void:
	if not rotating_model or selected_model.is_empty():
		return

	var model_pos = selected_model.get("position", Vector2.ZERO)
	var to_mouse = mouse_pos - model_pos
	var current_angle = to_mouse.angle()
	var angle_diff = current_angle - rotation_start_angle

	var new_rotation = model_start_rotation + angle_diff
	_apply_rotation_to_model(new_rotation)

func _end_model_rotation(mouse_pos: Vector2) -> void:
	if not rotating_model:
		return

	rotating_model = false
	_check_and_apply_pivot_cost()

	print("Ended rotation. New rotation: ", selected_model.get("rotation", 0.0))

func _rotate_model_by_angle(angle: float) -> void:
	if selected_model.is_empty():
		return

	var base_type = selected_model.get("base_type", "circular")
	if base_type == "circular":
		return

	var current_rotation = selected_model.get("rotation", 0.0)
	var new_rotation = current_rotation + angle
	_apply_rotation_to_model(new_rotation)
	_check_and_apply_pivot_cost()

func _apply_rotation_to_model(new_rotation: float) -> void:
	# Update the model's rotation
	selected_model["rotation"] = new_rotation

	# Update the model in GameState
	var unit = GameState.get_unit(active_unit_id)
	if unit:
		var models = unit.get("models", [])
		var model_id = selected_model.get("id", selected_model.get("model_id", ""))
		for i in range(models.size()):
			if models[i].get("id", "m%d" % (i+1)) == model_id:
				models[i]["rotation"] = new_rotation
				break

	# Update the visual if it exists
	if current_phase and current_phase.has_method("update_model_rotation"):
		current_phase.update_model_rotation(active_unit_id, selected_model["id"], new_rotation)

	# Update any ghost visual with the new rotation
	if ghost_visual and ghost_visual.get_child_count() > 0:
		var ghost_token = ghost_visual.get_child(0)
		# Use set_base_rotation for immediate visual update
		if ghost_token.has_method("set_base_rotation"):
			ghost_token.set_base_rotation(new_rotation)
		elif ghost_token.has_method("set_model_data"):
			# Fallback: update complete model data
			ghost_token.set_model_data(selected_model)
			ghost_token.queue_redraw()

	# Update token visual directly
	_update_model_token_visual(selected_model)

func _check_and_apply_pivot_cost() -> void:
	if pivot_cost_paid:
		return  # Already paid this movement

	# Check if this model needs pivot cost
	var base_type = selected_model.get("base_type", "circular")
	if base_type == "circular":
		return  # No pivot cost for circular bases

	# Check if model is a vehicle or monster
	var keywords = selected_model.get("meta", {}).get("keywords", [])
	var needs_pivot_cost = false
	for keyword in keywords:
		if keyword in ["VEHICLE", "MONSTER"]:
			needs_pivot_cost = true
			break

	if not needs_pivot_cost:
		return

	# Apply pivot cost
	pivot_cost_paid = true
	var remaining_movement = move_cap_inches - _get_accumulated_distance()
	remaining_movement -= pivot_cost_inches

	if remaining_movement < 0:
		print("WARNING: Pivot cost exceeds remaining movement!")
		# Show warning to player
		if illegal_reason_label:
			illegal_reason_label.text = "Pivot cost exceeds movement!"
			illegal_reason_label.modulate = Color.RED

	print("Applied pivot cost of ", pivot_cost_inches, " inches")
	_update_movement_display()

func _reset_pivot_cost() -> void:
	pivot_cost_paid = false

func _update_model_token_visual(model: Dictionary) -> void:
	# Find and update the token visual directly
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if not token_layer:
		return

	var unit_id = model.get("unit_id", "")
	var model_id = model.get("id", model.get("model_id", ""))

	for child in token_layer.get_children():
		if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id and \
		   child.has_meta("model_id") and child.get_meta("model_id") == model_id:
			if child.has_method("set_model_data"):
				child.set_model_data(model)
				child.queue_redraw()
			break

func _get_terrain_penalty_for_move(from_pos: Vector2, to_pos: Vector2) -> float:
	"""Calculate terrain penalty via TerrainManager.
	Units always stay on ground floor — no height penalty. Only difficult ground applies."""
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if not terrain_manager or not terrain_manager.has_method("calculate_movement_terrain_penalty"):
		return 0.0
	# Check if the active unit has FLY keyword
	var has_fly = false
	if active_unit_id != "":
		var unit = GameState.get_unit(active_unit_id)
		var keywords = unit.get("meta", {}).get("keywords", [])
		has_fly = "FLY" in keywords
	return terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, has_fly)

func _check_position_would_overlap(position: Vector2) -> bool:
	# Check if placing the selected model at the given position would overlap
	if not current_phase or selected_model.is_empty():
		return false

	var unit_id = selected_model.get("unit_id", "")
	var model_id = selected_model.get("model_id", "")

	# Use the MovementPhase's overlap check function
	if current_phase.has_method("_position_overlaps_other_models"):
		var model_copy = selected_model.duplicate()
		model_copy["position"] = position
		if current_phase._position_overlaps_other_models(unit_id, model_id, position, model_copy):
			return true

	# Also check wall overlap
	if selected_model:
		var test_model = selected_model.duplicate()
		test_model["position"] = position
		if Measurement.model_overlaps_any_wall(test_model):
			return true

	return false

func _is_position_outside_board(pos: Vector2, model: Dictionary) -> bool:
	# Check if any part of the model's base would extend beyond the board edges
	var board_width_px = SettingsService.get_board_width_px()
	var board_height_px = SettingsService.get_board_height_px()

	# Get the model's base bounds
	var base_shape = Measurement.create_base_shape(model)
	var bounds = base_shape.get_bounds()
	var half_width = bounds.size.x / 2.0
	var half_height = bounds.size.y / 2.0

	# Check if any edge of the base extends beyond the board
	if pos.x - half_width < 0 or pos.x + half_width > board_width_px:
		return true
	if pos.y - half_height < 0 or pos.y + half_height > board_height_px:
		return true

	return false

func _update_ghost_validity(is_valid: bool) -> void:
	# Update the ghost visual to show if position is valid
	if ghost_visual and ghost_visual.get_child_count() > 0:
		var ghost_token = ghost_visual.get_child(0)
		if ghost_token.has_method("set_validity"):
			ghost_token.set_validity(is_valid)
		elif ghost_token.has_method("is_valid_position"):
			ghost_token.is_valid_position = is_valid
			ghost_token.queue_redraw()

# MULTI-SELECTION SYSTEM FUNCTIONS

func _handle_ctrl_click_selection(mouse_pos: Vector2) -> void:
	"""Handle Ctrl+click for multi-model selection/deselection"""
	if active_unit_id == "" or active_mode == "":
		print("Cannot select - no active unit or mode")
		return

	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	var model = _get_model_at_position(world_pos)
	if model.is_empty():
		model = _get_model_near_position(world_pos, 10.0)
		if model.is_empty():
			return

	if model.unit_id != active_unit_id:
		print("Model belongs to different unit: ", model.unit_id, " vs ", active_unit_id)
		return

	# Check if model is already selected
	var model_index = _find_selected_model_index(model.model_id)
	if model_index >= 0:
		# Deselect the model
		selected_models.remove_at(model_index)
		print("Deselected model: ", model.model_id)
	else:
		# Select the model
		selected_models.append(model)
		print("Selected model: ", model.model_id)

	selection_mode = "MULTI" if selected_models.size() > 1 else "SINGLE"
	_update_model_selection_visuals()
	_update_movement_display()

func _handle_single_model_selection(mouse_pos: Vector2) -> void:
	"""Handle single model selection (clears existing multi-selection)"""
	# Clear existing multi-selection
	_clear_selection()

	# Proceed with existing single model selection logic
	_start_model_drag(mouse_pos)

func _should_start_drag_box() -> bool:
	"""Determine if we should start drag-box selection (requires Shift key)"""
	# Start drag box only when Shift is held and we're not clicking directly on a model
	# This prevents conflicts with normal drag-to-move operations
	# Convert screen position to board-local coords before checking model overlap
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2
	if board_root:
		world_pos = board_root.transform.affine_inverse() * get_viewport().get_mouse_position()
	else:
		world_pos = get_global_mouse_position()
	return not _is_clicking_on_model(world_pos)

func _is_clicking_on_model(world_pos: Vector2) -> bool:
	"""Check if the mouse position is over a model"""
	var model = _get_model_at_position(world_pos)
	if model.is_empty():
		model = _get_model_near_position(world_pos, 10.0)
	return not model.is_empty()

func _is_clicking_on_selected_model(mouse_pos: Vector2) -> bool:
	"""Check if the mouse position is over one of the selected models"""
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	var clicked_model = _get_model_at_position(world_pos)
	if clicked_model.is_empty():
		clicked_model = _get_model_near_position(world_pos, 10.0)
		if clicked_model.is_empty():
			return false

	# Check if this model is in our selected models list
	var clicked_model_id = clicked_model.get("model_id", "")
	for selected_model in selected_models:
		if selected_model.get("model_id", "") == clicked_model_id:
			return true

	return false

func _start_drag_box_selection(mouse_pos: Vector2) -> void:
	"""Start drag-box selection"""
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	drag_box_active = true
	drag_box_start = world_pos
	drag_box_end = world_pos
	selection_mode = "DRAG_BOX"

	# Show selection box
	if selection_visual:
		selection_visual.visible = true
		_update_drag_box_visual()

	print("Started drag-box selection at: ", world_pos)

func _update_drag_box_selection(mouse_pos: Vector2) -> void:
	"""Update drag-box selection during mouse drag"""
	if not drag_box_active:
		return

	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	drag_box_end = world_pos
	_update_drag_box_visual()

func _complete_drag_box_selection(mouse_pos: Vector2) -> void:
	"""Complete drag-box selection and select models within the box"""
	if not drag_box_active:
		return

	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	drag_box_end = world_pos
	drag_box_active = false

	# Hide selection box
	if selection_visual:
		selection_visual.visible = false

	# Select models within the drag box
	_select_models_in_box()

	# Update selection mode
	selection_mode = "MULTI" if selected_models.size() > 1 else "SINGLE"
	_update_model_selection_visuals()
	_update_movement_display()

	print("Completed drag-box selection. Selected ", selected_models.size(), " models")

func _update_drag_box_visual() -> void:
	"""Update the visual representation of the drag box"""
	if not selection_visual or not drag_box_active:
		return

	var min_pos = Vector2(min(drag_box_start.x, drag_box_end.x), min(drag_box_start.y, drag_box_end.y))
	var max_pos = Vector2(max(drag_box_start.x, drag_box_end.x), max(drag_box_start.y, drag_box_end.y))
	var box_size = max_pos - min_pos

	# Only show if drag box is large enough
	if box_size.length() > 10.0:
		selection_visual.position = min_pos
		selection_visual.box_size = box_size
		selection_visual.visible = true
		selection_visual.queue_redraw()
		# Show live preview of which models would be selected
		_update_drag_box_preview(min_pos, max_pos)
	else:
		selection_visual.visible = false
		_clear_selection_indicators()

func _update_drag_box_preview(min_pos: Vector2, max_pos: Vector2) -> void:
	"""Show live preview highlights on models inside the current drag box"""
	_clear_selection_indicators()

	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root or active_unit_id == "":
		return

	# Try visual tokens first
	var found_via_tokens = false
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if token_layer:
		for child in token_layer.get_children():
			if not child.has_meta("unit_id") or child.get_meta("unit_id") != active_unit_id:
				continue
			if not child.has_meta("model_id"):
				continue

			found_via_tokens = true
			var visual_pos = child.position
			if visual_pos.x >= min_pos.x and visual_pos.x <= max_pos.x and \
			   visual_pos.y >= min_pos.y and visual_pos.y <= max_pos.y:
				var base_radius = 16.0
				if child.has_method("get_base_radius"):
					base_radius = child.get_base_radius()
				elif child.has_meta("base_mm"):
					base_radius = Measurement.base_radius_px(child.get_meta("base_mm"))
				var indicator = _create_selection_ring_indicator(visual_pos, base_radius)
				if indicator:
					board_root.add_child(indicator)
					selection_indicators.append(indicator)

	# Fallback to GameState positions
	if not found_via_tokens:
		var unit = GameState.get_unit(active_unit_id)
		if unit.is_empty():
			return
		var models = unit.get("models", [])
		for model in models:
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

			if model_pos.x >= min_pos.x and model_pos.x <= max_pos.x and \
			   model_pos.y >= min_pos.y and model_pos.y <= max_pos.y:
				var base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
				var indicator = _create_selection_ring_indicator(model_pos, base_radius)
				if indicator:
					board_root.add_child(indicator)
					selection_indicators.append(indicator)

func _select_models_in_box() -> void:
	"""Select all models from the active unit within the drag box"""
	if not current_phase or active_unit_id == "":
		print("_select_models_in_box: No current_phase or active_unit_id")
		return

	# Clear existing selection
	_clear_selection()

	# Define the selection rectangle
	var min_pos = Vector2(min(drag_box_start.x, drag_box_end.x), min(drag_box_start.y, drag_box_end.y))
	var max_pos = Vector2(max(drag_box_start.x, drag_box_end.x), max(drag_box_start.y, drag_box_end.y))

	print("Selecting models in box from (", min_pos, ") to (", max_pos, ") active_unit: ", active_unit_id)

	# FIRST: Try visual tokens on the board
	var found_via_tokens = false
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if token_layer:
		for child in token_layer.get_children():
			if not child.has_meta("unit_id") or child.get_meta("unit_id") != active_unit_id:
				continue
			if not child.has_meta("model_id"):
				continue

			found_via_tokens = true
			var model_id = child.get_meta("model_id")
			var visual_pos = child.position

			if visual_pos.x >= min_pos.x and visual_pos.x <= max_pos.x and \
			   visual_pos.y >= min_pos.y and visual_pos.y <= max_pos.y:
				# Skip duplicates (TokenLayer may have duplicate tokens)
				if _find_selected_model_index(model_id) >= 0:
					continue
				var model = _get_model_by_id(active_unit_id, model_id)
				if model.is_empty():
					continue
				var model_data = model.duplicate()
				model_data["unit_id"] = active_unit_id
				model_data["model_id"] = model_id
				model_data["position"] = visual_pos
				selected_models.append(model_data)
				print("  Selected model ", model_id, " at visual position ", visual_pos)

	# FALLBACK: If no tokens found for this unit, use GameState positions
	if not found_via_tokens:
		print("  Falling back to GameState positions for unit: ", active_unit_id)
		var unit = GameState.get_unit(active_unit_id)
		if unit.is_empty():
			return
		var models = unit.get("models", [])
		var move_data = {}
		if current_phase.has_method("get_active_move_data"):
			move_data = current_phase.get_active_move_data(active_unit_id)

		for model in models:
			if not model.get("alive", true):
				continue
			var model_id = model.get("id", "")
			var model_pos: Vector2

			# Check staged position first
			var staged_pos_found = false
			if move_data.has("staged_moves"):
				for staged_move in move_data.staged_moves:
					if staged_move.get("model_id") == model_id:
						model_pos = staged_move.get("dest", Vector2.ZERO)
						staged_pos_found = true
						break

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

			print("  GameState model ", model_id, " pos=", model_pos)
			if model_pos.x >= min_pos.x and model_pos.x <= max_pos.x and \
			   model_pos.y >= min_pos.y and model_pos.y <= max_pos.y:
				var model_data = model.duplicate()
				model_data["unit_id"] = active_unit_id
				model_data["model_id"] = model_id
				model_data["position"] = model_pos
				selected_models.append(model_data)
				print("  Selected model ", model_id, " at GameState position ", model_pos)

func _find_selected_model_index(model_id: String) -> int:
	"""Find the index of a model in the selected_models array"""
	for i in range(selected_models.size()):
		if selected_models[i].get("model_id", "") == model_id:
			return i
	return -1

func _clear_selection() -> void:
	"""Clear all selected models and visual indicators"""
	selected_models.clear()
	selection_mode = "SINGLE"
	_clear_selection_indicators()
	_update_movement_display()

func _clear_selection_indicators() -> void:
	"""Clear all visual selection indicators"""
	for indicator in selection_indicators:
		if indicator and is_instance_valid(indicator):
			indicator.queue_free()
	selection_indicators.clear()

func _update_model_selection_visuals() -> void:
	"""Update visual indicators for selected models"""
	# Clear existing indicators
	_clear_selection_indicators()

	# Create selection indicators for each selected model
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		return

	for model_data in selected_models:
		var model_id = model_data.get("model_id", "")
		var visual_pos = model_data.get("position", Vector2.ZERO)
		var base_radius = Measurement.base_radius_px(model_data.get("base_mm", 32))
		var found_token = false

		# Try visual tokens first
		var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
		if token_layer:
			for child in token_layer.get_children():
				if child.has_meta("unit_id") and child.get_meta("unit_id") == active_unit_id and \
				   child.has_meta("model_id") and child.get_meta("model_id") == model_id:
					visual_pos = child.position
					model_data.position = visual_pos
					if child.has_method("get_base_radius"):
						base_radius = child.get_base_radius()
					elif child.has_meta("base_mm"):
						base_radius = Measurement.base_radius_px(child.get_meta("base_mm"))
					found_token = true
					break

		# Fallback: get latest position from GameState (handles staged moves)
		if not found_token and current_phase:
			var move_data = {}
			if current_phase.has_method("get_active_move_data"):
				move_data = current_phase.get_active_move_data(active_unit_id)
			if move_data.has("staged_moves"):
				for staged_move in move_data.staged_moves:
					if staged_move.get("model_id") == model_id:
						visual_pos = staged_move.get("dest", visual_pos)
						model_data.position = visual_pos
						break

		var indicator = _create_selection_ring_indicator(visual_pos, base_radius)
		if indicator:
			board_root.add_child(indicator)
			selection_indicators.append(indicator)

func _create_selection_ring_indicator(pos: Vector2, base_radius: float) -> Node2D:
	"""Create a visual ring indicator for a selected model"""
	var indicator = _SelectionRingIndicator.new()
	indicator.position = pos
	indicator.ring_radius = base_radius
	return indicator

func _start_group_movement(mouse_pos: Vector2) -> void:
	"""Start group movement for selected models"""
	if selected_models.is_empty():
		return

	print("Starting group movement with ", selected_models.size(), " models")

	# Get world position for the mouse click
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	# Calculate formation offsets relative to group center
	group_formation_offsets = _calculate_formation_offsets(selected_models)

	# Store starting positions for each model
	group_drag_start_positions.clear()
	for model_data in selected_models:
		group_drag_start_positions[model_data.model_id] = model_data.position

	# Set drag start position to the clicked point
	drag_start_pos = world_pos
	group_dragging = true

	# Hide selection indicators during drag - ghosts show the new positions
	_clear_selection_indicators()

	# Create ghost visuals for all selected models
	_create_group_ghost_visuals()

	# Position the ghost visual container at the origin - ghosts have absolute positions
	ghost_visual.position = Vector2.ZERO
	ghost_visual.visible = true

	# Update display - this should show initial "Group Max Used" values
	_update_group_movement_display()

func _calculate_formation_offsets(models: Array) -> Dictionary:
	"""Calculate relative positions within the group formation"""
	if models.is_empty():
		return {}

	var formation_center = _calculate_group_center(models)
	var offsets = {}

	for model_data in models:
		var offset = model_data.position - formation_center
		offsets[model_data.model_id] = offset

	return offsets

func _calculate_group_center(models: Array) -> Vector2:
	"""Calculate the center point of a group of models"""
	if models.is_empty():
		return Vector2.ZERO

	var total_pos = Vector2.ZERO
	for model_data in models:
		total_pos += model_data.position

	return total_pos / models.size()

func _update_group_movement_display() -> void:
	"""Update UI displays for group movement information"""
	if selected_models.size() <= 1:
		return

	var min_remaining = INF
	var max_used = 0.0

	for model_data in selected_models:
		var model_id = model_data.model_id
		var used = 0.0

		# Get distance from current move data if available
		if current_phase and current_phase.active_moves.has(active_unit_id):
			var move_data = current_phase.active_moves[active_unit_id]
			used = move_data.model_distances.get(model_id, 0.0)

		var remaining = move_cap_inches - used
		min_remaining = min(min_remaining, remaining)
		max_used = max(max_used, used)

	if inches_used_label:
		inches_used_label.text = "Group Max Used: %.1f\"" % max_used
	if inches_left_label:
		inches_left_label.text = "Group Min Left: %.1f\"" % min_remaining

func _select_all_unit_models() -> void:
	"""Select all models in the active unit (Ctrl+A functionality)"""
	if not current_phase or active_unit_id == "":
		return

	_clear_selection()

	# Use current game state, not snapshot
	var unit = current_phase.get_unit(active_unit_id)
	if unit.is_empty():
		return

	var models = unit.get("models", [])

	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue

		var model_id = model.get("id", "m%d" % (i+1))
		var model_data = model.duplicate()
		model_data["unit_id"] = active_unit_id
		model_data["model_id"] = model_id
		model_data["position"] = _get_model_position(model)
		selected_models.append(model_data)

	selection_mode = "MULTI" if selected_models.size() > 1 else "SINGLE"
	_update_model_selection_visuals()
	_update_movement_display()

	print("Selected all ", selected_models.size(), " models in unit")

func _update_group_drag(mouse_pos: Vector2) -> void:
	"""Update group drag movement"""
	if not group_dragging or selected_models.is_empty():
		return

	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	# Calculate drag vector from drag start position
	var drag_vector = world_pos - drag_start_pos

	# Update ghost positions to show preview
	for child in ghost_visual.get_children():
		var model_id = child.get_meta("model_id", "")
		var start_pos = group_drag_start_positions.get(model_id, Vector2.ZERO)

		# Update ghost position maintaining formation
		child.position = start_pos + drag_vector
		child.visible = true  # Ensure ghost is visible

		# Update the ghost's validity if it has the method
		if child.has_method("queue_redraw"):
			child.queue_redraw()

	# Calculate and display live distance updates for each model
	if current_phase and "active_moves" in current_phase and current_phase.active_moves.has(active_unit_id):
		var move_data = current_phase.active_moves[active_unit_id]
		var min_remaining = INF
		var max_used = 0.0

		for model_data in selected_models:
			var model_id = model_data.model_id
			var start_pos = group_drag_start_positions.get(model_id, model_data.position)
			var new_pos = start_pos + drag_vector

			# Calculate distance for this drag
			var drag_distance = Measurement.distance_inches(start_pos, new_pos)

			# Get previously accumulated distance
			var previous_distance = move_data.model_distances.get(model_id, 0.0)

			# Total distance would be previous + current drag
			var total_distance = previous_distance + drag_distance

			# Update tracking
			var remaining = move_cap_inches - total_distance
			min_remaining = min(min_remaining, remaining)
			max_used = max(max_used, total_distance)

		# Update the UI labels directly
		if inches_used_label:
			inches_used_label.text = "Group Max Used: %.1f\"" % max_used
		if inches_left_label:
			inches_left_label.text = "Group Min Left: %.1f\"" % min_remaining

		# Validate the move and update ghost colors based on validity
		var any_wall_collision = false
		var any_out_of_bounds = false

		# Check wall collisions and board edge for each model
		for model_data in selected_models:
			var model_id = model_data.model_id
			var start_pos = group_drag_start_positions.get(model_id, model_data.position)
			var new_pos = start_pos + drag_vector

			# Get the full model data with base information from GameState
			var full_model = _get_model_by_id(active_unit_id, model_id)
			if full_model.is_empty():
				# Fallback to using model_data if we can't get full data
				full_model = model_data

			# Check if this position would overlap with walls
			var test_model = full_model.duplicate()
			test_model["position"] = new_pos

			if Measurement.model_overlaps_any_wall(test_model):
				any_wall_collision = true
				if illegal_reason_label:
					illegal_reason_label.text = "Cannot overlap with walls"
					illegal_reason_label.modulate = Color.RED
				break

			# Check if this position would be outside the board
			if _is_position_outside_board(new_pos, full_model):
				any_out_of_bounds = true
				if illegal_reason_label:
					illegal_reason_label.text = "Cannot move beyond the board edge"
					illegal_reason_label.modulate = Color.RED
				break

		# Clear error label when all positions are valid
		if not any_wall_collision and not any_out_of_bounds and max_used <= move_cap_inches:
			if illegal_reason_label:
				illegal_reason_label.text = ""

		if max_used > move_cap_inches or any_wall_collision or any_out_of_bounds:
			# Some models exceed their movement or collide with walls - show invalid state
			for child in ghost_visual.get_children():
				if child.has_method("set_validity"):
					child.set_validity(false)
				elif child.has_method("queue_redraw"):
					child.is_valid_position = false
					child.queue_redraw()
		else:
			# Movement is valid
			for child in ghost_visual.get_children():
				if child.has_method("set_validity"):
					child.set_validity(true)
				elif child.has_method("queue_redraw"):
					child.is_valid_position = true
					child.queue_redraw()

func _end_group_drag(mouse_pos: Vector2) -> void:
	"""End group drag movement - now async to handle batch processing"""
	if not group_dragging:
		return

	print("Ending group drag with ", selected_models.size(), " models")

	var board_root = get_node_or_null("/root/Main/BoardRoot")
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	# Calculate final drag vector
	var drag_vector = world_pos - drag_start_pos

	# Send movement actions for all models in the group
	if current_phase:
		print("Processing group movement for ", selected_models.size(), " models")

		# First, validate that all moves are legal (no wall collisions)
		var all_moves_valid = true
		var invalid_reason = ""

		for model_data in selected_models:
			var model_id = model_data.model_id
			var start_pos = group_drag_start_positions.get(model_id, model_data.position)
			var new_pos = start_pos + drag_vector

			# Get the full model data with base information from GameState
			var full_model = _get_model_by_id(active_unit_id, model_id)
			if full_model.is_empty():
				print("ERROR: Could not get full model data for ", model_id)
				continue

			# Check if this position would overlap with walls
			var test_model = full_model.duplicate()
			test_model["position"] = new_pos

			if Measurement.model_overlaps_any_wall(test_model):
				all_moves_valid = false
				invalid_reason = "Model %s would overlap with walls" % model_id
				print("ERROR: ", invalid_reason)
				break

			# Also check model overlaps
			if _check_position_would_overlap(new_pos):
				all_moves_valid = false
				invalid_reason = "Model %s would overlap with other models" % model_id
				print("ERROR: ", invalid_reason)
				break

		# Only proceed with moves if all are valid
		if not all_moves_valid:
			print("Group move cancelled: ", invalid_reason)
			# Show error message to user
			if illegal_reason_label:
				illegal_reason_label.text = invalid_reason
				illegal_reason_label.modulate = Color.RED

			# Clear the drag but don't move anything
			group_dragging = false
			group_drag_start_positions.clear()
			group_formation_offsets.clear()
			_clear_ghost_visual()
			_update_model_selection_visuals()
			return

		# Build a batch of moves to send together
		var batch_moves = []
		for model_data in selected_models:
			var model_id = model_data.model_id
			var start_pos = group_drag_start_positions.get(model_id, model_data.position)
			var new_pos = start_pos + drag_vector
			var rotation = model_data.get("rotation", 0.0)

			batch_moves.append({
				"model_id": model_id,
				"dest": [new_pos.x, new_pos.y],
				"rotation": rotation,
				"start_pos": start_pos
			})
			print("  Preparing move for model ", model_id, " from ", start_pos, " to ", new_pos)

		# Send all moves in a batch to ensure they're processed together
		if batch_moves.size() > 0:
			# Option 1: Send individual moves with a small delay between them
			var delay_timer = 0.0
			for move in batch_moves:
				var action = {
					"type": "STAGE_MODEL_MOVE",
					"actor_unit_id": active_unit_id,
					"payload": {
						"model_id": move.model_id,
						"dest": move.dest,
						"rotation": move.rotation
					}
				}
				emit_signal("move_action_requested", action)

				# Add small delay to ensure signal processing completes
				await get_tree().create_timer(0.01).timeout

			print("Successfully sent ", batch_moves.size(), " move actions")

			# Verify all models were staged
			await get_tree().create_timer(0.1).timeout  # Wait for processing
			_verify_staged_moves(batch_moves)

	group_dragging = false

	# Clear the group drag state
	group_drag_start_positions.clear()
	group_formation_offsets.clear()

	# Clear ghost visuals
	_clear_ghost_visual()

	# Update displays
	_update_movement_display()
	_update_model_selection_visuals()

func _calculate_group_center_from_positions(positions: Dictionary) -> Vector2:
	"""Calculate center from a dictionary of model_id -> Vector2 positions"""
	if positions.is_empty():
		return Vector2.ZERO

	var total_pos = Vector2.ZERO
	for model_id in positions:
		total_pos += positions[model_id]

	return total_pos / positions.size()

func _get_model_position(model: Dictionary) -> Vector2:
	"""Get the position of a model from its data dictionary"""
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _get_model_by_id(unit_id: String, model_id: String) -> Dictionary:
	"""Get a specific model from a unit by its ID"""
	if not current_phase:
		return {}

	var unit = current_phase.get_unit(unit_id)
	if unit.is_empty():
		return {}

	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id:
			return model

	return {}

func _verify_staged_moves(expected_moves: Array) -> void:
	"""Verify that all expected moves were successfully staged"""
	if not current_phase or not "active_moves" in current_phase:
		print("[WARNING] Cannot verify staged moves - no active moves data")
		return

	if not current_phase.active_moves.has(active_unit_id):
		print("[WARNING] No active moves for unit ", active_unit_id)
		return

	var move_data = current_phase.active_moves[active_unit_id]
	var staged_moves = move_data.get("staged_moves", [])

	# Build a set of staged model IDs
	var staged_model_ids = {}
	for staged_move in staged_moves:
		staged_model_ids[staged_move.get("model_id", "")] = true

	# Check which models are missing
	var missing_models = []
	for expected_move in expected_moves:
		var model_id = expected_move.get("model_id", "")
		if not staged_model_ids.has(model_id):
			missing_models.append(model_id)

	if missing_models.size() > 0:
		print("[WARNING] The following models failed to stage moves: ", missing_models)
		print("  Retrying failed models...")

		# Retry the missing models
		for expected_move in expected_moves:
			var model_id = expected_move.get("model_id", "")
			if model_id in missing_models:
				var action = {
					"type": "STAGE_MODEL_MOVE",
					"actor_unit_id": active_unit_id,
					"payload": {
						"model_id": model_id,
						"dest": expected_move.dest,
						"rotation": expected_move.rotation
					}
				}
				print("  Retrying move for model ", model_id)
				emit_signal("move_action_requested", action)
	else:
		print("All ", expected_moves.size(), " models successfully staged for movement")

func _create_group_ghost_visuals() -> void:
	"""Create ghost visuals for all selected models in the group"""
	# Clear existing ghost visuals
	_clear_ghost_visual()

	if selected_models.is_empty():
		return

	# Make ghost_visual visible and slightly transparent
	ghost_visual.visible = true
	ghost_visual.modulate = Color(1, 1, 1, 0.6)  # More transparent for group

	# Create a ghost for each selected model
	for model_data in selected_models:
		# Create a ghost visual using the GhostVisual script
		var ghost_token = preload("res://scripts/GhostVisual.gd").new()
		ghost_token.name = "GhostModel_" + model_data.get("model_id", "")

		# Set up the ghost properties
		ghost_token.owner_player = GameState.get_active_player() if GameState else 1
		ghost_token.is_valid_position = true  # Start as valid, update during drag
		# Set model data to configure base shape
		ghost_token.set_model_data(model_data)

		# Initialize the ghost with the model's data
		ghost_token.set_model_data(model_data)

		# Position ghost at model's current position
		ghost_token.position = model_data.get("position", Vector2.ZERO)

		# Store metadata for tracking
		ghost_token.set_meta("model_id", model_data.get("model_id", ""))
		ghost_token.set_meta("formation_offset", group_formation_offsets.get(model_data.get("model_id", ""), Vector2.ZERO))
		ghost_token.set_meta("start_position", model_data.get("position", Vector2.ZERO))

		ghost_visual.add_child(ghost_token)

	print("Created ", ghost_visual.get_child_count(), " ghost visuals for group movement")

# ============================================================================
# COMMAND RE-ROLL HANDLERS
# ============================================================================

func _on_command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""Handle Command Re-roll opportunity for an advance roll."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ MovementController: COMMAND RE-ROLL OPPORTUNITY (Advance)")
	print("║ Unit: %s (player %d)" % [roll_context.get("unit_name", unit_id), player])
	print("║ Original roll: %s" % str(roll_context.get("original_rolls", [])))
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip dialog for AI players — AIPlayer handles the decision via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("MovementController: Skipping command reroll dialog for AI player %d" % player)
		return

	# Load and show the dialog
	var dialog_script = load("res://dialogs/CommandRerollDialog.gd")
	if not dialog_script:
		push_error("Failed to load CommandRerollDialog.gd")
		_on_command_reroll_declined(unit_id, player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(
		unit_id,
		player,
		roll_context.get("roll_type", "advance_roll"),
		roll_context.get("original_rolls", []),
		roll_context.get("context_text", "")
	)
	dialog.command_reroll_used.connect(_on_command_reroll_used)
	dialog.command_reroll_declined.connect(_on_command_reroll_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("MovementController: Command Re-roll dialog shown for player %d" % player)

func _on_command_reroll_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Command Re-roll for advance."""
	print("MovementController: Command Re-roll USED for %s advance" % unit_id)
	emit_signal("move_action_requested", {
		"type": "USE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

func _on_command_reroll_declined(unit_id: String, player: int) -> void:
	"""Handle player declining Command Re-roll for advance."""
	print("MovementController: Command Re-roll DECLINED for %s advance" % unit_id)
	emit_signal("move_action_requested", {
		"type": "DECLINE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

# ===================================================
# FIRE OVERWATCH HANDLING
# ===================================================

func _on_overwatch_opportunity(moved_unit_id: String, defending_player: int, eligible_units: Array) -> void:
	"""Handle Fire Overwatch opportunity — show dialog to the defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ MovementController: FIRE OVERWATCH OPPORTUNITY")
	print("║ Enemy unit moved: %s (defending player %d)" % [moved_unit_id, defending_player])
	print("║ Eligible units: %d" % eligible_units.size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip UI dialog for AI players — AIPlayer autoload handles the decision
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.is_ai_player(defending_player):
		print("MovementController: Defending player %d is AI — skipping overwatch dialog" % defending_player)
		return

	if eligible_units.is_empty():
		# No eligible units — auto-decline
		_on_fire_overwatch_declined(defending_player)
		return

	# Load and show the dialog
	var dialog_script = load("res://dialogs/FireOverwatchDialog.gd")
	if not dialog_script:
		push_error("Failed to load FireOverwatchDialog.gd")
		_on_fire_overwatch_declined(defending_player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(defending_player, moved_unit_id, eligible_units)
	dialog.fire_overwatch_used.connect(_on_fire_overwatch_used)
	dialog.fire_overwatch_declined.connect(_on_fire_overwatch_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("MovementController: Fire Overwatch dialog shown for player %d" % defending_player)

func _on_fire_overwatch_used(shooter_unit_id: String, player: int) -> void:
	"""Handle player choosing to use Fire Overwatch."""
	print("MovementController: Fire Overwatch USED by %s" % shooter_unit_id)
	emit_signal("move_action_requested", {
		"type": "USE_FIRE_OVERWATCH",
		"actor_unit_id": shooter_unit_id,
		"payload": {
			"shooter_unit_id": shooter_unit_id
		}
	})

func _on_fire_overwatch_declined(player: int) -> void:
	"""Handle player declining Fire Overwatch."""
	print("MovementController: Fire Overwatch DECLINED by player %d" % player)
	emit_signal("move_action_requested", {
		"type": "DECLINE_FIRE_OVERWATCH",
		"actor_unit_id": "",
	})

# ===================================================
# RAPID INGRESS HANDLING (T4-7)
# ===================================================

func _on_rapid_ingress_opportunity(player: int, eligible_units: Array) -> void:
	"""Handle Rapid Ingress opportunity — show dialog to the non-active player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ MovementController: RAPID INGRESS OPPORTUNITY")
	print("║ Non-active player %d has %d eligible reserve units" % [player, eligible_units.size()])
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip dialog for AI players — AIPlayer handles via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("MovementController: Skipping Rapid Ingress dialog for AI player %d" % player)
		return

	if eligible_units.is_empty():
		# No eligible units — auto-decline
		_on_rapid_ingress_declined(player)
		return

	# Load and show the dialog
	var dialog_script = load("res://dialogs/RapidIngressDialog.gd")
	if not dialog_script:
		push_error("Failed to load RapidIngressDialog.gd")
		_on_rapid_ingress_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(player, eligible_units)
	dialog.rapid_ingress_used.connect(_on_rapid_ingress_used)
	dialog.rapid_ingress_declined.connect(_on_rapid_ingress_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("MovementController: Rapid Ingress dialog shown for player %d" % player)

func _on_rapid_ingress_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Rapid Ingress."""
	print("MovementController: Rapid Ingress USED — unit %s by player %d" % [unit_id, player])
	emit_signal("move_action_requested", {
		"type": "USE_RAPID_INGRESS",
		"actor_unit_id": unit_id,
		"payload": {
			"unit_id": unit_id
		}
	})

func _on_rapid_ingress_declined(player: int) -> void:
	"""Handle player declining Rapid Ingress."""
	print("MovementController: Rapid Ingress DECLINED by player %d" % player)
	emit_signal("move_action_requested", {
		"type": "DECLINE_RAPID_INGRESS",
		"actor_unit_id": "",
	})


# ── Inner helper classes for selection visuals ──────────────────────────────

class _SelectionBoxVisual extends Node2D:
	"""Custom drawn selection rectangle with fill + dashed border"""
	var box_size: Vector2 = Vector2.ZERO

	func _draw() -> void:
		if box_size.length() < 1.0:
			return
		var rect = Rect2(Vector2.ZERO, box_size)
		# Semi-transparent blue fill
		draw_rect(rect, Color(0.3, 0.6, 1.0, 0.15))
		# Solid border
		draw_rect(rect, Color(0.4, 0.7, 1.0, 0.8), false, 2.0)
		# Corner markers for clarity
		var corner_len = min(12.0, min(box_size.x, box_size.y) * 0.3)
		var c = Color(0.5, 0.85, 1.0, 1.0)
		var w = 3.0
		# Top-left
		draw_line(Vector2.ZERO, Vector2(corner_len, 0), c, w)
		draw_line(Vector2.ZERO, Vector2(0, corner_len), c, w)
		# Top-right
		draw_line(Vector2(box_size.x, 0), Vector2(box_size.x - corner_len, 0), c, w)
		draw_line(Vector2(box_size.x, 0), Vector2(box_size.x, corner_len), c, w)
		# Bottom-left
		draw_line(Vector2(0, box_size.y), Vector2(corner_len, box_size.y), c, w)
		draw_line(Vector2(0, box_size.y), Vector2(0, box_size.y - corner_len), c, w)
		# Bottom-right
		draw_line(box_size, Vector2(box_size.x - corner_len, box_size.y), c, w)
		draw_line(box_size, Vector2(box_size.x, box_size.y - corner_len), c, w)


class _SelectionRingIndicator extends Node2D:
	"""Pulsing selection ring drawn around a selected model"""
	var ring_radius: float = 16.0
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var pulse = (sin(_time * 5.0) + 1.0) / 2.0  # 0..1 oscillation
		var alpha = 0.5 + pulse * 0.5
		# Outer glow ring
		draw_arc(Vector2.ZERO, ring_radius + 5.0, 0, TAU, 48, Color(0.3, 0.7, 1.0, alpha * 0.3), 4.0)
		# Main selection ring
		draw_arc(Vector2.ZERO, ring_radius + 3.0, 0, TAU, 48, Color(0.4, 0.8, 1.0, alpha), 2.5)
		# Inner fill circle
		draw_circle(Vector2.ZERO, ring_radius, Color(0.3, 0.6, 1.0, 0.1))
