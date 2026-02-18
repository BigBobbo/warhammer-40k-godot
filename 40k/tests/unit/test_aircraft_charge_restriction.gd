extends "res://addons/gut/test.gd"

# Tests for T2-9: AIRCRAFT restriction in charge phase
#
# 10e rules:
#   - AIRCRAFT units cannot declare charges
#   - Only units with FLY keyword can declare charges against AIRCRAFT targets
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   PX_PER_INCH = 40.0

const RulesEngineScript = preload("res://autoloads/RulesEngine.gd")

var measurement: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	measurement = AutoloadHelper.get_measurement()
	assert_not_null(measurement, "Measurement autoload must be available")

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

func _make_unit(owner: int, models: Array, keywords: Array = [], status: int = 2) -> Dictionary:
	return {
		"owner": owner,
		"status": status,
		"flags": {},
		"models": models,
		"meta": {
			"name": "Test Unit (owner %d)" % owner,
			"keywords": keywords,
		}
	}

func _make_board(units: Dictionary) -> Dictionary:
	return {"units": units}

# ==========================================
# RulesEngine.eligible_to_charge — AIRCRAFT cannot charge
# ==========================================

## AIRCRAFT unit should NOT be eligible to charge
func test_aircraft_unit_cannot_charge():
	var aircraft_model = _make_model("m1", 0.0, 200.0)
	var board = _make_board({
		"aircraft1": _make_unit(1, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
		"enemy1": _make_unit(2, [_make_model("em1", 400.0, 200.0)]),
	})

	var result = RulesEngineScript.eligible_to_charge("aircraft1", board)
	assert_false(result, "AIRCRAFT units should not be eligible to charge")

## Non-AIRCRAFT unit should be eligible to charge
func test_non_aircraft_unit_can_charge():
	var infantry_model = _make_model("m1", 0.0, 200.0)
	var board = _make_board({
		"infantry1": _make_unit(1, [infantry_model], ["INFANTRY"]),
		"enemy1": _make_unit(2, [_make_model("em1", 400.0, 200.0)]),
	})

	var result = RulesEngineScript.eligible_to_charge("infantry1", board)
	assert_true(result, "Non-AIRCRAFT units should be eligible to charge")

## FLY unit without AIRCRAFT should be eligible to charge
func test_fly_unit_without_aircraft_can_charge():
	var fly_model = _make_model("m1", 0.0, 200.0)
	var board = _make_board({
		"fly1": _make_unit(1, [fly_model], ["FLY", "JUMP PACK", "INFANTRY"]),
		"enemy1": _make_unit(2, [_make_model("em1", 400.0, 200.0)]),
	})

	var result = RulesEngineScript.eligible_to_charge("fly1", board)
	assert_true(result, "FLY units (without AIRCRAFT) should be eligible to charge")

# ==========================================
# RulesEngine.charge_targets_within_12 — only FLY can target AIRCRAFT
# ==========================================

## Non-FLY unit should NOT see AIRCRAFT targets
func test_non_fly_unit_cannot_target_aircraft():
	# Place units close together (within 12")
	var charger_model = _make_model("m1", 0.0, 200.0)
	var aircraft_model = _make_model("am1", 200.0, 200.0)  # 5" away

	var board = _make_board({
		"charger1": _make_unit(1, [charger_model], ["INFANTRY"]),
		"aircraft_enemy": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var targets = RulesEngineScript.charge_targets_within_12("charger1", board)
	assert_false(targets.has("aircraft_enemy"), "Non-FLY unit should not see AIRCRAFT as charge target")

## FLY unit SHOULD see AIRCRAFT targets
func test_fly_unit_can_target_aircraft():
	# Place units close together (within 12")
	var charger_model = _make_model("m1", 0.0, 200.0)
	var aircraft_model = _make_model("am1", 200.0, 200.0)  # 5" away

	var board = _make_board({
		"charger1": _make_unit(1, [charger_model], ["FLY", "JUMP PACK", "INFANTRY"]),
		"aircraft_enemy": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var targets = RulesEngineScript.charge_targets_within_12("charger1", board)
	assert_true(targets.has("aircraft_enemy"), "FLY unit should see AIRCRAFT as charge target")

## Non-FLY unit should still see non-AIRCRAFT targets
func test_non_fly_unit_can_target_non_aircraft():
	var charger_model = _make_model("m1", 0.0, 200.0)
	var enemy_model = _make_model("em1", 200.0, 200.0)  # 5" away

	var board = _make_board({
		"charger1": _make_unit(1, [charger_model], ["INFANTRY"]),
		"enemy1": _make_unit(2, [enemy_model], ["INFANTRY"]),
	})

	var targets = RulesEngineScript.charge_targets_within_12("charger1", board)
	assert_true(targets.has("enemy1"), "Non-FLY unit should still see non-AIRCRAFT targets")

## Mixed targets: non-FLY unit should see infantry but not AIRCRAFT
func test_non_fly_unit_mixed_targets_filters_aircraft():
	var charger_model = _make_model("m1", 0.0, 200.0)
	var infantry_model = _make_model("em1", 200.0, 200.0)  # 5" away
	var aircraft_model = _make_model("am1", 200.0, 250.0)  # ~5" away

	var board = _make_board({
		"charger1": _make_unit(1, [charger_model], ["INFANTRY"]),
		"enemy_infantry": _make_unit(2, [infantry_model], ["INFANTRY"]),
		"enemy_aircraft": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var targets = RulesEngineScript.charge_targets_within_12("charger1", board)
	assert_true(targets.has("enemy_infantry"), "Should see infantry target")
	assert_false(targets.has("enemy_aircraft"), "Should NOT see AIRCRAFT target without FLY")
