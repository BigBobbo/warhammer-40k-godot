extends "res://addons/gut/test.gd"

# Tests for T3-16: Difficult terrain / movement penalties
#
# Terrain pieces with the "difficult_ground" trait apply a flat 2" penalty
# to movement distance when a unit's path crosses them.
# FLY units ignore difficult ground entirely.
#
# PX_PER_INCH = 40.0

var terrain_manager: Node

func before_each():
	# Get TerrainManager directly from scene tree root — this test does not
	# require PhaseManager or other autoloads that may fail to compile.
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		terrain_manager = tree.root.get_node_or_null("TerrainManager")
	if terrain_manager == null:
		push_error("TerrainManager autoload not available - cannot run test")
		return
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

## Add a terrain piece with the difficult_ground trait at the given position.
## Position and size are in pixels. Height defaults to low (no climb penalty).
func _add_difficult_ground(id: String, position: Vector2, size: Vector2, height_category: String = "low") -> void:
	var half_size = size * 0.5
	var polygon = PackedVector2Array([
		position + Vector2(-half_size.x, -half_size.y),
		position + Vector2(half_size.x, -half_size.y),
		position + Vector2(half_size.x, half_size.y),
		position + Vector2(-half_size.x, half_size.y)
	])
	terrain_manager.terrain_features.append({
		"id": id,
		"type": "woods",
		"polygon": polygon,
		"height_category": height_category,
		"position": position,
		"size": size,
		"rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": true, "MONSTER": true},
		"traits": ["difficult_ground"]
	})

## Add terrain without difficult_ground trait (normal terrain).
func _add_normal_terrain(id: String, position: Vector2, size: Vector2, height_category: String = "low") -> void:
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
		"height_category": height_category,
		"position": position,
		"size": size,
		"rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false},
		"traits": []
	})

# ==========================================
# Terrain trait helpers
# ==========================================

func test_get_terrain_traits_returns_traits():
	_add_difficult_ground("woods_1", Vector2(200, 0), Vector2(80, 80))
	var terrain = terrain_manager.terrain_features[0]
	var traits = terrain_manager.get_terrain_traits(terrain)
	assert_eq(traits, ["difficult_ground"], "Should return the terrain's traits array")

func test_get_terrain_traits_returns_empty_for_no_traits():
	_add_normal_terrain("ruins_1", Vector2(200, 0), Vector2(80, 80))
	var terrain = terrain_manager.terrain_features[0]
	var traits = terrain_manager.get_terrain_traits(terrain)
	assert_eq(traits, [], "Should return empty array when no traits")

func test_has_terrain_trait_true():
	_add_difficult_ground("woods_1", Vector2(200, 0), Vector2(80, 80))
	var terrain = terrain_manager.terrain_features[0]
	assert_true(terrain_manager.has_terrain_trait(terrain, "difficult_ground"),
		"Should detect difficult_ground trait")

func test_has_terrain_trait_false():
	_add_normal_terrain("ruins_1", Vector2(200, 0), Vector2(80, 80))
	var terrain = terrain_manager.terrain_features[0]
	assert_false(terrain_manager.has_terrain_trait(terrain, "difficult_ground"),
		"Should not detect difficult_ground trait on normal terrain")

func test_has_terrain_trait_missing_traits_key():
	# Terrain piece without a traits key at all
	terrain_manager.terrain_features.append({
		"id": "old_terrain",
		"type": "ruins",
		"polygon": PackedVector2Array([Vector2(0, 0), Vector2(80, 0), Vector2(80, 80), Vector2(0, 80)]),
		"height_category": "low",
		"position": Vector2(40, 40),
		"size": Vector2(80, 80),
	})
	var terrain = terrain_manager.terrain_features[0]
	assert_false(terrain_manager.has_terrain_trait(terrain, "difficult_ground"),
		"Should return false when terrain has no traits key")

# ==========================================
# Movement penalty: difficult ground
# ==========================================

func test_difficult_ground_non_fly_movement_penalty():
	# Non-FLY unit crossing difficult ground (low terrain) gets flat 2" penalty
	_add_difficult_ground("woods_1", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 2.0, "Non-FLY crossing difficult ground should get 2\" penalty")

func test_difficult_ground_fly_no_penalty():
	# FLY units ignore difficult ground entirely
	_add_difficult_ground("woods_1", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(penalty, 0.0, "FLY unit should ignore difficult ground penalty")

func test_difficult_ground_path_misses_no_penalty():
	# Path doesn't cross the terrain — no penalty
	_add_difficult_ground("woods_1", Vector2(200, 200), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # Path goes horizontally, terrain at y=200

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "Path that misses difficult ground should have no penalty")

func test_normal_low_terrain_no_penalty():
	# Normal low terrain without difficult_ground trait has no penalty
	_add_normal_terrain("ruins_1", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "Normal low terrain without difficult_ground trait should have no penalty")

# ==========================================
# Multiple terrain pieces
# ==========================================

func test_multiple_difficult_ground_cumulative():
	# Two difficult ground pieces — penalties should accumulate
	_add_difficult_ground("woods_1", Vector2(150, 0), Vector2(60, 80))
	_add_difficult_ground("woods_2", Vector2(300, 0), Vector2(60, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 4.0, "Two difficult ground pieces should give 4\" total penalty (2\" each)")

func test_multiple_difficult_ground_fly_ignores_all():
	# FLY units ignore all difficult ground penalties
	_add_difficult_ground("woods_1", Vector2(150, 0), Vector2(60, 80))
	_add_difficult_ground("woods_2", Vector2(300, 0), Vector2(60, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(penalty, 0.0, "FLY should ignore all difficult ground penalties")

# ==========================================
# Difficult ground + height penalty combined
# ==========================================

func test_tall_difficult_ground_both_penalties():
	# Tall terrain with difficult_ground: climb penalty (12") + difficult ground (2") = 14"
	_add_difficult_ground("tall_woods", Vector2(200, 0), Vector2(80, 80), "tall")

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 14.0, "Tall difficult ground should give 14\" penalty (12\" climb + 2\" difficult)")

func test_tall_difficult_ground_fly_ignores_all():
	# FLY units ignore both height and difficult ground penalties during movement
	_add_difficult_ground("tall_woods", Vector2(200, 0), Vector2(80, 80), "tall")

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(penalty, 0.0, "FLY should ignore all terrain penalties during movement")

func test_mixed_terrain_types():
	# Mix of normal tall ruins + difficult ground woods
	_add_normal_terrain("ruins_1", Vector2(150, 0), Vector2(60, 80), "tall")
	_add_difficult_ground("woods_1", Vector2(300, 0), Vector2(60, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	# Ruins: tall (6") → climb penalty 12", no difficult ground
	# Woods: low with difficult ground → 2"
	assert_eq(penalty, 14.0, "Mixed terrain should sum both climb and difficult ground penalties")

# ==========================================
# Charge penalty: difficult ground
# ==========================================

func test_difficult_ground_charge_non_fly():
	# Non-FLY charge through difficult ground pays the penalty
	_add_difficult_ground("woods_1", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 2.0, "Non-FLY charge through difficult ground should get 2\" penalty")

func test_difficult_ground_charge_fly_ignores():
	# FLY units ignore difficult ground during charges too
	_add_difficult_ground("woods_1", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, true)
	assert_eq(penalty, 0.0, "FLY unit should ignore difficult ground penalty during charges")

# ==========================================
# DIFFICULT_GROUND_PENALTY_INCHES constant
# ==========================================

func test_difficult_ground_penalty_constant():
	assert_eq(terrain_manager.DIFFICULT_GROUND_PENALTY_INCHES, 2.0,
		"Difficult ground penalty should be 2 inches")
