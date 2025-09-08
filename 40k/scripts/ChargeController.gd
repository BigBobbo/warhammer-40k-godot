extends Node2D
class_name ChargeController

# ChargeController - Handles UI interactions for the Charge Phase
# Manages charge declarations, target selection, dice rolling, and movement validation

signal charge_action_requested(action: Dictionary)
signal charge_preview_updated(unit_id: String, target_ids: Array, valid: bool)
signal ui_update_requested()

# Charge state
var current_phase = null  # Can be ChargePhase or null
var active_unit_id: String = ""
var eligible_targets: Dictionary = {}  # target_unit_id -> target_data
var selected_targets: Array = []
var charge_distance: int = 0
var awaiting_roll: bool = false
var awaiting_movement: bool = false

# Charge movement tracking
var models_to_move: Array = []  # Models that still need to move
var moved_models: Dictionary = {}  # model_id -> new_position
var dragging_model = null  # Currently dragging model
var ghost_visual: Node2D = null  # Ghost visual for dragging
var movement_lines: Dictionary = {}  # model_id -> Line2D for movement path
var confirm_button: Button = null  # Button to confirm charge moves

# UI References
var board_view: Node2D
var charge_line_visual: Line2D
var range_visual: Node2D
var target_highlights: Node2D
var hud_bottom: Control
var hud_right: Control

# UI Elements
var unit_selector: ItemList
var target_list: ItemList
var charge_info_label: Label
var charge_distance_label: Label
var charge_used_label: Label
var charge_left_label: Label
var declare_button: Button
var roll_button: Button
var skip_button: Button
var next_unit_button: Button
var end_phase_button: Button
var charge_status_label: Label
var dice_log_display: RichTextLabel

# Visual settings
const HIGHLIGHT_COLOR_ELIGIBLE = Color.GREEN
const HIGHLIGHT_COLOR_SELECTED = Color.YELLOW
const CHARGE_LINE_COLOR = Color.ORANGE
const CHARGE_LINE_WIDTH = 3.0
const RANGE_CIRCLE_COLOR = Color(1.0, 0.5, 0.0, 0.3)

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)
	_setup_ui_references()
	_create_charge_visuals()
	print("ChargeController ready")

func _exit_tree() -> void:
	# Clean up visual elements
	if charge_line_visual and is_instance_valid(charge_line_visual):
		charge_line_visual.queue_free()
	if range_visual and is_instance_valid(range_visual):
		range_visual.queue_free()
	if target_highlights and is_instance_valid(target_highlights):
		target_highlights.queue_free()
	_clear_movement_visuals()
	
	# ENHANCEMENT: Comprehensive right panel cleanup
	var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
	if container and is_instance_valid(container):
		var charge_elements = ["ChargePanel", "ChargeScrollContainer", "ChargeActions"]
		for element in charge_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("ChargeController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

func _input(event: InputEvent) -> void:
	if not awaiting_movement:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Check if the click is within the confirm button area
			if is_instance_valid(confirm_button) and confirm_button.visible:
				var button_rect = confirm_button.get_global_rect()
				if button_rect.has_point(mouse_event.global_position):
					print("DEBUG: Click is within confirm button area, not handling")
					return  # Let the button handle this click
			
			print("DEBUG: ChargeController _input - Left mouse button, pressed: ", mouse_event.pressed)
			if mouse_event.pressed:
				_handle_mouse_down(mouse_event.global_position)
			else:
				_handle_mouse_release(mouse_event.global_position)
			get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion and dragging_model:
		_handle_mouse_motion(event.global_position)
		get_viewport().set_input_as_handled()

func _handle_mouse_down(global_pos: Vector2) -> void:
	print("DEBUG: Mouse down at global pos: ", global_pos)
	
	# Try a simpler approach - check token visual nodes directly
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if not token_layer:
		print("DEBUG: TokenLayer not found")
		return
	
	print("DEBUG: Models to move: ", models_to_move)
	
	# Check each token in the layer
	for child in token_layer.get_children():
		if not child.has_meta("unit_id") or not child.has_meta("model_id"):
			continue
			
		var unit_id = child.get_meta("unit_id")
		var model_id = child.get_meta("model_id")
		
		# Check if this is our charging unit and a model we need to move
		if unit_id != active_unit_id or model_id not in models_to_move:
			continue
		
		# Check if the click is on this token
		var token_global_pos = child.global_position
		var token_radius = 25.2  # Standard token radius in pixels
		
		var distance = token_global_pos.distance_to(global_pos)
		print("DEBUG: Token ", model_id, " at global ", token_global_pos, " distance from click: ", distance)
		
		if distance <= token_radius:
			print("DEBUG: Clicked on model ", model_id)
			
			# Get the model data
			var unit = GameState.get_unit(active_unit_id)
			for model in unit.get("models", []):
				if model.get("id", "") == model_id:
					dragging_model = model
					# Convert token position to BoardRoot local coordinates
					var board_root = get_node_or_null("/root/Main/BoardRoot")
					if board_root:
						var local_pos = board_root.to_local(token_global_pos)
						_start_model_drag(model, local_pos)
					return
	
	print("DEBUG: No model found at click position")

func _handle_mouse_motion(global_pos: Vector2) -> void:
	if not dragging_model:
		return
	
	# Convert global position to BoardRoot local coordinates
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		return
	
	var local_pos = board_root.to_local(global_pos)
	_update_model_drag(local_pos)

func _handle_mouse_release(global_pos: Vector2) -> void:
	if not dragging_model:
		return
	
	# Convert global position to BoardRoot local coordinates
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		return
	
	var local_pos = board_root.to_local(global_pos)
	_end_model_drag(local_pos)

func _setup_ui_references() -> void:
	# Get references to UI nodes
	board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
	hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	hud_right = get_node_or_null("/root/Main/HUD_Right")
	
	# Setup charge-specific UI elements
	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()

func _create_charge_visuals() -> void:
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		print("ERROR: Cannot find BoardRoot for visual layers")
		return
	
	# Create charge line visualization
	charge_line_visual = Line2D.new()
	charge_line_visual.name = "ChargeLineVisual"
	charge_line_visual.width = CHARGE_LINE_WIDTH
	charge_line_visual.default_color = CHARGE_LINE_COLOR
	charge_line_visual.add_point(Vector2.ZERO)
	charge_line_visual.clear_points()
	board_root.add_child(charge_line_visual)
	
	# Create range visualization node
	range_visual = Node2D.new()
	range_visual.name = "ChargeRangeVisual"
	board_root.add_child(range_visual)
	
	# Create target highlight container
	target_highlights = Node2D.new()
	target_highlights.name = "ChargeTargetHighlights"
	board_root.add_child(target_highlights)

func _setup_bottom_hud() -> void:
	# Get the main HBox container in bottom HUD
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: Cannot find HBoxContainer in HUD_Bottom")
		return
	
	# Clean up existing charge controls
	var existing_controls = main_container.get_node_or_null("ChargeControls")
	if existing_controls:
		main_container.remove_child(existing_controls)
		existing_controls.free()
	
	var container = HBoxContainer.new()
	container.name = "ChargeControls"
	main_container.add_child(container)
	
	# Add separator before charge controls
	container.add_child(VSeparator.new())
	
	# Charge info label
	charge_info_label = Label.new()
	charge_info_label.text = "Step 1: Select a unit from the list below to begin charge"
	container.add_child(charge_info_label)
	
	# Charge distance display labels (initially hidden)
	charge_distance_label = Label.new()
	charge_distance_label.text = "Charge: 0\""
	charge_distance_label.visible = false
	container.add_child(charge_distance_label)
	
	charge_used_label = Label.new()
	charge_used_label.text = "Used: 0.0\""
	charge_used_label.visible = false
	container.add_child(charge_used_label)
	
	charge_left_label = Label.new()
	charge_left_label.text = "Left: 0.0\""
	charge_left_label.visible = false
	container.add_child(charge_left_label)
	
	# Add separator
	container.add_child(VSeparator.new())
	
	# Declare charge button
	declare_button = Button.new()
	declare_button.text = "Declare Charge"
	declare_button.disabled = true
	declare_button.pressed.connect(_on_declare_charge_pressed)
	container.add_child(declare_button)
	
	# Roll charge button
	roll_button = Button.new()
	roll_button.text = "Roll 2D6"
	roll_button.disabled = true
	roll_button.pressed.connect(_on_roll_charge_pressed)
	container.add_child(roll_button)
	
	# Skip charge button
	skip_button = Button.new()
	skip_button.text = "Skip Charge"
	skip_button.disabled = true
	skip_button.pressed.connect(_on_skip_charge_pressed)
	container.add_child(skip_button)
	
	# Add separator
	container.add_child(VSeparator.new())
	
	# Next unit button
	next_unit_button = Button.new()
	next_unit_button.text = "Select Next Unit"
	next_unit_button.disabled = true
	next_unit_button.visible = false
	next_unit_button.pressed.connect(_on_next_unit_pressed)
	container.add_child(next_unit_button)
	
	# End phase button
	end_phase_button = Button.new()
	end_phase_button.text = "End Charge Phase"
	end_phase_button.pressed.connect(_on_end_phase_pressed)
	container.add_child(end_phase_button)
	
	# Add separator
	container.add_child(VSeparator.new())
	
	# Charge status label
	charge_status_label = Label.new()
	charge_status_label.text = ""
	container.add_child(charge_status_label)

func _setup_right_panel() -> void:
	# Main.gd already handles cleanup before controller creation
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)
	
	# Clean up existing charge scroll container
	var existing_scroll = container.get_node_or_null("ChargeScrollContainer")
	if existing_scroll:
		container.remove_child(existing_scroll)
		existing_scroll.free()
	
	# Create scroll container for better layout
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "ChargeScrollContainer"
	scroll_container.custom_minimum_size = Vector2(200, 400)  # Increased from 250 to 400
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Take available space
	container.add_child(scroll_container)
	
	# Create charge panel
	var charge_panel = VBoxContainer.new()
	charge_panel.name = "ChargePanel"
	charge_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(charge_panel)
	
	# Unit selector
	var unit_label = Label.new()
	unit_label.text = "Units that can charge:"
	charge_panel.add_child(unit_label)
	
	unit_selector = ItemList.new()
	unit_selector.custom_minimum_size = Vector2(200, 150)
	unit_selector.item_selected.connect(_on_unit_selected)
	charge_panel.add_child(unit_selector)
	
	# Target list
	var target_label = Label.new()
	target_label.text = "Eligible targets (click to select):"
	charge_panel.add_child(target_label)
	
	target_list = ItemList.new()
	target_list.custom_minimum_size = Vector2(200, 100)
	target_list.select_mode = ItemList.SELECT_MULTI
	target_list.item_selected.connect(_on_target_selected)
	target_list.mouse_filter = Control.MOUSE_FILTER_PASS  # Ensure mouse input is received
	# Add mouse click detection for debugging
	target_list.gui_input.connect(_on_target_list_input)
	print("DEBUG: Created target_list with signal connected to _on_target_selected")
	charge_panel.add_child(target_list)
	
	# Dice log display
	var dice_label = Label.new()
	dice_label.text = "Dice Log:"
	charge_panel.add_child(dice_label)
	
	dice_log_display = RichTextLabel.new()
	dice_log_display.custom_minimum_size = Vector2(200, 100)
	dice_log_display.bbcode_enabled = true
	charge_panel.add_child(dice_log_display)

func set_phase(phase_instance) -> void:
	current_phase = phase_instance
	
	# Connect to charge phase signals
	if current_phase.has_signal("unit_selected_for_charge"):
		if not current_phase.unit_selected_for_charge.is_connected(_on_unit_selected_for_charge):
			current_phase.unit_selected_for_charge.connect(_on_unit_selected_for_charge)
	
	if current_phase.has_signal("charge_targets_available"):
		if not current_phase.charge_targets_available.is_connected(_on_charge_targets_available):
			current_phase.charge_targets_available.connect(_on_charge_targets_available)
	
	if current_phase.has_signal("charge_roll_made"):
		if not current_phase.charge_roll_made.is_connected(_on_charge_roll_made):
			current_phase.charge_roll_made.connect(_on_charge_roll_made)
	
	if current_phase.has_signal("charge_resolved"):
		if not current_phase.charge_resolved.is_connected(_on_charge_resolved):
			current_phase.charge_resolved.connect(_on_charge_resolved)
	
	# Refresh UI with current phase data
	_refresh_ui()

func _refresh_ui() -> void:
	if not current_phase:
		print("ChargeController: No current_phase in _refresh_ui")
		return
	
	# Ensure UI components exist
	if not is_instance_valid(unit_selector):
		print("DEBUG: Unit selector missing, recreating UI...")
		_setup_right_panel()
		if not is_instance_valid(unit_selector):
			print("ERROR: Still no unit selector after recreating UI")
			return
	
	# Clear and populate unit selector with units that can charge
	unit_selector.clear()
	
	# Use ChargePhase's eligible units method which respects completed_charges
	var eligible_unit_ids = current_phase.get_eligible_charge_units()
	var current_player = current_phase.get_current_player()
	var units = current_phase.get_units_for_player(current_player)
	
	print("ChargeController: Refreshing UI for player ", current_player)
	print("ChargeController: Eligible units from phase: ", eligible_unit_ids)
	print("ChargeController: Completed charges: ", current_phase.get_completed_charges() if current_phase.has_method("get_completed_charges") else "N/A")
	
	var can_charge_count = 0
	for unit_id in eligible_unit_ids:
		if unit_id in units:
			var unit = units[unit_id]
			can_charge_count += 1
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			unit_selector.add_item(unit_name)
			unit_selector.set_item_metadata(unit_selector.get_item_count() - 1, unit_id)
			print("    Added eligible unit ", unit_id, " (", unit_name, ") to selector")
	
	print("ChargeController: Found ", can_charge_count, " units that can still charge")
	
	# CRITICAL: Ensure charge buttons exist and remain visible after refresh
	_ensure_charge_buttons_exist()
	
	# Update UI state
	_update_button_states()

func _can_unit_charge(unit: Dictionary) -> bool:
	# Use RulesEngine to check if unit can charge
	var unit_id = unit.get("id", "")
	var board = GameState.create_snapshot()
	return RulesEngine.eligible_to_charge(unit_id, board)

func _update_button_states() -> void:
	if not current_phase:
		print("DEBUG: _update_button_states() - no current_phase")
		return
	
	var has_selected_unit = active_unit_id != ""
	var has_selected_targets = selected_targets.size() > 0
	var can_declare = has_selected_unit and has_selected_targets and not awaiting_roll and not awaiting_movement
	var can_roll = awaiting_roll
	var can_skip = has_selected_unit and not awaiting_movement
	
	print("DEBUG: Button states - unit:", active_unit_id, " targets:", selected_targets.size(), " awaiting_roll:", awaiting_roll, " awaiting_movement:", awaiting_movement)
	print("DEBUG: has_selected_unit:", has_selected_unit, " has_selected_targets:", has_selected_targets, " can_declare:", can_declare)
	
	if is_instance_valid(declare_button):
		declare_button.disabled = not can_declare
	if is_instance_valid(roll_button):
		roll_button.disabled = not can_roll
	if is_instance_valid(skip_button):
		skip_button.disabled = not can_skip
	
	# Update charge status
	_update_charge_status()
	
	if is_instance_valid(declare_button):
		print("DEBUG: Declare button disabled:", declare_button.disabled)
	
	# Update info label with clear step-by-step instructions
	if is_instance_valid(charge_info_label):
		if awaiting_movement:
			charge_info_label.text = "Use UI to move models into engagement range"
		elif awaiting_roll:
			charge_info_label.text = "Click 'Roll 2D6' for charge distance"
		elif has_selected_unit and not has_selected_targets:
			charge_info_label.text = "Step 2: Click target(s) from the list below to select them"
		elif has_selected_unit and has_selected_targets:
			charge_info_label.text = "Step 3: Click 'Declare Charge' to proceed"
		else:
			charge_info_label.text = "Step 1: Select a unit from the list below to begin charge"

func _on_unit_selected(index: int) -> void:
	print("ChargeController: Unit selected at index ", index)
	if index >= 0 and index < unit_selector.get_item_count():
		active_unit_id = unit_selector.get_item_metadata(index)
		print("Selected unit for charge: ", active_unit_id)
		
		# Reset charge state for the new unit
		awaiting_roll = false
		awaiting_movement = false
		selected_targets.clear()
		
		# Ensure buttons are visible when selecting a unit
		if is_instance_valid(declare_button):
			declare_button.visible = true
		if is_instance_valid(roll_button):
			roll_button.visible = true
		if is_instance_valid(skip_button):
			skip_button.visible = true
			skip_button.disabled = false  # Can always skip once a unit is selected
		
		# Get eligible targets for this unit
		var board = GameState.create_snapshot()
		eligible_targets = RulesEngine.charge_targets_within_12(active_unit_id, board)
		
		print("Found ", eligible_targets.size(), " eligible targets for unit ", active_unit_id)
		for target_id in eligible_targets:
			print("  - ", target_id, ": ", eligible_targets[target_id])
		
		# Update target list
		_refresh_target_list()
		_update_button_states()
		_update_visuals()

func _refresh_target_list() -> void:
	if not is_instance_valid(target_list):
		return
	target_list.clear()
	selected_targets.clear()
	
	print("DEBUG: _refresh_target_list - adding ", eligible_targets.size(), " targets")
	for target_id in eligible_targets:
		var target_data = eligible_targets[target_id]
		var display_text = "%s (%.1f\")" % [target_data.name, target_data.distance]
		target_list.add_item(display_text)
		var item_index = target_list.get_item_count() - 1
		target_list.set_item_metadata(item_index, target_id)
		print("DEBUG: Added target item ", item_index, ": '", display_text, "' with metadata: ", target_id)
	
	print("DEBUG: Target list now has ", target_list.get_item_count(), " items")

func _on_target_list_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			print("DEBUG: Mouse left click detected on target_list at position: ", mouse_event.position)
			
			# Manual item selection since the signal isn't working
			var item_at_pos = target_list.get_item_at_position(mouse_event.position)
			print("DEBUG: Item at position: ", item_at_pos)
			
			if item_at_pos >= 0:
				print("DEBUG: Manually selecting item ", item_at_pos)
				target_list.select(item_at_pos)
				# Manually call the selection handler
				_on_target_selected(item_at_pos)

func _on_target_selected(index: int) -> void:
	print("DEBUG: _on_target_selected called with index:", index)
	if index >= 0 and index < target_list.get_item_count():
		var target_id = target_list.get_item_metadata(index)
		print("DEBUG: Target ID from metadata:", target_id)
		
		# Check if item is actually selected (for multi-select handling)
		var is_selected = target_list.is_selected(index)
		print("DEBUG: Item is_selected status:", is_selected)
		
		if is_selected:
			if target_id not in selected_targets:
				selected_targets.append(target_id)
				print("✅ Selected target: ", target_id, " (", selected_targets.size(), " total targets)")
			else:
				print("DEBUG: Target already in selected_targets list")
		else:
			# Item was deselected
			if target_id in selected_targets:
				selected_targets.erase(target_id)
				print("❌ Deselected target: ", target_id, " (", selected_targets.size(), " remaining targets)")
			else:
				print("DEBUG: Target was not in selected_targets list")
		
		print("DEBUG: selected_targets array after update:", selected_targets)
		_update_button_states()
		_update_visuals()
	else:
		print("DEBUG: Invalid index - index:", index, " item_count:", target_list.get_item_count())

func _update_visuals() -> void:
	# Clear existing visuals
	if is_instance_valid(charge_line_visual):
		charge_line_visual.clear_points()
	_clear_highlights()
	
	if active_unit_id == "":
		return
	
	# Get unit position
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		return
	
	var unit_center = _get_unit_center_position(unit)
	
	# Draw lines to selected targets
	for target_id in selected_targets:
		var target_unit = GameState.get_unit(target_id)
		if not target_unit.is_empty():
			var target_center = _get_unit_center_position(target_unit)
			if is_instance_valid(charge_line_visual):
				charge_line_visual.add_point(unit_center)
				charge_line_visual.add_point(target_center)
			
			# Add highlight to target
			_highlight_unit(target_id, HIGHLIGHT_COLOR_SELECTED)
	
	# Highlight eligible targets
	for target_id in eligible_targets:
		if target_id not in selected_targets:
			_highlight_unit(target_id, HIGHLIGHT_COLOR_ELIGIBLE)

func _get_unit_center_position(unit: Dictionary) -> Vector2:
	var models = unit.get("models", [])
	if models.is_empty():
		return Vector2.ZERO
	
	var center = Vector2.ZERO
	var count = 0
	
	for model in models:
		if model.get("alive", true):
			var pos = model.get("position")
			if pos:
				center += Vector2(pos.get("x", 0), pos.get("y", 0))
				count += 1
	
	if count > 0:
		center /= count
	
	return center

func _highlight_unit(unit_id: String, color: Color) -> void:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var pos = model.get("position")
		if not pos:
			continue
		
		var highlight = ColorRect.new()
		highlight.position = Vector2(pos.get("x", 0), pos.get("y", 0)) - Vector2(16, 16)
		highlight.size = Vector2(32, 32)
		highlight.color = color
		target_highlights.add_child(highlight)

func _clear_highlights() -> void:
	for child in target_highlights.get_children():
		child.queue_free()

func _log_unit_positions(unit_id: String, label: String) -> void:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		print("DEBUG: ", label, " (", unit_id, ") - Unit not found")
		return
	
	print("DEBUG: ", label, " (", unit_id, ") positions:")
	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		var pos = model.get("position", {})
		if pos.has("x") and pos.has("y"):
			print("  Model ", i, " (", model.get("id", ""), "): (", pos.x, ", ", pos.y, ")")
		else:
			print("  Model ", i, " (", model.get("id", ""), "): no position")

func _is_charge_successful(unit_id: String, rolled_distance: int, target_ids: Array) -> bool:
	# Check if at least one model can reach engagement range (1") of any target
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return false
	
	var rolled_px = Measurement.inches_to_px(rolled_distance)
	var engagement_px = Measurement.inches_to_px(1.0)  # 1" engagement range
	
	# Check each model in the charging unit
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue
		
		var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		
		# Check against each target unit
		for target_id in target_ids:
			var target = GameState.get_unit(target_id)
			if target.is_empty():
				continue
			
			# Find closest enemy model
			for target_model in target.get("models", []):
				if not target_model.get("alive", true):
					continue
				
				var target_pos = _get_model_position(target_model)
				if target_pos == null:
					continue
				
				var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
				
				# Calculate edge-to-edge distance
				var edge_distance = model_pos.distance_to(target_pos) - model_radius - target_radius
				
				# Check if this model could reach engagement range with the rolled distance
				if edge_distance - engagement_px <= rolled_px:
					print("Charge successful: Model can reach engagement range with roll of ", rolled_distance)
					return true
	
	print("Charge failed: No models can reach engagement range with roll of ", rolled_distance)
	return false

func _enable_charge_movement(unit_id: String, max_distance: int) -> void:
	print("Enabling charge movement for ", unit_id, " with max distance ", max_distance)
	
	# Clear any previous movement tracking
	models_to_move.clear()
	moved_models.clear()
	_clear_movement_visuals()
	
	# Get all alive models in the unit
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		print("ERROR: Unit ", unit_id, " not found in GameState!")
		return
	
	print("DEBUG: Unit has ", unit.get("models", []).size(), " models total")
	for model in unit.get("models", []):
		if model.get("alive", true):
			var model_id = model.get("id", "")
			models_to_move.append(model_id)
			print("DEBUG: Added model ", model_id, " to models_to_move")
	
	print("Models to move: ", models_to_move)
	
	# Add confirm button if not already present
	if not confirm_button:
		_add_confirm_button()
	
	if confirm_button and is_instance_valid(confirm_button):
		confirm_button.visible = true
		confirm_button.disabled = true  # Enable when at least one model moved
		print("DEBUG: Confirm button made visible and disabled")
		print("DEBUG: Confirm button position: ", confirm_button.position)
		print("DEBUG: Confirm button size: ", confirm_button.size)
	else:
		print("WARNING: Confirm button not created!")

func _clear_movement_visuals() -> void:
	# Clear ghost visual
	if ghost_visual and is_instance_valid(ghost_visual):
		ghost_visual.queue_free()
		ghost_visual = null
	
	# Clear movement lines
	for line in movement_lines.values():
		if is_instance_valid(line):
			line.queue_free()
	movement_lines.clear()

func _add_confirm_button() -> void:
	var container = hud_bottom.get_node_or_null("HBoxContainer")
	if not container:
		print("DEBUG: No HBoxContainer found for confirm button")
		return
	
	confirm_button = Button.new()
	confirm_button.text = "Confirm Charge Moves"
	confirm_button.visible = false
	print("DEBUG: Connecting confirm button signal...")
	confirm_button.pressed.connect(_on_confirm_charge_moves)
	print("DEBUG: Signal connected, adding to container...")
	container.add_child(confirm_button)
	print("DEBUG: Confirm button created and added to container")

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _get_model_at_position(world_pos: Vector2) -> Dictionary:
	# Find model under the cursor
	print("DEBUG: Looking for model at position ", world_pos, " for unit ", active_unit_id)
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		print("DEBUG: Unit ", active_unit_id, " not found in GameState")
		return {}
	
	print("DEBUG: Unit has ", unit.get("models", []).size(), " models")
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue
		
		var base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		var distance = model_pos.distance_to(world_pos)
		print("DEBUG: Model ", model.get("id", ""), " at ", model_pos, " distance: ", distance, " radius: ", base_radius)
		
		if distance <= base_radius:
			print("DEBUG: Found model ", model.get("id", ""))
			return model
	
	print("DEBUG: No model found at position")
	return {}

func _start_model_drag(model: Dictionary, world_pos: Vector2) -> void:
	var model_id = model.get("id", "")
	print("Starting drag for model ", model_id)
	
	# Store the original position in case we need to revert
	var original_pos = _get_model_position(model)
	if original_pos:
		# Store original position in the model for reverting if needed
		dragging_model["original_position"] = original_pos
	
	# Create ghost visual to show where the model will be moved
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if board_root:
		# Create ghost visual
		ghost_visual = Node2D.new()
		ghost_visual.name = "ChargeGhost_" + model_id
		board_root.add_child(ghost_visual)
		
		# Create ghost circle matching model base size
		var base_mm = model.get("base_mm", 32)
		var radius = Measurement.base_radius_px(base_mm)
		
		var circle = preload("res://scripts/CircleShape.gd").new()
		circle.radius = radius
		circle.color = Color(0, 1, 0, 0.7)  # Semi-transparent green
		ghost_visual.add_child(circle)
		ghost_visual.position = world_pos
		
		# Create movement line to show the path
		var line = Line2D.new()
		line.width = 2
		line.default_color = Color.YELLOW
		line.add_point(original_pos)
		line.add_point(world_pos)
		board_root.add_child(line)
		movement_lines[model_id] = line
		
		print("DEBUG: Created ghost visual and movement line for ", model_id)

func _update_model_drag(world_pos: Vector2) -> void:
	if not dragging_model:
		return
	
	var model_id = dragging_model.get("id", "")
	
	# TEMPORARY: Don't move the actual token during drag to prevent disappearing
	# Just update the ghost visual instead
	if ghost_visual:
		ghost_visual.position = world_pos
	
	# Update movement line
	if model_id in movement_lines:
		var line = movement_lines[model_id]
		if line.get_point_count() > 1:
			line.set_point_position(1, world_pos)
	
	# Check if position is valid (within charge distance and rules)
	var is_valid = _validate_charge_position(dragging_model, world_pos)
	
	# Calculate distance moved for display
	var original_pos = dragging_model.get("original_position")
	if original_pos:
		var distance_moved_px = original_pos.distance_to(world_pos)
		var distance_moved_inches = Measurement.px_to_inches(distance_moved_px)
		
		# Update distance display with preview
		_update_charge_distance_display_with_preview(distance_moved_inches, is_valid)

func _end_model_drag(world_pos: Vector2) -> void:
	if not dragging_model:
		return
	
	var model_id = dragging_model.get("id", "")
	
	# Validate final position
	if _validate_charge_position(dragging_model, world_pos):
		print("Model ", model_id, " moved to valid position")
		
		# Calculate and store distance moved
		var start_pos = _get_model_position(dragging_model)
		if start_pos:
			var distance_moved_px = start_pos.distance_to(world_pos)
			var distance_moved_inches = Measurement.px_to_inches(distance_moved_px)
			
			# Update distance display for this model
			_update_charge_distance_display(model_id, distance_moved_inches)
		
		# Store the new position
		moved_models[model_id] = world_pos
		
		# Move the visual token to the new position (only on successful drag end)
		print("DEBUG: Moving token visual after successful drag")
		_move_token_visual(active_unit_id, model_id, world_pos)
		
		# Update the model position in GameState directly
		print("DEBUG: Updating GameState position after successful drag")
		_update_model_position_in_gamestate(active_unit_id, model_id, world_pos)
		
		# Remove from models to move
		models_to_move.erase(model_id)
		
		# Update button state
		if moved_models.size() > 0 and is_instance_valid(confirm_button):
			confirm_button.disabled = false
			print("DEBUG: Confirm button enabled - moved_models.size() = ", moved_models.size())
			print("DEBUG: Confirm button global position: ", confirm_button.global_position)
			print("DEBUG: Confirm button global rect: ", confirm_button.get_global_rect())
			print("DEBUG: Confirm button visible: ", confirm_button.visible)
		else:
			print("DEBUG: Confirm button not enabled - moved_models.size() = ", moved_models.size(), " confirm_button valid = ", is_instance_valid(confirm_button))
		
		# Update info
		if is_instance_valid(charge_info_label):
			if models_to_move.is_empty():
				charge_info_label.text = "All models moved! Click 'Confirm Charge Moves' to complete"
			else:
				charge_info_label.text = "Move remaining %d models into engagement range" % models_to_move.size()
	else:
		print("Model ", model_id, " position invalid - reverting")
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Invalid position! Must be within %d\" and reach engagement range" % charge_distance
		
		# Revert token to original position if drag was invalid
		var original_pos = dragging_model.get("original_position")
		if original_pos:
			_move_token_visual(active_unit_id, model_id, original_pos)
			print("DEBUG: Reverted token ", model_id, " to original position ", original_pos)
	
	# Clean up ghost visual and movement line
	if ghost_visual:
		ghost_visual.queue_free()
		ghost_visual = null
	
	# Clean up movement line
	if model_id in movement_lines:
		var line = movement_lines[model_id]
		if is_instance_valid(line):
			line.queue_free()
		movement_lines.erase(model_id)
	
	dragging_model = null

func _move_token_visual(unit_id: String, model_id: String, new_pos: Vector2) -> void:
	# Find and move the actual token visual on screen
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if not token_layer:
		print("ERROR: TokenLayer not found, cannot move token visual")
		return
	
	print("DEBUG: Looking for token with unit_id=", unit_id, " model_id=", model_id)
	print("DEBUG: TokenLayer has ", token_layer.get_child_count(), " children")
	
	# Find the specific token for this model
	var found = false
	for i in range(token_layer.get_child_count()):
		var child = token_layer.get_child(i)
		
		# Debug what we're looking at
		if child.has_meta("unit_id") and child.has_meta("model_id"):
			var token_unit_id = child.get_meta("unit_id")
			var token_model_id = child.get_meta("model_id")
			print("DEBUG: Child ", i, " has unit_id=", token_unit_id, " model_id=", token_model_id)
			
			if token_unit_id == unit_id and token_model_id == model_id:
				# Found the token! Check current state
				print("DEBUG: FOUND TOKEN! Current position: ", child.global_position)
				print("DEBUG: Current visibility: ", child.visible, " modulate: ", child.modulate)
				
				# Move it using local position (since token is child of TokenLayer)
				child.position = new_pos
				child.visible = true  # Ensure it stays visible
				child.modulate = Color.WHITE  # Ensure it's not faded
				child.z_index = 10  # Bring to front to ensure it's not hidden
				
				# Double-check final state
				print("DEBUG: Token moved to position: ", child.position)
				print("DEBUG: Token global_position: ", child.global_position)
				print("DEBUG: Final visibility: ", child.visible, " modulate: ", child.modulate)
				print("DEBUG: Token name: ", child.name, " z_index: ", child.z_index)
				found = true
				return
	
	if not found:
		print("WARNING: Could not find token visual for unit=", unit_id, " model=", model_id)
		print("DEBUG: Available tokens in TokenLayer:")
		for i in range(token_layer.get_child_count()):
			var child = token_layer.get_child(i)
			if child.has_meta("unit_id") and child.has_meta("model_id"):
				print("  - unit_id=", child.get_meta("unit_id"), " model_id=", child.get_meta("model_id"))

func _update_model_position_in_gamestate(unit_id: String, model_id: String, new_pos: Vector2) -> void:
	# Directly update the model position in GameState for immediate persistence
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		print("ERROR: Cannot find unit ", unit_id, " in GameState")
		return
	
	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		if model.get("id", "") == model_id:
			# Update the position directly in GameState
			GameState.state.units[unit_id].models[i].position = {"x": new_pos.x, "y": new_pos.y}
			print("DEBUG: Updated GameState position for ", model_id, " to ", new_pos)
			return
	
	print("ERROR: Could not find model ", model_id, " in unit ", unit_id)

func _validate_charge_position(model: Dictionary, new_pos: Vector2) -> bool:
	# Check 1: Movement distance
	var old_pos = _get_model_position(model)
	if old_pos == null:
		return false
	
	var distance_moved = Measurement.px_to_inches(old_pos.distance_to(new_pos))
	if distance_moved > charge_distance:
		print("Movement too far: ", distance_moved, " > ", charge_distance)
		return false
	
	# Check 2: For individual model validation during drag, we're more lenient
	# We only require that the model is moving toward an enemy (not strict engagement)
	# The full unit validation will happen when confirming the charge
	print("DEBUG: Model position validation passed for individual drag")
	
	return true

func _on_confirm_charge_moves() -> void:
	print("DEBUG: _on_confirm_charge_moves called!")
	print("Confirming charge moves for ", active_unit_id)
	
	# Build the per-model paths for the charge action
	var per_model_paths = {}
	print("DEBUG: Building per_model_paths from moved_models: ", moved_models.keys())
	for model_id in moved_models:
		var new_pos = moved_models[model_id]
		print("DEBUG: Processing moved model ", model_id, " to position ", new_pos)
		# For charge moves, we just need start and end positions
		var unit = GameState.get_unit(active_unit_id)
		var old_pos = null
		for model in unit.get("models", []):
			if model.get("id", "") == model_id:
				old_pos = _get_model_position(model)
				break
		
		if old_pos and new_pos:
			per_model_paths[model_id] = [[old_pos.x, old_pos.y], [new_pos.x, new_pos.y]]
			print("DEBUG: Created path for ", model_id, ": ", per_model_paths[model_id])
		else:
			print("DEBUG: Failed to create path for ", model_id, " - old_pos: ", old_pos, " new_pos: ", new_pos)
	
	# Send APPLY_CHARGE_MOVE action with the paths we built
	var action = {
		"type": "APPLY_CHARGE_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": {
			"per_model_paths": per_model_paths
		}
	}
	
	print("Requesting apply charge move: ", action)
	charge_action_requested.emit(action)
	
	# Send COMPLETE_UNIT_CHARGE action
	var complete_action = {
		"type": "COMPLETE_UNIT_CHARGE",
		"actor_unit_id": active_unit_id
	}
	print("Requesting complete unit charge: ", complete_action)
	charge_action_requested.emit(complete_action)
	
	# Clear the movement state
	moved_models.clear()
	models_to_move.clear()
	
	# Reset movement state
	awaiting_movement = false
	_clear_movement_visuals()
	if is_instance_valid(confirm_button):
		confirm_button.visible = false
	
	# Update UI for next charge selection
	_update_ui_for_next_charge()

func _on_declare_charge_pressed() -> void:
	if active_unit_id == "" or selected_targets.is_empty():
		return
	
	# DEBUG: Log positions before charge declaration
	print("=== CHARGE DEBUG: Before Declare Charge ===")
	_log_unit_positions(active_unit_id, "CHARGING UNIT")
	for target_id in selected_targets:
		_log_unit_positions(target_id, "TARGET UNIT")
	print("=== End Position Logging ===")
	
	var action = {
		"type": "DECLARE_CHARGE",
		"actor_unit_id": active_unit_id,
		"payload": {
			"target_unit_ids": selected_targets
		}
	}
	
	print("Requesting charge declaration: ", action)
	charge_action_requested.emit(action)
	
	# Update state
	awaiting_roll = true
	_update_button_states()

func _on_roll_charge_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "CHARGE_ROLL",
		"actor_unit_id": active_unit_id
	}
	
	print("Requesting charge roll: ", action)
	charge_action_requested.emit(action)

func _on_skip_charge_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "SKIP_CHARGE",
		"actor_unit_id": active_unit_id
	}
	
	print("Requesting skip charge: ", action)
	charge_action_requested.emit(action)
	
	# Check for more eligible units
	_update_ui_for_next_charge()

func _on_next_unit_pressed() -> void:
	_reset_unit_selection()
	_refresh_ui()

func _on_end_phase_pressed() -> void:
	var action = {
		"type": "END_CHARGE"
	}
	
	print("Requesting end charge phase: ", action)
	charge_action_requested.emit(action)

func _update_ui_for_next_charge() -> void:
	# Clear current unit selection
	active_unit_id = ""
	selected_targets.clear()
	eligible_targets.clear()
	awaiting_roll = false
	awaiting_movement = false
	
	if is_instance_valid(unit_selector):
		unit_selector.deselect_all()
	if is_instance_valid(target_list):
		target_list.clear()
	_clear_highlights()
	if is_instance_valid(charge_line_visual):
		charge_line_visual.clear_points()
	
	# Reset button states for charge buttons (keep them visible but disabled initially)
	if is_instance_valid(declare_button):
		declare_button.visible = true
		declare_button.disabled = true
	if is_instance_valid(roll_button):
		roll_button.visible = true
		roll_button.disabled = true
	if is_instance_valid(skip_button):
		skip_button.visible = true
		skip_button.disabled = true
	
	# Hide charge distance display
	_hide_charge_distance_display()
	
	# Ensure the charge panel and buttons are visible
	_ensure_charge_panel_visible()
	_ensure_charge_buttons_exist()
	
	# Check if more units can charge
	if current_phase and is_instance_valid(current_phase):
		var eligible_units = current_phase.get_eligible_charge_units()
		if eligible_units.size() > 0:
			# Immediately show available units and update status
			if is_instance_valid(charge_info_label):
				charge_info_label.text = "Charge complete! Select another unit to charge or end phase."
			_update_charge_status()
			_refresh_ui()  # Refresh immediately to show available units
			
			# Hide next unit button since units are already available
			if is_instance_valid(next_unit_button):
				next_unit_button.visible = false
		else:
			# No more units can charge
			if is_instance_valid(next_unit_button):
				next_unit_button.visible = false
			if is_instance_valid(charge_info_label):
				charge_info_label.text = "All eligible units have charged."
			_update_charge_status()
			_refresh_ui()
	else:
		_refresh_ui()

func _ensure_charge_buttons_exist() -> void:
	# Make sure charge action buttons exist and are properly set up
	if not hud_bottom:
		print("ERROR: No hud_bottom reference in _ensure_charge_buttons_exist")
		return
		
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: No HBoxContainer in HUD_Bottom")
		return
		
	var charge_controls = main_container.get_node_or_null("ChargeControls")
	
	# If ChargeControls container doesn't exist or buttons are missing, recreate them
	if not charge_controls or not is_instance_valid(declare_button) or not is_instance_valid(roll_button) or not is_instance_valid(skip_button):
		print("DEBUG: Charge buttons missing, recreating bottom HUD")
		_setup_bottom_hud()
		return
	
	# Ensure the container and all buttons are visible
	charge_controls.visible = true
	
	if is_instance_valid(declare_button):
		declare_button.visible = true
		print("DEBUG: Declare button ensured visible")
	else:
		print("ERROR: Declare button not valid!")
		
	if is_instance_valid(roll_button):
		roll_button.visible = true
		print("DEBUG: Roll button ensured visible")
	else:
		print("ERROR: Roll button not valid!")
		
	if is_instance_valid(skip_button):
		skip_button.visible = true
		print("DEBUG: Skip button ensured visible")
	else:
		print("ERROR: Skip button not valid!")

func _ensure_charge_panel_visible() -> void:
	# Make sure the charge panel and its contents are visible
	if not hud_right:
		print("ERROR: No hud_right reference")
		return
		
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		print("DEBUG: No VBoxContainer found, recreating right panel")
		_setup_right_panel()
		return
	
	var charge_scroll = container.get_node_or_null("ChargeScrollContainer")
	if not charge_scroll:
		print("DEBUG: No ChargeScrollContainer found, recreating right panel")
		_setup_right_panel()
		return
	
	var charge_panel = charge_scroll.get_node_or_null("ChargePanel")
	if not charge_panel:
		print("DEBUG: No ChargePanel found, recreating right panel")
		_setup_right_panel()
		return
	
	# Ensure all components are visible
	hud_right.visible = true
	container.visible = true
	charge_scroll.visible = true
	charge_panel.visible = true
	
	# Also ensure unit_selector exists and is visible
	if is_instance_valid(unit_selector):
		unit_selector.visible = true
		print("DEBUG: Charge panel hierarchy made visible, unit_selector ready")
	else:
		print("ERROR: unit_selector not valid after ensuring panel visibility")
		_setup_right_panel()
		
	# Ensure HUD_Bottom and charge buttons are visible
	if hud_bottom:
		hud_bottom.visible = true
		var bottom_container = hud_bottom.get_node_or_null("HBoxContainer")
		if bottom_container:
			bottom_container.visible = true
			var charge_controls = bottom_container.get_node_or_null("ChargeControls")
			if charge_controls:
				charge_controls.visible = true
				print("DEBUG: Bottom HUD charge controls made visible")
				
	# Ensure charge action buttons are visible
	if is_instance_valid(declare_button):
		declare_button.visible = true
		print("DEBUG: Declare button made visible")
	if is_instance_valid(roll_button):
		roll_button.visible = true
		print("DEBUG: Roll button made visible") 
	if is_instance_valid(skip_button):
		skip_button.visible = true
		print("DEBUG: Skip button made visible")

func _update_charge_status() -> void:
	if not current_phase or not is_instance_valid(current_phase):
		return
	
	var completed = current_phase.get_completed_charges().size()
	var eligible = current_phase.get_eligible_charge_units().size()
	
	if is_instance_valid(charge_status_label):
		charge_status_label.text = "Charges: %d completed, %d eligible" % [completed, eligible]

func _reset_unit_selection() -> void:
	active_unit_id = ""
	selected_targets.clear()
	eligible_targets.clear()
	awaiting_roll = false
	awaiting_movement = false
	
	if is_instance_valid(unit_selector):
		unit_selector.deselect_all()
	if is_instance_valid(target_list):
		target_list.clear()
	_clear_highlights()
	if is_instance_valid(charge_line_visual):
		charge_line_visual.clear_points()
	
	# Hide charge distance display
	_hide_charge_distance_display()
	_update_button_states()

# Signal handlers from ChargePhase
func _on_unit_selected_for_charge(unit_id: String) -> void:
	print("Phase selected unit for charge: ", unit_id)
	# UI already handled the selection

func _on_charge_targets_available(unit_id: String, targets: Dictionary) -> void:
	print("Charge targets available for ", unit_id, ": ", targets.keys())
	# UI already updated targets

func _on_charge_roll_made(unit_id: String, distance: int, dice: Array) -> void:
	print("Charge roll made: ", unit_id, " rolled ", distance, " (", dice, ")")
	
	charge_distance = distance
	awaiting_roll = false
	
	# Update dice log
	var dice_text = "[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
		unit_id, distance, dice[0], dice[1]
	]
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text(dice_text)
	
	# Check if charge is successful (can at least one model reach engagement range?)
	var success = _is_charge_successful(unit_id, distance, selected_targets)
	
	if success:
		awaiting_movement = true
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Success! Rolled %d\" - Click models to move them into engagement (max %d\" each)" % [distance, distance]
		if is_instance_valid(dice_log_display):
			dice_log_display.append_text("[color=green]Charge successful! Move models into engagement range.[/color]\n")
		
		# Enable charge movement for this unit
		_enable_charge_movement(unit_id, distance)
		
		# Show charge distance tracking
		_show_charge_distance_display(distance)
	else:
		awaiting_movement = false
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Failed! Rolled %d\" - not enough to reach target" % distance
		if is_instance_valid(dice_log_display):
			dice_log_display.append_text("[color=red]Charge failed! Rolled distance insufficient to reach engagement range.[/color]\n")
		
		# Reset for next unit
		_reset_unit_selection()
	
	_update_button_states()

func _on_charge_resolved(unit_id: String, success: bool, result: Dictionary) -> void:
	print("Charge resolved: ", unit_id, " success: ", success)
	
	# DEBUG: Log positions after charge resolution
	print("=== CHARGE DEBUG: After Charge Resolved ===")
	_log_unit_positions(unit_id, "CHARGING UNIT")
	for target_id in selected_targets:
		_log_unit_positions(target_id, "TARGET UNIT")
	print("=== End Position Logging ===")
	
	var result_text = ""
	if success:
		result_text = "[color=green]Successful charge![/color] %s moved into engagement range\n" % unit_id
	else:
		var reason = result.get("reason", "Failed")
		result_text = "[color=red]Charge failed:[/color] %s - %s\n" % [unit_id, reason]
	
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text(result_text)
	
	# Reset UI state
	_reset_unit_selection()
	_refresh_ui()

func process_action(action: Dictionary) -> void:
	if not current_phase:
		return
	
	print("ChargeController processing action: ", action.get("type", ""))
	
	# Validate action with current phase
	var validation = current_phase.validate_action(action)
	if not validation.get("valid", false):
		print("Action validation failed: ", validation.get("errors", []))
		return
	
	# Process action through current phase
	var result = current_phase.process_action(action)
	if result.get("success", false):
		print("Action processed successfully")
		
		# Apply state changes if any
		var changes = result.get("changes", [])
		if not changes.is_empty():
			PhaseManager.apply_state_changes(changes)
		
		# Refresh UI after action
		_refresh_ui()
	else:
		print("Action processing failed: ", result.get("error", "Unknown error"))

func _process(delta: float) -> void:
	# Update available actions periodically
	if current_phase:
		var actions = current_phase.get_available_actions()
		# Could update UI based on available actions if needed

# Charge movement distance display functions
func _show_charge_distance_display(max_distance: int) -> void:
	if is_instance_valid(charge_distance_label):
		charge_distance_label.text = "Charge: %d\"" % max_distance
		charge_distance_label.visible = true
	
	if is_instance_valid(charge_used_label):
		charge_used_label.text = "Used: 0.0\""
		charge_used_label.visible = true
	
	if is_instance_valid(charge_left_label):
		charge_left_label.text = "Left: %d.0\"" % max_distance
		charge_left_label.visible = true

func _hide_charge_distance_display() -> void:
	if is_instance_valid(charge_distance_label):
		charge_distance_label.visible = false
	if is_instance_valid(charge_used_label):
		charge_used_label.visible = false
	if is_instance_valid(charge_left_label):
		charge_left_label.visible = false

func _update_charge_distance_display(model_id: String, distance_moved: float) -> void:
	if not is_instance_valid(charge_used_label) or not is_instance_valid(charge_left_label):
		return
	
	# Calculate total distance used by this model
	var total_used = distance_moved
	var left = charge_distance - total_used
	var valid = left >= 0
	
	# Update labels
	charge_used_label.text = "Used: %.1f\"" % total_used
	charge_used_label.modulate = Color.WHITE if valid else Color.RED
	
	charge_left_label.text = "Left: %.1f\"" % left
	charge_left_label.modulate = Color.WHITE if left >= 0 else Color.RED

func _update_charge_distance_display_with_preview(distance_moved: float, valid: bool) -> void:
	if not is_instance_valid(charge_used_label) or not is_instance_valid(charge_left_label):
		return
	
	var left = charge_distance - distance_moved
	
	# Update labels with preview
	charge_used_label.text = "Used: %.1f\"" % distance_moved
	charge_used_label.modulate = Color.WHITE if valid else Color.RED
	
	charge_left_label.text = "Left: %.1f\"" % left
	charge_left_label.modulate = Color.WHITE if left >= 0 else Color.RED
