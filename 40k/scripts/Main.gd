extends CanvasLayer
# Use global class_name references instead of preloads to avoid web export reload issues
# GameStateData, BasePhase, ShootingPhase, NetworkIntegration are available via class_name
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
const AIDifficultyConfigData = preload("res://scripts/AIDifficultyConfig.gd")

# UI z_index layering constants — ensure panels always render above all board elements
const UI_PANEL_Z: int = 500      # HUD panels (left, right, bottom, stats, logs)
const UI_OVERLAY_Z: int = 1000   # Tooltips, overlays, popups
const UI_MODAL_Z: int = 2000     # Modal dialogs (wound allocation, save/load, game over)

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
@onready var auto_decline_overwatch: CheckButton = $HUD_Bottom/HBoxContainer/AutoDeclineOverwatch
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
var secondary_mission_panel: Control
var is_left_panel_visible: bool = false
var mathhammer_ui: Control
var save_load_dialog: PanelContainer
var game_over_dialog: AcceptDialog = null
var disconnect_dialog: AcceptDialog = null  # P2-41: Graceful disconnect handling
var deployment_controller: Node
var coherency_banner: PanelContainer = null
var command_controller: Node
var movement_controller: Node
var shooting_controller: Node
var charge_controller: Node
var fight_controller: Node
var scoring_controller: Node
var current_phase: GameStateData.Phase

# Scout phase state
var _scout_active_unit_id: String = ""
var _scout_dragging_model: bool = false
var _scout_drag_model_id: String = ""
var _scout_drag_start_pos: Vector2 = Vector2.ZERO
var _scout_move_distance: float = 0.0
# Scout phase visual state (mirrors MovementController visuals)
var _scout_ghost_visual: Node2D = null  # Container for ghost preview
var _scout_path_visual: Line2D = null  # Path line from start to cursor
var _scout_staged_path_visual: Node2D = null  # HumanMovementPathVisual for staged moves
var _scout_movement_remaining_label: Label = null  # Floating distance label near ghost
var _scout_selected_model_data: Dictionary = {}  # Full model data for ghost creation
# Scout Moves state (ScoutMovesPhase)
var _current_scout_unit_id: String = ""
var _scout_model_destinations: Array = []
var view_offset: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0
var view_rotation: float = 0.0  # Board rotation in radians (multiples of PI/2)

# Replay mode
var is_replay_mode: bool = false
var replay_ui: Node = null

# Deployment progress indicator UI elements
var deployment_progress_container: PanelContainer
var p1_progress_bar: ProgressBar
var p2_progress_bar: ProgressBar
var p1_progress_label: Label
var p2_progress_label: Label

# "Waiting for Opponent" overlay — T5-MP6 (deployment) + T5-MP8 (all phases)
var waiting_overlay: PanelContainer = null
var waiting_overlay_label: Label = null
var waiting_overlay_timer_label: Label = null
var _waiting_overlay_pulse_tween: Tween = null
var _opponent_zone_pulse_tween: Tween = null

# MA-42: Reactive stratagem blocking overlay — blocks active player while opponent decides
var _reactive_stratagem_overlay: ColorRect = null
var _reactive_stratagem_overlay_panel: PanelContainer = null
var _reactive_stratagem_overlay_label: Label = null
var _reactive_stratagem_overlay_timer_label: Label = null
var _reactive_stratagem_overlay_pulse_tween: Tween = null
var _reactive_stratagem_pending: bool = false

# T5-V3: Phase transition animation banner
var phase_transition_banner: PhaseTransitionBanner = null

# Retro CRT overlay
# CRT overlay removed — letter/enhanced style toggle via key 8

# T7-20: AI thinking indicator overlay
var ai_thinking_overlay: PanelContainer = null
var ai_thinking_label: Label = null
var _ai_thinking_pulse_tween: Tween = null
var _ai_thinking_dots_timer: float = 0.0
var _ai_thinking_dots_count: int = 0

# T7-52: AI unit highlighting during actions
const AIUnitHighlightScript = preload("res://scripts/AIUnitHighlight.gd")
var _ai_highlight_nodes: Array = []  # Active highlight Node2D instances
var _ai_highlighted_unit_id: String = ""  # Currently highlighted unit

# T7-54: AI action log overlay
var _ai_action_log_overlay: AIActionLogOverlay = null

# T7-56: AI turn replay panel
var _ai_turn_replay_panel: AITurnReplayPanel = null

# T7-19: AI turn summary panel (post-turn summary popup)
var _ai_turn_summary_panel: AITurnSummaryPanel = null

# T7-55: Spectator mode (AI vs AI) speed indicator HUD
var _spectator_speed_label: Label = null
var _spectator_speed_panel: PanelContainer = null
var _is_spectator_mode: bool = false

# T7-36: AI speed controls HUD (for human-vs-AI mode)
var _ai_speed_panel: PanelContainer = null
var _ai_speed_label: Label = null
var _ai_step_continue_button: Button = null

# P2-44: Player turn screen-edge color indicator
var _player_turn_border: PlayerTurnBorder = null
var _last_active_player: int = -1  # Track player changes for flash animation

# T5-MP8: Phase timer HUD elements (visible to active player in multiplayer)
var phase_timer_label: Label = null
var _phase_timer_last_warning: int = -1

# T5-MP7: Surrender button for multiplayer games
var surrender_button: Button = null

# Strategic Reserves / Deep Strike UI elements
var reserves_button: Button = null
var reinforcements_button: Button = null
var _selected_unit_for_reserves: String = ""
var _reinforcement_placement_type: String = ""  # P2-80: chosen placement type (deep_strike or strategic_reserves)
var _deep_strike_exclusion_visual: Node2D = null  # 9" exclusion bubble around enemy models

# Deployment zone toggle (Z key) - allows viewing zones after deployment phase
var _deployment_zones_toggled_on: bool = false

# Deployment unit hover preview (T5-UX11)
var _hovered_deploy_unit_id: String = ""
var _deploy_hover_tooltip: PanelContainer = null
var _deploy_hover_tooltip_label: RichTextLabel = null

# P3-54: Keyboard shortcut reference overlay during deployment
var _keyboard_shortcut_overlay: KeyboardShortcutOverlay = null


# P3-56: Web relay "Waiting for game state" loading screen
var _web_relay_loading_overlay: PanelContainer = null
var _web_relay_loading_label: Label = null
var _web_relay_loading_pulse_tween: Tween = null

# P2-12: "Game Loaded" fade transition overlay
var _game_loaded_overlay: ColorRect = null

# SAVE-20: Save/load progress indicator overlay
var _save_load_progress_overlay: PanelContainer = null
var _save_load_progress_label: Label = null
var _save_load_progress_detail: Label = null
var _save_load_progress_pulse_tween: Tween = null
var _save_load_progress_auto_dismiss_timer: Timer = null

# Player scores and CP display (top bar)
var _p1_score_label: Label = null
var _p2_score_label: Label = null
var _p1_cp_label: Label = null
var _p2_cp_label: Label = null
var _score_display_container: HBoxContainer = null

# P3-109: Turn/round progress indicator
var _round_indicator_label: Label = null

# P3-111: Settings menu instance
var _settings_menu: SettingsMenu = null

# Game Event Log UI elements
var game_log_panel: GameLogPanel
var game_log_toggle_button: Button
var _current_combat_card: GameLogEntry = null  # Tracks active combat card for grouping

# P3-117: Dice Roll History panel UI elements
var _dice_history_panel: PanelContainer = null
var _dice_history_label: RichTextLabel = null
var _dice_history_scroll: ScrollContainer = null
var _is_dice_history_visible: bool = false
var _dice_history_toggle_button: Button = null

# P2-40: Deployment log panel — tracks all deployments in order for multiplayer visibility
var _deployment_log_panel: PanelContainer = null
var _deployment_log_label: RichTextLabel = null
var _deployment_log_entries: Array = []  # Array of {player: int, unit_name: String, position: Vector2}
var _deployment_camera_pan_tween: Tween = null
var _deployment_camera_return_tween: Tween = null
var _pre_pan_offset: Vector2 = Vector2.ZERO
var _pre_pan_zoom: float = 1.0

func _ready() -> void:
	# Clear stale game event log entries from previous sessions
	# GameEventLog is an autoload that persists across scene reloads
	if GameEventLog:
		GameEventLog.clear()
	# P3-117: Clear stale dice history from previous sessions
	if DiceHistoryPanel:
		DiceHistoryPanel.clear()

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

	# Check if we're coming from main menu, multiplayer lobby, loading a save, or replay
	var from_menu = GameState.state.meta.has("from_menu") if GameState.state.has("meta") else false
	var from_save = GameState.state.meta.has("from_save") if GameState.state.has("meta") else false
	var from_multiplayer = GameState.state.meta.has("from_multiplayer_lobby") if GameState.state.has("meta") else false
	var from_replay = GameState.state.meta.has("from_replay") if GameState.state.has("meta") else false

	print("Main: from_menu=", from_menu, " from_save=", from_save, " from_multiplayer=", from_multiplayer, " from_replay=", from_replay)

	# P2-12: Show fade overlay immediately when loading from save to hide visual setup
	if from_save:
		_show_game_loaded_overlay()

	# If entering replay mode, use a streamlined initialization path
	if from_replay:
		is_replay_mode = true
		print("Main: ✓ Entering REPLAY MODE")
		await _initialize_replay_mode()
		return

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

					# P3-56: Show loading overlay on guest while waiting for host state
					if not is_host:
						_setup_web_relay_loading_overlay()

					# If host, send initial state to guest after a short delay
					if is_host:
						await get_tree().create_timer(0.5).timeout
						print("Main: Host sending initial state to guest")
						NetworkManager.send_initial_state_via_relay()
				else:
					push_error("Main: NetworkManager not available for web relay mode")
	
	# Initialize view to show whole board centered in the viewport
	view_zoom = 0.3
	var viewport_size = get_viewport().get_visible_rect().size
	var board_center = Vector2(
		SettingsService.get_board_width_px() / 2.0,
		SettingsService.get_board_height_px() / 2.0
	)
	view_offset = board_center - viewport_size / (2.0 * view_zoom)
	update_view_transform()

	# Initialize PhaseManager with the correct starting phase
	var phase_manager = get_node("/root/PhaseManager")
	if phase_manager:
		if from_save:
			# SAVE/LOAD FIX: When loading from a saved game, restore the saved phase
			# instead of unconditionally starting at FORMATIONS (which would overwrite the saved phase)
			var saved_phase = GameState.get_current_phase()
			print("Main: Loading from save — restoring saved phase: ", GameStateData.Phase.keys()[saved_phase])
			phase_manager.transition_to_phase(saved_phase)
		else:
			# New game: start at FORMATIONS phase per 10e rules
			print("Main: Initializing formations phase with ", GameState.state.units.size(), " units")
			phase_manager.transition_to_phase(GameStateData.Phase.FORMATIONS)

		# DEBUG: Verify phase was created correctly
		await get_tree().process_frame
		var phase_inst = phase_manager.get_current_phase_instance()
		if phase_inst:
			print("Main: Phase instance created - class: ", phase_inst.get_class())
			print("Main: Phase instance script: ", phase_inst.get_script())
			print("Main: Phase has validate_action: ", phase_inst.has_method("validate_action"))
		else:
			print("Main: ERROR - No phase instance after transition!")

	# Camera controls: WASD/arrows to pan, +/- to zoom, F to focus on Player 2 zone, V to rotate board

	board_view.queue_redraw()
	setup_deployment_zones()

	# Setup objectives on the board
	_setup_objectives()

	# Move HUD_Bottom to top and create stats panel at bottom
	_restructure_ui_layout()

	# Setup player scores and CP display in top bar
	_setup_score_display()

	# P3-109: Setup turn/round progress indicator
	_setup_round_indicator()

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

	# Hide left panel (Mathhammer) by default — toggle with hotkey
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

	# SAVE/LOAD FIX: When loading from a save, recreate unit visuals for deployed units
	# and update deployment zone visibility. In a new game, units are undeployed so this is a no-op.
	if from_save:
		print("Main: Recreating unit visuals for loaded save...")
		_recreate_unit_visuals()
		update_deployment_zone_visibility()
		print("Main: Unit visuals recreated for loaded save")
		# P2-12: Dismiss the fade overlay now that visuals are restored
		_dismiss_game_loaded_overlay()

	# CRITICAL FIX: Must call update_ui_for_phase() to properly configure the phase action button
	# This sets the correct button text and connects the signal handler
	print("Main: ⚠️ Calling update_ui_for_phase() for initial phase setup")
	update_ui_for_phase()
	print("Main: ⚠️ Initial phase UI setup complete")

	# Setup deployment progress indicator
	_setup_deployment_progress_indicator()

	# Setup "Waiting for Opponent" overlay for multiplayer (T5-MP6 + T5-MP8)
	_setup_waiting_for_opponent_overlay()

	# MA-42: Setup reactive stratagem blocking overlay
	_setup_reactive_stratagem_overlay()

	# T5-MP8: Setup phase timer HUD for multiplayer
	_setup_phase_timer_hud()

	# T5-MP7: Setup surrender button for multiplayer
	_setup_surrender_button()

	# Setup Strategic Reserves button
	_setup_reserves_button()


	# Setup deployment hover tooltip (T5-UX11)
	_setup_deploy_hover_tooltip()

	# Setup Game Event Log panel
	_setup_game_log_panel()

	# P3-117: Setup Dice Roll History panel
	_setup_dice_history_panel()

	# T5-V3: Setup phase transition animation banner
	_setup_phase_transition_banner()

	# P2-44: Setup player turn screen-edge color indicator
	_setup_player_turn_border()

	# T7-20: Setup AI thinking indicator
	_setup_ai_thinking_indicator()

	# T7-54: Setup AI action log overlay
	_setup_ai_action_log_overlay()

	# T7-56: Setup AI turn replay panel
	_setup_ai_turn_replay_panel()

	# T7-19: Setup AI turn summary panel
	_setup_ai_turn_summary_panel()

	# T7-55: Setup spectator mode speed indicator
	_setup_spectator_speed_hud()

	# T7-36: Setup AI speed controls HUD
	_setup_ai_speed_hud()

	# Apply White Dwarf gothic UI theme
	_apply_white_dwarf_theme()

	# Enable autosave (saves every 5 minutes)
	SaveLoadManager.enable_autosave()
	print("Quick Save/Load enabled: [ key to save, ] key (or F9) to load")

	# Start replay recording if configured (auto for AI vs AI)
	_start_replay_recording_if_needed()

	# Final pass: ensure all UI panels render above board elements
	_ensure_ui_panels_on_top()

func _initialize_ai_player() -> void:
	# Configure AIPlayer autoload based on game_config from MainMenu
	var ai_player = get_node_or_null("/root/AIPlayer")
	if not ai_player:
		print("Main: AIPlayer autoload not found, skipping AI initialization")
		return

	var game_config = GameState.state.get("meta", {}).get("game_config", {})
	var p1_type = game_config.get("player1_type", "HUMAN")
	var p2_type = game_config.get("player2_type", "HUMAN")
	# T7-40: Get difficulty levels from config (default Normal for backwards compatibility)
	var p1_difficulty = int(game_config.get("player1_difficulty", AIDifficultyConfigData.Difficulty.NORMAL))
	var p2_difficulty = int(game_config.get("player2_difficulty", AIDifficultyConfigData.Difficulty.NORMAL))

	print("Main: Configuring AI Player - P1=%s (%s), P2=%s (%s)" % [
		p1_type, AIDifficultyConfigData.difficulty_name(p1_difficulty),
		p2_type, AIDifficultyConfigData.difficulty_name(p2_difficulty)])
	ai_player.configure({1: p1_type, 2: p2_type}, {1: p1_difficulty, 2: p2_difficulty})

	# Load per-player AI profiles if configured
	var p1_profile = game_config.get("player1_ai_profile", "")
	var p2_profile = game_config.get("player2_ai_profile", "")
	if p1_profile != "" and p1_type == "AI":
		ai_player.load_player_profile(1, p1_profile)
		print("Main: Loaded AI profile '%s' for player 1" % p1_profile)
	if p2_profile != "" and p2_type == "AI":
		ai_player.load_player_profile(2, p2_profile)
		print("Main: Loaded AI profile '%s' for player 2" % p2_profile)

	# Connect to AI deployment signal so we can create visual tokens
	if not ai_player.ai_unit_deployed.is_connected(_on_ai_unit_deployed):
		ai_player.ai_unit_deployed.connect(_on_ai_unit_deployed)
		print("Main: Connected to AIPlayer.ai_unit_deployed signal")

	# Connect to AI action signal so we can sync token positions after AI moves
	if not ai_player.ai_action_taken.is_connected(_on_ai_action_taken):
		ai_player.ai_action_taken.connect(_on_ai_action_taken)
		print("Main: Connected to AIPlayer.ai_action_taken signal")

	# T7-20: Connect to AI thinking signals for the thinking indicator
	if not ai_player.ai_turn_started.is_connected(_show_ai_thinking_indicator):
		ai_player.ai_turn_started.connect(_show_ai_thinking_indicator)
		print("Main: Connected to AIPlayer.ai_turn_started signal (T7-20)")
	if not ai_player.ai_turn_ended.is_connected(_on_ai_turn_ended):
		ai_player.ai_turn_ended.connect(_on_ai_turn_ended)
		print("Main: Connected to AIPlayer.ai_turn_ended signal (T7-20)")

	# T7-56: Connect turn history signal to replay panel
	if _ai_turn_replay_panel and ai_player.has_signal("turn_history_updated"):
		if not ai_player.turn_history_updated.is_connected(_ai_turn_replay_panel.refresh):
			ai_player.turn_history_updated.connect(_ai_turn_replay_panel.refresh)
			print("Main: Connected AIPlayer.turn_history_updated to replay panel (T7-56)")

	# T7-19: Connect ai_turn_ended to the turn summary panel
	if _ai_turn_summary_panel:
		if not ai_player.ai_turn_ended.is_connected(_ai_turn_summary_panel.show_summary):
			ai_player.ai_turn_ended.connect(_ai_turn_summary_panel.show_summary)
			print("Main: Connected AIPlayer.ai_turn_ended to turn summary panel (T7-19)")

	# T7-54: Connect AI signals to the action log overlay
	if _ai_action_log_overlay:
		if not ai_player.ai_turn_started.is_connected(_ai_action_log_overlay.on_ai_turn_started):
			ai_player.ai_turn_started.connect(_ai_action_log_overlay.on_ai_turn_started)
		if not ai_player.ai_turn_ended.is_connected(_ai_action_log_overlay.on_ai_turn_ended):
			ai_player.ai_turn_ended.connect(_ai_action_log_overlay.on_ai_turn_ended)
		if not ai_player.ai_action_taken.is_connected(_ai_action_log_overlay.add_action_entry):
			ai_player.ai_action_taken.connect(_ai_action_log_overlay.add_action_entry)
		if ai_player.has_signal("ai_thinking_step") and not ai_player.ai_thinking_step.is_connected(_ai_action_log_overlay.add_thinking_entry):
			ai_player.ai_thinking_step.connect(_ai_action_log_overlay.add_thinking_entry)
		print("Main: Connected AIPlayer signals to AI action log overlay (T7-54)")

	# T7-36: Apply AI speed setting from game config
	var ai_speed = int(game_config.get("ai_speed", 1))  # Default: Normal (index 1)
	ai_player.set_ai_speed_preset(ai_speed)
	print("Main: T7-36 AI speed preset set to %s" % ai_player.get_ai_speed_name())

	# T7-36: Connect AI speed signals
	if not ai_player.ai_speed_changed.is_connected(_on_ai_speed_changed):
		ai_player.ai_speed_changed.connect(_on_ai_speed_changed)
	if not ai_player.step_by_step_waiting.is_connected(_on_step_by_step_waiting):
		ai_player.step_by_step_waiting.connect(_on_step_by_step_waiting)

	# T7-36: Show AI speed HUD for non-spectator AI games
	_is_spectator_mode = ai_player.is_spectator_mode()
	if not _is_spectator_mode and ai_player.enabled:
		_update_ai_speed_label(ai_player.get_ai_speed_name())
		if _ai_speed_panel:
			_ai_speed_panel.visible = true

	# T7-55: Setup spectator mode if both players are AI
	if _is_spectator_mode:
		print("Main: T7-55 Spectator mode detected (AI vs AI)")
		# Tell the action log overlay to use spectator timing
		if _ai_action_log_overlay:
			_ai_action_log_overlay.set_spectator_mode(true)
		# Connect spectator-specific signals
		if not ai_player.spectator_speed_changed.is_connected(_on_spectator_speed_changed):
			ai_player.spectator_speed_changed.connect(_on_spectator_speed_changed)
		if not ai_player.spectator_phase_summary.is_connected(_on_spectator_phase_summary):
			ai_player.spectator_phase_summary.connect(_on_spectator_phase_summary)
		# Show the speed indicator HUD
		_update_spectator_speed_label(ai_player.get_spectator_speed())
		if _spectator_speed_panel:
			_spectator_speed_panel.visible = true

func _reinitialize_ai_after_load() -> void:
	"""SAVE-1: Re-initialize AI player after loading a save file.
	Uses reconfigure_ai_after_load() which cancels thinking, resets state, and
	reconfigures from loaded game_config WITHOUT triggering immediate evaluation.
	Also reconnects all AI signals to Main.gd UI elements."""
	var ai_player = get_node_or_null("/root/AIPlayer")
	if not ai_player:
		print("Main: AIPlayer autoload not found, skipping AI re-initialization after load")
		return

	var game_config = GameState.state.get("meta", {}).get("game_config", {})
	print("Main: SAVE-1 Re-initializing AI after load — config: P1=%s, P2=%s" % [
		game_config.get("player1_type", "HUMAN"),
		game_config.get("player2_type", "HUMAN")])

	# Use the dedicated load reconfiguration path
	if ai_player.has_method("reconfigure_ai_after_load"):
		ai_player.reconfigure_ai_after_load(game_config)
	else:
		# Fallback: use configure() if reconfigure_ai_after_load not available
		print("Main: WARNING — reconfigure_ai_after_load() not found, falling back to configure()")
		var p1_type = game_config.get("player1_type", "HUMAN")
		var p2_type = game_config.get("player2_type", "HUMAN")
		var p1_difficulty = int(game_config.get("player1_difficulty", AIDifficultyConfigData.Difficulty.NORMAL))
		var p2_difficulty = int(game_config.get("player2_difficulty", AIDifficultyConfigData.Difficulty.NORMAL))
		ai_player.configure({1: p1_type, 2: p2_type}, {1: p1_difficulty, 2: p2_difficulty})

	# SAVE-7: Restore AI turn history from snapshot (after reconfigure clears it)
	var saved_ai_history = GameState.state.get("ai_turn_history", [])
	if not saved_ai_history.is_empty() and ai_player.has_method("restore_turn_history"):
		ai_player.restore_turn_history(saved_ai_history)
		print("Main: SAVE-7 Restored %d AI turn history entries after load" % saved_ai_history.size())

	# Reconnect AI signals (using is_connected checks to avoid duplicates)
	if not ai_player.ai_unit_deployed.is_connected(_on_ai_unit_deployed):
		ai_player.ai_unit_deployed.connect(_on_ai_unit_deployed)
	if not ai_player.ai_action_taken.is_connected(_on_ai_action_taken):
		ai_player.ai_action_taken.connect(_on_ai_action_taken)
	if not ai_player.ai_turn_started.is_connected(_show_ai_thinking_indicator):
		ai_player.ai_turn_started.connect(_show_ai_thinking_indicator)
	if not ai_player.ai_turn_ended.is_connected(_on_ai_turn_ended):
		ai_player.ai_turn_ended.connect(_on_ai_turn_ended)

	# T7-56: Reconnect turn history signal to replay panel
	if _ai_turn_replay_panel and ai_player.has_signal("turn_history_updated"):
		if not ai_player.turn_history_updated.is_connected(_ai_turn_replay_panel.refresh):
			ai_player.turn_history_updated.connect(_ai_turn_replay_panel.refresh)

	# T7-19: Reconnect to turn summary panel
	if _ai_turn_summary_panel:
		if not ai_player.ai_turn_ended.is_connected(_ai_turn_summary_panel.show_summary):
			ai_player.ai_turn_ended.connect(_ai_turn_summary_panel.show_summary)

	# T7-54: Reconnect AI signals to action log overlay
	if _ai_action_log_overlay:
		if not ai_player.ai_turn_started.is_connected(_ai_action_log_overlay.on_ai_turn_started):
			ai_player.ai_turn_started.connect(_ai_action_log_overlay.on_ai_turn_started)
		if not ai_player.ai_turn_ended.is_connected(_ai_action_log_overlay.on_ai_turn_ended):
			ai_player.ai_turn_ended.connect(_ai_action_log_overlay.on_ai_turn_ended)
		if not ai_player.ai_action_taken.is_connected(_ai_action_log_overlay.add_action_entry):
			ai_player.ai_action_taken.connect(_ai_action_log_overlay.add_action_entry)
		if ai_player.has_signal("ai_thinking_step") and not ai_player.ai_thinking_step.is_connected(_ai_action_log_overlay.add_thinking_entry):
			ai_player.ai_thinking_step.connect(_ai_action_log_overlay.add_thinking_entry)

	# T7-36: Reconnect speed signals
	if not ai_player.ai_speed_changed.is_connected(_on_ai_speed_changed):
		ai_player.ai_speed_changed.connect(_on_ai_speed_changed)
	if not ai_player.step_by_step_waiting.is_connected(_on_step_by_step_waiting):
		ai_player.step_by_step_waiting.connect(_on_step_by_step_waiting)

	# Update spectator/speed UI
	_is_spectator_mode = ai_player.is_spectator_mode()
	if not _is_spectator_mode and ai_player.enabled:
		_update_ai_speed_label(ai_player.get_ai_speed_name())
		if _ai_speed_panel:
			_ai_speed_panel.visible = true
	if _is_spectator_mode:
		if _ai_action_log_overlay:
			_ai_action_log_overlay.set_spectator_mode(true)
		if not ai_player.spectator_speed_changed.is_connected(_on_spectator_speed_changed):
			ai_player.spectator_speed_changed.connect(_on_spectator_speed_changed)
		if not ai_player.spectator_phase_summary.is_connected(_on_spectator_phase_summary):
			ai_player.spectator_phase_summary.connect(_on_spectator_phase_summary)
		_update_spectator_speed_label(ai_player.get_spectator_speed())
		if _spectator_speed_panel:
			_spectator_speed_panel.visible = true

	print("Main: SAVE-1 AI re-initialization after load complete")

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

func _on_ai_action_taken(_player: int, action: Dictionary, _description: String) -> void:
	# After AI actions that change unit positions, sync token visuals from GameState
	var action_type = action.get("type", "")
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))

	# T7-58: Show charge arrow visuals when AI declares a charge
	if action_type == "DECLARE_CHARGE" and charge_controller and is_instance_valid(charge_controller):
		var charger_id = action.get("actor_unit_id", "")
		var target_ids = action.get("payload", {}).get("target_unit_ids", [])
		if charger_id != "" and target_ids.size() > 0:
			charge_controller.show_ai_charge_arrows(charger_id, target_ids)
			print("[Main] T7-58: Triggered AI charge arrows for %s -> %s" % [charger_id, str(target_ids)])

	# Movement-related actions that change model positions
	if action_type in ["CONFIRM_UNIT_MOVE", "REMAIN_STATIONARY", "CHARGE", "PILE_IN", "CONSOLIDATE"]:
		if unit_id != "":
			update_unit_visuals(unit_id)

	# Phase-ending actions: sync ALL token positions to catch any missed updates
	if action_type in ["END_MOVEMENT", "END_CHARGE", "END_FIGHT", "END_SHOOTING"]:
		_sync_all_token_positions()
		_clear_ai_unit_highlights()

	# T7-52: Highlight the AI's active unit based on action type
	if unit_id != "" and action_type not in ["END_MOVEMENT", "END_SHOOTING", "END_CHARGE", "END_FIGHT", "END_SCORING"]:
		var highlight_color = _get_ai_action_highlight_color(action_type)
		if highlight_color != Color.TRANSPARENT:
			_show_ai_unit_highlight(unit_id, highlight_color)

	# Refresh UI after any AI action to keep unit list and phase UI current
	refresh_unit_list()
	update_ui()

func _on_ai_turn_ended(player: int, _action_summary: Array) -> void:
	# T7-20: Hide the AI thinking indicator when AI finishes its turn
	_hide_ai_thinking_indicator(player)
	# T7-52: Clear AI unit highlights when AI turn ends
	_clear_ai_unit_highlights()
	# T7-36: Hide step-by-step continue button when AI turn ends
	_hide_step_continue_button()

func _sync_all_token_positions() -> void:
	# Sync all token visual positions from GameState (for after AI plays)
	for child in token_layer.get_children():
		if child.has_meta("unit_id") and child.has_meta("model_id"):
			var unit_id = child.get_meta("unit_id")
			var model_id = child.get_meta("model_id")
			var unit = GameState.get_unit(unit_id)
			if unit.is_empty():
				continue
			for model in unit.get("models", []):
				if model.get("id", "") == model_id:
					var pos = model.get("position")
					if pos != null:
						if pos is Dictionary:
							child.position = Vector2(pos.x, pos.y)
						else:
							child.position = pos
					if not model.get("alive", true):
						child.visible = false
					break

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

func _setup_waiting_for_opponent_overlay() -> void:
	# T5-MP6: Create a prominent "Waiting for Opponent" overlay for multiplayer deployment
	# This overlay is shown when it's the opponent's turn to deploy, providing clear visual
	# feedback instead of just a passive text item in the right panel.
	waiting_overlay = PanelContainer.new()
	waiting_overlay.name = "WaitingForOpponentOverlay"
	# Center the overlay horizontally, position it in the upper-middle area of the screen
	waiting_overlay.anchor_left = 0.25
	waiting_overlay.anchor_right = 0.75
	waiting_overlay.anchor_top = 0.0
	waiting_overlay.anchor_bottom = 0.0
	waiting_overlay.offset_top = 170.0  # Below deployment progress bar (100-160)
	waiting_overlay.offset_bottom = 250.0
	waiting_overlay.visible = false
	waiting_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Apply a distinct banner style — dark background with gold border
	var banner_style = StyleBoxFlat.new()
	banner_style.bg_color = Color(0.12, 0.08, 0.05, 0.95)
	banner_style.border_color = _WhiteDwarfTheme.WH_GOLD
	banner_style.set_border_width_all(2)
	banner_style.border_width_top = 3
	banner_style.border_width_bottom = 3
	banner_style.set_corner_radius_all(6)
	banner_style.set_content_margin_all(8)
	waiting_overlay.add_theme_stylebox_override("panel", banner_style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	waiting_overlay.add_child(vbox)

	# Main waiting text
	waiting_overlay_label = Label.new()
	waiting_overlay_label.text = "Waiting for opponent to deploy..."
	waiting_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_overlay_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	waiting_overlay_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(waiting_overlay_label)

	# Timer countdown label
	waiting_overlay_timer_label = Label.new()
	waiting_overlay_timer_label.text = ""
	waiting_overlay_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_overlay_timer_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	waiting_overlay_timer_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(waiting_overlay_timer_label)

	add_child(waiting_overlay)
	print("Main: Waiting-for-opponent overlay created (T5-MP6)")

func _update_waiting_for_opponent_overlay() -> void:
	# T5-MP6 + T5-MP8: Show/hide the waiting overlay for ALL phases in multiplayer
	if not waiting_overlay:
		return

	var network_manager = get_node_or_null("/root/NetworkManager")
	var is_multiplayer = network_manager and network_manager.is_networked()

	if not is_multiplayer:
		_hide_waiting_overlay()
		return

	var is_my_turn = network_manager.is_local_player_turn()
	if is_my_turn:
		_hide_waiting_overlay()
		return

	# It's opponent's turn — show the overlay with phase-appropriate text
	var active_player = GameState.get_active_player()
	var local_player = network_manager.get_local_player()
	var phase_name = _get_phase_label_text(current_phase)

	if current_phase == GameStateData.Phase.DEPLOYMENT:
		var opponent_role = "Defender" if active_player == 1 else "Attacker"
		waiting_overlay_label.text = "Waiting for Player %d (%s) to deploy..." % [active_player, opponent_role]
	else:
		waiting_overlay_label.text = "Waiting for Player %d — %s" % [active_player, phase_name]

	# Update turn timer countdown if available
	var time_left = network_manager.get_turn_time_remaining()
	if time_left >= 0:
		var seconds = int(time_left)
		waiting_overlay_timer_label.text = "Turn timer: %d:%02d remaining" % [seconds / 60, seconds % 60]
		waiting_overlay_timer_label.visible = true
		# Color-code the timer text
		if seconds <= 15:
			waiting_overlay_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif seconds <= 30:
			waiting_overlay_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			waiting_overlay_timer_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	else:
		waiting_overlay_timer_label.visible = false

	if not waiting_overlay.visible:
		waiting_overlay.visible = true
		_start_waiting_overlay_pulse()
		print("Main: Showing waiting-for-opponent overlay (Player %d in %s, you are Player %d)" % [active_player, phase_name, local_player])

func _hide_waiting_overlay() -> void:
	if waiting_overlay and waiting_overlay.visible:
		waiting_overlay.visible = false
		_stop_waiting_overlay_pulse()
		_stop_opponent_zone_pulse()

func _start_waiting_overlay_pulse() -> void:
	# Subtle pulse animation on the overlay border to indicate activity
	if _waiting_overlay_pulse_tween:
		_waiting_overlay_pulse_tween.kill()
	_waiting_overlay_pulse_tween = create_tween().set_loops()
	_waiting_overlay_pulse_tween.tween_property(waiting_overlay, "modulate", Color(1, 1, 1, 0.7), 1.2).set_trans(Tween.TRANS_SINE)
	_waiting_overlay_pulse_tween.tween_property(waiting_overlay, "modulate", Color(1, 1, 1, 1.0), 1.2).set_trans(Tween.TRANS_SINE)

	# Also pulse the opponent's deployment zone (only during deployment)
	if current_phase == GameStateData.Phase.DEPLOYMENT:
		_start_opponent_zone_pulse()

func _stop_waiting_overlay_pulse() -> void:
	if _waiting_overlay_pulse_tween:
		_waiting_overlay_pulse_tween.kill()
		_waiting_overlay_pulse_tween = null
	if waiting_overlay:
		waiting_overlay.modulate = Color(1, 1, 1, 1)

func _start_opponent_zone_pulse() -> void:
	# Subtle pulse animation on the opponent's deployment zone to show activity
	var active_player = GameState.get_active_player()
	var zone = p1_zone if active_player == 1 else p2_zone
	if not zone:
		return

	if _opponent_zone_pulse_tween:
		_opponent_zone_pulse_tween.kill()

	# Store the base modulate so we pulse around it
	var base_alpha = zone.modulate.a
	var bright_color = zone.modulate
	bright_color.a = min(base_alpha + 0.25, 1.0)
	var dim_color = zone.modulate
	dim_color.a = max(base_alpha - 0.1, 0.15)

	_opponent_zone_pulse_tween = create_tween().set_loops()
	_opponent_zone_pulse_tween.tween_property(zone, "modulate:a", bright_color.a, 1.0).set_trans(Tween.TRANS_SINE)
	_opponent_zone_pulse_tween.tween_property(zone, "modulate:a", dim_color.a, 1.0).set_trans(Tween.TRANS_SINE)

func _stop_opponent_zone_pulse() -> void:
	if _opponent_zone_pulse_tween:
		_opponent_zone_pulse_tween.kill()
		_opponent_zone_pulse_tween = null
	# Restore zone modulates via the normal visibility function
	if current_phase == GameStateData.Phase.DEPLOYMENT:
		update_deployment_zone_visibility()

# =============================================================================
# MA-42: Reactive Stratagem Blocking Overlay
# =============================================================================

func _setup_reactive_stratagem_overlay() -> void:
	# MA-42: Full-screen semi-transparent overlay that blocks active player input
	# while the non-active player is deciding on a reactive stratagem.
	_reactive_stratagem_overlay = ColorRect.new()
	_reactive_stratagem_overlay.name = "ReactiveStratagemOverlay"
	_reactive_stratagem_overlay.anchor_left = 0.0
	_reactive_stratagem_overlay.anchor_right = 1.0
	_reactive_stratagem_overlay.anchor_top = 0.0
	_reactive_stratagem_overlay.anchor_bottom = 1.0
	_reactive_stratagem_overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	_reactive_stratagem_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all input
	_reactive_stratagem_overlay.visible = false
	add_child(_reactive_stratagem_overlay)

	# Centered banner panel
	_reactive_stratagem_overlay_panel = PanelContainer.new()
	_reactive_stratagem_overlay_panel.anchor_left = 0.25
	_reactive_stratagem_overlay_panel.anchor_right = 0.75
	_reactive_stratagem_overlay_panel.anchor_top = 0.35
	_reactive_stratagem_overlay_panel.anchor_bottom = 0.35
	_reactive_stratagem_overlay_panel.offset_top = 0
	_reactive_stratagem_overlay_panel.offset_bottom = 120
	_reactive_stratagem_overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var banner_style = StyleBoxFlat.new()
	banner_style.bg_color = Color(0.12, 0.08, 0.05, 0.97)
	banner_style.border_color = _WhiteDwarfTheme.WH_GOLD
	banner_style.set_border_width_all(3)
	banner_style.set_corner_radius_all(8)
	banner_style.set_content_margin_all(16)
	_reactive_stratagem_overlay_panel.add_theme_stylebox_override("panel", banner_style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_reactive_stratagem_overlay_panel.add_child(vbox)

	# Main text
	_reactive_stratagem_overlay_label = Label.new()
	_reactive_stratagem_overlay_label.text = "Waiting for opponent's stratagem decision..."
	_reactive_stratagem_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reactive_stratagem_overlay_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	_reactive_stratagem_overlay_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_reactive_stratagem_overlay_label)

	# Timer label
	_reactive_stratagem_overlay_timer_label = Label.new()
	_reactive_stratagem_overlay_timer_label.text = ""
	_reactive_stratagem_overlay_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reactive_stratagem_overlay_timer_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	_reactive_stratagem_overlay_timer_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_reactive_stratagem_overlay_timer_label)

	_reactive_stratagem_overlay.add_child(_reactive_stratagem_overlay_panel)
	print("Main: MA-42 Reactive stratagem blocking overlay created")

func show_reactive_stratagem_waiting(stratagem_name: String = "stratagem") -> void:
	# MA-42: Show blocking overlay to the active player while opponent decides
	if not _reactive_stratagem_overlay:
		return
	_reactive_stratagem_pending = true
	_reactive_stratagem_overlay_label.text = "Waiting for opponent's %s decision..." % stratagem_name
	_reactive_stratagem_overlay_timer_label.text = "Auto-declining in 5 seconds..."
	_reactive_stratagem_overlay.visible = true

	# Start pulse animation
	if _reactive_stratagem_overlay_pulse_tween:
		_reactive_stratagem_overlay_pulse_tween.kill()
	_reactive_stratagem_overlay_pulse_tween = create_tween().set_loops()
	_reactive_stratagem_overlay_pulse_tween.tween_property(
		_reactive_stratagem_overlay_panel, "modulate", Color(1, 1, 1, 0.7), 1.2
	).set_trans(Tween.TRANS_SINE)
	_reactive_stratagem_overlay_pulse_tween.tween_property(
		_reactive_stratagem_overlay_panel, "modulate", Color(1, 1, 1, 1.0), 1.2
	).set_trans(Tween.TRANS_SINE)

	print("Main: MA-42 Showing reactive stratagem blocking overlay (%s)" % stratagem_name)

func hide_reactive_stratagem_waiting() -> void:
	# MA-42: Hide the blocking overlay when the decision is made or timer expires
	if not _reactive_stratagem_overlay:
		return
	if not _reactive_stratagem_pending:
		return
	_reactive_stratagem_pending = false
	_reactive_stratagem_overlay.visible = false
	if _reactive_stratagem_overlay_pulse_tween:
		_reactive_stratagem_overlay_pulse_tween.kill()
		_reactive_stratagem_overlay_pulse_tween = null
	if _reactive_stratagem_overlay_panel:
		_reactive_stratagem_overlay_panel.modulate = Color(1, 1, 1, 1)
	print("Main: MA-42 Hiding reactive stratagem blocking overlay")

# =============================================================================
# P3-56: Web Relay "Waiting for game state" Loading Screen
# =============================================================================

func _setup_web_relay_loading_overlay() -> void:
	# P3-56: Full-screen loading overlay shown on guest side in web relay mode.
	# Prevents flash of default army configuration while waiting for host state.
	_web_relay_loading_overlay = PanelContainer.new()
	_web_relay_loading_overlay.name = "WebRelayLoadingOverlay"
	# Cover entire screen
	_web_relay_loading_overlay.anchor_left = 0.0
	_web_relay_loading_overlay.anchor_right = 1.0
	_web_relay_loading_overlay.anchor_top = 0.0
	_web_relay_loading_overlay.anchor_bottom = 1.0
	_web_relay_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all input

	# Dark background style
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.06, 0.04, 0.97)
	bg_style.border_color = _WhiteDwarfTheme.WH_GOLD
	bg_style.set_border_width_all(0)
	_web_relay_loading_overlay.add_theme_stylebox_override("panel", bg_style)

	# Center content
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_web_relay_loading_overlay.add_child(center_container)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center_container.add_child(vbox)

	# Loading text
	_web_relay_loading_label = Label.new()
	_web_relay_loading_label.text = "Waiting for game state..."
	_web_relay_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_web_relay_loading_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	_web_relay_loading_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_web_relay_loading_label)

	# Subtitle
	var subtitle_label = Label.new()
	subtitle_label.text = "Host is syncing game data..."
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	subtitle_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(subtitle_label)

	add_child(_web_relay_loading_overlay)

	# Ensure overlay is on top of everything
	_web_relay_loading_overlay.z_index = UI_MODAL_Z

	# Start pulse animation
	_web_relay_loading_pulse_tween = create_tween().set_loops()
	_web_relay_loading_pulse_tween.tween_property(_web_relay_loading_label, "modulate", Color(1, 1, 1, 0.5), 1.0).set_trans(Tween.TRANS_SINE)
	_web_relay_loading_pulse_tween.tween_property(_web_relay_loading_label, "modulate", Color(1, 1, 1, 1.0), 1.0).set_trans(Tween.TRANS_SINE)

	print("Main: P3-56 Web relay loading overlay shown (guest waiting for host state)")

func _dismiss_web_relay_loading_overlay() -> void:
	# P3-56: Dismiss the loading overlay once host state is received
	if not _web_relay_loading_overlay:
		return

	print("Main: P3-56 Dismissing web relay loading overlay (host state received)")

	# Stop pulse animation
	if _web_relay_loading_pulse_tween:
		_web_relay_loading_pulse_tween.kill()
		_web_relay_loading_pulse_tween = null

	# Fade out and remove
	var fade_tween = create_tween()
	fade_tween.tween_property(_web_relay_loading_overlay, "modulate", Color(1, 1, 1, 0), 0.3).set_trans(Tween.TRANS_SINE)
	fade_tween.tween_callback(_web_relay_loading_overlay.queue_free)
	_web_relay_loading_overlay = null
	_web_relay_loading_label = null

# =============================================================================
# P2-12: "Game Loaded" Fade Transition Overlay
# =============================================================================

func _show_game_loaded_overlay() -> void:
	# P2-12: Full-screen dark overlay shown during save load to hide visual setup.
	# Dismissed with a fade-out after the game state is fully restored.
	if _game_loaded_overlay:
		return  # Already showing

	_game_loaded_overlay = ColorRect.new()
	_game_loaded_overlay.name = "GameLoadedOverlay"
	_game_loaded_overlay.color = Color(0.08, 0.06, 0.04, 1.0)

	# Cover entire screen
	_game_loaded_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_loaded_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input during transition

	# Add centered "Loading..." label
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_loaded_overlay.add_child(center)

	var label = Label.new()
	label.text = "Loading saved game..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	label.add_theme_font_size_override("font_size", 28)
	center.add_child(label)

	# Pulse animation on the label
	var pulse_tween = create_tween().set_loops()
	pulse_tween.tween_property(label, "modulate", Color(1, 1, 1, 0.5), 1.0).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(label, "modulate", Color(1, 1, 1, 1.0), 1.0).set_trans(Tween.TRANS_SINE)

	add_child(_game_loaded_overlay)
	_game_loaded_overlay.z_index = 100

	print("Main: P2-12 Game loaded overlay shown")

func _dismiss_game_loaded_overlay() -> void:
	# P2-12: Fade out and remove the game-loaded overlay
	if not _game_loaded_overlay or not is_instance_valid(_game_loaded_overlay):
		_game_loaded_overlay = null
		return

	print("Main: P2-12 Dismissing game loaded overlay (fade out)")

	# CRITICAL: Immediately stop blocking input so the game is interactive
	# even during the visual fade-out animation.
	_game_loaded_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Stop any tweens running on children (pulse animation)
	for child in _game_loaded_overlay.get_children():
		for grandchild in child.get_children():
			if grandchild is Label:
				# Just reset modulate so the label is fully visible during fade-out
				grandchild.modulate = Color(1, 1, 1, 1)

	# Fade out the entire overlay
	var fade_tween = create_tween()
	fade_tween.tween_property(_game_loaded_overlay, "modulate", Color(1, 1, 1, 0), 0.5).set_trans(Tween.TRANS_SINE)
	fade_tween.tween_callback(_game_loaded_overlay.queue_free)
	_game_loaded_overlay = null

# =============================================================================
# SAVE-20: Save/Load Progress Indicator
# =============================================================================
# A compact overlay shown during save/load operations, especially useful for
# cloud saves where operations are async. Shows operation type and current stage.

func _show_save_load_progress(operation: String) -> void:
	# operation is "Saving" or "Loading"
	if _save_load_progress_overlay and is_instance_valid(_save_load_progress_overlay):
		# Already showing — just update the text
		if _save_load_progress_label:
			_save_load_progress_label.text = operation + "..."
		return

	_save_load_progress_overlay = PanelContainer.new()
	_save_load_progress_overlay.name = "SaveLoadProgressOverlay"

	# Position at top-center of screen (non-blocking banner)
	_save_load_progress_overlay.anchor_left = 0.3
	_save_load_progress_overlay.anchor_right = 0.7
	_save_load_progress_overlay.anchor_top = 0.0
	_save_load_progress_overlay.anchor_bottom = 0.0
	_save_load_progress_overlay.offset_top = 8
	_save_load_progress_overlay.offset_bottom = 60
	_save_load_progress_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input

	# Style: dark panel with gold border (WhiteDwarf theme)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.06, 0.04, 0.92)
	bg_style.border_color = _WhiteDwarfTheme.WH_GOLD
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(6)
	bg_style.set_content_margin_all(8)
	_save_load_progress_overlay.add_theme_stylebox_override("panel", bg_style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	_save_load_progress_overlay.add_child(vbox)

	# Main label: "Saving..." or "Loading..."
	_save_load_progress_label = Label.new()
	_save_load_progress_label.text = operation + "..."
	_save_load_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_load_progress_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	_save_load_progress_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_save_load_progress_label)

	# Detail label: shows current stage (e.g. "Serializing game data...")
	_save_load_progress_detail = Label.new()
	_save_load_progress_detail.text = ""
	_save_load_progress_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_load_progress_detail.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	_save_load_progress_detail.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_save_load_progress_detail)

	add_child(_save_load_progress_overlay)
	_save_load_progress_overlay.z_index = 101  # Above game loaded overlay

	# Pulse animation on the main label
	_save_load_progress_pulse_tween = create_tween().set_loops()
	_save_load_progress_pulse_tween.tween_property(_save_load_progress_label, "modulate", Color(1, 1, 1, 0.5), 0.8).set_trans(Tween.TRANS_SINE)
	_save_load_progress_pulse_tween.tween_property(_save_load_progress_label, "modulate", Color(1, 1, 1, 1.0), 0.8).set_trans(Tween.TRANS_SINE)

	print("Main: SAVE-20 Save/load progress indicator shown: %s" % operation)

func _update_save_load_progress(detail: String) -> void:
	if _save_load_progress_detail and is_instance_valid(_save_load_progress_detail):
		_save_load_progress_detail.text = detail

func _dismiss_save_load_progress() -> void:
	if not _save_load_progress_overlay or not is_instance_valid(_save_load_progress_overlay):
		_save_load_progress_overlay = null
		_save_load_progress_label = null
		_save_load_progress_detail = null
		return

	print("Main: SAVE-20 Dismissing save/load progress indicator")

	# Stop pulse tween
	if _save_load_progress_pulse_tween:
		_save_load_progress_pulse_tween.kill()
		_save_load_progress_pulse_tween = null

	# Stop auto-dismiss timer if running
	if _save_load_progress_auto_dismiss_timer and is_instance_valid(_save_load_progress_auto_dismiss_timer):
		_save_load_progress_auto_dismiss_timer.queue_free()
		_save_load_progress_auto_dismiss_timer = null

	# Fade out
	var fade_tween = create_tween()
	fade_tween.tween_property(_save_load_progress_overlay, "modulate", Color(1, 1, 1, 0), 0.3).set_trans(Tween.TRANS_SINE)
	fade_tween.tween_callback(_save_load_progress_overlay.queue_free)
	_save_load_progress_overlay = null
	_save_load_progress_label = null
	_save_load_progress_detail = null

# =============================================================================
# T7-20: AI Thinking Indicator
# =============================================================================

func _setup_ai_thinking_indicator() -> void:
	# Create a centered "AI is thinking..." overlay, styled like the WaitingForOpponent overlay
	ai_thinking_overlay = PanelContainer.new()
	ai_thinking_overlay.name = "AIThinkingOverlay"
	# Center horizontally, position in upper area below HUD
	ai_thinking_overlay.anchor_left = 0.3
	ai_thinking_overlay.anchor_right = 0.7
	ai_thinking_overlay.anchor_top = 0.0
	ai_thinking_overlay.anchor_bottom = 0.0
	ai_thinking_overlay.offset_top = 110.0  # Below HUD_Bottom
	ai_thinking_overlay.offset_bottom = 160.0
	ai_thinking_overlay.visible = false
	ai_thinking_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dark background with gold border — WhiteDwarf gothic style
	var banner_style = StyleBoxFlat.new()
	banner_style.bg_color = Color(0.08, 0.06, 0.12, 0.92)
	banner_style.border_color = _WhiteDwarfTheme.WH_GOLD
	banner_style.set_border_width_all(2)
	banner_style.border_width_top = 3
	banner_style.border_width_bottom = 3
	banner_style.set_corner_radius_all(6)
	banner_style.set_content_margin_all(8)
	ai_thinking_overlay.add_theme_stylebox_override("panel", banner_style)

	# Label with the thinking text
	ai_thinking_label = Label.new()
	ai_thinking_label.text = "AI is thinking..."
	ai_thinking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ai_thinking_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	ai_thinking_label.add_theme_font_size_override("font_size", 18)
	ai_thinking_overlay.add_child(ai_thinking_label)

	add_child(ai_thinking_overlay)
	print("Main: AI thinking indicator created (T7-20)")

func _show_ai_thinking_indicator(player: int) -> void:
	if not ai_thinking_overlay:
		return
	var phase_name = _get_phase_label_text(current_phase)
	ai_thinking_label.text = "AI is thinking..."
	_ai_thinking_dots_count = 3
	ai_thinking_overlay.visible = true
	_start_ai_thinking_pulse()
	print("Main: Showing AI thinking indicator (Player %d, %s)" % [player, phase_name])

func _hide_ai_thinking_indicator(_player: int = 0) -> void:
	if ai_thinking_overlay and ai_thinking_overlay.visible:
		ai_thinking_overlay.visible = false
		_stop_ai_thinking_pulse()
		print("Main: Hiding AI thinking indicator")

func _start_ai_thinking_pulse() -> void:
	if _ai_thinking_pulse_tween:
		_ai_thinking_pulse_tween.kill()
	_ai_thinking_pulse_tween = create_tween().set_loops()
	_ai_thinking_pulse_tween.tween_property(ai_thinking_overlay, "modulate", Color(1, 1, 1, 0.6), 0.8).set_trans(Tween.TRANS_SINE)
	_ai_thinking_pulse_tween.tween_property(ai_thinking_overlay, "modulate", Color(1, 1, 1, 1.0), 0.8).set_trans(Tween.TRANS_SINE)

func _stop_ai_thinking_pulse() -> void:
	if _ai_thinking_pulse_tween:
		_ai_thinking_pulse_tween.kill()
		_ai_thinking_pulse_tween = null
	if ai_thinking_overlay:
		ai_thinking_overlay.modulate = Color(1, 1, 1, 1)

func _update_ai_thinking_dots(delta: float) -> void:
	# Animate the ellipsis dots: "AI is thinking.", "AI is thinking..", "AI is thinking..."
	if not ai_thinking_overlay or not ai_thinking_overlay.visible:
		return
	_ai_thinking_dots_timer += delta
	if _ai_thinking_dots_timer >= 0.4:
		_ai_thinking_dots_timer = 0.0
		_ai_thinking_dots_count = (_ai_thinking_dots_count % 3) + 1
		var dots = ".".repeat(_ai_thinking_dots_count)
		ai_thinking_label.text = "AI is thinking" + dots

# =============================================================================
# T7-54: AI Action Log Overlay
# =============================================================================

func _setup_ai_action_log_overlay() -> void:
	_ai_action_log_overlay = AIActionLogOverlay.new()
	add_child(_ai_action_log_overlay)
	print("Main: AI action log overlay created (T7-54)")

# =============================================================================
# T7-56: AI Turn Replay Panel
# =============================================================================

func _setup_ai_turn_replay_panel() -> void:
	_ai_turn_replay_panel = AITurnReplayPanel.new()
	add_child(_ai_turn_replay_panel)
	print("Main: AI turn replay panel created (T7-56)")

func _toggle_ai_turn_replay_panel() -> void:
	"""T7-56: Toggle the AI turn replay panel visibility."""
	if _ai_turn_replay_panel:
		_ai_turn_replay_panel.toggle_panel()

# =============================================================================
# T7-19: AI Turn Summary Panel
# =============================================================================

func _setup_ai_turn_summary_panel() -> void:
	_ai_turn_summary_panel = AITurnSummaryPanel.new()
	add_child(_ai_turn_summary_panel)
	print("Main: AI turn summary panel created (T7-19)")

# =============================================================================
# T7-55: Spectator Mode Speed Indicator HUD
# =============================================================================

func _setup_spectator_speed_hud() -> void:
	"""Create a small speed indicator panel for AI vs AI spectator mode."""
	_spectator_speed_panel = PanelContainer.new()
	_spectator_speed_panel.name = "SpectatorSpeedPanel"
	# Position at top-center, below the phase HUD
	_spectator_speed_panel.anchor_left = 0.5
	_spectator_speed_panel.anchor_right = 0.5
	_spectator_speed_panel.anchor_top = 0.0
	_spectator_speed_panel.anchor_bottom = 0.0
	_spectator_speed_panel.offset_left = -100.0
	_spectator_speed_panel.offset_right = 100.0
	_spectator_speed_panel.offset_top = 72.0
	_spectator_speed_panel.offset_bottom = 100.0
	_spectator_speed_panel.visible = false  # Hidden until spectator mode confirmed
	_spectator_speed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dark background with gold border — WhiteDwarf style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.85)
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.6)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	_spectator_speed_panel.add_theme_stylebox_override("panel", style)

	_spectator_speed_label = Label.new()
	_spectator_speed_label.text = "Spectator: 1.0x  [<] [>]"
	_spectator_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_speed_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	_spectator_speed_label.add_theme_font_size_override("font_size", 12)
	_spectator_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectator_speed_panel.add_child(_spectator_speed_label)

	add_child(_spectator_speed_panel)
	print("Main: Spectator speed HUD created (T7-55)")

func _on_spectator_speed_changed(speed: float) -> void:
	"""T7-55: Update the spectator speed label when speed changes."""
	_update_spectator_speed_label(speed)

func _update_spectator_speed_label(speed: float) -> void:
	"""T7-55: Update the speed indicator label text."""
	if _spectator_speed_label:
		var speed_text = "%.1fx" % speed if speed != int(speed) else "%dx" % int(speed)
		_spectator_speed_label.text = "Spectator: %s  [< >]" % speed_text

func _on_spectator_phase_summary(player: int, phase: int, summary: Dictionary) -> void:
	"""T7-55: Display a phase summary in the action log overlay."""
	if not _ai_action_log_overlay:
		return
	var phase_name = _get_phase_label_text(phase).replace(" Phase", "")
	_ai_action_log_overlay.add_phase_summary(player, phase_name, summary)

# =============================================================================
# T7-36: AI Speed Controls HUD
# =============================================================================

func _setup_ai_speed_hud() -> void:
	"""T7-36: Create a speed indicator panel for AI games (non-spectator mode)."""
	_ai_speed_panel = PanelContainer.new()
	_ai_speed_panel.name = "AISpeedPanel"
	# Position at top-center, below the phase HUD
	_ai_speed_panel.anchor_left = 0.5
	_ai_speed_panel.anchor_right = 0.5
	_ai_speed_panel.anchor_top = 0.0
	_ai_speed_panel.anchor_bottom = 0.0
	_ai_speed_panel.offset_left = -120.0
	_ai_speed_panel.offset_right = 120.0
	_ai_speed_panel.offset_top = 72.0
	_ai_speed_panel.offset_bottom = 110.0
	_ai_speed_panel.visible = false  # Hidden until AI game confirmed
	_ai_speed_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dark background with gold border — WhiteDwarf style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.85)
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.6)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	_ai_speed_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_ai_speed_panel.add_child(vbox)

	_ai_speed_label = Label.new()
	_ai_speed_label.text = "AI Speed: Normal  [< >]"
	_ai_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ai_speed_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	_ai_speed_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_ai_speed_label)

	# Step-by-step continue button (hidden unless step-by-step mode is paused)
	_ai_step_continue_button = Button.new()
	_ai_step_continue_button.text = "Continue (Space)"
	_ai_step_continue_button.custom_minimum_size = Vector2(0, 24)
	_ai_step_continue_button.visible = false
	_ai_step_continue_button.pressed.connect(_on_step_continue_pressed)
	_WhiteDwarfTheme.apply_to_button(_ai_step_continue_button)
	vbox.add_child(_ai_step_continue_button)

	add_child(_ai_speed_panel)
	print("Main: T7-36 AI speed HUD created")

func _on_ai_speed_changed(preset: int, preset_name: String) -> void:
	"""T7-36: Update the AI speed label when speed changes."""
	_update_ai_speed_label(preset_name)

func _update_ai_speed_label(speed_name: String) -> void:
	"""T7-36: Update the AI speed indicator label text."""
	if _ai_speed_label:
		_ai_speed_label.text = "AI Speed: %s  [< >]" % speed_name

func _on_step_by_step_waiting() -> void:
	"""T7-36: Show the continue button when step-by-step mode pauses."""
	if _ai_step_continue_button:
		_ai_step_continue_button.visible = true

func _on_step_continue_pressed() -> void:
	"""T7-36: User pressed the continue button in step-by-step mode."""
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player:
		ai_player.step_by_step_continue()
	if _ai_step_continue_button:
		_ai_step_continue_button.visible = false

func _hide_step_continue_button() -> void:
	"""T7-36: Hide the continue button (e.g., when AI turn ends)."""
	if _ai_step_continue_button:
		_ai_step_continue_button.visible = false

# =============================================================================
# T7-52: AI Unit Highlighting During Actions
# =============================================================================

func _get_ai_action_highlight_color(action_type: String) -> Color:
	"""Map AI action types to highlight colors: blue=move, red=shoot, orange=charge/fight."""
	# Movement actions → blue
	if action_type in ["STAGE_MODEL_MOVE", "CONFIRM_UNIT_MOVE", "REMAIN_STATIONARY",
			"BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK",
			"SET_SCOUT_MODEL_DEST", "CONFIRM_SCOUT_MOVE", "SKIP_SCOUT_MOVE",
			"BEGIN_REDEPLOY", "SET_REDEPLOY_MODEL_POS", "CONFIRM_REDEPLOY", "SKIP_REDEPLOY",
			"ACTIVATE_KUNNIN_INFILTRATOR", "PLACE_KUNNIN_INFILTRATOR"]:
		return AIUnitHighlightScript.COLOR_MOVE
	# Shooting actions → red
	if action_type in ["SHOOT", "ASSIGN_WEAPON", "CONFIRM_TARGETS", "RESOLVE_SHOOTING",
			"COMPLETE_SHOOTING_FOR_UNIT", "CONTINUE_SEQUENCE", "APPLY_SAVES",
			"ROLL_DICE", "CONFIRM_AND_RESOLVE_ATTACKS", "USE_GRENADE_STRATAGEM",
			"SKIP_UNIT"]:
		# Only use red for shooting skip — check phase context
		if action_type == "SKIP_UNIT":
			var phase = GameState.get_current_phase()
			if phase == GameStateData.Phase.SHOOTING:
				return AIUnitHighlightScript.COLOR_SHOOT
			return Color.TRANSPARENT
		return AIUnitHighlightScript.COLOR_SHOOT
	# Charge actions → orange
	if action_type in ["CHARGE", "CHARGE_ROLL", "APPLY_CHARGE_MOVE", "COMPLETE_UNIT_CHARGE",
			"SKIP_CHARGE", "DECLARE_CHARGE"]:
		return AIUnitHighlightScript.COLOR_CHARGE
	# Fight actions → orange (same as charge per spec)
	if action_type in ["SELECT_FIGHTER", "ASSIGN_ATTACKS", "PILE_IN", "CONSOLIDATE",
			"FIGHT_WITH_UNIT"]:
		return AIUnitHighlightScript.COLOR_CHARGE
	return Color.TRANSPARENT

func _show_ai_unit_highlight(unit_id: String, color: Color) -> void:
	"""Add pulsing highlight rings around all models of the given AI unit."""
	# Skip if already highlighting this unit with same color
	if unit_id == _ai_highlighted_unit_id and _ai_highlight_nodes.size() > 0:
		# Check if color changed (e.g. unit went from move to charge)
		if _ai_highlight_nodes.size() > 0 and _ai_highlight_nodes[0].highlight_color == color:
			return
		# Color changed — clear and re-apply
		_clear_ai_unit_highlights()

	# Clear previous highlights if switching to a different unit
	if unit_id != _ai_highlighted_unit_id:
		_clear_ai_unit_highlights()

	_ai_highlighted_unit_id = unit_id

	# Find all token visuals for this unit on the board
	for child in token_layer.get_children():
		if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id and child.visible:
			# Determine ring radius from the token's base shape
			var radius = 28.0  # Default
			if "base_shape" in child and child.base_shape:
				var bounds = child.base_shape.get_bounds()
				radius = max(bounds.size.x, bounds.size.y) / 2.0 + 6.0  # Slightly outside the base

			var highlight = Node2D.new()
			highlight.set_script(AIUnitHighlightScript)
			highlight.setup(radius, color)
			highlight.position = child.position
			highlight.z_index = 9  # Just below token z_index of 10
			# Store reference to the token so we can track position
			highlight.set_meta("tracked_token", child)
			token_layer.add_child(highlight)
			_ai_highlight_nodes.append(highlight)

	if _ai_highlight_nodes.size() > 0:
		print("Main: T7-52 AI highlight: %d rings for unit %s (color=%s)" % [_ai_highlight_nodes.size(), unit_id, color])

func _clear_ai_unit_highlights() -> void:
	"""Remove all AI unit highlight rings from the board."""
	for node in _ai_highlight_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_ai_highlight_nodes.clear()
	_ai_highlighted_unit_id = ""

func _update_ai_unit_highlight_positions() -> void:
	"""Keep highlight rings synced with token positions (tokens may move during AI actions)."""
	for highlight in _ai_highlight_nodes:
		if not is_instance_valid(highlight):
			continue
		var token = highlight.get_meta("tracked_token") if highlight.has_meta("tracked_token") else null
		if is_instance_valid(token):
			highlight.position = token.position
			highlight.visible = token.visible

func _setup_phase_timer_hud() -> void:
	# T5-MP8: Create a phase timer label in the top HUD bar for multiplayer games
	var network_manager = get_node_or_null("/root/NetworkManager")
	var is_multiplayer = network_manager and network_manager.is_networked()
	if not is_multiplayer:
		return

	var hud_container = get_node_or_null("HUD_Bottom/HBoxContainer")
	if not hud_container:
		print("Main: HUD_Bottom/HBoxContainer not found for phase timer")
		return

	phase_timer_label = Label.new()
	phase_timer_label.name = "PhaseTimerLabel"
	phase_timer_label.text = ""
	phase_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	phase_timer_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	phase_timer_label.add_theme_font_size_override("font_size", 14)
	phase_timer_label.custom_minimum_size = Vector2(100, 0)
	phase_timer_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	phase_timer_label.visible = true

	# Insert before the phase action button (last element)
	var button_idx = phase_action_button.get_index()
	hud_container.add_child(phase_timer_label)
	hud_container.move_child(phase_timer_label, button_idx)
	print("Main: Phase timer HUD label created (T5-MP8)")

func _update_phase_timer_hud() -> void:
	# T5-MP8: Update the phase timer display in the HUD bar
	if not phase_timer_label:
		return

	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager or not network_manager.is_networked():
		phase_timer_label.visible = false
		return

	var time_left = network_manager.get_turn_time_remaining()
	if time_left < 0:
		phase_timer_label.visible = false
		return

	var seconds = int(time_left)
	phase_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	phase_timer_label.visible = true

	# Color-code: green > 30s, yellow 15-30s, red < 15s
	if seconds <= 15:
		phase_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif seconds <= 30:
		phase_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		phase_timer_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)

func _on_turn_timer_warning(seconds_remaining: int) -> void:
	# T5-MP8: Show toast warning when turn timer is running low
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return

	var is_my_turn = network_manager.is_local_player_turn()

	if is_my_turn:
		# P2-42: During deployment, show auto-deploy warning at 60s and 30s
		var game_state = get_node_or_null("/root/GameState")
		var is_deployment = game_state and game_state.get_current_phase() == GameStateData.Phase.DEPLOYMENT
		if seconds_remaining <= 10:
			_show_toast("WARNING: %ds remaining!" % seconds_remaining, 2.0)
		elif seconds_remaining <= 30:
			if is_deployment:
				_show_toast("WARNING: %ds remaining — undeployed units will go to Reserves!" % seconds_remaining, 3.0)
			else:
				_show_toast("Turn timer: %ds remaining" % seconds_remaining, 2.0)
		elif seconds_remaining <= 60 and is_deployment:
			_show_toast("Deployment timer: %ds remaining" % seconds_remaining, 2.0)
	print("Main: Turn timer warning - %ds remaining (my_turn=%s)" % [seconds_remaining, is_my_turn])

func _on_phase_auto_ended(phase_name: String) -> void:
	# T5-MP8: Notify both players when a phase is auto-ended due to AFK timeout
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return

	var active_player = GameState.get_active_player()
	var is_my_turn = network_manager.is_local_player_turn()

	# P2-42: Deployment timeout gets a specific message about auto-reserves
	if phase_name == "DEPLOYMENT":
		if is_my_turn:
			_show_toast("Deployment timed out — remaining units sent to Strategic Reserves", 4.0)
		else:
			_show_toast("Player %d's deployment timed out — remaining units sent to Reserves" % active_player, 4.0)
	elif is_my_turn:
		_show_toast("Phase auto-ended due to timeout!", 3.0)
	else:
		_show_toast("Player %d's %s phase timed out" % [active_player, phase_name.to_lower()], 3.0)
	print("Main: Phase auto-ended - %s (active_player=%d, my_turn=%s)" % [phase_name, active_player, is_my_turn])

# ============================================================================
# T5-MP7: Surrender Button (multiplayer only)
# ============================================================================

func _setup_surrender_button() -> void:
	"""T5-MP7: Create a surrender button in the HUD for multiplayer games."""
	var network_manager = get_node_or_null("/root/NetworkManager")
	var is_multiplayer = network_manager and network_manager.is_networked()
	if not is_multiplayer:
		return

	var hud_container = get_node_or_null("HUD_Bottom/HBoxContainer")
	if not hud_container:
		print("Main: HUD_Bottom/HBoxContainer not found for surrender button")
		return

	surrender_button = Button.new()
	surrender_button.name = "SurrenderButton"
	surrender_button.text = "Surrender"
	surrender_button.custom_minimum_size = Vector2(90, 0)
	surrender_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_WhiteDwarfTheme.apply_to_button(surrender_button)
	# Use a red-tinted style to visually distinguish from other buttons
	surrender_button.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	surrender_button.add_theme_color_override("font_hover_color", Color(1.0, 0.3, 0.3))
	surrender_button.pressed.connect(_on_surrender_button_pressed)
	hud_container.add_child(surrender_button)
	print("Main: Surrender button created (T5-MP7)")

func _on_surrender_button_pressed() -> void:
	"""T5-MP7: Show confirmation dialog before surrendering."""
	print("Main: Surrender button pressed - showing confirmation")
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Surrender"
	confirm_dialog.dialog_text = "Are you sure you want to surrender?\nYour opponent will be declared the winner."
	confirm_dialog.ok_button_text = "Surrender"
	confirm_dialog.cancel_button_text = "Cancel"
	confirm_dialog.confirmed.connect(_on_surrender_confirmed.bind(confirm_dialog))
	confirm_dialog.canceled.connect(func(): confirm_dialog.queue_free())
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()

func _on_surrender_confirmed(dialog: ConfirmationDialog) -> void:
	"""T5-MP7: Player confirmed surrender - notify NetworkManager."""
	print("Main: Surrender confirmed by player")
	dialog.queue_free()
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.request_surrender()

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
			get_node("/root/TurnManager").check_deployment_alternation(unit_id)
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

func _show_deep_strike_placement_dialog(unit_id: String) -> void:
	"""P2-80: Show dialog for choosing between Deep Strike and Strategic Reserves placement rules."""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	print("Main: P2-80 — Showing DeepStrikePlacementDialog for %s" % unit_name)

	var dialog = load("res://dialogs/DeepStrikePlacementDialog.gd").new()
	add_child(dialog)
	dialog.z_index = UI_MODAL_Z
	dialog.setup(unit_id, unit_name)
	dialog.placement_chosen.connect(_on_deep_strike_placement_chosen)
	dialog.popup_centered()

func _on_deep_strike_placement_chosen(unit_id: String, placement_type: String) -> void:
	"""P2-80: Handle player's choice of placement type."""
	print("Main: P2-80 — Player chose %s placement for %s" % [placement_type, unit_id])
	_reinforcement_placement_type = placement_type
	_begin_reinforcement_placement(unit_id)

func _begin_reinforcement_placement(unit_id: String) -> void:
	"""Start placing a reserve unit on the battlefield as reinforcement"""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var reserve_type = unit.get("reserve_type", "strategic_reserves")

	# P2-80: Use the chosen placement type if available, otherwise default to reserve_type
	var placement_type = _reinforcement_placement_type if _reinforcement_placement_type != "" else reserve_type
	var type_label = "Deep Strike" if placement_type == "deep_strike" else "Strategic Reserves"

	print("Main: Beginning reinforcement placement for %s (%s)" % [unit_name, type_label])

	# Ensure deployment controller exists (it's freed during phase transitions)
	if not deployment_controller:
		print("Main: Creating deployment controller for reinforcement placement")
		setup_deployment_controller()

	# Use the deployment controller to handle model placement
	if deployment_controller:
		# Set reinforcement mode flag on deployment controller
		deployment_controller.is_reinforcement_mode = true
		# P2-80: Store placement type override on the controller for real-time validation
		deployment_controller.reinforcement_placement_type = placement_type

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

		# Show attached characters in the status text
		var attached_char_names = []
		var attachment_data = unit.get("attachment_data", {})
		for char_id in attachment_data.get("attached_characters", []):
			var char_unit = GameState.get_unit(char_id)
			if char_unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
				attached_char_names.append(char_unit.get("meta", {}).get("name", char_id))
		var char_suffix = ""
		if attached_char_names.size() > 0:
			char_suffix = " + " + ", ".join(attached_char_names)
		status_label.text = "Placing reinforcement: %s%s (%s) — >9\" from enemies" % [unit_name, char_suffix, type_label]
		# P2-80: Show board edge constraint only for strategic reserves placement
		if placement_type == "strategic_reserves":
			status_label.text += " — within 6\" of board edge"
		# Check for enemy Omni-scramblers creating 12" denial zones
		var active_player = GameState.get_active_player()
		var omni_positions = GameState.get_omni_scrambler_positions(active_player)
		if omni_positions.size() > 0:
			status_label.text += " — >12\" from Omni-scramblers"

		# Show 9" exclusion bubbles around all enemy models
		_show_deep_strike_exclusion()

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
	# P2-80: Include placement_type if it differs from the unit's reserve_type
	var action = {
		"type": "PLACE_REINFORCEMENT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": model_rotations,
		"phase": GameStateData.Phase.MOVEMENT,
		"timestamp": Time.get_unix_time_from_system()
	}
	if _reinforcement_placement_type != "":
		action["placement_type"] = _reinforcement_placement_type

	var result = NetworkIntegration.route_action(action)

	if result.success:
		var unit_name = unit_data.get("meta", {}).get("name", unit_id)
		# Check for attached characters that also arrived
		var attachment_data = unit_data.get("attachment_data", {})
		var arrived_chars = []
		for char_id in attachment_data.get("attached_characters", []):
			var char_unit = GameState.get_unit(char_id)
			if char_unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
				arrived_chars.append(char_unit.get("meta", {}).get("name", char_id))
		var toast_text = "Reinforcement arrived: %s" % unit_name
		if arrived_chars.size() > 0:
			toast_text += " + " + ", ".join(arrived_chars)
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_success(toast_text)
		print("Main: Reinforcement placed successfully for %s" % toast_text)
	else:
		var errors = result.get("errors", [])
		var error_msg = errors[0] if errors.size() > 0 else "Failed to place reinforcement"
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_error(error_msg)
		print("Main: Reinforcement placement failed: %s" % str(errors))

	_selected_unit_for_reserves = ""
	_reinforcement_placement_type = ""  # P2-80: Clear placement type choice

	# Hide deep strike exclusion bubbles
	_hide_deep_strike_exclusion()

	# Reset reinforcement mode
	if deployment_controller:
		deployment_controller.is_reinforcement_mode = false
		deployment_controller.reinforcement_placement_type = ""  # P2-80: Clear

	# Disconnect reinforcement signal
	if deployment_controller.unit_confirmed.is_connected(_on_reinforcement_confirmed):
		deployment_controller.unit_confirmed.disconnect(_on_reinforcement_confirmed)

	refresh_unit_list()
	update_ui()

func _show_deep_strike_exclusion() -> void:
	"""Show 9-inch exclusion bubbles around all enemy models for reinforcement placement."""
	_hide_deep_strike_exclusion()  # Clean up any existing visual
	var active_player = GameState.get_active_player()
	var enemy_positions = GameState.get_enemy_model_positions(active_player)
	if enemy_positions.is_empty():
		return
	_deep_strike_exclusion_visual = load("res://scripts/DeepStrikeExclusionVisual.gd").new()
	if ghost_layer:
		ghost_layer.add_child(_deep_strike_exclusion_visual)
	else:
		add_child(_deep_strike_exclusion_visual)
	_deep_strike_exclusion_visual.show_exclusion(enemy_positions)

func _hide_deep_strike_exclusion() -> void:
	"""Hide and free the deep strike exclusion visual."""
	if _deep_strike_exclusion_visual and is_instance_valid(_deep_strike_exclusion_visual):
		_deep_strike_exclusion_visual.hide_exclusion()
		_deep_strike_exclusion_visual.queue_free()
		_deep_strike_exclusion_visual = null

# T4-7: Rapid Ingress placement — same as reinforcement but uses PLACE_RAPID_INGRESS_REINFORCEMENT
var _rapid_ingress_unit_id: String = ""

func _begin_rapid_ingress_placement(unit_id: String) -> void:
	"""Start placing a reserve unit on the battlefield via Rapid Ingress stratagem."""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var reserve_type = unit.get("reserve_type", "strategic_reserves")
	var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"

	print("Main: Beginning Rapid Ingress placement for %s (%s)" % [unit_name, type_label])

	# Use the deployment controller to handle model placement
	if deployment_controller:
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

		# Store that we're in rapid ingress placement mode
		_rapid_ingress_unit_id = unit_id

		# Connect to confirm signal for rapid ingress completion
		if not deployment_controller.unit_confirmed.is_connected(_on_rapid_ingress_confirmed):
			deployment_controller.unit_confirmed.connect(_on_rapid_ingress_confirmed)

		status_label.text = "Rapid Ingress: placing %s (%s) — >9\" from enemies" % [unit_name, type_label]
		if reserve_type == "strategic_reserves":
			status_label.text += " — within 6\" of board edge"

		# Show 9" exclusion bubbles around all enemy models
		_show_deep_strike_exclusion()

		unit_list.visible = false
		show_unit_card(unit_id)

func _on_rapid_ingress_confirmed() -> void:
	"""Handle Rapid Ingress placement completion."""
	if _rapid_ingress_unit_id == "":
		return

	var unit_id = _rapid_ingress_unit_id
	var unit_data = GameState.get_unit(unit_id)

	if unit_data.is_empty() or not deployment_controller:
		return

	# Collect model positions from the deployment controller
	var model_positions = []
	for pos in deployment_controller.temp_positions:
		model_positions.append(pos)

	var model_rotations = deployment_controller.temp_rotations.duplicate()

	print("Main: Rapid Ingress placement confirmed for %s with %d model positions" % [unit_id, model_positions.size()])

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

	# Create the rapid ingress reinforcement action
	var action = {
		"type": "PLACE_RAPID_INGRESS_REINFORCEMENT",
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
			toast_mgr.show_success("Rapid Ingress: %s arrived!" % unit_name)
		print("Main: Rapid Ingress reinforcement placed successfully for %s" % unit_name)
	else:
		var errors = result.get("errors", [])
		var error_msg = errors[0] if errors.size() > 0 else "Failed to place reinforcement via Rapid Ingress"
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_error(error_msg)
		print("Main: Rapid Ingress placement failed: %s" % str(errors))

	_rapid_ingress_unit_id = ""

	# Hide deep strike exclusion bubbles
	_hide_deep_strike_exclusion()

	# Reset reinforcement mode
	if deployment_controller:
		deployment_controller.is_reinforcement_mode = false

	# Disconnect rapid ingress signal
	if deployment_controller.unit_confirmed.is_connected(_on_rapid_ingress_confirmed):
		deployment_controller.unit_confirmed.disconnect(_on_rapid_ingress_confirmed)

	refresh_unit_list()
	update_ui()

# OA-24: Kunnin' Infiltrator redeployment placement
var _kunnin_infiltrator_unit_id: String = ""

func _begin_kunnin_infiltrator_placement(unit_id: String) -> void:
	"""Start placing a unit at a new position via Kunnin' Infiltrator redeployment."""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	print("Main: Beginning Kunnin' Infiltrator redeployment placement for %s" % unit_name)

	# Ensure deployment controller exists
	if not deployment_controller:
		print("Main: Creating deployment controller for Kunnin' Infiltrator placement")
		setup_deployment_controller()

	if deployment_controller:
		deployment_controller.is_reinforcement_mode = true

		# Hide existing unit tokens temporarily (unit is "removed from the battlefield")
		for child in token_layer.get_children():
			if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id:
				child.visible = false

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

		# Store that we're in kunnin infiltrator placement mode
		_kunnin_infiltrator_unit_id = unit_id

		# Connect to confirm signal for placement completion
		if not deployment_controller.unit_confirmed.is_connected(_on_kunnin_infiltrator_confirmed):
			deployment_controller.unit_confirmed.connect(_on_kunnin_infiltrator_confirmed)

		status_label.text = "Kunnin' Infiltrator: placing %s — must be >9\" from all enemies" % unit_name

		unit_list.visible = false
		show_unit_card(unit_id)

func _on_kunnin_infiltrator_confirmed() -> void:
	"""Handle Kunnin' Infiltrator placement completion."""
	if _kunnin_infiltrator_unit_id == "":
		return

	var unit_id = _kunnin_infiltrator_unit_id
	var unit_data = GameState.get_unit(unit_id)

	if unit_data.is_empty() or not deployment_controller:
		return

	# Collect model positions from the deployment controller
	var model_positions = []
	for pos in deployment_controller.temp_positions:
		model_positions.append(pos)

	var model_rotations = deployment_controller.temp_rotations.duplicate()

	print("Main: Kunnin' Infiltrator placement confirmed for %s with %d model positions" % [unit_id, model_positions.size()])

	# Reset the unit status back to DEPLOYED before sending the action
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": GameStateData.UnitStatus.DEPLOYED
			}])

	# Create the placement action
	var action = {
		"type": "PLACE_KUNNIN_INFILTRATOR",
		"actor_unit_id": unit_id,
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
			toast_mgr.show_success("Kunnin' Infiltrator: %s redeployed!" % unit_name)
		print("Main: Kunnin' Infiltrator redeployment placed successfully for %s" % unit_name)
	else:
		var errors = result.get("errors", [])
		var error_msg = errors[0] if errors.size() > 0 else "Failed to place via Kunnin' Infiltrator"
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			toast_mgr.show_error(error_msg)
		print("Main: Kunnin' Infiltrator placement failed: %s" % str(errors))

	_kunnin_infiltrator_unit_id = ""

	# Reset reinforcement mode
	if deployment_controller:
		deployment_controller.is_reinforcement_mode = false

	# Disconnect signal
	if deployment_controller.unit_confirmed.is_connected(_on_kunnin_infiltrator_confirmed):
		deployment_controller.unit_confirmed.disconnect(_on_kunnin_infiltrator_confirmed)

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

		# Connect objective removal signal (for Scorched Earth burns and Supply Drop)
		if not MissionManager.objective_removed.is_connected(_on_objective_removed):
			MissionManager.objective_removed.connect(_on_objective_removed)
		if MissionManager.has_signal("objective_burn_started") and not MissionManager.objective_burn_started.is_connected(_on_objective_burn_started):
			MissionManager.objective_burn_started.connect(_on_objective_burn_started)

		# Do initial control check
		MissionManager.check_all_objectives()

		print("Main: Objectives setup complete")
	else:
		print("Main: MissionManager not available, skipping objectives")

func _on_objective_removed(objective_id: String) -> void:
	var visual = MissionManager.objectives_visual_refs.get(objective_id)
	if visual:
		visual.set_removed()
		print("Main: Objective %s removed from board" % objective_id)

func _on_objective_burn_started(objective_id: String, _player: int) -> void:
	var visual = MissionManager.objectives_visual_refs.get(objective_id)
	if visual:
		visual.set_burning(true)
		print("Main: Objective %s is now burning" % objective_id)

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

	# Make unit tokens visible again and recreate visuals
	_recreate_unit_visuals()
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

	# Grab reference to the secondary mission overlay panel (defined in Main.tscn)
	secondary_mission_panel = get_node_or_null("SecondaryMissionPanel")
	if secondary_mission_panel:
		print("Main: SecondaryMissionPanel found in scene")
	else:
		print("Main: WARNING — SecondaryMissionPanel not found in scene")

func _setup_score_display() -> void:
	var hud_container = get_node_or_null("HUD_Bottom/HBoxContainer")
	if not hud_container:
		print("Main: HUD_Bottom/HBoxContainer not found for score display")
		return

	# Create a container for the score/CP display
	_score_display_container = HBoxContainer.new()
	_score_display_container.name = "ScoreDisplay"
	_score_display_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Add separator before score display
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(2, 0)
	_score_display_container.add_child(sep)

	# Player 1 info
	_p1_cp_label = Label.new()
	_p1_cp_label.name = "P1CPLabel"
	_p1_cp_label.add_theme_font_size_override("font_size", 14)
	_p1_cp_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	_score_display_container.add_child(_p1_cp_label)

	_p1_score_label = Label.new()
	_p1_score_label.name = "P1ScoreLabel"
	_p1_score_label.add_theme_font_size_override("font_size", 14)
	_p1_score_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	_p1_score_label.tooltip_text = "Victory Points (Primary + Secondary)"
	_score_display_container.add_child(_p1_score_label)

	# Divider between players
	var divider = VSeparator.new()
	divider.custom_minimum_size = Vector2(2, 0)
	_score_display_container.add_child(divider)

	# Player 2 info
	_p2_cp_label = Label.new()
	_p2_cp_label.name = "P2CPLabel"
	_p2_cp_label.add_theme_font_size_override("font_size", 14)
	_p2_cp_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_score_display_container.add_child(_p2_cp_label)

	_p2_score_label = Label.new()
	_p2_score_label.name = "P2ScoreLabel"
	_p2_score_label.add_theme_font_size_override("font_size", 14)
	_p2_score_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_p2_score_label.tooltip_text = "Victory Points (Primary + Secondary)"
	_score_display_container.add_child(_p2_score_label)

	# Add separator after score display
	var sep2 = VSeparator.new()
	sep2.custom_minimum_size = Vector2(2, 0)
	_score_display_container.add_child(sep2)

	# Insert after ActivePlayerBadge (index 1) so scores appear in the middle of the top bar
	var badge_idx = active_player_badge.get_index()
	hud_container.add_child(_score_display_container)
	hud_container.move_child(_score_display_container, badge_idx + 1)

	_update_score_display()
	print("Main: P3-120: Score display created in top bar (VP with primary/secondary breakdown)")

func _update_score_display() -> void:
	if not _p1_score_label or not _p2_score_label:
		return

	var p1_data = GameState.state.get("players", {}).get("1", {})
	var p2_data = GameState.state.get("players", {}).get("2", {})

	var p1_cp = p1_data.get("cp", 0)
	var p1_vp = p1_data.get("vp", 0)
	var p1_primary = p1_data.get("primary_vp", 0)
	var p1_secondary = p1_data.get("secondary_vp", 0)
	var p2_cp = p2_data.get("cp", 0)
	var p2_vp = p2_data.get("vp", 0)
	var p2_primary = p2_data.get("primary_vp", 0)
	var p2_secondary = p2_data.get("secondary_vp", 0)

	var p1_faction = GameState.get_faction_name(1)
	var p2_faction = GameState.get_faction_name(2)

	_p1_cp_label.text = "P1 %s CP: %d" % [p1_faction, p1_cp]
	_p1_score_label.text = "VP: %d (%dP+%dS)" % [p1_vp, p1_primary, p1_secondary]
	_p1_score_label.tooltip_text = "P1 Victory Points: %d total\nPrimary: %d | Secondary: %d" % [p1_vp, p1_primary, p1_secondary]
	_p2_cp_label.text = "P2 %s CP: %d" % [p2_faction, p2_cp]
	_p2_score_label.text = "VP: %d (%dP+%dS)" % [p2_vp, p2_primary, p2_secondary]
	_p2_score_label.tooltip_text = "P2 Victory Points: %d total\nPrimary: %d | Secondary: %d" % [p2_vp, p2_primary, p2_secondary]

# P3-109: Setup turn/round progress indicator in top bar
func _setup_round_indicator() -> void:
	var hud_container = get_node_or_null("HUD_Bottom/HBoxContainer")
	if not hud_container:
		print("Main: HUD_Bottom/HBoxContainer not found for round indicator")
		return

	# Create the round indicator label
	_round_indicator_label = Label.new()
	_round_indicator_label.name = "RoundIndicator"
	_round_indicator_label.add_theme_font_size_override("font_size", 14)
	_round_indicator_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))  # Gold color for visibility
	_round_indicator_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Add separator before round indicator
	var sep = VSeparator.new()
	sep.name = "RoundIndicatorSep"
	sep.custom_minimum_size = Vector2(2, 0)

	# Insert at the beginning of the HBox (before PhaseLabel) so it's always visible
	hud_container.add_child(sep)
	hud_container.move_child(sep, 0)
	hud_container.add_child(_round_indicator_label)
	hud_container.move_child(_round_indicator_label, 0)

	_update_round_indicator()
	print("Main: P3-109: Round indicator created in top bar")

# P3-109: Update the round indicator text
func _update_round_indicator() -> void:
	if not _round_indicator_label:
		return

	var battle_round = GameState.get_battle_round()
	var active_player = GameState.get_active_player()
	var current_game_phase = GameState.get_current_phase()

	# During pre-game phases (before actual battle rounds), show setup indicator
	if current_game_phase in [GameStateData.Phase.FORMATIONS, GameStateData.Phase.DEPLOYMENT,
							  GameStateData.Phase.REDEPLOYMENT, GameStateData.Phase.SCOUT,
							  GameStateData.Phase.ROLL_OFF]:
		_round_indicator_label.text = "Setup"
	else:
		_round_indicator_label.text = "Round %d/5 - Player %d Turn" % [battle_round, active_player]

func _fix_hud_layout() -> void:
	# Fix z-ordering: BoardRoot children (tokens z=10, effects up to z=102) would render
	# above HUD panels (default z=0) within the same CanvasLayer. Push BoardRoot to a
	# negative z_index so all board elements render below the HUD panels.
	var board_root = get_node_or_null("BoardRoot")
	if board_root:
		board_root.z_index = -200
		print("Fixed HUD layout: BoardRoot z_index set to -200 (board elements render below HUD)")

	# Adjust both left and right HUD panels for proper layout
	var hud_left = get_node("HUD_Left")
	var hud_right = get_node("HUD_Right")

	# Unit stats panel starts hidden, so no bottom reservation needed initially
	var bottom_height = 0.0  # Panel is hidden by default
	var top_height = 100.0    # Space for top panel

	if hud_left:
		# Adjust HUD_Left to not overlap with panels
		hud_left.anchor_bottom = 1.0
		hud_left.offset_bottom = -bottom_height
		hud_left.anchor_top = 0.0
		hud_left.offset_top = top_height  # Leave space for top panel
		hud_left.z_index = UI_PANEL_Z
		print("Fixed HUD layout: HUD_Left adjusted for new layout")

	if hud_right:
		# HUD_Right extends full height when unit stats panel is hidden
		hud_right.anchor_bottom = 1.0
		hud_right.offset_bottom = -bottom_height
		hud_right.anchor_top = 0.0
		hud_right.offset_top = top_height  # Leave space for top panel
		hud_right.z_index = UI_PANEL_Z
		print("Fixed HUD layout: HUD_Right adjusted for new layout (full height, panel hidden)")

	# Set z_index on HUD_Bottom
	var hud_bottom = get_node_or_null("HUD_Bottom")
	if hud_bottom:
		hud_bottom.z_index = UI_PANEL_Z

	# Set z_index on unit stats and secondary mission panels
	if unit_stats_panel:
		unit_stats_panel.z_index = UI_PANEL_Z
	if secondary_mission_panel:
		secondary_mission_panel.z_index = UI_PANEL_Z

	# Ensure unit list expands to fill available space so all units are visible and scrollable
	var unit_list_panel = get_node_or_null("HUD_Right/VBoxContainer/UnitListPanel")
	if unit_list_panel:
		unit_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		unit_list_panel.custom_minimum_size = Vector2(0, 150)  # Minimum height of 150px
		print("Adjusted unit list: expand/fill with 150px minimum")

func _ensure_ui_panels_on_top() -> void:
	# Ensure all UI Control nodes that are direct children of Main render above board
	# elements. Board visuals are under BoardRoot (z_index = -200). As a robust safety
	# measure, we also set high z_index on all UI panels so they always appear on top.
	for child in get_children():
		if child is Control and child.z_index < UI_PANEL_Z:
			child.z_index = UI_PANEL_Z
	print("UI layering: All Control children set to z_index >= %d" % UI_PANEL_Z)

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

	# Theme score/CP display labels (preserve player colors)
	if _p1_score_label:
		_WhiteDwarfTheme.apply_to_label(_p1_score_label)
		_p1_score_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	if _p1_cp_label:
		_WhiteDwarfTheme.apply_to_label(_p1_cp_label)
		_p1_cp_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	if _p2_score_label:
		_WhiteDwarfTheme.apply_to_label(_p2_score_label)
		_p2_score_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	if _p2_cp_label:
		_WhiteDwarfTheme.apply_to_label(_p2_cp_label)
		_p2_cp_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

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

		# Connect to panel_visibility_changed to adjust HUD_Right layout
		if unit_stats_panel.has_signal("panel_visibility_changed"):
			unit_stats_panel.panel_visibility_changed.connect(_on_unit_stats_panel_visibility_changed)
			print("Connected to panel_visibility_changed signal from UnitStatsPanel")

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
	var keywords_container = VBoxContainer.new()
	content.add_child(keywords_container)

	var keywords_title = Label.new()
	keywords_title.text = "Keywords: "
	keywords_title.add_theme_font_size_override("font_size", 12)
	keywords_container.add_child(keywords_title)

	var keywords_label = Label.new()
	keywords_label.name = "KeywordsLabel"
	keywords_label.text = "TEST KEYWORDS - Panel Working!"
	keywords_label.add_theme_font_size_override("font_size", 12)
	keywords_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

func _setup_scout_moves_ui() -> void:
	print("Main: Setting up Scout Moves UI")
	# Scout Moves uses the unit list to show scout-eligible units
	# Units are selected from the list, then the player clicks on the board to set destinations
	# The ScoutMovesPhase handles all validation
	refresh_unit_list()

	# Connect unit list selection for scout moves if not already
	if not unit_list.item_selected.is_connected(_on_scout_unit_selected):
		unit_list.item_selected.connect(_on_scout_unit_selected)

	# Show status info
	var active_player = GameState.get_active_player()
	var scout_units = GameState.get_scout_units_for_player(active_player)
	status_label.text = "Scout Moves — Select a unit to move (max >9\" from enemies)"
	print("Main: Scout Moves setup complete. %d scout units for Player %d" % [scout_units.size(), active_player])

func _on_scout_unit_selected(index: int) -> void:
	"""Handle selection of a scout unit from the unit list"""
	if current_phase != GameStateData.Phase.SCOUT_MOVES:
		return

	var unit_id = unit_list.get_item_metadata(index)
	if unit_id == null or unit_id == "":
		return

	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	# Check if unit has already scouted
	if unit.get("flags", {}).get("scouted", false):
		print("Main: Unit %s already scouted" % unit_id)
		return

	# Begin scout move through network routing
	var action = {
		"type": "BEGIN_SCOUT_MOVE",
		"unit_id": unit_id,
		"player": GameState.get_active_player()
	}
	print("Main: Beginning scout move for %s" % unit_id)
	var result = NetworkIntegration.route_action(action)
	if result.get("success", false):
		_enter_scout_move_mode(unit_id)

func _enter_scout_move_mode(unit_id: String) -> void:
	"""Enter interactive scout move mode for a unit - allows clicking to place models"""
	var unit = GameState.get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", "Unknown")
	var scout_range = GameState.get_scout_range(unit_id)
	status_label.text = "Scout Move: %s — Click to set destination (max %d\", >9\" from enemies)" % [unit_name, int(scout_range)]

	# Store the unit being scouted for input handling
	_current_scout_unit_id = unit_id
	_scout_model_destinations = []
	for model in unit.get("models", []):
		_scout_model_destinations.append(null)

	# Update unit card
	unit_name_label.text = unit_name
	var model_count = unit.get("models", []).size()
	models_label.text = "Models: %d | Scout %d\"" % [model_count, int(scout_range)]
	keywords_label.text = ", ".join(unit.get("meta", {}).get("keywords", []))
	unit_card.visible = true

	# Show confirm/skip buttons
	confirm_button.visible = true
	confirm_button.text = "Confirm Scout"
	confirm_button.disabled = true  # Disabled until all models placed
	if not confirm_button.pressed.is_connected(_on_confirm_scout_pressed):
		confirm_button.pressed.connect(_on_confirm_scout_pressed)

	# Repurpose reset button as Skip
	reset_button.visible = true
	reset_button.text = "Skip Unit"
	if not reset_button.pressed.is_connected(_on_skip_scout_pressed):
		reset_button.pressed.connect(_on_skip_scout_pressed)

func _on_confirm_scout_pressed() -> void:
	"""Confirm the scout move for the current unit"""
	if _current_scout_unit_id == "":
		return

	var action = {
		"type": "CONFIRM_SCOUT_MOVE",
		"unit_id": _current_scout_unit_id,
		"model_positions": _scout_model_destinations,
		"player": GameState.get_active_player()
	}
	var result = NetworkIntegration.route_action(action)
	if result.get("success", false):
		print("Main: Scout move confirmed for %s" % _current_scout_unit_id)

	_exit_scout_move_mode()
	refresh_unit_list()

func _on_skip_scout_pressed() -> void:
	"""Skip the scout move for the current unit"""
	if _current_scout_unit_id == "":
		return

	var action = {
		"type": "SKIP_SCOUT_UNIT",
		"unit_id": _current_scout_unit_id,
		"player": GameState.get_active_player()
	}
	var result = NetworkIntegration.route_action(action)
	if result.get("success", false):
		print("Main: Scout move skipped for %s" % _current_scout_unit_id)

	_exit_scout_move_mode()
	refresh_unit_list()

func _exit_scout_move_mode() -> void:
	"""Clean up scout move mode"""
	_current_scout_unit_id = ""
	_scout_model_destinations = []
	status_label.text = "Scout Moves — Select a unit to move"
	confirm_button.visible = false
	reset_button.visible = false

	# Disconnect scout-specific button handlers
	if confirm_button.pressed.is_connected(_on_confirm_scout_pressed):
		confirm_button.pressed.disconnect(_on_confirm_scout_pressed)
	if reset_button.pressed.is_connected(_on_skip_scout_pressed):
		reset_button.pressed.disconnect(_on_skip_scout_pressed)

func _handle_scout_move_click(world_pos: Vector2) -> void:
	"""Handle a board click during scout move mode - move the entire unit as a group"""
	if _current_scout_unit_id == "":
		return

	var unit = GameState.get_unit(_current_scout_unit_id)
	if unit.is_empty():
		return

	var models = unit.get("models", [])
	if models.is_empty():
		return

	# Calculate the unit's centroid (average position of all models)
	var centroid = Vector2.ZERO
	var valid_model_count = 0
	for model in models:
		var pos = model.get("position", null)
		if pos != null:
			centroid += Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
			valid_model_count += 1

	if valid_model_count == 0:
		print("Main: No models have positions, cannot scout move")
		return

	centroid /= valid_model_count

	# Calculate the offset to move the unit centroid to the click position
	var offset = world_pos - centroid

	# Check that the move distance doesn't exceed scout range
	var scout_range = GameState.get_scout_range(_current_scout_unit_id)
	var move_distance_inches = offset.length() / 40.0  # PX_PER_INCH = 40
	if move_distance_inches > scout_range + 0.01:
		# Clamp the offset to max scout range
		offset = offset.normalized() * scout_range * 40.0
		print("Main: Scout move clamped to max range of %d\"" % int(scout_range))

	# Calculate new positions for all models (maintaining formation)
	var new_positions = []
	var all_valid = true
	var validation_error = ""

	for i in range(models.size()):
		var model = models[i]
		var pos = model.get("position", null)
		if pos == null:
			new_positions.append(null)
			continue

		var old_pos = Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
		var new_pos = old_pos + offset
		var new_pos_dict = {"x": new_pos.x, "y": new_pos.y}

		# Validate via phase validation
		var validate_action = {
			"type": "SET_SCOUT_MODEL_DEST",
			"unit_id": _current_scout_unit_id,
			"model_index": i,
			"destination": new_pos_dict
		}
		var validation = NetworkIntegration.route_action(validate_action)
		if not validation.get("success", false):
			var errors = validation.get("errors", [])
			if errors.size() > 0:
				validation_error = errors[0]
				all_valid = false
				break

		new_positions.append(new_pos_dict)

	if not all_valid:
		# Show toast with error
		print("Main: Scout move invalid: %s" % validation_error)
		if has_node("/root/ToastManager"):
			get_node("/root/ToastManager").show_toast(validation_error, "error")
		return

	# Store destinations and enable confirm
	_scout_model_destinations = new_positions
	confirm_button.disabled = false

	# Visual feedback: update status with distance
	var actual_distance = offset.length() / 40.0
	status_label.text = "Scout Move: %s — %.1f\" (Click Confirm or choose new position)" % [
		unit.get("meta", {}).get("name", "Unknown"), actual_distance
	]

	# Move token visuals to preview position
	_update_scout_preview_tokens(_current_scout_unit_id, new_positions)

func _update_scout_preview_tokens(unit_id: String, positions: Array) -> void:
	"""Update the visual tokens to show scout move preview"""
	# Find and move existing tokens on the board
	for child in token_layer.get_children():
		if child.has_method("get_unit_id") and child.get_unit_id() == unit_id:
			# This is a token for our unit - update model positions
			if child.has_method("update_model_positions"):
				child.update_model_positions(positions)
			return

	# If no token method available, just update positions directly in visuals
	# The actual game state update happens on CONFIRM_SCOUT_MOVE
	print("Main: Preview positions set for %s (visual update via confirm)" % unit_id)

func _setup_mathhammer_ui() -> void:
	# Create MathhammerUI and add it to the left HUD
	print("Setting up Mathhammer UI...")
	
	# Create the MathhammerUI instance using preload
	var MathhammerUIClass = preload("res://scripts/MathhammerUI.gd")
	mathhammer_ui = MathhammerUIClass.new()
	mathhammer_ui.name = "MathhammerUI"
	
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
		print("ERROR: Failed to create MathhammerUI instance!")

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

	# Add terrain-related controls to HUD
	var hud_container = $HUD_Bottom/HBoxContainer
	if hud_container:
		# Add separator
		var separator = VSeparator.new()
		hud_container.add_child(separator)

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

		# If objectives are empty, reinitialize from MissionManager before creating visuals
		if objectives.size() == 0:
			print("Main: No objectives in GameState, reinitializing from MissionManager...")
			MissionManager._setup_objectives_for_deployment(GameState.get_deployment_type())
			objectives = GameState.state.board.get("objectives", [])

		print("Main: Creating visuals for %d objectives" % objectives.size())
		
		for obj in objectives:
			var obj_visual = preload("res://scripts/ObjectiveVisual.gd").new()
			obj_visual.setup(obj)
			objectives_container.add_child(obj_visual)
			
			# Store reference in MissionManager for easy access
			MissionManager.objectives_visual_refs[obj.id] = obj_visual
			
			# Connect to control changes (T7-39: also flash on change)
			MissionManager.objective_control_changed.connect(
				func(obj_id, controller, old_ctrl):
					if obj_id == obj.id:
						obj_visual.update_control(controller)
						obj_visual.flash_control_change(controller, old_ctrl)
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

	# T5-V14: Set player numbers for deployment zone edge highlighting
	if p1_zone.has_method("set_active"):
		p1_zone.player_number = 1
	if p2_zone.has_method("set_active"):
		p2_zone.player_number = 2

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
	# Clean up scout phase visuals
	_scout_destroy_visuals()
	_scout_clear_highlights()
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
			if phase_instance.grenade_result.is_connected(shooting_controller._on_grenade_result):
				phase_instance.grenade_result.disconnect(shooting_controller._on_grenade_result)
				print("Main: Disconnected grenade_result")
			# T7-53: Disconnect shooting_damage_applied
			if phase_instance.has_signal("shooting_damage_applied") and shooting_controller.has_method("_on_shooting_damage_visual"):
				if phase_instance.shooting_damage_applied.is_connected(shooting_controller._on_shooting_damage_visual):
					phase_instance.shooting_damage_applied.disconnect(shooting_controller._on_shooting_damage_visual)
					print("Main: Disconnected shooting_damage_applied")

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
		GameStateData.Phase.FORMATIONS:
			_setup_formations_phase()
		GameStateData.Phase.DEPLOYMENT:
			setup_deployment_controller()
		GameStateData.Phase.SCOUT_MOVES:
			_setup_scout_moves_ui()
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

	# P2-40: Reset deployment log for new deployment phase
	_deployment_log_entries.clear()
	if _deployment_log_label:
		_deployment_log_label.text = ""
	print("P2-40: Deployment log cleared for new deployment phase")

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

	# P3-54: Setup keyboard shortcut reference overlay
	_setup_keyboard_shortcut_overlay()

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

func _setup_keyboard_shortcut_overlay() -> void:
	# P3-54: Create keyboard shortcut reference overlay (toggled with ? key)
	if _keyboard_shortcut_overlay and is_instance_valid(_keyboard_shortcut_overlay):
		_keyboard_shortcut_overlay.queue_free()

	_keyboard_shortcut_overlay = KeyboardShortcutOverlay.new()
	_keyboard_shortcut_overlay.name = "KeyboardShortcutOverlay"

	# Position bottom-left, above the HUD bottom bar
	_keyboard_shortcut_overlay.anchor_left = 0.0
	_keyboard_shortcut_overlay.anchor_right = 0.0
	_keyboard_shortcut_overlay.anchor_top = 1.0
	_keyboard_shortcut_overlay.anchor_bottom = 1.0
	_keyboard_shortcut_overlay.offset_left = 10
	_keyboard_shortcut_overlay.offset_right = 290
	_keyboard_shortcut_overlay.offset_top = -420
	_keyboard_shortcut_overlay.offset_bottom = -55

	add_child(_keyboard_shortcut_overlay)
	print("[Main] P3-54: Keyboard shortcut overlay created")


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
	unit_list.gui_input.connect(_on_unit_list_gui_input)
	unit_list.mouse_exited.connect(_on_unit_list_mouse_exited)
	undo_button.pressed.connect(_on_undo_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	# Phase action button connection will be handled in update_ui_for_phase()
	
	# Phase management signals
	PhaseManager.phase_changed.connect(_on_phase_changed)
	PhaseManager.phase_completed.connect(_on_phase_completed)

	# P2-40: Listen for deployment actions via GameManager.result_applied
	# (DEPLOY_UNIT goes through GameManager directly, not through the phase system)
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.result_applied.connect(_on_phase_action_for_deployment_log)
		print("P2-40: Connected to GameManager.result_applied for deployment log")

	TurnManager.deployment_side_changed.connect(_on_deployment_side_changed)
	TurnManager.deployment_phase_complete.connect(_on_deployment_complete)
	
	# Controller signals (if they exist) — guard against double-connection
	# (setup_deployment_controller already connects these)
	if deployment_controller:
		if not deployment_controller.unit_confirmed.is_connected(_on_unit_confirmed):
			deployment_controller.unit_confirmed.connect(_on_unit_confirmed)
		if not deployment_controller.models_placed_changed.is_connected(_on_models_placed_changed):
			deployment_controller.models_placed_changed.connect(_on_models_placed_changed)
		if deployment_controller.has_signal("coherency_warning_changed") and not deployment_controller.coherency_warning_changed.is_connected(_on_coherency_warning_changed):
			deployment_controller.coherency_warning_changed.connect(_on_coherency_warning_changed)
	
	# Connect save/load signals
	SaveLoadManager.save_completed.connect(_on_save_completed)
	SaveLoadManager.load_completed.connect(_on_load_completed)
	SaveLoadManager.autosave_completed.connect(_on_autosave_completed)
	SaveLoadManager.save_failed.connect(_on_save_failed)
	SaveLoadManager.load_failed.connect(_on_load_failed)
	# SAVE-20: Connect progress indicator signals
	SaveLoadManager.save_started.connect(_on_save_started)
	SaveLoadManager.load_started.connect(_on_load_started)
	SaveLoadManager.operation_progress.connect(_on_save_load_progress)
	if OS.has_feature("web"):
		SaveLoadManager.delete_completed.connect(_on_delete_completed_main)

	# Connect VP/score signals to update top bar display
	if MissionManager and MissionManager.has_signal("victory_points_scored"):
		if not MissionManager.victory_points_scored.is_connected(_on_score_changed):
			MissionManager.victory_points_scored.connect(_on_score_changed)
			print("Main: Connected to MissionManager.victory_points_scored for score display")
	var sec_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if sec_mgr and sec_mgr.has_signal("secondary_vp_scored"):
		if not sec_mgr.secondary_vp_scored.is_connected(_on_secondary_score_changed):
			sec_mgr.secondary_vp_scored.connect(_on_secondary_score_changed)
			print("Main: Connected to SecondaryMissionManager.secondary_vp_scored for score display")
	# P3-120: Connect to stratagem_used signal so CP display updates immediately when stratagems are used
	var strat_mgr = get_node_or_null("/root/StratagemManager")
	if strat_mgr and strat_mgr.has_signal("stratagem_used"):
		if not strat_mgr.stratagem_used.is_connected(_on_stratagem_used_update_display):
			strat_mgr.stratagem_used.connect(_on_stratagem_used_update_display)
			print("Main: P3-120: Connected to StratagemManager.stratagem_used for CP display updates")

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
		if not NetworkManager.game_over.is_connected(_on_network_game_over):
			NetworkManager.game_over.connect(_on_network_game_over)
			print("Main: Connected to NetworkManager.game_over signal")
		# T5-MP8: Connect phase timeout signals
		if NetworkManager.has_signal("turn_timer_warning") and not NetworkManager.turn_timer_warning.is_connected(_on_turn_timer_warning):
			NetworkManager.turn_timer_warning.connect(_on_turn_timer_warning)
			print("Main: Connected to NetworkManager.turn_timer_warning signal")
		if NetworkManager.has_signal("phase_auto_ended") and not NetworkManager.phase_auto_ended.is_connected(_on_phase_auto_ended):
			NetworkManager.phase_auto_ended.connect(_on_phase_auto_ended)
			print("Main: Connected to NetworkManager.phase_auto_ended signal")
		# P2-41: Connect graceful disconnect signal
		if NetworkManager.has_signal("peer_disconnect_grace_period") and not NetworkManager.peer_disconnect_grace_period.is_connected(_on_peer_disconnect_grace_period):
			NetworkManager.peer_disconnect_grace_period.connect(_on_peer_disconnect_grace_period)
			print("Main: Connected to NetworkManager.peer_disconnect_grace_period signal")
	

## MA-41: Check if a text input control (LineEdit/TextEdit) currently has focus.
## When true, keyboard input should not trigger game actions (camera pan, hotkeys, etc.).
func _is_text_input_focused() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _input(event: InputEvent) -> void:
	# ESC key handling — highest priority: opens settings menu (or closes overlays first)
	# Use direct keycode check for reliability (is_action_pressed can miss with physical_keycode-only mappings)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		print("Main: Escape key pressed")
		# T7-56: Close replay panel on ESC if open
		if _ai_turn_replay_panel and _ai_turn_replay_panel.visible:
			_ai_turn_replay_panel.hide_panel()
			get_viewport().set_input_as_handled()
			return
		if shooting_controller and shooting_controller.active_shooter_id != "":
			# Let ShootingController handle ESC for deselect/cancel
			return
		# Close save/load dialog if open
		if save_load_dialog and save_load_dialog.visible:
			save_load_dialog.hide()
			get_viewport().set_input_as_handled()
			return
		# Close settings menu if open, otherwise open it
		if _settings_menu and is_instance_valid(_settings_menu):
			_settings_menu.queue_free()
			_settings_menu = null
			print("Main: Settings menu closed via Escape")
			get_viewport().set_input_as_handled()
			return
		# Open settings menu
		_settings_menu = SettingsMenu.new()
		_settings_menu.show_return_to_menu = true
		_settings_menu.settings_closed.connect(_on_settings_menu_closed)
		_settings_menu.save_load_requested.connect(_on_settings_save_load_requested)
		add_child(_settings_menu)
		_settings_menu.z_index = UI_MODAL_Z
		print("Main: Settings menu opened via Escape")
		get_viewport().set_input_as_handled()
		return

	# MA-41: Skip all non-Escape keyboard input when a text input field has focus
	# (e.g., typing a save name in SaveLoadDialog should not trigger game hotkeys)
	if event is InputEventKey and _is_text_input_focused():
		return

	# Handle mouse clicks for scout move placement (ScoutMovesPhase)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_phase == GameStateData.Phase.SCOUT_MOVES and _current_scout_unit_id != "":
			var ui_rect = get_viewport().get_visible_rect()
			var right_hud_rect = Rect2(ui_rect.size.x - 400, 0, 400, ui_rect.size.y)
			var bottom_hud_rect = Rect2(0, ui_rect.size.y - 100, ui_rect.size.x, 100)

			if not right_hud_rect.has_point(event.position) and not bottom_hud_rect.has_point(event.position):
				var world_pos = screen_to_world_position(event.position)
				_handle_scout_move_click(world_pos)
				get_viewport().set_input_as_handled()
				return

	# Right-click context menu for unit color/label editing (letter mode)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click(event)

	# Army panel toggle - KEY_U
	if event is InputEventKey and event.pressed and event.keycode == KEY_U:
		_toggle_army_panel()
		get_viewport().set_input_as_handled()
		return

	# Visual style toggle - KEY_8 (letter <-> enhanced)
	if event is InputEventKey and event.pressed and event.keycode == KEY_8:
		_toggle_visual_style()
		get_viewport().set_input_as_handled()
		return

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
	
	# P3-54: Keyboard shortcut reference overlay toggle — '?' (Shift+/) during deployment
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "shortcut_overlay"):
		if current_phase == GameStateData.Phase.DEPLOYMENT and _keyboard_shortcut_overlay:
			_keyboard_shortcut_overlay.toggle()
			get_viewport().set_input_as_handled()
			return

	# T7-36: AI speed control — comma/period to adjust, slash to cycle, Space to continue step-by-step
	if event is InputEventKey and event.pressed:
		var ai_player = get_node_or_null("/root/AIPlayer")
		if ai_player and ai_player.enabled:
			# T7-36: Space key continues step-by-step mode
			if KeybindingManager.matches_action(event, "ai_step_continue") and ai_player.is_step_by_step_paused():
				ai_player.step_by_step_continue()
				_hide_step_continue_button()
				get_viewport().set_input_as_handled()
				return

			# T7-55: Spectator speed control (AI vs AI mode)
			if _is_spectator_mode:
				if KeybindingManager.matches_action(event, "ai_speed_decrease"):
					var idx = ai_player._spectator_speed_index
					if idx > 0:
						ai_player.set_spectator_speed_index(idx - 1)
					get_viewport().set_input_as_handled()
					return
				elif KeybindingManager.matches_action(event, "ai_speed_increase"):
					var idx = ai_player._spectator_speed_index
					if idx < ai_player.SPECTATOR_SPEED_PRESETS.size() - 1:
						ai_player.set_spectator_speed_index(idx + 1)
					get_viewport().set_input_as_handled()
					return
				elif KeybindingManager.matches_action(event, "ai_speed_cycle"):
					ai_player.cycle_spectator_speed()
					get_viewport().set_input_as_handled()
					return
			else:
				# T7-36: Non-spectator AI speed control — comma/period/slash
				if KeybindingManager.matches_action(event, "ai_speed_decrease"):
					var preset = ai_player.get_ai_speed_preset()
					if preset > 0:
						ai_player.set_ai_speed_preset(preset - 1)
					get_viewport().set_input_as_handled()
					return
				elif KeybindingManager.matches_action(event, "ai_speed_increase"):
					var preset = ai_player.get_ai_speed_preset()
					if preset < ai_player.AISpeedPreset.STEP_BY_STEP:
						ai_player.set_ai_speed_preset(preset + 1)
					get_viewport().set_input_as_handled()
					return
				elif KeybindingManager.matches_action(event, "ai_speed_cycle"):
					ai_player.cycle_ai_speed()
					get_viewport().set_input_as_handled()
					return

	# T7-56: AI Turn Replay panel toggle — 'r' key
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "toggle_replay_panel"):
		_toggle_ai_turn_replay_panel()
		get_viewport().set_input_as_handled()
		return

	# Secondary Missions panel toggle — 'm' key
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "toggle_missions_panel"):
		_toggle_secondary_mission_panel()
		get_viewport().set_input_as_handled()
		return

	# Board rotation - 'v' to rotate 90° clockwise
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "rotate_board"):
		rotate_board_view(PI / 2.0)
		get_viewport().set_input_as_handled()
		return

	# Deployment zone toggle - 'z' to show/hide deployment zones
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "toggle_deploy_zones"):
		_toggle_deployment_zones()
		get_viewport().set_input_as_handled()
		return

	# Terrain toggle - 'g' to show/hide terrain
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "toggle_terrain"):
		TerrainManager.toggle_terrain_visibility()
		print("Terrain visibility toggled: ", TerrainManager.terrain_visible)
		get_viewport().set_input_as_handled()
		return

	# Mathhammer panel toggle - 'h' to show/hide mathhammer
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "toggle_mathhammer"):
		_on_left_panel_toggle_pressed()
		get_viewport().set_input_as_handled()
		return

	# Unit labels toggle - 'n' to show/hide unit name labels underneath models
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "toggle_unit_labels"):
		SettingsService.toggle_unit_labels()
		_force_redraw_all_tokens()
		print("Unit labels toggled: ", SettingsService.show_unit_labels)
		get_viewport().set_input_as_handled()
		return

	# Measuring Tape controls - 't' to measure, 'y' to clear
	if event is InputEventKey:
		# Start/stop measuring with measuring tape key
		var _mt_binding = KeybindingManager.get_binding("measuring_tape")
		if _mt_binding.size() > 0 and (event.keycode == _mt_binding.key or (_mt_binding.alt_key != 0 and event.keycode == _mt_binding.alt_key)):
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
					print("Maximum number of measurements reached (10). Clear with '%s' key." % KeybindingManager.get_key_display_name("clear_measurements"))
					MeasuringTapeManager.cancel_measurement()
				get_viewport().set_input_as_handled()
			return

		# Clear all measurements with clear measurements key
		if event.pressed and KeybindingManager.matches_action(event, "clear_measurements"):
			MeasuringTapeManager.clear_all_measurements()
			print("All measurements cleared")
			get_viewport().set_input_as_handled()
			return

	# Update measurement preview while dragging
	if event is InputEventMouseMotion and MeasuringTapeManager.is_measuring:
		var world_pos = screen_to_world_position(event.position)
		MeasuringTapeManager.update_measurement(world_pos)
	
	# Don't process other input while dialog is open
	if save_load_dialog and save_load_dialog.visible:
		return
	
	# Quick save/load via KeybindingManager
	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "quick_save"):
		print("[KeybindingManager] Quick save key detected")
		_perform_quick_save()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and KeybindingManager.matches_action(event, "quick_load"):
		print("[KeybindingManager] Quick load key detected")
		_perform_quick_load()
		get_viewport().set_input_as_handled()
		return

	# SAVE-16: Save slot shortcuts (Ctrl+1..5 to save, Shift+1..5 to load)
	if event is InputEventKey and event.pressed:
		for slot in range(1, SaveLoadManager.MAX_SAVE_SLOTS + 1):
			if KeybindingManager.matches_action(event, "save_slot_%d" % slot):
				print("[KeybindingManager] Save to slot %d detected" % slot)
				_perform_slot_save(slot)
				get_viewport().set_input_as_handled()
				return
			if KeybindingManager.matches_action(event, "load_slot_%d" % slot):
				print("[KeybindingManager] Load from slot %d detected" % slot)
				_perform_slot_load(slot)
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
	
	# Scout phase model dragging
	if current_phase == GameStateData.Phase.SCOUT and _scout_active_unit_id != "":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_scout_handle_mouse_press(event.position)
			else:
				_scout_handle_mouse_release(event.position)
		elif event is InputEventMouseMotion and _scout_dragging_model:
			_scout_handle_mouse_motion(event.position)

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
	# MA-41: Skip camera/view keyboard controls when a text input has focus
	var _text_focused = _is_text_input_focused()

	# View controls using BoardRoot transform
	var pan_speed = 800.0 * delta / view_zoom
	var view_changed = false

	# Build pan vector in screen space, then rotate to match board orientation
	var pan_dir = Vector2.ZERO
	if not _text_focused and KeybindingManager.is_action_pressed("camera_pan_up"):
		pan_dir.y -= 1.0
	if not _text_focused and KeybindingManager.is_action_pressed("camera_pan_down"):
		pan_dir.y += 1.0
	if not _text_focused and KeybindingManager.is_action_pressed("camera_pan_left"):
		pan_dir.x -= 1.0
	if not _text_focused and KeybindingManager.is_action_pressed("camera_pan_right"):
		pan_dir.x += 1.0
	if pan_dir != Vector2.ZERO:
		# Counter-rotate the pan direction so WASD always maps to screen directions
		view_offset += pan_dir.rotated(-view_rotation) * pan_speed
		view_changed = true

	# Zoom controls
	if not _text_focused and KeybindingManager.is_action_pressed("zoom_in"):
		view_zoom *= 1.03
		view_zoom = clamp(view_zoom, 0.1, 3.0)
		view_changed = true
	if not _text_focused and KeybindingManager.is_action_pressed("zoom_out"):
		view_zoom *= 0.97
		view_zoom = clamp(view_zoom, 0.1, 3.0)
		view_changed = true

	# Focus commands
	if not _text_focused and KeybindingManager.is_action_pressed("focus_p2_zone"):
		focus_on_player2_zone()
		view_changed = true
	
	
	if view_changed:
		update_view_transform()

	# T5-MP8: Update phase timer HUD and waiting overlay timer (runs every frame, labels only change on integer second)
	_update_phase_timer_hud()
	if waiting_overlay and waiting_overlay.visible and waiting_overlay_timer_label:
		var network_manager = get_node_or_null("/root/NetworkManager")
		if network_manager:
			var time_left = network_manager.get_turn_time_remaining()
			if time_left >= 0:
				var seconds = int(time_left)
				waiting_overlay_timer_label.text = "Turn timer: %d:%02d remaining" % [seconds / 60, seconds % 60]
				waiting_overlay_timer_label.visible = true
				# Color-code the timer text
				if seconds <= 15:
					waiting_overlay_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
				elif seconds <= 30:
					waiting_overlay_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
				else:
					waiting_overlay_timer_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
			else:
				waiting_overlay_timer_label.visible = false

	# T7-20: Animate the AI thinking indicator dots
	_update_ai_thinking_dots(delta)

	# T7-52: Keep AI unit highlights synced with token positions
	if _ai_highlight_nodes.size() > 0:
		_update_ai_unit_highlight_positions()

func reset_camera() -> void:
	camera.position = Vector2(
		SettingsService.get_board_width_px() / 2,
		SettingsService.get_board_height_px() / 2
	)
	camera.zoom = Vector2(0.3, 0.3)
	view_rotation = 0.0
	print("Camera reset to position: ", camera.position, " zoom: ", camera.zoom)

func rotate_board_view(angle: float) -> void:
	view_rotation = fmod(view_rotation + angle, TAU)
	# Snap to nearest 90 degrees to avoid floating point drift
	var steps = round(view_rotation / (PI / 2.0))
	view_rotation = steps * (PI / 2.0)
	update_view_transform()
	var degrees = int(rad_to_deg(view_rotation)) % 360
	print("Board rotated to %d degrees" % degrees)

func update_view_transform() -> void:
	# Apply transform to BoardRoot to simulate camera movement
	# Rotation is applied around the board center so the board spins in place
	var board_center = Vector2(
		SettingsService.get_board_width_px() / 2.0,
		SettingsService.get_board_height_px() / 2.0
	)
	var t = Transform2D()
	# Translate so board center is at origin, rotate, then translate back
	t = t.translated(-board_center)
	t = t.rotated(view_rotation)
	t = t.translated(board_center)
	# Apply zoom and pan
	t = t.scaled(Vector2(view_zoom, view_zoom))
	t.origin += -view_offset * view_zoom
	$BoardRoot.transform = t

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

# T5-UX10: Auto-zoom to deployment zone — smoothly pan and zoom camera to active player's zone
var _auto_zoom_tween: Tween = null

func focus_on_deployment_zone(player: int, animate: bool = true) -> void:
	var zone = BoardState.get_deployment_zone_for_player(player)
	if zone.size() == 0:
		print("T5-UX10: No deployment zone found for player %d" % player)
		return

	# Calculate bounding box of the zone polygon
	var min_pt = Vector2(INF, INF)
	var max_pt = Vector2(-INF, -INF)
	for point in zone:
		min_pt.x = min(min_pt.x, point.x)
		min_pt.y = min(min_pt.y, point.y)
		max_pt.x = max(max_pt.x, point.x)
		max_pt.y = max(max_pt.y, point.y)

	var zone_center = (min_pt + max_pt) / 2.0
	var zone_size = max_pt - min_pt

	# Calculate zoom to fit the zone with some padding (20% margin)
	var viewport_size = get_viewport().get_visible_rect().size
	var padding = 1.2
	var zoom_x = viewport_size.x / (zone_size.x * padding) if zone_size.x > 0 else 1.0
	var zoom_y = viewport_size.y / (zone_size.y * padding) if zone_size.y > 0 else 1.0
	var target_zoom = min(zoom_x, zoom_y)
	target_zoom = clamp(target_zoom, 0.3, 1.5)

	# Calculate offset so the zone center appears at viewport center
	var target_offset = zone_center - viewport_size / (2.0 * target_zoom)

	print("T5-UX10: Focusing on Player %d deployment zone — center: %s, zoom: %.2f" % [player, zone_center, target_zoom])

	if animate:
		# Kill any existing auto-zoom tween
		if _auto_zoom_tween and _auto_zoom_tween.is_valid():
			_auto_zoom_tween.kill()

		_auto_zoom_tween = create_tween()
		_auto_zoom_tween.set_parallel(true)
		_auto_zoom_tween.set_ease(Tween.EASE_OUT)
		_auto_zoom_tween.set_trans(Tween.TRANS_CUBIC)
		_auto_zoom_tween.tween_property(self, "view_zoom", target_zoom, 0.6)
		_auto_zoom_tween.tween_property(self, "view_offset", target_offset, 0.6)
		# Call update_view_transform each frame during the tween via a method tween
		_auto_zoom_tween.tween_method(_tween_update_view, 0.0, 1.0, 0.6)
	else:
		view_zoom = target_zoom
		view_offset = target_offset
		update_view_transform()

func _tween_update_view(_progress: float) -> void:
	update_view_transform()

# P2-40: Briefly pan camera to a world position, then return after a delay
func focus_on_position_briefly(world_pos: Vector2, hold_duration: float = 1.5, pan_duration: float = 0.5) -> void:
	print("P2-40: Panning camera to position %s (hold=%.1fs)" % [world_pos, hold_duration])

	# Save current camera state for return trip
	_pre_pan_offset = view_offset
	_pre_pan_zoom = view_zoom

	# Kill any existing pan tweens
	if _deployment_camera_pan_tween and _deployment_camera_pan_tween.is_valid():
		_deployment_camera_pan_tween.kill()
	if _deployment_camera_return_tween and _deployment_camera_return_tween.is_valid():
		_deployment_camera_return_tween.kill()

	# Calculate target offset to center the position in viewport
	var viewport_size = get_viewport().get_visible_rect().size
	var target_zoom = clamp(view_zoom, 0.4, 1.0)  # Zoom in slightly if too far out
	var target_offset = world_pos - viewport_size / (2.0 * target_zoom)

	# Animate pan to the target position
	_deployment_camera_pan_tween = create_tween()
	_deployment_camera_pan_tween.set_parallel(true)
	_deployment_camera_pan_tween.set_ease(Tween.EASE_OUT)
	_deployment_camera_pan_tween.set_trans(Tween.TRANS_CUBIC)
	_deployment_camera_pan_tween.tween_property(self, "view_zoom", target_zoom, pan_duration)
	_deployment_camera_pan_tween.tween_property(self, "view_offset", target_offset, pan_duration)
	_deployment_camera_pan_tween.tween_method(_tween_update_view, 0.0, 1.0, pan_duration)

	# After hold duration, pan back to the original view
	await get_tree().create_timer(pan_duration + hold_duration).timeout

	# Only return if we haven't been interrupted by another focus
	if _deployment_camera_return_tween and _deployment_camera_return_tween.is_valid():
		_deployment_camera_return_tween.kill()

	_deployment_camera_return_tween = create_tween()
	_deployment_camera_return_tween.set_parallel(true)
	_deployment_camera_return_tween.set_ease(Tween.EASE_IN_OUT)
	_deployment_camera_return_tween.set_trans(Tween.TRANS_CUBIC)
	_deployment_camera_return_tween.tween_property(self, "view_zoom", _pre_pan_zoom, pan_duration)
	_deployment_camera_return_tween.tween_property(self, "view_offset", _pre_pan_offset, pan_duration)
	_deployment_camera_return_tween.tween_method(_tween_update_view, 0.0, 1.0, pan_duration)
	print("P2-40: Camera returning to original position")

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
					var unit_keywords = unit_data.get("meta", {}).get("keywords", [])
					if GameState.unit_is_fortification(unit_id):
						ability_tag = " [FORT]"
					elif "TITANIC" in unit_keywords:
						ability_tag = " [TITAN]"
					elif GameState.unit_has_deep_strike(unit_id):
						ability_tag = " [DS]"
					elif GameState.unit_has_infiltrators(unit_id):
						ability_tag = " [INF]"
					# Show attached character names for bodyguard units with pre-declared attachments
					var attach_info = ""
					var attached_char_ids = unit_data.get("attachment_data", {}).get("attached_characters", [])
					if attached_char_ids.size() > 0:
						var char_names = []
						for char_id in attached_char_ids:
							var char_unit = GameState.get_unit(char_id)
							if not char_unit.is_empty():
								char_names.append(char_unit.get("meta", {}).get("name", char_id))
								model_count += char_unit["models"].size()
						if char_names.size() > 0:
							attach_info = " + " + ", ".join(char_names)
					var display_text = "%s (%d models)%s%s" % [unit_name, model_count, attach_info, ability_tag]
					unit_list.add_item(display_text)
					unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)

				# Reserves are declared during Formations phase, not Deployment.
				# Hide the reserves button during deployment.
				if reserves_button:
					reserves_button.visible = false
					reserves_button.disabled = true
					_selected_unit_for_reserves = ""

		GameStateData.Phase.SCOUT:
			# Show only scout-capable units that haven't completed their scout move
			unit_list.visible = true
			var phase_instance = PhaseManager.get_current_phase_instance()
			var pending_scouts = []
			if phase_instance and phase_instance.has_method("get_available_actions"):
				# Get pending scout unit IDs from the phase
				var scout_pending = phase_instance.get("scout_units_pending")
				if scout_pending:
					pending_scouts = scout_pending.get(active_player, [])

			if pending_scouts.size() == 0:
				unit_list.add_item("No scout units remaining")
				unit_list.set_item_disabled(0, true)
			else:
				for scout_unit_id in pending_scouts:
					var scout_unit = GameState.get_unit(scout_unit_id)
					if scout_unit.is_empty():
						continue
					var scout_name = scout_unit.get("meta", {}).get("name", scout_unit_id)
					var model_count = scout_unit.get("models", []).size()
					var scout_dist = GameState.get_scout_distance(scout_unit_id)
					var display_text = "%s (%d models) [Scout %d\"]" % [scout_name, model_count, int(scout_dist)]
					unit_list.add_item(display_text)
					unit_list.set_item_metadata(unit_list.get_item_count() - 1, scout_unit_id)

			print("Refreshing right panel unit list for scout - found ", pending_scouts.size(), " pending scout units")

		GameStateData.Phase.SCOUT_MOVES:
			# Show scout-eligible units during Scout Moves phase
			unit_list.visible = true
			var scout_moves_units = GameState.get_scout_units_for_player(active_player)
			print("Refreshing right panel unit list for Scout Moves - found ", scout_moves_units.size(), " scout units")

			if scout_moves_units.is_empty():
				unit_list.add_item("No units with Scout ability")
				unit_list.set_item_disabled(0, true)
			else:
				# In multiplayer, only show units when it's your turn
				if is_multiplayer and not is_my_turn:
					unit_list.add_item("Waiting for Player %d to scout..." % active_player)
					unit_list.set_item_disabled(0, true)
				else:
					unit_list.add_item("--- SCOUT MOVES (>9\" from enemies) ---")
					unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)
					for unit_id in scout_moves_units:
						var unit_data = GameState.get_unit(unit_id)
						var unit_name = unit_data.get("meta", {}).get("name", unit_id)
						var model_count = unit_data.get("models", []).size()
						var scout_range = GameState.get_scout_range(unit_id)
						var scouted = unit_data.get("flags", {}).get("scouted", false)
						var status = " [SCOUTED]" if scouted else ""
						var display_text = "%s (%d models) [Scout %d\"]%s" % [unit_name, model_count, int(scout_range), status]
						unit_list.add_item(display_text)
						unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
						if scouted:
							unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)

		GameStateData.Phase.MOVEMENT:
			# MovementController manages its own right panel UI, hide the shared unit list
			unit_list.visible = false
			var all_units = GameState.get_units_for_player(active_player)
			var deployed_count = 0
			var battle_round = GameState.get_battle_round()

			# Show reinforcements header if there are reserve units and it's Turn 2+
			var reserves = GameState.get_reserves_for_player(active_player)
			# Filter out characters that are attached to a bodyguard in reserves
			# (they arrive automatically with their bodyguard, not independently)
			var independent_reserves = []
			var attached_chars_in_reserves = {}  # bodyguard_id -> [char names]
			for reserve_id in reserves:
				var reserve_unit = GameState.get_unit(reserve_id)
				var attached_to = reserve_unit.get("attached_to", "")
				if attached_to != "":
					# This is an attached character — don't show separately
					if not attached_chars_in_reserves.has(attached_to):
						attached_chars_in_reserves[attached_to] = []
					var char_name = reserve_unit.get("meta", {}).get("name", reserve_id)
					attached_chars_in_reserves[attached_to].append(char_name)
				else:
					independent_reserves.append(reserve_id)

			if independent_reserves.size() > 0 and battle_round >= 2:
				unit_list.add_item("--- REINFORCEMENTS (Reserves) ---")
				unit_list.set_item_disabled(unit_list.get_item_count() - 1, true)
				for reserve_id in independent_reserves:
					var reserve_unit = GameState.get_unit(reserve_id)
					var reserve_name = reserve_unit.get("meta", {}).get("name", reserve_id)
					var reserve_type = reserve_unit.get("reserve_type", "strategic_reserves")
					var type_tag = "[DS]" if reserve_type == "deep_strike" else "[SR]"
					var model_count = reserve_unit.get("models", []).size()
					# Show attached characters in the display text
					var char_suffix = ""
					if attached_chars_in_reserves.has(reserve_id):
						char_suffix = " + " + ", ".join(attached_chars_in_reserves[reserve_id])
					var display_text = "%s %s%s (%d models) - DEPLOY" % [type_tag, reserve_name, char_suffix, model_count]
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
				# Skip attached characters — they move with their bodyguard unit
				if unit.get("attached_to", null) != null:
					continue
				if unit_status >= GameStateData.UnitStatus.DEPLOYED and unit_status != GameStateData.UnitStatus.IN_RESERVES:
					var unit_name = unit.get("meta", {}).get("name", unit_id)
					var model_count = unit.get("models", []).size()
					var moved = unit.get("flags", {}).get("moved", false)
					var status = " [MOVED]" if moved else ""
					# Show attached character names for bodyguard units
					var attach_info = ""
					var attached_char_ids = unit.get("attachment_data", {}).get("attached_characters", [])
					if attached_char_ids.size() > 0:
						var char_names = []
						for char_id in attached_char_ids:
							var char_unit = GameState.get_unit(char_id)
							if not char_unit.is_empty():
								char_names.append(char_unit.get("meta", {}).get("name", char_id))
								model_count += char_unit.get("models", []).size()
						if char_names.size() > 0:
							attach_info = " + " + ", ".join(char_names)
					var display_text = "%s%s (%d models)%s" % [unit_name, attach_info, model_count, status]
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
	var first_turn_player = GameState.state.get("meta", {}).get("first_turn_player", 0)
	var role_label = ""
	if first_turn_player > 0:
		role_label = "Attacker" if active_player == first_turn_player else "Defender"
	else:
		role_label = "Defender" if active_player == 1 else "Attacker"
	var player_text = "Player %d (%s)" % [active_player, role_label]
	active_player_badge.text = player_text

	# Update player scores and CP in top bar
	_update_score_display()

	# P3-109: Update round indicator
	_update_round_indicator()

	# Phase-specific UI updates
	match current_phase:
		GameStateData.Phase.FORMATIONS:
			status_label.text = "Declare Battle Formations — Player %d" % active_player
			phase_action_button.disabled = false

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

			# Update waiting-for-opponent overlay (T5-MP6)
			_update_waiting_for_opponent_overlay()

			# Reserves are declared in Formations phase — hide button during deployment
			if reserves_button:
				reserves_button.visible = false


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
					var total = deployment_controller.get_total_model_count()
					var mode_info = ""
					if deployment_controller.is_infiltrators_mode:
						mode_info = " [INFILTRATORS — >9\" from enemies & enemy zone]"
					status_label.text = "Placing: %s — %d/%d models%s" % [unit_name, placed, total, mode_info]
				else:
					# Check if AI player is deploying
					var ai_player_node = get_node_or_null("/root/AIPlayer")
					if ai_player_node and ai_player_node.is_ai_player(active_player):
						var ai_role = "Defender" if active_player == 1 else "Attacker"
						status_label.text = "AI Player %d (%s) is deploying..." % [active_player, ai_role]
					# Check if it's our turn in multiplayer
					elif get_node_or_null("/root/NetworkManager") and get_node("/root/NetworkManager").is_networked() and not get_node("/root/NetworkManager").is_local_player_turn():
						var local_player = get_node("/root/NetworkManager").get_local_player()
						status_label.text = "Waiting for Player %d to deploy... (You are Player %d)" % [active_player, local_player]
					else:
						status_label.text = "Select a unit to deploy (or place in reserves)"

		GameStateData.Phase.ROLL_OFF:
			var ai_rolloff = get_node_or_null("/root/AIPlayer")
			if ai_rolloff and ai_rolloff.is_ai_player(active_player):
				status_label.text = "AI Player %d is rolling for first turn..." % active_player
			else:
				status_label.text = "Click 'Roll for First Turn' to determine who goes first"
			phase_action_button.disabled = false

		GameStateData.Phase.MOVEMENT:
			var ai_move = get_node_or_null("/root/AIPlayer")
			if ai_move and ai_move.is_ai_player(active_player):
				status_label.text = "AI Player %d is moving..." % active_player
			elif movement_controller and movement_controller.active_unit_id != "":
				if movement_controller.active_mode != "":
					status_label.text = "Drag models to move them"
				else:
					status_label.text = "Choose movement type (Normal/Advance/etc.)"
			else:
				status_label.text = "Select a unit to move"
			phase_action_button.disabled = false

		_:
			var ai_general = get_node_or_null("/root/AIPlayer")
			if ai_general and ai_general.is_ai_player(active_player):
				status_label.text = "AI Player %d — %s" % [active_player, GameStateData.Phase.keys()[current_phase]]
			else:
				status_label.text = "Phase: " + GameStateData.Phase.keys()[current_phase]
			phase_action_button.disabled = false

# ═══════════════════════════════════════════════════════
# T5-UX11: DEPLOYMENT UNIT HOVER PREVIEW
# ═══════════════════════════════════════════════════════

func _setup_deploy_hover_tooltip() -> void:
	"""Create the tooltip panel for showing unit base info on hover in the deployment list."""
	_deploy_hover_tooltip = PanelContainer.new()
	_deploy_hover_tooltip.name = "DeployHoverTooltip"
	_deploy_hover_tooltip.visible = false
	_deploy_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deploy_hover_tooltip.z_index = UI_OVERLAY_Z

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.05, 0.95)
	style.border_color = WhiteDwarfTheme.WH_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_deploy_hover_tooltip.add_theme_stylebox_override("panel", style)

	_deploy_hover_tooltip_label = RichTextLabel.new()
	_deploy_hover_tooltip_label.name = "TooltipLabel"
	_deploy_hover_tooltip_label.bbcode_enabled = true
	_deploy_hover_tooltip_label.fit_content = true
	_deploy_hover_tooltip_label.scroll_active = false
	_deploy_hover_tooltip_label.custom_minimum_size = Vector2(220, 0)
	_deploy_hover_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deploy_hover_tooltip_label.add_theme_color_override("default_color", WhiteDwarfTheme.WH_PARCHMENT)
	_deploy_hover_tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	_deploy_hover_tooltip.add_child(_deploy_hover_tooltip_label)

	# Add to HUD_Right so it layers on top of the unit list
	var hud_right = get_node_or_null("HUD_Right")
	if hud_right:
		hud_right.add_child(_deploy_hover_tooltip)
	else:
		add_child(_deploy_hover_tooltip)

	print("[T5-UX11] Deploy hover tooltip created")

func _on_unit_list_gui_input(event: InputEvent) -> void:
	"""Detect mouse hover over deployment unit list items for base preview."""
	if not event is InputEventMouseMotion:
		return
	if current_phase != GameStateData.Phase.DEPLOYMENT:
		return
	if deployment_controller and deployment_controller.is_placing():
		_hide_deploy_hover_tooltip()
		return

	# ItemList.get_item_at_position() returns the index at given local position
	var index = unit_list.get_item_at_position(event.position, true)
	if index >= 0 and not unit_list.is_item_disabled(index):
		var unit_id = unit_list.get_item_metadata(index)
		if unit_id and unit_id is String and unit_id != "":
			if unit_id != _hovered_deploy_unit_id:
				_hovered_deploy_unit_id = unit_id
				_show_deploy_hover_tooltip(unit_id, index)
			return

	# No valid item under cursor
	if _hovered_deploy_unit_id != "":
		_hovered_deploy_unit_id = ""
		_hide_deploy_hover_tooltip()

func _on_unit_list_mouse_exited() -> void:
	"""Clear hover state when mouse leaves the unit list."""
	if _hovered_deploy_unit_id != "":
		_hovered_deploy_unit_id = ""
		_hide_deploy_hover_tooltip()

func _show_deploy_hover_tooltip(unit_id: String, item_index: int) -> void:
	"""Build and display the base preview tooltip for the hovered unit."""
	if not _deploy_hover_tooltip or not _deploy_hover_tooltip_label:
		return

	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		_hide_deploy_hover_tooltip()
		return

	var unit_name = unit_data.get("meta", {}).get("name", unit_id)
	var models = unit_data.get("models", [])
	var model_count = models.size()
	var keywords = unit_data.get("meta", {}).get("keywords", [])

	# Get base size info from the first model (representative)
	var base_info = ""
	if models.size() > 0:
		var first_model = models[0]
		var base_mm = first_model.get("base_mm", 0)
		var base_type = first_model.get("base_type", "circular")

		if base_type == "circular":
			base_info = "%dmm round" % base_mm
		elif base_type == "oval":
			var dims = first_model.get("base_dimensions", {})
			var length = dims.get("length", base_mm)
			var width = dims.get("width", base_mm)
			base_info = "%dx%dmm oval" % [length, width]
		elif base_type == "rectangular":
			var dims = first_model.get("base_dimensions", {})
			var length = dims.get("length", base_mm)
			var width = dims.get("width", base_mm)
			base_info = "%dx%dmm rectangular" % [length, width]
		else:
			base_info = "%dmm" % base_mm

	# Build tooltip BBCode text
	var bbcode = "[b][color=#D49761]%s[/color][/b]\n" % unit_name
	bbcode += "[color=#EBE1C7]Models:[/color] %d\n" % model_count
	if base_info != "":
		bbcode += "[color=#EBE1C7]Base:[/color] %s\n" % base_info

	# Special deployment rules
	var special_rules = []
	if GameState.unit_is_fortification(unit_id):
		special_rules.append("[color=#9A1115]FORTIFICATION[/color] — must deploy")
	if GameState.unit_has_deep_strike(unit_id):
		special_rules.append("[color=#6A9BD2]Deep Strike[/color] available")
	if GameState.unit_has_infiltrators(unit_id):
		special_rules.append("[color=#6AD26A]Infiltrators[/color] — deploy anywhere >9\"")
	if "CHARACTER" in keywords:
		special_rules.append("[color=#D49761]CHARACTER[/color] — can lead units")
	if unit_data.has("transport_data"):
		var capacity = unit_data.get("transport_data", {}).get("capacity", 0)
		if capacity > 0:
			special_rules.append("[color=#D49761]TRANSPORT[/color] — %d capacity" % capacity)

	if special_rules.size() > 0:
		bbcode += "\n"
		for rule in special_rules:
			bbcode += rule + "\n"

	_deploy_hover_tooltip_label.text = bbcode

	# Position tooltip to the left of the unit list
	_deploy_hover_tooltip.visible = true
	# Wait a frame for the label to resize, then position
	await get_tree().process_frame
	if _hovered_deploy_unit_id == unit_id:
		_position_deploy_hover_tooltip(item_index)

func _position_deploy_hover_tooltip(item_index: int) -> void:
	"""Position the tooltip to the left of the unit list panel."""
	if not _deploy_hover_tooltip or not _deploy_hover_tooltip.visible:
		return

	# Get the unit list's global rect
	var list_rect = unit_list.get_global_rect()
	var tooltip_size = _deploy_hover_tooltip.size

	# Position to the left of the unit list, vertically aligned with the item
	var item_rect = unit_list.get_item_rect(item_index)
	var y_pos = list_rect.position.y + item_rect.position.y
	var x_pos = list_rect.position.x - tooltip_size.x - 8

	# Clamp to screen bounds
	var viewport_size = get_viewport().get_visible_rect().size
	y_pos = clamp(y_pos, 4, viewport_size.y - tooltip_size.y - 4)
	if x_pos < 4:
		# Not enough room to the left, position below the list item instead
		x_pos = list_rect.position.x
		y_pos = list_rect.position.y + item_rect.position.y + item_rect.size.y + 4

	_deploy_hover_tooltip.global_position = Vector2(x_pos, y_pos)

func _hide_deploy_hover_tooltip() -> void:
	"""Hide the deployment hover tooltip."""
	if _deploy_hover_tooltip:
		_deploy_hover_tooltip.visible = false

# ═══════════════════════════════════════════════════════
# END T5-UX11
# ═══════════════════════════════════════════════════════

func _on_unit_selected(index: int) -> void:
	# Hide hover tooltip when a unit is selected for deployment
	_hide_deploy_hover_tooltip()
	_hovered_deploy_unit_id = ""

	if deployment_controller and deployment_controller.is_placing() and current_phase == GameStateData.Phase.DEPLOYMENT:
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
		# Reserves are declared in Formations phase — no reserves button during deployment

		# Auto-assign unit color if not yet set (letter mode)
		var existing_color = GameState.get_unit_color(unit_id)
		if existing_color == Color.TRANSPARENT:
			GameState.auto_assign_unit_color(unit_id)

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
	elif current_phase == GameStateData.Phase.SCOUT:
		# Clean up any previous active scout move before starting a new one
		if _scout_active_unit_id != "" and _scout_active_unit_id != unit_id:
			_scout_reset_previous_unit(_scout_active_unit_id)

		# Begin scout move for the selected unit
		_scout_active_unit_id = unit_id
		show_unit_card(unit_id)
		var scout_dist = GameState.get_scout_distance(unit_id)
		_scout_move_distance = scout_dist
		print("Main: Scout unit selected: ", unit_id, " (Scout %d\")" % int(scout_dist))

		# Send BEGIN_SCOUT_MOVE action
		var scout_action = {
			"type": "BEGIN_SCOUT_MOVE",
			"unit_id": unit_id,
			"player": GameState.get_active_player()
		}
		var scout_result = NetworkIntegration.route_action(scout_action)
		if scout_result.get("success", false):
			status_label.text = "Scout move: Drag models up to %d\" (must end >9\" from enemies)" % int(scout_dist)
			# Show confirm/skip buttons
			_setup_scout_unit_card_buttons(unit_id)
			# Highlight the selected unit's models on the board
			_scout_highlight_active_unit(unit_id, scout_dist)
		else:
			print("Main: BEGIN_SCOUT_MOVE failed: ", scout_result.get("errors", ["Scout move failed"]))
			status_label.text = "Error: " + str(scout_result.get("errors", ["Scout move failed"]))
			_scout_active_unit_id = ""

	elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
		# Check if this is a reserve unit arriving as reinforcement
		var selected_unit = GameState.get_unit(unit_id)
		if selected_unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
			# Skip attached characters — they arrive with their bodyguard automatically
			var attached_to = selected_unit.get("attached_to", "")
			if attached_to != "":
				var bg_name = GameState.get_unit(attached_to).get("meta", {}).get("name", attached_to)
				print("Main: Attached character selected — will arrive with bodyguard %s" % bg_name)
				var toast_mgr = get_node_or_null("/root/ToastManager")
				if toast_mgr:
					toast_mgr.show_info("This character will arrive with %s" % bg_name)
				return

			print("Main: Reserve unit selected for reinforcement: ", unit_id)
			# P2-80: If unit has Deep Strike but is in Strategic Reserves, offer choice
			var reserve_type = selected_unit.get("reserve_type", "strategic_reserves")
			if reserve_type == "strategic_reserves" and GameState.unit_has_deep_strike(unit_id):
				print("Main: P2-80 — Unit has Deep Strike from Strategic Reserves, showing placement choice dialog")
				_show_deep_strike_placement_dialog(unit_id)
			else:
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
		elif current_phase == GameStateData.Phase.SCOUT:
			# Scout unit selected from bottom panel - trigger same logic as right panel
			# Clean up any previous active scout move before starting a new one
			if _scout_active_unit_id != "" and _scout_active_unit_id != unit_id:
				_scout_reset_previous_unit(_scout_active_unit_id)
			_scout_active_unit_id = unit_id
			var scout_dist_bp = GameState.get_scout_distance(unit_id)
			_scout_move_distance = scout_dist_bp
			var scout_action_bp = {
				"type": "BEGIN_SCOUT_MOVE",
				"unit_id": unit_id,
				"player": GameState.get_active_player()
			}
			var scout_result_bp = NetworkIntegration.route_action(scout_action_bp)
			if scout_result_bp.get("success", false):
				status_label.text = "Scout move: Drag models up to %d\" (must end >9\" from enemies)" % int(scout_dist_bp)
				_setup_scout_unit_card_buttons(unit_id)
				_scout_highlight_active_unit(unit_id, scout_dist_bp)
			else:
				_scout_active_unit_id = ""
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

func _on_unit_stats_panel_visibility_changed(panel_is_visible: bool) -> void:
	# Adjust HUD_Right and HUD_Left bottom offset based on unit stats panel visibility
	var hud_right = get_node_or_null("HUD_Right")
	var hud_left = get_node_or_null("HUD_Left")
	var bottom_offset = -300.0 if panel_is_visible else 0.0

	if hud_right:
		hud_right.offset_bottom = bottom_offset
		print("Main: HUD_Right offset_bottom adjusted to ", bottom_offset, " (panel visible: ", panel_is_visible, ")")

	if hud_left:
		hud_left.offset_bottom = bottom_offset
		print("Main: HUD_Left offset_bottom adjusted to ", bottom_offset, " (panel visible: ", panel_is_visible, ")")

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
						var total = deployment_controller.get_total_model_count()

						models_label.text = "Models: %d/%d" % [placed, total]
						
						# Show buttons based on deployment progress
						undo_button.visible = placed > 0  # Per-model undo
						reset_button.visible = placed > 0  # Full-unit reset
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
		
		GameStateData.Phase.SCOUT:
			# Scout phase buttons are managed by _setup_scout_unit_card_buttons
			# Just hide default buttons here; they'll be set up when a unit is selected
			if _scout_active_unit_id == "":
				undo_button.visible = false
				reset_button.visible = false
				confirm_button.visible = false
				models_label.text = "Select a unit to begin scout move"

		GameStateData.Phase.MOVEMENT:
			# During reinforcement placement, show deployment-style buttons
			if deployment_controller and deployment_controller.is_reinforcement_mode and deployment_controller.is_placing():
				var current_unit_id = deployment_controller.get_current_unit()
				if current_unit_id and current_unit_id != "":
					var unit_data = GameState.get_unit(current_unit_id)
					if unit_data and unit_data.has("models"):
						var placed = deployment_controller.get_placed_count()
						var total = deployment_controller.get_total_model_count()
						models_label.text = "Models: %d/%d" % [placed, total]
						undo_button.visible = placed > 0
						reset_button.visible = placed > 0
						confirm_button.visible = placed == total
						unit_card.visible = true
						return
			# Default: MovementController manages its own UI
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
				# Per-model undo: remove only the last placed model
				var undone = deployment_controller.undo_last_model()
				if undone:
					update_ui()
				else:
					# Nothing left to undo — no-op (unit stays selected)
					pass
		GameStateData.Phase.MOVEMENT:
			# Route to deployment controller during reinforcement placement
			if deployment_controller and deployment_controller.is_reinforcement_mode and deployment_controller.is_placing():
				var undone = deployment_controller.undo_last_model()
				if undone:
					update_unit_card_buttons()
					update_ui()
			elif movement_controller and movement_controller.active_unit_id != "":
				print("Undo button pressed for unit: ", movement_controller.active_unit_id)
				var action = {
					"type": "UNDO_LAST_MODEL_MOVE",
					"actor_unit_id": movement_controller.active_unit_id,
					"payload": {}
				}
				_on_movement_action_requested(action)

func _on_reset_pressed() -> void:
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if deployment_controller:
				# Save unit_id before reset clears it
				var reset_unit_id = deployment_controller.unit_id
				# Full-unit reset: clears all placed models and resets placement state
				deployment_controller.reset_unit()
				# Re-select the same unit so user can immediately place again
				if reset_unit_id != "":
					deployment_controller.begin_deploy(reset_unit_id)
				update_unit_card_buttons()
				update_ui()
		GameStateData.Phase.MOVEMENT:
			# Route to deployment controller during reinforcement placement
			if deployment_controller and deployment_controller.is_reinforcement_mode and deployment_controller.is_placing():
				var reset_unit_id = deployment_controller.unit_id
				deployment_controller.reset_unit()
				if reset_unit_id != "":
					_begin_reinforcement_placement(reset_unit_id)
				update_unit_card_buttons()
				update_ui()
			elif movement_controller and movement_controller.active_unit_id != "":
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
			# Route to deployment controller during reinforcement placement
			if deployment_controller and deployment_controller.is_reinforcement_mode and deployment_controller.is_placing():
				print("Confirm button pressed for reinforcement placement")
				deployment_controller.confirm()
			elif movement_controller and movement_controller.active_unit_id != "":
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

	# P2-44: Flash border on deployment side change
	if _player_turn_border:
		_player_turn_border.flash_turn_swap(player)
		_last_active_player = player

	# T5-UX10: Auto-zoom to the new active player's deployment zone on turn switch
	print("T5-UX10: Deployment side changed to Player %d — auto-zooming" % player)
	focus_on_deployment_zone(player)

	# T5-MP6: Show toast notification when deployment turn switches in multiplayer
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked():
		var is_my_turn = network_manager.is_local_player_turn()
		if is_my_turn:
			ToastManager.show_toast("Your turn to deploy!", Color(0.2, 0.8, 0.2), 3.0)
			print("Main: Toast — your turn to deploy (Player %d)" % player)
		else:
			var opponent_role = "Defender" if player == 1 else "Attacker"
			ToastManager.show_toast("Waiting for Player %d (%s) to deploy..." % [player, opponent_role], _WhiteDwarfTheme.WH_GOLD, 3.0)
			print("Main: Toast — waiting for opponent (Player %d) to deploy" % player)

func _on_deployment_complete() -> void:
	status_label.text = "Deployment complete!"
	phase_action_button.disabled = false
	# P2-40: Hide deployment log panel when deployment is done
	_hide_deployment_log_panel()

# ========================================
# P2-40: Opponent Deployment Notifications
# ========================================

func _on_phase_action_for_deployment_log(result: Dictionary) -> void:
	"""P2-40: Handle deployment actions via GameManager.result_applied — show camera pan, toast, and log entry"""
	var action_type = result.get("action_type", "")

	# Only care about deployment-related actions
	if action_type != "DEPLOY_UNIT":
		return

	# Only during deployment phase
	if current_phase != GameStateData.Phase.DEPLOYMENT:
		return

	var action_data = result.get("action_data", {})
	var unit_id = action_data.get("unit_id", "")
	var player = action_data.get("player", 0)
	if unit_id == "" or player == 0:
		return

	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Get the unit's deployed position (first alive model)
	var deploy_pos: Vector2 = Vector2.ZERO
	var has_pos = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			var pos = model.get("position", null)
			if pos != null:
				if pos is Dictionary:
					deploy_pos = Vector2(pos.get("x", 0), pos.get("y", 0))
				elif pos is Vector2:
					deploy_pos = pos
				has_pos = true
				break

	# Always add to deployment log (both local and remote deployments)
	_add_deployment_log_entry(player, unit_name, deploy_pos)

	# Check if this is the opponent's deployment (not local player's)
	var network_manager = get_node_or_null("/root/NetworkManager")
	var is_opponent_deploy = false
	if network_manager and network_manager.is_networked():
		var local_player = network_manager.get_local_player()
		is_opponent_deploy = (player != local_player)
	else:
		# Single player vs AI: check if AI deployed
		var ai_player = get_node_or_null("/root/AIPlayer")
		if ai_player and ai_player.is_ai_player(player):
			is_opponent_deploy = true

	if is_opponent_deploy:
		# Show toast notification
		ToastManager.show_toast("%s deployed" % unit_name, Color(0.9, 0.7, 0.2), 3.0)
		print("P2-40: Opponent deployed %s (Player %d)" % [unit_name, player])

		# Pan camera briefly to show where the unit was placed
		if has_pos:
			focus_on_position_briefly(deploy_pos, 1.5, 0.5)

func _add_deployment_log_entry(player: int, unit_name: String, position: Vector2) -> void:
	"""P2-40: Add an entry to the deployment log panel"""
	_deployment_log_entries.append({
		"player": player,
		"unit_name": unit_name,
		"position": position
	})
	print("P2-40: Deployment log entry added — P%d: %s at %s (total: %d)" % [player, unit_name, position, _deployment_log_entries.size()])

	# Ensure the deployment log panel exists and is visible
	if not _deployment_log_panel:
		_create_deployment_log_panel()
	_deployment_log_panel.visible = true
	_update_deployment_log_display()

func _create_deployment_log_panel() -> void:
	"""P2-40: Create the deployment log panel UI"""
	_deployment_log_panel = PanelContainer.new()
	_deployment_log_panel.name = "DeploymentLogPanel"

	# Style: dark semi-transparent panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.85)
	style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	style.border_width_bottom = 1
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_deployment_log_panel.add_theme_stylebox_override("panel", style)

	# Position: bottom-left corner, above the bottom HUD
	_deployment_log_panel.anchor_left = 0.0
	_deployment_log_panel.anchor_right = 0.0
	_deployment_log_panel.anchor_top = 1.0
	_deployment_log_panel.anchor_bottom = 1.0
	_deployment_log_panel.offset_left = 10
	_deployment_log_panel.offset_right = 300
	_deployment_log_panel.offset_top = -280
	_deployment_log_panel.offset_bottom = -50

	# VBox for header + scroll content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Header label
	var header = Label.new()
	header.text = "Deployment Log"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# Scrollable log content
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_deployment_log_label = RichTextLabel.new()
	_deployment_log_label.bbcode_enabled = true
	_deployment_log_label.fit_content = true
	_deployment_log_label.scroll_active = false
	_deployment_log_label.add_theme_font_size_override("normal_font_size", 12)
	_deployment_log_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	_deployment_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_deployment_log_label)

	vbox.add_child(scroll)
	_deployment_log_panel.add_child(vbox)

	# Don't intercept mouse events on the panel (allow clicking through)
	_deployment_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deployment_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(_deployment_log_panel)
	print("P2-40: Deployment log panel created")

func _update_deployment_log_display() -> void:
	"""P2-40: Refresh the deployment log panel content"""
	if not _deployment_log_label:
		return

	var bbcode = ""
	for i in range(_deployment_log_entries.size()):
		var entry = _deployment_log_entries[i]
		var player = entry.player
		var unit_name = entry.unit_name
		var color_hex = "4488ff" if player == 1 else "ff6644"
		var player_label = "P%d" % player
		bbcode += "[color=#888888]%d.[/color] [color=#%s]%s[/color]: %s\n" % [i + 1, color_hex, player_label, unit_name]

	_deployment_log_label.text = bbcode

func _hide_deployment_log_panel() -> void:
	"""P2-40: Hide the deployment log panel (called when deployment ends)"""
	if _deployment_log_panel:
		_deployment_log_panel.visible = false
		print("P2-40: Deployment log panel hidden")

# ========================================
# Formations Phase UI
# ========================================

var formations_dialog: Node = null

func _setup_formations_phase() -> void:
	"""Set up the Formations phase — show the declaration dialog for the local player."""
	print("Main: Setting up Formations phase")
	var is_multiplayer = NetworkIntegration.is_multiplayer_active()
	if is_multiplayer:
		# In multiplayer, each client shows their own player's dialog
		var local_player = NetworkManager.get_local_player()
		print("Main: Multiplayer mode — showing formations dialog for local player %d" % local_player)
		_show_formations_dialog(local_player)
	else:
		# Single player / hotseat — show for active player (starts with player 1)
		var active_player = GameState.get_active_player()
		_show_formations_dialog(active_player)

func _show_formations_dialog(player: int) -> void:
	"""Show the formations declaration dialog for a player."""
	# Clean up any existing dialog
	if formations_dialog and is_instance_valid(formations_dialog):
		formations_dialog.queue_free()
		formations_dialog = null

	var dialog_script = preload("res://scripts/FormationsDeclarationDialog.gd")
	formations_dialog = AcceptDialog.new()
	formations_dialog.set_script(dialog_script)
	add_child(formations_dialog)
	formations_dialog.z_index = UI_MODAL_Z
	formations_dialog.setup(player)
	formations_dialog.formations_confirmed.connect(_on_formations_dialog_confirmed)
	formations_dialog.popup_centered()
	print("Main: Showed formations dialog for Player %d" % player)

func _on_formations_dialog_confirmed(player: int, formations: Dictionary) -> void:
	"""Handle formations dialog confirmation — apply declarations through the network-aware action system."""
	print("Main: Player %d confirmed formations: %s" % [player, str(formations)])

	# Guard: bail out if we're no longer in the formations phase (e.g., AI already completed it)
	if current_phase != GameStateData.Phase.FORMATIONS:
		print("Main: Phase is no longer FORMATIONS (now %s) — ignoring stale dialog confirmation" % GameStateData.Phase.keys()[current_phase])
		return

	# Submit leader attachments
	var leader_attachments = formations.get("leader_attachments", {})
	print("Main: Submitting %d leader attachment(s) for Player %d: %s" % [leader_attachments.size(), player, str(leader_attachments)])
	for char_id in leader_attachments:
		var bg_id = leader_attachments[char_id]
		var result = NetworkIntegration.route_action({
			"type": "DECLARE_LEADER_ATTACHMENT",
			"character_id": char_id,
			"bodyguard_id": bg_id,
			"player": player
		})
		if result is Dictionary and not result.get("success", false) and not result.get("pending", false):
			push_error("Main: DECLARE_LEADER_ATTACHMENT failed for %s -> %s: %s" % [char_id, bg_id, str(result)])
		else:
			print("Main: DECLARE_LEADER_ATTACHMENT succeeded for %s -> %s" % [char_id, bg_id])

	# Submit transport embarkations
	for transport_id in formations.get("transport_embarkations", {}):
		var unit_ids = formations["transport_embarkations"][transport_id]
		if unit_ids.size() > 0:
			NetworkIntegration.route_action({
				"type": "DECLARE_TRANSPORT_EMBARKATION",
				"transport_id": transport_id,
				"unit_ids": unit_ids,
				"player": player
			})

	# Submit reserves declarations
	for entry in formations.get("reserves", []):
		var reserve_action = {
			"type": "DECLARE_RESERVES",
			"unit_id": entry["unit_id"],
			"reserve_type": entry["reserve_type"],
			"player": player
		}
		var attached_chars = entry.get("attached_character_ids", [])
		if attached_chars.size() > 0:
			reserve_action["attached_character_ids"] = attached_chars
		NetworkIntegration.route_action(reserve_action)

	# Confirm this player's formations
	var confirm_result = NetworkIntegration.route_action({
		"type": "CONFIRM_FORMATIONS",
		"player": player
	})

	# If the confirm action failed (e.g., phase already changed), stop here
	if not confirm_result.get("success", false) and not confirm_result.get("pending", false):
		print("Main: CONFIRM_FORMATIONS failed for player %d — not showing next dialog" % player)
		return

	var is_multiplayer = NetworkIntegration.is_multiplayer_active()
	if is_multiplayer:
		# In multiplayer, each player confirms on their own client.
		# The phase will auto-complete when both players have confirmed.
		print("Main: Player %d confirmed formations (multiplayer) — waiting for other player" % player)
	else:
		# Single player / hotseat — show dialog for the other player
		var other_player = 3 - player

		# If the other player is AI, let the AI handle its own formations
		var ai_player_node = get_node_or_null("/root/AIPlayer")
		if ai_player_node and ai_player_node.is_ai_player(other_player):
			print("Main: Player %d is AI — AI will handle its own formations" % other_player)
			return

		# Check phase is still FORMATIONS after action processing (phase may have auto-completed)
		if current_phase != GameStateData.Phase.FORMATIONS:
			print("Main: Phase changed to %s after confirmation — not showing next dialog" % GameStateData.Phase.keys()[current_phase])
			return

		var phase_instance = PhaseManager.get_current_phase_instance()
		if phase_instance and phase_instance.has_method("_is_player_confirmed") and not phase_instance._is_player_confirmed(other_player):
			print("Main: Showing formations dialog for Player %d" % other_player)
			_show_formations_dialog(other_player)
		else:
			print("Main: Both players confirmed formations — phase completing")

func _on_formations_confirm_pressed() -> void:
	"""Handle the phase action button press during formations phase."""
	print("Main: Formations confirm button pressed")

	# Guard: bail out if we're no longer in the formations phase
	if current_phase != GameStateData.Phase.FORMATIONS:
		print("Main: Phase is no longer FORMATIONS — ignoring confirm press")
		return

	# Determine which player to confirm for
	var is_multiplayer = NetworkIntegration.is_multiplayer_active()
	var confirming_player: int
	if is_multiplayer:
		confirming_player = NetworkManager.get_local_player()
	else:
		confirming_player = GameState.get_active_player()

	# Submit confirm through the network-aware action system
	var confirm_result = NetworkIntegration.route_action({
		"type": "CONFIRM_FORMATIONS",
		"player": confirming_player
	})

	# If the confirm action failed, stop here
	if not confirm_result.get("success", false) and not confirm_result.get("pending", false):
		print("Main: CONFIRM_FORMATIONS failed for player %d — not showing next dialog" % confirming_player)
		return

	if not is_multiplayer:
		# Single player / hotseat — show dialog for the other player if needed
		var other_player = 3 - confirming_player

		# If the other player is AI, let the AI handle its own formations
		var ai_player_node = get_node_or_null("/root/AIPlayer")
		if ai_player_node and ai_player_node.is_ai_player(other_player):
			print("Main: Player %d is AI — AI will handle its own formations" % other_player)
			return

		# Check phase is still FORMATIONS after action processing
		if current_phase != GameStateData.Phase.FORMATIONS:
			print("Main: Phase changed after confirmation — not showing next dialog")
			return

		var phase_instance = PhaseManager.get_current_phase_instance()
		if phase_instance and phase_instance.has_method("_is_player_confirmed") and not phase_instance._is_player_confirmed(other_player):
			_show_formations_dialog(other_player)

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
			# T5-UX8: Show deployment summary dialog before ending phase
			var deploy_phase_instance = PhaseManager.get_current_phase_instance()
			if deploy_phase_instance and deploy_phase_instance.has_method("get_deployment_summary"):
				var summary = deploy_phase_instance.get_deployment_summary()
				print("Main: T5-UX8: Showing deployment summary dialog")
				_show_deployment_summary_dialog(summary, active_player)
				return
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

# SAVE-16: Save to a numbered slot
func _perform_slot_save(slot: int) -> void:
	print("========================================")
	print("SAVE TO SLOT %d TRIGGERED" % slot)
	print("========================================")
	_show_save_notification("Saving to slot %d..." % slot, Color.YELLOW)
	var metadata = {"type": "slot", "slot_number": slot}
	var success = SaveLoadManager.save_game_to_slot(slot, metadata)
	if success:
		_show_save_notification("Saved to slot %d!" % slot, Color.GREEN)
	else:
		_show_save_notification("Save to slot %d failed!" % slot, Color.RED)

# SAVE-16: Load from a numbered slot
func _perform_slot_load(slot: int) -> void:
	print("========================================")
	print("LOAD FROM SLOT %d TRIGGERED" % slot)
	print("========================================")

	# Check if we're in multiplayer as a client
	if NetworkManager and NetworkManager.is_networked() and not NetworkManager.is_host():
		_show_save_notification("Only host can load games in multiplayer", Color.RED)
		push_warning("Main: Client attempted to load slot during multiplayer - blocked")
		return

	if not SaveLoadManager.slot_has_save(slot):
		_show_save_notification("Slot %d is empty!" % slot, Color.RED)
		return

	_show_save_notification("Loading slot %d..." % slot, Color.YELLOW)

	var success = SaveLoadManager.load_game_from_slot(slot)
	if success:
		_show_save_notification("Loaded slot %d!" % slot, Color.BLUE)

		# Same post-load logic as quick load
		_clear_right_panel_phase_ui()
		current_phase = GameState.get_current_phase()
		print("Loaded phase from slot %d: %s" % [slot, GameStateData.Phase.keys()[current_phase]])
		_sync_board_state_with_game_state()
		_initialize_ai_player()
		if PhaseManager.has_method("transition_to_phase"):
			PhaseManager.transition_to_phase(current_phase)
		await get_tree().process_frame
		await setup_phase_controllers()
		await get_tree().process_frame
		refresh_unit_list()
		update_ui()
		update_ui_for_phase()
		update_deployment_zone_visibility()
		_recreate_unit_visuals()
		print("Main: Slot %d load complete" % slot)
	else:
		_show_save_notification("Load from slot %d failed!" % slot, Color.RED)

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

		# Re-initialize AI player from loaded game_config
		_initialize_ai_player()

		# SAVE/LOAD FIX: Transition PhaseManager FIRST so phase instance is correct,
		# then set up controllers that reference the correct instance
		if PhaseManager.has_method("transition_to_phase"):
			PhaseManager.transition_to_phase(current_phase)

		# Wait one frame for phase transition to complete
		await get_tree().process_frame

		# Recreate phase controllers for the loaded phase (now references correct phase instance)
		await setup_phase_controllers()

		# Wait one frame for controllers to initialize
		await get_tree().process_frame

		# Refresh all UI elements
		refresh_unit_list()
		update_ui()
		update_ui_for_phase()
		update_deployment_zone_visibility()

		# Recreate visual tokens for deployed units
		_recreate_unit_visuals()
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

			# P1-67: Also sync token position from GameState (not just visibility)
			var model_pos = model.get("position")
			if model_pos != null:
				var target_pos: Vector2
				if model_pos is Dictionary:
					target_pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))
				else:
					target_pos = model_pos
				if token.position.distance_to(target_pos) > 1.0:
					print("  - P1-67: Syncing token position from (%.1f, %.1f) to (%.1f, %.1f)" % [token.position.x, token.position.y, target_pos.x, target_pos.y])
					token.position = target_pos

			# Also sync rotation from GameState
			var model_rotation = model.get("rotation", 0.0)
			if "model_data" in token and token.model_data is Dictionary:
				var current_rotation = token.model_data.get("rotation", 0.0)
				if abs(current_rotation - model_rotation) > 0.001:
					print("  - Syncing token rotation from %.3f to %.3f" % [current_rotation, model_rotation])
					token.model_data["rotation"] = model_rotation
					token.queue_redraw()

			if model_alive:
				# Model is alive → ensure visible
				token.visible = true
				print("  - ✅ Model alive → token.visible = true")
			else:
				# T5-V4: Fade-out death animation instead of instant hide
				if token.visible:
					_animate_token_death(token, unit_id, model_id)
				else:
					token.visible = false
				tokens_hidden += 1
				print("╔══════════════════════════════════════════════════════════════════")
				print("║ ✅ 💀 MODEL TOKEN HIDDEN")
				print("║ Unit: ", unit_id)
				print("║ Model: ", model_id)
				print("║ Token path: ", token.get_path())
				print("║ Token visible: false (with fade animation)")
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

func _animate_token_death(token: Node2D, unit_id: String, model_id: String) -> void:
	"""T5-V4: Animate token death — flash white then fade to invisible."""
	print("Main: T5-V4 death fade animation for %s:%s" % [unit_id, model_id])
	# Trigger death animation on TokenVisual if available
	_trigger_token_animation(token, "death")
	var death_tween = token.create_tween()
	# Flash white briefly
	death_tween.tween_property(token, "modulate", Color(2.0, 1.5, 1.5, 1.0), 0.1)
	# Fade out to transparent
	death_tween.tween_property(token, "modulate", Color(0.5, 0.1, 0.1, 0.0), 0.4).set_ease(Tween.EASE_IN)
	# Hide and reset modulate after fade completes
	death_tween.tween_callback(func():
		token.visible = false
		token.modulate = Color.WHITE
	)


func _trigger_token_animation(token: Node2D, anim_name: String) -> void:
	"""Trigger an animation on a token node. Handles both direct TokenVisual
	   nodes and container nodes with TokenVisual children."""
	if token.has_method("play_animation"):
		token.play_animation(anim_name)
	else:
		for child in token.get_children():
			if child.has_method("play_animation"):
				child.play_animation(anim_name)


func trigger_unit_animation(unit_id: String, anim_name: String) -> void:
	"""Trigger an animation on all token visuals belonging to a unit.
	   Can be called from game controllers to animate models."""
	var tl = get_node_or_null("BoardRoot/TokenLayer")
	if not tl:
		return
	for child in tl.get_children():
		if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id:
			_trigger_token_animation(child, anim_name)
		else:
			for grandchild in child.get_children():
				if grandchild.has_meta("unit_id") and grandchild.get_meta("unit_id") == unit_id:
					_trigger_token_animation(grandchild, anim_name)


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

func _on_autosave_completed(file_path: String) -> void:
	print("SAVE-10: Autosave completed: %s" % file_path)
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_toast("Game autosaved", Color(0.5, 0.8, 1.0), 1.5)
	else:
		_show_save_notification("Autosaved", Color(0.5, 0.8, 1.0))

func _on_save_completed(file_path: String, metadata: Dictionary) -> void:
	print("Save completed: %s" % file_path)
	# SAVE-20: Dismiss progress indicator on save completion
	_dismiss_save_load_progress()
	if OS.has_feature("web"):
		_show_save_notification("Game saved!", Color.GREEN)

func _on_load_completed(file_path: String, metadata: Dictionary) -> void:
	print("Load completed: %s" % file_path)

	# SAVE-20: Dismiss progress indicator on load completion
	_dismiss_save_load_progress()

	# P2-12: Show fade overlay during mid-game load to hide visual reconstruction
	_show_game_loaded_overlay()

	# Clear debug visualizations after load
	_clear_debug_visualizations()

	if OS.has_feature("web"):
		_show_save_notification("Game loaded!", Color.BLUE)

	# Unified load path: use _apply_loaded_state for both web and desktop.
	# On desktop, the load_completed signal fires synchronously inside load_game(),
	# so _on_load_requested would also call _apply_loaded_state — causing double
	# execution and a freeze. Now only this signal handler triggers state restoration.
	call_deferred("_apply_loaded_state")

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
	# SAVE-20: Dismiss progress indicator on failure
	_dismiss_save_load_progress()
	if OS.has_feature("web"):
		_show_save_notification("Save failed: " + error, Color.RED)

func _on_load_failed(error: String) -> void:
	print("Load failed: %s" % error)
	# SAVE-20: Dismiss progress indicator on failure
	_dismiss_save_load_progress()
	# Dismiss game loaded overlay if it was shown (prevents permanent input freeze)
	_dismiss_game_loaded_overlay()
	_show_save_notification("Load failed: " + error, Color.RED)

# SAVE-20: Signal handlers for save/load progress indicator
func _on_save_started(file_path: String) -> void:
	print("Main: SAVE-20 Save started: %s" % file_path)
	_show_save_load_progress("Saving")

func _on_load_started(file_path: String) -> void:
	print("Main: SAVE-20 Load started: %s" % file_path)
	_show_save_load_progress("Loading")

func _on_save_load_progress(stage: String, detail: String) -> void:
	_update_save_load_progress(detail)

func _on_delete_completed_main(save_name: String) -> void:
	print("Main: Cloud delete completed: ", save_name)
	_show_save_notification("Save deleted!", Color.ORANGE)

func _apply_loaded_state() -> void:
	# SAVE-4: Web platform load path — delegates to _refresh_after_load() for full restore.
	# Both desktop and web paths now use the same comprehensive restore logic.
	print("Main: _apply_loaded_state() called (delegating to _refresh_after_load)")
	await _refresh_after_load()

# Multiplayer sync handler - called when guest receives initial state or game starts
func _on_network_game_started() -> void:
	print("Main: Network game started signal received")

	# P3-56: Dismiss the web relay loading overlay now that host state is received
	_dismiss_web_relay_loading_overlay()

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

func _on_score_changed(_player: int, _points: int, _reason: String) -> void:
	_update_score_display()

func _on_secondary_score_changed(_player: int, _vp: int, _mission_id: String) -> void:
	_update_score_display()

# P3-120: Update CP display immediately when a stratagem is used
func _on_stratagem_used_update_display(_player: int, _stratagem_id: String, _target_unit_id: String) -> void:
	_update_score_display()

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

	# Check if active_player changed — refresh waiting overlay so it reflects the new state
	for diff in diffs:
		if diff.get("op") == "set" and diff.get("path") == "meta.active_player":
			print("Main: Active player changed via network to: ", diff.get("value"))
			_update_waiting_for_opponent_overlay()
			break

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

	# P3-101: In multiplayer, pile-in/consolidation movements are animated by
	# _animate_fight_movement_tokens in NetworkManager. Recreating visuals immediately
	# would teleport tokens to final positions, overriding the smooth tween animation.
	# Only skip for remote player actions (the local player's tokens are already correct).
	var is_animated_action = false
	if action_type in ["PILE_IN", "CONSOLIDATE"]:
		var nm = get_node_or_null("/root/NetworkManager")
		if nm and nm.is_networked():
			var action_player = result.get("action_data", {}).get("player", -1)
			var local_player = nm.get_local_player()
			if action_player != local_player:
				is_animated_action = true
				print("Main: P3-101: Skipping visual recreation for remote %s — animation handles it" % action_type)

	# Only recreate visuals if state actually changed in GameState
	if not is_staging_action and not is_animated_action and diffs.size() > 0:
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
	# Clean up network state so next game doesn't think it's still networked
	if NetworkManager.is_networked():
		print("Main: Disconnecting network before returning to menu")
		NetworkManager.disconnect_network()
	# Reset PhaseManager state so it doesn't carry stale phase instances into the next game
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if phase_manager:
		phase_manager.reset()
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

	# SAVE-1: Cancel any active AI thinking before load to prevent stale actions
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.has_method("cancel_ai_before_load"):
		ai_player.cancel_ai_before_load()

	# Show loading notification
	_show_save_notification("Loading...", Color.YELLOW)

	# Perform load — result comes via load_completed/load_failed signals for both
	# web (async) and desktop (synchronous, signal fires inside load_game).
	# State restoration is handled entirely by _on_load_completed → _apply_loaded_state.
	var success = SaveLoadManager.load_game(save_file, owner_id)
	if not OS.has_feature("web") and not success:
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
	# SAVE-4: Completely refresh all game state, visuals, and systems after loading a save.
	# This must fully restore the game to the loaded state without any stale data.
	print("Main: _refresh_after_load() called")

	# --- Step 1: Clear transient state from previous session ---
	print("Main: SAVE-4 Step 1 — Clearing transient state")
	_selected_unit_for_reserves = ""
	_reinforcement_placement_type = ""

	# --- Step 2: Clear stale visual elements ---
	print("Main: SAVE-4 Step 2 — Clearing stale visuals")

	# Clear ghost layer (movement preview ghosts from previous state)
	if ghost_layer:
		for child in ghost_layer.get_children():
			child.queue_free()
		print("Main: Cleared ghost layer")

	# Clear AI unit highlight rings
	_clear_ai_unit_highlights()

	# Hide AI thinking indicator (AI state is reset by _reinitialize_ai_after_load)
	_hide_ai_thinking_indicator()

	# Hide waiting overlay (stale multiplayer/AI waiting state)
	_hide_waiting_overlay()

	# Clear any active deployment placement
	if deployment_controller and deployment_controller.is_placing():
		deployment_controller.undo()

	# --- Step 3: Clear stale system caches and logs ---
	print("Main: SAVE-4 Step 3 — Clearing dependent system caches")

	# Clear stale game event log (entries from pre-load game are irrelevant)
	if GameEventLog:
		GameEventLog.clear()
		print("Main: Cleared GameEventLog")

	# Clear dice history (rolls from pre-load game are irrelevant)
	if DiceHistoryPanel:
		DiceHistoryPanel.clear()
		print("Main: Cleared DiceHistoryPanel")

	# Clear LoS cache (cached line-of-sight calculations are invalid after load)
	if EnhancedLineOfSight and EnhancedLineOfSight.has_method("clear_cache"):
		EnhancedLineOfSight.clear_cache()
		print("Main: Cleared EnhancedLineOfSight cache")

	# Clear measuring tape visuals (measurements from pre-load are stale)
	if MeasuringTapeManager and MeasuringTapeManager.has_method("clear_all_measurements"):
		MeasuringTapeManager.clear_all_measurements()
		print("Main: Cleared MeasuringTapeManager measurements")

	# Clear right panel phase UI before rebuilding
	_clear_right_panel_phase_ui()

	# --- Step 4: Sync core state ---
	print("Main: SAVE-4 Step 4 — Syncing core state")

	# Get the current phase from loaded GameState
	current_phase = GameState.get_current_phase()
	print("Main: Loaded phase is: ", current_phase)

	# Sync BoardState with loaded GameState (critical for legacy visual components)
	_sync_board_state_with_game_state()

	# --- Step 5: Re-initialize AI player ---
	print("Main: SAVE-4 Step 5 — Re-initializing AI")

	# SAVE-1: Re-initialize AI player from loaded game_config using dedicated load path
	# This cancels thinking, resets runtime state, and reconfigures without triggering
	# immediate evaluation (evaluation is deferred until phase controllers are ready)
	_reinitialize_ai_after_load()

	# --- Step 6: Transition phase and recreate controllers ---
	print("Main: SAVE-4 Step 6 — Transitioning phase and recreating controllers")

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

	# --- Step 7: Refresh all UI elements ---
	print("Main: SAVE-4 Step 7 — Refreshing UI elements")

	refresh_unit_list()
	update_ui()
	update_deployment_zone_visibility()

	# Update score display and round indicator for loaded state
	_update_score_display()
	_update_round_indicator()

	# --- Step 8: Recreate unit visuals ---
	print("Main: SAVE-4 Step 8 — Recreating unit visuals")

	# _recreate_unit_visuals() clears existing tokens before recreating them
	_recreate_unit_visuals()
	print("Main: Unit visuals recreated")

	# Update phase-specific UI (after visuals are ready)
	update_ui_for_phase()

	# --- Step 9: Trigger AI evaluation ---
	print("Main: SAVE-4 Step 9 — Triggering AI evaluation")

	# SAVE-1: Now that phase controllers and visuals are ready, trigger AI evaluation
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.has_method("request_evaluation_after_load"):
		ai_player.request_evaluation_after_load()

	# P2-12: Dismiss the fade overlay now that everything is restored
	_dismiss_game_loaded_overlay()

	print("Main: _refresh_after_load() complete — all state fully restored")

func update_deployment_zone_visibility() -> void:
	# P3-52: Show the active player's zone brightly and dim/desaturate the opponent's zone
	var active_player = GameState.get_active_player()
	print("Main: update_deployment_zone_visibility — active_player=%d" % active_player)

	# Active zone colors: saturated and bright
	# Inactive zone colors: desaturated (shifted toward gray) and dimmed
	var p1_active_color = Color(0, 0.1, 1, 0.65)      # Bright saturated blue
	var p1_dimmed_color = Color(0.25, 0.25, 0.45, 0.2) # Desaturated grayish-blue, low alpha
	var p2_active_color = Color(1, 0.1, 0, 0.65)       # Bright saturated red
	var p2_dimmed_color = Color(0.45, 0.25, 0.25, 0.2) # Desaturated grayish-red, low alpha

	var p1_active_border = Color(0, 0.3, 1, 1)         # Bright blue border
	var p1_dimmed_border = Color(0.35, 0.35, 0.5, 0.4) # Desaturated dim blue border
	var p2_active_border = Color(1, 0.3, 0, 1)         # Bright red border
	var p2_dimmed_border = Color(0.5, 0.35, 0.35, 0.4) # Desaturated dim red border

	if active_player == 1:
		p1_zone.modulate = p1_active_color
		p2_zone.modulate = p2_dimmed_color
	else:
		p1_zone.modulate = p1_dimmed_color
		p2_zone.modulate = p2_active_color

	p1_zone.visible = true
	p2_zone.visible = true

	# Set active/dimmed state on zone visuals for border and detail rendering
	if p1_zone.has_method("set_active"):
		p1_zone.set_active(true)  # Both zones stay active for border rendering
		p1_zone.border_color = p1_active_border if active_player == 1 else p1_dimmed_border
		p1_zone.is_dimmed = (active_player != 1)
	if p2_zone.has_method("set_active"):
		p2_zone.set_active(true)  # Both zones stay active for border rendering
		p2_zone.border_color = p2_active_border if active_player == 2 else p2_dimmed_border
		p2_zone.is_dimmed = (active_player != 2)

func _toggle_deployment_zones() -> void:
	# During deployment phase, zones are always visible - no toggling needed
	if current_phase == GameStateData.Phase.DEPLOYMENT:
		print("Main: Deployment zones are always visible during deployment phase")
		return

	_deployment_zones_toggled_on = not _deployment_zones_toggled_on
	print("Main: Deployment zones toggled %s" % ("ON" if _deployment_zones_toggled_on else "OFF"))

	if _deployment_zones_toggled_on:
		# Show both zones with semi-transparent coloring (no dimming outside deployment)
		p1_zone.modulate = Color(0, 0, 1, 0.3)
		p2_zone.modulate = Color(1, 0, 0, 0.3)
		p1_zone.visible = true
		p2_zone.visible = true
		if p1_zone.has_method("set_active"):
			p1_zone.set_active(true)
			p1_zone.border_color = Color(0, 0.3, 1, 1)
			p1_zone.is_dimmed = false
		if p2_zone.has_method("set_active"):
			p2_zone.set_active(true)
			p2_zone.border_color = Color(1, 0.3, 0, 1)
			p2_zone.is_dimmed = false
		ToastManager.show_toast("Deployment zones shown (Z to hide)", Color(0.6, 0.6, 0.8), 2.0)
	else:
		p1_zone.visible = false
		p2_zone.visible = false
		if p1_zone.has_method("set_active"):
			p1_zone.set_active(false)
		if p2_zone.has_method("set_active"):
			p2_zone.set_active(false)
		ToastManager.show_toast("Deployment zones hidden (Z to show)", Color(0.6, 0.6, 0.8), 2.0)

# Phase management handlers
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	# Stop processing phase changes if the game has ended
	if PhaseManager.game_ended:
		return

	current_phase = new_phase
	print("Phase changed to: ", GameStateData.Phase.keys()[new_phase])
	print("Active player: ", GameState.get_active_player())

	# P1-67: Sync all token positions from GameState on phase transitions
	# This ensures token visuals match GameState when entering shooting/fight phases
	_sync_all_token_positions()

	# Hide deployment hover tooltip on phase change (T5-UX11)
	_hide_deploy_hover_tooltip()
	_hovered_deploy_unit_id = ""

	# P3-54: Hide keyboard shortcut overlay when leaving deployment
	if _keyboard_shortcut_overlay and is_instance_valid(_keyboard_shortcut_overlay):
		_keyboard_shortcut_overlay.visible = false

	# Hide deep strike exclusion bubbles on phase change
	_hide_deep_strike_exclusion()

	# Clear transport panel when phase changes
	update_transport_panel("")

	# Clean up scout UI state when leaving the scout phase
	if _scout_active_unit_id != "":
		_scout_cleanup_after_move()

	await setup_phase_controllers()

	# Re-check after await — game may have ended while we were waiting
	if PhaseManager.game_ended:
		return

	update_ui_for_phase()

	# T5-V3: Show phase transition animation banner
	if phase_transition_banner:
		var banner_round = GameState.state.get("meta", {}).get("round", 1)
		var banner_player = GameState.get_active_player()
		phase_transition_banner.show_phase_banner(new_phase, banner_round, banner_player)

	# P2-44: Update player turn border color, flash on turn swap
	if _player_turn_border:
		var border_player = GameState.get_active_player()
		if _last_active_player != border_player:
			_player_turn_border.flash_turn_swap(border_player)
			_last_active_player = border_player
		else:
			_player_turn_border.set_active_player(border_player)

	# T7-54: Add phase header to AI action log overlay when AI is active
	if _ai_action_log_overlay:
		var ai_player = get_node_or_null("/root/AIPlayer")
		var active_player_for_log = GameState.get_active_player()
		if ai_player and ai_player.is_ai_player(active_player_for_log):
			var phase_label = _get_phase_label_text(new_phase).replace(" Phase", "")
			var round_num = GameState.state.get("meta", {}).get("round", 1)
			_ai_action_log_overlay.add_phase_header(phase_label, round_num, active_player_for_log)

	# T5-UX10: Auto-zoom to active player's deployment zone when entering deployment phase
	if current_phase == GameStateData.Phase.DEPLOYMENT:
		var active_player = GameState.get_active_player()
		print("T5-UX10: Deployment phase entered — auto-zooming to Player %d zone" % active_player)
		focus_on_deployment_zone(active_player)

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

	# Stop replay recording when game ends
	if PhaseManager.game_ended and ReplayManager and ReplayManager.is_recording:
		print("Main: Game ended, stopping replay recording")
		ReplayManager.stop_recording()

	# Show game over UI when game ends after 5 rounds
	if PhaseManager.game_ended and phase == GameStateData.Phase.SCORING:
		# Determine winner by VP
		var winner = _determine_vp_winner()
		_show_game_over_dialog(winner, "rounds_complete")

func _on_network_game_over(winner: int, reason: String) -> void:
	print("Main: Network game over - Winner: Player %d, Reason: %s" % [winner, reason])
	_show_game_over_dialog(winner, reason)

func _show_game_over_dialog(winner: int, reason: String) -> void:
	# Clean up any existing dialog
	if game_over_dialog and is_instance_valid(game_over_dialog):
		game_over_dialog.queue_free()
		game_over_dialog = null

	var dialog_script = preload("res://scripts/GameOverDialog.gd")
	game_over_dialog = AcceptDialog.new()
	game_over_dialog.set_script(dialog_script)
	add_child(game_over_dialog)
	game_over_dialog.z_index = UI_MODAL_Z

	# Determine local player number for networked games
	var local_player_num = 0
	if NetworkManager and NetworkManager.is_networked():
		local_player_num = NetworkManager.get_local_player()

	game_over_dialog.setup(winner, reason, local_player_num)
	game_over_dialog.return_to_menu_requested.connect(_on_game_over_return_to_menu)
	game_over_dialog.popup_centered()
	print("Main: Showed game over dialog - Winner: Player %d, Reason: %s" % [winner, reason])

func _determine_vp_winner() -> int:
	if not MissionManager:
		return 0
	var vp_summary = MissionManager.get_vp_summary()
	var p1_total = vp_summary["player1"]["total"]
	var p2_total = vp_summary["player2"]["total"]
	if p1_total > p2_total:
		return 1
	elif p2_total > p1_total:
		return 2
	else:
		return 0  # Draw

func _on_game_over_return_to_menu() -> void:
	print("Main: Returning to main menu from game over")
	# Clean up network state so next game doesn't think it's still networked
	if NetworkManager.is_networked():
		print("Main: Disconnecting network before returning to menu from game over")
		NetworkManager.disconnect_network()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
# P2-41: GRACEFUL DISCONNECT HANDLING
# ============================================================================

func _on_peer_disconnect_grace_period(disconnected_player: int) -> void:
	print("Main: Peer disconnect grace period started for Player %d" % disconnected_player)

	# Clean up any existing disconnect dialog
	if disconnect_dialog and is_instance_valid(disconnect_dialog):
		disconnect_dialog.queue_free()
		disconnect_dialog = null

	var dialog_script = preload("res://dialogs/DisconnectDialog.gd")
	disconnect_dialog = AcceptDialog.new()
	disconnect_dialog.set_script(dialog_script)
	add_child(disconnect_dialog)
	disconnect_dialog.z_index = UI_MODAL_Z

	disconnect_dialog.save_game_requested.connect(_on_disconnect_save_game)
	disconnect_dialog.continue_single_player_requested.connect(_on_disconnect_continue_single_player.bind(disconnected_player))
	disconnect_dialog.claim_victory_requested.connect(_on_disconnect_claim_victory)

	disconnect_dialog.setup(disconnected_player)
	disconnect_dialog.popup_centered()
	print("Main: Showed disconnect dialog for Player %d" % disconnected_player)

func _on_disconnect_save_game() -> void:
	print("Main: Disconnect — saving game state")
	if SaveLoadManager:
		var metadata = {
			"reason": "disconnect_save",
			"disconnected_player": NetworkManager._disconnected_player_num,
		}
		var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		var save_name = "disconnect_save_%s" % timestamp
		SaveLoadManager.save_game(save_name, metadata)
		print("Main: Game state saved as '%s'" % save_name)
		if ToastManager:
			ToastManager.show_success("Game saved: %s" % save_name)
	else:
		print("Main: WARNING — SaveLoadManager not available, cannot save")
		if ToastManager:
			ToastManager.show_error("Save failed — SaveLoadManager not available")

func _on_disconnect_continue_single_player(disconnected_player: int) -> void:
	print("Main: Disconnect — continuing in single-player mode")
	NetworkManager.finalize_disconnect_as_single_player()
	# Enable AI for the disconnected player so the game can continue
	if AIPlayer:
		var other_player = 3 - disconnected_player
		AIPlayer.ai_players[disconnected_player] = true
		AIPlayer.ai_players[other_player] = false
		AIPlayer.ai_difficulty[disconnected_player] = AIDifficultyConfigData.Difficulty.NORMAL
		AIPlayer.enabled = true
		print("Main: AI enabled for Player %d (Normal difficulty)" % disconnected_player)
	if ToastManager:
		ToastManager.show_info("Continuing in single-player — Player %d is now AI" % disconnected_player)

func _on_disconnect_claim_victory() -> void:
	print("Main: Disconnect — claiming victory")
	NetworkManager.finalize_disconnect_as_victory()

func _get_phase_label_text(phase: GameStateData.Phase) -> String:
	match phase:
		GameStateData.Phase.FORMATIONS: return "Declare Battle Formations"
		GameStateData.Phase.DEPLOYMENT: return "Deployment Phase"
		GameStateData.Phase.REDEPLOYMENT: return "Redeployment"
		GameStateData.Phase.SCOUT: return "Scout Moves"
		GameStateData.Phase.SCOUT_MOVES: return "Scout Moves"
		GameStateData.Phase.ROLL_OFF: return "Roll Off — First Turn"
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
		GameStateData.Phase.FORMATIONS: return "Confirm Formations"
		GameStateData.Phase.DEPLOYMENT: return "End Deployment"
		GameStateData.Phase.REDEPLOYMENT: return "End Redeployment"
		GameStateData.Phase.SCOUT: return "End Scout Moves"
		GameStateData.Phase.SCOUT_MOVES: return "End Scout Moves"
		GameStateData.Phase.ROLL_OFF: return "Roll for First Turn"
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
		GameStateData.Phase.FORMATIONS:
			_on_formations_confirm_pressed()
			return
		GameStateData.Phase.DEPLOYMENT:
			_on_end_deployment_pressed()  # Already handles network routing
			return
		GameStateData.Phase.REDEPLOYMENT:
			action = {"type": "END_REDEPLOYMENT_PHASE", "player": active_player}
		GameStateData.Phase.SCOUT:
			# Skip all remaining pending scout moves before ending the phase
			var scout_phase = PhaseManager.get_current_phase_instance()
			if scout_phase:
				var scout_pending = scout_phase.get("scout_units_pending")
				if scout_pending:
					# Collect all pending unit IDs across all players
					var all_pending = []
					for p in scout_pending:
						all_pending.append_array(scout_pending[p].duplicate())
					for pending_uid in all_pending:
						var skip_action = {"type": "SKIP_SCOUT_MOVE", "unit_id": pending_uid, "player": active_player}
						NetworkIntegration.route_action(skip_action)
			_scout_cleanup_after_move()
			action = {"type": "END_SCOUT_PHASE", "player": active_player}
		GameStateData.Phase.SCOUT_MOVES:
			action = {"type": "END_SCOUT_MOVES", "player": active_player}
		GameStateData.Phase.ROLL_OFF:
			action = {"type": "ROLL_FOR_FIRST_TURN", "player": active_player}
		GameStateData.Phase.COMMAND:
			# P3-94: Check for untested battle-shock units and show confirmation dialog
			var command_phase_instance = PhaseManager.get_current_phase_instance()
			if command_phase_instance and command_phase_instance.has_method("get_untested_battle_shock_units"):
				var untested = command_phase_instance.get_untested_battle_shock_units()
				if untested.size() > 0:
					print("Main: P3-94: %d untested battle-shock units remain, showing confirmation dialog" % untested.size())
					_show_battle_shock_confirmation_dialog(untested, active_player)
					return
			action = {"type": "END_COMMAND", "player": active_player}
		GameStateData.Phase.MOVEMENT:
			action = {"type": "END_MOVEMENT", "player": active_player}
		GameStateData.Phase.SHOOTING:
			action = {"type": "END_SHOOTING", "player": active_player}
		GameStateData.Phase.CHARGE:
			action = {"type": "END_CHARGE", "player": active_player}
		GameStateData.Phase.FIGHT:
			# T5-UX7: Check for unfought units and show confirmation dialog
			var fight_phase_instance = PhaseManager.get_current_phase_instance()
			if fight_phase_instance and fight_phase_instance.has_method("get_unfought_eligible_units"):
				var unfought = fight_phase_instance.get_unfought_eligible_units()
				if unfought.size() > 0:
					print("Main: T5-UX7: %d unfought units remain, showing confirmation dialog" % unfought.size())
					_show_end_fight_confirmation_dialog(unfought, active_player)
					return
			action = {"type": "END_FIGHT", "player": active_player}
		GameStateData.Phase.SCORING:
			if GameState.is_game_complete():
				print("Main: Game is complete, cannot advance phase")
				return
			# Check for active secondary missions and offer discard opportunity
			var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
			if secondary_mgr and secondary_mgr.is_initialized(active_player):
				var active_missions = secondary_mgr.get_active_missions(active_player)
				if active_missions.size() > 0:
					print("Main: Player %d has %d active secondary missions, showing discard dialog" % [active_player, active_missions.size()])
					_show_mission_discard_dialog(active_missions, active_player)
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
	else:
		# Update button text after successful roll-off (no longer need to roll)
		if current_phase == GameStateData.Phase.ROLL_OFF and action.get("type") == "ROLL_FOR_FIRST_TURN":
			if not result.get("tied", false):
				phase_action_button.text = "Start Game"
				print("Main: Roll-off complete, button text updated to 'Start Game'")

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


	# Show/hide waiting-for-opponent overlay based on phase (T5-MP6 + T5-MP8)
	_update_waiting_for_opponent_overlay()

	# Phase-specific UI configurations (zones, panels, etc.)
	match current_phase:
		GameStateData.Phase.FORMATIONS:
			# Hide deployment zones during formations declaration
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Hide unit list and unit card during formations
			unit_list.visible = false
			unit_card.visible = false
			# Button starts enabled — formations dialog handles the interaction
			phase_action_button.disabled = false

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

		GameStateData.Phase.SCOUT:
			# Hide deployment zones during scout phase
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Show unit list for scout unit selection, show unit card for details
			unit_list.visible = true
			unit_card.visible = true
			# End Scout Moves button always enabled (can skip remaining scouts)
			phase_action_button.disabled = false
			# Create scout visual elements (ghost, path, staged moves)
			_scout_create_visuals()

		GameStateData.Phase.SCOUT_MOVES:
			# Show deployment zones for reference during scout moves
			p1_zone.visible = true
			p2_zone.visible = true
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Show unit list for scout-eligible units
			unit_list.visible = true
			unit_card.visible = true
			# Button is always enabled (player can skip all scouts)
			phase_action_button.disabled = false

		GameStateData.Phase.ROLL_OFF:
			# Hide deployment zones during roll-off
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons
			_show_movement_action_buttons(false)
			# Hide unit list and unit card during roll-off
			unit_list.visible = false
			unit_card.visible = false
			# Button enabled — triggers the roll
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
			# Hide scout/deployment unit list and unit card - MovementController manages its own right panel UI
			unit_list.visible = false
			unit_card.visible = false

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

	# Override zone visibility if toggle is active (outside deployment phase)
	if _deployment_zones_toggled_on and current_phase != GameStateData.Phase.DEPLOYMENT:
		p1_zone.visible = true
		p2_zone.visible = true
		p1_zone.modulate = Color(0, 0, 1, 0.3)
		p2_zone.modulate = Color(1, 0, 0, 0.3)
		if p1_zone.has_method("set_active"):
			p1_zone.set_active(true)
			p1_zone.border_color = Color(0, 0.3, 1, 1)
		if p2_zone.has_method("set_active"):
			p2_zone.set_active(true)
			p2_zone.border_color = Color(1, 0.3, 0, 1)

	refresh_unit_list()
	update_ui()

	# Refresh the persistent secondary missions overlay if it's open
	if secondary_mission_panel and secondary_mission_panel.has_method("refresh"):
		if not secondary_mission_panel.is_collapsed:
			secondary_mission_panel.refresh()

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
				"USE_COMMAND_REROLL":
					# Advance reroll resolved — unit_move_begun signal handles UI update
					print("Main: Command Re-roll used for advance, UI updated via signal")
				"DECLINE_COMMAND_REROLL":
					# Advance resolved with original roll — unit_move_begun signal handles UI update
					print("Main: Command Re-roll declined for advance, UI updated via signal")
				"SET_MODEL_DEST":
					print("Main: Processing SET_MODEL_DEST - updating visuals for ", action.actor_unit_id, "/", action.payload.model_id)
					_update_model_visual(action.actor_unit_id, action.payload.model_id, action.payload.dest)
				"UNDO_LAST_MODEL_MOVE":
					print("Model move undone")
					# Visual update for the undone model is handled by model_drop_committed signal
					# from MovementPhase. Don't call _recreate_unit_visuals() here as it would
					# reset other staged models back to their GameState positions.
					if movement_controller:
						movement_controller._update_staged_moves_visual()
						# Sync pivot cost and update rotation visual after undo
						var mc_phase = movement_controller.current_phase
						if mc_phase and mc_phase.has_method("get_active_move_data"):
							var mc_move_data = mc_phase.get_active_move_data(movement_controller.active_unit_id)
							if not mc_move_data.is_empty() and not mc_move_data.get("pivot_cost_applied", false):
								movement_controller._reset_pivot_cost()
								movement_controller._update_movement_display()
					# Update token visuals for rotation changes applied by undo
					_update_token_rotations_from_state(action.get("actor_unit_id", ""))
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

			# T4-7: Handle Rapid Ingress — start reinforcement placement for the selected unit
			if action.type == "USE_RAPID_INGRESS" and result.get("rapid_ingress_used", false):
				var ri_unit_id = result.get("rapid_ingress_unit_id", action.get("actor_unit_id", ""))
				if ri_unit_id != "":
					print("Main: Rapid Ingress used — starting reinforcement placement for %s" % ri_unit_id)
					_begin_rapid_ingress_placement(ri_unit_id)

			# OA-24: Handle Kunnin' Infiltrator activation — start redeployment placement
			if action.type == "ACTIVATE_KUNNIN_INFILTRATOR" and result.get("kunnin_infiltrator_activated", false):
				var ki_unit_id = result.get("unit_id", action.get("actor_unit_id", ""))
				if ki_unit_id != "":
					print("Main: Kunnin' Infiltrator activated — starting redeployment placement for %s" % ki_unit_id)
					_begin_kunnin_infiltrator_placement(ki_unit_id)

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
			var error_msg = result.get("error", "Unknown error")
			print("Main: Fight action failed: ", error_msg)
			# T5-MP2: Show toast feedback to the player when server validation rejects
			var action_type = action.get("type", "")
			if action_type == "PILE_IN":
				ToastManager.show_error("Pile-in rejected: %s" % error_msg)
				# Re-request pile-in so player can try again
				_re_request_fight_movement(action, "pile_in")
			elif action_type == "CONSOLIDATE":
				ToastManager.show_error("Consolidate rejected: %s" % error_msg)
				# Re-request consolidate so player can try again
				_re_request_fight_movement(action, "consolidate")
			elif action_type == "SWEEPING_ADVANCE":
				ToastManager.show_error("Sweeping Advance rejected: %s" % error_msg)
			else:
				ToastManager.show_error("Fight action failed: %s" % error_msg)
	else:
		print("Main: Unexpected result from fight action")

func _show_end_fight_confirmation_dialog(unfought_units: Array, active_player: int) -> void:
	"""T5-UX7: Show confirmation dialog before ending fight phase with unfought units"""
	# Skip dialog for AI players — AI always confirms ending fight
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(active_player):
		print("Main: Skipping end fight confirmation dialog for AI player %d" % active_player)
		var action = {"type": "END_FIGHT", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var dialog_script = load("res://dialogs/EndFightConfirmationDialog.gd")
	if not dialog_script:
		push_error("Main: T5-UX7: Failed to load EndFightConfirmationDialog.gd")
		# Fall through and end phase anyway
		var action = {"type": "END_FIGHT", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(unfought_units)
	dialog.end_fight_confirmed.connect(_on_end_fight_confirmed.bind(active_player))
	dialog.end_fight_cancelled.connect(_on_end_fight_cancelled)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("Main: T5-UX7: End fight confirmation dialog shown")

func _on_end_fight_confirmed(active_player: int) -> void:
	"""T5-UX7: Player confirmed ending fight phase despite unfought units"""
	print("Main: T5-UX7: Player confirmed end fight phase")
	var action = {"type": "END_FIGHT", "player": active_player}
	var result = NetworkIntegration.route_action(action)
	if not result.get("success", false):
		print("Main: T5-UX7: Failed to end fight phase: ", result.get("error", "Unknown error"))
		if not NetworkManager.is_networked():
			print("Main: T5-UX7: Falling back to local phase advance")
			PhaseManager.advance_to_next_phase()

func _on_end_fight_cancelled() -> void:
	"""T5-UX7: Player cancelled ending fight phase"""
	print("Main: T5-UX7: Player cancelled end fight phase, returning to fight")

func _show_battle_shock_confirmation_dialog(untested_units: Array, active_player: int) -> void:
	"""P3-94: Show confirmation dialog before ending command phase with untested battle-shock units"""
	# Skip dialog for AI players — AI always confirms ending command
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(active_player):
		print("Main: Skipping battle-shock confirmation dialog for AI player %d" % active_player)
		var action = {"type": "END_COMMAND", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var dialog_script = load("res://dialogs/BattleShockConfirmationDialog.gd")
	if not dialog_script:
		push_error("Main: P3-94: Failed to load BattleShockConfirmationDialog.gd")
		# Fall through and end phase anyway
		var action = {"type": "END_COMMAND", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(untested_units)
	dialog.end_command_confirmed.connect(_on_end_command_confirmed.bind(active_player))
	dialog.end_command_cancelled.connect(_on_end_command_cancelled)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("Main: P3-94: Battle-shock confirmation dialog shown")

func _on_end_command_confirmed(active_player: int) -> void:
	"""P3-94: Player confirmed ending command phase despite untested battle-shock units"""
	print("Main: P3-94: Player confirmed end command phase with untested battle-shock units")
	var action = {"type": "END_COMMAND", "player": active_player}
	var result = NetworkIntegration.route_action(action)
	if not result.get("success", false):
		print("Main: P3-94: Failed to end command phase: ", result.get("error", "Unknown error"))
		if not NetworkManager.is_networked():
			print("Main: P3-94: Falling back to local phase advance")
			PhaseManager.advance_to_next_phase()

func _on_end_command_cancelled() -> void:
	"""P3-94: Player cancelled ending command phase"""
	print("Main: P3-94: Player cancelled end command phase, returning to command phase")

func _show_mission_discard_dialog(active_missions: Array, active_player: int) -> void:
	"""Show dialog offering to discard a secondary mission for CP before ending turn"""
	# Skip dialog for AI players — AI never discards via this prompt
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(active_player):
		print("Main: Skipping mission discard dialog for AI player %d" % active_player)
		var action = {"type": "END_SCORING", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var dialog_script = load("res://dialogs/MissionDiscardDialog.gd")
	if not dialog_script:
		push_error("Main: Failed to load MissionDiscardDialog.gd")
		var action = {"type": "END_SCORING", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var can_gain_cp = GameState.can_gain_bonus_cp(active_player)
	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(active_missions, can_gain_cp)
	dialog.mission_discard_requested.connect(_on_mission_discard_from_dialog.bind(active_player))
	dialog.end_turn_without_discard.connect(_on_end_scoring_without_discard.bind(active_player))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("Main: Mission discard dialog shown for player %d" % active_player)

func _on_mission_discard_from_dialog(mission_index: int, active_player: int) -> void:
	"""Player chose to discard a secondary mission from the end-turn dialog"""
	print("Main: Player %d discarding mission index %d from dialog" % [active_player, mission_index])
	var discard_action = {
		"type": "DISCARD_SECONDARY",
		"mission_index": mission_index,
		"player": active_player,
	}
	var result = NetworkIntegration.route_action(discard_action)
	if result.get("success", false):
		print("Main: Mission discarded successfully, now ending scoring phase")
	else:
		print("Main: Mission discard failed: ", result.get("error", "Unknown error"))
	# End the scoring phase after the discard
	var end_action = {"type": "END_SCORING", "player": active_player}
	var end_result = NetworkIntegration.route_action(end_action)
	if not end_result.get("success", false):
		print("Main: Failed to end scoring phase: ", end_result.get("error", "Unknown error"))
		if not NetworkManager.is_networked():
			print("Main: Falling back to local phase advance")
			PhaseManager.advance_to_next_phase()

func _on_end_scoring_without_discard(active_player: int) -> void:
	"""Player chose to end turn without discarding any mission"""
	print("Main: Player %d ending scoring phase without discarding" % active_player)
	var action = {"type": "END_SCORING", "player": active_player}
	var result = NetworkIntegration.route_action(action)
	if not result.get("success", false):
		print("Main: Failed to end scoring phase: ", result.get("error", "Unknown error"))
		if not NetworkManager.is_networked():
			print("Main: Falling back to local phase advance")
			PhaseManager.advance_to_next_phase()

func _show_deployment_summary_dialog(deployment_data: Dictionary, active_player: int) -> void:
	"""T5-UX8: Show deployment summary dialog before ending deployment phase"""
	# Skip dialog for AI players — AI always confirms ending deployment
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(active_player):
		print("Main: Skipping deployment summary dialog for AI player %d" % active_player)
		var action = {"type": "END_DEPLOYMENT", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var dialog_script = load("res://dialogs/DeploymentSummaryDialog.gd")
	if not dialog_script:
		push_error("Main: T5-UX8: Failed to load DeploymentSummaryDialog.gd")
		# Fall through and end phase anyway
		var action = {"type": "END_DEPLOYMENT", "player": active_player}
		NetworkIntegration.route_action(action)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(deployment_data)
	dialog.deployment_confirmed.connect(_on_deployment_confirmed.bind(active_player))
	dialog.deployment_cancelled.connect(_on_deployment_cancelled)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("Main: T5-UX8: Deployment summary dialog shown")

func _on_deployment_confirmed(active_player: int) -> void:
	"""T5-UX8: Player confirmed ending deployment phase"""
	print("Main: T5-UX8: Player confirmed end deployment phase")
	var action = {"type": "END_DEPLOYMENT", "player": active_player}
	var result = NetworkIntegration.route_action(action)
	if not result.get("success", false):
		print("Main: T5-UX8: Failed to end deployment phase: ", result.get("error", "Unknown error"))
		if not NetworkManager.is_networked():
			print("Main: T5-UX8: Falling back to local phase advance")
			PhaseManager.advance_to_next_phase()

func _on_deployment_cancelled() -> void:
	"""T5-UX8: Player cancelled ending deployment phase"""
	print("Main: T5-UX8: Player cancelled end deployment phase, returning to deployment")

func _re_request_fight_movement(action: Dictionary, movement_type: String) -> void:
	"""T5-MP2: Re-emit pile_in_required or consolidate_required so the dialog reopens after server rejection"""
	var phase_instance = PhaseManager.get_current_phase_instance()
	if not phase_instance:
		print("Main: T5-MP2: Cannot re-request %s — no phase instance" % movement_type)
		return

	var unit_id = action.get("unit_id", "")
	if unit_id.is_empty():
		print("Main: T5-MP2: Cannot re-request %s — no unit_id in action" % movement_type)
		return

	# Small delay to let previous dialog fully close before showing a new one
	await get_tree().create_timer(0.3).timeout

	if movement_type == "pile_in" and phase_instance.has_signal("pile_in_required"):
		print("Main: T5-MP2: Re-requesting pile-in for %s" % unit_id)
		phase_instance.emit_signal("pile_in_required", unit_id, 3.0)
	elif movement_type == "consolidate" and phase_instance.has_signal("consolidate_required"):
		print("Main: T5-MP2: Re-requesting consolidate for %s" % unit_id)
		phase_instance.emit_signal("consolidate_required", unit_id, 3.0)

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

func _on_model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2, rotation: float = 0.0) -> void:
	# Handle visual updates for model drops (including staged moves)
	print("Main: Model drop committed for ", unit_id, "/", model_id, " at ", dest_px, " rotation: ", rotation)

	# For staged moves, we want to move the visual token directly without updating GameState
	# Move ALL matching tokens (there may be duplicates from concurrent _recreate_unit_visuals calls)
	var found_any = false
	if token_layer:
		for child in token_layer.get_children():
			# Check direct child (tokens created by _recreate_unit_visuals)
			if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id and child.has_meta("model_id") and child.get_meta("model_id") == model_id:
				child.position = dest_px
				# Apply rotation to the token's model_data so it draws correctly
				if "model_data" in child and child.model_data is Dictionary:
					child.model_data["rotation"] = rotation
				child.queue_redraw()
				if not found_any:
					print("Moving token visual to ", dest_px, " with rotation ", rotation)
				found_any = true
				continue
			# Check nested children (deployment tokens have meta on inner base_circle)
			for grandchild in child.get_children():
				if grandchild.has_meta("unit_id") and grandchild.get_meta("unit_id") == unit_id and grandchild.has_meta("model_id") and grandchild.get_meta("model_id") == model_id:
					child.position = dest_px
					# Apply rotation to nested token's model_data
					if "model_data" in grandchild and grandchild.model_data is Dictionary:
						grandchild.model_data["rotation"] = rotation
					grandchild.queue_redraw()
					if not found_any:
						print("Moving token visual (nested) to ", dest_px, " with rotation ", rotation)
					found_any = true
					break

	if not found_any:
		print("Could not find token to move, falling back to full recreation")
		_update_model_visual(unit_id, model_id, [dest_px.x, dest_px.y])

func _update_token_rotations_from_state(unit_id: String) -> void:
	"""Update token visual rotations to match current GameState values."""
	if not token_layer or unit_id == "":
		return
	var unit = GameState.get_unit(unit_id)
	if not unit:
		return
	var models = unit.get("models", [])
	for model in models:
		var model_id = model.get("id", "")
		var rotation = model.get("rotation", 0.0)
		for child in token_layer.get_children():
			if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id and \
			   child.has_meta("model_id") and child.get_meta("model_id") == model_id:
				if child.has_method("set_base_rotation"):
					child.set_base_rotation(rotation)
				elif child.has_method("set_model_data"):
					child.set_model_data(model)
					child.queue_redraw()
				break

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

func _hide_left_panel() -> void:
	"""Hide the left panel by default"""
	var hud_left = get_node_or_null("HUD_Left")
	if hud_left:
		hud_left.visible = false
		is_left_panel_visible = false
		print("Left panel hidden by default")

func _on_left_panel_toggle_pressed() -> void:
	"""Toggle visibility of left panel (Mathhammer)"""
	var hud_left = get_node_or_null("HUD_Left")
	if not hud_left:
		print("ERROR: Could not find HUD_Left to toggle")
		return

	is_left_panel_visible = !is_left_panel_visible
	hud_left.visible = is_left_panel_visible

	print("Left panel visibility toggled: ", is_left_panel_visible)

func _toggle_secondary_mission_panel() -> void:
	"""Toggle the persistent secondary missions overlay (M key)."""
	if secondary_mission_panel and secondary_mission_panel.has_method("toggle"):
		secondary_mission_panel.toggle()
		print("Main: Secondary missions panel toggled")
	else:
		print("Main: SecondaryMissionPanel not available")


func _setup_phase_transition_banner() -> void:
	# T5-V3: Create the phase transition animation banner
	phase_transition_banner = PhaseTransitionBanner.new()
	phase_transition_banner.name = "PhaseTransitionBanner"
	add_child(phase_transition_banner)
	print("Main: T5-V3: Phase transition banner initialized")

func _setup_player_turn_border() -> void:
	# P2-44: Create the player turn screen-edge color indicator
	_player_turn_border = PlayerTurnBorder.new()
	add_child(_player_turn_border)
	var active_player = GameState.get_active_player()
	_player_turn_border.set_active_player(active_player)
	_last_active_player = active_player
	print("Main: P2-44: Player turn border initialized for Player %d" % active_player)

func _setup_game_log_panel() -> void:
	print("Main: Setting up Game Event Log panel (card-based)")
	game_log_panel = GameLogPanel.new()
	var hud_bottom = get_node_or_null("HUD_Bottom/HBoxContainer")
	game_log_panel.setup(self, hud_bottom, 105.0, -305.0)
	game_log_toggle_button = game_log_panel.get_toggle_button()
	print("Main: Game Event Log panel created (card-based)")

func _prune_old_log_entries() -> void:
	"""Remove oldest log entry cards when count exceeds 200 to prevent memory bloat."""
	if not game_log_entries_container:
		return
	var max_entries = 200
	while game_log_entries_container.get_child_count() > max_entries:
		var oldest = game_log_entries_container.get_child(0)
		game_log_entries_container.remove_child(oldest)
		oldest.queue_free()

# ============================================================================
# P3-117: Dice Roll History Panel
# ============================================================================

func _setup_dice_history_panel() -> void:
	print("Main: Setting up Dice Roll History panel")

	# Create panel anchored to the left side, offset from game log
	_dice_history_panel = PanelContainer.new()
	_dice_history_panel.name = "DiceHistoryPanel"
	add_child(_dice_history_panel)

	# Position to the right of the game log panel (280px) with a small gap
	_dice_history_panel.anchor_left = 0.0
	_dice_history_panel.anchor_right = 0.0
	_dice_history_panel.anchor_top = 0.0
	_dice_history_panel.anchor_bottom = 1.0
	_dice_history_panel.offset_left = 345.0
	_dice_history_panel.offset_right = 625.0
	_dice_history_panel.offset_top = 105.0
	_dice_history_panel.offset_bottom = -305.0

	# Dark semi-transparent background matching game log style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	style.border_width_left = 0
	style.border_width_right = 2
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.border_color = Color(0.7, 0.5, 0.9, 0.6)  # Purple accent to distinguish from game log
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	_dice_history_panel.add_theme_stylebox_override("panel", style)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	_dice_history_panel.add_child(vbox)

	# Header with title and close button
	var header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "Dice History"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))  # Purple
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var clear_btn = Button.new()
	clear_btn.text = "Clear"
	clear_btn.custom_minimum_size = Vector2(45, 25)
	clear_btn.add_theme_font_size_override("font_size", 11)
	clear_btn.pressed.connect(_on_dice_history_clear_pressed)
	header.add_child(clear_btn)

	var collapse_btn = Button.new()
	collapse_btn.text = "X"
	collapse_btn.custom_minimum_size = Vector2(30, 25)
	collapse_btn.add_theme_font_size_override("font_size", 12)
	collapse_btn.pressed.connect(_on_dice_history_collapse_pressed)
	header.add_child(collapse_btn)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Scroll container for dice history entries
	_dice_history_scroll = ScrollContainer.new()
	_dice_history_scroll.name = "DiceHistoryScroll"
	_dice_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dice_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_dice_history_scroll)

	# RichTextLabel for color-coded dice entries
	_dice_history_label = RichTextLabel.new()
	_dice_history_label.name = "DiceHistoryLabel"
	_dice_history_label.bbcode_enabled = true
	_dice_history_label.fit_content = true
	_dice_history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dice_history_label.scroll_active = false  # We use our own scroll container
	_dice_history_label.add_theme_font_size_override("normal_font_size", 10)
	_dice_history_label.add_theme_font_size_override("bold_font_size", 11)
	_dice_history_scroll.add_child(_dice_history_label)

	# Connect to DiceHistoryPanel autoload signal
	if DiceHistoryPanel:
		DiceHistoryPanel.roll_recorded.connect(_on_dice_history_roll_recorded)
		print("Main: Connected to DiceHistoryPanel.roll_recorded")

		# Populate any entries that were added before we connected
		for entry_item in DiceHistoryPanel.get_history():
			_append_dice_history_entry(entry_item)

	# Add toggle button to HUD_Bottom
	var hud_bottom = get_node_or_null("HUD_Bottom/HBoxContainer")
	if hud_bottom:
		_dice_history_toggle_button = Button.new()
		_dice_history_toggle_button.name = "DiceHistoryToggle"
		_dice_history_toggle_button.text = "Dice History"
		_dice_history_toggle_button.pressed.connect(_on_dice_history_toggle_pressed)
		hud_bottom.add_child(_dice_history_toggle_button)
		# Position after the game log toggle button
		var log_toggle_idx = game_log_toggle_button.get_index() if game_log_toggle_button else 1
		hud_bottom.move_child(_dice_history_toggle_button, log_toggle_idx + 1)

	# Start hidden — user opens via toggle button
	_dice_history_panel.visible = false

	print("Main: Dice Roll History panel created")

func _on_dice_history_roll_recorded(entry: Dictionary) -> void:
	_append_dice_history_entry(entry)

	# Auto-scroll to bottom
	if _dice_history_scroll:
		await get_tree().process_frame
		_dice_history_scroll.scroll_vertical = int(_dice_history_scroll.get_v_scroll_bar().max_value)

func _append_dice_history_entry(entry: Dictionary) -> void:
	if not _dice_history_label:
		return
	var bbcode = DiceHistoryPanel.format_entry_bbcode(entry)
	_dice_history_label.append_text(bbcode + "\n")

func _on_dice_history_collapse_pressed() -> void:
	_is_dice_history_visible = false
	if _dice_history_panel:
		_dice_history_panel.visible = false
	if _dice_history_toggle_button:
		_dice_history_toggle_button.text = "Dice History"

func _on_dice_history_toggle_pressed() -> void:
	_is_dice_history_visible = !_is_dice_history_visible
	if _dice_history_panel:
		_dice_history_panel.visible = _is_dice_history_visible
	if _dice_history_toggle_button:
		_dice_history_toggle_button.text = "Hide Dice" if _is_dice_history_visible else "Dice History"

func _on_dice_history_clear_pressed() -> void:
	if DiceHistoryPanel:
		DiceHistoryPanel.clear()
	if _dice_history_label:
		_dice_history_label.clear()

# ============================================================================
# Replay Mode
# ============================================================================

func _start_replay_recording_if_needed() -> void:
	"""Start replay recording for AI vs AI games automatically."""
	if not ReplayManager:
		return

	if ReplayManager.should_auto_record():
		print("Main: Auto-starting replay recording (AI vs AI game)")
		# Small delay to ensure all initialization is complete
		await get_tree().create_timer(0.2).timeout
		ReplayManager.start_recording()
	else:
		print("Main: Replay recording not auto-started (not AI vs AI)")

func _initialize_replay_mode() -> void:
	"""Initialize the Main scene in replay mode - streamlined, no game logic."""
	print("Main: Initializing replay mode...")

	# Initialize view
	view_zoom = 0.3
	view_offset = Vector2.ZERO
	update_view_transform()

	# Setup board visuals (terrain, deployment zones, objectives)
	board_view.queue_redraw()
	setup_deployment_zones()
	_setup_objectives()
	_restructure_ui_layout()
	_fix_hud_layout()
	_setup_terrain()

	# Hide normal game UI elements that aren't needed in replay
	if phase_action_button:
		phase_action_button.visible = false
	if undo_button:
		undo_button.visible = false
	if reset_button:
		reset_button.visible = false
	if confirm_button:
		confirm_button.visible = false

	# Create unit visuals from initial state
	_recreate_unit_visuals()

	# Wait for visuals to render
	await get_tree().process_frame

	# Create and setup the ReplayUI controller
	var ReplayUIScript = preload("res://scripts/ReplayUI.gd")
	replay_ui = Node.new()
	replay_ui.set_script(ReplayUIScript)
	replay_ui.name = "ReplayUI"
	add_child(replay_ui)
	replay_ui.setup(self)

	# Connect to ReplayManager signals for visual refresh during auto-play
	if ReplayManager:
		ReplayManager.replay_event_applied.connect(_on_replay_event_applied)

	# Update the top HUD to show replay info
	var meta = ReplayManager.get_replay_metadata() if ReplayManager else {}
	var p1_faction = meta.get("player1_faction", "Player 1")
	var p2_faction = meta.get("player2_faction", "Player 2")
	if phase_label:
		phase_label.text = "REPLAY: %s vs %s" % [p1_faction, p2_faction]
	if status_label:
		status_label.text = "Use Space to play/pause, Arrow keys to step"

	# Setup Game Event Log panel (useful for replay too)
	_setup_game_log_panel()
	# P3-117: Setup Dice Roll History panel
	_setup_dice_history_panel()
	_apply_white_dwarf_theme()

	# Ensure all UI panels render above board elements in replay mode too
	_ensure_ui_panels_on_top()

	print("Main: Replay mode initialization complete")

func _on_replay_event_applied(event: Dictionary) -> void:
	"""Called when a replay event is applied - refresh visuals to match state."""
	_replay_refresh_visuals()

	# Also add the event description to the game log
	var description = event.get("description", "")
	var event_type = event.get("type", "")
	if description != "":
		var entry_type = "info"
		if event_type == "phase_change":
			entry_type = "phase_header"
		elif event.get("active_player", 0) == 1:
			entry_type = "p1_action"
		elif event.get("active_player", 0) == 2:
			entry_type = "p2_action"
		if GameEventLog:
			GameEventLog.add_entry(description, entry_type)

var _replay_refresh_pending: bool = false

func _replay_refresh_visuals() -> void:
	"""Recreate all unit token visuals from current GameState.
	Called by ReplayUI after each step/jump.
	Uses a guard to prevent re-entrant refreshes during rapid auto-play."""
	if _replay_refresh_pending:
		return
	_replay_refresh_pending = true

	# Clear existing tokens
	for child in token_layer.get_children():
		child.queue_free()

	# Wait a frame for queue_free to process
	await get_tree().process_frame

	# Recreate tokens for all deployed/active units
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]

		# Skip embarked units
		if unit.get("embarked_in", null) != null:
			continue

		var status = unit.get("status", 0)
		if status >= GameStateData.UnitStatus.DEPLOYED:
			var models = unit.get("models", [])
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

	# Update HUD elements
	refresh_unit_list()
	update_ui()

	# Update phase label from GameState
	var phase = GameState.get_current_phase()
	if active_player_badge:
		active_player_badge.text = "P%d" % GameState.get_active_player()

	_replay_refresh_pending = false


# --- Visual Style Toggle (Key 8) ---

func _toggle_visual_style() -> void:
	if not SettingsService:
		return
	var current = SettingsService.unit_visual_style
	if current == "letter":
		SettingsService.set_unit_visual_style_setting("enhanced")
	else:
		SettingsService.set_unit_visual_style_setting("letter")

	# Force redraw of all tokens
	_force_redraw_all_tokens()

	# Show a toast notification
	var new_style = SettingsService.unit_visual_style
	if ToastManager and ToastManager.has_method("show_toast"):
		var msg = "STYLE: %s [8]" % new_style.to_upper()
		ToastManager.show_toast(msg)
	print("Main: Visual style toggled to %s" % new_style)


var _army_panel: ArmyPanel = null

func _toggle_army_panel() -> void:
	if _army_panel and is_instance_valid(_army_panel):
		_army_panel.queue_free()
		_army_panel = null
		return

	_army_panel = ArmyPanel.new()
	add_child(_army_panel)
	_army_panel.z_index = UI_OVERLAY_Z
	_army_panel.panel_closed.connect(_on_army_panel_closed)
	_army_panel.unit_visual_changed.connect(_on_army_panel_visual_changed)
	print("Main: Army panel opened")


func _on_army_panel_closed() -> void:
	_army_panel = null
	print("Main: Army panel closed")


func _on_army_panel_visual_changed(uid: String) -> void:
	_refresh_tokens_for_unit(uid)


func _force_redraw_all_tokens() -> void:
	if token_layer:
		for child in token_layer.get_children():
			if child is Node2D:
				# Redraw direct TokenVisual children (created by Main._create_token_visual)
				child.queue_redraw()
				# Also redraw sub-children for wrapped tokens (created by DeploymentController)
				for sub in child.get_children():
					if sub.has_method("queue_redraw"):
						sub.queue_redraw()


# --- Right-click context menu (color/label editing) ---

var _unit_context_menu: PopupMenu = null
var _context_unit_id: String = ""

func _handle_right_click(event: InputEventMouseButton) -> void:
	# Only in letter mode
	var style = SettingsService.unit_visual_style if SettingsService else "classic"
	if style != "letter":
		return

	# Convert screen position to world position
	var world_pos = _screen_to_world(event.global_position)
	if world_pos == null:
		return

	var uid = _find_unit_at_world_pos(world_pos)
	if uid == "":
		return

	_context_unit_id = uid

	# Remove existing context menu
	if _unit_context_menu and is_instance_valid(_unit_context_menu):
		_unit_context_menu.queue_free()

	_unit_context_menu = PopupMenu.new()
	_unit_context_menu.name = "UnitContextMenu"
	_unit_context_menu.add_item("Change Color", 0)
	_unit_context_menu.add_item("Change Label", 1)
	_unit_context_menu.id_pressed.connect(_on_unit_context_menu_pressed)
	add_child(_unit_context_menu)
	_unit_context_menu.z_index = UI_OVERLAY_Z
	_unit_context_menu.position = Vector2i(int(event.global_position.x), int(event.global_position.y))
	_unit_context_menu.popup()

	# Consume the event so other handlers (DeploymentController cancel,
	# MovementController rotation) don't also process this right-click
	get_viewport().set_input_as_handled()


func _on_unit_context_menu_pressed(id: int) -> void:
	match id:
		0:  # Change Color
			_show_unit_color_picker_popup(_context_unit_id)
		1:  # Change Label
			_show_unit_label_dialog(_context_unit_id)


func _show_unit_color_picker_popup(uid: String) -> void:
	# Remove any existing picker
	var existing = get_node_or_null("UnitColorPickerPopup")
	if existing:
		existing.queue_free()

	var picker = UnitColorPickerPopup.new()
	add_child(picker)
	picker.z_index = UI_OVERLAY_Z
	var popup_pos = get_viewport().get_mouse_position()
	picker.setup(uid, popup_pos)
	picker.color_changed.connect(_on_unit_color_changed_from_popup)


func _on_unit_color_changed_from_popup(uid: String, _color: Color) -> void:
	_refresh_tokens_for_unit(uid)


func _show_unit_label_dialog(uid: String) -> void:
	# Remove any existing label dialog
	var existing = get_node_or_null("UnitLabelDialog")
	if existing:
		existing.queue_free()

	var dialog = PanelContainer.new()
	dialog.name = "UnitLabelDialog"
	dialog.z_index = UI_MODAL_Z

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style_box.border_color = Color(0.8, 0.65, 0.3)
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.corner_radius_top_left = 6
	style_box.corner_radius_top_right = 6
	style_box.corner_radius_bottom_left = 6
	style_box.corner_radius_bottom_right = 6
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 12
	style_box.content_margin_bottom = 12
	dialog.add_theme_stylebox_override("panel", style_box)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "Custom Label"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.8, 0.65, 0.3))
	vbox.add_child(title_lbl)

	var line_edit = LineEdit.new()
	line_edit.text = GameState.get_unit_label(uid)
	line_edit.placeholder_text = "Enter label (leave empty for auto)"
	line_edit.custom_minimum_size = Vector2(200, 30)
	line_edit.max_length = 6
	vbox.add_child(line_edit)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(60, 28)
	ok_btn.pressed.connect(func():
		GameState.set_unit_label(uid, line_edit.text)
		_refresh_tokens_for_unit(uid)
		dialog.queue_free()
	)
	btn_row.add_child(ok_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(60, 28)
	cancel_btn.pressed.connect(func():
		dialog.queue_free()
	)
	btn_row.add_child(cancel_btn)

	add_child(dialog)
	var mouse_pos = get_viewport().get_mouse_position()
	dialog.position = mouse_pos
	line_edit.grab_focus()


func _find_unit_at_world_pos(world_pos: Vector2) -> String:
	if not token_layer:
		return ""

	var closest_uid: String = ""
	var closest_dist: float = INF

	for unit_node in token_layer.get_children():
		if not unit_node is Node2D:
			continue
		for model_node in unit_node.get_children():
			if not model_node is Node2D:
				continue
			if not model_node.has_meta("unit_id"):
				continue
			var dist = model_node.global_position.distance_to(world_pos)
			# Check if click is within the token's base radius
			var base_radius = 20.0  # Default
			if model_node.has_method("get") and model_node.get("base_shape"):
				var bounds = model_node.base_shape.get_bounds()
				base_radius = max(bounds.size.x, bounds.size.y) / 2.0
			if dist <= base_radius + 5.0 and dist < closest_dist:
				closest_dist = dist
				closest_uid = model_node.get_meta("unit_id")

	return closest_uid


func _screen_to_world(screen_pos: Vector2):
	# Convert screen position to world coordinates through the camera
	if not camera:
		return null
	var canvas_transform = get_viewport().canvas_transform
	return canvas_transform.affine_inverse() * screen_pos


func _refresh_tokens_for_unit(uid: String) -> void:
	if not token_layer:
		return
	for unit_node in token_layer.get_children():
		if not unit_node is Node2D:
			continue
		for model_node in unit_node.get_children():
			if model_node.has_meta("unit_id") and model_node.get_meta("unit_id") == uid:
				if model_node.has_method("queue_redraw"):
					model_node.queue_redraw()


# ============================================================================
# Scout Phase - Model Dragging and UI (reuses MovementController visual patterns)
# ============================================================================

func _scout_find_model_at_position(world_pos: Vector2) -> Dictionary:
	"""Find a model belonging to the active scout unit at the given world position.
	Returns full model data from GameState for proper ghost visual creation."""
	if not token_layer or _scout_active_unit_id == "":
		return {}

	var closest_model = {}
	var closest_distance = INF

	for child in token_layer.get_children():
		if not child.has_meta("unit_id") or not child.has_meta("model_id"):
			continue
		if child.get_meta("unit_id") != _scout_active_unit_id:
			continue

		var model_id = child.get_meta("model_id")
		var visual_pos = child.position
		var distance = world_pos.distance_to(visual_pos)

		var base_radius = 16.0
		if child.has_meta("base_mm"):
			base_radius = Measurement.base_radius_px(child.get_meta("base_mm"))

		if distance <= base_radius and distance < closest_distance:
			closest_distance = distance
			# Fetch complete model data from GameState (same as MovementController)
			var unit = GameState.get_unit(_scout_active_unit_id)
			if not unit.is_empty():
				var models = unit.get("models", [])
				for model_data in models:
					if model_data.get("id", "") == model_id:
						closest_model = model_data.duplicate()
						closest_model["unit_id"] = _scout_active_unit_id
						closest_model["model_id"] = model_id
						closest_model["position"] = visual_pos
						break
			# Fallback if GameState lookup fails
			if closest_model.is_empty():
				closest_model = {
					"unit_id": _scout_active_unit_id,
					"model_id": model_id,
					"position": visual_pos,
					"base_mm": child.get_meta("base_mm") if child.has_meta("base_mm") else 32
				}

	return closest_model

func _scout_create_visuals() -> void:
	"""Create scout phase visual elements (ghost, path, labels) in BoardRoot space.
	Mirrors MovementController._create_path_visuals()."""
	var board_root = get_node_or_null("BoardRoot")
	if not board_root:
		return

	# Ghost visual container (same as MovementController)
	if not _scout_ghost_visual or not is_instance_valid(_scout_ghost_visual):
		_scout_ghost_visual = Node2D.new()
		_scout_ghost_visual.name = "ScoutGhostVisual"
		board_root.add_child(_scout_ghost_visual)

	# Path visual (green line from drag start to cursor, same as MovementController)
	if not _scout_path_visual or not is_instance_valid(_scout_path_visual):
		_scout_path_visual = Line2D.new()
		_scout_path_visual.name = "ScoutPathVisual"
		_scout_path_visual.width = 2.0
		_scout_path_visual.default_color = Color.GREEN
		board_root.add_child(_scout_path_visual)

	# Staged moves visualization (HumanMovementPathVisual for already-placed models)
	if not _scout_staged_path_visual or not is_instance_valid(_scout_staged_path_visual):
		var HumanMovementPathVisualScript = preload("res://scripts/HumanMovementPathVisual.gd")
		_scout_staged_path_visual = Node2D.new()
		_scout_staged_path_visual.set_script(HumanMovementPathVisualScript)
		_scout_staged_path_visual.name = "ScoutStagedPathVisual"
		board_root.add_child(_scout_staged_path_visual)

func _scout_destroy_visuals() -> void:
	"""Clean up all scout phase visual elements."""
	if _scout_ghost_visual and is_instance_valid(_scout_ghost_visual):
		_scout_ghost_visual.queue_free()
		_scout_ghost_visual = null
	if _scout_path_visual and is_instance_valid(_scout_path_visual):
		_scout_path_visual.queue_free()
		_scout_path_visual = null
	if _scout_staged_path_visual and is_instance_valid(_scout_staged_path_visual):
		_scout_staged_path_visual.queue_free()
		_scout_staged_path_visual = null
	_scout_movement_remaining_label = null

func _scout_show_ghost_visual(model: Dictionary) -> void:
	"""Create a ghost preview for the model being dragged (same as MovementController._show_ghost_visual)."""
	_scout_clear_ghost_visual()
	if not _scout_ghost_visual or not is_instance_valid(_scout_ghost_visual):
		_scout_create_visuals()

	# Create ghost token using GhostVisual (same as MovementController)
	var ghost_token = preload("res://scripts/GhostVisual.gd").new()
	ghost_token.owner_player = GameState.get_active_player()
	ghost_token.is_valid_position = true
	ghost_token.set_model_data(model)

	if model.has("rotation"):
		ghost_token.set_base_rotation(model.get("rotation", 0.0))

	ghost_token.position = Vector2.ZERO
	_scout_ghost_visual.add_child(ghost_token)
	_scout_ghost_visual.modulate = Color(1, 1, 1, 0.8)

	# Create floating movement remaining label (same as MovementController)
	_scout_movement_remaining_label = Label.new()
	_scout_movement_remaining_label.name = "ScoutMovementRemainingLabel"
	_scout_movement_remaining_label.text = ""
	_scout_movement_remaining_label.add_theme_font_size_override("font_size", 16)
	_scout_movement_remaining_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 0.9))
	_scout_movement_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scout_movement_remaining_label.z_index = 58
	_scout_movement_remaining_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_mm = model.get("base_mm", 32)
	var base_radius_px = Measurement.base_radius_px(base_mm)
	_scout_movement_remaining_label.position = Vector2(-30, -(base_radius_px + 22))
	_scout_ghost_visual.add_child(_scout_movement_remaining_label)

func _scout_clear_ghost_visual() -> void:
	"""Remove all children from the ghost visual container."""
	if _scout_ghost_visual and is_instance_valid(_scout_ghost_visual):
		for child in _scout_ghost_visual.get_children():
			child.queue_free()
	_scout_movement_remaining_label = null

func _scout_update_ghost_position(world_pos: Vector2) -> void:
	"""Move the ghost visual to the given world position."""
	if _scout_ghost_visual and is_instance_valid(_scout_ghost_visual):
		_scout_ghost_visual.position = world_pos

func _scout_update_ghost_validity(is_valid: bool) -> void:
	"""Update the ghost visual's validity state (green vs red)."""
	if not _scout_ghost_visual or not is_instance_valid(_scout_ghost_visual):
		return
	for child in _scout_ghost_visual.get_children():
		if child.has_method("set_validity"):
			child.set_validity(is_valid)

func _scout_update_movement_remaining_label(inches_left: float, is_valid: bool) -> void:
	"""Update the floating movement remaining label (same as MovementController._update_movement_remaining_label)."""
	if not _scout_movement_remaining_label or not is_instance_valid(_scout_movement_remaining_label):
		return
	if inches_left >= 0:
		_scout_movement_remaining_label.text = "%.1f\" left" % inches_left
	else:
		_scout_movement_remaining_label.text = "%.1f\" over!" % abs(inches_left)
	# Green when valid, orange for position invalid, red when over cap
	if is_valid and inches_left >= 0:
		_scout_movement_remaining_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 0.9))
	elif inches_left >= 0:
		_scout_movement_remaining_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1, 0.9))
	else:
		_scout_movement_remaining_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1, 0.9))

func _scout_update_path_visual(from_pos: Vector2, to_pos: Vector2, is_valid: bool) -> void:
	"""Update the path line during drag (same as MovementController._update_path_visual)."""
	if not _scout_path_visual or not is_instance_valid(_scout_path_visual):
		return
	_scout_path_visual.clear_points()
	_scout_path_visual.add_point(from_pos)
	_scout_path_visual.add_point(to_pos)
	_scout_path_visual.default_color = Color.GREEN if is_valid else Color.RED

func _scout_clear_path_visual() -> void:
	"""Clear the path line."""
	if _scout_path_visual and is_instance_valid(_scout_path_visual):
		_scout_path_visual.clear_points()

func _scout_update_staged_moves_visual() -> void:
	"""Show dashed path lines for models that have already been staged in this scout move.
	Uses HumanMovementPathVisual same as MovementController._update_movement_path_preview."""
	if not _scout_staged_path_visual or not is_instance_valid(_scout_staged_path_visual):
		return

	var phase_instance = PhaseManager.get_current_phase_instance()
	if not phase_instance or not phase_instance.get("active_scout_moves"):
		if _scout_staged_path_visual.has_method("clear_now"):
			_scout_staged_path_visual.clear_now()
		return

	var active_moves = phase_instance.active_scout_moves
	if not active_moves.has(_scout_active_unit_id):
		if _scout_staged_path_visual.has_method("clear_now"):
			_scout_staged_path_visual.clear_now()
		return

	var move_data = active_moves[_scout_active_unit_id]
	var staged_positions = move_data.get("staged_positions", {})
	var original_positions = move_data.get("original_positions", {})
	var preview_paths: Array = []

	for model_id in staged_positions:
		var orig = original_positions.get(model_id, null)
		if orig == null:
			continue
		var orig_pos = Vector2(orig.x, orig.y) if orig is Dictionary else orig
		var staged = staged_positions[model_id]
		var staged_pos = Vector2(staged.x, staged.y) if staged is Dictionary else staged

		if orig_pos.distance_to(staged_pos) > 5.0:
			var distance_inches = orig_pos.distance_to(staged_pos) / 40.0
			preview_paths.append({
				"from": orig_pos,
				"to": staged_pos,
				"distance": distance_inches
			})

	if preview_paths.is_empty():
		if _scout_staged_path_visual.has_method("clear_now"):
			_scout_staged_path_visual.clear_now()
		return

	var player = GameState.get_active_player()
	if _scout_staged_path_visual.has_method("update_planning_paths"):
		_scout_staged_path_visual.update_planning_paths(preview_paths, player, _scout_move_distance)

func _scout_handle_mouse_press(screen_pos: Vector2) -> void:
	"""Handle mouse press during scout phase - start dragging a model.
	Creates ghost visual and path line like MovementController."""
	# Check if click is on UI area
	var ui_rect = get_viewport().get_visible_rect()
	var right_hud_rect = Rect2(ui_rect.size.x - 400, 0, 400, ui_rect.size.y)
	var bottom_hud_rect = Rect2(0, ui_rect.size.y - 100, ui_rect.size.x, 100)
	if right_hud_rect.has_point(screen_pos) or bottom_hud_rect.has_point(screen_pos):
		return

	var world_pos = screen_to_world_position(screen_pos)
	var model = _scout_find_model_at_position(world_pos)
	if model.is_empty():
		return

	_scout_dragging_model = true
	_scout_drag_model_id = model.model_id
	_scout_drag_start_pos = model.position
	_scout_selected_model_data = model

	# Create visuals if needed
	_scout_create_visuals()

	# Show ghost visual at the model's current position (same as MovementController)
	_scout_show_ghost_visual(model)
	_scout_update_ghost_position(world_pos)

	print("Main: Scout drag started for model ", model.model_id, " at ", model.position)
	get_viewport().set_input_as_handled()

func _scout_handle_mouse_motion(screen_pos: Vector2) -> void:
	"""Handle mouse motion during scout phase - update ghost, path, and distance display.
	Mirrors MovementController._update_model_drag behavior."""
	if not _scout_dragging_model:
		return

	var world_pos = screen_to_world_position(screen_pos)

	# Move the visual token (same as before)
	if token_layer:
		for child in token_layer.get_children():
			if child.has_meta("unit_id") and child.get_meta("unit_id") == _scout_active_unit_id \
			   and child.has_meta("model_id") and child.get_meta("model_id") == _scout_drag_model_id:
				child.position = world_pos
				break

	# Calculate distance
	var distance_px = _scout_drag_start_pos.distance_to(world_pos)
	var distance_inches = distance_px / 40.0
	var inches_left = _scout_move_distance - distance_inches
	var is_within_range = distance_inches <= _scout_move_distance + 0.02

	# Check board bounds
	var board_width_px = GameState.state.board.size.width * 40.0
	var board_height_px = GameState.state.board.size.height * 40.0
	var out_of_bounds = world_pos.x < 0 or world_pos.x > board_width_px or world_pos.y < 0 or world_pos.y > board_height_px

	var is_valid = is_within_range and not out_of_bounds

	# Update ghost visual (same as MovementController)
	_scout_update_ghost_position(world_pos)
	_scout_update_ghost_validity(is_valid)

	# Update path line from start to cursor (same as MovementController)
	_scout_update_path_visual(_scout_drag_start_pos, world_pos, is_valid)

	# Update floating movement remaining label (same as MovementController)
	_scout_update_movement_remaining_label(inches_left, is_valid)

	# Update status bar with distance info (matches movement phase format)
	if is_valid:
		status_label.text = "Scout: %.1f\" / %d\" (%.1f\" remaining)" % [distance_inches, int(_scout_move_distance), inches_left]
	else:
		if not is_within_range:
			status_label.text = "Scout: %.1f\" exceeds %d\" range!" % [distance_inches, int(_scout_move_distance)]
		elif out_of_bounds:
			status_label.text = "Scout: Cannot move beyond the board edge"

func _scout_handle_mouse_release(screen_pos: Vector2) -> void:
	"""Handle mouse release during scout phase - commit model position.
	Validates and shows staged move visualization like MovementController."""
	if not _scout_dragging_model:
		return

	var world_pos = screen_to_world_position(screen_pos)
	_scout_dragging_model = false

	# Clear drag visuals
	_scout_clear_ghost_visual()
	_scout_clear_path_visual()

	# Send SET_SCOUT_MODEL_DEST action
	var action = {
		"type": "SET_SCOUT_MODEL_DEST",
		"unit_id": _scout_active_unit_id,
		"model_id": _scout_drag_model_id,
		"destination": {"x": world_pos.x, "y": world_pos.y},
		"player": GameState.get_active_player()
	}

	var result = NetworkIntegration.route_action(action)
	if result.get("success", false):
		print("Main: Scout model %s moved to %s" % [_scout_drag_model_id, str(world_pos)])
		status_label.text = "Scout move: Model placed. Drag more models or Confirm/Skip."
		# Update staged moves visualization (shows dashed paths for placed models)
		_scout_update_staged_moves_visual()
	else:
		# Move visual token back to original position on failure
		print("Main: Scout model move failed: ", result.get("errors", []))
		status_label.text = "Invalid: " + str(result.get("errors", ["Move rejected"]))
		if token_layer:
			for child in token_layer.get_children():
				if child.has_meta("unit_id") and child.get_meta("unit_id") == _scout_active_unit_id \
				   and child.has_meta("model_id") and child.get_meta("model_id") == _scout_drag_model_id:
					child.position = _scout_drag_start_pos
					break

	_scout_drag_model_id = ""
	_scout_selected_model_data = {}
	get_viewport().set_input_as_handled()

func _setup_scout_unit_card_buttons(unit_id: String) -> void:
	"""Configure the unit card buttons for scout move confirm/skip.
	Uses same button layout as movement phase (Confirm Move / Reset Unit)."""
	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		return

	var unit_name = unit_data.get("meta", {}).get("name", unit_id)
	var scout_dist = GameState.get_scout_distance(unit_id)
	unit_name_label.text = "%s [Scout %d\"]" % [unit_name, int(scout_dist)]
	models_label.text = "Drag models to move (up to %d\", must end >9\" from enemies)" % int(scout_dist)

	# Configure buttons (same layout as movement phase)
	confirm_button.visible = true
	confirm_button.text = "Confirm Move"
	confirm_button.disabled = false

	reset_button.visible = true
	reset_button.text = "Skip Scout"
	reset_button.disabled = false

	undo_button.visible = false

	# Disconnect any existing connections
	if confirm_button.pressed.is_connected(_on_scout_confirm_pressed):
		confirm_button.pressed.disconnect(_on_scout_confirm_pressed)
	if reset_button.pressed.is_connected(_on_scout_skip_pressed):
		reset_button.pressed.disconnect(_on_scout_skip_pressed)

	# Connect to scout-specific handlers
	confirm_button.pressed.connect(_on_scout_confirm_pressed)
	reset_button.pressed.connect(_on_scout_skip_pressed)

	unit_card.visible = true

func _on_scout_confirm_pressed() -> void:
	"""Confirm the scout move for the active unit.
	Shows confirmed path visual before cleanup (same as MovementController)."""
	if _scout_active_unit_id == "":
		return

	# Show confirmed movement paths before cleanup (same as MovementController._show_confirmed_movement_paths)
	_scout_show_confirmed_paths()

	var action = {
		"type": "CONFIRM_SCOUT_MOVE",
		"unit_id": _scout_active_unit_id,
		"player": GameState.get_active_player()
	}

	var result = NetworkIntegration.route_action(action)
	if result.get("success", false):
		print("Main: Scout move confirmed for ", _scout_active_unit_id)
		_scout_cleanup_after_move()
		_recreate_unit_visuals()
		refresh_unit_list()
		status_label.text = "Scout move confirmed. Select next unit."
	else:
		print("Main: Scout confirm failed: ", result.get("errors", []))
		status_label.text = "Error: " + str(result.get("errors", ["Confirm failed"]))

func _scout_show_confirmed_paths() -> void:
	"""Show confirmed movement paths (hold + fade) for the scout move that was just confirmed.
	Same as MovementController._show_confirmed_movement_paths."""
	var phase_instance = PhaseManager.get_current_phase_instance()
	if not phase_instance or not phase_instance.get("active_scout_moves"):
		return

	var active_moves = phase_instance.active_scout_moves
	if not active_moves.has(_scout_active_unit_id):
		return

	var move_data = active_moves[_scout_active_unit_id]
	var staged_positions = move_data.get("staged_positions", {})
	var original_positions = move_data.get("original_positions", {})
	var confirmed_paths: Array = []

	for model_id in staged_positions:
		var orig = original_positions.get(model_id, null)
		if orig == null:
			continue
		var from_pos = Vector2(orig.x, orig.y) if orig is Dictionary else orig
		var staged = staged_positions[model_id]
		var to_pos = Vector2(staged.x, staged.y) if staged is Dictionary else staged

		if from_pos.distance_to(to_pos) > 5.0:
			confirmed_paths.append({"from": from_pos, "to": to_pos})

	if confirmed_paths.is_empty():
		return

	var board_root = get_node_or_null("BoardRoot")
	if not board_root:
		return

	var HumanMovementPathVisualScript = preload("res://scripts/HumanMovementPathVisual.gd")
	var confirmed_visual = Node2D.new()
	confirmed_visual.set_script(HumanMovementPathVisualScript)
	confirmed_visual.name = "ScoutMovementConfirmed_%d" % (randi() % 10000)
	board_root.add_child(confirmed_visual)
	confirmed_visual.show_confirmed_paths(confirmed_paths, GameState.get_active_player())

func _on_scout_skip_pressed() -> void:
	"""Skip the scout move for the active unit."""
	if _scout_active_unit_id == "":
		return

	var action = {
		"type": "SKIP_SCOUT_MOVE",
		"unit_id": _scout_active_unit_id,
		"player": GameState.get_active_player()
	}

	var result = NetworkIntegration.route_action(action)
	if result.get("success", false):
		print("Main: Scout move skipped for ", _scout_active_unit_id)
		_scout_cleanup_after_move()
		_recreate_unit_visuals()
		refresh_unit_list()
		status_label.text = "Scout move skipped. Select next unit."
	else:
		print("Main: Scout skip failed: ", result.get("errors", []))
		status_label.text = "Error: " + str(result.get("errors", ["Skip failed"]))

func _scout_cleanup_after_move() -> void:
	"""Clean up scout state after a move is confirmed or skipped."""
	# Disconnect button signals
	if confirm_button.pressed.is_connected(_on_scout_confirm_pressed):
		confirm_button.pressed.disconnect(_on_scout_confirm_pressed)
	if reset_button.pressed.is_connected(_on_scout_skip_pressed):
		reset_button.pressed.disconnect(_on_scout_skip_pressed)

	# Clear all visual elements
	_scout_clear_highlights()
	_scout_clear_ghost_visual()
	_scout_clear_path_visual()
	# Clear staged paths visual
	if _scout_staged_path_visual and is_instance_valid(_scout_staged_path_visual) and _scout_staged_path_visual.has_method("clear_now"):
		_scout_staged_path_visual.clear_now()

	_scout_active_unit_id = ""
	_scout_dragging_model = false
	_scout_drag_model_id = ""
	_scout_move_distance = 0.0
	_scout_selected_model_data = {}

func _scout_reset_previous_unit(previous_unit_id: String) -> void:
	"""Reset the previous scout unit's active move when selecting a different unit.
	Restores any dragged models to their original positions and cleans up phase state."""
	print("Main: Resetting previous scout unit: ", previous_unit_id)

	# Restore any visually dragged models to their original positions
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance and phase_instance.get("active_scout_moves"):
		var active_moves = phase_instance.active_scout_moves
		if active_moves.has(previous_unit_id):
			var move_data = active_moves[previous_unit_id]
			var original_positions = move_data.get("original_positions", {})
			# Restore visual token positions
			if token_layer:
				for child in token_layer.get_children():
					if child.has_meta("unit_id") and child.get_meta("unit_id") == previous_unit_id:
						var model_id = child.get_meta("model_id") if child.has_meta("model_id") else ""
						if original_positions.has(model_id):
							var orig = original_positions[model_id]
							child.position = Vector2(orig.x, orig.y)
			# Remove the active move entry so BEGIN_SCOUT_MOVE can succeed again
			active_moves.erase(previous_unit_id)

	# Clean up all visual state
	_scout_clear_highlights()
	_scout_clear_ghost_visual()
	_scout_clear_path_visual()
	if _scout_staged_path_visual and is_instance_valid(_scout_staged_path_visual) and _scout_staged_path_visual.has_method("clear_now"):
		_scout_staged_path_visual.clear_now()
	_scout_dragging_model = false
	_scout_drag_model_id = ""
	_scout_selected_model_data = {}

func _scout_highlight_active_unit(unit_id: String, scout_distance: float) -> void:
	"""Highlight the active scout unit's models and show movement range circles.
	Uses set_selected() for the pulsing gold ring (same as MovementController._highlight_unit_models)
	and creates range circles matching the movement phase style."""
	if not token_layer:
		return

	# Clear any existing scout highlights first
	_scout_clear_highlights()

	# Create visuals if needed
	_scout_create_visuals()

	var range_px = scout_distance * 40.0  # PX_PER_INCH = 40.0

	for child in token_layer.get_children():
		if not child.has_meta("unit_id") or child.get_meta("unit_id") != unit_id:
			continue

		# Use set_selected for the pulsing gold ring (same as MovementController)
		if child.has_method("set_selected"):
			child.set_selected(true)
			child.set_meta("scout_was_selected", true)

		# Add a movement range circle around each model (improved style)
		var range_circle = _scout_create_range_circle(range_px)
		range_circle.set_meta("scout_highlight", true)
		child.add_child(range_circle)

func _scout_create_range_circle(radius_px: float) -> Node2D:
	"""Create a visual circle showing scout movement range.
	Uses a dashed circle with fill matching movement phase style."""
	var container = Node2D.new()
	container.set_meta("scout_highlight", true)
	container.z_index = -1  # Draw behind models

	# Determine player color (same scheme as movement phase)
	var player = GameState.get_active_player()
	var circle_color: Color
	var fill_color: Color
	if player == 1:
		circle_color = Color(0.3, 0.6, 1.0, 0.6)  # Blue for P1
		fill_color = Color(0.3, 0.6, 1.0, 0.08)
	else:
		circle_color = Color(1.0, 0.3, 0.3, 0.6)  # Red for P2
		fill_color = Color(1.0, 0.3, 0.3, 0.08)

	# Create semi-transparent fill circle
	var fill_polygon = Polygon2D.new()
	fill_polygon.set_meta("scout_highlight", true)
	var fill_points = PackedVector2Array()
	var point_count = 64
	for i in range(point_count):
		var angle = (float(i) / point_count) * TAU
		fill_points.append(Vector2(cos(angle) * radius_px, sin(angle) * radius_px))
	fill_polygon.polygon = fill_points
	fill_polygon.color = fill_color
	container.add_child(fill_polygon)

	# Create dashed circle outline using Line2D segments
	var dash_length_deg = 5.0  # degrees per dash
	var gap_length_deg = 3.0   # degrees per gap
	var segment_deg = dash_length_deg + gap_length_deg
	var angle_deg = 0.0
	while angle_deg < 360.0:
		var dash_line = Line2D.new()
		dash_line.width = 2.0
		dash_line.default_color = circle_color
		dash_line.set_meta("scout_highlight", true)
		var start_rad = deg_to_rad(angle_deg)
		var end_rad = deg_to_rad(min(angle_deg + dash_length_deg, 360.0))
		var steps = max(2, int((end_rad - start_rad) / (TAU / 64.0)) + 1)
		for i in range(steps + 1):
			var t = float(i) / float(steps)
			var a = lerp(start_rad, end_rad, t)
			dash_line.add_point(Vector2(cos(a) * radius_px, sin(a) * radius_px))
		container.add_child(dash_line)
		angle_deg += segment_deg

	return container

func _scout_clear_highlights() -> void:
	"""Remove all scout movement range highlights and model selection."""
	if not token_layer:
		return

	for child in token_layer.get_children():
		# Deselect models (remove pulsing gold ring)
		if child.has_meta("scout_was_selected"):
			if child.has_method("set_selected"):
				child.set_selected(false)
			child.remove_meta("scout_was_selected")

		# Remove range circle children
		var to_remove = []
		for subchild in child.get_children():
			if subchild.has_meta("scout_highlight"):
				to_remove.append(subchild)
		for node in to_remove:
			node.queue_free()

# ============================================================================
# P3-111: In-game Settings Menu (Escape key)
# ============================================================================

func _unhandled_input(_event: InputEvent) -> void:
	pass

func _on_settings_menu_closed() -> void:
	_settings_menu = null
	print("Main: Settings menu closed")

func _on_settings_save_load_requested() -> void:
	_settings_menu = null
	if save_load_dialog:
		save_load_dialog.show_dialog()
		print("Main: Save/Load dialog opened from settings menu")
