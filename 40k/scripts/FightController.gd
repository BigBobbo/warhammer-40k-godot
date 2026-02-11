extends Node2D
class_name FightController

const BasePhase = preload("res://phases/BasePhase.gd")


# FightController - Handles UI interactions for the Fight Phase
# Manages fight sequencing, pile in/consolidate movement, attack assignment

signal fight_action_requested(action: Dictionary)
signal fighter_preview_updated(unit_id: String, valid: bool)
signal ui_update_requested()

# Fight state
var current_phase = null  # Can be FightPhase or null
var eligible_targets: Dictionary = {}  # target_unit_id -> target_data
var fight_sequence: Array = []  # Units in fight order
var current_fight_index: int = -1
var pending_pile_in_unit: String = ""
var pending_consolidate_unit: String = ""

# Pile-in/Consolidate interactive mode
var pile_in_active: bool = false
var consolidate_active: bool = false
var pile_in_unit_id: String = ""
var pile_in_dialog_ref: Node = null
var original_model_positions: Dictionary = {}  # model_id -> Vector2
var current_model_positions: Dictionary = {}   # model_id -> Vector2
var dragging_model: Node2D = null
var drag_model_id: String = ""
var drag_offset: Vector2 = Vector2.ZERO
var drag_start_pos: Vector2 = Vector2.ZERO

# UI References
var board_view: Node2D
var movement_visual: Line2D
var range_visual: Node2D
var target_highlights: Node2D
var hud_bottom: Control
var hud_right: Control

# Pile-in visual indicators
var pile_in_visuals: Node2D = null  # Container for all pile-in visuals
var range_circles: Dictionary = {}  # model_id -> Node2D (circle showing 3" range)
var direction_lines: Dictionary = {}  # model_id -> Line2D (to closest enemy)
var coherency_lines: Array = []  # Array of Line2D showing unit coherency

# Track current fighting unit and its owner
var current_fighter_id: String = ""
var current_fighter_owner: int = -1

# UI Elements
var unit_selector: ItemList
var attack_tree: Tree
var target_basket: ItemList
var pile_in_button: Button
var consolidate_button: Button
var confirm_button: Button
var clear_button: Button
var dice_log_display: RichTextLabel

# Visual settings
const HIGHLIGHT_COLOR_ELIGIBLE = Color.GREEN
const HIGHLIGHT_COLOR_INELIGIBLE = Color.GRAY
const HIGHLIGHT_COLOR_SELECTED = Color.YELLOW
const HIGHLIGHT_COLOR_ACTIVE_FIGHTER = Color.ORANGE
const MOVEMENT_LINE_COLOR = Color.BLUE
const MOVEMENT_LINE_WIDTH = 3.0
const ENGAGEMENT_RANGE_MM = 25.4  # 1 inch in mm

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)
	_setup_ui_references()
	_create_fight_visuals()
	print("FightController ready")

func _exit_tree() -> void:
	# Clean up visual elements
	if movement_visual and is_instance_valid(movement_visual):
		movement_visual.queue_free()
	if range_visual and is_instance_valid(range_visual):
		range_visual.queue_free()
	if target_highlights and is_instance_valid(target_highlights):
		target_highlights.queue_free()
	
	# Clean up UI elements from bottom HUD
	var hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	if hud_bottom:
		var main_container = hud_bottom.get_node_or_null("HBoxContainer")
		if main_container:
			# Remove the spacer
			var spacer = main_container.get_node_or_null("FightPhaseSpacer")
			if spacer and is_instance_valid(spacer):
				main_container.remove_child(spacer)
				spacer.queue_free()
			
			# Main.gd now handles phase action button cleanup
			
			# Remove any legacy FightControls container
			var fight_controls = main_container.get_node_or_null("FightControls")
			if fight_controls and is_instance_valid(fight_controls):
				main_container.remove_child(fight_controls)
				fight_controls.queue_free()
				print("FightController: Removed legacy FightControls container")
	
	# ENHANCEMENT: Comprehensive right panel cleanup
	var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
	if container and is_instance_valid(container):
		var fight_elements = ["FightPanel", "FightScrollContainer", "FightSequence", "FightActions"]
		for element in fight_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("FightController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

func _setup_ui_references() -> void:
	# Get references to UI nodes
	board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
	hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	hud_right = get_node_or_null("/root/Main/HUD_Right")
	
	# Setup fight-specific UI elements
	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()

func _create_fight_visuals() -> void:
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		print("ERROR: Cannot find BoardRoot for visual layers")
		return
	
	# Create movement visualization line
	movement_visual = Line2D.new()
	movement_visual.name = "FightMovementVisual"
	movement_visual.width = MOVEMENT_LINE_WIDTH
	movement_visual.default_color = MOVEMENT_LINE_COLOR
	movement_visual.add_point(Vector2.ZERO)
	movement_visual.clear_points()
	board_root.add_child(movement_visual)
	
	# Create engagement range visualization node
	range_visual = Node2D.new()
	range_visual.name = "FightRangeVisual"
	board_root.add_child(range_visual)
	
	# Create target highlight container
	target_highlights = Node2D.new()
	target_highlights.name = "FightTargetHighlights"
	board_root.add_child(target_highlights)

func _setup_bottom_hud() -> void:
	# NOTE: Main.gd now handles the phase action button
	# FightController only manages fight-specific UI in the right panel
	pass

func _setup_right_panel() -> void:
	# Main.gd already handles cleanup before controller creation
	# Check for existing VBoxContainer in HUD_Right
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)
	
	# Check for existing fight panel
	var scroll_container = container.get_node_or_null("FightScrollContainer")
	var fight_panel = null
	
	if not scroll_container:
		# Create scroll container for better layout
		scroll_container = ScrollContainer.new()
		scroll_container.name = "FightScrollContainer"
		scroll_container.custom_minimum_size = Vector2(250, 400)
		scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.add_child(scroll_container)
		
		fight_panel = VBoxContainer.new()
		fight_panel.name = "FightPanel"
		fight_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_container.add_child(fight_panel)
	else:
		# Get existing fight panel
		fight_panel = scroll_container.get_node_or_null("FightPanel")
		if fight_panel:
			# Clear existing children to rebuild fresh
			print("FightController: Removing existing fight panel children (", fight_panel.get_children().size(), " children)")
			for child in fight_panel.get_children():
				fight_panel.remove_child(child)
				child.free()
	
	# Title
	var title = Label.new()
	title.text = "Fight Controls"
	title.add_theme_font_size_override("font_size", 16)
	fight_panel.add_child(title)
	
	fight_panel.add_child(HSeparator.new())
	
	# Fight sequence display
	var sequence_label = Label.new()
	sequence_label.text = "Fight Sequence:"
	fight_panel.add_child(sequence_label)
	
	unit_selector = ItemList.new()
	unit_selector.custom_minimum_size = Vector2(230, 100)
	unit_selector.item_selected.connect(_on_unit_selected)
	fight_panel.add_child(unit_selector)
	
	fight_panel.add_child(HSeparator.new())
	
	# Attack assignments tree
	var attack_label = Label.new()
	attack_label.text = "Melee Attacks:"
	fight_panel.add_child(attack_label)
	
	attack_tree = Tree.new()
	attack_tree.custom_minimum_size = Vector2(230, 120)
	attack_tree.columns = 2
	attack_tree.set_column_title(0, "Weapon")
	attack_tree.set_column_title(1, "Target")
	attack_tree.hide_root = true
	attack_tree.item_selected.connect(_on_attack_tree_item_selected)
	attack_tree.button_clicked.connect(_on_attack_tree_button_clicked)
	fight_panel.add_child(attack_tree)
	
	# Target basket
	var basket_label = Label.new()
	basket_label.text = "Current Targets:"
	fight_panel.add_child(basket_label)
	
	target_basket = ItemList.new()
	target_basket.custom_minimum_size = Vector2(230, 80)
	fight_panel.add_child(target_basket)
	
	# Action buttons
	var button_container = HBoxContainer.new()
	
	clear_button = Button.new()
	clear_button.text = "Clear All"
	clear_button.pressed.connect(_on_clear_pressed)
	button_container.add_child(clear_button)
	
	confirm_button = Button.new()
	confirm_button.text = "Fight!"
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)
	
	fight_panel.add_child(button_container)
	
	# Dice log
	fight_panel.add_child(HSeparator.new())
	
	var dice_label = Label.new()
	dice_label.text = "Combat Log:"
	fight_panel.add_child(dice_label)
	
	dice_log_display = RichTextLabel.new()
	dice_log_display.custom_minimum_size = Vector2(230, 100)
	dice_log_display.bbcode_enabled = true
	dice_log_display.scroll_following = true
	fight_panel.add_child(dice_log_display)
	
	# ADD: Action buttons section (moved from top bar)
	fight_panel.add_child(HSeparator.new())
	
	# Fight status display (moved from top bar)
	var status_section_label = Label.new()
	status_section_label.text = "Fight Status:"
	status_section_label.add_theme_font_size_override("font_size", 14)
	fight_panel.add_child(status_section_label)
	
	# Fight sequence status (moved from top bar)
	var fight_sequence_status = Label.new()
	fight_sequence_status.text = "No active fights"
	fight_sequence_status.name = "SequenceLabel"
	fight_panel.add_child(fight_sequence_status)
	
	# Action buttons container
	var action_section_label = Label.new()
	action_section_label.text = "Movement Actions:"
	action_section_label.add_theme_font_size_override("font_size", 14)
	fight_panel.add_child(action_section_label)
	
	var action_button_container = HBoxContainer.new()
	action_button_container.name = "FightMovementButtons"
	
	# Pile In button (moved from top bar)
	pile_in_button = Button.new()
	pile_in_button.text = "Pile In"
	pile_in_button.pressed.connect(_on_pile_in_pressed)
	pile_in_button.disabled = true
	action_button_container.add_child(pile_in_button)
	
	# Consolidate button (moved from top bar)
	consolidate_button = Button.new()
	consolidate_button.text = "Consolidate"
	consolidate_button.pressed.connect(_on_consolidate_pressed)
	consolidate_button.disabled = true
	action_button_container.add_child(consolidate_button)
	
	fight_panel.add_child(action_button_container)

func set_phase(phase: BasePhase) -> void:
	current_phase = phase
	print("DEBUG: FightController.set_phase called with phase type: ", phase.get_class() if phase else "null")
	
	if phase and phase.has_method("get_available_actions"):
		# Connect to phase signals if they exist
		if phase.has_signal("fighter_selected") and not phase.fighter_selected.is_connected(_on_fighter_selected):
			phase.fighter_selected.connect(_on_fighter_selected)
		if phase.has_signal("targets_available") and not phase.targets_available.is_connected(_on_targets_available):
			phase.targets_available.connect(_on_targets_available)
		if phase.has_signal("fight_resolved") and not phase.fight_resolved.is_connected(_on_fight_resolved):
			phase.fight_resolved.connect(_on_fight_resolved)
		if phase.has_signal("dice_rolled") and not phase.dice_rolled.is_connected(_on_dice_rolled):
			phase.dice_rolled.connect(_on_dice_rolled)
		if phase.has_signal("fight_sequence_updated") and not phase.fight_sequence_updated.is_connected(_on_fight_sequence_updated):
			phase.fight_sequence_updated.connect(_on_fight_sequence_updated)

		# Connect to new dialog signals for subphase system
		if phase.has_signal("fight_selection_required") and not phase.fight_selection_required.is_connected(_on_fight_selection_required):
			phase.fight_selection_required.connect(_on_fight_selection_required)
		if phase.has_signal("pile_in_required") and not phase.pile_in_required.is_connected(_on_pile_in_required):
			phase.pile_in_required.connect(_on_pile_in_required)
		if phase.has_signal("attack_assignment_required") and not phase.attack_assignment_required.is_connected(_on_attack_assignment_required):
			phase.attack_assignment_required.connect(_on_attack_assignment_required)
		if phase.has_signal("attack_assigned") and not phase.attack_assigned.is_connected(_on_attack_assigned):
			phase.attack_assigned.connect(_on_attack_assigned)
		if phase.has_signal("consolidate_required") and not phase.consolidate_required.is_connected(_on_consolidate_required):
			phase.consolidate_required.connect(_on_consolidate_required)
		if phase.has_signal("subphase_transition") and not phase.subphase_transition.is_connected(_on_subphase_transition):
			phase.subphase_transition.connect(_on_subphase_transition)

		print("DEBUG: FightController signals connected, setting up UI")

		# Ensure UI is set up after phase assignment
		_setup_ui_references()

		# IMPORTANT: Check if we missed the initial fight_selection_required signal
		# This happens because phase emits the signal during enter_phase, before we connect
		if phase.has_method("_emit_fight_selection_required"):
			print("DEBUG: Re-triggering fight selection after signal connection")
			# Give the phase a moment to finish setup, then re-emit
			await get_tree().create_timer(0.1).timeout
			if current_phase and current_phase.has_method("_emit_fight_selection_required"):
				current_phase._emit_fight_selection_required()
		
		_refresh_fight_sequence()
		
		# Restore state if loading from save
		_restore_state_after_load()
		
		# Initial UI population
		print("DEBUG: FightController calling _refresh_available_actions from set_phase")
		_refresh_available_actions()
		
		show()
	else:
		_clear_visuals()
		hide()

func _restore_state_after_load() -> void:
	"""Restore FightController UI state after loading from save"""
	if not current_phase or not current_phase is FightPhase:
		return
	
	var fight_state = current_phase.get_current_fight_state()
	
	# Restore current fighter if there was one
	if fight_state.current_fighter_id != "":
		current_fighter_id = fight_state.current_fighter_id
		
		# Query targets for the active fighter
		eligible_targets = RulesEngine.get_eligible_melee_targets(current_fighter_id, current_phase.game_state_snapshot)
		
		# Restore UI elements
		_refresh_attack_tree()
		_show_engagement_indicators()
		
		# Show feedback in combat log
		if dice_log_display:
			dice_log_display.append_text("[color=blue]Restored fight state for %s[/color]\n" % 
				current_phase.get_unit(current_fighter_id).get("meta", {}).get("name", current_fighter_id))
	
	# Update fight sequence display
	_refresh_fight_sequence()

func _refresh_fight_sequence() -> void:
	if not unit_selector or not current_phase:
		return
	
	unit_selector.clear()
	
	# Get fight sequence from phase
	if current_phase.has_method("get_fight_sequence"):
		fight_sequence = current_phase.get_fight_sequence()
		current_fight_index = current_phase.get_current_fight_index()
	
	# Display fight sequence with status indicators
	for i in range(fight_sequence.size()):
		var unit_id = fight_sequence[i]
		var unit = current_phase.get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		
		# Add status indicators
		if i < current_fight_index:
			unit_name += " [FOUGHT]"
		elif i == current_fight_index:
			unit_name += " [ACTIVE]"
		elif current_fighter_id == unit_id:
			unit_name += " [SELECTED]"
		
		unit_selector.add_item(unit_name)
		unit_selector.set_item_metadata(unit_selector.get_item_count() - 1, unit_id)
	
	# Update sequence label in right panel (moved from bottom HUD)
	var sequence_label = hud_right.get_node_or_null("VBoxContainer/FightScrollContainer/FightPanel/SequenceLabel")
	
	# Refresh available actions to populate fight controls
	_refresh_available_actions()
	if sequence_label:
		if fight_sequence.is_empty():
			sequence_label.text = "No active fights"
		else:
			var active_unit = "None"
			if current_fight_index >= 0 and current_fight_index < fight_sequence.size():
				var unit_id = fight_sequence[current_fight_index]
				var unit = current_phase.get_unit(unit_id)
				active_unit = unit.get("meta", {}).get("name", unit_id)
			sequence_label.text = "Fighting: %s (%d/%d)" % [active_unit, current_fight_index + 1, fight_sequence.size()]

func _refresh_attack_tree() -> void:
	if not attack_tree or current_fighter_id == "":
		return
	
	attack_tree.clear()
	var root = attack_tree.create_item()
	
	# Get unit melee weapons from RulesEngine
	var unit_weapons = RulesEngine.get_unit_melee_weapons(current_fighter_id)
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
		
		# Skip if weapon profile not found
		if weapon_profile.is_empty():
			print("WARNING: Skipping weapon with missing profile: ", weapon_id)
			continue
			
		# Skip non-melee weapons
		if weapon_profile.get("type", "") != "Melee":
			continue
			
		var weapon_item = attack_tree.create_item(root)
		weapon_item.set_text(0, "%s (x%d)" % [weapon_profile.get("name", weapon_id), weapon_counts[weapon_id]])
		weapon_item.set_metadata(0, weapon_id)
		
		# Add target selector in second column
		if eligible_targets.size() > 0:
			weapon_item.set_text(1, "[Click to Select]")
			weapon_item.set_selectable(0, true)
			weapon_item.set_selectable(1, false)

			# REMOVED: Icon button for consistency with ShootingController
			# Users can select weapon, then click enemy unit to assign target

func _show_engagement_indicators() -> void:
	_clear_range_indicators()
	
	if current_fighter_id == "" or not current_phase:
		return
	
	var fighter_unit = current_phase.get_unit(current_fighter_id)
	if fighter_unit.is_empty():
		return
	
	# Draw engagement range circles from each model
	for model in fighter_unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.ZERO:
			continue
		
		# Create a circle to show engagement range (1 inch)
		var circle = Node2D.new()
		circle.position = model_pos
		circle.set_script(GDScript.new())
		
		var script_source = """
extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var radius = """ + str(ENGAGEMENT_RANGE_MM) + """
	var color = Color.ORANGE
	
	# Draw engagement range circle
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.0, true)
	
	# Draw filled circle with transparency
	var fill_color = color
	fill_color.a = 0.2
	draw_circle(Vector2.ZERO, radius, fill_color)
"""
		circle.set_script(GDScript.new())
		circle.get_script().source_code = script_source
		circle.get_script().reload()
		
		range_visual.add_child(circle)
	
	# Highlight enemies within engagement range
	_highlight_enemies_by_engagement(fighter_unit)

func _highlight_enemies_by_engagement(fighter_unit: Dictionary) -> void:
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
		
		# Check if any model in the fighter unit can reach any model in the enemy unit
		var is_in_engagement = false
		
		for fighter_model in fighter_unit.get("models", []):
			if not fighter_model.get("alive", true):
				continue
			var fighter_pos = _get_model_position(fighter_model)
			
			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				var enemy_pos = _get_model_position(enemy_model)
				
				var distance = fighter_pos.distance_to(enemy_pos)
				
				# Check if within engagement range (1 inch)
				if distance <= ENGAGEMENT_RANGE_MM:
					is_in_engagement = true
					break
			
			if is_in_engagement:
				break
		
		# Highlight the unit based on engagement status
		if is_in_engagement:
			_create_target_highlight(enemy_id, HIGHLIGHT_COLOR_ELIGIBLE)
		else:
			_create_target_highlight(enemy_id, Color(0.5, 0.5, 0.5, 0.3))  # Gray for out of range

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
		highlight.set_meta("base_radius", 35.0)
		
		# Add custom draw script for the highlight
		var script_source = """
extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var color = get_meta("highlight_color", Color.GREEN)
	var radius = get_meta("base_radius", 35.0)
	
	# Draw outer ring
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 4.0, true)
	
	# Draw inner filled circle with transparency
	var fill_color = color
	fill_color.a = 0.3
	draw_circle(Vector2.ZERO, radius - 3, fill_color)
	
	# Draw pulsing effect for eligible targets
	if color == Color.GREEN:
		draw_arc(Vector2.ZERO, radius + 8, 0, TAU, 32, color, 2.0, true)
"""
		highlight.set_script(GDScript.new())
		highlight.get_script().source_code = script_source
		highlight.get_script().reload()
		
		target_highlights.add_child(highlight)

func _clear_target_highlights() -> void:
	if target_highlights:
		for child in target_highlights.get_children():
			child.queue_free()

func _clear_range_indicators() -> void:
	if range_visual:
		for child in range_visual.get_children():
			child.queue_free()

func _clear_visuals() -> void:
	if movement_visual:
		movement_visual.clear_points()
	_clear_range_indicators()
	_clear_target_highlights()

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _update_ui_state() -> void:
	if confirm_button:
		# Enable fight button if we have attack assignments
		confirm_button.disabled = target_basket.get_item_count() == 0
	if clear_button:
		clear_button.disabled = target_basket.get_item_count() == 0
	
	# Update movement buttons based on phase state
	if pile_in_button:
		pile_in_button.disabled = current_fighter_id == "" or not _can_pile_in()
	if consolidate_button:
		consolidate_button.disabled = current_fighter_id == "" or not _can_consolidate()

func _refresh_available_actions() -> void:
	"""Refresh available actions and populate fight controls dynamically"""
	if not current_phase or not current_phase.has_method("get_available_actions"):
		return
		
	print("DEBUG: FightController calling get_available_actions()")
	var available_actions = current_phase.get_available_actions()
	print("DEBUG: FightController received %d available actions" % available_actions.size())
	
	# Clear any existing action buttons (except fixed UI elements)
	_clear_dynamic_action_buttons()
	
	# Create buttons for each available action (only for simple actions like PILE_IN)
	for action in available_actions:
		var action_type = action.get("type", "")
		if action_type in ["PILE_IN", "CONFIRM_AND_RESOLVE_ATTACKS", "CONSOLIDATE", "END_PHASE"]:
			_create_action_button(action)
	
	# Update the right panel with fighters and weapons
	print("DEBUG: _refresh_available_actions calling _refresh_fighter_list and _refresh_weapon_tree")
	_refresh_fighter_list()
	_refresh_weapon_tree()

func _clear_dynamic_action_buttons() -> void:
	"""Remove dynamically created action buttons"""
	var fight_controls = hud_bottom.get_node_or_null("HBoxContainer/FightControls")
	if not fight_controls:
		return
	
	# Remove all action buttons (they start with "ActionButton_")
	for child in fight_controls.get_children():
		if child.name.begins_with("ActionButton_"):
			print("DEBUG: Removing old action button: %s" % child.name)
			child.queue_free()

func _create_action_button(action: Dictionary) -> void:
	"""Create a button for an available action"""
	var action_type = action.get("type", "")
	var description = action.get("description", action_type)
	var unit_id = action.get("unit_id", "")
	
	print("DEBUG: Creating action button for: %s (%s)" % [action_type, description])
	
	# Find the fight controls container
	var fight_controls = hud_bottom.get_node_or_null("HBoxContainer/FightControls")
	if not fight_controls:
		print("ERROR: Could not find FightControls container")
		return
	
	# Create the action button
	var button = Button.new()
	button.text = description
	button.name = "ActionButton_" + action_type
	
	# Connect the button to execute the action
	if action_type == "SELECT_FIGHTER":
		button.pressed.connect(_on_select_fighter_pressed.bind(unit_id))
	elif action_type == "SELECT_MELEE_WEAPON":
		var weapon_id = action.get("weapon_id", "")
		button.pressed.connect(_on_select_melee_weapon_pressed.bind(unit_id, weapon_id))
	elif action_type == "PILE_IN":
		button.pressed.connect(_on_pile_in_pressed)  # Uses existing signature
	elif action_type == "ASSIGN_ATTACKS_UI":
		button.pressed.connect(_on_assign_attacks_ui_pressed.bind(unit_id))
	elif action_type == "CONFIRM_AND_RESOLVE_ATTACKS":
		button.pressed.connect(_on_confirm_pressed)  # Uses existing signature
	elif action_type == "CONSOLIDATE":
		button.pressed.connect(_on_consolidate_pressed)  # Uses existing signature
	
	# Add the button to the fight controls
	fight_controls.add_child(button)
	print("DEBUG: Added action button '%s' to FightControls" % button.text)

func _on_select_fighter_pressed(unit_id: String) -> void:
	"""Handle SELECT_FIGHTER button press"""
	print("DEBUG: SELECT_FIGHTER button pressed for unit: %s" % unit_id)
	
	# Create the action to send to the phase
	var action = {
		"type": "SELECT_FIGHTER",
		"unit_id": unit_id
	}
	
	# Send the action to the phase
	if current_phase and current_phase.has_method("execute_action"):
		print("DEBUG: Executing SELECT_FIGHTER action: %s" % str(action))
		var result = current_phase.execute_action(action)
		print("DEBUG: SELECT_FIGHTER result: %s" % str(result))
		
		# Refresh the UI after executing action
		_refresh_available_actions()
	else:
		print("ERROR: Cannot execute SELECT_FIGHTER - no valid phase")

func _on_select_melee_weapon_pressed(unit_id: String, weapon_id: String) -> void:
	"""Handle SELECT_MELEE_WEAPON button press"""
	print("DEBUG: SELECT_MELEE_WEAPON button pressed for unit: %s, weapon: %s" % [unit_id, weapon_id])
	
	# Create the action to send to the phase
	var action = {
		"type": "SELECT_MELEE_WEAPON",
		"unit_id": unit_id,
		"weapon_id": weapon_id
	}
	
	# Send the action to the phase
	if current_phase and current_phase.has_method("execute_action"):
		print("DEBUG: Executing SELECT_MELEE_WEAPON action: %s" % str(action))
		var result = current_phase.execute_action(action)
		print("DEBUG: SELECT_MELEE_WEAPON result: %s" % str(result))
		
		# Refresh the UI after executing action
		_refresh_available_actions()
	else:
		print("ERROR: Cannot execute SELECT_MELEE_WEAPON - no valid phase")

func _refresh_fighter_list() -> void:
	"""Refresh the unit list with eligible fighters (similar to ShootingController)"""
	print("DEBUG: _refresh_fighter_list called")
	if not unit_selector:
		print("DEBUG: No unit_selector found, returning")
		return
	if not current_phase:
		print("DEBUG: No current_phase found, returning")
		return
		
	print("DEBUG: Clearing unit_selector and refreshing fighter list")
	unit_selector.clear()
	
	# Get the fight sequence and show all units in combat
	if not current_phase.has_method("get_current_fight_state"):
		print("DEBUG: No get_current_fight_state method, returning")
		return
		
	var fight_state = current_phase.get_current_fight_state()
	var fight_sequence = fight_state.get("fight_sequence", [])
	var current_fight_index = fight_state.get("current_fight_index", 0)
	var units_that_fought = fight_state.get("units_that_fought", [])
	
	print("DEBUG: Fight sequence: ", fight_sequence)
	print("DEBUG: Current fight index: ", current_fight_index)
	
	for i in range(fight_sequence.size()):
		var unit_id = fight_sequence[i]
		var unit = current_phase.get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		
		# Add status indicators
		if unit_id in units_that_fought:
			unit_name += " [FOUGHT]"
		elif i == current_fight_index:
			unit_name += " [ACTIVE]"
		elif i < current_fight_index:
			unit_name += " [NEXT]"
			
		unit_selector.add_item(unit_name)
		unit_selector.set_item_metadata(unit_selector.get_item_count() - 1, unit_id)

func _refresh_weapon_tree() -> void:
	"""Refresh the weapon tree with melee weapons for selected fighter"""
	if not attack_tree:
		return
		
	attack_tree.clear()
	
	if not current_phase or current_fighter_id == "":
		return
		
	# Get melee weapons for the current fighter
	var snapshot = current_phase.game_state_snapshot if "game_state_snapshot" in current_phase else {}
	var melee_weapons = RulesEngine.get_unit_melee_weapons(current_fighter_id, snapshot)
	
	print("DEBUG: Refreshing weapon tree for %s with weapons: %s" % [current_fighter_id, str(melee_weapons)])
	
	# Create root
	var root = attack_tree.create_item()
	root.set_text(0, "Melee Weapons")
	
	# Add weapons organized by model
	for model_id in melee_weapons:
		var model_weapons = melee_weapons[model_id]  # Array of weapon names
		var model_item = attack_tree.create_item(root)
		model_item.set_text(0, "Model " + model_id)
		
		for weapon_name in model_weapons:
			var weapon_item = attack_tree.create_item(model_item)
			weapon_item.set_text(0, weapon_name)
			weapon_item.set_metadata(0, {
				"type": "weapon",
				"weapon_id": weapon_name,
				"model_id": model_id
			})

func _on_assign_attacks_ui_pressed(unit_id: String) -> void:
	"""Handle ASSIGN_ATTACKS_UI button press - shows weapon/target selection UI"""
	print("DEBUG: ASSIGN_ATTACKS_UI button pressed for unit: %s" % unit_id)
	# The weapon selection is handled through the weapon tree UI
	# Target selection would be handled through clicking on enemy units

func _can_pile_in() -> bool:
	# Can pile in if we have a selected fighter and they haven't piled in yet
	if current_phase and current_phase.has_method("can_unit_pile_in"):
		return current_phase.can_unit_pile_in(current_fighter_id)
	return false

func _can_consolidate() -> bool:
	# Can consolidate if we have a selected fighter and they've finished fighting
	if current_phase and current_phase.has_method("can_unit_consolidate"):
		return current_phase.can_unit_consolidate(current_fighter_id)
	return false

# Signal handlers

func _on_unit_selected(index: int) -> void:
	if not unit_selector or not current_phase:
		return
	
	var unit_id = unit_selector.get_item_metadata(index)
	if unit_id:
		# Update local state
		current_fighter_id = unit_id
		print("DEBUG: Unit selected from list: %s" % unit_id)
		
		# Send SELECT_FIGHTER action to phase
		emit_signal("fight_action_requested", {
			"type": "SELECT_FIGHTER",
			"unit_id": unit_id
		})
		
		# Refresh the weapon tree for this fighter
		_refresh_weapon_tree()

func _on_attack_tree_item_selected() -> void:
	if not attack_tree:
		return
		
	var selected = attack_tree.get_selected()
	if not selected:
		return
		
	var metadata = selected.get_metadata(0)
	if metadata:
		# Handle both old format (string) and new format (dictionary)
		var weapon_id = ""
		if metadata is String:
			weapon_id = metadata
		elif metadata is Dictionary:
			weapon_id = metadata.get("weapon_id", "")
		
		if weapon_id:
			# Visual feedback - highlight the selected weapon
			selected.set_custom_bg_color(0, Color(0.2, 0.4, 0.2, 0.5))
			
			# Update instruction text in column 1
			selected.set_text(1, "[Click enemy to assign]")
			
			# Show a message to the user
			if dice_log_display:
				dice_log_display.append_text("[color=yellow]Selected %s - Click on an enemy unit or use the button to assign target[/color]\n" % 
					RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id))

func _on_attack_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if not item or column != 1:
		return
		
	var metadata = item.get_metadata(0)
	if not metadata or eligible_targets.is_empty():
		return
	
	# Handle both old format (string) and new format (dictionary)
	var weapon_id = ""
	if metadata is String:
		weapon_id = metadata
	elif metadata is Dictionary:
		weapon_id = metadata.get("weapon_id", "")
	
	if not weapon_id:
		return
		
	# Auto-assign first available target
	var first_target = eligible_targets.keys()[0]
	print("DEBUG: Button clicked - auto-assigning target: ", first_target)
	_select_target_for_current_weapon(first_target)

func _on_fighter_selected(unit_id: String) -> void:
	current_fighter_id = unit_id
	
	# Debug logging
	print("Selected fighter: ", unit_id)
	
	_refresh_attack_tree()
	_show_engagement_indicators()
	_update_ui_state()

func _on_targets_available(unit_id: String, targets: Dictionary) -> void:
	eligible_targets = targets
	_refresh_attack_tree()
	_show_engagement_indicators()

func _on_fight_resolved(fighter_id: String, results: Dictionary) -> void:
	# Update visuals after fighting
	_clear_visuals()
	current_fighter_id = ""
	eligible_targets.clear()
	_refresh_fight_sequence()
	_update_ui_state()

func _on_dice_rolled(dice_data: Dictionary) -> void:
	if not dice_log_display:
		return

	var context = dice_data.get("context", "")
	var rolls_raw = dice_data.get("rolls_raw", [])
	var successes = dice_data.get("successes", 0)
	var threshold = dice_data.get("threshold", "")
	var weapon = dice_data.get("weapon", "")

	# Format context name
	var context_name = context.capitalize().replace("_", " ")

	# Build display text
	var log_text = "[b]%s[/b]" % context_name

	# Add weapon info if present
	if weapon != "":
		var weapon_profile = RulesEngine.get_weapon_profile(weapon)
		if weapon_profile:
			log_text += " (%s)" % weapon_profile.get("name", weapon)

	# Add threshold
	if threshold != "":
		log_text += " (need %s)" % threshold

	log_text += ":\n"

	# Color-code individual dice results
	if not rolls_raw.is_empty():
		var target_num = int(threshold.replace("+", "")) if threshold != "" else 4
		var colored_rolls = []
		for roll in rolls_raw:
			if roll >= target_num:
				colored_rolls.append("[color=green]%d[/color]" % roll)
			else:
				colored_rolls.append("[color=gray]%d[/color]" % roll)

		log_text += "  Rolls: [%s]" % ", ".join(colored_rolls)
	else:
		log_text += "  Rolls: %s" % str(rolls_raw)

	# Add success count
	log_text += " → [b][color=green]%d successes[/color][/b]" % successes

	# Save roll: show failed saves (which cause wounds)
	if context == "save_roll":
		var failed = dice_data.get("failed", 0)
		if failed > 0:
			log_text += ", [color=red]%d failed (wounds)[/color]" % failed
		else:
			log_text += " [color=green](all saved!)[/color]"

	log_text += "\n"

	dice_log_display.append_text(log_text)

func _on_fight_sequence_updated(sequence: Array, index: int) -> void:
	fight_sequence = sequence
	current_fight_index = index
	_refresh_fight_sequence()

func _on_pile_in_pressed() -> void:
	if current_fighter_id != "":
		pending_pile_in_unit = current_fighter_id
		if dice_log_display:
			dice_log_display.append_text("[color=cyan]Click to move %s up to 3\" toward closest enemy[/color]\n" % 
				current_phase.get_unit(current_fighter_id).get("meta", {}).get("name", current_fighter_id))

func _on_consolidate_pressed() -> void:
	if current_fighter_id != "":
		pending_consolidate_unit = current_fighter_id
		if dice_log_display:
			dice_log_display.append_text("[color=cyan]Click to move %s up to 3\" toward closest enemy[/color]\n" % 
				current_phase.get_unit(current_fighter_id).get("meta", {}).get("name", current_fighter_id))

func _on_clear_pressed() -> void:
	emit_signal("fight_action_requested", {
		"type": "CLEAR_ALL_ASSIGNMENTS"
	})
	_update_ui_state()

func _on_confirm_pressed() -> void:
	# Show visual feedback that fighting is resolving
	if dice_log_display:
		dice_log_display.append_text("[color=yellow]Rolling melee combat...[/color]\n")
	
	emit_signal("fight_action_requested", {
		"type": "CONFIRM_ATTACKS"
	})

func _on_end_phase_pressed() -> void:
	emit_signal("fight_action_requested", {
		"type": "END_FIGHT"
	})

func _input(event: InputEvent) -> void:
	if not current_phase or not current_phase is FightPhase:
		return

	# Debug: Log when pile-in mode is active
	if event is InputEventMouseButton:
		print("[FightController] _input: pile_in_active=", pile_in_active, " consolidate_active=", consolidate_active)

	# Handle interactive pile-in mode - process at input level to bypass dialog
	if pile_in_active or consolidate_active:
		_handle_pile_in_input(event)
		get_viewport().set_input_as_handled()  # Prevent dialog from blocking
		return

	# Handle pile in or consolidate movement (legacy)
	if (pending_pile_in_unit != "" or pending_consolidate_unit != "") and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var board_root = get_node_or_null("/root/Main/BoardRoot")
		if board_root:
			var mouse_pos = board_root.get_local_mouse_position()
			_handle_movement_click(mouse_pos)
		return

	# Only handle target selection input if we have an active fighter and eligible targets
	if current_fighter_id == "" or eligible_targets.is_empty():
		return

	# Handle clicking on units for target selection
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var board_root = get_node_or_null("/root/Main/BoardRoot")
		if board_root:
			var mouse_pos = board_root.get_local_mouse_position()
			print("DEBUG: Mouse click at board position: ", mouse_pos)
			_handle_board_click(mouse_pos)

func _handle_movement_click(position: Vector2) -> void:
	var unit_id = ""
	var movement_type = ""
	
	if pending_pile_in_unit != "":
		unit_id = pending_pile_in_unit
		movement_type = "PILE_IN"
		pending_pile_in_unit = ""
	elif pending_consolidate_unit != "":
		unit_id = pending_consolidate_unit
		movement_type = "CONSOLIDATE"  
		pending_consolidate_unit = ""
	else:
		return
	
	# Send movement action to phase
	emit_signal("fight_action_requested", {
		"type": movement_type,
		"actor_unit_id": unit_id,
		"position": {"x": position.x, "y": position.y}
	})
	
	if dice_log_display:
		var unit_name = current_phase.get_unit(unit_id).get("meta", {}).get("name", unit_id)
		dice_log_display.append_text("[color=green]✓ %s movement for %s[/color]\n" % [movement_type.capitalize(), unit_name])

func _handle_board_click(position: Vector2) -> void:
	# First check if we have a weapon selected
	if not attack_tree:
		print("DEBUG: No attack tree")
		return
		
	var selected_weapon = attack_tree.get_selected()
	if not selected_weapon:
		if dice_log_display:
			dice_log_display.append_text("[color=red]Please select a melee weapon first![/color]\n")
		print("DEBUG: No weapon selected")
		return
	
	# Check if click is on an eligible target
	var closest_target = ""
	var closest_distance = INF
	
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
	
	# Use a click threshold to make selection easier
	if closest_target != "" and closest_distance < 100:
		print("DEBUG: Selecting target: ", closest_target, " at distance: ", closest_distance)
		_select_target_for_current_weapon(closest_target)
	else:
		print("DEBUG: No target close enough. Closest was: ", closest_target, " at distance: ", closest_distance)
		
		# If no target is close enough, auto-select the first available target
		if not eligible_targets.is_empty():
			var first_target = eligible_targets.keys()[0]
			print("DEBUG: Auto-selecting first available target: ", first_target)
			_select_target_for_current_weapon(first_target)

func _select_target_for_current_weapon(target_id: String) -> void:
	# Get currently selected weapon from tree
	if not attack_tree:
		return
	
	var selected = attack_tree.get_selected()
	if not selected:
		return
	
	var metadata = selected.get_metadata(0)
	if not metadata:
		return
	
	# Handle both old format (string) and new format (dictionary)
	var weapon_id = ""
	var weapon_model_id = ""
	if metadata is String:
		weapon_id = metadata
	elif metadata is Dictionary:
		weapon_id = metadata.get("weapon_id", "")
		weapon_model_id = metadata.get("model_id", "")
	
	if not weapon_id:
		return
	
	# Get model IDs for this weapon
	var model_ids = []
	if weapon_model_id:
		# If we have a specific model ID from metadata, use it
		model_ids.append(weapon_model_id)
	else:
		# Otherwise find all models with this weapon
		var unit_weapons = RulesEngine.get_unit_melee_weapons(current_fighter_id)
		for model_id in unit_weapons:
			if weapon_id in unit_weapons[model_id]:
				model_ids.append(model_id)
	
	emit_signal("fight_action_requested", {
		"type": "ASSIGN_ATTACKS",
		"unit_id": current_fighter_id,
		"target_id": target_id,
		"weapon_id": weapon_id,
		"attacking_models": model_ids
	})
	
	# Update UI
	var target_name = eligible_targets.get(target_id, {}).get("unit_name", target_id)
	selected.set_text(1, target_name)
	selected.set_custom_bg_color(1, Color(0.4, 0.2, 0.2, 0.5))  # Red background for assigned target
	
	# Update target basket
	target_basket.add_item("%s → %s" % [RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id), target_name])
	
	# Show feedback
	if dice_log_display:
		var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		dice_log_display.append_text("[color=green]✓ Assigned %s attacks to %s[/color]\n" % [weapon_name, target_name])

	_update_ui_state()

# New dialog handler functions for subphase system
func _on_fight_selection_required(data: Dictionary) -> void:
	"""Show fight selection dialog when phase requests it"""
	print("DEBUG: FightController._on_fight_selection_required called")
	print("DEBUG: Dialog data: subphase=%s, player=%d, eligible=%d" % [
		data.get("current_subphase", "?"),
		data.get("selecting_player", 0),
		data.get("eligible_units", {}).size()
	])

	# Close any existing fight selection dialog first (for multiplayer sync)
	# Find and close existing dialogs that might be open
	for child in get_tree().root.get_children():
		if child is AcceptDialog and child.get_script() == load("res://dialogs/FightSelectionDialog.gd"):
			print("DEBUG: Closing existing fight selection dialog")
			child.queue_free()

	# Load the dialog script
	var dialog_script = load("res://dialogs/FightSelectionDialog.gd")
	if not dialog_script:
		push_error("Failed to load FightSelectionDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(data, current_phase)
	dialog.fighter_selected.connect(_on_fighter_selected_from_dialog)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("DEBUG: Fight selection dialog shown")

func _on_fighter_selected_from_dialog(unit_id: String) -> void:
	"""Submit SELECT_FIGHTER action when unit selected from dialog"""
	# Get the unit's owner as the player, not the active player
	# In Fight Phase, the selecting player may not be the active player
	var unit = GameState.get_unit(unit_id)
	var player_id = unit.get("owner", GameState.get_active_player())

	# Store for subsequent actions in this activation
	current_fighter_id = unit_id
	current_fighter_owner = player_id

	var action = {
		"type": "SELECT_FIGHTER",
		"unit_id": unit_id,
		"player": player_id
	}
	emit_signal("fight_action_requested", action)

func _on_pile_in_required(unit_id: String, max_distance: float) -> void:
	"""Show pile-in dialog and enable interactive movement"""
	var dialog_script = load("res://dialogs/PileInDialog.gd")
	if not dialog_script:
		push_error("Failed to load PileInDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(unit_id, max_distance, current_phase, self)  # Pass controller reference
	dialog.pile_in_confirmed.connect(_on_pile_in_confirmed.bind(unit_id))
	dialog.pile_in_skipped.connect(_on_pile_in_skipped.bind(unit_id))
	dialog.tree_exiting.connect(_on_pile_in_dialog_closed)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	# Enable pile-in mode
	_enable_pile_in_mode(unit_id, dialog)

func _on_pile_in_confirmed(movements: Dictionary, unit_id: String) -> void:
	"""Submit PILE_IN action with movements"""
	print("[FightController] Pile-in confirmed with movements: ", movements)

	# Convert model IDs from "m1" format to array indices "0" format for FightPhase
	var converted_movements = {}
	if not movements.is_empty() and current_phase:
		var unit = current_phase.get_unit(unit_id)
		if unit:
			var models = unit.get("models", [])
			for model_id in movements:
				# Find the array index for this model_id
				for i in range(models.size()):
					if models[i].get("id", "") == model_id:
						converted_movements[str(i)] = movements[model_id]
						print("[FightController] Converted ", model_id, " to index ", i)
						break

	print("[FightController] Converted movements: ", converted_movements)

	var action = {
		"type": "PILE_IN",
		"unit_id": unit_id,
		"movements": converted_movements,
		"player": current_fighter_owner
	}
	emit_signal("fight_action_requested", action)

func _on_pile_in_skipped(unit_id: String) -> void:
	"""Submit PILE_IN action with no movements"""
	_on_pile_in_confirmed({}, unit_id)

func _on_attack_assignment_required(unit_id: String, targets: Dictionary) -> void:
	"""Show attack assignment dialog"""
	print("[FightController] Attack assignment required for ", unit_id)
	print("[FightController] Eligible targets: ", targets.keys())

	# Wait for previous dialog to close
	await get_tree().create_timer(0.3).timeout

	print("[FightController] Loading AttackAssignmentDialog...")
	var dialog_script = load("res://dialogs/AttackAssignmentDialog.gd")
	if not dialog_script:
		push_error("Failed to load AttackAssignmentDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	print("[FightController] Setting up dialog...")
	dialog.setup(unit_id, targets, current_phase)
	dialog.attacks_confirmed.connect(_on_attacks_confirmed)
	get_tree().root.add_child(dialog)
	print("[FightController] Showing attack assignment dialog...")
	dialog.popup_centered()

func _on_attacks_confirmed(assignments: Array) -> void:
	"""Submit attack assignments and trigger resolution"""
	print("[FightController] Attacks confirmed, processing %d assignments" % assignments.size())

	# First, send individual ASSIGN_ATTACKS actions to populate pending_attacks
	for assignment in assignments:
		var assign_action = {
			"type": "ASSIGN_ATTACKS",
			"unit_id": assignment.get("attacker", ""),
			"target_id": assignment.get("target", ""),
			"weapon_id": assignment.get("weapon", ""),
			"attacking_models": assignment.get("models", []),
			"player": current_fighter_owner
		}
		print("[FightController] Sending ASSIGN_ATTACKS: ", assign_action)
		emit_signal("fight_action_requested", assign_action)
		# Small delay to ensure actions process in order
		await get_tree().create_timer(0.05).timeout

	# Now confirm the attacks
	var confirm_action = {
		"type": "CONFIRM_AND_RESOLVE_ATTACKS",
		"player": current_fighter_owner
	}
	print("[FightController] Sending CONFIRM_AND_RESOLVE_ATTACKS")
	emit_signal("fight_action_requested", confirm_action)

	# Then trigger dice rolling
	var roll_action = {
		"type": "ROLL_DICE",
		"player": current_fighter_owner
	}
	# Delay slightly to let confirmation process
	await get_tree().create_timer(0.1).timeout
	print("[FightController] Sending ROLL_DICE")
	emit_signal("fight_action_requested", roll_action)

func _on_consolidate_required(unit_id: String, max_distance: float) -> void:
	"""Show consolidate dialog and enable interactive movement"""
	var dialog_script = load("res://dialogs/ConsolidateDialog.gd")
	if not dialog_script:
		push_error("Failed to load ConsolidateDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(unit_id, max_distance, current_phase, self)  # Pass controller reference
	dialog.consolidate_confirmed.connect(_on_consolidate_confirmed.bind(unit_id))
	dialog.consolidate_skipped.connect(_on_consolidate_skipped.bind(unit_id))
	dialog.tree_exiting.connect(_on_consolidate_dialog_closed)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	# Enable consolidate mode (uses same system as pile-in)
	_enable_consolidate_mode(unit_id, dialog)

func _on_consolidate_confirmed(movements: Dictionary, unit_id: String) -> void:
	"""Submit CONSOLIDATE action with movements"""
	print("[FightController] Consolidate confirmed with movements: ", movements)

	# Convert model IDs from "m1" format to array indices "0" format for FightPhase
	var converted_movements = {}
	if not movements.is_empty() and current_phase:
		var unit = current_phase.get_unit(unit_id)
		if unit:
			var models = unit.get("models", [])
			for model_id in movements:
				# Find the array index for this model_id
				for i in range(models.size()):
					if models[i].get("id", "") == model_id:
						converted_movements[str(i)] = movements[model_id]
						print("[FightController] Converted ", model_id, " to index ", i)
						break

	print("[FightController] Converted movements: ", converted_movements)

	var action = {
		"type": "CONSOLIDATE",
		"unit_id": unit_id,
		"movements": converted_movements,
		"player": current_fighter_owner
	}
	emit_signal("fight_action_requested", action)

	# Clear tracking after activation complete
	current_fighter_id = ""
	current_fighter_owner = -1

func _on_consolidate_skipped(unit_id: String) -> void:
	"""Submit CONSOLIDATE action with no movements"""
	_on_consolidate_confirmed({}, unit_id)

func _on_subphase_transition(from_subphase: String, to_subphase: String) -> void:
	"""Show notification when transitioning between subphases"""
	if dice_log_display:
		dice_log_display.append_text("\n[color=yellow]=== %s Complete ===[/color]\n" % from_subphase)
		dice_log_display.append_text("[color=yellow]Starting %s...[/color]\n\n" % to_subphase)

func _on_attack_assigned(attacker_id: String, target_id: String, weapon_id: String) -> void:
	"""Display attack assignment to both host and client"""
	print("[FightController] Attack assigned: %s → %s with %s" % [attacker_id, target_id, weapon_id])

	# Get unit names for display
	var attacker = current_phase.get_unit(attacker_id) if current_phase else {}
	var target = current_phase.get_unit(target_id) if current_phase else {}
	var attacker_name = attacker.get("meta", {}).get("name", attacker_id)
	var target_name = target.get("meta", {}).get("name", target_id)

	# Get weapon name (convert ID back to display name)
	var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
	var weapon_name = weapon_profile.get("name", weapon_id)

	# Show in dice log for both players
	if dice_log_display:
		dice_log_display.append_text("[color=green]✓ %s assigned %s attacks to %s[/color]\n" % [attacker_name, weapon_name, target_name])

# ============================================================================
# PILE-IN/CONSOLIDATE INTERACTIVE MODE
# ============================================================================

func _enable_pile_in_mode(unit_id: String, dialog: Node) -> void:
	"""Enable interactive pile-in mode for the unit"""
	pile_in_active = true
	pile_in_unit_id = unit_id
	pile_in_dialog_ref = dialog

	# Store original positions for all models in the unit
	var unit = current_phase.get_unit(unit_id) if current_phase else null
	if not unit:
		push_error("Failed to get unit for pile-in: " + unit_id)
		return

	original_model_positions.clear()
	current_model_positions.clear()

	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		var pos_data = model.get("position", {})
		if pos_data == null:
			continue
		var pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
		# Use the model's actual ID (e.g., "m1", "m2") not the array index
		var model_id = model.get("id", "m%d" % (i+1))
		original_model_positions[model_id] = pos
		current_model_positions[model_id] = pos
		print("[FightController] Stored position for model ", model_id, " at ", pos)

	# Create visual indicators
	_create_pile_in_visuals()

	print("[FightController] Pile-in mode enabled for ", unit_id)

func _disable_pile_in_mode() -> void:
	"""Disable pile-in mode and clean up"""
	print("[FightController] _disable_pile_in_mode called - STACK TRACE:")
	print_stack()

	pile_in_active = false
	consolidate_active = false
	pile_in_unit_id = ""
	pile_in_dialog_ref = null
	original_model_positions.clear()
	current_model_positions.clear()
	dragging_model = null
	drag_model_id = ""

	# Clean up visual indicators
	_clear_pile_in_visuals()

	print("[FightController] Pile-in mode disabled")

func _on_pile_in_dialog_closed() -> void:
	"""Handle pile-in dialog being closed"""
	_disable_pile_in_mode()

func _create_pile_in_visuals() -> void:
	"""Create visual indicators for pile-in movement"""
	_clear_pile_in_visuals()

	if not board_view:
		return

	# Create container for all pile-in visuals
	pile_in_visuals = Node2D.new()
	pile_in_visuals.name = "PileInVisuals"
	pile_in_visuals.z_index = 100  # Draw on top
	board_view.add_child(pile_in_visuals)

	# Create range circles for each model (3" radius)
	for model_id in original_model_positions:
		var pos = original_model_positions[model_id]
		var circle = _create_range_circle(pos, 3.0)
		circle.name = "RangeCircle_" + model_id
		pile_in_visuals.add_child(circle)
		range_circles[model_id] = circle

	# Create direction lines for each model
	for model_id in original_model_positions:
		var line = Line2D.new()
		line.width = 2.0
		line.default_color = Color.YELLOW
		line.name = "DirectionLine_" + model_id
		pile_in_visuals.add_child(line)
		direction_lines[model_id] = line

	# Update visuals to show initial state
	_update_pile_in_visuals()

func _create_range_circle(center: Vector2, radius_inches: float) -> Node2D:
	"""Create a circle showing movement range"""
	var circle = Node2D.new()
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.3, 0.6, 1.0, 0.5)  # Light blue, semi-transparent

	# Create circle points
	var radius_px = Measurement.inches_to_px(radius_inches)
	var num_points = 64
	for i in range(num_points + 1):
		var angle = (i / float(num_points)) * TAU
		var point = center + Vector2(cos(angle), sin(angle)) * radius_px
		line.add_point(point)

	circle.add_child(line)
	return circle

func _clear_pile_in_visuals() -> void:
	"""Remove all pile-in visual indicators"""
	if pile_in_visuals and is_instance_valid(pile_in_visuals):
		pile_in_visuals.queue_free()
		pile_in_visuals = null

	range_circles.clear()
	direction_lines.clear()
	coherency_lines.clear()

func _update_pile_in_visuals() -> void:
	"""Update visual feedback for current model positions"""
	if not pile_in_active or not current_phase:
		return

	# Update direction lines
	for model_id in current_model_positions:
		if not direction_lines.has(model_id):
			continue

		var line = direction_lines[model_id]
		var current_pos = current_model_positions[model_id]
		var original_pos = original_model_positions.get(model_id, current_pos)

		# Find closest enemy position
		var closest_enemy = _find_closest_enemy_pos(current_pos)

		# Draw line from current position to closest enemy
		line.clear_points()
		if closest_enemy != Vector2.ZERO:
			line.add_point(current_pos)
			line.add_point(closest_enemy)

			# Color based on whether movement is valid (closer to enemy)
			var original_dist = original_pos.distance_to(closest_enemy)
			var current_dist = current_pos.distance_to(closest_enemy)
			var is_closer = current_dist <= original_dist

			# Validate distance limit
			var move_distance = Measurement.distance_inches(original_pos, current_pos)
			var distance_ok = move_distance <= 3.0

			# Set color based on validation
			if is_closer and distance_ok:
				line.default_color = Color.GREEN
			else:
				line.default_color = Color.RED

	# Update coherency lines (show connections between models)
	_update_coherency_visuals()

func _update_coherency_visuals() -> void:
	"""Update coherency lines between models"""
	# Clear old coherency lines
	for line in coherency_lines:
		if is_instance_valid(line):
			line.queue_free()
	coherency_lines.clear()

	if not pile_in_visuals or not is_instance_valid(pile_in_visuals):
		return

	# Create lines showing 2" coherency connections
	var positions = current_model_positions.values()
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var pos1 = positions[i]
			var pos2 = positions[j]
			var dist = Measurement.distance_inches(pos1, pos2)

			if dist <= 2.0:  # Within coherency range
				var line = Line2D.new()
				line.width = 1.0
				line.default_color = Color(0.0, 1.0, 0.0, 0.3)  # Green, transparent
				line.add_point(pos1)
				line.add_point(pos2)
				pile_in_visuals.add_child(line)
				coherency_lines.append(line)

func _find_closest_enemy_pos(from_pos: Vector2) -> Vector2:
	"""Find the closest enemy model position"""
	if not current_phase or pile_in_unit_id == "":
		return Vector2.ZERO

	var unit = current_phase.get_unit(pile_in_unit_id)
	var unit_owner = unit.get("owner", 0)
	var all_units = current_phase.game_state_snapshot.get("units", {})
	var closest_pos = Vector2.ZERO
	var closest_distance = INF

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit.get("owner", 0) == unit_owner:
			continue  # Skip same army

		var models = other_unit.get("models", [])
		for model in models:
			if not model.get("alive", true):
				continue

			var model_pos_data = model.get("position", {})
			if model_pos_data == null:
				continue
			var model_pos = Vector2(model_pos_data.get("x", 0), model_pos_data.get("y", 0))
			var distance = from_pos.distance_to(model_pos)

			if distance < closest_distance:
				closest_distance = distance
				closest_pos = model_pos

	return closest_pos

func _find_closest_objective_pos(from_pos: Vector2, objectives: Array) -> Vector2:
	"""Find the closest objective marker position"""
	var closest_pos = Vector2.ZERO
	var closest_distance = INF

	for objective in objectives:
		var obj_pos = objective.get("position", Vector2.ZERO)
		if obj_pos == Vector2.ZERO:
			continue

		var distance = from_pos.distance_to(obj_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_pos = obj_pos

	return closest_pos

func get_pile_in_movements() -> Dictionary:
	"""Get current movements for submission"""
	var movements = {}
	for model_id in current_model_positions:
		if current_model_positions[model_id] != original_model_positions[model_id]:
			movements[model_id] = current_model_positions[model_id]
	return movements

func reset_pile_in_movements() -> void:
	"""Reset all model positions to original"""
	print("[FightController] reset_pile_in_movements called - STACK TRACE:")
	print_stack()

	for model_id in original_model_positions:
		current_model_positions[model_id] = original_model_positions[model_id]

	# Move visual models back to original positions
	_apply_model_positions_to_scene()
	_update_pile_in_visuals()

	print("[FightController] Pile-in movements reset")

func _apply_model_positions_to_scene() -> void:
	"""Apply current_model_positions to the actual model tokens in the scene"""
	if pile_in_unit_id == "":
		return

	# Get token layer
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if not token_layer:
		return

	# Update each model token's position
	for model_id in current_model_positions:
		# Find the token with matching metadata
		for token in token_layer.get_children():
			if token.has_meta("unit_id") and token.has_meta("model_id"):
				if token.get_meta("unit_id") == pile_in_unit_id and token.get_meta("model_id") == model_id:
					token.position = current_model_positions[model_id]
					break

func _handle_pile_in_input(event: InputEvent) -> void:
	"""Handle input events during pile-in mode"""
	if not board_view:
		print("[FightController] Pile-in input: no board_view")
		return

	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		print("[FightController] Pile-in input: no board_root")
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start dragging
			var mouse_pos = board_root.get_local_mouse_position()
			print("[FightController] Mouse down at: ", mouse_pos)
			_start_model_drag_pile_in(mouse_pos)
		else:
			# End dragging
			print("[FightController] Mouse up")
			_end_model_drag_pile_in()
	elif event is InputEventMouseMotion and dragging_model:
		# Update drag
		var mouse_pos = board_root.get_local_mouse_position()
		_update_model_drag_pile_in(mouse_pos)

func _start_model_drag_pile_in(mouse_pos: Vector2) -> void:
	"""Start dragging a model during pile-in"""
	print("[FightController] _start_model_drag_pile_in called, pile_in_unit_id=", pile_in_unit_id)

	if pile_in_unit_id == "":
		print("[FightController] No pile_in_unit_id")
		return

	# Get token layer from BoardRoot
	var token_layer = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if not token_layer:
		print("[FightController] Could not find TokenLayer")
		return

	print("[FightController] Checking ", current_model_positions.size(), " models")

	# Find which model token is being clicked
	# Models are individual TokenVisual nodes in token_layer with metadata
	for model_id in current_model_positions:
		var model_pos = current_model_positions[model_id]
		var distance_to_mouse = mouse_pos.distance_to(model_pos)

		print("[FightController] Model ", model_id, " at ", model_pos, " distance: ", distance_to_mouse)

		# Check if click is within model's base (50px radius for easier clicking)
		if distance_to_mouse < 50.0:
			print("[FightController] Distance check passed! Looking for token with unit_id=", pile_in_unit_id, " model_id=", model_id)
			# Find the actual token in token_layer with matching metadata
			var tokens_checked = 0
			for token in token_layer.get_children():
				tokens_checked += 1
				if token.has_meta("unit_id") and token.has_meta("model_id"):
					var token_unit_id = token.get_meta("unit_id")
					var token_model_id = token.get_meta("model_id")
					print("[FightController]   Token ", tokens_checked, ": unit_id=", token_unit_id, " model_id=", token_model_id)

					if token_unit_id == pile_in_unit_id and token_model_id == model_id:
						dragging_model = token
						drag_model_id = model_id
						drag_start_pos = model_pos
						drag_offset = model_pos - mouse_pos

						print("[FightController] Started dragging model token ", model_id)
						return

			print("[FightController] Checked ", tokens_checked, " tokens but none matched")

	print("[FightController] No model found near click position")

func _update_model_drag_pile_in(mouse_pos: Vector2) -> void:
	"""Update model position during drag"""
	if drag_model_id == "" or not dragging_model:
		return

	var new_pos = mouse_pos + drag_offset

	# Update position tracking
	current_model_positions[drag_model_id] = new_pos

	# Update visual position
	if dragging_model:
		dragging_model.position = new_pos

	# Check for overlaps and update visual feedback
	var has_overlap = _check_model_overlaps(drag_model_id, new_pos)
	_update_model_overlap_visual(dragging_model, has_overlap)

	# Update visual indicators
	_update_pile_in_visuals()

	# Update dialog with current movements if possible
	if pile_in_dialog_ref and pile_in_dialog_ref.has_method("update_movements"):
		pile_in_dialog_ref.update_movements(get_pile_in_movements())

func _end_model_drag_pile_in() -> void:
	"""End model drag"""
	if drag_model_id == "":
		return

	print("[FightController] Ended dragging model ", drag_model_id)

	var original_pos = original_model_positions.get(drag_model_id, Vector2.ZERO)
	var final_pos = current_model_positions[drag_model_id]
	var reverted = false

	# Check for overlaps - if overlapping, revert to original position
	if _check_model_overlaps(drag_model_id, final_pos):
		print("[FightController] Model would overlap - reverting to original position")
		current_model_positions[drag_model_id] = original_pos
		if dragging_model:
			dragging_model.position = original_pos
		reverted = true
	else:
		# Validate final position
		var distance = Measurement.distance_inches(original_pos, final_pos)

		# Check if model moved at all
		if distance > 0.01:  # Threshold to detect actual movement
			# For consolidate, check which mode applies
			if consolidate_active and current_phase:
				var unit = current_phase.get_unit(pile_in_unit_id)
				var can_reach_engagement = current_phase._can_unit_reach_engagement_range(unit) if current_phase.has_method("_can_unit_reach_engagement_range") else true

				if can_reach_engagement:
					# ENGAGEMENT mode - must move toward enemy
					var closest_enemy_pos = _find_closest_enemy_pos(original_pos)
					if closest_enemy_pos != Vector2.ZERO:
						var old_distance_to_enemy = original_pos.distance_to(closest_enemy_pos)
						var new_distance_to_enemy = final_pos.distance_to(closest_enemy_pos)

						if new_distance_to_enemy >= old_distance_to_enemy:
							print("[FightController] Model not moving closer to enemy - reverting to original position")
							print("  Old distance: %.2f\", New distance: %.2f\"" % [
								Measurement.px_to_inches(old_distance_to_enemy),
								Measurement.px_to_inches(new_distance_to_enemy)
							])
							current_model_positions[drag_model_id] = original_pos
							if dragging_model:
								dragging_model.position = original_pos
							reverted = true
				else:
					# OBJECTIVE mode - must move toward objective
					var objectives = GameState.state.board.get("objectives", [])
					if not objectives.is_empty():
						var closest_obj_pos = _find_closest_objective_pos(original_pos, objectives)
						if closest_obj_pos != Vector2.ZERO:
							var old_distance_to_obj = original_pos.distance_to(closest_obj_pos)
							var new_distance_to_obj = final_pos.distance_to(closest_obj_pos)

							if new_distance_to_obj >= old_distance_to_obj:
								print("[FightController] Model not moving closer to objective - reverting to original position")
								print("  Old distance: %.2f\", New distance: %.2f\"" % [
									Measurement.px_to_inches(old_distance_to_obj),
									Measurement.px_to_inches(new_distance_to_obj)
								])
								current_model_positions[drag_model_id] = original_pos
								if dragging_model:
									dragging_model.position = original_pos
								reverted = true
			else:
				# Pile-in mode - always check toward enemy
				var closest_enemy_pos = _find_closest_enemy_pos(original_pos)
				if closest_enemy_pos != Vector2.ZERO:
					var old_distance_to_enemy = original_pos.distance_to(closest_enemy_pos)
					var new_distance_to_enemy = final_pos.distance_to(closest_enemy_pos)

					if new_distance_to_enemy >= old_distance_to_enemy:
						print("[FightController] Model not moving closer to enemy - reverting to original position")
						print("  Old distance: %.2f\", New distance: %.2f\"" % [
							Measurement.px_to_inches(old_distance_to_enemy),
							Measurement.px_to_inches(new_distance_to_enemy)
						])
						current_model_positions[drag_model_id] = original_pos
						if dragging_model:
							dragging_model.position = original_pos
						reverted = true

		# If not reverted, check distance limits
		if not reverted:
			# Check if movement exceeds 3"
			if distance > 3.0:
				# Snap back to maximum 3" distance in the same direction
				var direction = (final_pos - original_pos).normalized()
				var max_distance_px = Measurement.inches_to_px(3.0)
				var clamped_pos = original_pos + direction * max_distance_px
				current_model_positions[drag_model_id] = clamped_pos

				if dragging_model:
					dragging_model.position = clamped_pos

				print("[FightController] Clamped movement to 3\" limit")

	# Clear overlap visual feedback
	if dragging_model:
		_update_model_overlap_visual(dragging_model, false)

	# Clear drag state
	dragging_model = null
	drag_model_id = ""
	drag_start_pos = Vector2.ZERO

	# Final visual update
	_update_pile_in_visuals()

	# Update dialog
	if pile_in_dialog_ref and pile_in_dialog_ref.has_method("update_movements"):
		pile_in_dialog_ref.update_movements(get_pile_in_movements())

func _enable_consolidate_mode(unit_id: String, dialog: Node) -> void:
	"""Enable interactive consolidate mode (uses same system as pile-in)"""
	consolidate_active = true
	# Reuse the pile-in infrastructure
	_enable_pile_in_mode(unit_id, dialog)
	print("[FightController] Consolidate mode enabled for ", unit_id)

func _on_consolidate_dialog_closed() -> void:
	"""Handle consolidate dialog being closed"""
	_disable_pile_in_mode()

func _check_model_overlaps(moving_model_id: String, new_pos: Vector2) -> bool:
	"""Check if a model at the given position would overlap with any other models"""
	if not current_phase or pile_in_unit_id == "":
		return false

	# Get the moving model's data
	var unit = current_phase.get_unit(pile_in_unit_id)
	if not unit:
		return false

	var models = unit.get("models", [])
	var moving_model = null
	for model in models:
		if model.get("id", "") == moving_model_id:
			moving_model = model
			break

	if not moving_model:
		return false

	# Create a temporary model dict with the new position for overlap checking
	var check_model = moving_model.duplicate()
	check_model["position"] = new_pos

	# Check against all other models in all units
	var all_units = current_phase.game_state_snapshot.get("units", {})
	for check_unit_id in all_units:
		var check_unit = all_units[check_unit_id]
		var check_models = check_unit.get("models", [])

		for i in range(check_models.size()):
			var other_model = check_models[i]

			# Skip self
			if check_unit_id == pile_in_unit_id and other_model.get("id", "") == moving_model_id:
				continue

			# Skip dead models
			if not other_model.get("alive", true):
				continue

			# Use position from current_model_positions if this is a friendly model being moved
			var other_pos = other_model.get("position", {})
			if other_pos == null:
				continue

			var other_model_check = other_model.duplicate()
			if check_unit_id == pile_in_unit_id:
				var other_id = other_model.get("id", "")
				if other_id in current_model_positions:
					other_model_check["position"] = current_model_positions[other_id]

			# Check for overlap using Measurement system
			if Measurement.models_overlap(check_model, other_model_check):
				print("[FightController] Overlap detected with ", check_unit_id, "/", other_model.get("id", ""))
				return true

	return false

func _update_model_overlap_visual(token: Node2D, has_overlap: bool) -> void:
	"""Update visual feedback to show if a model is overlapping"""
	if not token:
		return

	# Change the model's modulate color to indicate overlap
	if has_overlap:
		token.modulate = Color(1.0, 0.3, 0.3, 1.0)  # Red tint
	else:
		token.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal
