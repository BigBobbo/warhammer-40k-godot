extends Control
class_name WoundAllocationOverlay

# Interactive Wound Allocation Overlay for 10th Edition Warhammer 40K
# Implements sequential, one-at-a-time wound allocation with board-based model selection

# Preload scripts at class level (REQUIRED for instantiation to work)
const WoundAllocationBoardHighlightsScript = preload("res://scripts/WoundAllocationBoardHighlights.gd")

# Signals for state changes
signal wound_allocated(model_id: String, wound_index: int)
signal save_rolled(result: Dictionary)
signal allocation_complete(summary: Dictionary)

# State
var save_data: Dictionary = {}  # From RulesEngine.prepare_save_resolution()
var current_wound_index: int = 0
var total_wounds: int = 0
var allocation_history: Array = []  # [{wound_index, model_id, roll, saved, damage}]
var defender_player: int = 0
var awaiting_selection: bool = false
var rng_service: RulesEngine.RNGService = null

# References
var board_view: Node2D
var target_unit: Dictionary
var board_highlighter: WoundAllocationBoardHighlights

# UI Nodes
var overlay_panel: PanelContainer
var attack_info_label: Label
var status_label: Label
var target_info_label: Label
var save_info_label: RichTextLabel
var instruction_label: RichTextLabel
var dice_result_panel: PanelContainer
var result_label: Label
var outcome_label: RichTextLabel  # FIX: Changed from Label to RichTextLabel
var continue_button: Button

func _ready() -> void:
	# CRITICAL: Log to both console AND push_warning so it's impossible to miss
	push_warning("░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░")
	push_warning("░░░ WoundAllocationOverlay._ready() CALLED ░░░")
	push_warning("░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░")
	print("░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░")
	print("░░░ WoundAllocationOverlay._ready() CALLED ░░░")
	print("░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░")
	print("WoundAllocationOverlay: [READY STEP 1] Setting anchors to full screen...")

	# Make this overlay fill the entire screen and be on top
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	z_index = 100  # Ensure we're on top of everything
	mouse_filter = Control.MOUSE_FILTER_STOP  # FIXED: STOP clicks from passing through

	print("WoundAllocationOverlay: [READY STEP 2] Anchors and z_index set")
	print("  - anchor_left: ", anchor_left)
	print("  - anchor_right: ", anchor_right)
	print("  - z_index: ", z_index)
	print("  - mouse_filter: ", mouse_filter)

	print("WoundAllocationOverlay: [READY STEP 3] Skipping background dim (board should remain visible)")
	# No background dim - board must remain visible for model selection

	print("WoundAllocationOverlay: [READY STEP 5] Building UI...")
	# Create overlay panel - CRITICAL: This must succeed
	_ensure_ui_built()
	print("WoundAllocationOverlay: [READY STEP 6] UI built, verifying nodes...")
	print("  - overlay_panel exists: ", overlay_panel != null)
	print("  - dice_result_panel exists: ", dice_result_panel != null)
	print("  - continue_button exists: ", continue_button != null)

	print("WoundAllocationOverlay: [READY STEP 7] Getting BoardView reference...")
	# Get board reference
	board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
	if not board_view:
		push_error("WoundAllocationOverlay: BoardView not found!")
		print("WoundAllocationOverlay: [READY STEP 8] ERROR - BoardView not found!")
	else:
		print("WoundAllocationOverlay: [READY STEP 8] BoardView found at: ", board_view.get_path())

	print("WoundAllocationOverlay: [READY STEP 9] Creating board highlighter...")
	# Create board highlighter using class-level preload constant
	board_highlighter = WoundAllocationBoardHighlightsScript.new()
	board_highlighter.name = "WoundHighlights"
	if board_view:
		board_view.add_child(board_highlighter)
		print("WoundAllocationOverlay: [READY STEP 10] Board highlighter created and added to BoardView")
	else:
		print("WoundAllocationOverlay: [READY STEP 10] WARNING - board_view is null, cannot add highlighter")

	# Hide dice result panel initially (with null check)
	if dice_result_panel:
		dice_result_panel.visible = false
		print("WoundAllocationOverlay: [READY STEP 11] Dice result panel hidden")
	else:
		push_error("WoundAllocationOverlay: [READY STEP 11] ERROR - dice_result_panel is NULL!")

	print("WoundAllocationOverlay: [READY STEP 12] Final _ready() state:")
	print("  - Visible: ", visible)
	print("  - In tree: ", is_inside_tree())
	print("  - Tree path: ", get_path() if is_inside_tree() else "NOT IN TREE")
	print("  - Global position: ", global_position if is_inside_tree() else "N/A")
	print("  - Size: ", size)
	print("  - Rect: ", get_rect())
	print("  - Children count: ", get_child_count())

	print("░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░")
	print("░░░ WoundAllocationOverlay._ready() COMPLETE ░░░")
	print("░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░")

func _ensure_ui_built() -> void:
	"""Ensure UI is built - call this before any UI access"""
	print("WoundAllocationOverlay: _ensure_ui_built CALLED")
	print("  - overlay_panel null: ", overlay_panel == null)
	print("  - dice_result_panel null: ", dice_result_panel == null)
	print("  - continue_button null: ", continue_button == null)
	print("  - instruction_label null: ", instruction_label == null)

	# CRITICAL FIX: Check if ALL critical UI nodes exist, not just overlay_panel
	var all_nodes_exist = (
		overlay_panel != null and is_instance_valid(overlay_panel) and
		attack_info_label != null and is_instance_valid(attack_info_label) and
		status_label != null and is_instance_valid(status_label) and
		instruction_label != null and is_instance_valid(instruction_label) and
		dice_result_panel != null and is_instance_valid(dice_result_panel) and
		result_label != null and is_instance_valid(result_label) and
		outcome_label != null and is_instance_valid(outcome_label) and
		continue_button != null and is_instance_valid(continue_button)
	)

	if all_nodes_exist:
		print("WoundAllocationOverlay: _ensure_ui_built - ALL UI nodes exist and are valid")
		return

	if overlay_panel != null:
		push_error("WoundAllocationOverlay: _ensure_ui_built - Some nodes exist but others are null! Rebuilding ALL UI...")
		# Clear the partially-built UI
		if is_instance_valid(overlay_panel):
			overlay_panel.queue_free()
		overlay_panel = null

	print("WoundAllocationOverlay: _ensure_ui_built - Building UI now...")
	print("  - Self is in tree: ", is_inside_tree())
	print("  - Self path: ", get_path() if is_inside_tree() else "NOT IN TREE")

	_build_ui()

	# Verify all critical nodes were created AND are valid
	var all_good = true
	if overlay_panel == null or not is_instance_valid(overlay_panel):
		push_error("WoundAllocationOverlay: CRITICAL - overlay_panel is null or invalid after _build_ui!")
		all_good = false
	if dice_result_panel == null or not is_instance_valid(dice_result_panel):
		push_error("WoundAllocationOverlay: CRITICAL - dice_result_panel is null or invalid after _build_ui!")
		all_good = false
	if continue_button == null or not is_instance_valid(continue_button):
		push_error("WoundAllocationOverlay: CRITICAL - continue_button is null or invalid after _build_ui!")
		all_good = false
	if status_label == null or not is_instance_valid(status_label):
		push_error("WoundAllocationOverlay: CRITICAL - status_label is null or invalid after _build_ui!")
		all_good = false
	if result_label == null or not is_instance_valid(result_label):
		push_error("WoundAllocationOverlay: CRITICAL - result_label is null or invalid after _build_ui!")
		all_good = false
	if outcome_label == null or not is_instance_valid(outcome_label):
		push_error("WoundAllocationOverlay: CRITICAL - outcome_label is null or invalid after _build_ui!")
		all_good = false

	if all_good:
		print("WoundAllocationOverlay: _ensure_ui_built - All UI nodes created successfully and are valid")
	else:
		push_error("WoundAllocationOverlay: _ensure_ui_built - FAILED to create all UI nodes!")

func _build_ui() -> void:
	"""Build the overlay UI structure"""
	print("██████████████████████████████████████████████████████")
	print("██████ WoundAllocationOverlay._build_ui() START ██████")
	print("██████████████████████████████████████████████████████")
	print("WoundAllocationOverlay: _build_ui() starting")
	print("  - Current overlay_panel value: ", overlay_panel)
	print("  - Is in tree: ", is_inside_tree())
	print("  - Self path: ", get_path() if is_inside_tree() else "NOT IN TREE")

	# Create centered panel
	print("WoundAllocationOverlay: _build_ui() [STEP 1] Creating PanelContainer...")
	overlay_panel = PanelContainer.new()
	print("WoundAllocationOverlay: _build_ui() [STEP 2] PanelContainer created: ", overlay_panel)

	overlay_panel.custom_minimum_size = Vector2(450, 250)
	overlay_panel.anchor_left = 0.5
	overlay_panel.anchor_top = 0.2
	overlay_panel.anchor_right = 0.5
	overlay_panel.anchor_bottom = 0.2
	overlay_panel.offset_left = -225  # Half of width
	overlay_panel.offset_right = 225
	overlay_panel.offset_bottom = 250
	overlay_panel.z_index = 101  # Above the overlay background
	overlay_panel.mouse_filter = Control.MOUSE_FILTER_PASS  # FIXED: Pass clicks through panel to overlay, not to board
	overlay_panel.visible = true
	print("WoundAllocationOverlay: _build_ui() [STEP 3] PanelContainer configured")
	print("  - custom_minimum_size: ", overlay_panel.custom_minimum_size)
	print("  - z_index: ", overlay_panel.z_index)
	print("  - visible: ", overlay_panel.visible)

	print("WoundAllocationOverlay: _build_ui() [STEP 4] Adding overlay_panel as child...")
	add_child(overlay_panel)
	print("WoundAllocationOverlay: _build_ui() [STEP 5] overlay_panel added to tree")
	print("  - overlay_panel in tree: ", overlay_panel.is_inside_tree())
	print("  - overlay_panel path: ", overlay_panel.get_path() if overlay_panel.is_inside_tree() else "NOT IN TREE")

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	overlay_panel.add_child(main_vbox)

	# Header - Attack Info
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	attack_info_label = Label.new()
	attack_info_label.add_theme_font_size_override("font_size", 14)
	attack_info_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8))
	header_hbox.add_child(attack_info_label)

	main_vbox.add_child(HSeparator.new())

	# Status
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color.YELLOW)
	main_vbox.add_child(status_label)

	# Target Info
	target_info_label = Label.new()
	target_info_label.add_theme_font_size_override("font_size", 11)
	main_vbox.add_child(target_info_label)

	# Save Info
	save_info_label = RichTextLabel.new()
	save_info_label.custom_minimum_size = Vector2(0, 40)
	save_info_label.bbcode_enabled = true
	save_info_label.fit_content = true
	save_info_label.scroll_active = false
	main_vbox.add_child(save_info_label)

	main_vbox.add_child(HSeparator.new())

	# Instructions Panel
	var instruction_panel = PanelContainer.new()
	var instruction_panel_style = StyleBoxFlat.new()
	instruction_panel_style.bg_color = Color(0.2, 0.2, 0.3, 0.5)
	instruction_panel_style.set_border_width_all(1)
	instruction_panel_style.border_color = Color.YELLOW
	instruction_panel.add_theme_stylebox_override("panel", instruction_panel_style)
	main_vbox.add_child(instruction_panel)

	instruction_label = RichTextLabel.new()
	instruction_label.custom_minimum_size = Vector2(0, 50)
	instruction_label.bbcode_enabled = true
	instruction_label.fit_content = true
	instruction_label.scroll_active = false
	instruction_panel.add_child(instruction_label)

	# Dice Result Panel (hidden initially)
	dice_result_panel = PanelContainer.new()
	var dice_panel_style = StyleBoxFlat.new()
	dice_panel_style.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	dice_result_panel.add_theme_stylebox_override("panel", dice_panel_style)
	main_vbox.add_child(dice_result_panel)

	var dice_vbox = VBoxContainer.new()
	dice_result_panel.add_child(dice_vbox)

	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 16)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_vbox.add_child(result_label)

	outcome_label = RichTextLabel.new()
	outcome_label.custom_minimum_size = Vector2(0, 50)
	outcome_label.bbcode_enabled = true
	outcome_label.fit_content = true
	outcome_label.scroll_active = false
	dice_vbox.add_child(outcome_label)

	main_vbox.add_child(HSeparator.new())

	# Action buttons
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(action_hbox)

	print("WoundAllocationOverlay: _build_ui() [STEP 6] Creating continue_button...")
	continue_button = Button.new()
	print("WoundAllocationOverlay: _build_ui() [STEP 7] continue_button created: ", continue_button)
	continue_button.text = "Continue Now"
	continue_button.disabled = true
	continue_button.pressed.connect(_on_continue_pressed)
	action_hbox.add_child(continue_button)
	print("WoundAllocationOverlay: _build_ui() [STEP 8] continue_button added to tree")

	print("██████████████████████████████████████████████████████")
	print("██████ WoundAllocationOverlay._build_ui() COMPLETE ██████")
	print("██████████████████████████████████████████████████████")
	print("WoundAllocationOverlay: _build_ui() FINAL VERIFICATION:")
	print("  - overlay_panel: ", overlay_panel)
	print("  - attack_info_label: ", attack_info_label)
	print("  - status_label: ", status_label)
	print("  - target_info_label: ", target_info_label)
	print("  - save_info_label: ", save_info_label)
	print("  - instruction_label: ", instruction_label)
	print("  - dice_result_panel: ", dice_result_panel)
	print("  - result_label: ", result_label)
	print("  - outcome_label: ", outcome_label)
	print("  - continue_button: ", continue_button)
	print("██████████████████████████████████████████████████████")

func setup(p_save_data: Dictionary, p_defender_player: int) -> void:
	"""Initialize the overlay with save data"""
	push_warning("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")
	push_warning("◆◆◆ WoundAllocationOverlay.setup() CALLED ◆◆◆")
	push_warning("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")
	print("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")
	print("◆◆◆ WoundAllocationOverlay.setup() CALLED ◆◆◆")
	print("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")

	# CRITICAL: Ensure UI exists before doing anything else
	print("WoundAllocationOverlay: [SETUP STEP 0] Ensuring UI is built...")
	_ensure_ui_built()

	print("WoundAllocationOverlay: [SETUP STEP 1] Initial state:")
	print("  - Visibility: ", visible)
	print("  - Modulate: ", modulate)
	print("  - In tree: ", is_inside_tree())
	print("  - Size: ", size)
	print("  - Global position: ", global_position)

	print("WoundAllocationOverlay: [SETUP STEP 1.5] VERIFYING UI nodes exist:")
	print("  - overlay_panel is null: ", overlay_panel == null)
	print("  - attack_info_label is null: ", attack_info_label == null)
	print("  - dice_result_panel is null: ", dice_result_panel == null)
	print("  - continue_button is null: ", continue_button == null)
	print("  - status_label is null: ", status_label == null)
	print("  - result_label is null: ", result_label == null)
	print("  - outcome_label is null: ", outcome_label == null)

	# WARNING (not fatal) if UI still doesn't exist - but let's try to continue anyway
	if overlay_panel == null or dice_result_panel == null or continue_button == null:
		push_error("WoundAllocationOverlay: ⚠ WARNING - Some UI nodes are null after _ensure_ui_built()!")
		push_error("  - overlay_panel null: %s" % (overlay_panel == null))
		push_error("  - dice_result_panel null: %s" % (dice_result_panel == null))
		push_error("  - continue_button null: %s" % (continue_button == null))
		push_error("  - Attempting to continue anyway - expect errors!")
		# DON'T return - let it try to continue

	save_data = p_save_data
	defender_player = p_defender_player
	total_wounds = save_data.get("wounds_to_save", 0)
	current_wound_index = 0
	allocation_history.clear()

	print("WoundAllocationOverlay: [SETUP STEP 2] Save data loaded:")
	print("  - Total wounds: ", total_wounds)
	print("  - Defender player: ", defender_player)
	print("  - Save data keys: ", save_data.keys())

	print("WoundAllocationOverlay: [SETUP STEP 3] Creating RNG service...")
	# Initialize RNG service
	rng_service = RulesEngine.RNGService.new()
	print("WoundAllocationOverlay: [SETUP STEP 4] RNG service created")

	# Get target unit
	var target_unit_id = save_data.get("target_unit_id", "")
	print("WoundAllocationOverlay: [SETUP STEP 5] Target unit ID: ", target_unit_id)
	target_unit = GameState.get_unit(target_unit_id)

	if target_unit.is_empty():
		push_error("WoundAllocationOverlay: Target unit not found: " + target_unit_id)
		print("WoundAllocationOverlay: [SETUP STEP 6] ERROR - Target unit is empty!")
		return

	print("WoundAllocationOverlay: [SETUP STEP 6] Target unit found: ", target_unit.get("meta", {}).get("name", target_unit_id))
	print("WoundAllocationOverlay: [SETUP STEP 7] Starting allocation for %d wounds" % total_wounds)

	print("WoundAllocationOverlay: [SETUP STEP 8] Setting visible=true and calling show()...")
	# Ensure overlay is visible
	visible = true
	show()
	print("WoundAllocationOverlay: [SETUP STEP 9] After show(), visible: ", visible)

	print("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")
	print("◆◆◆ WoundAllocationOverlay.setup() STATE ◆◆◆")
	print("  - Visibility: ", visible)
	print("  - In tree: ", is_inside_tree())
	print("  - Z-index: ", z_index)
	print("  - Position: ", position)
	print("  - Global position: ", global_position)
	print("  - Size: ", size)
	print("  - Rect: ", get_rect())
	print("  - Input processing: ", is_processing_input())
	print("  - Awaiting selection: ", awaiting_selection)
	print("  - Modulate: ", modulate)
	print("  - Parent: ", get_parent().name if get_parent() else "NO PARENT")
	print("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")

	print("WoundAllocationOverlay: [SETUP STEP 12] Starting wound allocation...")
	# Start first allocation
	_start_wound_allocation()
	print("WoundAllocationOverlay: [SETUP STEP 13] _start_wound_allocation() returned")
	print("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")
	print("◆◆◆ WoundAllocationOverlay.setup() COMPLETE ◆◆◆")
	print("◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆")

func _start_wound_allocation() -> void:
	"""Begin allocation for current_wound_index"""
	awaiting_selection = true

	# Update UI labels
	_update_ui_for_current_wound()

	# Highlight valid models on board
	_highlight_valid_models()

	# Enable input
	set_process_input(true)

	print("WoundAllocationOverlay: Wound allocation started - awaiting input")
	print("  - Overlay visible: ", visible)
	print("  - Overlay in tree: ", is_inside_tree())
	print("  - Overlay z_index: ", z_index)
	print("  - Panel visible: ", overlay_panel.visible if overlay_panel else "panel is null")
	print("  - Status label text: ", status_label.text if status_label else "label is null")

func _update_ui_for_current_wound() -> void:
	"""Update UI to show current wound status"""
	print("▓▓▓ WoundAllocationOverlay._update_ui_for_current_wound() START ▓▓▓")
	print("  - attack_info_label null: ", attack_info_label == null)
	print("  - status_label null: ", status_label == null)
	print("  - target_info_label null: ", target_info_label == null)
	print("  - save_info_label null: ", save_info_label == null)
	print("  - instruction_label null: ", instruction_label == null)

	# Attack info
	var weapon_name = save_data.get("weapon_name", "Unknown Weapon")
	var ap = save_data.get("ap", 0)
	var damage = save_data.get("damage", 1)
	var shooter_name = save_data.get("shooter_unit_id", "Unknown")

	if attack_info_label:
		attack_info_label.text = "⚔ %s (AP%d, D%d)" % [weapon_name, ap, damage]
		print("  - Set attack_info_label.text: ", attack_info_label.text)
	else:
		push_error("WoundAllocationOverlay: attack_info_label is NULL in _update_ui_for_current_wound!")

	# Status
	if status_label:
		status_label.text = "Wound %d of %d" % [current_wound_index + 1, total_wounds]
		print("  - Set status_label.text: ", status_label.text)
	else:
		push_error("WoundAllocationOverlay: status_label is NULL in _update_ui_for_current_wound!")

	# Target info
	var alive_count = 0
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			alive_count += 1

	target_info_label.text = "Target: %s (%d models alive)" % [target_unit.get("meta", {}).get("name", "Unknown"), alive_count]

	# Save info
	var example_profile = save_data.get("model_save_profiles", [])[0] if not save_data.get("model_save_profiles", []).is_empty() else {}
	var save_needed = example_profile.get("save_needed", 7)
	var using_invuln = example_profile.get("using_invuln", false)
	var has_cover = example_profile.get("has_cover", false)

	var save_text = "[b]Save Required:[/b] %d+" % save_needed
	if using_invuln:
		save_text += " (invulnerable)"
	if has_cover:
		save_text += " [+1 from cover]"

	save_info_label.text = save_text

	# Instructions
	var wounded_models = _get_wounded_models()
	if not wounded_models.is_empty():
		instruction_label.text = "[center][b]⚠ PRIORITY TARGET ⚠[/b]\n[color=red]Must select wounded model first![/color]\nClick on the [color=red][b]RED PULSING[/b][/color] model on the board[/center]"
	else:
		instruction_label.text = "[center][b]Click on a model to allocate this wound[/b]\nClick any [color=green][b]GREEN[/b][/color] highlighted model on the board[/center]"

	# Hide dice result
	dice_result_panel.visible = false

func _highlight_valid_models() -> void:
	"""Add visual highlights to models based on allocation rules"""
	if not board_highlighter:
		return

	board_highlighter.clear_all()

	var wounded_models = _get_wounded_models()
	var all_models = target_unit.get("models", [])

	for i in range(all_models.size()):
		var model = all_models[i]
		var model_id = model.get("id", "m%d" % i)
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.ZERO:
			continue

		var base_mm = model.get("base_mm", 32)

		# NEW: Mark dead models with gray X overlay
		if not model.get("alive", true):
			board_highlighter.create_highlight(
				model_pos, base_mm,
				WoundAllocationBoardHighlights.HighlightType.DEAD,
				model_id
			)
			continue

		# Highlight alive models
		if model_id in wounded_models:
			# MUST SELECT - Red pulsing highlight
			board_highlighter.create_highlight(
				model_pos, base_mm,
				WoundAllocationBoardHighlights.HighlightType.PRIORITY,
				model_id
			)
		elif wounded_models.is_empty():
			# CAN SELECT - Green highlight (only if no wounded models)
			board_highlighter.create_highlight(
				model_pos, base_mm,
				WoundAllocationBoardHighlights.HighlightType.SELECTABLE,
				model_id
			)

func _input(event: InputEvent) -> void:
	if not awaiting_selection:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("WoundAllocationOverlay: Mouse click detected during wound allocation!")
		print("  - Event position: ", event.position)
		print("  - Awaiting selection: ", awaiting_selection)

		# Convert screen click to board position
		if not board_view:
			print("WoundAllocationOverlay: ERROR - board_view is null!")
			return

		var click_pos = board_view.get_local_mouse_position()
		print("  - Board local position: ", click_pos)

		var clicked_model_id = _find_model_at_position(click_pos)
		print("  - Clicked model ID: ", clicked_model_id if clicked_model_id != "" else "NONE")

		if clicked_model_id != "":
			_on_model_clicked(clicked_model_id)
			accept_event()  # Consume the event
		else:
			print("WoundAllocationOverlay: No model found at click position")

func _on_model_clicked(model_id: String) -> void:
	"""Handle defender clicking a model"""
	print("WoundAllocationOverlay: Model clicked: %s" % model_id)

	# Validate selection
	if not _is_valid_selection(model_id):
		_show_error_flash("Must select wounded model first!")
		return

	awaiting_selection = false
	set_process_input(false)

	# Get model data
	var model = _get_model_by_id(model_id)
	if model.is_empty():
		push_error("WoundAllocationOverlay: Model not found: " + model_id)
		return

	# Flash selected model
	var model_pos = _get_model_position(model)
	if model_pos != Vector2.ZERO:
		board_highlighter.create_highlight(
			model_pos, model.get("base_mm", 32),
			WoundAllocationBoardHighlights.HighlightType.SELECTED
		)

	# Emit signal for multiplayer sync (future)
	emit_signal("wound_allocated", model_id, current_wound_index)

	# Roll save immediately
	_roll_save_for_model(model_id)

func _roll_save_for_model(model_id: String) -> void:
	"""Roll save and apply damage, with Feel No Pain if applicable"""
	print("WoundAllocationOverlay: Rolling save for model: %s" % model_id)

	# Find model profile
	var save_profile = _get_model_save_profile(model_id)
	if save_profile.is_empty():
		push_error("WoundAllocationOverlay: Save profile not found for model: " + model_id)
		return

	# Roll save
	var roll = rng_service.roll_d6(1)[0]
	var needed = save_profile.get("save_needed", 7)
	var saved = roll >= needed

	print("WoundAllocationOverlay: Save roll: %d vs %d+ = %s" % [roll, needed, "SAVED" if saved else "FAILED"])

	# FNP and damage tracking
	var weapon_damage = save_data.get("damage", 1)
	var actual_damage = 0
	var fnp_rolls_data = []
	var fnp_prevented = 0
	var fnp_val = 0
	var model_destroyed = false

	if not saved:
		actual_damage = weapon_damage

		# FEEL NO PAIN: Roll FNP for each point of damage
		fnp_val = RulesEngine.get_unit_fnp(target_unit)
		if fnp_val > 0 and rng_service != null:
			var fnp_result = RulesEngine.roll_feel_no_pain(weapon_damage, fnp_val, rng_service)
			fnp_rolls_data = fnp_result.rolls
			fnp_prevented = fnp_result.wounds_prevented
			actual_damage = fnp_result.wounds_remaining
			print("WoundAllocationOverlay: FNP %d+ — rolled %s, prevented %d/%d wounds" % [fnp_val, str(fnp_rolls_data), fnp_prevented, weapon_damage])

		# Check if model is destroyed using actual damage after FNP
		var current_wounds = save_profile.get("current_wounds", 1)
		if actual_damage >= current_wounds:
			model_destroyed = true

	# Build result
	var result = {
		"wound_index": current_wound_index,
		"model_id": model_id,
		"model_index": save_profile.get("model_index", 0),
		"roll": roll,
		"needed": needed,
		"saved": saved,
		"damage": actual_damage,
		"model_destroyed": model_destroyed,
		"fnp_rolls": fnp_rolls_data,
		"fnp_value": fnp_val,
		"fnp_prevented": fnp_prevented,
		"actual_damage": actual_damage,
		"weapon_damage": weapon_damage
	}

	allocation_history.append(result)

	# Emit signal for multiplayer sync (future)
	emit_signal("save_rolled", result)

	# Display result in UI
	_display_save_result(result)

	# Apply damage immediately (using actual damage after FNP)
	if not saved and actual_damage > 0:
		_apply_damage_to_model(model_id, save_profile.get("model_index", 0), actual_damage, model_destroyed)

	# Enable continue button
	print("WoundAllocationOverlay: Attempting to enable continue button")
	print("  - continue_button is null: ", continue_button == null)
	if continue_button == null:
		push_error("WoundAllocationOverlay: continue_button is null!")
	else:
		continue_button.disabled = false
		print("WoundAllocationOverlay: Continue button enabled")

	# Auto-advance after delay
	await get_tree().create_timer(1.5).timeout

	if is_inside_tree():  # Check still valid after timer
		_continue_to_next_wound()

func _display_save_result(result: Dictionary) -> void:
	"""Show dice result in overlay"""
	print("WoundAllocationOverlay: _display_save_result() called")
	print("  - dice_result_panel is null: ", dice_result_panel == null)
	print("  - result_label is null: ", result_label == null)
	print("  - outcome_label is null: ", outcome_label == null)

	# CRITICAL FIX: Ensure UI is built before trying to use it
	if dice_result_panel == null or result_label == null or outcome_label == null:
		push_error("WoundAllocationOverlay: UI nodes are null in _display_save_result! Attempting to build UI now...")
		_ensure_ui_built()

		# Check again after ensuring UI is built
		if dice_result_panel == null:
			push_error("WoundAllocationOverlay: dice_result_panel is STILL null after _ensure_ui_built!")
			return
		if result_label == null:
			push_error("WoundAllocationOverlay: result_label is STILL null after _ensure_ui_built!")
			return
		if outcome_label == null:
			push_error("WoundAllocationOverlay: outcome_label is STILL null after _ensure_ui_built!")
			return

	dice_result_panel.visible = true

	result_label.text = "🎲 %d vs %d+" % [result.get("roll", 0), result.get("needed", 7)]

	var saved = result.get("saved", false)
	var outcome_text = ""

	if saved:
		outcome_text = "[center][color=green][b]✓ SAVED[/b][/color][/center]"
	else:
		outcome_text = "[center][color=red][b]✗ FAILED[/b][/color]\n"

		# FEEL NO PAIN: Show FNP rolls if applicable
		var fnp_rolls = result.get("fnp_rolls", [])
		var fnp_val = result.get("fnp_value", 0)
		var fnp_prevented = result.get("fnp_prevented", 0)
		var actual_dmg = result.get("actual_damage", result.get("damage", 1))
		var weapon_dmg = result.get("weapon_damage", result.get("damage", 1))

		if fnp_val > 0 and not fnp_rolls.is_empty():
			# Show FNP dice rolls
			var fnp_dice_str = ""
			for fnp_roll in fnp_rolls:
				if fnp_roll >= fnp_val:
					fnp_dice_str += "[color=green]%d[/color] " % fnp_roll
				else:
					fnp_dice_str += "[color=red]%d[/color] " % fnp_roll
			outcome_text += "[color=cyan]Feel No Pain %d+:[/color] %s\n" % [fnp_val, fnp_dice_str.strip_edges()]

			if fnp_prevented > 0:
				outcome_text += "[color=green]%d wound(s) prevented![/color]\n" % fnp_prevented

			if actual_dmg == 0:
				outcome_text += "[color=green][b]All damage prevented by FNP![/b][/color]"
			else:
				outcome_text += "%s takes %d damage (reduced from %d)" % [result.get("model_id", "Unknown"), actual_dmg, weapon_dmg]
		else:
			outcome_text += "%s takes %d damage" % [result.get("model_id", "Unknown"), actual_dmg]

		if result.get("model_destroyed", false):
			outcome_text += "\n[color=red][b]💀 DESTROYED[/b][/color]"
		outcome_text += "[/center]"

	outcome_label.text = outcome_text
	print("WoundAllocationOverlay: _display_save_result() completed successfully")

func _apply_damage_to_model(model_id: String, model_index: int, damage: int, destroyed: bool) -> void:
	"""Apply damage to the model in GameState and trigger visual update"""
	print("╔═══════════════════════════════════════════════════════════")
	print("║ WoundAllocationOverlay._apply_damage_to_model() CALLED")
	print("║ model_id: ", model_id)
	print("║ model_index: ", model_index)
	print("║ damage: ", damage)
	print("║ destroyed: ", destroyed)
	print("╚═══════════════════════════════════════════════════════════")

	var target_unit_id = save_data.get("target_unit_id", "")
	print("WoundAllocationOverlay: target_unit_id = ", target_unit_id)

	# Update GameState directly (in single-player)
	var models = target_unit.get("models", [])
	print("WoundAllocationOverlay: Unit has %d models" % models.size())

	if model_index >= 0 and model_index < models.size():
		var model = models[model_index]
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var new_wounds = max(0, current_wounds - damage)

		print("WoundAllocationOverlay: Model current_wounds: %d → %d" % [current_wounds, new_wounds])

		# Update model in GameState
		GameState.state.units[target_unit_id].models[model_index].current_wounds = new_wounds
		print("WoundAllocationOverlay: Updated GameState current_wounds")

		if destroyed:
			GameState.state.units[target_unit_id].models[model_index].alive = false
			print("╔═══════════════════════════════════════════════════════════")
			print("║ 💀 MODEL DESTROYED - alive set to false in GameState")
			print("║ model_id: ", model_id)
			print("║ model.alive before: ", model.get("alive", true))
			print("║ model.alive after: ", GameState.state.units[target_unit_id].models[model_index].alive)
			print("╚═══════════════════════════════════════════════════════════")

			# VISUAL FEEDBACK: Show death animation
			print("WoundAllocationOverlay: Calling _show_model_death_effect()...")
			_show_model_death_effect(model_id, model)
			print("WoundAllocationOverlay: _show_model_death_effect() returned")
		else:
			print("WoundAllocationOverlay: Model damaged but not destroyed")
			# VISUAL FEEDBACK: Show damage effect
			_show_model_damage_effect(model_id, model, new_wounds)

		# Trigger board redraw to update model visuals
		print("WoundAllocationOverlay: Calling _refresh_board_visuals()...")
		_refresh_board_visuals()
		print("WoundAllocationOverlay: _refresh_board_visuals() returned")
	else:
		print("WoundAllocationOverlay: ERROR - model_index %d out of range (0-%d)" % [model_index, models.size() - 1])

func _show_model_death_effect(model_id: String, model: Dictionary) -> void:
	"""Show visual effect when a model dies"""
	print("╔══════════════════════════════════════════════════════════════════")
	print("║ _show_model_death_effect() CALLED")
	print("║ model_id: ", model_id)
	print("║ model keys: ", model.keys())
	print("╚══════════════════════════════════════════════════════════════════")

	print("WoundAllocationOverlay: Checking board_highlighter...")
	print("  - board_highlighter is null: ", board_highlighter == null)
	print("  - board_highlighter is valid: ", is_instance_valid(board_highlighter) if board_highlighter != null else "N/A")

	if not board_highlighter:
		push_error("WoundAllocationOverlay: ❌ CRITICAL - board_highlighter is null! Death marker cannot be created!")
		return

	var model_pos = _get_model_position(model)
	print("WoundAllocationOverlay: Model position: ", model_pos)

	if model_pos == Vector2.ZERO:
		push_error("WoundAllocationOverlay: ❌ CRITICAL - model_pos is Vector2.ZERO! Cannot create death marker at invalid position!")
		return

	var base_mm = model.get("base_mm", 32)
	print("WoundAllocationOverlay: Model base_mm: ", base_mm)

	# ENHANCEMENT 1: Create persistent death marker (red circle)
	print("╔══════════════════════════════════════════════════════════════════")
	print("║ CREATING DEATH MARKER")
	print("║ Position: ", model_pos)
	print("║ Base size: ", base_mm, "mm")
	print("║ Model ID: ", model_id)
	print("╚══════════════════════════════════════════════════════════════════")

	board_highlighter.create_death_marker(
		model_pos,
		base_mm,
		model_id
	)
	print("WoundAllocationOverlay: ✅ create_death_marker() call completed")

	# ENHANCEMENT 2: Flash effect (yellow, temporary)
	print("╔══════════════════════════════════════════════════════════════════")
	print("║ Creating YELLOW FLASH (for comparison with death marker)")
	print("╚══════════════════════════════════════════════════════════════════")
	print("WoundAllocationOverlay: Creating yellow flash effect...")
	print("  - Position: ", model_pos)
	print("  - Base size: ", base_mm)
	print("  - Type: SELECTED (yellow)")
	board_highlighter.create_highlight(
		model_pos,
		base_mm,
		WoundAllocationBoardHighlights.HighlightType.SELECTED  # Yellow flash
	)
	print("WoundAllocationOverlay: ✅ Flash effect created")
	print("WoundAllocationOverlay: ⚠ QUESTION: Can you see a YELLOW FLASH on screen? (This uses the same system as death markers)")

	# ENHANCEMENT 3: Trigger board to hide the model token
	print("WoundAllocationOverlay: Calling _hide_destroyed_model_token()...")
	_hide_destroyed_model_token(model_id)
	print("WoundAllocationOverlay: ✅ _hide_destroyed_model_token() returned")

	print("╔══════════════════════════════════════════════════════════════════")
	print("║ ✅ 💀 MODEL DEATH EFFECT COMPLETE")
	print("║ Model %s destroyed - marker created, token hidden" % model_id)
	print("╚══════════════════════════════════════════════════════════════════")

func _show_model_damage_effect(model_id: String, model: Dictionary, new_wounds: int) -> void:
	"""Show visual effect when a model takes damage"""
	if not board_highlighter:
		return

	var model_pos = _get_model_position(model)
	if model_pos == Vector2.ZERO:
		return

	# Flash the model briefly to show damage taken
	var max_wounds = model.get("wounds", 1)
	var wound_percentage = float(new_wounds) / float(max_wounds)

	# Color based on remaining wounds (red = low, yellow = medium, green = high)
	var flash_color = Color(1.0, wound_percentage, 0.0, 0.7)  # Red to yellow gradient

	print("WoundAllocationOverlay: ⚡ Model %s took damage - %d/%d wounds remaining" % [model_id, new_wounds, max_wounds])

func _hide_destroyed_model_token(model_id: String) -> void:
	"""Hide the visual token for a destroyed model"""
	print("╔══════════════════════════════════════════════════════════════════")
	print("║ _hide_destroyed_model_token() CALLED")
	print("║ model_id: ", model_id)
	print("╚══════════════════════════════════════════════════════════════════")

	# Get Main node which manages model visuals
	var main = get_node_or_null("/root/Main")
	print("WoundAllocationOverlay: Main node lookup...")
	print("  - main is null: ", main == null)

	if not main:
		push_error("WoundAllocationOverlay: ❌ CRITICAL - Main node not found! Cannot hide token!")
		return

	# Signal Main to update visuals for this unit
	var target_unit_id = save_data.get("target_unit_id", "")
	print("WoundAllocationOverlay: target_unit_id: ", target_unit_id)
	print("WoundAllocationOverlay: Checking if Main has update_unit_visuals method...")
	print("  - main.has_method('update_unit_visuals'): ", main.has_method("update_unit_visuals"))

	if main.has_method("update_unit_visuals"):
		print("WoundAllocationOverlay: ✅ Calling Main.update_unit_visuals(", target_unit_id, ")...")
		main.update_unit_visuals(target_unit_id)
		print("WoundAllocationOverlay: ✅ Main.update_unit_visuals() returned")
	else:
		print("WoundAllocationOverlay: ⚠ update_unit_visuals method not found, using fallback...")
		# Fallback: full board redraw
		var board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
		print("  - board_view is null: ", board_view == null)
		if board_view:
			print("WoundAllocationOverlay: Calling board_view.queue_redraw()...")
			board_view.queue_redraw()
			print("WoundAllocationOverlay: ✅ board_view.queue_redraw() called")
		else:
			push_error("WoundAllocationOverlay: ❌ CRITICAL - BoardView not found! Cannot redraw board!")

func _refresh_board_visuals() -> void:
	"""Trigger board to refresh model visuals after damage"""
	if not board_view:
		return

	# Force board redraw to show/hide models based on alive status
	if board_view.has_method("queue_redraw"):
		board_view.queue_redraw()
		print("WoundAllocationOverlay: Triggered board visual refresh")

	# Also notify Main to update model tokens
	var main = get_node_or_null("/root/Main")
	if main and main.has_method("refresh_all_model_visuals"):
		main.refresh_all_model_visuals()

	# Refresh target unit reference to get latest state
	var target_unit_id = save_data.get("target_unit_id", "")
	target_unit = GameState.get_unit(target_unit_id)

func _continue_to_next_wound() -> void:
	"""Move to next wound or complete allocation"""
	print("WoundAllocationOverlay: _continue_to_next_wound() called")

	if continue_button != null:
		continue_button.disabled = true
	if dice_result_panel != null:
		dice_result_panel.visible = false

	current_wound_index += 1

	if current_wound_index >= total_wounds:
		_complete_allocation()
	else:
		_start_wound_allocation()

func _on_continue_pressed() -> void:
	"""Handle Continue Now button press"""
	_continue_to_next_wound()

func _complete_allocation() -> void:
	"""All wounds allocated - show summary"""
	print("WoundAllocationOverlay: Allocation complete!")

	var summary = _build_summary()
	emit_signal("allocation_complete", summary)

	# Show summary in UI
	_display_summary(summary)

	# Auto-close after 2s
	await get_tree().create_timer(2.0).timeout
	_close()

func _display_summary(summary: Dictionary) -> void:
	"""Display allocation summary"""
	instruction_label.text = "[center][b]Allocation Complete![/b][/center]"

	var summary_text = "[center]"
	summary_text += "[b]Total Wounds:[/b] %d\n" % summary.get("total_wounds", 0)
	summary_text += "[color=green]Saves Passed:[/color] %d\n" % summary.get("saves_passed", 0)
	summary_text += "[color=red]Saves Failed:[/color] %d\n" % summary.get("saves_failed", 0)
	summary_text += "[b]Damage Dealt:[/b] %d\n" % summary.get("total_damage", 0)
	summary_text += "[color=red]Models Destroyed:[/color] %d" % summary.get("models_destroyed", 0)
	summary_text += "[/center]"

	save_info_label.text = summary_text
	dice_result_panel.visible = false
	status_label.visible = false
	target_info_label.visible = false

func _build_summary() -> Dictionary:
	"""Build allocation summary"""
	var passed = 0
	var failed = 0
	var total_damage = 0
	var destroyed = 0

	for entry in allocation_history:
		if entry.get("saved", false):
			passed += 1
		else:
			failed += 1
			total_damage += entry.get("damage", 0)
			if entry.get("model_destroyed", false):
				destroyed += 1

	return {
		"total_wounds": total_wounds,
		"saves_passed": passed,
		"saves_failed": failed,
		"total_damage": total_damage,
		"models_destroyed": destroyed,
		"allocation_history": allocation_history
	}

func _close() -> void:
	"""Clean up and close overlay"""
	print("WoundAllocationOverlay: Closing")

	# Clear board highlights
	if board_highlighter and is_instance_valid(board_highlighter):
		board_highlighter.clear_all()
		board_highlighter.queue_free()

	# Remove from tree
	queue_free()

# Helper functions

func _is_valid_selection(model_id: String) -> bool:
	"""Check if model can be selected per 10e rules"""
	var wounded_models = _get_wounded_models()

	# If there are wounded models, MUST select one of them
	if not wounded_models.is_empty():
		return model_id in wounded_models

	# Otherwise, any alive model is valid
	var model = _get_model_by_id(model_id)
	return model.get("alive", true) if not model.is_empty() else false

func _get_wounded_models() -> Array:
	"""Return array of model_ids that have lost wounds"""
	var wounded = []
	var models = target_unit.get("models", [])

	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue

		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var max_wounds = model.get("wounds", 1)

		if current_wounds < max_wounds:
			wounded.append(model.get("id", "m%d" % i))

	return wounded

func _find_model_at_position(click_pos: Vector2) -> String:
	"""Find which model was clicked based on position"""
	var models = target_unit.get("models", [])
	var closest_model_id = ""
	var closest_distance = INF

	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == Vector2.ZERO:
			continue

		var base_mm = model.get("base_mm", 32)
		var base_radius_px = Measurement.base_radius_px(base_mm)

		# Generous click radius (base + 50px for easier selection)
		var click_radius = base_radius_px + 50

		var distance = model_pos.distance_to(click_pos)

		if distance <= click_radius and distance < closest_distance:
			closest_distance = distance
			closest_model_id = model.get("id", "m%d" % i)

	return closest_model_id

func _get_model_by_id(model_id: String) -> Dictionary:
	"""Get model data by ID"""
	var models = target_unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id:
			return model
	return {}

func _get_model_save_profile(model_id: String) -> Dictionary:
	"""Get save profile for model"""
	var profiles = save_data.get("model_save_profiles", [])
	for profile in profiles:
		if profile.get("model_id", "") == model_id:
			return profile
	return {}

func _get_model_position(model: Dictionary) -> Vector2:
	"""Get model position as Vector2"""
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _show_error_flash(message: String) -> void:
	"""Show error message briefly"""
	instruction_label.text = "[center][color=red][b]" + message + "[/b][/color][/center]"
	await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		_update_ui_for_current_wound()
