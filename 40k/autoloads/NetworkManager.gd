extends Node

# NetworkManager - Multiplayer networking for Warhammer 40K game
# Note: No class_name since this is an autoload singleton

# Signals
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal game_started()

# Network modes
enum NetworkMode { OFFLINE, HOST, CLIENT }

# State
var network_mode: NetworkMode = NetworkMode.OFFLINE
var peer_to_player_map: Dictionary = {}  # peer_id -> player_number
var game_manager: GameManager = null
var game_state: GameStateData = null

# Turn timer (Phase 3)
var turn_timer: Timer = null
const TURN_TIMEOUT_SECONDS: float = 90.0

# RNG determinism (Phase 4)
var rng_seed_counter: int = 0
var game_session_id: String = ""

func _ready() -> void:
	if not FeatureFlags.MULTIPLAYER_ENABLED:
		print("NetworkManager: Multiplayer disabled via feature flag")
		return

	# Get references to other autoloads
	game_manager = get_node("/root/GameManager")
	game_state = get_node("/root/GameState")

	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# Create turn timer
	turn_timer = Timer.new()
	turn_timer.one_shot = true
	turn_timer.timeout.connect(_on_turn_timeout)
	add_child(turn_timer)

	# Initialize RNG session ID
	game_session_id = str(Time.get_unix_time_from_system())

	print("NetworkManager: Initialized")

# ============================================================================
# PHASE 1: CORE SYNC - Connection and State Synchronization
# ============================================================================

func create_host(port: int = 7777) -> int:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 1)  # Max 1 client (2 player game)

	if error != OK:
		print("NetworkManager: Failed to create host - ", error)
		return error

	multiplayer.multiplayer_peer = peer
	network_mode = NetworkMode.HOST
	peer_to_player_map[1] = 1  # Host is player 1

	print("NetworkManager: Hosting on port ", port)
	return OK

func join_as_client(ip: String, port: int = 7777) -> int:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)

	if error != OK:
		print("NetworkManager: Failed to connect to ", ip, ":", port, " - ", error)
		return error

	multiplayer.multiplayer_peer = peer
	network_mode = NetworkMode.CLIENT

	print("NetworkManager: Connecting to ", ip, ":", port)
	return OK

func is_host() -> bool:
	return network_mode == NetworkMode.HOST

func is_networked() -> bool:
	return network_mode != NetworkMode.OFFLINE

func disconnect_network() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	network_mode = NetworkMode.OFFLINE
	peer_to_player_map.clear()
	print("NetworkManager: Disconnected")

# Action submission and routing
func submit_action(action: Dictionary) -> void:
	print("NetworkManager: submit_action called for type: ", action.get("type"))
	print("NetworkManager: is_networked() = ", is_networked())

	if not is_networked():
		# Single player mode - apply directly
		print("NetworkManager: Single-player mode - applying directly")
		game_manager.apply_action(action)
		return

	if is_host():
		print("NetworkManager: Host mode - validating and applying")
		# Host validates and applies
		var peer_id = 1  # Host's own peer ID
		var validation = validate_action(action, peer_id)

		if not validation.valid:
			push_error("NetworkManager: Host action rejected: %s" % validation.get("reason", "Unknown reason"))
			return

		# Execute via GameManager
		var result = game_manager.apply_action(action)
		print("NetworkManager: Host applied action, result.success = ", result.success)
		if result.success:
			# Broadcast the result to client
			print("NetworkManager: Broadcasting result to clients")
			_broadcast_result.rpc(result)
	else:
		print("NetworkManager: Client mode - sending to host")
		# Client sends to host
		_send_action_to_host.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable")
func _send_action_to_host(action: Dictionary) -> void:
	if not is_host():
		print("NetworkManager: _send_action_to_host called on non-host, ignoring")
		return

	# Get sender peer ID
	var peer_id = multiplayer.get_remote_sender_id()
	print("NetworkManager: Host received action from client peer %d: %s" % [peer_id, action.get("type")])
	print("NetworkManager: Action details: ", action)

	# Phase 2: Validate action
	var validation = validate_action(action, peer_id)
	print("NetworkManager: Validation result: ", validation)

	if not validation.valid:
		var reason = validation.get("reason", "Unknown validation error")
		print("NetworkManager: REJECTING action: ", reason)
		_reject_action.rpc_id(peer_id, action.get("type", ""), reason)
		return

	print("NetworkManager: Action VALIDATED, applying via GameManager")
	# Execute via GameManager - this applies the state changes AND emits result_applied signal
	var result = game_manager.apply_action(action)
	print("NetworkManager: Host applied client action, result.success = ", result.success)

	if result.success:
		# Update phase snapshot so next validation sees the changes
		_update_phase_snapshot()

		# Broadcast the result to all clients (but not back to host since it already applied)
		print("NetworkManager: Host broadcasting client action result to all clients")
		_broadcast_result.rpc(result)
	else:
		print("NetworkManager: GameManager returned failure: ", result.get("error", "Unknown"))

@rpc("authority", "call_remote", "reliable")
func _broadcast_result(result: Dictionary) -> void:
	print("NetworkManager: _broadcast_result received, is_host = ", is_host())
	if is_host():
		return  # Host already applied locally

	# Client applies the result (with diffs already computed by host)
	print("NetworkManager: Client applying result with %d diffs" % result.get("diffs", []).size())
	game_manager.apply_result(result)

	# Update phase snapshot so it stays in sync with GameState
	_update_phase_snapshot()

	print("NetworkManager: Client finished applying result")

# Initial state sync when client joins
@rpc("authority", "call_remote", "reliable")
func _send_initial_state(snapshot: Dictionary) -> void:
	print("NetworkManager: Receiving initial state from host")

	# Replace local state with host's state
	game_state.load_from_snapshot(snapshot)

	print("NetworkManager: State synchronized")
	emit_signal("game_started")

# ============================================================================
# LOAD SYNCHRONIZATION - State sync after host loads a saved game
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_loaded_state(snapshot: Dictionary, save_name: String) -> void:
	"""
	Called by host to synchronize loaded game state to clients.
	Similar to _send_initial_state() but used for mid-game loads.
	"""
	print("NetworkManager: ========================================")
	print("NetworkManager: CLIENT RECEIVED LOADED STATE RPC")
	print("NetworkManager: ========================================")
	print("NetworkManager: Save name: ", save_name)
	print("NetworkManager: Snapshot keys: ", snapshot.keys())
	print("NetworkManager: Snapshot has ", snapshot.get("units", {}).size(), " units")
	print("NetworkManager: Snapshot turn: ", snapshot.get("meta", {}).get("turn_number", "unknown"))

	# Replace local state with host's loaded state
	print("NetworkManager: Applying loaded state to GameState...")
	game_state.load_from_snapshot(snapshot)
	print("NetworkManager: State applied, GameState now has ", game_state.state.get("units", {}).size(), " units")

	# Trigger UI refresh on client side
	print("NetworkManager: Triggering UI refresh on client...")
	_refresh_client_ui_after_load(snapshot)

	print("NetworkManager: Loaded state synchronized")
	print("NetworkManager: ========================================")

func _refresh_client_ui_after_load(snapshot: Dictionary) -> void:
	"""
	Triggers UI refresh on client after receiving loaded state.
	Notifies Main scene to refresh all game elements.
	"""
	# Get Main scene if it exists
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("_refresh_after_load"):
		print("NetworkManager: Triggering client UI refresh")
		main_scene._refresh_after_load()

		# Show notification to client
		if main_scene.has_method("_show_save_notification"):
			var turn = snapshot.get("meta", {}).get("turn_number", 0)
			var phase = snapshot.get("meta", {}).get("phase", "Unknown")
			main_scene._show_save_notification(
				"Host loaded game (Turn %d, %s)" % [turn, phase],
				Color.CYAN
			)
	else:
		print("NetworkManager: Warning - Could not trigger client UI refresh")

func sync_loaded_state() -> void:
	"""
	Called by SaveLoadManager after host loads a game.
	Broadcasts the loaded state to all connected clients.
	"""
	if not is_networked():
		print("NetworkManager: Not in multiplayer, skipping load sync")
		return

	if not is_host():
		push_error("NetworkManager: Only host can sync loaded state!")
		return

	print("NetworkManager: ========================================")
	print("NetworkManager: SYNCING LOADED STATE TO CLIENTS")
	print("NetworkManager: ========================================")

	# Create snapshot of current (newly loaded) state
	var snapshot = game_state.create_snapshot()
	print("NetworkManager: Created snapshot with keys: ", snapshot.keys())
	print("NetworkManager: Snapshot has ", snapshot.get("units", {}).size(), " units")
	print("NetworkManager: Snapshot turn: ", snapshot.get("meta", {}).get("turn_number", "unknown"))

	# Get save name from metadata if available
	var save_name = snapshot.get("meta", {}).get("save_name", "Unknown")

	# Check if we have connected peers
	var peer_count = multiplayer.get_peers().size()
	print("NetworkManager: Broadcasting to ", peer_count, " connected peers")
	print("NetworkManager: Connected peer IDs: ", multiplayer.get_peers())

	# Broadcast to all clients
	_send_loaded_state.rpc(snapshot, save_name)

	print("NetworkManager: Loaded state sync RPC sent")
	print("NetworkManager: ========================================")

# Initiates game start for both host and all clients
@rpc("authority", "call_local", "reliable")
func start_multiplayer_game() -> void:
	print("NetworkManager: Starting multiplayer game - transitioning to Main scene")
	print("NetworkManager: Units in GameState BEFORE scene change: ", game_state.state.get("units", {}).size())

	# DEBUG: Show unit IDs
	if game_state.state.has("units"):
		print("NetworkManager: Unit IDs: ", game_state.state.units.keys())

	# This runs on both host and client due to call_local
	var error = get_tree().change_scene_to_file("res://scenes/Main.tscn")
	if error != OK:
		push_error("NetworkManager: Failed to load Main scene: %d" % error)
		# Fallback: return to lobby
		get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")
		return

	# Emit local signal for any cleanup
	emit_signal("game_started")

# ============================================================================
# PHASE 2: VALIDATION - Action Validation and Authority
# ============================================================================

func validate_action(action: Dictionary, peer_id: int) -> Dictionary:
	print("NetworkManager: Validating action type=%s from peer_id=%d" % [action.get("type"), peer_id])

	# Layer 1: Schema validation
	if not action.has("type"):
		print("NetworkManager: VALIDATION FAILED - missing type")
		return {"valid": false, "reason": "Invalid action schema - missing type"}

	# Layer 2: Authority validation
	var claimed_player = action.get("player", -1)
	var peer_player = peer_to_player_map.get(peer_id, -1)
	print("NetworkManager: claimed_player=%d, peer_player=%d (from peer_to_player_map)" % [claimed_player, peer_player])
	print("NetworkManager: peer_to_player_map = ", peer_to_player_map)
	if claimed_player != peer_player:
		print("NetworkManager: VALIDATION FAILED - player mismatch")
		return {"valid": false, "reason": "Player ID mismatch (claimed=%d, expected=%d)" % [claimed_player, peer_player]}

	# Layer 3: Turn validation
	var active_player = game_state.get_active_player()
	print("NetworkManager: active_player=%d" % active_player)
	if claimed_player != active_player:
		print("NetworkManager: VALIDATION FAILED - not player's turn")
		return {"valid": false, "reason": "Not your turn"}

	# Layer 4: Game rules validation (delegate to phase)
	var phase_mgr = get_node("/root/PhaseManager")
	if phase_mgr:
		var phase = phase_mgr.get_current_phase_instance()
		if phase and phase.has_method("validate_action"):
			var phase_validation = phase.validate_action(action)
			print("NetworkManager: Phase validation result = ", phase_validation)
			return phase_validation

	print("NetworkManager: VALIDATION PASSED (no phase validation)")
	return {"valid": true}

@rpc("authority", "call_remote", "reliable")
func _reject_action(action_type: String, reason: String) -> void:
	push_error("NetworkManager: Action rejected: %s - %s" % [action_type, reason])
	# TODO: Show UI error message to player

# ============================================================================
# PHASE 3: TURN TIMER - Timeout Enforcement
# ============================================================================

func start_turn_timer() -> void:
	if not is_networked() or not is_host():
		return

	turn_timer.start(TURN_TIMEOUT_SECONDS)
	print("NetworkManager: Turn timer started - ", TURN_TIMEOUT_SECONDS, " seconds")

func stop_turn_timer() -> void:
	if turn_timer:
		turn_timer.stop()

func _on_turn_timeout() -> void:
	if not is_host():
		return

	print("NetworkManager: Turn timeout!")
	var current_player = game_state.get_active_player()
	var winner = 3 - current_player  # Other player wins (1->2, 2->1)

	_broadcast_game_over.rpc(winner, "turn_timeout")

@rpc("authority", "call_remote", "reliable")
func _broadcast_game_over(winner: int, reason: String) -> void:
	print("NetworkManager: Game over! Winner: Player %d (%s)" % [winner, reason])
	# TODO: Show game over UI with winner and reason

# Hook into phase changes to restart timer
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	if not is_networked():
		return

	# Restart timer on each phase change
	if is_host():
		start_turn_timer()

# ============================================================================
# PHASE 4: DETERMINISTIC RNG - Seed Generation
# ============================================================================

func get_next_rng_seed() -> int:
	if not is_networked():
		return -1  # Single player - non-deterministic

	if not is_host():
		push_error("NetworkManager: Only host can generate RNG seeds!")
		return -1

	rng_seed_counter += 1
	var seed_value = hash([game_session_id, rng_seed_counter, game_state.get_turn_number()])
	print("NetworkManager: Generated RNG seed: ", seed_value)
	return seed_value

# ============================================================================
# CONNECTION EVENTS
# ============================================================================

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected - ", peer_id)

	if is_host():
		# Assign player 2 to new peer
		peer_to_player_map[peer_id] = 2

		# Send full game state to joining client
		var snapshot = game_state.create_snapshot()
		_send_initial_state.rpc_id(peer_id, snapshot)

		emit_signal("peer_connected", peer_id)
		emit_signal("game_started")
	else:
		# Client successfully connected to host
		# The peer_id here is the server (always 1)
		print("NetworkManager: Successfully connected to host")
		emit_signal("peer_connected", peer_id)
		emit_signal("game_started")

func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer disconnected - ", peer_id)

	if peer_to_player_map.has(peer_id):
		peer_to_player_map.erase(peer_id)

	emit_signal("peer_disconnected", peer_id)

	# MVP: End game on disconnect
	push_error("Player disconnected - game ending")
	get_tree().quit()

func _on_connection_failed() -> void:
	print("NetworkManager: Connection failed")
	emit_signal("connection_failed", "Could not connect to host")
	network_mode = NetworkMode.OFFLINE

# ============================================================================
# PHASE SNAPSHOT MANAGEMENT
# ============================================================================

func _update_phase_snapshot() -> void:
	"""Update the current phase's snapshot after applying state changes"""
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager:
		return

	var current_phase = phase_manager.get_current_phase_instance()
	if not current_phase:
		return

	# Create fresh snapshot from current GameState
	var new_snapshot = game_state.create_snapshot()

	# Update phase's internal snapshot
	if current_phase.has_method("update_local_state"):
		current_phase.update_local_state(new_snapshot)
		print("NetworkManager: Updated phase snapshot with ", new_snapshot.get("units", {}).size(), " units")