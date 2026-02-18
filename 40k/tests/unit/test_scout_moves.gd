extends "res://addons/gut/test.gd"

# Tests for the Scout moves implementation (T3-5)
#
# Per Warhammer 40k 10th Edition rules:
# After both players have deployed their armies, units with Scout X"
# can make a Normal Move of up to X", ending >9" from all enemy models.
# The player going first moves their Scout units first.
#
# These tests verify:
# 1. Scout ability detection (unit_has_scout, get_scout_distance)
# 2. ScoutPhase creation and phase transitions
# 3. Scout move validation (distance, enemy proximity, board bounds)
# 4. Scout move processing (model position updates)
# 5. Phase auto-skips when no Scout units exist
# 6. Player alternation in Scout phase

const GameStateData = preload("res://autoloads/GameState.gd")
const ScoutPhaseScript = preload("res://phases/ScoutPhase.gd")

var game_state_node: Node
var phase: Node

# ==========================================
# Setup / Teardown
# ==========================================

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state_node = AutoloadHelper.get_game_state()
	assert_not_null(game_state_node, "GameState autoload must be available")

func after_each():
	if phase:
		phase.queue_free()
		phase = null

# ==========================================
# Helpers
# ==========================================

func _create_scout_test_state(include_scouts: bool = true) -> Dictionary:
	"""Create a test game state with optional Scout units."""
	var state = {
		"game_id": "test_scout",
		"meta": {
			"active_player": 1,
			"turn_number": 1,
			"battle_round": 1,
			"phase": GameStateData.Phase.SCOUT
		},
		"units": {},
		"board": {
			"size": {"width": 44.0, "height": 60.0},
			"deployment_zones": [],
			"terrain": []
		},
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		},
		"phase_log": [],
		"history": []
	}

	# Player 1 scout unit - deployed in their half of the board
	if include_scouts:
		state.units["scout_unit_1"] = _create_scout_unit("scout_unit_1", "Infiltrator Squad", 1, Vector2(400, 1800), 6)

	# Player 1 non-scout unit
	state.units["normal_unit_1"] = _create_normal_unit("normal_unit_1", "Intercessor Squad", 1, Vector2(200, 2000))

	# Player 2 enemy unit - deployed in their half
	state.units["enemy_unit_1"] = _create_normal_unit("enemy_unit_1", "Ork Boyz", 2, Vector2(400, 600))

	return state

func _create_scout_unit(id: String, name: String, owner: int, base_pos: Vector2, scout_dist: int = 6) -> Dictionary:
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": name,
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"keywords": ["INFANTRY", "PRIMARIS", "PHOBOS"],
			"abilities": [
				{
					"name": "Scout %d\"" % scout_dist,
					"type": "Core",
					"value": scout_dist,
					"description": "After deployment, this unit can make a Normal Move of up to %d\"." % scout_dist
				},
				{
					"name": "Infiltrators",
					"type": "Core",
					"description": "Can deploy anywhere >9\" from enemies."
				}
			]
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": {"x": base_pos.x, "y": base_pos.y}, "alive": true, "status_effects": []},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": {"x": base_pos.x + 60.0, "y": base_pos.y}, "alive": true, "status_effects": []}
		]
	}

func _create_normal_unit(id: String, name: String, owner: int, base_pos: Vector2) -> Dictionary:
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": name,
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"keywords": ["INFANTRY"],
			"abilities": []
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": {"x": base_pos.x, "y": base_pos.y}, "alive": true, "status_effects": []},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": {"x": base_pos.x + 60.0, "y": base_pos.y}, "alive": true, "status_effects": []}
		]
	}

func _setup_phase_with_state(test_state: Dictionary) -> void:
	game_state_node.state = test_state
	phase = ScoutPhaseScript.new()
	add_child(phase)
	phase.enter_phase(test_state)

# ==========================================
# Scout Ability Detection Tests
# ==========================================

func test_unit_has_scout_with_scout_ability():
	"""unit_has_scout should detect Scout ability in dict format."""
	var test_state = _create_scout_test_state(true)
	game_state_node.state = test_state
	assert_true(game_state_node.unit_has_scout("scout_unit_1"), "Scout unit should have Scout ability")

func test_unit_has_scout_returns_false_for_non_scout():
	"""unit_has_scout should return false for units without Scout."""
	var test_state = _create_scout_test_state(true)
	game_state_node.state = test_state
	assert_false(game_state_node.unit_has_scout("normal_unit_1"), "Non-scout unit should not have Scout ability")

func test_unit_has_scout_returns_false_for_nonexistent_unit():
	"""unit_has_scout should return false for nonexistent unit."""
	var test_state = _create_scout_test_state(true)
	game_state_node.state = test_state
	assert_false(game_state_node.unit_has_scout("nonexistent_unit"), "Nonexistent unit should not have Scout ability")

func test_get_scout_distance_from_value_field():
	"""get_scout_distance should extract distance from value field."""
	var test_state = _create_scout_test_state(true)
	game_state_node.state = test_state
	var distance = game_state_node.get_scout_distance("scout_unit_1")
	assert_eq(distance, 6.0, "Scout distance should be 6.0 from value field")

func test_get_scout_distance_from_name_parsing():
	"""get_scout_distance should parse distance from name when no value field."""
	var test_state = _create_scout_test_state(false)
	# Add a unit with Scout ability but no value field
	test_state.units["parsed_scout"] = {
		"id": "parsed_scout",
		"squad_id": "parsed_scout",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Scout Unit",
			"stats": {"move": 6},
			"keywords": [],
			"abilities": [
				{"name": "Scout 9\"", "type": "Core", "description": "Can scout 9 inches."}
			]
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": {"x": 200, "y": 200}, "alive": true, "status_effects": []}
		]
	}
	game_state_node.state = test_state
	var distance = game_state_node.get_scout_distance("parsed_scout")
	assert_eq(distance, 9.0, "Scout distance should be 9.0 parsed from name 'Scout 9\"'")

func test_get_scout_distance_returns_zero_for_non_scout():
	"""get_scout_distance should return 0.0 for non-scout unit."""
	var test_state = _create_scout_test_state(true)
	game_state_node.state = test_state
	var distance = game_state_node.get_scout_distance("normal_unit_1")
	assert_eq(distance, 0.0, "Non-scout unit should have 0 scout distance")

func test_get_scout_units_for_player():
	"""get_scout_units_for_player should return only deployed scout units for specified player."""
	var test_state = _create_scout_test_state(true)
	game_state_node.state = test_state
	var scouts = game_state_node.get_scout_units_for_player(1)
	assert_eq(scouts.size(), 1, "Player 1 should have 1 scout unit")
	assert_has(scouts, "scout_unit_1", "Scout unit should be in the list")

func test_get_scout_units_for_player_excludes_reserves():
	"""get_scout_units_for_player should not include units in reserves."""
	var test_state = _create_scout_test_state(true)
	test_state.units["scout_unit_1"]["status"] = GameStateData.UnitStatus.IN_RESERVES
	game_state_node.state = test_state
	var scouts = game_state_node.get_scout_units_for_player(1)
	assert_eq(scouts.size(), 0, "Reserves unit should not be in scout list")

# ==========================================
# Phase Enum Tests
# ==========================================

func test_scout_phase_exists_in_enum():
	"""SCOUT should exist in the Phase enum between DEPLOYMENT and COMMAND."""
	var scout_value = GameStateData.Phase.SCOUT
	var deployment_value = GameStateData.Phase.DEPLOYMENT
	var command_value = GameStateData.Phase.COMMAND
	assert_true(scout_value > deployment_value, "SCOUT should be after DEPLOYMENT")
	assert_true(scout_value < command_value, "SCOUT should be before COMMAND")

# ==========================================
# ScoutPhase Initialization Tests
# ==========================================

func test_scout_phase_identifies_scout_units():
	"""ScoutPhase should identify units with Scout ability on enter."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	# Check that scout_units_pending has the scout unit
	var p1_pending = phase.scout_units_pending.get(1, [])
	assert_eq(p1_pending.size(), 1, "Player 1 should have 1 pending scout unit")
	assert_has(p1_pending, "scout_unit_1", "scout_unit_1 should be pending")

func test_scout_phase_no_scouts_auto_completes():
	"""ScoutPhase should auto-complete when no units have Scout ability."""
	var test_state = _create_scout_test_state(false)
	_setup_phase_with_state(test_state)

	# Phase should signal completion (via call_deferred)
	# Wait for the deferred call
	await get_tree().process_frame
	await get_tree().process_frame

	# The phase should have no pending units
	var total_pending = 0
	for player in phase.scout_units_pending:
		total_pending += phase.scout_units_pending[player].size()
	assert_eq(total_pending, 0, "No pending scout units when no scouts exist")

# ==========================================
# Scout Move Validation Tests
# ==========================================

func test_validate_begin_scout_move_valid():
	"""BEGIN_SCOUT_MOVE should succeed for a valid scout unit."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	var action = {"type": "BEGIN_SCOUT_MOVE", "unit_id": "scout_unit_1"}
	var result = phase.validate_action(action)
	assert_true(result.valid, "Valid scout unit should pass validation")

func test_validate_begin_scout_move_non_scout_unit():
	"""BEGIN_SCOUT_MOVE should fail for a unit without Scout ability."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	var action = {"type": "BEGIN_SCOUT_MOVE", "unit_id": "normal_unit_1"}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Non-scout unit should fail validation")

func test_validate_begin_scout_move_wrong_player():
	"""BEGIN_SCOUT_MOVE should fail for a unit belonging to the wrong player."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	var action = {"type": "BEGIN_SCOUT_MOVE", "unit_id": "enemy_unit_1"}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Enemy unit should fail validation")

func test_validate_scout_move_within_distance():
	"""SET_SCOUT_MODEL_DEST should succeed when move is within Scout distance."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	# Begin the scout move
	var begin_action = {"type": "BEGIN_SCOUT_MOVE", "unit_id": "scout_unit_1"}
	phase.process_action(begin_action)

	# Move a model 5" (200px at 40px/inch) - well within 6" limit
	var current_y = 1800.0
	var dest_y = current_y - 200.0  # 5 inches north
	var action = {
		"type": "SET_SCOUT_MODEL_DEST",
		"unit_id": "scout_unit_1",
		"model_id": "m1",
		"destination": {"x": 400.0, "y": dest_y}
	}
	var result = phase.validate_action(action)
	assert_true(result.valid, "Move within 5\" should be valid (max 6\")")

func test_validate_scout_move_exceeds_distance():
	"""SET_SCOUT_MODEL_DEST should fail when move exceeds Scout distance."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	# Begin the scout move
	var begin_action = {"type": "BEGIN_SCOUT_MOVE", "unit_id": "scout_unit_1"}
	phase.process_action(begin_action)

	# Try to move 8" (320px) - exceeds 6" limit
	var current_y = 1800.0
	var dest_y = current_y - 320.0
	var action = {
		"type": "SET_SCOUT_MODEL_DEST",
		"unit_id": "scout_unit_1",
		"model_id": "m1",
		"destination": {"x": 400.0, "y": dest_y}
	}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Move exceeding 8\" should be invalid (max 6\")")

func test_validate_scout_move_too_close_to_enemy():
	"""SET_SCOUT_MODEL_DEST should fail when ending <9\" from enemy models."""
	var test_state = _create_scout_test_state(true)
	# Place enemy unit close enough that a scout move would violate the 9" rule
	# Enemy is at y=600, scout is at y=1800
	# Distance between them is 1200px = 30"
	# If scout moves 6" (240px) toward enemy: y = 1800-240 = 1560
	# Distance to enemy: 1560-600 = 960px = 24" — still safe
	# To test violation, place enemy much closer
	test_state.units["close_enemy"] = _create_normal_unit("close_enemy", "Close Ork", 2, Vector2(400, 1200))
	_setup_phase_with_state(test_state)

	# Begin the scout move
	var begin_action = {"type": "BEGIN_SCOUT_MOVE", "unit_id": "scout_unit_1"}
	phase.process_action(begin_action)

	# Move model to a position that would be <9" from close_enemy (at y=1200)
	# 9" = 360px. Model base ~32mm = 0.63", so edge-to-edge needs to be >9"
	# Center-to-center needs to be > 9" + both radii (~9.63" = ~385px)
	# Destination at y=1200-385+50 = y~865 would be too close
	# Actually let's move the scout model toward enemy ending within 9"
	# Enemy at y=1200, if we put model at y=1200 - 340 = 860, that's ~340px/40 = 8.5" center-to-center
	# Edge-to-edge: 8.5 - 0.63 - 0.63 = ~7.24" < 9"... but model starts at y=1800
	# Model needs to be within 6" (240px) move from y=1800 — max y=1560
	# 1560 to 1200 = 360px = 9" center-to-center, minus radii = ~7.74" edge-to-edge < 9"
	var action = {
		"type": "SET_SCOUT_MODEL_DEST",
		"unit_id": "scout_unit_1",
		"model_id": "m1",
		"destination": {"x": 400.0, "y": 1560.0}
	}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Scout move ending <9\" from enemy should be invalid")

# ==========================================
# Scout Move Processing Tests
# ==========================================

func test_process_begin_scout_move():
	"""BEGIN_SCOUT_MOVE should set up active move data."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	var action = {"type": "BEGIN_SCOUT_MOVE", "unit_id": "scout_unit_1"}
	var result = phase.process_action(action)

	assert_true(result.success, "BEGIN_SCOUT_MOVE should succeed")
	assert_true(phase.active_scout_moves.has("scout_unit_1"), "Active scout moves should contain unit")
	assert_eq(phase.active_scout_moves["scout_unit_1"].scout_distance, 6.0, "Scout distance should be 6")

func test_process_confirm_scout_move():
	"""CONFIRM_SCOUT_MOVE should apply staged positions to game state."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	# Begin and stage a move
	phase.process_action({"type": "BEGIN_SCOUT_MOVE", "unit_id": "scout_unit_1"})
	phase.process_action({
		"type": "SET_SCOUT_MODEL_DEST",
		"unit_id": "scout_unit_1",
		"model_id": "m1",
		"destination": {"x": 400.0, "y": 1640.0}  # Move 4" north (160px)
	})

	# Confirm the move
	var result = phase.process_action({"type": "CONFIRM_SCOUT_MOVE", "unit_id": "scout_unit_1"})
	assert_true(result.success, "CONFIRM_SCOUT_MOVE should succeed")

	# Verify unit was removed from pending
	assert_false(phase.scout_units_pending.get(1, []).has("scout_unit_1"),
		"Scout unit should be removed from pending after confirm")

	# Verify unit was added to completed
	assert_has(phase.scout_units_completed, "scout_unit_1",
		"Scout unit should be in completed list")

func test_process_skip_scout_move():
	"""SKIP_SCOUT_MOVE should mark unit as completed without moving."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	var result = phase.process_action({"type": "SKIP_SCOUT_MOVE", "unit_id": "scout_unit_1"})
	assert_true(result.success, "SKIP_SCOUT_MOVE should succeed")

	# Unit should be completed
	assert_has(phase.scout_units_completed, "scout_unit_1",
		"Skipped unit should be in completed list")

	# Unit should not be in pending
	assert_false(phase.scout_units_pending.get(1, []).has("scout_unit_1"),
		"Skipped unit should be removed from pending")

# ==========================================
# Get Available Actions Tests
# ==========================================

func test_get_available_actions_with_scouts():
	"""get_available_actions should return BEGIN/SKIP for pending scout units."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	var actions = phase.get_available_actions()
	var action_types = []
	for a in actions:
		action_types.append(a.get("type", ""))

	assert_has(action_types, "BEGIN_SCOUT_MOVE", "Should have BEGIN_SCOUT_MOVE action")
	assert_has(action_types, "SKIP_SCOUT_MOVE", "Should have SKIP_SCOUT_MOVE action")

func test_get_available_actions_after_all_complete():
	"""get_available_actions should return END_SCOUT_PHASE when all scouts done."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	# Skip the only scout unit
	phase.process_action({"type": "SKIP_SCOUT_MOVE", "unit_id": "scout_unit_1"})

	# Wait for any deferred calls
	await get_tree().process_frame

	var actions = phase.get_available_actions()
	var action_types = []
	for a in actions:
		action_types.append(a.get("type", ""))

	assert_has(action_types, "END_SCOUT_PHASE", "Should have END_SCOUT_PHASE when all done")

# ==========================================
# Phase Transition Tests
# ==========================================

func test_scout_phase_type():
	"""ScoutPhase should have SCOUT phase type."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)
	assert_eq(phase.phase_type, GameStateData.Phase.SCOUT, "Phase type should be SCOUT")

func test_should_complete_phase_false_while_pending():
	"""_should_complete_phase should return false while scouts are pending."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)
	assert_false(phase._should_complete_phase(), "Should not complete while scouts pending")

func test_should_complete_phase_true_when_done():
	"""_should_complete_phase should return true when all scouts are done."""
	var test_state = _create_scout_test_state(true)
	_setup_phase_with_state(test_state)

	# Skip all scout units
	phase.process_action({"type": "SKIP_SCOUT_MOVE", "unit_id": "scout_unit_1"})

	# Wait for deferred calls
	await get_tree().process_frame

	assert_true(phase._should_complete_phase(), "Should complete when all scouts done")

# ==========================================
# String-format Scout ability detection
# ==========================================

func test_unit_has_scout_string_format():
	"""unit_has_scout should detect Scout as a simple string ability."""
	var test_state = _create_scout_test_state(false)
	test_state.units["string_scout"] = {
		"id": "string_scout",
		"squad_id": "string_scout",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "String Scout",
			"stats": {"move": 6},
			"keywords": [],
			"abilities": ["Scout 6\""]
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": {"x": 200, "y": 200}, "alive": true, "status_effects": []}
		]
	}
	game_state_node.state = test_state
	assert_true(game_state_node.unit_has_scout("string_scout"), "Should detect Scout as string ability")

func test_get_scout_distance_string_format():
	"""get_scout_distance should parse distance from string-format ability."""
	var test_state = _create_scout_test_state(false)
	test_state.units["string_scout"] = {
		"id": "string_scout",
		"squad_id": "string_scout",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "String Scout",
			"stats": {"move": 6},
			"keywords": [],
			"abilities": ["Scout 12\""]
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": {"x": 200, "y": 200}, "alive": true, "status_effects": []}
		]
	}
	game_state_node.state = test_state
	var distance = game_state_node.get_scout_distance("string_scout")
	assert_eq(distance, 12.0, "Scout distance should be 12.0 from string 'Scout 12\"'")
