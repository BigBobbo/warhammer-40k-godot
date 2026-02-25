extends Node2D
class_name ChargeController

const GameStateData = preload("res://autoloads/GameState.gd")
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")


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
var last_processed_charge_roll: Dictionary = {}  # Tracks last processed roll to prevent duplicates
var _pending_complete_unit_id: String = ""  # Unit awaiting COMPLETE_UNIT_CHARGE after charge_resolved

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

# T7-58: Charge arrow visuals - animated arrows from charger to targets
var charge_arrow_visuals: Array = []  # Array of ChargeArrowVisual instances

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
var charge_status_label: Label
var dice_log_display: RichTextLabel
var dice_roll_visual: DiceRollVisual  # T5-V1: Animated dice roll visualization
var failed_charges_container: VBoxContainer  # Container for failed charge tooltip entries

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
	_clear_charge_arrow_visuals()  # T7-58
	_clear_movement_visuals()
	
	# Clean up bottom HUD elements (End Charge Phase button and related)
	var hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	if hud_bottom:
		var main_container = hud_bottom.get_node_or_null("HBoxContainer")
		if main_container and is_instance_valid(main_container):
			# Main.gd now handles phase action button cleanup
			
			# Remove any spacer controls we added
			for child in main_container.get_children():
				if child is Control and not (child is Button or child is Label or child is VSeparator):
					if child.size_flags_horizontal == Control.SIZE_EXPAND_FILL:
						main_container.remove_child(child)
						child.queue_free()
	
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
	elif event is InputEventKey:
		# Keyboard rotation controls during charge movement
		if event.pressed and dragging_model:
			if event.keycode == KEY_Q:
				_rotate_dragging_model(-PI/12)  # Rotate 15 degrees left
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_E:
				_rotate_dragging_model(PI/12)  # Rotate 15 degrees right
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

			# Get the model data from GameState
			var unit = GameState.get_unit(active_unit_id)
			print("DEBUG: Retrieved unit from GameState: ", unit.get("meta", {}).get("name", "unknown"))

			for model in unit.get("models", []):
				if model.get("id", "") == model_id:
					# Log the complete model data from GameState
					print("DEBUG: Model data from GameState:")
					print("  id: ", model.get("id", "NOT SET"))
					print("  base_mm: ", model.get("base_mm", "NOT SET"))
					print("  base_type: ", model.get("base_type", "NOT SET"))
					print("  base_dimensions: ", model.get("base_dimensions", "NOT SET"))
					print("  rotation: ", model.get("rotation", "NOT SET"))
					print("  position: ", model.get("position", "NOT SET"))
					print("  Full model keys: ", model.keys())

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
	# NOTE: Main.gd now handles the phase action button
	# ChargeController only manages charge-specific UI in the right panel
	pass

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
	scroll_container.custom_minimum_size = Vector2(250, 400)  # Standard size across all phases
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
	
	# T5-V1: Animated dice roll visualization
	dice_roll_visual = DiceRollVisual.new()
	dice_roll_visual.custom_minimum_size = Vector2(200, 0)
	dice_roll_visual.visible = false  # Hidden until first roll
	charge_panel.add_child(dice_roll_visual)

	dice_log_display = RichTextLabel.new()
	dice_log_display.custom_minimum_size = Vector2(200, 100)
	dice_log_display.bbcode_enabled = true
	charge_panel.add_child(dice_log_display)

	# ADD: Action buttons section after dice log
	charge_panel.add_child(HSeparator.new())
	
	# Charge status display (moved from top bar)
	var status_label = Label.new()
	status_label.text = "Charge Actions:"
	status_label.add_theme_font_size_override("font_size", 14)
	charge_panel.add_child(status_label)
	
	# Charge info label (moved from top bar)
	charge_info_label = Label.new()
	charge_info_label.text = "Step 1: Select a unit from the list above to begin charge"
	charge_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	charge_panel.add_child(charge_info_label)
	
	# Action buttons container
	var action_button_container = VBoxContainer.new()
	action_button_container.name = "ChargeActionButtons"
	
	# First row: Main action buttons
	var main_buttons = HBoxContainer.new()
	
	declare_button = Button.new()
	declare_button.text = "Declare Charge"
	declare_button.disabled = true
	declare_button.pressed.connect(_on_declare_charge_pressed)
	_WhiteDwarfTheme.apply_to_button(declare_button)
	main_buttons.add_child(declare_button)

	roll_button = Button.new()
	roll_button.text = "Roll 2D6"
	roll_button.disabled = true
	roll_button.pressed.connect(_on_roll_charge_pressed)
	_WhiteDwarfTheme.apply_to_button(roll_button)
	main_buttons.add_child(roll_button)
	
	action_button_container.add_child(main_buttons)
	
	# Second row: Secondary buttons
	var secondary_buttons = HBoxContainer.new()
	
	skip_button = Button.new()
	skip_button.text = "Skip Charge"
	skip_button.disabled = true
	skip_button.pressed.connect(_on_skip_charge_pressed)
	_WhiteDwarfTheme.apply_to_button(skip_button)
	secondary_buttons.add_child(skip_button)

	next_unit_button = Button.new()
	next_unit_button.text = "Select Next Unit"
	next_unit_button.disabled = true
	next_unit_button.visible = false
	next_unit_button.pressed.connect(_on_next_unit_pressed)
	_WhiteDwarfTheme.apply_to_button(next_unit_button)
	secondary_buttons.add_child(next_unit_button)
	
	action_button_container.add_child(secondary_buttons)
	
	charge_panel.add_child(action_button_container)
	
	# Distance tracking section (moved from top bar, initially hidden)
	var distance_container = VBoxContainer.new()
	distance_container.name = "DistanceTracking"
	
	charge_distance_label = Label.new()
	charge_distance_label.text = "Charge: 0\""
	charge_distance_label.visible = false
	distance_container.add_child(charge_distance_label)
	
	charge_used_label = Label.new()
	charge_used_label.text = "Used: 0.0\""
	charge_used_label.visible = false
	distance_container.add_child(charge_used_label)
	
	charge_left_label = Label.new()
	charge_left_label.text = "Left: 0.0\""
	charge_left_label.visible = false
	distance_container.add_child(charge_left_label)
	
	charge_panel.add_child(distance_container)
	
	# Charge status (moved from top bar)
	charge_status_label = Label.new()
	charge_status_label.text = ""
	charge_status_label.add_theme_font_size_override("font_size", 12)
	charge_panel.add_child(charge_status_label)

	# Failed Charges section - displays structured failure tooltips
	var failed_separator = HSeparator.new()
	charge_panel.add_child(failed_separator)

	var failed_header = Label.new()
	failed_header.text = "Failed Charges:"
	failed_header.add_theme_font_size_override("font_size", 13)
	charge_panel.add_child(failed_header)

	failed_charges_container = VBoxContainer.new()
	failed_charges_container.name = "FailedChargesContainer"
	charge_panel.add_child(failed_charges_container)

	# Start with a placeholder message
	var no_failures_label = Label.new()
	no_failures_label.name = "NoFailuresLabel"
	no_failures_label.text = "No failed charges yet"
	no_failures_label.add_theme_font_size_override("font_size", 11)
	no_failures_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	failed_charges_container.add_child(no_failures_label)

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

	if current_phase.has_signal("dice_rolled"):
		if not current_phase.dice_rolled.is_connected(_on_dice_rolled):
			current_phase.dice_rolled.connect(_on_dice_rolled)

	if current_phase.has_signal("charge_resolved"):
		if not current_phase.charge_resolved.is_connected(_on_charge_resolved):
			current_phase.charge_resolved.connect(_on_charge_resolved)

	if current_phase.has_signal("charge_unit_completed"):
		if not current_phase.charge_unit_completed.is_connected(_on_charge_unit_completed):
			current_phase.charge_unit_completed.connect(_on_charge_unit_completed)

	if current_phase.has_signal("charge_unit_skipped"):
		if not current_phase.charge_unit_skipped.is_connected(_on_charge_unit_skipped):
			current_phase.charge_unit_skipped.connect(_on_charge_unit_skipped)

	if current_phase.has_signal("ability_reroll_opportunity"):
		if not current_phase.ability_reroll_opportunity.is_connected(_on_ability_reroll_opportunity):
			current_phase.ability_reroll_opportunity.connect(_on_ability_reroll_opportunity)

	if current_phase.has_signal("command_reroll_opportunity"):
		if not current_phase.command_reroll_opportunity.is_connected(_on_command_reroll_opportunity):
			current_phase.command_reroll_opportunity.connect(_on_command_reroll_opportunity)

	if current_phase.has_signal("overwatch_opportunity"):
		if not current_phase.overwatch_opportunity.is_connected(_on_overwatch_opportunity):
			current_phase.overwatch_opportunity.connect(_on_overwatch_opportunity)


	if current_phase.has_signal("heroic_intervention_opportunity"):
		if not current_phase.heroic_intervention_opportunity.is_connected(_on_heroic_intervention_opportunity):
			current_phase.heroic_intervention_opportunity.connect(_on_heroic_intervention_opportunity)

	if current_phase.has_signal("tank_shock_opportunity"):
		if not current_phase.tank_shock_opportunity.is_connected(_on_tank_shock_opportunity):
			current_phase.tank_shock_opportunity.connect(_on_tank_shock_opportunity)

	if current_phase.has_signal("tank_shock_result"):
		if not current_phase.tank_shock_result.is_connected(_on_tank_shock_result):
			current_phase.tank_shock_result.connect(_on_tank_shock_result)

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
	
	# Debug help: Show why units might not be eligible
	if eligible_unit_ids.is_empty():
		print("ChargeController: No units eligible for charge. Checking reasons...")
		for unit_id in units:
			var unit = units[unit_id]
			var status = unit.get("status", 0)
			var flags = unit.get("flags", {})
			var status_name = GameStateData.UnitStatus.keys()[status] if status < GameStateData.UnitStatus.size() else "UNKNOWN"
			
			print("  Unit ", unit_id, " (", unit.get("meta", {}).get("name", unit_id), "):")
			print("    Status: ", status, " (", status_name, ")")
			print("    Flags: ", flags)
			
			# Check specific blocking conditions
			if not (status == GameStateData.UnitStatus.DEPLOYED or status == GameStateData.UnitStatus.MOVED or status == GameStateData.UnitStatus.SHOT):
				print("    BLOCKED: Status must be DEPLOYED, MOVED, or SHOT")
			elif flags.get("cannot_charge", false):
				print("    BLOCKED: Unit has 'cannot_charge' flag")
			elif flags.get("advanced", false):
				print("    BLOCKED: Unit has 'advanced' flag (Advanced units cannot charge)")
			elif flags.get("fell_back", false):
				print("    BLOCKED: Unit has 'fell_back' flag")
			elif unit_id in current_phase.get_completed_charges():
				print("    BLOCKED: Unit has already charged this phase")
			else:
				print("    SHOULD BE ELIGIBLE - this might be a bug")
	
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
	_clear_charge_arrow_visuals()  # T7-58: Clear old arrows

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

			# T7-58: Create animated charge arrow visual
			_create_charge_arrow_visual(unit_center, target_center, false)

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

func _get_charge_targets_from_phase(unit_id: String) -> Array:
	"""Get the declared charge targets from ChargePhase's synced game state.

	This ensures both charging and defending players use the same target list
	when determining charge success, fixing the bug where defending players
	always see "charge failed" due to empty local selected_targets.

	NOTE: This only works on the host where pending_charges is populated.
	Clients should use targets from dice_data instead.
	"""
	if not current_phase:
		print("WARNING: No current_phase available to get charge targets")
		return []

	if not current_phase.has_method("get_pending_charges"):
		print("ERROR: current_phase doesn't have get_pending_charges method")
		return []

	var pending = current_phase.get_pending_charges()
	if not pending.has(unit_id):
		print("WARNING: No pending charge found for unit ", unit_id, " (this is expected on clients)")
		return []

	var charge_data = pending[unit_id]
	var targets = charge_data.get("targets", [])

	print("Retrieved ", targets.size(), " targets from phase for unit ", unit_id, ": ", targets)
	return targets

func _is_charge_successful(unit_id: String, rolled_distance: int, target_ids: Array) -> bool:
	# Check if at least one model can reach engagement range (1") of any target.
	# T1-8 fix: Use inches (same unit as ChargePhase._is_charge_roll_sufficient)
	# to ensure deterministic results and avoid pixel/inch conversion divergence.
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return false

	# T2-8: Check FLY keyword for terrain penalty calculation
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	# Check each model in the charging unit
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue

		# Check against each target unit
		for target_id in target_ids:
			var target = GameState.get_unit(target_id)
			if target.is_empty():
				continue

			# Find closest enemy model using shape-aware edge-to-edge distance
			for target_model in target.get("models", []):
				if not target_model.get("alive", true):
					continue

				var target_pos = _get_model_position(target_model)
				if target_pos == null:
					continue

				# Edge-to-edge distance in inches, minus engagement range (1")
				var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
				var distance_to_close = distance_inches - 1.0  # 1" engagement range

				# T2-8: Add terrain penalty for straight-line path
				var terrain_penalty = _calculate_terrain_penalty_for_path(model_pos, target_pos)
				var effective_distance = distance_to_close + terrain_penalty

				# Check if this model could reach engagement range with the rolled distance
				if effective_distance <= rolled_distance:
					print("Charge successful: Model can reach engagement range with roll of ", rolled_distance)
					return true

	print("Charge failed: No models can reach engagement range with roll of ", rolled_distance)
	return false

func _calculate_min_distance_to_targets(unit_id: String, target_ids: Array) -> float:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return INF

	var min_distance = INF
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		for target_id in target_ids:
			var target = GameState.get_unit(target_id)
			if target.is_empty():
				continue
			for target_model in target.get("models", []):
				if not target_model.get("alive", true):
					continue
				var dist = Measurement.model_to_model_distance_inches(model, target_model)
				min_distance = min(min_distance, dist)

	return min_distance

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
	# Add confirm button to right panel instead of top bar
	var right_container = hud_right.get_node_or_null("VBoxContainer")
	if not right_container:
		print("DEBUG: No VBoxContainer found in right panel for confirm button")
		return
	
	var charge_scroll = right_container.get_node_or_null("ChargeScrollContainer")
	if not charge_scroll:
		print("DEBUG: No ChargeScrollContainer found for confirm button")
		return
	
	var charge_panel = charge_scroll.get_node_or_null("ChargePanel")
	if not charge_panel:
		print("DEBUG: No ChargePanel found for confirm button")
		return
	
	# Find the action buttons container to add confirm button
	var action_container = charge_panel.get_node_or_null("ChargeActionButtons")
	if not action_container:
		print("DEBUG: No ChargeActionButtons container found for confirm button")
		return
	
	confirm_button = Button.new()
	confirm_button.text = "Confirm Charge Moves"
	confirm_button.visible = false
	_WhiteDwarfTheme.apply_to_button(confirm_button)
	print("DEBUG: Connecting confirm button signal...")
	confirm_button.pressed.connect(_on_confirm_charge_moves)
	print("DEBUG: Signal connected, adding to right panel...")
	
	# Add confirm button as a separate row in action container
	var confirm_row = HBoxContainer.new()
	confirm_row.add_child(confirm_button)
	action_container.add_child(confirm_row)
	print("DEBUG: Confirm button created and added to right panel")

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

	# DEBUG: Verify model data completeness
	print("DEBUG: Model Dictionary keys: ", model.keys())
	print("DEBUG: Model base_type: ", model.get("base_type", "NOT SET"))
	print("DEBUG: Model base_mm: ", model.get("base_mm", "NOT SET"))
	print("DEBUG: Model base_dimensions: ", model.get("base_dimensions", "NOT SET"))
	print("DEBUG: Model rotation: ", model.get("rotation", 0.0))

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

		# Use GhostVisual for consistent ghost rendering across all controllers
		var ghost_token = preload("res://scripts/GhostVisual.gd").new()
		var unit = GameState.get_unit(active_unit_id)
		ghost_token.owner_player = unit.get("owner", 1)
		# Set the complete model data for shape handling
		ghost_token.set_model_data(model)
		# Set initial rotation if model has one
		if model.has("rotation"):
			ghost_token.set_base_rotation(model.get("rotation", 0.0))

		# Set ghost appearance
		ghost_token.position = Vector2.ZERO
		ghost_visual.add_child(ghost_token)
		ghost_visual.modulate = Color(0, 1, 0, 0.7)  # Semi-transparent green
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

	# Update ghost visual color based on validity
	if ghost_visual:
		if is_valid:
			ghost_visual.modulate = Color(0, 1, 0, 0.7)  # Green for valid
		else:
			ghost_visual.modulate = Color(1, 0, 0, 0.7)  # Red for invalid

	# Calculate distance moved for display (including terrain penalty - T2-8)
	var original_pos = dragging_model.get("original_position")
	if original_pos:
		var distance_moved_px = original_pos.distance_to(world_pos)
		var distance_moved_inches = Measurement.px_to_inches(distance_moved_px)
		var terrain_penalty = _calculate_terrain_penalty_for_path(original_pos, world_pos)
		var effective_distance = distance_moved_inches + terrain_penalty

		# Update distance display with preview (show effective distance including terrain)
		_update_charge_distance_display_with_preview(effective_distance, is_valid)

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
		
		# Store the new position AND rotation
		moved_models[model_id] = {
			"position": world_pos,
			"rotation": dragging_model.get("rotation", 0.0)
		}

		# IMPORTANT: Update GameState FIRST with position and rotation
		# This ensures GameState has the correct data before we update visuals
		print("DEBUG: Updating GameState position and rotation FIRST")
		_update_model_position_in_gamestate(active_unit_id, model_id, world_pos)

		# NOW update the visual token (after GameState has been updated)
		print("DEBUG: Moving token visual after GameState update")
		var model_rotation = dragging_model.get("rotation", 0.0)
		_move_token_visual(active_unit_id, model_id, world_pos, model_rotation)
		
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
		
		# Revert token to original position and rotation if drag was invalid
		var original_pos = dragging_model.get("original_position")
		if original_pos:
			# Get original rotation from GameState
			var original_rotation = 0.0
			var unit = GameState.get_unit(active_unit_id)
			for model in unit.get("models", []):
				if model.get("id", "") == model_id:
					original_rotation = model.get("rotation", 0.0)
					break
			_move_token_visual(active_unit_id, model_id, original_pos, original_rotation)
			print("DEBUG: Reverted token ", model_id, " to original position ", original_pos, " and rotation ", rad_to_deg(original_rotation), " degrees")
	
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

func _move_token_visual(unit_id: String, model_id: String, new_pos: Vector2, rotation: float = 0.0) -> void:
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

				# Always update rotation when we're moving a model during charge
				# Priority: Use dragging_model rotation if available, otherwise use passed rotation
				var new_rotation = 0.0
				var should_update_rotation = false

				if dragging_model and dragging_model.get("id", "") == model_id:
					# This is the model we're dragging - use its current rotation
					new_rotation = dragging_model.get("rotation", 0.0)
					should_update_rotation = true
					print("DEBUG: Using rotation from dragging_model: ", rad_to_deg(new_rotation), " degrees")
				else:
					# Use the rotation parameter that was passed
					new_rotation = rotation
					should_update_rotation = true
					print("DEBUG: Using passed rotation: ", rad_to_deg(new_rotation), " degrees")

				# Apply rotation update if needed
				if should_update_rotation and child.get_child_count() > 0:
					var token_visual = child.get_child(0)
					if token_visual and token_visual.has_method("set_model_data"):
						# IMPORTANT: Use dragging_model if available (has correct rotation)
						var model_data = null
						if dragging_model and dragging_model.get("id", "") == model_id:
							# Use dragging_model which has all the current data
							model_data = dragging_model.duplicate()
						else:
							# Fall back to GameState but update rotation
							var unit = GameState.get_unit(unit_id)
							for model in unit.get("models", []):
								if model.get("id", "") == model_id:
									model_data = model.duplicate()
									model_data["rotation"] = new_rotation
									break

						if model_data:
							token_visual.set_model_data(model_data)
							token_visual.queue_redraw()
							print("DEBUG: Updated token rotation to ", rad_to_deg(new_rotation), " degrees")
						else:
							print("WARNING: No model data found for rotation update")

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

			# Also update rotation if this model has been rotated
			if dragging_model and dragging_model.get("id", "") == model_id:
				var new_rotation = dragging_model.get("rotation", 0.0)
				GameState.state.units[unit_id].models[i].rotation = new_rotation
				print("DEBUG: Updated GameState position and rotation for ", model_id, " to ", new_pos, " and ", rad_to_deg(new_rotation), " degrees")
				# NOTE: We don't update the token visual here because _move_token_visual will be called after this
			else:
				print("DEBUG: Updated GameState position for ", model_id, " to ", new_pos)
			return

	print("ERROR: Could not find model ", model_id, " in unit ", unit_id)

func _validate_charge_position(model: Dictionary, new_pos: Vector2) -> bool:
	# Check 1: Movement distance (including terrain penalty - T2-8)
	var old_pos = _get_model_position(model)
	if old_pos == null:
		return false

	var distance_moved = Measurement.px_to_inches(old_pos.distance_to(new_pos))

	# T2-8: Add terrain vertical distance penalty
	var terrain_penalty = _calculate_terrain_penalty_for_path(old_pos, new_pos)
	var effective_distance = distance_moved + terrain_penalty

	if effective_distance > charge_distance:
		if terrain_penalty > 0.0:
			print("Movement too far with terrain: %.1f\" + %.1f\" terrain = %.1f\" > %d\"" % [
				distance_moved, terrain_penalty, effective_distance, charge_distance])
		else:
			print("Movement too far: ", distance_moved, " > ", charge_distance)
		return false

	# Check 2: Model overlap detection
	if _check_position_would_overlap(model, new_pos):
		print("Position would overlap with another model")
		return false

	# Check 3 (T3-8): Each model must end closer to at least one charge target
	var charge_targets = selected_targets
	if charge_targets.is_empty() and current_phase:
		charge_targets = _get_charge_targets_from_phase(active_unit_id)
	if not charge_targets.is_empty():
		var ends_closer = false
		for target_id in charge_targets:
			var target_unit = GameState.get_unit(target_id)
			if target_unit.is_empty():
				continue
			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue
				var target_pos = _get_model_position(target_model)
				if target_pos == null or target_pos == Vector2.ZERO:
					continue
				if new_pos.distance_to(target_pos) < old_pos.distance_to(target_pos):
					ends_closer = true
					break
			if ends_closer:
				break
		if not ends_closer:
			print("T3-8: Model must end charge move closer to at least one charge target")
			return false

	print("DEBUG: Model position validation passed for individual drag")

	return true

func _on_confirm_charge_moves() -> void:
	print("DEBUG: _on_confirm_charge_moves called!")
	print("Confirming charge moves for ", active_unit_id)

	# Build the per-model paths and rotations for the charge action
	var per_model_paths = {}
	var per_model_rotations = {}
	print("DEBUG: Building per_model_paths from moved_models: ", moved_models.keys())
	for model_id in moved_models:
		var move_data = moved_models[model_id]
		var new_pos = move_data["position"] if move_data is Dictionary else move_data
		var new_rotation = move_data["rotation"] if move_data is Dictionary and move_data.has("rotation") else 0.0
		print("DEBUG: Processing moved model ", model_id, " to position ", new_pos, " with rotation ", rad_to_deg(new_rotation), " degrees")
		# For charge moves, we just need start and end positions
		var unit = GameState.get_unit(active_unit_id)
		var old_pos = null
		for model in unit.get("models", []):
			if model.get("id", "") == model_id:
				old_pos = _get_model_position(model)
				break

		if old_pos and new_pos:
			per_model_paths[model_id] = [[old_pos.x, old_pos.y], [new_pos.x, new_pos.y]]
			per_model_rotations[model_id] = new_rotation
			print("DEBUG: Created path for ", model_id, ": ", per_model_paths[model_id], " with rotation: ", rad_to_deg(new_rotation))
		else:
			print("DEBUG: Failed to create path for ", model_id, " - old_pos: ", old_pos, " new_pos: ", new_pos)

	# Store the unit_id so the charge_resolved handler can send COMPLETE_UNIT_CHARGE
	_pending_complete_unit_id = active_unit_id

	# Send APPLY_CHARGE_MOVE action with the paths and rotations we built
	# NOTE: COMPLETE_UNIT_CHARGE is now sent from _on_charge_resolved() after
	# the server confirms the charge succeeded, preventing state corruption if
	# APPLY_CHARGE_MOVE fails validation.
	var action = {
		"type": "APPLY_CHARGE_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": {
			"per_model_paths": per_model_paths,
			"per_model_rotations": per_model_rotations
		}
	}

	print("Requesting apply charge move: ", action)
	charge_action_requested.emit(action)

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

	# Also refresh failed charges display
	_refresh_failed_charges_display()

func _refresh_failed_charges_display() -> void:
	if not is_instance_valid(failed_charges_container):
		return
	if not current_phase or not current_phase.has_method("get_failed_charge_attempts"):
		return

	var failures = current_phase.get_failed_charge_attempts()

	# Clear existing children
	for child in failed_charges_container.get_children():
		child.queue_free()

	if failures.is_empty():
		var no_failures_label = Label.new()
		no_failures_label.name = "NoFailuresLabel"
		no_failures_label.text = "No failed charges yet"
		no_failures_label.add_theme_font_size_override("font_size", 11)
		no_failures_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		failed_charges_container.add_child(no_failures_label)
		return

	for failure in failures:
		var entry = _create_failure_tooltip_entry(failure)
		failed_charges_container.add_child(entry)

func _create_failure_tooltip_entry(failure: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()

	# Style the panel with a subtle dark background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.1, 0.1, 0.9)
	style.border_color = Color(0.6, 0.2, 0.2, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	# Header line: [CATEGORY] Unit Name (rolled X")
	var header = RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.custom_minimum_size = Vector2(220, 0)

	var unit_name = failure.get("unit_name", failure.get("unit_id", "Unknown"))
	var roll = failure.get("roll", 0)
	var primary_cat = failure.get("primary_category", "UNKNOWN")
	var cat_color = _get_category_color(primary_cat)
	var cat_tag = "[color=%s][%s][/color]" % [cat_color, primary_cat]

	header.text = "%s %s (rolled %d\")" % [cat_tag, unit_name, roll]
	vbox.add_child(header)

	# Detail lines for each categorized error
	var categorized = failure.get("categorized_errors", [])
	for cat_error in categorized:
		var detail_label = RichTextLabel.new()
		detail_label.bbcode_enabled = true
		detail_label.fit_content = true
		detail_label.scroll_active = false
		detail_label.custom_minimum_size = Vector2(220, 0)

		var cat = cat_error.get("category", "UNKNOWN")
		var detail = cat_error.get("detail", "")
		var detail_color = _get_category_color(cat)
		detail_label.text = " [color=%s]•[/color] %s" % [detail_color, detail]
		vbox.add_child(detail_label)

	# Tooltip text: shows the full rule explanation on hover
	var tooltip_lines = []
	var seen_categories = {}
	for cat_error in categorized:
		var cat = cat_error.get("category", "")
		if cat != "" and not seen_categories.has(cat):
			seen_categories[cat] = true
			if current_phase and current_phase.has_method("get_failure_category_tooltip"):
				tooltip_lines.append("[%s] %s" % [cat, current_phase.get_failure_category_tooltip(cat)])
	if tooltip_lines.size() > 0:
		panel.tooltip_text = "\n\n".join(tooltip_lines)
	else:
		panel.tooltip_text = "Charge failed. Hover for details."

	return panel

func _get_category_color(category: String) -> String:
	match category:
		"INSUFFICIENT_ROLL":
			return "#FF6666"  # Light red
		"DISTANCE":
			return "#FF9944"  # Orange
		"ENGAGEMENT":
			return "#FFCC00"  # Yellow
		"NON_TARGET_ER":
			return "#FF44FF"  # Magenta
		"COHERENCY":
			return "#44AAFF"  # Light blue
		"OVERLAP":
			return "#FF4444"  # Red
		"BASE_CONTACT":
			return "#44FF44"  # Green
		_:
			return "#AAAAAA"  # Grey

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
func _on_charge_unit_completed(unit_id: String) -> void:
	print("ChargeController: Charge unit completed signal received for ", unit_id)
	# Refresh the unit list so the completed unit is removed from eligible list
	_update_ui_for_next_charge()

func _on_charge_unit_skipped(unit_id: String) -> void:
	print("ChargeController: Charge unit skipped signal received for ", unit_id)
	# Refresh the unit list so the skipped unit is removed from eligible list
	_update_ui_for_next_charge()

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

	# Mark that we've processed this charge roll (prevents duplicate processing from dice_rolled signal)
	last_processed_charge_roll = {"unit_id": unit_id, "distance": distance}

	# Update dice log
	var dice_text = "[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
		unit_id, distance, dice[0], dice[1]
	]
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text(dice_text)

	# Server-side failure detection: if the phase already determined the roll was
	# insufficient, it will have cleaned up pending_charges and emitted charge_resolved.
	# In that case, skip the local success check — _on_charge_resolved handles the rest.
	if current_phase and current_phase.has_method("has_pending_charge"):
		if not current_phase.has_pending_charge(unit_id):
			print("ChargeController: Phase already determined charge failure for %s — deferring to charge_resolved" % unit_id)
			# T7-58: Update arrows with failure result
			_update_charge_arrow_roll_results(distance, false)
			_update_button_states()
			return

	# Phase says charge is still pending → roll was sufficient, enable movement
	awaiting_movement = true
	if is_instance_valid(charge_info_label):
		charge_info_label.text = "Success! Rolled %d\" - Click models to move them into engagement (max %d\" each)" % [distance, distance]
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=green]Charge successful! Move models into engagement range.[/color]\n")
	# T7-58: Update arrows with success result (roll sufficient)
	_update_charge_arrow_roll_results(distance, true)

	# Enable charge movement for this unit
	_enable_charge_movement(unit_id, distance)

	# Show charge distance tracking
	_show_charge_distance_display(distance)

	_update_button_states()

func _on_dice_rolled(dice_data: Dictionary) -> void:
	"""Handle dice_rolled signal from ChargePhase - critical for multiplayer sync.
	On clients, this is the primary handler (fires before charge_roll_made).
	The server-side charge_failed flag from the phase determines success/failure
	rather than recomputing locally, ensuring both players agree."""
	if not is_instance_valid(dice_log_display):
		return

	# T5-V1: Trigger animated dice visualization for charge rolls
	if dice_roll_visual and dice_data.get("context", "") == "charge_roll":
		var charge_rolls = dice_data.get("rolls", [])
		if charge_rolls.size() == 2:
			# Adapt charge roll format to standard dice visual format
			var visual_data = {
				"context": "charge_roll",
				"rolls_raw": charge_rolls,
				"threshold": "",  # No threshold for charge rolls
			}
			dice_roll_visual.show_dice_roll(visual_data)

	print("ChargeController: _on_dice_rolled called with data: ", dice_data)

	# Extract dice data
	var context = dice_data.get("context", "")
	var unit_id = dice_data.get("unit_id", "")
	var unit_name = dice_data.get("unit_name", unit_id)
	var rolls = dice_data.get("rolls", [])
	var total = dice_data.get("total", 0)
	var targets = dice_data.get("targets", [])
	var charge_failed = dice_data.get("charge_failed", false)
	var min_distance = dice_data.get("min_distance", 0.0)

	# Only process charge rolls
	if context != "charge_roll" or rolls.size() != 2:
		return

	# Check if this charge roll was already processed by _on_charge_roll_made
	# This prevents duplicate processing on the host (which receives both signals)
	if last_processed_charge_roll.get("unit_id", "") == unit_id and last_processed_charge_roll.get("distance", -1) == total:
		print("ChargeController: Skipping duplicate charge roll processing (already handled by charge_roll_made)")
		return

	# Update dice log display
	var dice_text = "[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
		unit_name, total, rolls[0], rolls[1]
	]
	dice_log_display.append_text(dice_text)
	print("ChargeController: Added dice roll to display: ", dice_text.strip_edges())

	charge_distance = total
	awaiting_roll = false

	# Use the server-side charge_failed flag from the phase result.
	# This avoids local recomputation and ensures host and client agree.
	if charge_failed:
		# Server determined charge roll insufficient — show failure, let charge_resolved
		# (re-emitted by NetworkManager) handle the full UI update.
		awaiting_movement = false
		var needed = max(0.0, min_distance - 1.0)

		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Failed! Rolled %d\" but needed ~%.1f\" to reach engagement range" % [total, needed]
		if is_instance_valid(dice_log_display):
			dice_log_display.append_text("[color=red][INSUFFICIENT_ROLL] Charge failed![/color] Rolled %d\" but nearest target is %.1f\" away (need ~%.1f\" to reach 1\" engagement range).\n" % [total, min_distance, needed])

		# T7-58: Update arrows with failure result
		_update_charge_arrow_roll_results(total, false)

		print("ChargeController: Server determined charge failed for %s (rolled %d, min dist %.1f\")" % [unit_id, total, min_distance])
		# charge_resolved signal will fire next and handle _reset_unit_selection + display refresh
		_update_button_states()
		return

	# Charge roll sufficient — enable movement
	# Fall back to local check if charge_failed flag was absent (backwards compat)
	var success = true
	if not dice_data.has("charge_failed"):
		print("ChargeController: No charge_failed flag in dice_data, using local success check")
		success = _is_charge_successful(unit_id, total, targets)

	if success:
		awaiting_movement = true
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Success! Rolled %d\" - Click models to move them into engagement (max %d\" each)" % [total, total]
		if is_instance_valid(dice_log_display):
			dice_log_display.append_text("[color=green]Charge successful! Move models into engagement range.[/color]\n")

		# T7-58: Update arrows with success result
		_update_charge_arrow_roll_results(total, true)

		_enable_charge_movement(unit_id, total)
		_show_charge_distance_display(total)

	_update_button_states()

func _on_charge_resolved(unit_id: String, success: bool, result: Dictionary) -> void:
	print("Charge resolved: ", unit_id, " success: ", success)

	# T7-58: Update charge arrows with the final result (they will fade on their own)
	var distance = result.get("distance", charge_distance)
	_update_charge_arrow_roll_results(distance, success)

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
		# Use structured failure data if available
		var failure_record = result.get("failure_record", {})
		var categorized = failure_record.get("categorized_errors", [])

		if categorized.size() > 0:
			# Build rich failure text with category tags
			var primary_cat = failure_record.get("primary_category", "UNKNOWN")
			var cat_color = _get_category_color(primary_cat)
			result_text = "[color=%s][%s][/color] [color=red]Charge failed:[/color] %s\n" % [cat_color, primary_cat, unit_id]

			for cat_error in categorized:
				var cat = cat_error.get("category", "")
				var detail = cat_error.get("detail", "")
				var c = _get_category_color(cat)
				result_text += "  [color=%s]•[/color] %s\n" % [c, detail]
		else:
			# Fallback to plain reason string
			var reason = result.get("reason", "Failed")
			result_text = "[color=red]Charge failed:[/color] %s - %s\n" % [unit_id, reason]

	if is_instance_valid(dice_log_display):
		dice_log_display.append_text(result_text)

	# Send COMPLETE_UNIT_CHARGE only after charge_resolved confirms the result.
	# This prevents state corruption that occurred when both APPLY_CHARGE_MOVE and
	# COMPLETE_UNIT_CHARGE were fired simultaneously without waiting for confirmation.
	if _pending_complete_unit_id != "" and _pending_complete_unit_id == unit_id:
		var complete_action = {
			"type": "COMPLETE_UNIT_CHARGE",
			"actor_unit_id": _pending_complete_unit_id
		}
		print("Requesting complete unit charge (after charge_resolved): ", complete_action)
		charge_action_requested.emit(complete_action)
		_pending_complete_unit_id = ""

	# Reset UI state
	_reset_unit_selection()
	# Refresh UI (which also refreshes failed charges display)
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

# Rotation functions for charge movement
func _check_position_would_overlap(model: Dictionary, new_pos: Vector2) -> bool:
	# Check if placing the model at the given position would overlap
	if not current_phase:
		return false

	var unit_id = active_unit_id
	var model_id = model.get("id", "")

	# Build a test model with the new position
	var test_model = model.duplicate()
	test_model["position"] = new_pos

	# Get all units and check for overlaps
	# Access the game state units directly
	var units = {}
	if current_phase and current_phase.has_method("get_game_state_snapshot"):
		var state_snapshot = current_phase.get_game_state_snapshot()
		units = state_snapshot.get("units", {})
	else:
		# Fallback to GameState if phase not available
		units = GameState.state.get("units", {})

	for check_unit_id in units:
		var check_unit = units[check_unit_id]
		var check_models = check_unit.get("models", [])

		for check_model in check_models:
			var check_model_id = check_model.get("id", "")

			# Skip self
			if check_unit_id == unit_id and check_model_id == model_id:
				continue

			# Skip dead models
			if not check_model.get("alive", true):
				continue

			# Get the current position of the other model
			# For other charging models in same unit, check their moved positions
			var other_position = _get_model_position(check_model)
			if check_unit_id == unit_id and moved_models.has(check_model_id):
				var moved_data = moved_models[check_model_id]
				if moved_data is Dictionary and moved_data.has("position"):
					other_position = moved_data["position"]
				elif moved_data is Vector2:
					other_position = moved_data

			if other_position == null:
				continue

			# Build other model dict with position
			var other_model_check = check_model.duplicate()
			other_model_check["position"] = other_position

			# Check for overlap
			if Measurement.models_overlap(test_model, other_model_check):
				return true

	# Also check wall collision
	if Measurement.model_overlaps_any_wall(test_model):
		return true

	return false

## T2-8: Calculate terrain vertical distance penalty for a straight-line path.
## Uses TerrainManager to check if the path crosses terrain >2" high.
## FLY units get diagonal measurement (shorter penalty).
func _calculate_terrain_penalty_for_path(from_pos: Vector2, to_pos: Vector2) -> float:
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if not terrain_manager:
		return 0.0

	# Check if the charging unit has FLY keyword
	var has_fly = false
	if active_unit_id != "":
		var unit = GameState.get_unit(active_unit_id)
		var keywords = unit.get("meta", {}).get("keywords", [])
		has_fly = "FLY" in keywords

	return terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, has_fly)

func _rotate_dragging_model(angle: float) -> void:
	if not dragging_model:
		return

	# Check if model has a non-circular base
	var base_type = dragging_model.get("base_type", "circular")
	if base_type == "circular":
		return  # No rotation needed for circular bases

	# Update the models rotation
	var current_rotation = dragging_model.get("rotation", 0.0)
	var new_rotation = current_rotation + angle
	dragging_model["rotation"] = new_rotation

	# Update the ghost visual if it exists - use GhostVisual's set_base_rotation method
	if ghost_visual and ghost_visual.get_child_count() > 0:
		var ghost_token = ghost_visual.get_child(0)
		if ghost_token.has_method("set_base_rotation"):
			ghost_token.set_base_rotation(new_rotation)
		elif ghost_token.has_method("set_model_data"):
			# Fallback for compatibility
			ghost_token.set_model_data(dragging_model)
			ghost_token.queue_redraw()

	# IMPORTANT: Also update the actual token visual immediately during rotation
	# This ensures the rotation is visible right away, not just when drag ends
	var model_id = dragging_model.get("id", "")
	if model_id != "" and active_unit_id != "":
		_update_token_rotation(active_unit_id, model_id, new_rotation)

	print("DEBUG: Rotated charge model by ", rad_to_deg(angle), " degrees. New rotation: ", rad_to_deg(new_rotation))

func _update_token_rotation(unit_id: String, model_id: String, new_rotation: float) -> void:
	# Find and update the actual token visual with new model data including rotation
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if not token_layer:
		print("ERROR: TokenLayer not found, cannot update token rotation")
		return

	# Find the specific token for this model
	for child in token_layer.get_children():
		if not child.has_meta("unit_id") or not child.has_meta("model_id"):
			continue

		var token_unit_id = child.get_meta("unit_id")
		var token_model_id = child.get_meta("model_id")

		if token_unit_id == unit_id and token_model_id == model_id:
			# Found the token! Update its model data
			var token_visual = child.get_child(0)  # TokenVisual is first child
			if token_visual and token_visual.has_method("set_model_data"):
				# IMPORTANT: Use dragging_model if available (it has the updated rotation)
				# Otherwise fall back to GameState (but update rotation)
				var model_data = null
				if dragging_model and dragging_model.get("id", "") == model_id:
					# Use dragging_model which has the current rotation
					model_data = dragging_model.duplicate()
				else:
					# Get from GameState but update the rotation
					var unit = GameState.get_unit(unit_id)
					for model in unit.get("models", []):
						if model.get("id", "") == model_id:
							model_data = model.duplicate()
							model_data["rotation"] = new_rotation
							break

				if model_data:
					token_visual.set_model_data(model_data)
					print("DEBUG: Updated token visual rotation for ", model_id, " to ", rad_to_deg(new_rotation), " degrees")
					return

	print("WARNING: Could not find token visual for rotation update: unit=", unit_id, " model=", model_id)

# ============================================================================
# ABILITY REROLL HANDLERS (e.g. Swift Onslaught — free charge reroll)
# ============================================================================

func _on_ability_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""Handle ability reroll opportunity — show dialog to the charging player."""
	var ability_name = roll_context.get("ability_name", "Ability")
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: ABILITY REROLL OPPORTUNITY (%s)" % ability_name)
	print("║ Unit: %s (player %d)" % [roll_context.get("unit_name", unit_id), player])
	print("║ Original rolls: %s = %d" % [str(roll_context.get("original_rolls", [])), roll_context.get("total", 0)])
	print("╚═══════════════════════════════════════════════════════════════")

	# Show the dice in the log first
	var rolls = roll_context.get("original_rolls", [])
	var total = roll_context.get("total", 0)
	var unit_name = roll_context.get("unit_name", unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
			unit_name, total, rolls[0] if rolls.size() > 0 else 0, rolls[1] if rolls.size() > 1 else 0
		])
		dice_log_display.append_text("[color=cyan]%s: Free re-roll available![/color]\n" % ability_name)

	# Skip UI dialog for AI players — AIPlayer autoload handles the decision
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.is_ai_player(player):
		print("ChargeController: Player %d is AI — skipping ability reroll dialog" % player)
		return

	# Reuse CommandRerollDialog with modified display (ability name instead of CP cost)
	var dialog_script = load("res://dialogs/CommandRerollDialog.gd")
	if not dialog_script:
		push_error("Failed to load CommandRerollDialog.gd for ability reroll")
		_on_ability_reroll_declined(unit_id, player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(
		unit_id,
		player,
		"charge_roll",
		roll_context.get("original_rolls", []),
		"%s — %s" % [ability_name, roll_context.get("context_text", "Re-roll charge dice for free")]
	)
	# Override the dialog title to show ability name instead of "Command Re-roll"
	dialog.title = "%s — Free Charge Re-roll" % ability_name
	dialog.command_reroll_used.connect(_on_ability_reroll_used)
	dialog.command_reroll_declined.connect(_on_ability_reroll_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("ChargeController: Ability reroll dialog shown for player %d (%s)" % [player, ability_name])

func _on_ability_reroll_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use ability reroll."""
	print("ChargeController: Ability reroll USED for %s" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=cyan]SWIFT ONSLAUGHT used! Re-rolling charge...[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "USE_ABILITY_REROLL",
		"actor_unit_id": unit_id,
	})

func _on_ability_reroll_declined(unit_id: String, player: int) -> void:
	"""Handle player declining ability reroll."""
	print("ChargeController: Ability reroll DECLINED for %s" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Declined free re-roll.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_ABILITY_REROLL",
		"actor_unit_id": unit_id,
	})

# ============================================================================
# COMMAND RE-ROLL HANDLERS
# ============================================================================

func _on_command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""Handle Command Re-roll opportunity — show dialog to the charging player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: COMMAND RE-ROLL OPPORTUNITY")
	print("║ Unit: %s (player %d)" % [roll_context.get("unit_name", unit_id), player])
	print("║ Roll type: %s" % roll_context.get("roll_type", "unknown"))
	print("║ Original rolls: %s = %d" % [str(roll_context.get("original_rolls", [])), roll_context.get("total", 0)])
	print("╚═══════════════════════════════════════════════════════════════")

	# Show the dice in the log first
	var rolls = roll_context.get("original_rolls", [])
	var total = roll_context.get("total", 0)
	var unit_name = roll_context.get("unit_name", unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
			unit_name, total, rolls[0] if rolls.size() > 0 else 0, rolls[1] if rolls.size() > 1 else 0
		])
		dice_log_display.append_text("[color=gold]Command Re-roll available! (1 CP)[/color]\n")

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
		roll_context.get("roll_type", "charge_roll"),
		roll_context.get("original_rolls", []),
		roll_context.get("context_text", "")
	)
	dialog.command_reroll_used.connect(_on_command_reroll_used)
	dialog.command_reroll_declined.connect(_on_command_reroll_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("ChargeController: Command Re-roll dialog shown for player %d" % player)

func _on_command_reroll_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Command Re-roll."""
	print("ChargeController: Command Re-roll USED for %s" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gold]COMMAND RE-ROLL used! Re-rolling charge...[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "USE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

func _on_command_reroll_declined(unit_id: String, player: int) -> void:
	"""Handle player declining Command Re-roll."""
	print("ChargeController: Command Re-roll DECLINED for %s" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Kept original roll.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

# ===================================================
# FIRE OVERWATCH HANDLING (during Charge Phase)
# ===================================================

func _on_overwatch_opportunity(charging_unit_id: String, defending_player: int, eligible_units: Array) -> void:
	"""Handle Fire Overwatch opportunity — show dialog to the defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: FIRE OVERWATCH OPPORTUNITY (Charge Phase)")
	print("║ Charging unit: %s (defending player %d)" % [charging_unit_id, defending_player])
	print("║ Eligible units: %d" % eligible_units.size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip UI dialog for AI players — AIPlayer autoload handles the decision
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.is_ai_player(defending_player):
		print("ChargeController: Defending player %d is AI — skipping overwatch dialog" % defending_player)
		return

	if eligible_units.is_empty():
		_on_fire_overwatch_declined(defending_player)
		return

	var dialog_script = load("res://dialogs/FireOverwatchDialog.gd")
	if not dialog_script:
		push_error("Failed to load FireOverwatchDialog.gd")
		_on_fire_overwatch_declined(defending_player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(defending_player, charging_unit_id, eligible_units)
	dialog.fire_overwatch_used.connect(_on_fire_overwatch_used)
	dialog.fire_overwatch_declined.connect(_on_fire_overwatch_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange_red]FIRE OVERWATCH available for Player %d![/color]\n" % defending_player)

func _on_fire_overwatch_used(shooter_unit_id: String, player: int) -> void:
	"""Handle player choosing to use Fire Overwatch during charge."""
	print("ChargeController: Fire Overwatch USED by %s" % shooter_unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange_red]FIRE OVERWATCH! Player %d fires with %s[/color]\n" % [player, shooter_unit_id])
	emit_signal("charge_action_requested", {
		"type": "USE_FIRE_OVERWATCH",
		"actor_unit_id": shooter_unit_id,
		"payload": {
			"shooter_unit_id": shooter_unit_id
		}
	})

func _on_fire_overwatch_declined(player: int) -> void:
	"""Handle player declining Fire Overwatch during charge."""
	print("ChargeController: Fire Overwatch DECLINED by player %d" % player)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Fire Overwatch declined.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_FIRE_OVERWATCH",
		"actor_unit_id": "",
	})

# ============================================================================
# HEROIC INTERVENTION HANDLERS
# ============================================================================

func _on_heroic_intervention_opportunity(player: int, eligible_units: Array, charging_unit_id: String) -> void:
	"""Handle Heroic Intervention opportunity — show dialog to the defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: HEROIC INTERVENTION OPPORTUNITY")
	print("║ Defending player: %d" % player)
	print("║ Charging enemy unit: %s" % charging_unit_id)
	print("║ Eligible units: %d" % eligible_units.size())
	print("╚═══════════════════════════════════════════════════════════════")

	if eligible_units.is_empty():
		_on_heroic_intervention_declined(player)
		return

	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gold]HEROIC INTERVENTION available for Player %d! (2 CP)[/color]\n" % player)

	# Load and show the dialog
	var dialog_script = load("res://dialogs/HeroicInterventionDialog.gd")
	if not dialog_script:
		push_error("Failed to load HeroicInterventionDialog.gd")
		_on_heroic_intervention_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(player, charging_unit_id, eligible_units)
	dialog.heroic_intervention_used.connect(_on_heroic_intervention_used)
	dialog.heroic_intervention_declined.connect(_on_heroic_intervention_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("ChargeController: Heroic Intervention dialog shown for player %d" % player)

func _on_heroic_intervention_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Heroic Intervention."""
	print("ChargeController: Heroic Intervention USED: player %d selects %s" % [player, unit_id])

	if is_instance_valid(dice_log_display):
		var unit_name = GameState.get_unit(unit_id).get("meta", {}).get("name", unit_id)
		dice_log_display.append_text("[color=gold]HEROIC INTERVENTION used — %s will counter-charge![/color]\n" % unit_name)

	emit_signal("charge_action_requested", {
		"type": "USE_HEROIC_INTERVENTION",
		"unit_id": unit_id,
		"player": player,
	})

func _on_heroic_intervention_declined(player: int) -> void:
	"""Handle player declining Heroic Intervention."""
	print("ChargeController: Heroic Intervention DECLINED by player %d" % player)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Heroic Intervention declined.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_HEROIC_INTERVENTION",
		"player": player,
	})

# ============================================================================
# TANK SHOCK HANDLERS
# ============================================================================

func _on_tank_shock_opportunity(player: int, vehicle_unit_id: String, eligible_targets: Array) -> void:
	"""Handle Tank Shock opportunity — show dialog to the charging player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: TANK SHOCK OPPORTUNITY")
	print("║ Player: %d" % player)
	print("║ Vehicle: %s" % vehicle_unit_id)
	print("║ Eligible targets: %d" % eligible_targets.size())
	print("╚═══════════════════════════════════════════════════════════════")

	if eligible_targets.is_empty():
		_on_tank_shock_declined(player)
		return

	if is_instance_valid(dice_log_display):
		var vehicle_unit = GameState.get_unit(vehicle_unit_id)
		var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
		var toughness = int(vehicle_unit.get("meta", {}).get("toughness", 4))
		dice_log_display.append_text("[color=orange_red]TANK SHOCK available for %s (T%d, 1 CP)![/color]\n" % [vehicle_name, toughness])

	# Load and show the dialog
	var dialog_script = load("res://dialogs/TankShockDialog.gd")
	if not dialog_script:
		push_error("Failed to load TankShockDialog.gd")
		_on_tank_shock_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(player, vehicle_unit_id, eligible_targets)
	dialog.tank_shock_used.connect(_on_tank_shock_used)
	dialog.tank_shock_declined.connect(_on_tank_shock_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("ChargeController: Tank Shock dialog shown for player %d" % player)

func _on_tank_shock_used(target_unit_id: String, player: int) -> void:
	"""Handle player choosing to use Tank Shock."""
	print("ChargeController: Tank Shock USED targeting %s" % target_unit_id)
	if is_instance_valid(dice_log_display):
		var target_unit = GameState.get_unit(target_unit_id)
		var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
		dice_log_display.append_text("[color=orange_red]TANK SHOCK! Ramming %s![/color]\n" % target_name)
	emit_signal("charge_action_requested", {
		"type": "USE_TANK_SHOCK",
		"actor_unit_id": "",
		"payload": {
			"target_unit_id": target_unit_id
		}
	})

func _on_tank_shock_declined(player: int) -> void:
	"""Handle player declining Tank Shock."""
	print("ChargeController: Tank Shock DECLINED by player %d" % player)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Tank Shock declined.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_TANK_SHOCK",
		"actor_unit_id": "",
	})

func _on_tank_shock_result(vehicle_unit_id: String, target_unit_id: String, result: Dictionary) -> void:
	"""Handle Tank Shock result — show result dialog."""
	print("ChargeController: Tank Shock result received — %d mortal wounds" % result.get("mortal_wounds", 0))

	if is_instance_valid(dice_log_display):
		var rolls = result.get("dice_rolls", [])
		var mw = result.get("mortal_wounds", 0)
		var dice_count = result.get("dice_count", 0)
		dice_log_display.append_text("[color=orange_red]Rolled %dD6: %s — %d mortal wound(s)[/color]\n" % [dice_count, str(rolls), mw])

	# Show result dialog
	var dialog_script = load("res://dialogs/TankShockResultDialog.gd")
	if not dialog_script:
		push_error("Failed to load TankShockResultDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup({
		"dice_rolls": result.get("dice_rolls", []),
		"mortal_wounds": result.get("mortal_wounds", 0),
		"casualties": result.get("casualties", 0),
		"toughness": result.get("toughness", 0),
		"dice_count": result.get("dice_count", 0),
		"vehicle_unit_id": vehicle_unit_id,
		"target_unit_id": target_unit_id,
	})
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

# --- T7-58: Charge Arrow Visual Management ---

func _create_charge_arrow_visual(from_pos: Vector2, to_pos: Vector2, animate: bool) -> ChargeArrowVisual:
	"""Create and display a charge arrow visual from charger to target."""
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		print("[ChargeController] T7-58: Cannot find BoardRoot for charge arrow")
		return null

	var visual = ChargeArrowVisual.new()
	visual.name = "ChargeArrowVisual_%d" % charge_arrow_visuals.size()
	board_root.add_child(visual)
	charge_arrow_visuals.append(visual)

	if animate:
		visual.play(from_pos, to_pos)
	else:
		visual.show_static(from_pos, to_pos)

	print("[ChargeController] T7-58: Created charge arrow %s -> %s (animate=%s)" % [str(from_pos), str(to_pos), str(animate)])
	return visual

func _clear_charge_arrow_visuals() -> void:
	"""Remove all charge arrow visuals from the scene."""
	for visual in charge_arrow_visuals:
		if is_instance_valid(visual):
			visual.clear_now()
			visual.queue_free()
	charge_arrow_visuals.clear()

func _update_charge_arrow_roll_results(roll_total: int, success: bool) -> void:
	"""Update all active charge arrow visuals with the roll result."""
	for visual in charge_arrow_visuals:
		if is_instance_valid(visual):
			visual.set_roll_result(roll_total, success)
	print("[ChargeController] T7-58: Updated %d arrow(s) with roll result: %d\" (%s)" % [charge_arrow_visuals.size(), roll_total, "success" if success else "failed"])

func show_ai_charge_arrows(charger_unit_id: String, target_unit_ids: Array) -> void:
	"""Show animated charge arrows for an AI charge declaration.
	Called from external code (e.g. AIPlayer or Main) when AI declares a charge."""
	_clear_charge_arrow_visuals()

	var charger = GameState.get_unit(charger_unit_id)
	if charger.is_empty():
		print("[ChargeController] T7-58: Cannot find charger unit %s for arrow visual" % charger_unit_id)
		return

	var from_pos = _get_unit_center_position(charger)
	if from_pos == Vector2.ZERO:
		return

	for target_id in target_unit_ids:
		var target_unit = GameState.get_unit(target_id)
		if not target_unit.is_empty():
			var to_pos = _get_unit_center_position(target_unit)
			if to_pos != Vector2.ZERO:
				_create_charge_arrow_visual(from_pos, to_pos, true)

	print("[ChargeController] T7-58: Showing %d AI charge arrow(s) for %s" % [charge_arrow_visuals.size(), charger_unit_id])
