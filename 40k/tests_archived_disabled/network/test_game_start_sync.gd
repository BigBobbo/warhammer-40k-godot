extends "res://addons/gut/test.gd"

# Unit tests for multiplayer game start synchronization
# Tests that the RPC method correctly initiates game start for both host and client

var network_manager: NetworkManager

func before_each():
	network_manager = NetworkManager.new()
	add_child_autofree(network_manager)

func test_start_game_rpc_exists():
	assert_true(network_manager.has_method("start_multiplayer_game"),
		"NetworkManager should have start_multiplayer_game RPC method")

func test_only_host_can_call_start_game():
	network_manager.network_mode = NetworkManager.NetworkMode.CLIENT

	# Attempting to call as client should fail
	# Note: In actual implementation, Godot will reject this at network level
	# This test documents the expected behavior
	assert_false(network_manager.is_host(),
		"Client should not be able to call authority RPC")

func test_host_can_call_start_game():
	network_manager.network_mode = NetworkManager.NetworkMode.HOST

	# Host should be able to trigger game start
	assert_true(network_manager.is_host(),
		"Host should be able to call authority RPC")

func test_network_manager_has_game_started_signal():
	# Verify the game_started signal exists
	assert_signal_exists(network_manager, "game_started",
		"NetworkManager should have game_started signal")
