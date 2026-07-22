extends PhaseControllerBase
class_name MovementController

const GameStateData = preload("res://autoloads/GameState.gd")
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# Floating-point tolerance for movement cap checks — must match MovementPhase.MOVEMENT_CAP_EPSILON
const MOVEMENT_CAP_EPSILON: float = 0.02

# MovementController - Handles UI interactions for the Movement Phase
# Manages model dragging, path visualization, and movement validation

signal move_action_requested(action: Dictionary)
signal movement_preview_updated(unit_id: String, model_id: String, valid: bool)
signal ui_update_requested()  # Signal to request UI refresh

# Movement state
var current_phase = null  # Can be MovementPhase or null
var active_unit_id: String = ""
# 11e 18.04: unit_id -> bool, set when the DisembarkDialog's Combat
# Disembark toggle was checked; consumed when CONFIRM_DISEMBARK is built.
var _pending_combat_disembark: Dictionary = {}
# The live DisembarkController placement (at most one). Selecting another unit
# or starting a second disembark cancels the previous placement — a stale
# controller kept processing board clicks against its OWN transport, spamming
# "Must be within 3\" of transport" errors measured from the wrong vehicle
# while its (unrotated) range border stayed on screen.
var _active_disembark_controller: Node = null
var active_mode: String = ""  # NORMAL, ADVANCE, FALL_BACK
var move_cap_inches: float = 0.0
var selected_model: Dictionary = {}
var dragging_model: bool = false
var drag_start_pos: Vector2

# T03: drag-ruler segments. Computed by compute_drag_segments() so scenarios
# can assert color_slot per cursor position. Schema:
#   [{from: Vector2, to: Vector2, color_slot: String, distance_inches: float}]
# color_slot is one of CONFIRMED_GREEN / MARGINAL_YELLOW / INVALID_RED.
var current_drag_segments: Array = []

const T03_ADVANCE_INCHES := 6.0  # 40k 10e advance: M + d6, capped here at 6"

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
# True while _end_group_drag's staging pipeline (dispatch + verify/retry) is in
# flight. The pad router waits on this before auto-regrabbing leftovers or
# confirming a Start-pressed move, so it never reads a half-staged unit.
var group_drop_in_flight: bool = false

# UI References (board_view / hud_bottom / hud_right live in PhaseControllerBase)
var path_visual: Line2D
var staged_path_visual: Line2D  # NEW: Visual for staged movements
var ruler_visual: Line2D
var ghost_visual: Node2D
var model_path_visuals: Dictionary = {}  # Dictionary of model_id -> Line2D for individual paths
var movement_path_preview: Node2D = null  # P3-125: HumanMovementPathVisual for drag-to-plan preview
var move_range_visual: Node2D = null  # T-094: Container for movement range circle overlay
var er_overlay_visual: Node2D = null  # T-094: Container for enemy engagement-range rings during move
var coherency_dots_visual: Node2D = null  # T-094: Container for friendly coherency dots during move
var ui_setup_complete: bool = false  # Flag to prevent duplicate UI creation

# Floating movement indicator (shown near model during drag)
var movement_remaining_label: Label
# P3-116: Coherency status label shown below movement remaining label
var coherency_status_label: Label
var _last_coherency_state: bool = true  # Track state changes to avoid per-frame logging

# UI Elements
var move_cap_label: Label
var inches_used_label: Label
var inches_left_label: Label
var illegal_reason_label: Label
var unit_list: ItemList
var dice_log_display: RichTextLabel
var dice_roll_visual: DiceRollVisual  # P3-118: Dice roll visualization for reroll comparisons

# New UI elements for 4-section layout
var selected_unit_label: Label
var unit_mode_label: Label
var mode_button_group: ButtonGroup
var normal_radio: CheckBox
var advance_radio: CheckBox
var fall_back_radio: CheckBox
var stationary_radio: CheckBox
var confirm_mode_button: Button
# ISS-073 (24.35): optional Super-Heavy Walker MOBILE gamble toggle. Visible only
# for SUPER-HEAVY WALKER units at edition >= 11; its value is wired into the
# BEGIN_NORMAL_MOVE / BEGIN_ADVANCE / BEGIN_FALL_BACK payload as shw_mobile_gamble.
var shw_gamble_checkbox: CheckBox = null
# B2 (21.03): "take to the skies" toggle for FLY units at edition >= 11.
var take_to_skies_checkbox: CheckBox = null
# Guard so programmatic checkbox syncs (from phase move data) don't re-enter
# _on_take_to_skies_toggled and dispatch spurious SET_TAKE_TO_SKIES actions.
var _syncing_take_to_skies: bool = false
# Turbo Boostas (Speedwaaagh!): "use turbo" toggle for SPEED FREEKS / TRUKK
# units at edition >= 11 — Advance becomes a flat 24" move (no roll), ranged
# weapons gain ASSAULT and the unit cannot charge this turn.
var turbo_boost_checkbox: CheckBox = null
var advance_roll_label: Label

# Flag to prevent duplicate actions when programmatically setting radio buttons
var setting_radio_programmatically: bool = false

# QoL: when the player has moved models for a unit but never clicked "Confirm
# Move", treat that move as confirmed the moment they end the phase or switch to
# another unit. This guard prevents re-entrancy while the auto-dispatched
# CONFIRM_UNIT_MOVE runs (it fires unit_move_confirmed → _auto_select_next_unmoved).
var _auto_confirming_pending_move: bool = false

# OA-24: PopupMenu for special movement actions (e.g. Kunnin' Infiltrator)
var _movement_action_popup: PopupMenu = null
var _popup_pending_unit_id: String = ""  # Unit awaiting action choice from popup
var _kunnin_infiltrator_button: Button = null  # Persistent button in mode selection panel

# Path tracking
var current_path: Array = []  # Array of Vector2 points
var path_valid: bool = false

# Helper function to get unit movement stat with proper error handling
func get_unit_movement(unit: Dictionary) -> float:
	var movement: float = 6.0
	# Try the expected path first
	if unit.has("meta") and unit.meta.has("stats") and unit.meta.stats.has("move"):
		movement = float(unit.meta.stats.move)
	elif unit.get("meta", {}).get("stats", {}).has("move"):
		# Try nested get with type safety
		movement = float(unit.get("meta", {}).get("stats", {}).get("move"))
	else:
		# Log warning and use default
		var unit_name = unit.get("meta", {}).get("name", "Unknown")
		push_warning("MovementController: Unit %s missing movement stat, using default: 6" % unit_name)

	# SPECIAL DOSE: +6" to Move while Waaagh! active (Zodgrod Wortsnagga)
	if unit.get("flags", {}).get("special_dose_active", false):
		var old_movement = movement
		movement += 6.0
		print("MovementController: Special Dose — movement %d → %d (+6\")" % [int(old_movement), int(movement)])

	return movement

# T03: compute the colored drag-ruler segments for a model being moved from
# from_pt to to_pt. Reads the unit's M from get_unit_movement and applies a
# fixed Advance budget of T03_ADVANCE_INCHES inches. Returns an array of
# {from, to, color_slot, distance_inches} dicts. Always also stores into
# current_drag_segments so scenarios can read the latest result.
func compute_drag_segments(unit_id: String, from_pt: Vector2, to_pt: Vector2) -> Array:
	current_drag_segments = []
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return current_drag_segments
	var unit = gs.get_unit(unit_id)
	if typeof(unit) != TYPE_DICTIONARY or unit.is_empty():
		return current_drag_segments
	var move_inches: float = get_unit_movement(unit)
	var advance_inches: float = T03_ADVANCE_INCHES
	var px_per_inch: float = float(Measurement.PX_PER_INCH)
	var move_px: float = move_inches * px_per_inch
	var advance_px: float = (move_inches + advance_inches) * px_per_inch
	var total_px: float = from_pt.distance_to(to_pt)
	if total_px <= 0.0:
		return current_drag_segments
	var dir: Vector2 = (to_pt - from_pt) / total_px

	var cuts: Array = [0.0]
	if move_px < total_px:
		cuts.append(move_px)
	if advance_px < total_px:
		cuts.append(advance_px)
	cuts.append(total_px)
	for i in range(cuts.size() - 1):
		var t0: float = cuts[i]
		var t1: float = cuts[i + 1]
		if t1 <= t0:
			continue
		var seg_from: Vector2 = from_pt + dir * t0
		var seg_to: Vector2 = from_pt + dir * t1
		var mid: float = (t0 + t1) * 0.5
		var color_slot: String
		if mid <= move_px:
			color_slot = "CONFIRMED_GREEN"
		elif mid <= advance_px:
			color_slot = "MARGINAL_YELLOW"
		else:
			color_slot = "INVALID_RED"
		current_drag_segments.append({
			"from": seg_from,
			"to": seg_to,
			"color_slot": color_slot,
			"distance_inches": (t1 - t0) / px_per_inch,
		})
	return current_drag_segments


func _ready() -> void:
	# Add to group so DisembarkController can find us
	add_to_group("movement_controller")

	set_process_unhandled_input(true)
	set_process(true)  # Enable process for debugging
	_setup_ui_references()
	_create_path_visuals()
	print("MovementController ready")

func _exit_tree() -> void:
	# A still-open disembark placement must not outlive the phase — cancel it so
	# its input processing and range border don't leak into the next phase.
	_cancel_active_disembark_placement()

	# Clean up visuals that were added to BoardRoot
	if path_visual and is_instance_valid(path_visual):
		path_visual.queue_free()
	if staged_path_visual and is_instance_valid(staged_path_visual):
		staged_path_visual.queue_free()
	if ruler_visual and is_instance_valid(ruler_visual):
		ruler_visual.queue_free()  
	if ghost_visual and is_instance_valid(ghost_visual):
		ghost_visual.queue_free()

	# T-094: Free the movement-only overlay containers that live under BoardRoot.
	# These were previously leaked on phase exit, so any rings still present when
	# the Movement phase ended survived into the Shooting phase. The enemy
	# engagement-range overlay (the red "don't move here" circles) was the most
	# visible offender and cluttered the board once movement was over. Free all
	# three so no movement-only overlay outlives the phase.
	if move_range_visual and is_instance_valid(move_range_visual):
		move_range_visual.queue_free()
		move_range_visual = null
	if er_overlay_visual and is_instance_valid(er_overlay_visual):
		er_overlay_visual.queue_free()
		er_overlay_visual = null
	if coherency_dots_visual and is_instance_valid(coherency_dots_visual):
		coherency_dots_visual.queue_free()
		coherency_dots_visual = null

	# Clean up individual model path visuals
	for model_id in model_path_visuals:
		var line = model_path_visuals[model_id]
		if line and is_instance_valid(line):
			line.queue_free()
	model_path_visuals.clear()

	# P3-125: Clean up movement path preview
	if movement_path_preview and is_instance_valid(movement_path_preview):
		movement_path_preview.queue_free()
		movement_path_preview = null

	# Clean up multi-selection visuals
	if selection_visual and is_instance_valid(selection_visual):
		selection_visual.queue_free()

	# Clean up selection indicators
	for indicator in selection_indicators:
		if indicator and is_instance_valid(indicator):
			indicator.queue_free()
	selection_indicators.clear()
	
	# Clean up UI containers
	var movement_info = SceneRefs.main_path("HUD_Bottom/HBoxContainer/MovementInfo")
	if movement_info and is_instance_valid(movement_info):
		movement_info.queue_free()

	var movement_buttons = SceneRefs.main_path("HUD_Bottom/HBoxContainer/MovementButtons")
	if movement_buttons and is_instance_valid(movement_buttons):
		movement_buttons.queue_free()

	# Clean up right panel elements (standard pattern)
	var container = SceneRefs.hud_right_vbox()
	if container and is_instance_valid(container):
		var movement_elements = ["MovementScrollContainer", "MovementPanel"]
		for element in movement_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("MovementController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

	# OA-24: Clean up movement action popup
	if _movement_action_popup and is_instance_valid(_movement_action_popup):
		_movement_action_popup.queue_free()
		_movement_action_popup = null

	# Reset UI setup flag
	ui_setup_complete = false

func _create_path_visuals() -> void:
	# Get references to the proper layers in BoardRoot
	var board_root = SceneRefs.board_root()
	if not board_root:
		print("ERROR: Cannot find BoardRoot for visual layers")
		return
	
	# Create path visualization line in BoardRoot space
	path_visual = Line2D.new()
	path_visual.name = "MovementPathVisual"
	path_visual.width = 3.0
	path_visual.default_color = Color(0.2, 1.0, 0.4, 0.85)
	path_visual.begin_cap_mode = Line2D.LINE_CAP_ROUND
	path_visual.end_cap_mode = Line2D.LINE_CAP_ROUND
	path_visual.add_point(Vector2.ZERO)  # Dummy point
	path_visual.clear_points()
	board_root.add_child(path_visual)
	
	# Create staged path visualization line (yellow for staged moves)
	staged_path_visual = Line2D.new()
	staged_path_visual.name = "StagedMovementPathVisual"
	staged_path_visual.width = 2.5
	staged_path_visual.default_color = Color(1.0, 0.85, 0.2, 0.7)
	staged_path_visual.begin_cap_mode = Line2D.LINE_CAP_ROUND
	staged_path_visual.end_cap_mode = Line2D.LINE_CAP_ROUND
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

	# P3-125: Create movement path preview visual (dashed lines with arrowheads)
	var HumanMovementPathVisualScript = preload("res://scripts/HumanMovementPathVisual.gd")
	movement_path_preview = Node2D.new()
	movement_path_preview.set_script(HumanMovementPathVisualScript)
	movement_path_preview.name = "HumanMovementPathPreview"
	board_root.add_child(movement_path_preview)

	# Create selection box visual for drag-box selection (custom drawn)
	selection_visual = _SelectionBoxVisual.new()
	selection_visual.name = "MultiSelectionBox"
	selection_visual.visible = false
	board_root.add_child(selection_visual)

	# T-094: Movement range overlay (circle showing unit's move cap around active unit)
	move_range_visual = Node2D.new()
	move_range_visual.name = "MoveRangeVisual"
	board_root.add_child(move_range_visual)

	# T-094: ER overlay container (engagement-range rings around enemy models during movement)
	er_overlay_visual = Node2D.new()
	er_overlay_visual.name = "MovementERVisual"
	board_root.add_child(er_overlay_visual)

	# T-094: Coherency dots container (2" rings around friendly staged positions)
	coherency_dots_visual = Node2D.new()
	coherency_dots_visual.name = "MovementCoherencyVisual"
	board_root.add_child(coherency_dots_visual)

func _setup_bottom_hud() -> void:
	# NOTE: Main.gd now handles the phase action button
	# MovementController only manages movement-specific UI in the right panel
	pass

# NOTE: do NOT grab the persistent UnitListPanel — the movement controller
# creates its own ItemList in _create_section1_unit_list(). Reusing the
# persistent one causes an "already has a parent" error on add_child.
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
	label.text = "UNITS (MOVE / DISEMBARK)"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	section.add_child(label)

	# Always create a fresh ItemList for the movement panel
	unit_list = ItemList.new()
	unit_list.name = "MovementUnitList"
	unit_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	unit_list.custom_minimum_size = Vector2(0, 120)
	_WhiteDwarfTheme.apply_to_item_list(unit_list)

	# Connect unit selection signal
	if not unit_list.item_selected.is_connected(_on_unit_selected):
		unit_list.item_selected.connect(_on_unit_selected)

	section.add_child(unit_list)
	parent.add_child(section)

func _create_section2_unit_details(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()
	section.name = "Section2_UnitDetails"

	_add_movement_gold_separator(parent)

	var label = Label.new()
	label.text = "SELECTED UNIT"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	section.add_child(label)

	selected_unit_label = Label.new()
	selected_unit_label.text = "Unit: None Selected"
	selected_unit_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	section.add_child(selected_unit_label)

	unit_mode_label = Label.new()
	unit_mode_label.text = "Mode: Normal Move (Default)"
	unit_mode_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	section.add_child(unit_mode_label)

	# Add helpful hint
	var hint_label = Label.new()
	hint_label.text = "Drag models to move, or select a different mode below"
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.48, 0.4))
	section.add_child(hint_label)

	parent.add_child(section)

func _create_section3_mode_selection(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()
	section.name = "Section3_ModeSelection"

	_add_movement_gold_separator(parent)

	var label = Label.new()
	label.text = "MOVEMENT MODE"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	section.add_child(label)
	
	# Create radio button group
	mode_button_group = ButtonGroup.new()
	
	var button_container = HBoxContainer.new()
	button_container.name = "ModeButtons"
	
	# Create radio buttons (CheckBox with ButtonGroup for radio behavior)
	normal_radio = CheckBox.new()
	normal_radio.text = "Normal Move"
	normal_radio.toggle_mode = true
	normal_radio.button_group = mode_button_group
	normal_radio.pressed.connect(_on_normal_move_pressed)
	normal_radio.tooltip_text = "Move up to the unit's Move characteristic."
	normal_radio.add_theme_font_size_override("font_size", 13)
	normal_radio.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	normal_radio.add_theme_color_override("font_pressed_color", Color(0.6, 0.85, 1.0))
	button_container.add_child(normal_radio)

	advance_radio = CheckBox.new()
	advance_radio.text = "Advance"
	advance_radio.toggle_mode = true
	advance_radio.button_group = mode_button_group
	advance_radio.pressed.connect(_on_advance_pressed)
	advance_radio.tooltip_text = "Move + D6\". Unit cannot shoot or charge this turn."
	advance_radio.add_theme_font_size_override("font_size", 13)
	advance_radio.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	advance_radio.add_theme_color_override("font_pressed_color", Color(0.5, 1.0, 0.5))
	button_container.add_child(advance_radio)

	fall_back_radio = CheckBox.new()
	fall_back_radio.text = "Fall Back"
	fall_back_radio.toggle_mode = true
	fall_back_radio.button_group = mode_button_group
	fall_back_radio.pressed.connect(_on_fall_back_pressed)
	fall_back_radio.tooltip_text = "Disengage from combat. Unit cannot shoot or charge this turn."
	fall_back_radio.add_theme_font_size_override("font_size", 13)
	fall_back_radio.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	fall_back_radio.add_theme_color_override("font_pressed_color", Color(1.0, 0.6, 0.5))
	button_container.add_child(fall_back_radio)

	stationary_radio = CheckBox.new()
	stationary_radio.text = "Remain Still"
	stationary_radio.toggle_mode = true
	stationary_radio.button_group = mode_button_group
	stationary_radio.pressed.connect(_on_remain_stationary_pressed)
	stationary_radio.tooltip_text = "Unit does not move this phase. Counts as having Remained Stationary."
	stationary_radio.add_theme_font_size_override("font_size", 13)
	stationary_radio.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	stationary_radio.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.8))
	button_container.add_child(stationary_radio)
	
	section.add_child(button_container)

	# OA-24: Add Kunnin' Infiltrator button (hidden by default, shown when ability available)
	_kunnin_infiltrator_button = Button.new()
	_kunnin_infiltrator_button.name = "KunninInfiltratorButton"
	_kunnin_infiltrator_button.text = "Kunnin' Infiltrator (Redeploy)"
	_kunnin_infiltrator_button.visible = false
	_kunnin_infiltrator_button.pressed.connect(_on_kunnin_infiltrator_button_pressed)
	_WhiteDwarfTheme.apply_to_button(_kunnin_infiltrator_button)
	section.add_child(_kunnin_infiltrator_button)

	# Add dice result display (hidden initially)
	advance_roll_label = Label.new()
	advance_roll_label.text = "Advance Roll: -"
	advance_roll_label.visible = false
	section.add_child(advance_roll_label)

	# Issue #51: "Confirm movement mode" button. Once pressed, locks
	# the mode for this unit so the player must finish moving it
	# before switching to another mode or selecting another unit.
	# Wires to the existing _on_confirm_mode_pressed handler (which
	# dispatches LOCK_MOVEMENT_MODE, handles ADVANCE roll and
	# REMAIN_STATIONARY auto-complete, and disables mode radios).
	confirm_mode_button = Button.new()
	confirm_mode_button.name = "ConfirmModeButton"
	confirm_mode_button.text = "Confirm Movement Mode"
	confirm_mode_button.tooltip_text = "Lock the selected movement mode and begin moving this unit. Cannot be undone for this unit this turn."
	confirm_mode_button.disabled = true
	confirm_mode_button.visible = false  # Only shown for Advance / Remain Still
	confirm_mode_button.pressed.connect(_on_confirm_mode_pressed)
	_WhiteDwarfTheme.apply_to_button(confirm_mode_button)
	section.add_child(confirm_mode_button)

	# ISS-073 (24.35): Super-Heavy Walker MOBILE gamble toggle. A SUPER-HEAVY
	# WALKER may opt to grant all its models MOBILE for this move (letting it
	# cross dense terrain it could not otherwise) — but at move end it rolls a
	# D6 and on a 1 the unit is battle-shocked. Hidden by default; shown only
	# for SUPER-HEAVY WALKER units at edition >= 11 (see _update_shw_gamble_visibility).
	shw_gamble_checkbox = CheckBox.new()
	shw_gamble_checkbox.name = "ShwMobileGambleCheckBox"
	shw_gamble_checkbox.text = "Risk MOBILE (D6: 1 = battle-shock)"
	shw_gamble_checkbox.toggle_mode = true
	shw_gamble_checkbox.visible = false
	shw_gamble_checkbox.tooltip_text = "Super-Heavy Walker (24.35): grant all models MOBILE for this move to cross dense terrain. At move end roll a D6 — on a 1 the unit is battle-shocked."
	shw_gamble_checkbox.add_theme_font_size_override("font_size", 13)
	shw_gamble_checkbox.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	shw_gamble_checkbox.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.4))
	section.add_child(shw_gamble_checkbox)

	# B2 (21.03): "take to the skies" toggle. A FLY unit may declare it will fly
	# over this move — -2" max distance (0 with HOVER), ignoring vertical and
	# moving through all models/terrain. Shown only for FLY units at edition >= 11.
	take_to_skies_checkbox = CheckBox.new()
	take_to_skies_checkbox.name = "TakeToSkiesCheckBox"
	take_to_skies_checkbox.text = "Take to the skies (-2\" move)"
	take_to_skies_checkbox.toggle_mode = true
	take_to_skies_checkbox.visible = false
	take_to_skies_checkbox.tooltip_text = "FLY (21.03): fly over this move — subtract 2\" from the max distance (0 with HOVER), ignore vertical distance, and move through all models and terrain."
	take_to_skies_checkbox.add_theme_font_size_override("font_size", 13)
	take_to_skies_checkbox.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	take_to_skies_checkbox.add_theme_color_override("font_pressed_color", Color(0.7, 0.9, 1.0))
	# The default drag flow auto-begins a NORMAL move at unit selection, before
	# the player can tick this box — forward later ticks to the active move.
	take_to_skies_checkbox.toggled.connect(_on_take_to_skies_toggled)
	section.add_child(take_to_skies_checkbox)

	# Turbo Boostas (Speedwaaagh! detachment rule): "use turbo" toggle. Shown
	# only for SPEED FREEKS / TRUKK units (excl. AIRCRAFT) of a Speedwaaagh!
	# player at edition >= 11. Applies to Advance only: no roll, flat 24"
	# move, ranged weapons gain ASSAULT, cannot charge this turn.
	turbo_boost_checkbox = CheckBox.new()
	turbo_boost_checkbox.name = "TurboBoostCheckBox"
	turbo_boost_checkbox.text = "Use turbo (Advance: flat 24\", no charge)"
	turbo_boost_checkbox.toggle_mode = true
	turbo_boost_checkbox.visible = false
	turbo_boost_checkbox.tooltip_text = "Turbo Boostas (Speedwaaagh!): instead of rolling for this Advance, move a flat 24\". Ranged weapons gain ASSAULT until end of turn and the unit cannot declare a charge."
	turbo_boost_checkbox.add_theme_font_size_override("font_size", 13)
	turbo_boost_checkbox.add_theme_color_override("font_color", Color(1.0, 0.45, 0.25))
	turbo_boost_checkbox.add_theme_color_override("font_pressed_color", Color(1.0, 0.6, 0.35))
	section.add_child(turbo_boost_checkbox)

	parent.add_child(section)

func _create_section4_actions(parent: VBoxContainer) -> void:
	var section = VBoxContainer.new()
	section.name = "Section4_Actions"

	_add_movement_gold_separator(parent)

	var label = Label.new()
	label.text = "MOVEMENT ACTIONS"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	section.add_child(label)
	
	# Distance information
	var distance_info = VBoxContainer.new()
	distance_info.name = "DistanceInfo"

	move_cap_label = Label.new()
	move_cap_label.text = "Move: 0\""
	move_cap_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	move_cap_label.add_theme_font_size_override("font_size", 12)
	distance_info.add_child(move_cap_label)

	inches_used_label = Label.new()
	inches_used_label.text = "Used: 0\""
	inches_used_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	inches_used_label.add_theme_font_size_override("font_size", 12)
	distance_info.add_child(inches_used_label)

	inches_left_label = Label.new()
	inches_left_label.text = "Left: 0\""
	inches_left_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
	inches_left_label.add_theme_font_size_override("font_size", 12)
	distance_info.add_child(inches_left_label)

	illegal_reason_label = Label.new()
	illegal_reason_label.text = ""
	illegal_reason_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	illegal_reason_label.add_theme_font_size_override("font_size", 11)
	distance_info.add_child(illegal_reason_label)
	
	section.add_child(distance_info)
	
	# Action buttons (moved from top panel)
	var button_container = HBoxContainer.new()
	button_container.name = "ActionButtons"
	
	var undo_button = Button.new()
	undo_button.name = "UndoModelButton"
	undo_button.text = "Undo Model"
	undo_button.pressed.connect(_on_undo_model_pressed)
	_WhiteDwarfTheme.apply_secondary_button(undo_button)
	button_container.add_child(undo_button)

	var reset_button = Button.new()
	reset_button.name = "ResetUnitButton"
	reset_button.text = "Reset Unit"
	reset_button.pressed.connect(_on_reset_unit_pressed)
	_WhiteDwarfTheme.apply_secondary_button(reset_button)
	button_container.add_child(reset_button)

	var confirm_button = Button.new()
	confirm_button.name = "ConfirmMoveButton"
	# "End This Unit's Move" (not "Confirm Move") so it is not confused with the
	# "Confirm Movement Mode" button above: this button FINALISES the unit's move
	# for the phase, it does NOT lock in the chosen mode. Players were clicking it
	# right after picking Advance and ending the move without actually advancing.
	confirm_button.text = "End This Unit's Move"
	confirm_button.tooltip_text = "Finish and lock in this unit's movement for the phase. Do this AFTER you have moved the models. (This is not the same as 'Confirm Movement Mode', which starts an Advance / Remain Stationary.)"
	confirm_button.pressed.connect(_on_confirm_move_pressed)
	_WhiteDwarfTheme.apply_primary_button(confirm_button)
	button_container.add_child(confirm_button)
	
	section.add_child(button_container)
	parent.add_child(section)

func _add_movement_gold_separator(parent: VBoxContainer) -> void:
	var spacer_top = Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 2)
	parent.add_child(spacer_top)
	var sep = ColorRect.new()
	sep.color = Color(_WhiteDwarfTheme.WH_GOLD, 0.3)
	sep.custom_minimum_size = Vector2(0, 1)
	parent.add_child(sep)
	var spacer_bot = Control.new()
	spacer_bot.custom_minimum_size = Vector2(0, 2)
	parent.add_child(spacer_bot)

func _create_dice_log_display(parent: VBoxContainer) -> void:
	# Create dice log display only if it doesn't exist
	if not dice_log_display:
		var existing_dice_log = parent.get_node_or_null("DiceLog")
		if not existing_dice_log:
			var dice_label = Label.new()
			dice_label.text = "Dice Log:"
			dice_label.add_theme_font_size_override("font_size", 12)
			dice_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
			if FactionPalettes.FONT_RAJDHANI_BOLD:
				dice_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
			parent.add_child(dice_label)

			dice_log_display = RichTextLabel.new()
			dice_log_display.name = "DiceLog"
			dice_log_display.custom_minimum_size = Vector2(300, 200)  # Increased height to use more space
			dice_log_display.bbcode_enabled = true
			parent.add_child(dice_log_display)

	# P3-118: Add dice roll visual for reroll comparisons
	if not dice_roll_visual:
		dice_roll_visual = DiceRollVisual.new()
		dice_roll_visual.custom_minimum_size = Vector2(200, 0)
		dice_roll_visual.visible = false
		parent.add_child(dice_roll_visual)

func _update_selected_unit_display() -> void:
	if selected_unit_label:
		var unit_name = "None Selected"
		if active_unit_id != "" and current_phase:
			var unit = current_phase.get_unit(active_unit_id)
			if unit:
				unit_name = unit.get("meta", {}).get("name", active_unit_id)
				# Show attached character names for bodyguard units
				var attached_char_ids = unit.get("attachment_data", {}).get("attached_characters", [])
				if attached_char_ids.size() > 0:
					var char_names = []
					for char_id in attached_char_ids:
						var char_unit = GameState.get_unit(char_id)
						if not char_unit.is_empty():
							char_names.append(char_unit.get("meta", {}).get("name", char_id))
					if char_names.size() > 0:
						unit_name += " + " + ", ".join(char_names)
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
			# P3-118: Connect reroll completed signal for visualization
			if phase.has_signal("command_reroll_completed"):
				if not phase.command_reroll_completed.is_connected(_on_command_reroll_completed):
					phase.command_reroll_completed.connect(_on_command_reroll_completed)
			if phase.has_signal("overwatch_opportunity"):
				if not phase.overwatch_opportunity.is_connected(_on_overwatch_opportunity):
					phase.overwatch_opportunity.connect(_on_overwatch_opportunity)
			if phase.has_signal("rapid_ingress_opportunity"):
				if not phase.rapid_ingress_opportunity.is_connected(_on_rapid_ingress_opportunity):
					phase.rapid_ingress_opportunity.connect(_on_rapid_ingress_opportunity)
			if phase.has_signal("krump_and_run_opportunity"):
				if not phase.krump_and_run_opportunity.is_connected(_on_krump_and_run_opportunity):
					phase.krump_and_run_opportunity.connect(_on_krump_and_run_opportunity)
			if phase.has_signal("kunnin_infiltrator_available"):
				if not phase.kunnin_infiltrator_available.is_connected(_on_kunnin_infiltrator_available):
					phase.kunnin_infiltrator_available.connect(_on_kunnin_infiltrator_available)
			if phase.has_signal("scatter_opportunity"):
				if not phase.scatter_opportunity.is_connected(_on_scatter_opportunity):
					phase.scatter_opportunity.connect(_on_scatter_opportunity)

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

# Read-only accessor for tests/scenarios: how many "arrive from reserves"
# rows the movement unit list is currently offering the player. 0 means no
# reinforcements are on offer (correct on the first turn / before Round 2).
# Counts the reserve rows between the "--- REINFORCEMENTS ---" header and the
# "--- DEPLOYED UNITS ---" separator (the header itself is not counted).
func get_reinforcement_row_count() -> int:
	if not unit_list:
		return 0
	var count := 0
	var in_reinforcements := false
	for i in range(unit_list.get_item_count()):
		var text := unit_list.get_item_text(i)
		if text.begins_with("--- REINFORCEMENTS"):
			in_reinforcements = true
			continue
		if text.begins_with("--- DEPLOYED UNITS"):
			in_reinforcements = false
			continue
		if in_reinforcements:
			count += 1
	return count

# Read-only accessor for tests/scenarios: the current unit-list row texts.
# Used to assert duplicate squads render distinct (display_name) rows.
func get_unit_list_texts() -> Array:
	var out := []
	if unit_list:
		for i in range(unit_list.get_item_count()):
			out.append(unit_list.get_item_text(i))
	return out

func _refresh_unit_list() -> void:
	if not unit_list or not current_phase:
		return

	unit_list.clear()
	var actions = current_phase.get_available_actions()
	var added_units = {}

	# Debug: Log all actions returned by the phase
	print("MovementController: _refresh_unit_list — got %d actions from phase" % actions.size())
	for dbg_action in actions:
		print("MovementController:   Action type=%s actor_unit_id=%s desc=%s" % [
			dbg_action.get("type", "?"),
			dbg_action.get("actor_unit_id", dbg_action.get("unit_id", "none")),
			dbg_action.get("description", "")
		])

	# Show reinforcement units (PLACE_REINFORCEMENT actions use "unit_id" not "actor_unit_id")
	var has_reinforcements = false
	for action in actions:
		if action.get("type", "") == "PLACE_REINFORCEMENT":
			var reserve_unit_id = action.get("unit_id", "")
			if reserve_unit_id != "" and not added_units.has(reserve_unit_id):
				if not has_reinforcements:
					unit_list.add_item("--- REINFORCEMENTS (Click to Deploy) ---")
					unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)
					has_reinforcements = true
				var desc = action.get("description", reserve_unit_id)
				unit_list.add_item(desc)
				unit_list.set_item_metadata(unit_list.get_item_count() - 1, reserve_unit_id)
				added_units[reserve_unit_id] = true

	if has_reinforcements:
		unit_list.add_item("--- DEPLOYED UNITS ---")
		unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)

	# OA-24: Build a set of unit_ids that have special movement actions
	var _special_action_types = ["ACTIVATE_KUNNIN_INFILTRATOR"]
	var units_with_special_actions = {}
	for action in actions:
		if action.get("type", "") in _special_action_types:
			units_with_special_actions[action.get("actor_unit_id", "")] = action.get("type", "")

	for action in actions:
		var unit_id = action.get("actor_unit_id", "")
		if unit_id != "" and not added_units.has(unit_id):
			var unit = current_phase.get_unit(unit_id)
			# Use display_name so duplicate squads (e.g. "Custodian Guard Alpha"
			# vs "Custodian Guard Beta") stay distinguishable in the unit list
			# instead of collapsing to an identical "Custodian Guard" for each.
			var _uname_meta = unit.get("meta", {})
			var unit_name = _uname_meta.get("display_name", _uname_meta.get("name", unit_id))
			var action_type = action.get("type", "")

			# NOTE: attached character names are appended below via `attach_info`
			# (just before add_item). Do NOT also append them to unit_name here —
			# doing both double-printed the leader, e.g.
			# "Custodian Guard Alpha + Blade Champion + Blade Champion".

			var status = _get_unit_movement_status(unit_id)
			var status_text = ""

			match status:
				"not_moved":
					status_text = " [YET TO MOVE]"
				"moving":
					status_text = " [CURRENTLY MOVING]"
				"completed":
					status_text = " [COMPLETED MOVING]"

			# OA-24: Show ability indicator for units with special movement actions
			if units_with_special_actions.has(unit_id):
				status_text += " *ABILITY*"

			# Show if unit is embarked (special case - can still be selected to disembark)
			if unit.get("embarked_in", null) != null:
				var transport = GameState.get_unit(unit.embarked_in)
				var transport_name = transport.get("meta", {}).get("name", unit.embarked_in) if transport else "Transport"
				if action_type == "DISEMBARK_UNIT":
					status_text = " [Embarked in %s — Click to Disembark]" % transport_name
				elif action_type == "DISEMBARK_BLOCKED":
					status_text = " [Embarked in %s — Cannot Disembark]" % transport_name
				else:
					status_text = " [Embarked in %s]" % transport_name

			# Show attached character names for bodyguard units
			var attach_info = ""
			var attached_char_ids = unit.get("attachment_data", {}).get("attached_characters", [])
			if attached_char_ids.size() > 0:
				var char_names = []
				for char_id in attached_char_ids:
					var char_unit = GameState.get_unit(char_id)
					if not char_unit.is_empty():
						char_names.append(char_unit.get("meta", {}).get("name", char_id))
				if char_names.size() > 0:
					attach_info = " + " + ", ".join(char_names)

			unit_list.add_item(unit_name + attach_info + status_text)
			unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
			# Disable blocked disembark items so they can't be clicked
			if action_type == "DISEMBARK_BLOCKED":
				unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)
			added_units[unit_id] = true

func _on_unit_selected(index: int) -> void:
	var unit_id = unit_list.get_item_metadata(index)
	if unit_id == null or unit_id == "":
		return

	var unit = GameState.get_unit(unit_id)
	if not unit:
		return

	# Reinforcement placement lock (mirror of DEPLOY-CYCLE): while a reserve
	# unit is being placed, switching units follows the deployment rules —
	# free while nothing is placed (the session is cancelled, its unit returns
	# to reserves), blocked once models are on the table until they are
	# undone. Re-selecting the unit being placed is a no-op (restarting would
	# wipe its placed models).
	var main_for_switch = SceneRefs.main()
	if main_for_switch and main_for_switch.has_method("_reinforcement_try_switch_unit") \
			and not main_for_switch._reinforcement_try_switch_unit(str(unit_id)):
		return

	# Any unit selection ends an in-progress disembark placement: the old
	# controller must not keep validating board clicks against its transport.
	_cancel_active_disembark_placement()

	# QoL: switching to a different unit auto-confirms the previously selected
	# unit's moved-but-unconfirmed move (same as clicking "Confirm Move"). Do this
	# before we repoint active_unit_id so the pending unit is the one confirmed.
	if unit_id != active_unit_id:
		_auto_confirm_pending_move(active_unit_id)
		# The old unit's multi-selection must not survive the switch: model ids
		# repeat between units, so a stale selection makes a later click on the
		# NEW unit's "m1" read as "clicked a selected model" and group-drag the
		# OLD unit's models under the new unit's actor id.
		_clear_selection()

	# Route reserve units to Main's reinforcement placement flow
	if unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
		print("MovementController: Reserve unit %s selected — routing to Main for reinforcement placement" % unit_id)
		var main_node = SceneRefs.main()
		if main_node:
			var reserve_type = unit.get("reserve_type", "strategic_reserves")
			if reserve_type == "strategic_reserves" and GameState.unit_has_deep_strike(unit_id):
				main_node._show_deep_strike_placement_dialog(unit_id)
			else:
				main_node._begin_reinforcement_placement(unit_id)
		return

	active_unit_id = unit_id
	print("MovementController: Unit selected - ", unit_id)

	# Update transport panel in Main for transport info display
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("update_transport_panel"):
		main_node.update_transport_panel(unit_id)

	# Check if unit is embarked and needs to disembark
	if unit.get("embarked_in", null) != null:
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
			# Sync pivot state from phase data
			pivot_cost_paid = existing_move_data.get("pivot_cost_applied", false)
			pivot_cost_inches = existing_move_data.get("pivot_value", 0.0) if pivot_cost_paid else 0.0

	if not has_existing_move:
		# Reset pivot state for new unit
		_reset_pivot_cost()

		# Get unit movement cap
		if unit:
			move_cap_inches = get_unit_movement(unit)
			print("MovementController: Unit %s has movement cap of %.1f inches" % [unit_id, move_cap_inches])

		# OA-24: Check if unit has special movement actions (e.g. Kunnin' Infiltrator)
		# If so, show a popup to let the player choose instead of auto-starting Normal Move
		if current_phase:
			var special_actions = _get_special_movement_actions(unit_id)
			if special_actions.size() > 0:
				_show_movement_action_popup(unit_id, special_actions)
			else:
				# No special actions — proceed with Normal Move as before
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

func _select_unit_in_list_by_id(unit_id: String) -> bool:
	"""Select `unit_id` in the unit list exactly as clicking its row would
	(emits item_selected → _on_unit_selected). Unlike begin_unit_movement it does
	NOT pre-set active_unit_id, so switching from a previously moved unit still
	triggers that unit's auto-confirm. Returns false if the unit is not listed."""
	if not unit_list or not is_instance_valid(unit_list):
		return false
	for i in range(unit_list.get_item_count()):
		if unit_list.get_item_metadata(i) == unit_id:
			unit_list.select(i)
			unit_list.emit_signal("item_selected", i)
			return true
	return false

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
	# Clear any existing unit highlight first
	_clear_unit_highlight()

	# Build set of unit IDs to highlight (bodyguard + attached characters)
	var highlight_ids = {unit_id: true}
	var unit = GameState.get_unit(unit_id)
	if unit and not unit.is_empty():
		var attached_char_ids = unit.get("attachment_data", {}).get("attached_characters", [])
		for char_id in attached_char_ids:
			highlight_ids[char_id] = true

	# Set all token visuals for this unit (and attached characters) as selected
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		return

	for child in token_layer.get_children():
		if child.has_meta("unit_id") and child.get_meta("unit_id") in highlight_ids:
			if child.has_method("set_selected"):
				child.set_selected(true)

func _clear_unit_highlight() -> void:
	# Clear selection highlight from all token visuals
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		return

	for child in token_layer.get_children():
		if child.has_method("set_selected"):
			child.set_selected(false)

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

	print("Normal move radio pressed for unit: ", active_unit_id)
	if active_unit_id == "":
		print("No unit selected!")
		# Try to help the user
		if unit_list and unit_list.get_item_count() > 0:
			print("Please select a unit from the list first")
		return

	# Don't dispatch BEGIN_NORMAL_MOVE yet — wait for "Confirm Movement Mode" button
	_refresh_confirm_mode_button_enable()

func _on_advance_pressed() -> void:
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

	print("Advance button pressed for unit: ", active_unit_id)
	if active_unit_id == "":
		print("No unit selected for advance!")
		return

	# Don't dispatch BEGIN_ADVANCE yet — wait for "Confirm Movement Mode" button
	_refresh_confirm_mode_button_enable()

func _on_fall_back_pressed() -> void:
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

	if active_unit_id == "":
		return

	# ISS-073 (24.35): a SUPER-HEAVY WALKER falling back may also take the MOBILE
	# gamble. Fall Back is dispatched immediately on radio-press (no Confirm
	# Movement Mode step), so read the toggle here.
	var fb_payload := {}
	if _shw_gamble_requested():
		fb_payload["shw_mobile_gamble"] = true
	if _take_to_skies_requested():
		fb_payload["take_to_skies"] = true

	var action = {
		"type": "BEGIN_FALL_BACK",
		"actor_unit_id": active_unit_id,
		"payload": fb_payload
	}
	emit_signal("move_action_requested", action)
	_refresh_confirm_mode_button_enable()  # issue #51

func _on_remain_stationary_pressed() -> void:
	# Ignore if we're setting the radio programmatically
	if setting_radio_programmatically:
		return

	if active_unit_id == "":
		return

	# Don't dispatch REMAIN_STATIONARY yet — wait for "Confirm Movement Mode" button
	_refresh_confirm_mode_button_enable()

func _on_kunnin_infiltrator_button_pressed() -> void:
	"""Handle the Kunnin' Infiltrator button press in the mode selection panel."""
	if active_unit_id == "":
		return
	print("MovementController: Kunnin' Infiltrator button pressed for %s" % active_unit_id)
	emit_signal("move_action_requested", {
		"type": "ACTIVATE_KUNNIN_INFILTRATOR",
		"actor_unit_id": active_unit_id
	})

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

func _has_pending_unconfirmed_move(unit_id: String) -> bool:
	"""True when `unit_id` has an active move with at least one moved model that
	has NOT yet been confirmed (the player dragged models but skipped the
	"Confirm Move" button). Fall Back / Remain Stationary that never moved a
	model, and already-completed moves, return false."""
	if unit_id == "":
		return false
	if not current_phase or not current_phase.has_method("get_active_move_data"):
		return false
	var move_data = current_phase.get_active_move_data(unit_id)
	if move_data.is_empty():
		return false
	if move_data.get("completed", false):
		return false
	# Staged (drag flow) or committed-but-unconfirmed (direct-set flow) moves both count.
	var has_staged = not move_data.get("staged_moves", []).is_empty()
	var has_committed = not move_data.get("model_moves", []).is_empty()
	return has_staged or has_committed

func _auto_confirm_pending_move(unit_id: String) -> bool:
	"""If `unit_id` moved models but was never confirmed, dispatch the same
	CONFIRM_UNIT_MOVE the "Confirm Move" button sends so the player does not have
	to click it before ending the phase or moving a different unit. Returns true
	if a confirm was dispatched. Reuses the full action pipeline, so coherency
	checks, Fire Overwatch, network sync, etc. behave exactly as a manual confirm."""
	if _auto_confirming_pending_move:
		return false
	if not _has_pending_unconfirmed_move(unit_id):
		return false
	print("MovementController: Auto-confirming pending move for %s (player did not click Confirm Move)" % unit_id)
	DebugLogger.info(str("[MovementController] Auto-confirming pending move for ", unit_id, " (no explicit Confirm Move)"))
	_auto_confirming_pending_move = true
	emit_signal("move_action_requested", {
		"type": "CONFIRM_UNIT_MOVE",
		"actor_unit_id": unit_id,
		"payload": {}
	})
	_auto_confirming_pending_move = false
	return true

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
	# NOTE: The live "End Phase" button in the Movement phase is wired to
	# Main._on_phase_action_pressed (which auto-confirms via
	# _auto_confirm_all_pending_moves before dispatching END_MOVEMENT), not to
	# this handler. This is kept for parity and any legacy/local wiring.
	_auto_confirm_all_pending_moves()

	var action = {
		"type": "END_MOVEMENT",
		"payload": {}
	}
	emit_signal("move_action_requested", action)

func _auto_confirm_all_pending_moves() -> void:
	"""Auto-confirm every unit that moved models but was never confirmed. Used
	when ending the phase so no stray staged move blocks END_MOVEMENT."""
	if not current_phase or not "active_moves" in current_phase:
		return
	# Copy the keys — confirming flips each move's `completed` flag as we go.
	var unit_ids: Array = current_phase.active_moves.keys()
	for uid in unit_ids:
		_auto_confirm_pending_move(uid)

func _on_confirm_mode_pressed() -> void:
	if not active_unit_id:
		return

	var selected_mode = _get_selected_movement_mode()
	if selected_mode == "":
		print("No movement mode selected!")
		return

	# ISS-073 (24.35): capture the SHW MOBILE-gamble toggle before the panel is
	# torn down below, and fold it into the BEGIN payload for the move modes
	# that actually move the unit (Normal / Advance).
	var shw_payload := {}
	if _shw_gamble_requested():
		shw_payload["shw_mobile_gamble"] = true
	if _take_to_skies_requested():
		shw_payload["take_to_skies"] = true
	# Turbo Boostas (Speedwaaagh!): only meaningful for BEGIN_ADVANCE — the
	# movement phase ignores the key on other move types.
	if _turbo_boost_requested():
		shw_payload["turbo_boost"] = true

	# Dispatch the actual movement action based on selected mode
	match selected_mode:
		"NORMAL":
			emit_signal("move_action_requested", {
				"type": "BEGIN_NORMAL_MOVE",
				"actor_unit_id": active_unit_id,
				"payload": shw_payload
			})
		"ADVANCE":
			emit_signal("move_action_requested", {
				"type": "BEGIN_ADVANCE",
				"actor_unit_id": active_unit_id,
				"payload": shw_payload
			})
		"REMAIN_STATIONARY":
			emit_signal("move_action_requested", {
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": active_unit_id,
				"payload": {}
			})
			_clear_unit_highlight()
			active_unit_id = ""
			call_deferred("_update_selected_unit_display")
			if unit_list:
				call_deferred("_populate_unit_list")

	# Lock the mode
	emit_signal("move_action_requested", {
		"type": "LOCK_MOVEMENT_MODE",
		"actor_unit_id": active_unit_id,
		"payload": {"mode": selected_mode}
	})

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
	if confirm_mode_button:
		if not enabled:
			confirm_mode_button.visible = false
			confirm_mode_button.disabled = true
		else:
			_refresh_confirm_mode_button_enable()

func _refresh_confirm_mode_button_enable() -> void:
	if not confirm_mode_button:
		return
	var selected_mode = _get_selected_movement_mode()
	var needs_confirm = selected_mode in ["NORMAL", "ADVANCE", "REMAIN_STATIONARY"]
	var any_radio_enabled := false
	if normal_radio and not normal_radio.disabled:
		any_radio_enabled = true
	elif advance_radio and not advance_radio.disabled:
		any_radio_enabled = true
	elif stationary_radio and not stationary_radio.disabled:
		any_radio_enabled = true
	confirm_mode_button.visible = needs_confirm
	confirm_mode_button.disabled = not (any_radio_enabled and needs_confirm)

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

func _unit_is_super_heavy_walker(unit_id: String) -> bool:
	# ISS-073 (24.35): the MOBILE gamble is only available to SUPER-HEAVY WALKER
	# units at edition >= 11.
	if unit_id == "" or GameConstants.edition < 11:
		return false
	var unit = GameState.get_unit(unit_id)
	if unit == null or unit.is_empty():
		return false
	return "SUPER-HEAVY WALKER" in unit.get("meta", {}).get("keywords", [])

func _update_shw_gamble_visibility() -> void:
	# ISS-073 (24.35): show the MOBILE-gamble toggle only for a SUPER-HEAVY
	# WALKER at edition >= 11 whose mode is not already locked. When hidden,
	# also clear its pressed state so a stale toggle can't leak into the next
	# unit's BEGIN payload.
	if not shw_gamble_checkbox:
		return
	var eligible := _unit_is_super_heavy_walker(active_unit_id)
	var mode_locked := false
	if eligible and current_phase and current_phase.active_moves.has(active_unit_id):
		mode_locked = current_phase.active_moves[active_unit_id].get("mode_locked", false)
	var show := eligible and not mode_locked
	shw_gamble_checkbox.visible = show
	if not show:
		shw_gamble_checkbox.button_pressed = false

func _shw_gamble_requested() -> bool:
	# True only when the toggle is actually offered (visible) AND ticked, so a
	# non-SHW / edition-10 unit can never accidentally pass the gamble flag.
	return shw_gamble_checkbox != null and shw_gamble_checkbox.visible and shw_gamble_checkbox.button_pressed

func _unit_can_fly(unit_id: String) -> bool:
	# B2 (21.03): "take to the skies" is only available to FLY units at e11.
	if unit_id == "" or GameConstants.edition < 11:
		return false
	var unit = GameState.get_unit(unit_id)
	if unit == null or unit.is_empty():
		return false
	var kws = unit.get("meta", {}).get("keywords", [])
	return "FLY" in kws or "FLYING" in kws

func _update_take_to_skies_visibility() -> void:
	# Show the take-to-skies toggle only for a FLY unit at e11 whose mode is not
	# already locked; clear its pressed state when hidden so it can't leak.
	if not take_to_skies_checkbox:
		return
	var eligible := _unit_can_fly(active_unit_id)
	var mode_locked := false
	if eligible and current_phase and current_phase.active_moves.has(active_unit_id):
		mode_locked = current_phase.active_moves[active_unit_id].get("mode_locked", false)
	var show := eligible and not mode_locked
	take_to_skies_checkbox.visible = show
	if not show:
		_set_take_to_skies_checkbox_silently(false)
	else:
		# Reflect the unit's ACTUAL declaration: the drag flow auto-begins a
		# NORMAL move at selection (took_to_skies=false), and a tick left over
		# from the previously selected unit must not leak onto this one.
		if current_phase and current_phase.has_method("get_active_move_data"):
			var md = current_phase.get_active_move_data(active_unit_id)
			if not md.is_empty() and not md.get("completed", false):
				_set_take_to_skies_checkbox_silently(bool(md.get("took_to_skies", false)))

func _set_take_to_skies_checkbox_silently(pressed: bool) -> void:
	if not take_to_skies_checkbox or take_to_skies_checkbox.button_pressed == pressed:
		return
	_syncing_take_to_skies = true
	take_to_skies_checkbox.button_pressed = pressed
	_syncing_take_to_skies = false

func _on_take_to_skies_toggled(pressed: bool) -> void:
	# B2/ISS-061: the checkbox is normally folded into the BEGIN_* payload by
	# _on_confirm_mode_pressed, but the default drag flow auto-begins a NORMAL
	# move when the unit is selected — before the player can tick the box. A
	# tick made while a move is already active must therefore be forwarded to
	# the phase as SET_TAKE_TO_SKIES so the dense-terrain gate and move cap
	# see the declaration.
	if _syncing_take_to_skies:
		return
	if active_unit_id == "" or not current_phase:
		return
	if not current_phase.has_method("get_active_move_data"):
		return
	var move_data = current_phase.get_active_move_data(active_unit_id)
	if move_data.is_empty() or move_data.get("completed", false):
		return  # no active move yet — the tick rides the BEGIN payload instead
	if bool(move_data.get("took_to_skies", false)) == pressed:
		return
	emit_signal("move_action_requested", {
		"type": "SET_TAKE_TO_SKIES",
		"actor_unit_id": active_unit_id,
		"payload": {"take_to_skies": pressed}
	})
	# Dispatch is synchronous in single-player: re-read the authoritative move
	# data next frame so a rejected toggle (e.g. a model already moved past the
	# reduced cap) snaps the checkbox back while the error toast explains why.
	call_deferred("_sync_take_to_skies_from_phase")

func _sync_take_to_skies_from_phase() -> void:
	if active_unit_id == "" or not current_phase or not take_to_skies_checkbox:
		return
	if not current_phase.has_method("get_active_move_data"):
		return
	var move_data = current_phase.get_active_move_data(active_unit_id)
	if move_data.is_empty():
		return
	_set_take_to_skies_checkbox_silently(bool(move_data.get("took_to_skies", false)))
	# The declaration changes the move cap (-2" on, back to full off) — pull the
	# authoritative cap so the Move/Left readout matches immediately.
	move_cap_inches = float(move_data.get("move_cap_inches", move_cap_inches))
	_update_movement_display()

func _take_to_skies_requested() -> bool:
	return take_to_skies_checkbox != null and take_to_skies_checkbox.visible and take_to_skies_checkbox.button_pressed

func _unit_can_turbo_boost(unit_id: String) -> bool:
	# Turbo Boostas (Speedwaaagh!): SPEED FREEKS / TRUKK units (excl.
	# AIRCRAFT) of a Speedwaaagh! player at e11.
	if unit_id == "" or GameConstants.edition < 11:
		return false
	var unit = GameState.get_unit(unit_id)
	if unit == null or unit.is_empty():
		return false
	var fam = get_node_or_null("/root/FactionAbilityManager")
	return fam != null and fam.unit_can_turbo_boost(unit)

func _update_turbo_boost_visibility() -> void:
	# Show the turbo toggle only for an eligible Speedwaaagh! unit whose mode
	# is not already locked; clear its pressed state when hidden so a stale
	# toggle can't leak into the next unit's BEGIN payload.
	if not turbo_boost_checkbox:
		return
	var eligible := _unit_can_turbo_boost(active_unit_id)
	var mode_locked := false
	if eligible and current_phase and current_phase.active_moves.has(active_unit_id):
		mode_locked = current_phase.active_moves[active_unit_id].get("mode_locked", false)
	var show := eligible and not mode_locked
	turbo_boost_checkbox.visible = show
	if not show:
		turbo_boost_checkbox.button_pressed = false

func _turbo_boost_requested() -> bool:
	return turbo_boost_checkbox != null and turbo_boost_checkbox.visible and turbo_boost_checkbox.button_pressed

func _reset_mode_selection_for_new_unit(unit_id: String) -> void:
	# Check if this unit already has its mode locked
	var mode_is_locked = false
	if current_phase and current_phase.active_moves.has(unit_id):
		mode_is_locked = current_phase.active_moves[unit_id].get("mode_locked", false)
	
	if mode_is_locked:
		# Unit's mode is already locked, disable all controls
		_update_mode_buttons_state(false)
		# OA-24: Hide ability button when mode is locked
		if _kunnin_infiltrator_button:
			_kunnin_infiltrator_button.visible = false

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

		# ISS-073: keep the SHW gamble toggle hidden once the mode is locked.
		_update_shw_gamble_visibility()
		_update_take_to_skies_visibility()
		_update_turbo_boost_visibility()
	else:
		# Unit's mode is not locked, enable fresh selection
		_update_mode_buttons_state(true)

		# Reset to default (Normal) selection
		active_mode = "NORMAL"  # Set mode variable
		if normal_radio:
			setting_radio_programmatically = true
			normal_radio.button_pressed = true
			setting_radio_programmatically = false

		# Refresh the Confirm Movement Mode button now that NORMAL is selected
		_refresh_confirm_mode_button_enable()

		# Hide advance roll label
		if advance_roll_label:
			advance_roll_label.visible = false

		# OA-24: Show/hide Kunnin' Infiltrator button based on unit abilities
		if _kunnin_infiltrator_button:
			var has_ki = _get_special_movement_actions(unit_id).size() > 0 if current_phase else false
			_kunnin_infiltrator_button.visible = has_ki

		# ISS-073: show the SHW MOBILE-gamble toggle for an eligible fresh unit.
		_update_shw_gamble_visibility()
		_update_take_to_skies_visibility()
		_update_turbo_boost_visibility()

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
	_update_selected_unit_display()

	# Trigger move animation on all models in the unit
	_trigger_unit_animation(unit_id, "move")

	# T-094 (revised): the movement-reach circle is now drawn per-model when a
	# model is picked up (see _start_model_drag / _start_group_movement), not as a
	# unit-wide bubble centred on the unit's centre of mass.
	# T-094: Show engagement-range rings around enemy units (edition-aware ER)
	_show_er_overlay(unit_id)
	# T-094: Show 2" coherency rings around friendly models in this unit
	_show_coherency_dots(unit_id)

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
		# Pad flow: an Advance chosen from the pad move menu resolves its dice
		# here (immediately, or after the Command Re-roll dialog). Hand the pad
		# player the first model — the same auto-carry choosing plain Move gets —
		# so a D-pad press can then grab the whole squad. PadRouter no-ops unless
		# IT armed this when the menu choice was applied (mouse/AI unaffected).
		if PadRouter.has_method("on_advance_move_resolved"):
			PadRouter.on_advance_move_resolved(unit_id)

	# Notify Main to update UI
	emit_signal("ui_update_requested")

func _on_model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2, rotation: float = 0.0) -> void:
	print("MovementController: Model drop committed for ", model_id, " at ", dest_px, " rotation: ", rotation)
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
	# Return unit to idle animation
	_trigger_unit_animation(unit_id, "idle")

	# P3-125: Show confirmed movement path animation before clearing state
	_show_confirmed_movement_paths(unit_id)

	# Clear movement state
	_clear_unit_highlight()
	_clear_move_range_overlay()  # T-094
	_clear_er_overlay()  # T-094
	_clear_coherency_dots()  # T-094
	# The confirmed unit's multi-selection dies with its move — a selection that
	# outlives the confirm matches the NEXT unit's model ids and group-drags the
	# wrong models (see _is_clicking_on_selected_model).
	_clear_selection()
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

	# P3-125: Clear the planning preview (confirmed visual is a separate instance)
	if movement_path_preview and is_instance_valid(movement_path_preview):
		movement_path_preview.clear_now()

	_update_movement_display()
	_refresh_unit_list()
	emit_signal("ui_update_requested")

	# T-094: auto-select next unmoved unit in the list.
	# Skip when this confirm was auto-triggered by the player switching units or
	# ending the phase — they already chose what happens next, and re-selecting
	# here would fight that choice (and could spawn a stray active move).
	if not _auto_confirming_pending_move:
		_auto_select_next_unmoved()


func _auto_select_next_unmoved() -> void:
	if not unit_list or not is_instance_valid(unit_list):
		return
	for i in range(unit_list.get_item_count()):
		# get_item_metadata() returns null for list items without metadata (e.g.
		# section headers) — coerce to "" instead of crashing on the typed assign.
		var _meta = unit_list.get_item_metadata(i)
		var entry_unit_id: String = _meta if _meta is String else ""
		if entry_unit_id == "":
			continue
		var unit = GameState.get_unit(entry_unit_id)
		if unit.is_empty():
			continue
		var status = _get_unit_movement_status(entry_unit_id)
		# Skip if already moved/marked stationary; pick the first that hasn't acted yet
		if status == "YET TO MOVE" or status == "":
			unit_list.select(i)
			unit_list.emit_signal("item_selected", i)
			print("[T-094] Auto-selected next unmoved unit: %s" % entry_unit_id)
			return


func _show_confirmed_movement_paths(unit_id: String) -> void:
	"""P3-125: Create a confirmed movement path visual (hold + fade) for the unit that just moved."""
	if not current_phase or not "active_moves" in current_phase:
		return

	var active_moves = current_phase.active_moves
	if not active_moves.has(unit_id):
		return

	var move_data = active_moves[unit_id]
	var model_moves = move_data.get("model_moves", [])
	var original_positions = move_data.get("original_positions", {})

	# Build paths from original positions to final destinations
	var confirmed_paths: Array = []

	# Collect the final destination for each model (last move wins, keyed by composite key)
	var final_destinations: Dictionary = {}
	for model_move in model_moves:
		var model_id = model_move.get("model_id", "")
		if model_id != "":
			var source = model_move.get("model_source_unit_id", unit_id)
			var mk = "%s:%s" % [source, model_id]
			final_destinations[mk] = model_move.get("dest", Vector2.ZERO)

	# Also include staged moves that haven't been converted yet
	for staged_move in move_data.get("staged_moves", []):
		var model_id = staged_move.get("model_id", "")
		if model_id != "":
			var source = staged_move.get("model_source_unit_id", unit_id)
			var mk = "%s:%s" % [source, model_id]
			final_destinations[mk] = staged_move.get("dest", Vector2.ZERO)

	for mk in final_destinations:
		var from_pos = original_positions.get(mk, Vector2.ZERO)
		var to_pos = final_destinations[mk]
		if from_pos == Vector2.ZERO:
			continue
		if from_pos.distance_to(to_pos) > 5.0:
			confirmed_paths.append({"from": from_pos, "to": to_pos})

	if confirmed_paths.is_empty():
		return

	# Create a new visual instance for the confirmed animation (it self-destructs after fade)
	var board_root = SceneRefs.board_root()
	if not board_root:
		return

	var HumanMovementPathVisualScript = preload("res://scripts/HumanMovementPathVisual.gd")
	var confirmed_visual = Node2D.new()
	confirmed_visual.set_script(HumanMovementPathVisualScript)
	confirmed_visual.name = "HumanMovementConfirmed_%d" % (randi() % 10000)
	board_root.add_child(confirmed_visual)
	confirmed_visual.show_confirmed_paths(confirmed_paths, GameState.get_active_player())

func _on_unit_move_reset(unit_id: String) -> void:
	_clear_path_visual()
	path_visual.clear_points()  # Clear staged moves visual as well

	# Clear all individual model path visuals
	for model_id in model_path_visuals:
		var line = model_path_visuals[model_id]
		if line and is_instance_valid(line):
			line.queue_free()
	model_path_visuals.clear()

	# P3-125: Clear planning path preview on reset
	if movement_path_preview and is_instance_valid(movement_path_preview):
		movement_path_preview.clear_now()

	# Reset pivot cost tracking in the controller
	_reset_pivot_cost()

	# Recreate unit visuals to reflect restored rotations
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("_recreate_unit_visuals"):
		main_node._recreate_unit_visuals()

	# After reset, the phase erased active_moves for this unit.
	# Clear controller state so the user can cleanly re-select the unit.
	if unit_id == active_unit_id:
		active_unit_id = ""
		active_mode = ""
	# A multi-selection built during the reset move is stale now (positions and
	# staged state both rolled back) — drop it with the rest of the move state.
	_clear_selection()

	_update_movement_display()
	_refresh_unit_list()
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
				elif _try_click_select_unit(event.position):
					pass  # Click on a different friendly unit's model — selection/switch handled
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
		if KeybindingManager.matches_action(event, "select_all"):
			_select_all_unit_models()
		elif event.keycode == KEY_ESCAPE:
			_clear_selection()
		# Keyboard rotation controls - work during dragging or when model selected
		elif (selected_model.size() > 0 or selected_models.size() > 0):
			if KeybindingManager.matches_action(event, "rotate_left"):
				_rotate_model_by_angle(-PI/12)  # Rotate 15 degrees left
			elif KeybindingManager.matches_action(event, "rotate_right"):
				_rotate_model_by_angle(PI/12)  # Rotate 15 degrees right

func _is_model_in_active_unit_group(model_unit_id: String) -> bool:
	"""Check if a model belongs to the active unit or one of its attached characters"""
	if model_unit_id == active_unit_id:
		return true
	var active_unit = GameState.get_unit(active_unit_id)
	if active_unit:
		var attached_chars = active_unit.get("attachment_data", {}).get("attached_characters", [])
		if model_unit_id in attached_chars:
			return true
	return false

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
	var board_root = SceneRefs.board_root()
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
		# Allow dragging attached character models (e.g. Deffkilla Wartrike attached to Warbikers)
		# They are part of the combined unit and should be positionable during movement
		if _is_model_in_active_unit_group(model.unit_id):
			print("MovementController: Dragging attached character model from unit %s (bodyguard: %s)" % [model.unit_id, active_unit_id])
		else:
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
	# T-094 (revised): show this model's movement-reach circle anchored at its
	# pickup position (reflects Advance distance and any remaining staged budget).
	_show_model_range_overlay(model, drag_start_pos)

# P0 Steam Deck smoothness: clamp a tentative drag position to the model's
# remaining movement budget, so an over-range pad carry stops exactly on the
# reach circle instead of being rejected on drop (matching XCOM 2 / Into the
# Breach, where the unit stops at the movement boundary). Geometry only — the
# endpoint terrain penalty is subtracted from the budget, and an already-legal
# move is returned unchanged. Overlap / board-edge legality is left to the
# caller: shortening distance must not silently force an illegal overlap.
func _clamp_move_to_budget(world_pos: Vector2) -> Vector2:
	var seg: Vector2 = world_pos - drag_start_pos
	var seg_len_px: float = seg.length()
	if seg_len_px <= 0.0:
		return world_pos
	var already_used: float = _get_accumulated_distance()
	var effective_cap: float = _get_effective_move_cap()
	var terrain_penalty: float = _get_terrain_penalty_for_move(drag_start_pos, world_pos)
	var max_geo_inches: float = max(0.0, effective_cap - already_used - terrain_penalty)
	if Measurement.px_to_inches(seg_len_px) <= max_geo_inches + MOVEMENT_CAP_EPSILON:
		return world_pos
	return drag_start_pos + seg.normalized() * Measurement.inches_to_px(max_geo_inches)

func _update_model_drag(mouse_pos: Vector2) -> void:
	if not dragging_model:
		return

	# Get the board transform from Main
	var board_root = SceneRefs.board_root()
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	# Snap to grid if enabled
	if _should_snap_to_grid():
		world_pos = _snap_to_grid(world_pos)

	# P0 Steam Deck smoothness: on the pad, clamp an over-range drag to the
	# model's remaining move budget so the ghost stops on the reach circle
	# instead of running past it (over-range clamped, not rejected — the XCOM 2 /
	# Into the Breach feel). Mouse keeps its free red-preview drag.
	if InputDeviceManager.is_pad_active():
		world_pos = _clamp_move_to_budget(world_pos)

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
	var effective_cap = _get_effective_move_cap()
	var inches_left = effective_cap - total_distance

	# Check validity based on total distance (accounting for pivot cost)
	# Use epsilon tolerance to match MovementPhase validation — prevents false
	# "invalid" indicator at exactly max range due to floating-point imprecision
	path_valid = total_distance <= effective_cap + MOVEMENT_CAP_EPSILON

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
			if Measurement.model_overlaps_any_wall(test_model, _get_active_unit_keywords()):
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
	if not overlap_detected and not out_of_bounds and total_distance <= effective_cap + MOVEMENT_CAP_EPSILON:
		if illegal_reason_label:
			illegal_reason_label.text = ""

	# Update visuals
	_update_path_visual()
	_update_ruler_visual()
	_update_ghost_position(world_pos)
	_update_ghost_validity(!overlap_detected and !out_of_bounds and total_distance <= effective_cap + MOVEMENT_CAP_EPSILON)
	# Show total distance used (already accumulated + current drag)
	_update_movement_display_with_preview(total_distance, inches_left, path_valid)
	# Update floating movement remaining indicator near the ghost
	_update_movement_remaining_label(inches_left, path_valid)
	# P3-116: Update coherency preview lines during drag
	_update_coherency_preview(world_pos)

func _compute_move_rejection(world_pos: Vector2) -> String:
	"""Single source of truth for why staging the active model at world_pos is
	illegal ("" = legal): over the move cap, off the board, or overlapping a
	wall/model. Shared by _end_model_drag (mouse + pad drop) and the pad carry's
	pad_carry_drop_rejection() so a controller drop is judged identically to a
	mouse drop."""
	var terrain_penalty = _get_terrain_penalty_for_move(drag_start_pos, world_pos)
	var distance_inches = Measurement.distance_polyline_inches([drag_start_pos, world_pos]) + terrain_penalty
	var total_distance = _get_accumulated_distance() + distance_inches
	var effective_cap = _get_effective_move_cap()
	if total_distance > effective_cap + MOVEMENT_CAP_EPSILON:
		return "Movement exceeds %.1f\" cap (would be %.1f\")" % [effective_cap, total_distance]
	if current_phase and selected_model and _is_position_outside_board(world_pos, selected_model):
		return "Cannot place model beyond the board edge"
	if current_phase and _check_position_would_overlap(world_pos):
		# Distinguish wall overlap from model overlap so the player knows whether
		# to find a different lane or just nudge sideways.
		var test_model = selected_model.duplicate()
		test_model["position"] = world_pos
		if Measurement.model_overlaps_any_wall(test_model, _get_active_unit_keywords()):
			return "Cannot place model overlapping a wall this unit can't cross"
		return "Cannot place model overlapping another model"
	return ""

func _end_model_drag(mouse_pos: Vector2) -> void:
	if not dragging_model:
		return

	print("Ending model drag")
	
	# Get the board transform from Main
	var board_root = SceneRefs.board_root()
	var world_pos: Vector2
	
	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()
	
	# Snap to grid if enabled
	if _should_snap_to_grid():
		world_pos = _snap_to_grid(world_pos)
	
	print("Final position: ", world_pos)

	# P0: clamp over-range to the budget (see _update_model_drag) so a pad drop
	# stages at the boundary rather than being rejected and snapping back.
	if InputDeviceManager.is_pad_active():
		world_pos = _clamp_move_to_budget(world_pos)

	# Distance is recomputed here only for the debug log; the legality decision
	# lives in _compute_move_rejection so the pad carry can consult the exact
	# same rules BEFORE it releases a model (see pad_carry_drop_rejection).
	var terrain_penalty = _get_terrain_penalty_for_move(drag_start_pos, world_pos)
	var distance_inches = Measurement.distance_polyline_inches([drag_start_pos, world_pos]) + terrain_penalty
	var total_distance = _get_accumulated_distance() + distance_inches
	print("Distance moved: ", distance_inches, " inches (terrain penalty: ", terrain_penalty, ")")

	# Single rejection-reason string (empty = legal) so silent reverts don't
	# leave the player guessing why the model snapped back — and so the pad
	# carry refuses an illegal drop with the identical rule set.
	var rejection_reason: String = _compute_move_rejection(world_pos)

	if rejection_reason == "":
		print("Move is valid, sending STAGE_MODEL_MOVE action")
		print("  From: ", drag_start_pos, " To: ", world_pos)
		print("  Distance: ", distance_inches, " inches")
		print("  Total staged: ", total_distance, " inches")

		# Send STAGE_MODEL_MOVE action instead of SET_MODEL_DEST
		var payload = {
			"model_id": selected_model.model_id,
			"dest": [world_pos.x, world_pos.y],
			"rotation": selected_model.get("rotation", 0.0)  # Preserve rotation
		}
		# Include source unit ID when model belongs to an attached character
		# (model IDs like "m1" can collide between bodyguard and character units)
		if selected_model.get("unit_id", "") != "" and selected_model.unit_id != active_unit_id:
			payload["model_source_unit_id"] = selected_model.unit_id
		var action = {
			"type": "STAGE_MODEL_MOVE",  # Changed to stage instead of commit
			"actor_unit_id": active_unit_id,
			"payload": payload
		}
		print("  Action: ", action)
		emit_signal("move_action_requested", action)
	else:
		print("Move invalid: %s" % rejection_reason)
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr and toast_mgr.has_method("show_error"):
			toast_mgr.show_error(rejection_reason)
	
	# Clear drag state
	dragging_model = false
	selected_model = {}
	current_path.clear()
	_clear_ghost_visual()
	_clear_path_visual()
	_clear_ruler_visual()
	_clear_move_range_overlay()  # T-094 (revised): remove per-model reach circle
	
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
	var token_layer = SceneRefs.token_layer()
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
	var token_layer = SceneRefs.token_layer()
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
	
	# Check distance cap (accounting for pivot cost, with floating-point tolerance)
	if distance_inches > _get_effective_move_cap() + MOVEMENT_CAP_EPSILON:
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
	dialog.name = "DisembarkDialog"  # Stable path for tests/tooling (/root/DisembarkDialog)
	dialog.setup(unit_id)
	dialog.disembark_confirmed.connect(_on_disembark_confirmed.bind(unit_id))
	dialog.disembark_canceled.connect(_on_disembark_canceled.bind(unit_id))

	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)

func _on_disembark_confirmed(combat_mode: bool, unit_id: String) -> void:
	"""Handle disembark confirmation - start placement controller"""
	print("MovementController: Starting disembark placement for unit %s (combat_mode=%s)" % [unit_id, str(combat_mode)])

	# Belt-and-braces: never allow two live placement controllers. A leftover
	# controller validates clicks against the WRONG transport (wrong-distance
	# errors) and leaves its range border on the board.
	_cancel_active_disembark_placement()

	# Create disembark controller for model placement
	var controller = preload("res://scripts/DisembarkController.gd").new()
	# 11e 18.04: the dialog's Combat Disembark toggle switches the
	# placement rules (6" set-up, engaged-with-transport's-foes allowed)
	# and is echoed to the phase via payload.can_setup_tactical=false.
	controller.combat_requested = combat_mode
	_pending_combat_disembark[unit_id] = combat_mode
	controller.disembark_completed.connect(_on_disembark_completed)
	controller.disembark_canceled.connect(_on_disembark_canceled)

	# Add to scene
	var board_root = SceneRefs.board_root()
	if board_root:
		board_root.add_child(controller)
	else:
		get_tree().root.add_child(controller)

	# Start disembark placement
	_active_disembark_controller = controller
	controller.start_disembark(unit_id)

func _cancel_active_disembark_placement() -> void:
	"""Cancel a still-open disembark placement (player switched units/phase)."""
	if _active_disembark_controller and is_instance_valid(_active_disembark_controller):
		_active_disembark_controller.cancel_placement()
	_active_disembark_controller = null

func _on_disembark_completed(unit_id: String, positions: Array) -> void:
	"""Handle successful disembark - route through action system for multiplayer sync"""
	print("MovementController: Disembark completed for unit %s with %d positions" % [unit_id, positions.size()])
	_active_disembark_controller = null

	# Serialize positions for action payload (Vector2 -> dict for network transport)
	var serialized_positions = []
	for pos in positions:
		serialized_positions.append({"x": pos.x, "y": pos.y})

	# Route through action system instead of calling TransportManager directly
	var action = {
		"type": "CONFIRM_DISEMBARK",
		"actor_unit_id": unit_id,
		"payload": {
			"positions": serialized_positions,
			"can_setup_tactical": not _pending_combat_disembark.get(unit_id, false)
		}
	}
	_pending_combat_disembark.erase(unit_id)
	print("MovementController: Routing CONFIRM_DISEMBARK through action system")
	emit_signal("move_action_requested", action)

	# UI updates happen in _post_disembark_ui_update after Main routes the action
	call_deferred("_post_disembark_ui_update", unit_id)

func _post_disembark_ui_update(unit_id: String) -> void:
	"""Update controller UI after a CONFIRM_DISEMBARK action has been processed"""
	# Refresh board visuals to show the disembarked models
	var main = SceneRefs.main()
	if main and main.has_method("_recreate_unit_visuals"):
		print("MovementController: Refreshing board visuals after disembark")
		main._recreate_unit_visuals()

	# Refresh UI to show disembarked unit
	_refresh_unit_list()

	# Check if the disembarked unit can move
	var unit = GameState.get_unit(unit_id)
	if unit and not unit.get("flags", {}).get("cannot_move", false):
		print("MovementController: Disembarked unit can move")
		active_unit_id = unit_id
		active_mode = "NORMAL"

		if unit:
			move_cap_inches = get_unit_movement(unit)
			print("MovementController: Unit %s has movement cap of %d inches" % [unit_id, move_cap_inches])

		_update_selected_unit_display()
		_update_fall_back_visibility()
		# 18.04: a tactical disembark lets the unit make a normal OR advance move.
		# Set up the mode radios with the decision OPEN (the phase left mode_locked
		# false) so the Advance option is offered on BOTH the mouse (mode radios)
		# and the pad (the PadActionBar move menu reads radio visibility/enabled).
		# Without this the radios stay stale/disabled after disembark and neither
		# surface exposes Advance — the reported controller gap.
		_reset_mode_selection_for_new_unit(unit_id)
		emit_signal("ui_update_requested")

		# Find and select the unit in the list
		for i in range(unit_list.get_item_count()):
			if unit_list.get_item_metadata(i) == unit_id:
				unit_list.select(i)
				break
	else:
		print("MovementController: Disembarked unit cannot move (transport already moved)")
		active_unit_id = ""
		_update_selected_unit_display()

func _on_disembark_canceled(unit_id: String) -> void:
	"""Handle canceled disembark"""
	print("MovementController: Disembark canceled for unit %s" % unit_id)
	_active_disembark_controller = null

	# Clear selection
	_clear_unit_highlight()
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
		# P3-125: Clear preview when no active movement
		if movement_path_preview and is_instance_valid(movement_path_preview):
			movement_path_preview.clear_now()
		return

	var board_root = SceneRefs.board_root()
	if not board_root:
		return
	
	# Get staged moves from phase
	if current_phase != null and "active_moves" in current_phase:
		var active_moves = current_phase.active_moves
		if active_moves.has(active_unit_id):
			var move_data = active_moves[active_unit_id]
			
			# Group staged moves by model to build complete paths (composite key to avoid collision)
			var models_with_segments = {}

			# Collect all segments for each model
			for staged_move in move_data.get("staged_moves", []):
				var model_id = staged_move.get("model_id", "")
				if model_id != "" and staged_move.has("from") and staged_move.has("dest"):
					var source = staged_move.get("model_source_unit_id", active_unit_id)
					var mk = "%s:%s" % [source, model_id]
					if not models_with_segments.has(mk):
						models_with_segments[mk] = []
					models_with_segments[mk].append(staged_move)
			
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
					line.name = "Path_" + model_id.replace(":", "_")
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

			# P3-125: Update HumanMovementPathVisual with staged paths
			_update_movement_path_preview(move_data, models_with_segments)

func _update_movement_path_preview(move_data: Dictionary, models_with_segments: Dictionary) -> void:
	"""P3-125: Update the dashed-line path preview for staged model moves."""
	if not movement_path_preview or not is_instance_valid(movement_path_preview):
		return

	var preview_paths: Array = []
	for model_id in models_with_segments:
		var segments = models_with_segments[model_id]
		if segments.is_empty():
			continue

		# Use the first segment's 'from' as origin and last segment's 'dest' as destination
		var origin: Vector2 = segments[0].from
		var destination: Vector2 = segments[-1].dest

		if origin.distance_to(destination) < 5.0:
			continue

		# Calculate total distance for this model
		var distance: float = move_data.get("model_distances", {}).get(model_id, 0.0)

		preview_paths.append({
			"from": origin,
			"to": destination,
			"distance": distance
		})

	var player = GameState.get_active_player()
	var cap = move_data.get("move_cap_inches", move_cap_inches)
	# Account for pivot cost when passing cap to path preview visual
	if pivot_cost_paid:
		cap -= pivot_cost_inches
	movement_path_preview.update_planning_paths(preview_paths, player, cap)

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

	# Create floating movement remaining indicator above the ghost
	movement_remaining_label = Label.new()
	movement_remaining_label.name = "MovementRemainingLabel"
	movement_remaining_label.text = ""
	movement_remaining_label.add_theme_font_size_override("font_size", 16)
	movement_remaining_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 0.9))
	movement_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	movement_remaining_label.z_index = 58  # Above other overlays
	movement_remaining_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Position above the model base (offset upward)
	var base_mm = model.get("base_mm", 32)
	var base_radius_px = Measurement.base_radius_px(base_mm)
	movement_remaining_label.position = Vector2(-30, -(base_radius_px + 22))
	ghost_visual.add_child(movement_remaining_label)

	# P3-116: Create coherency status label below the movement remaining label
	coherency_status_label = Label.new()
	coherency_status_label.name = "CoherencyStatusLabel"
	coherency_status_label.text = ""
	coherency_status_label.add_theme_font_size_override("font_size", 13)
	coherency_status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2, 0.8))
	coherency_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coherency_status_label.z_index = 58
	coherency_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coherency_status_label.position = Vector2(-30, -(base_radius_px + 8))
	ghost_visual.add_child(coherency_status_label)

	print("Created ghost visual for model")

func _update_ghost_position(world_pos: Vector2) -> void:
	if ghost_visual:
		ghost_visual.position = world_pos
		# Debug: Show cursor and ghost positions
		print("Updating ghost position to: ", world_pos)
		# T-094: board-edge warning
		_update_board_edge_warning(world_pos)


# T-094: warn the player if ghost is near the board edge
const BOARD_EDGE_WARNING_INCHES: float = 1.5
func _update_board_edge_warning(world_pos: Vector2) -> void:
	if not coherency_status_label or not is_instance_valid(coherency_status_label):
		return
	if not SettingsService:
		return
	var board_w_px = SettingsService.get_board_width_px()
	var board_h_px = SettingsService.get_board_height_px()
	var warning_px = Measurement.inches_to_px(BOARD_EDGE_WARNING_INCHES)
	var near_left = world_pos.x < warning_px
	var near_right = world_pos.x > board_w_px - warning_px
	var near_top = world_pos.y < warning_px
	var near_bottom = world_pos.y > board_h_px - warning_px
	if near_left or near_right or near_top or near_bottom:
		var existing = coherency_status_label.text
		if not existing.contains("Edge!"):
			coherency_status_label.text = existing + (" " if existing else "") + "[Near Edge!]"
			coherency_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2, 1.0))

func _clear_ghost_visual() -> void:
	for child in ghost_visual.get_children():
		child.queue_free()
	movement_remaining_label = null
	coherency_status_label = null

func _get_accumulated_distance() -> float:
	# Get distance for the currently selected model
	return _get_accumulated_distance_for_model(selected_model)

func _get_accumulated_distance_for_model(model: Dictionary) -> float:
	# Get the distance already staged this phase for an arbitrary model.
	if not current_phase or not active_unit_id or model.is_empty():
		return 0.0

	var model_id = model.get("model_id", model.get("id", ""))
	if model_id == "":
		return 0.0

	var model_source = model.get("unit_id", active_unit_id)
	var mk = "%s:%s" % [model_source, model_id]

	# Check if phase has active_moves data
	if current_phase.has_method("get_active_move_data"):
		var move_data = current_phase.get_active_move_data(active_unit_id)
		if move_data and move_data.has("model_distances"):
			return move_data.model_distances.get(mk, 0.0)
	elif current_phase != null and "active_moves" in current_phase:
		var active_moves = current_phase.active_moves
		if active_moves.has(active_unit_id):
			var move_data = active_moves[active_unit_id]
			if move_data.has("model_distances"):
				return move_data.model_distances.get(mk, 0.0)

	return 0.0

func _update_movement_display() -> void:
	# Calculate effective cap accounting for pivot cost
	var effective_cap = move_cap_inches
	if pivot_cost_paid:
		effective_cap -= pivot_cost_inches

	if move_cap_label:
		if pivot_cost_paid and pivot_cost_inches > 0:
			move_cap_label.text = "Move: %.1f\" (pivot: -%.0f\")" % [effective_cap, pivot_cost_inches]
		else:
			move_cap_label.text = "Move: %.1f\"" % move_cap_inches

	# Handle group selection display
	if selected_models.size() > 1:
		_update_group_movement_display()
	elif selected_models.size() == 1:
		# Single model from multi-selection
		var model_data = selected_models[0]
		var model_id = model_data.get("model_id", "")
		var accumulated = _get_model_accumulated_distance(model_id, model_data.get("unit_id", ""))

		if inches_used_label:
			inches_used_label.text = "%s Used: %.1f\"" % [model_id, accumulated]
		if inches_left_label:
			inches_left_label.text = "Left: %.1f\"" % (effective_cap - accumulated)
	elif not selected_model.is_empty():
		# Original single model selection
		var accumulated = _get_accumulated_distance()
		var model_id = selected_model.get("model_id", "")

		if inches_used_label:
			inches_used_label.text = "%s Used: %.1f\"" % [model_id, accumulated]
		if inches_left_label:
			inches_left_label.text = "Left: %.1f\"" % (effective_cap - accumulated)
	else:
		# No selection
		if inches_used_label:
			inches_used_label.text = "Staged: -"
		if inches_left_label:
			inches_left_label.text = "Left: -"

func _get_model_accumulated_distance(model_id: String, source_unit_id: String = "") -> float:
	"""Get accumulated distance for a specific model"""
	if not current_phase or not active_unit_id or model_id == "":
		return 0.0

	var mk = "%s:%s" % [source_unit_id if source_unit_id != "" else active_unit_id, model_id]

	# Check if phase has active_moves data
	if current_phase.has_method("get_active_move_data"):
		var move_data = current_phase.get_active_move_data(active_unit_id)
		if move_data and move_data.has("model_distances"):
			return move_data.model_distances.get(mk, 0.0)
	elif current_phase != null and "active_moves" in current_phase:
		var active_moves = current_phase.active_moves
		if active_moves.has(active_unit_id):
			var move_data = active_moves[active_unit_id]
			if move_data.has("model_distances"):
				return move_data.model_distances.get(mk, 0.0)

	return 0.0


func _update_movement_display_with_preview(used: float, left: float, valid: bool) -> void:
	var effective_cap = move_cap_inches
	if pivot_cost_paid:
		effective_cap -= pivot_cost_inches
	if move_cap_label:
		if pivot_cost_paid and pivot_cost_inches > 0:
			move_cap_label.text = "Move: %.1f\" (pivot: -%.0f\")" % [effective_cap, pivot_cost_inches]
		else:
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

func _update_movement_remaining_label(inches_left: float, valid: bool) -> void:
	if not movement_remaining_label or not is_instance_valid(movement_remaining_label):
		return
	var moved = move_cap_inches - inches_left
	if inches_left >= 0:
		movement_remaining_label.text = "%.1f\" / %.1f\"" % [moved, move_cap_inches]
	else:
		movement_remaining_label.text = "%.1f\" OVER" % abs(inches_left)
	# Green when valid, red when over cap or invalid position
	if valid and inches_left >= 0:
		if inches_left < 1.0 and move_cap_inches > 0:
			movement_remaining_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 0.9))
		else:
			movement_remaining_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 0.9))
	elif inches_left >= 0:
		movement_remaining_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1, 0.9))
	else:
		movement_remaining_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1, 0.9))

func _update_coherency_preview(ghost_world_pos: Vector2) -> void:
	"""P3-116: Update coherency preview lines from ghost to all other models in the unit.
	Shows green lines for models within 2\" coherency, red lines for models outside."""
	if not current_phase or active_unit_id == "" or selected_model.is_empty():
		return

	# Get the ghost token from ghost_visual
	var ghost_token = null
	if ghost_visual and ghost_visual.get_child_count() > 0:
		var first_child = ghost_visual.get_child(0)
		if first_child.has_method("set_coherency_preview"):
			ghost_token = first_child

	if not ghost_token:
		return

	var unit = current_phase.get_unit(active_unit_id)
	if unit.is_empty():
		ghost_token.clear_coherency_preview()
		return

	var models = unit.get("models", [])
	var alive_models = []
	for model in models:
		if model.get("alive", true):
			alive_models.append(model)

	# Single model units don't need coherency preview
	if alive_models.size() <= 1:
		ghost_token.clear_coherency_preview()
		_update_coherency_status_label("", true)
		return

	var dragged_model_id = selected_model.get("model_id", "")

	# Get staged move data for this unit
	var move_data = {}
	if current_phase.has_method("get_active_move_data"):
		move_data = current_phase.get_active_move_data(active_unit_id)
	elif current_phase != null and "active_moves" in current_phase:
		var active_moves = current_phase.active_moves
		if active_moves.has(active_unit_id):
			move_data = active_moves[active_unit_id]

	# Build staged position lookup
	var staged_positions = {}
	for staged_move in move_data.get("staged_moves", []):
		staged_positions[staged_move.get("model_id", "")] = staged_move.get("dest", Vector2.ZERO)

	# Build the ghost model dict (dragged model at ghost position)
	var ghost_model = selected_model.duplicate()
	ghost_model["position"] = ghost_world_pos

	# Build list of all other models with their current/staged positions
	var other_models_data = []  # Array of { model_dict, world_pos }
	for model in alive_models:
		var model_id = model.get("id", "")
		if model_id == dragged_model_id:
			continue  # Skip the model being dragged

		var model_dict = model.duplicate()
		# Use staged position if available
		if staged_positions.has(model_id):
			model_dict["position"] = staged_positions[model_id]
		else:
			var pos = model.get("position")
			if pos == null:
				continue
			if pos is Dictionary:
				model_dict["position"] = Vector2(pos.get("x", 0), pos.get("y", 0))
			elif pos is Vector2:
				model_dict["position"] = pos
			else:
				continue
		other_models_data.append(model_dict)

	# Calculate coherency lines from ghost to each other model
	var lines_data = []
	var coherent_count = 0
	var total_count = other_models_data.size()

	for other_model in other_models_data:
		var other_pos = other_model.get("position", Vector2.ZERO)
		if other_pos is Dictionary:
			other_pos = Vector2(other_pos.get("x", 0), other_pos.get("y", 0))
		var dist_inches = Measurement.model_to_model_distance_inches(ghost_model, other_model)
		var in_coherency = Measurement.is_within_coherency(ghost_model, other_model)
		if in_coherency:
			coherent_count += 1

		lines_data.append({
			"world_pos": other_pos,
			"distance_inches": dist_inches,
			"in_coherency": in_coherency
		})

	# Determine coherency via the edition-aware single source of truth (11e 03.03:
	# within 2" of a mate AND within 9" of every other model in the unit). The ghost is
	# coherent when dropping the dragged model here leaves it satisfying coherency.
	var coherency_models = other_models_data.duplicate()
	coherency_models.append(ghost_model)
	var ghost_id = str(ghost_model.get("id", "__ghost__"))
	var coh_result = AttackSequence.check_unit_coherency({"models": coherency_models})
	var ghost_is_coherent = not (ghost_id in coh_result.get("offenders", []))

	# Build status text
	var status_text = "Coherent" if ghost_is_coherent else "Out of coherency"

	# Update the ghost visual with coherency data
	ghost_token.set_coherency_preview(lines_data, status_text, ghost_is_coherent)

	# Update the coherency status label
	_update_coherency_status_label(status_text, ghost_is_coherent)

	# Only log when coherency state changes to avoid per-frame spam
	if ghost_is_coherent != _last_coherency_state:
		print("P3-116: Coherency preview — %s (%d/%d in coherency)" % [
			"OK" if ghost_is_coherent else "BROKEN",
			coherent_count, total_count
		])
		_last_coherency_state = ghost_is_coherent

func _update_coherency_status_label(status_text: String, is_coherent: bool) -> void:
	"""P3-116: Update the coherency status label below the movement remaining label."""
	if not coherency_status_label or not is_instance_valid(coherency_status_label):
		return
	coherency_status_label.text = status_text
	if is_coherent:
		coherency_status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2, 0.8))
	else:
		coherency_status_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 0.9))

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

	# T-094 (revised): an Advance roll raises the move cap, so any reach circle
	# already on screen must grow to the new distance rather than show the stale,
	# smaller value. (A circle picked up after this point already reads the new
	# cap via _start_model_drag, so this only matters for a circle drawn before
	# the roll resolved.)
	_refresh_model_range_overlay()

func _refresh_model_range_overlay() -> void:
	# Redraw the currently-displayed per-model reach circle(s) using the latest
	# move cap. No-op when nothing is being dragged.
	if not is_instance_valid(move_range_visual):
		return
	if group_dragging:
		_show_group_range_overlay()
	elif dragging_model and not selected_model.is_empty():
		_show_model_range_overlay(selected_model, drag_start_pos)

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

	# Check if model has a non-circular base, or is a Vehicle with flying stem on round base >32mm
	var base_type = selected_model.get("base_type", "circular")
	var base_mm = selected_model.get("base_mm", 32)
	var has_flying_stem = selected_model.get("flying_stem", false)

	if base_type == "circular":
		# Vehicles on round bases >32mm with flying stem can still pivot (with cost)
		if not (base_mm > 32 and has_flying_stem):
			return  # No rotation needed for standard circular bases

	rotating_model = true
	var model_pos = selected_model.get("position", Vector2.ZERO)
	var to_mouse = mouse_pos - model_pos
	rotation_start_angle = to_mouse.angle()
	model_start_rotation = selected_model.get("rotation", 0.0)

	# Store original rotation in the phase's move data for undo/reset
	_store_original_rotation(selected_model.get("id", selected_model.get("model_id", "")), model_start_rotation)

	print("Starting rotation for model with base type: %s (base_mm: %d)" % [base_type, base_mm])

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
	var base_mm = selected_model.get("base_mm", 32)
	var has_flying_stem = selected_model.get("flying_stem", false)

	if base_type == "circular" and not (base_mm > 32 and has_flying_stem):
		return

	var current_rotation = selected_model.get("rotation", 0.0)
	# Store original rotation before first keyboard rotation
	_store_original_rotation(selected_model.get("id", selected_model.get("model_id", "")), current_rotation)
	var new_rotation = current_rotation + angle
	_apply_rotation_to_model(new_rotation)
	_check_and_apply_pivot_cost()

func _apply_rotation_to_model(new_rotation: float) -> void:
	# Update the model's rotation
	selected_model["rotation"] = new_rotation

	# Update the model in GameState — check bodyguard unit and attached characters
	var model_id = selected_model.get("id", selected_model.get("model_id", ""))
	var model_found = false
	var model_owner_unit_id = active_unit_id

	var unit = GameState.get_unit(active_unit_id)
	if unit:
		var models = unit.get("models", [])
		for i in range(models.size()):
			if models[i].get("id", "m%d" % (i+1)) == model_id:
				models[i]["rotation"] = new_rotation
				model_found = true
				break

		# If model not found in bodyguard, check attached characters
		if not model_found:
			var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
			for char_id in attached_chars:
				var char_unit = GameState.get_unit(char_id)
				if char_unit:
					var char_models = char_unit.get("models", [])
					for i in range(char_models.size()):
						if char_models[i].get("id", "m%d" % (i+1)) == model_id:
							char_models[i]["rotation"] = new_rotation
							model_owner_unit_id = char_id
							model_found = true
							break
				if model_found:
					break

	# Update the visual if it exists
	if current_phase and current_phase.has_method("update_model_rotation"):
		current_phase.update_model_rotation(model_owner_unit_id, selected_model["id"], new_rotation)

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

	# Get pivot value from the phase's active move data (10e Core Rules Update)
	if not current_phase or active_unit_id == "":
		return

	var move_data = {}
	if current_phase.has_method("get_active_move_data"):
		move_data = current_phase.get_active_move_data(active_unit_id)

	if move_data.is_empty():
		return

	var pivot_value = move_data.get("pivot_value", 0.0)
	if pivot_value <= 0:
		return  # No pivot cost for this unit

	if move_data.get("pivot_cost_applied", false):
		pivot_cost_paid = true  # Sync with phase state
		return

	# Apply pivot cost through the phase action system
	pivot_cost_paid = true
	pivot_cost_inches = pivot_value

	var action = {
		"type": "APPLY_PIVOT_COST",
		"actor_unit_id": active_unit_id
	}
	emit_signal("move_action_requested", action)

	var remaining_movement = move_cap_inches - pivot_value - _get_accumulated_distance()
	if remaining_movement < 0:
		print("WARNING: Pivot cost exceeds remaining movement!")
		if illegal_reason_label:
			illegal_reason_label.text = "Pivot cost (%.0f\") exceeds remaining movement!" % pivot_value
			illegal_reason_label.modulate = Color.RED

	print("Applied pivot cost of %.0f inches (10e Core Rules Update)" % pivot_value)
	_update_movement_display()

func _reset_pivot_cost() -> void:
	pivot_cost_paid = false
	pivot_cost_inches = 0.0

func _store_original_rotation(model_id: String, rotation: float) -> void:
	"""Store the original rotation for a model in the phase's move data for undo/reset."""
	if not current_phase or active_unit_id == "":
		return
	if not current_phase.has_method("get_active_move_data"):
		return
	var move_data = current_phase.get_active_move_data(active_unit_id)
	if move_data.is_empty():
		return
	# Only store the first rotation (the original) — don't overwrite
	if not move_data.has("original_rotations"):
		move_data["original_rotations"] = {}
	if not move_data["original_rotations"].has(model_id):
		move_data["original_rotations"][model_id] = rotation
		print("Stored original rotation %.2f for model %s" % [rotation, model_id])

func _get_effective_move_cap() -> float:
	"""Returns move cap adjusted for pivot cost (if any)."""
	if pivot_cost_paid:
		return move_cap_inches - pivot_cost_inches
	return move_cap_inches

func _update_model_token_visual(model: Dictionary) -> void:
	# Find and update the token visual directly
	var token_layer = SceneRefs.token_layer()
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

func _get_active_unit_keywords() -> Array:
	if active_unit_id == "":
		return []
	var unit = GameState.get_unit(active_unit_id)
	return unit.get("meta", {}).get("keywords", [])

func _get_terrain_penalty_for_move(from_pos: Vector2, to_pos: Vector2) -> float:
	"""Calculate terrain penalty via TerrainManager.
	Units always stay on ground floor — no height penalty. Only difficult ground applies."""
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if not terrain_manager or not terrain_manager.has_method("calculate_movement_terrain_penalty"):
		return 0.0
	# Pass keywords so INFANTRY moving through a ruin are not charged the 2"
	# difficult-ground penalty (10e: they move through walls/floors freely). This
	# also fixes the "sticky" penalty: the live preview recomputes from keywords
	# each frame, so an infantry model dragged onto then away from a ruin shows 0.
	var keywords = _get_active_unit_keywords()
	var has_fly = "FLY" in keywords
	return terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, has_fly, keywords)

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

	# Also check wall overlap, honoring the unit's per-keyword traversal rules
	# (e.g. INFANTRY can pass through ruin walls in 10e).
	if selected_model:
		var test_model = selected_model.duplicate()
		test_model["position"] = position
		if Measurement.model_overlaps_any_wall(test_model, _get_active_unit_keywords()):
			return true

	return false

func _is_position_outside_board(pos: Vector2, model: Dictionary) -> bool:
	# Issue #87: delegate to the shared Measurement helper so deployment,
	# movement, charge, and fight all use the same rule.
	return Measurement.model_outside_board(pos, model)

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

	var board_root = SceneRefs.board_root()
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
		# Check if clicked model belongs to a character attached to the active bodyguard unit
		if _is_model_in_active_unit_group(model.unit_id):
			print("MovementController: Ctrl+click on attached character model — character moves automatically with bodyguard")
			return
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

func _try_click_select_unit(mouse_pos: Vector2) -> bool:
	"""Click-to-select: a left-click on a model belonging to a DIFFERENT unit of
	the active player selects that unit, exactly as clicking its row in the
	right-hand unit list would. If the currently active unit still has an
	unconfirmed (staged) move, a UnitSwitchConfirmDialog asks the player first
	instead of switching silently. Returns true when the click was handled."""
	# In multiplayer, never select/switch units when it's not the local player's turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		return false

	# While a switch dialog is open, swallow further board clicks so a second
	# dialog can't stack on top of the first.
	if get_tree().root.get_node_or_null("UnitSwitchConfirmDialog") != null:
		return true

	# Don't switch units while a decision dialog is pausing the phase
	# (e.g. an advance-roll Command Re-roll offer).
	if get_tree().root.get_node_or_null("CommandRerollDialog") != null:
		return false

	var board_root = SceneRefs.board_root()
	var world_pos: Vector2
	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	var model = _get_model_at_position(world_pos)
	if model.is_empty():
		model = _get_model_near_position(world_pos, 10.0)
	if model.is_empty():
		return false

	var clicked_unit_id = str(model.get("unit_id", ""))
	if clicked_unit_id == "" or clicked_unit_id == active_unit_id:
		return false
	# Attached character models are dragged with the active bodyguard, not selected
	if _is_model_in_active_unit_group(clicked_unit_id):
		return false

	var unit = GameState.get_unit(clicked_unit_id)
	if not unit or unit.is_empty():
		return false
	# Only the active player's own units can be selected off the board
	if unit.get("owner", 0) != GameState.get_active_player():
		return false
	# Only units the right-hand list offers this phase are selectable
	if not _is_unit_selectable_in_list(clicked_unit_id):
		print("MovementController: Click on %s ignored — unit not selectable this phase" % clicked_unit_id)
		return false

	if _has_pending_unconfirmed_move(active_unit_id):
		print("MovementController: Click-to-select %s while %s has an unconfirmed move — asking player" % [clicked_unit_id, active_unit_id])
		_show_unit_switch_dialog(clicked_unit_id)
	else:
		print("MovementController: Click-to-select unit %s from board token" % clicked_unit_id)
		_select_unit_in_list_by_id(clicked_unit_id)
	return true

func _is_unit_selectable_in_list(unit_id: String) -> bool:
	"""True when `unit_id` has an enabled row in the right-hand unit list."""
	if not unit_list or not is_instance_valid(unit_list):
		return false
	for i in range(unit_list.get_item_count()):
		if unit_list.get_item_metadata(i) == unit_id:
			return not unit_list.is_item_disabled(i)
	return false

func _unit_switch_display_name(unit_id: String) -> String:
	var unit = GameState.get_unit(unit_id)
	if not unit or unit.is_empty():
		return unit_id
	var unit_meta = unit.get("meta", {})
	return unit_meta.get("display_name", unit_meta.get("name", unit_id))

func _show_unit_switch_dialog(target_unit_id: String) -> void:
	"""Ask the player whether to switch to `target_unit_id` while the active
	unit still has an unconfirmed move. Confirming routes through the normal
	list-selection flow, which auto-confirms the pending move first."""
	var dialog_script = load("res://dialogs/UnitSwitchConfirmDialog.gd")
	if not dialog_script:
		push_error("Failed to load UnitSwitchConfirmDialog.gd — switching without confirmation")
		_select_unit_in_list_by_id(target_unit_id)
		return

	var current_name = _unit_switch_display_name(active_unit_id)
	var target_name = _unit_switch_display_name(target_unit_id)
	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(current_name, target_name, target_unit_id,
		"%s's unconfirmed move will be confirmed." % current_name)
	dialog.switch_confirmed.connect(_on_unit_switch_confirmed)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("MovementController: Unit switch dialog shown (%s -> %s)" % [active_unit_id, target_unit_id])

func _on_unit_switch_confirmed(target_unit_id: String) -> void:
	# Same flow as clicking the unit's row in the list: _on_unit_selected
	# auto-confirms the previous unit's pending move before switching.
	print("MovementController: Unit switch confirmed — selecting %s" % target_unit_id)
	_select_unit_in_list_by_id(target_unit_id)

func _should_start_drag_box() -> bool:
	"""Determine if we should start drag-box selection (requires Shift key)"""
	# Start drag box only when Shift is held and we're not clicking directly on a model
	# This prevents conflicts with normal drag-to-move operations
	# Convert screen position to board-local coords before checking model overlap
	var board_root = SceneRefs.board_root()
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
	var board_root = SceneRefs.board_root()
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

	# Check if this model is in our selected models list. Match the SOURCE UNIT
	# too: model ids ("m1", …) collide between units, and a stale selection from
	# a previously moved unit matching a fresh unit's model by id alone silently
	# started a group drag of the OLD unit's models.
	var clicked_model_id = clicked_model.get("model_id", "")
	var clicked_unit_id = clicked_model.get("unit_id", "")
	for selected_model in selected_models:
		if selected_model.get("model_id", "") == clicked_model_id \
				and selected_model.get("unit_id", active_unit_id) == clicked_unit_id:
			return true

	return false

func _start_drag_box_selection(mouse_pos: Vector2) -> void:
	"""Start drag-box selection"""
	var board_root = SceneRefs.board_root()
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

	var board_root = SceneRefs.board_root()
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

	var board_root = SceneRefs.board_root()
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

	var board_root = SceneRefs.board_root()
	if not board_root or active_unit_id == "":
		return

	# Collect all unit IDs in the group (bodyguard + attached characters)
	var group_unit_ids = [active_unit_id]
	var active_unit_data = GameState.get_unit(active_unit_id)
	if active_unit_data:
		var attached_chars_preview = active_unit_data.get("attachment_data", {}).get("attached_characters", [])
		for char_id in attached_chars_preview:
			group_unit_ids.append(char_id)

	# Try visual tokens first
	var found_via_tokens = false
	var token_layer = SceneRefs.token_layer()
	if token_layer:
		for child in token_layer.get_children():
			if not child.has_meta("unit_id") or child.get_meta("unit_id") not in group_unit_ids:
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
	"""Select all models from the active unit and attached characters within the drag box"""
	if not current_phase or active_unit_id == "":
		print("_select_models_in_box: No current_phase or active_unit_id")
		return

	# Clear existing selection
	_clear_selection()

	# Collect all unit IDs in the group (bodyguard + attached characters)
	var group_unit_ids = [active_unit_id]
	var active_unit = GameState.get_unit(active_unit_id)
	if active_unit:
		var attached_chars = active_unit.get("attachment_data", {}).get("attached_characters", [])
		for char_id in attached_chars:
			group_unit_ids.append(char_id)

	# Define the selection rectangle
	var min_pos = Vector2(min(drag_box_start.x, drag_box_end.x), min(drag_box_start.y, drag_box_end.y))
	var max_pos = Vector2(max(drag_box_start.x, drag_box_end.x), max(drag_box_start.y, drag_box_end.y))

	print("Selecting models in box from (", min_pos, ") to (", max_pos, ") active_unit: ", active_unit_id)

	# FIRST: Try visual tokens on the board
	var found_via_tokens = false
	var token_layer = SceneRefs.token_layer()
	if token_layer:
		for child in token_layer.get_children():
			if not child.has_meta("unit_id") or child.get_meta("unit_id") not in group_unit_ids:
				continue
			if not child.has_meta("model_id"):
				continue

			found_via_tokens = true
			var token_unit_id = child.get_meta("unit_id")
			var model_id = child.get_meta("model_id")
			var visual_pos = child.position

			if visual_pos.x >= min_pos.x and visual_pos.x <= max_pos.x and \
			   visual_pos.y >= min_pos.y and visual_pos.y <= max_pos.y:
				# Skip duplicates (TokenLayer may have duplicate tokens for same unit)
				if _find_selected_model_index(model_id, token_unit_id) >= 0:
					continue
				var model = _get_model_by_id(token_unit_id, model_id)
				if model.is_empty():
					continue
				var model_data = model.duplicate()
				model_data["unit_id"] = token_unit_id
				model_data["model_id"] = model_id
				model_data["position"] = visual_pos
				selected_models.append(model_data)
				print("  Selected model ", model_id, " from unit ", token_unit_id, " at visual position ", visual_pos)

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

func _find_selected_model_index(model_id: String, unit_id: String = "") -> int:
	"""Find the index of a model in the selected_models array"""
	for i in range(selected_models.size()):
		if selected_models[i].get("model_id", "") == model_id:
			if unit_id == "" or selected_models[i].get("unit_id", "") == unit_id:
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
	var board_root = SceneRefs.board_root()
	if not board_root:
		return

	for model_data in selected_models:
		var model_id = model_data.get("model_id", "")
		var visual_pos = model_data.get("position", Vector2.ZERO)
		var base_radius = Measurement.base_radius_px(model_data.get("base_mm", 32))
		var found_token = false

		# Try visual tokens first
		var token_layer = SceneRefs.token_layer()
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
	var board_root = SceneRefs.board_root()
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

	# T-094 (revised): per-model reach circles for each model in the group
	_show_group_range_overlay()

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
		var model_source = model_data.get("unit_id", active_unit_id)
		var mk = "%s:%s" % [model_source, model_id]
		var used = 0.0

		# Get distance from current move data if available
		if current_phase and current_phase.active_moves.has(active_unit_id):
			var move_data = current_phase.active_moves[active_unit_id]
			used = move_data.model_distances.get(mk, 0.0)

		var remaining = _get_effective_move_cap() - used
		min_remaining = min(min_remaining, remaining)
		max_used = max(max_used, used)

	if inches_used_label:
		inches_used_label.text = "Group Max Used: %.1f\"" % max_used
	if inches_left_label:
		inches_left_label.text = "Group Min Left: %.1f\"" % min_remaining

func _select_all_unit_models() -> void:
	"""Select all models in the active unit and attached characters (Ctrl+A functionality)"""
	if not current_phase or active_unit_id == "":
		return

	_clear_selection()

	# Collect all unit IDs to select from (bodyguard + attached characters)
	var unit_ids_to_select = [active_unit_id]
	var unit = current_phase.get_unit(active_unit_id)
	if unit.is_empty():
		return

	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		unit_ids_to_select.append(char_id)

	for sel_unit_id in unit_ids_to_select:
		var sel_unit = current_phase.get_unit(sel_unit_id)
		if sel_unit.is_empty():
			continue
		var models = sel_unit.get("models", [])

		for i in range(models.size()):
			var model = models[i]
			if not model.get("alive", true):
				continue

			var model_id = model.get("id", "m%d" % (i+1))
			var model_data = model.duplicate()
			model_data["unit_id"] = sel_unit_id
			model_data["model_id"] = model_id
			model_data["position"] = _get_model_position(model)
			selected_models.append(model_data)

	selection_mode = "MULTI" if selected_models.size() > 1 else "SINGLE"
	_update_model_selection_visuals()
	_update_movement_display()

	print("Selected all ", selected_models.size(), " models in unit (including attached characters)")

func _update_group_drag(mouse_pos: Vector2) -> void:
	"""Update group drag movement"""
	if not group_dragging or selected_models.is_empty():
		return

	var board_root = SceneRefs.board_root()
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	# Calculate drag vector from drag start position
	var drag_vector = world_pos - drag_start_pos

	# P0 pad smoothness, group edition: clamp the whole formation to the tightest
	# member's remaining budget so the ghosts stop on the reach circles instead of
	# running past them (mirrors _clamp_move_to_budget in the single-model drag).
	# Mouse keeps its free red-preview drag.
	if InputDeviceManager.is_pad_active():
		drag_vector = _clamp_group_drag_vector(drag_vector)

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
			var model_source = model_data.get("unit_id", active_unit_id)
			var mk = "%s:%s" % [model_source, model_id]
			var start_pos = group_drag_start_positions.get(model_id, model_data.position)
			var new_pos = start_pos + drag_vector

			# Calculate distance for this drag
			var drag_distance = Measurement.distance_inches(start_pos, new_pos)

			# Get previously accumulated distance
			var previous_distance = move_data.model_distances.get(mk, 0.0)

			# Total distance would be previous + current drag
			var total_distance = previous_distance + drag_distance

			# Update tracking
			var remaining = _get_effective_move_cap() - total_distance
			min_remaining = min(min_remaining, remaining)
			max_used = max(max_used, total_distance)

		# Update the UI labels directly
		if inches_used_label:
			inches_used_label.text = "Group Max Used: %.1f\"" % max_used
		if inches_left_label:
			inches_left_label.text = "Group Min Left: %.1f\"" % min_remaining

		# Per-model validity → per-ghost coloring. The drop places every model
		# whose destination is legal (partial placement), so each ghost previews
		# its OWN fate: green = will be placed, red = will stay behind.
		var drag_len_inches: float = Measurement.px_to_inches(drag_vector.length())
		var placeable_count := 0
		var first_reason := ""
		var rejection_by_model := {}
		for model_data in selected_models:
			var reason := _group_move_rejection_for(model_data, group_drag_start_positions.get(model_data.model_id, model_data.position) + drag_vector, drag_len_inches, selected_models)
			rejection_by_model[model_data.model_id] = reason
			if reason == "":
				placeable_count += 1
			elif first_reason == "":
				first_reason = reason

		if illegal_reason_label:
			if placeable_count == selected_models.size():
				illegal_reason_label.text = ""
			elif placeable_count == 0:
				illegal_reason_label.text = first_reason
				illegal_reason_label.modulate = Color.RED
			else:
				illegal_reason_label.text = "%d of %d models can be placed here" % [placeable_count, selected_models.size()]
				illegal_reason_label.modulate = Color.ORANGE

		for child in ghost_visual.get_children():
			if child is Label:
				continue
			var ghost_ok: bool = str(rejection_by_model.get(child.get_meta("model_id", ""), "")) == ""
			if child.has_method("set_validity"):
				child.set_validity(ghost_ok)
			elif child.has_method("queue_redraw"):
				child.is_valid_position = ghost_ok
				child.queue_redraw()

		# Update floating movement remaining label for group drag
		_update_movement_remaining_label(min_remaining, placeable_count == selected_models.size())
		# Position label near the cursor during group drag
		if movement_remaining_label and is_instance_valid(movement_remaining_label):
			movement_remaining_label.position = world_pos + Vector2(-30, -40)

func _end_group_drag(mouse_pos: Vector2) -> void:
	"""End group drag movement — partial placement: models whose destination is
	legal are staged; blocked models stay where they were (and stay selected) so
	the player can re-drag just them. The whole drop only fails when NO model can
	be placed."""
	if not group_dragging:
		return

	print("Ending group drag with ", selected_models.size(), " models")

	var board_root = SceneRefs.board_root()
	var world_pos: Vector2

	if board_root:
		world_pos = board_root.transform.affine_inverse() * mouse_pos
	else:
		world_pos = get_global_mouse_position()

	# Calculate final drag vector
	var drag_vector = world_pos - drag_start_pos
	# Pad drop: same budget clamp the live preview used, so the drop lands where
	# the ghosts stopped instead of being rejected past the reach circle.
	if InputDeviceManager.is_pad_active():
		drag_vector = _clamp_group_drag_vector(drag_vector)

	# Freeze the members + start positions, then tear down the live-drag state
	# immediately: the staging below awaits, and a still-true group_dragging
	# would keep feeding cursor motion into _update_group_drag meanwhile.
	var members: Array = selected_models.duplicate()
	var starts: Dictionary = group_drag_start_positions.duplicate()
	group_dragging = false
	group_drag_start_positions.clear()
	group_formation_offsets.clear()
	_clear_ghost_visual()
	_clear_move_range_overlay()  # T-094 (revised): remove per-model reach circles

	if not current_phase or members.is_empty():
		_update_movement_display()
		_update_model_selection_visuals()
		return

	# Per-model legality (client-side; the phase re-validates on staging). A
	# member's destination is judged against everything EXCEPT the other members
	# — they are all moving by the same vector, so member-vs-member spacing is
	# preserved by construction.
	var placeable: Array = []
	var blocked: Array = []
	var first_reason := ""
	var drag_len_inches: float = Measurement.px_to_inches(drag_vector.length())
	for model_data in members:
		var start_pos = starts.get(model_data.model_id, model_data.position)
		var reason := _group_move_rejection_for(model_data, start_pos + drag_vector, drag_len_inches, members)
		if reason == "":
			placeable.append(model_data)
		else:
			blocked.append(model_data)
			if first_reason == "":
				first_reason = reason
			print("Group drop: model %s blocked — %s" % [str(model_data.model_id), reason])

	var toast_mgr = get_node_or_null("/root/ToastManager")
	if placeable.is_empty():
		# Nothing fits at that spot — refuse the whole drop (models stay put and
		# stay selected so the player can immediately try another spot).
		print("Group move cancelled: ", first_reason)
		if illegal_reason_label:
			illegal_reason_label.text = first_reason
			illegal_reason_label.modulate = Color.RED
		if toast_mgr and toast_mgr.has_method("show_error"):
			toast_mgr.show_error(first_reason if first_reason != "" else "No model in the group can be placed there")
		_update_movement_display()
		_update_model_selection_visuals()
		return

	# Stage front-most first (largest projection along the drag direction).
	# The phase checks a destination against other models' staged-or-current
	# positions, so a member moving into the spot a leading member is vacating
	# must stage AFTER that leader — front-most-first makes tight formations
	# stage cleanly in one pass instead of relying on retries.
	if drag_vector.length() > 0.001:
		var dir := drag_vector.normalized()
		placeable.sort_custom(func(a, b):
			var pa: Vector2 = starts.get(a.model_id, a.position)
			var pb: Vector2 = starts.get(b.model_id, b.position)
			return pa.dot(dir) > pb.dot(dir))

	group_drop_in_flight = true
	var batch_moves = []
	for model_data in placeable:
		var model_id = model_data.model_id
		var start_pos = starts.get(model_id, model_data.position)
		var new_pos = start_pos + drag_vector
		batch_moves.append({
			"model_id": model_id,
			"source_unit_id": model_data.get("unit_id", active_unit_id),
			"dest": [new_pos.x, new_pos.y],
			"rotation": model_data.get("rotation", 0.0),
			"start_pos": start_pos
		})
		print("  Preparing move for model ", model_id, " from ", start_pos, " to ", new_pos)

	for move in batch_moves:
		emit_signal("move_action_requested", _build_group_stage_action(move))
		# Small delay to ensure signal processing completes before the next one
		await get_tree().create_timer(0.01).timeout

	print("Sent ", batch_moves.size(), " group move actions (", blocked.size(), " blocked client-side)")

	# Verify what actually staged; retry stragglers once (a member can be
	# rejected because another member had not staged yet when it was checked).
	await get_tree().create_timer(0.1).timeout
	var missing := _unstaged_batch_moves(batch_moves)
	if missing.size() > 0:
		print("[WARNING] ", missing.size(), " group moves failed to stage — retrying: ", missing.map(func(mv): return mv.model_id))
		for move in missing:
			emit_signal("move_action_requested", _build_group_stage_action(move))
			await get_tree().create_timer(0.01).timeout
		await get_tree().create_timer(0.1).timeout
		missing = _unstaged_batch_moves(batch_moves)

	# Anything still missing joins the blocked pile (the phase refused it —
	# e.g. engagement range or a rule the client-side pre-check doesn't model).
	for move in missing:
		for model_data in placeable:
			if model_data.model_id == move.model_id and model_data.get("unit_id", active_unit_id) == move.source_unit_id:
				blocked.append(model_data)
				break
	var moved_count: int = placeable.size() - missing.size()
	print("Group drop result: ", moved_count, "/", members.size(), " models staged")

	if blocked.is_empty():
		if illegal_reason_label:
			illegal_reason_label.text = ""
	else:
		# Partial drop: keep ONLY the leftover models selected so the next drag
		# (mouse) / re-grab (pad) moves exactly the models still to be placed.
		selected_models = blocked.duplicate()
		selection_mode = "MULTI" if selected_models.size() > 1 else "SINGLE"
		var reason_note := (" (%s)" % first_reason) if first_reason != "" else ""
		if toast_mgr and toast_mgr.has_method("show_warning"):
			toast_mgr.show_warning("Placed %d of %d models — %d couldn't be placed there%s" % [moved_count, members.size(), blocked.size(), reason_note])

	group_drop_in_flight = false

	# Update displays
	_update_movement_display()
	_update_model_selection_visuals()


func _build_group_stage_action(move: Dictionary) -> Dictionary:
	var payload = {
		"model_id": move.model_id,
		"dest": move.dest,
		"rotation": move.rotation
	}
	# Attached-character models stage under the bodyguard's move with their
	# source unit spelled out ("m1" ids collide between the two units).
	if str(move.source_unit_id) != "" and str(move.source_unit_id) != active_unit_id:
		payload["model_source_unit_id"] = move.source_unit_id
	return {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": payload
	}


func _unstaged_batch_moves(batch_moves: Array) -> Array:
	"""The subset of batch_moves that has no staged move recorded for the active
	unit (source-unit aware — bodyguard and attached character ids can collide)."""
	var staged := _staged_keys_for_active_unit()
	var missing: Array = []
	for move in batch_moves:
		if not staged.has("%s:%s" % [str(move.source_unit_id), str(move.model_id)]):
			missing.append(move)
	return missing


func _staged_keys_for_active_unit() -> Dictionary:
	"""Set of "source_unit_id:model_id" keys with a staged move in the active
	unit's move data."""
	var keys := {}
	if not current_phase or active_unit_id == "" or not current_phase.has_method("get_active_move_data"):
		return keys
	var move_data = current_phase.get_active_move_data(active_unit_id)
	for staged_move in move_data.get("staged_moves", []):
		var src := str(staged_move.get("model_source_unit_id", active_unit_id))
		keys["%s:%s" % [src, str(staged_move.get("model_id", ""))]] = true
	return keys


func _clamp_group_drag_vector(v: Vector2) -> Vector2:
	"""Clamp a group drag vector so no member exceeds its remaining movement
	budget (geometry only, like _clamp_move_to_budget — endpoint legality stays
	with the drop checks)."""
	var len_px := v.length()
	if len_px <= 0.0:
		return v
	var max_used := 0.0
	for model_data in selected_models:
		max_used = max(max_used, _get_accumulated_distance_for_model(model_data))
	var allowed_inches: float = max(0.0, _get_effective_move_cap() - max_used)
	if Measurement.px_to_inches(len_px) <= allowed_inches + MOVEMENT_CAP_EPSILON:
		return v
	return v.normalized() * Measurement.inches_to_px(allowed_inches)


func _group_move_rejection_for(model_data: Dictionary, dest: Vector2, drag_len_inches: float, members: Array) -> String:
	"""Why moving this group member by the group's drag vector is illegal
	("" = legal): over its budget, off the board, on a wall, or overlapping a
	model OUTSIDE the moving group. Client-side approximation of the phase's
	STAGE_MODEL_MOVE validation, minus the other moving members (rigid
	translation preserves member spacing)."""
	var total: float = _get_accumulated_distance_for_model(model_data) + drag_len_inches
	var effective_cap: float = _get_effective_move_cap()
	if total > effective_cap + MOVEMENT_CAP_EPSILON:
		return "Movement exceeds %.1f\" cap (would be %.1f\")" % [effective_cap, total]
	var source_unit_id: String = str(model_data.get("unit_id", active_unit_id))
	var full_model = _get_model_by_id(source_unit_id, model_data.model_id)
	if full_model.is_empty():
		full_model = model_data
	if _is_position_outside_board(dest, full_model):
		return "Cannot place model beyond the board edge"
	var test_model = full_model.duplicate()
	test_model["position"] = dest
	if Measurement.model_overlaps_any_wall(test_model, _get_active_unit_keywords()):
		return "Cannot place model overlapping a wall this unit can't cross"
	if _group_dest_overlaps_non_member(test_model, source_unit_id, str(model_data.model_id), members):
		return "Cannot place model overlapping another model"
	return ""


func _group_dest_overlaps_non_member(test_model: Dictionary, source_unit_id: String, model_id: String, members: Array) -> bool:
	"""Would test_model (already at its destination) overlap any alive model that
	is NOT part of the moving group? Staged positions win over pre-move ones
	(mirrors MovementPhase._position_overlaps_other_models, including its
	touching tolerance for circular bases)."""
	var member_keys := {}
	for member in members:
		member_keys["%s:%s" % [str(member.get("unit_id", active_unit_id)), str(member.model_id)]] = true
	member_keys["%s:%s" % [source_unit_id, model_id]] = true
	var staged_dests := {}
	if current_phase and active_unit_id != "" and current_phase.has_method("get_active_move_data"):
		for staged_move in current_phase.get_active_move_data(active_unit_id).get("staged_moves", []):
			var src := str(staged_move.get("model_source_unit_id", active_unit_id))
			staged_dests["%s:%s" % [src, str(staged_move.get("model_id", ""))]] = staged_move.get("dest")
	var test_pos: Vector2 = test_model.get("position", Vector2.ZERO)
	var test_circular: bool = test_model.get("base_type", "circular") == "circular"
	var test_radius: float = Measurement.base_radius_px(test_model.get("base_mm", 32))
	var units = GameState.state.get("units", {})
	for check_unit_id in units:
		var models = units[check_unit_id].get("models", [])
		for i in range(models.size()):
			var other = models[i]
			if not other.get("alive", true):
				continue
			var other_id := str(other.get("id", "m%d" % (i + 1)))
			var key := "%s:%s" % [str(check_unit_id), other_id]
			if member_keys.has(key):
				continue
			var other_pos = staged_dests.get(key, null)
			if other_pos == null:
				# Embarked/undeployed models have no position — they can't be
				# collided with (mirrors the phase checker's null skip).
				if other.get("position") == null:
					continue
				other_pos = _get_model_position(other)
			elif other_pos is Array and other_pos.size() >= 2:
				other_pos = Vector2(float(other_pos[0]), float(other_pos[1]))
			if not (other_pos is Vector2):
				continue
			# Circular-vs-circular fast path (the common case — this runs per
			# member per drag frame): pure distance math, with the same 0.5px
			# touching tolerance MovementPhase applies, and no dict duplication.
			if test_circular and other.get("base_type", "circular") == "circular":
				var other_radius: float = Measurement.base_radius_px(other.get("base_mm", 32))
				if test_pos.distance_to(other_pos) + 0.5 < (test_radius + other_radius):
					return true
				continue
			var other_check = other.duplicate()
			other_check["position"] = other_pos
			if Measurement.models_overlap(test_model, other_check):
				# Same touching tolerance the phase applies for circular pairs,
				# so a base placed exactly against a staged neighbour isn't
				# flagged here only to be accepted by the phase.
				if _circles_touch_within_tolerance(test_model, other_check):
					continue
				return true
	return false


func _circles_touch_within_tolerance(model_a: Dictionary, model_b: Dictionary) -> bool:
	if model_a.get("base_type", "circular") != "circular" or model_b.get("base_type", "circular") != "circular":
		return false
	var pos_a = model_a.get("position", Vector2.ZERO)
	var pos_b = model_b.get("position", Vector2.ZERO)
	if pos_a is Dictionary:
		pos_a = Vector2(pos_a.get("x", 0), pos_a.get("y", 0))
	if pos_b is Dictionary:
		pos_b = Vector2(pos_b.get("x", 0), pos_b.get("y", 0))
	var radius_a = Measurement.base_radius_px(model_a.get("base_mm", 32))
	var radius_b = Measurement.base_radius_px(model_b.get("base_mm", 32))
	# 0.5px tolerance — matches MovementPhase.OVERLAP_TOLERANCE_PX.
	return pos_a.distance_to(pos_b) + 0.5 >= (radius_a + radius_b)

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

	# Create floating movement remaining indicator for group drag
	movement_remaining_label = Label.new()
	movement_remaining_label.name = "MovementRemainingLabel"
	movement_remaining_label.text = ""
	movement_remaining_label.add_theme_font_size_override("font_size", 16)
	movement_remaining_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 0.9))
	movement_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	movement_remaining_label.z_index = 58
	movement_remaining_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_visual.add_child(movement_remaining_label)

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

	# Show the advance roll in the dice log
	var rolls = roll_context.get("original_rolls", [])
	var unit_name = roll_context.get("unit_name", unit_id)
	if is_instance_valid(dice_log_display):
		var roll_val = rolls[0] if rolls.size() > 0 else 0
		dice_log_display.append_text("[color=orange]Advance Roll:[/color] %s rolled D6 = %d\n" % [unit_name, roll_val])
		dice_log_display.append_text("[color=gold]Command Re-roll available! (1 CP)[/color]\n")

	# Skip dialog for AI players — AIPlayer handles the decision via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("MovementController: Skipping command reroll dialog for AI player %d" % player)
		return

	# Multiplayer: the re-roll decision belongs to the advancing unit's OWNER —
	# only their seat shows the dialog.
	if NetworkManager and NetworkManager.is_networked() \
			and NetworkManager.get_local_player() != player:
		print("MovementController: Command Re-roll is P%d's decision — local seat waits" % player)
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
	DialogUtils.popup_at_bottom(dialog)
	print("MovementController: Command Re-roll dialog shown for player %d" % player)

func _on_command_reroll_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Command Re-roll for advance."""
	print("MovementController: Command Re-roll USED for %s advance" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gold]COMMAND RE-ROLL used! (1 CP) Re-rolling advance...[/color]\n")
	emit_signal("move_action_requested", {
		"type": "USE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

func _on_command_reroll_declined(unit_id: String, player: int) -> void:
	"""Handle player declining Command Re-roll for advance."""
	print("MovementController: Command Re-roll DECLINED for %s advance" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Kept original advance roll.[/color]\n")
	emit_signal("move_action_requested", {
		"type": "DECLINE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

func _on_command_reroll_completed(original_rolls: Array, new_rolls: Array, context: String) -> void:
	"""P3-118: Show reroll comparison visualization when Command Re-roll completes."""
	print("MovementController: Reroll comparison — %s → %s (%s)" % [str(original_rolls), str(new_rolls), context])
	if dice_roll_visual and is_instance_valid(dice_roll_visual):
		dice_roll_visual.show_reroll_comparison(original_rolls, new_rolls, context)

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

	# Auto-decline if the player has toggled auto-decline overwatch
	var auto_decline_btn = SceneRefs.main_path("HUD_Bottom/HBoxContainer/AutoDeclineOverwatch")
	if auto_decline_btn and auto_decline_btn.button_pressed:
		print("MovementController: Auto-declining Fire Overwatch for player %d (toggle enabled)" % defending_player)
		_on_fire_overwatch_declined(defending_player)
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
	DialogUtils.popup_at_bottom(dialog)
	print("MovementController: Fire Overwatch dialog shown for player %d" % defending_player)

	# MA-42: Show blocking overlay to active player
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("show_reactive_stratagem_waiting"):
		main_node.show_reactive_stratagem_waiting("Fire Overwatch")

func _on_fire_overwatch_used(shooter_unit_id: String, player: int) -> void:
	"""Handle player choosing to use Fire Overwatch."""
	print("MovementController: Fire Overwatch USED by %s" % shooter_unit_id)
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
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
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
	emit_signal("move_action_requested", {
		"type": "DECLINE_FIRE_OVERWATCH",
		"actor_unit_id": "",
	})

# ===================================================
# RAPID INGRESS HANDLING (T4-7)
# ===================================================

func _on_rapid_ingress_opportunity(player: int, eligible_units: Array) -> void:
	"""Handle Rapid Ingress opportunity — show dialog to the non-active player.
	In networked mode, only shows the interactive dialog on the correct player's client.
	The active player sees a 'Waiting for opponent...' notification instead."""
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

	# In networked mode, only show the dialog to the player who owns the reserves
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked():
		var local_player = network_manager.get_local_player()
		if local_player != player:
			# This client is the active player — show a waiting notification
			print("MovementController: Local player %d is not rapid ingress player %d — showing waiting notification" % [local_player, player])
			var toast_mgr = get_node_or_null("/root/ToastManager")
			if toast_mgr:
				toast_mgr.show_toast("Waiting for opponent to decide on Rapid Ingress... (10s)", Color.DODGER_BLUE, 10.0)
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
	DialogUtils.popup_at_bottom(dialog)
	print("MovementController: Rapid Ingress dialog shown for player %d (10s countdown)" % player)

	# MA-42: Show blocking overlay to active player
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("show_reactive_stratagem_waiting"):
		main_node.show_reactive_stratagem_waiting("Rapid Ingress")

func _on_rapid_ingress_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Rapid Ingress."""
	print("MovementController: Rapid Ingress USED — unit %s by player %d" % [unit_id, player])
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
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
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
	emit_signal("move_action_requested", {
		"type": "DECLINE_RAPID_INGRESS",
		"actor_unit_id": "",
	})

# ===================================================
# KRUMP AND RUN HANDLING (OA-8)
# ===================================================

func _on_krump_and_run_opportunity(player: int, eligible_units: Array, fell_back_unit_id: String) -> void:
	"""Handle Krump and Run opportunity — show dialog to the defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ MovementController: KRUMP AND RUN OPPORTUNITY")
	print("║ Player %d has %d eligible ORKS units after enemy fell back" % [player, eligible_units.size()])
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip dialog for AI players — AIPlayer handles via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("MovementController: Skipping Krump and Run dialog for AI player %d" % player)
		_on_krump_and_run_declined(player)
		return

	if eligible_units.is_empty():
		_on_krump_and_run_declined(player)
		return

	# Load and show the dialog
	var dialog_script = load("res://dialogs/KrumpAndRunDialog.gd")
	if not dialog_script:
		push_error("Failed to load KrumpAndRunDialog.gd")
		_on_krump_and_run_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(player, eligible_units, fell_back_unit_id)
	dialog.krump_and_run_used.connect(_on_krump_and_run_used)
	dialog.krump_and_run_declined.connect(_on_krump_and_run_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("MovementController: Krump and Run dialog shown for player %d" % player)

func _on_krump_and_run_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Krump and Run."""
	print("MovementController: Krump and Run USED — unit %s by player %d" % [unit_id, player])
	emit_signal("move_action_requested", {
		"type": "USE_KRUMP_AND_RUN",
		"actor_unit_id": unit_id,
		"payload": {
			"unit_id": unit_id
		}
	})

func _on_krump_and_run_declined(player: int) -> void:
	"""Handle player declining Krump and Run."""
	print("MovementController: Krump and Run DECLINED by player %d" % player)
	emit_signal("move_action_requested", {
		"type": "DECLINE_KRUMP_AND_RUN",
		"actor_unit_id": "",
	})

# ===================================================
# OA-42: SCATTER! HANDLING
# ===================================================

func _on_scatter_opportunity(player: int, eligible_units: Array, trigger_unit_id: String) -> void:
	"""Handle Scatter! opportunity — show dialog to the defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ MovementController: SCATTER! OPPORTUNITY")
	print("║ Player %d has %d eligible unit(s) after enemy moved within 9\"" % [player, eligible_units.size()])
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip dialog for AI players — AIPlayer handles via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("MovementController: Skipping Scatter! dialog for AI player %d" % player)
		_on_scatter_declined(player)
		return

	if eligible_units.is_empty():
		_on_scatter_declined(player)
		return

	# Load and show the dialog
	var dialog_script = load("res://dialogs/ScatterDialog.gd")
	if not dialog_script:
		push_error("Failed to load ScatterDialog.gd")
		_on_scatter_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(player, eligible_units, trigger_unit_id)
	dialog.scatter_used.connect(_on_scatter_used)
	dialog.scatter_declined.connect(_on_scatter_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("MovementController: Scatter! dialog shown for player %d" % player)

func _on_scatter_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Scatter!."""
	print("MovementController: Scatter! USED — unit %s by player %d" % [unit_id, player])
	emit_signal("move_action_requested", {
		"type": "USE_SCATTER",
		"actor_unit_id": unit_id,
		"payload": {
			"unit_id": unit_id
		}
	})

func _on_scatter_declined(player: int) -> void:
	"""Handle player declining Scatter!."""
	print("MovementController: Scatter! DECLINED by player %d" % player)
	emit_signal("move_action_requested", {
		"type": "DECLINE_SCATTER",
		"actor_unit_id": "",
	})

# ===================================================
# KUNNIN' INFILTRATOR HANDLING (OA-24)
# ===================================================

func _on_kunnin_infiltrator_available(unit_id: String, player: int) -> void:
	"""Handle Kunnin' Infiltrator activation — notify UI that redeployment placement is needed.
	The actual placement is handled by Main.gd via DeploymentController (same as reinforcements)."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ MovementController: KUNNIN' INFILTRATOR AVAILABLE")
	print("║ Unit: %s, Player: %d" % [unit_id, player])
	print("║ Awaiting redeployment placement via DeploymentController...")
	print("╚═══════════════════════════════════════════════════════════════")

	# Refresh the UI to show the updated available actions (PLACE/CANCEL)
	_refresh_unit_list()
	emit_signal("ui_update_requested")

# ===================================================
# SPECIAL MOVEMENT ACTION POPUP (OA-24)
# Shows a popup when a unit has abilities like Kunnin' Infiltrator
# that replace the Normal Move, letting the player choose.
# ===================================================

func _get_special_movement_actions(unit_id: String) -> Array:
	"""Check phase available actions for special movement abilities for this unit.
	Returns an array of special action dictionaries (e.g. ACTIVATE_KUNNIN_INFILTRATOR)."""
	if not current_phase:
		print("MovementController: _get_special_movement_actions — no current_phase")
		return []

	var special_types = ["ACTIVATE_KUNNIN_INFILTRATOR"]
	var special_actions = []
	var actions = current_phase.get_available_actions()
	print("MovementController: _get_special_movement_actions for %s — checking %d available actions" % [unit_id, actions.size()])
	for action in actions:
		var action_type = action.get("type", "")
		var action_unit = action.get("actor_unit_id", action.get("unit_id", ""))
		if action_unit == unit_id:
			print("MovementController:   Action for %s: type=%s" % [unit_id, action_type])
		if action_unit == unit_id and action_type in special_types:
			special_actions.append(action)
	return special_actions

func _show_movement_action_popup(unit_id: String, special_actions: Array) -> void:
	"""Show a popup menu letting the player choose between Normal Move and special actions.
	Deferred to next frame to avoid the unit-list click immediately closing the popup."""
	_popup_pending_unit_id = unit_id
	_popup_pending_special_actions = special_actions
	# Defer to next frame so the current mouse click doesn't immediately close the popup
	call_deferred("_show_movement_action_popup_deferred")

var _popup_pending_special_actions: Array = []

func _show_movement_action_popup_deferred() -> void:
	"""Actually show the popup (called deferred to avoid click-through)."""
	var unit_id = _popup_pending_unit_id
	var special_actions = _popup_pending_special_actions
	_popup_pending_special_actions = []

	if unit_id == "":
		return

	# Create popup if needed
	if _movement_action_popup == null:
		_movement_action_popup = PopupMenu.new()
		_movement_action_popup.name = "MovementActionPopup"
		add_child(_movement_action_popup)
		_movement_action_popup.id_pressed.connect(_on_movement_action_popup_selected)
		_movement_action_popup.popup_hide.connect(_on_movement_action_popup_closed)

	_movement_action_popup.clear()

	# Add Normal Move as the first option (ID 0)
	_movement_action_popup.add_item("Normal Move", 0)

	# Add each special action
	for i in range(special_actions.size()):
		var action = special_actions[i]
		var label = action.get("description", action.get("type", "Special Action"))
		_movement_action_popup.add_item(label, 100 + i)
		# Store action data in metadata
		_movement_action_popup.set_item_metadata(_movement_action_popup.get_item_count() - 1, action)

	# Position popup near mouse
	var popup_pos = get_viewport().get_mouse_position()
	_movement_action_popup.position = Vector2i(int(popup_pos.x), int(popup_pos.y))
	_movement_action_popup.popup()

	var unit_name = GameState.get_unit(unit_id).get("meta", {}).get("name", unit_id) if GameState.get_unit(unit_id) else unit_id
	print("MovementController: Showing movement action popup for %s with %d special actions" % [unit_name, special_actions.size()])

func _on_movement_action_popup_selected(id: int) -> void:
	"""Handle player's choice from the movement action popup."""
	var unit_id = _popup_pending_unit_id
	_popup_pending_unit_id = ""

	if unit_id == "":
		return

	if id == 0:
		# Normal Move selected
		print("MovementController: Player chose Normal Move for %s" % unit_id)
		var action = {
			"type": "BEGIN_NORMAL_MOVE",
			"actor_unit_id": unit_id
		}
		emit_signal("move_action_requested", action)
	else:
		# Special action selected — find the metadata
		for item_idx in range(_movement_action_popup.item_count):
			if _movement_action_popup.get_item_id(item_idx) == id:
				var action = _movement_action_popup.get_item_metadata(item_idx)
				if action and action is Dictionary:
					var action_type = action.get("type", "")
					print("MovementController: Player chose special action %s for %s" % [action_type, unit_id])
					emit_signal("move_action_requested", {
						"type": action_type,
						"actor_unit_id": unit_id
					})
				break

func _on_movement_action_popup_closed() -> void:
	"""Handle popup dismissed without selection — player can re-select or use radio buttons."""
	if _popup_pending_unit_id != "":
		print("MovementController: Movement action popup dismissed for %s — use radio buttons or re-select" % _popup_pending_unit_id)
		_popup_pending_unit_id = ""


# ── Pad (M4) move-mode action menu adapters ────────────────────────────────
# PadRouter opens PadActionBar with pad_menu_options() when the pad player
# presses A on a selected unit whose movement mode is still open, and applies
# the choice through pad_apply_menu_choice(). Both delegate to the exact
# handlers the mouse radios / Confirm Movement Mode button use, so payload
# logic (SHW gamble, turbo, mode locking, advance dice) stays in one place.

func pad_can_cycle_to(unit_id: String) -> bool:
	"""Bumper cycling skips units whose activation is spent (PRP §2.6: cycling
	follows eligibility, not raw list order). Mouse row-clicks are unaffected."""
	return _get_unit_movement_status(unit_id) != "completed"


func pad_carry_drop_rejection(screen_pos: Vector2) -> String:
	"""Pad carry seam: would dropping the carried model at screen_pos be
	rejected? Returns the toast reason ("" = legal), computed at the EXACT world
	position _end_model_drag would stage (same board transform, grid snap and
	over-range budget clamp). PadRouter consults this BEFORE releasing the
	synthetic button so an illegal drop keeps the model in hand instead of
	snapping it back and stranding the cursor."""
	if not dragging_model:
		return ""
	var board_root = SceneRefs.board_root()
	var world_pos: Vector2 = board_root.transform.affine_inverse() * screen_pos if board_root else get_global_mouse_position()
	if _should_snap_to_grid():
		world_pos = _snap_to_grid(world_pos)
	if InputDeviceManager.is_pad_active():
		world_pos = _clamp_move_to_budget(world_pos)
	return _compute_move_rejection(world_pos)


# ── Pad group carry ("grab all unmoved models") seams ───────────────────────
# PadRouter starts a group carry by (1) pad_select_unmoved_models(), (2) warping
# the virtual cursor onto pad_group_anchor_world_pos() and (3) holding the
# synthetic left button — the click lands on a selected model, so the exact
# mouse group-drag pipeline (_start_group_movement → _update_group_drag →
# _end_group_drag) runs underneath, partial placement included.

func pad_can_grab_group() -> bool:
	"""True while the active unit has a live, unfinished move session — the only
	state in which STAGE_MODEL_MOVE (and therefore a group carry) is accepted."""
	if active_unit_id == "":
		return false
	if not current_phase or not current_phase.has_method("get_active_move_data"):
		return false
	var move_data = current_phase.get_active_move_data(active_unit_id)
	return not move_data.is_empty() and not move_data.get("completed", false)


func pad_select_unmoved_models() -> int:
	"""Select every alive model of the active unit (and its attached characters)
	that has NO staged move yet — "all models still to be moved". Returns the
	number selected (0 = nothing left to move)."""
	if not current_phase or active_unit_id == "":
		return 0
	_clear_selection()
	var staged := _staged_keys_for_active_unit()
	var unit_ids = [active_unit_id]
	var unit = current_phase.get_unit(active_unit_id)
	if unit.is_empty():
		return 0
	for char_id in unit.get("attachment_data", {}).get("attached_characters", []):
		unit_ids.append(char_id)
	for sel_unit_id in unit_ids:
		var sel_unit = current_phase.get_unit(sel_unit_id)
		if sel_unit.is_empty():
			continue
		var models = sel_unit.get("models", [])
		for i in range(models.size()):
			var model = models[i]
			if not model.get("alive", true):
				continue
			var model_id = model.get("id", "m%d" % (i + 1))
			if staged.has("%s:%s" % [str(sel_unit_id), str(model_id)]):
				continue  # already placed this move — keeps its spot
			var model_data = model.duplicate()
			model_data["unit_id"] = sel_unit_id
			model_data["model_id"] = model_id
			model_data["position"] = _get_model_position(model)
			selected_models.append(model_data)
	selection_mode = "MULTI" if selected_models.size() > 1 else "SINGLE"
	_update_model_selection_visuals()
	_update_movement_display()
	print("Pad group carry: selected ", selected_models.size(), " unmoved models of ", active_unit_id)
	return selected_models.size()


func pad_group_anchor_world_pos():
	"""World position of the selected model nearest the selection's centroid —
	where the pad warps the cursor so the synthetic pickup click lands ON a
	selected model. Null when nothing is selected."""
	if selected_models.is_empty():
		return null
	var center := _calculate_group_center(selected_models)
	var best = null
	var best_d := INF
	for model_data in selected_models:
		var pos: Vector2 = model_data.get("position", Vector2.ZERO)
		var d := pos.distance_squared_to(center)
		if d < best_d:
			best_d = d
			best = pos
	return best


func pad_group_drop_rejection(screen_pos: Vector2) -> String:
	"""Group-carry drop check: "" when AT LEAST ONE carried model can legally be
	placed at the translated destination (the drop then stages exactly those),
	else the blocking reason. PadRouter consults this BEFORE releasing so a
	fully-illegal drop keeps the group in hand."""
	if not group_dragging or selected_models.is_empty():
		return ""
	var board_root = SceneRefs.board_root()
	var world_pos: Vector2 = board_root.transform.affine_inverse() * screen_pos if board_root else get_global_mouse_position()
	var drag_vector: Vector2 = world_pos - drag_start_pos
	if InputDeviceManager.is_pad_active():
		drag_vector = _clamp_group_drag_vector(drag_vector)
	var drag_len_inches: float = Measurement.px_to_inches(drag_vector.length())
	var first_reason := ""
	for model_data in selected_models:
		var start_pos = group_drag_start_positions.get(model_data.model_id, model_data.position)
		var reason := _group_move_rejection_for(model_data, start_pos + drag_vector, drag_len_inches, selected_models)
		if reason == "":
			return ""
		if first_reason == "":
			first_reason = reason
	return first_reason if first_reason != "" else "No model in the group can be placed there"


func pad_group_drop_busy() -> bool:
	return group_drop_in_flight


func pad_abort_group_drag() -> void:
	"""Cancel a live group carry WITHOUT staging anything (pad B): models never
	left their spots — only ghosts moved — so tearing down the drag state and
	selection restores the pre-grab state exactly."""
	group_dragging = false
	group_drag_start_positions.clear()
	group_formation_offsets.clear()
	_clear_ghost_visual()
	_clear_move_range_overlay()
	_clear_selection()
	_update_movement_display()


func pad_is_move_session_locked() -> bool:
	"""True once the active unit has committed to its move — mode locked (Advance
	rolled, Fall Back, confirmed) OR at least one model staged/committed. While
	locked, the pad bumpers refuse to switch units (deployment-style lock) so a
	mis-cycle can't strand a half-moved unit. Choosing a mode but not yet touching
	a model does NOT lock, so the player can still freely change their mind."""
	if active_unit_id == "":
		return false
	if not current_phase or not current_phase.has_method("get_active_move_data"):
		return false
	var move_data = current_phase.get_active_move_data(active_unit_id)
	if move_data.is_empty() or move_data.get("completed", false):
		return false
	if move_data.get("mode_locked", false):
		return true
	return not move_data.get("staged_moves", []).is_empty() \
		or not move_data.get("model_moves", []).is_empty()


func pad_confirm_move() -> bool:
	"""Start-button context action in the Movement phase: confirm the active
	unit's in-progress move (the same CONFIRM_UNIT_MOVE the "Confirm Move" button
	sends). Returns true only when there is a pending move to confirm, so Start
	falls through to the End-Phase confirm when nothing is staged."""
	if active_unit_id == "":
		return false
	if not _has_pending_unconfirmed_move(active_unit_id):
		return false
	_on_confirm_move_pressed()
	return true


func pad_menu_options() -> Array:
	"""Options for the pad action bar: [{id, label}], mirroring the mode-radio
	eligibility. Empty when the unit has no open mode decision (mode locked,
	models already staged/moved, embarked, or nothing selected)."""
	if active_unit_id == "":
		return []
	if _pad_mode_resolved():
		return []
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty() or unit.get("embarked_in", null) != null:
		return []
	# A unit that has already moved this phase — including one that just
	# arrived from reserves (ingress sets flags.moved + the until-charge
	# lock) — has no open mode decision: selecting it must not offer
	# Move / Advance / Stay Still chips whose actions the phase would
	# reject anyway.
	var unit_flags = unit.get("flags", {})
	if unit_flags.get("moved", false) or unit_flags.get("no_moves_until_charge_phase", false):
		return []
	var opts: Array = []
	if normal_radio and normal_radio.visible and not normal_radio.disabled:
		opts.append({"id": "NORMAL", "label": "Move"})
	if advance_radio and advance_radio.visible and not advance_radio.disabled:
		opts.append({"id": "ADVANCE", "label": "Advance"})
	if fall_back_radio and fall_back_radio.visible and not fall_back_radio.disabled:
		opts.append({"id": "FALL_BACK", "label": "Fall Back"})
	if stationary_radio and stationary_radio.visible and not stationary_radio.disabled:
		opts.append({"id": "REMAIN_STATIONARY", "label": "Stay Still"})
	# Moving the whole unit at once is NOT a separate menu entry: once any move
	# mode is under way (Normal, Advance, Fall Back), a D-pad press grabs every
	# model still to be moved (PadRouter._try_grab_all_remaining), so the group
	# carry composes with every mode instead of being hardwired to Normal.
	for action in _get_special_movement_actions(active_unit_id):
		var action_type := str(action.get("type", ""))
		if action_type == "":
			continue
		opts.append({
			"id": "SPECIAL:" + action_type,
			"label": str(action.get("description", action_type))
		})
	return opts


func _pad_mode_resolved() -> bool:
	"""True when the active unit's move-mode decision is no longer open:
	mode locked/completed, or models already staged/committed this move."""
	if not current_phase or not current_phase.has_method("get_active_move_data"):
		return false
	var move_data = current_phase.get_active_move_data(active_unit_id)
	if move_data.is_empty():
		return false
	if move_data.get("completed", false) or move_data.get("mode_locked", false):
		return true
	return not move_data.get("staged_moves", []).is_empty() \
		or not move_data.get("model_moves", []).is_empty()


func pad_apply_menu_choice(choice_id: String) -> void:
	"""Apply a PadActionBar choice by driving the same handlers the mouse UI
	uses (radios + Confirm Movement Mode / Fall Back dispatch)."""
	if active_unit_id == "":
		return
	if choice_id.begins_with("SPECIAL:"):
		emit_signal("move_action_requested", {
			"type": choice_id.trim_prefix("SPECIAL:"),
			"actor_unit_id": active_unit_id
		})
		return
	_pad_set_mode_radio(choice_id)
	match choice_id:
		"NORMAL":
			# Selection normally auto-dispatched BEGIN_NORMAL_MOVE already; the
			# special-action popup path skips it, so make sure a move exists.
			var move_data = current_phase.get_active_move_data(active_unit_id) \
				if current_phase and current_phase.has_method("get_active_move_data") else {}
			if move_data.is_empty():
				emit_signal("move_action_requested", {
					"type": "BEGIN_NORMAL_MOVE",
					"actor_unit_id": active_unit_id
				})
		"ADVANCE", "REMAIN_STATIONARY":
			_on_confirm_mode_pressed()
		"FALL_BACK":
			_on_fall_back_pressed()


func _pad_set_mode_radio(mode: String) -> void:
	var radio: CheckBox = null
	match mode:
		"NORMAL":
			radio = normal_radio
		"ADVANCE":
			radio = advance_radio
		"FALL_BACK":
			radio = fall_back_radio
		"REMAIN_STATIONARY":
			radio = stationary_radio
	if radio == null:
		return
	# ButtonGroup radios: pressing one programmatically releases the others.
	# `pressed` is not emitted by programmatic sets, but keep the guard for
	# parity with every other programmatic radio write in this file.
	setting_radio_programmatically = true
	radio.button_pressed = true
	setting_radio_programmatically = false


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


func _trigger_unit_animation(unit_id: String, anim_name: String) -> void:
	"""Trigger an animation on all token visuals for a unit."""
	var tl = SceneRefs.token_layer()
	if not tl:
		return
	for child in tl.get_children():
		if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id:
			if child.has_method("play_animation"):
				child.play_animation(anim_name)
			else:
				for grandchild in child.get_children():
					if grandchild.has_method("play_animation"):
						grandchild.play_animation(anim_name)

# T-094: Movement range overlay helpers
const MOVE_RANGE_OVERLAY_COLOR: Color = Color(0.3, 0.85, 0.4, 0.55)
const MOVE_RANGE_OVERLAY_WIDTH: float = 12.0  # Width in board-space px (board scale ~0.3)

func _draw_dashed_range_circle(center: Vector2, radius_px: float, label_text: String) -> void:
	# Draws a dashed circle (with optional distance label) into move_range_visual.
	# Shared by the per-model movement-reach overlays.
	if not is_instance_valid(move_range_visual) or radius_px <= 0.0:
		return
	# P1 (Steam Deck): on the pad the carried model CLAMPS exactly onto this ring
	# (MovementController._clamp_move_to_budget), so the boundary is a hard edge the
	# player slides to — draw it brighter, thicker, and lifted above board tokens so
	# it can't read as a faint suggestion or be occluded. Mouse keeps the softer
	# dashed guide, since a mouse drag can cross the ring into an invalid preview.
	var pad_carry := InputDeviceManager.is_pad_active()
	var col: Color = MOVE_RANGE_OVERLAY_COLOR
	var width: float = MOVE_RANGE_OVERLAY_WIDTH
	if pad_carry:
		col = Color(col.r, col.g, col.b, 0.9)
		width = MOVE_RANGE_OVERLAY_WIDTH * 1.4
	var total_arcs: int = 8
	var arc_length: float = TAU / float(total_arcs)
	var dash_fraction: float = 0.75
	for arc_idx in range(total_arcs):
		var arc_start: float = arc_idx * arc_length
		var arc_dash_end: float = arc_start + arc_length * dash_fraction
		var dash := Line2D.new()
		dash.name = "MoveRangeDash_%d_%d_%d" % [int(center.x), int(center.y), arc_idx]
		dash.width = width
		dash.default_color = col
		dash.begin_cap_mode = Line2D.LINE_CAP_ROUND
		dash.end_cap_mode = Line2D.LINE_CAP_ROUND
		if pad_carry:
			dash.z_index = 50  # above board tokens (z 0); below the label's 55
		var pts: int = 8
		for i in range(pts + 1):
			var theta: float = arc_start + (arc_dash_end - arc_start) * float(i) / float(pts)
			dash.add_point(center + Vector2(cos(theta), sin(theta)) * radius_px)
		move_range_visual.add_child(dash)
	if label_text != "":
		# Distance label at the top of the circle
		var range_label := Label.new()
		range_label.text = label_text
		range_label.add_theme_font_size_override("font_size", 36)
		range_label.add_theme_color_override("font_color", col)
		range_label.position = center + Vector2(-20, -(radius_px + 40))
		range_label.z_index = 55
		move_range_visual.add_child(range_label)

func _format_range_label(inches: float) -> String:
	# Whole numbers (the common case: M, or M+Advance) render without a decimal;
	# a fractional remainder left after a staged partial move keeps one decimal.
	if abs(inches - round(inches)) > 0.05:
		return "%.1f\"" % inches
	return "%d\"" % int(round(inches))

func _show_model_range_overlay(model: Dictionary, center: Vector2) -> void:
	# T-094 (revised): per-model movement-reach circle, anchored at the model's
	# pickup position. Radius is the *remaining* distance this model may move, so
	# it automatically reflects the Advance distance during an Advance, and shrinks
	# to the leftover allowance when continuing a staged move.
	if not is_instance_valid(move_range_visual) or model.is_empty():
		return
	_clear_move_range_overlay()
	var remaining: float = _get_effective_move_cap() - _get_accumulated_distance_for_model(model)
	if remaining <= 0.0:
		return
	_draw_dashed_range_circle(center, Measurement.inches_to_px(remaining), _format_range_label(remaining))

func _show_group_range_overlay() -> void:
	# Per-model reach circles for every model in a group drag (labels omitted to
	# avoid clutter when several circles overlap).
	if not is_instance_valid(move_range_visual) or selected_models.is_empty():
		return
	_clear_move_range_overlay()
	var cap: float = _get_effective_move_cap()
	for model_data in selected_models:
		var start_pos = group_drag_start_positions.get(model_data.get("model_id", ""), model_data.get("position", Vector2.ZERO))
		if start_pos is Dictionary:
			start_pos = Vector2(start_pos.get("x", 0), start_pos.get("y", 0))
		var remaining: float = cap - _get_accumulated_distance_for_model(model_data)
		if remaining <= 0.0:
			continue
		_draw_dashed_range_circle(start_pos, Measurement.inches_to_px(remaining), "")

func _clear_move_range_overlay() -> void:
	if not is_instance_valid(move_range_visual):
		return
	for child in move_range_visual.get_children():
		child.queue_free()


# T-094: engagement-range rings around enemy units during movement.
# ISS-002: the ring radius MUST use the edition-aware
# GameConstants.engagement_range_inches() (2" at 11e, 1" at 10e). A hardcoded
# 1" here previously under-drew the no-go zone at 11e, so moves were refused
# while the model still looked clear of the red circles.
const MOVE_ER_OVERLAY_COLOR: Color = Color(1.0, 0.3, 0.3, 0.45)
const MOVE_ER_OVERLAY_WIDTH: float = 6.0

func _show_er_overlay(unit_id: String) -> void:
	if not is_instance_valid(er_overlay_visual):
		return
	_clear_er_overlay()
	if not GameState:
		return
	var active_unit = GameState.get_unit(unit_id)
	var owner = int(active_unit.get("owner", 0))
	var snapshot = GameState.create_snapshot(false)
	for uid in snapshot.get("units", {}):
		var u = snapshot.units[uid]
		if int(u.get("owner", 0)) == owner:
			continue
		for em in u.get("models", []):
			if not em.get("alive", true):
				continue
			var pos_data = em.get("position")
			if pos_data == null:
				continue
			var pos: Vector2
			if pos_data is Dictionary:
				pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
			else:
				pos = pos_data
			var base_radius = Measurement.base_radius_px(em.get("base_mm", 32))
			# Engagement range is measured base-edge to base-edge, so the ring
			# marks the line the moving model's BASE may not touch.
			var ring_radius = base_radius + Measurement.inches_to_px(GameConstants.engagement_range_inches())
			var ring = Line2D.new()
			ring.width = MOVE_ER_OVERLAY_WIDTH
			ring.default_color = MOVE_ER_OVERLAY_COLOR
			ring.closed = true
			var segments: int = 32
			for i in range(segments):
				var theta = TAU * float(i) / float(segments)
				ring.add_point(pos + Vector2(cos(theta), sin(theta)) * ring_radius)
			er_overlay_visual.add_child(ring)


func _clear_er_overlay() -> void:
	if not is_instance_valid(er_overlay_visual):
		return
	for child in er_overlay_visual.get_children():
		child.queue_free()


# T-094: 2" coherency rings around the moving unit's models
const MOVE_COHERENCY_COLOR: Color = Color(0.3, 0.9, 1.0, 0.4)
const MOVE_COHERENCY_WIDTH: float = 5.0
# ISS-002: coherency distance comes from GameConstants.coherency_distance_inches().

func _show_coherency_dots(unit_id: String) -> void:
	if not is_instance_valid(coherency_dots_visual):
		return
	_clear_coherency_dots()
	var unit = GameState.get_unit(unit_id) if GameState else {}
	if unit.is_empty():
		return
	for m in unit.get("models", []):
		if not m.get("alive", true):
			continue
		var pos_data = m.get("position")
		if pos_data == null:
			continue
		var pos: Vector2
		if pos_data is Dictionary:
			pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
		else:
			pos = pos_data
		var base_radius = Measurement.base_radius_px(m.get("base_mm", 32))
		var ring_radius = base_radius + Measurement.inches_to_px(GameConstants.coherency_distance_inches())
		var ring = Line2D.new()
		ring.width = MOVE_COHERENCY_WIDTH
		ring.default_color = MOVE_COHERENCY_COLOR
		ring.closed = true
		var segments: int = 32
		for i in range(segments):
			var theta = TAU * float(i) / float(segments)
			ring.add_point(pos + Vector2(cos(theta), sin(theta)) * ring_radius)
		coherency_dots_visual.add_child(ring)


func _clear_coherency_dots() -> void:
	if not is_instance_valid(coherency_dots_visual):
		return
	for child in coherency_dots_visual.get_children():
		child.queue_free()
