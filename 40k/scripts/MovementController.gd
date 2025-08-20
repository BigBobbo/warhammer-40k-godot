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
var ruler_visual: Line2D
var ghost_visual: Node2D
var hud_bottom: Control
var hud_right: Control

# UI Elements
var move_cap_label: Label
var inches_used_label: Label
var inches_left_label: Label
var illegal_reason_label: Label
var unit_list: ItemList
var dice_log_display: RichTextLabel

# Path tracking
var current_path: Array = []  # Array of Vector2 points
var path_valid: bool = false

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
	if ruler_visual and is_instance_valid(ruler_visual):
		ruler_visual.queue_free()  
	if ghost_visual and is_instance_valid(ghost_visual):
		ghost_visual.queue_free()
	
	# Clean up UI containers
	var movement_info = get_node_or_null("/root/Main/HUD_Bottom/MovementInfo")
	if movement_info and is_instance_valid(movement_info):
		movement_info.queue_free()
	
	var movement_buttons = get_node_or_null("/root/Main/HUD_Bottom/MovementButtons")
	if movement_buttons and is_instance_valid(movement_buttons):
		movement_buttons.queue_free()
	
	var movement_actions = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/MovementActions")
	if movement_actions and is_instance_valid(movement_actions):
		movement_actions.queue_free()

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
		
	# Always recreate movement HUD elements to avoid duplication
	var container = hud_bottom.get_node_or_null("MovementInfo")
	if container:
		print("MovementController: Removing existing MovementInfo container")
		hud_bottom.remove_child(container)
		container.free()
	
	container = HBoxContainer.new()
	container.name = "MovementInfo"
	hud_bottom.add_child(container)
	
	# Movement cap display
	move_cap_label = Label.new()
	move_cap_label.text = "Move: 0\""
	container.add_child(move_cap_label)
	
	# Inches used display
	inches_used_label = Label.new()
	inches_used_label.text = "Used: 0\""
	container.add_child(inches_used_label)
	
	# Inches left display
	inches_left_label = Label.new()
	inches_left_label.text = "Left: 0\""
	container.add_child(inches_left_label)
	
	# Illegal reason display
	illegal_reason_label = Label.new()
	illegal_reason_label.text = ""
	illegal_reason_label.modulate = Color.RED
	container.add_child(illegal_reason_label)
	
	# Action buttons - clean up existing first
	var existing_buttons = hud_bottom.get_node_or_null("MovementButtons")
	if existing_buttons:
		print("MovementController: Removing existing MovementButtons container")
		hud_bottom.remove_child(existing_buttons)
		existing_buttons.free()
	
	var button_container = HBoxContainer.new()
	button_container.name = "MovementButtons"
	hud_bottom.add_child(button_container)
	
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
	
	# Add separator
	button_container.add_child(VSeparator.new())
	
	# Add End Movement Phase button
	var end_phase_button = Button.new()
	end_phase_button.name = "EndPhaseButton"
	end_phase_button.text = "End Movement Phase"
	end_phase_button.pressed.connect(_on_end_phase_pressed)
	button_container.add_child(end_phase_button)

func _setup_right_panel() -> void:
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)
	
	# Use existing unit list if not already set
	if not unit_list:
		unit_list = container.get_node_or_null("UnitListPanel")
		if unit_list:
			# Connect to existing unit list
			if not unit_list.item_selected.is_connected(_on_unit_selected):
				unit_list.item_selected.connect(_on_unit_selected)
	
	# Always recreate movement action buttons to avoid timing issues after loading
	var action_container = container.get_node_or_null("MovementActions")
	if action_container:
		print("MovementController: Removing existing MovementActions container immediately")
		container.remove_child(action_container)
		action_container.free()
	
	print("MovementController: Creating new MovementActions container")
	action_container = VBoxContainer.new()
	action_container.name = "MovementActions"
	container.add_child(action_container)
	
	var normal_button = Button.new()
	normal_button.text = "Normal Move"
	normal_button.pressed.connect(_on_normal_move_pressed)
	action_container.add_child(normal_button)
	
	var advance_button = Button.new()
	advance_button.text = "Advance"
	advance_button.pressed.connect(_on_advance_pressed)
	action_container.add_child(advance_button)
	print("MovementController: Added Advance button")
	
	var fall_back_button = Button.new()
	fall_back_button.text = "Fall Back"
	fall_back_button.pressed.connect(_on_fall_back_pressed)
	action_container.add_child(fall_back_button)
	print("MovementController: Added Fall Back button")
	
	var stationary_button = Button.new()
	stationary_button.text = "Remain Stationary"
	stationary_button.pressed.connect(_on_remain_stationary_pressed)
	action_container.add_child(stationary_button)
	
	# Create dice log display only if it doesn't exist
	if not dice_log_display:
		var existing_dice_log = container.get_node_or_null("DiceLog")
		if not existing_dice_log:
			var dice_label = Label.new()
			dice_label.text = "Dice Log:"
			container.add_child(dice_label)
			
			dice_log_display = RichTextLabel.new()
			dice_log_display.name = "DiceLog"
			dice_log_display.custom_minimum_size = Vector2(300, 150)
			dice_log_display.bbcode_enabled = true
			container.add_child(dice_log_display)

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
			if phase.has_signal("unit_move_confirmed"):
				if not phase.unit_move_confirmed.is_connected(_on_unit_move_confirmed):
					phase.unit_move_confirmed.connect(_on_unit_move_confirmed)
			if phase.has_signal("unit_move_reset"):
				if not phase.unit_move_reset.is_connected(_on_unit_move_reset):
					phase.unit_move_reset.connect(_on_unit_move_reset)
			
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
			var status = ""
			
			if unit.get("flags", {}).get("moved", false):
				status = " [MOVED]"
			elif unit.get("flags", {}).get("advanced", false):
				status = " [ADVANCING]"
			elif unit.get("flags", {}).get("fell_back", false):
				status = " [FALLING BACK]"
			
			unit_list.add_item(unit_name + status)
			unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
			added_units[unit_id] = true

func _on_unit_selected(index: int) -> void:
	var unit_id = unit_list.get_item_metadata(index)
	active_unit_id = unit_id
	print("MovementController: Unit selected - ", unit_id)
	_highlight_unit_models(unit_id)
	emit_signal("ui_update_requested")

func _highlight_unit_models(unit_id: String) -> void:
	# Visual feedback for selected unit
	# This would highlight all models in the unit on the board
	pass

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
			move_cap_inches = unit.get("flags", {}).get("move_cap_inches", 6.0)
			print("Move cap set to: ", move_cap_inches, " inches")
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
	# Update path visual
	_update_movement_display()
	_refresh_unit_list()
	emit_signal("ui_update_requested")

func _on_unit_move_confirmed(unit_id: String, result_summary: Dictionary) -> void:
	# Clear movement state
	active_unit_id = ""
	active_mode = ""
	move_cap_inches = 0.0
	_clear_path_visual()
	_update_movement_display()
	_refresh_unit_list()
	_update_end_phase_button()
	emit_signal("ui_update_requested")

func _on_unit_move_reset(unit_id: String) -> void:
	_clear_path_visual()
	_update_movement_display()
	emit_signal("ui_update_requested")

func _unhandled_input(event: InputEvent) -> void:
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
	var inches_left = move_cap_inches - distance_inches
	
	# Check validity
	path_valid = _validate_move_path(current_path, distance_inches)
	
	# Update visuals
	_update_path_visual()
	_update_ruler_visual()
	_update_ghost_position(world_pos)
	_update_movement_display_with_preview(distance_inches, inches_left, path_valid)

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
	
	# For now, skip validation to test if movement works
	var valid = distance_inches <= move_cap_inches
	
	if valid:
		print("Move is valid, sending SET_MODEL_DEST action")
		print("  From: ", drag_start_pos, " To: ", world_pos)
		print("  Distance: ", distance_inches, " inches")
		
		# Send SET_MODEL_DEST action
		var action = {
			"type": "SET_MODEL_DEST",
			"actor_unit_id": active_unit_id,
			"payload": {
				"model_id": selected_model.model_id,
				"dest": [world_pos.x, world_pos.y]
			}
		}
		print("  Action: ", action)
		emit_signal("move_action_requested", action)
	else:
		print("Move invalid: exceeds movement cap (", distance_inches, " > ", move_cap_inches, ")")
	
	# Clear drag state
	dragging_model = false
	selected_model = {}
	current_path.clear()
	_clear_ghost_visual()
	_clear_path_visual()
	_clear_ruler_visual()

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
			
			# Check if click is within model's base
			if distance <= base_radius:
				# Use closest model if multiple overlap
				if distance < closest_distance:
					closest_distance = distance
					closest_model = {
						"unit_id": unit_id,
						"model_id": model.get("id", "m%d" % (i+1)),
						"position": model_pos,
						"base_mm": model.get("base_mm", 32)
					}
	
	if not closest_model.is_empty():
		print("Found model at distance ", closest_distance, " pixels")
	else:
		# Debug: Show all model positions
		print("No model found at ", world_pos, ". Model positions:")
		for unit_id in units:
			var unit = units[unit_id]
			if unit.get("owner", 0) == GameState.get_active_player():
				var models = unit.get("models", [])
				for model in models:
					var pos = model.get("position")
					if pos:
						print("  ", unit_id, "/", model.get("id", "?"), " at ", pos)
	
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
	path_visual.clear_points()
	if current_path.size() < 2:
		return
	
	for point in current_path:
		path_visual.add_point(point)
	
	# Color based on validity
	path_visual.default_color = Color.GREEN if path_valid else Color.RED

func _clear_path_visual() -> void:
	path_visual.clear_points()

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

func _update_movement_display() -> void:
	if move_cap_label:
		move_cap_label.text = "Move: %.1f\"" % move_cap_inches
	if inches_used_label:
		inches_used_label.text = "Used: 0.0\""
	if inches_left_label:
		inches_left_label.text = "Left: %.1f\"" % move_cap_inches

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
		inches_used_label.text = "Used: %.1f\"" % used
		inches_used_label.modulate = Color.WHITE if valid else Color.RED
	if inches_left_label:
		inches_left_label.text = "Left: %.1f\"" % left
		inches_left_label.modulate = Color.WHITE if left >= 0 else Color.RED

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
