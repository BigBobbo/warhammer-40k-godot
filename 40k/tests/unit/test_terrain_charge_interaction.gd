extends "res://addons/gut/test.gd"

# Tests for T2-8: Terrain interaction during charges
#
# 10e rule: Terrain features 2" or less can be moved over freely during charges.
# Terrain taller than 2" requires counting vertical distance (climb up + down)
# against the charge roll. FLY units measure diagonally instead.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   PX_PER_INCH = 40.0

const RulesEngineScript = preload("res://autoloads/RulesEngine.gd")

var measurement: Node
var terrain_manager: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	measurement = AutoloadHelper.get_measurement()
	terrain_manager = AutoloadHelper.get_terrain_manager()
	assert_not_null(measurement, "Measurement autoload must be available")
	assert_not_null(terrain_manager, "TerrainManager autoload must be available")

	# Clear terrain for each test so we can set up specific scenarios
	terrain_manager.terrain_features.clear()

func after_each():
	# Restore default terrain layout after tests
	if terrain_manager:
		terrain_manager.terrain_features.clear()

# ==========================================
# Helpers
# ==========================================

func _make_model(id: String, pos_x: float, pos_y: float, alive: bool = true) -> Dictionary:
	return {
		"id": id,
		"alive": alive,
		"current_wounds": 1,
		"wounds": 1,
		"base_mm": 32,
		"base_type": "circular",
		"position": {"x": pos_x, "y": pos_y}
	}

func _make_unit(owner: int, models: Array, keywords: Array = []) -> Dictionary:
	return {
		"owner": owner,
		"models": models,
		"meta": {
			"name": "Test Unit (owner %d)" % owner,
			"keywords": keywords,
		}
	}

func _make_board(units: Dictionary) -> Dictionary:
	return {"units": units, "terrain_features": terrain_manager.terrain_features}

## Add a tall terrain piece (6" high) at the given position.
## Position and size are in pixels.
func _add_tall_terrain(id: String, position: Vector2, size: Vector2) -> void:
	var half_size = size * 0.5
	var polygon = PackedVector2Array([
		position + Vector2(-half_size.x, -half_size.y),
		position + Vector2(half_size.x, -half_size.y),
		position + Vector2(half_size.x, half_size.y),
		position + Vector2(-half_size.x, half_size.y)
	])
	terrain_manager.terrain_features.append({
		"id": id,
		"type": "ruins",
		"polygon": polygon,
		"height_category": "tall",
		"position": position,
		"size": size,
		"rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}
	})

## Add a low terrain piece (1.5" high) at the given position.
func _add_low_terrain(id: String, position: Vector2, size: Vector2) -> void:
	var half_size = size * 0.5
	var polygon = PackedVector2Array([
		position + Vector2(-half_size.x, -half_size.y),
		position + Vector2(half_size.x, -half_size.y),
		position + Vector2(half_size.x, half_size.y),
		position + Vector2(-half_size.x, half_size.y)
	])
	terrain_manager.terrain_features.append({
		"id": id,
		"type": "ruins",
		"polygon": polygon,
		"height_category": "low",
		"position": position,
		"size": size,
		"rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}
	})

## Add a medium terrain piece (3.5" high) at the given position.
func _add_medium_terrain(id: String, position: Vector2, size: Vector2) -> void:
	var half_size = size * 0.5
	var polygon = PackedVector2Array([
		position + Vector2(-half_size.x, -half_size.y),
		position + Vector2(half_size.x, -half_size.y),
		position + Vector2(half_size.x, half_size.y),
		position + Vector2(-half_size.x, half_size.y)
	])
	terrain_manager.terrain_features.append({
		"id": id,
		"type": "ruins",
		"polygon": polygon,
		"height_category": "medium",
		"position": position,
		"size": size,
		"rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}
	})

# ==========================================
# TerrainManager.get_height_inches tests
# ==========================================

func test_height_inches_low():
	var terrain = {"height_category": "low"}
	var height = terrain_manager.get_height_inches(terrain)
	assert_eq(height, 1.5, "LOW terrain should be 1.5 inches")

func test_height_inches_medium():
	var terrain = {"height_category": "medium"}
	var height = terrain_manager.get_height_inches(terrain)
	assert_eq(height, 3.5, "MEDIUM terrain should be 3.5 inches")

func test_height_inches_tall():
	var terrain = {"height_category": "tall"}
	var height = terrain_manager.get_height_inches(terrain)
	assert_eq(height, 6.0, "TALL terrain should be 6.0 inches")

# ==========================================
# Terrain penalty: no terrain = no penalty
# ==========================================

func test_no_terrain_no_penalty():
	# No terrain features, path should have zero penalty
	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # 10" horizontal move
	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "No terrain should mean zero penalty")

# ==========================================
# Low terrain (<=2"): no penalty
# ==========================================

func test_low_terrain_no_penalty():
	# Place low terrain (1.5" high) between charger and target
	# Low terrain is 2" or less, so no penalty
	_add_low_terrain("low_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # Path crosses the low terrain

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "Low terrain (<=2\") should have no charge penalty")

# ==========================================
# Tall terrain (>2"): non-FLY pays full climb penalty
# ==========================================

func test_tall_terrain_non_fly_penalty():
	# Place tall terrain (6" high) between charger and target
	# Non-FLY unit must climb up + down = 6" * 2 = 12" penalty
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # Path crosses the tall terrain

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 12.0, "Tall terrain (6\") non-FLY penalty should be 12\" (climb up + down)")

# ==========================================
# Tall terrain: FLY unit pays diagonal penalty (less than full climb)
# ==========================================

func test_tall_terrain_fly_penalty_less_than_non_fly():
	# Place tall terrain (6" high) between charger and target
	# FLY unit measures diagonally: penalty = sqrt(h^2 + cross^2) - cross
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # Path crosses the tall terrain

	var non_fly_penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	var fly_penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, true)

	assert_gt(non_fly_penalty, 0.0, "Non-FLY should have positive penalty")
	assert_gt(fly_penalty, 0.0, "FLY should have positive penalty")
	assert_lt(fly_penalty, non_fly_penalty, "FLY penalty should be less than non-FLY penalty")

# ==========================================
# Medium terrain (2-5"): penalty applies (>2")
# ==========================================

func test_medium_terrain_has_penalty():
	# Medium terrain is 3.5" high (>2"), so penalty applies
	_add_medium_terrain("medium_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	# Medium = 3.5", non-FLY penalty = 3.5 * 2 = 7.0"
	assert_eq(penalty, 7.0, "Medium terrain (3.5\") non-FLY penalty should be 7.0\" (climb up + down)")

# ==========================================
# Path does NOT cross terrain: no penalty
# ==========================================

func test_path_misses_terrain_no_penalty():
	# Place tall terrain at y=200, but path goes along y=0
	_add_tall_terrain("off_path_ruins", Vector2(200, 200), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # Path goes horizontally, terrain is far away

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "Path that doesn't cross terrain should have no penalty")

# ==========================================
# RulesEngine: validate_charge_paths with terrain penalty
# ==========================================

func test_rules_engine_charge_paths_terrain_penalty():
	# Set up: charger 5" away from target, rolls 7
	# But tall terrain (6" high) is between them
	# Horizontal path = 5", terrain penalty = 12" (non-FLY)
	# Effective distance = 5" + 12" = 17" > rolled 7 = FAIL
	var px_per_inch = 40.0
	var target_x = 5.0 * px_per_inch + 50.4  # 5" edge-to-edge for 32mm bases

	# Place tall terrain between charger and target
	_add_tall_terrain("blocking_ruins", Vector2(target_x / 2.0, 0), Vector2(80, 80))

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(1, [charger]),
		"target_unit": _make_unit(2, [target])
	})

	# Path: straight line from charger to near target
	var move_end_x = target_x - 50.4  # Move to b2b position
	var per_model_paths = {
		"marine_1": [[0, 0], [move_end_x, 0]]
	}

	var result = RulesEngineScript.validate_charge_paths(
		"charger_unit", ["target_unit"], 7, per_model_paths, board
	)

	# The path itself is only ~5" but terrain adds 12" penalty
	# Total effective distance > 7 rolled, so should fail
	assert_false(result.valid, "Should fail: terrain penalty makes effective distance exceed roll")
	assert_true(result.reasons.size() > 0, "Should have error reasons")
	assert_true("terrain" in result.reasons[0].to_lower(), "Error should mention terrain penalty")

# ==========================================
# RulesEngine: FLY unit can charge through terrain more efficiently
# ==========================================

func test_rules_engine_fly_unit_terrain_advantage():
	# Set up: charger 3" away from target, tall terrain between them
	# Non-FLY: 3" path + 12" terrain = 15" effective (needs 15 roll)
	# FLY: 3" path + ~diagonal penalty (much less than 12")
	var px_per_inch = 40.0
	var target_x = 3.0 * px_per_inch + 50.4  # 3" edge-to-edge

	_add_tall_terrain("blocking_ruins", Vector2(target_x / 2.0, 0), Vector2(80, 80))

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	# Board with NON-FLY unit
	var board_no_fly = _make_board({
		"charger_unit": _make_unit(1, [charger], ["INFANTRY"]),
		"target_unit": _make_unit(2, [target])
	})

	# Board with FLY unit
	var board_fly = _make_board({
		"charger_unit": _make_unit(1, [charger], ["INFANTRY", "FLY"]),
		"target_unit": _make_unit(2, [target])
	})

	var move_end_x = target_x - 50.4
	var per_model_paths = {
		"marine_1": [[0, 0], [move_end_x, 0]]
	}

	# Non-FLY should fail with roll of 7 (3" + 12" terrain = 15")
	var result_no_fly = RulesEngineScript.validate_charge_paths(
		"charger_unit", ["target_unit"], 7, per_model_paths, board_no_fly
	)

	# FLY should have lower penalty — check that penalty is calculated differently
	var result_fly = RulesEngineScript.validate_charge_paths(
		"charger_unit", ["target_unit"], 7, per_model_paths, board_fly
	)

	# Non-FLY should definitely fail
	assert_false(result_no_fly.valid, "Non-FLY should fail with terrain penalty exceeding roll")

	# FLY should have less penalty — we can't guarantee it passes with roll 7
	# but it should have fewer/different errors if any
	# The key assertion: FLY terrain penalty is less than non-FLY
	var non_fly_penalty = RulesEngineScript._calculate_charge_terrain_penalty_rules(
		per_model_paths["marine_1"], false, board_no_fly)
	var fly_penalty = RulesEngineScript._calculate_charge_terrain_penalty_rules(
		per_model_paths["marine_1"], true, board_fly)

	assert_gt(non_fly_penalty, 0.0, "Non-FLY should have terrain penalty")
	assert_gt(fly_penalty, 0.0, "FLY should have terrain penalty (diagonal)")
	assert_lt(fly_penalty, non_fly_penalty, "FLY terrain penalty should be less than non-FLY")

# ==========================================
# No terrain in path: charge proceeds normally
# ==========================================

func test_charge_no_terrain_normal_validation():
	# Standard charge with no terrain: 3" away, roll 7 = success
	var px_per_inch = 40.0
	var target_x = 3.0 * px_per_inch + 50.4  # 3" edge-to-edge

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(1, [charger]),
		"target_unit": _make_unit(2, [target])
	})

	var move_end_x = target_x - 50.4  # b2b position
	var per_model_paths = {
		"marine_1": [[0, 0], [move_end_x, 0]]
	}

	var result = RulesEngineScript.validate_charge_paths(
		"charger_unit", ["target_unit"], 7, per_model_paths, board
	)

	assert_true(result.valid, "Should be valid with no terrain and sufficient roll: %s" % str(result.reasons))

# ==========================================
# get_tall_terrain_on_path utility test
# ==========================================

func test_get_tall_terrain_on_path():
	_add_tall_terrain("tall_1", Vector2(200, 0), Vector2(80, 80))
	_add_low_terrain("low_1", Vector2(300, 0), Vector2(80, 80))
	_add_tall_terrain("tall_2", Vector2(400, 200), Vector2(80, 80))  # Off path

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(500, 0)

	var tall_terrain = terrain_manager.get_tall_terrain_on_path(from_pos, to_pos)

	# Should only include tall_1 (on path), not low_1 (not tall) or tall_2 (off path)
	assert_eq(tall_terrain.size(), 1, "Should find exactly 1 tall terrain on path")
	if tall_terrain.size() > 0:
		assert_eq(tall_terrain[0].id, "tall_1", "Should be the tall terrain that's on the path")

# ==========================================
# Multiple terrain pieces on same path
# ==========================================

func test_multiple_terrain_penalties_accumulate():
	# Place two tall terrain pieces between charger and target
	_add_tall_terrain("ruins_a", Vector2(150, 0), Vector2(60, 60))
	_add_tall_terrain("ruins_b", Vector2(350, 0), Vector2(60, 60))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(500, 0)

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)

	# Two tall terrain pieces: 6" * 2 * 2 = 24" total penalty
	assert_eq(penalty, 24.0, "Two tall terrain penalties should accumulate: 12\" + 12\" = 24\"")

# ==========================================
# Moving onto / off terrain during charge: partial climb
# ==========================================

func test_charge_onto_tall_terrain_half_penalty():
	# Charging onto tall terrain should only pay climb up = height * 1
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)       # Outside terrain
	var to_pos = Vector2(200, 0)       # Inside terrain (center)

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 6.0, "Charging onto tall terrain should only pay climb up = 6\" (not 12\")")

func test_charge_off_tall_terrain_half_penalty():
	# Charging from inside terrain to outside should only pay climb down = height * 1
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(200, 0)     # Inside terrain (center)
	var to_pos = Vector2(400, 0)       # Outside terrain

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 6.0, "Charging off tall terrain should only pay climb down = 6\" (not 12\")")
