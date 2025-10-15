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

	# Update window title to show player number
	DisplayServer.window_set_title("40k Game - PLAYER 1 (HOST)")

	print("========================================")
	print("   YOU ARE: PLAYER 1 (HOST)")
	print("   Hosting on port: ", port)
	print("========================================")
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
			# Get error message from either "reason" or first "errors" entry
			var error_msg = validation.get("reason", "Validation failed")
			if error_msg == "Validation failed" and validation.has("errors") and validation.errors.size() > 0:
				error_msg = validation.errors[0]
			print("NetworkManager: Host validation failed: ", error_msg)
			print("NetworkManager: Full validation result: ", validation)
			push_error("NetworkManager: Host action rejected: %s" % error_msg)

			# Notify UI of validation failure
			if has_node("/root/Main"):
				var main = get_node("/root/Main")
				if main.has_method("show_error_toast"):
					main.call_deferred("show_error_toast", error_msg)

			return

		# Execute via GameManager
		var result = game_manager.apply_action(action)
		print("NetworkManager: Host applied action, result.success = ", result.success)

		# CRITICAL LOGGING: Check if result contains sequential_pause for APPLY_SAVES
		if action.get("type") == "APPLY_SAVES":
			print("╔═══════════════════════════════════════════════════════════════")
			print("║ HOST APPLIED OWN APPLY_SAVES - CHECKING RESULT")
			print("║ result.success: ", result.success)
			print("║ result.sequential_pause: ", result.get("sequential_pause", false))
			print("║ result.remaining_weapons: ", result.get("remaining_weapons", []).size() if result.has("remaining_weapons") else "MISSING")
			print("║ result.current_weapon_index: ", result.get("current_weapon_index", -1))
			print("╚═══════════════════════════════════════════════════════════════")

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
		# Get reason from either "reason" field or first error in "errors" array
		var reason = validation.get("reason", "Unknown validation error")
		if reason == "Unknown validation error" and validation.has("errors") and validation.errors.size() > 0:
			reason = validation.errors[0]
		print("NetworkManager: REJECTING action: ", reason)
		print("NetworkManager: Full validation result: ", validation)
		_reject_action.rpc_id(peer_id, action.get("type", ""), reason)
		return

	print("NetworkManager: Action VALIDATED, applying via GameManager")
	# Execute via GameManager - this applies the state changes AND emits result_applied signal
	var result = game_manager.apply_action(action)
	print("NetworkManager: Host applied client action, result.success = ", result.success)

	# CRITICAL LOGGING: Check if result contains sequential_pause for APPLY_SAVES
	if action.get("type") == "APPLY_SAVES":
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ HOST APPLIED CLIENT APPLY_SAVES - CHECKING RESULT")
		print("║ result.success: ", result.success)
		print("║ result.sequential_pause: ", result.get("sequential_pause", false))
		print("║ result.remaining_weapons: ", result.get("remaining_weapons", []).size() if result.has("remaining_weapons") else "MISSING")
		print("║ result.current_weapon_index: ", result.get("current_weapon_index", -1))
		print("╚═══════════════════════════════════════════════════════════════")

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
	print("NetworkManager: Result keys: ", result.keys())
	print("NetworkManager: Action type: ", result.get("action_type", "NONE"))
	print("NetworkManager: Has save_data_list: ", result.has("save_data_list"))
	if result.has("save_data_list"):
		print("NetworkManager: save_data_list size: ", result.get("save_data_list", []).size())

	if is_host():
		return  # Host already applied locally

	# Client applies the result (with diffs already computed by host)
	print("NetworkManager: Client applying result with %d diffs" % result.get("diffs", []).size())
	game_manager.apply_result(result)

	# Update phase snapshot so it stays in sync with GameState
	_update_phase_snapshot()

	# MULTIPLAYER FIX: Re-emit phase-specific signals for client visual updates
	# When host applies actions, it emits signals that update visuals
	# Clients need to emit the same signals after applying results
	print("NetworkManager: Client calling _emit_client_visual_updates")
	_emit_client_visual_updates(result)

	print("NetworkManager: Client finished applying result")

func _emit_client_visual_updates(result: Dictionary) -> void:
	"""Emit phase-specific signals on client after applying result for visual updates"""
	print("NetworkManager: _emit_client_visual_updates START")
	var action_type = result.get("action_type", "")
	var action_data = result.get("action_data", {})
	print("NetworkManager:   action_type = ", action_type)

	# Get current phase instance
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager:
		print("NetworkManager:   ERROR - PhaseManager not found!")
		return
	if not phase_manager.current_phase_instance:
		print("NetworkManager:   ERROR - No current_phase_instance!")
		return

	var phase = phase_manager.current_phase_instance
	print("NetworkManager:   phase = ", phase)
	print("NetworkManager:   phase has saves_required signal: ", phase.has_signal("saves_required"))

	# Handle movement phase visual updates
	if action_type == "STAGE_MODEL_MOVE":
		if phase.has_signal("model_drop_committed"):
			var unit_id = action_data.get("actor_unit_id", "")
			var model_id = action_data.get("payload", {}).get("model_id", "")
			var dest = action_data.get("payload", {}).get("dest", [])

			if unit_id != "" and model_id != "" and dest.size() == 2:
				var dest_vec = Vector2(dest[0], dest[1])
				print("NetworkManager: Client emitting model_drop_committed for ", unit_id, "/", model_id, " at ", dest_vec)
				phase.emit_signal("model_drop_committed", unit_id, model_id, dest_vec)

	# Handle shooting phase SELECT_SHOOTER visual updates
	if action_type == "SELECT_SHOOTER":
		if phase.has_signal("unit_selected_for_shooting"):
			var unit_id = action_data.get("actor_unit_id", "")
			if unit_id != "":
				print("NetworkManager: Client emitting unit_selected_for_shooting for ", unit_id)
				phase.emit_signal("unit_selected_for_shooting", unit_id)

				# Also emit targets_available with eligible targets
				if phase.has_signal("targets_available"):
					var eligible_targets = RulesEngine.get_eligible_targets(unit_id, GameState.create_snapshot())
					print("NetworkManager: Client emitting targets_available with %d targets" % eligible_targets.size())
					phase.emit_signal("targets_available", unit_id, eligible_targets)

	# Handle shooting phase weapon_order_required signal
	# This happens when CONFIRM_TARGETS detects multiple weapon types
	print("NetworkManager:   Checking for weapon_order_required...")
	if action_type == "CONFIRM_TARGETS":
		var weapon_order_required = result.get("weapon_order_required", false)
		print("NetworkManager:   weapon_order_required = ", weapon_order_required)

		if weapon_order_required and phase.has_signal("weapon_order_required"):
			var confirmed_assignments = result.get("confirmed_assignments", [])
			print("NetworkManager: ✅ Client re-emitting weapon_order_required signal with %d assignments" % confirmed_assignments.size())
			phase.emit_signal("weapon_order_required", confirmed_assignments)

			# Also update the client's phase resolution_state
			if "resolution_state" in phase:
				phase.resolution_state = {
					"phase": "awaiting_weapon_order",
					"assignments": confirmed_assignments
				}
				print("NetworkManager: ✅ Client updated resolution_state")

	# Handle next_weapon_confirmation_required signal for sequential mode
	# This happens when APPLY_SAVES completes OR when RESOLVE_WEAPON_SEQUENCE has no wounds (miss) OR when CONTINUE_SEQUENCE needs next weapon
	# OR when CONFIRM_TARGETS resolves a single weapon that misses (no saves needed)
	print("NetworkManager:   Checking for sequential_pause...")
	if action_type == "APPLY_SAVES" or action_type == "RESOLVE_WEAPON_SEQUENCE" or action_type == "CONTINUE_SEQUENCE" or action_type == "CONFIRM_TARGETS":
		var sequential_pause = result.get("sequential_pause", false)
		print("NetworkManager:   sequential_pause = ", sequential_pause)

		if sequential_pause and phase.has_signal("next_weapon_confirmation_required"):
			var remaining_weapons = result.get("remaining_weapons", [])
			var current_index = result.get("current_weapon_index", 0)
			var last_weapon_result = result.get("last_weapon_result", {})

			print("╔═══════════════════════════════════════════════════════════════")
			print("║ CLIENT RE-EMITTING next_weapon_confirmation_required")
			print("║ Action type: ", action_type)
			print("║ remaining_weapons.size(): ", remaining_weapons.size())
			print("║ current_index: ", current_index)
			print("║ last_weapon_result.size(): ", last_weapon_result.size())
			print("║ last_weapon_result.weapon_name: ", last_weapon_result.get("weapon_name", "MISSING"))
			print("║ Local peer: ", multiplayer.get_unique_id())
			print("║ Local player: ", peer_to_player_map.get(multiplayer.get_unique_id(), -1))
			print("║ Active player: ", game_state.get_active_player() if game_state else -1)

			# Validate remaining weapons
			for i in range(remaining_weapons.size()):
				var weapon = remaining_weapons[i]
				print("║   Weapon %d: %s" % [i, weapon.get("weapon_id", "MISSING")])

			print("╚═══════════════════════════════════════════════════════════════")

			print("NetworkManager: ✅ Client re-emitting next_weapon_confirmation_required with %d remaining weapons" % remaining_weapons.size())
			phase.emit_signal("next_weapon_confirmation_required", remaining_weapons, current_index, last_weapon_result)
		else:
			if not sequential_pause:
				print("NetworkManager: ℹ️ No sequential_pause in result - NOT re-emitting signal")
			elif not phase.has_signal("next_weapon_confirmation_required"):
				print("NetworkManager: ⚠️ Phase doesn't have next_weapon_confirmation_required signal!")

	# Handle dice_rolled signal - re-emit dice data so attacker sees updates
	# This happens when actions contain dice data (hits, wounds, etc.)
	print("NetworkManager:   Checking for dice data...")
	var dice_data = result.get("dice", [])
	if not dice_data.is_empty() and phase.has_signal("dice_rolled"):
		print("NetworkManager: ✅ Client re-emitting dice_rolled signals for %d dice blocks" % dice_data.size())
		for dice_block in dice_data:
			phase.emit_signal("dice_rolled", dice_block)

	# Handle shooting phase saves_required signal
	# This happens when CONFIRM_TARGETS, RESOLVE_SHOOTING, RESOLVE_WEAPON_SEQUENCE, or APPLY_SAVES needs saves
	print("NetworkManager:   Checking for saves_required...")
	print("NetworkManager:   action_type == CONFIRM_TARGETS: ", action_type == "CONFIRM_TARGETS")
	print("NetworkManager:   action_type == RESOLVE_SHOOTING: ", action_type == "RESOLVE_SHOOTING")
	print("NetworkManager:   action_type == RESOLVE_WEAPON_SEQUENCE: ", action_type == "RESOLVE_WEAPON_SEQUENCE")
	print("NetworkManager:   action_type == APPLY_SAVES: ", action_type == "APPLY_SAVES")

	if action_type == "CONFIRM_TARGETS" or action_type == "RESOLVE_SHOOTING" or action_type == "RESOLVE_WEAPON_SEQUENCE" or action_type == "APPLY_SAVES":
		var save_data_list = result.get("save_data_list", [])

		if not save_data_list.is_empty() and phase.has_signal("saves_required"):
			# NEW: Only re-emit if local player is the defender
			var first_save_data = save_data_list[0]
			var target_unit_id = first_save_data.get("target_unit_id", "")

			if target_unit_id != "":
				var target_unit = GameState.get_unit(target_unit_id)
				var defender_player = target_unit.get("owner", -1)

				var local_peer_id = multiplayer.get_unique_id()
				var local_player = peer_to_player_map.get(local_peer_id, -1)

				print("NetworkManager:   Defender check: local=%d, defender=%d" % [local_player, defender_player])

				if local_player == defender_player:
					# LOGGING: Track NetworkManager re-emission
					var timestamp = Time.get_ticks_msec()
					var weapon = first_save_data.get("weapon_name", "unknown")
					var wounds = first_save_data.get("wounds_to_save", 0)

					print("╔═══════════════════════════════════════════════════════════════")
					print("║ SAVES_REQUIRED RE-EMISSION (from NetworkManager)")
					print("║ Timestamp: ", timestamp)
					print("║ Source: NetworkManager._emit_client_visual_updates")
					print("║ Action Type: ", action_type)
					print("║ Local peer ID: ", local_peer_id)
					print("║ Local player: ", local_player)
					print("║ Defender player: ", defender_player)
					print("║ Target: ", target_unit_id)
					print("║ Weapon: ", weapon)
					print("║ Wounds: ", wounds)
					print("║ Save data list size: ", save_data_list.size())
					print("╚═══════════════════════════════════════════════════════════════")

					print("NetworkManager: ✅ Client (defender) re-emitting saves_required signal")
					phase.emit_signal("saves_required", save_data_list)

					# Also store the pending_save_data on the client's phase instance
					if "pending_save_data" in phase:
						phase.pending_save_data = save_data_list
						print("NetworkManager: ✅ Client stored pending_save_data")
				else:
					print("NetworkManager: ℹ️ Client (attacker) skipping saves_required re-emission - local=%d is not defender=%d" % [local_player, defender_player])
			else:
				print("NetworkManager:   ⚠️ No target_unit_id, skipping saves_required check")

	print("NetworkManager: _emit_client_visual_updates END")

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

	# Check if this is a phase control action or reactive action that bypasses player/turn validation
	var action_type = action.get("type", "")
	var exempt_actions = [
		"END_DEPLOYMENT",
		"END_PHASE",
		"EMBARK_UNITS_DEPLOYMENT",
		"APPLY_SAVES"  # Reactive action - defender responds during attacker's turn
	]
	var is_exempt = action_type in exempt_actions

	if is_exempt:
		print("NetworkManager: Exempt action '%s' - skipping turn validation (allows reactive actions)" % action_type)
		# Skip turn validation for exempt actions - go straight to game rules validation
		# EMBARK_UNITS_DEPLOYMENT: part of the deployment action that just switched turns
		# APPLY_SAVES: reactive action where defender responds during attacker's turn

		# Still validate player authority (that the peer is who they claim to be)
		if action_type == "APPLY_SAVES":
			var claimed_player = action.get("player", -1)
			var peer_player = peer_to_player_map.get(peer_id, -1)
			print("NetworkManager: APPLY_SAVES authority check - claimed=%d, peer=%d" % [claimed_player, peer_player])
			if claimed_player != peer_player:
				print("NetworkManager: VALIDATION FAILED - player mismatch for APPLY_SAVES")
				return {"valid": false, "reason": "Player ID mismatch (claimed=%d, expected=%d)" % [claimed_player, peer_player]}
	else:
		# Layer 2: Authority validation (only for player-specific actions)
		var claimed_player = action.get("player", -1)
		var peer_player = peer_to_player_map.get(peer_id, -1)
		print("NetworkManager: claimed_player=%d, peer_player=%d (from peer_to_player_map)" % [claimed_player, peer_player])
		print("NetworkManager: peer_to_player_map = ", peer_to_player_map)
		if claimed_player != peer_player:
			print("NetworkManager: VALIDATION FAILED - player mismatch")
			return {"valid": false, "reason": "Player ID mismatch (claimed=%d, expected=%d)" % [claimed_player, peer_player]}

		# Layer 3: Turn validation (only for player-specific actions)
		var active_player = game_state.get_active_player()
		print("NetworkManager: active_player=%d" % active_player)
		if claimed_player != active_player:
			print("NetworkManager: VALIDATION FAILED - not player's turn")
			return {"valid": false, "reason": "Not your turn"}

	# Layer 4: Game rules validation (delegate to phase)
	var phase_mgr = get_node("/root/PhaseManager")
	print("NetworkManager: phase_mgr = ", phase_mgr)
	if phase_mgr:
		var phase = phase_mgr.get_current_phase_instance()
		print("NetworkManager: current_phase_instance = ", phase)
		if phase:
			print("NetworkManager: phase class = ", phase.get_class())
			print("NetworkManager: phase has validate_action? ", phase.has_method("validate_action"))
		if phase and phase.has_method("validate_action"):
			print("NetworkManager: Calling phase.validate_action()")
			var phase_validation = phase.validate_action(action)
			print("NetworkManager: Phase validation result = ", phase_validation)
			return phase_validation
		else:
			print("NetworkManager: No phase or no validate_action method")

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
		# Client is always player 2
		var my_peer_id = multiplayer.get_unique_id()
		peer_to_player_map[my_peer_id] = 2
		print("NetworkManager: Client set peer_to_player_map[%d] = 2" % my_peer_id)

		# Update window title to show player number
		DisplayServer.window_set_title("40k Game - PLAYER 2 (CLIENT)")

		print("========================================")
		print("   YOU ARE: PLAYER 2 (CLIENT)")
		print("   Connected to host")
		print("========================================")

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