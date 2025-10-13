extends Control

# MultiplayerLobby - UI for hosting/joining multiplayer games

# UI References
@onready var host_button: Button = $LobbyContainer/ModeSelection/ButtonsContainer/HostButton
@onready var join_button: Button = $LobbyContainer/ModeSelection/ButtonsContainer/JoinButton
@onready var port_input: LineEdit = $LobbyContainer/ConnectionSettings/PortContainer/PortInput
@onready var ip_input: LineEdit = $LobbyContainer/ConnectionSettings/IPContainer/IPInput
@onready var status_label: Label = $LobbyContainer/StatusSection/StatusLabel
@onready var info_label: Label = $LobbyContainer/StatusSection/InfoLabel
@onready var player_list_label: Label = $LobbyContainer/StatusSection/PlayerListLabel
@onready var start_game_button: Button = $LobbyContainer/ActionButtons/StartGameButton
@onready var disconnect_button: Button = $LobbyContainer/ActionButtons/DisconnectButton
@onready var back_button: Button = $LobbyContainer/ActionButtons/BackButton

# Army selection UI
@onready var player1_dropdown: OptionButton = $LobbyContainer/ArmySelection/Player1Container/Player1Dropdown
@onready var player2_dropdown: OptionButton = $LobbyContainer/ArmySelection/Player2Container/Player2Dropdown

# State
var is_hosting: bool = false
var connected_players: int = 0

# Army configuration
var army_options: Array = []
var selected_player1_army: String = "A_C_test"
var selected_player2_army: String = "ORK_test"

func _ready() -> void:
	# Check if multiplayer is enabled
	if not FeatureFlags.is_multiplayer_available():
		status_label.text = "Status: Multiplayer Disabled"
		info_label.text = "Enable MULTIPLAYER_ENABLED in FeatureFlags.gd"
		host_button.disabled = true
		join_button.disabled = true
		return

	# Connect UI signals
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	disconnect_button.pressed.connect(_on_disconnect_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

	# Connect NetworkManager signals
	var network_manager = get_node("/root/NetworkManager")
	if network_manager:
		network_manager.peer_connected.connect(_on_peer_connected)
		network_manager.peer_disconnected.connect(_on_peer_disconnected)
		network_manager.connection_failed.connect(_on_connection_failed)
		network_manager.game_started.connect(_on_game_started)

	# Load available armies from ArmyListManager
	_setup_army_selection()

	print("MultiplayerLobby: Ready")

func _on_host_button_pressed() -> void:
	print("MultiplayerLobby: Host button pressed")

	var port = port_input.text.to_int()
	if port <= 0 or port > 65535:
		_show_error("Invalid port number. Use 1-65535")
		return

	var network_manager = get_node("/root/NetworkManager")
	var result = network_manager.create_host(port)

	if result == OK:
		is_hosting = true
		connected_players = 1  # Host counts as 1 player
		_update_ui_for_hosting()
		status_label.text = "Status: Hosting on port %d" % port
		info_label.text = "Waiting for player 2 to connect..."
		player_list_label.text = "Connected Players: 1/2 (You are Player 1)"
		print("MultiplayerLobby: Successfully hosting on port ", port)
	else:
		_show_error("Failed to create host. Error code: %d" % result)

func _on_join_button_pressed() -> void:
	print("MultiplayerLobby: Join button pressed")

	var ip = ip_input.text
	var port = port_input.text.to_int()

	if ip.is_empty():
		_show_error("Please enter host IP address")
		return

	if port <= 0 or port > 65535:
		_show_error("Invalid port number. Use 1-65535")
		return

	var network_manager = get_node("/root/NetworkManager")
	var result = network_manager.join_as_client(ip, port)

	if result == OK:
		is_hosting = false
		_update_ui_for_joining()
		status_label.text = "Status: Connecting to %s:%d..." % [ip, port]
		info_label.text = "Waiting for host to accept connection"
		print("MultiplayerLobby: Attempting to join ", ip, ":", port)
	else:
		_show_error("Failed to connect. Error code: %d" % result)

func _on_start_game_button_pressed() -> void:
	print("MultiplayerLobby: Start game button pressed")

	if not is_hosting:
		_show_error("Only the host can start the game")
		return

	if connected_players < 2:
		_show_error("Waiting for player 2 to connect")
		return

	# Load armies before starting game
	print("MultiplayerLobby: Loading armies...")

	# Initialize GameState if needed
	if GameState.state.is_empty():
		GameState.initialize_default_state()

	# Clear existing units
	GameState.state.units.clear()

	# Load Player 1 army (host)
	print("MultiplayerLobby: Loading ", selected_player1_army, " for Player 1")
	var player1_army = ArmyListManager.load_army_list(selected_player1_army, 1)
	print("MultiplayerLobby: Player 1 army loaded, has ", player1_army.get("units", {}).size(), " units")
	if player1_army.is_empty():
		_show_error("Failed to load Player 1 army: " + selected_player1_army)
		return
	ArmyListManager.apply_army_to_game_state(player1_army, 1)
	print("MultiplayerLobby: After applying P1 army, GameState has ", GameState.state.units.size(), " units")

	# Load Player 2 army (client)
	print("MultiplayerLobby: Loading ", selected_player2_army, " for Player 2")
	var player2_army = ArmyListManager.load_army_list(selected_player2_army, 2)
	print("MultiplayerLobby: Player 2 army loaded, has ", player2_army.get("units", {}).size(), " units")
	if player2_army.is_empty():
		_show_error("Failed to load Player 2 army: " + selected_player2_army)
		return
	ArmyListManager.apply_army_to_game_state(player2_army, 2)
	print("MultiplayerLobby: After applying P2 army, GameState has ", GameState.state.units.size(), " units")

	# Store army config in GameState metadata
	if not GameState.state.has("meta"):
		GameState.state["meta"] = {}

	# Set the from_multiplayer_lobby flag at the top level of meta
	GameState.state.meta["from_multiplayer_lobby"] = true
	GameState.state.meta["game_config"] = {
		"player1_army": selected_player1_army,
		"player2_army": selected_player2_army
	}

	print("MultiplayerLobby: Armies loaded. Total units: ", GameState.state.units.size())

	# CRITICAL: Sync the loaded armies to client BEFORE starting game
	var network_manager = get_node("/root/NetworkManager")

	# Send updated state snapshot with armies to all clients
	if network_manager.is_host():
		print("MultiplayerLobby: Syncing loaded armies to clients...")
		var snapshot = GameState.create_snapshot()
		print("MultiplayerLobby: Snapshot has ", snapshot.get("units", {}).size(), " units")

		# Send to all connected peers
		for peer_id in network_manager.peer_to_player_map.keys():
			if peer_id != 1:  # Don't send to self (host is peer 1)
				network_manager._send_initial_state.rpc_id(peer_id, snapshot)
				print("MultiplayerLobby: Sent army snapshot to peer ", peer_id)

	# Small delay to ensure state sync completes before scene change
	await get_tree().create_timer(0.5).timeout

	# Trigger game start via NetworkManager RPC
	# This will call on both host and client automatically
	network_manager.start_multiplayer_game.rpc()

	print("MultiplayerLobby: Game start RPC sent to all peers")

func _on_disconnect_button_pressed() -> void:
	print("MultiplayerLobby: Disconnect button pressed")

	var network_manager = get_node("/root/NetworkManager")
	network_manager.disconnect_network()

	_reset_ui()
	status_label.text = "Status: Disconnected"
	info_label.text = "Select Host or Join to begin"
	player_list_label.text = "Connected Players: 0/2"

func _on_back_button_pressed() -> void:
	print("MultiplayerLobby: Back button pressed")

	# Disconnect if connected
	var network_manager = get_node("/root/NetworkManager")
	if network_manager.is_networked():
		network_manager.disconnect_network()

	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_peer_connected(peer_id: int) -> void:
	print("MultiplayerLobby: Peer connected - ", peer_id)
	connected_players += 1

	if is_hosting:
		status_label.text = "Status: Player 2 connected!"
		info_label.text = "Ready to start game"
		player_list_label.text = "Connected Players: 2/2"
		start_game_button.disabled = false

		# Send current army selections to client
		_sync_army_selection.rpc(1, selected_player1_army)
		_sync_army_selection.rpc(2, selected_player2_army)
	else:
		status_label.text = "Status: Connected to host"
		info_label.text = "Select your army and wait for host to start"
		player_list_label.text = "Connected Players: 2/2 (You are Player 2)"

		# Enable client to select their army (Player 2)
		player2_dropdown.disabled = false

func _on_peer_disconnected(peer_id: int) -> void:
	print("MultiplayerLobby: Peer disconnected - ", peer_id)
	connected_players -= 1

	if is_hosting:
		status_label.text = "Status: Player 2 disconnected"
		info_label.text = "Waiting for player 2 to reconnect..."
		player_list_label.text = "Connected Players: 1/2"
		start_game_button.disabled = true
	else:
		# Client disconnected from host
		_show_error("Disconnected from host")
		_reset_ui()

func _on_connection_failed(reason: String) -> void:
	print("MultiplayerLobby: Connection failed - ", reason)
	_show_error("Connection failed: %s" % reason)
	_reset_ui()

func _on_game_started() -> void:
	print("MultiplayerLobby: Game started signal received")
	# The host will trigger scene change via start button
	# Clients will automatically transition when host loads the game

func _update_ui_for_hosting() -> void:
	host_button.disabled = true
	join_button.disabled = true
	port_input.editable = false
	ip_input.editable = false
	disconnect_button.disabled = false
	back_button.disabled = true

	# Enable host to select their army (Player 1)
	player1_dropdown.disabled = false
	player2_dropdown.disabled = true  # Can't pre-select opponent's army

func _update_ui_for_joining() -> void:
	host_button.disabled = true
	join_button.disabled = true
	port_input.editable = false
	ip_input.editable = false
	disconnect_button.disabled = false
	back_button.disabled = true

	# Disable both until we receive host's state
	player1_dropdown.disabled = true
	player2_dropdown.disabled = true

func _reset_ui() -> void:
	host_button.disabled = false
	join_button.disabled = false
	port_input.editable = true
	ip_input.editable = true
	start_game_button.disabled = true
	disconnect_button.disabled = true
	back_button.disabled = false
	is_hosting = false
	connected_players = 0

	# Reset army selection
	player1_dropdown.disabled = true
	player2_dropdown.disabled = true

	# Try to find A_C_test and ORK_test as defaults
	var p1_index = 0
	var p2_index = min(1, army_options.size() - 1)

	for i in range(army_options.size()):
		if army_options[i].id == "A_C_test":
			p1_index = i
		if army_options[i].id == "ORK_test":
			p2_index = i

	player1_dropdown.selected = p1_index
	player2_dropdown.selected = p2_index
	selected_player1_army = army_options[p1_index].id if not army_options.is_empty() else "A_C_test"
	selected_player2_army = army_options[p2_index].id if not army_options.is_empty() else "ORK_test"

func _show_error(message: String) -> void:
	print("MultiplayerLobby: Error - ", message)
	status_label.text = "Status: Error"
	info_label.text = message

	# Reset UI after a delay
	await get_tree().create_timer(3.0).timeout
	if not is_hosting and connected_players == 0:
		status_label.text = "Status: Not Connected"
		info_label.text = "Select Host or Join to begin"

# ============================================================================
# NETWORK - ARMY SYNCHRONIZATION
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _sync_army_selection(player: int, army_id: String) -> void:
	"""
	Called by host to synchronize army selection to client.
	Updates the UI to reflect the current army selections.
	"""
	print("MultiplayerLobby: Syncing army selection - Player ", player, " -> ", army_id)

	# Find army index
	var army_index = -1
	for i in range(army_options.size()):
		if army_options[i].id == army_id:
			army_index = i
			break

	if army_index == -1:
		print("MultiplayerLobby: Warning - Unknown army ID: ", army_id)
		return

	# Update selection
	if player == 1:
		selected_player1_army = army_id
		player1_dropdown.selected = army_index
	elif player == 2:
		selected_player2_army = army_id
		player2_dropdown.selected = army_index

@rpc("any_peer", "call_remote", "reliable")
func _request_army_change(player: int, army_id: String) -> void:
	"""
	Called by client to request army change.
	Host validates and broadcasts the change.
	"""
	if not is_hosting:
		print("MultiplayerLobby: Ignoring army change request (not host)")
		return

	var peer_id = multiplayer.get_remote_sender_id()
	print("MultiplayerLobby: Received army change request from peer ", peer_id, " for player ", player, " -> ", army_id)

	# Validate: Only allow peer to change their own army (peer 2 = player 2)
	var peer_player = 2 if peer_id != 1 else 1
	if player != peer_player:
		print("MultiplayerLobby: Rejecting army change - peer ", peer_id, " cannot change player ", player)
		return

	# Validate army exists
	var army_exists = false
	for option in army_options:
		if option.id == army_id:
			army_exists = true
			break

	if not army_exists:
		print("MultiplayerLobby: Rejecting army change - invalid army ID: ", army_id)
		return

	# Apply change locally (host)
	if player == 2:
		selected_player2_army = army_id
		var army_index = -1
		for i in range(army_options.size()):
			if army_options[i].id == army_id:
				army_index = i
				break
		player2_dropdown.selected = army_index

	# Broadcast to all peers (including requester for confirmation)
	_sync_army_selection.rpc(player, army_id)
	print("MultiplayerLobby: Army change applied and synced")

# ============================================================================
# ARMY SELECTION
# ============================================================================

func _setup_army_selection() -> void:
	# Get available armies
	army_options = []
	var available_armies = ArmyListManager.get_available_armies()

	# Build army options (mirror MainMenu.gd pattern)
	for army_name in available_armies:
		army_options.append({
			"id": army_name,
			"name": _format_army_name(army_name)
		})

	# Fallback if no armies found
	if army_options.is_empty():
		army_options = [
			{"id": "A_C_test", "name": "A C Test"},
			{"id": "ORK_test", "name": "ORK Test"}
		]

	# Populate dropdowns
	for option in army_options:
		player1_dropdown.add_item(option.name)
		player2_dropdown.add_item(option.name)

	# Set defaults - try to find A_C_test for P1 and ORK_test for P2
	var p1_default = 0
	var p2_default = min(1, army_options.size() - 1)

	for i in range(army_options.size()):
		if army_options[i].id == "A_C_test":
			p1_default = i
		if army_options[i].id == "ORK_test":
			p2_default = i

	player1_dropdown.selected = p1_default
	player2_dropdown.selected = p2_default

	selected_player1_army = army_options[p1_default].id
	selected_player2_army = army_options[p2_default].id

	# Connect dropdown signals
	player1_dropdown.item_selected.connect(_on_player1_army_changed)
	player2_dropdown.item_selected.connect(_on_player2_army_changed)

	# Initially disable both until connection is established
	player1_dropdown.disabled = true
	player2_dropdown.disabled = true

	print("MultiplayerLobby: Army selection initialized with ", army_options.size(), " armies")

func _format_army_name(army_id: String) -> String:
	"""Convert snake_case army ID to Title Case"""
	var parts = army_id.split("_")
	var formatted_parts = []
	for part in parts:
		formatted_parts.append(part.capitalize())
	return " ".join(formatted_parts)

func _on_player1_army_changed(index: int) -> void:
	if index < 0 or index >= army_options.size():
		return

	selected_player1_army = army_options[index].id
	print("MultiplayerLobby: Player 1 army changed to ", selected_player1_army)

	# If we're the host and connected, broadcast to client
	if is_hosting and connected_players >= 2:
		_sync_army_selection.rpc(1, selected_player1_army)

func _on_player2_army_changed(index: int) -> void:
	if index < 0 or index >= army_options.size():
		return

	selected_player2_army = army_options[index].id
	print("MultiplayerLobby: Player 2 army changed to ", selected_player2_army)

	# If we're the client, send request to host
	# Fixed GitHub Issue #98: Client only has connected_players=1 (only server peer connected),
	# so we rely on UI gating (dropdown disabled until connected) instead
	if not is_hosting:
		_request_army_change.rpc_id(1, 2, selected_player2_army)