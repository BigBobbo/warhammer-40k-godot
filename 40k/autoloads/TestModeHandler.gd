extends Node

# TestModeHandler - Handles command-line arguments for automated testing
# Allows the game to be launched in specific modes for integration testing

var is_test_mode: bool = false
var test_config: Dictionary = {}

# Test mode types
enum TestMode {
	NONE,
	AUTO_HOST,
	AUTO_JOIN,
	AUTO_LOAD
}

var current_test_mode: TestMode = TestMode.NONE

# Command simulation system
var _command_dir: String = ""
var _result_dir: String = ""
var _check_interval: float = 0.1  # Check every 100ms
var _time_since_check: float = 0.0
var _sequence_counter: int = 0

func _ready() -> void:
	_parse_command_line_arguments()

	if is_test_mode:
		print("========================================")
		print("   RUNNING IN TEST MODE")
		print("   Config: ", test_config)
		print("========================================")
		# Setup command directories
		_setup_command_directories()
		# Call setup on next frame to ensure everything is initialized
		call_deferred("_setup_test_mode")

func _parse_command_line_arguments():
	var args = OS.get_cmdline_args()

	for i in range(args.size()):
		var arg = args[i]

		# Check for test mode flag
		if arg == "--test-mode":
			is_test_mode = true
			continue

		# Instance name (for logging)
		if arg.begins_with("--instance-name="):
			test_config["instance_name"] = arg.split("=")[1]
			continue

		# Auto-host mode
		if arg == "--auto-host":
			current_test_mode = TestMode.AUTO_HOST
			test_config["is_host"] = true
			continue

		# Auto-join mode
		if arg == "--auto-join":
			current_test_mode = TestMode.AUTO_JOIN
			test_config["is_host"] = false
			continue

		# Port configuration
		if arg.begins_with("--port="):
			test_config["port"] = arg.split("=")[1].to_int()
			continue

		# Host IP for joining
		if arg.begins_with("--host-ip="):
			test_config["host_ip"] = arg.split("=")[1]
			continue

		# Host port for joining
		if arg.begins_with("--host-port="):
			test_config["host_port"] = arg.split("=")[1].to_int()
			continue

		# Auto-load save
		if arg.begins_with("--auto-load-save="):
			test_config["auto_load_save"] = arg.split("=")[1]
			continue

		# Window position
		if arg.begins_with("--position="):
			var pos_str = arg.split("=")[1]
			var pos_parts = pos_str.split(",")
			if pos_parts.size() == 2:
				var x = pos_parts[0].to_int()
				var y = pos_parts[1].to_int()
				test_config["window_position"] = Vector2i(x, y)
			continue

		# Window resolution
		if arg.begins_with("--resolution="):
			var res_str = arg.split("=")[1]
			var res_parts = res_str.split("x")
			if res_parts.size() == 2:
				var width = res_parts[0].to_int()
				var height = res_parts[1].to_int()
				test_config["window_size"] = Vector2i(width, height)
			continue

func _setup_test_mode():
	# Apply window configuration if specified
	if test_config.has("window_position"):
		var pos = test_config["window_position"]
		DisplayServer.window_set_position(pos)
		print("TestModeHandler: Set window position to ", pos)

	if test_config.has("window_size"):
		var size = test_config["window_size"]
		DisplayServer.window_set_size(size)
		print("TestModeHandler: Set window size to ", size)

	# Update window title with instance name
	if test_config.has("instance_name"):
		var title = "40k Test - " + test_config["instance_name"]
		DisplayServer.window_set_title(title)

	# Set up automatic actions based on mode
	match current_test_mode:
		TestMode.AUTO_HOST:
			_schedule_auto_host()
		TestMode.AUTO_JOIN:
			_schedule_auto_join()

func _schedule_auto_host():
	print("TestModeHandler: Scheduling auto-host...")

	# Wait for main menu to load and be ready
	await get_tree().create_timer(2.0).timeout

	var main_menu = get_tree().current_scene
	print("TestModeHandler: Current scene: ", main_menu.name if main_menu else "null")

	# Automatically click multiplayer and host
	if main_menu and main_menu.has_method("_on_multiplayer_button_pressed"):
		print("TestModeHandler: Triggering multiplayer mode...")
		main_menu._on_multiplayer_button_pressed()

		# Wait for scene change to complete
		await get_tree().create_timer(1.5).timeout

		# Now we should be in multiplayer lobby
		var lobby = get_tree().current_scene
		print("TestModeHandler: Lobby scene: ", lobby.name if lobby else "null")

		if lobby and lobby.has_method("_on_host_button_pressed"):
			print("TestModeHandler: Creating host on port ", test_config.get("port", 7777))
			lobby._on_host_button_pressed()

			# Wait for client to connect, then start the game
			print("TestModeHandler: Waiting for client to connect...")
			await _wait_for_peer_connection()

			# Client connected, now start the game
			await get_tree().create_timer(1.0).timeout
			print("TestModeHandler: Starting game...")
			if lobby.has_method("_on_start_game_button_pressed"):
				lobby._on_start_game_button_pressed()
			else:
				print("TestModeHandler: ERROR - Lobby doesn't have _on_start_game_button_pressed method")

			# Wait for game scene to load and verify phase initialization
			await get_tree().create_timer(3.0).timeout  # Increased wait time for scene load

			# Verify phase initialization with retry logic
			var max_retries = 10
			var retry_count = 0
			while retry_count < max_retries:
				var current_phase = GameState.get_current_phase()
				if current_phase == GameStateData.Phase.DEPLOYMENT:
					print("TestModeHandler: Game successfully in Deployment phase")
					break

				print("TestModeHandler: Waiting for Deployment phase (attempt %d/%d) - current phase: %d" % [retry_count+1, max_retries, current_phase])
				await get_tree().create_timer(0.5).timeout
				retry_count += 1

			if retry_count >= max_retries:
				push_error("TestModeHandler: Game failed to enter Deployment phase after %d attempts" % max_retries)

			# If we have a save to auto-load, schedule it
			if test_config.has("auto_load_save"):
				await get_tree().create_timer(2.0).timeout
				_auto_load_save(test_config["auto_load_save"])
		else:
			print("TestModeHandler: ERROR - Lobby scene doesn't have _on_host_button_pressed method")

func _schedule_auto_join():
	print("TestModeHandler: Scheduling auto-join...")

	# Wait for main menu to load and be ready
	await get_tree().create_timer(2.0).timeout

	var main_menu = get_tree().current_scene
	print("TestModeHandler: Current scene: ", main_menu.name if main_menu else "null")

	# Automatically click multiplayer and join
	if main_menu and main_menu.has_method("_on_multiplayer_button_pressed"):
		print("TestModeHandler: Triggering multiplayer mode...")
		main_menu._on_multiplayer_button_pressed()

		# Wait for scene change to complete
		await get_tree().create_timer(1.5).timeout

		# Now we should be in multiplayer lobby
		var lobby = get_tree().current_scene
		print("TestModeHandler: Lobby scene: ", lobby.name if lobby else "null")

		if lobby:
			# Set the IP address if we have an IP input field
			var ip_input = lobby.get_node_or_null("IPInput")
			if ip_input and ip_input is LineEdit:
				ip_input.text = test_config.get("host_ip", "127.0.0.1")
				print("TestModeHandler: Set IP to ", ip_input.text)

			# Join the game
			if lobby.has_method("_on_join_button_pressed"):
				print("TestModeHandler: Joining host at ", test_config.get("host_ip", "127.0.0.1"))
				lobby._on_join_button_pressed()
			else:
				print("TestModeHandler: ERROR - Lobby scene doesn't have _on_join_button_pressed method")

func _auto_load_save(save_path: String):
	print("TestModeHandler: Auto-loading save: ", save_path)

	# Trigger save load through SaveLoadManager
	if SaveLoadManager:
		# Add file extension if not present
		if not save_path.ends_with(".w40ksave"):
			save_path = save_path + ".w40ksave"

		# Check if it's a test save (in tests/saves/) or regular save (in saves/)
		# If path doesn't contain a directory separator, treat it as a test save
		if not save_path.contains("/"):
			save_path = "tests/saves/" + save_path
			print("TestModeHandler: Loading test save from: ", save_path)

		if SaveLoadManager.has_method("load_game"):
			SaveLoadManager.load_game(save_path)
			print("TestModeHandler: Called SaveLoadManager.load_game(%s)" % save_path)
		else:
			print("TestModeHandler: SaveLoadManager doesn't have load_game method")

func _wait_for_peer_connection() -> void:
	# Wait for NetworkManager to signal that a peer has connected
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		push_error("TestModeHandler: NetworkManager not found!")
		return

	# Check if already connected
	if network_manager.peer_to_player_map.size() > 1:
		print("TestModeHandler: Client already connected!")
		return

	# Wait for peer_connected signal
	print("TestModeHandler: Listening for peer connection...")
	await network_manager.peer_connected
	print("TestModeHandler: Client connected!")

func is_auto_host() -> bool:
	return current_test_mode == TestMode.AUTO_HOST

func is_auto_join() -> bool:
	return current_test_mode == TestMode.AUTO_JOIN

func get_test_instance_name() -> String:
	return test_config.get("instance_name", "Unknown")

func get_test_port() -> int:
	return test_config.get("port", 7777)

# ============================================================================
# Command Simulation System
# ============================================================================

func _setup_command_directories():
	# Setup directory paths
	_command_dir = OS.get_user_data_dir() + "/test_commands/commands/"
	_result_dir = OS.get_user_data_dir() + "/test_commands/results/"

	var base_dir = OS.get_user_data_dir() + "/test_commands"

	# Create directories if they don't exist
	var dir = DirAccess.open(OS.get_user_data_dir())
	if not dir:
		push_error("TestModeHandler: Failed to open user data dir")
		return

	if not dir.dir_exists("test_commands"):
		dir.make_dir("test_commands")

	dir = DirAccess.open(base_dir)
	if not dir:
		push_error("TestModeHandler: Failed to open test_commands dir")
		return

	if not dir.dir_exists("commands"):
		dir.make_dir("commands")
	if not dir.dir_exists("results"):
		dir.make_dir("results")

	print("TestModeHandler: Command directories ready")
	print("  Commands: ", _command_dir)
	print("  Results: ", _result_dir)

func _process(delta: float):
	if not is_test_mode:
		return

	_time_since_check += delta
	if _time_since_check >= _check_interval:
		_time_since_check = 0.0
		_check_for_commands()

func _check_for_commands():
	var dir = DirAccess.open(_command_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("."):
			_execute_command_file(file_name)
		file_name = dir.get_next()

	dir.list_dir_end()

func _execute_command_file(file_name: String):
	var file_path = _command_dir + file_name
	var file = FileAccess.open(file_path, FileAccess.READ)

	if not file:
		push_error("TestModeHandler: Failed to open command file: " + file_name)
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)

	if error != OK:
		push_error("TestModeHandler: Failed to parse command JSON: " + file_name)
		return

	var command_data = json.data
	var start_time = Time.get_ticks_msec()

	print("TestModeHandler: Executing command from file: ", file_name)

	# Execute the command
	var result = await _execute_command(command_data["command"])

	var execution_time = Time.get_ticks_msec() - start_time

	# Write result
	_write_result(file_name, command_data["sequence"], result, execution_time)

	# Delete command file
	DirAccess.remove_absolute(file_path)
	print("TestModeHandler: Command executed and result written")

func _execute_command(command: Dictionary) -> Dictionary:
	var action = command["action"]
	var params = command.get("parameters", {})

	print("TestModeHandler: Executing action: ", action)

	match action:
		"load_save":
			return await _handle_load_save(params)
		"deploy_unit":
			return _handle_deploy_unit(params)
		"undo_deployment":
			return _handle_undo_deployment(params)
		"complete_deployment":
			return _handle_complete_deployment(params)
		"get_game_state":
			return _handle_get_game_state(params)
		"get_available_units":
			return _handle_get_available_units(params)
		"capture_screenshot":
			return _handle_capture_screenshot(params)
		"save_game_state":
			return _handle_save_game_state(params)
		_:
			return {
				"success": false,
				"message": "Unknown action: " + action,
				"error": "UNKNOWN_ACTION"
			}

func _write_result(command_file: String, sequence: int, result: Dictionary, execution_time: int):
	var result_file_name = command_file.replace(".json", "_result.json")
	var result_path = _result_dir + result_file_name

	var result_data = {
		"version": "1.0",
		"timestamp": Time.get_ticks_msec(),
		"sequence": sequence,
		"execution_time_ms": execution_time,
		"result": result
	}

	var file = FileAccess.open(result_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result_data, "\t"))
		file.close()
		print("TestModeHandler: Result written to: ", result_file_name)
	else:
		push_error("TestModeHandler: Failed to write result file: " + result_path)

# ============================================================================
# Action Handlers
# ============================================================================

func _handle_load_save(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling load_save action")

	var save_name = params.get("save_name", "")

	if save_name.is_empty():
		return {
			"success": false,
			"message": "Missing save_name parameter",
			"error": "MISSING_PARAMETER"
		}

	# Build the full path for test saves
	var save_path = save_name

	# Add file extension if not present
	if not save_path.ends_with(".w40ksave"):
		save_path = save_path + ".w40ksave"

	# Check if it's a test save (in tests/saves/) or regular save (in saves/)
	var is_test_save = not save_path.contains("/")
	if is_test_save:
		# Build full path to test save: res://tests/saves/filename.w40ksave
		save_path = "res://tests/saves/" + save_path
		print("TestModeHandler: Loading test save from: ", save_path)
	else:
		# Regular save - ensure it has res:// prefix
		if not save_path.begins_with("res://"):
			save_path = "res://" + save_path
		print("TestModeHandler: Loading save from: ", save_path)

	var save_load_manager = get_node_or_null("/root/SaveLoadManager")
	if not save_load_manager:
		return {
			"success": false,
			"message": "SaveLoadManager not found",
			"error": "SAVE_LOAD_MANAGER_NOT_FOUND"
		}

	# Use _load_game_from_path for test saves (requires full path)
	# Use load_game for regular saves (uses save_directory)
	var load_success = false
	if is_test_save:
		if not save_load_manager.has_method("_load_game_from_path"):
			return {
				"success": false,
				"message": "SaveLoadManager doesn't have _load_game_from_path method",
				"error": "METHOD_NOT_FOUND"
			}
		load_success = save_load_manager._load_game_from_path(save_path)
		print("TestModeHandler: Called SaveLoadManager._load_game_from_path(%s), result: %s" % [save_path, load_success])
	else:
		if not save_load_manager.has_method("load_game"):
			return {
				"success": false,
				"message": "SaveLoadManager doesn't have load_game method",
				"error": "METHOD_NOT_FOUND"
			}
		load_success = save_load_manager.load_game(save_name)  # Use original name without path/extension
		print("TestModeHandler: Called SaveLoadManager.load_game(%s), result: %s" % [save_name, load_success])

	# Check if load was successful
	if not load_success:
		return {
			"success": false,
			"message": "Failed to load save file: " + save_path,
			"error": "LOAD_FAILED"
		}

	# Wait a moment for the save to fully process
	await get_tree().create_timer(0.5).timeout

	# Verify units were loaded
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.state.has("units"):
		var unit_count = game_state.state.units.size()
		var unit_ids = game_state.state.units.keys()
		print("TestModeHandler: Save loaded, %d units found" % unit_count)
		print("TestModeHandler: Unit IDs: %s" % str(unit_ids))

		return {
			"success": true,
			"message": "Save file loaded successfully",
			"data": {
				"save_path": save_path,
				"unit_count": unit_count,
				"unit_ids": unit_ids
			}
		}
	else:
		return {
			"success": false,
			"message": "Save loaded but no units found in GameState",
			"error": "NO_UNITS_LOADED"
		}

func _handle_deploy_unit(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling deploy_unit action")

	var unit_id = params.get("unit_id", "")
	var position = params.get("position", {})

	if unit_id.is_empty():
		return {
			"success": false,
			"message": "Missing unit_id parameter",
			"error": "MISSING_PARAMETER"
		}

	if not position.has("x") or not position.has("y"):
		return {
			"success": false,
			"message": "Missing position coordinates",
			"error": "MISSING_PARAMETER"
		}

	# Get GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return {
			"success": false,
			"message": "GameManager not found",
			"error": "GAME_MANAGER_NOT_FOUND"
		}

	# Check if we're in deployment phase (via GameState)
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		var current_phase = game_state.get_current_phase()
		if current_phase != game_state.Phase.DEPLOYMENT:
			return {
				"success": false,
				"message": "Not in deployment phase (current: %s)" % current_phase,
				"error": "INVALID_PHASE"
			}
	# If GameState not available, skip phase check (test environment)

	# Try to deploy the unit
	var pos_vector = Vector2(position["x"], position["y"])
	var success = game_manager.deploy_unit(unit_id, pos_vector)

	if success:
		return {
			"success": true,
			"message": "Unit deployed successfully",
			"data": {
				"unit_id": unit_id,
				"position": position
			}
		}
	else:
		return {
			"success": false,
			"message": "Failed to deploy unit (check deployment zone, terrain, etc.)",
			"error": "DEPLOYMENT_FAILED"
		}

func _handle_undo_deployment(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling undo_deployment action")

	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return {
			"success": false,
			"message": "GameManager not found",
			"error": "GAME_MANAGER_NOT_FOUND"
		}

	# Check if undo is available
	if not game_manager.has_method("undo_last_action"):
		return {
			"success": false,
			"message": "Undo not supported in this phase",
			"error": "UNDO_NOT_SUPPORTED"
		}

	var success = game_manager.undo_last_action()

	if success:
		return {
			"success": true,
			"message": "Deployment undone",
			"data": {}
		}
	else:
		return {
			"success": false,
			"message": "No action to undo",
			"error": "NO_ACTION_TO_UNDO"
		}

func _handle_complete_deployment(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling complete_deployment action")

	var player_id = params.get("player_id", 1)

	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return {
			"success": false,
			"message": "GameManager not found",
			"error": "GAME_MANAGER_NOT_FOUND"
		}

	# Mark deployment as complete
	if game_manager.has_method("complete_deployment"):
		var success = game_manager.complete_deployment(player_id)

		if success:
			return {
				"success": true,
				"message": "Player %d deployment complete" % player_id,
				"data": {
					"player_id": player_id,
					"deployment_complete": true
				}
			}
		else:
			return {
				"success": false,
				"message": "Failed to complete deployment",
				"error": "COMPLETION_FAILED"
			}
	else:
		return {
			"success": false,
			"message": "Complete deployment method not found",
			"error": "METHOD_NOT_FOUND"
		}

func _handle_get_game_state(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling get_game_state action")

	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return {
			"success": false,
			"message": "GameManager not found",
			"error": "GAME_MANAGER_NOT_FOUND"
		}

	# Get phase information from GameState
	var game_state = get_node_or_null("/root/GameState")
	var phase_name = "Unknown"
	if game_state:
		var current_phase = game_state.get_current_phase()
		# Convert enum to string
		match current_phase:
			game_state.Phase.DEPLOYMENT:
				phase_name = "Deployment"
			game_state.Phase.COMMAND:
				phase_name = "Command"
			game_state.Phase.MOVEMENT:
				phase_name = "Movement"
			game_state.Phase.SHOOTING:
				phase_name = "Shooting"
			game_state.Phase.CHARGE:
				phase_name = "Charge"
			game_state.Phase.FIGHT:
				phase_name = "Fight"
			game_state.Phase.SCORING:
				phase_name = "Scoring"
			game_state.Phase.MORALE:
				phase_name = "Morale"

	# Collect game state information
	var state_data = {
		"current_phase": phase_name,
		"current_turn": game_state.get("current_turn") if game_state and game_state.get("current_turn") != null else 0,
		"player_turn": game_state.get("active_player") if game_state and game_state.get("active_player") != null else 0,
		"units": {}
	}

	# Debug logging
	print("TestModeHandler: get_game_state - Phase: %s, Turn: %d, Player: %d" % [
		state_data["current_phase"],
		state_data["current_turn"],
		state_data["player_turn"]
	])

	# Try to get unit information
	if game_manager.has_method("get_all_units"):
		var units = game_manager.get_all_units()
		state_data["units"] = units

	return {
		"success": true,
		"message": "Game state retrieved",
		"data": state_data
	}

func _handle_get_available_units(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling get_available_units action")

	var game_state = get_node_or_null("/root/GameState")
	if not game_state:
		return {
			"success": false,
			"message": "GameState not found",
			"error": "GAME_STATE_NOT_FOUND"
		}

	# Get all units from GameState
	var all_units = game_state.state.get("units", {})

	# Organize units by player
	var player_1_units = []
	var player_2_units = []
	var undeployed_p1_units = []
	var undeployed_p2_units = []

	for unit_id in all_units:
		var unit = all_units[unit_id]
		var owner = unit.get("owner", 0)
		var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)

		if owner == 1:
			player_1_units.append(unit_id)
			if status == GameStateData.UnitStatus.UNDEPLOYED:
				undeployed_p1_units.append(unit_id)
		elif owner == 2:
			player_2_units.append(unit_id)
			if status == GameStateData.UnitStatus.UNDEPLOYED:
				undeployed_p2_units.append(unit_id)

	print("TestModeHandler: Player 1 units: %s (undeployed: %s)" % [player_1_units, undeployed_p1_units])
	print("TestModeHandler: Player 2 units: %s (undeployed: %s)" % [player_2_units, undeployed_p2_units])

	return {
		"success": true,
		"message": "Available units retrieved",
		"data": {
			"player_1_units": player_1_units,
			"player_2_units": player_2_units,
			"player_1_undeployed": undeployed_p1_units,
			"player_2_undeployed": undeployed_p2_units,
			"total_units": all_units.size()
		}
	}

func _handle_capture_screenshot(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling capture_screenshot action")

	var filename = params.get("filename", "screenshot_%s.png" % Time.get_ticks_msec())
	var artifacts_dir = OS.get_user_data_dir() + "/test_artifacts/screenshots/"

	# Ensure directory exists
	var dir = DirAccess.open(OS.get_user_data_dir())
	if not dir.dir_exists("test_artifacts"):
		dir.make_dir("test_artifacts")
	if not dir.dir_exists("test_artifacts/screenshots"):
		dir.make_dir("test_artifacts/screenshots")

	var full_path = artifacts_dir + filename

	# Capture screenshot
	var viewport = get_tree().root.get_viewport()
	var image = viewport.get_texture().get_image()
	var error = image.save_png(full_path)

	if error == OK:
		return {
			"success": true,
			"message": "Screenshot captured",
			"path": full_path
		}
	else:
		return {
			"success": false,
			"message": "Failed to save screenshot",
			"error": "SCREENSHOT_FAILED"
		}

func _handle_save_game_state(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling save_game_state action")

	var save_name = params.get("save_name", "test_state_%s" % Time.get_ticks_msec())
	var save_dir = params.get("save_dir", "test_artifacts/saves/")

	var save_load_manager = get_node_or_null("/root/SaveLoadManager")
	if not save_load_manager:
		return {
			"success": false,
			"message": "SaveLoadManager not found",
			"error": "SAVE_LOAD_MANAGER_NOT_FOUND"
		}

	# Ensure test artifacts directory exists
	var user_data_dir = OS.get_user_data_dir()
	var dir = DirAccess.open(user_data_dir)
	if not dir.dir_exists("test_artifacts"):
		dir.make_dir("test_artifacts")
	if not dir.dir_exists("test_artifacts/saves"):
		dir.make_dir("test_artifacts/saves")

	# Save the game state
	var success = save_load_manager.save_game(save_name)

	if success:
		var save_path = save_load_manager.save_directory + save_name + ".w40ksave"
		return {
			"success": true,
			"message": "Game state saved",
			"path": save_path,
			"save_name": save_name
		}
	else:
		return {
			"success": false,
			"message": "Failed to save game state",
			"error": "SAVE_FAILED"
		}