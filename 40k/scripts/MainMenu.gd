extends Control

# MainMenu - Entry point for the game, allows configuration of mission and armies

@onready var terrain_dropdown: OptionButton = $MenuContainer/MissionSection/TerrainContainer/TerrainDropdown
@onready var mission_dropdown: OptionButton = $MenuContainer/MissionSection/MissionContainer/MissionDropdown
@onready var deployment_dropdown: OptionButton = $MenuContainer/MissionSection/DeploymentContainer/DeploymentDropdown
@onready var player1_dropdown: OptionButton = $MenuContainer/ArmySection/Player1Container/Player1Dropdown
@onready var player2_dropdown: OptionButton = $MenuContainer/ArmySection/Player2Container/Player2Dropdown
@onready var start_button: Button = $MenuContainer/ButtonSection/StartButton
@onready var multiplayer_button: Button = $MenuContainer/ButtonSection/MultiplayerButton
@onready var load_button: Button = $MenuContainer/ButtonSection/LoadButton

# Configuration options
var terrain_options = [
	{"id": "layout_2", "name": "Chapter Approved Layout 2"}
	# Future: Add more layouts
]

var mission_options = [
	{"id": "take_and_hold", "name": "Take and Hold"}
	# Future: Add more missions
]

var deployment_options = [
	{"id": "hammer_anvil", "name": "Hammer and Anvil"}
	# Future: Add Dawn of War, Search and Destroy, etc.
]

var army_options = [
	{"id": "adeptus_custodes", "name": "Adeptus Custodes"},
	{"id": "space_marines", "name": "Space Marines"},
	{"id": "orks", "name": "Orks"}
]

var save_load_dialog: AcceptDialog

func _ready() -> void:
	print("MainMenu: Initializing main menu")
	_setup_dropdowns()
	_connect_signals()
	_setup_save_load_dialog()
	
	# Set defaults
	terrain_dropdown.selected = 0
	mission_dropdown.selected = 0
	deployment_dropdown.selected = 0
	player1_dropdown.selected = 0  # Custodes
	player2_dropdown.selected = 2  # Orks
	
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
	
	# Populate army dropdowns
	for option in army_options:
		player1_dropdown.add_item(option.name)
		player2_dropdown.add_item(option.name)
	
	print("MainMenu: Dropdowns populated")

func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)

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
	var config = {
		"terrain": terrain_options[terrain_dropdown.selected].id,
		"mission": mission_options[mission_dropdown.selected].id,
		"deployment": deployment_options[deployment_dropdown.selected].id,
		"player1_army": army_options[player1_dropdown.selected].id,
		"player2_army": army_options[player2_dropdown.selected].id
	}
	
	print("MainMenu: Starting game with config: ", config)
	
	# Initialize game with configuration
	_initialize_game_with_config(config)
	
	# Transition to main game scene
	print("MainMenu: Transitioning to Main scene")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _initialize_game_with_config(config: Dictionary) -> void:
	print("MainMenu: Initializing game state with configuration")
	
	# Clear any existing state first
	GameState.state.clear()
	
	# Initialize base game state
	GameState.initialize_default_state()
	
	# Apply terrain configuration
	if TerrainManager:
		TerrainManager.current_layout = config.terrain
		TerrainManager.load_terrain_layout(config.terrain)
		print("MainMenu: Terrain layout set to: ", config.terrain)
	
	# Apply mission configuration (MissionManager will use default "Take and Hold" for now)
	# Future: Add mission configuration when more missions are available
	
	# Clear existing units before loading new armies
	GameState.state.units.clear()
	
	# Load Player 1 army
	if ArmyListManager:
		var player1_army = ArmyListManager.load_army_list(config.player1_army, 1)
		if not player1_army.is_empty():
			ArmyListManager.apply_army_to_game_state(player1_army, 1)
			print("MainMenu: Loaded ", config.player1_army, " for Player 1")
		else:
			print("MainMenu: Failed to load army for Player 1, using placeholder")
			GameState._initialize_placeholder_armies_player(1)
	
		# Load Player 2 army
		var player2_army = ArmyListManager.load_army_list(config.player2_army, 2)
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

func _on_load_requested(save_file: String) -> void:
	print("MainMenu: Load requested for file: ", save_file)

	# Check if we're in multiplayer (shouldn't be from main menu, but safety check)
	if NetworkManager and NetworkManager.is_networked():
		print("MainMenu: Cannot load during active multiplayer session")
		# Could show error dialog here
		return

	if SaveLoadManager:
		var success = SaveLoadManager.load_game(save_file)
		if success:
			print("MainMenu: Successfully loaded game: ", save_file)
			# Mark that we're loading from a save, not from menu config
			if GameState.state.meta:
				GameState.state.meta["from_save"] = true
				GameState.state.meta.erase("from_menu")
			# Transition to main game scene
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
		else:
			print("MainMenu: Failed to load game: ", save_file)
			# Could show an error dialog here
	else:
		print("MainMenu: SaveLoadManager not available")