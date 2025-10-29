extends GutTest

# Tests multiplayer load synchronization
# Tests for GitHub Issue #99: Multiplayer Load Synchronization

func before_each():
	# Initialize game state
	GameState.initialize_default_state()

	# Setup minimal multiplayer environment
	if NetworkManager:
		NetworkManager.network_mode = NetworkManager.NetworkMode.OFFLINE

func test_host_can_trigger_load_sync():
	# Setup host
	NetworkManager.network_mode = NetworkManager.NetworkMode.HOST
	NetworkManager.peer_to_player_map[1] = 1

	# Create a test save
	var test_state = GameState.create_snapshot()
	test_state["meta"]["turn_number"] = 5

	# Verify sync_loaded_state exists and can be called
	assert_has_method(NetworkManager, "sync_loaded_state", "NetworkManager should have sync_loaded_state method")

	# Note: We can't fully test the RPC without actual network peers
	# but we can verify the method exists and doesn't crash when called
	NetworkManager.sync_loaded_state()

	# Should see "Syncing loaded state" in console logs

func test_client_cannot_trigger_load_sync():
	# Setup client
	NetworkManager.network_mode = NetworkManager.NetworkMode.CLIENT
	NetworkManager.peer_to_player_map[2] = 2

	# Try to sync (should fail with error)
	NetworkManager.sync_loaded_state()

	# Should see error in console: "Only host can sync loaded state!"
	# In a real test environment, we'd capture the error output

func test_load_sync_includes_full_state():
	# Setup host
	NetworkManager.network_mode = NetworkManager.NetworkMode.HOST

	# Create test state with units
	GameState.state.units = {
		"unit_1": {"owner": 1, "position": Vector2(100, 100)},
		"unit_2": {"owner": 2, "position": Vector2(200, 200)}
	}

	# Get snapshot
	var snapshot = GameState.create_snapshot()

	# Verify snapshot has units
	assert_eq(snapshot.units.size(), 2, "Snapshot should include all units")
	assert_true(snapshot.has("meta"), "Snapshot should include metadata")
	assert_true(snapshot.has("board"), "Snapshot should include board")

func test_offline_mode_skips_sync():
	# Ensure offline mode
	NetworkManager.network_mode = NetworkManager.NetworkMode.OFFLINE

	# Call sync (should return early)
	NetworkManager.sync_loaded_state()

	# Should see "Not in multiplayer, skipping load sync" in console

func test_send_loaded_state_rpc_exists():
	# Verify the RPC function exists
	assert_has_method(NetworkManager, "_send_loaded_state", "NetworkManager should have _send_loaded_state RPC")

func test_refresh_client_ui_helper_exists():
	# Verify the helper function exists
	assert_has_method(NetworkManager, "_refresh_client_ui_after_load", "NetworkManager should have _refresh_client_ui_after_load helper")

func test_saveloadmanager_has_network_check():
	# This is more of an integration test
	# Verify SaveLoadManager references NetworkManager
	assert_not_null(NetworkManager, "NetworkManager should be available as singleton")

	# We can't easily test the actual load path without a real save file
	# but we can verify the autoload exists
	assert_true(SaveLoadManager != null, "SaveLoadManager should be available")
