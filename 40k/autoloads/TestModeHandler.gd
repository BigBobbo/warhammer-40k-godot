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

func _ready() -> void:
	_parse_command_line_arguments()

	if is_test_mode:
		print("========================================")
		print("   RUNNING IN TEST MODE")
		print("   Config: ", test_config)
		print("========================================")
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
		# Check if it's a test save or regular save
		if save_path.begins_with("test_"):
			save_path = "res://tests/saves/" + save_path

		if SaveLoadManager.has_method("load_game"):
			SaveLoadManager.load_game(save_path)
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