extends GutTest

# Integration tests for multiplayer army selection in lobby
# Tests the army selection UI and synchronization between host and client

func test_army_options_populated():
	# Create a lobby instance
	var lobby_scene = load("res://scenes/MultiplayerLobby.tscn")
	var lobby = lobby_scene.instantiate()
	add_child(lobby)

	# Wait for ready
	await get_tree().process_frame

	# Verify army options exist
	assert_gt(lobby.army_options.size(), 0, "Should have army options")
	assert_true(lobby.army_options[0].has("id"), "Army option should have id")
	assert_true(lobby.army_options[0].has("name"), "Army option should have name")

	# Cleanup
	lobby.queue_free()

func test_army_sync_rpc():
	# Create a lobby instance
	var lobby_scene = load("res://scenes/MultiplayerLobby.tscn")
	var lobby = lobby_scene.instantiate()
	add_child(lobby)

	# Wait for ready
	await get_tree().process_frame

	# Simulate army sync
	lobby._sync_army_selection(1, "space_marines")

	assert_eq(lobby.selected_player1_army, "space_marines", "Player 1 army should update")

	# Cleanup
	lobby.queue_free()

func test_army_loading_integration():
	# Initialize GameState
	GameState.initialize_default_state()
	GameState.state.units.clear()

	# Load armies
	var p1_army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	ArmyListManager.apply_army_to_game_state(p1_army, 1)

	var p2_army = ArmyListManager.load_army_list("orks", 2)
	ArmyListManager.apply_army_to_game_state(p2_army, 2)

	# Verify units loaded
	assert_gt(GameState.state.units.size(), 0, "Should have units")

	# Verify both players have units
	var p1_units = 0
	var p2_units = 0
	for unit_id in GameState.state.units:
		var unit = GameState.state.units[unit_id]
		if unit.owner == 1:
			p1_units += 1
		elif unit.owner == 2:
			p2_units += 1

	assert_gt(p1_units, 0, "Player 1 should have units")
	assert_gt(p2_units, 0, "Player 2 should have units")

func test_format_army_name():
	# Create a lobby instance
	var lobby_scene = load("res://scenes/MultiplayerLobby.tscn")
	var lobby = lobby_scene.instantiate()
	add_child(lobby)

	# Wait for ready
	await get_tree().process_frame

	# Test army name formatting
	var formatted = lobby._format_army_name("adeptus_custodes")
	assert_eq(formatted, "Adeptus Custodes", "Should format snake_case to Title Case")

	formatted = lobby._format_army_name("space_marines")
	assert_eq(formatted, "Space Marines", "Should format snake_case to Title Case")

	# Cleanup
	lobby.queue_free()

func test_army_dropdowns_disabled_initially():
	# Create a lobby instance
	var lobby_scene = load("res://scenes/MultiplayerLobby.tscn")
	var lobby = lobby_scene.instantiate()
	add_child(lobby)

	# Wait for ready
	await get_tree().process_frame

	# Verify dropdowns are disabled initially
	assert_true(lobby.player1_dropdown.disabled, "Player 1 dropdown should be disabled initially")
	assert_true(lobby.player2_dropdown.disabled, "Player 2 dropdown should be disabled initially")

	# Cleanup
	lobby.queue_free()

func test_host_enables_player1_dropdown():
	# Create a lobby instance
	var lobby_scene = load("res://scenes/MultiplayerLobby.tscn")
	var lobby = lobby_scene.instantiate()
	add_child(lobby)

	# Wait for ready
	await get_tree().process_frame

	# Simulate hosting
	lobby.is_hosting = true
	lobby._update_ui_for_hosting()

	# Verify Player 1 dropdown is enabled for host
	assert_false(lobby.player1_dropdown.disabled, "Player 1 dropdown should be enabled for host")
	assert_true(lobby.player2_dropdown.disabled, "Player 2 dropdown should be disabled for host")

	# Cleanup
	lobby.queue_free()
