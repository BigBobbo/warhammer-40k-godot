extends Node2D
class_name ShootingController

# ShootingController - Handles UI interactions for the Shooting Phase
# Manages unit selection, target visualization, weapon assignment UI

signal shoot_action_requested(action: Dictionary)
signal target_preview_updated(unit_id: String, target_id: String, valid: bool)
signal ui_update_requested()

# Shooting state
var current_phase = null  # Can be ShootingPhase or null
var active_shooter_id: String = ""
var eligible_targets: Dictionary = {}  # target_unit_id -> target_data
var selected_target_id: String = ""
var weapon_assignments: Dictionary = {}  # weapon_id -> target_unit_id

# UI References
var board_view: Node2D
var los_visual: Line2D
var range_visual: Node2D
var target_highlights: Node2D
var los_debug_visual: Node2D  # New LoS debug visualization
var hud_bottom: Control
var hud_right: Control

# UI Elements
var unit_selector: ItemList
var weapon_tree: Tree
var target_basket: ItemList
var confirm_button: Button
var clear_button: Button
var dice_log_display: RichTextLabel

# Visual settings
const HIGHLIGHT_COLOR_ELIGIBLE = Color.GREEN
const HIGHLIGHT_COLOR_INELIGIBLE = Color.GRAY
const HIGHLIGHT_COLOR_SELECTED = Color.YELLOW
const LOS_LINE_COLOR = Color.RED
const LOS_LINE_WIDTH = 2.0

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)  # Keep both for safety
	_setup_ui_references()
	_create_shooting_visuals()
	print("ShootingController ready")

func _exit_tree() -> void:
	# Clean up visual elements (existing)
	if los_visual and is_instance_valid(los_visual):
		los_visual.queue_free()
	if range_visual and is_instance_valid(range_visual):
		range_visual.queue_free()
	if target_highlights and is_instance_valid(target_highlights):
		target_highlights.queue_free()
	
	# Clean up UI containers
	var shooting_controls = get_node_or_null("/root/Main/HUD_Bottom/HBoxContainer/ShootingControls")
	if shooting_controls and is_instance_valid(shooting_controls):
		shooting_controls.queue_free()
	
	# ENHANCEMENT: Comprehensive right panel cleanup
	var shooting_panel = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/ShootingPanel")
	if shooting_panel and is_instance_valid(shooting_panel):
		shooting_panel.get_parent().remove_child(shooting_panel)
		shooting_panel.queue_free()
	
	var shooting_scroll = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/ShootingScrollContainer")
	if shooting_scroll and is_instance_valid(shooting_scroll):
		shooting_scroll.get_parent().remove_child(shooting_scroll)
		shooting_scroll.queue_free()
	
	# DON'T restore UnitListPanel/UnitCard visibility here - let Main.gd handle it

func _setup_ui_references() -> void:
	# Get references to UI nodes
	board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
	hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	hud_right = get_node_or_null("/root/Main/HUD_Right")
	
	# Setup shooting-specific UI elements
	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()

func _create_shooting_visuals() -> void:
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		print("ERROR: Cannot find BoardRoot for visual layers")
		return
	
	# Create LoS visualization line
	los_visual = Line2D.new()
	los_visual.name = "ShootingLoSVisual"
	los_visual.width = LOS_LINE_WIDTH
	los_visual.default_color = LOS_LINE_COLOR
	los_visual.add_point(Vector2.ZERO)
	los_visual.clear_points()
	board_root.add_child(los_visual)
	
	# Create LoS debug visualization
	los_debug_visual = preload("res://scripts/LoSDebugVisual.gd").new()
	los_debug_visual.name = "LoSDebugVisual"
	board_root.add_child(los_debug_visual)
	print("ShootingController: Added LoS debug visualization")
	
	# Create range visualization node
	range_visual = Node2D.new()
	range_visual.name = "ShootingRangeVisual"
	board_root.add_child(range_visual)
	
	# Create target highlight container
	target_highlights = Node2D.new()
	target_highlights.name = "ShootingTargetHighlights"
	board_root.add_child(target_highlights)

func _setup_bottom_hud() -> void:
	# Get the main HBox container in bottom HUD
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: Cannot find HBoxContainer in HUD_Bottom")
		return
	
	# Check for existing shooting controls container
	var controls_container = main_container.get_node_or_null("ShootingControls")
	if not controls_container:
		controls_container = HBoxContainer.new()
		controls_container.name = "ShootingControls"
		main_container.add_child(controls_container)
		
		# Add separator before shooting controls
		controls_container.add_child(VSeparator.new())
	else:
		# Clear existing children to prevent duplicates - use immediate cleanup
		print("ShootingController: Removing existing shooting controls children (", controls_container.get_children().size(), " children)")
		for child in controls_container.get_children():
			controls_container.remove_child(child)
			child.free()
	
	# Create UI elements (existing logic)
	# Phase label
	var phase_label = Label.new()
	phase_label.text = "SHOOTING PHASE"
	phase_label.add_theme_font_size_override("font_size", 18)
	controls_container.add_child(phase_label)
	
	# Separator
	controls_container.add_child(VSeparator.new())
	
	# Action buttons
	var end_phase_button = Button.new()
	end_phase_button.text = "End Shooting Phase"
	end_phase_button.pressed.connect(_on_end_phase_pressed)
	controls_container.add_child(end_phase_button)

func _setup_right_panel() -> void:
	# Main.gd already handles cleanup before controller creation
	# Check for existing VBoxContainer in HUD_Right
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)
	
	# Check for existing shooting panel
	var scroll_container = container.get_node_or_null("ShootingScrollContainer")
	var shooting_panel = null
	
	if not scroll_container:
		# Create scroll container for better layout
		scroll_container = ScrollContainer.new()
		scroll_container.name = "ShootingScrollContainer"
		scroll_container.custom_minimum_size = Vector2(250, 400)  # Increased from 300 to 400
		scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Take available space
		container.add_child(scroll_container)
		
		shooting_panel = VBoxContainer.new()
		shooting_panel.name = "ShootingPanel"
		shooting_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_container.add_child(shooting_panel)
	else:
		# Get existing shooting panel
		shooting_panel = scroll_container.get_node_or_null("ShootingPanel")
		if shooting_panel:
			# Clear existing children to rebuild fresh - use immediate cleanup
			print("ShootingController: Removing existing shooting panel children (", shooting_panel.get_children().size(), " children)")
			for child in shooting_panel.get_children():
				shooting_panel.remove_child(child)
				child.free()
	
	# Create UI elements (existing logic)
	print("ShootingController: Creating shooting UI elements")
	# Title
	var title = Label.new()
	title.text = "Shooting Controls"
	title.add_theme_font_size_override("font_size", 16)
	shooting_panel.add_child(title)
	print("ShootingController: Added title to shooting panel")
	
	shooting_panel.add_child(HSeparator.new())
	
	# Unit selector
	var unit_label = Label.new()
	unit_label.text = "Select Shooter:"
	shooting_panel.add_child(unit_label)
	
	unit_selector = ItemList.new()
	unit_selector.custom_minimum_size = Vector2(230, 80)
	unit_selector.item_selected.connect(_on_unit_selected)
	shooting_panel.add_child(unit_selector)
	
	shooting_panel.add_child(HSeparator.new())
	
	# Weapon assignments tree
	var weapon_label = Label.new()
	weapon_label.text = "Weapon Assignments:"
	shooting_panel.add_child(weapon_label)
	
	weapon_tree = Tree.new()
	weapon_tree.custom_minimum_size = Vector2(230, 120)
	weapon_tree.columns = 2
	weapon_tree.set_column_title(0, "Weapon")
	weapon_tree.set_column_title(1, "Target")
	weapon_tree.hide_root = true
	weapon_tree.item_selected.connect(_on_weapon_tree_item_selected)
	weapon_tree.button_clicked.connect(_on_weapon_tree_button_clicked)
	shooting_panel.add_child(weapon_tree)
	
	# Target basket
	var basket_label = Label.new()
	basket_label.text = "Current Targets:"
	shooting_panel.add_child(basket_label)
	
	target_basket = ItemList.new()
	target_basket.custom_minimum_size = Vector2(230, 80)
	shooting_panel.add_child(target_basket)
	
	# Action buttons
	var button_container = HBoxContainer.new()
	
	clear_button = Button.new()
	clear_button.text = "Clear All"
	clear_button.pressed.connect(_on_clear_pressed)
	button_container.add_child(clear_button)
	
	confirm_button = Button.new()
	confirm_button.text = "Confirm Targets"
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)
	
	shooting_panel.add_child(button_container)
	
	# Dice log
	shooting_panel.add_child(HSeparator.new())
	
	var dice_label = Label.new()
	dice_label.text = "Dice Log:"
	shooting_panel.add_child(dice_label)
	
	dice_log_display = RichTextLabel.new()
	dice_log_display.custom_minimum_size = Vector2(230, 100)
	dice_log_display.bbcode_enabled = true
	dice_log_display.scroll_following = true
	shooting_panel.add_child(dice_log_display)
	
	print("ShootingController: Finished creating shooting UI - panel should be visible!")

func set_phase(phase: BasePhase) -> void:
	current_phase = phase
	
	if phase and phase is ShootingPhase:
		# Connect to phase signals
		if not phase.unit_selected_for_shooting.is_connected(_on_unit_selected_for_shooting):
			phase.unit_selected_for_shooting.connect(_on_unit_selected_for_shooting)
		if not phase.targets_available.is_connected(_on_targets_available):
			phase.targets_available.connect(_on_targets_available)
		if not phase.shooting_resolved.is_connected(_on_shooting_resolved):
			phase.shooting_resolved.connect(_on_shooting_resolved)
		if not phase.dice_rolled.is_connected(_on_dice_rolled):
			phase.dice_rolled.connect(_on_dice_rolled)
		
		# Ensure UI is set up after phase assignment (especially after loading)
		_setup_ui_references()
		
		# Hide UnitListPanel and UnitCard when shooting phase starts
		var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
		if container:
			var unit_list_panel = container.get_node_or_null("UnitListPanel")
			if unit_list_panel:
				print("ShootingController: Hiding UnitListPanel on phase start")
				unit_list_panel.visible = false
			
			var unit_card = container.get_node_or_null("UnitCard")
			if unit_card:
				print("ShootingController: Hiding UnitCard on phase start")
				unit_card.visible = false
		
		_refresh_unit_list()
		
		# NEW: Restore state if loading from save
		_restore_state_after_load()
		
		show()
	else:
		_clear_visuals()
		hide()

func _restore_state_after_load() -> void:
	"""Restore ShootingController UI state after loading from save"""
	if not current_phase or not current_phase is ShootingPhase:
		return
	
	var shooting_state = current_phase.get_current_shooting_state()
	
	# Restore active shooter if there was one
	if shooting_state.active_shooter_id != "":
		active_shooter_id = shooting_state.active_shooter_id
		
		# Query targets for the active shooter
		eligible_targets = RulesEngine.get_eligible_targets(active_shooter_id, current_phase.game_state_snapshot)
		
		# Restore UI elements
		_refresh_weapon_tree()
		_show_range_indicators()
		
		# Update assignment display from phase state
		weapon_assignments.clear()
		for assignment in shooting_state.pending_assignments:
			weapon_assignments[assignment.weapon_id] = assignment.target_unit_id
		
		for assignment in shooting_state.confirmed_assignments:
			weapon_assignments[assignment.weapon_id] = assignment.target_unit_id
		
		_update_ui_state()
		
		# Show feedback in dice log
		if dice_log_display:
			dice_log_display.append_text("[color=blue]Restored shooting state for %s[/color]\n" % 
				current_phase.get_unit(active_shooter_id).get("meta", {}).get("name", active_shooter_id))
	
	# Update unit list to reflect units that have already shot
	_refresh_unit_list()

func _refresh_unit_list() -> void:
	if not unit_selector:
		return
	
	unit_selector.clear()
	
	if not current_phase:
		return
	
	var units = current_phase.get_units_for_player(current_phase.get_current_player())
	var units_shot = current_phase.get_units_that_shot() if current_phase.has_method("get_units_that_shot") else []
	
	for unit_id in units:
		var unit = units[unit_id]
		if current_phase._can_unit_shoot(unit) or unit_id in units_shot:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			
			# Show status for units that have shot
			if unit_id in units_shot:
				unit_name += " [SHOT]"
			elif unit_id == active_shooter_id:
				unit_name += " [ACTIVE]"
			
			unit_selector.add_item(unit_name)
			unit_selector.set_item_metadata(unit_selector.get_item_count() - 1, unit_id)
	
	# Auto-select first unit for debugging if we have units
	if unit_selector.get_item_count() > 0 and active_shooter_id == "":
		unit_selector.select(0)
		_on_unit_selected(0)

func _refresh_weapon_tree() -> void:
	if not weapon_tree or active_shooter_id == "":
		return
	
	weapon_tree.clear()
	var root = weapon_tree.create_item()
	
	# Get unit weapons from RulesEngine
	var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
	var weapon_counts = {}
	
	# Count weapons by type
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if not weapon_counts.has(weapon_id):
				weapon_counts[weapon_id] = 0
			weapon_counts[weapon_id] += 1
	
	# Create tree items for each weapon type
	for weapon_id in weapon_counts:
		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		var weapon_item = weapon_tree.create_item(root)
		weapon_item.set_text(0, "%s (x%d)" % [weapon_profile.get("name", weapon_id), weapon_counts[weapon_id]])
		weapon_item.set_metadata(0, weapon_id)
		
		# Add target selector in second column
		if eligible_targets.size() > 0:
			weapon_item.set_text(1, "[Click to Select]")
			weapon_item.set_selectable(0, true)  # Make the weapon selectable
			weapon_item.set_selectable(1, false) # Don't make column 1 selectable
			
			# Add a button to auto-assign the first available target
			weapon_item.add_button(1, preload("res://icon.svg"), 0, false, "Auto-assign first target")

func _highlight_targets() -> void:
	_clear_target_highlights()
	
	if not board_view or eligible_targets.is_empty():
		return
	
	# Clear previous LoS lines
	if los_debug_visual:
		los_debug_visual.clear_los_lines()
	
	# Highlight each eligible target
	for target_id in eligible_targets:
		var target_data = eligible_targets[target_id]
		var is_in_range = target_data.get("in_range", true)
		var color = HIGHLIGHT_COLOR_ELIGIBLE if is_in_range else HIGHLIGHT_COLOR_INELIGIBLE
		_create_target_highlight(target_id, color)
		
		# Visualize LoS to this target if debug is enabled
		if los_debug_visual and los_debug_visual.debug_enabled and active_shooter_id != "":
			_visualize_los_to_target(active_shooter_id, target_id)

func _create_target_highlight(unit_id: String, color: Color) -> void:
	if not target_highlights or not current_phase:
		return
	
	var unit = current_phase.get_unit(unit_id)
	if unit.is_empty():
		return
	
	# Create highlight for each model in the unit
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var pos = _get_model_position(model)
		if pos == Vector2.ZERO:
			continue
		
		# Create a circle highlight indicator
		var highlight = Node2D.new()
		highlight.position = pos
		highlight.set_script(GDScript.new())
		highlight.set_meta("highlight_color", color)
		highlight.set_meta("base_radius", 30.0)
		
		# Add custom draw script for the highlight
		var script_source = """
extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var color = get_meta("highlight_color", Color.GREEN)
	var radius = get_meta("base_radius", 30.0)
	
	# Draw outer ring
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 3.0, true)
	
	# Draw inner filled circle with transparency
	var fill_color = color
	fill_color.a = 0.3
	draw_circle(Vector2.ZERO, radius - 2, fill_color)
	
	# Draw pulsing effect
	if color == Color.GREEN:  # In range - add extra emphasis
		draw_arc(Vector2.ZERO, radius + 5, 0, TAU, 32, color, 1.0, true)
"""
		highlight.set_script(GDScript.new())
		highlight.get_script().source_code = script_source
		highlight.get_script().reload()
		
		target_highlights.add_child(highlight)

func _clear_target_highlights() -> void:
	if target_highlights:
		for child in target_highlights.get_children():
			child.queue_free()


func _draw_los_line(from_unit_id: String, to_unit_id: String) -> void:
	if not los_visual or not current_phase:
		return
	
	los_visual.clear_points()
	
	var from_unit = current_phase.get_unit(from_unit_id)
	var to_unit = current_phase.get_unit(to_unit_id)
	
	if from_unit.is_empty() or to_unit.is_empty():
		return
	
	# Find closest models between units
	var min_distance = INF
	var from_pos = Vector2.ZERO
	var to_pos = Vector2.ZERO
	
	for from_model in from_unit.get("models", []):
		if not from_model.get("alive", true):
			continue
		var f_pos = _get_model_position(from_model)
		
		for to_model in to_unit.get("models", []):
			if not to_model.get("alive", true):
				continue
			var t_pos = _get_model_position(to_model)
			
			var dist = f_pos.distance_to(t_pos)
			if dist < min_distance:
				min_distance = dist
				from_pos = f_pos
				to_pos = t_pos
	
	if from_pos != Vector2.ZERO and to_pos != Vector2.ZERO:
		los_visual.add_point(from_pos)
		los_visual.add_point(to_pos)
		
		# Add range indicator
		var range_inches = Measurement.px_to_inches(min_distance)
		var mid_point = (from_pos + to_pos) / 2
		_show_range_label(mid_point, "%.1f\"" % range_inches)

func _show_range_label(position: Vector2, text: String) -> void:
	if not range_visual:
		return
	
	# Clear previous labels
	for child in range_visual.get_children():
		child.queue_free()
	
	# Create new label
	var label = Label.new()
	label.text = text
	label.position = position
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	range_visual.add_child(label)

func _clear_visuals() -> void:
	if los_visual:
		los_visual.clear_points()
	if range_visual:
		for child in range_visual.get_children():
			child.queue_free()
	_clear_target_highlights()
	_clear_range_indicators()

func _show_range_indicators() -> void:
	_clear_range_indicators()
	
	if active_shooter_id == "" or not current_phase:
		return
	
	var shooter_unit = current_phase.get_unit(active_shooter_id)
	if shooter_unit.is_empty():
		return
	
	# Get all unique weapon ranges for this unit
	var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
	var weapon_ranges = {}
	
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
			var range_inches = weapon_profile.get("range", 0)
			if range_inches > 0:
				weapon_ranges[weapon_id] = range_inches
	
	# Draw range circles from each model
	for model in shooter_unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.ZERO:
			continue
		
		# Draw range circles for each weapon type
		for weapon_id in weapon_ranges:
			var range_inches = weapon_ranges[weapon_id]
			var range_px = Measurement.inches_to_px(range_inches)
			
			# Create a circle to show weapon range
			var circle = preload("res://scripts/RangeCircle.gd").new()
			circle.position = model_pos
			circle.setup(range_px, weapon_id)
			range_visual.add_child(circle)
	
	# Highlight enemies within range with different colors
	_highlight_enemies_by_range(shooter_unit, weapon_ranges)

func _highlight_enemies_by_range(shooter_unit: Dictionary, weapon_ranges: Dictionary) -> void:
	if not current_phase:
		return
	
	var current_player = current_phase.get_current_player()
	var enemy_player = 1 if current_player == 0 else 0
	var enemy_units = current_phase.get_units_for_player(enemy_player)
	
	# Clear existing highlights
	_clear_target_highlights()
	
	# Check each enemy unit
	for enemy_id in enemy_units:
		var enemy_unit = enemy_units[enemy_id]
		if enemy_unit.get("models", []).is_empty():
			continue
		
		# Check if any model in the shooter unit can reach any model in the enemy unit
		var is_in_range = false
		var min_distance = INF
		
		for shooter_model in shooter_unit.get("models", []):
			if not shooter_model.get("alive", true):
				continue
			var shooter_pos = _get_model_position(shooter_model)
			
			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				var enemy_pos = _get_model_position(enemy_model)
				
				var distance = shooter_pos.distance_to(enemy_pos)
				min_distance = min(min_distance, distance)
				
				# Check if within any weapon range
				for weapon_id in weapon_ranges:
					var range_px = Measurement.inches_to_px(weapon_ranges[weapon_id])
					if distance <= range_px:
						is_in_range = true
						break
			
			if is_in_range:
				break
		
		# Highlight the unit based on range status
		if is_in_range:
			_create_target_highlight(enemy_id, HIGHLIGHT_COLOR_ELIGIBLE)
			# Debug: Visualize LoS to this target
			if los_debug_visual and los_debug_visual.debug_enabled:
				_visualize_los_to_target(active_shooter_id, enemy_id)
		else:
			_create_target_highlight(enemy_id, Color(0.5, 0.5, 0.5, 0.3))  # Gray for out of range

func _clear_range_indicators() -> void:
	if range_visual:
		for child in range_visual.get_children():
			child.queue_free()

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _visualize_los_to_target(shooter_id: String, target_id: String) -> void:
	if not los_debug_visual or not current_phase:
		return
	
	var shooter_unit = GameState.get_unit(shooter_id)
	var target_unit = GameState.get_unit(target_id)
	
	if shooter_unit.is_empty() or target_unit.is_empty():
		return
	
	var board = GameState.create_snapshot()
	
	# Use enhanced LoS visualization for each model pair
	for shooter_model in shooter_unit.get("models", []):
		if not shooter_model.get("alive", true):
			continue
			
		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue
			
			# Enhanced LoS visualization shows base-aware sight lines
			los_debug_visual.visualize_enhanced_los(shooter_model, target_model, board)
	
	print("[ShootingController] Enhanced LoS visualization: %s → %s" % [shooter_id, target_id])

func _get_closest_model_position(from_unit: Dictionary, to_unit: Dictionary) -> Vector2:
	# Find the model in from_unit closest to any model in to_unit
	var min_distance = INF
	var best_pos = Vector2.ZERO
	
	for from_model in from_unit.get("models", []):
		if not from_model.get("alive", true):
			continue
		var f_pos = _get_model_position(from_model)
		if f_pos == Vector2.ZERO:
			continue
		
		for to_model in to_unit.get("models", []):
			if not to_model.get("alive", true):
				continue
			var t_pos = _get_model_position(to_model)
			if t_pos == Vector2.ZERO:
				continue
			
			var dist = f_pos.distance_to(t_pos)
			if dist < min_distance:
				min_distance = dist
				best_pos = f_pos
	
	return best_pos

func _cleanup_existing_ui() -> void:
	# Remove existing shooting controls if present
	if hud_bottom:
		var existing_controls = hud_bottom.get_node_or_null("ShootingControls")
		if existing_controls:
			existing_controls.queue_free()
	
	# ENHANCEMENT: Proactively clear any movement phase residuals
	if hud_right:
		var container = hud_right.get_node_or_null("VBoxContainer")
		if container:
			# Clear any remaining movement sections
			for section_name in ["Section1_UnitList", "Section2_UnitDetails", 
								"Section3_ModeSelection", "Section4_Actions"]:
				var section = container.get_node_or_null(section_name)
				if section:
					print("ShootingController: Cleaning up residual movement section: ", section_name)
					container.remove_child(section)
					section.queue_free()
			
			# Hide UnitListPanel if present
			var unit_list_panel = container.get_node_or_null("UnitListPanel")
			if unit_list_panel:
				print("ShootingController: Hiding UnitListPanel")
				unit_list_panel.visible = false
			
			# Hide UnitCard if present
			var unit_card = container.get_node_or_null("UnitCard")
			if unit_card:
				print("ShootingController: Hiding UnitCard")
				unit_card.visible = false
			
			# Clear any other non-shooting UI elements
			var existing_panel = container.get_node_or_null("ShootingPanel")
			if existing_panel:
				existing_panel.queue_free()

# Signal handlers

func _on_unit_selected_for_shooting(unit_id: String) -> void:
	print("ShootingController: Unit selected for shooting: ", unit_id)
	active_shooter_id = unit_id
	weapon_assignments.clear()
	
	# Clear previous visualizations
	if los_debug_visual:
		los_debug_visual.clear_los_lines()
	
	# Request targets and trigger LoS visualization
	eligible_targets = RulesEngine.get_eligible_targets(unit_id, GameState.create_snapshot())
	_highlight_targets()
	_refresh_weapon_tree()
	_update_ui_state()
	_show_range_indicators()
	
	# Visualize LoS to all eligible targets
	if los_debug_visual and los_debug_visual.debug_enabled:
		print("ShootingController: Visualizing LoS to ", eligible_targets.size(), " targets")
		for target_id in eligible_targets:
			_visualize_los_to_target(unit_id, target_id)

func _on_targets_available(unit_id: String, targets: Dictionary) -> void:
	print("ShootingController: Targets available for ", unit_id, ": ", targets.size())
	active_shooter_id = unit_id
	eligible_targets = targets
	# Don't call _highlight_targets here since _show_range_indicators handles it
	_refresh_weapon_tree()
	# Show range indicators which will also highlight enemies
	_show_range_indicators()
	
	# Trigger LoS visualization for each eligible target
	if los_debug_visual and los_debug_visual.debug_enabled:
		print("ShootingController: Visualizing LoS to ", targets.size(), " targets")
		for target_id in targets:
			_visualize_los_to_target(unit_id, target_id)

func _on_shooting_resolved(shooter_id: String, target_id: String, result: Dictionary) -> void:
	print("ShootingController: Shooting resolved for ", shooter_id, " -> ", target_id)
	# Update visuals after shooting
	_clear_visuals()
	active_shooter_id = ""
	eligible_targets.clear()
	weapon_assignments.clear()
	_refresh_weapon_tree()
	# Clear LoS visualization after shooting
	if los_debug_visual:
		los_debug_visual.clear_los_lines()

func _on_dice_rolled(dice_data: Dictionary) -> void:
	if not dice_log_display:
		return
	
	# Get data from the dice roll
	var context = dice_data.get("context", "Roll")
	var rolls = dice_data.get("rolls", dice_data.get("rolls_raw", []))
	var successes = dice_data.get("successes", -1)
	
	# Format the display text
	var log_text = "[b]%s:[/b] %s" % [context.capitalize(), str(rolls)]
	if successes >= 0:
		log_text += " → %d successes" % successes
	log_text += "\n"
	
	dice_log_display.append_text(log_text)

func _on_unit_selected(index: int) -> void:
	if not unit_selector or not current_phase:
		return
	
	var unit_id = unit_selector.get_item_metadata(index)
	if unit_id:
		# Clear previous LoS visualizations
		if los_debug_visual:
			los_debug_visual.clear_los_lines()
		
		emit_signal("shoot_action_requested", {
			"type": "SELECT_SHOOTER",
			"actor_unit_id": unit_id
		})
		
		# Manually trigger visualization
		_on_unit_selected_for_shooting(unit_id)

func _on_weapon_tree_item_selected() -> void:
	if not weapon_tree:
		return
		
	var selected = weapon_tree.get_selected()
	if not selected:
		return
		
	var weapon_id = selected.get_metadata(0)
	if weapon_id:
		# Visual feedback - highlight the selected weapon
		selected.set_custom_bg_color(0, Color(0.2, 0.4, 0.2, 0.5))
		
		# Update instruction text in column 1
		selected.set_text(1, "[Click enemy to assign]")
		
		# Show a message to the user
		if dice_log_display:
			dice_log_display.append_text("[color=yellow]Selected %s - Click on an enemy unit or use the button to assign target[/color]\n" % 
				RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id))

func _on_weapon_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if not item or column != 1:
		return
		
	var weapon_id = item.get_metadata(0)
	if not weapon_id or eligible_targets.is_empty():
		return
		
	# Auto-assign first available target
	var first_target = eligible_targets.keys()[0]
	print("DEBUG: Button clicked - auto-assigning target: ", first_target)
	_select_target_for_current_weapon(first_target)

func _on_clear_pressed() -> void:
	emit_signal("shoot_action_requested", {
		"type": "CLEAR_ALL_ASSIGNMENTS"
	})
	weapon_assignments.clear()
	_update_ui_state()

func _on_confirm_pressed() -> void:
	# Show visual feedback that shooting is resolving
	if dice_log_display:
		dice_log_display.append_text("[color=yellow]Rolling dice...[/color]\n")
	
	emit_signal("shoot_action_requested", {
		"type": "CONFIRM_TARGETS"
	})
	
	# The phase will now auto-resolve after confirmation

func _on_end_phase_pressed() -> void:
	emit_signal("shoot_action_requested", {
		"type": "END_SHOOTING"
	})

func _update_ui_state() -> void:
	if confirm_button:
		confirm_button.disabled = weapon_assignments.is_empty()
	if clear_button:
		clear_button.disabled = weapon_assignments.is_empty()
	
	# Update target basket
	if target_basket:
		target_basket.clear()
		for weapon_id in weapon_assignments:
			var target_id = weapon_assignments[weapon_id]
			var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
			var target_name = eligible_targets.get(target_id, {}).get("unit_name", target_id)
			target_basket.add_item("%s → %s" % [weapon_profile.get("name", weapon_id), target_name])

func _input(event: InputEvent) -> void:
	if not current_phase or not current_phase is ShootingPhase:
		return
	
	# Only handle input if we have an active shooter and eligible targets
	if active_shooter_id == "" or eligible_targets.is_empty():
		return
	
	# Handle clicking on units for target selection
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Get the board root which contains the units
		var board_root = get_node_or_null("/root/Main/BoardRoot")
		if board_root:
			# Convert screen position to board local position
			var mouse_pos = board_root.get_local_mouse_position()
			print("DEBUG: Mouse click at board position: ", mouse_pos)
			_handle_board_click(mouse_pos)
		else:
			print("DEBUG: BoardRoot not found, using global position")
			var mouse_pos = get_global_mouse_position()
			_handle_board_click(mouse_pos)
	
	# Handle hovering for LoS preview
	elif event is InputEventMouseMotion:
		# Get the board root which contains the units
		var board_root = get_node_or_null("/root/Main/BoardRoot")
		if board_root:
			var mouse_pos = board_root.get_local_mouse_position()
			_handle_board_hover(mouse_pos)
		else:
			var mouse_pos = get_global_mouse_position()
			_handle_board_hover(mouse_pos)

func _handle_board_click(position: Vector2) -> void:
	# First check if we have a weapon selected
	if not weapon_tree:
		print("DEBUG: No weapon tree")
		return
		
	var selected_weapon = weapon_tree.get_selected()
	if not selected_weapon:
		if dice_log_display:
			dice_log_display.append_text("[color=red]Please select a weapon first![/color]\n")
		print("DEBUG: No weapon selected")
		return
	
	# Check if click is on an eligible target
	var closest_target = ""
	var closest_distance = INF
	var closest_model_pos = Vector2.ZERO
	
	print("DEBUG: Checking click at position: ", position)
	print("DEBUG: Available targets: ", eligible_targets.keys())
	
	for target_id in eligible_targets:
		var unit = current_phase.get_unit(target_id)
		print("DEBUG: Checking unit ", target_id, " with ", unit.get("models", []).size(), " models")
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = _get_model_position(model)
			print("DEBUG: Model at ", model_pos)
			var distance = model_pos.distance_to(position)
			if distance < closest_distance:
				closest_distance = distance
				closest_target = target_id
				closest_model_pos = model_pos
	
	# Use a larger click threshold to make selection easier
	if closest_target != "" and closest_distance < 500:  # Very large threshold for testing
		print("DEBUG: Selecting target: ", closest_target, " at distance: ", closest_distance)
		_select_target_for_current_weapon(closest_target)
	else:
		print("DEBUG: No target close enough. Closest was: ", closest_target, " at distance: ", closest_distance, " at position: ", closest_model_pos)
		
		# If no target is close enough, let's try a different approach - just select the first available target
		if not eligible_targets.is_empty():
			var first_target = eligible_targets.keys()[0]
			print("DEBUG: Auto-selecting first available target: ", first_target)
			_select_target_for_current_weapon(first_target)

func _handle_board_hover(position: Vector2) -> void:
	# Show LoS line to hovered target
	for target_id in eligible_targets:
		var unit = current_phase.get_unit(target_id)
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = _get_model_position(model)
			if model_pos.distance_to(position) < 50:  # Hover threshold
				_draw_los_line(active_shooter_id, target_id)
				return
	
	# Clear LoS if not hovering a target
	if los_visual:
		los_visual.clear_points()

func _select_target_for_current_weapon(target_id: String) -> void:
	# Get currently selected weapon from tree
	if not weapon_tree:
		return
	
	var selected = weapon_tree.get_selected()
	if not selected:
		return
	
	var weapon_id = selected.get_metadata(0)
	if not weapon_id:
		return
	
	# Assign target
	weapon_assignments[weapon_id] = target_id
	
	# Get model IDs for this weapon
	var model_ids = []
	var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
	for model_id in unit_weapons:
		if weapon_id in unit_weapons[model_id]:
			model_ids.append(model_id)
	
	emit_signal("shoot_action_requested", {
		"type": "ASSIGN_TARGET",
		"payload": {
			"weapon_id": weapon_id,
			"target_unit_id": target_id,
			"model_ids": model_ids
		}
	})
	
	# Update UI
	var target_name = eligible_targets.get(target_id, {}).get("unit_name", target_id)
	selected.set_text(1, target_name)
	selected.set_custom_bg_color(1, Color(0.4, 0.2, 0.2, 0.5))  # Red background for assigned target
	
	# Show feedback
	if dice_log_display:
		var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		dice_log_display.append_text("[color=green]✓ Assigned %s to target %s[/color]\n" % [weapon_name, target_name])
	
	_update_ui_state()
