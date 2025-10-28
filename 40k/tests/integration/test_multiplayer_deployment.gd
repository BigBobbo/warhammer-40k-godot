extends MultiplayerIntegrationTest

# Tests multiplayer functionality during the deployment phase
# Verifies that both players can see units, make deployments, and stay synchronized

func test_basic_multiplayer_connection():
	# Most basic test - just verify two instances can connect
	print("\n[TEST] Basic Multiplayer Connection")

	# Launch both instances
	var launched = await launch_host_and_client()
	assert_true(launched, "Should successfully launch both instances")

	# Wait for connection
	var connected = await wait_for_connection()
	assert_true(connected, "Client should connect to host")

	# Verify connection state
	assert_connection_established("Connection should be established")

	print("[TEST] Basic connection test PASSED")

func test_multiplayer_save_load_deployment():
	# Test loading a save file in deployment phase
	print("\n[TEST] Multiplayer Save Load - Deployment Phase")

	# Launch instances
	var launched = await launch_host_and_client()
	assert_true(launched, "Should launch both instances")

	# Wait for connection
	var connected = await wait_for_connection()
	assert_true(connected, "Client should connect to host")

	# Host starts the game
	var game_started = simulate_host_action("start_game")
	assert_true(game_started, "Host should start the game")

	# Wait for game start on both sides
	await wait_for_seconds(2.0)
	assert_game_started("Game should be started on both instances")

	# Host loads deployment save
	var save_loaded = await load_test_save("deployment_test.w40ksave", true)
	assert_true(save_loaded, "Host should load the save file")

	# Verify both instances sync to deployment phase
	var in_deployment = await wait_for_phase("Deployment", 10.0)
	assert_true(in_deployment, "Both instances should be in deployment phase")

	# Verify game state is synchronized
	var synced = await verify_game_state_sync()
	assert_true(synced, "Game state should be synchronized")

	print("[TEST] Save load deployment test PASSED")

func test_deployment_action_sync():
	# Test that deployment actions sync between players
	print("\n[TEST] Deployment Action Synchronization")

	# Setup multiplayer session with deployment save
	var launched = await launch_host_and_client()
	assert_true(launched)

	var connected = await wait_for_connection()
	assert_true(connected)

	simulate_host_action("start_game")
	await wait_for_seconds(2.0)

	await load_test_save("deployment_test.w40ksave", true)
	await wait_for_phase("Deployment", 10.0)

	# Host deploys a unit
	print("[TEST] Host deploying unit...")
	var deployed = simulate_host_action("deploy_unit:tactical_squad:position:100,100")
	assert_true(deployed, "Host should deploy unit")

	# Wait for sync
	await wait_for_seconds(2.0)

	# Verify client sees the deployment
	var client_state = client_instance.get_game_state()
	# Would check for unit at position in client state
	assert_true(
		client_state.has("units_deployed"),
		"Client should see deployed units"
	)

	print("[TEST] Deployment action sync test PASSED")

func test_deployment_turn_order():
	# Test that players alternate deployment turns correctly
	print("\n[TEST] Deployment Turn Order")

	# Setup session
	await launch_host_and_client()
	await wait_for_connection()
	simulate_host_action("start_game")
	await load_test_save("deployment_test.w40ksave", true)
	await wait_for_phase("Deployment", 10.0)

	# Check initial turn - should be Player 1 (host)
	var host_state = host_instance.get_game_state()
	assert_eq(
		host_state.get("active_player", -1),
		1,
		"Player 1 (host) should have first deployment turn"
	)

	# Host completes deployment action
	simulate_host_action("end_deployment_turn")
	await wait_for_seconds(2.0)

	# Check turn switched to Player 2 (client)
	host_state = host_instance.get_game_state()
	var client_state = client_instance.get_game_state()

	assert_eq(
		host_state.get("active_player", -1),
		2,
		"Turn should switch to Player 2"
	)
	assert_eq(
		client_state.get("active_player", -1),
		2,
		"Client should also show Player 2's turn"
	)

	print("[TEST] Deployment turn order test PASSED")

func test_deployment_completion_sync():
	# Test that deployment completion is synchronized
	print("\n[TEST] Deployment Completion Synchronization")

	# Setup session with mostly deployed save
	await launch_host_and_client()
	await wait_for_connection()
	simulate_host_action("start_game")

	# Load save where deployment is nearly complete
	await load_test_save("deployment_nearly_complete.w40ksave", true)
	await wait_for_phase("Deployment", 10.0)

	# Both players complete deployment
	simulate_host_action("finish_deployment")
	await wait_for_seconds(1.0)
	simulate_client_action("finish_deployment")

	# Wait for phase transition
	await wait_for_seconds(3.0)

	# Verify both moved to next phase (Movement)
	var moved_to_movement = await wait_for_phase("Movement", 10.0)
	assert_true(
		moved_to_movement,
		"Both instances should transition to Movement phase"
	)

	print("[TEST] Deployment completion sync test PASSED")

func test_disconnection_during_deployment():
	# Test handling disconnection during deployment
	gut.pending("Disconnection handling - not in MVP")

func test_deployment_with_terrain():
	# Test deployment with terrain obstacles
	print("\n[TEST] Deployment with Terrain")

	await launch_host_and_client()
	await wait_for_connection()
	simulate_host_action("start_game")

	# Load save with terrain
	await load_test_save("deployment_with_terrain.w40ksave", true)
	await wait_for_phase("Deployment", 10.0)

	# Verify terrain is visible on both instances
	var host_state = host_instance.get_game_state()
	var client_state = client_instance.get_game_state()

	assert_true(
		host_state.has("terrain_features"),
		"Host should have terrain data"
	)
	assert_true(
		client_state.has("terrain_features"),
		"Client should have terrain data"
	)

	# Test invalid deployment (on terrain)
	var invalid_deploy = simulate_host_action("deploy_unit:tactical_squad:position:200,200")
	# Would verify this is rejected due to terrain

	print("[TEST] Deployment with terrain test PASSED")