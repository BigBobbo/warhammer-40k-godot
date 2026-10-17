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
#   Engagement range = 2" = 80 px at 11e (1" = 40 px at 10e)
#
# 11e migration (harness default edition 11): the enemy-model geometry was
# authored for the 10e 1" engagement range. 11e 03.04: "A model's engagement
# range is the area of the battlefield within 2" horizontally and 5"
# vertically of it", and 09.05 NORMAL MOVE: "ELIGIBLE IF: Your unit is on the
# battlefield and unengaged." / "AFTER MOVING: Your unit must be unengaged."
# With the old spacing the Stompa started within 2" of the enemy, so
# BEGIN_NORMAL_MOVE was (correctly) refused with "unit is engaged". Every
# start/destination below now keeps >2" edge-to-edge from the enemy while the
# straight path still overlaps the enemy base, so the same assertions hold at
# both editions.
# Rule basis at 11e for the model-crossing checks: core 17.01 "Each time you
# make a normal or advance move with a unit, MONSTER/VEHICLE models in that
# unit can be moved through friendly and enemy models (excluding other
# MONSTER/VEHICLE models)" (covers the INFANTRY case), core 03.01 "Its base
# cannot be moved through enemy models" (TITANIC case), and core 24.35
# SUPER-HEAVY WALKER "can move through models (including MONSTER/VEHICLE
# models, but excluding TITANIC models)". The 11e datasheet text of Stompin'
# Forward itself is NOT available locally: 40k/data/40kdc/abilities.json
# "stompin-forward" carries only {"passthrough": ["all-terrain"]} and
# scripts/40kdc/curated/orks_codex_11e.json has no datasheet abilities, so the
# MONSTER/VEHICLE cases still encode the 10e ability text quoted above.
#
# Terrain isolation: TerrainManager loads the default layout
# (take_and_hold_mirror_1, 44 pieces) at startup. Without clearing it these
# tests hit real layout terrain (difficult-ground/climb penalties at both
# editions; the 11e 13.06 dense gate refuses the 5" ruin
# corner-ruin-right-6), and they only passed in a full-suite run because an
# earlier test happened to clear terrain_features. before_each now saves and
# clears the features and after_each restores them. The terrain sections
# below therefore exercise only the legacy board.terrain "impassable"
# endpoint check (which runs at both editions); the 11e 13.06 dense-terrain
# gate with the Stompin' Forward 4" step-over is covered by
# tests/test_solid_terrain_movement_11e.gd (T1: 5" wall blocks the Stompa,
# T7: Stompa crosses a 3" dense generator, plain VEHICLE does not).

const MovementPhaseScript = preload("res://phases/MovementPhase.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

var phase: Node
var game_state_node: Node
var terrain_manager: Node
var _saved_terrain_features: Array = []

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state_node = AutoloadHelper.get_game_state()
	assert_not_null(game_state_node, "GameState autoload must be available")
	# Isolate from the default terrain layout (see header): save + clear.
	terrain_manager = AutoloadHelper.get_terrain_manager()
	assert_not_null(terrain_manager, "TerrainManager autoload must be available")
	if terrain_manager:
		_saved_terrain_features = terrain_manager.terrain_features.duplicate(true)
		terrain_manager.terrain_features.clear()

func after_each():
	if phase:
		phase.queue_free()
		phase = null
	if terrain_manager:
		terrain_manager.terrain_features = _saved_terrain_features
		_saved_terrain_features = []

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
	# Stompa (200mm, 157.5px radius) at (800,200), enemy infantry (32mm, 25.2px) at (930,440)
	# Combined radii = 182.7px. ER threshold = 262.7px at 11e (2", 03.04); 222.7px at 10e (1").
	# At y=440: lateral = 130px < 182.7 → bases overlap ✓
	# Start to enemy: sqrt(130²+240²) = 272.9 > 262.7 → not engaged (2.26" gap) ✓
	# Dest (800,680) to enemy: sqrt(130²+240²) = 272.9 > 262.7 → not engaged ✓
	# Move distance: 480px / 40 = 12" = max move ✓
	# 11e migration: enemy moved (930,400) -> (930,440). At (930,400) the start
	# gap was 1.39" — engaged under the 11e 2" engagement range, so 09.05
	# refused the Normal Move ("ELIGIBLE IF: ... unengaged").
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(800, 200)),
		"enemy_infantry": _create_unit("enemy_infantry", 2, Vector2(930, 440), ["INFANTRY"]),
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
	# Stompa (200mm, 157.5px) at (800,200), enemy MONSTER (80mm, 63px) at (1010,440)
	# Combined = 220.5px. ER threshold = 300.5px at 11e (2", 03.04); 260.5px at 10e.
	# At y=440: lateral = 210px < 220.5 → bases overlap ✓
	# Start to enemy: sqrt(210²+240²) = 318.9 > 300.5 → not engaged (2.46" gap) ✓
	# Dest (800,680) to enemy: sqrt(210²+240²) = 318.9 > 300.5 ✓
	# 11e migration: enemy moved (1010,400) -> (1010,440); at y=400 the start
	# gap was 1.74" — engaged under 11e 03.04, so 09.05 refused the move.
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(800, 200)),
		"enemy_monster": _create_unit("enemy_monster", 2, Vector2(1010, 440), ["MONSTER"], 80),
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
	# Same geometry as MONSTER test (11e-migrated: enemy at (1010,440), see there)
	var units = {
		"stompa": _create_stompa("stompa", 1, Vector2(800, 200)),
		"enemy_vehicle": _create_unit("enemy_vehicle", 2, Vector2(1010, 440), ["VEHICLE"], 80),
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
	# Stompa (200mm, 157.5px) at (800,200), enemy TITANIC (170mm, 134px) at (1070,480)
	# Combined = 291.3px. ER threshold = 371.3px at 11e (2", 03.04); 331.3px at 10e.
	# At y=480: lateral = 270px < 291.3 → bases overlap ✓
	# Start to enemy: sqrt(270²+280²) = 389.0 > 371.3 → not engaged (2.44" gap) ✓
	# Dest (800,760) to enemy: sqrt(270²+280²) = 389.0 > 371.3 ✓
	# Move distance: 560px / 40 = 14" → Stompa given M14 for this test only.
	# 11e migration: the 10e layout (enemy (1080,400), dest (800,680), M12)
	# started the Stompa 1.32" from the TITANIC — engaged under 11e 03.04, so
	# 09.05 refused BEGIN_NORMAL_MOVE and the assert_false below only passed
	# vacuously ("No active move"). A straight path that overlaps a 170mm base
	# and starts/ends >2" from it needs >11.5", hence M14 here; the asserted
	# outcome is unchanged. 11e basis for "blocked": 03.01 "Its base cannot be
	# moved through enemy models"; 17.01 excludes other MONSTER/VEHICLE models;
	# 24.35 excludes TITANIC models.
	var stompa_unit = _create_stompa("stompa", 1, Vector2(800, 200))
	stompa_unit["meta"]["stats"]["move"] = 14
	var units = {
		"stompa": stompa_unit,
		"enemy_titanic": _create_unit("enemy_titanic", 2, Vector2(1070, 480), ["VEHICLE", "TITANIC"], 170),
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
			"dest": [800.0, 760.0],
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
	# 11e migration: enemy (400,300) -> (400,340) and dest (400,400) -> (400,480).
	# The old 1.24" start gap is engaged under the 11e 2" engagement range
	# (03.04), so BEGIN_NORMAL_MOVE was refused (09.05) and the assert_false
	# below passed only vacuously. Now: start/dest gaps = 140 - 50.4 = 89.6px
	# (2.24") and the 7" straight path runs through the enemy base, so the
	# block comes from 11e 03.01 "Its base cannot be moved through enemy
	# models" (17.01 does not apply — the mover is INFANTRY).
	var units = {
		"infantry": _create_unit("infantry", 1, Vector2(400, 200), ["INFANTRY"]),
		"enemy_infantry": _create_unit("enemy_infantry", 2, Vector2(400, 340), ["INFANTRY"]),
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
			"dest": [400.0, 480.0],
			"rotation": 0.0
		}
	}
	var result = phase.validate_action(stage)
	assert_false(result.get("valid", true), "Unit without Stompin' Forward should still be blocked by enemy infantry")
