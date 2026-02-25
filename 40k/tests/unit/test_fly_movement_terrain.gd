extends "res://addons/gut/test.gd"

# Tests for T3-18: FLY units should ignore terrain elevation during movement
#
# 10e rule: When measuring movement distance, terrain features taller than 2"
# require counting vertical distance (climb up + climb down). FLY units ignore
# terrain elevation entirely during movement (penalty = 0).
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   PX_PER_INCH = 40.0

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
# calculate_movement_terrain_penalty: basic tests
# ==========================================

func test_no_terrain_no_movement_penalty():
	# No terrain features, movement should have zero penalty
	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # 10" horizontal move
	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "No terrain should mean zero movement penalty")

func test_fly_always_zero_movement_penalty():
	# FLY unit should always have zero terrain penalty during movement
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(fly_penalty, 0.0, "FLY unit should have zero terrain penalty during movement")

func test_non_fly_tall_terrain_movement_penalty():
	# Non-FLY unit crossing tall terrain (6") pays climb up + down = 12"
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 12.0, "Non-FLY tall terrain movement penalty should be 12\" (6\" * 2)")

func test_low_terrain_no_movement_penalty():
	# Low terrain (<=2") has no penalty for anyone
	_add_low_terrain("low_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var non_fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	var fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(non_fly_penalty, 0.0, "Low terrain should have no movement penalty for non-FLY")
	assert_eq(fly_penalty, 0.0, "Low terrain should have no movement penalty for FLY")

func test_medium_terrain_non_fly_movement_penalty():
	# Medium terrain (3.5" high > 2") penalizes non-FLY
	_add_medium_terrain("medium_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 7.0, "Medium terrain (3.5\") non-FLY movement penalty should be 7.0\"")

func test_medium_terrain_fly_no_movement_penalty():
	# Medium terrain has no penalty for FLY during movement
	_add_medium_terrain("medium_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(penalty, 0.0, "FLY unit should have zero terrain penalty during movement")

# ==========================================
# Multiple terrain pieces
# ==========================================

func test_multiple_tall_terrain_non_fly_cumulative():
	# Two tall terrain pieces — penalties should accumulate
	_add_tall_terrain("ruins_1", Vector2(150, 0), Vector2(60, 80))
	_add_tall_terrain("ruins_2", Vector2(300, 0), Vector2(60, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 24.0, "Two tall terrain pieces should give 24\" total penalty (12\" each)")

func test_multiple_terrain_fly_always_zero():
	# FLY units ignore all terrain elevation
	_add_tall_terrain("ruins_1", Vector2(150, 0), Vector2(60, 80))
	_add_tall_terrain("ruins_2", Vector2(300, 0), Vector2(60, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(penalty, 0.0, "FLY should ignore all terrain elevation during movement")

# ==========================================
# Path does not cross terrain: no penalty
# ==========================================

func test_path_misses_terrain_no_penalty():
	# Terrain is to the side of the movement path
	_add_tall_terrain("tall_ruins", Vector2(200, 200), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)  # Path goes horizontally, terrain is at y=200

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "Path that misses terrain should have no penalty")

# ==========================================
# Verify FLY vs non-FLY difference in movement
# ==========================================

func test_fly_vs_non_fly_movement_difference():
	# With tall terrain, FLY units should have 0 penalty while non-FLY gets 12"
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var non_fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	var fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)

	assert_gt(non_fly_penalty, 0.0, "Non-FLY should have positive movement penalty for tall terrain")
	assert_eq(fly_penalty, 0.0, "FLY should have zero movement penalty")
	assert_gt(non_fly_penalty, fly_penalty, "Non-FLY penalty should be greater than FLY penalty")

# ==========================================
# Charge vs Movement: FLY behavior differs
# ==========================================

func test_fly_charge_penalty_vs_movement_penalty():
	# During charges, FLY units get a reduced diagonal penalty
	# During movement, FLY units get ZERO penalty (ignore elevation entirely)
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var charge_fly_penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, true)
	var movement_fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)

	assert_gt(charge_fly_penalty, 0.0, "FLY charge penalty should be positive (diagonal)")
	assert_eq(movement_fly_penalty, 0.0, "FLY movement penalty should be zero (ignore elevation)")

# ==========================================
# Moving onto / off terrain: partial climb penalty
# ==========================================

func test_moving_onto_tall_terrain_half_penalty():
	# Moving from outside to inside tall terrain should only pay climb UP = height * 1
	# Terrain centered at (200, 0) with size (80, 80) → polygon from (160, -40) to (240, 40)
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)       # Outside terrain
	var to_pos = Vector2(200, 0)       # Inside terrain (center)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 6.0, "Moving onto tall terrain should only pay climb up = 6\" (not 12\")")

func test_moving_off_tall_terrain_half_penalty():
	# Moving from inside to outside tall terrain should only pay climb DOWN = height * 1
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(200, 0)     # Inside terrain (center)
	var to_pos = Vector2(400, 0)       # Outside terrain

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 6.0, "Moving off tall terrain should only pay climb down = 6\" (not 12\")")

func test_moving_through_tall_terrain_full_penalty():
	# Moving through tall terrain (both endpoints outside) should pay full climb up + down
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)       # Outside terrain
	var to_pos = Vector2(400, 0)       # Outside terrain

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 12.0, "Moving through tall terrain should pay full climb up + down = 12\"")

func test_moving_onto_medium_terrain_half_penalty():
	# Moving onto medium terrain (3.5") should pay climb up = 3.5"
	_add_medium_terrain("medium_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)       # Outside terrain
	var to_pos = Vector2(200, 0)       # Inside terrain (center)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 3.5, "Moving onto medium terrain should only pay climb up = 3.5\" (not 7\")")
