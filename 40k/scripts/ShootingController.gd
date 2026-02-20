extends Node2D
class_name ShootingController

const BasePhase = preload("res://phases/BasePhase.gd")


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
var assignment_history: Array = []  # T5-UX4: Stack of weapon_ids in assignment order for undo
var selected_weapon_id: String = ""  # Currently selected weapon for modifier display
var save_dialog_showing: bool = false  # Prevent multiple dialogs
var current_save_context: Dictionary = {}  # Track what we're showing dialog for (weapon, target)
var active_allocation_overlay: WoundAllocationOverlay = null  # Track active overlay instance
var processing_saves_signal: bool = false  # Flag to prevent re-entrant signal calls

# T5-MP4: Save dialog timing reliability
var _save_processing_timeout_timer: Timer = null  # Safety timer to reset processing_saves_signal
var _awaiting_remote_saves: bool = false  # True on attacker side while waiting for defender saves
var _pending_save_data_for_retry: Array = []  # Cached save data for potential retry
var _save_ack_received: bool = false  # Whether defender acknowledged receiving save dialog
const SAVE_PROCESSING_TIMEOUT_SEC: float = 10.0  # Max time for processing_saves_signal to stay true
const SAVE_ACK_TIMEOUT_SEC: float = 8.0  # Time to wait for defender acknowledgment before retry

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
var undo_button: Button  # T5-UX4: Undo last weapon assignment
var dice_log_display: RichTextLabel
var dice_roll_visual: DiceRollVisual  # T5-V1: Animated dice roll visualization
var auto_target_button_container: HBoxContainer  # Reference to auto-target UI
var last_assigned_target_id: String = ""  # Track last assigned target for "Apply to All"
var grenade_button: Button  # GRENADE stratagem button

# Modifier UI elements (Phase 1 MVP)
var modifier_panel: VBoxContainer
var modifier_label: Label
var reroll_ones_checkbox: CheckBox
var plus_one_checkbox: CheckBox
var minus_one_checkbox: CheckBox

# T5-MP3: Remote player visual feedback
var shooting_lines_container: Node2D  # Container for shooter-to-target visual lines
var remote_assignment_lines: Array = []  # Track remote assignment Line2D nodes

# T5-UX1: Expected damage preview when hovering weapons
var damage_preview_panel: PanelContainer
var damage_preview_label: RichTextLabel
var _hovered_weapon_id: String = ""  # Track which weapon is being hovered
var _last_preview_weapon_id: String = ""  # Cache to avoid redundant recalculation
var _last_preview_target_id: String = ""  # Cache target for recalculation check

# Visual settings
const HIGHLIGHT_COLOR_ELIGIBLE = Color.GREEN
const HIGHLIGHT_COLOR_INELIGIBLE = Color.GRAY
const HIGHLIGHT_COLOR_SELECTED = Color.YELLOW
const LOS_LINE_COLOR = Color.RED
const LOS_LINE_WIDTH = 2.0
const SHOOTING_LINE_COLOR = Color(1.0, 0.5, 0.0, 0.8)  # Orange for shooting lines
const SHOOTING_LINE_WIDTH = 3.0

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)  # Keep both for safety
	_setup_ui_references()
	_create_shooting_visuals()
	# T5-MP4: Setup save processing timeout timer
	_save_processing_timeout_timer = Timer.new()
	_save_processing_timeout_timer.one_shot = true
	_save_processing_timeout_timer.timeout.connect(_on_save_processing_timeout)
	add_child(_save_processing_timeout_timer)
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

	# T5-MP3: Clean up shooting lines container
	if shooting_lines_container and is_instance_valid(shooting_lines_container):
		shooting_lines_container.queue_free()
	remote_assignment_lines.clear()

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

	# T5-MP3: Create container for shooter-to-target visual lines (remote player feedback)
	shooting_lines_container = Node2D.new()
	shooting_lines_container.name = "ShootingLinesContainer"
	board_root.add_child(shooting_lines_container)

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
	
	# Ensure the shooting_panel exists and is valid
	if not shooting_panel:
		push_error("ShootingController: shooting_panel is null!")
		return

	# Make sure panel is visible
	shooting_panel.visible = true
	scroll_container.visible = true

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

	# Create "Apply to All" button container (initially hidden)
	auto_target_button_container = HBoxContainer.new()
	auto_target_button_container.name = "AutoTargetContainer"
	auto_target_button_container.visible = false  # Hidden until first weapon assigned

	var auto_target_label = Label.new()
	auto_target_label.text = "Same target for all:"
	auto_target_button_container.add_child(auto_target_label)

	var apply_to_all_button = Button.new()
	apply_to_all_button.name = "ApplyToAllButton"
	apply_to_all_button.text = "Apply to All Weapons"
	apply_to_all_button.custom_minimum_size = Vector2(150, 30)
	apply_to_all_button.pressed.connect(_on_apply_to_all_pressed)
	auto_target_button_container.add_child(apply_to_all_button)

	shooting_panel.add_child(auto_target_button_container)

	weapon_tree = Tree.new()
	weapon_tree.custom_minimum_size = Vector2(230, 120)
	weapon_tree.columns = 2
	weapon_tree.set_column_title(0, "Weapon")
	weapon_tree.set_column_title(1, "Target")
	weapon_tree.hide_root = true
	weapon_tree.item_selected.connect(_on_weapon_tree_item_selected)
	weapon_tree.button_clicked.connect(_on_weapon_tree_button_clicked)
	# T5-UX1: Connect gui_input for hover detection and mouse_exited for cleanup
	weapon_tree.gui_input.connect(_on_weapon_tree_gui_input)
	weapon_tree.mouse_exited.connect(_on_weapon_tree_mouse_exited)
	shooting_panel.add_child(weapon_tree)

	# T5-UX1: Expected damage preview panel (shown on weapon hover/select)
	damage_preview_panel = PanelContainer.new()
	damage_preview_panel.name = "DamagePreviewPanel"
	damage_preview_panel.custom_minimum_size = Vector2(230, 0)
	damage_preview_panel.visible = false  # Hidden until a weapon is hovered
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	preview_style.border_color = Color(0.833, 0.588, 0.376, 0.6)  # WH_GOLD with alpha
	preview_style.set_border_width_all(1)
	preview_style.set_content_margin_all(6)
	preview_style.set_corner_radius_all(3)
	damage_preview_panel.add_theme_stylebox_override("panel", preview_style)
	damage_preview_label = RichTextLabel.new()
	damage_preview_label.bbcode_enabled = true
	damage_preview_label.fit_content = true
	damage_preview_label.scroll_active = false
	damage_preview_label.custom_minimum_size = Vector2(218, 0)
	damage_preview_label.add_theme_font_size_override("normal_font_size", 11)
	damage_preview_panel.add_child(damage_preview_label)
	shooting_panel.add_child(damage_preview_panel)

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

	# GRENADE stratagem button
	grenade_button = Button.new()
	grenade_button.name = "GrenadeButton"
	grenade_button.text = "Use GRENADE (1 CP)"
	grenade_button.custom_minimum_size = Vector2(230, 35)
	grenade_button.pressed.connect(_on_grenade_button_pressed)
	grenade_button.tooltip_text = "GRENADES unit: Roll 6D6, each 4+ = 1 mortal wound to enemy within 8\""
	shooting_panel.add_child(grenade_button)
	_update_grenade_button_visibility()

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

	# T5-UX4: Undo last assignment button
	undo_button = Button.new()
	undo_button.text = "Undo Last"
	undo_button.pressed.connect(_on_undo_last_pressed)
	undo_button.tooltip_text = "Remove the most recent weapon assignment"
	undo_button.disabled = true
	button_container.add_child(undo_button)

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
	
	# T5-V1: Animated dice roll visualization
	dice_roll_visual = DiceRollVisual.new()
	dice_roll_visual.custom_minimum_size = Vector2(230, 0)
	dice_roll_visual.visible = false  # Hidden until first roll
	shooting_panel.add_child(dice_roll_visual)

	dice_log_display = RichTextLabel.new()
	dice_log_display.custom_minimum_size = Vector2(230, 100)
	dice_log_display.bbcode_enabled = true
	dice_log_display.scroll_following = true
	shooting_panel.add_child(dice_log_display)

	print("ShootingController: Finished creating shooting UI - panel should be visible!")
	print("ShootingController: UI Debug Info:")
	print("  - shooting_panel children: ", shooting_panel.get_child_count())
	print("  - shooting_panel visible: ", shooting_panel.visible)
	print("  - scroll_container visible: ", scroll_container.visible)
	print("  - container visible: ", container.visible)
	print("  - hud_right visible: ", hud_right.visible if hud_right else "hud_right is null")

func set_phase(phase: BasePhase) -> void:
	current_phase = phase

	if phase and phase is ShootingPhase:
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ ShootingController.set_phase() CALLED")
		print("║ ShootingController Instance ID: ", get_instance_id())
		print("║ Phase Instance ID: ", phase.get_instance_id())
		print("╚═══════════════════════════════════════════════════════════════")

		# CRITICAL FIX: Disconnect before connecting to prevent duplicate signal connections
		# The is_connected() check was unreliable, so we guarantee single connection by
		# disconnecting first (harmless if not connected)

		if phase.unit_selected_for_shooting.is_connected(_on_unit_selected_for_shooting):
			phase.unit_selected_for_shooting.disconnect(_on_unit_selected_for_shooting)
			print("║ Disconnected existing unit_selected_for_shooting connection")
		phase.unit_selected_for_shooting.connect(_on_unit_selected_for_shooting)

		if phase.targets_available.is_connected(_on_targets_available):
			phase.targets_available.disconnect(_on_targets_available)
			print("║ Disconnected existing targets_available connection")
		phase.targets_available.connect(_on_targets_available)

		if phase.shooting_resolved.is_connected(_on_shooting_resolved):
			phase.shooting_resolved.disconnect(_on_shooting_resolved)
			print("║ Disconnected existing shooting_resolved connection")
		phase.shooting_resolved.connect(_on_shooting_resolved)

		if phase.dice_rolled.is_connected(_on_dice_rolled):
			phase.dice_rolled.disconnect(_on_dice_rolled)
			print("║ Disconnected existing dice_rolled connection")
		phase.dice_rolled.connect(_on_dice_rolled)

		if phase.saves_required.is_connected(_on_saves_required):
			phase.saves_required.disconnect(_on_saves_required)
			print("║ Disconnected existing saves_required connection from instance ", get_instance_id())
		phase.saves_required.connect(_on_saves_required)
		print("║ Connected saves_required signal to instance ", get_instance_id())

		if phase.weapon_order_required.is_connected(_on_weapon_order_required):
			phase.weapon_order_required.disconnect(_on_weapon_order_required)
			print("║ Disconnected existing weapon_order_required connection")
		phase.weapon_order_required.connect(_on_weapon_order_required)

		# T5-MP3: Connect shooting_begun for remote player visual feedback
		if phase.shooting_begun.is_connected(_on_shooting_begun):
			phase.shooting_begun.disconnect(_on_shooting_begun)
			print("║ Disconnected existing shooting_begun connection")
		phase.shooting_begun.connect(_on_shooting_begun)

		if phase.next_weapon_confirmation_required.is_connected(_on_next_weapon_confirmation_required):
			phase.next_weapon_confirmation_required.disconnect(_on_next_weapon_confirmation_required)
			print("║ Disconnected existing next_weapon_confirmation_required connection")
		phase.next_weapon_confirmation_required.connect(_on_next_weapon_confirmation_required)

		if phase.reactive_stratagem_opportunity.is_connected(_on_reactive_stratagem_opportunity):
			phase.reactive_stratagem_opportunity.disconnect(_on_reactive_stratagem_opportunity)
			print("║ Disconnected existing reactive_stratagem_opportunity connection")
		phase.reactive_stratagem_opportunity.connect(_on_reactive_stratagem_opportunity)

		if phase.grenade_result.is_connected(_on_grenade_result):
			phase.grenade_result.disconnect(_on_grenade_result)
			print("║ Disconnected existing grenade_result connection")
		phase.grenade_result.connect(_on_grenade_result)

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
			var local_player = NetworkManager.get_local_player()
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
	# T5-UX1: Hide damage preview when weapon tree is refreshed
	_hide_damage_preview()
	_hovered_weapon_id = ""
	var root = weapon_tree.create_item()

	# PISTOL RULES: Check if unit is in engagement range
	# ASSAULT RULES: Check if unit has advanced
	var shooter_unit = GameState.get_unit(active_shooter_id)
	var in_engagement = shooter_unit.get("flags", {}).get("in_engagement", false)
	var has_advanced = shooter_unit.get("flags", {}).get("advanced", false)

	# Get unit weapons from RulesEngine
	var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)

	# ONE SHOT (T4-2): Filter out already-fired one-shot weapons
	unit_weapons = RulesEngine.filter_fired_one_shot_weapons(active_shooter_id, unit_weapons)

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

		# PISTOL RULES: Check if weapon is a Pistol
		# ASSAULT RULES: Check if weapon is an Assault weapon
		# HEAVY RULES: Check if weapon is Heavy
		# RAPID FIRE RULES: Check if weapon is Rapid Fire
		# LETHAL HITS (PRP-010): Check if weapon has Lethal Hits
		# SUSTAINED HITS (PRP-011): Check if weapon has Sustained Hits
		# DEVASTATING WOUNDS (PRP-012): Check if weapon has Devastating Wounds
		# BLAST (PRP-013): Check if weapon has Blast
		# TORRENT (PRP-014): Check if weapon has Torrent (auto-hit)
		# ONE SHOT (T4-2): Check if weapon is One Shot
		var is_pistol = RulesEngine.is_pistol_weapon(weapon_id)
		var is_assault = RulesEngine.is_assault_weapon(weapon_id)
		var is_heavy = RulesEngine.is_heavy_weapon(weapon_id)
		var rapid_fire_value = RulesEngine.get_rapid_fire_value(weapon_id)
		var has_lethal_hits = RulesEngine.has_lethal_hits(weapon_id)
		var sustained_hits_display = RulesEngine.get_sustained_hits_display(weapon_id)
		var has_devastating_wounds = RulesEngine.has_devastating_wounds(weapon_id)
		var is_blast = RulesEngine.is_blast_weapon(weapon_id)
		var is_torrent = RulesEngine.is_torrent_weapon(weapon_id)
		var is_one_shot = RulesEngine.is_one_shot_weapon(weapon_id)
		var weapon_name = weapon_profile.get("name", weapon_id)

		# Build display name with keyword indicators
		var display_name = ""
		var indicators = []
		if is_torrent:
			indicators.append("T")  # Torrent indicator (PRP-014) - first because it's most impactful
		if is_one_shot:
			indicators.append("1")  # One Shot indicator (T4-2)
		if is_pistol:
			indicators.append("P")
		if is_assault:
			indicators.append("A")
		if is_heavy:
			indicators.append("H")
		if rapid_fire_value > 0:
			indicators.append("RF%d" % rapid_fire_value)
		if has_lethal_hits:
			indicators.append("LH")  # Lethal Hits indicator
		if sustained_hits_display != "":
			indicators.append(sustained_hits_display)  # Sustained Hits indicator (e.g., "SH 1" or "SH D3")
		if has_devastating_wounds:
			indicators.append("DW")  # Devastating Wounds indicator (PRP-012)
		if is_blast:
			indicators.append("B")  # Blast indicator (PRP-013)

		if not indicators.is_empty():
			display_name = "[%s] %s (x%d)" % ["/".join(indicators), weapon_name, weapon_counts[weapon_id]]
		else:
			display_name = "%s (x%d)" % [weapon_name, weapon_counts[weapon_id]]

		weapon_item.set_text(0, display_name)
		weapon_item.set_metadata(0, weapon_id)

		# T5-UX6: Show weapon stats as compact sub-line beneath each weapon
		var _wp_range = weapon_profile.get("range", 0)
		var _range_display = "Melee" if (weapon_profile.get("type", "") == "Melee" or _wp_range == 0) else str(_wp_range) + "\""
		var _atk_display = weapon_profile.get("attacks_raw", str(weapon_profile.get("attacks", 1)))
		var _skill_key = "WS" if weapon_profile.get("type", "") == "Melee" else "BS"
		var _skill_val = weapon_profile.get("ws", 4) if weapon_profile.get("type", "") == "Melee" else weapon_profile.get("bs", 4)
		var _s_display = str(weapon_profile.get("strength", 3))
		var _ap_display = str(weapon_profile.get("ap", 0))
		var _dmg_display = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
		var stat_line = "%s  A:%s %s:%s+ S:%s AP:%s D:%s" % [_range_display, _atk_display, _skill_key, str(_skill_val), _s_display, _ap_display, _dmg_display]
		var stats_item = weapon_tree.create_item(weapon_item)
		stats_item.set_text(0, stat_line)
		stats_item.set_selectable(0, false)
		stats_item.set_selectable(1, false)
		stats_item.set_custom_color(0, Color(0.7, 0.65, 0.4))  # Muted gold for stat line
		stats_item.set_metadata(0, weapon_id)  # Same weapon_id so hover triggers damage preview
		weapon_item.set_disable_folding(true)  # Always show stats, no collapse arrow

		# PISTOL RULES: Disable non-Pistol weapons when in engagement
		# ASSAULT RULES: Disable non-Assault weapons when unit has advanced
		var weapon_disabled = false
		var disable_reason = ""

		if in_engagement and not is_pistol:
			weapon_disabled = true
			disable_reason = "[Disabled - In Engagement]"
		elif has_advanced and not is_assault:
			weapon_disabled = true
			disable_reason = "[Disabled - Unit Advanced]"

		if weapon_disabled:
			# Gray out and disable non-usable weapons
			weapon_item.set_custom_color(0, Color(0.5, 0.5, 0.5))
			weapon_item.set_custom_color(1, Color(0.5, 0.5, 0.5))
			weapon_item.set_selectable(0, false)
			weapon_item.set_selectable(1, false)
			weapon_item.set_text(1, disable_reason)
			weapon_item.set_custom_bg_color(0, Color(0.3, 0.3, 0.3, 0.3))
			# T5-UX6: Also gray out the stats sub-line
			var disabled_stats = weapon_item.get_first_child()
			if disabled_stats:
				disabled_stats.set_custom_color(0, Color(0.5, 0.5, 0.5))

			# Show feedback in dice log (only once)
			if dice_log_display and weapon_counts[weapon_id] > 0:
				if in_engagement and not is_pistol:
					dice_log_display.append_text("[color=gray]%s disabled - Only PISTOL weapons can be used in engagement range[/color]\n" % weapon_name)
				elif has_advanced and not is_assault:
					dice_log_display.append_text("[color=gray]%s disabled - Only ASSAULT weapons can be used after Advancing[/color]\n" % weapon_name)
			continue  # Skip auto-target and target selection for disabled weapons

		# Highlight Pistol weapons when in engagement
		if in_engagement and is_pistol:
			weapon_item.set_custom_bg_color(0, Color(0.2, 0.4, 0.2, 0.3))  # Green tint for available Pistols

		# Highlight Assault weapons when unit has advanced
		if has_advanced and is_assault:
			weapon_item.set_custom_bg_color(0, Color(0.2, 0.4, 0.2, 0.3))  # Green tint for available Assault weapons

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

				# REMOVED: Icon button that was making rows too tall
				# Users can select weapon, then click enemy unit to assign target

	# T5-UX2: Auto-select weapon for single-weapon units
	# If only one weapon type is usable (not disabled), auto-select it in the tree
	# so the player can directly click on enemy units without selecting the weapon first
	_try_auto_select_single_weapon()

func _try_auto_select_single_weapon() -> void:
	"""T5-UX2: If unit has only one usable weapon type, auto-select it in the weapon tree.
	This skips the manual weapon selection step for single-weapon units, letting the player
	click directly on an enemy to assign the target."""
	if not weapon_tree:
		return

	var root = weapon_tree.get_root()
	if not root:
		return

	# Count usable (selectable) weapon items that don't already have a target assigned
	var usable_items: Array = []
	var child = root.get_first_child()
	while child:
		var weapon_id = child.get_metadata(0)
		if weapon_id and child.is_selectable(0):
			usable_items.append(child)
		child = child.get_next()

	# Only auto-select if exactly one usable weapon type exists
	if usable_items.size() != 1:
		return

	var single_weapon_item = usable_items[0]
	var weapon_id = single_weapon_item.get_metadata(0)

	# Don't auto-select if the weapon is already assigned to a target (auto-target handled it)
	if weapon_assignments.has(weapon_id):
		return

	# Auto-select this weapon in the tree
	single_weapon_item.select(0)
	selected_weapon_id = weapon_id

	# Visual feedback - highlight the auto-selected weapon
	single_weapon_item.set_custom_bg_color(0, Color(0.2, 0.4, 0.2, 0.5))
	single_weapon_item.set_text(1, "[Click enemy to assign]")

	# Show modifier panel for this weapon
	if modifier_panel and modifier_label:
		modifier_panel.visible = true
		modifier_label.visible = true
		_load_modifiers_for_weapon(weapon_id)

	# T5-UX1: Show damage preview for auto-selected weapon
	_update_damage_preview(weapon_id)

	# Show feedback in dice log
	if dice_log_display:
		var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		dice_log_display.append_text("[color=cyan]Auto-selected %s (only weapon) — click an enemy unit to assign target[/color]\n" % weapon_name)

	print("ShootingController: T5-UX2 Auto-selected single weapon: %s" % weapon_id)

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

			# Use shape-aware edge-to-edge distance
			var dist = Measurement.model_to_model_distance_px(from_model, to_model)
			if dist < min_distance:
				min_distance = dist
				from_pos = f_pos
				to_pos = t_pos

	if from_pos != Vector2.ZERO and to_pos != Vector2.ZERO:
		los_visual.add_point(from_pos)
		los_visual.add_point(to_pos)

		# Add range indicator using edge-to-edge distance
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

	# T5-MP3: Clear shooting lines (remote player feedback)
	_clear_shooting_lines()

	print("ShootingController: All visuals cleared")

# ==========================================
# T5-MP3: Remote Player Visual Feedback
# ==========================================

func show_remote_target_assignment(shooter_id: String, target_unit_id: String, weapon_id: String) -> void:
	"""Called by NetworkManager when the remote active player assigns a weapon to a target.
	Draws a shooting line from the shooter to the target so the remote player can see
	what's being targeted. T5-MP3."""
	if not current_phase:
		return

	print("ShootingController: T5-MP3 show_remote_target_assignment — %s → %s (weapon: %s)" % [shooter_id, target_unit_id, weapon_id])

	var shooter_unit = current_phase.get_unit(shooter_id)
	var target_unit = current_phase.get_unit(target_unit_id)
	if shooter_unit.is_empty() or target_unit.is_empty():
		return

	# Find closest model positions between shooter and target
	var from_pos = Vector2.ZERO
	var to_pos = Vector2.ZERO
	var min_distance = INF

	for from_model in shooter_unit.get("models", []):
		if not from_model.get("alive", true):
			continue
		var f_pos = _get_model_position(from_model)
		for to_model in target_unit.get("models", []):
			if not to_model.get("alive", true):
				continue
			var t_pos = _get_model_position(to_model)
			var dist = f_pos.distance_to(t_pos)
			if dist < min_distance:
				min_distance = dist
				from_pos = f_pos
				to_pos = t_pos

	if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
		return

	# Create a shooting line from shooter to target
	var line = Line2D.new()
	line.width = SHOOTING_LINE_WIDTH
	line.default_color = SHOOTING_LINE_COLOR
	line.add_point(from_pos)
	line.add_point(to_pos)
	line.name = "ShootingLine_%s_%s" % [shooter_id.substr(0, 8), target_unit_id.substr(0, 8)]

	if shooting_lines_container and is_instance_valid(shooting_lines_container):
		shooting_lines_container.add_child(line)
		remote_assignment_lines.append(line)

	# Also highlight the target unit if not already highlighted
	_create_target_highlight(target_unit_id, HIGHLIGHT_COLOR_SELECTED)

	# Show weapon name label at midpoint
	var mid_point = (from_pos + to_pos) / 2
	var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
	var label = Label.new()
	label.text = weapon_name
	label.position = mid_point + Vector2(0, -15)
	label.add_theme_color_override("font_color", SHOOTING_LINE_COLOR)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 12)
	if shooting_lines_container and is_instance_valid(shooting_lines_container):
		shooting_lines_container.add_child(label)

func clear_remote_target_assignments() -> void:
	"""Clear all remote target assignment visuals. Called when the remote active player
	clears their weapon assignments. T5-MP3."""
	print("ShootingController: T5-MP3 clear_remote_target_assignments")
	_clear_shooting_lines()
	_clear_target_highlights()

func _clear_shooting_lines() -> void:
	"""Clear all shooting line visuals from the container. T5-MP3."""
	if shooting_lines_container and is_instance_valid(shooting_lines_container):
		for child in shooting_lines_container.get_children():
			child.queue_free()
	remote_assignment_lines.clear()

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

			# RAPID FIRE: Add half-range circle for Rapid Fire weapons (orange color)
			var rapid_fire_value = RulesEngine.get_rapid_fire_value(weapon_id)
			if rapid_fire_value > 0:
				var half_range_px = range_px / 2.0
				var half_range_circle = preload("res://scripts/RangeCircle.gd").new()
				half_range_circle.position = model_pos
				half_range_circle.setup(half_range_px, weapon_id + " (RF %d)" % rapid_fire_value, Color.ORANGE)
				range_visual.add_child(half_range_circle)

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

				# Use shape-aware edge-to-edge distance
				var distance = Measurement.model_to_model_distance_px(shooter_model, enemy_model)
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

			# Use shape-aware edge-to-edge distance
			var dist = Measurement.model_to_model_distance_px(from_model, to_model)
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
	assignment_history.clear()  # T5-UX4: Clear undo history for new shooter

	# NEW: Hide auto-target button when selecting new shooter
	if auto_target_button_container:
		auto_target_button_container.visible = false
	last_assigned_target_id = ""

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

func _on_shooting_begun(unit_id: String) -> void:
	"""T5-MP3: Handle shooting_begun signal. For the remote player, this draws shooting
	lines from the active shooter to all confirmed targets, providing visual context
	for what's being resolved."""
	print("ShootingController: T5-MP3 _on_shooting_begun for %s" % unit_id)

	# Only draw shooting lines on the remote (non-active) player's screen
	# The active player already has their weapon tree and target highlights
	if not NetworkManager.is_networked():
		return

	var local_player = NetworkManager.get_local_player()
	var active_player = current_phase.get_current_player() if current_phase else -1
	if local_player == active_player:
		# Active player already has all the visual feedback
		return

	print("ShootingController: T5-MP3 Remote player — drawing shooting lines for confirmed targets")

	# Draw lines from shooter to each confirmed target
	if current_phase and "confirmed_assignments" in current_phase:
		var seen_targets = {}
		for assignment in current_phase.confirmed_assignments:
			var target_unit_id = assignment.get("target_unit_id", "")
			var weapon_id = assignment.get("weapon_id", "")
			if target_unit_id != "" and not seen_targets.has(target_unit_id):
				seen_targets[target_unit_id] = true
				show_remote_target_assignment(unit_id, target_unit_id, weapon_id)

	# Show feedback in dice log on remote player
	if dice_log_display:
		var shooter_name = ""
		if current_phase:
			var shooter = current_phase.get_unit(unit_id)
			shooter_name = shooter.get("meta", {}).get("name", unit_id)
		dice_log_display.append_text("[color=orange]%s is shooting...[/color]\n" % shooter_name)

func _on_shooting_resolved(shooter_id: String, target_id: String, result: Dictionary) -> void:
	print("ShootingController: Shooting resolved for ", shooter_id, " -> ", target_id)
	# Update visuals after shooting
	_clear_visuals()
	active_shooter_id = ""
	eligible_targets.clear()
	weapon_assignments.clear()
	assignment_history.clear()  # T5-UX4: Clear undo history
	_refresh_weapon_tree()
	# Clear LoS visualization after shooting
	if los_debug_visual:
		los_debug_visual.clear_los_lines()
	# Update grenade button (unit may have shot, reducing eligible units)
	_update_grenade_button_visibility()

func _on_dice_rolled(dice_data: Dictionary) -> void:
	if not dice_log_display:
		return

	# T5-V1: Trigger animated dice visualization
	if dice_roll_visual:
		dice_roll_visual.show_dice_roll(dice_data)

	# T5-MP5: Handle resolution_start context — show header message in dice log
	var context = dice_data.get("context", "Roll")
	if context == "resolution_start":
		var message = dice_data.get("message", "Beginning attack resolution...")
		dice_log_display.append_text("[b][color=white]--- %s ---[/color][/b]\n" % message)
		return

	# Check if this is a weapon progress message (sequential resolution)
	if context == "weapon_progress":
		var message = dice_data.get("message", "")
		var current_index = dice_data.get("current_index", 0)
		var total_weapons = dice_data.get("total_weapons", 0)
		dice_log_display.append_text("[b][color=yellow]>>> %s <<<[/color][/b]\n" % message)
		return

	# FEEL NO PAIN: Handle feel_no_pain dice block
	if context == "feel_no_pain":
		var fnp_val = dice_data.get("fnp_value", 0)
		var prevented = dice_data.get("wounds_prevented", 0)
		var remaining = dice_data.get("wounds_remaining", 0)
		var total = dice_data.get("total_wounds", 0)
		var fnp_rolls = dice_data.get("rolls_raw", [])
		var target_name = dice_data.get("target_unit_name", "")

		var log_text = "[b][color=cyan]Feel No Pain %d+[/color][/b]" % fnp_val
		if not target_name.is_empty():
			log_text += " (%s)" % target_name
		log_text += "\n"

		# Show individual dice
		var dice_str = "  Rolls: "
		for fnp_roll in fnp_rolls:
			if fnp_roll >= fnp_val:
				dice_str += "[color=green]%d[/color] " % fnp_roll
			else:
				dice_str += "[color=red]%d[/color] " % fnp_roll
		log_text += dice_str + "\n"

		# Show summary
		if prevented > 0:
			log_text += "  [color=green]%d/%d wounds prevented[/color]" % [prevented, total]
		else:
			log_text += "  [color=red]No wounds prevented[/color]"
		if remaining > 0:
			log_text += ", [color=red]%d wounds get through[/color]" % remaining
		log_text += "\n"

		dice_log_display.append_text(log_text)
		return

	# Variable damage display
	if context == "variable_damage":
		var notation = dice_data.get("notation", "")
		var total_dmg = dice_data.get("total_damage", 0)
		var dmg_rolls = dice_data.get("rolls", [])
		var log_text = "[b][color=yellow]Variable Damage (%s)[/color][/b]\n" % notation
		var roll_values = []
		for r in dmg_rolls:
			roll_values.append(str(r.get("value", 0)))
		log_text += "  Rolled: [%s] = %d total damage\n" % [", ".join(roll_values), total_dmg]
		dice_log_display.append_text(log_text)
		return

	# TORRENT (PRP-014): Handle auto_hit context for Torrent weapons
	if context == "auto_hit":
		var total_attacks = dice_data.get("total_attacks", 0)
		var hits = dice_data.get("successes", 0)
		var message = dice_data.get("message", "Torrent: automatic hits")
		var log_text = "[b][color=lime]TORRENT - Automatic Hits[/color][/b]\n"

		# Show variable attacks if rolled
		var torrent_var_attacks = dice_data.get("variable_attacks", false)
		if torrent_var_attacks:
			var attacks_notation = dice_data.get("attacks_notation", "")
			var attacks_rolls = dice_data.get("attacks_rolls", [])
			var base_atk = dice_data.get("base_attacks", 0)
			var roll_values = []
			for r in attacks_rolls:
				roll_values.append(str(r.get("value", 0)))
			log_text += "  [color=yellow][VARIABLE ATTACKS] %s per model → rolled [%s] = %d attacks[/color]\n" % [attacks_notation, ", ".join(roll_values), base_atk]

		log_text += "  [color=lime]%s[/color]\n" % message

		# Show Blast bonus if this is a Torrent + Blast weapon
		var blast_weapon = dice_data.get("blast_weapon", false)
		if blast_weapon:
			var target_model_count = dice_data.get("target_model_count", 0)
			var blast_bonus_attacks = dice_data.get("blast_bonus_attacks", 0)
			if blast_bonus_attacks > 0:
				log_text += "  [color=lime][BLAST] +%d bonus attacks (%d models)[/color]\n" % [blast_bonus_attacks, target_model_count]

		# Note if weapon has Lethal Hits or Sustained Hits (they won't trigger)
		var lethal_hits_weapon = dice_data.get("lethal_hits_weapon", false)
		var sustained_hits_weapon = dice_data.get("sustained_hits_weapon", false)
		if lethal_hits_weapon or sustained_hits_weapon:
			log_text += "  [color=gray]Note: Lethal/Sustained Hits don't trigger (no hit roll)[/color]\n"

		log_text += "  [b][color=green]→ %d hits proceeding to wound roll[/color][/b]\n" % hits
		dice_log_display.append_text(log_text)
		return

	# Get data from the dice roll
	var rolls_raw = dice_data.get("rolls_raw", [])
	var rolls_modified = dice_data.get("rolls_modified", [])
	var rerolls = dice_data.get("rerolls", [])
	var successes = dice_data.get("successes", -1)
	var threshold = dice_data.get("threshold", "")

	# Format the display text with modifier effects
	var log_text = "[b]%s[/b] (need %s):\n" % [context.capitalize().replace("_", " "), threshold]

	# Show Heavy bonus if applied
	var heavy_bonus_applied = dice_data.get("heavy_bonus_applied", false)
	if heavy_bonus_applied:
		log_text += "  [color=cyan][HEAVY] +1 to hit (unit stationary)[/color]\n"

	# Show variable attacks if rolled
	var variable_attacks = dice_data.get("variable_attacks", false)
	if variable_attacks:
		var attacks_notation = dice_data.get("attacks_notation", "")
		var attacks_rolls = dice_data.get("attacks_rolls", [])
		var base_attacks = dice_data.get("base_attacks", 0)
		var roll_values = []
		for r in attacks_rolls:
			roll_values.append(str(r.get("value", 0)))
		log_text += "  [color=yellow][VARIABLE ATTACKS] %s per model → rolled [%s] = %d attacks[/color]\n" % [attacks_notation, ", ".join(roll_values), base_attacks]

	# Show Rapid Fire bonus if applied
	var rapid_fire_bonus = dice_data.get("rapid_fire_bonus", 0)
	if rapid_fire_bonus > 0:
		var rf_value = dice_data.get("rapid_fire_value", 1)
		var models_in_half = dice_data.get("models_in_half_range", 0)
		var base_atk = dice_data.get("base_attacks", 0)
		log_text += "  [color=orange][RAPID FIRE %d] +%d attacks (%d models in half range, %d base attacks)[/color]\n" % [rf_value, rapid_fire_bonus, models_in_half, base_atk]

	# BLAST (PRP-013): Show Blast bonus if applied
	var blast_weapon = dice_data.get("blast_weapon", false)
	if blast_weapon and context == "to_hit":
		var target_model_count = dice_data.get("target_model_count", 0)
		var blast_bonus_attacks = dice_data.get("blast_bonus_attacks", 0)

		if blast_bonus_attacks > 0:
			log_text += "  [color=lime][BLAST] +%d attacks (%d models in target)[/color]\n" % [blast_bonus_attacks, target_model_count]
		elif blast_bonus_attacks == 0:
			log_text += "  [color=gray][BLAST] No bonus (%d models in target < 5)[/color]\n" % target_model_count

	# LETHAL HITS (PRP-010): Show Lethal Hits indicator and auto-wounds
	var lethal_hits_weapon = dice_data.get("lethal_hits_weapon", false)
	if lethal_hits_weapon and context == "to_hit":
		log_text += "  [color=magenta][LETHAL HITS] Critical hits (6s) auto-wound![/color]\n"

	# SUSTAINED HITS (PRP-011): Show Sustained Hits indicator
	var sustained_hits_weapon = dice_data.get("sustained_hits_weapon", false)
	if sustained_hits_weapon and context == "to_hit":
		var sh_value = dice_data.get("sustained_hits_value", 0)
		var sh_is_dice = dice_data.get("sustained_hits_is_dice", false)
		var sh_display = "D%d" % sh_value if sh_is_dice else str(sh_value)
		log_text += "  [color=cyan][SUSTAINED HITS %s] Critical hits (6s) generate +%s extra hits![/color]\n" % [sh_display, sh_display]

	# Show re-rolls if any occurred
	if not rerolls.is_empty():
		log_text += "  [color=yellow]Re-rolled:[/color] "
		for reroll in rerolls:
			log_text += "[s]%d[/s]→%d " % [reroll.original, reroll.rerolled_to]
		log_text += "\n"

	# Show rolls (use modified if available, otherwise raw)
	var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
	log_text += "  Rolls: %s" % str(display_rolls)

	# CRITICAL HIT TRACKING (PRP-031): Show critical hits for to_hit rolls
	var critical_hits = dice_data.get("critical_hits", 0)
	if context == "to_hit" and critical_hits > 0:
		log_text += " [color=magenta](%d critical)[/color]" % critical_hits

	# Show success count
	if successes >= 0:
		log_text += " → [b][color=green]%d successes[/color][/b]" % successes

	# SUSTAINED HITS (PRP-011): Show bonus hits generated for to_hit rolls
	var sustained_bonus_hits = dice_data.get("sustained_bonus_hits", 0)
	if context == "to_hit" and sustained_bonus_hits > 0:
		var total_for_wounds = dice_data.get("total_hits_for_wounds", 0)
		log_text += "\n  [color=cyan][SUSTAINED HITS] +%d bonus hits → %d total hits for wound roll[/color]" % [sustained_bonus_hits, total_for_wounds]

	# LETHAL HITS (PRP-010): Show auto-wounds for wound rolls
	var lethal_auto_wounds = dice_data.get("lethal_hits_auto_wounds", 0)
	if context == "to_wound" and lethal_auto_wounds > 0:
		var wounds_from_rolls = dice_data.get("wounds_from_rolls", 0)
		log_text += "\n  [color=magenta][LETHAL HITS] %d auto-wounds + %d from rolls[/color]" % [lethal_auto_wounds, wounds_from_rolls]

	# Save roll: show failed saves (which cause wounds)
	if context == "save_roll":
		var failed = dice_data.get("failed", 0)
		if failed > 0:
			log_text += ", [color=red]%d failed (wounds)[/color]" % failed
		else:
			log_text += " [color=green](all saved!)[/color]"
		var using_invuln_save = dice_data.get("using_invuln", false)
		if using_invuln_save:
			log_text += "\n  [color=cyan](Using Invulnerable Save)[/color]"

	log_text += "\n"

	dice_log_display.append_text(log_text)

func _on_saves_required(save_data_list: Array) -> void:
	"""Show WoundAllocationOverlay when defender needs to make saves"""

	# CRITICAL: Prevent re-entrant calls (signal connected multiple times)
	if processing_saves_signal:
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ ❌ DUPLICATE SIGNAL BLOCKED")
		print("║ Already processing saves_required signal")
		print("║ Timestamp: ", Time.get_ticks_msec())
		print("║ This is likely due to the signal being connected multiple times")
		print("╚═══════════════════════════════════════════════════════════════")
		return

	processing_saves_signal = true

	# COMPREHENSIVE LOGGING: Track every call to this function
	var timestamp = Time.get_ticks_msec()
	var call_stack = get_stack()
	var caller_info = "unknown"
	if call_stack.size() > 1:
		caller_info = str(call_stack[1])

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SAVES_REQUIRED RECEIVED (ShootingController)")
	print("║ Timestamp: ", timestamp)
	print("║ ShootingController Instance ID: ", get_instance_id())
	print("║ Function: ShootingController._on_saves_required")
	print("║ Call stack depth: ", call_stack.size())
	print("║ Caller: ", caller_info)
	print("║ Save data list size: ", save_data_list.size())
	print("║ processing_saves_signal was: false (now set to true)")

	if save_data_list.is_empty():
		print("║ ⚠️  WARNING: Empty save data list - RETURNING")
		print("╚═══════════════════════════════════════════════════════════════")
		processing_saves_signal = false
		return

	var save_data = save_data_list[0]
	var target = save_data.get("target_unit_id", "unknown")
	var weapon = save_data.get("weapon_name", "unknown")
	var wounds = save_data.get("wounds_to_save", 0)

	print("║ Target: ", target)
	print("║ Weapon: ", weapon)
	print("║ Wounds: ", wounds)

	# ENHANCED DEBOUNCE: Check if overlay already exists for this weapon/target
	if active_allocation_overlay != null and is_instance_valid(active_allocation_overlay):
		var existing_target = active_allocation_overlay.save_data.get("target_unit_id", "")
		var existing_weapon = active_allocation_overlay.save_data.get("weapon_name", "")
		var existing_wounds = active_allocation_overlay.save_data.get("wounds_to_save", 0)

		print("║ ")
		print("║ ⚠️  DEBOUNCE CHECK:")
		print("║   Active overlay exists: YES")
		print("║   Existing: weapon='%s', target='%s', wounds=%d" % [existing_weapon, existing_target, existing_wounds])
		print("║   Incoming: weapon='%s', target='%s', wounds=%d" % [weapon, target, wounds])

		if existing_target == target and existing_weapon == weapon:
			print("║   ")
			print("║   ❌ DUPLICATE DETECTED - IGNORING THIS CALL")
			print("║   This is a duplicate signal emission for the same weapon/target")
			print("╚═══════════════════════════════════════════════════════════════")
			return
		else:
			print("║   ")
			print("║   ✅ Different weapon/target - allowing new overlay")
	else:
		print("║ ")
		print("║ Active overlay exists: NO")
		print("║ This is the first allocation for this combat")

	print("║ ")
	print("║ PROCEEDING WITH OVERLAY CREATION...")
	print("╚═══════════════════════════════════════════════════════════════")

	# Get defender
	var target_unit_id = save_data.get("target_unit_id", "")
	if target_unit_id == "":
		push_error("ShootingController: No target_unit_id in save data")
		processing_saves_signal = false
		return

	var target_unit = GameState.get_unit(target_unit_id)
	if target_unit.is_empty():
		push_error("ShootingController: Target unit not found: " + target_unit_id)
		processing_saves_signal = false
		return

	var defender_player = target_unit.get("owner", 0)

	# Determine if this local player should see the dialog
	var should_show_dialog = false
	var local_player = -1

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ PLAYER ROLE CHECK")

	if NetworkManager.is_networked():
		local_player = NetworkManager.get_local_player()
		should_show_dialog = (local_player == defender_player)
		print("║ Mode: MULTIPLAYER")
		print("║ Local player (via get_local_player): ", local_player)
		print("║ Defender player: ", defender_player)
		print("║ Should show dialog: ", should_show_dialog)
	else:
		should_show_dialog = true
		print("║ Mode: SINGLE PLAYER")
		print("║ Should show dialog: TRUE (always in single player)")

	if not should_show_dialog:
		print("║ ")
		print("║ ❌ NOT SHOWING DIALOG - Not the defending player")
		print("║ This client is the attacker, not the defender")
		# T5-MP4: Attacker-side — show "Waiting for defender" feedback and start ack timeout
		if NetworkManager.is_networked():
			_awaiting_remote_saves = true
			_save_ack_received = false
			_pending_save_data_for_retry = save_data_list.duplicate(true)
			print("║ T5-MP4: Attacker waiting for defender to make saves")
			print("║ T5-MP4: Starting ack timeout (%.0fs)" % SAVE_ACK_TIMEOUT_SEC)
			_show_waiting_for_saves_feedback(target, weapon)
			# Start ack timeout timer — if defender doesn't ack, we'll log a warning
			if _save_processing_timeout_timer:
				_save_processing_timeout_timer.wait_time = SAVE_ACK_TIMEOUT_SEC
				_save_processing_timeout_timer.start()
		print("╚═══════════════════════════════════════════════════════════════")
		processing_saves_signal = false
		return

	print("║ ")
	print("║ ✅ SHOWING DIALOG - This is the defending player")
	print("╚═══════════════════════════════════════════════════════════════")

	# Temporarily disable ShootingController's input processing
	set_process_input(false)
	set_process_unhandled_input(false)

	# Create WoundAllocationOverlay
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ CREATING WOUND ALLOCATION OVERLAY")
	print("║ Timestamp: ", Time.get_ticks_msec())
	print("║ Target: ", target)
	print("║ Weapon: ", weapon)
	print("║ Wounds: ", wounds)

	var overlay = WoundAllocationOverlay.new()
	print("║ Overlay instance created: ", overlay)
	print("║ Overlay instance ID: ", overlay.get_instance_id())

	# Store reference to active overlay
	active_allocation_overlay = overlay
	print("║ Stored in active_allocation_overlay")

	# Connect to allocation_complete signal to clear the reference AND submit APPLY_SAVES
	overlay.allocation_complete.connect(func(summary):
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ WOUND ALLOCATION COMPLETE")
		print("║ Timestamp: ", Time.get_ticks_msec())
		print("║ Summary: ", summary)
		print("║ Submitting APPLY_SAVES action to network...")

		# Build APPLY_SAVES action from summary
		var apply_saves_action = {
			"type": "APPLY_SAVES",
			"payload": {
				"save_results_list": [summary]  # Wrap summary in array as expected by phase
			}
		}

		print("║ Action built: ", apply_saves_action)
		print("║ Emitting shoot_action_requested signal...")

		# Submit action through Main (which routes through NetworkManager)
		emit_signal("shoot_action_requested", apply_saves_action)

		print("║ APPLY_SAVES action submitted successfully")
		print("║ Clearing overlay reference and processing flag")
		print("╚═══════════════════════════════════════════════════════════════")

		active_allocation_overlay = null  # Clear reference
		processing_saves_signal = false  # Reset flag to allow next allocation
		# T5-MP4: Stop safety timer and clear retry state
		if _save_processing_timeout_timer:
			_save_processing_timeout_timer.stop()
		set_process_input(true)
		set_process_unhandled_input(true)
	)
	print("║ Connected to allocation_complete signal")

	# Add to scene tree
	var main = get_node_or_null("/root/Main")
	if not main:
		push_error("ShootingController: /root/Main not found!")
		print("╚═══════════════════════════════════════════════════════════════")
		processing_saves_signal = false
		return

	main.add_child(overlay)
	print("║ Added overlay to Main scene tree")

	# T5-MP4: Start safety timer to reset processing_saves_signal if something goes wrong
	if _save_processing_timeout_timer:
		_save_processing_timeout_timer.wait_time = SAVE_PROCESSING_TIMEOUT_SEC
		_save_processing_timeout_timer.start()
		print("║ T5-MP4: Started save processing safety timer (%.0fs)" % SAVE_PROCESSING_TIMEOUT_SEC)

	# Wait one frame to ensure _ready() has been called
	await get_tree().process_frame

	# Setup with save data
	overlay.setup(save_data, defender_player)
	print("║ Overlay setup complete")

	# T5-MP4: Send acknowledgment to attacker that save dialog is now showing
	if NetworkManager.is_networked():
		print("║ T5-MP4: Sending save_dialog_ack to attacker")
		NetworkManager.send_save_dialog_ack(target_unit_id, weapon)
	print("╚═══════════════════════════════════════════════════════════════")

func _on_weapon_order_required(assignments: Array) -> void:
	"""Show WeaponOrderDialog when multiple weapon types are assigned"""
	print("========================================")
	print("ShootingController: _on_weapon_order_required CALLED")
	print("ShootingController: Assignments: %d" % assignments.size())

	# Check if this is the attacking player in multiplayer
	var should_show_dialog = false

	if NetworkManager.is_networked():
		# Multiplayer: Only show dialog if this peer is the attacker
		var local_player = NetworkManager.get_local_player()
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

func _on_next_weapon_confirmation_required(remaining_weapons: Array, current_index: int, last_weapon_result: Dictionary) -> void:
	"""Handle next weapon confirmation in sequential mode"""
	print("========================================")
	print("ShootingController: _on_next_weapon_confirmation_required CALLED")
	print("ShootingController: Remaining weapons: %d, current_index: %d" % [remaining_weapons.size(), current_index])
	print("ShootingController: Last weapon result keys: %s" % str(last_weapon_result.keys()))

	# Note: remaining_weapons CAN be empty - this is the final weapon case!
	if remaining_weapons.is_empty():
		print("ShootingController: ✓ Empty remaining_weapons - this is the FINAL weapon")
		print("ShootingController: Dialog will show 'Complete Shooting' button")

	# Validate last_weapon_result
	if last_weapon_result.is_empty():
		push_warning("ShootingController: last_weapon_result is EMPTY - showing dialog without summary")

	# NEW: Validate weapon structure
	print("ShootingController: Validating remaining weapons structure...")
	for i in range(remaining_weapons.size()):
		var weapon = remaining_weapons[i]
		var weapon_id = weapon.get("weapon_id", "")
		var target_id = weapon.get("target_unit_id", "")
		var model_ids = weapon.get("model_ids", [])

		if weapon_id == "":
			push_error("ShootingController: Weapon %d has EMPTY weapon_id!" % i)
			print("  ❌ Weapon %d: weapon_id is EMPTY" % i)
			print("     Full object: %s" % str(weapon))
		else:
			print("  ✓ Weapon %d: %s → %s (%d models)" % [i, weapon_id, target_id, model_ids.size()])

	# Check if this is for the local attacking player
	var should_show_dialog = false

	if NetworkManager.is_networked():
		var local_player = NetworkManager.get_local_player()
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
		var weapon_name = last_weapon_result.get("weapon_name", "Unknown")
		var casualties = last_weapon_result.get("casualties", 0)
		dice_log_display.append_text("[b][color=yellow]>>> %s complete: %d casualties <<<[/color][/b]\n" %
			[weapon_name, casualties])

	# Close any existing dialogs
	var root_children = get_tree().root.get_children()
	for child in root_children:
		if child is AcceptDialog:
			print("ShootingController: Closing existing dialog: %s" % child.name)
			child.hide()
			child.queue_free()

	await get_tree().process_frame

	# Load NextWeaponDialog
	var weapon_dialog_script = preload("res://scripts/NextWeaponDialog.gd")
	var dialog = weapon_dialog_script.new()

	# Connect to confirmation signal - when user clicks Continue, show WeaponOrderDialog
	dialog.continue_confirmed.connect(_on_show_weapon_order_from_next_weapon_dialog)

	# NEW: Connect to completion signal - when user clicks "Complete Shooting"
	dialog.shooting_complete_confirmed.connect(_on_shooting_complete)

	# Add to scene tree
	get_tree().root.add_child(dialog)

	# Setup with enhanced data
	print("ShootingController: Calling dialog.setup() with %d weapons and last weapon result" % remaining_weapons.size())
	dialog.setup(remaining_weapons, current_index, last_weapon_result)

	# Show dialog
	dialog.popup_centered()

	print("ShootingController: NextWeaponDialog shown with last weapon results")
	print("========================================")

func _on_reactive_stratagem_opportunity(defending_player: int, available_stratagems: Array, target_unit_ids: Array) -> void:
	"""Handle reactive stratagem opportunity - show dialog to defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ShootingController: REACTIVE STRATAGEM OPPORTUNITY")
	print("║ Defending player: %d" % defending_player)
	print("║ Available stratagems: %d" % available_stratagems.size())
	print("║ Target units: %s" % str(target_unit_ids))
	print("╚═══════════════════════════════════════════════════════════════")

	# Check if this is for the local player (multiplayer support)
	var should_show_dialog = false
	if NetworkManager.is_networked():
		var local_player = NetworkManager.get_local_player()
		should_show_dialog = (local_player == defending_player)
	else:
		# Single player / hot-seat: always show
		should_show_dialog = true

	if not should_show_dialog:
		# Not the local defending player - auto-decline
		print("ShootingController: Not the defending player locally, auto-declining")
		emit_signal("shoot_action_requested", {
			"type": "DECLINE_REACTIVE_STRATAGEM"
		})
		return

	# Show StratagemDialog
	var dialog_script = preload("res://dialogs/StratagemDialog.gd")
	var dialog = dialog_script.new()

	dialog.stratagem_selected.connect(_on_reactive_stratagem_selected)
	dialog.stratagem_declined.connect(_on_reactive_stratagem_declined)

	get_tree().root.add_child(dialog)
	dialog.setup(defending_player, available_stratagems, target_unit_ids)
	dialog.popup_centered()

	print("ShootingController: StratagemDialog shown for player %d" % defending_player)

func _on_reactive_stratagem_selected(stratagem_id: String, target_unit_id: String) -> void:
	"""Handle defender selecting a reactive stratagem."""
	print("ShootingController: Reactive stratagem selected: %s on %s" % [stratagem_id, target_unit_id])
	emit_signal("shoot_action_requested", {
		"type": "USE_REACTIVE_STRATAGEM",
		"stratagem_id": stratagem_id,
		"target_unit_id": target_unit_id
	})

func _on_reactive_stratagem_declined() -> void:
	"""Handle defender declining all reactive stratagems."""
	print("ShootingController: Reactive stratagems declined")
	emit_signal("shoot_action_requested", {
		"type": "DECLINE_REACTIVE_STRATAGEM"
	})

func _on_show_weapon_order_from_next_weapon_dialog(remaining_weapons: Array, fast_roll: bool) -> void:
	"""Show WeaponOrderDialog after NextWeaponDialog's Continue button is pressed"""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SHOOTING CONTROLLER: RECEIVED continue_confirmed SIGNAL")
	print("║ Handler: _on_show_weapon_order_from_next_weapon_dialog")
	print("║ remaining_weapons.size(): ", remaining_weapons.size())
	print("║ fast_roll: ", fast_roll)
	print("║ Weapons received:")
	for i in range(min(3, remaining_weapons.size())):
		var weapon = remaining_weapons[i]
		print("║   Weapon %d: %s → %s" % [i, weapon.get("weapon_id", "UNKNOWN"), weapon.get("target_unit_id", "UNKNOWN")])
	if remaining_weapons.size() > 3:
		print("║   ... and %d more weapons" % (remaining_weapons.size() - 3))
	print("╚═══════════════════════════════════════════════════════════════")

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

	# Connect to weapon_order_confirmed signal
	dialog.weapon_order_confirmed.connect(_on_next_weapon_order_confirmed)

	# Add to scene tree
	get_tree().root.add_child(dialog)

	# Setup with remaining weapons AND pass the current_phase
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SHOOTING CONTROLLER: SHOWING WEAPON ORDER DIALOG")
	print("║ Passing %d weapons to dialog.setup()" % remaining_weapons.size())
	dialog.setup(remaining_weapons, current_phase)

	# Customize the title to show it's a continuation
	dialog.title = "Choose Next Weapon (%d remaining)" % remaining_weapons.size()

	# Show dialog
	dialog.popup_centered()

	print("║ WeaponOrderDialog shown successfully")
	print("║ Waiting for weapon_order_confirmed signal...")
	print("╚═══════════════════════════════════════════════════════════════")

func _on_next_weapon_order_confirmed(weapon_order: Array, fast_roll: bool) -> void:
	"""Handle next weapon order confirmation (mid-sequence)"""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SHOOTING CONTROLLER: WEAPON ORDER CONFIRMED")
	print("║ Handler: _on_next_weapon_order_confirmed")
	print("║ weapon_order.size(): ", weapon_order.size())
	print("║ fast_roll: ", fast_roll)
	print("║ Weapons in order:")
	for i in range(min(3, weapon_order.size())):
		var weapon = weapon_order[i]
		print("║   %d: %s → %s" % [i, weapon.get("weapon_id", "UNKNOWN"), weapon.get("target_unit_id", "UNKNOWN")])
	if weapon_order.size() > 3:
		print("║   ... and %d more weapons" % (weapon_order.size() - 3))
	print("║")

	# Show feedback in dice log
	if dice_log_display:
		dice_log_display.append_text("[color=cyan]Continuing to next weapon...[/color]\n")

	# If fast_roll is true in mid-sequence, just resolve all remaining weapons at once
	if fast_roll:
		print("║ MODE: Fast Roll - resolving all remaining weapons at once")
		# Build action to resolve remaining weapons as fast roll
		var action = {
			"type": "RESOLVE_WEAPON_SEQUENCE",
			"payload": {
				"weapon_order": weapon_order,
				"fast_roll": true,
				"is_reorder": true
			}
		}
		print("║ Emitting action: RESOLVE_WEAPON_SEQUENCE")
		print("║ Action payload: ", action)
		emit_signal("shoot_action_requested", action)
	else:
		print("║ MODE: Sequential - continuing to next weapon")
		# Continue sequential - either with reordered weapons or same order
		var action = {
			"type": "CONTINUE_SEQUENCE",
			"payload": {
				"weapon_order": weapon_order
			}
		}
		print("║ Emitting action: CONTINUE_SEQUENCE")
		print("║ Action payload: ", action)
		emit_signal("shoot_action_requested", action)

	print("║ Action emitted successfully")
	print("╚═══════════════════════════════════════════════════════════════")

func _on_shooting_complete() -> void:
	"""Handle shooting completion after final weapon"""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SHOOTING CONTROLLER: SHOOTING COMPLETE")
	print("║ User confirmed completion after viewing final weapon results")
	print("╚═══════════════════════════════════════════════════════════════")

	# Get the current active shooter ID before clearing
	var shooter_id = active_shooter_id

	if shooter_id == "":
		print("WARNING: No active shooter when shooting_complete_confirmed received")
		return

	# Emit action to mark shooter as complete
	emit_signal("shoot_action_requested", {
		"type": "COMPLETE_SHOOTING_FOR_UNIT",
		"actor_unit_id": shooter_id
	})

	# Clear local state
	active_shooter_id = ""
	weapon_assignments.clear()
	_clear_visuals()

	# Show feedback in dice log
	if dice_log_display:
		dice_log_display.append_text("[b][color=green]✓ Shooting complete for unit[/color][/b]\n")

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
		# DEBUG: Log weapon selection
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ WEAPON SELECTED IN TREE")
		print("║ Weapon ID: ", weapon_id)
		print("║ Weapon Name: ", RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id))
		print("║ Has assignment: ", weapon_assignments.has(weapon_id))
		if weapon_assignments.has(weapon_id):
			print("║ Assigned to: ", weapon_assignments[weapon_id])
			print("║ Target name: ", eligible_targets.get(weapon_assignments[weapon_id], {}).get("unit_name", "Unknown"))
		print("║ Current tree text column 1: ", selected.get_text(1))

		# Store selected weapon for modifier application
		selected_weapon_id = weapon_id

		# Visual feedback - highlight the selected weapon
		selected.set_custom_bg_color(0, Color(0.2, 0.4, 0.2, 0.5))

		# FIX: Only update instruction text if weapon doesn't have a target assigned yet
		if not weapon_assignments.has(weapon_id):
			print("║ Setting text to '[Click enemy to assign]' (no assignment)")
			selected.set_text(1, "[Click enemy to assign]")
		else:
			print("║ Keeping existing assignment text (weapon already assigned)")

		print("║ After update, tree text column 1: ", selected.get_text(1))
		print("╚═══════════════════════════════════════════════════════════════")

		# Show modifier panel and load modifiers for this weapon
		if modifier_panel and modifier_label:
			modifier_panel.visible = true
			modifier_label.visible = true
			_load_modifiers_for_weapon(weapon_id)

		# T5-UX1: Update damage preview for selected weapon
		_update_damage_preview(weapon_id)

		# Show a message to the user
		if dice_log_display:
			var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
			if weapon_assignments.has(weapon_id):
				var target_name = eligible_targets.get(weapon_assignments[weapon_id], {}).get("unit_name", "Unknown")
				dice_log_display.append_text("[color=yellow]Selected %s (currently assigned to %s)[/color]\n" % [weapon_name, target_name])
			else:
				dice_log_display.append_text("[color=yellow]Selected %s - Click on an enemy unit to assign target[/color]\n" % weapon_name)

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
	assignment_history.clear()  # T5-UX4: Clear undo history

	# NEW: Hide auto-target button when clearing assignments
	if auto_target_button_container:
		auto_target_button_container.visible = false
	last_assigned_target_id = ""

	_update_ui_state()

# T5-UX4: Undo the most recent weapon assignment
func _on_undo_last_pressed() -> void:
	if assignment_history.is_empty():
		return

	# Pop the most recent weapon_id from the history
	var weapon_id = assignment_history.pop_back()

	print("T5-UX4: Undoing last assignment for weapon: ", weapon_id)

	# Remove from local tracking
	weapon_assignments.erase(weapon_id)

	# Tell the phase to clear this assignment
	emit_signal("shoot_action_requested", {
		"type": "CLEAR_ASSIGNMENT",
		"payload": {"weapon_id": weapon_id}
	})

	# Update weapon tree to clear the target text for this weapon
	if weapon_tree:
		var root = weapon_tree.get_root()
		if root:
			var child = root.get_first_child()
			while child:
				if child.get_metadata(0) == weapon_id:
					child.set_text(1, "[Click enemy to assign]")
					child.clear_custom_bg_color(1)
					break
				child = child.get_next()

	# Update last_assigned_target_id from the remaining history
	if not assignment_history.is_empty():
		var prev_weapon = assignment_history.back()
		last_assigned_target_id = weapon_assignments.get(prev_weapon, "")
	else:
		last_assigned_target_id = ""
		if auto_target_button_container:
			auto_target_button_container.visible = false

	# Show feedback
	if dice_log_display:
		var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		dice_log_display.append_text("[color=orange]↩ Undid assignment for %s[/color]\n" % weapon_name)

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
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ UPDATE UI STATE CALLED")
	print("║ weapon_assignments count: ", weapon_assignments.size())

	if confirm_button:
		confirm_button.disabled = weapon_assignments.is_empty()
	if clear_button:
		clear_button.disabled = weapon_assignments.is_empty()
	if undo_button:
		undo_button.disabled = assignment_history.is_empty()

	# Update target basket
	if target_basket:
		target_basket.clear()
		print("║ Updating target basket:")
		for weapon_id in weapon_assignments:
			var target_id = weapon_assignments[weapon_id]
			var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
			var target_name = eligible_targets.get(target_id, {}).get("unit_name", target_id)
			var display_text = "%s → %s" % [weapon_profile.get("name", weapon_id), target_name]
			target_basket.add_item(display_text)
			print("║   Added to basket: ", display_text)

	# DEBUG: Also log what's in the weapon tree
	print("║ Current weapon tree display:")
	var root = weapon_tree.get_root()
	if root:
		var child = root.get_first_child()
		while child:
			var wpn_id = child.get_metadata(0)
			var wpn_name = child.get_text(0)
			var target_text = child.get_text(1)
			print("║   - %s | Target: %s | Assigned: %s" % [wpn_name, target_text, weapon_assignments.has(wpn_id)])
			child = child.get_next()
	print("╚═══════════════════════════════════════════════════════════════")

func _input(event: InputEvent) -> void:
	# CRITICAL: Skip ALL input handling if wound allocation dialog is showing
	if save_dialog_showing:
		print("ShootingController: Skipping input - wound allocation in progress")
		return

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
		print("[ShootingController] Click detected - assigning target: %s (distance: %.1f)" % [closest_target, closest_distance])
		_select_target_for_current_weapon(closest_target)
	else:
		# REMOVED FALLBACK: Don't auto-assign first target if click misses
		# This was causing weapons to be incorrectly reassigned
		print("[ShootingController] Click missed all targets (closest: %s at %.1f px). Please click directly on enemy model." % [closest_target if closest_target != "" else "none", closest_distance])
		if dice_log_display:
			dice_log_display.append_text("[color=red]Click missed - please click directly on an enemy model[/color]\n")

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

	# DEBUG: Log target assignment
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ TARGET ASSIGNMENT")
	print("║ Weapon ID: ", weapon_id)
	print("║ Weapon Name: ", RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id))
	print("║ Target ID: ", target_id)
	print("║ Target Name: ", eligible_targets.get(target_id, {}).get("unit_name", "Unknown"))
	print("║ Previous assignment: ", weapon_assignments.get(weapon_id, "None"))

	# Assign target
	weapon_assignments[weapon_id] = target_id

	# T5-UX4: Track assignment in history for undo (remove if re-assigned, then push)
	assignment_history.erase(weapon_id)
	assignment_history.push_back(weapon_id)

	print("║ Assignment stored in weapon_assignments dictionary")
	print("║ Current weapon_assignments state:")
	for wpn_id in weapon_assignments:
		var wpn_name = RulesEngine.get_weapon_profile(wpn_id).get("name", wpn_id)
		var tgt_id = weapon_assignments[wpn_id]
		var tgt_name = eligible_targets.get(tgt_id, {}).get("unit_name", "Unknown")
		print("║   - %s → %s" % [wpn_name, tgt_name])
	print("╚═══════════════════════════════════════════════════════════════")

	# NEW: Store last assigned target for "Apply to All" feature
	last_assigned_target_id = target_id

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

	# NEW: Show "Apply to All" button if there are unassigned weapons remaining
	var unassigned_count = _count_unassigned_weapons()
	if unassigned_count > 0 and auto_target_button_container:
		auto_target_button_container.visible = true

		# Update button text to show how many weapons will be affected
		var apply_button = auto_target_button_container.get_node_or_null("ApplyToAllButton")
		if apply_button:
			apply_button.text = "Apply to %d Remaining Weapons" % unassigned_count

	# Show feedback
	if dice_log_display:
		var weapon_name = RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		dice_log_display.append_text("[color=green]✓ Assigned %s to target %s[/color]\n" % [weapon_name, target_name])

	# T5-UX1: Refresh damage preview with newly assigned target
	_last_preview_target_id = ""  # Force recalculation
	_update_damage_preview(weapon_id)

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

	# T5-UX4: Track assignment in history for undo
	assignment_history.erase(weapon_id)
	assignment_history.push_back(weapon_id)

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

# ==========================================
# APPLY TO ALL SYSTEM
# ==========================================

func _count_unassigned_weapons() -> int:
	"""Count how many weapons don't have targets assigned yet"""
	var root = weapon_tree.get_root()
	if not root:
		return 0

	var unassigned = 0
	var child = root.get_first_child()

	while child:
		var weapon_id = child.get_metadata(0)
		if weapon_id and not weapon_assignments.has(weapon_id):
			unassigned += 1
		child = child.get_next()

	return unassigned

func _on_apply_to_all_pressed() -> void:
	"""Apply the last assigned target to all unassigned weapons"""
	if last_assigned_target_id == "" or not eligible_targets.has(last_assigned_target_id):
		print("ERROR: No valid target to apply")
		return

	var target_name = eligible_targets.get(last_assigned_target_id, {}).get("unit_name", last_assigned_target_id)

	# Get all weapons from the tree
	var root = weapon_tree.get_root()
	if not root:
		return

	var assigned_count = 0
	var child = root.get_first_child()

	while child:
		var weapon_id = child.get_metadata(0)

		# Check if this weapon is not yet assigned
		if weapon_id and not weapon_assignments.has(weapon_id):
			# Get model IDs for this weapon
			var model_ids = []
			var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
			for model_id in unit_weapons:
				if weapon_id in unit_weapons[model_id]:
					model_ids.append(model_id)

			# Assign target
			weapon_assignments[weapon_id] = last_assigned_target_id

			# T5-UX4: Track in assignment history for undo
			assignment_history.erase(weapon_id)
			assignment_history.push_back(weapon_id)

			# Update UI for this weapon
			child.set_text(1, target_name)
			child.set_custom_bg_color(1, Color(0.4, 0.2, 0.2, 0.5))

			# Build payload for network sync
			var payload = {
				"weapon_id": weapon_id,
				"target_unit_id": last_assigned_target_id,
				"model_ids": model_ids
			}

			# Add modifiers if they exist
			if weapon_modifiers.has(weapon_id):
				payload["modifiers"] = weapon_modifiers[weapon_id]

			# Emit assignment action
			emit_signal("shoot_action_requested", {
				"type": "ASSIGN_TARGET",
				"payload": payload
			})

			assigned_count += 1

		child = child.get_next()

	# Hide the "Apply to All" button since all weapons are now assigned
	if auto_target_button_container:
		auto_target_button_container.visible = false

	# Show feedback
	if dice_log_display:
		dice_log_display.append_text("[color=green]✓ Applied target %s to %d weapons[/color]\n" %
			[target_name, assigned_count])

	# Update UI state
	_update_ui_state()

# ============================================================================
# GRENADE STRATAGEM SUPPORT
# ============================================================================

func _update_grenade_button_visibility() -> void:
	"""Show/hide the grenade button based on whether any GRENADES units are eligible."""
	if not grenade_button:
		return

	if not current_phase:
		grenade_button.visible = false
		return

	# Only show for the active player
	var current_player = current_phase.get_current_player()

	# Check if local player is the active player (multiplayer support)
	if NetworkManager.is_networked():
		var local_player = NetworkManager.get_local_player()
		if local_player != current_player:
			grenade_button.visible = false
			return

	# Check if any units can use GRENADE
	var eligible = StratagemManager.get_grenade_eligible_units(current_player)
	var player_cp = StratagemManager.get_player_cp(current_player)

	if eligible.is_empty() or player_cp < 1:
		grenade_button.visible = false
	else:
		grenade_button.visible = true
		grenade_button.text = "Use GRENADE (1 CP) — %d unit%s" % [eligible.size(), "s" if eligible.size() != 1 else ""]

func _on_grenade_button_pressed() -> void:
	"""Handle grenade button press - show GrenadeTargetDialog."""
	if not current_phase:
		return

	var current_player = current_phase.get_current_player()
	var eligible = StratagemManager.get_grenade_eligible_units(current_player)

	if eligible.is_empty():
		if dice_log_display:
			dice_log_display.append_text("[color=red]No eligible GRENADES units available[/color]\n")
		return

	print("ShootingController: Opening GrenadeTargetDialog with %d eligible units" % eligible.size())

	var dialog = GrenadeTargetDialog.new()
	dialog.grenade_confirmed.connect(_on_grenade_confirmed)
	dialog.grenade_cancelled.connect(_on_grenade_cancelled)

	get_tree().root.add_child(dialog)
	dialog.setup(current_player, eligible)
	dialog.popup_centered()

func _on_grenade_confirmed(grenade_unit_id: String, target_unit_id: String) -> void:
	"""Handle grenade target selection confirmed - send action."""
	print("ShootingController: Grenade confirmed: %s -> %s" % [grenade_unit_id, target_unit_id])

	if dice_log_display:
		var grenade_unit = GameState.get_unit(grenade_unit_id)
		var target_unit = GameState.get_unit(target_unit_id)
		dice_log_display.append_text("[color=orange]GRENADE: %s throws at %s...[/color]\n" % [
			grenade_unit.get("meta", {}).get("name", grenade_unit_id),
			target_unit.get("meta", {}).get("name", target_unit_id)
		])

	emit_signal("shoot_action_requested", {
		"type": "USE_GRENADE_STRATAGEM",
		"grenade_unit_id": grenade_unit_id,
		"target_unit_id": target_unit_id
	})

func _on_grenade_cancelled() -> void:
	"""Handle grenade dialog cancelled."""
	print("ShootingController: Grenade cancelled")

func _on_grenade_result(result: Dictionary) -> void:
	"""Handle grenade result - show result dialog and update UI."""
	print("ShootingController: Grenade result received: %s" % str(result))

	var dice_rolls = result.get("dice_rolls", [])
	var mortal_wounds = result.get("mortal_wounds", 0)
	var casualties = result.get("casualties", 0)

	# Log to dice display
	if dice_log_display:
		var rolls_str = ""
		for roll in dice_rolls:
			if roll >= 4:
				rolls_str += "[color=green][%d][/color] " % roll
			else:
				rolls_str += "[color=red][%d][/color] " % roll

		dice_log_display.append_text("[color=orange]GRENADE:[/color] Rolled 6D6: %s\n" % rolls_str)
		if mortal_wounds > 0:
			dice_log_display.append_text("[color=green]  → %d mortal wound%s dealt" % [mortal_wounds, "s" if mortal_wounds != 1 else ""])
			if casualties > 0:
				dice_log_display.append_text(", %d model%s destroyed" % [casualties, "s" if casualties != 1 else ""])
			dice_log_display.append_text("[/color]\n")
		else:
			dice_log_display.append_text("[color=gray]  → No mortal wounds dealt[/color]\n")

	# Show result dialog
	var grenade_result_data = {
		"dice_rolls": dice_rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties,
		"grenade_unit_id": result.get("grenade_unit_id", ""),
		"target_unit_id": result.get("target_unit_id", ""),
		"message": result.get("message", "")
	}

	var result_dialog = GrenadeResultDialog.new()
	result_dialog.result_acknowledged.connect(_on_grenade_result_acknowledged)
	get_tree().root.add_child(result_dialog)
	result_dialog.setup(grenade_result_data)
	result_dialog.popup_centered()

func _on_grenade_result_acknowledged() -> void:
	"""Handle grenade result dialog dismissed - refresh UI."""
	print("ShootingController: Grenade result acknowledged, refreshing UI")
	_refresh_unit_list()
	_update_grenade_button_visibility()

# ====================================================================
# T5-MP4: Save dialog timing reliability helpers
# ====================================================================

func _show_waiting_for_saves_feedback(target_id: String, weapon_name: String) -> void:
	"""Show attacker-side feedback while waiting for defender to make saves."""
	var target_unit = GameState.get_unit(target_id)
	var target_name = target_unit.get("meta", {}).get("name", target_id) if not target_unit.is_empty() else target_id

	# Update status label via Main
	var main = get_node_or_null("/root/Main")
	if main and "status_label" in main and main.status_label:
		main.status_label.text = "Waiting for defender to make saves (%s vs %s)..." % [weapon_name, target_name]

	# Also show a toast notification
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_toast("Waiting for defender to resolve saves...", Color.YELLOW, 4.0)

	print("T5-MP4: Showing 'Waiting for defender' feedback — weapon=%s, target=%s" % [weapon_name, target_name])

func _on_save_processing_timeout() -> void:
	"""Safety timeout — reset processing_saves_signal if it got stuck, or handle ack timeout."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ T5-MP4: SAVE PROCESSING TIMEOUT FIRED")
	print("║ Timestamp: ", Time.get_ticks_msec())
	print("║ processing_saves_signal: ", processing_saves_signal)
	print("║ _awaiting_remote_saves: ", _awaiting_remote_saves)
	print("║ _save_ack_received: ", _save_ack_received)

	if _awaiting_remote_saves and not _save_ack_received:
		# Attacker side: defender didn't acknowledge — try re-sending save data
		print("║ Attacker: No ack from defender — attempting retry via NetworkManager")
		print("╚═══════════════════════════════════════════════════════════════")
		_retry_save_data_broadcast()
		return

	if processing_saves_signal:
		# Defender side: processing_saves_signal got stuck — reset it
		print("║ SAFETY RESET: processing_saves_signal was stuck — resetting to false")
		print("║ This allows future saves_required signals to be processed")
		print("╚═══════════════════════════════════════════════════════════════")
		processing_saves_signal = false
		# Re-enable input in case it was disabled
		set_process_input(true)
		set_process_unhandled_input(true)
	else:
		print("║ No action needed — processing_saves_signal already false")
		print("╚═══════════════════════════════════════════════════════════════")

func _retry_save_data_broadcast() -> void:
	"""Re-broadcast save data to defender if ack was not received."""
	if _pending_save_data_for_retry.is_empty():
		print("T5-MP4: No pending save data to retry")
		return

	print("T5-MP4: Retrying save data broadcast (%d entries)" % _pending_save_data_for_retry.size())

	# Ask NetworkManager to re-send the save data via relay
	NetworkManager.retry_save_data_broadcast(_pending_save_data_for_retry)

	# Show updated feedback
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_toast("Retrying save data to defender...", Color.ORANGE, 3.0)

	# Don't retry indefinitely — clear after one retry attempt
	_pending_save_data_for_retry.clear()

func on_save_dialog_acknowledged(target_unit_id: String, weapon_name: String) -> void:
	"""Called by NetworkManager when defender acknowledges receiving the save dialog."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ T5-MP4: SAVE DIALOG ACKNOWLEDGED BY DEFENDER")
	print("║ Timestamp: ", Time.get_ticks_msec())
	print("║ Target: ", target_unit_id)
	print("║ Weapon: ", weapon_name)
	print("╚═══════════════════════════════════════════════════════════════")

	_save_ack_received = true
	_awaiting_remote_saves = false
	_pending_save_data_for_retry.clear()

	# Stop the ack timeout timer
	if _save_processing_timeout_timer:
		_save_processing_timeout_timer.stop()

	# Update attacker feedback
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id) if not target_unit.is_empty() else target_unit_id

	var main = get_node_or_null("/root/Main")
	if main and "status_label" in main and main.status_label:
		main.status_label.text = "Defender is making saves (%s vs %s)..." % [weapon_name, target_name]

func clear_awaiting_saves_state() -> void:
	"""Clear the waiting-for-saves state (called when APPLY_SAVES result arrives)."""
	if _awaiting_remote_saves:
		print("T5-MP4: Clearing awaiting remote saves state")
	_awaiting_remote_saves = false
	_save_ack_received = false
	_pending_save_data_for_retry.clear()
	if _save_processing_timeout_timer:
		_save_processing_timeout_timer.stop()

# ==========================================
# T5-UX1: EXPECTED DAMAGE PREVIEW SYSTEM
# ==========================================

func _on_weapon_tree_mouse_exited() -> void:
	"""Clear hover state when mouse leaves the weapon tree"""
	if _hovered_weapon_id != "" and selected_weapon_id == "":
		_hovered_weapon_id = ""
		_hide_damage_preview()

func _on_weapon_tree_gui_input(event: InputEvent) -> void:
	"""Detect mouse hover over weapon tree items for damage preview"""
	if not event is InputEventMouseMotion:
		return
	if not weapon_tree or active_shooter_id == "":
		return

	var item = weapon_tree.get_item_at_position(event.position)
	if item:
		var weapon_id = item.get_metadata(0)
		if weapon_id and weapon_id != _hovered_weapon_id:
			_hovered_weapon_id = weapon_id
			_update_damage_preview(weapon_id)
	else:
		# Mouse moved off all items — keep preview showing if a weapon is selected
		if _hovered_weapon_id != "" and selected_weapon_id == "":
			_hovered_weapon_id = ""
			_hide_damage_preview()

func _update_damage_preview(weapon_id: String) -> void:
	"""Calculate and display expected damage preview for a weapon"""
	if not damage_preview_panel or not damage_preview_label:
		return

	# Determine target: use assigned target, or first eligible target
	var target_id = ""
	if weapon_assignments.has(weapon_id):
		target_id = weapon_assignments[weapon_id]
	elif not eligible_targets.is_empty():
		target_id = eligible_targets.keys()[0]

	if target_id == "":
		_hide_damage_preview()
		return

	# Skip recalculation if same weapon + target combo
	if weapon_id == _last_preview_weapon_id and target_id == _last_preview_target_id:
		damage_preview_panel.visible = true
		return

	_last_preview_weapon_id = weapon_id
	_last_preview_target_id = target_id

	# Get weapon profile
	var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
	if weapon_profile.is_empty():
		_hide_damage_preview()
		return

	# Get target unit data
	var target_unit = GameState.get_unit(target_id)
	if target_unit.is_empty():
		_hide_damage_preview()
		return

	var target_name = target_unit.get("meta", {}).get("name", target_id)
	var target_stats = target_unit.get("meta", {}).get("stats", {})
	var toughness = target_stats.get("toughness", 4)
	var save_stat = target_stats.get("save", 4)

	# Get number of models with this weapon
	var model_count = 0
	var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
	for model_id in unit_weapons:
		if weapon_id in unit_weapons[model_id]:
			model_count += 1

	# Weapon stats
	var attacks_per_model = weapon_profile.get("attacks", 1)
	var total_attacks = attacks_per_model * model_count
	var strength = weapon_profile.get("strength", 4)
	var ap = weapon_profile.get("ap", 0)
	var damage_per_wound = weapon_profile.get("damage", 1)
	var bs = weapon_profile.get("bs", 4)
	var is_torrent = RulesEngine.is_torrent_weapon(weapon_id)

	# Check for invulnerable save on target models
	var invuln = 0
	var target_models = target_unit.get("models", [])
	for model in target_models:
		if model.get("alive", true):
			invuln = model.get("invuln", 0)
			break  # Use first alive model's invuln

	# Calculate hit probability
	var hit_prob = 0.0
	if is_torrent:
		hit_prob = 1.0
	else:
		hit_prob = max(0.0, (7.0 - bs) / 6.0)

	# Calculate wound probability (S vs T)
	var wound_prob = _calc_wound_probability(strength, toughness)

	# Calculate save probability (considering AP and invuln)
	var modified_save = save_stat + abs(ap)  # AP makes save worse (higher number)
	var best_save = modified_save
	if invuln > 0 and invuln < best_save:
		best_save = invuln  # Invuln is unaffected by AP

	var save_prob = 0.0
	if best_save <= 6:
		save_prob = max(0.0, (7.0 - best_save) / 6.0)

	var unsaved_prob = 1.0 - save_prob

	# Calculate expected values
	var expected_hits = total_attacks * hit_prob
	var expected_wounds = expected_hits * wound_prob
	var expected_unsaved = expected_wounds * unsaved_prob
	var expected_damage = expected_unsaved * damage_per_wound

	# Calculate expected models killed
	var wounds_per_model = target_stats.get("wounds", 1)
	var alive_models = RulesEngine.count_alive_models(target_unit)
	var expected_models_killed = 0.0
	if wounds_per_model > 0:
		expected_models_killed = min(expected_damage / wounds_per_model, alive_models)

	# Build preview BBCode text
	var preview_text = ""
	preview_text += "[color=#D49761]── Expected vs %s ──[/color]\n" % target_name
	preview_text += "[color=#B0B0B0]T%d | Sv%d+" % [toughness, save_stat]
	if invuln > 0:
		preview_text += " | Inv%d+" % invuln
	preview_text += "[/color]\n"

	# Pipeline: Attacks → Hits → Wounds → Unsaved → Damage
	preview_text += "[color=#EBE1C7]Atk: %d[/color]" % total_attacks
	preview_text += " → [color=#88CC88]Hit: %.1f[/color]" % expected_hits
	preview_text += " → [color=#CCCC88]Wnd: %.1f[/color]\n" % expected_wounds
	preview_text += "[color=#CC8888]Unsaved: %.1f[/color]" % expected_unsaved
	preview_text += " → [color=#FF8866]Dmg: %.1f[/color]\n" % expected_damage

	# Models killed estimate
	if expected_models_killed >= 0.1:
		preview_text += "[color=#D49761]~%.1f models killed[/color]" % expected_models_killed
	else:
		preview_text += "[color=#888888]<0.1 models killed[/color]"

	# Show hit/wound/save percentages on a compact line
	var wound_display = _wound_threshold_display(strength, toughness)
	preview_text += "\n[color=#666666]Hit:%d+ Wnd:%s Sv:%d+[/color]" % [bs, wound_display, best_save if best_save <= 6 else 7]

	damage_preview_label.text = ""
	damage_preview_label.append_text(preview_text)
	damage_preview_panel.visible = true

	print("T5-UX1: Damage preview — %s vs %s: %.1f avg dmg, ~%.1f kills" % [
		weapon_profile.get("name", weapon_id), target_name, expected_damage, expected_models_killed])

func _hide_damage_preview() -> void:
	"""Hide the damage preview panel"""
	if damage_preview_panel:
		damage_preview_panel.visible = false
	_last_preview_weapon_id = ""
	_last_preview_target_id = ""

func _calc_wound_probability(strength: int, toughness: int) -> float:
	"""Calculate wound probability based on Strength vs Toughness (10e rules)"""
	if strength >= toughness * 2:
		return 5.0 / 6.0  # 2+
	elif strength > toughness:
		return 4.0 / 6.0  # 3+
	elif strength == toughness:
		return 3.0 / 6.0  # 4+
	elif strength * 2 <= toughness:
		return 1.0 / 6.0  # 6+
	else:
		return 2.0 / 6.0  # 5+

func _wound_threshold_display(strength: int, toughness: int) -> String:
	"""Return the wound threshold as a display string (e.g., '3+')"""
	if strength >= toughness * 2:
		return "2+"
	elif strength > toughness:
		return "3+"
	elif strength == toughness:
		return "4+"
	elif strength * 2 <= toughness:
		return "6+"
	else:
		return "5+"
