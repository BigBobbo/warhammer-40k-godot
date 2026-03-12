extends "res://addons/gut/test.gd"

# Tests for OA-28: Clankin' Forward ability (Morkanaut/Gorkanaut)
#
# Clankin' Forward: Each time this model makes a Normal, Advance or Fall Back move,
# it can move over enemy models (excluding MONSTER and VEHICLE models) and terrain
# features that are 4" or less in height as if they were not there.
#
# Tests verify:
# 1. Can move over non-MONSTER/VEHICLE enemy models
# 2. Still blocked by enemy MONSTER/VEHICLE models
# 3. Can move over terrain ≤4" height (low, medium)
# 4. Blocked by terrain >4" height (tall)
# 5. Units without the ability are still blocked normally
#
# Position math for bases:
#   32mm base radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   170mm base (Morkanaut) radius_px ≈ 134 px (170mm / 25.4 * 40 / 2)
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

func _create_unit(id: String, owner: int, pos: Vector2, keywords: Array = [], base_mm: int = 32, abilities: Array = []) -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {
			"name": "Unit %s" % id,
			"stats": {"move": 10},
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
		"game_id": "test_clankin_forward",
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
			"terrain": terrain
		},
		"phase_data": {},
		"settings": {
			"measurement_unit": "inches",
			"scale": 1.0
		}
	}

func _create_morkanaut(id: String, owner: int, pos: Vector2) -> Dictionary:
	# Morkanaut: VEHICLE, TITANIC, TOWERING, WALKER with Clankin' Forward ability
	# Using 170mm base (large walker model)
	return _create_unit(id, owner, pos, ["ORKS", "VEHICLE", "TITANIC", "TOWERING", "WALKER"], 170, ["Clankin' Forward"])

# ==========================================
# Clankin' Forward: Can move over non-MONSTER/VEHICLE enemy models
# ==========================================

func test_clankin_forward_can_cross_enemy_infantry():
	"""Morkanaut with Clankin' Forward should move over enemy Infantry"""
	# 170mm base radius ≈ 134 px, 32mm base radius ≈ 25 px
	# Enemy offset laterally so path crosses its base but destination doesn't overlap.
	# At y=400, morkanaut base (radius 134) at x=600 extends to x=734 — overlaps enemy at x=700.
	# At dest (600,550), distance to enemy (700,400) = sqrt(100²+150²)=180 > 159 — no overlap.
	var units = {
		"morkanaut": _create_morkanaut("morkanaut", 1, Vector2(600, 200)),
		"enemy_infantry": _create_unit("enemy_infantry", 2, Vector2(700, 400), ["INFANTRY"]),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "morkanaut"}
	var begin_result = phase.execute_action(begin)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	# Move from y=200 to y=590 (390 px = 9.75", within 10" move)
	# Path crosses enemy infantry base (lateral overlap due to 170mm base width)
	# At dest (600,590), distance to enemy (700,400) = ~214 px > 199 px (ER+bases), no ER violation
	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "morkanaut",
		"payload": {
			"model_id": "morkanaut_m1",
			"dest": [600.0, 590.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Morkanaut with Clankin' Forward should cross enemy Infantry")

# ==========================================
# Clankin' Forward: Still blocked by enemy MONSTER
# ==========================================

func test_clankin_forward_blocked_by_enemy_monster():
	"""Morkanaut with Clankin' Forward should still be blocked by enemy MONSTER models"""
	# 170mm base (134 px) + 80mm base (63 px): combined radii ≈ 197 px
	# Path from (600,200) to (600,550) crosses enemy monster at (700,400)
	# At y=400, morkanaut base extends to x=734, enemy at x=700 extends to x=763 → overlap
	var units = {
		"morkanaut": _create_morkanaut("morkanaut", 1, Vector2(600, 200)),
		"enemy_monster": _create_unit("enemy_monster", 2, Vector2(700, 400), ["MONSTER"], 80),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "morkanaut"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "morkanaut",
		"payload": {
			"model_id": "morkanaut_m1",
			"dest": [600.0, 550.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Morkanaut should be blocked by enemy MONSTER")

# ==========================================
# Clankin' Forward: Still blocked by enemy VEHICLE
# ==========================================

func test_clankin_forward_blocked_by_enemy_vehicle():
	"""Morkanaut with Clankin' Forward should still be blocked by enemy VEHICLE models"""
	# 170mm base (134 px) + 80mm base (63 px): combined radii ≈ 197 px
	# Path from (600,200) to (600,550) crosses enemy vehicle at (700,400)
	var units = {
		"morkanaut": _create_morkanaut("morkanaut", 1, Vector2(600, 200)),
		"enemy_vehicle": _create_unit("enemy_vehicle", 2, Vector2(700, 400), ["VEHICLE"], 80),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "morkanaut"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "morkanaut",
		"payload": {
			"model_id": "morkanaut_m1",
			"dest": [600.0, 550.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Morkanaut should be blocked by enemy VEHICLE")

# ==========================================
# Clankin' Forward: Terrain ≤4" is passable
# ==========================================

func test_clankin_forward_can_cross_low_terrain():
	"""Morkanaut with Clankin' Forward should move through low (1.5\") impassable terrain"""
	# Create impassable terrain at the destination with low height
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
		"morkanaut": _create_morkanaut("morkanaut", 1, Vector2(400, 300)),
	}
	var state = _create_state(units, terrain)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "morkanaut"}
	phase.execute_action(begin)

	# Move into the low terrain area
	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "morkanaut",
		"payload": {
			"model_id": "morkanaut_m1",
			"dest": [400.0, 500.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Morkanaut should pass through low (≤4\") impassable terrain")

func test_clankin_forward_can_cross_medium_terrain():
	"""Morkanaut with Clankin' Forward should move through medium (3.5\") impassable terrain"""
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
		"morkanaut": _create_morkanaut("morkanaut", 1, Vector2(400, 300)),
	}
	var state = _create_state(units, terrain)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "morkanaut"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "morkanaut",
		"payload": {
			"model_id": "morkanaut_m1",
			"dest": [400.0, 500.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_true(result.get("valid", false), "Morkanaut should pass through medium (≤4\") impassable terrain")

# ==========================================
# Clankin' Forward: Terrain >4" blocks movement
# ==========================================

func test_clankin_forward_blocked_by_tall_terrain():
	"""Morkanaut with Clankin' Forward should be blocked by tall (6\") impassable terrain"""
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
		"morkanaut": _create_morkanaut("morkanaut", 1, Vector2(400, 300)),
	}
	var state = _create_state(units, terrain)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "morkanaut"}
	phase.execute_action(begin)

	var stage = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "morkanaut",
		"payload": {
			"model_id": "morkanaut_m1",
			"dest": [400.0, 500.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Morkanaut should be blocked by tall (>4\") impassable terrain")

# ==========================================
# Units WITHOUT Clankin' Forward: Still blocked by enemy infantry
# ==========================================

func test_normal_unit_still_blocked_by_enemy_infantry():
	"""A unit without Clankin' Forward should still be blocked by enemy models during Normal Move"""
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
	assert_false(result.get("valid", true), "Unit without Clankin' Forward should still be blocked by enemy infantry")

# ==========================================
# Units WITHOUT Clankin' Forward: Still blocked by impassable terrain
# ==========================================

func test_normal_unit_still_blocked_by_low_terrain():
	"""A unit without Clankin' Forward should be blocked by low impassable terrain"""
	var terrain = [
		{
			"type": "impassable",
			"height_category": "low",
			"poly": [
				Vector2(350, 350), Vector2(450, 350),
				Vector2(450, 450), Vector2(350, 450)
			]
		}
	]
	var units = {
		"infantry": _create_unit("infantry", 1, Vector2(400, 200), ["INFANTRY"]),
	}
	var state = _create_state(units, terrain)
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
	assert_false(result.get("valid", true), "Unit without Clankin' Forward should be blocked by low impassable terrain")
