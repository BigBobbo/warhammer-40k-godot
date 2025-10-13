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
var weapon_modifiers: Dictionary = {}  # weapon_id -> {hit: {reroll_ones: bool, plus_one: bool, minus_one: bool}}
var selected_weapon_id: String = ""  # Currently selected weapon for modifier display
var save_dialog_showing: bool = false  # Prevent multiple dialogs

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

# Modifier UI elements (Phase 1 MVP)
var modifier_panel: VBoxContainer
var modifier_label: Label
var reroll_ones_checkbox: CheckBox
var plus_one_checkbox: CheckBox
var minus_one_checkbox: CheckBox

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

	# Clean up LoS debug visualization
	if los_debug_visual and is_instance_valid(los_debug_visual):
		los_debug_visual.clear_all_debug_visuals()
		los_debug_visual.queue_free()

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
	# NOTE: Main.gd now handles the phase action button
	# ShootingController only manages shooting-specific UI in the right panel
	pass

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

	shooting_panel.add_child(HSeparator.new())

	# Modifier panel (Phase 1 MVP)
	modifier_label = Label.new()
	modifier_label.text = "Hit Modifiers:"
	shooting_panel.add_child(modifier_label)

	modifier_panel = VBoxContainer.new()
	modifier_panel.name = "ModifierPanel"

	reroll_ones_checkbox = CheckBox.new()
	reroll_ones_checkbox.text = "Re-roll 1s to Hit"
	reroll_ones_checkbox.toggled.connect(_on_reroll_ones_toggled)
	modifier_panel.add_child(reroll_ones_checkbox)

	plus_one_checkbox = CheckBox.new()
	plus_one_checkbox.text = "+1 To Hit"
	plus_one_checkbox.toggled.connect(_on_plus_one_toggled)
	modifier_panel.add_child(plus_one_checkbox)

	minus_one_checkbox = CheckBox.new()
	minus_one_checkbox.text = "-1 To Hit"
	minus_one_checkbox.toggled.connect(_on_minus_one_toggled)
	modifier_panel.add_child(minus_one_checkbox)

	shooting_panel.add_child(modifier_panel)

	# Initially hide modifiers until a weapon is selected
	modifier_panel.visible = false
	modifier_label.visible = false

	shooting_panel.add_child(HSeparator.new())

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
		if not phase.saves_required.is_connected(_on_saves_required):
			phase.saves_required.connect(_on_saves_required)
			print("ShootingController: Connected to saves_required signal")
		if not phase.weapon_order_required.is_connected(_on_weapon_order_required):
			phase.weapon_order_required.connect(_on_weapon_order_required)
			print("ShootingController: Connected to weapon_order_required signal")
		if not phase.next_weapon_confirmation_required.is_connected(_on_next_weapon_confirmation_required):
			phase.next_weapon_confirmation_required.connect(_on_next_weapon_confirmation_required)
			print("ShootingController: Connected to next_weapon_confirmation_required signal")

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
	# BUT only if it's the local player's turn in multiplayer
	if unit_selector.get_item_count() > 0 and active_shooter_id == "":
		var should_auto_select = false

		if NetworkManager.is_networked():
			# In multiplayer: Only auto-select if it's our turn
			var local_peer_id = multiplayer.get_unique_id()
			var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
			var active_player = current_phase.get_current_player() if current_phase else -1
			should_auto_select = (local_player == active_player)
		else:
			# In single-player: Always auto-select
			should_auto_select = true

		if should_auto_select:
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
			# AUTO-TARGET: If only one eligible target, auto-assign it (Phase 1 MVP)
			if eligible_targets.size() == 1:
				var only_target_id = eligible_targets.keys()[0]
				var only_target_name = eligible_targets[only_target_id].unit_name
				weapon_item.set_text(1, only_target_name + " [AUTO]")
				weapon_item.set_custom_bg_color(1, Color(0.2, 0.6, 0.2, 0.3))  # Green tint

				# Show feedback in dice log
				if dice_log_display:
					dice_log_display.append_text("[color=cyan]Auto-selected %s for %s (only eligible target)[/color]\n" %
						[only_target_name, weapon_profile.get("name", weapon_id)])

				# Auto-assign this target
				_auto_assign_target(weapon_id, only_target_id)
			else:
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
	"""Clear all shooting visual elements from the board"""
	print("ShootingController: Clearing all visuals")

	# Clear LoS line
	if los_visual and is_instance_valid(los_visual):
		los_visual.clear_points()

	# Clear range indicators (this clears children of range_visual)
	_clear_range_indicators()

	# Clear target highlights
	_clear_target_highlights()

	# Clear LoS debug visuals if present
	if los_debug_visual and is_instance_valid(los_debug_visual):
		if los_debug_visual.has_method("clear_all_debug_visuals"):
			los_debug_visual.clear_all_debug_visuals()

	print("ShootingController: All visuals cleared")

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

# Public API for refreshing LoS debug visuals
# Called when LoS debug is toggled ON while a shooter is already active
func refresh_los_debug_visuals() -> void:
	print("[ShootingController] refresh_los_debug_visuals called")
	print("  los_debug_visual exists: ", los_debug_visual != null)
	if los_debug_visual:
		print("  los_debug_visual.debug_enabled: ", los_debug_visual.debug_enabled)
	print("  active_shooter_id: ", active_shooter_id)
	print("  eligible_targets count: ", eligible_targets.size())

	if not los_debug_visual:
		print("[ShootingController] ERROR: los_debug_visual is null!")
		return

	if not los_debug_visual.debug_enabled:
		print("[ShootingController] ERROR: debug_enabled is false!")
		return

	if active_shooter_id == "":
		print("[ShootingController] No active shooter")
		return

	# Clear existing visuals first
	los_debug_visual.clear_all_debug_visuals()

	# If no eligible targets, visualize LoS to ALL enemy units to show why they're not eligible
	if eligible_targets.is_empty():
		print("[ShootingController] No eligible targets - visualizing LoS to ALL enemy units for debugging")
		if current_phase:
			var current_player = current_phase.get_current_player()
			var enemy_player = 1 if current_player == 0 else 0

			print("[ShootingController] Current player: %d, Enemy player: %d" % [current_player, enemy_player])

			# Get ALL units from GameState to debug
			var all_units = GameState.get_units()
			print("[ShootingController] Total units in GameState: %d" % all_units.size())
			for unit_id in all_units:
				var unit = all_units[unit_id]
				var owner = unit.get("owner", -1)
				var name = unit.get("meta", {}).get("name", "Unknown")
				var status = unit.get("status", -1)
				print("  Unit %s: owner=%d, name=%s, status=%d" % [unit_id, owner, name, status])

			var enemy_units = current_phase.get_units_for_player(enemy_player)
			print("[ShootingController] Enemy units from phase: %d" % enemy_units.size())

			if enemy_units.is_empty():
				print("[ShootingController] Phase query returned empty - trying direct GameState query")
				# Try getting enemy units directly from GameState
				var enemy_units_direct = {}
				for unit_id in all_units:
					var unit = all_units[unit_id]
					if unit.get("owner", -1) == enemy_player:
						enemy_units_direct[unit_id] = unit

				print("[ShootingController] Direct GameState query found %d enemy units" % enemy_units_direct.size())

				if enemy_units_direct.is_empty():
					print("[ShootingController] WARNING: No enemy units found anywhere!")
					var main = get_node_or_null("/root/Main")
					if main and main.has_method("_show_toast"):
						main._show_toast("LoS Debug: No enemy units found", 3.0)
					return

				# Use direct query results
				enemy_units = enemy_units_direct

			print("[ShootingController] Visualizing LoS to %d enemy units" % enemy_units.size())
			for enemy_id in enemy_units:
				print("[ShootingController] Visualizing LoS to enemy unit: %s" % enemy_id)
				_visualize_los_to_target(active_shooter_id, enemy_id)
		return

	print("[ShootingController] Refreshing LoS debug visuals for active shooter: %s" % active_shooter_id)
	print("[ShootingController] Visualizing LoS to %d eligible targets" % eligible_targets.size())

	# Re-visualize LoS to all eligible targets
	for target_id in eligible_targets:
		print("[ShootingController] Visualizing LoS to target: %s" % target_id)
		_visualize_los_to_target(active_shooter_id, target_id)

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

	# Clear previous visualizations (comprehensive cleanup)
	if los_debug_visual and is_instance_valid(los_debug_visual):
		los_debug_visual.clear_all_debug_visuals()
	
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

	# Check if this is a weapon progress message (sequential resolution)
	var context = dice_data.get("context", "Roll")
	if context == "weapon_progress":
		var message = dice_data.get("message", "")
		var current_index = dice_data.get("current_index", 0)
		var total_weapons = dice_data.get("total_weapons", 0)
		dice_log_display.append_text("[b][color=yellow]>>> %s <<<[/color][/b]\n" % message)
		return

	# Get data from the dice roll
	var rolls_raw = dice_data.get("rolls_raw", [])
	var rolls_modified = dice_data.get("rolls_modified", [])
	var rerolls = dice_data.get("rerolls", [])
	var successes = dice_data.get("successes", -1)
	var threshold = dice_data.get("threshold", "")

	# Format the display text with modifier effects
	var log_text = "[b]%s[/b] (need %s):\n" % [context.capitalize().replace("_", " "), threshold]

	# Show re-rolls if any occurred
	if not rerolls.is_empty():
		log_text += "  [color=yellow]Re-rolled:[/color] "
		for reroll in rerolls:
			log_text += "[s]%d[/s]→%d " % [reroll.original, reroll.rerolled_to]
		log_text += "\n"

	# Show rolls (use modified if available, otherwise raw)
	var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
	log_text += "  Rolls: %s" % str(display_rolls)

	# Show success count
	if successes >= 0:
		log_text += " → [b][color=green]%d successes[/color][/b]" % successes

	log_text += "\n"

	dice_log_display.append_text(log_text)

func _on_saves_required(save_data_list: Array) -> void:
	"""Show SaveDialog when defender needs to make saves"""
	print("========================================")
	print("ShootingController: _on_saves_required CALLED")
	print("ShootingController: Saves required for %d targets" % save_data_list.size())
	print("ShootingController: is_networked = ", NetworkManager.is_networked())
	print("ShootingController: is_host = ", NetworkManager.is_host())

	if save_data_list.is_empty():
		print("ShootingController: Warning - empty save data list")
		return

	# IMPORTANT: For Phase 1 MVP, we only show ONE dialog for the FIRST target
	# Even if multiple targets need saves, we process them one at a time
	# This prevents multiple exclusive window errors
	var save_data = save_data_list[0]
	print("ShootingController: save_data keys = ", save_data.keys())

	# Get the target unit to determine who the defender is
	var target_unit_id = save_data.get("target_unit_id", "")
	print("ShootingController: target_unit_id = ", target_unit_id)
	if target_unit_id == "":
		push_error("ShootingController: No target_unit_id in save data")
		return

	var target_unit = GameState.get_unit(target_unit_id)
	print("ShootingController: target_unit found = ", not target_unit.is_empty())
	if target_unit.is_empty():
		push_error("ShootingController: Target unit not found: " + target_unit_id)
		return

	var defender_player = target_unit.get("owner", 0)
	print("ShootingController: Defender is player %d" % defender_player)

	# Determine if this local player should see the dialog
	var should_show_dialog = false

	if NetworkManager.is_networked():
		# Multiplayer: Only show dialog if this peer controls the defending player
		var local_peer_id = multiplayer.get_unique_id()
		print("ShootingController: local_peer_id = ", local_peer_id)
		print("ShootingController: peer_to_player_map = ", NetworkManager.peer_to_player_map)
		var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
		print("ShootingController: Local player is %d (peer %d)" % [local_player, local_peer_id])
		print("ShootingController: defender_player = %d" % defender_player)
		print("ShootingController: local_player == defender_player: ", local_player == defender_player)
		should_show_dialog = (local_player == defender_player)
	else:
		# Single player: Always show dialog (local player controls both sides)
		print("ShootingController: Single-player mode - always showing dialog")
		should_show_dialog = true

	print("ShootingController: should_show_dialog = ", should_show_dialog)

	if not should_show_dialog:
		print("ShootingController: Not showing dialog - not the defending player (attacker)")
		# Don't show "waiting" message for attacker - dice rolls will update automatically
		# The attacker should see the dice rolls, not a waiting message
		print("========================================")
		return

	# DEBOUNCE: Prevent multiple dialogs from being created
	if save_dialog_showing:
		print("ShootingController: ❌ Dialog already showing, ignoring duplicate signal")
		print("========================================")
		return

	save_dialog_showing = true
	print("ShootingController: ✅ Showing SaveDialog for defender")

	# Show feedback in dice log
	if dice_log_display:
		dice_log_display.append_text("[color=yellow]⚠ You must make saves![/color]\n")

	# Close any existing AcceptDialog instances to prevent multiple exclusive windows
	# This is a more aggressive cleanup to avoid the exclusive window error
	print("ShootingController: Checking for existing dialogs...")
	var root_children = get_tree().root.get_children()
	for child in root_children:
		if child is AcceptDialog:
			print("ShootingController: Closing existing AcceptDialog: %s" % child.name)
			child.hide()
			child.queue_free()

	# Wait one frame for cleanup to complete
	await get_tree().process_frame

	# Load SaveDialog script
	var save_dialog_script = preload("res://scripts/SaveDialog.gd")
	var dialog = save_dialog_script.new()

	# Connect to save_complete signal to clear the debounce flag
	dialog.save_complete.connect(func():
		print("ShootingController: Save complete, clearing dialog flag")
		save_dialog_showing = false
	)

	# Add to scene tree FIRST (so _ready() runs and creates UI elements)
	get_tree().root.add_child(dialog)

	# Setup with save data AFTER _ready() has run, passing defender_player
	dialog.setup(save_data, defender_player)

	# Show dialog
	dialog.popup_centered()

	print("ShootingController: SaveDialog shown for %s (defender=player %d)" %
		[save_data.get("target_unit_name", "Unknown"), defender_player])
	print("========================================")

func _on_weapon_order_required(assignments: Array) -> void:
	"""Show WeaponOrderDialog when multiple weapon types are assigned"""
	print("========================================")
	print("ShootingController: _on_weapon_order_required CALLED")
	print("ShootingController: Assignments: %d" % assignments.size())

	# Check if this is the attacking player in multiplayer
	var should_show_dialog = false

	if NetworkManager.is_networked():
		# Multiplayer: Only show dialog if this peer is the attacker
		var local_peer_id = multiplayer.get_unique_id()
		var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
		var active_player = current_phase.get_current_player() if current_phase else -1
		print("ShootingController: local_player = %d, active_player = %d" % [local_player, active_player])
		should_show_dialog = (local_player == active_player)
	else:
		# Single player: Always show dialog
		should_show_dialog = true

	if not should_show_dialog:
		print("ShootingController: Not showing weapon order dialog - not the attacking player")
		print("========================================")
		return

	# Show feedback in dice log
	if dice_log_display:
		dice_log_display.append_text("[b][color=cyan]Multiple weapon types detected - choose firing order...[/color][/b]\n")

	# Close any existing AcceptDialog instances
	print("ShootingController: Checking for existing dialogs...")
	var root_children = get_tree().root.get_children()
	for child in root_children:
		if child is AcceptDialog:
			print("ShootingController: Closing existing AcceptDialog: %s" % child.name)
			child.hide()
			child.queue_free()

	# Wait one frame for cleanup
	await get_tree().process_frame

	# Load WeaponOrderDialog script
	var weapon_order_dialog_script = preload("res://scripts/WeaponOrderDialog.gd")
	var dialog = weapon_order_dialog_script.new()

	# Connect to weapon_order_confirmed signal
	dialog.weapon_order_confirmed.connect(_on_weapon_order_confirmed)

	# Add to scene tree FIRST (so _ready() runs)
	get_tree().root.add_child(dialog)

	# Setup with assignments AND pass the current_phase for signal connections
	dialog.setup(assignments, current_phase)

	# Show dialog
	dialog.popup_centered()

	print("ShootingController: WeaponOrderDialog shown and connected to phase signals")
	print("========================================")

func _on_weapon_order_confirmed(weapon_order: Array, fast_roll: bool) -> void:
	"""Handle weapon order confirmation from WeaponOrderDialog"""
	print("========================================")
	print("ShootingController: _on_weapon_order_confirmed CALLED")
	print("ShootingController: Weapon order confirmed - fast_roll=%s, weapons=%d" % [fast_roll, weapon_order.size()])

	# Show feedback in dice log
	if dice_log_display:
		if fast_roll:
			dice_log_display.append_text("[color=cyan]Fast rolling all weapons at once...[/color]\n")
		else:
			dice_log_display.append_text("[color=cyan]Starting sequential weapon resolution...[/color]\n")

	# Build the action
	var action = {
		"type": "RESOLVE_WEAPON_SEQUENCE",
		"payload": {
			"weapon_order": weapon_order,
			"fast_roll": fast_roll
		}
	}

	print("ShootingController: Emitting shoot_action_requested signal...")
	print("ShootingController: Action = ", action)
	print("ShootingController: Signal connected? ", shoot_action_requested.is_connected(_on_weapon_order_confirmed))

	# Emit action to resolve weapon sequence
	emit_signal("shoot_action_requested", action)

	print("ShootingController: Signal emitted successfully")
	print("========================================")

func _on_next_weapon_confirmation_required(remaining_weapons: Array, current_index: int) -> void:
	"""Handle next weapon confirmation in sequential mode"""
	print("========================================")
	print("ShootingController: _on_next_weapon_confirmation_required CALLED")
	print("ShootingController: Remaining weapons: %d, current_index: %d" % [remaining_weapons.size(), current_index])

	# Check if this is for the local attacking player
	var should_show_dialog = false

	if NetworkManager.is_networked():
		var local_peer_id = multiplayer.get_unique_id()
		var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
		var active_player = current_phase.get_current_player() if current_phase else -1
		should_show_dialog = (local_player == active_player)
		print("ShootingController: local_player=%d, active_player=%d, should_show=%s" % [local_player, active_player, should_show_dialog])
	else:
		should_show_dialog = true

	if not should_show_dialog:
		print("ShootingController: Not showing confirmation dialog - not the attacking player")
		print("========================================")
		return

	# Show feedback in dice log
	if dice_log_display:
		dice_log_display.append_text("[b][color=yellow]>>> Weapon complete - Choose next weapon <<<[/color][/b]\n")

	# Show weapon order dialog with remaining weapons
	# User can reorder or just click "Sequential" to continue with current order
	print("ShootingController: Showing WeaponOrderDialog for remaining weapons")

	# Close any existing dialogs
	var root_children = get_tree().root.get_children()
	for child in root_children:
		if child is AcceptDialog:
			print("ShootingController: Closing existing dialog: %s" % child.name)
			child.hide()
			child.queue_free()

	await get_tree().process_frame

	# Load WeaponOrderDialog
	var weapon_order_dialog_script = preload("res://scripts/WeaponOrderDialog.gd")
	var dialog = weapon_order_dialog_script.new()

	# Connect to weapon_order_confirmed signal - but handle it differently
	dialog.weapon_order_confirmed.connect(_on_next_weapon_order_confirmed)

	# Add to scene tree
	get_tree().root.add_child(dialog)

	# Setup with remaining weapons AND pass the current_phase
	dialog.setup(remaining_weapons, current_phase)

	# Customize the title to show it's a continuation
	dialog.title = "Choose Next Weapon (%d remaining)" % remaining_weapons.size()

	# Show dialog
	dialog.popup_centered()

	print("ShootingController: WeaponOrderDialog shown for next weapon selection")
	print("========================================")

func _on_next_weapon_order_confirmed(weapon_order: Array, fast_roll: bool) -> void:
	"""Handle next weapon order confirmation (mid-sequence)"""
	print("========================================")
	print("ShootingController: _on_next_weapon_order_confirmed CALLED")
	print("ShootingController: Weapon order: %d weapons, fast_roll=%s" % [weapon_order.size(), fast_roll])

	# Show feedback in dice log
	if dice_log_display:
		dice_log_display.append_text("[color=cyan]Continuing to next weapon...[/color]\n")

	# If fast_roll is true in mid-sequence, just resolve all remaining weapons at once
	if fast_roll:
		# Build action to resolve remaining weapons as fast roll
		var action = {
			"type": "RESOLVE_WEAPON_SEQUENCE",
			"payload": {
				"weapon_order": weapon_order,
				"fast_roll": true,
				"is_reorder": true
			}
		}
		emit_signal("shoot_action_requested", action)
	else:
		# Continue sequential - either with reordered weapons or same order
		var action = {
			"type": "CONTINUE_SEQUENCE",
			"payload": {
				"weapon_order": weapon_order
			}
		}
		emit_signal("shoot_action_requested", action)

	print("ShootingController: Action emitted")
	print("========================================")

func _on_unit_selected(index: int) -> void:
	if not unit_selector or not current_phase:
		return

	var unit_id = unit_selector.get_item_metadata(index)
	if unit_id:
		# Clear previous LoS visualizations (comprehensive cleanup)
		if los_debug_visual and is_instance_valid(los_debug_visual):
			los_debug_visual.clear_all_debug_visuals()

		print("ShootingController: User selected unit %s from list" % unit_id)

		# Emit action request - visualization will be triggered when action is confirmed
		emit_signal("shoot_action_requested", {
			"type": "SELECT_SHOOTER",
			"actor_unit_id": unit_id
		})

		# DON'T call _on_unit_selected_for_shooting() here in multiplayer
		# The phase will emit unit_selected_for_shooting signal after processing the action
		# For single-player, we can call it immediately for responsiveness
		if not NetworkManager.is_networked():
			_on_unit_selected_for_shooting(unit_id)

func _on_weapon_tree_item_selected() -> void:
	if not weapon_tree:
		return

	var selected = weapon_tree.get_selected()
	if not selected:
		return

	var weapon_id = selected.get_metadata(0)
	if weapon_id:
		# Store selected weapon for modifier application
		selected_weapon_id = weapon_id

		# Visual feedback - highlight the selected weapon
		selected.set_custom_bg_color(0, Color(0.2, 0.4, 0.2, 0.5))

		# Update instruction text in column 1
		selected.set_text(1, "[Click enemy to assign]")

		# Show modifier panel and load modifiers for this weapon
		if modifier_panel and modifier_label:
			modifier_panel.visible = true
			modifier_label.visible = true
			_load_modifiers_for_weapon(weapon_id)

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
			_handle_board_click(mouse_pos)
		else:
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
		return
		
	var selected_weapon = weapon_tree.get_selected()
	if not selected_weapon:
		if dice_log_display:
			dice_log_display.append_text("[color=red]Please select a weapon first![/color]\n")
		return
	
	# Check if click is on an eligible target
	var closest_target = ""
	var closest_distance = INF
	var closest_model_pos = Vector2.ZERO
	
	
	for target_id in eligible_targets:
		var unit = current_phase.get_unit(target_id)
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = _get_model_position(model)
			var distance = model_pos.distance_to(position)
			if distance < closest_distance:
				closest_distance = distance
				closest_target = target_id
				closest_model_pos = model_pos
	
	# Use a larger click threshold to make selection easier
	if closest_target != "" and closest_distance < 500:  # Very large threshold for testing
		_select_target_for_current_weapon(closest_target)
	else:
		
		# If no target is close enough, let's try a different approach - just select the first available target
		if not eligible_targets.is_empty():
			var first_target = eligible_targets.keys()[0]
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

	# Include modifiers in the assignment (Phase 1 MVP)
	var payload = {
		"weapon_id": weapon_id,
		"target_unit_id": target_id,
		"model_ids": model_ids
	}

	# Add modifiers if they exist for this weapon
	if weapon_modifiers.has(weapon_id):
		payload["modifiers"] = weapon_modifiers[weapon_id]

	emit_signal("shoot_action_requested", {
		"type": "ASSIGN_TARGET",
		"payload": payload
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

# ==========================================
# MODIFIER SYSTEM (Phase 1 MVP)
# ==========================================

func _load_modifiers_for_weapon(weapon_id: String) -> void:
	"""Load existing modifiers for a weapon into the UI checkboxes"""
	# Initialize modifiers if they don't exist
	if not weapon_modifiers.has(weapon_id):
		weapon_modifiers[weapon_id] = {
			"hit": {
				"reroll_ones": false,
				"plus_one": false,
				"minus_one": false
			}
		}
	
	var mods = weapon_modifiers[weapon_id].hit
	
	# Update checkboxes without triggering signals
	if reroll_ones_checkbox:
		reroll_ones_checkbox.set_pressed_no_signal(mods.reroll_ones)
	if plus_one_checkbox:
		plus_one_checkbox.set_pressed_no_signal(mods.plus_one)
	if minus_one_checkbox:
		minus_one_checkbox.set_pressed_no_signal(mods.minus_one)

func _on_reroll_ones_toggled(button_pressed: bool) -> void:
	"""Handle re-roll 1s to hit checkbox toggle"""
	if selected_weapon_id == "":
		return
	
	if not weapon_modifiers.has(selected_weapon_id):
		weapon_modifiers[selected_weapon_id] = {"hit": {}}
	
	weapon_modifiers[selected_weapon_id].hit["reroll_ones"] = button_pressed
	
	if dice_log_display:
		var status = "enabled" if button_pressed else "disabled"
		dice_log_display.append_text("[color=cyan]Re-roll 1s to Hit %s for %s[/color]\n" % 
			[status, RulesEngine.get_weapon_profile(selected_weapon_id).get("name", selected_weapon_id)])

func _on_plus_one_toggled(button_pressed: bool) -> void:
	"""Handle +1 to hit checkbox toggle"""
	if selected_weapon_id == "":
		return
	
	if not weapon_modifiers.has(selected_weapon_id):
		weapon_modifiers[selected_weapon_id] = {"hit": {}}
	
	weapon_modifiers[selected_weapon_id].hit["plus_one"] = button_pressed
	
	if dice_log_display:
		var status = "enabled" if button_pressed else "disabled"
		dice_log_display.append_text("[color=cyan]+1 To Hit %s for %s[/color]\n" % 
			[status, RulesEngine.get_weapon_profile(selected_weapon_id).get("name", selected_weapon_id)])

func _on_minus_one_toggled(button_pressed: bool) -> void:
	"""Handle -1 to hit checkbox toggle"""
	if selected_weapon_id == "":
		return
	
	if not weapon_modifiers.has(selected_weapon_id):
		weapon_modifiers[selected_weapon_id] = {"hit": {}}
	
	weapon_modifiers[selected_weapon_id].hit["minus_one"] = button_pressed
	
	if dice_log_display:
		var status = "enabled" if button_pressed else "disabled"
		dice_log_display.append_text("[color=cyan]-1 To Hit %s for %s[/color]\n" % 
			[status, RulesEngine.get_weapon_profile(selected_weapon_id).get("name", selected_weapon_id)])

func _auto_assign_target(weapon_id: String, target_id: String) -> void:
	"""Auto-assign a target to a weapon (used when only one eligible target exists)"""
	# Mark as assigned
	weapon_assignments[weapon_id] = target_id

	# Get model IDs for this weapon
	var model_ids = []
	var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
	for model_id in unit_weapons:
		if weapon_id in unit_weapons[model_id]:
			model_ids.append(model_id)

	# Include modifiers in the assignment
	var payload = {
		"weapon_id": weapon_id,
		"target_unit_id": target_id,
		"model_ids": model_ids
	}

	# Add modifiers if they exist for this weapon
	if weapon_modifiers.has(weapon_id):
		payload["modifiers"] = weapon_modifiers[weapon_id]

	# Emit assignment action
	emit_signal("shoot_action_requested", {
		"type": "ASSIGN_TARGET",
		"payload": payload
	})

	# Update UI state
	_update_ui_state()
