extends Control

# MultiplayerLobby - UI for hosting/joining multiplayer games

# UI References
@onready var host_button: Button = $LobbyContainer/ModeSelection/ButtonsContainer/HostButton
@onready var join_button: Button = $LobbyContainer/ModeSelection/ButtonsContainer/JoinButton
@onready var online_button: Button = $LobbyContainer/ModeSelection/ButtonsContainer/OnlineButton
@onready var port_input: LineEdit = $LobbyContainer/ConnectionSettings/PortContainer/PortInput
@onready var ip_input: LineEdit = $LobbyContainer/ConnectionSettings/IPContainer/IPInput
@onready var status_label: Label = $LobbyContainer/StatusSection/StatusLabel
@onready var info_label: Label = $LobbyContainer/StatusSection/InfoLabel
@onready var player_list_label: Label = $LobbyContainer/StatusSection/PlayerListLabel
@onready var start_game_button: Button = $LobbyContainer/ActionButtons/StartGameButton
@onready var resume_game_button: Button = $LobbyContainer/ActionButtons/ResumeGameButton
@onready var disconnect_button: Button = $LobbyContainer/ActionButtons/DisconnectButton
@onready var back_button: Button = $LobbyContainer/ActionButtons/BackButton

# Army selection UI
@onready var player1_dropdown: OptionButton = $LobbyContainer/ArmySelection/Player1Container/Player1Dropdown
@onready var player2_dropdown: OptionButton = $LobbyContainer/ArmySelection/Player2Container/Player2Dropdown

# Deployment selection UI
@onready var deployment_dropdown: OptionButton = $LobbyContainer/ArmySelection/DeploymentContainer/DeploymentDropdown

# Mission selection UI
@onready var mission_dropdown: OptionButton = $LobbyContainer/ArmySelection/MissionContainer/MissionDropdown

# State
var is_hosting: bool = false
var connected_players: int = 0

# Army configuration
var army_options: Array = []
var selected_player1_army: String = "recon_stomps"
var selected_player2_army: String = "custodes_lions"
# Army sort mode: "alphabetical" or "newest_first"
var army_sort_mode: String = "alphabetical"
var army_sort_container: HBoxContainer = null
var army_sort_dropdown: OptionButton = null

# Deployment configuration
var deployment_options = [
	{"id": "hammer_anvil", "name": "Hammer and Anvil"},
	{"id": "dawn_of_war", "name": "Dawn of War"},
	{"id": "search_and_destroy", "name": "Search and Destroy"},
	{"id": "sweeping_engagement", "name": "Sweeping Engagement"},
	{"id": "crucible_of_battle", "name": "Crucible of Battle"},
	{"id": "tipping_point", "name": "Tipping Point"}
]
var selected_deployment: String = "hammer_anvil"

# Mission configuration
# 10e legacy shared-mission list — only used when the 11e layout index is
# missing (fallback builds). At 11e the primary mission is NOT a shared pick:
# each player picks a Force Disposition and scores their own card from the
# disposition pairing (PrimaryMissionData11e), exactly like the single-player
# MainMenu flow.
var mission_options = [
	{"id": "take_and_hold", "name": "Take and Hold"},
	{"id": "supply_drop", "name": "Supply Drop"},
	{"id": "purge_the_foe", "name": "Purge the Foe"},
	{"id": "linchpin", "name": "Linchpin"},
	{"id": "sites_of_power", "name": "Sites of Power"},
	{"id": "scorched_earth", "name": "Scorched Earth"},
	{"id": "the_ritual", "name": "The Ritual"},
	{"id": "terraform", "name": "Terraform"},
	{"id": "hidden_supplies", "name": "Hidden Supplies"},
]
var selected_mission: String = "take_and_hold"

# 11e Force Disposition + terrain-variant selection (mirrors MainMenu).
# Host owns P1's disposition and the terrain variant; the client owns P2's
# disposition (requested via RPC, host validates + rebroadcasts).
var use_11e_missions: bool = false
var selected_p1_disposition: String = "take_and_hold"
var selected_p2_disposition: String = "take_and_hold"
var selected_terrain: String = ""
var terrain_variant_options: Array = []  # layout metadata dicts for the current matchup
var p1_disposition_dropdown: OptionButton = null
var p2_disposition_dropdown: OptionButton = null
var terrain_variant_dropdown: OptionButton = null
var primary_card_label: Label = null

# Cloud army loading state
var _cloud_fetch_count: int = 0
var _cloud_start_pending: bool = false

# SAVE-15: Resume game dialog
var save_load_dialog: PanelContainer

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
	online_button.pressed.connect(_on_online_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	resume_game_button.pressed.connect(_on_resume_game_button_pressed)
	disconnect_button.pressed.connect(_on_disconnect_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

	# Hide online button on web platform (they go directly to WebLobby)
	# Also hide LAN buttons on web platform (ENet not supported in browser)
	if OS.has_feature("web"):
		host_button.visible = false
		join_button.visible = false
		port_input.get_parent().visible = false
		ip_input.get_parent().visible = false
		# Auto-redirect to WebLobby on web platform
		await get_tree().process_frame
		_on_online_button_pressed()

	# Connect NetworkManager signals
	var network_manager = NetworkManager
	if network_manager:
		network_manager.peer_connected.connect(_on_peer_connected)
		network_manager.peer_disconnected.connect(_on_peer_disconnected)
		network_manager.connection_failed.connect(_on_connection_failed)
		network_manager.game_started.connect(_on_game_started)

	# Load available armies, deployment, and mission options from ArmyListManager
	_setup_army_selection()
	_setup_deployment_selection()
	_setup_mission_selection()

	# Fetch cloud armies asynchronously
	_load_cloud_armies()

	# SAVE-15: Setup save/load dialog for resume game flow
	_setup_save_load_dialog()

	print("MultiplayerLobby: Ready")

func _on_host_button_pressed() -> void:
	print("MultiplayerLobby: Host button pressed")

	var port = port_input.text.to_int()
	if port <= 0 or port > 65535:
		_show_error("Invalid port number. Use 1-65535")
		return

	var network_manager = NetworkManager
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

	var network_manager = NetworkManager
	var result = network_manager.join_as_client(ip, port)

	if result == OK:
		is_hosting = false
		_update_ui_for_joining()
		status_label.text = "Status: Connecting to %s:%d..." % [ip, port]
		info_label.text = "Waiting for host to accept connection"
		print("MultiplayerLobby: Attempting to join ", ip, ":", port)
	else:
		_show_error("Failed to connect. Error code: %d" % result)

func _setup_deployment_selection() -> void:
	# Populate deployment dropdown
	for option in deployment_options:
		deployment_dropdown.add_item(option.name)
	deployment_dropdown.selected = 0
	selected_deployment = deployment_options[0].id
	deployment_dropdown.item_selected.connect(_on_deployment_changed)
	deployment_dropdown.disabled = true  # Disabled until connected
	print("MultiplayerLobby: Deployment selection initialized with ", deployment_options.size(), " options")

func _on_deployment_changed(index: int) -> void:
	if index < 0 or index >= deployment_options.size():
		return
	selected_deployment = deployment_options[index].id
	print("MultiplayerLobby: Deployment changed to ", selected_deployment)
	# If host and connected, broadcast to client
	if is_hosting and connected_players >= 2:
		_sync_deployment_selection.rpc(selected_deployment)

func _setup_mission_selection() -> void:
	# 11e GDM 2026: the primary mission is not a shared dropdown pick — each
	# player selects a Force Disposition and scores the card their disposition
	# pairs into against the opponent's (PrimaryMissionData11e). The terrain is
	# one of the matchup's 3 official layout variants and fixes the deployment
	# pattern. Falls back to the legacy 10e shared-mission dropdown only when
	# the generated 11e layout index is absent (unexpected in player builds).
	var tm = get_node_or_null("/root/TerrainManager")
	use_11e_missions = tm != null and tm.has_method("get_11e_layout_ids") \
		and not tm.get_11e_layout_ids().is_empty()

	if use_11e_missions:
		_setup_disposition_selection_11e()
		return

	# Legacy 10e fallback: populate mission dropdown
	for option in mission_options:
		mission_dropdown.add_item(option.name)
	mission_dropdown.selected = 0
	selected_mission = mission_options[0].id
	mission_dropdown.item_selected.connect(_on_mission_changed)
	mission_dropdown.disabled = true  # Disabled until connected
	print("MultiplayerLobby: Mission selection initialized with ", mission_options.size(), " options")

func _setup_disposition_selection_11e() -> void:
	"""Build the 11e Force Disposition + terrain-variant UI in place of the
	legacy shared-mission dropdown (which is hidden). Mirrors MainMenu."""
	var army_selection = $LobbyContainer/ArmySelection
	var mission_container = mission_dropdown.get_parent()
	mission_container.visible = false

	var disposition_container = VBoxContainer.new()
	disposition_container.name = "DispositionContainer"
	disposition_container.add_theme_constant_override("separation", 6)
	army_selection.add_child(disposition_container)
	# Place where the mission row was (right below the section label)
	army_selection.move_child(disposition_container, mission_container.get_index())

	var section_label = Label.new()
	section_label.text = "Force Disposition (11th Edition):"
	disposition_container.add_child(section_label)

	for player in [1, 2]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		disposition_container.add_child(row)

		var label = Label.new()
		label.text = "Player %d:" % player
		label.custom_minimum_size = Vector2(150, 0)
		row.add_child(label)

		var dropdown = OptionButton.new()
		dropdown.name = "P%dDispositionDropdown" % player
		dropdown.custom_minimum_size = Vector2(300, 0)
		for disp_id in PrimaryMissionData11e.DISPOSITIONS:
			dropdown.add_item(PrimaryMissionData11e.get_disposition_name(disp_id))
		dropdown.selected = 0
		dropdown.disabled = true  # Enabled per-seat once connected
		dropdown.item_selected.connect(_on_disposition_changed.bind(player))
		row.add_child(dropdown)

		if player == 1:
			p1_disposition_dropdown = dropdown
		else:
			p2_disposition_dropdown = dropdown

	# Resolved primary cards (read-only, derived from the pairing)
	primary_card_label = Label.new()
	primary_card_label.name = "PrimaryCardLabel"
	primary_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	disposition_container.add_child(primary_card_label)

	# Terrain variant row — the matchup's 3 official layouts; the variant
	# fixes the deployment pattern (deployment dropdown becomes read-only).
	var terrain_row = HBoxContainer.new()
	terrain_row.add_theme_constant_override("separation", 8)
	disposition_container.add_child(terrain_row)

	var terrain_label = Label.new()
	terrain_label.text = "Terrain Layout:"
	terrain_label.custom_minimum_size = Vector2(150, 0)
	terrain_row.add_child(terrain_label)

	terrain_variant_dropdown = OptionButton.new()
	terrain_variant_dropdown.name = "TerrainVariantDropdown"
	terrain_variant_dropdown.custom_minimum_size = Vector2(300, 0)
	terrain_variant_dropdown.disabled = true  # Host-only once connected
	terrain_variant_dropdown.item_selected.connect(_on_terrain_variant_changed)
	terrain_row.add_child(terrain_variant_dropdown)

	# Deployment follows the chosen variant at 11e — never hand-picked
	deployment_dropdown.disabled = true

	_refresh_matchup_terrain_options_11e(true)
	print("MultiplayerLobby: 11e Force Disposition selection initialized")

func _refresh_matchup_terrain_options_11e(reset_to_variant_1: bool) -> void:
	"""Rebuild the terrain variant dropdown for the current disposition
	matchup, keep the deployment display in step, and refresh the resolved
	primary-card label."""
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return
	terrain_variant_options = tm.get_layouts_for_matchup(selected_p1_disposition, selected_p2_disposition)

	var keep_id = selected_terrain
	terrain_variant_dropdown.clear()
	for meta in terrain_variant_options:
		var variant = int(meta.get("variant", 0))
		var recs: Array = meta.get("recommended_deployments", [])
		var dep_name = _deployment_display_name(str(recs[0])) if not recs.is_empty() else "?"
		terrain_variant_dropdown.add_item("Variant %d (%s)" % [variant, dep_name])

	if terrain_variant_options.is_empty():
		selected_terrain = ""
		_refresh_primary_card_label_11e()
		return

	var target_idx = 0
	if not reset_to_variant_1:
		for i in range(terrain_variant_options.size()):
			if str(terrain_variant_options[i].get("id", "")) == keep_id:
				target_idx = i
				break
	terrain_variant_dropdown.selected = target_idx
	_apply_terrain_variant_11e(target_idx)

func _apply_terrain_variant_11e(index: int) -> void:
	"""Set selected_terrain + derived deployment from the variant metadata."""
	if index < 0 or index >= terrain_variant_options.size():
		return
	var meta = terrain_variant_options[index]
	selected_terrain = str(meta.get("id", ""))
	var recs: Array = meta.get("recommended_deployments", [])
	if not recs.is_empty():
		var dep_id = str(recs[0])
		for i in range(deployment_options.size()):
			if deployment_options[i].id == dep_id:
				selected_deployment = dep_id
				deployment_dropdown.selected = i
				break
	_refresh_primary_card_label_11e()
	print("MultiplayerLobby: 11e terrain variant -> %s (deployment: %s)" % [selected_terrain, selected_deployment])

func _refresh_primary_card_label_11e() -> void:
	if primary_card_label == null:
		return
	var p1_card = PrimaryMissionData11e.get_card(selected_p1_disposition, selected_p2_disposition)
	var p2_card = PrimaryMissionData11e.get_card(selected_p2_disposition, selected_p1_disposition)
	primary_card_label.text = "Primary — P1: %s | P2: %s" % [
		str(p1_card.get("name", "?")), str(p2_card.get("name", "?"))]

func _deployment_display_name(deployment_id: String) -> String:
	for option in deployment_options:
		if str(option.get("id", "")) == deployment_id:
			return str(option.get("name", deployment_id))
	return deployment_id

func _disposition_index(disp_id: String) -> int:
	var idx = PrimaryMissionData11e.DISPOSITIONS.find(disp_id)
	return idx if idx >= 0 else 0

func _on_disposition_changed(index: int, player: int) -> void:
	if index < 0 or index >= PrimaryMissionData11e.DISPOSITIONS.size():
		return
	var disp_id = PrimaryMissionData11e.DISPOSITIONS[index]

	if is_hosting:
		if player == 1:
			selected_p1_disposition = disp_id
		else:
			# Host may pre-pick P2's disposition before the client connects;
			# once connected the dropdown is client-owned (disabled host-side).
			selected_p2_disposition = disp_id
		_refresh_matchup_terrain_options_11e(true)
		if connected_players >= 2:
			_sync_disposition_selection.rpc(player, disp_id)
			_sync_terrain_selection.rpc(selected_terrain, selected_deployment)
	else:
		# Client owns only P2's disposition; ask the host to apply it
		if player == 2:
			_request_disposition_change.rpc_id(1, 2, disp_id)

func _on_terrain_variant_changed(index: int) -> void:
	if not is_hosting:
		return
	_apply_terrain_variant_11e(index)
	if connected_players >= 2:
		_sync_terrain_selection.rpc(selected_terrain, selected_deployment)

func _on_mission_changed(index: int) -> void:
	if index < 0 or index >= mission_options.size():
		return
	selected_mission = mission_options[index].id
	print("MultiplayerLobby: Mission changed to ", selected_mission)
	# If host and connected, broadcast to client
	if is_hosting and connected_players >= 2:
		_sync_mission_selection.rpc(selected_mission)

func _on_start_game_button_pressed() -> void:
	print("MultiplayerLobby: Start game button pressed")

	if not is_hosting:
		_show_error("Only the host can start the game")
		return

	if connected_players < 2:
		_show_error("Waiting for player 2 to connect")
		return

	# Check if cloud armies need fetching before starting
	var p1_is_cloud = _is_cloud_selection(selected_player1_army)
	var p2_is_cloud = _is_cloud_selection(selected_player2_army)

	if p1_is_cloud or p2_is_cloud:
		start_game_button.disabled = true
		status_label.text = "Status: Downloading cloud armies..."
		_cloud_fetch_count = 0
		_cloud_start_pending = true

		if p1_is_cloud:
			_cloud_fetch_count += 1
			ArmyListManager.fetch_cloud_army(selected_player1_army, 1)
		if p2_is_cloud:
			_cloud_fetch_count += 1
			ArmyListManager.fetch_cloud_army(selected_player2_army, 2)
		return

	_do_start_game()

func _do_start_game() -> void:
	# Load armies before starting game
	print("MultiplayerLobby: Loading armies with deployment: ", selected_deployment, " mission: ", selected_mission)

	# Initialize GameState with selected deployment type
	if GameState.state.is_empty():
		GameState.initialize_default_state(selected_deployment)
	else:
		# Re-initialize with selected deployment type if state already exists
		GameState.initialize_default_state(selected_deployment)

	# Load the chosen terrain into the fresh state on the HOST.
	# initialize_default_state wipes board.terrain; clients rebuild theirs in
	# load_from_snapshot (the snapshot carries terrain_layout), but the host
	# must load it here or it adjudicates terrain rules (movement through
	# ruins walls etc.) against an EMPTY terrain list while the client saw 14
	# pieces. At 11e the layout is the matchup variant chosen in this lobby —
	# NOT whatever layout happened to be loaded before (stale current_layout).
	var terrain_mgr = get_node_or_null("/root/TerrainManager")
	if terrain_mgr:
		if use_11e_missions and selected_terrain != "":
			terrain_mgr.load_terrain_layout(selected_terrain)
			print("MultiplayerLobby: Loaded 11e matchup terrain '%s' (%d pieces)" % [
				selected_terrain, terrain_mgr.terrain_features.size()])
		elif terrain_mgr.current_layout != "":
			terrain_mgr.load_terrain_layout(terrain_mgr.current_layout)
			print("MultiplayerLobby: Reloaded terrain layout '%s' into fresh game state (%d pieces)" % [
				terrain_mgr.current_layout, terrain_mgr.terrain_features.size()])

	# Clear existing units
	GameState.state.units.clear()

	# Load Player 1 army (host) - supports both local and cached cloud armies
	print("MultiplayerLobby: Loading ", selected_player1_army, " for Player 1")
	var player1_army = ArmyListManager.load_army_for_game(selected_player1_army, 1)
	print("MultiplayerLobby: Player 1 army loaded, has ", player1_army.get("units", {}).size(), " units")
	if player1_army.is_empty():
		_show_error("Failed to load Player 1 army: " + selected_player1_army)
		return
	ArmyListManager.apply_army_to_game_state(player1_army, 1)
	print("MultiplayerLobby: After applying P1 army, GameState has ", GameState.state.units.size(), " units")

	# Load Player 2 army (client)
	print("MultiplayerLobby: Loading ", selected_player2_army, " for Player 2")
	var player2_army = ArmyListManager.load_army_for_game(selected_player2_army, 2)
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
		"player2_army": selected_player2_army,
		"deployment": selected_deployment,
		"mission": selected_mission,
		# Both seats are humans in a networked game — stated explicitly so
		# AI/human checks (e.g. ScoringPhase._is_human_player_11e) can't
		# misread an absent key.
		"player1_type": "HUMAN",
		"player2_type": "HUMAN",
		# 11e GDM 2026: per-player Force Dispositions drive the primary
		# mission pairing (MissionManager.initialize_dispositions_11e reads
		# these). The lobby currently always uses tactical secondaries.
		"player1_disposition": selected_p1_disposition,
		"player2_disposition": selected_p2_disposition,
		"terrain": selected_terrain if use_11e_missions else (terrain_mgr.current_layout if terrain_mgr else ""),
		"player1_secondary_mode": "tactical",
		"player2_secondary_mode": "tactical",
	}

	# Shared deck seed: secondary mission deck shuffles must be identical on
	# host and client (CommandPhase builds/draws decks on BOTH peers when it
	# enters). The seed travels to the client inside the initial snapshot.
	GameState.state.meta["game_seed"] = randi() & 0x7FFFFFFF

	# Reset secondary mission state — the lobby previously never did this, so
	# a second multiplayer game in one session inherited the previous game's
	# decks/hands/VP (MainMenu's single-player flow always resets).
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr:
		secondary_mgr.initialize_for_game()

	# Initialize MissionManager with selected mission (at 11e this also reads
	# the Force Dispositions from meta.game_config and resolves each player's
	# primary mission card from the pairing table)
	if MissionManager:
		MissionManager.initialize_mission(selected_mission)
		print("MultiplayerLobby: Mission initialized: ", selected_mission)

	# Initialize BoardState deployment zones to match selected deployment
	if BoardState:
		BoardState.initialize_deployment_zones(selected_deployment)

	print("MultiplayerLobby: Armies loaded. Total units: ", GameState.state.units.size())

	# CRITICAL: Sync the loaded armies to client BEFORE starting game
	var network_manager = NetworkManager

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

	var network_manager = NetworkManager
	network_manager.disconnect_network()

	_reset_ui()
	status_label.text = "Status: Disconnected"
	info_label.text = "Select Host or Join to begin"
	player_list_label.text = "Connected Players: 0/2"

func _on_online_button_pressed() -> void:
	print("MultiplayerLobby: Online button pressed")
	# Navigate to WebLobby for online play
	get_tree().change_scene_to_file("res://scenes/WebLobby.tscn")

func _on_back_button_pressed() -> void:
	print("MultiplayerLobby: Back button pressed")

	# Disconnect if connected
	var network_manager = NetworkManager
	if network_manager.is_networked():
		network_manager.disconnect_network()

	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_peer_connected(peer_id: int) -> void:
	print("MultiplayerLobby: Peer connected - ", peer_id)
	connected_players += 1

	if is_hosting:
		status_label.text = "Status: Player 2 connected!"
		info_label.text = "Ready to start game or resume a saved game"
		player_list_label.text = "Connected Players: 2/2"
		start_game_button.disabled = false
		resume_game_button.disabled = false  # SAVE-15: Enable resume when both players connected

		# Send current army, deployment, and mission selections to client
		_sync_army_selection.rpc(1, selected_player1_army)
		_sync_army_selection.rpc(2, selected_player2_army)
		_sync_deployment_selection.rpc(selected_deployment)
		_sync_mission_selection.rpc(selected_mission)
		if use_11e_missions:
			_sync_disposition_selection.rpc(1, selected_p1_disposition)
			_sync_disposition_selection.rpc(2, selected_p2_disposition)
			_sync_terrain_selection.rpc(selected_terrain, selected_deployment)
			# The connected client now owns P2's disposition
			if p2_disposition_dropdown:
				p2_disposition_dropdown.disabled = true
	else:
		status_label.text = "Status: Connected to host"
		info_label.text = "Select your army and wait for host to start"
		player_list_label.text = "Connected Players: 2/2 (You are Player 2)"

		# Enable client to select their army (Player 2)
		player2_dropdown.disabled = false
		# 11e: client owns their own Force Disposition
		if use_11e_missions and p2_disposition_dropdown:
			p2_disposition_dropdown.disabled = false

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

	# Enable host to select their army (Player 1), deployment, and mission
	player1_dropdown.disabled = false
	player2_dropdown.disabled = true  # Can't pre-select opponent's army
	if use_11e_missions:
		# 11e: host owns P1 disposition + terrain variant; deployment is
		# derived from the variant and stays read-only. Host may pre-set P2's
		# disposition until the client connects and takes it over.
		if p1_disposition_dropdown:
			p1_disposition_dropdown.disabled = false
		if p2_disposition_dropdown:
			p2_disposition_dropdown.disabled = false
		if terrain_variant_dropdown:
			terrain_variant_dropdown.disabled = false
	else:
		deployment_dropdown.disabled = false  # Host can select deployment map
		mission_dropdown.disabled = false  # Host can select mission

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
	deployment_dropdown.disabled = true  # Client cannot change deployment
	mission_dropdown.disabled = true  # Client cannot change mission
	if use_11e_missions:
		# Client owns only P2's disposition — enabled on connection
		if p1_disposition_dropdown:
			p1_disposition_dropdown.disabled = true
		if p2_disposition_dropdown:
			p2_disposition_dropdown.disabled = true
		if terrain_variant_dropdown:
			terrain_variant_dropdown.disabled = true

func _reset_ui() -> void:
	host_button.disabled = false
	join_button.disabled = false
	port_input.editable = true
	ip_input.editable = true
	start_game_button.disabled = true
	resume_game_button.disabled = true  # SAVE-15
	disconnect_button.disabled = true
	back_button.disabled = false
	is_hosting = false
	connected_players = 0

	# Reset army, deployment, and mission selection
	player1_dropdown.disabled = true
	player2_dropdown.disabled = true
	deployment_dropdown.disabled = true
	mission_dropdown.disabled = true
	if use_11e_missions:
		if p1_disposition_dropdown:
			p1_disposition_dropdown.disabled = true
		if p2_disposition_dropdown:
			p2_disposition_dropdown.disabled = true
		if terrain_variant_dropdown:
			terrain_variant_dropdown.disabled = true
		# Keep the current disposition/terrain picks — they carry over to the
		# next hosting session in this lobby visit.
	else:
		deployment_dropdown.selected = 0
		selected_deployment = deployment_options[0].id
		mission_dropdown.selected = 0
		selected_mission = mission_options[0].id

	# Default matchup: Recon Stomps (P1) vs Custodes Lions (P2)
	var p1_index = 0
	var p2_index = min(1, army_options.size() - 1)

	for i in range(army_options.size()):
		if army_options[i].id == "recon_stomps":
			p1_index = i
		if army_options[i].id == "custodes_lions":
			p2_index = i

	player1_dropdown.selected = p1_index
	player2_dropdown.selected = p2_index
	selected_player1_army = army_options[p1_index].id if not army_options.is_empty() else "recon_stomps"
	selected_player2_army = army_options[p2_index].id if not army_options.is_empty() else "custodes_lions"

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
# SAVE-15: MULTIPLAYER RESUME FLOW
# ============================================================================

func _setup_save_load_dialog() -> void:
	var dialog_scene = load("res://scenes/SaveLoadDialog.tscn")
	if dialog_scene:
		save_load_dialog = dialog_scene.instantiate()
		add_child(save_load_dialog)
		save_load_dialog.load_requested.connect(_on_resume_load_requested)
		print("MultiplayerLobby: SAVE-15 Save/Load dialog setup for resume flow")
	else:
		print("MultiplayerLobby: Warning - Could not load SaveLoadDialog.tscn")

func _on_resume_game_button_pressed() -> void:
	print("MultiplayerLobby: SAVE-15 Resume game button pressed")

	if not is_hosting:
		_show_error("Only the host can resume a saved game")
		return

	if connected_players < 2:
		_show_error("Waiting for player 2 to connect before resuming")
		return

	if save_load_dialog:
		save_load_dialog.show_dialog()
	else:
		_show_error("Save/Load dialog not available")

func _on_resume_load_requested(save_file: String, owner_id: String = "") -> void:
	print("MultiplayerLobby: SAVE-15 Resume load requested for: ", save_file, " (owner_id: ", owner_id, ")")

	if not SaveLoadManager:
		_show_error("SaveLoadManager not available")
		return

	if OS.has_feature("web"):
		# Web: async load
		if not SaveLoadManager.load_completed.is_connected(_on_resume_load_completed):
			SaveLoadManager.load_completed.connect(_on_resume_load_completed)
		if not SaveLoadManager.load_failed.is_connected(_on_resume_load_failed):
			SaveLoadManager.load_failed.connect(_on_resume_load_failed)
		SaveLoadManager.load_game(save_file, owner_id)
		status_label.text = "Status: Loading saved game..."
	else:
		# Desktop: synchronous load
		var success = SaveLoadManager.load_game(save_file, owner_id)
		if success:
			_finalize_resume_load()
		else:
			_show_error("Failed to load save file: " + save_file)

func _on_resume_load_completed(_file_path: String, _metadata: Dictionary) -> void:
	print("MultiplayerLobby: SAVE-15 Cloud/async resume load completed")
	# Disconnect one-shot signals
	if SaveLoadManager.load_completed.is_connected(_on_resume_load_completed):
		SaveLoadManager.load_completed.disconnect(_on_resume_load_completed)
	if SaveLoadManager.load_failed.is_connected(_on_resume_load_failed):
		SaveLoadManager.load_failed.disconnect(_on_resume_load_failed)
	_finalize_resume_load()

func _on_resume_load_failed(error: String) -> void:
	print("MultiplayerLobby: SAVE-15 Resume load failed: ", error)
	if SaveLoadManager.load_completed.is_connected(_on_resume_load_completed):
		SaveLoadManager.load_completed.disconnect(_on_resume_load_completed)
	if SaveLoadManager.load_failed.is_connected(_on_resume_load_failed):
		SaveLoadManager.load_failed.disconnect(_on_resume_load_failed)
	_show_error("Failed to load saved game: " + error)

func _finalize_resume_load() -> void:
	"""SAVE-15: After loading a save, mark as multiplayer resume and sync to client."""
	print("MultiplayerLobby: SAVE-15 Finalizing multiplayer resume load")

	# Mark the game state as coming from a multiplayer resume
	if not GameState.state.has("meta"):
		GameState.state["meta"] = {}
	GameState.state.meta["from_save"] = true
	GameState.state.meta["from_multiplayer_lobby"] = true
	GameState.state.meta.erase("from_menu")

	# Sync loaded state to client via NetworkManager
	var network_manager = NetworkManager
	if network_manager.is_host():
		print("MultiplayerLobby: SAVE-15 Syncing resumed game state to clients...")
		var snapshot = GameState.create_snapshot()
		print("MultiplayerLobby: SAVE-15 Snapshot has ", snapshot.get("units", {}).size(), " units")

		for peer_id in network_manager.peer_to_player_map.keys():
			if peer_id != 1:
				network_manager._send_initial_state.rpc_id(peer_id, snapshot)
				print("MultiplayerLobby: SAVE-15 Sent resume snapshot to peer ", peer_id)

	# Small delay to ensure state sync completes before scene change
	await get_tree().create_timer(0.5).timeout

	# Start the game via NetworkManager RPC (transitions both host and client)
	network_manager.start_multiplayer_game.rpc()
	print("MultiplayerLobby: SAVE-15 Resume game RPC sent to all peers")

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
# NETWORK - DEPLOYMENT SYNCHRONIZATION
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _sync_deployment_selection(deployment_id: String) -> void:
	"""Called by host to synchronize deployment selection to client."""
	print("MultiplayerLobby: Syncing deployment selection -> ", deployment_id)

	# Find deployment index
	for i in range(deployment_options.size()):
		if deployment_options[i].id == deployment_id:
			selected_deployment = deployment_id
			deployment_dropdown.selected = i
			return

	print("MultiplayerLobby: Warning - Unknown deployment ID: ", deployment_id)

# ============================================================================
# NETWORK - MISSION SYNCHRONIZATION
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _sync_mission_selection(mission_id: String) -> void:
	"""Called by host to synchronize mission selection to client."""
	print("MultiplayerLobby: Syncing mission selection -> ", mission_id)
	if use_11e_missions:
		# 11e mode has no shared mission dropdown — nothing to mirror.
		selected_mission = mission_id
		return

	# Find mission index
	for i in range(mission_options.size()):
		if mission_options[i].id == mission_id:
			selected_mission = mission_id
			mission_dropdown.selected = i
			return

	print("MultiplayerLobby: Warning - Unknown mission ID: ", mission_id)

# ============================================================================
# NETWORK - 11e DISPOSITION / TERRAIN SYNCHRONIZATION
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _sync_disposition_selection(player: int, disp_id: String) -> void:
	"""Host broadcasts a disposition pick to the client."""
	print("MultiplayerLobby: Syncing disposition — Player %d -> %s" % [player, disp_id])
	if not use_11e_missions or not PrimaryMissionData11e.is_valid_disposition(disp_id):
		return
	if player == 1:
		selected_p1_disposition = disp_id
		if p1_disposition_dropdown:
			p1_disposition_dropdown.selected = _disposition_index(disp_id)
	else:
		selected_p2_disposition = disp_id
		if p2_disposition_dropdown:
			p2_disposition_dropdown.selected = _disposition_index(disp_id)
	# The terrain matchup depends on both dispositions; the host follows up
	# with _sync_terrain_selection, so only refresh the local option list.
	_refresh_matchup_terrain_options_11e(false)

@rpc("any_peer", "call_remote", "reliable")
func _request_disposition_change(player: int, disp_id: String) -> void:
	"""Client requests changing their own (P2) disposition. Host validates,
	applies, and rebroadcasts (mirrors _request_army_change)."""
	if not is_hosting:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	print("MultiplayerLobby: Disposition change request from peer %d: P%d -> %s" % [peer_id, player, disp_id])
	# Only the guest may change player 2's disposition
	var peer_player = 2 if peer_id != 1 else 1
	if player != peer_player or player != 2:
		print("MultiplayerLobby: Rejecting disposition change — peer %d cannot change player %d" % [peer_id, player])
		return
	if not PrimaryMissionData11e.is_valid_disposition(disp_id):
		print("MultiplayerLobby: Rejecting disposition change — invalid id: ", disp_id)
		return

	selected_p2_disposition = disp_id
	if p2_disposition_dropdown:
		p2_disposition_dropdown.selected = _disposition_index(disp_id)
	# New matchup — rebuild terrain options and default to variant 1
	_refresh_matchup_terrain_options_11e(true)

	_sync_disposition_selection.rpc(player, disp_id)
	_sync_terrain_selection.rpc(selected_terrain, selected_deployment)

@rpc("authority", "call_remote", "reliable")
func _sync_terrain_selection(terrain_id: String, deployment_id: String) -> void:
	"""Host broadcasts the chosen terrain variant (and its derived deployment)."""
	print("MultiplayerLobby: Syncing terrain -> %s (deployment %s)" % [terrain_id, deployment_id])
	if not use_11e_missions:
		return
	selected_terrain = terrain_id
	selected_deployment = deployment_id
	# Mirror the variant in the local dropdown (options were rebuilt from the
	# synced dispositions, so the id should be present).
	for i in range(terrain_variant_options.size()):
		if str(terrain_variant_options[i].get("id", "")) == terrain_id:
			if terrain_variant_dropdown:
				terrain_variant_dropdown.selected = i
			break
	for i in range(deployment_options.size()):
		if deployment_options[i].id == deployment_id:
			deployment_dropdown.selected = i
			break
	_refresh_primary_card_label_11e()

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
		print("MultiplayerLobby: No cloud armies available")
		return

	# Save current selections
	var p1_selected_id = selected_player1_army
	var p2_selected_id = selected_player2_army

	# Add cloud armies that aren't already available locally
	var local_ids = []
	for option in army_options:
		if option.get("source", "local") == "local":
			local_ids.append(option.id)

	var added_count = 0
	for cloud_name in cloud_armies:
		if cloud_name not in local_ids:
			var base_name = _format_army_name(cloud_name) + " (Cloud)"
			var date_str = ArmyListManager.get_army_date(cloud_name)
			var display_name = base_name
			if not date_str.is_empty():
				display_name = "%s (%s)" % [base_name, _format_date_display(date_str)]
			army_options.append({"id": cloud_name, "name": base_name, "date": date_str, "display": display_name, "source": "cloud"})
			player1_dropdown.add_item(display_name)
			player2_dropdown.add_item(display_name)
			added_count += 1

	if added_count > 0:
		print("MultiplayerLobby: Added %d cloud armies to dropdowns" % added_count)

		# Restore selections
		for i in range(army_options.size()):
			if army_options[i].id == p1_selected_id:
				player1_dropdown.selected = i
			if army_options[i].id == p2_selected_id:
				player2_dropdown.selected = i

func _is_cloud_selection(army_id: String) -> bool:
	return ArmyListManager and ArmyListManager.is_cloud_army(army_id)

func _on_cloud_army_fetched(_army_name: String, _army_data: Dictionary) -> void:
	_cloud_fetch_count -= 1
	print("MultiplayerLobby: Cloud army fetched, remaining: ", _cloud_fetch_count)

	if _cloud_fetch_count <= 0 and _cloud_start_pending:
		_cloud_start_pending = false
		_do_start_game()

func _on_cloud_army_fetch_failed(army_name: String, error: String) -> void:
	print("MultiplayerLobby: Failed to download cloud army '%s': %s" % [army_name, error])
	_cloud_fetch_count = 0
	_cloud_start_pending = false
	start_game_button.disabled = false
	_show_error("Failed to download cloud army: " + army_name)

# ============================================================================
# ARMY SELECTION
# ============================================================================

func _setup_army_selection() -> void:
	# Create sort dropdown
	_create_army_sort_dropdown()

	# Get available armies
	army_options = []
	var available_armies = ArmyListManager.get_available_armies()

	# Build army options with dates (mirror MainMenu.gd pattern)
	for army_name in available_armies:
		var base_name = _format_army_name(army_name)
		var date_str = ArmyListManager.get_army_date(army_name)
		var display_name = base_name
		if not date_str.is_empty():
			display_name = "%s (%s)" % [base_name, _format_date_display(date_str)]
		army_options.append({
			"id": army_name,
			"name": base_name,
			"date": date_str,
			"display": display_name
		})

	# Fallback if no armies found
	if army_options.is_empty():
		army_options = [
			{"id": "recon_stomps", "name": "Recon Stomps", "date": "", "display": "Recon Stomps"},
			{"id": "custodes_lions", "name": "Custodes Lions", "date": "", "display": "Custodes Lions"}
		]

	# Sort based on current mode
	_sort_army_options()

	# Populate dropdowns
	_populate_army_dropdowns()

	# Set defaults - Recon Stomps for P1, Custodes Lions for P2
	var p1_default = 0
	var p2_default = min(1, army_options.size() - 1)

	for i in range(army_options.size()):
		if army_options[i].id == "recon_stomps":
			p1_default = i
		if army_options[i].id == "custodes_lions":
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

func _format_date_display(date_str: String) -> String:
	"""Convert YYYY-MM-DD to a readable format like 'Mar 7, 2025'."""
	if date_str.is_empty():
		return ""
	var parts = date_str.split("-")
	if parts.size() != 3:
		return date_str
	var month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_idx = parts[1].to_int() - 1
	if month_idx < 0 or month_idx >= 12:
		return date_str
	var day = parts[2].to_int()
	return "%s %d, %s" % [month_names[month_idx], day, parts[0]]

func _sort_army_options() -> void:
	"""Sort army_options based on current sort mode."""
	if army_sort_mode == "newest_first":
		army_options.sort_custom(func(a, b): return a.date > b.date)
	else:
		army_options.sort_custom(func(a, b): return a.name < b.name)

func _populate_army_dropdowns() -> void:
	"""Clear and repopulate army dropdowns from army_options."""
	player1_dropdown.clear()
	player2_dropdown.clear()
	for option in army_options:
		player1_dropdown.add_item(option.display)
		player2_dropdown.add_item(option.display)

func _create_army_sort_dropdown() -> void:
	"""Create a sort mode dropdown for army list ordering."""
	var army_selection = $LobbyContainer/ArmySelection

	army_sort_container = HBoxContainer.new()
	army_sort_container.name = "ArmySortContainer"

	var sort_label = Label.new()
	sort_label.text = "Sort By:"
	sort_label.custom_minimum_size = Vector2(150, 0)
	army_sort_container.add_child(sort_label)

	army_sort_dropdown = OptionButton.new()
	army_sort_dropdown.name = "ArmySortDropdown"
	army_sort_dropdown.custom_minimum_size = Vector2(300, 0)
	army_sort_dropdown.add_item("Alphabetical")
	army_sort_dropdown.add_item("Newest First")
	army_sort_dropdown.selected = 0
	army_sort_dropdown.item_selected.connect(_on_army_sort_changed)
	army_sort_container.add_child(army_sort_dropdown)

	# Insert after the ArmyLabel (index 0 in ArmySelection)
	army_selection.add_child(army_sort_container)
	army_selection.move_child(army_sort_container, 1)

	print("MultiplayerLobby: Army sort dropdown created")

func _on_army_sort_changed(index: int) -> void:
	"""Handle sort mode change."""
	var previous_p1_id = selected_player1_army
	var previous_p2_id = selected_player2_army

	army_sort_mode = "newest_first" if index == 1 else "alphabetical"
	_sort_army_options()
	_populate_army_dropdowns()

	# Restore selections
	for i in range(army_options.size()):
		if army_options[i].id == previous_p1_id:
			player1_dropdown.selected = i
		if army_options[i].id == previous_p2_id:
			player2_dropdown.selected = i

	print("MultiplayerLobby: Army sort changed to ", army_sort_mode)

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