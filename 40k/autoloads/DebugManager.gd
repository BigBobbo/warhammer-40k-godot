extends Node

# DebugManager - Global manager for debug mode functionality
# Allows unrestricted model movement from any army without phase constraints

signal debug_mode_changed(active: bool)
signal debug_movement_requested(unit_id: String, model_id: String, position: Vector2)

var debug_mode_active: bool = false
var previous_phase: GameStateData.Phase
var was_in_phase: bool = false
var debug_overlay: Control = null
var debug_drag_active: bool = false
var debug_selected_model: Dictionary = {}

# Constants
const TOKEN_CLICK_RADIUS: float = 30.0

func _ready() -> void:
	print("DebugManager initialized")
	set_process_unhandled_input(false)  # Only process input when in debug mode

# Main API
func toggle_debug_mode() -> void:
	if debug_mode_active:
		exit_debug_mode()
	else:
		enter_debug_mode()

func enter_debug_mode() -> void:
	if debug_mode_active:
		return
	
	print("Entering DEBUG MODE")
	
	# Store current phase state
	if PhaseManager and PhaseManager.current_phase_instance:
		previous_phase = GameState.get_current_phase()
		was_in_phase = true
	else:
		was_in_phase = false
	
	debug_mode_active = true
	set_process_unhandled_input(true)  # Enable debug input handling
	
	# Notify systems
	emit_signal("debug_mode_changed", true)
	
	# Show debug overlay
	_show_debug_overlay()
	
	# Update all token visuals
	_update_all_tokens_debug_state(true)

func exit_debug_mode() -> void:
	if not debug_mode_active:
		return
	
	print("Exiting DEBUG MODE")
	
	debug_mode_active = false
	set_process_unhandled_input(false)  # Disable debug input handling
	debug_drag_active = false
	debug_selected_model.clear()
	
	# Notify systems
	emit_signal("debug_mode_changed", false)
	
	# Hide debug overlay
	_hide_debug_overlay()
	
	# Update all token visuals
	_update_all_tokens_debug_state(false)
	
	# Phase restoration is automatic since we never changed it
	if was_in_phase:
		print("Returning to previous phase: ", previous_phase)

func is_debug_active() -> bool:
	return debug_mode_active

# Debug-specific input handling
func _unhandled_input(event: InputEvent) -> void:
	if not debug_mode_active:
		return
	
	# Handle debug drag operations
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_debug_drag(event.position)
			else:
				_end_debug_drag(event.position)
			get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion and debug_drag_active:
		_update_debug_drag(event.position)
		get_viewport().set_input_as_handled()

func _start_debug_drag(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world_position(screen_pos)
	var model = _find_model_at_position_debug(world_pos)
	
	if not model.is_empty():
		debug_drag_active = true
		debug_selected_model = model
		print("Debug: Started dragging ", model.model_id, " from unit ", model.unit_id)
		
		# Visual feedback
		_highlight_dragged_model(model)

func _update_debug_drag(screen_pos: Vector2) -> void:
	if not debug_drag_active or debug_selected_model.is_empty():
		return
	
	var world_pos = _screen_to_world_position(screen_pos)
	
	# Update ghost visual position
	_update_ghost_position(world_pos)

func _end_debug_drag(screen_pos: Vector2) -> void:
	if not debug_drag_active or debug_selected_model.is_empty():
		return
	
	var world_pos = _screen_to_world_position(screen_pos)
	
	# Update model position directly in game state
	_update_model_position_debug(debug_selected_model.unit_id, debug_selected_model.model_id, world_pos)
	
	print("Debug: Moved ", debug_selected_model.model_id, " to ", world_pos)
	
	# Clear drag state
	debug_drag_active = false
	debug_selected_model.clear()
	
	# Clear visual feedback
	_clear_drag_visuals()
	
	# Trigger visual refresh
	_refresh_board_visuals()

# Debug-specific model finding (no ownership/phase restrictions)
func _find_model_at_position_debug(world_pos: Vector2) -> Dictionary:
	var closest_model = {}
	var closest_distance = INF
	
	# Check ALL models from ALL units (no ownership filtering)
	for unit_id in GameState.state.units:
		var unit = GameState.state.units[unit_id]
		for model in unit.get("models", []):
			# Skip dead models
			if not model.get("alive", true):
				continue
				
			var pos_dict = model.get("position", {})
			if pos_dict.is_empty() or pos_dict.get("x") == null or pos_dict.get("y") == null:
				continue
				
			var model_pos = Vector2(pos_dict.get("x", 0), pos_dict.get("y", 0))
			var distance = world_pos.distance_to(model_pos)
			
			if distance < closest_distance and distance < TOKEN_CLICK_RADIUS:
				closest_distance = distance
				closest_model = {
					"unit_id": unit_id,
					"model_id": model.get("id", ""),
					"model": model,
					"position": model_pos
				}
	
	return closest_model

# Update model position directly in game state (debug mode only)
func _update_model_position_debug(unit_id: String, model_id: String, new_position: Vector2) -> void:
	if not GameState.state.units.has(unit_id):
		push_error("Debug: Unit not found: " + unit_id)
		return
	
	var unit = GameState.state.units[unit_id]
	var models = unit.get("models", [])
	
	for i in range(models.size()):
		if models[i].get("id", "") == model_id:
			models[i]["position"] = {
				"x": new_position.x,
				"y": new_position.y
			}
			# Update the unit in game state
			GameState.state.units[unit_id]["models"] = models
			break

# Visual overlay management
func _show_debug_overlay() -> void:
	if debug_overlay:
		debug_overlay.visible = true
		return
	
	# Create debug overlay dynamically
	var main_node = get_node_or_null("/root/Main")
	if not main_node:
		push_error("Debug: Main node not found")
		return
	
	# Create a simple overlay
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 128  # Highest layer
	canvas_layer.name = "DebugOverlayLayer"
	
	debug_overlay = Control.new()
	debug_overlay.name = "DebugOverlay"
	debug_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_overlay.anchor_right = 1.0
	debug_overlay.anchor_bottom = 1.0
	
	# Add background tint
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.2, 0.3)  # Semi-transparent dark blue
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_overlay.add_child(bg)
	
	# Add debug text
	var label_container = VBoxContainer.new()
	label_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_container.anchor_left = 0.5
	label_container.anchor_right = 0.5
	label_container.anchor_top = 0.0
	label_container.anchor_bottom = 0.0
	label_container.offset_left = -200
	label_container.offset_right = 200
	label_container.offset_top = 20
	
	var debug_label = Label.new()
	debug_label.text = "DEBUG MODE ACTIVE"
	debug_label.add_theme_font_size_override("font_size", 32)
	debug_label.add_theme_color_override("font_color", Color.YELLOW)
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_container.add_child(debug_label)
	
	var instructions_label = Label.new()
	instructions_label.text = "Press 9 to exit | Click and drag any model"
	instructions_label.add_theme_font_size_override("font_size", 16)
	instructions_label.add_theme_color_override("font_color", Color.WHITE)
	instructions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_container.add_child(instructions_label)
	
	debug_overlay.add_child(label_container)
	canvas_layer.add_child(debug_overlay)
	main_node.add_child(canvas_layer)

func _hide_debug_overlay() -> void:
	if not debug_overlay:
		return
	
	debug_overlay.visible = false
	
	# Clean up the overlay completely
	var canvas_layer = debug_overlay.get_parent()
	if canvas_layer:
		canvas_layer.queue_free()
	debug_overlay = null

# Update all token visuals for debug state
func _update_all_tokens_debug_state(debug_active: bool) -> void:
	var main_node = get_node_or_null("/root/Main")
	if not main_node:
		return
	
	var token_layer = main_node.get_node_or_null("BoardRoot/TokenLayer")
	if not token_layer:
		return
	
	# Update each token visual
	for token in token_layer.get_children():
		if token.has_method("set_debug_mode"):
			token.set_debug_mode(debug_active)

# Visual feedback helpers
func _highlight_dragged_model(model_data: Dictionary) -> void:
	# This would highlight the selected model
	pass

func _update_ghost_position(world_pos: Vector2) -> void:
	# Update ghost visual position during drag
	var main_node = get_node_or_null("/root/Main")
	if not main_node:
		return
	
	var ghost_layer = main_node.get_node_or_null("BoardRoot/GhostLayer")
	if ghost_layer and ghost_layer.get_child_count() > 0:
		var ghost = ghost_layer.get_child(0)
		ghost.position = world_pos

func _clear_drag_visuals() -> void:
	# Clear any drag-related visuals
	var main_node = get_node_or_null("/root/Main")
	if not main_node:
		return
	
	var ghost_layer = main_node.get_node_or_null("BoardRoot/GhostLayer")
	if ghost_layer:
		for child in ghost_layer.get_children():
			child.queue_free()

func _refresh_board_visuals() -> void:
	# Trigger a visual refresh of the board
	var main_node = get_node_or_null("/root/Main")
	if main_node and main_node.has_method("_recreate_unit_visuals"):
		main_node._recreate_unit_visuals()

# Utility functions
func _screen_to_world_position(screen_pos: Vector2) -> Vector2:
	var main_node = get_node_or_null("/root/Main")
	if not main_node:
		return screen_pos
	
	if main_node.has_method("screen_to_world_position"):
		return main_node.screen_to_world_position(screen_pos)
	
	# Fallback: use BoardRoot transform
	var board_root = main_node.get_node_or_null("BoardRoot")
	if board_root:
		return board_root.transform.affine_inverse() * screen_pos
	
	return screen_pos