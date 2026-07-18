extends PhaseControllerBase
class_name FightController

const BasePhase = preload("res://phases/BasePhase.gd")
const EngagementRangeVisualScript = preload("res://scripts/EngagementRangeVisual.gd")
const DamageFeedbackVisualScript = preload("res://scripts/DamageFeedbackVisual.gd")  # T5-V12
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")


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

# Pile-in/Consolidate/Sweeping Advance interactive mode
var pile_in_active: bool = false
var consolidate_active: bool = false
var sweeping_advance_active: bool = false
var acrobatic_escape_active: bool = false
var pile_in_unit_id: String = ""
var pile_in_dialog_ref: Node = null
var original_model_positions: Dictionary = {}  # model_id -> Vector2
var current_model_positions: Dictionary = {}   # model_id -> Vector2
var dragging_model: Node2D = null
var drag_model_id: String = ""
var drag_offset: Vector2 = Vector2.ZERO
var drag_start_pos: Vector2 = Vector2.ZERO
var locked_base_contact_models: Dictionary = {}  # T4-5: model_id -> true for models already in base contact

# Model rotation during pile-in / consolidate. Mirrors the MovementController
# pivot rules: only models on a non-circular base (or a round base >32mm with a
# flying stem on a VEHICLE) may be pivoted about their centre, and the pivot
# cost (2") counts against the model's 3" pile-in/consolidate move. Right-click
# drag rotates (as in the movement phase); the rotate_left/rotate_right
# keybinds nudge the last-touched model in 15° steps.
var original_model_rotations: Dictionary = {}  # model_id -> float (radians)
var current_model_rotations: Dictionary = {}   # model_id -> float (radians)
var pile_in_rotating_model: bool = false
var rotation_model_id: String = ""
var rotation_start_angle: float = 0.0
var rotation_model_start: float = 0.0
var pile_in_last_touched_model: String = ""  # last model clicked/rotated (for keyboard pivots)
const PILE_IN_MAX_INCHES: float = 3.0

# UI References (board_view / hud_bottom / hud_right live in PhaseControllerBase)
var movement_visual: Line2D
var range_visual: Node2D
var target_highlights: Node2D

# T5-MP1: Drag preview sync throttle
var _last_drag_preview_time: float = 0.0
const DRAG_PREVIEW_INTERVAL_MS: float = 100.0  # Send preview at most every 100ms

# Pile-in visual indicators
var pile_in_visuals: Node2D = null  # Container for all pile-in visuals
var range_circles: Dictionary = {}  # model_id -> Node2D (circle showing 3" range)
var direction_lines: Dictionary = {}  # model_id -> Line2D (to closest enemy)
var coherency_lines: Array = []  # Array of Line2D showing unit coherency
var pile_in_movement_visual: Node2D = null  # T5-V8: Enhanced arrows + distance labels

# Track current fighting unit and its owner
var current_fighter_id: String = ""
var current_fighter_owner: int = -1

# P0-58: Track active melee wound allocation overlay
# WoundAllocationOverlay (10e per-wound) or AllocationGroupOverlay (11e batch)
var active_melee_allocation_overlay = null
var processing_melee_saves_signal: bool = false

# STAGED FIGHT: the sequence dialog showing hit/wound pauses + Command Re-roll
var active_fight_sequence_dialog = null

# 11e global-step sections in the right panel (12.02 Pile In / 12.07
# Consolidate). These replace the old PileInStepDialog / ConsolidationStepDialog
# pop-ups, which covered the battlefield the player was about to move models
# across — unit-to-activate selection lives on the right-hand panel like every
# other phase. Node names are stable for windowed scenarios:
#   FightPanel/PileInStepPanel/UnitList/PileIn_<unit_id>
#   FightPanel/PileInStepPanel/EndPileInButton
#   FightPanel/ConsolidationStepPanel/UnitList/Consolidate_<unit_id>
#   FightPanel/ConsolidationStepPanel/EndConsolidationButton
var pile_in_step_panel: VBoxContainer = null
var consolidation_step_panel: VBoxContainer = null
var _pile_in_step_player: int = 0
var _consolidation_step_player: int = 0

# 12.04 fighter selection lives on the right panel too. It replaces the old
# centered FightSelectionDialog pop-up, which covered the middle of the board
# every time a player had to pick which unit fights next — every other
# unit-to-activate pick in the game happens on the right-hand panel. Node names
# are stable for windowed scenarios:
#   FightPanel/FightSelectionPanel/TurnIndicator/TurnLabel
#   FightPanel/FightSelectionPanel/SubphaseLabel
#   FightPanel/FightSelectionPanel/UnitList/Fight_<unit_id>
#   FightPanel/FightSelectionPanel/Instructions
var fight_selection_panel: VBoxContainer = null

const PILE_IN_STEP_INSTRUCTIONS := "Pick a unit to make its pile-in move (up to 3\", each model closer to its pile-in target). Piling in is optional — units you don't pick simply stay put."
const CONSOLIDATE_STEP_INSTRUCTIONS := "All fighting is resolved. Pick a unit to make its consolidation move (up to 3\"). Consolidating is optional — units you don't pick simply stay put."
const STEP_MOVE_IN_PROGRESS_INSTRUCTIONS := "Drag the unit's models on the battlefield, then Confirm Move (or Skip) in the dialog below."

# UI Elements
var unit_selector: ItemList
var attack_tree: Tree
var target_basket: ItemList
var confirm_button: Button
var clear_button: Button
var dice_log_display: RichTextLabel
var dice_roll_visual: DiceRollVisual  # T5-V1: Animated dice roll visualization
var fight_state_banner: FightPhaseStateBanner = null  # T5-V10: Fight phase state banner
var damage_feedback: DamageFeedbackVisual = null  # T5-V12: Damage visualization (floating numbers, flash)
var _phase_wounds_label: Label = null  # T-093: Running phase damage tally
var _phase_wounds_p1: int = 0  # T-093: Total wounds dealt by P1 this fight phase
var _phase_wounds_p2: int = 0  # T-093: Total wounds dealt by P2 this fight phase
var _phase_scoreboard: RichTextLabel = null  # T-093: per-unit fight scoreboard
var _phase_unit_stats: Dictionary = {}  # T-093: unit_id -> {wounds_dealt, kills_inflicted}

# Visual settings
const HIGHLIGHT_COLOR_ELIGIBLE = Color.GREEN
const HIGHLIGHT_COLOR_INELIGIBLE = Color.GRAY
const HIGHLIGHT_COLOR_SELECTED = Color.YELLOW
const HIGHLIGHT_COLOR_ACTIVE_FIGHTER = Color.ORANGE
const MOVEMENT_LINE_COLOR = Color.BLUE
const MOVEMENT_LINE_WIDTH = 3.0
# ISS-002: engagement range comes from GameConstants.engagement_range_inches()
# (edition-dependent). Do not re-declare it as a local constant.

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

	# T5-V10: Clean up fight phase state banner
	if fight_state_banner and is_instance_valid(fight_state_banner):
		fight_state_banner.queue_free()
		fight_state_banner = null

	# T5-V12: Clean up damage feedback visual
	if damage_feedback and is_instance_valid(damage_feedback):
		damage_feedback.queue_free()
		damage_feedback = null

	# Right panel cleanup
	var container = SceneRefs.hud_right_vbox()
	if container and is_instance_valid(container):
		var fight_elements = ["FightPanel", "FightScrollContainer", "FightSequence", "FightActions"]
		for element in fight_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("FightController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

func _on_ui_references_ready() -> void:
	# T5-V12: Create damage feedback visual for floating numbers + flash effects
	if board_view and not (damage_feedback and is_instance_valid(damage_feedback)):
		damage_feedback = DamageFeedbackVisualScript.new()
		damage_feedback.name = "FightDamageFeedback"
		board_view.add_child(damage_feedback)
		print("[FightController] T5-V12: DamageFeedbackVisual created and added to BoardView")

	# T5-V10: Setup fight phase state banner (anchored below HUD_Top)
	_setup_fight_state_banner()

func _setup_fight_state_banner() -> void:
	# T5-V10: Create the persistent fight phase state banner below HUD_Top
	if fight_state_banner and is_instance_valid(fight_state_banner):
		return  # Already set up

	var hud_top = SceneRefs.hud_top()
	if not hud_top:
		print("FightController: WARNING — HUD_Top not found, placing banner at top of Main")

	fight_state_banner = FightPhaseStateBanner.new()
	fight_state_banner.name = "FightPhaseStateBanner"

	# Insert after HUD_Top in the Main scene tree so it appears below the top bar
	var main_node = SceneRefs.main()
	if main_node:
		main_node.add_child(fight_state_banner)
		# Position it below HUD_Top using anchors
		fight_state_banner.anchor_left = 0.15
		fight_state_banner.anchor_right = 0.85
		fight_state_banner.anchor_top = 0.0
		fight_state_banner.anchor_bottom = 0.0
		# Offset below HUD_Top (typically ~40px)
		var top_offset = 42.0
		if hud_top and is_instance_valid(hud_top):
			top_offset = hud_top.size.y + 2.0
		fight_state_banner.offset_top = top_offset
		fight_state_banner.offset_bottom = top_offset + FightPhaseStateBanner.BANNER_HEIGHT
		print("FightController: T5-V10 — Fight phase state banner created")
	else:
		print("FightController: ERROR — Cannot find Main node for state banner")

func _create_fight_visuals() -> void:
	var board_root = SceneRefs.board_root()
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
		# Fill the scroll viewport vertically so the combat log (the only
		# vertically-expanding child) can absorb any leftover panel height.
		fight_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	title.text = "FIGHT CONTROLS"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	fight_panel.add_child(title)

	_add_fight_gold_separator(fight_panel)

	# 11e global step sections (Pile In 12.02 / Consolidate 12.07) — hidden
	# until their step is active. Picking which unit to activate happens HERE,
	# on the right panel like every other phase, not in a board-covering
	# pop-up (the old PileInStepDialog / ConsolidationStepDialog).
	pile_in_step_panel = _build_step_panel("PileInStepPanel", "EndPileInButton", _on_end_pile_in_button_pressed)
	fight_panel.add_child(pile_in_step_panel)
	consolidation_step_panel = _build_step_panel("ConsolidationStepPanel", "EndConsolidationButton", _on_end_consolidation_button_pressed)
	fight_panel.add_child(consolidation_step_panel)

	# 12.04 fighter selection section — hidden until the phase asks for a pick.
	# Replaces the centered FightSelectionDialog pop-up that covered the board.
	fight_selection_panel = _build_fight_selection_panel()
	fight_panel.add_child(fight_selection_panel)

	# Fight sequence display
	var sequence_label = Label.new()
	sequence_label.text = "FIGHT SEQUENCE"
	sequence_label.add_theme_font_size_override("font_size", 13)
	sequence_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		sequence_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	fight_panel.add_child(sequence_label)
	
	unit_selector = ItemList.new()
	unit_selector.custom_minimum_size = Vector2(230, 100)
	unit_selector.item_selected.connect(_on_unit_selected)
	_WhiteDwarfTheme.apply_to_item_list(unit_selector)
	fight_panel.add_child(unit_selector)

	_add_fight_gold_separator(fight_panel)

	# NOTE: The legacy right-panel manual attack-assignment controls — the
	# MELEE ATTACKS weapon tree, the CURRENT TARGETS basket, and the
	# Clear All / Fight! / Auto-Fight buttons — were intentionally removed.
	#
	# In 11th edition ALL attack allocation is driven by the pop-up
	# AttackAssignmentDialog (opened via the phase's attack_assignment_required
	# signal), which owns its own weapon + target lists and confirms attacks.
	# The right-panel versions were a dead parallel path: selecting a weapon in
	# the tree never dispatched SELECT_MELEE_WEAPON, so the controller's
	# `eligible_targets` was never populated — which meant clicking an enemy did
	# nothing and Auto-Fight bailed out immediately. Showing those affordances
	# only invited a broken interaction and confused players (two ways to fight,
	# one of them non-functional). The dialog flow is now the single source of
	# truth. `attack_tree`, `target_basket`, `confirm_button` and `clear_button`
	# are deliberately left null; every reference to them is null-guarded.

	# T-093: Phase wounds tally
	_phase_wounds_label = Label.new()
	_phase_wounds_label.name = "PhaseWoundsTally"
	_phase_wounds_label.text = "PHASE DAMAGE — P1: 0 | P2: 0"
	_phase_wounds_label.add_theme_font_size_override("font_size", 13)
	_phase_wounds_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		_phase_wounds_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	fight_panel.add_child(_phase_wounds_label)
	# T-093: per-unit scoreboard (RichTextLabel for color-coding)
	_phase_scoreboard = RichTextLabel.new()
	_phase_scoreboard.name = "FightPhaseScoreboard"
	_phase_scoreboard.bbcode_enabled = true
	_phase_scoreboard.fit_content = true
	_phase_scoreboard.custom_minimum_size = Vector2(230, 60)
	_phase_scoreboard.text = "[i]No fighters yet[/i]"
	fight_panel.add_child(_phase_scoreboard)
	_add_fight_gold_separator(fight_panel)

	var dice_label = Label.new()
	dice_label.text = "COMBAT LOG"
	dice_label.add_theme_font_size_override("font_size", 13)
	dice_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		dice_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	fight_panel.add_child(dice_label)
	
	# T5-V1: Animated dice roll visualization
	dice_roll_visual = DiceRollVisual.new()
	dice_roll_visual.custom_minimum_size = Vector2(230, 0)
	dice_roll_visual.visible = false  # Hidden until first roll
	fight_panel.add_child(dice_roll_visual)

	dice_log_display = RichTextLabel.new()
	dice_log_display.custom_minimum_size = Vector2(230, 100)
	dice_log_display.bbcode_enabled = true
	dice_log_display.scroll_following = true
	# Expand to fill any unused right-panel height instead of leaving dead space.
	dice_log_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fight_panel.add_child(dice_log_display)

	_add_fight_gold_separator(fight_panel)

	# Fight status display
	var status_section_label = Label.new()
	status_section_label.text = "FIGHT STATUS"
	status_section_label.add_theme_font_size_override("font_size", 13)
	status_section_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		status_section_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	fight_panel.add_child(status_section_label)
	
	# Fight sequence status (moved from top bar)
	var fight_sequence_status = Label.new()
	fight_sequence_status.text = "No active fights"
	fight_sequence_status.name = "SequenceLabel"
	fight_panel.add_child(fight_sequence_status)
	# NOTE: The per-unit "MOVEMENT ACTIONS: Pile In / Consolidate" buttons were
	# removed here. In 11e (12.02 / 12.07) pile-in and consolidate are GLOBAL
	# phase steps driven by the PileInStepPanel / ConsolidationStepPanel
	# sections above, not per-activation buttons. The old buttons were
	# permanently disabled dead code (they queried can_unit_pile_in/
	# can_unit_consolidate on the phase, which do not exist there) and
	# dispatched a 10e payload the 11e validators reject.

func _add_fight_gold_separator(parent: VBoxContainer) -> void:
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

func _build_step_panel(panel_name: String, end_button_name: String, end_handler: Callable) -> VBoxContainer:
	"""Build one (hidden) right-panel section for a global fight-phase step
	(Pile In / Consolidate). The skeleton is permanent — only the UnitList
	buttons are rebuilt per step emission — so the End button is never freed
	from inside its own pressed signal."""
	var panel = VBoxContainer.new()
	panel.name = panel_name
	panel.visible = false

	var step_title = Label.new()
	step_title.name = "StepTitle"
	step_title.add_theme_font_size_override("font_size", 13)
	step_title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		step_title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	panel.add_child(step_title)

	var instructions = Label.new()
	instructions.name = "StepInstructions"
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Bound the width so the autowrap label reports a sane minimum height
	instructions.custom_minimum_size = Vector2(230, 0)
	instructions.add_theme_font_size_override("font_size", 12)
	panel.add_child(instructions)

	var unit_list = VBoxContainer.new()
	unit_list.name = "UnitList"
	panel.add_child(unit_list)

	var end_button = Button.new()
	end_button.name = end_button_name
	end_button.pressed.connect(end_handler)
	panel.add_child(end_button)

	_add_fight_gold_separator(panel)
	return panel

func _build_fight_selection_panel() -> VBoxContainer:
	"""Build the (hidden) right-panel section for the 12.04 fighter pick.
	The skeleton is permanent — only the UnitList contents are rebuilt per
	fight_selection_required emission. Mirrors the step panels above."""
	var panel = VBoxContainer.new()
	panel.name = "FightSelectionPanel"
	panel.visible = false

	# Colored whose-turn banner (blue = P1, red = P2), same cue the old
	# pop-up led with.
	var turn_indicator = Panel.new()
	turn_indicator.name = "TurnIndicator"
	turn_indicator.custom_minimum_size = Vector2(230, 34)
	var turn_label = Label.new()
	turn_label.name = "TurnLabel"
	turn_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_label.add_theme_font_size_override("font_size", 14)
	turn_label.add_theme_color_override("font_color", Color.WHITE)
	if FactionPalettes:
		turn_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	turn_indicator.add_child(turn_label)
	panel.add_child(turn_indicator)

	var subphase_label = Label.new()
	subphase_label.name = "SubphaseLabel"
	subphase_label.add_theme_font_size_override("font_size", 13)
	panel.add_child(subphase_label)

	var unit_list = VBoxContainer.new()
	unit_list.name = "UnitList"
	panel.add_child(unit_list)

	var instructions = Label.new()
	instructions.name = "Instructions"
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Bound the width so the autowrap label reports a sane minimum height
	instructions.custom_minimum_size = Vector2(230, 0)
	instructions.add_theme_font_size_override("font_size", 12)
	instructions.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(instructions)

	_add_fight_gold_separator(panel)
	return panel

func _clear_step_unit_list(unit_list: Node) -> void:
	"""Drop the per-unit step buttons. remove_child releases the stable
	PileIn_/Consolidate_/Fight_ node names immediately (queue_free alone is
	deferred, and a same-frame repopulation would get its buttons auto-renamed)."""
	if unit_list == null or not is_instance_valid(unit_list):
		return
	for child in unit_list.get_children():
		unit_list.remove_child(child)
		child.queue_free()

func _hide_step_panels() -> void:
	if pile_in_step_panel and is_instance_valid(pile_in_step_panel):
		pile_in_step_panel.visible = false
	if consolidation_step_panel and is_instance_valid(consolidation_step_panel):
		consolidation_step_panel.visible = false
	if fight_selection_panel and is_instance_valid(fight_selection_panel):
		fight_selection_panel.visible = false

func _show_step_panel_waiting(panel: VBoxContainer, title_text: String, waiting_text: String) -> void:
	"""Multiplayer: the non-acting client sees whose half is running instead
	of an interactive unit list (the old pop-up flow showed nothing at all)."""
	if panel == null or not is_instance_valid(panel):
		return
	_hide_step_panels()
	panel.get_node("StepTitle").text = title_text
	panel.get_node("StepInstructions").text = waiting_text
	_clear_step_unit_list(panel.get_node("UnitList"))
	for btn_name in ["EndPileInButton", "EndConsolidationButton"]:
		var b = panel.get_node_or_null(btn_name)
		if b:
			b.visible = false
	panel.visible = true

func _set_step_panel_busy(panel: VBoxContainer, busy: bool) -> void:
	"""Grey the step section out while the chosen unit's interactive move is
	in progress on the battlefield (prevents double-activation / ending the
	half mid-move). Re-enabled when the move dialog closes or the phase
	re-emits the step data."""
	if panel == null or not is_instance_valid(panel):
		return
	var unit_list = panel.get_node_or_null("UnitList")
	if unit_list:
		for child in unit_list.get_children():
			if child is Button:
				child.disabled = busy
	for btn_name in ["EndPileInButton", "EndConsolidationButton"]:
		var b = panel.get_node_or_null(btn_name)
		if b:
			b.disabled = busy

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
		# T5-V12: Connect attacks_resolved for damage visualization
		if phase.has_signal("attacks_resolved") and not phase.attacks_resolved.is_connected(_on_attacks_resolved_visual):
			phase.attacks_resolved.connect(_on_attacks_resolved_visual)
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
		# 11e 12.07: global Consolidate step — player picks units to consolidate
		if phase.has_signal("consolidation_step_required") and not phase.consolidation_step_required.is_connected(_on_consolidation_step_required):
			phase.consolidation_step_required.connect(_on_consolidation_step_required)
		# 11e 12.02: global Pile In step — player picks units to pile in
		if phase.has_signal("pile_in_step_required") and not phase.pile_in_step_required.is_connected(_on_pile_in_step_required):
			phase.pile_in_step_required.connect(_on_pile_in_step_required)
		if phase.has_signal("subphase_transition") and not phase.subphase_transition.is_connected(_on_subphase_transition):
			phase.subphase_transition.connect(_on_subphase_transition)
		if phase.has_signal("epic_challenge_opportunity") and not phase.epic_challenge_opportunity.is_connected(_on_epic_challenge_opportunity):
			phase.epic_challenge_opportunity.connect(_on_epic_challenge_opportunity)
		if phase.has_signal("counter_offensive_opportunity") and not phase.counter_offensive_opportunity.is_connected(_on_counter_offensive_opportunity):
			phase.counter_offensive_opportunity.connect(_on_counter_offensive_opportunity)
		if phase.has_signal("katah_stance_required") and not phase.katah_stance_required.is_connected(_on_katah_stance_required):
			phase.katah_stance_required.connect(_on_katah_stance_required)
		if phase.has_signal("dread_foe_resolved") and not phase.dread_foe_resolved.is_connected(_on_dread_foe_resolved):
			phase.dread_foe_resolved.connect(_on_dread_foe_resolved)
		# P0-58: Connect saves_required signal for interactive melee wound allocation
		if phase.has_signal("saves_required") and not phase.saves_required.is_connected(_on_melee_saves_required):
			phase.saves_required.connect(_on_melee_saves_required)
		# Sweeping Advance signal
		if phase.has_signal("sweeping_advance_available") and not phase.sweeping_advance_available.is_connected(_on_sweeping_advance_available):
			phase.sweeping_advance_available.connect(_on_sweeping_advance_available)
		# Acrobatic Escape signal
		if phase.has_signal("acrobatic_escape_available") and not phase.acrobatic_escape_available.is_connected(_on_acrobatic_escape_available):
			phase.acrobatic_escape_available.connect(_on_acrobatic_escape_available)
		# STAGED FIGHT: open the sequence dialog when a fighter's attacks are
		# confirmed (before ROLL_DICE in the same batch), so the dialog catches
		# every dice_rolled / fight_stage_paused emission.
		if phase.has_signal("fighting_begun") and not phase.fighting_begun.is_connected(_on_fighting_begun_staged):
			phase.fighting_begun.connect(_on_fighting_begun_staged)

		print("DEBUG: FightController signals connected, setting up UI")

		# Ensure UI is set up after phase assignment
		_setup_ui_references()

		# T3-13: Check if phase has pending dialog data from before we connected signals.
		# This replaces the old fragile 0.1s timer workaround. The phase stores dialog
		# data when _emit_fight_selection_required() fires, so the controller can
		# retrieve it after connecting, eliminating the race condition.
		if phase.has_method("get_pending_fight_selection_data"):
			var pending_data = phase.get_pending_fight_selection_data()
			if not pending_data.is_empty():
				print("DEBUG: T3-13 - Retrieved pending fight selection data after signal connection")
				_on_fight_selection_required(pending_data)
			else:
				print("DEBUG: T3-13 - No pending fight selection data (phase may not have entered yet)")

		# 11e 12.02: the Pile In step starts during phase entry, before this
		# controller connects — pull the missed step data (T3-13 pattern)
		# and populate the right-panel step section from it
		if phase.has_method("get_pending_pile_in_step_data"):
			var pending_pile_in = phase.get_pending_pile_in_step_data()
			if not pending_pile_in.is_empty():
				print("DEBUG: Retrieved pending pile-in step data after signal connection")
				_on_pile_in_step_required(pending_pile_in)
		
		_refresh_fighter_list()
		
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
	_refresh_fighter_list()

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
		
		# T5-V9: Create pulsing engagement range circle (edition-aware ER).
		# ER is measured base-edge to base-edge, so include the model's own
		# base radius — a bare ER-radius circle under-draws the true reach.
		var circle = Node2D.new()
		circle.set_script(EngagementRangeVisualScript)
		circle.position = model_pos
		var er_base_radius_px = Measurement.base_radius_px(model.get("base_mm", 32))
		circle.setup_engagement_range(er_base_radius_px + Measurement.inches_to_px(GameConstants.engagement_range_inches()), Color.ORANGE)

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

			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue

				# Use shape-aware edge-to-edge engagement range check
				if Measurement.is_in_engagement_range_shape_aware(fighter_model, enemy_model):
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
		
		# T5-V9: Create pulsing target highlight indicator
		var is_eligible = (color == HIGHLIGHT_COLOR_ELIGIBLE)
		var highlight = Node2D.new()
		highlight.set_script(EngagementRangeVisualScript)
		highlight.position = pos
		highlight.setup_target_highlight(35.0, color, is_eligible)

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
	# The Fight! / Clear All buttons, the CURRENT TARGETS basket, and the per-unit
	# MOVEMENT ACTIONS (Pile In / Consolidate) buttons have all been removed —
	# attack allocation is handled by the AttackAssignmentDialog pop-up, and
	# pile-in/consolidate are global 11e phase steps driven by the right-panel
	# PileInStepPanel / ConsolidationStepPanel sections, which the step_required
	# signal handlers populate directly.
	pass

func _refresh_available_actions() -> void:
	"""Refresh available actions and update right panel controls"""
	if not current_phase or not current_phase.has_method("get_available_actions"):
		return

	print("DEBUG: FightController calling get_available_actions()")
	var available_actions = current_phase.get_available_actions()
	print("DEBUG: FightController received %d available actions" % available_actions.size())

	# Update right panel button states based on available actions
	_update_ui_state()

	# Update the right panel with fighters and weapons
	print("DEBUG: _refresh_available_actions calling _refresh_fighter_list and _refresh_weapon_tree")
	_refresh_fighter_list()
	_refresh_weapon_tree()

func _on_select_fighter_pressed(unit_id: String) -> void:
	"""Handle SELECT_FIGHTER button press"""
	print("DEBUG: SELECT_FIGHTER button pressed for unit: %s" % unit_id)
	
	# Create the action to send to the phase
	var action = {
		"type": "SELECT_FIGHTER",
		"unit_id": unit_id
	}

	# Route through NetworkIntegration: in multiplayer a direct
	# current_phase.execute_action() ran only on the clicking peer — the host
	# never validated or broadcast it, desyncing the fight sequence.
	if current_phase:
		print("DEBUG: Routing SELECT_FIGHTER action: %s" % str(action))
		var result = NetworkIntegration.route_action(action)
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

	# Route through NetworkIntegration (see _on_select_fighter_pressed).
	if current_phase:
		print("DEBUG: Routing SELECT_MELEE_WEAPON action: %s" % str(action))
		var result = NetworkIntegration.route_action(action)
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
		# display_name keeps duplicate squads (e.g. "... Alpha"/"... Beta") distinct.
		var _uname_meta = unit.get("meta", {})
		var unit_name = _uname_meta.get("display_name", _uname_meta.get("name", unit_id))
		
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

	# Keep current_fighter_owner in sync with whichever unit is now fighting.
	# This signal fires for EVERY fighter selection — including AI-selected
	# fighters, which never pass through _on_fight_selection_unit_chosen (the
	# only other place that refreshed current_fighter_owner). Without this, the
	# owner stays stale from the previous (often human) activation, so the AI's
	# own attack-assignment / pile-in / consolidate prompts fail the
	# is_ai_player(current_fighter_owner) gate and get shown to the human player.
	# (Symptom: human Orks fight, then the AI's Custodes fight and the "who do you
	# want to allocate the Custodes' attacks to" dialog pops up for the human.)
	var unit = GameState.get_unit(unit_id)
	if not unit.is_empty():
		current_fighter_owner = int(unit.get("owner", current_fighter_owner))

	# Debug logging
	print("Selected fighter: ", unit_id, " (owner player %d)" % current_fighter_owner)

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
	_refresh_fighter_list()
	_update_ui_state()

# T5-V12: Damage application visualization — floating numbers + flash effects
func _update_phase_wounds_label() -> void:
	# T-093: Refresh the running phase damage tally label.
	if _phase_wounds_label and is_instance_valid(_phase_wounds_label):
		_phase_wounds_label.text = "Phase Damage — P1: %d | P2: %d" % [_phase_wounds_p1, _phase_wounds_p2]


func _update_phase_scoreboard() -> void:
	# T-093: Per-unit scoreboard, color-coded by player.
	if not _phase_scoreboard or not is_instance_valid(_phase_scoreboard):
		return
	if _phase_unit_stats.is_empty():
		_phase_scoreboard.text = "[i]No fighters yet[/i]"
		return
	var lines: Array = []
	for uid in _phase_unit_stats:
		var stats = _phase_unit_stats[uid]
		var unit = GameState.get_unit(uid)
		var name = unit.get("meta", {}).get("name", uid)
		var owner = stats.get("owner", 0)
		var color_tag = "[color=#5070ff]" if owner == 1 else "[color=#ff6060]"
		lines.append("%s%s[/color]: %dW, %dK" % [color_tag, name, stats.get("wounds_dealt", 0), stats.get("kills_inflicted", 0)])
	_phase_scoreboard.text = "\n".join(lines)

func _on_attacks_resolved_visual(attacker_id: String, target_id: String, result: Dictionary) -> void:
	"""Parse fight resolution diffs to show floating damage numbers and flash effects on damaged models.
	Note: This signal fires BEFORE diffs are applied to GameState (signal emitted inside process_action,
	diffs applied by execute_action afterward), so GameState has pre-damage values we can use."""
	if not damage_feedback or not is_instance_valid(damage_feedback):
		print("[FightController] T5-V12: No damage_feedback visual, skipping damage visualization")
		return

	var diffs = result.get("diffs", [])
	if diffs.is_empty():
		return

	print("[FightController] T5-V12: Processing %d diffs for damage visualization" % diffs.size())

	# Pass 1: Collect wound changes and kill flags from diffs
	# Key format: "unit_id.model_index"
	var wound_changes: Dictionary = {}  # key -> {unit_id, model_idx, new_wounds}
	var kill_set: Dictionary = {}  # key -> true

	for diff in diffs:
		if diff.get("op", "") != "set":
			continue
		var path: String = diff.get("path", "")

		# Parse path format: "units.<UNIT_ID>.models.<INDEX>.<field>"
		var parts = path.split(".")
		if parts.size() < 5 or parts[0] != "units" or parts[2] != "models":
			continue

		var unit_id = parts[1]
		var model_idx = int(parts[3])
		var field = parts[4]

		# Only process diffs for the target unit of THIS assignment
		# (result contains diffs for ALL assignments; signal fires per assignment)
		if unit_id != target_id:
			continue

		var key = "%s.%d" % [unit_id, model_idx]

		if field == "alive" and diff.get("value") == false:
			kill_set[key] = true

		elif field == "current_wounds":
			var new_wounds: int = diff.get("value", 0)
			wound_changes[key] = {"unit_id": unit_id, "model_idx": model_idx, "new_wounds": new_wounds}

	# Pass 2: Play visual effects for each affected model
	for key in wound_changes:
		var info = wound_changes[key]
		var unit_id: String = info["unit_id"]
		var model_idx: int = info["model_idx"]
		var new_wounds: int = info["new_wounds"]
		var is_kill = kill_set.has(key)

		# Get model data from GameState (still has OLD values since diffs not yet applied)
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		var models = unit.get("models", [])
		if model_idx < 0 or model_idx >= models.size():
			continue
		var model = models[model_idx]

		var model_pos = _get_model_position(model)
		if model_pos == Vector2.ZERO:
			continue

		var base_mm = model.get("base_mm", 32)
		var base_px = Measurement.base_radius_px(base_mm)
		var max_wounds = model.get("wounds", 1)
		# Old wounds from GameState (pre-diff), new wounds from diff
		var old_wounds = model.get("current_wounds", max_wounds)
		var damage_dealt = max(1, old_wounds - new_wounds)

		if is_kill:
			# Model destroyed — play death animation + floating kill number
			damage_feedback.play_death_animation(model_pos, base_px)
			damage_feedback.play_floating_number(model_pos, damage_dealt, true)
			print("[FightController] T5-V12: Model killed at %s — -%d (was %d/%d)" % [str(model_pos), damage_dealt, old_wounds, max_wounds])
		else:
			# Model survived — play damage flash + floating number
			damage_feedback.play_damage_flash(model_pos, base_px, damage_dealt, max_wounds)
			damage_feedback.play_floating_number(model_pos, damage_dealt, false)
			print("[FightController] T5-V12: Model damaged at %s — -%d (%d→%d/%d)" % [str(model_pos), damage_dealt, old_wounds, new_wounds, max_wounds])

		# T-093: Accumulate phase damage tally — attacker's owner gets credit
		var attacker_unit = GameState.get_unit(attacker_id)
		var attacker_owner = attacker_unit.get("owner", 0)
		if attacker_owner == 1:
			_phase_wounds_p1 += damage_dealt
		elif attacker_owner == 2:
			_phase_wounds_p2 += damage_dealt
		# T-093: per-unit scoreboard tracking
		if not _phase_unit_stats.has(attacker_id):
			_phase_unit_stats[attacker_id] = {"wounds_dealt": 0, "kills_inflicted": 0, "owner": attacker_owner}
		_phase_unit_stats[attacker_id]["wounds_dealt"] += damage_dealt
		if is_kill:
			_phase_unit_stats[attacker_id]["kills_inflicted"] += 1
		_update_phase_wounds_label()
		_update_phase_scoreboard()

	# Flash the target unit's token nodes red for immediate visual feedback
	if not wound_changes.is_empty():
		_flash_fight_target_tokens(target_id)

	# T7-53: Check for full unit destruction → kill notification
	if not kill_set.is_empty():
		var unit = GameState.get_unit(target_id)
		if not unit.is_empty():
			var models = unit.get("models", [])
			var alive_count = 0
			for m_idx in range(models.size()):
				var model = models[m_idx]
				if model.get("alive", true):
					var key = "%s.%d" % [target_id, m_idx]
					if not kill_set.has(key):
						alive_count += 1
			if alive_count == 0:
				var unit_name = unit.get("meta", {}).get("name", target_id)
				var center_pos = _get_unit_center(unit)
				if center_pos != Vector2.ZERO:
					damage_feedback.play_kill_notification(center_pos, unit_name)
					print("[FightController] T7-53: UNIT DESTROYED — %s" % unit_name)

func _get_unit_center(unit: Dictionary) -> Vector2:
	"""T7-53: Compute average position of alive models for kill notification."""
	var models = unit.get("models", [])
	var positions: Array = []
	for model in models:
		if model.get("alive", true):
			var pos = _get_model_position(model)
			if pos != Vector2.ZERO:
				positions.append(pos)
	if positions.is_empty():
		return Vector2.ZERO
	var center = Vector2.ZERO
	for pos in positions:
		center += pos
	return center / positions.size()

func _flash_fight_target_tokens(target_unit_id: String) -> void:
	"""T5-V12: Flash the target unit's token nodes red briefly after melee damage."""
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		return

	for child in token_layer.get_children():
		if not child.has_meta("unit_id"):
			continue
		if child.get_meta("unit_id") != target_unit_id:
			continue
		# Flash red via modulate tween
		var original_modulate = child.modulate
		var tween = child.create_tween()
		tween.tween_property(child, "modulate", Color(1.5, 0.3, 0.3, 1.0), 0.1)
		tween.tween_property(child, "modulate", original_modulate, 0.3)
	print("[FightController] T5-V12: Flashed target tokens for unit %s" % target_unit_id)

func _on_dice_rolled(dice_data: Dictionary) -> void:
	# P3-117: Record roll in centralized dice history
	if DiceHistoryPanel:
		DiceHistoryPanel.record_roll(dice_data, "Fight")

	if not dice_log_display:
		return

	# T5-V1: Trigger animated dice visualization
	if dice_roll_visual:
		dice_roll_visual.show_dice_roll(dice_data)

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

	# Flush the header, then render the dice as inline d6 face icons (rounded
	# square + pips) via the shared DiceFaceIcons textures — the same faces used
	# by the shooting resolution log, the FightSequenceDialog and the animated
	# dice roller — instead of a [n, n, n] number list, so dice look consistent
	# across the whole game.
	dice_log_display.append_text(log_text)
	dice_log_display.append_text("  Rolls: ")
	if not rolls_raw.is_empty():
		var target_num = int(threshold.replace("+", "")) if threshold != "" else 0
		_append_dice_icons(dice_log_display, rolls_raw, target_num, context)
	else:
		dice_log_display.append_text("[color=gray]—[/color]")

	# Add success count
	var suffix = " → [b][color=green]%d successes[/color][/b]" % successes

	# Save roll: show failed saves (which cause wounds)
	if context == "save_roll":
		var failed = dice_data.get("failed", 0)
		if failed > 0:
			suffix += ", [color=red]%d failed (wounds)[/color]" % failed
		else:
			suffix += " [color=green](all saved!)[/color]"

	suffix += "\n"

	dice_log_display.append_text(suffix)

func _append_dice_icons(target_label: RichTextLabel, rolls: Array, threshold_num: int, context: String) -> void:
	# Render `rolls` as inline d6 face icons using the shared DiceFaceIcons
	# textures. Colour follows the standard d6 semantics: crit (gold) on a 6 for
	# hit/wound rolls, fumble (red) on a 1, pass/fail vs threshold, else neutral.
	if not target_label or rolls.is_empty():
		return
	var crit_threshold = 6 if context in ["to_hit", "hit_roll_melee", "to_wound", "wound_roll_melee"] else 7
	for i in range(rolls.size()):
		var v = int(rolls[i])
		var bg = DiceFaceIcons.color_for(v, threshold_num, threshold_num > 0, crit_threshold)
		target_label.add_image(DiceFaceIcons.get_face(v, bg), 18, 18, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		if i < rolls.size() - 1:
			target_label.append_text(" ")

func _on_fight_sequence_updated(_sequence: Array = []) -> void:
	_refresh_fighter_list()

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


# T-093: Auto-fight — assigns all melee weapons to the first engaged enemy
# unit and immediately requests CONFIRM_ATTACKS, all without opening the
# AttackAssignmentDialog. Useful for fast resolution.
func _on_auto_fight_pressed() -> void:
	if current_fighter_id == "":
		print("[FightController] Auto-Fight: no active fighter")
		return
	if eligible_targets.is_empty():
		print("[FightController] Auto-Fight: no eligible targets")
		return
	# Pick the first eligible target (highest-priority by ordering)
	var target_id: String = eligible_targets.keys()[0]
	var unit = current_phase.get_unit(current_fighter_id) if current_phase else GameState.get_unit(current_fighter_id)
	if unit.is_empty():
		return
	var assignments: Array = []
	for weapon in unit.get("meta", {}).get("weapons", []):
		if weapon.get("type", "").to_lower() != "melee":
			continue
		var weapon_id = RulesEngine.generate_weapon_id(weapon.get("name", ""), weapon.get("type", ""))
		assignments.append({
			"attacker": current_fighter_id,
			"weapon": weapon_id,
			"target": target_id,
		})
	if assignments.is_empty():
		print("[FightController] Auto-Fight: unit has no melee weapons")
		return
	if dice_log_display:
		var unit_name = unit.get("meta", {}).get("name", current_fighter_id)
		dice_log_display.append_text("[color=cyan]Auto-Fight: %s -> %s[/color]\n" % [unit_name, target_id])
	emit_signal("fight_action_requested", {
		"type": "ASSIGN_ATTACKS",
		"unit_id": current_fighter_id,
		"payload": {"assignments": assignments},
	})
	emit_signal("fight_action_requested", {
		"type": "CONFIRM_ATTACKS",
	})

# ISS-008: deliberately _input (not _unhandled_input) — interactive pile-in /
# consolidate must receive mouse events while the PileInDialog (a modal
# AcceptDialog) is open; _unhandled_input would never fire then.
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

	# Only handle target selection input if we have an active fighter and eligible targets
	if current_fighter_id == "" or eligible_targets.is_empty():
		return

	# Handle clicking on units for target selection
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var board_root = SceneRefs.board_root()
		if board_root:
			var mouse_pos = board_root.get_local_mouse_position()
			print("DEBUG: Mouse click at board position: ", mouse_pos)
			_handle_board_click(mouse_pos)

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

# 12.04 fighter selection — right-panel section handlers
func _on_fight_selection_required(data: Dictionary) -> void:
	"""Populate the right-panel fighter-selection section when the phase asks
	for a pick. Replaces the old centered FightSelectionDialog pop-up, which
	covered the middle of the board — unit-to-activate selection lives on the
	right panel like every other phase."""
	print("DEBUG: FightController._on_fight_selection_required called")
	# The Fight step's selection is starting (or a 12.08 forced fight is
	# interrupting the Consolidate step) — the global-step unit sections don't
	# apply while a fighter is being selected. They re-show when the phase
	# re-emits their step data.
	_hide_step_panels()
	print("DEBUG: Selection data: subphase=%s, player=%d, eligible=%d" % [
		data.get("current_subphase", "?"),
		data.get("selecting_player", 0),
		data.get("eligible_units", {}).size()
	])

	# T5-V10: Update the fight phase state banner
	if fight_state_banner and is_instance_valid(fight_state_banner):
		fight_state_banner.update_state(data)

	# Skip the panel for AI players — they submit SELECT_FIGHTER actions directly
	var selecting_player = data.get("selecting_player", 0)
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(selecting_player):
		print("DEBUG: AI player %d selecting — fighter-selection panel stays hidden" % selecting_player)
		return

	# Multiplayer: the section is populated on BOTH peers for visibility (like
	# the old dialog was) — the per-button gate below disables the pick for the
	# non-selecting peer.
	_populate_fight_selection_panel(data)
	print("DEBUG: Fighter-selection panel shown")

func _populate_fight_selection_panel(data: Dictionary) -> void:
	if fight_selection_panel == null or not is_instance_valid(fight_selection_panel):
		print("[FightController] WARNING: fight_selection_panel missing — right panel not built yet")
		return

	var selecting_player = int(data.get("selecting_player", 0))
	var player_color = Color.BLUE if selecting_player == 1 else Color.RED
	var turn_indicator: Panel = fight_selection_panel.get_node("TurnIndicator")
	turn_indicator.add_theme_stylebox_override("panel", _create_selection_turn_style(player_color))
	turn_indicator.get_node("TurnLabel").text = "PLAYER %d'S TURN TO SELECT" % selecting_player

	fight_selection_panel.get_node("SubphaseLabel").text = "Current: %s Subphase" % data.get("current_subphase", "?")

	var unit_list = fight_selection_panel.get_node("UnitList")
	_clear_step_unit_list(unit_list)
	# Show all units organized by subphase (same sectioning as the old dialog,
	# which the fight_dialog_* scenario helpers walk)
	_add_selection_subphase_units(unit_list, data, "FIGHTS_FIRST", data.get("fights_first_units", {}))
	_add_selection_subphase_units(unit_list, data, "REMAINING_COMBATS", data.get("remaining_units", {}))
	if data.has("fights_last_units"):
		_add_selection_subphase_units(unit_list, data, "FIGHTS_LAST", data.fights_last_units)

	fight_selection_panel.get_node("Instructions").text = _selection_instructions_text(data)
	fight_selection_panel.visible = true

func _add_selection_subphase_units(container: VBoxContainer, data: Dictionary, subphase_name: String, units_by_player: Dictionary) -> void:
	var subphase_header = Label.new()
	subphase_header.text = "=== %s ===" % subphase_name
	subphase_header.add_theme_font_size_override("font_size", 13)

	# Highlight if this is current subphase
	var is_current = subphase_name == data.get("current_subphase", "")
	if is_current:
		subphase_header.add_theme_color_override("font_color", Color.GREEN)
	else:
		subphase_header.add_theme_color_override("font_color", Color.GRAY)

	container.add_child(subphase_header)

	var units_that_fought: Array = data.get("units_that_fought", [])
	var eligible_units: Dictionary = data.get("eligible_units", {})

	# Multiplayer: the section shows on BOTH peers for visibility, but only the
	# selecting player may pick. Without this gate the other player saw enabled
	# buttons whose clicks were then rejected by the host ("Player ID
	# mismatch") — confusing dead UI.
	var is_local_players_pick = true
	if NetworkManager and NetworkManager.is_networked():
		is_local_players_pick = (NetworkManager.get_local_player() == int(data.get("selecting_player", 0)))

	# Add units for each player
	for player in ["1", "2"]:
		var player_units = units_by_player.get(player, [])
		if player_units.is_empty():
			continue

		var player_label = Label.new()
		player_label.text = "Player %s:" % player
		container.add_child(player_label)

		for unit_id in player_units:
			var has_fought = unit_id in units_that_fought
			var is_eligible = eligible_units.has(unit_id)

			var unit_button = Button.new()
			unit_button.name = "Fight_%s" % unit_id
			# Resolve through GameState's display-name helper (Alpha/Beta
			# suffixes) so same-named squads are tellable apart, matching the
			# labels used everywhere else. eligible_units only carries the
			# SELECTING player's units, so its name lookup would leave every
			# other unit rendering as a raw unit id.
			var unit_name = GameState.get_unit_display_name(unit_id)
			unit_button.text = "%s%s" % [
				unit_name,
				" (Fought)" if has_fought else ""
			]
			unit_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			unit_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

			# Style based on state
			if has_fought:
				unit_button.disabled = true
				unit_button.modulate = Color.GRAY
			elif not is_eligible:
				unit_button.disabled = true
			elif not is_local_players_pick:
				unit_button.disabled = true
				unit_button.tooltip_text = "Player %d is selecting" % int(data.get("selecting_player", 0))
			elif is_current:
				unit_button.modulate = Color.LIGHT_GREEN

			if is_eligible and not has_fought and is_local_players_pick:
				unit_button.pressed.connect(_on_fight_selection_unit_chosen.bind(unit_id))

			container.add_child(unit_button)

	container.add_child(HSeparator.new())

func _selection_instructions_text(data: Dictionary) -> String:
	"""The alternation explanation under the unit list — same wording (and
	truthfulness guards) as the old dialog's Instructions label."""
	var other_player = 2 if int(data.get("selecting_player", 0)) == 1 else 1
	var other_player_key = str(other_player)

	# Check if other player has units remaining in the CURRENT subphase
	var current_subphase = str(data.get("current_subphase", ""))
	var current_source: Dictionary = data.get("fights_first_units", {})
	if current_subphase == "REMAINING_COMBATS":
		current_source = data.get("remaining_units", {})
	elif current_subphase == "FIGHTS_LAST" and data.has("fights_last_units"):
		current_source = data.fights_last_units
	var other_player_has_units = _selection_has_unfought_units(data, current_source, other_player_key)

	if other_player_has_units:
		return "Select a unit to activate. After this unit fights, Player %d will select." % other_player
	elif current_subphase == "FIGHTS_FIRST" and _selection_has_unfought_units(data, data.get("remaining_units", {}), other_player_key):
		# The opponent HAS engaged units — just none with Fights First, so
		# they select later, in the Remaining Combats step. The old blanket
		# "Player X has no eligible units" here read as "their engaged units
		# never get to fight" and was reported as an engagement bug.
		return "Player %d has no Fights First units. Select your Fights First units in turn — Player %d will then select in Remaining Combats." % [other_player, other_player]
	else:
		return "Player %d has no eligible units. Select all remaining units in turn." % other_player

func _selection_has_unfought_units(data: Dictionary, units_by_player: Dictionary, player_key: String) -> bool:
	var units_that_fought: Array = data.get("units_that_fought", [])
	for unit_id in units_by_player.get(player_key, []):
		if unit_id not in units_that_fought:
			return true
	return false

func _create_selection_turn_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	return style

func _on_fight_selection_unit_chosen(unit_id: String) -> void:
	"""Submit SELECT_FIGHTER when a unit button is picked (single click)"""
	print("DEBUG: FightController - Fighter picked from selection panel: ", unit_id)
	# Retire the section immediately (mirrors the old dialog closing on click);
	# the phase re-emits fight_selection_required for the next pick.
	if fight_selection_panel and is_instance_valid(fight_selection_panel):
		fight_selection_panel.visible = false

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

func _on_epic_challenge_opportunity(unit_id: String, player: int) -> void:
	"""Show Epic Challenge dialog when a CHARACTER unit is selected to fight"""
	print("[FightController] Epic Challenge opportunity for unit %s (player %d)" % [unit_id, player])

	# Multiplayer: the decision belongs to `player` — only THEIR peer shows the
	# dialog. The phase runs on the host, so without this gate the host showed
	# (and could only fail to answer) the remote player's stratagem prompt.
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.is_networked() and nm.get_local_player() != player:
		print("[FightController] Epic Challenge decision belongs to remote player %d — not showing dialog here" % player)
		return

	# Skip dialog for AI players — AIPlayer handles via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("[FightController] Skipping Epic Challenge dialog for AI player %d" % player)
		return

	var dialog_script = load("res://dialogs/EpicChallengeDialog.gd")
	if not dialog_script:
		push_error("Failed to load EpicChallengeDialog.gd")
		# Decline automatically if dialog can't be loaded
		_on_epic_challenge_declined(unit_id, player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(unit_id, player)
	dialog.epic_challenge_used.connect(_on_epic_challenge_used)
	dialog.epic_challenge_declined.connect(_on_epic_challenge_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("[FightController] Epic Challenge dialog shown")

func _on_epic_challenge_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Epic Challenge"""
	print("[FightController] Epic Challenge USED for %s" % unit_id)
	var action = {
		"type": "USE_EPIC_CHALLENGE",
		"unit_id": unit_id,
		"player": player
	}
	emit_signal("fight_action_requested", action)

	if dice_log_display:
		var unit_name = current_phase.get_unit(unit_id).get("meta", {}).get("name", unit_id) if current_phase else unit_id
		dice_log_display.append_text("[color=gold]EPIC CHALLENGE used on %s — melee attacks gain [PRECISION][/color]\n" % unit_name)

func _on_epic_challenge_declined(unit_id: String, player: int) -> void:
	"""Handle player declining Epic Challenge"""
	print("[FightController] Epic Challenge DECLINED for %s" % unit_id)
	var action = {
		"type": "DECLINE_EPIC_CHALLENGE",
		"unit_id": unit_id,
		"player": player
	}
	emit_signal("fight_action_requested", action)

func _on_counter_offensive_opportunity(player: int, eligible_units: Array) -> void:
	"""Show Counter-Offensive dialog when an enemy unit has fought"""
	print("[FightController] Counter-Offensive opportunity for player %d (%d eligible units)" % [player, eligible_units.size()])

	# T7-32: Skip dialog for AI players - they submit actions via AIPlayer signal handler
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("[FightController] Skipping Counter-Offensive dialog for AI player %d" % player)
		return

	var dialog_script = load("res://dialogs/CounterOffensiveDialog.gd")
	if not dialog_script:
		push_error("Failed to load CounterOffensiveDialog.gd")
		# Decline automatically if dialog can't be loaded
		_on_counter_offensive_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(player, eligible_units)
	dialog.counter_offensive_used.connect(_on_counter_offensive_used)
	dialog.counter_offensive_declined.connect(_on_counter_offensive_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("[FightController] Counter-Offensive dialog shown")

	# MA-42: Show blocking overlay to active player
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("show_reactive_stratagem_waiting"):
		main_node.show_reactive_stratagem_waiting("Counter-Offensive")

func _on_counter_offensive_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Counter-Offensive"""
	print("[FightController] Counter-Offensive USED: player %d selects %s" % [player, unit_id])
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()

	# Store for subsequent actions in this activation
	current_fighter_id = unit_id
	current_fighter_owner = player

	var action = {
		"type": "USE_COUNTER_OFFENSIVE",
		"unit_id": unit_id,
		"player": player
	}
	emit_signal("fight_action_requested", action)

	if dice_log_display:
		var unit_name = current_phase.get_unit(unit_id).get("meta", {}).get("name", unit_id) if current_phase else unit_id
		dice_log_display.append_text("[color=orange]COUNTER-OFFENSIVE used — %s fights next![/color]\n" % unit_name)

func _on_counter_offensive_declined(player: int) -> void:
	"""Handle player declining Counter-Offensive"""
	print("[FightController] Counter-Offensive DECLINED by player %d" % player)
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
	var action = {
		"type": "DECLINE_COUNTER_OFFENSIVE",
		"player": player
	}
	emit_signal("fight_action_requested", action)

func _on_katah_stance_required(unit_id: String, player: int) -> void:
	"""Show Martial Ka'tah stance selection dialog"""
	print("[FightController] Martial Ka'tah stance selection required for %s (player %d)" % [unit_id, player])

	# Check if Master of the Stances is available for this unit
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	var master_available = ability_mgr and ability_mgr.has_master_of_the_stances(unit_id)

	# Skip dialog for AI players - auto-select "both" if Master of the Stances available, else dacatarai
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		var ai_stance = "both" if master_available else "dacatarai"
		print("[FightController] Auto-selecting Ka'tah stance '%s' for AI player %d" % [ai_stance, player])
		var action = {
			"type": "SELECT_KATAH_STANCE",
			"unit_id": unit_id,
			"stance": ai_stance,
			"player": player
		}
		emit_signal("fight_action_requested", action)
		return

	var dialog_script = load("res://dialogs/KatahStanceDialog.gd")
	if not dialog_script:
		push_error("Failed to load KatahStanceDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.name = "KatahStanceDialog"
	dialog.setup(unit_id, player, master_available)
	dialog.stance_selected.connect(_on_katah_stance_selected)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("[FightController] Ka'tah stance dialog shown for %s (master_of_stances: %s)" % [unit_id, str(master_available)])

func _on_katah_stance_selected(unit_id: String, stance: String, player: int) -> void:
	"""Submit SELECT_KATAH_STANCE action when stance selected from dialog"""
	print("[FightController] Ka'tah stance selected: %s for unit %s" % [stance, unit_id])

	var action = {
		"type": "SELECT_KATAH_STANCE",
		"unit_id": unit_id,
		"stance": stance,
		"player": player
	}
	emit_signal("fight_action_requested", action)

	if dice_log_display:
		var unit_name = current_phase.get_unit(unit_id).get("meta", {}).get("name", unit_id) if current_phase else unit_id
		var stance_display = ""
		if stance == "both":
			stance_display = "MASTER OF THE STANCES (Dacatarai + Rendax)"
		elif stance == "dacatarai":
			stance_display = "Dacatarai (Sustained Hits 1)"
		else:
			stance_display = "Rendax (Lethal Hits)"
		dice_log_display.append_text("[color=gold]MARTIAL KA'TAH: %s assumes %s stance[/color]\n" % [unit_name, stance_display])

func _on_dread_foe_resolved(unit_id: String, result: Dictionary) -> void:
	"""P1-17: Display Dread Foe mortal wounds result in dice log"""
	print("[FightController] Dread Foe resolved for %s — result: %s" % [unit_id, str(result)])

	if dice_log_display:
		var unit_name = current_phase.get_unit(unit_id).get("meta", {}).get("name", unit_id) if current_phase else unit_id
		var roll = result.get("roll", 0)
		var modified_roll = result.get("modified_roll", 0)
		var mortal_wounds = result.get("mortal_wounds", 0)
		var casualties = result.get("casualties", 0)

		var roll_text = str(roll)
		if modified_roll != roll:
			roll_text = "%d +2 (charged) = %d" % [roll, modified_roll]

		if mortal_wounds > 0:
			dice_log_display.append_text("[color=red]DREAD FOE: %s rolled %s — %d mortal wound(s)! (%d casualt(y/ies))[/color]\n" % [
				unit_name, roll_text, mortal_wounds, casualties
			])
		else:
			dice_log_display.append_text("[color=gray]DREAD FOE: %s rolled %s — no effect (needs 4+)[/color]\n" % [
				unit_name, roll_text
			])

func _on_pile_in_required(unit_id: String, max_distance: float) -> void:
	"""Show pile-in dialog and enable interactive movement"""
	# Skip dialog for AI players - they submit PILE_IN actions directly
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(current_fighter_owner):
		print("[FightController] Skipping pile-in dialog for AI player %d" % current_fighter_owner)
		return

	var dialog_script = load("res://dialogs/PileInDialog.gd")
	if not dialog_script:
		push_error("Failed to load PileInDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.name = "PileInDialog"
	dialog.setup(unit_id, max_distance, current_phase, self)  # Pass controller reference
	dialog.pile_in_confirmed.connect(_on_pile_in_confirmed.bind(unit_id))
	dialog.pile_in_skipped.connect(_on_pile_in_skipped.bind(unit_id))
	dialog.tree_exiting.connect(_on_pile_in_dialog_closed)
	get_tree().root.add_child(dialog)
	# Dock to the bottom of the screen so it doesn't cover the battlefield the
	# player is dragging models across.
	DialogUtils.popup_at_bottom(dialog, DialogConstants.SMALL)

	# Enable pile-in mode
	_enable_pile_in_mode(unit_id, dialog)

func _convert_fight_move_payload(unit_id: String, payload: Dictionary) -> Dictionary:
	"""Convert tracking keys ("m1" / "char_unit:m1") to the index form FightPhase
	expects ("0" for the chosen unit's models, "char_unit:0" for an attached
	character's — 19.03: one Attached-unit move covers both)."""
	var converted = {}
	if not current_phase:
		return converted
	for key in payload:
		var route = _pile_in_split_key(str(key))
		# Keys always carry the chosen unit's models unprefixed; when consolidate
		# mode re-enters with a different pile_in_unit_id fall back to unit_id.
		var route_unit_id = route.unit_id if route.unit_id != "" else unit_id
		var models = current_phase.get_unit(route_unit_id).get("models", [])
		for i in range(models.size()):
			if models[i].get("id", "") == route.model_id:
				var out_key = str(i) if route_unit_id == unit_id else "%s:%d" % [route_unit_id, i]
				converted[out_key] = payload[key]
				print("[FightController] Converted ", key, " to ", out_key)
				break
	return converted

func _on_pile_in_confirmed(movements: Dictionary, unit_id: String) -> void:
	"""Submit PILE_IN action with movements"""
	print("[FightController] Pile-in confirmed with movements: ", movements)

	# Convert model IDs from "m1" format to array indices "0" format for FightPhase
	# (attached characters' models keep their "unit:index" prefix)
	var converted_movements = _convert_fight_move_payload(unit_id, movements)
	var converted_rotations = _convert_fight_move_payload(unit_id, get_pile_in_rotations())

	print("[FightController] Converted movements: ", converted_movements, " rotations: ", converted_rotations)

	# current_fighter_owner can be stale (-1) on re-request paths — the
	# unit's owner is always the right submitting player for PILE_IN
	var pile_in_player = current_fighter_owner
	if pile_in_player < 0 and current_phase:
		pile_in_player = int(current_phase.get_unit(unit_id).get("owner", GameState.get_active_player()))

	var action = {
		"type": "PILE_IN",
		"unit_id": unit_id,
		"movements": converted_movements,
		"rotations": converted_rotations,
		"player": pile_in_player
	}
	emit_signal("fight_action_requested", action)

func _on_pile_in_skipped(unit_id: String) -> void:
	"""Submit PILE_IN action with no movements"""
	_on_pile_in_confirmed({}, unit_id)

func _on_attack_assignment_required(unit_id: String, targets: Dictionary) -> void:
	"""Show attack assignment dialog"""
	print("[FightController] Attack assignment required for ", unit_id)
	print("[FightController] Eligible targets: ", targets.keys())

	# Skip dialog for AI players - they submit ASSIGN_ATTACKS actions directly
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(current_fighter_owner):
		print("[FightController] Skipping dialog for AI player %d" % current_fighter_owner)
		return

	# Wait for previous dialog to close
	await get_tree().create_timer(0.3).timeout

	print("[FightController] Loading AttackAssignmentDialog...")
	var dialog_script = load("res://dialogs/AttackAssignmentDialog.gd")
	if not dialog_script:
		push_error("Failed to load AttackAssignmentDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.name = "AttackAssignmentDialog"
	print("[FightController] Setting up dialog...")
	dialog.setup(unit_id, targets, current_phase)
	dialog.attacks_confirmed.connect(_on_attacks_confirmed)
	dialog.skip_fight_requested.connect(_on_attack_dialog_skip_requested)
	get_tree().root.add_child(dialog)
	print("[FightController] Showing attack assignment dialog...")
	DialogUtils.popup_at_bottom(dialog)

func _on_attack_dialog_skip_requested(unit_id: String) -> void:
	"""Escape hatch from an AttackAssignmentDialog with no eligible targets:
	end the unit's activation via SKIP_UNIT so the fight sequence advances
	instead of dead-ending (the phase normally auto-ends such activations
	before the dialog is requested — this covers any path that still got here)."""
	print("[FightController] Attack dialog skip requested for %s (no eligible targets)" % unit_id)
	var skip_player = current_fighter_owner
	if skip_player < 0 and current_phase:
		skip_player = int(current_phase.get_unit(unit_id).get("owner", GameState.get_active_player()))
	emit_signal("fight_action_requested", {
		"type": "SKIP_UNIT",
		"unit_id": unit_id,
		"player": skip_player
	})

func _on_attacks_confirmed(assignments: Array) -> void:
	"""Submit attack assignments and trigger resolution via a single batched action.
	T3-12: Previously sent individual actions with fixed 50ms/100ms delays between them,
	which caused race conditions in multiplayer when network latency exceeded the delays.
	Now bundles all sub-actions into a single BATCH_FIGHT_ACTIONS that is processed atomically."""
	print("[FightController] Attacks confirmed, processing %d assignments" % assignments.size())

	# Build all sub-actions for the batch
	var sub_actions: Array = []

	# 1. ASSIGN_ATTACKS for each weapon assignment
	for assignment in assignments:
		var assign_action = {
			"type": "ASSIGN_ATTACKS",
			"unit_id": assignment.get("attacker", ""),
			"target_id": assignment.get("target", ""),
			"weapon_id": assignment.get("weapon", ""),
			"attacking_models": assignment.get("models", []),
			"player": current_fighter_owner
		}
		print("[FightController] Batching ASSIGN_ATTACKS: ", assign_action)
		sub_actions.append(assign_action)

	# 2. CONFIRM_AND_RESOLVE_ATTACKS
	sub_actions.append({
		"type": "CONFIRM_AND_RESOLVE_ATTACKS",
		"player": current_fighter_owner
	})

	# 3. ROLL_DICE
	sub_actions.append({
		"type": "ROLL_DICE",
		"player": current_fighter_owner
	})

	# Send as a single atomic action — no delays needed
	var batch_action = {
		"type": "BATCH_FIGHT_ACTIONS",
		"sub_actions": sub_actions,
		"player": current_fighter_owner
	}
	print("[FightController] Sending BATCH_FIGHT_ACTIONS with %d sub-actions" % sub_actions.size())
	emit_signal("fight_action_requested", batch_action)

# =============================================================================
# STAGED FIGHT: sequence dialog (hit pause / wound pause / Command Re-roll)
# =============================================================================

func _on_fighting_begun_staged(unit_id: String) -> void:
	# The staged sequence only runs in non-networked play for human attackers —
	# mirror FightPhase._should_stage_fight so we never open a dialog that will
	# get no pause events.
	if NetworkManager.is_networked():
		return
	var fighter_owner = GameState.get_unit(unit_id).get("owner", -1)
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.get("enabled") and ai_player_node.is_ai_player(fighter_owner):
		return

	# Replace any dialog left over from a previous activation.
	if active_fight_sequence_dialog != null and is_instance_valid(active_fight_sequence_dialog):
		active_fight_sequence_dialog.queue_free()
		active_fight_sequence_dialog = null

	var dialog_script = load("res://dialogs/FightSequenceDialog.gd")
	if not dialog_script:
		push_error("FightController: Failed to load FightSequenceDialog.gd")
		return
	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	var fighter_name = GameState.get_unit(unit_id).get("meta", {}).get("name", unit_id)
	# Add to the tree FIRST (_ready builds the UI nodes), THEN setup() — which
	# connects the phase signals. Both happen during CONFIRM processing, before
	# ROLL_DICE runs in the same batch, so no dice/pause event is missed.
	get_tree().root.add_child(dialog)
	dialog.setup(current_phase, fighter_name)
	dialog.staged_continue_requested.connect(_on_fight_staged_continue_requested)
	dialog.staged_reroll_requested.connect(_on_fight_staged_reroll_requested)
	DialogUtils.popup_at_bottom(dialog)
	active_fight_sequence_dialog = dialog
	print("[FightController] FightSequenceDialog opened for %s" % fighter_name)

func _on_fight_staged_continue_requested(next_step: String) -> void:
	var action_type = "CONTINUE_TO_WOUNDS" if next_step == "wounds" else "CONTINUE_TO_SAVES"
	print("[FightController] Staged continue: %s" % action_type)
	emit_signal("fight_action_requested", {"type": action_type})

func _on_fight_staged_reroll_requested(stage: String, die_index: int) -> void:
	print("[FightController] Staged Command Re-roll: %s die %d" % [stage, die_index])
	emit_signal("fight_action_requested", {
		"type": "USE_FIGHT_REROLL",
		"payload": {"stage": stage, "die_index": die_index}
	})

func _on_consolidate_required(unit_id: String, max_distance: float) -> void:
	"""Show consolidate dialog and enable interactive movement"""
	# The Consolidate move is a drag-on-the-battlefield interaction, so clear any
	# leftover board-covering fight dialogs (the staged FightSequenceDialog lingers
	# on its "Close" summary; a stray AttackAssignmentDialog can survive too) before
	# opening the bottom-docked ConsolidateDialog — otherwise the player can't see
	# the models they're being asked to move.
	_dismiss_blocking_fight_dialogs()

	# Skip dialog for AI players - they submit CONSOLIDATE actions directly
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(current_fighter_owner):
		print("[FightController] Skipping consolidate dialog for AI player %d" % current_fighter_owner)
		return

	var dialog_script = load("res://dialogs/ConsolidateDialog.gd")
	if not dialog_script:
		push_error("Failed to load ConsolidateDialog.gd")
		return

	# A just-freed predecessor still holds the node name for a frame (11e
	# global step opens dialogs back-to-back) — rename it out of the way so
	# the new dialog keeps the stable scenario-addressable name.
	var stale = get_tree().root.get_node_or_null("ConsolidateDialog")
	if stale != null:
		stale.name = "ConsolidateDialogStale"
		if not stale.is_queued_for_deletion():
			stale.queue_free()

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.name = "ConsolidateDialog"
	dialog.setup(unit_id, max_distance, current_phase, self)  # Pass controller reference
	dialog.consolidate_confirmed.connect(_on_consolidate_confirmed.bind(unit_id))
	dialog.consolidate_skipped.connect(_on_consolidate_skipped.bind(unit_id))
	dialog.tree_exiting.connect(_on_consolidate_dialog_closed)
	get_tree().root.add_child(dialog)
	# Dock to the bottom of the screen so it doesn't cover the battlefield the
	# player is dragging models across (same treatment as the Pile In dialog).
	DialogUtils.popup_at_bottom(dialog, DialogConstants.SMALL)

	# Enable consolidate mode (uses same system as pile-in)
	_enable_consolidate_mode(unit_id, dialog)

func _on_consolidate_confirmed(movements: Dictionary, unit_id: String) -> void:
	"""Submit CONSOLIDATE action with movements"""
	print("[FightController] Consolidate confirmed with movements: ", movements)

	# Convert model IDs from "m1" format to array indices "0" format for FightPhase
	# (attached characters' models keep their "unit:index" prefix)
	var converted_movements = _convert_fight_move_payload(unit_id, movements)
	var converted_rotations = _convert_fight_move_payload(unit_id, get_pile_in_rotations())

	print("[FightController] Converted movements: ", converted_movements, " rotations: ", converted_rotations)

	# current_fighter_owner can be stale (-1) on re-request paths — the
	# unit's owner is always the right submitting player for CONSOLIDATE
	var action_player = current_fighter_owner
	if action_player < 0 and current_phase:
		action_player = int(current_phase.get_unit(unit_id).get("owner", GameState.get_active_player()))

	var action = {
		"type": "CONSOLIDATE",
		"unit_id": unit_id,
		"movements": converted_movements,
		"rotations": converted_rotations,
		"player": action_player
	}
	emit_signal("fight_action_requested", action)

	# Clear tracking after activation complete
	current_fighter_id = ""
	current_fighter_owner = -1

func _on_consolidate_skipped(unit_id: String) -> void:
	"""Submit CONSOLIDATE action with no movements"""
	_on_consolidate_confirmed({}, unit_id)

# ============================================================================
# 11e 12.02: GLOBAL PILE IN STEP UI
# ============================================================================

func _on_pile_in_step_required(data: Dictionary) -> void:
	"""Populate the right-panel Pile In-step section for the piling-in player.
	The fight phase opens here at 11e: each player in turn piles in the
	eligible units they choose (optional per unit) or ends their half. Unit
	selection lives on the right panel like every other phase — the old
	board-covering PileInStepDialog pop-up is gone."""
	var piling_in_player = data.get("piling_in_player", 0)
	print("[FightController] Pile In step: player %d, %d eligible unit(s)" % [
		piling_in_player, data.get("eligible_units", {}).size()])

	# AI players submit PILE_IN/END_PILE_IN from get_available_actions
	# directly — no step panel for them
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(piling_in_player):
		print("[FightController] AI player %d piling in — step panel hidden" % piling_in_player)
		_hide_step_panels()
		return

	# Multiplayer: only the piling-in player's client gets the unit list
	if NetworkManager.is_networked() and NetworkManager.get_local_player() != piling_in_player:
		print("[FightController] Not local player's pile-in half — showing waiting note")
		_show_step_panel_waiting(pile_in_step_panel,
			"PILE IN STEP — PLAYER %d" % piling_in_player,
			"Waiting for Player %d to finish their pile-in moves..." % piling_in_player)
		return

	_populate_pile_in_step_panel(data)

func _populate_pile_in_step_panel(data: Dictionary) -> void:
	if pile_in_step_panel == null or not is_instance_valid(pile_in_step_panel):
		print("[FightController] WARNING: pile_in_step_panel missing — right panel not built yet")
		return
	var player = data.get("piling_in_player", 0)
	_pile_in_step_player = player
	if consolidation_step_panel and is_instance_valid(consolidation_step_panel):
		consolidation_step_panel.visible = false

	pile_in_step_panel.get_node("StepTitle").text = "PILE IN STEP — PLAYER %d" % player
	pile_in_step_panel.get_node("StepInstructions").text = PILE_IN_STEP_INSTRUCTIONS

	var unit_list = pile_in_step_panel.get_node("UnitList")
	_clear_step_unit_list(unit_list)
	var eligible: Dictionary = data.get("eligible_units", {})
	for unit_id in eligible:
		var info = eligible[unit_id]
		var engaged: bool = info.get("engaged", false)
		var unit_button = Button.new()
		unit_button.name = "PileIn_%s" % unit_id
		unit_button.text = "%s  %s" % [info.get("name", unit_id), "[Engaged]" if engaged else "[Charged]"]
		unit_button.tooltip_text = "Engaged — every engaged enemy is a pile-in target" if engaged \
			else "Charged this turn — pick enemy units within 5\" as targets"
		unit_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		unit_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		unit_button.pressed.connect(_on_pile_in_step_unit_chosen.bind(unit_id))
		unit_list.add_child(unit_button)

	var end_button = pile_in_step_panel.get_node("EndPileInButton")
	end_button.text = "End Pile In (Player %d)" % player
	end_button.visible = true
	end_button.disabled = false
	pile_in_step_panel.visible = true

func _on_pile_in_step_unit_chosen(unit_id: String) -> void:
	"""Open the PileInDialog + interactive movement for the chosen unit"""
	var unit = GameState.get_unit(unit_id)
	# The pile-in confirm path reads these for action.player / AI checks
	current_fighter_id = unit_id
	current_fighter_owner = int(unit.get("owner", GameState.get_active_player()))
	# Grey the section out while the move is made on the battlefield; the
	# phase re-emits pile_in_step_required (repopulating the section) once
	# the move is confirmed or skipped.
	_set_step_panel_busy(pile_in_step_panel, true)
	if pile_in_step_panel and is_instance_valid(pile_in_step_panel):
		pile_in_step_panel.get_node("StepInstructions").text = STEP_MOVE_IN_PROGRESS_INSTRUCTIONS
	_on_pile_in_required(unit_id, 3.0)

func _on_end_pile_in_button_pressed() -> void:
	_on_end_pile_in(_pile_in_step_player)

func _on_end_pile_in(player: int) -> void:
	"""Current player passes — their pile-in half is over"""
	print("[FightController] Player %d ends their pile-in half" % player)
	var action = {
		"type": "END_PILE_IN",
		"player": player
	}
	emit_signal("fight_action_requested", action)

# ============================================================================
# 11e 12.07: GLOBAL CONSOLIDATE STEP UI
# ============================================================================

func _on_consolidation_step_required(data: Dictionary) -> void:
	"""Populate the right-panel Consolidate-step section for the consolidating
	player. After all fighting, each player in turn consolidates the eligible
	units they choose (optional per unit at 11e) or ends their half. Unit
	selection lives on the right panel like every other phase — the old
	board-covering ConsolidationStepDialog pop-up is gone."""
	var consolidating_player = data.get("consolidating_player", 0)
	print("[FightController] Consolidation step: player %d, %d eligible unit(s)" % [
		consolidating_player, data.get("eligible_units", {}).size()])

	# All fighting is resolved once the global Consolidate step opens, so tear
	# down any board-covering fight dialogs left over from the last activation
	# (staged FightSequenceDialog on its "Close" summary, orphaned
	# AttackAssignmentDialog). They otherwise hide the battlefield the player
	# consolidates across.
	_dismiss_blocking_fight_dialogs()

	# AI players submit CONSOLIDATE/END_CONSOLIDATION from
	# get_available_actions directly — no step panel for them
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(consolidating_player):
		print("[FightController] AI player %d consolidating — step panel hidden" % consolidating_player)
		_hide_step_panels()
		return

	# Multiplayer: only the consolidating player's client gets the unit list
	if NetworkManager.is_networked() and NetworkManager.get_local_player() != consolidating_player:
		print("[FightController] Not local player's consolidation half — showing waiting note")
		_show_step_panel_waiting(consolidation_step_panel,
			"CONSOLIDATE STEP — PLAYER %d" % consolidating_player,
			"Waiting for Player %d to finish their consolidation moves..." % consolidating_player)
		return

	_populate_consolidation_step_panel(data)

func _populate_consolidation_step_panel(data: Dictionary) -> void:
	if consolidation_step_panel == null or not is_instance_valid(consolidation_step_panel):
		print("[FightController] WARNING: consolidation_step_panel missing — right panel not built yet")
		return
	var player = data.get("consolidating_player", 0)
	_consolidation_step_player = player
	if pile_in_step_panel and is_instance_valid(pile_in_step_panel):
		pile_in_step_panel.visible = false

	consolidation_step_panel.get_node("StepTitle").text = "CONSOLIDATE STEP — PLAYER %d" % player
	consolidation_step_panel.get_node("StepInstructions").text = CONSOLIDATE_STEP_INSTRUCTIONS

	var unit_list = consolidation_step_panel.get_node("UnitList")
	_clear_step_unit_list(unit_list)
	var eligible: Dictionary = data.get("eligible_units", {})
	for unit_id in eligible:
		var info = eligible[unit_id]
		var mode = str(info.get("mode", ""))
		var mode_tag := ""
		var mode_tooltip := ""
		match mode:
			"ongoing":
				mode_tag = "[Ongoing]"
				mode_tooltip = "Ongoing — engaged: move closer to the enemy"
			"engaging":
				mode_tag = "[Engaging]"
				mode_tooltip = "Engaging — enemy within 3\": may move into engagement"
			"objective":
				mode_tag = "[Objective]"
				mode_tooltip = "Objective within 3\": may move onto it"
			_:
				mode_tag = "[No move]"
				mode_tooltip = "No move possible from here"
		var unit_button = Button.new()
		unit_button.name = "Consolidate_%s" % unit_id
		unit_button.text = "%s  %s" % [info.get("name", unit_id), mode_tag]
		unit_button.tooltip_text = mode_tooltip
		unit_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		unit_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		unit_button.pressed.connect(_on_consolidation_unit_chosen.bind(unit_id))
		unit_list.add_child(unit_button)

	var end_button = consolidation_step_panel.get_node("EndConsolidationButton")
	end_button.text = "End Consolidation (Player %d)" % player
	end_button.visible = true
	end_button.disabled = false
	consolidation_step_panel.visible = true

func _on_consolidation_unit_chosen(unit_id: String) -> void:
	"""Open the ConsolidateDialog + interactive movement for the chosen unit"""
	var unit = GameState.get_unit(unit_id)
	# The consolidate confirm path reads these for action.player / AI checks
	current_fighter_id = unit_id
	current_fighter_owner = int(unit.get("owner", GameState.get_active_player()))
	# Grey the section out while the move is made on the battlefield; the
	# phase re-emits consolidation_step_required (repopulating the section)
	# once the move is confirmed or skipped.
	_set_step_panel_busy(consolidation_step_panel, true)
	if consolidation_step_panel and is_instance_valid(consolidation_step_panel):
		consolidation_step_panel.get_node("StepInstructions").text = STEP_MOVE_IN_PROGRESS_INSTRUCTIONS
	var dist = 3.0
	if current_phase and current_phase.has_method("_get_consolidation_distance"):
		dist = current_phase._get_consolidation_distance(unit_id)
	_on_consolidate_required(unit_id, dist)

func _on_end_consolidation_button_pressed() -> void:
	_on_end_consolidation(_consolidation_step_player)

func _on_end_consolidation(player: int) -> void:
	"""Current player passes — their consolidation half is over"""
	print("[FightController] Player %d ends their consolidation half" % player)
	var action = {
		"type": "END_CONSOLIDATION",
		"player": player
	}
	emit_signal("fight_action_requested", action)

func _dismiss_blocking_fight_dialogs() -> void:
	"""Free the centered, board-covering fight-resolution dialogs so the
	Consolidate step (an interactive drag on the battlefield) isn't buried under
	them. The staged FightSequenceDialog stays open on its "Close" summary after
	the final activation, and a stray AttackAssignmentDialog can linger too — both
	sit centered over the board. This is only ever called once all fighting is
	resolved (the Consolidate step / consolidate dialogs), so nothing is
	interrupted; the combat log they displayed remains available in the right
	panel's COMBAT LOG."""
	# Staged melee resolution dialog — clear the tracked ref and, defensively,
	# any node still parked under the stable "FightSequenceDialog" name (the ref
	# can go stale if the dialog was closed/reopened).
	if active_fight_sequence_dialog != null and is_instance_valid(active_fight_sequence_dialog):
		active_fight_sequence_dialog.queue_free()
	active_fight_sequence_dialog = null
	var seq_dialog = get_tree().root.get_node_or_null("FightSequenceDialog")
	if seq_dialog != null and is_instance_valid(seq_dialog):
		# Release the stable name immediately (queue_free is deferred) so it can't
		# collide with a future dialog claiming the same node name this frame.
		seq_dialog.name = "StaleFightSequenceDialog"
		seq_dialog.queue_free()

	# Any orphaned attack-assignment picker from the final activation.
	var attack_dialog = get_tree().root.get_node_or_null("AttackAssignmentDialog")
	if attack_dialog != null and is_instance_valid(attack_dialog):
		attack_dialog.name = "StaleAttackAssignmentDialog"
		attack_dialog.queue_free()
		print("[FightController] Dismissed leftover AttackAssignmentDialog for Consolidate step")

func _on_subphase_transition(from_subphase: String, to_subphase: String) -> void:
	"""Show notification when transitioning between subphases"""
	# A step boundary always retires the current global-step section; the
	# PILE_IN / CONSOLIDATE targets repopulate via their step_required
	# emissions, which follow the transition signal.
	_hide_step_panels()
	if dice_log_display:
		dice_log_display.append_text("\n[color=yellow]=== %s Complete ===[/color]\n" % from_subphase)
		dice_log_display.append_text("[color=yellow]Starting %s...[/color]\n\n" % to_subphase)

	# T5-V10: Animate subphase transition on the state banner
	if fight_state_banner and is_instance_valid(fight_state_banner):
		fight_state_banner.show_subphase_transition(from_subphase, to_subphase)

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

# ============================================================================
# ATTACHED-UNIT (19.03) KEY SPACE FOR PILE-IN / CONSOLIDATE
# ============================================================================
# The piling-in unit and its attached characters move as ONE Attached unit.
# Position/rotation tracking keys: the chosen unit's own models keep their
# raw model id ("m1"); an attached character's models are keyed
# "<char_unit_id>:m1" (mirrors the movement phase's unit:model convention
# and the FightPhase payload format).

func _pile_in_group_unit_ids() -> Array:
	"""The piling-in unit plus its attached character units."""
	var out: Array = [pile_in_unit_id]
	if current_phase and pile_in_unit_id != "":
		var unit = current_phase.get_unit(pile_in_unit_id)
		for char_id in unit.get("attachment_data", {}).get("attached_characters", []):
			out.append(str(char_id))
	return out

func _pile_in_model_key(unit_id: String, model_id: String) -> String:
	if unit_id == pile_in_unit_id:
		return model_id
	return "%s:%s" % [unit_id, model_id]

func _pile_in_split_key(key: String) -> Dictionary:
	"""{unit_id, model_id} for a tracking key (plain or 'unit:model')."""
	var sep := key.find(":")
	if sep < 0:
		return {"unit_id": pile_in_unit_id, "model_id": key}
	return {"unit_id": key.substr(0, sep), "model_id": key.substr(sep + 1)}

func _enable_pile_in_mode(unit_id: String, dialog: Node) -> void:
	"""Enable interactive pile-in mode for the unit (and its attached characters)"""
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
	original_model_rotations.clear()
	current_model_rotations.clear()
	locked_base_contact_models.clear()
	pile_in_last_touched_model = ""

	# 19.03: the attached characters' models pile in / consolidate as part of
	# this unit — seed them too so the player can drag every model of the
	# Attached unit in the one move. Sweeping Advance / Acrobatic Escape reuse
	# this mode but their submit paths stay single-unit, so they keep the
	# chosen unit's own models only.
	var seed_ids = _pile_in_group_unit_ids() if not (sweeping_advance_active or acrobatic_escape_active) else [unit_id]
	for group_unit_id in seed_ids:
		var group_unit = current_phase.get_unit(group_unit_id)
		if group_unit.is_empty():
			continue
		var models = group_unit.get("models", [])
		for i in range(models.size()):
			var model = models[i]
			var pos_data = model.get("position", {})
			if pos_data == null:
				continue
			var pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
			# Use the model's actual ID (e.g., "m1", "m2") not the array index
			var model_id = model.get("id", "m%d" % (i+1))
			var key = _pile_in_model_key(group_unit_id, model_id)
			original_model_positions[key] = pos
			current_model_positions[key] = pos
			# Seed rotation state so pivots measure against the model's starting facing
			var rot = float(model.get("rotation", 0.0))
			original_model_rotations[key] = rot
			current_model_rotations[key] = rot
			print("[FightController] Stored position for model ", key, " at ", pos)

	# T4-5: Detect models already in base contact with an enemy and lock them
	_detect_locked_base_contact_models()

	# Create visual indicators
	_create_pile_in_visuals()

	print("[FightController] Pile-in mode enabled for ", unit_id)
	if not locked_base_contact_models.is_empty():
		print("[FightController] T4-5: %d model(s) locked (already in base contact)" % locked_base_contact_models.size())

func _detect_locked_base_contact_models() -> void:
	"""T4-5: Detect models already in base-to-base contact with an enemy.
	Per 10e rules, models already in base contact are not moved during pile-in/consolidation.
	Covers the piling-in unit AND its attached characters (19.03)."""
	if not current_phase:
		return

	var all_units = current_phase.game_state_snapshot.get("units", {})
	const B2B_TOLERANCE: float = 0.1  # Match BASE_CONTACT_TOLERANCE_INCHES (was 0.25 — too generous)

	for group_unit_id in _pile_in_group_unit_ids():
		var group_unit = current_phase.get_unit(group_unit_id)
		if group_unit.is_empty():
			continue
		var models = group_unit.get("models", [])
		var unit_owner = group_unit.get("owner", 0)

		for i in range(models.size()):
			var model = models[i]
			if not model.get("alive", true):
				continue

			var model_id = model.get("id", "m%d" % (i + 1))
			var key = _pile_in_model_key(group_unit_id, model_id)
			var pos_data = model.get("position", {})
			if pos_data == null:
				continue

			# Check distance to all enemy models
			for other_unit_id in all_units:
				var other_unit = all_units[other_unit_id]
				if other_unit.get("owner", 0) == unit_owner:
					continue  # Skip friendly units

				var enemy_models = other_unit.get("models", [])
				for enemy_model in enemy_models:
					if not enemy_model.get("alive", true):
						continue

					var distance = Measurement.model_to_model_distance_inches(model, enemy_model)
					if distance <= B2B_TOLERANCE:
						locked_base_contact_models[key] = true
						print("[FightController] T4-5: Model %s is in base contact with enemy (%.2f\") — locked" % [key, distance])
						break  # No need to check more enemies for this model

				if key in locked_base_contact_models:
					break  # Already found base contact, skip remaining enemy units

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
	original_model_rotations.clear()
	current_model_rotations.clear()
	locked_base_contact_models.clear()
	dragging_model = null
	drag_model_id = ""
	pile_in_rotating_model = false
	rotation_model_id = ""
	pile_in_last_touched_model = ""

	# Clean up visual indicators
	_clear_pile_in_visuals()

	# Re-enable the global-step sections (covers the move dialog being closed
	# without confirming — the unit hasn't spent its step move, so it can be
	# picked again). On the confirm path the phase has already repopulated the
	# section by the time the dialog frees, so this is a harmless no-op.
	_set_step_panel_busy(pile_in_step_panel, false)
	_set_step_panel_busy(consolidation_step_panel, false)
	if pile_in_step_panel and is_instance_valid(pile_in_step_panel) and pile_in_step_panel.visible \
			and pile_in_step_panel.get_node("StepInstructions").text == STEP_MOVE_IN_PROGRESS_INSTRUCTIONS:
		pile_in_step_panel.get_node("StepInstructions").text = PILE_IN_STEP_INSTRUCTIONS
	if consolidation_step_panel and is_instance_valid(consolidation_step_panel) and consolidation_step_panel.visible \
			and consolidation_step_panel.get_node("StepInstructions").text == STEP_MOVE_IN_PROGRESS_INSTRUCTIONS:
		consolidation_step_panel.get_node("StepInstructions").text = CONSOLIDATE_STEP_INSTRUCTIONS

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

	# Create range circles for each model (3" radius) — skip locked models
	for model_id in original_model_positions:
		if model_id in locked_base_contact_models:
			continue  # T4-5: No range circle for locked models
		var pos = original_model_positions[model_id]
		var circle = _create_range_circle(pos, 3.0)
		circle.name = "RangeCircle_" + model_id
		pile_in_visuals.add_child(circle)
		range_circles[model_id] = circle

	# T4-5: Create lock indicators for models in base contact
	for model_id in locked_base_contact_models:
		var pos = original_model_positions.get(model_id, Vector2.ZERO)
		if pos == Vector2.ZERO:
			continue
		var lock_indicator = _create_locked_model_indicator(pos)
		lock_indicator.name = "LockedIndicator_" + model_id
		pile_in_visuals.add_child(lock_indicator)

	# T5-V8: Create enhanced movement visual (arrows + dashed paths + distance labels)
	# This replaces the old plain Line2D direction lines
	var PileInMovementVisualScript = preload("res://scripts/PileInMovementVisual.gd")
	pile_in_movement_visual = Node2D.new()
	pile_in_movement_visual.set_script(PileInMovementVisualScript)
	pile_in_movement_visual.name = "PileInMovementVisual"
	board_view.add_child(pile_in_movement_visual)

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

func _create_locked_model_indicator(center: Vector2) -> Node2D:
	"""T4-5: Create a visual indicator showing a model is locked (in base contact, cannot move).
	Draws a red X over the model position."""
	var indicator = Node2D.new()
	var cross_size = 15.0  # Pixel size of the X arms

	# Draw an X shape with two lines
	var line1 = Line2D.new()
	line1.width = 3.0
	line1.default_color = Color(1.0, 0.3, 0.3, 0.8)  # Red, semi-transparent
	line1.add_point(center + Vector2(-cross_size, -cross_size))
	line1.add_point(center + Vector2(cross_size, cross_size))
	indicator.add_child(line1)

	var line2 = Line2D.new()
	line2.width = 3.0
	line2.default_color = Color(1.0, 0.3, 0.3, 0.8)
	line2.add_point(center + Vector2(cross_size, -cross_size))
	line2.add_point(center + Vector2(-cross_size, cross_size))
	indicator.add_child(line2)

	# Add a "LOCKED" label
	var label = Label.new()
	label.text = "B2B"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.9))
	label.position = center + Vector2(-12, cross_size + 2)
	indicator.add_child(label)

	return indicator

func _clear_pile_in_visuals() -> void:
	"""Remove all pile-in visual indicators"""
	if pile_in_visuals and is_instance_valid(pile_in_visuals):
		pile_in_visuals.queue_free()
		pile_in_visuals = null

	# T5-V8: Clean up enhanced movement visual
	if pile_in_movement_visual and is_instance_valid(pile_in_movement_visual):
		pile_in_movement_visual.queue_free()
		pile_in_movement_visual = null

	range_circles.clear()
	direction_lines.clear()
	coherency_lines.clear()

func _update_pile_in_visuals() -> void:
	"""Update visual feedback for current model positions"""
	if not pile_in_active or not current_phase:
		return

	# T5-V8: Update enhanced movement visual with arrows, dashed paths, and distance labels
	if pile_in_movement_visual and is_instance_valid(pile_in_movement_visual):
		for model_id in current_model_positions:
			if model_id in locked_base_contact_models:
				continue  # T4-5: No visuals for locked models

			var current_pos = current_model_positions[model_id]
			var original_pos = original_model_positions.get(model_id, current_pos)

			# Find closest enemy position
			var closest_enemy = _find_closest_enemy_pos(current_pos)

			# Calculate validity
			var move_distance = Measurement.distance_inches(original_pos, current_pos)
			var is_valid = false
			if closest_enemy != Vector2.ZERO:
				var original_dist = original_pos.distance_to(closest_enemy)
				var current_dist = current_pos.distance_to(closest_enemy)
				var is_closer = current_dist <= original_dist
				var distance_ok = move_distance <= 3.0
				is_valid = is_closer and distance_ok

			pile_in_movement_visual.update_model(model_id, original_pos, current_pos, closest_enemy, is_valid, move_distance)

	# Also update old direction_lines if any still exist (backward compatibility)
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

			if dist <= 2.0 + Measurement.DISTANCE_TOLERANCE_INCHES:  # Within coherency range
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
	"""Reset all model positions AND facings to original"""
	print("[FightController] reset_pile_in_movements called - STACK TRACE:")
	print_stack()

	for model_id in original_model_positions:
		current_model_positions[model_id] = original_model_positions[model_id]
	for model_id in original_model_rotations:
		current_model_rotations[model_id] = original_model_rotations[model_id]

	# Move visual models back to original positions and facings
	_apply_model_positions_to_scene()
	_update_pile_in_visuals()

	print("[FightController] Pile-in movements reset")

func _apply_model_positions_to_scene() -> void:
	"""Apply current_model_positions (and rotations) to the actual tokens in the scene"""
	if pile_in_unit_id == "":
		return

	# Get token layer
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		return

	# Update each model token's position and facing (keys may address the
	# unit's own models or an attached character's — "unit:model")
	for key in current_model_positions:
		var route = _pile_in_split_key(key)
		# Find the token with matching metadata
		for token in token_layer.get_children():
			if token.has_meta("unit_id") and token.has_meta("model_id"):
				if token.get_meta("unit_id") == route.unit_id and token.get_meta("model_id") == route.model_id:
					token.position = current_model_positions[key]
					if current_model_rotations.has(key) and "model_data" in token and token.model_data is Dictionary:
						token.model_data["rotation"] = current_model_rotations[key]
						token.queue_redraw()
					break

# T-093: Compute snap-to-base-contact target for the dragging model. Returns
# Vector2.ZERO if no snap is in effect (no enemy within snap zone).
const PILEIN_SNAP_ZONE_INCHES: float = 0.6
func _maybe_snap_to_b2b(candidate_pos: Vector2) -> Vector2:
	if drag_model_id == "" or pile_in_unit_id == "":
		return Vector2.ZERO
	var attacker_unit = GameState.get_unit(pile_in_unit_id) if GameState else {}
	if attacker_unit.is_empty():
		return Vector2.ZERO
	# Find own model's base radius (the dragged model may belong to an
	# attached character — _find_pile_in_model resolves the key)
	var own_radius_px: float = 25.0
	var drag_model = _find_pile_in_model(drag_model_id)
	if not drag_model.is_empty():
		own_radius_px = Measurement.base_radius_px(drag_model.get("base_mm", 32))
	# Iterate enemy units (units of the OTHER owner) for closest model
	var owner = int(attacker_unit.get("owner", 0))
	var snap_zone_px: float = Measurement.inches_to_px(PILEIN_SNAP_ZONE_INCHES)
	var best_candidate: Vector2 = Vector2.ZERO
	var best_excess: float = INF
	var snapshot = GameState.create_snapshot() if GameState else {}
	for uid in snapshot.get("units", {}):
		var u = snapshot.units[uid]
		if int(u.get("owner", 0)) == owner:
			continue
		for em in u.get("models", []):
			if not em.get("alive", true):
				continue
			var epos_data = em.get("position")
			if epos_data == null:
				continue
			var epos: Vector2
			if epos_data is Dictionary:
				epos = Vector2(epos_data.get("x", 0), epos_data.get("y", 0))
			else:
				epos = epos_data
			var enemy_radius_px: float = Measurement.base_radius_px(em.get("base_mm", 32))
			var contact_distance: float = own_radius_px + enemy_radius_px
			var distance: float = candidate_pos.distance_to(epos)
			# Excess = how far INTO the snap zone the candidate is
			var excess: float = distance - contact_distance
			if excess >= 0.0 and excess <= snap_zone_px and excess < best_excess:
				best_excess = excess
				# Snap so own center is exactly contact_distance from enemy center
				var dir_vec: Vector2 = candidate_pos - epos
				if dir_vec.length() < 0.01:
					dir_vec = Vector2(1, 0)
				dir_vec = dir_vec.normalized()
				best_candidate = epos + dir_vec * (contact_distance + 1.0)
	return best_candidate


func _handle_pile_in_input(event: InputEvent) -> void:
	"""Handle input events during pile-in mode"""
	if not board_view:
		print("[FightController] Pile-in input: no board_view")
		return

	var board_root = SceneRefs.board_root()
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
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click for pivoting (mirrors the movement phase rotation UX)
		var mouse_pos = board_root.get_local_mouse_position()
		if event.pressed:
			_start_model_rotation_pile_in(mouse_pos)
		elif pile_in_rotating_model:
			_end_model_rotation_pile_in()
	elif event is InputEventMouseMotion and pile_in_rotating_model:
		# Update rotation
		var mouse_pos = board_root.get_local_mouse_position()
		_update_model_rotation_pile_in(mouse_pos)
	elif event is InputEventMouseMotion and dragging_model:
		# Update drag
		var mouse_pos = board_root.get_local_mouse_position()
		_update_model_drag_pile_in(mouse_pos)
	elif event is InputEventKey and event.pressed:
		# Keyboard pivot of the last-touched model (15° per press)
		if KeybindingManager.matches_action(event, "rotate_left"):
			_rotate_pile_in_model_by_angle(-PI / 12.0)
		elif KeybindingManager.matches_action(event, "rotate_right"):
			_rotate_pile_in_model_by_angle(PI / 12.0)

func _start_model_drag_pile_in(mouse_pos: Vector2) -> void:
	"""Start dragging a model during pile-in"""
	print("[FightController] _start_model_drag_pile_in called, pile_in_unit_id=", pile_in_unit_id)

	if pile_in_unit_id == "":
		print("[FightController] No pile_in_unit_id")
		return

	# Get token layer from BoardRoot
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		print("[FightController] Could not find TokenLayer")
		return

	print("[FightController] Checking ", current_model_positions.size(), " models")

	# Find which model token is being clicked — the piling-in unit's own
	# models or an attached character's ("unit:model" keys)
	# Models are individual TokenVisual nodes in token_layer with metadata
	for key in current_model_positions:
		var model_pos = current_model_positions[key]
		var distance_to_mouse = mouse_pos.distance_to(model_pos)

		print("[FightController] Model ", key, " at ", model_pos, " distance: ", distance_to_mouse)

		# Check if click is within model's base (50px radius for easier clicking)
		if distance_to_mouse < 50.0:
			# T4-5: Block dragging for models already in base contact with an enemy
			if key in locked_base_contact_models:
				print("[FightController] T4-5: Model %s is locked (already in base contact) — cannot drag" % key)
				return
			var route = _pile_in_split_key(key)
			print("[FightController] Distance check passed! Looking for token with unit_id=", route.unit_id, " model_id=", route.model_id)
			# Find the actual token in token_layer with matching metadata
			var tokens_checked = 0
			for token in token_layer.get_children():
				tokens_checked += 1
				if token.has_meta("unit_id") and token.has_meta("model_id"):
					var token_unit_id = token.get_meta("unit_id")
					var token_model_id = token.get_meta("model_id")
					print("[FightController]   Token ", tokens_checked, ": unit_id=", token_unit_id, " model_id=", token_model_id)

					if token_unit_id == route.unit_id and token_model_id == route.model_id:
						dragging_model = token
						drag_model_id = key
						drag_start_pos = model_pos
						drag_offset = model_pos - mouse_pos
						pile_in_last_touched_model = key

						print("[FightController] Started dragging model token ", key)
						return

			print("[FightController] Checked ", tokens_checked, " tokens but none matched")

	print("[FightController] No model found near click position")

func _update_model_drag_pile_in(mouse_pos: Vector2) -> void:
	"""Update model position during drag"""
	if drag_model_id == "" or not dragging_model:
		return

	var new_pos = mouse_pos + drag_offset

	# T-093: snap-to-base-contact — if dragging within snap zone of a closest
	# enemy model, snap to base-to-base. Snap zone is 0.6" beyond contact
	# (mirrors charge phase snap behavior).
	var snap_pos = _maybe_snap_to_b2b(new_pos)
	if snap_pos != Vector2.ZERO:
		new_pos = snap_pos

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

	# T5-MP1: Send throttled drag preview to remote player (resolve the key —
	# the dragged model may belong to an attached character unit)
	var now_ms = Time.get_ticks_msec()
	if now_ms - _last_drag_preview_time >= DRAG_PREVIEW_INTERVAL_MS:
		_last_drag_preview_time = now_ms
		var network_manager = get_node_or_null("/root/NetworkManager")
		if network_manager and network_manager.is_networked():
			var drag_route = _pile_in_split_key(drag_model_id)
			network_manager.send_drag_preview(drag_route.unit_id, drag_route.model_id, new_pos)

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
	elif _model_off_board(drag_model_id, final_pos):
		# Issue #87: pile-in / consolidate cannot push a model off-board.
		print("[FightController] Pile-in/consolidate would place model off the board - reverting")
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
			# A pivoted model spends part of its 3" budget on the pivot cost, so
			# the positional move is capped at (3" − pivot cost). See
			# _effective_pile_in_cap_inches().
			var effective_cap = _effective_pile_in_cap_inches(drag_model_id)
			# Check if movement exceeds the effective cap (with float tolerance)
			if distance > effective_cap + 0.02:
				# Snap back to the maximum allowed distance in the same direction
				var direction = (final_pos - original_pos).normalized()
				var max_distance_px = Measurement.inches_to_px(effective_cap)
				var clamped_pos = original_pos + direction * max_distance_px
				current_model_positions[drag_model_id] = clamped_pos

				if dragging_model:
					dragging_model.position = clamped_pos

				print("[FightController] Clamped movement to %.1f\" limit (pivot-aware)" % effective_cap)

	# P3-101: Send final corrected position to remote player after revert/clamp
	# Without this, the remote player's last drag preview shows the pre-revert position
	if drag_model_id != "":
		var final_synced_pos = current_model_positions.get(drag_model_id, Vector2.ZERO)
		var network_manager = get_node_or_null("/root/NetworkManager")
		if network_manager and network_manager.is_networked():
			print("[FightController] P3-101: Sending final drag position for %s: %s" % [drag_model_id, final_synced_pos])
			var final_route = _pile_in_split_key(drag_model_id)
			network_manager.send_drag_preview(final_route.unit_id, final_route.model_id, final_synced_pos)

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

# ============================================================================
# PILE-IN / CONSOLIDATE MODEL ROTATION (pivoting)
# ============================================================================
# Models on non-circular bases (e.g. bikes on oval bases) may be pivoted about
# their centre during a pile-in / consolidate move, exactly as they can in the
# movement phase. The pivot cost (2") is deducted from the model's 3" move — see
# _effective_pile_in_cap_inches().

func _model_can_pivot(model: Dictionary, model_key: String = "") -> bool:
	"""Mirror of MovementController's rotation gate: only non-circular bases (or a
	round base >32mm with a flying stem on a VEHICLE) can be pivoted. The optional
	key resolves the model's OWN unit (it may be an attached character's)."""
	if model.is_empty():
		return false
	var base_type = model.get("base_type", "circular")
	if base_type != "circular":
		return true
	# Round base >32mm with a flying stem — VEHICLE only (mirrors pivot value rules)
	var base_mm = int(model.get("base_mm", 32))
	var has_flying_stem = model.get("flying_stem", false)
	if base_mm > 32 and has_flying_stem:
		var unit_id = _pile_in_split_key(model_key).unit_id if model_key != "" else pile_in_unit_id
		var unit = current_phase.get_unit(unit_id) if current_phase else {}
		var keywords = unit.get("meta", {}).get("keywords", [])
		if "VEHICLE" in keywords:
			return true
	return false

func _pivot_cost_inches(model: Dictionary, model_key: String = "") -> float:
	"""Cost in inches a pivot deducts from the 3" move. All non-round bases (and
	eligible round >32mm flying-stem VEHICLE bases) cost 2" per Pariah Nexus."""
	return 2.0 if _model_can_pivot(model, model_key) else 0.0

func _find_pile_in_model(model_key: String) -> Dictionary:
	"""Look up a model dict by tracking key — the piling-in unit's own models
	(plain id) or an attached character's ("unit:model")."""
	if not current_phase or pile_in_unit_id == "":
		return {}
	var route = _pile_in_split_key(model_key)
	var unit = current_phase.get_unit(route.unit_id)
	for m in unit.get("models", []):
		if m.get("id", "") == route.model_id:
			return m
	return {}

func _is_model_pivoted(model_id: String) -> bool:
	"""True if the model's rotation has changed from its start-of-move facing."""
	if not current_model_rotations.has(model_id):
		return false
	var start = original_model_rotations.get(model_id, 0.0)
	return abs(current_model_rotations[model_id] - start) > 0.001

func _effective_pile_in_cap_inches(model_id: String) -> float:
	"""The positional distance a model may still move: 3" minus the pivot cost if
	it has been pivoted this move."""
	if _is_model_pivoted(model_id):
		var model = _find_pile_in_model(model_id)
		return max(0.0, PILE_IN_MAX_INCHES - _pivot_cost_inches(model, model_id))
	return PILE_IN_MAX_INCHES

func _model_id_at_pos(mouse_pos: Vector2) -> String:
	"""Return the id of the (unlocked) model nearest the cursor within its base
	(plus a small grab margin), or "" if none. The hit radius scales with the
	model's base so large oval/rectangular vehicles are grabbable."""
	var best_id := ""
	var best_dist := INF
	for model_id in current_model_positions:
		if model_id in locked_base_contact_models:
			continue
		var d = mouse_pos.distance_to(current_model_positions[model_id])
		var model = _find_pile_in_model(model_id)
		var hit_radius = max(50.0, Measurement.base_radius_px(int(model.get("base_mm", 32))) + 20.0)
		if d <= hit_radius and d < best_dist:
			best_dist = d
			best_id = model_id
	return best_id

func _start_model_rotation_pile_in(mouse_pos: Vector2) -> void:
	"""Begin pivoting the model under the cursor (right-click)."""
	if pile_in_unit_id == "":
		return
	var model_id = _model_id_at_pos(mouse_pos)
	if model_id == "":
		return
	var model = _find_pile_in_model(model_id)
	if not _model_can_pivot(model, model_id):
		print("[FightController] Model %s has a circular base — no pivot needed" % model_id)
		return

	pile_in_rotating_model = true
	rotation_model_id = model_id
	pile_in_last_touched_model = model_id
	var model_pos = current_model_positions.get(model_id, Vector2.ZERO)
	rotation_start_angle = (mouse_pos - model_pos).angle()
	rotation_model_start = current_model_rotations.get(model_id, 0.0)
	print("[FightController] Started pivoting model %s (base_type=%s)" % [model_id, model.get("base_type", "circular")])

func _update_model_rotation_pile_in(mouse_pos: Vector2) -> void:
	"""Track the cursor while pivoting — rotate about the model's centre."""
	if not pile_in_rotating_model or rotation_model_id == "":
		return
	var model_pos = current_model_positions.get(rotation_model_id, Vector2.ZERO)
	var current_angle = (mouse_pos - model_pos).angle()
	var new_rotation = rotation_model_start + (current_angle - rotation_start_angle)
	_apply_pile_in_rotation(rotation_model_id, new_rotation)

func _end_model_rotation_pile_in() -> void:
	"""Finish a pivot: settle budget/overlap and refresh the dialog."""
	if not pile_in_rotating_model:
		return
	var model_id = rotation_model_id
	pile_in_rotating_model = false
	rotation_model_id = ""

	# Pivoting consumes budget, so an already-moved model may now exceed its
	# (3" − pivot cost) allowance. Pull the position back along the move line so
	# the state stays legal, exactly as the movement phase reduces the move cap.
	_enforce_effective_cap_after_pivot(model_id)

	# An oval base can swing into a neighbour without its centre moving; if the
	# pivot causes an overlap, revert the rotation.
	if _check_model_overlaps(model_id, current_model_positions.get(model_id, Vector2.ZERO)):
		print("[FightController] Pivot causes overlap — reverting rotation for %s" % model_id)
		_apply_pile_in_rotation(model_id, original_model_rotations.get(model_id, 0.0))

	print("[FightController] Ended pivot for %s — rotation %.2f rad" % [model_id, current_model_rotations.get(model_id, 0.0)])
	_update_pile_in_visuals()
	if pile_in_dialog_ref and pile_in_dialog_ref.has_method("update_movements"):
		pile_in_dialog_ref.update_movements(get_pile_in_movements())
	if pile_in_dialog_ref and pile_in_dialog_ref.has_method("update_rotations"):
		pile_in_dialog_ref.update_rotations(get_pile_in_rotations())

func _rotate_pile_in_model_by_angle(angle: float) -> void:
	"""Keyboard pivot: nudge the last-touched model by `angle` radians."""
	if pile_in_unit_id == "":
		return
	var model_id = pile_in_last_touched_model
	if model_id == "" or model_id in locked_base_contact_models:
		return
	var model = _find_pile_in_model(model_id)
	if not _model_can_pivot(model, model_id):
		return
	var new_rotation = current_model_rotations.get(model_id, 0.0) + angle
	_apply_pile_in_rotation(model_id, new_rotation)
	_enforce_effective_cap_after_pivot(model_id)
	if _check_model_overlaps(model_id, current_model_positions.get(model_id, Vector2.ZERO)):
		_apply_pile_in_rotation(model_id, current_model_rotations.get(model_id, 0.0) - angle)
	_update_pile_in_visuals()
	if pile_in_dialog_ref and pile_in_dialog_ref.has_method("update_movements"):
		pile_in_dialog_ref.update_movements(get_pile_in_movements())
	if pile_in_dialog_ref and pile_in_dialog_ref.has_method("update_rotations"):
		pile_in_dialog_ref.update_rotations(get_pile_in_rotations())

func _enforce_effective_cap_after_pivot(model_id: String) -> void:
	"""After a pivot reduces the budget, clamp the model's position so its move
	distance still fits within (3" − pivot cost)."""
	var original_pos = original_model_positions.get(model_id, Vector2.ZERO)
	var current_pos = current_model_positions.get(model_id, original_pos)
	var distance = Measurement.distance_inches(original_pos, current_pos)
	var cap = _effective_pile_in_cap_inches(model_id)
	if distance > cap + 0.02:
		var direction = (current_pos - original_pos).normalized()
		var clamped = original_pos + direction * Measurement.inches_to_px(cap)
		current_model_positions[model_id] = clamped
		_apply_single_model_position_to_scene(model_id, clamped)
		print("[FightController] Pivot cost clamped %s move to %.1f\"" % [model_id, cap])

func _apply_pile_in_rotation(model_id: String, new_rotation: float) -> void:
	"""Store the new facing and redraw the model's token immediately. Mirrors
	MovementController._update_model_token_visual so the token re-renders the
	rotated base exactly as it does in the movement phase."""
	current_model_rotations[model_id] = new_rotation

	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		return
	var route = _pile_in_split_key(model_id)
	for token in token_layer.get_children():
		if token.has_meta("unit_id") and token.has_meta("model_id"):
			if token.get_meta("unit_id") == route.unit_id and token.get_meta("model_id") == route.model_id:
				if "model_data" in token and token.model_data is Dictionary:
					token.model_data["rotation"] = new_rotation
					# Rebuild base_shape + redraw the same way the movement phase does
					if token.has_method("set_model_data"):
						token.set_model_data(token.model_data)
				token.queue_redraw()
				break

func _apply_single_model_position_to_scene(model_id: String, pos: Vector2) -> void:
	"""Move one model's token to `pos` (used when the pivot clamp adjusts it)."""
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		return
	var route = _pile_in_split_key(model_id)
	for token in token_layer.get_children():
		if token.has_meta("unit_id") and token.has_meta("model_id"):
			if token.get_meta("unit_id") == route.unit_id and token.get_meta("model_id") == route.model_id:
				token.position = pos
				break

func get_pile_in_rotations() -> Dictionary:
	"""Return {model_id: rotation} for every model whose facing changed."""
	var rotations = {}
	for model_id in current_model_rotations:
		var start = original_model_rotations.get(model_id, 0.0)
		if abs(current_model_rotations[model_id] - start) > 0.001:
			rotations[model_id] = current_model_rotations[model_id]
	return rotations

func _enable_consolidate_mode(unit_id: String, dialog: Node) -> void:
	"""Enable interactive consolidate mode (uses same system as pile-in)"""
	consolidate_active = true
	# Reuse the pile-in infrastructure
	_enable_pile_in_mode(unit_id, dialog)
	print("[FightController] Consolidate mode enabled for ", unit_id)

func _on_consolidate_dialog_closed() -> void:
	"""Handle consolidate dialog being closed"""
	_disable_pile_in_mode()

func _model_off_board(moving_model_id: String, new_pos: Vector2) -> bool:
	"""Issue #87: returns true if `moving_model_id` placed at `new_pos`
	would extend beyond the battlefield. Wraps the shared Measurement
	helper with the model lookup (key may address an attached character)."""
	if not current_phase or pile_in_unit_id == "":
		return false
	var m = _find_pile_in_model(moving_model_id)
	if m.is_empty():
		return false
	return Measurement.model_outside_board(new_pos, m)

func _check_model_overlaps(moving_model_id: String, new_pos: Vector2) -> bool:
	"""Check if a model at the given position would overlap with any other models.
	The moving key may address the piling-in unit's own models or an attached
	character's ("unit:model") — both are part of the one Attached-unit move."""
	if not current_phase or pile_in_unit_id == "":
		return false

	# Get the moving model's data
	var moving_route = _pile_in_split_key(moving_model_id)
	var moving_model = _find_pile_in_model(moving_model_id)
	if moving_model.is_empty():
		return false

	# Create a temporary model dict with the new position (and live pivot facing)
	# for overlap checking. Rotation matters for non-circular bases: an oval base
	# can swing into a neighbour even when its centre stays put.
	var check_model = moving_model.duplicate()
	check_model["position"] = new_pos
	if current_model_rotations.has(moving_model_id):
		check_model["rotation"] = current_model_rotations[moving_model_id]

	# Check against all other models in all units
	var all_units = current_phase.game_state_snapshot.get("units", {})
	var group_ids = _pile_in_group_unit_ids()
	for check_unit_id in all_units:
		var check_unit = all_units[check_unit_id]
		var check_models = check_unit.get("models", [])

		for i in range(check_models.size()):
			var other_model = check_models[i]

			# Skip self
			if check_unit_id == moving_route.unit_id and other_model.get("id", "") == moving_route.model_id:
				continue

			# Skip dead models
			if not other_model.get("alive", true):
				continue

			# Use position from current_model_positions if this is a friendly model being moved
			var other_pos = other_model.get("position", {})
			if other_pos == null:
				continue

			var other_model_check = other_model.duplicate()
			if check_unit_id in group_ids:
				var other_key = _pile_in_model_key(check_unit_id, other_model.get("id", ""))
				if other_key in current_model_positions:
					other_model_check["position"] = current_model_positions[other_key]
				if other_key in current_model_rotations:
					other_model_check["rotation"] = current_model_rotations[other_key]

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

# =============================================================================
# P0-58: INTERACTIVE MELEE WOUND ALLOCATION
# =============================================================================

func _on_melee_saves_required(save_data_list: Array) -> void:
	"""Show WoundAllocationOverlay when defender needs to make saves in melee combat."""
	# Prevent re-entrant calls
	if processing_melee_saves_signal:
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ P0-58: ❌ DUPLICATE MELEE SAVES SIGNAL BLOCKED")
		print("╚═══════════════════════════════════════════════════════════════")
		return

	processing_melee_saves_signal = true

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ P0-58: MELEE SAVES_REQUIRED RECEIVED (FightController)")
	print("║ Timestamp: ", Time.get_ticks_msec())
	print("║ Save data list size: ", save_data_list.size())

	if save_data_list.is_empty():
		print("║ ⚠️  WARNING: Empty save data list - RETURNING")
		print("╚═══════════════════════════════════════════════════════════════")
		processing_melee_saves_signal = false
		return

	var save_data = save_data_list[0]
	var target = save_data.get("target_unit_id", "unknown")
	var weapon = save_data.get("weapon_name", "unknown")
	var wounds = save_data.get("wounds_to_save", 0)

	print("║ Target: ", target)
	print("║ Weapon: ", weapon)
	print("║ Wounds: ", wounds)

	# Check if overlay already exists
	if active_melee_allocation_overlay != null and is_instance_valid(active_melee_allocation_overlay):
		print("║ ⚠️  Active melee overlay already exists — ignoring duplicate")
		print("╚═══════════════════════════════════════════════════════════════")
		processing_melee_saves_signal = false
		return

	# Get defender
	var target_unit_id = save_data.get("target_unit_id", "")
	if target_unit_id == "":
		push_error("FightController: P0-58: No target_unit_id in save data")
		processing_melee_saves_signal = false
		return

	var target_unit = GameState.get_unit(target_unit_id)
	if target_unit.is_empty():
		push_error("FightController: P0-58: Target unit not found: " + target_unit_id)
		processing_melee_saves_signal = false
		return

	var defender_player = target_unit.get("owner", 0)

	# Determine if this local player should see the dialog
	var should_show_dialog = false

	if NetworkManager.is_networked():
		var local_player = NetworkManager.get_local_player()
		should_show_dialog = (local_player == defender_player)
		print("║ Mode: MULTIPLAYER, Local: %d, Defender: %d, Show: %s" % [local_player, defender_player, str(should_show_dialog)])
	else:
		should_show_dialog = true
		print("║ Mode: SINGLE PLAYER — showing dialog")

	if not should_show_dialog:
		print("║ ❌ NOT SHOWING — Not the defending player")
		print("╚═══════════════════════════════════════════════════════════════")
		processing_melee_saves_signal = false
		return

	print("║ ✅ SHOWING MELEE WOUND ALLOCATION DIALOG")
	print("╚═══════════════════════════════════════════════════════════════")

	# Temporarily disable input
	set_process_input(false)
	set_process_unhandled_input(false)

	# Create the wound allocation overlay — the 11e allocation-group flow
	# (defender rolls saves, optional save Command Re-roll, casualty picks)
	# at edition >= 11, the legacy per-wound overlay otherwise. Mirrors
	# ShootingController._on_saves_required.
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ P0-58: CREATING MELEE WOUND ALLOCATION OVERLAY")
	print("║ Target: ", target)
	print("║ Weapon: ", weapon)
	print("║ Wounds: ", wounds)

	var overlay = null
	if GameConstants.edition >= 11:
		overlay = AllocationGroupOverlay.new()
	else:
		overlay = WoundAllocationOverlay.new()
	active_melee_allocation_overlay = overlay
	print("║ Overlay instance created: ", overlay.get_instance_id(), " (", overlay.get_class(), " 11e=", GameConstants.edition >= 11, ")")

	# Connect to allocation_complete signal to submit APPLY_MELEE_SAVES
	overlay.allocation_complete.connect(func(summary):
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ P0-58: MELEE WOUND ALLOCATION COMPLETE")
		print("║ Timestamp: ", Time.get_ticks_msec())
		print("║ Summary: ", summary)

		# Build APPLY_MELEE_SAVES action from summary
		var apply_melee_saves_action = {
			"type": "APPLY_MELEE_SAVES",
			"payload": {
				"save_results_list": [summary]
			}
		}

		print("║ Emitting fight_action_requested with APPLY_MELEE_SAVES")
		emit_signal("fight_action_requested", apply_melee_saves_action)

		print("║ APPLY_MELEE_SAVES action submitted successfully")
		print("╚═══════════════════════════════════════════════════════════════")

		active_melee_allocation_overlay = null
		processing_melee_saves_signal = false
		set_process_input(true)
		set_process_unhandled_input(true)
	)

	# Add to scene tree
	var main = SceneRefs.main()
	if not main:
		push_error("FightController: P0-58: /root/Main not found!")
		processing_melee_saves_signal = false
		return

	main.add_child(overlay)
	print("║ Overlay added to scene tree")

	# Setup overlay with save data and defender player
	overlay.setup(save_data, defender_player)
	print("║ Overlay setup called with defender_player=%d" % defender_player)
	print("╚═══════════════════════════════════════════════════════════════")

# ============================================================================
# SWEEPING ADVANCE
# ============================================================================

func _on_sweeping_advance_available(unit_id: String, player: int, in_engagement: bool, move_distance: float) -> void:
	"""Show Sweeping Advance dialog and enable interactive movement"""
	print("[FightController] Sweeping Advance available for %s (player %d, in_engagement=%s, move=%.0f\")" % [
		unit_id, player, str(in_engagement), move_distance
	])

	# Skip dialog for AI players — they handle it via AIDecisionMaker
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("[FightController] Skipping Sweeping Advance dialog for AI player %d" % player)
		return

	var dialog_script = load("res://dialogs/SweepingAdvanceDialog.gd")
	if not dialog_script:
		push_error("Failed to load SweepingAdvanceDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(unit_id, in_engagement, move_distance, current_phase, self)
	dialog.sweeping_advance_accepted.connect(_on_sweeping_advance_accepted.bind(unit_id))
	dialog.sweeping_advance_declined.connect(_on_sweeping_advance_declined.bind(unit_id))
	dialog.tree_exiting.connect(_on_sweeping_advance_dialog_closed)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)

	# Enable movement mode (reuses pile-in infrastructure)
	sweeping_advance_active = true
	_enable_pile_in_mode(unit_id, dialog)

	# Show in dice log
	if dice_log_display:
		var unit_name = ""
		if current_phase:
			var unit = current_phase.get_unit(unit_id)
			unit_name = unit.get("meta", {}).get("name", unit_id)
		var move_type = "Fall Back" if in_engagement else "Normal Move"
		dice_log_display.append_text("\n[color=gold]SWEEPING ADVANCE: %s may make a %s (%.0f\")[/color]\n" % [
			unit_name, move_type, move_distance
		])

	print("[FightController] Sweeping Advance dialog shown for %s" % unit_id)

func _on_sweeping_advance_accepted(movements: Dictionary, unit_id: String) -> void:
	"""Submit SWEEPING_ADVANCE action with movements"""
	print("[FightController] Sweeping Advance accepted for %s with movements: %s" % [unit_id, str(movements)])

	# Convert model IDs from "m1" format to array indices for FightPhase
	var converted_movements = {}
	if not movements.is_empty() and current_phase:
		var unit = current_phase.get_unit(unit_id)
		if unit:
			var models = unit.get("models", [])
			for model_id in movements:
				for i in range(models.size()):
					if models[i].get("id", "") == model_id:
						converted_movements[str(i)] = movements[model_id]
						break

	var action = {
		"type": "SWEEPING_ADVANCE",
		"unit_id": unit_id,
		"movements": converted_movements,
		"player": current_phase.get_unit(unit_id).get("owner", 0) if current_phase else 0
	}
	emit_signal("fight_action_requested", action)
	sweeping_advance_active = false

func _on_sweeping_advance_declined(unit_id: String) -> void:
	"""Player declined Sweeping Advance"""
	print("[FightController] Sweeping Advance declined for %s" % unit_id)

	var action = {
		"type": "DECLINE_SWEEPING_ADVANCE",
		"unit_id": unit_id,
		"player": current_phase.get_unit(unit_id).get("owner", 0) if current_phase else 0
	}
	emit_signal("fight_action_requested", action)
	sweeping_advance_active = false

func _on_sweeping_advance_dialog_closed() -> void:
	"""Handle Sweeping Advance dialog being closed"""
	_disable_pile_in_mode()
	sweeping_advance_active = false

# ============================================================================
# ACROBATIC ESCAPE (Callidus Assassin)
# ============================================================================

func _on_acrobatic_escape_available(unit_id: String, player: int, move_distance: float) -> void:
	"""Show Acrobatic Escape dialog and enable interactive movement"""
	print("[FightController] Acrobatic Escape available for %s (player %d, D6=%.0f\")" % [
		unit_id, player, move_distance
	])

	# Skip dialog for AI players — they handle it via AIDecisionMaker
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("[FightController] Skipping Acrobatic Escape dialog for AI player %d" % player)
		return

	var dialog_script = load("res://dialogs/AcrobaticEscapeDialog.gd")
	if not dialog_script:
		push_error("Failed to load AcrobaticEscapeDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(unit_id, move_distance, current_phase, self)
	dialog.acrobatic_escape_accepted.connect(_on_acrobatic_escape_accepted.bind(unit_id))
	dialog.acrobatic_escape_declined.connect(_on_acrobatic_escape_declined.bind(unit_id))
	dialog.tree_exiting.connect(_on_acrobatic_escape_dialog_closed)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)

	# Enable movement mode (reuses pile-in infrastructure)
	acrobatic_escape_active = true
	_enable_pile_in_mode(unit_id, dialog)

	# Show in dice log
	if dice_log_display:
		var unit_name = ""
		if current_phase:
			var unit = current_phase.get_unit(unit_id)
			unit_name = unit.get("meta", {}).get("name", unit_id)
		dice_log_display.append_text("\n[color=#CC33CC]ACROBATIC ESCAPE: %s may Fall Back (D6 = %.0f\")[/color]\n" % [
			unit_name, move_distance
		])

	print("[FightController] Acrobatic Escape dialog shown for %s" % unit_id)

func _on_acrobatic_escape_accepted(movements: Dictionary, unit_id: String) -> void:
	"""Submit ACROBATIC_ESCAPE action with movements"""
	print("[FightController] Acrobatic Escape accepted for %s with movements: %s" % [unit_id, str(movements)])

	# Convert model IDs from "m1" format to array indices for FightPhase
	var converted_movements = {}
	if not movements.is_empty() and current_phase:
		var unit = current_phase.get_unit(unit_id)
		if unit:
			var models = unit.get("models", [])
			for model_id in movements:
				for i in range(models.size()):
					if models[i].get("id", "") == model_id:
						converted_movements[str(i)] = movements[model_id]
						break

	var action = {
		"type": "ACROBATIC_ESCAPE",
		"unit_id": unit_id,
		"movements": converted_movements,
		"player": current_phase.get_unit(unit_id).get("owner", 0) if current_phase else 0
	}
	emit_signal("fight_action_requested", action)
	acrobatic_escape_active = false

func _on_acrobatic_escape_declined(unit_id: String) -> void:
	"""Player declined Acrobatic Escape"""
	print("[FightController] Acrobatic Escape declined for %s" % unit_id)

	var action = {
		"type": "DECLINE_ACROBATIC_ESCAPE",
		"unit_id": unit_id,
		"player": current_phase.get_unit(unit_id).get("owner", 0) if current_phase else 0
	}
	emit_signal("fight_action_requested", action)
	acrobatic_escape_active = false

func _on_acrobatic_escape_dialog_closed() -> void:
	"""Handle Acrobatic Escape dialog being closed"""
	_disable_pile_in_mode()
	acrobatic_escape_active = false
