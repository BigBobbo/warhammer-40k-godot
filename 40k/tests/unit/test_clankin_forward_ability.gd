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
#   Engagement range = 2" = 80 px at 11e (1" = 40 px at 10e)
#
# 11e migration (harness default edition 11): 11e 03.04 "A model's engagement
# range is the area of the battlefield within 2" horizontally and 5"
# vertically of it"; 09.05 NORMAL MOVE "ELIGIBLE IF: Your unit is on the
# battlefield and unengaged." / "AFTER MOVING: Your unit must be unengaged."
# The enemy-infantry crossing test and the no-ability infantry test were laid
# out for the 10e 1" range and started engaged at 11e; their geometry now
# keeps >2" edge-to-edge at start and destination (see each test).
# 11e basis for the model-crossing checks: core 17.01 "Each time you make a
# normal or advance move with a unit, MONSTER/VEHICLE models in that unit can
# be moved through friendly and enemy models (excluding other MONSTER/VEHICLE
# models)" and 03.01 "Its base cannot be moved through enemy models". The 11e
# datasheet text of Clankin' Forward is NOT available locally
# (40k/data/40kdc/abilities.json "clankin-forward" carries only
# {"passthrough": ["all-terrain"]}; scripts/40kdc/curated/orks_codex_11e.json
# has no datasheet abilities), so the ability wording above is the 10e text.
#
# Terrain isolation: TerrainManager loads the default layout
# (take_and_hold_mirror_1) at startup; its area-medium-7 / corner-short-10
# pieces added difficult-ground + climb penalties (up to 8") that blew the 10"
# cap at BOTH editions. These tests only passed in a full-suite run because an
# earlier test happened to clear terrain_features. before_each now saves and
# clears the features and after_each restores them. The terrain sections
# therefore exercise only the legacy board.terrain "impassable" endpoint
# check (runs at both editions); the 11e 13.06 dense-terrain gate with the
# 4" step-over granted to Clankin'/Stompin' Forward
# (MovementPhase._terrain_rule_keywords) is covered for the Stompa by
# tests/test_solid_terrain_movement_11e.gd T1/T7 — no Morkanaut-specific 11e
# 13.06 test exists (gap).

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
	# 170mm base radius ≈ 134 px, 32mm base radius ≈ 25 px → combined 159.1 px
	# Enemy offset laterally so path crosses its base but destination doesn't overlap.
	# At y=395, morkanaut base (radius 134) at x=600 extends to x=734 — overlaps enemy at x=745
	# (lateral 145 < 159.1).
	# 11e migration: enemy moved (700,400) -> (745,395). With the old spot the
	# start gap was 1.61" and the destination gap 1.39" — both inside the 11e
	# 2" engagement range (03.04), so 09.05 refused BEGIN_NORMAL_MOVE ("unit is
	# engaged") and the destination would also fail "AFTER MOVING: Your unit
	# must be unengaged". Now start/dest → enemy = sqrt(145²+195²) = 243.0 px,
	# a 2.10" gap (> 239.1 px ER threshold).
	var units = {
		"morkanaut": _create_morkanaut("morkanaut", 1, Vector2(600, 200)),
		"enemy_infantry": _create_unit("enemy_infantry", 2, Vector2(745, 395), ["INFANTRY"]),
	}
	var state = _create_state(units)
	_setup_phase(state)

	var begin = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "morkanaut"}
	var begin_result = phase.execute_action(begin)
	assert_true(begin_result.get("success", false), "BEGIN_NORMAL_MOVE should succeed")

	# Move from y=200 to y=590 (390 px = 9.75", within 10" move)
	# Path crosses enemy infantry base (lateral overlap due to 170mm base width)
	# At dest (600,590), distance to enemy (745,395) = 243.0 px > 239.1 px (2" ER + bases), no ER violation
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
	# NOTE (2026-10-17 triage, not changed): start → enemy = 223.6 px vs 196.9 px
	# combined radii = 0.67" gap, inside engagement range at BOTH editions (1"
	# and 2"), so BEGIN_NORMAL_MOVE is refused and this assert_false (and the
	# VEHICLE twin below) passes vacuously via "No active move". With M10 a
	# straight path that overlaps an 80mm base and starts/ends >2" away needs
	# ≥9.7", so a non-vacuous 11e layout needs a geometry/M rework.
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
