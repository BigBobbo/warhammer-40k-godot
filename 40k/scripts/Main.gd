extends CanvasLayer
# Use global class_name references instead of preloads to avoid web export reload issues
# GameStateData, BasePhase, ShootingPhase, NetworkIntegration are available via class_name
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

@onready var camera: Camera2D = $BoardRoot/Camera2D
@onready var board_view: Node2D = $BoardRoot/BoardView
@onready var deployment_zones: Node2D = $BoardRoot/DeploymentZones
@onready var p1_zone: Polygon2D = $BoardRoot/DeploymentZones/P1Zone
@onready var p2_zone: Polygon2D = $BoardRoot/DeploymentZones/P2Zone
@onready var token_layer: Node2D = $BoardRoot/TokenLayer
@onready var ghost_layer: Node2D = $BoardRoot/GhostLayer

@onready var phase_label: Label = $HUD_Bottom/HBoxContainer/PhaseLabel
@onready var active_player_badge: Label = $HUD_Bottom/HBoxContainer/ActivePlayerBadge
@onready var status_label: Label = $HUD_Bottom/HBoxContainer/StatusLabel
@onready var phase_action_button: Button = $HUD_Bottom/HBoxContainer/PhaseActionButton

@onready var unit_list: ItemList = $HUD_Right/VBoxContainer/UnitListPanel
@onready var unit_card: VBoxContainer = $HUD_Right/VBoxContainer/UnitCard
@onready var unit_name_label: Label = $HUD_Right/VBoxContainer/UnitCard/UnitNameLabel
@onready var keywords_label: Label = $HUD_Right/VBoxContainer/UnitCard/KeywordsLabel
@onready var models_label: Label = $HUD_Right/VBoxContainer/UnitCard/ModelsLabel
@onready var undo_button: Button = $HUD_Right/VBoxContainer/UnitCard/ButtonContainer/UndoButton
@onready var reset_button: Button = $HUD_Right/VBoxContainer/UnitCard/ButtonContainer/ResetButton
@onready var confirm_button: Button = $HUD_Right/VBoxContainer/UnitCard/ButtonContainer/ConfirmButton

var unit_stats_panel: Control
var left_panel_toggle_button: Button
var is_left_panel_visible: bool = false
var mathhammer_ui: Control
var save_load_dialog: AcceptDialog
var deployment_controller: Node
var coherency_banner: PanelContainer = null
var command_controller: Node
var movement_controller: Node
var shooting_controller: Node
var charge_controller: Node
var fight_controller: Node
var scoring_controller: Node
var current_phase: GameStateData.Phase
var view_offset: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0

# Deployment progress indicator UI elements
var deployment_progress_container: PanelContainer
var p1_progress_bar: ProgressBar
var p2_progress_bar: ProgressBar
var p1_progress_label: Label
var p2_progress_label: Label

# Strategic Reserves / Deep Strike UI elements
var reserves_button: Button = null
var reinforcements_button: Button = null
var _selected_unit_for_reserves: String = ""

# Game Event Log UI elements
var game_log_panel: PanelContainer
var game_log_label: RichTextLabel
var game_log_scroll: ScrollContainer
var is_game_log_visible: bool = true
var game_log_toggle_button: Button

func _ready() -> void:
	# DEBUG: Check current state before any initialization
	print("Main: _ready() called")
	print("Main: DebugLogger log file path: ", DebugLogger.get_real_log_file_path())
	DebugLogger.info("Main._ready() called", {})
	print("Main: Current units count BEFORE check: ", GameState.state.get("units", {}).size())
	if GameState.state.get("units", {}).size() > 0:
		print("Main: Unit IDs in GameState: ", GameState.state.units.keys())
	if GameState.state.has("meta"):
		print("Main: Meta flags: ", GameState.state.meta.keys())
		if GameState.state.meta.has("game_config"):
			print("Main: Game config: ", GameState.state.meta.game_config)

	# Check if we're coming from main menu, multiplayer lobby, or loading a save
	var from_menu = GameState.state.meta.has("from_menu") if GameState.state.has("meta") else false
	var from_save = GameState.state.meta.has("from_save") if GameState.state.has("meta") else false
	var from_multiplayer = GameState.state.meta.has("from_multiplayer_lobby") if GameState.state.has("meta") else false

	print("Main: from_menu=", from_menu, " from_save=", from_save, " from_multiplayer=", from_multiplayer)

	if not from_menu and not from_save and not from_multiplayer:
		# Legacy path: direct load for testing
		print("Main: ❌ Direct load detected, initializing default state")
		GameState.initialize_default_state()
		print("Main: Units after initialize_default_state: ", GameState.state.units.size())
	else:
		if from_menu:
			print("Main: ✓ Loading from main menu with configuration")
		elif from_save:
			print("Main: ✓ Loading from saved game")
		elif from_multiplayer:
			print("Main: ✓ Loading from multiplayer lobby with armies already loaded")
			print("Main: Units count AFTER multiplayer check: ", GameState.state.units.size())

			# Initialize web relay mode for multiplayer
			var from_web_lobby = GameState.state.meta.get("from_web_lobby", false)
			if from_web_lobby:
				var is_host = GameState.state.meta.get("is_host", false)
				var game_code = GameState.state.meta.get("game_code", "")
				print("Main: Initializing web relay mode (is_host=%s, code=%s)" % [is_host, game_code])

				if NetworkManager:
					NetworkManager.enter_web_relay_mode(is_host, game_code)

					# If host, send initial state to guest after a short delay
					if is_host:
						await get_tree().create_timer(0.5).timeout
						print("Main: Host sending initial state to guest")
						NetworkManager.send_initial_state_via_relay()
				else:
					push_error("Main: NetworkManager not available for web relay mode")
	
	# Initialize view to show whole board
	view_zoom = 0.3
	view_offset = Vector2(0, 0)  # Start at top-left
	update_view_transform()

	# Initialize PhaseManager with deployment phase NOW that armies are loaded
	var phase_manager = get_node("/root/PhaseManager")
	if phase_manager and not phase_manager.current_phase_instance:
		print("Main: Initializing deployment phase with ", GameState.state.units.size(), " units")
		phase_manager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)

		# DEBUG: Verify phase was created correctly
		await get_tree().process_frame
		var phase_inst = phase_manager.get_current_phase_instance()
		if phase_inst:
			print("Main: Phase instance created - class: ", phase_inst.get_class())
			print("Main: Phase instance script: ", phase_inst.get_script())
			print("Main: Phase has validate_action: ", phase_inst.has_method("validate_action"))
		else:
			print("Main: ERROR - No phase instance after transition!")

	# Camera controls: WASD/arrows to pan, +/- to zoom, F to focus on Player 2 zone

	board_view.queue_redraw()
	setup_deployment_zones()

	# Setup objectives on the board
	_setup_objectives()

	# Move HUD_Bottom to top and create stats panel at bottom
	_restructure_ui_layout()

	# Fix HUD layout to prevent overlap
	_fix_hud_layout()

	# Setup Mathhammer UI
	_setup_mathhammer_ui()

	# Setup Save/Load Dialog
	_setup_save_load_dialog()

	# Setup Terrain
	_setup_terrain()

	# Setup Measuring Tape
	_setup_measuring_tape()

	# Setup Transport Panel
	_setup_transport_panel()

	# Setup left panel toggle and hide by default
	_setup_left_panel_toggle()
	_hide_left_panel()

	# Setup phase-specific controllers based on current phase
	current_phase = GameState.get_current_phase()
	await setup_phase_controllers()

	# Connect signals BEFORE initializing AI so that phase_changed events
	# update the UI as the AI plays through phases
	connect_signals()
	refresh_unit_list()
	update_ui()

	# Initialize AI Player AFTER signals are connected so UI updates during AI play
	_initialize_ai_player()

	# CRITICAL FIX: Must call update_ui_for_phase() to properly configure the phase action button
	# This sets the correct button text and connects the signal handler
	print("Main: ⚠️ Calling update_ui_for_phase() for initial phase setup")
	update_ui_for_phase()
	print("Main: ⚠️ Initial phase UI setup complete")

	# Setup deployment progress indicator
	_setup_deployment_progress_indicator()

	# Setup Strategic Reserves button
	_setup_reserves_button()

	# Setup Game Event Log panel
	_setup_game_log_panel()

	# Apply White Dwarf gothic UI theme
	_apply_white_dwarf_theme()

	# Enable autosave (saves every 5 minutes)
	SaveLoadManager.enable_autosave()
	print("Quick Save/Load enabled: [ key to save, ] key (or F9) to load")

func _initialize_ai_player() -> void:
	# Configure AIPlayer autoload based on game_config from MainMenu
	var ai_player = get_node_or_null("/root/AIPlayer")
	if not ai_player:
		print("Main: AIPlayer autoload not found, skipping AI initialization")
		return

	var game_config = GameState.state.get("meta", {}).get("game_config", {})
	var p1_type = game_config.get("player1_type", "HUMAN")
	var p2_type = game_config.get("player2_type", "HUMAN")

	print("Main: Configuring AI Player - P1=%s, P2=%s" % [p1_type, p2_type])
	ai_player.configure({1: p1_type, 2: p2_type})

	# Connect to AI deployment signal so we can create visual tokens
	if not ai_player.ai_unit_deployed.is_connected(_on_ai_unit_deployed):
		ai_player.ai_unit_deployed.connect(_on_ai_unit_deployed)
		print("Main: Connected to AIPlayer.ai_unit_deployed signal")

func _on_ai_unit_deployed(player: int, unit_id: String) -> void:
	# Create visual tokens for an AI-deployed unit
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		push_error("Main: _on_ai_unit_deployed - unit not found: %s" % unit_id)
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var models = unit.get("models", [])
	var tokens_created = 0

	print("Main: Creating visuals for AI-deployed unit %s (%s) with %d models" % [unit_name, unit_id, models.size()])

	for i in range(models.size()):
		var model = models[i]
		var pos = model.get("position")
		if pos != null and model.get("alive", true):
			var token = _create_token_visual(unit_id, model)
			if token:
				token_layer.add_child(token)
				var final_pos: Vector2
				if pos is Dictionary:
					final_pos = Vector2(pos.x, pos.y)
				else:
					final_pos = pos
				token.position = final_pos
				tokens_created += 1

	print("Main: Created %d token visuals for AI unit %s" % [tokens_created, unit_name])

	# Refresh the unit list and deployment progress so UI stays up to date
	refresh_unit_list()
	_update_deployment_progress()

func _setup_deployment_progress_indicator() -> void:
	# Create a panel that sits just below HUD_Bottom (which has been moved to the top)
	deployment_progress_container = PanelContainer.new()
	deployment_progress_container.name = "DeploymentProgressContainer"
	# Position below HUD_Bottom (top bar is 0-100px, so we start at 100)
	# Inset from sides to avoid overlapping left/right HUD panels (400px each)
	deployment_progress_container.anchor_left = 0.0
	deployment_progress_container.anchor_right = 1.0
	deployment_progress_container.anchor_top = 0.0
	deployment_progress_container.anchor_bottom = 0.0
	deployment_progress_container.offset_left = 400.0
	deployment_progress_container.offset_right = -400.0
	deployment_progress_container.offset_top = 100.0
	deployment_progress_container.offset_bottom = 160.0
	deployment_progress_container.visible = false
	add_child(deployment_progress_container)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	deployment_progress_container.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	margin.add_child(hbox)

	# Player 1 progress section
	var p1_vbox = VBoxContainer.new()
	p1_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(p1_vbox)

	p1_progress_label = Label.new()
	p1_progress_label.text = "Player 1 (Defender): 0/0 units deployed"
	p1_vbox.add_child(p1_progress_label)

	p1_progress_bar = ProgressBar.new()
	p1_progress_bar.min_value = 0
	p1_progress_bar.max_value = 1
	p1_progress_bar.value = 0
	p1_progress_bar.custom_minimum_size = Vector2(0, 16)
	p1_progress_bar.show_percentage = false
	p1_vbox.add_child(p1_progress_bar)

	# Player 2 progress section
	var p2_vbox = VBoxContainer.new()
	p2_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(p2_vbox)

	p2_progress_label = Label.new()
	p2_progress_label.text = "Player 2 (Attacker): 0/0 units deployed"
	p2_vbox.add_child(p2_progress_label)

	p2_progress_bar = ProgressBar.new()
	p2_progress_bar.min_value = 0
	p2_progress_bar.max_value = 1
	p2_progress_bar.value = 0
	p2_progress_bar.custom_minimum_size = Vector2(0, 16)
	p2_progress_bar.show_percentage = false
	p2_vbox.add_child(p2_progress_bar)

	# Apply themed styling to the progress bars
	_style_deployment_progress_bar(p1_progress_bar, WhiteDwarfTheme.P1_FILL, WhiteDwarfTheme.P1_BORDER)
	_style_deployment_progress_bar(p2_progress_bar, WhiteDwarfTheme.P2_FILL, WhiteDwarfTheme.P2_BORDER)

	print("Main: Deployment progress indicator created")

func _style_deployment_progress_bar(bar: ProgressBar, fill_color: Color, border_color: Color) -> void:
	# Background style
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.07, 0.05, 0.9)
	bg_style.border_color = border_color.darkened(0.3)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg_style)

	# Fill style
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = fill_color.lightened(0.2)
	fill_style.border_color = border_color
	fill_style.set_border_width_all(1)
	fill_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill_style)

func _update_deployment_progress() -> void:
	if not deployment_progress_container:
		return

	var p1_progress = GameState.get_deployment_progress(1)
	var p2_progress = GameState.get_deployment_progress(2)

	# Update Player 1
	var p1_reserves_text = " (%d in reserves)" % p1_progress.in_reserves if p1_progress.in_reserves > 0 else ""
	p1_progress_label.text = "Player 1 (Defender): %d/%d units deployed%s" % [p1_progress.deployed, p1_progress.total, p1_reserves_text]
	if p1_progress.total > 0:
		p1_progress_bar.max_value = p1_progress.total
		p1_progress_bar.value = p1_progress.deployed
	else:
		p1_progress_bar.max_value = 1
		p1_progress_bar.value = 0

	# Update Player 2
	var p2_reserves_text = " (%d in reserves)" % p2_progress.in_reserves if p2_progress.in_reserves > 0 else ""
	p2_progress_label.text = "Player 2 (Attacker): %d/%d units deployed%s" % [p2_progress.deployed, p2_progress.total, p2_reserves_text]
	if p2_progress.total > 0:
		p2_progress_bar.max_value = p2_progress.total
		p2_progress_bar.value = p2_progress.deployed
	else:
		p2_progress_bar.max_value = 1
		p2_progress_bar.value = 0

	print("Main: Deployment progress updated - P1: %d/%d, P2: %d/%d" % [p1_progress.deployed, p1_progress.total, p2_progress.deployed, p2_progress.total])

func _setup_reserves_button() -> void:
	# Create "Place in Reserves" button in the HUD_Right panel, below the unit list
	var hud_right = get_node_or_null("HUD_Right/VBoxContainer")
	if not hud_right:
		print("Main: HUD_Right/VBoxContainer not found for reserves button")
		return

	reserves_button = Button.new()
	reserves_button.name = "ReservesButton"
	reserves_button.text = "Place in Reserves"
	reserves_button.visible = false
	reserves_button.disabled = true
	reserves_button.custom_minimum_size = Vector2(0, 36)

	# Style the button
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.15, 0.3, 0.9)  # Dark purple for reserves
	style.border_color = Color(0.6, 0.4, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	reserves_button.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.3, 0.2, 0.4, 0.95)
	reserves_button.add_theme_stylebox_override("hover", hover_style)

	reserves_button.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
	reserves_button.add_theme_font_size_override("font_size", 13)

	reserves_button.pressed.connect(_on_reserves_button_pressed)

	# Insert after the unit list but before the unit card
	var unit_list_idx = unit_list.get_index()
	hud_right.add_child(reserves_button)
	hud_right.move_child(reserves_button, unit_list_idx + 1)

	print("Main: Reserves button created and added to HUD_Right")

func _on_reserves_button_pressed() -> void:
	if _selected_unit_for_reserves == "":
		return

	var unit_id = _selected_unit_for_reserves
	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		return

	# Determine reserve type
	var reserve_type = "deep_strike" if GameState.unit_has_deep_strike(unit_id) else "strategic_reserves"

	print("Main: Placing unit %s in reserves (type: %s)" % [unit_id, reserve_type])

	var action = {
		"type": "PLACE_IN_RESERVES",
		"unit_id": unit_id,
		"reserve_type": reserve_type,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	var result = NetworkIntegration.route_action(action)

	if result.success:
		var unit_name = unit_data.get("meta", {}).get("name", unit_id)
		var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_success("%s placed in %s" % [unit_name, type_label])
		print("Main: Successfully placed %s in %s" % [unit_name, type_label])

		# Trigger deployment alternation (reserves count as a deployment action)
		if has_node("/root/TurnManager"):
			get_node("/root/TurnManager").check_deployment_alternation()
	else:
		var errors = result.get("errors", [])
		var error_msg = errors[0] if errors.size() > 0 else "Failed to place in reserves"
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_error(error_msg)
		print("Main: Failed to place in reserves: %s" % str(errors))

	_selected_unit_for_reserves = ""
	refresh_unit_list()
	update_ui()

func _begin_reinforcement_placement(unit_id: String) -> void:
	"""Start placing a reserve unit on the battlefield as reinforcement"""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var reserve_type = unit.get("reserve_type", "strategic_reserves")
	var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"

	print("Main: Beginning reinforcement placement for %s (%s)" % [unit_name, type_label])

	# Use the deployment controller to handle model placement
	if deployment_controller:
		# Set reinforcement mode flag on deployment controller
		deployment_controller.is_reinforcement_mode = true

		# Temporarily set unit status to DEPLOYING so the controller can work with it
		if has_node("/root/PhaseManager"):
			var phase_manager = get_node("/root/PhaseManager")
			if phase_manager.current_phase_instance:
				phase_manager.apply_state_changes([{
					"op": "set",
					"path": "units.%s.status" % unit_id,
					"value": GameStateData.UnitStatus.DEPLOYING
				}])

		deployment_controller.unit_id = unit_id
		deployment_controller.model_idx = 0
		deployment_controller.temp_positions.clear()
		deployment_controller.temp_rotations.clear()
		var unit_data = GameState.get_unit(unit_id)
		deployment_controller.temp_positions.resize(unit_data["models"].size())
		deployment_controller.temp_rotations.resize(unit_data["models"].size())
		deployment_controller.temp_rotations.fill(0.0)
		deployment_controller.formation_rotation = 0.0

		# Create ghost for placement
		deployment_controller._create_ghost()

		# Store that we're in reinforcement mode
		_selected_unit_for_reserves = unit_id

		# Connect to confirm signal for reinforcement completion
		if not deployment_controller.unit_confirmed.is_connected(_on_reinforcement_confirmed):
			deployment_controller.unit_confirmed.connect(_on_reinforcement_confirmed)

		status_label.text = "Placing reinforcement: %s (%s) — >9\" from enemies" % [unit_name, type_label]
		if reserve_type == "strategic_reserves":
			status_label.text += " — within 6\" of board edge"

		unit_list.visible = false
		show_unit_card(unit_id)

func _on_reinforcement_confirmed() -> void:
	"""Handle reinforcement placement completion"""
	if _selected_unit_for_reserves == "":
		return

	var unit_id = _selected_unit_for_reserves
	var unit_data = GameState.get_unit(unit_id)

	if unit_data.is_empty() or not deployment_controller:
		return

	# Collect model positions from the deployment controller
	var model_positions = []
	for pos in deployment_controller.temp_positions:
		model_positions.append(pos)

	var model_rotations = deployment_controller.temp_rotations.duplicate()

	print("Main: Reinforcement placement confirmed for %s with %d model positions" % [unit_id, model_positions.size()])

	# Reset the unit status back to IN_RESERVES before sending the action
	# (the action processor will set it to DEPLOYED)
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": GameStateData.UnitStatus.IN_RESERVES
			}])

	# Create the reinforcement action
	var action = {
		"type": "PLACE_REINFORCEMENT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": model_rotations,
		"phase": GameStateData.Phase.MOVEMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	var result = NetworkIntegration.route_action(action)

	if result.success:
		var unit_name = unit_data.get("meta", {}).get("name", unit_id)
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_success("Reinforcement arrived: %s" % unit_name)
		print("Main: Reinforcement placed successfully for %s" % unit_name)
	else:
		var errors = result.get("errors", [])
		var error_msg = errors[0] if errors.size() > 0 else "Failed to place reinforcement"
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_error(error_msg)
		print("Main: Reinforcement placement failed: %s" % str(errors))

	_selected_unit_for_reserves = ""

	# Reset reinforcement mode
	if deployment_controller:
		deployment_controller.is_reinforcement_mode = false

	# Disconnect reinforcement signal
	if deployment_controller.unit_confirmed.is_connected(_on_reinforcement_confirmed):
		deployment_controller.unit_confirmed.disconnect(_on_reinforcement_confirmed)

	refresh_unit_list()
	update_ui()

func _restructure_ui_layout() -> void:
	# Move HUD_Bottom to top of screen
	var hud_bottom = get_node("HUD_Bottom")
	if hud_bottom:
		hud_bottom.anchor_top = 0.0
		hud_bottom.anchor_bottom = 0.0
		hud_bottom.offset_top = 0.0
		hud_bottom.offset_bottom = 100.0
		print("Moved HUD_Bottom to top of screen")
	
	# Create unit stats panel at bottom
	_setup_unit_stats_panel()

func _fix_hud_layout() -> void:
	# Adjust both left and right HUD panels for proper layout
	var hud_left = get_node("HUD_Left")
	var hud_right = get_node("HUD_Right")
	
	# Reserve space for the unit stats panel at bottom (40px collapsed, up to 300px expanded)
	var bottom_height = 300.0  # Max height when expanded
	var top_height = 100.0    # Space for top panel
	
	if hud_left:
		# Adjust HUD_Left to not overlap with panels
		hud_left.anchor_bottom = 1.0
		hud_left.offset_bottom = -bottom_height
		hud_left.anchor_top = 0.0
		hud_left.offset_top = top_height  # Leave space for top panel
		
		print("Fixed HUD layout: HUD_Left adjusted for new layout")
	
	if hud_right:
		# Adjust HUD_Right to not overlap with bottom panel
		hud_right.anchor_bottom = 1.0
		hud_right.offset_bottom = -bottom_height
		hud_right.anchor_top = 0.0
		hud_right.offset_top = top_height  # Leave space for top panel
		
		print("Fixed HUD layout: HUD_Right adjusted for new layout")
	
	# Adjust unit list to take less space, giving more room to phase panels
	var unit_list = get_node_or_null("HUD_Right/VBoxContainer/UnitListPanel")
	if unit_list:
		# Change from size_flags_vertical = 3 (expand/fill) to 0 (fixed size)
		unit_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unit_list.custom_minimum_size = Vector2(0, 150)  # Fixed height of 150px
		print("Adjusted unit list: fixed height to 150px")

func _apply_white_dwarf_theme() -> void:
	# Apply gothic red/black/gold UI chrome to HUD panels
	print("Main: Applying White Dwarf gothic theme")

	# Theme the HUD panels
	var hud_bottom = get_node_or_null("HUD_Bottom")
	if hud_bottom and hud_bottom is PanelContainer:
		_WhiteDwarfTheme.apply_to_panel(hud_bottom)

	var hud_left = get_node_or_null("HUD_Left")
	if hud_left and hud_left is PanelContainer:
		_WhiteDwarfTheme.apply_to_panel(hud_left)

	var hud_right = get_node_or_null("HUD_Right")
	if hud_right and hud_right is PanelContainer:
		_WhiteDwarfTheme.apply_to_panel(hud_right)

	# Theme labels in HUD_Bottom
	if phase_label:
		_WhiteDwarfTheme.apply_to_label(phase_label, true)
	if active_player_badge:
		_WhiteDwarfTheme.apply_to_label(active_player_badge)
	if status_label:
		_WhiteDwarfTheme.apply_to_label(status_label)

	# Theme the phase action button
	if phase_action_button:
		_WhiteDwarfTheme.apply_to_button(phase_action_button)

	# Theme unit list and card labels
	if unit_list:
		_WhiteDwarfTheme.apply_to_item_list(unit_list)
	if unit_name_label:
		_WhiteDwarfTheme.apply_to_label(unit_name_label, true)
	if keywords_label:
		_WhiteDwarfTheme.apply_to_label(keywords_label)
	if models_label:
		_WhiteDwarfTheme.apply_to_label(models_label)

	# Theme buttons in unit card
	if undo_button:
		_WhiteDwarfTheme.apply_to_button(undo_button)
	if reset_button:
		_WhiteDwarfTheme.apply_to_button(reset_button)
	if confirm_button:
		_WhiteDwarfTheme.apply_to_button(confirm_button)

	# Theme the UnitStatsPanel if it exists
	if unit_stats_panel and unit_stats_panel is PanelContainer:
		_WhiteDwarfTheme.apply_to_panel(unit_stats_panel)

	# Theme the deployment progress indicator
	if deployment_progress_container:
		_WhiteDwarfTheme.apply_to_panel(deployment_progress_container)
	if p1_progress_label:
		_WhiteDwarfTheme.apply_to_label(p1_progress_label)
	if p2_progress_label:
		_WhiteDwarfTheme.apply_to_label(p2_progress_label)

	# Theme the game log toggle button
	if game_log_toggle_button:
		_WhiteDwarfTheme.apply_to_button(game_log_toggle_button)

	print("Main: White Dwarf theme applied")

func _setup_unit_stats_panel() -> void:
	# UnitStatsPanel is now directly in the Main.tscn scene file
	print("Looking for UnitStatsPanel in scene...")
	unit_stats_panel = get_node_or_null("UnitStatsPanel")
	
	if unit_stats_panel:
		print("Found UnitStatsPanel in scene structure")
		
		# Connect to the unit_selected signal from the panel
		if unit_stats_panel.has_signal("unit_selected"):
			unit_stats_panel.unit_selected.connect(_on_unit_stats_panel_unit_selected)
			print("Connected to unit_selected signal from UnitStatsPanel")
		else:
			print("Warning: UnitStatsPanel does not have unit_selected signal")
		
		# Initialize the panel with current phase
		if unit_stats_panel.has_method("populate_unit_lists"):
			var phase_name = GameStateData.Phase.keys()[current_phase]
			unit_stats_panel.populate_unit_lists(phase_name)
			print("Initialized UnitStatsPanel unit lists for phase: ", phase_name)
	else:
		print("ERROR: UnitStatsPanel not found in scene! Check Main.tscn")

func _create_stats_panel_programmatically() -> PanelContainer:
	print("Creating unit stats panel with full UI structure...")
	
	var panel = PanelContainer.new()
	panel.name = "UnitStatsPanel"
	
	# Main VBox container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	panel.add_child(vbox)
	
	# Header with toggle button
	var header = HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(header)
	
	var toggle_button = Button.new()
	toggle_button.name = "ToggleButton"
	toggle_button.text = "▲ Unit Stats"
	toggle_button.custom_minimum_size = Vector2(120, 30)
	toggle_button.add_theme_font_size_override("font_size", 14)
	header.add_child(toggle_button)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	# Scroll container for content
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(scroll)
	
	# Content VBox
	var content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	
	# Keywords section
	var keywords_container = HBoxContainer.new()
	content.add_child(keywords_container)
	
	var keywords_title = Label.new()
	keywords_title.text = "Keywords: "
	keywords_title.add_theme_font_size_override("font_size", 12)
	keywords_container.add_child(keywords_title)
	
	var keywords_label = Label.new()
	keywords_label.name = "KeywordsLabel"
	keywords_label.text = "TEST KEYWORDS - Panel Working!"
	keywords_label.add_theme_font_size_override("font_size", 12)
	keywords_container.add_child(keywords_label)
	
	# Separator
	content.add_child(HSeparator.new())
	
	# Stats section
	var stats_container = VBoxContainer.new()
	content.add_child(stats_container)
	
	var stats_title = Label.new()
	stats_title.text = "UNIT STATS"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_container.add_child(stats_title)
	
	var stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.text = "M6\" | T4 | Sv3+ | W2 | Ld6+ | OC2 (PROGRAMMATIC TEST)"
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_container.add_child(stats_label)
	
	# Separator
	content.add_child(HSeparator.new())
	
	# Weapons section
	var weapons_container = VBoxContainer.new()
	weapons_container.name = "WeaponsContainer"
	content.add_child(weapons_container)
	
	var weapons_title = Label.new()
	weapons_title.text = "WEAPONS"
	weapons_title.add_theme_font_size_override("font_size", 14)
	weapons_container.add_child(weapons_title)
	
	var weapons_test = Label.new()
	weapons_test.text = "✓ Toggle button should be visible above\n✓ This content should be visible\n✓ Panel should be at screen bottom"
	weapons_test.add_theme_font_size_override("font_size", 12)
	weapons_container.add_child(weapons_test)
	
	# Store collapsed state as a property of the panel
	panel.set_meta("is_collapsed", false)
	
	# Connect toggle button with proper state tracking
	toggle_button.pressed.connect(func():
		var is_collapsed = panel.get_meta("is_collapsed", false)
		is_collapsed = !is_collapsed
		panel.set_meta("is_collapsed", is_collapsed)
		print("Toggle clicked - collapsed: ", is_collapsed)
		
		# Update button text
		toggle_button.text = "▼ Unit Stats" if is_collapsed else "▲ Unit Stats"
		
		# Update content visibility
		scroll.visible = !is_collapsed
		print("Setting scroll visible to: ", !is_collapsed)
		
		# Set panel size immediately
		if is_collapsed:
			panel.custom_minimum_size.y = 40
			panel.offset_top = -40
			panel.size.y = 40
		else:
			panel.custom_minimum_size.y = 300
			panel.offset_top = -300
			panel.size.y = 300
		
		print("Set panel height to: ", panel.custom_minimum_size.y)
		print("Set panel offset to: ", panel.offset_top)
		print("Set panel size to: ", panel.size.y)
		
		# Force the panel to update its layout
		panel.set_deferred("size:y", panel.custom_minimum_size.y)
		
		# Debug output after a frame
		panel.get_tree().create_timer(0.1).timeout.connect(func():
			print("After update - Panel size: ", panel.size)
			print("After update - Panel offset_top: ", panel.offset_top)
			print("After update - Scroll visible: ", scroll.visible)
		)
	)

	# Store references to UI elements for the display_unit callback
	panel.set_meta("_keywords_label", keywords_label)
	panel.set_meta("_stats_label", stats_label)
	panel.set_meta("_weapons_container", weapons_container)
	panel.set_meta("_weapons_title", weapons_title)

	# Add display_unit method to the panel for showing unit data
	panel.set_meta("display_unit", _create_display_unit_callback(panel))
	
	print("Programmatic panel created with toggle functionality and display_unit method")
	return panel

func _create_display_unit_callback(panel: PanelContainer) -> Callable:
	"""Create a callable for displaying unit data in the transport panel"""
	return func(unit_data: Dictionary):
		print("Displaying unit data for: ", unit_data.get("id", "unknown"))

		var keywords_label = panel.get_meta("_keywords_label")
		var stats_label = panel.get_meta("_stats_label")
		var weapons_container = panel.get_meta("_weapons_container")
		var weapons_title = panel.get_meta("_weapons_title")

		# Update keywords
		if keywords_label and unit_data.has("meta"):
			var meta = unit_data["meta"]
			if meta.has("keywords"):
				keywords_label.text = ", ".join(meta["keywords"])

		# Update stats
		if stats_label and unit_data.has("meta"):
			var meta = unit_data["meta"]
			if meta.has("stats"):
				var stats = meta["stats"]
				stats_label.text = "M%d\" | T%d | Sv%d+ | W%d | Ld%d+ | OC%d" % [
					stats.get("move", 0),
					stats.get("toughness", 0),
					stats.get("save", 0),
					stats.get("wounds", 0),
					stats.get("leadership", 0),
					stats.get("objective_control", 0)
				]

		# Clear and update weapons
		if weapons_container:
			for child in weapons_container.get_children():
				if child != weapons_title:
					child.queue_free()

			if unit_data.has("meta") and unit_data["meta"].has("weapons"):
				var weapons = unit_data["meta"]["weapons"]
				for weapon in weapons:
					var weapon_label = Label.new()
					var weapon_type = weapon.get("type", "Unknown")
					var weapon_name = weapon.get("name", "Unknown")
					var weapon_stats = ""

					if weapon_type == "Ranged":
						weapon_stats = "Range: %s\" | A: %s | BS: %s+ | S: %s | AP: %s | D: %s" % [
							weapon.get("range", "-"),
							weapon.get("attacks", "-"),
							weapon.get("ballistic_skill", "-"),
							weapon.get("strength", "-"),
							weapon.get("ap", "-"),
							weapon.get("damage", "-")
						]
					else:  # Melee
						weapon_stats = "Melee | A: %s | WS: %s+ | S: %s | AP: %s | D: %s" % [
							weapon.get("attacks", "-"),
							weapon.get("weapon_skill", "-"),
							weapon.get("strength", "-"),
							weapon.get("ap", "-"),
							weapon.get("damage", "-")
						]

					weapon_label.text = "• %s (%s): %s" % [weapon_name, weapon_type, weapon_stats]
					weapon_label.add_theme_font_size_override("font_size", 11)
					weapons_container.add_child(weapon_label)

		print("Unit data display updated")

func _setup_mathhammer_ui() -> void:
	# Create MathhhammerUI and add it to the left HUD
	print("Setting up Mathhammer UI...")
	
	# Create the MathhhammerUI instance using preload
	var MathhhammerUIClass = preload("res://scripts/MathhhammerUI.gd")
	mathhammer_ui = MathhhammerUIClass.new()
	mathhammer_ui.name = "MathhhammerUI"
	
	if mathhammer_ui:
		# Add to the left HUD VBox container 
		var hud_left_vbox = get_node("HUD_Left/VBoxContainer")
		if hud_left_vbox:
			# Add the Mathhammer UI to the left HUD
			hud_left_vbox.add_child(mathhammer_ui)
			print("Mathhammer UI added to left HUD")
		else:
			print("ERROR: Could not find HUD_Left/VBoxContainer!")
			return
		
		print("Mathhammer UI successfully integrated into left side of main UI")
	else:
		print("ERROR: Failed to create MathhhammerUI instance!")

func _setup_measuring_tape() -> void:
	print("Setting up measuring tape visual...")
	
	# Create measuring tape visual layer
	var measuring_tape_visual = preload("res://scripts/MeasuringTapeVisual.gd").new()
	measuring_tape_visual.name = "MeasuringTapeVisual"
	$BoardRoot.add_child(measuring_tape_visual)
	print("Added MeasuringTapeVisual to BoardRoot")
	print("Measuring Tape: Hold 't' and drag to measure, press 'y' to clear all measurements")
	
	# Add measuring tape save toggle to top HUD
	var hud_container = $HUD_Bottom/HBoxContainer
	if hud_container:
		# Add separator
		var separator = VSeparator.new()
		hud_container.add_child(separator)
		
		# Create measuring tape save toggle button
		var tape_save_button = CheckBox.new()
		tape_save_button.name = "MeasuringTapeSaveToggle"
		tape_save_button.text = "Save Measurements"
		tape_save_button.button_pressed = SettingsService.get_save_measurements()
		tape_save_button.toggled.connect(_on_measuring_tape_save_toggle)
		tape_save_button.tooltip_text = "Enable to persist measurement lines in save files"
		tape_save_button.add_theme_font_size_override("font_size", 12)
		hud_container.add_child(tape_save_button)
		
		print("Added measuring tape save toggle to HUD")

func _setup_terrain() -> void:
	print("Setting up terrain system...")
	
	# Create terrain visual layer
	var terrain_visual = preload("res://scripts/TerrainVisual.gd").new()
	terrain_visual.name = "TerrainVisual"
	$BoardRoot.add_child(terrain_visual)
	print("Added TerrainVisual to BoardRoot")

	# Create Line of Sight visual layer
	var los_visual = preload("res://scripts/LineOfSightVisual.gd").new()
	los_visual.name = "LineOfSightVisual"
	$BoardRoot.add_child(los_visual)
	print("Added LineOfSightVisual to BoardRoot")
	print("Line of Sight: Hold 'V' to check what models can see the cursor position")

	# Add terrain toggle button to top HUD
	var hud_container = $HUD_Bottom/HBoxContainer
	if hud_container:
		# Add separator
		var separator = VSeparator.new()
		hud_container.add_child(separator)
		
		# Create terrain toggle button
		var terrain_button = Button.new()
		terrain_button.name = "TerrainToggleButton"
		terrain_button.text = "Toggle Terrain"
		terrain_button.toggle_mode = true
		terrain_button.button_pressed = true  # Start with terrain visible
		terrain_button.toggled.connect(_on_terrain_toggle)
		hud_container.add_child(terrain_button)
		
		# Create terrain info label
		var terrain_label = Label.new()
		terrain_label.name = "TerrainInfoLabel"
		terrain_label.text = "Terrain: Layout 2"
		terrain_label.add_theme_font_size_override("font_size", 12)
		hud_container.add_child(terrain_label)
		
		# Add LoS debug toggle button
		var los_button = Button.new()
		los_button.name = "LoSDebugButton"
		los_button.text = "LoS Debug (L)"
		los_button.toggle_mode = true
		los_button.button_pressed = false  # Start with debug off (matches LoSDebugVisual default)
		los_button.toggled.connect(func(pressed): _toggle_los_debug())
		hud_container.add_child(los_button)
		
		print("Added terrain UI controls to HUD")

func _on_terrain_toggle(pressed: bool) -> void:
	TerrainManager.set_terrain_visibility(pressed)
	print("Terrain visibility: ", pressed)

func _on_measuring_tape_save_toggle(pressed: bool) -> void:
	SettingsService.set_save_measurements(pressed)
	print("Measuring tape save persistence: ", pressed)

func _setup_transport_panel() -> void:
	print("Setting up transport panel...")

	# Add transport info panel to HUD_Right
	var hud_right = get_node_or_null("HUD_Right/VBoxContainer")
	if not hud_right:
		print("ERROR: HUD_Right/VBoxContainer not found for transport panel")
		return

	# Create transport panel container
	var transport_panel = PanelContainer.new()
	transport_panel.name = "TransportPanel"
	transport_panel.visible = false  # Hidden by default
	transport_panel.custom_minimum_size = Vector2(250, 120)

	# Create VBox for transport info
	var vbox = VBoxContainer.new()
	transport_panel.add_child(vbox)

	# Title label
	var title_label = Label.new()
	title_label.name = "TransportTitle"
	title_label.text = "Transport Status"
	title_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_label)

	# Separator
	vbox.add_child(HSeparator.new())

	# Transport info label
	var info_label = RichTextLabel.new()
	info_label.name = "TransportInfo"
	info_label.custom_minimum_size = Vector2(0, 60)
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	vbox.add_child(info_label)

	# Action buttons container
	var button_container = HBoxContainer.new()
	button_container.name = "TransportActions"
	vbox.add_child(button_container)

	# Embark button (for units near transports)
	var embark_button = Button.new()
	embark_button.name = "EmbarkButton"
	embark_button.text = "Embark"
	embark_button.visible = false
	embark_button.pressed.connect(_on_embark_button_pressed)
	button_container.add_child(embark_button)

	# Disembark button (for embarked units)
	var disembark_button = Button.new()
	disembark_button.name = "DisembarkButton"
	disembark_button.text = "Disembark"
	disembark_button.visible = false
	disembark_button.pressed.connect(_on_disembark_button_pressed)
	button_container.add_child(disembark_button)

	# Add panel to HUD_Right
	hud_right.add_child(transport_panel)
	hud_right.move_child(transport_panel, 0)  # Place at top

	print("Transport panel added to HUD_Right")

func _on_embark_button_pressed() -> void:
	print("Embark button pressed")
	# Movement controller handles embark logic

func _on_disembark_button_pressed() -> void:
	print("Disembark button pressed")

	# Get the currently selected unit from the main unit list
	var selected_indices = unit_list.get_selected_items()
	if selected_indices.size() == 0:
		print("WARNING: No unit selected for disembark")
		return

	var selected_unit_id = unit_list.get_item_metadata(selected_indices[0])
	var selected_unit = GameState.get_unit(selected_unit_id)
	if not selected_unit or selected_unit.get("embarked_in", null) == null:
		print("WARNING: Selected unit is not embarked: ", selected_unit_id)
		return

	# Route to disembark flow via MovementController
	if movement_controller and current_phase == GameStateData.Phase.MOVEMENT:
		print("Main: Disembark button routing to MovementController for unit: ", selected_unit_id)
		movement_controller.active_unit_id = selected_unit_id
		movement_controller._handle_embarked_unit_selected(selected_unit_id)

func update_transport_panel(unit_id: String = "") -> void:
	"""Update transport panel based on selected unit"""
	var transport_panel = get_node_or_null("HUD_Right/VBoxContainer/TransportPanel")
	if not transport_panel:
		return

	var info_label = transport_panel.get_node_or_null("VBoxContainer/TransportInfo")
	var embark_button = transport_panel.get_node_or_null("VBoxContainer/TransportActions/EmbarkButton")
	var disembark_button = transport_panel.get_node_or_null("VBoxContainer/TransportActions/DisembarkButton")

	# If any child nodes are missing, the panel structure is invalid
	if not info_label or not embark_button or not disembark_button:
		print("WARNING: TransportPanel structure is incomplete, hiding panel")
		transport_panel.visible = false
		return

	if unit_id == "":
		transport_panel.visible = false
		return

	var unit = GameState.get_unit(unit_id)
	if not unit:
		transport_panel.visible = false
		return

	# Check if unit is a transport
	if unit.has("transport_data"):
		transport_panel.visible = true
		var transport_data = unit.transport_data
		var capacity = transport_data.get("capacity", 0)
		var embarked_count = 0
		for e_unit in TransportManager.get_embarked_units(unit_id):
			embarked_count += e_unit.models.filter(func(m): return m.get("alive", true)).size()
		var embarked_units = TransportManager.get_embarked_units(unit_id)

		var info_text = "[b]Transport: %s[/b]\n" % unit.meta.get("name", unit_id)
		info_text += "Capacity: %d/%d models\n" % [embarked_count, capacity]

		if embarked_units.size() > 0:
			info_text += "[color=green]Embarked units:[/color]\n"
			for embarked_unit in embarked_units:
				info_text += "• %s\n" % embarked_unit.meta.get("name", embarked_unit.id)
		else:
			info_text += "[color=gray]No embarked units[/color]\n"

		if transport_data.get("firing_deck", 0) > 0:
			info_text += "[color=yellow]Firing Deck: %d models[/color]" % transport_data.firing_deck

		info_label.text = info_text
		embark_button.visible = false
		disembark_button.visible = false

	# Check if unit is embarked
	elif unit.get("embarked_in", null) != null:
		transport_panel.visible = true
		var transport = GameState.get_unit(unit.embarked_in)
		var transport_name = transport.meta.get("name", unit.embarked_in) if transport else "Unknown"

		var info_text = "[b]%s[/b]\n" % unit.meta.get("name", unit_id)
		info_text += "[color=blue]Embarked in: %s[/color]\n" % transport_name

		# Check if can disembark (only in movement phase)
		if current_phase == GameStateData.Phase.MOVEMENT:
			var can_disembark = TransportManager.can_disembark(unit_id)
			if can_disembark.valid:
				info_text += "[color=green]Can disembark[/color]"
				disembark_button.visible = true
			else:
				info_text += "[color=red]Cannot disembark: %s[/color]" % can_disembark.reason
				disembark_button.visible = false
		else:
			disembark_button.visible = false

		info_label.text = info_text
		embark_button.visible = false

	# Check if unit can embark (only in movement/deployment phases)
	elif current_phase in [GameStateData.Phase.DEPLOYMENT, GameStateData.Phase.MOVEMENT]:
		# Check for nearby transports
		var player = unit.get("owner", 0)
		var can_embark_in_any = false

		for t_id in GameState.state.units:
			var transport = GameState.state.units[t_id]
			if transport.owner == player and transport.has("transport_data"):
				var validation = TransportManager.can_embark(unit_id, t_id)
				if validation.valid:
					can_embark_in_any = true
					break

		if can_embark_in_any:
			transport_panel.visible = true
			var info_text = "[b]%s[/b]\n" % unit.meta.get("name", unit_id)
			info_text += "[color=green]Transport available nearby[/color]"
			info_label.text = info_text
			embark_button.visible = true
			disembark_button.visible = false
		else:
			transport_panel.visible = false
	else:
		transport_panel.visible = false

func _setup_objectives() -> void:
	print("Setting up objectives on board...")
	
	# Create objectives container
	var objectives_container = Node2D.new()
	objectives_container.name = "Objectives"
	objectives_container.z_index = -8  # Between board and deployment zones
	$BoardRoot.add_child(objectives_container)
	
	if MissionManager:
		var objectives = GameState.state.board.get("objectives", [])
		print("Main: Creating visuals for %d objectives" % objectives.size())
		
		for obj in objectives:
			var obj_visual = preload("res://scripts/ObjectiveVisual.gd").new()
			obj_visual.setup(obj)
			objectives_container.add_child(obj_visual)
			
			# Store reference in MissionManager for easy access
			MissionManager.objectives_visual_refs[obj.id] = obj_visual
			
			# Connect to control changes
			MissionManager.objective_control_changed.connect(
				func(obj_id, controller):
					if obj_id == obj.id:
						obj_visual.update_control(controller)
			)
		
		# Do initial control check
		MissionManager.check_all_objectives()
		
		print("Main: Objectives setup complete")
	else:
		print("Main: MissionManager not available, skipping objectives")

func _toggle_los_debug() -> void:
	# Try to get LoS debug visual from ShootingController first (if in shooting phase)
	var shooting_controller = get_node_or_null("ShootingController")
	var los_debug = null

	if shooting_controller and "los_debug_visual" in shooting_controller and shooting_controller.los_debug_visual:
		los_debug = shooting_controller.los_debug_visual
		print("LoS debug: Using ShootingController's instance")
	else:
		# Fallback to finding it in BoardRoot
		los_debug = get_node_or_null("BoardRoot/LoSDebugVisual")
		print("LoS debug: Using BoardRoot instance (fallback)")

	if los_debug:
		var was_enabled = los_debug.debug_enabled
		print("LoS debug: Was enabled: ", was_enabled)
		los_debug.toggle_debug()
		var is_now_enabled = los_debug.debug_enabled
		print("LoS debug visualization: ", is_now_enabled)
		_show_toast("LoS Debug: " + ("ON" if is_now_enabled else "OFF"))

		# Sync the HUD button state without re-triggering this function
		var los_button = get_node_or_null("HUD_Bottom/HBoxContainer/LoSDebugButton")
		if los_button:
			los_button.set_pressed_no_signal(is_now_enabled)

		# If we just turned debug ON, refresh visuals if shooting phase is active
		if not was_enabled and is_now_enabled and shooting_controller:
			print("LoS debug: Calling refresh on ShootingController")
			if shooting_controller.has_method("refresh_los_debug_visuals"):
				shooting_controller.refresh_los_debug_visuals()
				print("LoS debug: Refreshed visuals for active shooter")
	else:
		print("LoS debug visual not found")

func _show_toast(message: String, duration: float = 2.0) -> void:
	# Route through global ToastManager for consistent on-screen display
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_toast(message, Color.YELLOW, duration)
	else:
		print("[Toast fallback] %s" % message)

func show_error_toast(message: String) -> void:
	# Public wrapper for showing error toasts (called by NetworkManager)
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_error(message)
	else:
		print("[Toast ERROR fallback] %s" % message)

func _setup_save_load_dialog() -> void:
	# Load and instantiate the SaveLoadDialog scene
	print("Setting up Save/Load Dialog...")
	
	var dialog_scene = preload("res://scenes/SaveLoadDialog.tscn")
	save_load_dialog = dialog_scene.instantiate()
	save_load_dialog.name = "SaveLoadDialog"
	
	# Add to scene tree
	add_child(save_load_dialog)
	
	# Connect dialog signals
	save_load_dialog.save_requested.connect(_on_save_requested)
	save_load_dialog.load_requested.connect(_on_load_requested)
	save_load_dialog.delete_requested.connect(_on_delete_requested)
	save_load_dialog.main_menu_requested.connect(_on_main_menu_requested)
	
	# Hide initially
	save_load_dialog.hide()
	
	print("Save/Load Dialog setup completed")

func setup_deployment_zones() -> void:
	# Ensure BoardState zones match the deployment type stored in GameState
	var deployment_type = GameState.get_deployment_type()
	BoardState.initialize_deployment_zones(deployment_type)
	print("Main: Setting up deployment zones for: ", deployment_type)

	var zone1 = BoardState.get_deployment_zone_for_player(1)
	var zone2 = BoardState.get_deployment_zone_for_player(2)

	p1_zone.polygon = zone1
	p2_zone.polygon = zone2

	update_deployment_zone_visibility()

var _setting_up_controllers: bool = false  # Semaphore to prevent concurrent setup

func setup_phase_controllers() -> void:
	# CRITICAL: Prevent concurrent calls that create duplicate controllers
	if _setting_up_controllers:
		print("Main: setup_phase_controllers() already running - waiting for completion...")
		while _setting_up_controllers:
			await get_tree().process_frame
		print("Main: Previous setup_phase_controllers() completed - skipping duplicate call")
		return

	_setting_up_controllers = true
	print("Main: setup_phase_controllers() STARTING (semaphore locked)")

	# ENHANCEMENT: Clear right panel before cleanup
	_clear_right_panel_phase_ui()

	# Clean up existing controllers
	if deployment_controller:
		deployment_controller.queue_free()
		deployment_controller = null
	if coherency_banner and is_instance_valid(coherency_banner):
		coherency_banner.queue_free()
		coherency_banner = null
	if command_controller:
		command_controller.queue_free()
		command_controller = null
	if movement_controller:
		movement_controller.queue_free()
		movement_controller = null
	if shooting_controller:
		# CRITICAL: Disconnect ALL signals before freeing to prevent lingering connections
		print("Main: Cleaning up shooting_controller instance ID: ", shooting_controller.get_instance_id())
		var phase_instance = PhaseManager.get_current_phase_instance()
		if phase_instance and phase_instance is ShootingPhase:
			# Disconnect all phase signals
			if phase_instance.unit_selected_for_shooting.is_connected(shooting_controller._on_unit_selected_for_shooting):
				phase_instance.unit_selected_for_shooting.disconnect(shooting_controller._on_unit_selected_for_shooting)
				print("Main: Disconnected unit_selected_for_shooting")
			if phase_instance.targets_available.is_connected(shooting_controller._on_targets_available):
				phase_instance.targets_available.disconnect(shooting_controller._on_targets_available)
				print("Main: Disconnected targets_available")
			if phase_instance.shooting_resolved.is_connected(shooting_controller._on_shooting_resolved):
				phase_instance.shooting_resolved.disconnect(shooting_controller._on_shooting_resolved)
				print("Main: Disconnected shooting_resolved")
			if phase_instance.dice_rolled.is_connected(shooting_controller._on_dice_rolled):
				phase_instance.dice_rolled.disconnect(shooting_controller._on_dice_rolled)
				print("Main: Disconnected dice_rolled")
			if phase_instance.saves_required.is_connected(shooting_controller._on_saves_required):
				phase_instance.saves_required.disconnect(shooting_controller._on_saves_required)
				print("Main: Disconnected saves_required")
			if phase_instance.weapon_order_required.is_connected(shooting_controller._on_weapon_order_required):
				phase_instance.weapon_order_required.disconnect(shooting_controller._on_weapon_order_required)
				print("Main: Disconnected weapon_order_required")
			if phase_instance.next_weapon_confirmation_required.is_connected(shooting_controller._on_next_weapon_confirmation_required):
				phase_instance.next_weapon_confirmation_required.disconnect(shooting_controller._on_next_weapon_confirmation_required)
				print("Main: Disconnected next_weapon_confirmation_required")
			if phase_instance.reactive_stratagem_opportunity.is_connected(shooting_controller._on_reactive_stratagem_opportunity):
				phase_instance.reactive_stratagem_opportunity.disconnect(shooting_controller._on_reactive_stratagem_opportunity)
				print("Main: Disconnected reactive_stratagem_opportunity")

		# ENHANCEMENT: Clear visuals before freeing controller
		if shooting_controller.has_method("_clear_visuals"):
			shooting_controller._clear_visuals()
		shooting_controller.queue_free()
		shooting_controller = null
		print("Main: Shooting controller queued for deletion")
	if charge_controller:
		charge_controller.queue_free()
		charge_controller = null
	if fight_controller:
		fight_controller.queue_free()
		fight_controller = null
	if scoring_controller:
		scoring_controller.queue_free()
		scoring_controller = null
	
	# Wait TWO frames for complete cleanup
	await get_tree().process_frame
	await get_tree().process_frame
	
	# ENHANCEMENT: Clear again after controller cleanup
	_clear_right_panel_phase_ui()
	
	# Setup controller based on current phase
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			setup_deployment_controller()
		GameStateData.Phase.COMMAND:
			setup_command_controller()
		GameStateData.Phase.MOVEMENT:
			setup_movement_controller()
		GameStateData.Phase.SHOOTING:
			setup_shooting_controller()
		GameStateData.Phase.CHARGE:
			setup_charge_controller()
		GameStateData.Phase.FIGHT:
			setup_fight_controller()
		GameStateData.Phase.SCORING:
			setup_scoring_controller()
		_:
			print("No controller for phase: ", current_phase)

	# CRITICAL: Unlock semaphore when done
	_setting_up_controllers = false
	print("Main: setup_phase_controllers() COMPLETE (semaphore unlocked)")

func setup_deployment_controller() -> void:
	print("[Main] setup_deployment_controller() called")
	print("[Main] token_layer is null: ", token_layer == null)
	print("[Main] ghost_layer is null: ", ghost_layer == null)

	var DeploymentControllerScript = load("res://scripts/DeploymentController.gd")
	print("[Main] DeploymentController script loaded: ", DeploymentControllerScript != null)

	deployment_controller = DeploymentControllerScript.new()
	deployment_controller.name = "DeploymentController"
	add_child(deployment_controller)
	deployment_controller.set_layers(token_layer, ghost_layer)
	print("[Main] DeploymentController set_layers called with valid layers")

	# Connect controller signals
	deployment_controller.unit_confirmed.connect(_on_unit_confirmed)
	deployment_controller.models_placed_changed.connect(_on_models_placed_changed)
	deployment_controller.coherency_warning_changed.connect(_on_coherency_warning_changed)

	# Setup coherency warning banner
	_setup_coherency_banner()

	# Add formation UI controls to unit card
	_setup_formation_ui()

func _setup_coherency_banner() -> void:
	# Remove any existing banner
	if coherency_banner and is_instance_valid(coherency_banner):
		coherency_banner.queue_free()

	# Create a non-blocking yellow warning banner
	coherency_banner = PanelContainer.new()
	coherency_banner.name = "CoherencyBanner"

	# Style the panel with yellow/amber warning colors
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.85, 0.65, 0.0, 0.9)  # Amber/yellow
	style_box.border_color = Color(0.7, 0.5, 0.0, 1.0)
	style_box.set_border_width_all(2)
	style_box.set_corner_radius_all(4)
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 6
	style_box.content_margin_bottom = 6
	coherency_banner.add_theme_stylebox_override("panel", style_box)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_label = Label.new()
	icon_label.text = "WARNING"
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.add_theme_color_override("font_color", Color(0.3, 0.2, 0.0))
	var bold_font = SystemFont.new()
	bold_font.font_weight = 700
	icon_label.add_theme_font_override("font", bold_font)
	hbox.add_child(icon_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(8, 0)
	hbox.add_child(spacer)

	var msg_label = Label.new()
	msg_label.name = "MessageLabel"
	msg_label.text = ""
	msg_label.add_theme_font_size_override("font_size", 14)
	msg_label.add_theme_color_override("font_color", Color(0.2, 0.1, 0.0))
	hbox.add_child(msg_label)

	coherency_banner.add_child(hbox)

	# Position at top-center, below the HUD top bar
	coherency_banner.anchor_left = 0.5
	coherency_banner.anchor_right = 0.5
	coherency_banner.anchor_top = 0.0
	coherency_banner.anchor_bottom = 0.0
	coherency_banner.offset_left = -200
	coherency_banner.offset_right = 200
	coherency_banner.offset_top = 110
	coherency_banner.offset_bottom = 140

	# Start hidden
	coherency_banner.visible = false
	coherency_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(coherency_banner)

func _on_coherency_warning_changed(is_incoherent: bool, message: String) -> void:
	if not coherency_banner or not is_instance_valid(coherency_banner):
		return

	if is_incoherent:
		var msg_label = coherency_banner.get_node("HBoxContainer/MessageLabel")
		if msg_label:
			msg_label.text = message
		coherency_banner.visible = true
		print("[Main] Coherency banner shown: %s" % message)
	else:
		coherency_banner.visible = false
		print("[Main] Coherency banner hidden")

func _setup_formation_ui() -> void:
	# Check if formation controls already exist
	var existing_controls = unit_card.get_node_or_null("FormationControls")
	if existing_controls:
		existing_controls.queue_free()

	var formation_container = HBoxContainer.new()
	formation_container.name = "FormationControls"

	var formation_label = Label.new()
	formation_label.text = "Deploy Formation:"
	formation_container.add_child(formation_label)

	# Create button group for exclusive selection
	var button_group = ButtonGroup.new()

	# Single mode button
	var single_btn = Button.new()
	single_btn.text = "Single"
	single_btn.toggle_mode = true
	single_btn.button_pressed = true  # Default to single mode
	single_btn.button_group = button_group
	single_btn.pressed.connect(_on_formation_mode_changed.bind("SINGLE"))
	formation_container.add_child(single_btn)

	# Spread formation button
	var spread_btn = Button.new()
	spread_btn.text = "Spread (2\")"
	spread_btn.toggle_mode = true
	spread_btn.button_group = button_group
	spread_btn.pressed.connect(_on_formation_mode_changed.bind("SPREAD"))
	formation_container.add_child(spread_btn)

	# Tight formation button
	var tight_btn = Button.new()
	tight_btn.text = "Tight"
	tight_btn.toggle_mode = true
	tight_btn.button_group = button_group
	tight_btn.pressed.connect(_on_formation_mode_changed.bind("TIGHT"))
	formation_container.add_child(tight_btn)

	# Add below unit name (position 2 in the VBoxContainer)
	unit_card.add_child(formation_container)
	if unit_card.get_child_count() > 2:
		unit_card.move_child(formation_container, 2)

func _on_formation_mode_changed(mode: String) -> void:
	if deployment_controller:
		deployment_controller.set_formation_mode(mode)

func setup_command_controller() -> void:
	print("Setting up CommandController...")
	command_controller = preload("res://scripts/CommandController.gd").new()
	command_controller.name = "CommandController"
	add_child(command_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a CommandPhase
		var is_command_phase = false
		if phase_instance.get("phase_type") == GameStateData.Phase.COMMAND:
			is_command_phase = true
		
		if is_command_phase:
			command_controller.set_phase(phase_instance)
			print("Connected CommandController to CommandPhase")
		else:
			print("WARNING: Phase instance is not a CommandPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect command controller signals
	if not command_controller.command_action_requested.is_connected(_on_command_action_requested):
		command_controller.command_action_requested.connect(_on_command_action_requested)
		print("Connected command_action_requested signal")
	if not command_controller.ui_update_requested.is_connected(_on_command_ui_update_requested):
		command_controller.ui_update_requested.connect(_on_command_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_movement_controller() -> void:
	print("Setting up MovementController...")
	var movement_controller_script = load("res://scripts/MovementController.gd")
	movement_controller = movement_controller_script.new()
	movement_controller.name = "MovementController"
	add_child(movement_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a MovementPhase by checking for movement-specific signals or methods
		var is_movement_phase = false
		if phase_instance.has_signal("unit_move_begun"):
			is_movement_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.MOVEMENT:
			is_movement_phase = true
		elif phase_instance.has_method("_process_begin_normal_move"):
			# If it has movement-specific methods, treat it as MovementPhase
			is_movement_phase = true
		elif phase_instance.has_method("_validate_stage_model_move"):
			# Or if it has our new staged move methods
			is_movement_phase = true
			
		if is_movement_phase:
			movement_controller.set_phase(phase_instance)
			
			# Connect phase signals to movement controller
			if not phase_instance.unit_move_begun.is_connected(movement_controller._on_unit_move_begun):
				phase_instance.unit_move_begun.connect(movement_controller._on_unit_move_begun)
				print("Connected unit_move_begun signal")
			if phase_instance.has_signal("model_drop_committed"):
				if not phase_instance.model_drop_committed.is_connected(movement_controller._on_model_drop_committed):
					phase_instance.model_drop_committed.connect(movement_controller._on_model_drop_committed)
					print("Connected model_drop_committed signal")
				# Also connect to Main for visual updates
				if not phase_instance.model_drop_committed.is_connected(_on_model_drop_committed):
					phase_instance.model_drop_committed.connect(_on_model_drop_committed)
					print("Connected model_drop_committed to Main for visual updates")
			if phase_instance.has_signal("unit_move_confirmed"):
				if not phase_instance.unit_move_confirmed.is_connected(movement_controller._on_unit_move_confirmed):
					phase_instance.unit_move_confirmed.connect(movement_controller._on_unit_move_confirmed)
					print("Connected unit_move_confirmed signal")
			if phase_instance.has_signal("unit_move_reset"):
				if not phase_instance.unit_move_reset.is_connected(movement_controller._on_unit_move_reset):
					phase_instance.unit_move_reset.connect(movement_controller._on_unit_move_reset)
					print("Connected unit_move_reset signal")
		else:
			print("WARNING: Phase instance is not a MovementPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect movement controller signals
	if not movement_controller.move_action_requested.is_connected(_on_movement_action_requested):
		movement_controller.move_action_requested.connect(_on_movement_action_requested)
		print("Connected move_action_requested signal")
	if not movement_controller.ui_update_requested.is_connected(_on_movement_ui_update_requested):
		movement_controller.ui_update_requested.connect(_on_movement_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_shooting_controller() -> void:
	print("Setting up ShootingController...")
	shooting_controller = preload("res://scripts/ShootingController.gd").new()
	shooting_controller.name = "ShootingController"
	add_child(shooting_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a ShootingPhase
		var is_shooting_phase = false
		if phase_instance.has_signal("unit_selected_for_shooting"):
			is_shooting_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.SHOOTING:
			is_shooting_phase = true
		
		if is_shooting_phase:
			# CRITICAL FIX: set_phase() already connects ALL phase signals internally
			# Connecting them here creates duplicate connections!
			# DO NOT duplicate signal connections - set_phase() handles everything
			shooting_controller.set_phase(phase_instance)
		else:
			print("WARNING: Phase instance is not a ShootingPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect shooting controller signals
	if not shooting_controller.shoot_action_requested.is_connected(_on_shooting_action_requested):
		shooting_controller.shoot_action_requested.connect(_on_shooting_action_requested)
		print("Connected shoot_action_requested signal")
	if not shooting_controller.ui_update_requested.is_connected(_on_shooting_ui_update_requested):
		shooting_controller.ui_update_requested.connect(_on_shooting_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_charge_controller() -> void:
	print("Setting up ChargeController...")
	charge_controller = preload("res://scripts/ChargeController.gd").new()
	charge_controller.name = "ChargeController"
	add_child(charge_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a ChargePhase
		var is_charge_phase = false
		if phase_instance.has_signal("unit_selected_for_charge"):
			is_charge_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.CHARGE:
			is_charge_phase = true
		
		if is_charge_phase:
			charge_controller.set_phase(phase_instance)
			print("Connected ChargeController to ChargePhase")
		else:
			print("WARNING: Phase instance is not a ChargePhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect charge controller signals
	if not charge_controller.charge_action_requested.is_connected(_on_charge_action_requested):
		charge_controller.charge_action_requested.connect(_on_charge_action_requested)
		print("Connected charge_action_requested signal")
	if not charge_controller.ui_update_requested.is_connected(_on_charge_ui_update_requested):
		charge_controller.ui_update_requested.connect(_on_charge_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_fight_controller() -> void:
	print("Setting up FightController...")
	fight_controller = preload("res://scripts/FightController.gd").new()
	fight_controller.name = "FightController"
	add_child(fight_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a FightPhase
		var is_fight_phase = false
		if phase_instance.has_signal("fighter_selected"):
			is_fight_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.FIGHT:
			is_fight_phase = true
		
		if is_fight_phase:
			fight_controller.set_phase(phase_instance)
			print("Connected FightController to FightPhase")
		else:
			print("WARNING: Phase instance is not a FightPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect fight controller signals
	if not fight_controller.fight_action_requested.is_connected(_on_fight_action_requested):
		fight_controller.fight_action_requested.connect(_on_fight_action_requested)
		print("Connected fight_action_requested signal")
	if not fight_controller.ui_update_requested.is_connected(_on_fight_ui_update_requested):
		fight_controller.ui_update_requested.connect(_on_fight_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_scoring_controller() -> void:
	print("Setting up ScoringController...")
	scoring_controller = preload("res://scripts/ScoringController.gd").new()
	scoring_controller.name = "ScoringController"
	add_child(scoring_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a ScoringPhase
		var is_scoring_phase = false
		if phase_instance.get("phase_type") == GameStateData.Phase.SCORING:
			is_scoring_phase = true
		
		if is_scoring_phase:
			scoring_controller.set_phase(phase_instance)
			print("Connected ScoringController to ScoringPhase")
		else:
			print("WARNING: Phase instance is not a ScoringPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect scoring controller signals
	if not scoring_controller.scoring_action_requested.is_connected(_on_scoring_action_requested):
		scoring_controller.scoring_action_requested.connect(_on_scoring_action_requested)
		print("Connected scoring_action_requested signal")
	if not scoring_controller.ui_update_requested.is_connected(_on_scoring_ui_update_requested):
		scoring_controller.ui_update_requested.connect(_on_scoring_ui_update_requested)
		print("Connected ui_update_requested signal")

func connect_signals() -> void:
	unit_list.item_selected.connect(_on_unit_selected)
	undo_button.pressed.connect(_on_undo_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	# Phase action button connection will be handled in update_ui_for_phase()
	
	# Phase management signals
	PhaseManager.phase_changed.connect(_on_phase_changed)
	PhaseManager.phase_completed.connect(_on_phase_completed)
	
	TurnManager.deployment_side_changed.connect(_on_deployment_side_changed)
	TurnManager.deployment_phase_complete.connect(_on_deployment_complete)
	
	# Controller signals (if they exist)
	if deployment_controller:
		deployment_controller.unit_confirmed.connect(_on_unit_confirmed)
		deployment_controller.models_placed_changed.connect(_on_models_placed_changed)
		if deployment_controller.has_signal("coherency_warning_changed") and not deployment_controller.coherency_warning_changed.is_connected(_on_coherency_warning_changed):
			deployment_controller.coherency_warning_changed.connect(_on_coherency_warning_changed)
	
	# Connect save/load signals
	SaveLoadManager.save_completed.connect(_on_save_completed)
	SaveLoadManager.load_completed.connect(_on_load_completed)
	SaveLoadManager.save_failed.connect(_on_save_failed)
	SaveLoadManager.load_failed.connect(_on_load_failed)
	if OS.has_feature("web"):
		SaveLoadManager.delete_completed.connect(_on_delete_completed_main)

	# Connect multiplayer sync signals
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		game_manager.result_applied.connect(_on_network_result_applied)
		print("Main: Connected to GameManager.result_applied signal")

	# Connect NetworkManager signals for web relay mode
	if NetworkManager:
		if not NetworkManager.game_started.is_connected(_on_network_game_started):
			NetworkManager.game_started.connect(_on_network_game_started)
			print("Main: Connected to NetworkManager.game_started signal")
	

func _input(event: InputEvent) -> void:
	# Debug mode toggle - highest priority
	if event is InputEventKey and event.pressed and event.keycode == KEY_9:
		print("Debug mode key (9) pressed!")
		DebugManager.toggle_debug_mode()
		get_viewport().set_input_as_handled()
		return
	
	# LoS debug toggle - KEY_L
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		print("LoS debug toggle key (L) pressed!")
		_toggle_los_debug()
		get_viewport().set_input_as_handled()
		return
	
	# Objective control check debug - KEY_O
	if event is InputEventKey and event.pressed and event.keycode == KEY_O:
		print("\n=== MANUAL OBJECTIVE CONTROL CHECK (O key pressed) ===")
		if MissionManager:
			MissionManager.check_all_objectives()
			var control_summary = MissionManager.get_objective_control_summary()
			print("Control Summary:")
			print("  Player 1 controlled: %d" % control_summary.player1_controlled)
			print("  Player 2 controlled: %d" % control_summary.player2_controlled)
			print("  Contested: %d" % control_summary.contested)
			print("\nObjective Status:")
			for obj_id in control_summary.objectives:
				var controller = control_summary.objectives[obj_id]
				var control_text = "Contested"
				if controller == 1:
					control_text = "Player 1"
				elif controller == 2:
					control_text = "Player 2"
				print("  %s: %s" % [obj_id, control_text])
		else:
			print("MissionManager not available!")
		print("=== END OBJECTIVE CONTROL CHECK ===\n")
		get_viewport().set_input_as_handled()
		return
	
	# Measuring Tape controls - 't' to measure, 'y' to clear
	if event is InputEventKey:
		# Start/stop measuring with 't' key
		if event.keycode == KEY_T:
			if event.pressed and not MeasuringTapeManager.is_measuring:
				var mouse_pos = get_viewport().get_mouse_position()
				var world_pos = screen_to_world_position(mouse_pos)
				MeasuringTapeManager.start_measurement(world_pos)
				get_viewport().set_input_as_handled()
			elif not event.pressed and MeasuringTapeManager.is_measuring:
				var mouse_pos = get_viewport().get_mouse_position()
				var world_pos = screen_to_world_position(mouse_pos)
				if MeasuringTapeManager.can_add_measurement():
					MeasuringTapeManager.complete_measurement(world_pos)
				else:
					print("Maximum number of measurements reached (10). Clear with 'y' key.")
					MeasuringTapeManager.cancel_measurement()
				get_viewport().set_input_as_handled()
			return
		
		# Clear all measurements with 'y' key
		if event.pressed and event.keycode == KEY_Y:
			MeasuringTapeManager.clear_all_measurements()
			print("All measurements cleared")
			get_viewport().set_input_as_handled()
			return
	
	# Update measurement preview while dragging
	if event is InputEventMouseMotion and MeasuringTapeManager.is_measuring:
		var world_pos = screen_to_world_position(event.position)
		MeasuringTapeManager.update_measurement(world_pos)
	
	# ESC key handling for save/load dialog
	# Only handle ESC if dialog is not visible (to avoid interfering with dialog input)
	if event.is_action_pressed("ui_cancel"):
		if save_load_dialog and not save_load_dialog.visible:
			_toggle_save_load_menu()
			get_viewport().set_input_as_handled()
			return
		elif save_load_dialog and save_load_dialog.visible:
			# Let the dialog handle ESC (it has dialog_close_on_escape = true)
			return
	
	# Don't process other input while dialog is open
	if save_load_dialog and save_load_dialog.visible:
		return
	
	# Debug: Check for [ key directly for save
	if event is InputEventKey and event.pressed and event.keycode == KEY_BRACKETLEFT:
		print("[ KEY DETECTED DIRECTLY!")
		_perform_quick_save()
		get_viewport().set_input_as_handled()
		return
	
	# Debug: Check for ] key directly for load
	if event is InputEventKey and event.pressed and event.keycode == KEY_BRACKETRIGHT:
		print("] KEY DETECTED DIRECTLY!")
		_perform_quick_load()
		get_viewport().set_input_as_handled()
		return
	
	# Handle quick save/load
	if event.is_action_pressed("quick_save"):
		print("quick_save action detected!")
		_perform_quick_save()
		get_viewport().set_input_as_handled()
		return
		
	if event.is_action_pressed("quick_load"):
		_perform_quick_load()
		get_viewport().set_input_as_handled()
		return
	
	# Handle mouse clicks for placement - but only consume if we actually place something
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if deployment_controller and deployment_controller.is_placing():
			# Check if click is on the board area (not on UI)
			var ui_rect = get_viewport().get_visible_rect()
			var right_hud_rect = Rect2(ui_rect.size.x - 400, 0, 400, ui_rect.size.y)  # Right HUD area
			var bottom_hud_rect = Rect2(0, ui_rect.size.y - 100, ui_rect.size.x, 100)  # Bottom HUD area

			if not right_hud_rect.has_point(event.position) and not bottom_hud_rect.has_point(event.position):
				# DeploymentController now handles formation vs single placement internally
				# via its _unhandled_input, so we don't need to call anything here
				pass  # Let DeploymentController handle it

func screen_to_world_position(screen_pos: Vector2) -> Vector2:
	# Convert screen position to world position using our transform
	var board_transform = $BoardRoot.transform
	return board_transform.affine_inverse() * screen_pos

func _process(delta: float) -> void:
	# View controls using BoardRoot transform
	var pan_speed = 800.0 * delta / view_zoom
	var view_changed = false
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		view_offset.y -= pan_speed
		view_changed = true
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		view_offset.y += pan_speed
		view_changed = true
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		view_offset.x -= pan_speed
		view_changed = true
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		view_offset.x += pan_speed
		view_changed = true
	
	# Zoom controls
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_PLUS):
		view_zoom *= 1.03
		view_zoom = clamp(view_zoom, 0.1, 3.0)
		view_changed = true
	if Input.is_key_pressed(KEY_MINUS):
		view_zoom *= 0.97
		view_zoom = clamp(view_zoom, 0.1, 3.0)
		view_changed = true
	
	# Focus commands
	if Input.is_key_pressed(KEY_F):
		focus_on_player2_zone()
		view_changed = true
	
	
	if view_changed:
		update_view_transform()

func reset_camera() -> void:
	camera.position = Vector2(
		SettingsService.get_board_width_px() / 2,
		SettingsService.get_board_height_px() / 2
	)
	camera.zoom = Vector2(0.3, 0.3)
	print("Camera reset to position: ", camera.position, " zoom: ", camera.zoom)

func update_view_transform() -> void:
	# Apply transform to BoardRoot to simulate camera movement
	var transform = Transform2D()
	transform = transform.scaled(Vector2(view_zoom, view_zoom))
	transform.origin = -view_offset * view_zoom
	$BoardRoot.transform = transform

func focus_on_player2_zone() -> void:
	var zone2 = BoardState.get_deployment_zone_for_player(2)
	if zone2.size() > 0:
		# Calculate center of the zone
		var center = Vector2.ZERO
		for point in zone2:
			center += point
		center /= zone2.size()
		
		view_offset = center - get_viewport().get_visible_rect().size / 2
		view_zoom = 0.8
		print("Focused view on Player 2 zone at: ", center)

func refresh_unit_list() -> void:
	# Update the new bottom panel unit lists (always visible for comparison)
	if unit_stats_panel and unit_stats_panel.has_method("populate_unit_lists"):
		var phase_name = GameStateData.Phase.keys()[current_phase]
		unit_stats_panel.populate_unit_lists(phase_name)
		print("Refreshed bottom panel unit lists for phase: ", phase_name)
	
	# Right panel unit list - phase-specific functionality
	unit_list.clear()
	var active_player = GameState.get_active_player()
	
	# Check if we're in multiplayer and if it's our turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	var is_multiplayer = network_manager and network_manager.is_networked()
	var is_my_turn = not is_multiplayer or network_manager.is_local_player_turn()
	var local_player = network_manager.get_local_player() if network_manager else active_player

	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			# Show only undeployed units during deployment in right panel
			unit_list.visible = true

			# Check if active player is AI — block human interaction
			var ai_player_node = get_node_or_null("/root/AIPlayer")
			if ai_player_node and ai_player_node.is_ai_player(active_player):
				unit_list.add_item("AI Player %d deploying..." % active_player)
				unit_list.set_item_disabled(0, true)
				if reserves_button:
					reserves_button.visible = false
				print("Refreshing right panel - AI player %d is deploying" % active_player)
				return

			# In multiplayer, only show units when it's your turn
			if is_multiplayer and not is_my_turn:
				unit_list.add_item("Waiting for Player %d to deploy..." % active_player)
				unit_list.set_item_disabled(0, true)
				print("Refreshing right panel - waiting for opponent (Player %d)" % active_player)
			else:
				var units = GameState.get_undeployed_units_for_player(active_player)
				print("Refreshing right panel unit list for deployment - found ", units.size(), " undeployed units (your turn)")

				for unit_id in units:
					var unit_data = GameState.get_unit(unit_id)
					var unit_name = unit_data["meta"]["name"]
					var model_count = unit_data["models"].size()
					# Add ability indicators for units with special deployment abilities
					var ability_tag = ""
					if GameState.unit_has_deep_strike(unit_id):
						ability_tag = " [DS]"
					elif GameState.unit_has_infiltrators(unit_id):
						ability_tag = " [INF]"
					var display_text = "%s (%d models)%s" % [unit_name, model_count, ability_tag]
					unit_list.add_item(display_text)
					unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)

				# Show reserves button during deployment (visible when units available)
				if reserves_button:
					reserves_button.visible = units.size() > 0
					reserves_button.disabled = true  # Disabled until a unit is selected
					_selected_unit_for_reserves = ""

		GameStateData.Phase.MOVEMENT:
			# Show deployed units during movement in right panel
			unit_list.visible = true
			var all_units = GameState.get_units_for_player(active_player)
			var deployed_count = 0
			var battle_round = GameState.get_battle_round()

			# Show reinforcements header if there are reserve units and it's Turn 2+
			var reserves = GameState.get_reserves_for_player(active_player)
			if reserves.size() > 0 and battle_round >= 2:
				unit_list.add_item("--- REINFORCEMENTS (Reserves) ---")
				unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)
				for reserve_id in reserves:
					var reserve_unit = GameState.get_unit(reserve_id)
					var reserve_name = reserve_unit.get("meta", {}).get("name", reserve_id)
					var reserve_type = reserve_unit.get("reserve_type", "strategic_reserves")
					var type_tag = "[DS]" if reserve_type == "deep_strike" else "[SR]"
					var model_count = reserve_unit.get("models", []).size()
					var display_text = "%s %s (%d models) - DEPLOY" % [type_tag, reserve_name, model_count]
					unit_list.add_item(display_text)
					unit_list.set_item_metadata(unit_list.get_item_count() - 1, reserve_id)
				unit_list.add_item("--- DEPLOYED UNITS ---")
				unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)
			elif reserves.size() > 0 and battle_round < 2:
				unit_list.add_item("(%d units in reserves - arrive Turn 2+)" % reserves.size())
				unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)

			for unit_id in all_units:
				var unit = all_units[unit_id]
				var unit_status = unit.get("status", 0)
				# Skip reserve units (shown above) and undeployed
				if unit_status == GameStateData.UnitStatus.IN_RESERVES:
					continue
				if unit_status >= GameStateData.UnitStatus.DEPLOYED and unit_status != GameStateData.UnitStatus.IN_RESERVES:
					var unit_name = unit.get("meta", {}).get("name", unit_id)
					var model_count = unit.get("models", []).size()
					var moved = unit.get("flags", {}).get("moved", false)
					var status = " [MOVED]" if moved else ""
					var display_text = "%s (%d models)%s" % [unit_name, model_count, status]
					unit_list.add_item(display_text)
					unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
					deployed_count += 1

			print("Refreshing right panel unit list for movement - found ", deployed_count, " deployed units, ", reserves.size(), " in reserves")
		
		GameStateData.Phase.SHOOTING:
			# Hide unit list during shooting phase - shooting controller handles its own UI
			unit_list.visible = false
			unit_list.clear()
			print("Refreshing right panel unit list for shooting - unit list hidden")
		
		GameStateData.Phase.CHARGE:
			# Hide unit list during charge phase - charge controller handles its own UI
			unit_list.visible = false
			unit_list.clear()
			print("Refreshing right panel unit list for charge - unit list hidden")
		
		GameStateData.Phase.FIGHT:
			# Hide unit list during fight phase - fight controller handles its own UI
			unit_list.visible = false
			unit_list.clear()
			print("Refreshing right panel unit list for fight - unit list hidden")
		
		_:
			# Default: show all units for active player in right panel
			unit_list.visible = true
			var all_units = GameState.get_units_for_player(active_player)
			for unit_id in all_units:
				var unit = all_units[unit_id]
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				var model_count = unit.get("models", []).size()
				var display_text = "%s (%d models)" % [unit_name, model_count]
				unit_list.add_item(display_text)
				unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)

func update_ui() -> void:
	var active_player = GameState.get_active_player()
	var player_text = "Player %d (%s)" % [
		active_player,
		"Defender" if active_player == 1 else "Attacker"
	]
	active_player_badge.text = player_text
	
	# Phase-specific UI updates
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			var all_deployed = GameState.all_units_deployed()
			print("Main: ⚠️ update_ui() - DEPLOYMENT phase - all_deployed: ", all_deployed)
			print("Main: ⚠️ Button state BEFORE change - disabled: ", phase_action_button.disabled, " text: '", phase_action_button.text, "'")
			DebugLogger.info("update_ui deployment check", {
				"all_deployed": all_deployed,
				"current_button_disabled": phase_action_button.disabled,
				"button_text": phase_action_button.text
			})

			# Update deployment progress indicator
			_update_deployment_progress()

			# Show reserves button during deployment phase
			if reserves_button:
				reserves_button.visible = current_phase == GameStateData.Phase.DEPLOYMENT and not all_deployed

			if all_deployed:
				phase_action_button.disabled = false
				# Check if any units are in reserves
				var p1_reserves = GameState.get_reserves_for_player(1).size()
				var p2_reserves = GameState.get_reserves_for_player(2).size()
				var reserves_text = ""
				if p1_reserves + p2_reserves > 0:
					reserves_text = " (%d units in reserves)" % (p1_reserves + p2_reserves)
				status_label.text = "All units deployed%s! Click 'End Deployment' to continue." % reserves_text
				print("Main: ⚠️ update_ui() - Setting button ENABLED (all deployed)")
				print("Main: ⚠️ Button state AFTER enable - disabled: ", phase_action_button.disabled)
			else:
				phase_action_button.disabled = true
				print("Main: ⚠️ update_ui() - Setting button DISABLED (not all deployed)")
				print("Main: ⚠️ Button state AFTER disable - disabled: ", phase_action_button.disabled)
				if deployment_controller and deployment_controller.is_placing():
					var unit_id = deployment_controller.get_current_unit()
					var unit_data = GameState.get_unit(unit_id)
					var unit_name = unit_data["meta"]["name"]
					var placed = deployment_controller.get_placed_count()
					var total = unit_data["models"].size()
					var mode_info = ""
					if deployment_controller.is_infiltrators_mode:
						mode_info = " [INFILTRATORS — >9\" from enemies & enemy zone]"
					status_label.text = "Placing: %s — %d/%d models%s" % [unit_name, placed, total, mode_info]
				else:
					# Check if it's our turn in multiplayer
					var network_manager = get_node_or_null("/root/NetworkManager")
					if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
						var local_player = network_manager.get_local_player()
						status_label.text = "Waiting for Player %d to deploy... (You are Player %d)" % [active_player, local_player]
					else:
						status_label.text = "Select a unit to deploy (or place in reserves)"
		
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				if movement_controller.active_mode != "":
					status_label.text = "Drag models to move them"
				else:
					status_label.text = "Choose movement type (Normal/Advance/etc.)"
			else:
				status_label.text = "Select a unit to move"
			phase_action_button.disabled = false

		_:
			status_label.text = "Phase: " + GameStateData.Phase.keys()[current_phase]
			phase_action_button.disabled = false

func _on_unit_selected(index: int) -> void:
	if deployment_controller and deployment_controller.is_placing():
		return

	# Block selection during AI player's turn
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(GameState.get_active_player()):
		print("Main: Blocking unit selection - AI player's turn")
		return

	# In multiplayer deployment, block selection if it's not your turn
	if current_phase == GameStateData.Phase.DEPLOYMENT:
		var network_manager = get_node_or_null("/root/NetworkManager")
		if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
			print("Main: Blocking unit selection - not your turn")
			return

	var unit_id = unit_list.get_item_metadata(index)

	# Show detailed stats in bottom panel
	var unit_data = GameState.get_unit(unit_id)
	print("Main: Unit selected - ", unit_id)
	print("Main: Unit data available - ", unit_data != null)
	print("Main: Unit stats panel available - ", unit_stats_panel != null)

	# Update transport panel for selected unit
	update_transport_panel(unit_id)

	if unit_data and unit_stats_panel:
		# Try the programmatic display_unit function stored as metadata
		var display_func = unit_stats_panel.get_meta("display_unit", null)
		if display_func:
			print("Main: Calling programmatic display_unit function")
			display_func.call(unit_data)
		elif unit_stats_panel.has_method("display_unit"):
			print("Main: Calling display_unit method")
			unit_stats_panel.display_unit(unit_data)
		else:
			print("Main: No display_unit method available!")
	
	# Handle unit selection based on current phase
	if current_phase == GameStateData.Phase.DEPLOYMENT and deployment_controller:
		# Update reserves button state for the selected unit
		if reserves_button:
			_selected_unit_for_reserves = unit_id
			reserves_button.disabled = false
			# Update button text based on unit abilities
			if GameState.unit_has_deep_strike(unit_id):
				reserves_button.text = "Deep Strike (Reserves)"
			else:
				reserves_button.text = "Strategic Reserves"

		# Check if this is a transport unit
		var unit_keywords = unit_data.get("meta", {}).get("keywords", [])
		if "TRANSPORT" in unit_keywords:
			# For transports, show dialog to select units to embark
			_show_transport_deployment_dialog(unit_id)
		else:
			# For non-transport units, deploy normally
			deployment_controller.begin_deploy(unit_id)
			show_unit_card(unit_id)
			unit_list.visible = false
	elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
		# Check if this is a reserve unit arriving as reinforcement
		var selected_unit = GameState.get_unit(unit_id)
		if selected_unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
			print("Main: Reserve unit selected for reinforcement: ", unit_id)
			_begin_reinforcement_placement(unit_id)
			return

		# Check if unit is embarked - route to disembark flow instead of normal move
		if selected_unit.get("embarked_in", null) != null:
			print("Main: Embarked unit selected, routing to disembark flow: ", unit_id)
			movement_controller.active_unit_id = unit_id
			movement_controller._handle_embarked_unit_selected(unit_id)
			update_ui()
			return

		# Pass unit selection to MovementController
		movement_controller.active_unit_id = unit_id
		print("Selected unit for movement: ", unit_id)

		# AUTO-START NORMAL MOVE FOR EASIER TESTING
		# In production, user would click a movement type button
		print("Auto-starting Normal Move for easier testing...")
		var action = {
			"type": "BEGIN_NORMAL_MOVE",
			"actor_unit_id": unit_id,
			"payload": {}
		}
		_on_movement_action_requested(action)
		status_label.text = "Drag models to move them (Normal Move mode)"

	update_ui()

func _on_unit_stats_panel_unit_selected(unit_id: String, is_enemy: bool) -> void:
	var unit_data = GameState.get_unit(unit_id)
	if not unit_data:
		print("Main: Unit not found - ", unit_id)
		return
	
	print("Main: Unit selected from bottom panel - ", unit_id, " (enemy: ", is_enemy, ")")
	
	# Show the unit card with unit info (but not during movement phase)
	if current_phase != GameStateData.Phase.MOVEMENT:
		show_unit_card(unit_id)
	
	# Handle selection based on phase and unit ownership
	if not is_enemy:  # Player unit selected
		# Handle unit selection based on current phase
		if current_phase == GameStateData.Phase.DEPLOYMENT and deployment_controller:
			# Check if this is a transport unit
			var unit_keywords = unit_data.get("meta", {}).get("keywords", [])
			if "TRANSPORT" in unit_keywords:
				# For transports, show dialog to select units to embark
				_show_transport_deployment_dialog(unit_id)
			else:
				# For non-transport units, deploy normally
				deployment_controller.begin_deploy(unit_id)
				unit_list.visible = false
		elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
			# Check if unit is embarked - route to disembark flow instead of normal move
			if unit_data.get("embarked_in", null) != null:
				print("Main: Embarked unit selected from stats panel, routing to disembark flow: ", unit_id)
				movement_controller.active_unit_id = unit_id
				movement_controller._handle_embarked_unit_selected(unit_id)
				return

			# Pass unit selection to MovementController
			movement_controller.active_unit_id = unit_id
			print("Selected unit for movement: ", unit_id)
			# REMOVED: update_movement_card_buttons() - MovementController handles its own UI

			# AUTO-START NORMAL MOVE FOR EASIER TESTING
			print("Auto-starting Normal Move for easier testing...")
			var action = {
				"type": "BEGIN_NORMAL_MOVE",
				"actor_unit_id": unit_id,
				"payload": {}
			}
			_on_movement_action_requested(action)
			status_label.text = "Drag models to move them (Normal Move mode)"
	else:  # Enemy unit selected
		# For enemy units, just show the card for viewing
		print("Enemy unit selected for viewing: ", unit_id)
		# Could add additional enemy-specific functionality here
	
	update_ui()

func show_unit_card(unit_id: String) -> void:
	var unit_data = GameState.get_unit(unit_id)
	unit_name_label.text = unit_data["meta"]["name"]
	keywords_label.text = "Keywords: " + ", ".join(unit_data["meta"]["keywords"])
	
	unit_card.visible = true
	update_unit_card_buttons()

func update_unit_card_buttons() -> void:
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if deployment_controller:
				var current_unit_id = deployment_controller.get_current_unit()
				if current_unit_id and current_unit_id != "":
					var unit_data = GameState.get_unit(current_unit_id)
					if unit_data and unit_data.has("models"):
						var placed = deployment_controller.get_placed_count()
						var total = unit_data["models"].size()
						
						models_label.text = "Models: %d/%d" % [placed, total]
						
						# Show buttons based on deployment progress
						undo_button.visible = placed > 0
						reset_button.visible = false  # No reset in deployment
						confirm_button.visible = placed == total
					else:
						# No active deployment, hide buttons
						undo_button.visible = false
						reset_button.visible = false
						confirm_button.visible = false
				else:
					# No unit being deployed, hide deployment buttons
					undo_button.visible = false
					reset_button.visible = false
					confirm_button.visible = false
		
		GameStateData.Phase.MOVEMENT:
			# CHANGE: Don't call update_movement_card_buttons() - MovementController manages its own UI
			unit_card.visible = false

func update_movement_card_buttons() -> void:
	if not movement_controller:
		return
	
	# EARLY EXIT: Don't show UnitCard during movement phase
	if current_phase == GameStateData.Phase.MOVEMENT:
		unit_card.visible = false
		return
	
	# Show movement buttons if there's an active move
	if movement_controller.active_unit_id != "":
		var unit_data = GameState.get_unit(movement_controller.active_unit_id)
		unit_name_label.text = unit_data.get("meta", {}).get("name", movement_controller.active_unit_id)
		
		# Show movement mode and cap
		var mode = movement_controller.active_mode
		var cap = movement_controller.move_cap_inches
		
		if mode != "":
			keywords_label.text = "Mode: %s" % mode
			models_label.text = "Move Cap: %.1f\" - Drag models to move" % cap
		else:
			keywords_label.text = "Select movement type:"
			models_label.text = "Normal Move / Advance / Fall Back"
		
		# Show/hide buttons based on move state
		# Try to get active_moves from the phase if it's a MovementPhase
		var has_model_moves = false
		if movement_controller.current_phase:
			# MovementPhase should have active_moves as a property
			if movement_controller.current_phase.get("active_moves") != null:
				var active_moves = movement_controller.current_phase.active_moves
				var move_data = active_moves.get(movement_controller.active_unit_id, {})
				has_model_moves = not move_data.get("model_moves", []).is_empty()
		
		undo_button.visible = has_model_moves
		reset_button.visible = has_model_moves
		confirm_button.visible = has_model_moves  # Can confirm if any moves made
		
		unit_card.visible = true
	else:
		# Hide unit card when no active move
		unit_card.visible = false
	
	# Update main status label
	update_ui()

func _on_undo_pressed() -> void:
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if deployment_controller:
				deployment_controller.undo()
				unit_card.visible = false
				unit_list.visible = true
				update_ui()
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				print("Undo button pressed for unit: ", movement_controller.active_unit_id)
				var action = {
					"type": "UNDO_LAST_MODEL_MOVE",
					"actor_unit_id": movement_controller.active_unit_id,
					"payload": {}
				}
				_on_movement_action_requested(action)

func _on_reset_pressed() -> void:
	match current_phase:
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				print("Reset button pressed for unit: ", movement_controller.active_unit_id)
				var action = {
					"type": "RESET_UNIT_MOVE",
					"actor_unit_id": movement_controller.active_unit_id,
					"payload": {}
				}
				_on_movement_action_requested(action)

func _on_confirm_pressed() -> void:
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if deployment_controller:
				deployment_controller.confirm()
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				print("Confirm button pressed for unit: ", movement_controller.active_unit_id)
				var action = {
					"type": "CONFIRM_UNIT_MOVE",
					"actor_unit_id": movement_controller.active_unit_id,
					"payload": {}
				}
				_on_movement_action_requested(action)

func _on_unit_confirmed() -> void:
	# Hide coherency warning when unit is confirmed
	if coherency_banner and is_instance_valid(coherency_banner):
		coherency_banner.visible = false
	unit_card.visible = false
	unit_list.visible = true
	refresh_unit_list()
	update_ui()

func _on_models_placed_changed() -> void:
	print("Main: ⚠️ _on_models_placed_changed() called")
	DebugLogger.info("Models placed changed signal received", {})

	update_unit_card_buttons()

	print("Main: Calling update_ui() after models_placed_changed")
	update_ui()

	# Check if all units are deployed now
	var all_units_deployed = GameState.all_units_deployed()
	print("Main: ⚠️ After update_ui - all_units_deployed: ", all_units_deployed, " button_disabled: ", phase_action_button.disabled)
	DebugLogger.info("After models_placed update_ui", {
		"all_units_deployed": all_units_deployed,
		"button_disabled": phase_action_button.disabled,
		"button_text": phase_action_button.text,
		"button_visible": phase_action_button.visible
	})

func _on_deployment_side_changed(player: int) -> void:
	refresh_unit_list()
	update_ui()
	update_deployment_zone_visibility()

func _on_deployment_complete() -> void:
	status_label.text = "Deployment complete!"
	phase_action_button.disabled = false

func _on_end_deployment_pressed() -> void:
	print("Main: ========== _on_end_deployment_pressed CALLED ==========")
	DebugLogger.info("_on_end_deployment_pressed called", {
		"current_phase": GameStateData.Phase.keys()[current_phase]
	})

	# Route end-phase actions through the action system for multiplayer sync
	var action = {}
	var active_player = GameState.get_active_player()

	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			print("Main: Ending deployment phase via action system...")
			DebugLogger.info("Ending deployment phase", {})
			action = {"type": "END_DEPLOYMENT", "player": active_player}

		GameStateData.Phase.MOVEMENT:
			print("Ending movement phase via action system...")
			action = {"type": "END_MOVEMENT", "player": active_player}

		GameStateData.Phase.SHOOTING:
			print("Ending shooting phase via action system...")
			action = {"type": "END_SHOOTING", "player": active_player}

		GameStateData.Phase.MORALE:
			print("Ending morale phase via action system...")
			action = {"type": "END_MORALE", "player": active_player}

		_:
			print("Ending phase: ", current_phase, " via action system...")
			# Generic end-phase action
			action = {"type": "END_PHASE", "player": active_player}

	# Route through NetworkIntegration for multiplayer support
	if action.has("type"):
		print("Main: ⚠️ Calling NetworkIntegration.route_action with action: ", action)
		DebugLogger.info("Routing END_DEPLOYMENT action", {"action_type": action.type})

		var result = NetworkIntegration.route_action(action)

		print("Main: ⚠️ NetworkIntegration.route_action returned: ", result)
		DebugLogger.info("END_DEPLOYMENT action result", {
			"result": result,
			"pending": result.get("pending", false),
			"success": result.get("success", false),
			"error": result.get("error", "none")
		})

		if result.get("pending", false):
			print("Main: End-phase action submitted to network")
		elif result.get("success", false):
			print("Main: End-phase action succeeded")
		else:
			print("Main: ⚠️ End-phase action FAILED: ", result.get("error", "Unknown"))
			DebugLogger.info("END_DEPLOYMENT FAILED", {"error": result.get("error", "Unknown")})

func _perform_quick_save() -> void:
	print("========================================")
	print("QUICK SAVE TRIGGERED WITH [ KEY")
	print("========================================")
	print("Current game state meta: ", GameState.state.get("meta", {}))
	
	# Show immediate UI feedback
	_show_save_notification("Save debug started...", Color.YELLOW)
	
	# Debug: Run save system test
	_debug_save_system()
	
	var success = SaveLoadManager.quick_save()
	print("========================================")
	print("QUICK SAVE RESULT: ", success)
	print("========================================")
	if success:
		_show_save_notification("Game saved!", Color.GREEN)
	else:
		_show_save_notification("Save failed!", Color.RED)

func _debug_save_system():
	print("\n=== Quick Save Debug ===")
	
	# Check if save directory exists
	var dir = DirAccess.open("res://")
	if dir and dir.dir_exists("saves"):
		print("✅ saves directory exists")
	else:
		print("❌ saves directory missing")
	
	# Test GameState
	var snapshot = GameState.create_snapshot()
	print("GameState snapshot keys: ", snapshot.keys())
	print("GameState snapshot size: ", snapshot.size())
	
	# Test StateSerializer
	if StateSerializer:
		var serialized = StateSerializer.serialize_game_state(snapshot)
		print("Serialized data length: ", serialized.length())
		if serialized.length() > 0:
			print("✅ Serialization successful")
		else:
			print("❌ Serialization failed")
	else:
		print("❌ StateSerializer not available")
	
	print("=== Debug Complete ===\n")

func _perform_quick_load() -> void:
	print("========================================")
	print("QUICK LOAD TRIGGERED WITH ] KEY")
	print("========================================")
	print("Pre-load game state meta: ", GameState.state.get("meta", {}))

	# Check if we're in multiplayer as a client
	if NetworkManager and NetworkManager.is_networked() and not NetworkManager.is_host():
		_show_save_notification("Only host can load games in multiplayer", Color.RED)
		push_warning("Main: Client attempted to load during multiplayer - blocked")
		return

	# Show immediate UI feedback
	_show_save_notification("Loading...", Color.YELLOW)
	
	# Debug: Check if save file exists
	_debug_load_system()
	
	var success = SaveLoadManager.quick_load()
	print("========================================")
	print("QUICK LOAD RESULT: ", success)
	print("Post-load game state meta: ", GameState.state.get("meta", {}))
	print("========================================")
	
	if success:
		_show_save_notification("Game loaded!", Color.BLUE)
		
		# ENHANCEMENT: Clear UI before phase setup
		_clear_right_panel_phase_ui()
		
		# Update current phase
		current_phase = GameState.get_current_phase()
		print("Loaded phase: ", GameStateData.Phase.keys()[current_phase])
		
		# Sync BoardState with loaded GameState (for visual components)
		_sync_board_state_with_game_state()
		
		# Recreate phase controllers for the loaded phase
		await setup_phase_controllers()
		
		# NEW: Give controllers time to initialize before UI refresh
		await get_tree().process_frame
		
		# Refresh all UI elements
		refresh_unit_list()
		update_ui()
		update_ui_for_phase()
		update_deployment_zone_visibility()
		
		# Recreate visual tokens for deployed units
		_recreate_unit_visuals()
		
		# Notify PhaseManager of the loaded state
		if PhaseManager.has_method("transition_to_phase"):
			PhaseManager.transition_to_phase(current_phase)
	else:
		_show_save_notification("Load failed - No save found!", Color.RED)

func _sync_board_state_with_game_state() -> void:
	# Sync the legacy BoardState with the loaded GameState
	print("Syncing BoardState with loaded GameState...")
	
	var units = GameState.state.get("units", {})
	print("Loaded units count: ", units.size())
	
	# Update BoardState units (for legacy visual components)
	for unit_id in units:
		var unit = units[unit_id]
		if BoardState.units.has(unit_id):
			# Update existing unit
			BoardState.units[unit_id]["status"] = unit.get("status", BoardState.UnitStatus.UNDEPLOYED)
			BoardState.units[unit_id]["models"] = unit.get("models", [])
			print("Updated BoardState unit: ", unit_id, " status: ", unit.get("status", 0))
		else:
			# Add new unit to BoardState
			BoardState.units[unit_id] = unit
			print("Added new unit to BoardState: ", unit_id)

func _recreate_unit_visuals() -> void:
	# Clear existing tokens
	print("Clearing existing token visuals...")
	for child in token_layer.get_children():
		child.queue_free()
	
	# Wait a frame for queue_free to process
	await get_tree().process_frame
	
	# Recreate tokens for deployed units
	var units = GameState.state.get("units", {})
	var tokens_created = 0
	
	print("Recreating token visuals from ", units.size(), " units in GameState...")
	
	for unit_id in units:
		var unit = units[unit_id]
		print("  Processing unit ", unit_id, " - status: ", unit.get("status", 0))

		# Skip embarked units - they shouldn't be visible
		if unit.get("embarked_in", null) != null:
			print("    Unit is embarked - skipping visual creation")
			continue

		# Render units that are deployed or have moved/acted
		var status = unit.get("status", 0)
		if status >= GameStateData.UnitStatus.DEPLOYED:
			var models = unit.get("models", [])
			print("    Unit has ", models.size(), " models")
			
			for i in range(models.size()):
				var model = models[i]
				var pos = model.get("position")
				var model_id = model.get("id", "m%d" % (i+1))
				
				print("      Model ", model_id, " position: ", pos)
				
				if pos != null and model.get("alive", true):
					# Create visual token
					var token = _create_token_visual(unit_id, model)
					if token:
						token_layer.add_child(token)
						
						# Set position based on format
						var final_pos: Vector2
						if pos is Dictionary:
							final_pos = Vector2(pos.x, pos.y)
						else:
							final_pos = pos
							
						token.position = final_pos
						tokens_created += 1
						
						print("        Created token at ", final_pos)
				else:
					print("        Skipped model (no position or dead)")
	
	print("Recreated ", tokens_created, " unit tokens")

func _create_token_visual(unit_id: String, model: Dictionary) -> Node2D:
	# Use the existing TokenVisual class
	var token = preload("res://scripts/TokenVisual.gd").new()

	# Set properties
	var unit = GameState.get_unit(unit_id)
	token.owner_player = unit.get("owner", 1)
	token.is_preview = false

	# Pass complete model data for base shape handling
	token.set_model_data(model)

	# Extract model number from ID (e.g., "m1" -> 1)
	var model_id = model.get("id", "m1")
	if model_id.begins_with("m"):
		token.model_number = model_id.substr(1).to_int()
	else:
		token.model_number = 1

	# Set metadata for charge movement and other controllers
	token.set_meta("unit_id", unit_id)
	token.set_meta("model_id", model_id)

	# Redraw now that unit_id meta is set (needed for overlay glyphs)
	token.queue_redraw()

	return token

func update_unit_visuals(unit_id: String) -> void:
	"""Update visual tokens for a specific unit"""
	print("╔══════════════════════════════════════════════════════════════════")
	print("║ Main.update_unit_visuals() CALLED")
	print("║ unit_id: ", unit_id)
	print("╚══════════════════════════════════════════════════════════════════")

	var unit = GameState.get_unit(unit_id)
	print("Main: Unit lookup result:")
	print("  - unit.is_empty(): ", unit.is_empty())

	if unit.is_empty():
		push_error("Main: ❌ Unit not found in GameState: ", unit_id)
		return

	print("Main: Unit found: ", unit.get("meta", {}).get("name", unit_id))

	# Iterate through model tokens in TokenLayer (NOT BoardView!)
	var token_layer = $BoardRoot/TokenLayer
	print("Main: TokenLayer lookup:")
	print("  - token_layer is null: ", token_layer == null)

	if not token_layer:
		push_error("Main: ❌ TokenLayer not found!")
		return

	print("Main: TokenLayer found at: ", token_layer.get_path())

	var models = unit.get("models", [])
	print("Main: Unit has %d models" % models.size())

	var tokens_updated = 0
	var tokens_hidden = 0
	var tokens_not_found = 0

	for i in range(models.size()):
		var model = models[i]
		var model_id = model.get("id", "m%d" % i)
		var model_alive = model.get("alive", true)

		print("Main: Processing model %d/%d: %s (alive=%s)" % [i+1, models.size(), model_id, model_alive])

		# Find token visual for this model BY METADATA (tokens don't have names!)
		print("  - Searching token_layer children for unit_id=%s, model_id=%s" % [unit_id, model_id])

		var token = null
		for child in token_layer.get_children():
			if child.has_meta("unit_id") and child.has_meta("model_id"):
				if child.get_meta("unit_id") == unit_id and child.get_meta("model_id") == model_id:
					token = child
					break

		print("  - token found: ", token != null)

		if token:
			print("  - Token found at: ", token.get_path())
			print("  - Token visible before: ", token.visible)

			if model_alive:
				# Model is alive → ensure visible
				token.visible = true
				print("  - ✅ Model alive → token.visible = true")
			else:
				# Model is dead → hide token
				token.visible = false
				tokens_hidden += 1
				print("╔══════════════════════════════════════════════════════════════════")
				print("║ ✅ 💀 MODEL TOKEN HIDDEN")
				print("║ Unit: ", unit_id)
				print("║ Model: ", model_id)
				print("║ Token path: ", token.get_path())
				print("║ Token visible: false")
				print("╚══════════════════════════════════════════════════════════════════")

			tokens_updated += 1
		else:
			tokens_not_found += 1
			push_error("Main: ⚠ Token not found for unit_id=%s, model_id=%s" % [unit_id, model_id])

	print("╔══════════════════════════════════════════════════════════════════")
	print("║ Main.update_unit_visuals() COMPLETE")
	print("║ Unit: ", unit_id)
	print("║ Models processed: ", models.size())
	print("║ Tokens updated: ", tokens_updated)
	print("║ Tokens hidden: ", tokens_hidden)
	print("║ Tokens not found: ", tokens_not_found)
	print("╚══════════════════════════════════════════════════════════════════")

func refresh_all_model_visuals() -> void:
	"""Refresh visual state of all model tokens based on GameState"""
	var units = GameState.state.get("units", {})

	for unit_id in units:
		update_unit_visuals(unit_id)

	print("Main: Refreshed all model visuals")

func _debug_load_system():
	print("\n=== Quick Load Debug ===")
	
	# Check if save file exists
	var file_path = "res://saves/quicksave.w40ksave"
	if FileAccess.file_exists(file_path):
		print("✅ Quicksave file exists at: ", file_path)
		
		# Try to read the file
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			print("File size: ", content.length(), " bytes")
			
			# Try to parse it
			var json = JSON.new()
			var parse_result = json.parse(content)
			if parse_result == OK:
				var data = json.data
				print("✅ JSON parse successful")
				print("Save contains keys: ", data.keys())
				if data.has("state"):
					print("State meta: ", data["state"].get("meta", {}))
			else:
				print("❌ JSON parse failed: ", parse_result)
		else:
			print("❌ Could not open file for reading")
	else:
		print("❌ Quicksave file does not exist")
	
	# Check SaveLoadManager state
	if SaveLoadManager:
		print("✅ SaveLoadManager exists")
	else:
		print("❌ SaveLoadManager not available")
	
	print("=== Debug Complete ===\n")

func _show_save_notification(message: String, color: Color) -> void:
	# Simple notification using the status label temporarily
	var original_text = status_label.text
	var original_color = status_label.modulate
	
	status_label.text = message
	status_label.modulate = color
	
	# Create a timer to restore original text after 2 seconds
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(func():
		status_label.text = original_text
		status_label.modulate = original_color
		timer.queue_free()
	)
	add_child(timer)
	timer.start()

func _on_save_completed(file_path: String, metadata: Dictionary) -> void:
	print("Save completed: %s" % file_path)
	if OS.has_feature("web"):
		_show_save_notification("Game saved!", Color.GREEN)

func _on_load_completed(file_path: String, metadata: Dictionary) -> void:
	print("Load completed: %s" % file_path)

	# Clear debug visualizations after load
	_clear_debug_visualizations()

	if OS.has_feature("web"):
		# On web, load is async - apply state now that data arrived
		_show_save_notification("Game loaded!", Color.BLUE)
		call_deferred("_apply_loaded_state")
	else:
		# Force UI refresh after loading
		call_deferred("_refresh_after_load")

# Helper method to clear debug visualizations safely
func _clear_debug_visualizations() -> void:
	var board_root = get_node_or_null("BoardRoot")
	if not board_root:
		return

	var los_debug = board_root.get_node_or_null("LoSDebugVisual")
	if los_debug and is_instance_valid(los_debug) and los_debug.has_method("clear_all_debug_visuals"):
		los_debug.clear_all_debug_visuals()

func _on_save_failed(error: String) -> void:
	print("Save failed: %s" % error)
	if OS.has_feature("web"):
		_show_save_notification("Save failed: " + error, Color.RED)

func _on_load_failed(error: String) -> void:
	print("Load failed: %s" % error)
	if OS.has_feature("web"):
		_show_save_notification("Load failed: " + error, Color.RED)

func _on_delete_completed_main(save_name: String) -> void:
	print("Main: Cloud delete completed: ", save_name)
	_show_save_notification("Save deleted!", Color.ORANGE)

func _apply_loaded_state() -> void:
	print("Main: _apply_loaded_state() called")

	# ENHANCEMENT: Clear UI before phase setup
	_clear_right_panel_phase_ui()

	# Update current phase
	current_phase = GameState.get_current_phase()

	# Sync BoardState with loaded GameState
	_sync_board_state_with_game_state()

	# Recreate phase controllers for the loaded phase
	await setup_phase_controllers()

	# Give controllers time to initialize
	await get_tree().process_frame

	# Refresh all UI elements
	refresh_unit_list()
	update_ui()
	update_ui_for_phase()
	update_deployment_zone_visibility()

	# Recreate visual tokens for deployed units
	_recreate_unit_visuals()

	# Notify PhaseManager of the loaded state
	if PhaseManager.has_method("transition_to_phase"):
		PhaseManager.transition_to_phase(current_phase)

	print("Main: _apply_loaded_state() complete")

# Multiplayer sync handler - called when guest receives initial state or game starts
func _on_network_game_started() -> void:
	print("Main: Network game started signal received")

	# Refresh all visuals and UI after receiving initial state
	if NetworkManager and NetworkManager.is_networked():
		print("Main: Refreshing UI after network game started")

		# Recreate unit visuals
		_recreate_unit_visuals()

		# Refresh unit lists
		refresh_unit_list()

		# Update UI
		update_ui()
		update_ui_for_phase()
		update_deployment_zone_visibility()

		print("Main: UI refresh complete after network game started")

# Multiplayer sync handler
func _on_network_result_applied(result: Dictionary) -> void:
	print("Main: Network result applied, recreating visuals")

	# Check if phase changed
	var diffs = result.get("diffs", [])
	var phase_changed = false
	var new_phase = null

	for diff in diffs:
		if diff.get("op") == "set" and diff.get("path") == "meta.phase":
			phase_changed = true
			new_phase = diff.get("value")
			break

	# If phase changed, update phase managers and controllers
	if phase_changed and new_phase != null:
		print("Main: Phase changed via network to: ", new_phase)
		current_phase = new_phase

		# Transition PhaseManager to new phase
		if PhaseManager and PhaseManager.has_method("transition_to_phase"):
			print("Main: Transitioning PhaseManager to phase: ", new_phase)
			PhaseManager.transition_to_phase(new_phase)

		# Wait for phase transition
		await get_tree().process_frame

		# Recreate phase controllers for new phase
		print("Main: Recreating phase controllers for new phase")
		await setup_phase_controllers()

		# Update phase-specific UI
		update_ui_for_phase()

	# Check if this is a staging action (doesn't modify GameState, only phase-local state)
	# These actions already update visuals via signals, so skip recreation
	var action_type = result.get("action_type", "")
	var is_staging_action = action_type in [
		"STAGE_MODEL_MOVE",           # Movement staging
		"PREVIEW_MODEL_MOVE",         # Movement preview
		"BEGIN_NORMAL_MOVE",          # Movement initialization
		"BEGIN_ADVANCE",              # Movement initialization
		"BEGIN_FALL_BACK",            # Movement initialization
		"LOCK_MOVEMENT_MODE",         # Movement mode lock
		"SET_ADVANCE_BONUS",          # Movement dice roll
		"UNDO_LAST_MODEL_MOVE",       # Movement undo (handles own visuals)
		"RESET_UNIT_MOVE",            # Movement reset (handles own visuals)
		"SELECT_TARGET",              # Shooting target selection
		"DECLARE_CHARGE",             # Charge declaration
	]

	# Only recreate visuals if state actually changed in GameState
	if not is_staging_action and diffs.size() > 0:
		# Recreate unit visuals to reflect the new state
		_recreate_unit_visuals()
	elif not is_staging_action:
		print("Main: Skipping visual recreation - no state changes")

	# Update UI to show current state
	update_ui()
	refresh_unit_list()

# Save/Load Dialog handlers
func _toggle_save_load_menu() -> void:
	if save_load_dialog.visible:
		save_load_dialog.hide()
		print("Save/Load dialog hidden")
	else:
		# Show the dialog and ensure it gets focus
		save_load_dialog.show_dialog()
		print("Save/Load dialog shown")

func _on_main_menu_requested() -> void:
	print("Main: Returning to Main Menu")
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_save_requested(save_name: String) -> void:
	print("Main: Save requested with name: ", save_name)

	# Create metadata with user description
	var user_description = save_name
	var metadata = {
		"type": "manual",
		"description": user_description
	}

	# Show saving notification
	_show_save_notification("Saving...", Color.YELLOW)

	# Perform save (on web this is async - result comes via signals)
	var success = SaveLoadManager.save_game(save_name, metadata)
	if not success:
		_show_save_notification("Save failed!", Color.RED)

func _on_load_requested(save_file: String, owner_id: String = "") -> void:
	print("Main: Load requested for file: ", save_file, " (owner_id: ", owner_id, ")")

	# Show loading notification
	_show_save_notification("Loading...", Color.YELLOW)

	# Perform load (on web this is async - result comes via load_completed/load_failed signals)
	var success = SaveLoadManager.load_game(save_file, owner_id)
	if not OS.has_feature("web"):
		# Desktop: synchronous result
		if success:
			_show_save_notification("Game loaded!", Color.BLUE)
			_apply_loaded_state()
		else:
			_show_save_notification("Load failed!", Color.RED)

func _on_delete_requested(save_file: String) -> void:
	print("Main: Delete requested for file: ", save_file)

	# Perform deletion (on web this is async - result comes via delete_completed signal)
	var success = SaveLoadManager.delete_save_file(save_file)
	if OS.has_feature("web"):
		_show_save_notification("Deleting...", Color.YELLOW)
	elif success:
		_show_save_notification("Save deleted!", Color.ORANGE)
		print("Save file deleted successfully: ", save_file)
	else:
		_show_save_notification("Delete failed!", Color.RED)
		print("Failed to delete save file: ", save_file)

func _refresh_after_load() -> void:
	# Completely refresh the UI to match loaded state
	print("Main: _refresh_after_load() called")

	# Get the current phase from GameState
	current_phase = GameState.get_current_phase()
	print("Main: Loaded phase is: ", current_phase)

	# CRITICAL: Transition PhaseManager to loaded phase FIRST
	# This creates the phase instance that controllers will reference
	print("Main: Transitioning PhaseManager to loaded phase: ", current_phase)
	if PhaseManager and PhaseManager.has_method("transition_to_phase"):
		PhaseManager.transition_to_phase(current_phase)
		print("Main: Phase transition complete")
	else:
		print("Main: WARNING - Could not transition to phase (PhaseManager not available)")

	# Wait one frame for phase transition to complete
	await get_tree().process_frame

	# CRITICAL: Recreate phase controllers for the loaded phase
	# This ensures phase-specific UI (like "End Command Phase" button) works
	# Controllers will now reference the correct phase instance from PhaseManager
	print("Main: Recreating phase controllers after load...")
	await setup_phase_controllers()

	# Wait one frame for controllers to initialize
	await get_tree().process_frame

	# Refresh UI elements
	refresh_unit_list()
	update_ui()
	update_deployment_zone_visibility()

	# CRITICAL: Recreate unit visuals on the battlefield
	print("Main: Recreating unit visuals after load...")
	_recreate_unit_visuals()
	print("Main: Unit visuals recreated")

	# Clear any active deployment
	if deployment_controller and deployment_controller.is_placing():
		deployment_controller.undo()

	# Update phase-specific UI
	update_ui_for_phase()

	print("Main: _refresh_after_load() complete")

func update_deployment_zone_visibility() -> void:
	# Show the active player's zone more prominently
	var active_player = GameState.get_active_player()
	if active_player == 1:
		p1_zone.modulate = Color(0, 0, 1, 0.6)  # Brighter blue for active
		p2_zone.modulate = Color(1, 0, 0, 0.3)  # Visible red for inactive
		p1_zone.visible = true
		p2_zone.visible = true
		# Set active borders
		if p1_zone.has_method("set_active"):
			p1_zone.set_active(true)
			p1_zone.border_color = Color(0, 0.3, 1, 1)
		if p2_zone.has_method("set_active"):
			p2_zone.set_active(false)
	else:
		p1_zone.modulate = Color(0, 0, 1, 0.3)  # Visible blue for inactive
		p2_zone.modulate = Color(1, 0, 0, 0.6)  # Brighter red for active
		p1_zone.visible = true
		p2_zone.visible = true
		# Set active borders
		if p1_zone.has_method("set_active"):
			p1_zone.set_active(false)
		if p2_zone.has_method("set_active"):
			p2_zone.set_active(true)
			p2_zone.border_color = Color(1, 0.3, 0, 1)

# Phase management handlers
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	current_phase = new_phase
	print("Phase changed to: ", GameStateData.Phase.keys()[new_phase])
	print("Active player: ", GameState.get_active_player())

	# Clear transport panel when phase changes
	update_transport_panel("")

	await setup_phase_controllers()
	update_ui_for_phase()
	
	# Debug: Check what units are available
	if current_phase == GameStateData.Phase.MOVEMENT:
		# Need to wait a frame for the phase to set the active player
		await get_tree().process_frame
		var active_player = GameState.get_active_player()
		var units = GameState.get_units_for_player(active_player)
		print("Units available for player ", active_player, ":")
		for unit_id in units:
			var unit = units[unit_id]
			print("  - ", unit_id, " (status: ", unit.get("status", 0), ")")
		
		# Re-refresh the UI after player change
		refresh_unit_list()
		update_ui()

func _on_phase_completed(phase: GameStateData.Phase) -> void:
	print("Phase completed: ", GameStateData.Phase.keys()[phase])

func _get_phase_label_text(phase: GameStateData.Phase) -> String:
	match phase:
		GameStateData.Phase.DEPLOYMENT: return "Deployment Phase"
		GameStateData.Phase.COMMAND: return "Command Phase"
		GameStateData.Phase.MOVEMENT: return "Movement Phase"
		GameStateData.Phase.SHOOTING: return "Shooting Phase"
		GameStateData.Phase.CHARGE: return "Charge Phase"
		GameStateData.Phase.FIGHT: return "Fight Phase"
		GameStateData.Phase.SCORING: return "Scoring Phase"
		GameStateData.Phase.MORALE: return "Morale Phase"
		_: return "Unknown Phase"

func _get_phase_button_text(phase: GameStateData.Phase) -> String:
	match phase:
		GameStateData.Phase.DEPLOYMENT: return "End Deployment"
		GameStateData.Phase.COMMAND: return "End Command Phase"
		GameStateData.Phase.MOVEMENT: return "End Movement Phase"
		GameStateData.Phase.SHOOTING: return "End Shooting Phase"
		GameStateData.Phase.CHARGE: return "End Charge Phase"
		GameStateData.Phase.FIGHT: return "End Fight Phase"
		GameStateData.Phase.SCORING: return "End Turn"
		GameStateData.Phase.MORALE: return "End Morale Phase"
		_: return "End Phase"

func _clear_phase_ui_artifacts() -> void:
	# Remove any dynamically added phase-specific buttons from HUD_Bottom
	var hbox = get_node_or_null("HUD_Bottom/HBoxContainer")
	if not hbox:
		return

	for child in hbox.get_children():
		if child.name in ["ScoringControls", "MovementButtons", "EndChargePhaseButton",
						  "CommandControls", "ChargeControls"]:
			print("Main: Removing phase UI artifact: ", child.name)
			hbox.remove_child(child)
			child.queue_free()

func _on_phase_action_pressed() -> void:
	# Handle phase action button press based on current phase
	print("Main: ========== PHASE ACTION BUTTON PRESSED ==========")
	print("Main: ⚠️⚠️⚠️ BUTTON WAS ACTUALLY CLICKED ⚠️⚠️⚠️")
	print("Main: Current phase: ", GameStateData.Phase.keys()[current_phase])
	print("Main: Button text: ", phase_action_button.text)
	print("Main: Button disabled: ", phase_action_button.disabled)
	DebugLogger.info("⚠️ Phase action button CLICKED", {
		"phase": GameStateData.Phase.keys()[current_phase],
		"button_text": phase_action_button.text,
		"button_disabled": phase_action_button.disabled,
		"timestamp": Time.get_ticks_msec()
	})

	# For multiplayer sync, we need to route phase end actions through the network system
	var action = {}
	var active_player = GameState.get_active_player()

	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			_on_end_deployment_pressed()  # Already handles network routing
			return
		GameStateData.Phase.COMMAND:
			action = {"type": "END_COMMAND", "player": active_player}
		GameStateData.Phase.MOVEMENT:
			action = {"type": "END_MOVEMENT", "player": active_player}
		GameStateData.Phase.SHOOTING:
			action = {"type": "END_SHOOTING", "player": active_player}
		GameStateData.Phase.CHARGE:
			action = {"type": "END_CHARGE", "player": active_player}
		GameStateData.Phase.FIGHT:
			action = {"type": "END_FIGHT", "player": active_player}
		GameStateData.Phase.SCORING:
			if GameState.is_game_complete():
				print("Main: Game is complete, cannot advance phase")
				return
			action = {"type": "END_SCORING", "player": active_player}
		GameStateData.Phase.MORALE:
			action = {"type": "END_MORALE", "player": active_player}
		_:
			print("WARNING: Unknown phase for action button: ", current_phase)
			return

	# Route through NetworkIntegration for multiplayer sync
	print("Main: Routing phase end action through network: ", action.type)
	var result = NetworkIntegration.route_action(action)

	if not result.get("success", false):
		print("Main: Failed to end phase: ", result.get("error", "Unknown error"))
		# If network routing fails, try local advance as fallback for single player
		if not NetworkManager.is_networked():
			print("Main: Falling back to local phase advance")
			PhaseManager.advance_to_next_phase()

func update_ui_for_phase() -> void:
	# Clear any phase-specific UI artifacts first
	_clear_phase_ui_artifacts()

	print("Main: ========== UPDATE UI FOR PHASE ==========")
	print("Main: Current phase: ", GameStateData.Phase.keys()[current_phase])
	DebugLogger.info("update_ui_for_phase START", {
		"phase": GameStateData.Phase.keys()[current_phase],
		"button_exists": phase_action_button != null,
		"button_path": phase_action_button.get_path() if phase_action_button else "null"
	})
	DebugLogger.info("Updating UI for phase", {
		"phase": GameStateData.Phase.keys()[current_phase]
	})

	# Update phase label
	phase_label.text = _get_phase_label_text(current_phase)

	# Configure the single action button for current phase
	phase_action_button.visible = true
	phase_action_button.text = _get_phase_button_text(current_phase)

	# Set initial disabled state based on phase
	# Deployment phase starts disabled (enabled when all units deployed)
	# Other phases start enabled
	if current_phase == GameStateData.Phase.DEPLOYMENT:
		# Check if all units are deployed to determine button state
		var all_deployed = GameState.all_units_deployed()
		phase_action_button.disabled = not all_deployed
		print("Main: Deployment phase - all_units_deployed: ", all_deployed, " button_disabled: ", phase_action_button.disabled)
		DebugLogger.info("Deployment button state", {
			"all_deployed": all_deployed,
			"button_disabled": phase_action_button.disabled
		})
	else:
		phase_action_button.disabled = false

	print("Main: Phase button configured - text: '", phase_action_button.text, "' visible: ", phase_action_button.visible, " disabled: ", phase_action_button.disabled)
	DebugLogger.info("Phase button configured", {
		"text": phase_action_button.text,
		"visible": phase_action_button.visible,
		"disabled": phase_action_button.disabled
	})

	# Disconnect all previous connections
	var was_connected = phase_action_button.pressed.is_connected(_on_phase_action_pressed)
	if was_connected:
		phase_action_button.pressed.disconnect(_on_phase_action_pressed)
		print("Main: Disconnected previous phase action button connection")

	# Connect to the standardized handler
	phase_action_button.pressed.connect(_on_phase_action_pressed)
	print("Main: Connected phase action button to _on_phase_action_pressed")

	# Verify the connection worked
	var is_now_connected = phase_action_button.pressed.is_connected(_on_phase_action_pressed)
	print("Main: ⚠️ VERIFICATION - Button connected: ", is_now_connected)
	DebugLogger.info("Phase button signal connected", {
		"was_previously_connected": was_connected,
		"is_now_connected": is_now_connected,
		"connection_verified": is_now_connected
	})

	# Show/hide deployment progress indicator based on phase
	if deployment_progress_container:
		deployment_progress_container.visible = (current_phase == GameStateData.Phase.DEPLOYMENT)
		if current_phase == GameStateData.Phase.DEPLOYMENT:
			_update_deployment_progress()

	# Phase-specific UI configurations (zones, panels, etc.)
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			# Show deployment zones
			p1_zone.visible = true
			p2_zone.visible = true
			# Hide movement action buttons during deployment
			_show_movement_action_buttons(false)
			# Show unit list and unit card during deployment phase
			unit_list.visible = true
			unit_card.visible = true
			# Update button state based on deployment status
			if GameState.all_units_deployed():
				phase_action_button.disabled = false

		GameStateData.Phase.COMMAND:
			# Hide deployment zones during command phase
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons during command
			_show_movement_action_buttons(false)
			# Hide unit list and unit card during command phase
			unit_list.visible = false
			unit_card.visible = false

		GameStateData.Phase.MOVEMENT:
			# Hide deployment zones during movement
			p1_zone.visible = false
			p2_zone.visible = false
			# Show movement action buttons
			_show_movement_action_buttons(true)
			# Show unit list and unit card during movement phase
			unit_list.visible = true
			unit_card.visible = true

		GameStateData.Phase.SHOOTING:
			# Hide deployment zones
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Hide unit list and unit card during shooting phase
			unit_list.visible = false
			unit_card.visible = false

		GameStateData.Phase.CHARGE:
			# Hide deployment zones
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Hide unit list and unit card during charge phase
			unit_list.visible = false
			unit_card.visible = false

		GameStateData.Phase.FIGHT:
			# Hide deployment zones
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Hide unit list and unit card - FightController provides its own right panel
			unit_list.visible = false
			unit_card.visible = false

		GameStateData.Phase.SCORING:
			# Hide deployment zones
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Hide unit list and unit card during scoring phase
			unit_list.visible = false
			unit_card.visible = false

		GameStateData.Phase.MORALE:
			# Hide deployment zones
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Show unit list and unit card
			unit_list.visible = true
			unit_card.visible = true

	refresh_unit_list()
	update_ui()

func _on_movement_action_requested(action: Dictionary) -> void:
	print("Main: Received movement action request: ", action.type)

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(action)
	print("Main: Action result: ", result)

	if result.get("success", false):
		if result.get("pending", false):
			print("Main: Movement action submitted to network")
		else:
			print("Main: Movement action succeeded")

			# Handle different action types
			match action.type:
				"BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK":
					# Movement has begun, mode should be set in controller
					print("Movement mode initiated: ", action.type)
				"SET_MODEL_DEST":
					print("Main: Processing SET_MODEL_DEST - updating visuals for ", action.actor_unit_id, "/", action.payload.model_id)
					_update_model_visual(action.actor_unit_id, action.payload.model_id, action.payload.dest)
				"UNDO_LAST_MODEL_MOVE":
					print("Model move undone")
					_recreate_unit_visuals()
				"RESET_UNIT_MOVE":
					print("Unit movement reset")
					_recreate_unit_visuals()
				"CONFIRM_UNIT_MOVE":
					print("Unit movement confirmed")
					# Clear the active unit in controller
					if movement_controller:
						movement_controller.active_unit_id = ""
						movement_controller.active_mode = ""
				"CONFIRM_DISEMBARK":
					print("Main: Disembark confirmed for unit: ", action.actor_unit_id)
					# Refresh board visuals to show the disembarked models
					_recreate_unit_visuals()
					# Refresh unit list
					refresh_unit_list()
					# Check if the disembarked unit can move
					var disembarked_unit = GameState.get_unit(action.actor_unit_id)
					if disembarked_unit and not disembarked_unit.get("flags", {}).get("cannot_move", false):
						print("Main: Disembarked unit can move, selecting for movement")
						if movement_controller:
							movement_controller.active_unit_id = action.actor_unit_id
							movement_controller.active_mode = "NORMAL"
							var move_cap = movement_controller.get_unit_movement(disembarked_unit)
							movement_controller.move_cap_inches = move_cap
							print("Main: Unit %s has movement cap of %d inches" % [action.actor_unit_id, move_cap])
							movement_controller._update_selected_unit_display()
							movement_controller._update_fall_back_visibility()
							movement_controller.emit_signal("ui_update_requested")
							# Select the unit in the list
							for i in range(movement_controller.unit_list.get_item_count()):
								if movement_controller.unit_list.get_item_metadata(i) == action.actor_unit_id:
									movement_controller.unit_list.select(i)
									break
					else:
						print("Main: Disembarked unit cannot move (transport already moved)")
						if movement_controller:
							movement_controller.active_unit_id = ""
							movement_controller._update_selected_unit_display()

			# Update UI after successful action
			update_movement_card_buttons()
	else:
		print("Movement action failed: ", result.get("error", "Unknown error"))
		if result.has("errors"):
			for error in result.errors:
				print("  - ", error)
		# Show error in status label
		status_label.text = "Error: " + result.get("error", "Action failed")

func _show_movement_action_buttons(show: bool) -> void:
	# Show or hide movement action buttons
	var movement_actions = get_node_or_null("HUD_Right/VBoxContainer/MovementActions")
	if movement_actions:
		movement_actions.visible = show
		print("Movement action buttons visibility set to: ", show)
	else:
		print("WARNING: MovementActions container not found!")
		# If it doesn't exist and we want to show it, make sure MovementController creates it
		if show and movement_controller:
			movement_controller._setup_right_panel()

func _on_movement_ui_update_requested() -> void:
	# Update UI when MovementController requests it
	if current_phase == GameStateData.Phase.MOVEMENT:
		update_movement_card_buttons()

func _on_shooting_action_requested(action: Dictionary) -> void:
	print("========================================")
	print("Main: _on_shooting_action_requested CALLED")
	print("Main: Received shooting action request: ", action.get("type", ""))
	print("Main: Full action = ", action)

	# Route through NetworkIntegration (handles multiplayer and single-player)
	print("Main: Routing action through NetworkIntegration...")
	var result = NetworkIntegration.route_action(action)
	print("Main: NetworkIntegration returned result = ", result)

	if result.has("success"):
		if result.success:
			if result.get("pending", false):
				print("Main: Shooting action submitted to network")
			else:
				print("Main: Shooting action succeeded")
				update_after_shooting_action()
		else:
			print("Main: Shooting action failed: ", result.get("error", "Unknown error"))
	else:
		print("Main: Unexpected result from shooting action")

	print("========================================")

func _on_shooting_ui_update_requested() -> void:
	# Update UI when ShootingController requests it
	if current_phase == GameStateData.Phase.SHOOTING:
		update_ui()

func _on_charge_action_requested(action: Dictionary) -> void:
	print("Main: Received charge action request: ", action.get("type", ""))

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(action)

	if result.has("success"):
		if result.success:
			if result.get("pending", false):
				print("Main: Charge action submitted to network")
			else:
				print("Main: Charge action succeeded")
				# Update UI after successful action (state changes applied by BasePhase)
				update_after_charge_action()
		else:
			print("Main: Charge action failed: ", result.get("error", "Unknown error"))
			print("Main: Full charge action result: ", result)
	else:
		print("Main: Unexpected result from charge action")

func _on_charge_ui_update_requested() -> void:
	# Update UI when ChargeController requests it
	if current_phase == GameStateData.Phase.CHARGE:
		update_ui()

func _on_fight_action_requested(action: Dictionary) -> void:
	print("Main: Received fight action request: ", action.get("type", ""))

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(action)

	if result.has("success"):
		if result.success:
			if result.get("pending", false):
				print("Main: Fight action submitted to network")
			else:
				print("Main: Fight action succeeded")
				# Note: State changes are already applied by BasePhase.execute_action()
				# No need to apply them again here
				# Update UI after successful action
				update_after_fight_action()
		else:
			print("Main: Fight action failed: ", result.get("error", "Unknown error"))
	else:
		print("Main: Unexpected result from fight action")

func _on_fight_ui_update_requested() -> void:
	# Update UI when FightController requests it
	if current_phase == GameStateData.Phase.FIGHT:
		update_ui()

func _on_scoring_action_requested(action: Dictionary) -> void:
	print("Main: Received scoring action request: ", action.get("type", ""))

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(action)

	if result.has("success"):
		if result.success:
			if result.get("pending", false):
				print("Main: Scoring action submitted to network")
			else:
				print("Main: Scoring action succeeded")
				# Note: State changes are already applied by BasePhase.execute_action()
				# No need to apply them again here
				# Update UI after successful action
				update_after_scoring_action()
		else:
			print("Main: Scoring action failed: ", result.get("error", "Unknown error"))
	else:
		print("Main: Unexpected result from scoring action")

func _on_command_action_requested(action: Dictionary) -> void:
	print("Main: Received command action request: ", action.get("type", ""))

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(action)

	if result.has("success"):
		if result.success:
			if result.get("pending", false):
				print("Main: Command action submitted to network")
			else:
				print("Main: Command action succeeded")
				# Note: State changes are already applied by BasePhase.execute_action()
				# No need to apply them again here
				# Update UI after successful action
				update_after_command_action()
		else:
			print("Main: Command action failed: ", result.get("error", "Unknown error"))
	else:
		print("Main: Unexpected result from command action")

func _on_command_ui_update_requested() -> void:
	# Update UI when CommandController requests it
	if current_phase == GameStateData.Phase.COMMAND:
		update_ui()

func update_after_command_action() -> void:
	# Refresh UI after a command action
	refresh_unit_list()
	update_ui()
	
	# Update command controller state
	if command_controller:
		command_controller._refresh_ui()

func _on_scoring_ui_update_requested() -> void:
	# Update UI when ScoringController requests it
	if current_phase == GameStateData.Phase.SCORING:
		update_ui()

func update_after_scoring_action() -> void:
	# Refresh UI after a scoring action (mainly for turn switching)
	refresh_unit_list()
	update_ui()
	
	# Update scoring controller state
	if scoring_controller:
		scoring_controller._refresh_ui()

func update_after_charge_action() -> void:
	
	# Refresh visuals and UI after a charge action
	_recreate_unit_visuals()
	refresh_unit_list()
	update_ui()
	
	# Update charge controller state
	if charge_controller:
		charge_controller._refresh_ui()
	

func update_after_fight_action() -> void:
	# Refresh visuals and UI after a fight action
	_recreate_unit_visuals()  # This should handle dead model removal
	refresh_unit_list()
	update_ui()
	
	# Update fight controller state
	if fight_controller:
		fight_controller._refresh_fight_sequence()

func update_after_shooting_action() -> void:
	# Refresh visuals and UI after a shooting action
	_recreate_unit_visuals()  # This should handle dead model removal
	refresh_unit_list()
	update_ui()
	
	# Update shooting controller state
	if shooting_controller:
		shooting_controller._refresh_unit_list()

func _update_model_visual(unit_id: String, model_id: String, dest: Array) -> void:
	# Update the visual position of the model
	print("Updating visual for ", unit_id, "/", model_id, " to ", dest)
	
	# Wait a frame for the GameState to fully update
	await get_tree().process_frame
	
	# Recreate all unit visuals with updated positions
	_recreate_unit_visuals()

func _on_model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2) -> void:
	# Handle visual updates for model drops (including staged moves)
	print("Main: Model drop committed for ", unit_id, "/", model_id, " at ", dest_px)
	
	# For staged moves, we want to move the visual token directly without updating GameState
	# Find the existing token in token_layer
	if token_layer:
		for child in token_layer.get_children():
			if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id and child.has_meta("model_id") and child.get_meta("model_id") == model_id:
				print("Moving token visual to ", dest_px)
				child.position = dest_px
				return

	print("Could not find token to move, falling back to full recreation")
	_update_model_visual(unit_id, model_id, [dest_px.x, dest_px.y])

func _clear_right_panel_phase_ui() -> void:
	"""Completely clear all phase-specific UI from right panel"""
	var container = get_node_or_null("HUD_Right/VBoxContainer")
	if not container:
		print("WARNING: Right panel VBoxContainer not found")
		return

	# List of known phase-specific UI elements to remove
	var phase_ui_patterns = [
		# Standardized scroll containers (new naming convention)
		"DeploymentScrollContainer", "CommandScrollContainer",
		"MovementScrollContainer", "ShootingScrollContainer",
		"ChargeScrollContainer", "FightScrollContainer",
		"ScoringScrollContainer", "MoraleScrollContainer",

		# Standardized panels (new naming convention)
		"DeploymentPanel", "CommandPanel",
		"MovementPanel", "ShootingPanel",
		"ChargePanel", "FightPanel",
		"ScoringPanel", "MoralePanel",

		# Legacy Movement phase sections (to be removed after refactor)
		"Section1_UnitList", "Section2_UnitDetails",
		"Section3_ModeSelection", "Section4_Actions",
		"MovementActions",

		# Legacy Shooting phase elements
		"ShootingControls", "WeaponTree", "TargetBasket",

		# Legacy Charge phase elements
		"ChargeActions", "ChargeStatus",

		# Legacy Fight phase elements
		"FightSequence", "FightActions",

		# Generic phase elements
		"PhasePanel", "PhaseControls", "PhaseActions"
	]

	# Remove all matching elements
	for pattern in phase_ui_patterns:
		var node = container.get_node_or_null(pattern)
		if node and is_instance_valid(node):
			print("Main: Removing phase UI element: ", pattern)
			container.remove_child(node)
			node.queue_free()

	# Also remove any unknown dynamic children (defensive)
	var children_to_check = container.get_children()
	for child in children_to_check:
		# Keep only persistent UI elements
		if child.name in ["UnitListPanel", "UnitCard", "TransportPanel"]:
			continue
		# Remove if it looks like phase-specific UI
		if "Section" in child.name or "Panel" in child.name or "Actions" in child.name or "ScrollContainer" in child.name:
			print("Main: Removing unrecognized phase UI: ", child.name)
			container.remove_child(child)
			child.queue_free()

	# Reset visibility of persistent UI elements to defaults
	var unit_list = container.get_node_or_null("UnitListPanel")
	if unit_list:
		unit_list.visible = true  # Default visible

	var unit_card = container.get_node_or_null("UnitCard")
	if unit_card:
		unit_card.visible = false  # Default hidden

func _show_transport_deployment_dialog(transport_id: String) -> void:
	"""Show info about deploying a transport and offer to embark units"""
	print("Main: Transport selected for deployment: ", transport_id)

	var transport = GameState.get_unit(transport_id)
	var transport_name = transport.get("meta", {}).get("name", transport_id)

	# For now, deploy the transport empty
	# Units can be embarked after deployment by deploying them directly into the transport
	print("Main: Deploying transport ", transport_name, " - deploy INFANTRY units afterwards to embark them")

	# Update status to inform user
	if status_label:
		status_label.text = "Deploying %s - Deploy INFANTRY units after to embark them" % transport_name

	# Deploy the transport
	deployment_controller.begin_deploy(transport_id)
	show_unit_card(transport_id)
	unit_list.visible = false

func _debug_check_right_panel() -> void:
	"""Debug method to validate right panel state"""
	var container = get_node_or_null("HUD_Right/VBoxContainer")
	if not container:
		return
	
	for child in container.get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	
	# Check for wrong phase UI
	var current_phase_name = GameStateData.Phase.keys()[current_phase]
	
	# Flag any mismatched UI
	if current_phase != GameStateData.Phase.MOVEMENT:
		for section in ["Section1_UnitList", "Section2_UnitDetails", 
					   "Section3_ModeSelection", "Section4_Actions"]:
			if container.get_node_or_null(section):
				print("ERROR: Movement UI found in wrong phase!")
	
	if current_phase != GameStateData.Phase.SHOOTING:
		if container.get_node_or_null("ShootingPanel"):
			print("ERROR: Shooting UI found in wrong phase!")

func _setup_left_panel_toggle() -> void:
	"""Setup toggle button for left panel in top HUD"""
	var hud_bottom = get_node_or_null("HUD_Bottom/HBoxContainer")
	if not hud_bottom:
		print("ERROR: Could not find HUD_Bottom/HBoxContainer for left panel toggle")
		return

	# Create toggle button
	left_panel_toggle_button = Button.new()
	left_panel_toggle_button.name = "LeftPanelToggle"
	left_panel_toggle_button.text = "Show Mathhammer"
	left_panel_toggle_button.pressed.connect(_on_left_panel_toggle_pressed)

	# Add to the beginning of the HBox (before phase label)
	hud_bottom.add_child(left_panel_toggle_button)
	hud_bottom.move_child(left_panel_toggle_button, 0)

	print("Left panel toggle button added to top HUD")

func _hide_left_panel() -> void:
	"""Hide the left panel by default"""
	var hud_left = get_node_or_null("HUD_Left")
	if hud_left:
		hud_left.visible = false
		is_left_panel_visible = false
		print("Left panel hidden by default")

func _on_left_panel_toggle_pressed() -> void:
	"""Toggle visibility of left panel"""
	var hud_left = get_node_or_null("HUD_Left")
	if not hud_left:
		print("ERROR: Could not find HUD_Left to toggle")
		return

	is_left_panel_visible = !is_left_panel_visible
	hud_left.visible = is_left_panel_visible

	# Update button text
	if left_panel_toggle_button:
		if is_left_panel_visible:
			left_panel_toggle_button.text = "Hide Mathhammer"
		else:
			left_panel_toggle_button.text = "Show Mathhammer"

	print("Left panel visibility toggled: ", is_left_panel_visible)

func _setup_game_log_panel() -> void:
	print("Main: Setting up Game Event Log panel")

	# Create the main panel container anchored to the left side
	game_log_panel = PanelContainer.new()
	game_log_panel.name = "GameLogPanel"
	add_child(game_log_panel)

	# Anchor to left side, below top HUD, above bottom stats panel
	game_log_panel.anchor_left = 0.0
	game_log_panel.anchor_right = 0.0
	game_log_panel.anchor_top = 0.0
	game_log_panel.anchor_bottom = 1.0
	game_log_panel.offset_left = 0.0
	game_log_panel.offset_right = 280.0
	game_log_panel.offset_top = 105.0
	game_log_panel.offset_bottom = -305.0

	# Dark semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	style.border_width_left = 0
	style.border_width_right = 2
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.border_color = Color(0.833, 0.588, 0.376, 0.6)  # Gold accent
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	game_log_panel.add_theme_stylebox_override("panel", style)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	game_log_panel.add_child(vbox)

	# Header with title and toggle
	var header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "Game Log"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.833, 0.588, 0.376))  # Gold
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var collapse_btn = Button.new()
	collapse_btn.text = "X"
	collapse_btn.custom_minimum_size = Vector2(30, 25)
	collapse_btn.add_theme_font_size_override("font_size", 12)
	collapse_btn.pressed.connect(_on_game_log_collapse_pressed)
	header.add_child(collapse_btn)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Scroll container for the log entries
	game_log_scroll = ScrollContainer.new()
	game_log_scroll.name = "LogScroll"
	game_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(game_log_scroll)

	# RichTextLabel for color-coded entries
	game_log_label = RichTextLabel.new()
	game_log_label.name = "LogLabel"
	game_log_label.bbcode_enabled = true
	game_log_label.fit_content = true
	game_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_log_label.scroll_active = false  # We use our own scroll container
	game_log_label.add_theme_font_size_override("normal_font_size", 11)
	game_log_label.add_theme_font_size_override("bold_font_size", 12)
	game_log_scroll.add_child(game_log_label)

	# Connect to GameEventLog signal
	if GameEventLog:
		GameEventLog.entry_added.connect(_on_game_log_entry_added)
		print("Main: Connected to GameEventLog.entry_added")

		# Populate any entries that were added before we connected
		for entry in GameEventLog.get_all_entries():
			_append_log_entry(entry.text, entry.type)

	# Add toggle button to top HUD
	var hud_bottom = get_node_or_null("HUD_Bottom/HBoxContainer")
	if hud_bottom:
		game_log_toggle_button = Button.new()
		game_log_toggle_button.name = "GameLogToggle"
		game_log_toggle_button.text = "Hide Log"
		game_log_toggle_button.pressed.connect(_on_game_log_toggle_pressed)
		hud_bottom.add_child(game_log_toggle_button)
		hud_bottom.move_child(game_log_toggle_button, 1)  # After left panel toggle

	print("Main: Game Event Log panel created")

func _on_game_log_entry_added(text: String, entry_type: String) -> void:
	_append_log_entry(text, entry_type)

	# Auto-scroll to bottom
	if game_log_scroll:
		await get_tree().process_frame
		game_log_scroll.scroll_vertical = int(game_log_scroll.get_v_scroll_bar().max_value)

func _append_log_entry(text: String, entry_type: String) -> void:
	if not game_log_label:
		return

	var colored_text = ""
	match entry_type:
		"phase_header":
			colored_text = "[b][color=#D49761]%s[/color][/b]" % text
		"p1_action":
			colored_text = "[color=#6699CC]%s[/color]" % text
		"p2_action":
			colored_text = "[color=#CC6666]%s[/color]" % text
		_:
			colored_text = "[color=#AAAAAA]%s[/color]" % text

	game_log_label.append_text(colored_text + "\n")

func _on_game_log_collapse_pressed() -> void:
	is_game_log_visible = false
	if game_log_panel:
		game_log_panel.visible = false
	if game_log_toggle_button:
		game_log_toggle_button.text = "Show Log"

func _on_game_log_toggle_pressed() -> void:
	is_game_log_visible = !is_game_log_visible
	if game_log_panel:
		game_log_panel.visible = is_game_log_visible
	if game_log_toggle_button:
		game_log_toggle_button.text = "Hide Log" if is_game_log_visible else "Show Log"
