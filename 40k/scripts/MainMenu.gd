extends Control

# MainMenu - Entry point for the game, allows configuration of mission and armies

@onready var terrain_dropdown: OptionButton = $MenuContainer/MissionSection/TerrainContainer/TerrainDropdown
@onready var mission_dropdown: OptionButton = $MenuContainer/MissionSection/MissionContainer/MissionDropdown
@onready var deployment_dropdown: OptionButton = $MenuContainer/MissionSection/DeploymentContainer/DeploymentDropdown
@onready var player1_type_dropdown: OptionButton = $MenuContainer/ArmySection/Player1TypeContainer/Player1TypeDropdown
@onready var player1_dropdown: OptionButton = $MenuContainer/ArmySection/Player1Container/Player1Dropdown
@onready var player2_type_dropdown: OptionButton = $MenuContainer/ArmySection/Player2TypeContainer/Player2TypeDropdown
@onready var player2_dropdown: OptionButton = $MenuContainer/ArmySection/Player2Container/Player2Dropdown
@onready var start_button: Button = $MenuContainer/ButtonSection/StartButton
@onready var multiplayer_button: Button = $MenuContainer/ButtonSection/MultiplayerButton
@onready var load_button: Button = $MenuContainer/ButtonSection/LoadButton
@onready var replay_button: Button = $MenuContainer/ButtonSection/ReplayButton

# Configuration options
var terrain_options = [
	{"id": "layout_1", "name": "Chapter Approved Layout 1"},
	{"id": "layout_2", "name": "Chapter Approved Layout 2"},
	{"id": "layout_3", "name": "Chapter Approved Layout 3"},
	{"id": "layout_4", "name": "Chapter Approved Layout 4"},
	{"id": "layout_5", "name": "Chapter Approved Layout 5"},
	{"id": "layout_6", "name": "Chapter Approved Layout 6"},
	{"id": "layout_7", "name": "Chapter Approved Layout 7"},
	{"id": "layout_8", "name": "Chapter Approved Layout 8"}
]

var mission_options = [
	{"id": "take_and_hold", "name": "Take and Hold"}
	# Future: Add more missions
]

var deployment_options = [
	{"id": "hammer_anvil", "name": "Hammer and Anvil"},
	{"id": "dawn_of_war", "name": "Dawn of War"},
	{"id": "search_and_destroy", "name": "Search and Destroy"},
	{"id": "sweeping_engagement", "name": "Sweeping Engagement"},
	{"id": "crucible_of_battle", "name": "Crucible of Battle"}
]

# Army options - dynamically populated from ArmyListManager
var army_options = []

var save_load_dialog: AcceptDialog

# Cloud army loading state
var _waiting_for_cloud_armies: bool = false
var _cloud_army_fetch_pending: bool = false
var _pending_game_config: Dictionary = {}
var _cloud_fetch_count: int = 0  # How many cloud armies still need fetching

func _ready() -> void:
	print("MainMenu: Initializing main menu")
	_setup_dropdowns()
	_connect_signals()
	_setup_save_load_dialog()

	# Set defaults
	terrain_dropdown.selected = 0
	mission_dropdown.selected = 0
	deployment_dropdown.selected = 0

	# Set default army selections based on available armies
	_set_default_army_selections()

	# Fetch cloud armies asynchronously
	_load_cloud_armies()

	print("MainMenu: Ready with default selections")

func _setup_dropdowns() -> void:
	# Populate terrain dropdown
	for option in terrain_options:
		terrain_dropdown.add_item(option.name)

	# Populate mission dropdown
	for option in mission_options:
		mission_dropdown.add_item(option.name)

	# Populate deployment dropdown
	for option in deployment_options:
		deployment_dropdown.add_item(option.name)

	# Populate player type dropdowns (Human / AI)
	player1_type_dropdown.add_item("Human")
	player1_type_dropdown.add_item("AI")
	player1_type_dropdown.selected = 0  # Default: Human
	player2_type_dropdown.add_item("Human")
	player2_type_dropdown.add_item("AI")
	player2_type_dropdown.selected = 1  # Default: AI (most common single-player setup)

	# Dynamically populate army dropdowns from ArmyListManager
	_load_available_armies()
	for option in army_options:
		player1_dropdown.add_item(option.name)
		player2_dropdown.add_item(option.name)

	print("MainMenu: Dropdowns populated with ", army_options.size(), " armies")

func _load_available_armies() -> void:
	# Dynamically load available armies from ArmyListManager
	army_options.clear()

	if not ArmyListManager:
		print("MainMenu: Warning - ArmyListManager not available, using empty army list")
		return

	var available_armies = ArmyListManager.get_available_armies()

	if available_armies.is_empty():
		print("MainMenu: Warning - No armies found in armies/ directory")
		# Add a fallback option
		army_options.append({"id": "placeholder", "name": "No Armies Available"})
		return

	# Convert army IDs to display names
	for army_id in available_armies:
		var display_name = _format_army_name(army_id)
		army_options.append({"id": army_id, "name": display_name})

	# Sort armies alphabetically by display name
	army_options.sort_custom(func(a, b): return a.name < b.name)

	print("MainMenu: Loaded ", army_options.size(), " armies: ", army_options.map(func(a): return a.name))

func _format_army_name(army_id: String) -> String:
	# Convert army_id (e.g., "adeptus_custodes") to display name (e.g., "Adeptus Custodes")
	var words = army_id.split("_")
	var formatted_words = []

	for word in words:
		if word.is_empty():
			continue
		# Capitalize first letter of each word
		var capitalized = word[0].to_upper() + word.substr(1)
		formatted_words.append(capitalized)

	return " ".join(formatted_words)

func _set_default_army_selections() -> void:
	# Set intelligent defaults for army selections
	if army_options.is_empty():
		return

	# Try to find specific armies for defaults
	var player1_index = 0
	var player2_index = min(1, army_options.size() - 1)  # Different army if possible

	# Prefer A_C_test for Player 1 if available
	for i in range(army_options.size()):
		if army_options[i].id == "A_C_test":
			player1_index = i
			break

	# Prefer ORK_test for Player 2 if available
	for i in range(army_options.size()):
		if army_options[i].id == "ORK_test":
			player2_index = i
			break

	# Ensure players have different armies if possible
	if player1_index == player2_index and army_options.size() > 1:
		player2_index = (player1_index + 1) % army_options.size()

	player1_dropdown.selected = player1_index
	player2_dropdown.selected = player2_index

	print("MainMenu: Default armies set - Player 1: ", army_options[player1_index].name, ", Player 2: ", army_options[player2_index].name)

# ============================================================================
# Cloud Army Integration
# ============================================================================

func _load_cloud_armies() -> void:
	if not ArmyListManager:
		return
	ArmyListManager.cloud_armies_loaded.connect(_on_cloud_armies_loaded)
	ArmyListManager.cloud_army_fetched.connect(_on_cloud_army_fetched)
	ArmyListManager.cloud_army_fetch_failed.connect(_on_cloud_army_fetch_failed)
	ArmyListManager.load_cloud_armies()

func _on_cloud_armies_loaded(cloud_armies: Array) -> void:
	if cloud_armies.is_empty():
		print("MainMenu: No cloud armies available")
		return

	# Save current selections before modifying dropdowns
	var p1_selected_id = ""
	var p2_selected_id = ""
	if player1_dropdown.selected >= 0 and player1_dropdown.selected < army_options.size():
		p1_selected_id = army_options[player1_dropdown.selected].id
	if player2_dropdown.selected >= 0 and player2_dropdown.selected < army_options.size():
		p2_selected_id = army_options[player2_dropdown.selected].id

	# Add cloud armies that aren't already available locally
	var local_ids = available_armies_ids()
	var added_count = 0
	for cloud_name in cloud_armies:
		if cloud_name not in local_ids:
			var display_name = _format_army_name(cloud_name) + " (Cloud)"
			army_options.append({"id": cloud_name, "name": display_name, "source": "cloud"})
			player1_dropdown.add_item(display_name)
			player2_dropdown.add_item(display_name)
			added_count += 1

	if added_count > 0:
		print("MainMenu: Added %d cloud armies to dropdowns" % added_count)

		# Restore selections
		_restore_dropdown_selection(player1_dropdown, p1_selected_id)
		_restore_dropdown_selection(player2_dropdown, p2_selected_id)

func available_armies_ids() -> Array:
	var ids = []
	for option in army_options:
		if option.get("source", "local") == "local":
			ids.append(option.id)
	return ids

func _restore_dropdown_selection(dropdown: OptionButton, army_id: String) -> void:
	for i in range(army_options.size()):
		if army_options[i].id == army_id:
			dropdown.selected = i
			return

func _is_cloud_selection(army_id: String) -> bool:
	return ArmyListManager and ArmyListManager.is_cloud_army(army_id)

func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)
	replay_button.pressed.connect(_on_replay_button_pressed)

	# Show/hide multiplayer button based on feature flag
	multiplayer_button.visible = FeatureFlags.is_multiplayer_available()
	print("MainMenu: Multiplayer button visible: ", multiplayer_button.visible)

	print("MainMenu: Signals connected")

func _setup_save_load_dialog() -> void:
	# Create save/load dialog
	var dialog_scene = load("res://scenes/SaveLoadDialog.tscn")
	if dialog_scene:
		save_load_dialog = dialog_scene.instantiate()
		add_child(save_load_dialog)
		save_load_dialog.load_requested.connect(_on_load_requested)
		print("MainMenu: Save/Load dialog setup complete")
	else:
		print("MainMenu: Warning - Could not load SaveLoadDialog.tscn")

func _on_start_button_pressed() -> void:
	print("MainMenu: Start button pressed")

	# Validate selections (ensure different armies if desired)
	if player1_dropdown.selected == player2_dropdown.selected:
		print("MainMenu: Warning - Both players have the same army selected")
		# For now, allow it but warn

	# Store configuration in GameState
	var p1_type = "AI" if player1_type_dropdown.selected == 1 else "HUMAN"
	var p2_type = "AI" if player2_type_dropdown.selected == 1 else "HUMAN"
	var config = {
		"terrain": terrain_options[terrain_dropdown.selected].id,
		"mission": mission_options[mission_dropdown.selected].id,
		"deployment": deployment_options[deployment_dropdown.selected].id,
		"player1_army": army_options[player1_dropdown.selected].id,
		"player2_army": army_options[player2_dropdown.selected].id,
		"player1_type": p1_type,
		"player2_type": p2_type
	}

	print("MainMenu: Starting game with config: ", config)

	# Check if any selected armies are cloud armies that need fetching
	var p1_is_cloud = _is_cloud_selection(config.player1_army)
	var p2_is_cloud = _is_cloud_selection(config.player2_army)

	if p1_is_cloud or p2_is_cloud:
		# Need to download cloud armies before starting
		start_button.disabled = true
		start_button.text = "Downloading armies..."
		_pending_game_config = config
		_cloud_fetch_count = 0

		if p1_is_cloud:
			_cloud_fetch_count += 1
			print("MainMenu: Fetching cloud army for Player 1: ", config.player1_army)
			ArmyListManager.fetch_cloud_army(config.player1_army, 1)

		if p2_is_cloud:
			_cloud_fetch_count += 1
			print("MainMenu: Fetching cloud army for Player 2: ", config.player2_army)
			ArmyListManager.fetch_cloud_army(config.player2_army, 2)
		return

	# No cloud armies - proceed immediately
	_initialize_game_with_config(config)

	# Transition to main game scene
	print("MainMenu: Transitioning to Main scene")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_cloud_army_fetched(_army_name: String, _army_data: Dictionary) -> void:
	_cloud_fetch_count -= 1
	print("MainMenu: Cloud army fetched, remaining: ", _cloud_fetch_count)

	if _cloud_fetch_count <= 0 and not _pending_game_config.is_empty():
		# All cloud armies downloaded, proceed with game start
		start_button.text = "Start Game"
		start_button.disabled = false

		var config = _pending_game_config
		_pending_game_config = {}
		_initialize_game_with_config(config)

		print("MainMenu: Transitioning to Main scene")
		get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_cloud_army_fetch_failed(army_name: String, error: String) -> void:
	print("MainMenu: Failed to download cloud army '%s': %s" % [army_name, error])
	_cloud_fetch_count = 0
	_pending_game_config = {}
	start_button.text = "Start Game"
	start_button.disabled = false

func _initialize_game_with_config(config: Dictionary) -> void:
	print("MainMenu: Initializing game state with configuration")
	
	# Clear any existing state first
	GameState.state.clear()

	# Initialize base game state with selected deployment type
	GameState.initialize_default_state(config.deployment)
	
	# Apply terrain configuration
	if TerrainManager:
		TerrainManager.current_layout = config.terrain
		TerrainManager.load_terrain_layout(config.terrain)
		print("MainMenu: Terrain layout set to: ", config.terrain)
	
	# Initialize BoardState deployment zones to match selected deployment
	if BoardState:
		BoardState.initialize_deployment_zones(config.deployment)

	# Apply mission configuration (MissionManager will use default "Take and Hold" for now)
	# Future: Add mission configuration when more missions are available
	
	# Clear existing units before loading new armies
	GameState.state.units.clear()

	# Load Player 1 army (supports both local and cached cloud armies)
	if ArmyListManager:
		var player1_army = ArmyListManager.load_army_for_game(config.player1_army, 1)
		if not player1_army.is_empty():
			ArmyListManager.apply_army_to_game_state(player1_army, 1)
			print("MainMenu: Loaded ", config.player1_army, " for Player 1")
		else:
			print("MainMenu: Failed to load army for Player 1, using placeholder")
			GameState._initialize_placeholder_armies_player(1)

		# Load Player 2 army
		var player2_army = ArmyListManager.load_army_for_game(config.player2_army, 2)
		if not player2_army.is_empty():
			ArmyListManager.apply_army_to_game_state(player2_army, 2)
			print("MainMenu: Loaded ", config.player2_army, " for Player 2")
		else:
			print("MainMenu: Failed to load army for Player 2, using placeholder")
			GameState._initialize_placeholder_armies_player(2)
	else:
		print("MainMenu: ArmyListManager not available, using placeholder armies")
		GameState._initialize_placeholder_armies()
	
	# Store configuration in game state for reference
	GameState.state.meta["game_config"] = config
	GameState.state.meta["from_menu"] = true
	
	print("MainMenu: Game initialization complete. Total units: ", GameState.state.units.size())

func _on_multiplayer_button_pressed() -> void:
	print("MainMenu: Multiplayer button pressed")
	# Transition to multiplayer lobby
	get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")

func _on_load_button_pressed() -> void:
	print("MainMenu: Load button pressed")
	if save_load_dialog:
		save_load_dialog.popup_centered(Vector2(600, 400))
	else:
		print("MainMenu: Error - Save/Load dialog not available")

func _on_load_requested(save_file: String, owner_id: String = "") -> void:
	print("MainMenu: Load requested for file: ", save_file, " (owner_id: ", owner_id, ")")

	# Check if we're in multiplayer (shouldn't be from main menu, but safety check)
	if NetworkManager and NetworkManager.is_networked():
		print("MainMenu: Cannot load during active multiplayer session")
		return

	if not SaveLoadManager:
		print("MainMenu: SaveLoadManager not available")
		return

	if OS.has_feature("web"):
		# Web: async load - connect to signals, then trigger load
		if not SaveLoadManager.load_completed.is_connected(_on_cloud_load_completed):
			SaveLoadManager.load_completed.connect(_on_cloud_load_completed)
		if not SaveLoadManager.load_failed.is_connected(_on_cloud_load_failed):
			SaveLoadManager.load_failed.connect(_on_cloud_load_failed)
		SaveLoadManager.load_game(save_file, owner_id)
		print("MainMenu: Initiated async cloud load for: ", save_file)
	else:
		# Desktop: synchronous load
		var success = SaveLoadManager.load_game(save_file, owner_id)
		if success:
			print("MainMenu: Successfully loaded game: ", save_file)
			if GameState.state.meta:
				GameState.state.meta["from_save"] = true
				GameState.state.meta.erase("from_menu")
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
		else:
			print("MainMenu: Failed to load game: ", save_file)

func _on_cloud_load_completed(file_path: String, metadata: Dictionary) -> void:
	print("MainMenu: Cloud load completed: ", file_path)
	# Mark that we're loading from a save
	if GameState.state.meta:
		GameState.state.meta["from_save"] = true
		GameState.state.meta.erase("from_menu")
	# Transition to main game scene
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_cloud_load_failed(error: String) -> void:
	print("MainMenu: Cloud load failed: ", error)

# ============================================================================
# Replay Browser
# ============================================================================

var replay_dialog: AcceptDialog = null

func _on_replay_button_pressed() -> void:
	print("MainMenu: Replay button pressed")
	_show_replay_browser()

func _show_replay_browser() -> void:
	"""Show a dialog listing available replays."""
	if not ReplayManager:
		print("MainMenu: ReplayManager not available")
		return

	var replays = ReplayManager.get_available_replays()
	print("MainMenu: Found %d replays" % replays.size())

	# Create or reuse dialog
	if replay_dialog and is_instance_valid(replay_dialog):
		replay_dialog.queue_free()

	replay_dialog = AcceptDialog.new()
	replay_dialog.title = "Watch Replays"
	replay_dialog.ok_button_text = "Close"
	replay_dialog.min_size = Vector2(650, 450)
	add_child(replay_dialog)

	# Build content
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 380)
	replay_dialog.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	if replays.is_empty():
		var no_replays_label = Label.new()
		no_replays_label.text = "No replays found.\n\nReplays are automatically saved during AI vs AI games.\nYou can also start recording from the game manually."
		no_replays_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(no_replays_label)
	else:
		for replay_entry in replays:
			var meta = replay_entry.get("meta", {})
			var file_path = replay_entry.get("file_path", "")

			# Create a row for each replay
			var row = PanelContainer.new()
			var row_style = StyleBoxFlat.new()
			row_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
			row_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
			row_style.border_width_bottom = 1
			row_style.content_margin_left = 10
			row_style.content_margin_right = 10
			row_style.content_margin_top = 8
			row_style.content_margin_bottom = 8
			row.add_theme_stylebox_override("panel", row_style)
			vbox.add_child(row)

			var hbox = HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 12)
			row.add_child(hbox)

			# Info column
			var info_vbox = VBoxContainer.new()
			info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(info_vbox)

			# Title: factions
			var p1_faction = meta.get("player1_faction", "Player 1")
			var p2_faction = meta.get("player2_faction", "Player 2")
			var title_label = Label.new()
			title_label.text = "%s vs %s" % [p1_faction, p2_faction]
			title_label.add_theme_font_size_override("font_size", 16)
			info_vbox.add_child(title_label)

			# Subtitle: date, rounds, score
			var created_at = meta.get("created_at", 0)
			var date_str = _format_timestamp(created_at)
			var final_round = meta.get("final_round", "?")
			var final_score = meta.get("final_score", {})
			var p1_vp = final_score.get("p1_vp", 0)
			var p2_vp = final_score.get("p2_vp", 0)
			var total_events = meta.get("total_events", 0)
			var p1_type = meta.get("player1_type", "?")
			var p2_type = meta.get("player2_type", "?")

			var replay_status = meta.get("status", "complete")
			var status_label = "[Complete]" if replay_status == "complete" else "[In Progress]"

			var subtitle = Label.new()
			subtitle.text = "%s %s | %s vs %s | Round %s | Score: %d-%d | %d events" % [
				status_label, date_str, p1_type, p2_type, str(final_round), p1_vp, p2_vp, total_events]
			subtitle.add_theme_font_size_override("font_size", 12)
			var subtitle_color = Color(0.6, 0.6, 0.6) if replay_status == "complete" else Color(0.8, 0.7, 0.3)
			subtitle.add_theme_color_override("font_color", subtitle_color)
			info_vbox.add_child(subtitle)

			# Watch button
			var watch_btn = Button.new()
			watch_btn.text = "Watch"
			watch_btn.custom_minimum_size = Vector2(80, 35)
			watch_btn.pressed.connect(_on_replay_selected.bind(file_path))
			hbox.add_child(watch_btn)

			# Delete button
			var delete_btn = Button.new()
			delete_btn.text = "X"
			delete_btn.custom_minimum_size = Vector2(35, 35)
			delete_btn.tooltip_text = "Delete replay"
			delete_btn.pressed.connect(_on_replay_delete.bind(file_path))
			hbox.add_child(delete_btn)

	replay_dialog.popup_centered()

func _on_replay_selected(file_path: String) -> void:
	"""Load a replay and start playback."""
	print("MainMenu: Loading replay: %s" % file_path)

	if not ReplayManager:
		print("MainMenu: ReplayManager not available")
		return

	# Load the replay file
	var success = ReplayManager.load_replay_from_file(file_path)
	if not success:
		print("MainMenu: Failed to load replay: %s" % file_path)
		return

	# Apply the initial state to GameState
	ReplayManager.apply_initial_state()

	# Mark that we're entering replay mode
	GameState.state.meta["from_replay"] = true
	GameState.state.meta.erase("from_menu")
	GameState.state.meta.erase("from_save")

	# Close dialog and transition to Main scene in replay mode
	if replay_dialog:
		replay_dialog.hide()

	print("MainMenu: Transitioning to replay mode")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_replay_delete(file_path: String) -> void:
	"""Delete a replay file and refresh the browser."""
	print("MainMenu: Deleting replay: %s" % file_path)
	if ReplayManager:
		ReplayManager.delete_replay(file_path)
	# Refresh the dialog
	_show_replay_browser()

func _format_timestamp(unix_time: float) -> String:
	"""Format a Unix timestamp to a readable date string."""
	if unix_time <= 0:
		return "Unknown date"
	var dt = Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]