extends GutTest

# Unit tests for GameState autoload
# Tests core game state management functionality

var test_game_state: GameStateData
var initial_snapshot: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Create a fresh GameState instance for testing
	test_game_state = GameStateData.new()
	test_game_state.initialize_default_state()
	initial_snapshot = test_game_state.create_snapshot()

func after_each():
	if test_game_state:
		test_game_state.queue_free()

# Test initialization and default state
func test_initialize_default_state():
	assert_not_null(test_game_state.state, "State should be initialized")
	
	# Check required top-level keys
	var required_keys = ["meta", "board", "units", "players", "phase_log", "history"]
	for key in required_keys:
		assert_true(test_game_state.state.has(key), "State should have key: " + key)
	
	# Check meta structure
	var meta = test_game_state.state.meta
	assert_true(meta.has("game_id"), "Meta should have game_id")
	assert_eq(1, meta.turn_number, "Initial turn should be 1")
	assert_eq(1, meta.active_player, "Initial active player should be 1")
	assert_eq(GameStateData.Phase.DEPLOYMENT, meta.phase, "Initial phase should be DEPLOYMENT")
	assert_true(meta.has("created_at"), "Meta should have created_at timestamp")
	assert_eq("1.0.0", meta.version, "Version should be set")

func test_generate_game_id():
	var id1 = test_game_state.generate_game_id()
	var id2 = test_game_state.generate_game_id()
	
	assert_not_null(id1, "Game ID should not be null")
	assert_not_null(id2, "Game ID should not be null")
	assert_ne(id1, id2, "Game IDs should be unique")
	
	# Check UUID format (basic check)
	assert_true(id1.length() > 30, "Game ID should have reasonable length")
	assert_true(id1.contains("-"), "Game ID should contain dashes")

# Test phase management
func test_get_current_phase():
	var phase = test_game_state.get_current_phase()
	assert_eq(GameStateData.Phase.DEPLOYMENT, phase, "Initial phase should be DEPLOYMENT")

func test_set_phase():
	test_game_state.set_phase(GameStateData.Phase.MOVEMENT)
	assert_eq(GameStateData.Phase.MOVEMENT, test_game_state.get_current_phase(), "Phase should be updated to MOVEMENT")
	
	test_game_state.set_phase(GameStateData.Phase.SHOOTING)
	assert_eq(GameStateData.Phase.SHOOTING, test_game_state.get_current_phase(), "Phase should be updated to SHOOTING")

# Test player management
func test_get_active_player():
	var player = test_game_state.get_active_player()
	assert_eq(1, player, "Initial active player should be 1")

func test_set_active_player():
	test_game_state.set_active_player(2)
	assert_eq(2, test_game_state.get_active_player(), "Active player should be updated to 2")

# Test turn management
func test_get_turn_number():
	var turn = test_game_state.get_turn_number()
	assert_eq(1, turn, "Initial turn should be 1")

func test_advance_turn():
	var initial_turn = test_game_state.get_turn_number()
	test_game_state.advance_turn()
	assert_eq(initial_turn + 1, test_game_state.get_turn_number(), "Turn should be incremented")
	
	test_game_state.advance_turn()
	assert_eq(initial_turn + 2, test_game_state.get_turn_number(), "Turn should continue incrementing")

# Test unit management
func test_get_units_for_player():
	var player1_units = test_game_state.get_units_for_player(1)
	var player2_units = test_game_state.get_units_for_player(2)
	
	assert_gt(player1_units.size(), 0, "Player 1 should have units")
	assert_gt(player2_units.size(), 0, "Player 2 should have units")
	
	# Check that units belong to correct players
	for unit_id in player1_units:
		var unit = player1_units[unit_id]
		assert_eq(1, unit.owner, "Player 1 unit should have owner = 1")
	
	for unit_id in player2_units:
		var unit = player2_units[unit_id]
		assert_eq(2, unit.owner, "Player 2 unit should have owner = 2")

func test_get_unit():
	var unit = test_game_state.get_unit("U_INTERCESSORS_A")
	assert_not_null(unit, "Should find existing unit")
	assert_eq("U_INTERCESSORS_A", unit.id, "Unit should have correct ID")
	assert_eq("Intercessor Squad", unit.meta.name, "Unit should have correct name")
	
	var missing_unit = test_game_state.get_unit("NONEXISTENT")
	assert_true(missing_unit.is_empty(), "Should return empty dict for missing unit")

func test_get_undeployed_units_for_player():
	var undeployed_p1 = test_game_state.get_undeployed_units_for_player(1)
	var undeployed_p2 = test_game_state.get_undeployed_units_for_player(2)
	
	# All units should start undeployed
	assert_gt(undeployed_p1.size(), 0, "Player 1 should have undeployed units")
	assert_gt(undeployed_p2.size(), 0, "Player 2 should have undeployed units")
	
	# Verify these are actually undeployed
	for unit_id in undeployed_p1:
		var unit = test_game_state.get_unit(unit_id)
		assert_eq(GameStateData.UnitStatus.UNDEPLOYED, unit.status, "Unit should be UNDEPLOYED")

func test_has_undeployed_units():
	assert_true(test_game_state.has_undeployed_units(1), "Player 1 should have undeployed units")
	assert_true(test_game_state.has_undeployed_units(2), "Player 2 should have undeployed units")

func test_all_units_deployed():
	assert_false(test_game_state.all_units_deployed(), "Not all units should be deployed initially")
	
	# Deploy all units
	for unit_id in test_game_state.state.units:
		test_game_state.state.units[unit_id].status = GameStateData.UnitStatus.DEPLOYED
	
	assert_true(test_game_state.all_units_deployed(), "All units should be deployed after setting status")

# Test deployment zones
func test_get_deployment_zone_for_player():
	var zone1 = test_game_state.get_deployment_zone_for_player(1)
	var zone2 = test_game_state.get_deployment_zone_for_player(2)
	
	assert_not_null(zone1, "Player 1 should have deployment zone")
	assert_not_null(zone2, "Player 2 should have deployment zone")
	assert_eq(1, zone1.player, "Zone 1 should belong to player 1")
	assert_eq(2, zone2.player, "Zone 2 should belong to player 2")
	
	assert_true(zone1.has("poly"), "Zone should have polygon coordinates")
	assert_true(zone1.poly is Array, "Zone poly should be an array")
	assert_gt(zone1.poly.size(), 0, "Zone should have coordinates")

func test_get_deployment_zone_coords():
	var zone1_coords = test_game_state._get_dawn_of_war_zone_1_coords()
	var zone2_coords = test_game_state._get_dawn_of_war_zone_2_coords()
	
	assert_eq(4, zone1_coords.size(), "Zone 1 should have 4 coordinates")
	assert_eq(4, zone2_coords.size(), "Zone 2 should have 4 coordinates")
	
	# Check coordinate structure
	for coord in zone1_coords:
		assert_true(coord.has("x"), "Coordinate should have x")
		assert_true(coord.has("y"), "Coordinate should have y")

# Test logging and history
func test_add_action_to_phase_log():
	var initial_size = test_game_state.state.phase_log.size()
	
	var action = {"type": "test_action", "unit_id": "test"}
	test_game_state.add_action_to_phase_log(action)
	
	assert_eq(initial_size + 1, test_game_state.state.phase_log.size(), "Phase log should grow")
	assert_eq(action, test_game_state.state.phase_log[-1], "Last action should be the one we added")

func test_commit_phase_log_to_history():
	var initial_history_size = test_game_state.state.history.size()
	
	# Add some actions to phase log
	test_game_state.add_action_to_phase_log({"type": "action1"})
	test_game_state.add_action_to_phase_log({"type": "action2"})
	
	assert_eq(2, test_game_state.state.phase_log.size(), "Should have 2 actions in phase log")
	
	test_game_state.commit_phase_log_to_history()
	
	assert_eq(0, test_game_state.state.phase_log.size(), "Phase log should be cleared")
	assert_eq(initial_history_size + 1, test_game_state.state.history.size(), "History should grow")
	
	var last_entry = test_game_state.state.history[-1]
	assert_true(last_entry.has("turn"), "History entry should have turn")
	assert_true(last_entry.has("phase"), "History entry should have phase")
	assert_true(last_entry.has("actions"), "History entry should have actions")
	assert_eq(2, last_entry.actions.size(), "History entry should have both actions")

# Test snapshots and state management
func test_create_snapshot():
	var snapshot = test_game_state.create_snapshot()
	
	assert_not_null(snapshot, "Snapshot should not be null")
	assert_true(snapshot is Dictionary, "Snapshot should be a dictionary")
	assert_true(snapshot.has("meta"), "Snapshot should have meta")
	assert_true(snapshot.has("units"), "Snapshot should have units")
	
	# Verify it's a deep copy
	snapshot.meta.turn_number = 99
	assert_ne(99, test_game_state.state.meta.turn_number, "Original should not be modified")

func test_load_from_snapshot():
	# Modify current state
	test_game_state.set_phase(GameStateData.Phase.MOVEMENT)
	test_game_state.advance_turn()
	
	# Load from initial snapshot
	test_game_state.load_from_snapshot(initial_snapshot)
	
	assert_eq(GameStateData.Phase.DEPLOYMENT, test_game_state.get_current_phase(), "Phase should be restored")
	assert_eq(1, test_game_state.get_turn_number(), "Turn should be restored")

func test_deep_copy_functionality():
	var original = {
		"level1": {
			"level2": {
				"array": [1, 2, {"nested": "value"}]
			}
		}
	}
	
	var copy = test_game_state._deep_copy_dict(original)
	
	# Modify copy
	copy.level1.level2.array[2].nested = "modified"
	
	# Original should be unchanged
	assert_eq("value", original.level1.level2.array[2].nested, "Original should not be modified")
	assert_eq("modified", copy.level1.level2.array[2].nested, "Copy should be modified")

# Test validation
func test_validate_state():
	var validation = test_game_state.validate_state()
	assert_true(validation.valid, "Default state should be valid")
	assert_eq(0, validation.errors.size(), "Default state should have no errors")

func test_validate_state_with_missing_keys():
	# Remove required key
	test_game_state.state.erase("meta")
	
	var validation = test_game_state.validate_state()
	assert_false(validation.valid, "State with missing key should be invalid")
	assert_gt(validation.errors.size(), 0, "Should have error messages")
	
	var found_meta_error = false
	for error in validation.errors:
		if error.contains("meta"):
			found_meta_error = true
			break
	assert_true(found_meta_error, "Should report missing meta key")

func test_validate_state_with_missing_meta_keys():
	# Remove required meta key
	test_game_state.state.meta.erase("game_id")
	
	var validation = test_game_state.validate_state()
	assert_false(validation.valid, "State with missing meta key should be invalid")
	assert_gt(validation.errors.size(), 0, "Should have error messages")
	
	var found_game_id_error = false
	for error in validation.errors:
		if error.contains("game_id"):
			found_game_id_error = true
			break
	assert_true(found_game_id_error, "Should report missing game_id key")

# Test board structure
func test_board_structure():
	var board = test_game_state.state.board
	assert_true(board.has("size"), "Board should have size")
	assert_true(board.has("deployment_zones"), "Board should have deployment zones")
	assert_true(board.has("objectives"), "Board should have objectives array")
	assert_true(board.has("terrain"), "Board should have terrain array")
	
	var size = board.size
	assert_eq(44, size.width, "Board width should be 44 inches")
	assert_eq(60, size.height, "Board height should be 60 inches")

# Test unit structure
func test_unit_structure():
	var unit = test_game_state.get_unit("U_INTERCESSORS_A")
	
	# Check required unit fields
	var required_fields = ["id", "squad_id", "owner", "status", "meta", "models"]
	for field in required_fields:
		assert_true(unit.has(field), "Unit should have field: " + field)
	
	# Check unit meta
	var meta = unit.meta
	assert_true(meta.has("name"), "Unit meta should have name")
	assert_true(meta.has("keywords"), "Unit meta should have keywords")
	assert_true(meta.has("stats"), "Unit meta should have stats")
	
	# Check models
	assert_gt(unit.models.size(), 0, "Unit should have models")
	
	var model = unit.models[0]
	var required_model_fields = ["id", "wounds", "current_wounds", "base_mm", "position", "alive", "status_effects"]
	for field in required_model_fields:
		assert_true(model.has(field), "Model should have field: " + field)

# Test players structure
func test_players_structure():
	var players = test_game_state.state.players
	assert_true(players.has("1"), "Should have player 1")
	assert_true(players.has("2"), "Should have player 2")
	
	var player1 = players["1"]
	assert_true(player1.has("cp"), "Player should have CP")
	assert_true(player1.has("vp"), "Player should have VP")
	assert_eq(3, player1.cp, "Initial CP should be 3")
	assert_eq(0, player1.vp, "Initial VP should be 0")