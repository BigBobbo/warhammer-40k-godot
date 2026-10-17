extends "res://addons/gut/test.gd"

# Tests for T3-9: Barricade engagement range (2" instead of 1")
#
# Per 10e rules: When models are on opposite sides of a Barricade terrain feature,
# the engagement range is 2" instead of the standard 1".
#
# EDITION NOTE: 11e has no barricade engagement-range exception. 11e 03.04
# ENGAGEMENT: "A model's engagement range is the area of the battlefield within
# 2" horizontally and 5" vertically of it." — and barricades are simply LIGHT
# terrain (13.04 "Examples: Barricades, low walls, statuary."), whose movement
# rule (13.06) says nothing about engagement range. So the 1" baselines below are
# 10e-only and pinned via _pin_legacy_10e(); the 11e behaviour (2" everywhere) is
# covered by test_11e_engagement_range_is_2_inches_with_or_without_barricade.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   PX_PER_INCH = 40.0

const RulesEngineScript = preload("res://autoloads/RulesEngine.gd")

var measurement: Node
var terrain_manager: Node
var _prev_edition := 11

func before_each():
	_prev_edition = GameConstants.edition
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
	GameConstants.edition = _prev_edition

# Legacy 10e regression: 1" standard engagement range (the baseline the 10e
# barricade 2" exception is contrasted against) — 11e 03.04 replaced it ("A
# model's engagement range is the area of the battlefield within 2" horizontally
# and 5" vertically of it."); 11e coverage:
# test_11e_engagement_range_is_2_inches_with_or_without_barricade (this file),
# tests/test_iss002_game_constants.gd ("edition 11: engagement range 2.0\""),
# tests/test_iss039_engagement_range_11e.gd.
# Called at the top of each test that asserts the 1" baseline; after_each
# restores the harness edition.
func _pin_legacy_10e() -> void:
	GameConstants.edition = 10
	assert_eq(GameConstants.edition, 10, "Legacy 10e 1\" engagement-range regression must run at edition 10")

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

## Add a barricade terrain piece at the given position.
## Position and size are in pixels.
func _add_barricade(id: String, position: Vector2, size: Vector2) -> void:
	var half_size = size * 0.5
	var polygon = PackedVector2Array([
		position + Vector2(-half_size.x, -half_size.y),
		position + Vector2(half_size.x, -half_size.y),
		position + Vector2(half_size.x, half_size.y),
		position + Vector2(-half_size.x, half_size.y)
	])
	terrain_manager.terrain_features.append({
		"id": id,
		"type": "barricade",
		"polygon": polygon,
		"height_category": "low",
		"position": position,
		"size": size,
		"rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}
	})

## Add a ruins terrain piece (not a barricade) for comparison tests.
func _add_ruins(id: String, position: Vector2, size: Vector2) -> void:
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

# ==========================================
# TerrainManager.is_barricade_between tests
# ==========================================

func test_barricade_between_two_positions():
	"""A barricade between two positions should be detected"""
	# Place barricade at x=200, thin barrier
	_add_barricade("barricade_1", Vector2(200, 0), Vector2(10, 200))

	var pos1 = Vector2(100, 0)  # Left of barricade
	var pos2 = Vector2(300, 0)  # Right of barricade

	assert_true(
		terrain_manager.is_barricade_between(pos1, pos2),
		"Should detect barricade between two positions"
	)

func test_no_barricade_between_positions():
	"""No barricade between positions when path doesn't cross one"""
	_add_barricade("barricade_1", Vector2(200, 200), Vector2(10, 100))

	var pos1 = Vector2(100, 0)  # Above the barricade
	var pos2 = Vector2(300, 0)  # Above the barricade

	assert_false(
		terrain_manager.is_barricade_between(pos1, pos2),
		"Should not detect barricade when path doesn't cross one"
	)

func test_ruins_not_detected_as_barricade():
	"""Ruins terrain should not trigger barricade detection"""
	_add_ruins("ruins_1", Vector2(200, 0), Vector2(100, 100))

	var pos1 = Vector2(100, 0)  # Left of ruins
	var pos2 = Vector2(300, 0)  # Right of ruins

	assert_false(
		terrain_manager.is_barricade_between(pos1, pos2),
		"Ruins should not be detected as a barricade"
	)

# ==========================================
# TerrainManager.get_engagement_range_for_positions tests
# ==========================================

func test_engagement_range_through_barricade_is_2_inches():
	"""Engagement range through a barricade should be 2 inches"""
	_add_barricade("barricade_1", Vector2(200, 0), Vector2(10, 200))

	var pos1 = Vector2(100, 0)
	var pos2 = Vector2(300, 0)

	var er = terrain_manager.get_engagement_range_for_positions(pos1, pos2)
	assert_eq(er, 2.0, "Engagement range through barricade should be 2\"")

func test_engagement_range_without_barricade_is_1_inch():
	"""Standard engagement range without barricade should be 1 inch"""
	# Legacy 10e regression (see _pin_legacy_10e): 11e 03.04 engagement range is 2".
	_pin_legacy_10e()
	var pos1 = Vector2(100, 0)
	var pos2 = Vector2(300, 0)

	var er = terrain_manager.get_engagement_range_for_positions(pos1, pos2)
	assert_eq(er, 1.0, "Standard engagement range should be 1\"")

func test_engagement_range_through_ruins_is_1_inch():
	"""Engagement range through ruins (not a barricade) should still be 1 inch"""
	# Legacy 10e regression (see _pin_legacy_10e): 11e 03.04 engagement range is 2".
	_pin_legacy_10e()
	_add_ruins("ruins_1", Vector2(200, 0), Vector2(100, 100))

	var pos1 = Vector2(100, 0)
	var pos2 = Vector2(300, 0)

	var er = terrain_manager.get_engagement_range_for_positions(pos1, pos2)
	assert_eq(er, 1.0, "Engagement range through ruins should be 1\" (not a barricade)")

# ==========================================
# RulesEngine: Barricade-aware engagement range (static)
# ==========================================

func test_rules_engine_effective_er_with_barricade():
	"""RulesEngine static helper should return 2\" through barricade"""
	_add_barricade("barricade_1", Vector2(200, 0), Vector2(10, 200))

	var board = _make_board({})
	var er = RulesEngineScript._get_effective_engagement_range_rules(
		Vector2(100, 0), Vector2(300, 0), board
	)
	assert_eq(er, 2.0, "RulesEngine should detect barricade and return 2\" ER")

func test_rules_engine_effective_er_without_barricade():
	"""RulesEngine static helper should return 1\" without barricade"""
	# Legacy 10e regression (see _pin_legacy_10e): 11e 03.04 engagement range is 2".
	_pin_legacy_10e()
	var board = _make_board({})
	var er = RulesEngineScript._get_effective_engagement_range_rules(
		Vector2(100, 0), Vector2(300, 0), board
	)
	assert_eq(er, 1.0, "RulesEngine should return 1\" ER without barricade")

# ==========================================
# Charge validation: barricade ER applied to charge targets
# ==========================================

func test_charge_valid_within_2_inches_of_target_through_barricade():
	"""Charge should succeed when model ends within 2\" of target through a barricade"""
	var px_per_inch = 40.0
	var base_radius_px = 32.0 / 25.4 * px_per_inch / 2.0  # ~25.2 px

	# Geometry:
	# - Target at x=400, charger starts at x=0
	# - Barricade at x=300 (between final charger position and target)
	# - Charger ends at x=340 which is ~1.5" edge-to-edge from target
	#   (center-to-center = 400-340 = 60px = 1.5", minus 2 * base_radius = ~50.4px -> e2e = 60-50.4 = 9.6px = 0.24")
	# Actually let me compute more carefully:
	# For 1.5" edge-to-edge: center_to_center = 1.5" * 40 + 2 * 25.2 = 60 + 50.4 = 110.4px
	# So target at x=400, charger final at x = 400 - 110.4 = 289.6
	# Barricade needs to be between 289.6 and 400 => place at x=345

	var target_x = 400.0
	var final_edge_to_edge_inches = 1.5  # Within 2" but outside 1"
	var final_c2c_px = final_edge_to_edge_inches * px_per_inch + 2.0 * base_radius_px
	var charger_final_x = target_x - final_c2c_px

	# Place barricade between charger final position and target
	var barricade_x = (charger_final_x + target_x) / 2.0
	_add_barricade("barricade_1", Vector2(barricade_x, 0), Vector2(10, 200))

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(1, [charger]),
		"target_unit": _make_unit(2, [target])
	})

	var per_model_paths = {
		"marine_1": [[0, 0], [charger_final_x, 0]]
	}

	var result = RulesEngineScript.validate_charge_paths(
		"charger_unit", ["target_unit"], 12, per_model_paths, board
	)

	# Should succeed because barricade makes ER = 2", and model is within 2" of target (1.5" e2e)
	# Note: base-to-base enforcement may trigger if b2b is reachable, but the ER check should pass
	var er_errors_only = []
	for reason in result.reasons:
		if "engagement range" in reason.to_lower():
			er_errors_only.append(reason)
	assert_eq(er_errors_only.size(), 0, "No engagement range errors: within 2\" ER through barricade. ER errors: %s" % str(er_errors_only))

func test_charge_fails_beyond_2_inches_through_barricade():
	"""Charge should fail when model ends beyond 2\" of target even through barricade"""
	var px_per_inch = 40.0
	var base_radius_px = 32.0 / 25.4 * px_per_inch / 2.0

	var target_x = 600.0
	var final_edge_to_edge_inches = 2.5  # Beyond even barricade ER
	var final_c2c_px = final_edge_to_edge_inches * px_per_inch + 2.0 * base_radius_px
	var charger_final_x = target_x - final_c2c_px

	# Place barricade between charger final position and target
	var barricade_x = (charger_final_x + target_x) / 2.0
	_add_barricade("barricade_1", Vector2(barricade_x, 0), Vector2(10, 200))

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(1, [charger]),
		"target_unit": _make_unit(2, [target])
	})

	var per_model_paths = {
		"marine_1": [[0, 0], [charger_final_x, 0]]
	}

	var result = RulesEngineScript.validate_charge_paths(
		"charger_unit", ["target_unit"], 12, per_model_paths, board
	)

	# Should fail: even with 2" ER through barricade, 2.5" is too far
	assert_false(result.valid, "Charge should fail: beyond 2\" ER even through barricade")

func test_charge_without_barricade_requires_1_inch():
	"""Without a barricade, charge requires standard 1\" engagement range"""
	var px_per_inch = 40.0
	var base_radius_px = 32.0 / 25.4 * px_per_inch / 2.0

	# No barricade placed
	var target_x = 400.0
	var final_edge_to_edge_inches = 1.5  # Outside standard 1" ER
	var final_c2c_px = final_edge_to_edge_inches * px_per_inch + 2.0 * base_radius_px
	var charger_final_x = target_x - final_c2c_px

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(1, [charger]),
		"target_unit": _make_unit(2, [target])
	})

	var per_model_paths = {
		"marine_1": [[0, 0], [charger_final_x, 0]]
	}

	var result = RulesEngineScript.validate_charge_paths(
		"charger_unit", ["target_unit"], 12, per_model_paths, board
	)

	# Should fail: 1.5" exceeds standard 1" ER (no barricade)
	# NOT pinned to 10e: the move must still be rejected at 11e, for a different
	# reason. 11e 11.04 CHARGE MOVE, WHILE MOVING: "Each model that can end its move
	# within 1" of one or more charge targets must do so." — this model rolled 12"
	# and needed only ~7.7" to close within 1", yet stopped 1.5" short. At 11e the
	# engine accepts it (RulesEngine.validate_base_to_base_possible_rules uses
	# close_inches = engagement_range_inches() = 2"), a known 11e engine bug.
	assert_false(result.valid, "Charge should fail: 1.5\" exceeds standard 1\" ER without barricade")

# ==========================================
# Constants verification
# ==========================================

func test_terrain_manager_constants():
	"""Verify engagement range constants (ISS-002: centralized in GameConstants)"""
	# Legacy 10e regression (see _pin_legacy_10e): 11e 03.04 engagement range is 2".
	_pin_legacy_10e()
	assert_eq(
		GameConstants.engagement_range_inches(), 1.0,
		"Standard ER should be 1\" at edition 10"
	)
	assert_eq(
		GameConstants.barricade_engagement_range_inches(), 2.0,
		"Barricade ER should be 2\""
	)

# ==========================================
# 11e: no barricade exception — engagement range is 2" everywhere (03.04)
# ==========================================

func test_11e_engagement_range_is_2_inches_with_or_without_barricade():
	"""11e 03.04: "A model's engagement range is the area of the battlefield within
	2\" horizontally and 5\" vertically of it." — barricades are LIGHT terrain
	(13.04) with no engagement-range exception, so every lookup returns 2\"."""
	GameConstants.edition = 11
	assert_eq(GameConstants.edition, 11, "11e engagement-range coverage must run at edition 11")
	assert_eq(GameConstants.engagement_range_inches(), 2.0, "11e 03.04: standard engagement range is 2\"")

	var pos1 = Vector2(100, 0)
	var pos2 = Vector2(300, 0)
	assert_eq(terrain_manager.get_engagement_range_for_positions(pos1, pos2), 2.0,
		"11e: engagement range with no terrain between is 2\"")
	assert_eq(RulesEngineScript._get_effective_engagement_range_rules(pos1, pos2, _make_board({})), 2.0,
		"11e: RulesEngine effective engagement range with no terrain between is 2\"")

	_add_ruins("ruins_1", Vector2(200, 0), Vector2(100, 100))
	assert_eq(terrain_manager.get_engagement_range_for_positions(pos1, pos2), 2.0,
		"11e: engagement range through ruins is 2\"")

	terrain_manager.terrain_features.clear()
	_add_barricade("barricade_1", Vector2(200, 0), Vector2(10, 200))
	assert_eq(terrain_manager.get_engagement_range_for_positions(pos1, pos2), 2.0,
		"11e: engagement range through a barricade is the same 2\" (no extension)")
