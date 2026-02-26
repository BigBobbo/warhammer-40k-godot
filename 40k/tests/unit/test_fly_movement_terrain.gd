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

func test_non_fly_tall_terrain_no_movement_penalty():
	# Units always stay on ground floor — no height penalty even for tall terrain
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "No height penalty — units always stay on ground floor")

func test_low_terrain_no_movement_penalty():
	# Low terrain (<=2") has no penalty for anyone
	_add_low_terrain("low_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var non_fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	var fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)
	assert_eq(non_fly_penalty, 0.0, "Low terrain should have no movement penalty for non-FLY")
	assert_eq(fly_penalty, 0.0, "Low terrain should have no movement penalty for FLY")

func test_medium_terrain_non_fly_no_movement_penalty():
	# Units always stay on ground floor — no height penalty even for medium terrain
	_add_medium_terrain("medium_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "No height penalty — units always stay on ground floor")

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

func test_multiple_tall_terrain_non_fly_no_penalty():
	# Units always stay on ground floor — no height penalty even with multiple terrain
	_add_tall_terrain("ruins_1", Vector2(150, 0), Vector2(60, 80))
	_add_tall_terrain("ruins_2", Vector2(300, 0), Vector2(60, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	assert_eq(penalty, 0.0, "No height penalty — units always stay on ground floor")

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

func test_fly_vs_non_fly_movement_both_zero():
	# With ground floor assumption, both FLY and non-FLY have zero height penalty
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var non_fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false)
	var fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)

	assert_eq(non_fly_penalty, 0.0, "No height penalty — units always stay on ground floor")
	assert_eq(fly_penalty, 0.0, "FLY should have zero movement penalty")

# ==========================================
# Charge vs Movement: FLY behavior differs
# ==========================================

func test_fly_charge_and_movement_both_zero():
	# With ground floor assumption, no height penalty for either charge or movement
	_add_tall_terrain("tall_ruins", Vector2(200, 0), Vector2(80, 80))

	var from_pos = Vector2(0, 0)
	var to_pos = Vector2(400, 0)

	var charge_fly_penalty = terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, true)
	var movement_fly_penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, true)

	assert_eq(charge_fly_penalty, 0.0, "No height penalty — units always stay on ground floor")
	assert_eq(movement_fly_penalty, 0.0, "No height penalty — units always stay on ground floor")
