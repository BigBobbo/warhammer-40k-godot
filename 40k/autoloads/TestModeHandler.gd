extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# TestModeHandler - Handles command-line arguments for automated testing
# Allows the game to be launched in specific modes for integration testing

var is_test_mode: bool = false
var test_config: Dictionary = {}

# Test mode types
enum TestMode {
	NONE,
	AUTO_HOST,
	AUTO_JOIN,
	AUTO_LOAD,
	AI_VS_AI
}

var current_test_mode: TestMode = TestMode.NONE

# Command simulation system
var _command_dir: String = ""
var _result_dir: String = ""
var _command_dir_res: String = ""
var _result_dir_res: String = ""
var _check_interval: float = 0.1  # Check every 100ms
var _time_since_check: float = 0.0
var _sequence_counter: int = 0
var _game_state_cache = null
# In-flight set: tracks command filenames currently being executed.
# Prevents the 100ms scanner from re-picking up a command file while an async
# handler is mid-await (e.g. _handle_use_grenade_stratagem yields to the
# stratagem flow → NetworkManager → signal handlers, during which time the
# command file still exists on disk because deletion happens after the await
# returns). Without this guard, the same command runs twice; the second
# invocation finds the phase torn down and clobbers the success result with
# "No active phase instance". See task notes / `/tmp/mp_run4.log`.
var _commands_in_flight: Dictionary = {}
const COMMANDS_SUBDIR := "test_results/test_commands/commands"
const RESULTS_SUBDIR := "test_results/test_commands/results"
const TEST_ARTIFACTS_SUBDIR := "test_results/test_artifacts"
const TEST_SAVES_SUBDIR := "test_results/test_artifacts/saves"

func _init():
	_parse_command_line_arguments()

func _gs():
	if _game_state_cache == null:
		_game_state_cache = get_node_or_null("/root/GameState")
	return _game_state_cache

func _ready() -> void:
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
	var user_args = OS.get_cmdline_user_args()
	# Merge both engine args and user args (after --)
	var all_args = args + user_args
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("test_results/test_commands")
	var args_file = FileAccess.open("res://test_results/test_commands/args_log.txt", FileAccess.WRITE_READ)
	if args_file:
		args_file.seek_end()
		args_file.store_line("ARGS: " + str(all_args))
		args_file.close()
	print("TestModeHandler: Args -> ", all_args)
	args = all_args

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

		# Deployment type override
		if arg.begins_with("--deployment="):
			test_config["deployment"] = arg.split("=")[1]
			print("TestModeHandler: Deployment type override: %s" % test_config["deployment"])
			continue

		# AI vs AI mode - auto-start with both players as AI
		if arg == "--ai-vs-ai":
			current_test_mode = TestMode.AI_VS_AI
			is_test_mode = true
			test_config["ai_vs_ai"] = true
			print("TestModeHandler: AI vs AI mode enabled")
			continue

func _setup_test_mode():
	set_process(true)
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
		TestMode.AI_VS_AI:
			_schedule_ai_vs_ai()

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

			# Wait for scene to change to Main
			await get_tree().create_timer(2.0).timeout

			# IMPORTANT: Initialize deployment phase if not already initialized
			var phase_mgr = get_node_or_null("/root/PhaseManager")
			if phase_mgr and not phase_mgr.current_phase_instance:
				print("TestModeHandler: Initializing deployment phase in PhaseManager")
				phase_mgr.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
				await get_tree().process_frame  # Let phase initialize
			elif phase_mgr and phase_mgr.current_phase_instance:
				print("TestModeHandler: PhaseManager already has phase instance")

			# Wait for game scene to load and verify phase initialization
			await get_tree().create_timer(3.0).timeout  # Increased wait time for scene load

			# Wait for GameState singleton to be ready before checking phase
			var max_gs_retries = 20
			var gs_retry_count = 0
			while gs_retry_count < max_gs_retries:
				var gs = _gs()
				if gs and gs.has_method("get_current_phase"):
					print("TestModeHandler: GameState singleton is ready")
					break
				print("TestModeHandler: Waiting for GameState singleton (attempt %d/%d)" % [gs_retry_count+1, max_gs_retries])
				await get_tree().process_frame
				gs_retry_count += 1

			if gs_retry_count >= max_gs_retries:
				push_error("TestModeHandler: GameState singleton failed to initialize after %d attempts" % max_gs_retries)
				return

			# Verify phase initialization with retry logic
			var max_retries = 10
			var retry_count = 0
			while retry_count < max_retries:
				var current_phase = _gs().get_current_phase()
				if current_phase == GameStateData.Phase.DEPLOYMENT:
					print("TestModeHandler: Game successfully in Deployment phase")

					# IMPORTANT: Ensure PhaseManager has a phase instance
					var phase_mgr_check = get_node_or_null("/root/PhaseManager")
					if phase_mgr_check and not phase_mgr_check.current_phase_instance:
						print("TestModeHandler: PhaseManager has no instance - initializing deployment phase")
						phase_mgr_check.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
						await get_tree().process_frame  # Let the phase initialize
					elif phase_mgr_check and phase_mgr_check.current_phase_instance:
						print("TestModeHandler: PhaseManager already has phase instance")

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

func _schedule_ai_vs_ai():
	print("TestModeHandler: Scheduling AI vs AI auto-start...")

	# Wait for main menu to load and be ready
	await get_tree().create_timer(1.0).timeout

	var main_menu = get_tree().current_scene
	print("TestModeHandler: Current scene: ", main_menu.name if main_menu else "null")

	if main_menu and main_menu.has_method("_on_start_button_pressed"):
		# Set both player types to AI
		if main_menu.get("player1_type_dropdown"):
			main_menu.player1_type_dropdown.selected = 1  # AI
			print("TestModeHandler: Set Player 1 to AI")
		if main_menu.get("player2_type_dropdown"):
			main_menu.player2_type_dropdown.selected = 1  # AI
			print("TestModeHandler: Set Player 2 to AI")

		# Set deployment type if specified
		var deploy_override = test_config.get("deployment", "")
		if deploy_override != "" and main_menu.get("deployment_dropdown"):
			var deploy_options = main_menu.get("deployment_options")
			if deploy_options:
				for i in range(deploy_options.size()):
					if deploy_options[i].id == deploy_override:
						main_menu.deployment_dropdown.selected = i
						print("TestModeHandler: Set deployment to %s (index %d)" % [deploy_override, i])
						break

		# Trigger start
		print("TestModeHandler: Starting AI vs AI game...")
		main_menu._on_start_button_pressed()
	else:
		print("TestModeHandler: ERROR - Main menu not ready or missing _on_start_button_pressed")

func is_ai_vs_ai() -> bool:
	return current_test_mode == TestMode.AI_VS_AI

func _auto_load_save(save_path: String):
	print("TestModeHandler: Auto-loading save: ", save_path)

	# Trigger save load through SaveLoadManager
	var save_manager = get_node_or_null("/root/SaveLoadManager")
	if save_manager:
		# Add file extension if not present
		if not save_path.ends_with(".w40ksave"):
			save_path = save_path + ".w40ksave"

		# Check if it's a test save (in tests/saves/) or regular save (in saves/)
		# If path doesn't contain a directory separator, treat it as a test save
		if not save_path.contains("/"):
			save_path = "tests/saves/" + save_path
			print("TestModeHandler: Loading test save from: ", save_path)

		if save_manager.has_method("load_game"):
			save_manager.load_game(save_path)
			print("TestModeHandler: Called SaveLoadManager.load_game(%s)" % save_path)
		else:
			print("TestModeHandler: SaveLoadManager doesn't have load_game method")
	else:
		print("TestModeHandler: SaveLoadManager not available; skipping auto-load")

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
	var root = DirAccess.open("res://")
	if not root:
		push_error("TestModeHandler: Failed to open project root")
		return

	root.make_dir_recursive(COMMANDS_SUBDIR)
	root.make_dir_recursive(RESULTS_SUBDIR)

	_command_dir = ProjectSettings.globalize_path("res://" + COMMANDS_SUBDIR)
	_result_dir = ProjectSettings.globalize_path("res://" + RESULTS_SUBDIR)
	_command_dir_res = "res://" + COMMANDS_SUBDIR  # Set the res:// path for checking

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
	var dir = DirAccess.open(_command_dir_res)
	if not dir:
		print("TestModeHandler: Command directory not accessible: ", _command_dir_res)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("."):
			# Skip if this command is already in flight (handler is mid-await).
			# Without this, the 100ms scan loop re-enters _execute_command_file
			# for the same file before the first invocation gets a chance to
			# delete it after its internal await completes — causing a phantom
			# second execution that overwrites the real result with a bogus
			# "No active phase instance" failure (the original phase was torn
			# down by the time the duplicate runs).
			if _commands_in_flight.has(file_name):
				file_name = dir.get_next()
				continue
			print("TestModeHandler: Processing command file ", file_name)
			_execute_command_file(file_name)
		file_name = dir.get_next()

	dir.list_dir_end()

func _execute_command_file(file_name: String):
	# Mark this command as in-flight BEFORE any await or early-return paths so
	# a concurrent _check_for_commands cannot re-enter for the same filename.
	# Cleanup happens in the cleanup block at the bottom of this function.
	_commands_in_flight[file_name] = true

	var file_path = _command_dir + "/" + file_name
	var file = FileAccess.open(file_path, FileAccess.READ)

	if not file:
		push_error("TestModeHandler: Failed to open command file: " + file_name)
		_commands_in_flight.erase(file_name)
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)

	if error != OK:
		push_error("TestModeHandler: Failed to parse command JSON: " + file_name)
		_commands_in_flight.erase(file_name)
		return

	var command_data = json.data
	var start_time = Time.get_ticks_msec()

	print("TestModeHandler: Executing command from file: ", file_name)

	# Execute the command (may internally await across signal handlers)
	var result = await _execute_command(command_data["command"])

	var execution_time = Time.get_ticks_msec() - start_time

	# Write result
	_write_result(file_name, command_data["sequence"], result, execution_time)

	# Delete command file
	DirAccess.remove_absolute(file_path)
	# Clear the in-flight marker now that the result is on disk and the
	# command file is removed. Erasing AFTER deletion guarantees that even if
	# the OS hasn't fully flushed the unlink yet, the next scanner tick that
	# might race with this still sees the in-flight marker and skips.
	_commands_in_flight.erase(file_name)
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
		"select_shooter":
			return _handle_select_shooter(params)
		"assign_target":
			return _handle_assign_target(params)
		"clear_assignment":
			return _handle_clear_assignment(params)
		"confirm_targets":
			return _handle_confirm_targets(params)
		"complete_shooting_for_unit":
			return _handle_complete_shooting_for_unit(params)
		"use_grenade_stratagem":
			return _handle_use_grenade_stratagem(params)
		"transition_to_phase":
			return await _handle_transition_to_phase(params)
		_:
			return {
				"success": false,
				"message": "Unknown action: " + action,
				"error": "UNKNOWN_ACTION"
			}

func _write_result(command_file: String, sequence: int, result: Dictionary, execution_time: int):
	var result_file_name = command_file.replace(".json", "_result.json")
	var result_path = _result_dir + "/" + result_file_name

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
		var bare_name = save_name.get_file().get_basename() if save_name.contains("/") else save_name
		load_success = save_load_manager.load_game(bare_name)
		print("TestModeHandler: Called SaveLoadManager.load_game(%s), result: %s" % [save_name, load_success])

	# Check if load was successful
	if not load_success:
		return {
			"success": false,
			"message": "Failed to load save file: " + save_path,
			"error": "LOAD_FAILED"
		}

	# Mirror the MainMenu load flow (`scripts/MainMenu.gd:945-952`) so the
	# loaded state actually drives a fresh Main scene with a real phase
	# instance. Without this, SaveLoadManager populates GameState.state but
	# PhaseManager never constructs a phase instance for `state.meta.phase`,
	# so any subsequent shooting/movement/charge handler dispatched against
	# the active phase fails with "No active phase instance".
	#
	# The required flow is the three-step pattern documented in
	# `40k/tests/TESTING_METHODOLOGY.md`:
	#   1. SaveLoadManager.load_game(...) — already done above
	#   2. GameState.state.meta["from_save"] = true — see Main._ready
	#      at scripts/Main.gd:239 which keys off this flag to restore phase
	#      state instead of reinitialising a fresh game
	#   3. change_scene_to_file("res://scenes/Main.tscn") — re-runs
	#      Main._ready, which calls into PhaseManager to instantiate the
	#      phase class matching state.meta.phase and registers it as the
	#      current phase instance
	var game_state = _gs()
	if game_state and game_state.state and game_state.state.has("meta"):
		game_state.state.meta["from_save"] = true
		game_state.state.meta.erase("from_menu")

	# Trigger the scene reload. change_scene_to_file is deferred to the
	# next frame; we then poll for the new Main scene to complete its
	# _ready (which constructs and registers the phase instance).
	#
	# Why polling instead of a fixed timer: the IPC layer in
	# `MultiplayerIntegrationTest._wait_for_result` enforces a hard 5-second
	# round-trip budget. A naive `await create_timer(2.0).timeout` plus
	# scene-change + autoload init pushed total round-trip past the limit
	# and load_save started timing out. Polling lets us return as soon as
	# the phase instance is ready (typically <500ms total) while still
	# enforcing a max wait. The TestModeHandler autoload survives the scene
	# change, so this function continues normally across the change.
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

	# Wait until PhaseManager has a current phase instance, or 3 seconds
	# elapse. Three seconds is the hard ceiling we can afford within the
	# 5-second IPC budget while leaving time for the result-file write and
	# the test's polling jitter.
	var phase_mgr_for_wait = null
	var poll_deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < poll_deadline:
		# Yield at least one frame after each poll so the scene-change can
		# actually progress. At 60fps that's ~16ms per iteration, giving
		# ~180 polls in the 3s budget.
		await get_tree().process_frame
		phase_mgr_for_wait = get_node_or_null("/root/PhaseManager")
		if phase_mgr_for_wait and phase_mgr_for_wait.has_method("get_current_phase_instance"):
			if phase_mgr_for_wait.get_current_phase_instance() != null:
				break

	# Re-fetch game_state after the scene change in case anything was
	# rewired (the autoload reference is stable but defensive).
	game_state = _gs()
	if game_state and game_state.state and game_state.state.has("units"):
		var unit_count = game_state.state.units.size()
		var unit_ids = game_state.state.units.keys()
		print("TestModeHandler: Save loaded + Main scene reloaded, %d units found" % unit_count)
		print("TestModeHandler: Unit IDs: %s" % str(unit_ids))

		# Surface the active phase class so callers can quickly verify the
		# scene reload constructed the expected phase instance (ShootingPhase
		# for a phase=8 save, MovementPhase for phase=7, etc.).
		var phase_instance_class := ""
		var phase_mgr = get_node_or_null("/root/PhaseManager")
		if phase_mgr and phase_mgr.has_method("get_current_phase_instance"):
			var inst = phase_mgr.get_current_phase_instance()
			if inst:
				var script = inst.get_script()
				if script and script.resource_path != "":
					phase_instance_class = script.resource_path.get_file().get_basename()

		return {
			"success": true,
			"message": "Save file loaded successfully",
			"data": {
				"save_path": save_path,
				"unit_count": unit_count,
				"unit_ids": unit_ids,
				"phase_instance_class": phase_instance_class
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
	var game_state = _gs()
	if game_state and game_state.has_method("get_current_phase"):
		var current_phase = game_state.get_current_phase()
		if current_phase != GameStateData.Phase.DEPLOYMENT:
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

	# Get phase information from GameState. The match must cover every
	# Phase enum value defined in GameState.gd, otherwise unmatched values
	# fall through to "Unknown" — that's what was happening for FORMATIONS,
	# REDEPLOYMENT, SCOUT, and SCOUT_MOVES before this fix. Multi-peer tests
	# load saves that may legitimately sit in any of these phases.
	var game_state = _gs()
	var phase_name = "Unknown"
	if game_state and game_state.has_method("get_current_phase"):
		var current_phase = game_state.get_current_phase()
		match current_phase:
			GameStateData.Phase.FORMATIONS:
				phase_name = "Formations"
			GameStateData.Phase.DEPLOYMENT:
				phase_name = "Deployment"
			GameStateData.Phase.REDEPLOYMENT:
				phase_name = "Redeployment"
			GameStateData.Phase.ROLL_OFF:
				phase_name = "Roll-Off"
			GameStateData.Phase.FIRST_TURN_ROLLOFF:
				phase_name = "First-Turn Roll-Off"
			GameStateData.Phase.SCOUT:
				phase_name = "Scout"
			GameStateData.Phase.SCOUT_MOVES:
				phase_name = "Scout Moves"
			GameStateData.Phase.COMMAND:
				phase_name = "Command"
			GameStateData.Phase.MOVEMENT:
				phase_name = "Movement"
			GameStateData.Phase.SHOOTING:
				phase_name = "Shooting"
			GameStateData.Phase.CHARGE:
				phase_name = "Charge"
			GameStateData.Phase.FIGHT:
				phase_name = "Fight"
			GameStateData.Phase.SCORING:
				phase_name = "Scoring"
			GameStateData.Phase.MORALE:
				phase_name = "Morale"

	# Read turn and active player via the explicit GameState getters. The
	# previous implementation used `game_state.get("current_turn")` etc.,
	# which calls Object.get() against the autoload object itself — those
	# property names don't exist as direct fields, so the calls returned
	# null and the fallback `else 0` always fired. The real values live in
	# `state["meta"]` and are surfaced via get_turn_number() /
	# get_active_player(). Multi-peer integration tests filtering units by
	# active-player owner depend on these reading correctly.
	var current_turn := 0
	var player_turn := 0
	if game_state:
		if game_state.has_method("get_turn_number"):
			current_turn = game_state.get_turn_number()
		if game_state.has_method("get_active_player"):
			player_turn = game_state.get_active_player()

	# Collect game state information
	var state_data = {
		"current_phase": phase_name,
		"current_turn": current_turn,
		"player_turn": player_turn,
		"units": {}
	}

	# Debug logging
	print("TestModeHandler: get_game_state - Phase: %s, Turn: %d, Player: %d" % [
		state_data["current_phase"],
		state_data["current_turn"],
		state_data["player_turn"]
	])

	# Try to get unit information from GameState directly
	if game_state and game_state.state.has("units"):
		state_data["units"] = game_state.state.get("units", {})

	# Expose ShootingPhase.active_shooter_id when the active phase is a
	# ShootingPhase. Multi-peer integration tests use this to verify a
	# host SELECT_SHOOTER actually mutated the host phase. Stays empty
	# when the active phase is not Shooting (or when no shooter is selected).
	# NOTE: this reads HOST-side state only. The client's ShootingPhase
	# instance does NOT currently get its `active_shooter_id` written by
	# the broadcast pipeline (NetworkManager._emit_client_visual_updates
	# emits visual signals but does not call _process_select_shooter on the
	# client phase), so a get_game_state on the client will report "" here
	# even after the host has selected a shooter. The client-side controller
	# state IS updated via the unit_selected_for_shooting signal handler;
	# exposing that would require a future get_controller_state action.
	state_data["active_shooter_id"] = ""
	# Expose the most recent ShootingPhase.saves_required broadcast id so
	# multi-peer integration tests can assert the wound-allocation broadcast
	# pipeline stamped one in (T5-MP4-RELIABILITY).
	#
	# Two sources are consulted, host-attacker first (authoritative emit
	# site), then client-defender second (delivery confirmation):
	#
	#   1. ShootingPhase.pending_save_data[0].save_broadcast_id  (HOST)
	#      Populated immediately before `emit_signal("saves_required", ...)`
	#      and stays populated until APPLY_SAVES finishes. This is the same
	#      string the defender would dedupe on and the attacker would track
	#      in its retry budget — directly readable from the host phase.
	#   2. ShootingController._shown_save_broadcast_ids[-1]  (CLIENT)
	#      Each broadcast the client actually received and showed a dialog
	#      for is appended here for dedupe. The most-recent entry is the id
	#      the broadcast pipeline successfully delivered. Reading this is
	#      how a client-side `get_game_state` proves the broadcast crossed
	#      the wire — the host phase's `pending_save_data` is host-only.
	#
	# Both fields stay empty when neither source has anything (no broadcast
	# has fired this phase yet, or the active phase is not Shooting).
	state_data["save_broadcast_id"] = ""
	state_data["pending_save_count"] = 0
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if phase_mgr:
		var current_phase_inst = phase_mgr.get_current_phase_instance()
		if current_phase_inst:
			var script = current_phase_inst.get_script()
			var script_path = script.resource_path if script else ""
			if script_path.ends_with("ShootingPhase.gd"):
				if "active_shooter_id" in current_phase_inst:
					state_data["active_shooter_id"] = current_phase_inst.active_shooter_id
				if "pending_save_data" in current_phase_inst:
					var pending = current_phase_inst.pending_save_data
					if pending != null and pending is Array and not pending.is_empty():
						state_data["pending_save_count"] = pending.size()
						# All entries in a single saves_required emission carry
						# the same broadcast id (stamped by _stamp_save_broadcast_id).
						# Read from the first entry.
						state_data["save_broadcast_id"] = pending[0].get("save_broadcast_id", "")

	# Fallback for the client peer: when the host emitted a broadcast that
	# was delivered to the client, the client's ShootingController records
	# the id in `_shown_save_broadcast_ids` for dedupe. If the host-side
	# read above returned empty (i.e. this is the client and its phase has
	# no `pending_save_data`), surface the most-recent shown broadcast id
	# instead so multi-peer tests can verify the broadcast crossed the wire.
	if state_data["save_broadcast_id"] == "":
		var shooting_controller = SceneRefs.main_path("ShootingController")
		if shooting_controller and "_shown_save_broadcast_ids" in shooting_controller:
			var shown_ids = shooting_controller._shown_save_broadcast_ids
			if shown_ids != null and shown_ids is Array and not shown_ids.is_empty():
				state_data["save_broadcast_id"] = str(shown_ids[shown_ids.size() - 1])
				# `pending_save_count` reflects host-side state only; leave it
				# at 0 here since the client doesn't track wound-batch size in
				# this field. The id presence is the protocol-relevant signal.

	return {
		"success": true,
		"message": "Game state retrieved",
		"data": state_data
	}

func _handle_get_available_units(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling get_available_units action")

	var game_state = _gs()
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
	var artifacts_dir = ProjectSettings.globalize_path("res://" + TEST_ARTIFACTS_SUBDIR) + "/screenshots"

	# Ensure directory exists
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive(TEST_ARTIFACTS_SUBDIR + "/screenshots")

	var full_path = artifacts_dir + "/" + filename

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

# ============================================================================
# Shooting-phase action handlers
# ============================================================================
#
# Each shooting handler delegates to the same code path the UI uses by
# invoking phase.execute_action({"type": "<UPPERCASE>", ...}) on the active
# ShootingPhase instance. Required-param validation up-front returns a clear
# error dict; missing/wrong phase type returns INVALID_PHASE.
#
# Handler contract: {"success": bool, "result": <phase result>, "message": ...}
# Mirrors _handle_deploy_unit() above for consistency.

func _get_active_shooting_phase() -> Dictionary:
	"""Locate the active ShootingPhase instance via PhaseManager.

	Returns a dict {"ok": bool, "phase": ShootingPhase | null,
	                 "error_dict": Dictionary | null}. On failure, error_dict
	carries a fully-formed handler-style error response that the caller can
	return verbatim. On success, phase is the active ShootingPhase node.
	"""
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if not phase_mgr:
		return {
			"ok": false,
			"phase": null,
			"error_dict": {
				"success": false,
				"message": "PhaseManager not found",
				"error": "PHASE_MANAGER_NOT_FOUND"
			}
		}

	var phase = phase_mgr.get_current_phase_instance()
	if phase == null:
		return {
			"ok": false,
			"phase": null,
			"error_dict": {
				"success": false,
				"message": "No active phase instance",
				"error": "NO_PHASE_INSTANCE"
			}
		}

	# Verify the phase is actually a ShootingPhase. Match on script path so
	# subclasses (none today, but guard for future) and stub phases used in
	# headless tests both pass.
	var script = phase.get_script()
	var script_path = script.resource_path if script else ""
	if not script_path.ends_with("ShootingPhase.gd"):
		return {
			"ok": false,
			"phase": null,
			"error_dict": {
				"success": false,
				"message": "Active phase is not ShootingPhase (got %s)" % script_path,
				"error": "INVALID_PHASE"
			}
		}

	return {"ok": true, "phase": phase, "error_dict": null}

func _handle_select_shooter(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling select_shooter action")

	var actor_unit_id = params.get("actor_unit_id", "")
	if actor_unit_id == "":
		return {
			"success": false,
			"message": "Missing actor_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}

	var lookup = _get_active_shooting_phase()
	if not lookup.ok:
		return lookup.error_dict

	var action = {
		"type": "SELECT_SHOOTER",
		"actor_unit_id": actor_unit_id
	}
	var result = lookup.phase.execute_action(action)

	return {
		"success": bool(result.get("success", false)),
		"result": result,
		"message": "SELECT_SHOOTER dispatched for %s" % actor_unit_id
	}

func _handle_assign_target(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling assign_target action")

	var actor_unit_id = params.get("actor_unit_id", "")
	var target_unit_id = params.get("target_unit_id", "")
	var weapon_id = params.get("weapon_id", "")
	var model_ids = params.get("model_ids", [])

	if actor_unit_id == "":
		return {
			"success": false,
			"message": "Missing actor_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}
	if target_unit_id == "":
		return {
			"success": false,
			"message": "Missing target_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}
	if weapon_id == "":
		return {
			"success": false,
			"message": "Missing weapon_id parameter",
			"error": "MISSING_PARAMETER"
		}

	var lookup = _get_active_shooting_phase()
	if not lookup.ok:
		return lookup.error_dict

	var action = {
		"type": "ASSIGN_TARGET",
		"actor_unit_id": actor_unit_id,
		"payload": {
			"weapon_id": weapon_id,
			"target_unit_id": target_unit_id,
			"model_ids": model_ids
		}
	}
	var result = lookup.phase.execute_action(action)

	return {
		"success": bool(result.get("success", false)),
		"result": result,
		"message": "ASSIGN_TARGET dispatched: %s -> %s with %s" % [actor_unit_id, target_unit_id, weapon_id]
	}

func _handle_clear_assignment(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling clear_assignment action")

	var actor_unit_id = params.get("actor_unit_id", "")
	if actor_unit_id == "":
		return {
			"success": false,
			"message": "Missing actor_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}

	var lookup = _get_active_shooting_phase()
	if not lookup.ok:
		return lookup.error_dict

	# CLEAR_ASSIGNMENT clears the assignment for the specified weapon. Allow
	# the caller to optionally provide weapon_id; otherwise pull the most
	# recent pending assignment's weapon_id from the phase (the current
	# weapon being targeted in the UI).
	var weapon_id = params.get("weapon_id", "")
	if weapon_id == "":
		var pending = lookup.phase.get("pending_assignments")
		if pending != null and pending is Array and not pending.is_empty():
			weapon_id = pending[pending.size() - 1].get("weapon_id", "")
	if weapon_id == "":
		return {
			"success": false,
			"message": "No weapon_id provided and no pending assignment to infer one from",
			"error": "MISSING_PARAMETER"
		}

	var action = {
		"type": "CLEAR_ASSIGNMENT",
		"actor_unit_id": actor_unit_id,
		"payload": {
			"weapon_id": weapon_id
		}
	}
	var result = lookup.phase.execute_action(action)

	return {
		"success": bool(result.get("success", false)),
		"result": result,
		"message": "CLEAR_ASSIGNMENT dispatched for %s weapon=%s" % [actor_unit_id, weapon_id]
	}

func _handle_confirm_targets(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling confirm_targets action")

	var actor_unit_id = params.get("actor_unit_id", "")
	if actor_unit_id == "":
		return {
			"success": false,
			"message": "Missing actor_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}

	var lookup = _get_active_shooting_phase()
	if not lookup.ok:
		return lookup.error_dict

	var action = {
		"type": "CONFIRM_TARGETS",
		"actor_unit_id": actor_unit_id
	}
	var result = lookup.phase.execute_action(action)

	return {
		"success": bool(result.get("success", false)),
		"result": result,
		"message": "CONFIRM_TARGETS dispatched for %s" % actor_unit_id
	}

func _handle_complete_shooting_for_unit(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling complete_shooting_for_unit action")

	var actor_unit_id = params.get("actor_unit_id", "")
	if actor_unit_id == "":
		return {
			"success": false,
			"message": "Missing actor_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}

	var lookup = _get_active_shooting_phase()
	if not lookup.ok:
		return lookup.error_dict

	var action = {
		"type": "COMPLETE_SHOOTING_FOR_UNIT",
		"actor_unit_id": actor_unit_id
	}
	var result = lookup.phase.execute_action(action)

	return {
		"success": bool(result.get("success", false)),
		"result": result,
		"message": "COMPLETE_SHOOTING_FOR_UNIT dispatched for %s" % actor_unit_id
	}

func _handle_use_grenade_stratagem(params: Dictionary) -> Dictionary:
	print("TestModeHandler: Handling use_grenade_stratagem action")

	# USE_GRENADE_STRATAGEM uses a different payload shape than the other
	# shooting actions: it reads grenade_unit_id and target_unit_id directly
	# off the action root (see _validate_use_grenade_stratagem).
	var actor_unit_id = params.get("actor_unit_id", "")
	var target_unit_id = params.get("target_unit_id", "")

	if actor_unit_id == "":
		return {
			"success": false,
			"message": "Missing actor_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}
	if target_unit_id == "":
		return {
			"success": false,
			"message": "Missing target_unit_id parameter",
			"error": "MISSING_PARAMETER"
		}

	var lookup = _get_active_shooting_phase()
	if not lookup.ok:
		return lookup.error_dict

	var action = {
		"type": "USE_GRENADE_STRATAGEM",
		"grenade_unit_id": actor_unit_id,
		"target_unit_id": target_unit_id
	}
	var result = lookup.phase.execute_action(action)

	return {
		"success": bool(result.get("success", false)),
		"result": result,
		"message": "USE_GRENADE_STRATAGEM dispatched: %s -> %s" % [actor_unit_id, target_unit_id]
	}

func _handle_transition_to_phase(params: Dictionary) -> Dictionary:
	# Drive PhaseManager.transition_to_phase from a multi-peer test so the
	# integration tests can advance the host peer past the boot phase
	# (FORMATIONS) and into whichever phase they need to exercise.
	#
	# Why this exists: peers spawned by GameInstance.gd with --auto-host /
	# --auto-join boot into FORMATIONS (the real-game start phase per 10e
	# rules), not DEPLOYMENT. Previously the deployment-driving integration
	# tests asserted "current_phase == Deployment" immediately after
	# launch_host_and_client(), which silently failed (got "Unknown" pre-
	# 9d77ed7) or honestly failed (got "Formations" post-9d77ed7). Tests
	# need an explicit advance step. See task notes / `/tmp/mp_run4.log`.
	#
	# Why the host call is enough on its own: PhaseManager.transition_to_phase
	# already calls NetworkManager.broadcast_phase_change(...) when the host
	# is networked, which RPCs _receive_phase_change to the client and re-
	# enters PhaseManager.transition_to_phase on that side. So
	# simulate_host_action("transition_to_phase", {...}) advances both peers.
	#
	# Param: `phase` — accepts either an int (GameStateData.Phase enum value)
	# or a string ("DEPLOYMENT", "FORMATIONS", etc. — case-insensitive).
	print("TestModeHandler: Handling transition_to_phase action")

	if not params.has("phase"):
		return {
			"success": false,
			"message": "Missing phase parameter",
			"error": "MISSING_PARAMETER"
		}

	var raw_phase = params["phase"]
	var target_phase: int = -1
	var phase_keys = GameStateData.Phase.keys()

	# Resolve int or string to a Phase enum int.
	match typeof(raw_phase):
		TYPE_INT:
			target_phase = int(raw_phase)
		TYPE_FLOAT:
			# JSON parsers sometimes hand us floats for whole numbers.
			target_phase = int(raw_phase)
		TYPE_STRING:
			var name_upper = String(raw_phase).to_upper()
			var idx = phase_keys.find(name_upper)
			if idx >= 0:
				target_phase = idx
		_:
			pass

	if target_phase < 0 or target_phase >= phase_keys.size():
		return {
			"success": false,
			"message": "Invalid phase value: %s (must be int 0..%d or one of %s)" % [
				str(raw_phase), phase_keys.size() - 1, str(phase_keys)
			],
			"error": "INVALID_PARAMETER"
		}

	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager:
		return {
			"success": false,
			"message": "PhaseManager not found",
			"error": "PHASE_MANAGER_NOT_FOUND"
		}
	if not phase_manager.has_method("transition_to_phase"):
		return {
			"success": false,
			"message": "PhaseManager missing transition_to_phase method",
			"error": "METHOD_NOT_FOUND"
		}

	var from_phase = -1
	if phase_manager.has_method("get_current_phase"):
		from_phase = phase_manager.get_current_phase()

	# Drive the transition. PhaseManager will:
	#   - exit any current phase instance
	#   - call GameState.set_phase(target_phase)
	#   - broadcast to clients via NetworkManager.broadcast_phase_change
	#     (when this peer is the networked host)
	#   - construct + enter the new phase instance
	phase_manager.transition_to_phase(target_phase)

	# Yield one frame so the new phase instance's enter_phase() runs and
	# any deferred phase-completion (e.g. FORMATIONS auto-completing because
	# both players already confirmed) can settle before the result file is
	# written. This keeps the post-transition get_game_state read accurate.
	await get_tree().process_frame

	var resolved_phase = -1
	if phase_manager.has_method("get_current_phase"):
		resolved_phase = phase_manager.get_current_phase()

	return {
		"success": true,
		"message": "Transitioned phase: %s -> %s (resolved %s)" % [
			phase_keys[from_phase] if from_phase >= 0 and from_phase < phase_keys.size() else str(from_phase),
			phase_keys[target_phase],
			phase_keys[resolved_phase] if resolved_phase >= 0 and resolved_phase < phase_keys.size() else str(resolved_phase)
		],
		"data": {
			"from_phase": from_phase,
			"requested_phase": target_phase,
			"resolved_phase": resolved_phase
		}
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
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive(TEST_SAVES_SUBDIR)

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
