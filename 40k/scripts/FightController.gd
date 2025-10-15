extends Node2D
class_name FightController

# FightController - Handles UI interactions for the Fight Phase
# Manages fight sequencing, pile in/consolidate movement, attack assignment

signal fight_action_requested(action: Dictionary)
signal fighter_preview_updated(unit_id: String, valid: bool)
signal ui_update_requested()

# Fight state
var current_phase = null  # Can be FightPhase or null
var current_fighter_id: String = ""
var eligible_targets: Dictionary = {}  # target_unit_id -> target_data
var fight_sequence: Array = []  # Units in fight order
var current_fight_index: int = -1
var pending_pile_in_unit: String = ""
var pending_consolidate_unit: String = ""

# UI References
var board_view: Node2D
var movement_visual: Line2D
var range_visual: Node2D
var target_highlights: Node2D
var hud_bottom: Control
var hud_right: Control

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
		
		print("DEBUG: FightController signals connected, setting up UI")
		
		# Ensure UI is set up after phase assignment
		_setup_ui_references()
		
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
	var rolls = dice_data.get("rolls_raw", [])
	var successes = dice_data.get("successes", 0)
	
	var log_text = "[b]%s:[/b] %s → %d successes\n" % [context.capitalize(), str(rolls), successes]
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
	
	# Handle pile in or consolidate movement
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
	
	# Update target basket
	target_basket.add_item("%s → %s" % [RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id), target_name])
	
	# Show feedback
	if dice_log_display:
		var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		dice_log_display.append_text("[color=green]✓ Assigned %s attacks to %s[/color]\n" % [weapon_name, target_name])
	
	_update_ui_state()
