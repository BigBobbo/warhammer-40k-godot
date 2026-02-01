extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")

# Unit tests for NetworkManager
# Tests basic networking functionality without requiring actual network connections

var network_manager: NetworkManager
var game_manager: GameManager
var game_state: GameStateData

func before_each():
	# Create fresh instances for testing
	network_manager = NetworkManager.new()
	game_manager = GameManager.new()
	game_state = GameStateData.new()

	# Inject dependencies (since we can't use autoloads in tests)
	network_manager.game_manager = game_manager
	network_manager.game_state = game_state

	add_child_autofree(network_manager)
	add_child_autofree(game_manager)
	add_child_autofree(game_state)

func after_each():
	# Cleanup
	if network_manager:
		network_manager.disconnect_network()

# ============================================================================
# PHASE 0: INITIALIZATION TESTS
# ============================================================================

func test_network_manager_initializes_in_offline_mode():
	assert_eq(network_manager.network_mode, NetworkManager.NetworkMode.OFFLINE,
		"NetworkManager should start in offline mode")

func test_network_manager_has_empty_peer_map_on_init():
	assert_eq(network_manager.peer_to_player_map.size(), 0,
		"Peer map should be empty on initialization")

func test_network_manager_initializes_rng_session_id():
	assert_ne(network_manager.game_session_id, "",
		"RNG session ID should be initialized")

# ============================================================================
# PHASE 1: CONNECTION TESTS
# ============================================================================

func test_is_networked_returns_false_when_offline():
	assert_false(network_manager.is_networked(),
		"is_networked() should return false in offline mode")

func test_is_host_returns_false_when_offline():
	assert_false(network_manager.is_host(),
		"is_host() should return false in offline mode")

func test_network_mode_changes_on_host_creation():
	# Note: This test may fail in CI without network support
	if not OS.has_feature("network"):
		pass_test("Skipping - network not available")
		return

	var result = network_manager.create_host(7778)  # Use different port
	if result == OK:
		assert_eq(network_manager.network_mode, NetworkManager.NetworkMode.HOST,
			"Network mode should be HOST after creating host")
		assert_true(network_manager.is_host(),
			"is_host() should return true after creating host")
		assert_true(network_manager.is_networked(),
			"is_networked() should return true after creating host")

func test_disconnect_network_resets_state():
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.peer_to_player_map[2] = 2

	network_manager.disconnect_network()

	assert_eq(network_manager.network_mode, NetworkManager.NetworkMode.OFFLINE,
		"Network mode should be offline after disconnect")
	assert_eq(network_manager.peer_to_player_map.size(), 0,
		"Peer map should be cleared after disconnect")

# ============================================================================
# PHASE 2: VALIDATION TESTS
# ============================================================================

func test_validation_rejects_action_without_type():
	var action = {"player": 1}
	var validation = network_manager.validate_action(action, 1)

	assert_false(validation.valid, "Action without type should be invalid")
	assert_string_contains(validation.reason, "schema",
		"Rejection reason should mention schema")

func test_validation_rejects_wrong_player():
	# Setup
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.peer_to_player_map[1] = 1
	network_manager.peer_to_player_map[2] = 2
	game_state.set_active_player(1)

	# Player 2 tries to act when it's Player 1's turn
	var action = {"type": "MOVE_UNIT", "player": 2, "unit_id": "U1"}
	var validation = network_manager.validate_action(action, 2)

	assert_false(validation.valid, "Action from non-active player should be invalid")
	assert_eq(validation.reason, "Not your turn",
		"Rejection reason should be 'Not your turn'")

func test_validation_rejects_player_id_mismatch():
	# Setup
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.peer_to_player_map[1] = 1
	network_manager.peer_to_player_map[2] = 2

	# Peer 2 claims to be Player 1
	var action = {"type": "MOVE_UNIT", "player": 1, "unit_id": "U1"}
	var validation = network_manager.validate_action(action, 2)

	assert_false(validation.valid, "Action with mismatched player ID should be invalid")
	assert_eq(validation.reason, "Player ID mismatch",
		"Rejection reason should be 'Player ID mismatch'")

func test_validation_accepts_valid_action():
	# Setup
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.peer_to_player_map[1] = 1
	game_state.set_active_player(1)

	# Valid action from correct player
	var action = {"type": "DEPLOY_UNIT", "player": 1, "unit_id": "U1"}
	var validation = network_manager.validate_action(action, 1)

	assert_true(validation.valid, "Valid action should be accepted")

# ============================================================================
# PHASE 3: TURN TIMER TESTS
# ============================================================================

func test_turn_timer_exists():
	assert_not_null(network_manager.turn_timer,
		"Turn timer should be created during initialization")

func test_turn_timer_starts_only_when_host():
	network_manager.network_mode = NetworkManager.NetworkMode.CLIENT
	network_manager.start_turn_timer()

	assert_false(network_manager.turn_timer.time_left > 0,
		"Turn timer should not start for clients")

	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.start_turn_timer()

	assert_true(network_manager.turn_timer.time_left > 0,
		"Turn timer should start for host")

func test_turn_timer_can_be_stopped():
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.start_turn_timer()

	assert_true(network_manager.turn_timer.time_left > 0,
		"Turn timer should be running")

	network_manager.stop_turn_timer()

	assert_false(network_manager.turn_timer.time_left > 0,
		"Turn timer should be stopped")

# ============================================================================
# PHASE 4: DETERMINISTIC RNG TESTS
# ============================================================================

func test_rng_seed_generation_offline_returns_negative():
	network_manager.network_mode = NetworkManager.NetworkMode.OFFLINE
	var seed = network_manager.get_next_rng_seed()

	assert_eq(seed, -1,
		"RNG seed should be -1 in offline mode (non-deterministic)")

func test_rng_seed_generation_increments_counter():
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.rng_seed_counter = 0

	var seed1 = network_manager.get_next_rng_seed()
	var seed2 = network_manager.get_next_rng_seed()

	assert_eq(network_manager.rng_seed_counter, 2,
		"RNG seed counter should increment with each call")
	assert_ne(seed1, seed2,
		"Each RNG seed should be unique")

func test_rng_seed_generation_client_returns_negative():
	network_manager.network_mode = NetworkManager.NetworkMode.CLIENT
	var seed = network_manager.get_next_rng_seed()

	assert_eq(seed, -1,
		"RNG seed should be -1 for clients (only host generates seeds)")

func test_rng_seeds_are_deterministic_with_same_state():
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.game_session_id = "test_session"
	network_manager.rng_seed_counter = 0
	game_state.state["meta"]["turn_number"] = 1

	var seed1 = network_manager.get_next_rng_seed()

	# Reset counter but keep same session and turn
	network_manager.rng_seed_counter = 0
	var seed2 = network_manager.get_next_rng_seed()

	assert_eq(seed1, seed2,
		"RNG seeds should be deterministic with same state")

# ============================================================================
# ACTION ROUTING TESTS
# ============================================================================

func test_submit_action_routes_through_game_manager_in_offline_mode():
	network_manager.network_mode = NetworkManager.NetworkMode.OFFLINE
	var action = {
		"type": "DEPLOY_UNIT",
		"unit_id": "U1",
		"player": 1,
		"models": []
	}

	network_manager.submit_action(action)

	# Verify GameManager received the action
	assert_gt(game_manager.action_history.size(), 0,
		"GameManager should have received the action")
	assert_eq(game_manager.action_history[0]["type"], "DEPLOY_UNIT",
		"Action type should match")

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

func test_peer_map_correctly_assigns_players():
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	network_manager.peer_to_player_map[1] = 1  # Host is player 1

	assert_eq(network_manager.peer_to_player_map[1], 1,
		"Host should be assigned to player 1")

	# Simulate client connection
	network_manager.peer_to_player_map[2] = 2

	assert_eq(network_manager.peer_to_player_map[2], 2,
		"Client should be assigned to player 2")
