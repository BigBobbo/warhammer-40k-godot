extends "res://addons/gut/test.gd"

# Tests for OA-29: Stompin' Forward ability (Stompa)
#
# Stompin' Forward: Each time this model makes a Normal, Advance or Fall Back move,
# it can move over all non-TITANIC models and terrain features that are 4" or less
# in height as if they were not there.
#
# Tests verify:
# 1. Can move over enemy Infantry (non-TITANIC)
# 2. Can move over enemy MONSTER models (non-TITANIC)
# 3. Can move over enemy VEHICLE models (non-TITANIC)
# 4. Blocked by enemy TITANIC models
# 5. Can move over terrain ≤4" height (low, medium)
# 6. Blocked by terrain >4" height (tall)
# 7. Units without the ability are still blocked normally
#
# Position math for bases:
#   32mm base radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   80mm base radius_px ≈ 63.0 px  (80mm / 25.4 * 40 / 2)
#   170mm base radius_px ≈ 134.0 px (170mm / 25.4 * 40 / 2)
#   200mm base (Stompa) radius_px ≈ 157.5 px (200mm / 25.4 * 40 / 2)
#   PX_PER_INCH = 40.0
#   Engagement range = 1" = 40 px

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

func _create_unit(id: String, owner: int, pos: Vector2, keywords: Array = [], base_mm: int = 32, abilities: Array = []) -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {
			"name": "Unit %s" % id,
			"stats": {"move": 12},
			"keywords": keywords,
			"abilities": abilities
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

func _create_state(units: Dictionary, terrain: Array = []) -> Dictionary:
	return {
		"game_id": "test_stompin_forward",
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
			"size": {"width": 60.0, "height": 60.0},
			"terrain": terrain
		},
		"phase_data": {},
		"settings": {
			"measurement_unit": "inches",
			"scale": 1.0
		}
	}

func _create_stompa(id: String, owner: int, pos: Vector2) -> Dictionary:
	# Stompa: VEHICLE, TITANIC, TOWERING, WALKER with Stompin' Forward ability
	# Using 200mm base (large super-heavy walker)
	return _create_unit(id, owner, pos, ["ORKS", "VEHICLE", "TITANIC", "TOWERING", "WALKER"], 200, ["Stompin' Forward"])

# ==========================================
# Stompin' Forward: Can move over enemy Infantry (non-TITANIC)
# ==========================================

func test_stompin_forward_can_cross_enemy_infantry():
	"""Stompa with Stompin' Forward should move over enemy Infantry"""
	# Stompa (200mm, 157.5px radius) at (800,200), enemy infantry (32mm, 25.2px) at (930,400)
	# Combined radii = 182.7px. ER threshold = 222.7px.
	# At y=400: lateral = 130px < 182.7 → bases overlap ✓
	# Start to enemy: sqrt(130²+200²) = 238.5 > 222.7 → not engaged ✓
	# Dest (800,680) to enemy: sqrt(130²+280²) = 308.7 > 222.7 → not engaged ✓
	# Move distance: 480px / 40 = 12" = max move ✓
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(800, 200)),
		"enemy_infantry": _create_unit("enemy_infantry", 2, Vector2(930, 400), ["INFANTRY"]),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "stompa"}
	var begin_result = phase.execute_action(begin)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "stompa",
		"payload": {
			"model_id": "stompa_m1",
			"dest": [800.0, 680.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Stompa with Stompin' Forward should cross enemy Infantry")

# ==========================================
# Stompin' Forward: Can move over enemy MONSTER models
# ==========================================

func test_stompin_forward_can_cross_enemy_monster():
	"""Stompa with Stompin' Forward should move over enemy MONSTER models (non-TITANIC)"""
	# Stompa (200mm, 157.5px) at (800,200), enemy MONSTER (80mm, 63px) at (1010,400)
	# Combined = 220.5px. ER threshold = 260.5px.
	# At y=400: lateral = 210px < 220.5 → bases overlap ✓
	# Start to enemy: sqrt(210²+200²) = 290 > 260.5 ✓
	# Dest (800,680) to enemy: sqrt(210²+280²) = 350 > 260.5 ✓
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(800, 200)),
		"enemy_monster": _create_unit("enemy_monster", 2, Vector2(1010, 400), ["MONSTER"], 80),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "stompa"}
	var begin_result = phase.execute_action(begin)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "stompa",
		"payload": {
			"model_id": "stompa_m1",
			"dest": [800.0, 680.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Stompa with Stompin' Forward should cross enemy MONSTER")

# ==========================================
# Stompin' Forward: Can move over enemy VEHICLE models
# ==========================================

func test_stompin_forward_can_cross_enemy_vehicle():
	"""Stompa with Stompin' Forward should move over enemy VEHICLE models (non-TITANIC)"""
	# Same geometry as MONSTER test
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(800, 200)),
		"enemy_vehicle": _create_unit("enemy_vehicle", 2, Vector2(1010, 400), ["VEHICLE"], 80),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "stompa"}
	var begin_result = phase.execute_action(begin)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "stompa",
		"payload": {
			"model_id": "stompa_m1",
			"dest": [800.0, 680.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Stompa with Stompin' Forward should cross enemy VEHICLE")

# ==========================================
# Stompin' Forward: Blocked by enemy TITANIC models
# ==========================================

func test_stompin_forward_blocked_by_enemy_titanic():
	"""Stompa with Stompin' Forward should be blocked by enemy TITANIC models"""
	# Stompa (200mm, 157.5px) at (800,200), enemy TITANIC (170mm, 134px) at (1080,400)
	# Combined = 291.5px. ER threshold = 331.5px.
	# At y=400: lateral = 280px < 291.5 → bases overlap ✓
	# Start to enemy: sqrt(280²+200²) = 344 > 331.5 → not engaged ✓
	# Dest (800,680) to enemy: sqrt(280²+280²) = 396 > 331.5 ✓
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(800, 200)),
		"enemy_titanic": _create_unit("enemy_titanic", 2, Vector2(1080, 400), ["VEHICLE", "TITANIC"], 170),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "stompa"}
	var begin_result = phase.execute_action(begin)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "stompa",
		"payload": {
			"model_id": "stompa_m1",
			"dest": [800.0, 680.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Stompa should be blocked by enemy TITANIC model")

# ==========================================
# Stompin' Forward: Terrain ≤4" is passable
# ==========================================

func test_stompin_forward_can_cross_low_terrain():
	"""Stompa with Stompin' Forward should move through low (1.5\") impassable terrain"""
	var terrain = [
		{
			"type": "impassable",
			"height_category": "low",
			"poly": [
				Vector2(350, 450), Vector2(450, 450),
				Vector2(450, 550), Vector2(350, 550)
			]
		}
	]
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(400, 300)),
	}
	var state = _create_state(units, terrain)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "stompa"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "stompa",
		"payload": {
			"model_id": "stompa_m1",
			"dest": [400.0, 500.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Stompa should pass through low (≤4\") impassable terrain")

func test_stompin_forward_can_cross_medium_terrain():
	"""Stompa with Stompin' Forward should move through medium (3.5\") impassable terrain"""
	var terrain = [
		{
			"type": "impassable",
			"height_category": "medium",
			"poly": [
				Vector2(350, 450), Vector2(450, 450),
				Vector2(450, 550), Vector2(350, 550)
			]
		}
	]
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(400, 300)),
	}
	var state = _create_state(units, terrain)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "stompa"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "stompa",
		"payload": {
			"model_id": "stompa_m1",
			"dest": [400.0, 500.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Stompa should pass through medium (≤4\") impassable terrain")

# ==========================================
# Stompin' Forward: Terrain >4" blocks movement
# ==========================================

func test_stompin_forward_blocked_by_tall_terrain():
	"""Stompa with Stompin' Forward should be blocked by tall (6\") impassable terrain"""
	var terrain = [
		{
			"type": "impassable",
			"height_category": "tall",
			"poly": [
				Vector2(350, 450), Vector2(450, 450),
				Vector2(450, 550), Vector2(350, 550)
			]
		}
	]
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(400, 300)),
	}
	var state = _create_state(units, terrain)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "stompa"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "stompa",
		"payload": {
			"model_id": "stompa_m1",
			"dest": [400.0, 500.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Stompa should be blocked by tall (>4\") impassable terrain")

# ==========================================
# Units WITHOUT Stompin' Forward: Still blocked normally
# ==========================================

func test_normal_unit_still_blocked_by_enemy_infantry():
	"""A unit without Stompin' Forward should still be blocked by enemy models during Normal Move"""
	var units = {
		"infantry": _create_unit("infantry", 1, Vector2(400, 200), ["INFANTRY"]),
		"enemy_infantry": _create_unit("enemy_infantry", 2, Vector2(400, 300), ["INFANTRY"]),
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
	assert_false(result.get("valid", true), "Unit without Stompin' Forward should still be blocked by enemy infantry")
