extends "res://addons/gut/test.gd"

# Tests for P2-73: Monster/Vehicle cannot move through friendly Monster/Vehicle
#
# 10e Errata: No model can move across MONSTER or VEHICLE models (friendly or enemy)
# unless the moving model has the FLY keyword.
#
# This validates _path_crosses_monster_vehicle_bases() blocks movement paths
# that cross friendly or enemy Monster/Vehicle model bases, and that FLY exempts.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   PX_PER_INCH = 40.0

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

func after_each():
	if phase:
		phase.queue_free()
		phase = null

# ==========================================
# Helpers
# ==========================================

func _setup_phase(test_state: Dictionary) -> void:
	game_state_node.state = test_state
	phase = MovementPhaseScript.new()
	add_child(phase)
	phase.enter_phase(test_state)

func _create_unit(id: String, owner: int, pos: Vector2, keywords: Array = [], base_mm: int = 32) -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {
			"name": "Unit %s" % id,
			"stats": {"move": 6},
			"keywords": keywords
		},
		"models": [
			{
				"id": "%s_m1" % id,
				"alive": true,
				"position": {"x": pos.x, "y": pos.y},
				"base_mm": base_mm
			}
		],
		"weapons": [],
		"attachment_data": {}
	}

func _create_state(units: Dictionary) -> Dictionary:
	return {
		"game_id": "test_mv_block",
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
		"units": units,
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

# ==========================================
# Infantry moving through friendly VEHICLE is blocked
# ==========================================

func test_infantry_blocked_by_friendly_vehicle():
	"""Infantry moving through a friendly Vehicle model should be blocked"""
	# Place infantry at y=200, friendly vehicle at y=300, destination at y=400
	# The path from 200 -> 400 crosses the vehicle at y=300
	var units = {
		"infantry": _create_unit("infantry", 1, Vector2(400, 200), ["INFANTRY"]),
		"vehicle": _create_unit("vehicle", 1, Vector2(400, 300), ["VEHICLE"], 60),
	}
	var state = _create_state(units)
	_setup_phase(state)

	# Begin normal move for infantry
	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "infantry"}
	var begin_result = phase.execute_action(begin)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	# Try to stage a move that crosses the vehicle base
	# Move from y=200 to y=400 (5" = 200px), crossing vehicle at y=300
	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "infantry",
		"payload": {
			"model_id": "infantry_m1",
			"dest": [400.0, 400.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Should be blocked from crossing friendly Vehicle")
	var errors = result.get("errors", [])
	var found_mv_error = false
	for err in errors:
		if "Monster or Vehicle" in err:
			found_mv_error = true
			break
	assert_true(found_mv_error, "Error should mention Monster or Vehicle blocking")

# ==========================================
# Infantry moving through friendly MONSTER is blocked
# ==========================================

func test_infantry_blocked_by_friendly_monster():
	"""Infantry moving through a friendly Monster model should be blocked"""
	var units = {
		"infantry": _create_unit("infantry", 1, Vector2(400, 200), ["INFANTRY"]),
		"monster": _create_unit("monster", 1, Vector2(400, 300), ["MONSTER"], 60),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "infantry"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "infantry",
		"payload": {
			"model_id": "infantry_m1",
			"dest": [400.0, 400.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Should be blocked from crossing friendly Monster")

# ==========================================
# FLY units are exempt
# ==========================================

func test_fly_unit_can_cross_friendly_vehicle():
	"""A unit with FLY keyword should be able to move through friendly Vehicle"""
	var units = {
		"flyer": _create_unit("flyer", 1, Vector2(400, 200), ["INFANTRY", "FLY"]),
		"vehicle": _create_unit("vehicle", 1, Vector2(400, 300), ["VEHICLE"], 60),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "flyer"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "flyer",
		"payload": {
			"model_id": "flyer_m1",
			"dest": [400.0, 400.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "FLY unit should be able to cross friendly Vehicle")

# ==========================================
# Infantry NOT crossing Monster/Vehicle is fine
# ==========================================

func test_infantry_not_crossing_vehicle_is_allowed():
	"""Infantry moving alongside (not through) a Vehicle should be allowed"""
	# Place infantry at (200, 200), vehicle at (400, 300) — not in the path
	var units = {
		"infantry": _create_unit("infantry", 1, Vector2(200, 200), ["INFANTRY"]),
		"vehicle": _create_unit("vehicle", 1, Vector2(400, 300), ["VEHICLE"], 60),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "infantry"}
	phase.execute_action(begin)

	# Move infantry downward, well away from the vehicle
	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "infantry",
		"payload": {
			"model_id": "infantry_m1",
			"dest": [200.0, 400.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Infantry not crossing Vehicle path should be allowed")

# ==========================================
# Monster/Vehicle blocking enemy Monster/Vehicle too
# ==========================================

func test_infantry_blocked_by_enemy_vehicle():
	"""Infantry should also be blocked from moving through enemy Vehicle (in addition to existing enemy path crossing)"""
	# The existing _path_crosses_enemy_bases already blocks enemy crossing
	# for Normal/Advance. This test verifies the Monster/Vehicle check also
	# applies to enemy units.
	var units = {
		"infantry": _create_unit("infantry", 1, Vector2(400, 200), ["INFANTRY"]),
		"enemy_vehicle": _create_unit("enemy_vehicle", 2, Vector2(400, 300), ["VEHICLE"], 60),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "infantry"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "infantry",
		"payload": {
			"model_id": "infantry_m1",
			"dest": [400.0, 400.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	# Should be blocked (by either enemy crossing or Monster/Vehicle crossing)
	assert_false(result.get("valid", true), "Should be blocked from crossing enemy Vehicle")

# ==========================================
# Monster cannot move through friendly Monster
# ==========================================

func test_monster_blocked_by_friendly_monster():
	"""A Monster moving through another friendly Monster should be blocked"""
	var units = {
		"monster_a": _create_unit("monster_a", 1, Vector2(400, 200), ["MONSTER"], 60),
		"monster_b": _create_unit("monster_b", 1, Vector2(400, 300), ["MONSTER"], 60),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "monster_a"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "monster_a",
		"payload": {
			"model_id": "monster_a_m1",
			"dest": [400.0, 440.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Monster should be blocked from crossing friendly Monster")

# ==========================================
# Infantry can still move through friendly Infantry
# ==========================================

func test_infantry_can_cross_friendly_infantry():
	"""Infantry should still be able to move through friendly Infantry (not Monster/Vehicle)"""
	var units = {
		"infantry_a": _create_unit("infantry_a", 1, Vector2(400, 200), ["INFANTRY"]),
		"infantry_b": _create_unit("infantry_b", 1, Vector2(400, 300), ["INFANTRY"]),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "infantry_a"}
	phase.execute_action(begin)

	# Move through friendly infantry position — should be allowed (path crossing OK,
	# just can't end on top)
	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "infantry_a",
		"payload": {
			"model_id": "infantry_a_m1",
			"dest": [400.0, 400.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Infantry should be able to move through friendly Infantry")
