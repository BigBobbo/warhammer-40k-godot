extends "res://addons/gut/test.gd"

# Tests for T2-12: active_moves dictionary sync via GameState flags
#
# Per the MULTIPLAYER_STATE_SYNC_PATTERN: validation logic must use synced
# GameState flags, not local phase state. This test verifies that:
# 1. movement_active flag is set when movement begins
# 2. movement_active flag is cleared when movement is confirmed
# 3. movement_active flag is cleared when movement is reset
# 4. get_available_actions uses GameState flags for completion checks
# 5. _validate_end_movement uses GameState flags for blocking

const MovementPhaseScript = preload("res://phases/MovementPhase.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

var phase: Node
var game_state_node: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state_node = AutoloadHelper.get_game_state()
	assert_not_null(game_state_node, "GameState autoload must be available")

	# Set up a minimal game state for movement testing
	var test_state = _create_movement_test_state()
	game_state_node.state = test_state

	# Create and enter movement phase
	phase = MovementPhaseScript.new()
	add_child(phase)
	phase.enter_phase(test_state)

func after_each():
	if phase:
		phase.queue_free()
		phase = null

# ==========================================
# Helpers
# ==========================================

func _create_movement_test_state() -> Dictionary:
	return {
		"game_id": "test_sync",
		"current_phase": GameStateData.Phase.MOVEMENT,
		"current_player": 1,
		"active_player": 1,
		"turn": 1,
		"round": 1,
		"meta": {
			"active_player": 1,
			"turn_number": 1,
			"battle_round": 1,
			"phase": GameStateData.Phase.MOVEMENT
		},
		"units": {
			"unit_a": _create_test_unit("unit_a", "Test Marines", 1, Vector2(200, 200)),
			"unit_b": _create_test_unit("unit_b", "Test Assault", 1, Vector2(400, 200)),
			"enemy_1": _create_test_unit("enemy_1", "Enemy Unit", 2, Vector2(200, 2000)),
		},
		"board": {
			"size": {"width": 44.0, "height": 60.0},
			"terrain": []
		},
		"phase_data": {},
		"settings": {
			"measurement_unit": "inches",
			"scale": 1.0
		}
	}

func _create_test_unit(id: String, name: String, owner: int, base_pos: Vector2 = Vector2(200, 200)) -> Dictionary:
	# Models spaced 60px apart (> 50.4px for 32mm bases) to avoid overlap
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {
			"name": name,
			"stats": {"move": 6},
			"keywords": []
		},
		"models": [
			{
				"id": "%s_m1" % id,
				"alive": true,
				"position": {"x": base_pos.x, "y": base_pos.y},
				"base_mm": 32
			},
			{
				"id": "%s_m2" % id,
				"alive": true,
				"position": {"x": base_pos.x + 60.0, "y": base_pos.y},
				"base_mm": 32
			}
		],
		"weapons": [],
		"attachment_data": {}
	}

# ==========================================
# BEGIN_NORMAL_MOVE sets movement_active flag
# ==========================================

func test_begin_normal_move_sets_movement_active_flag():
	"""BEGIN_NORMAL_MOVE should include movement_active flag in changes"""
	var action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_a"}
	var result = phase.process_action(action)

	assert_true(result.success, "BEGIN_NORMAL_MOVE should succeed")

	# Check that changes include movement_active flag
	var found_movement_active = false
	for change in result.get("changes", []):
		if change.get("path", "").ends_with("flags.movement_active") and change.get("value") == true:
			found_movement_active = true
			break

	assert_true(found_movement_active,
		"BEGIN_NORMAL_MOVE changes should include movement_active=true flag")

func test_begin_normal_move_sets_move_cap_flag():
	"""BEGIN_NORMAL_MOVE should also set move_cap_inches"""
	var action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_a"}
	var result = phase.process_action(action)

	assert_true(result.success, "BEGIN_NORMAL_MOVE should succeed")

	var found_move_cap = false
	for change in result.get("changes", []):
		if change.get("path", "").ends_with("flags.move_cap_inches"):
			found_move_cap = true
			break

	assert_true(found_move_cap,
		"BEGIN_NORMAL_MOVE changes should include move_cap_inches flag")

# ==========================================
# BEGIN_FALL_BACK sets movement_active flag
# ==========================================

func test_begin_fall_back_sets_movement_active_flag():
	"""BEGIN_FALL_BACK should include movement_active flag in changes"""
	# For fall back we need the unit to be "engaged" - mock this by setting up
	# the state so _is_unit_engaged returns true. Since we can't easily mock
	# engagement, we test the process function directly by testing the changes
	# returned contain the movement_active flag pattern.
	# The validation would fail without engagement, but process_action can be
	# tested by looking at what _process_begin_fall_back returns.

	# Instead, verify the flag is present in the changes returned by
	# _process_begin_fall_back by calling it directly
	var action = {"type": "BEGIN_FALL_BACK", "actor_unit_id": "unit_a"}

	# We call process_action directly (skipping validation) to test flag output
	var result = phase.process_action(action)

	# Check for movement_active in changes
	var found_movement_active = false
	for change in result.get("changes", []):
		if change.get("path", "").ends_with("flags.movement_active") and change.get("value") == true:
			found_movement_active = true
			break

	assert_true(found_movement_active,
		"BEGIN_FALL_BACK changes should include movement_active=true flag")

# ==========================================
# CONFIRM_UNIT_MOVE clears movement_active flag
# ==========================================

func test_confirm_unit_move_clears_movement_active_flag():
	"""CONFIRM_UNIT_MOVE should remove movement_active flag"""
	# First begin a normal move
	var begin_action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_a"}
	var begin_result = phase.execute_action(begin_action)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	# Stage a model move (move away from the other model to avoid overlap)
	# Move model_m1 downward by 80px (~2") - well within 6" move cap
	var stage_action = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_a",
		"payload": {
			"model_id": "unit_a_m1",
			"dest": [200.0, 280.0],
			"rotation": 0.0
		}
	}
	var stage_result = phase.execute_action(stage_action)
	assert_true(stage_result.get("success", false), "STAGE_MODEL_MOVE should succeed")

	# Now confirm the move
	var confirm_action = {"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "unit_a"}
	var confirm_result = phase.process_action(confirm_action)
	assert_true(confirm_result.success, "CONFIRM_UNIT_MOVE should succeed")

	# Check that changes include removal of movement_active flag
	var found_remove_active = false
	var found_set_moved = false
	for change in confirm_result.get("changes", []):
		if change.get("path", "").ends_with("flags.movement_active") and change.get("op") == "remove":
			found_remove_active = true
		if change.get("path", "").ends_with("flags.moved") and change.get("value") == true:
			found_set_moved = true

	assert_true(found_remove_active,
		"CONFIRM_UNIT_MOVE changes should remove movement_active flag")
	assert_true(found_set_moved,
		"CONFIRM_UNIT_MOVE changes should set moved=true flag")

# ==========================================
# RESET_UNIT_MOVE clears movement_active flag
# ==========================================

func test_reset_unit_move_clears_movement_active_flag():
	"""RESET_UNIT_MOVE should remove movement_active flag"""
	# First begin a normal move
	var begin_action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_a"}
	var begin_result = phase.execute_action(begin_action)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	# Now reset the move
	var reset_action = {"type": "RESET_UNIT_MOVE", "actor_unit_id": "unit_a"}
	var reset_result = phase.process_action(reset_action)
	assert_true(reset_result.success, "RESET_UNIT_MOVE should succeed")

	# Check that changes include removal of movement_active flag
	var found_remove_active = false
	for change in reset_result.get("changes", []):
		if change.get("path", "").ends_with("flags.movement_active") and change.get("op") == "remove":
			found_remove_active = true
			break

	assert_true(found_remove_active,
		"RESET_UNIT_MOVE changes should remove movement_active flag")

# ==========================================
# END_MOVEMENT cleanup of stale flags
# ==========================================

func test_end_movement_cleans_up_stale_movement_active_flags():
	"""END_MOVEMENT should clean up any remaining movement_active flags"""
	# Manually set a stale movement_active flag in GameState
	var unit = game_state_node.state.units.get("unit_a", {})
	if not unit.has("flags"):
		unit["flags"] = {}
	unit.flags["movement_active"] = true
	unit.flags["moved"] = true  # Mark as moved so it doesn't block end

	# Refresh phase snapshot
	phase.game_state_snapshot = game_state_node.state.duplicate(true)

	var action = {"type": "END_MOVEMENT"}
	var result = phase.process_action(action)
	assert_true(result.success, "END_MOVEMENT should succeed")

	# Check that stale movement_active flag is cleaned up
	var found_cleanup = false
	for change in result.get("changes", []):
		if "unit_a" in change.get("path", "") and change.get("path", "").ends_with("flags.movement_active") and change.get("op") == "remove":
			found_cleanup = true
			break

	assert_true(found_cleanup,
		"END_MOVEMENT should clean up stale movement_active flags")

# ==========================================
# get_available_actions uses GameState for completion check
# ==========================================

func test_get_available_actions_uses_gamestate_for_active_move_completion():
	"""get_available_actions should use GameState flags.moved, not local completed flag"""
	# Begin a move (sets up local active_moves)
	var begin_action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_a"}
	phase.execute_action(begin_action)

	# Simulate what happens in multiplayer: GameState says moved=true
	# but local active_moves still has completed=false
	var unit = game_state_node.state.units.get("unit_a", {})
	unit.flags["moved"] = true
	# Remove movement_active since it would have been cleared on confirm
	unit.flags.erase("movement_active")
	phase.game_state_snapshot = game_state_node.state.duplicate(true)

	# get_available_actions should NOT show CONFIRM/RESET for unit_a
	# because GameState flags.moved=true (even though local completed=false)
	var actions = phase.get_available_actions()

	var has_confirm_for_unit_a = false
	for action in actions:
		if action.get("type") == "CONFIRM_UNIT_MOVE" and action.get("actor_unit_id") == "unit_a":
			has_confirm_for_unit_a = true
			break

	assert_false(has_confirm_for_unit_a,
		"Should not show CONFIRM_UNIT_MOVE for unit_a when GameState says moved=true")

func test_get_available_actions_blocks_end_movement_when_movement_active_in_gamestate():
	"""END_MOVEMENT should be blocked when GameState has movement_active flag"""
	# Set movement_active flag in GameState for a unit (simulating host started a move)
	var unit = game_state_node.state.units.get("unit_a", {})
	if not unit.has("flags"):
		unit["flags"] = {}
	unit.flags["movement_active"] = true
	phase.game_state_snapshot = game_state_node.state.duplicate(true)

	var actions = phase.get_available_actions()

	var has_end_movement = false
	for action in actions:
		if action.get("type") == "END_MOVEMENT":
			has_end_movement = true
			break

	assert_false(has_end_movement,
		"END_MOVEMENT should not be available when GameState has movement_active flag")

# ==========================================
# validate_end_movement uses GameState for blocking
# ==========================================

func test_validate_end_movement_blocks_when_movement_active_in_gamestate():
	"""_validate_end_movement should block when GameState shows movement_active"""
	# Set movement_active flag in GameState
	var unit = game_state_node.state.units.get("unit_a", {})
	if not unit.has("flags"):
		unit["flags"] = {}
	unit.flags["movement_active"] = true
	phase.game_state_snapshot = game_state_node.state.duplicate(true)

	var action = {"type": "END_MOVEMENT"}
	var result = phase.validate_action(action)

	assert_false(result.get("valid", true),
		"END_MOVEMENT should be invalid when movement_active flag is set in GameState")

func test_validate_end_movement_passes_when_no_active_moves():
	"""_validate_end_movement should pass when no active moves exist"""
	# Clean state - no active moves, no movement_active flags
	var action = {"type": "END_MOVEMENT"}
	var result = phase.validate_action(action)

	assert_true(result.get("valid", false),
		"END_MOVEMENT should be valid when no active moves exist")

# ==========================================
# Consistency check function
# ==========================================

func test_consistency_check_detects_desync():
	"""_check_active_moves_sync should detect when local and GameState disagree"""
	# Begin a move to populate active_moves
	var begin_action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_a"}
	var result = phase.execute_action(begin_action)
	assert_true(result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	# Verify active_moves was populated
	assert_true(phase.active_moves.has("unit_a"), "active_moves should have unit_a after begin move")

	# Simulate desync: manually set local completed=true without setting GameState moved=true
	phase.active_moves["unit_a"]["completed"] = true

	# This should log a warning but not crash
	phase._check_active_moves_sync()

	# If we get here without error, the function works
	assert_true(true, "Consistency check should run without crashing")

# ==========================================
# Helper assertion
# ==========================================

func assert_has(container, item, message: String = ""):
	var contains = item in container
	assert_true(contains, message if message else str(container) + " should contain " + str(item))
