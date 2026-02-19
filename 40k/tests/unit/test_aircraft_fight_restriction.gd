extends "res://addons/gut/test.gd"

# Tests for T4-4: AIRCRAFT restrictions in fight phase
#
# 10e rules:
#   - Aircraft cannot Pile In or Consolidate
#   - Aircraft can only fight against units that can Fly
#   - Unless a model can Fly, ignore Aircraft when determining the closest
#     enemy model during Pile In or Consolidate
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   PX_PER_INCH = 40.0
#   Engagement range = 1" = 40px (edge-to-edge)

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
# is_eligible_to_fight — Aircraft keyword checks
# ==========================================

## AIRCRAFT unit should NOT be eligible to fight non-FLY enemy
func test_aircraft_not_eligible_to_fight_non_fly():
	# Place aircraft and infantry within engagement range (within 1")
	# 32mm base radius ≈ 25.2px, edge-to-edge at 60px centers ≈ 0.24" apart
	var aircraft_model = _make_model("am1", 100.0, 200.0)
	var infantry_model = _make_model("im1", 160.0, 200.0)

	var board = _make_board({
		"aircraft1": _make_unit(1, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
		"infantry1": _make_unit(2, [infantry_model], ["INFANTRY"]),
	})

	var result = RulesEngineScript.is_eligible_to_fight("aircraft1", board)
	assert_false(result, "AIRCRAFT unit should NOT be eligible to fight non-FLY enemy")

## AIRCRAFT unit SHOULD be eligible to fight FLY enemy
func test_aircraft_eligible_to_fight_fly_enemy():
	var aircraft_model = _make_model("am1", 100.0, 200.0)
	var fly_model = _make_model("fm1", 160.0, 200.0)

	var board = _make_board({
		"aircraft1": _make_unit(1, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
		"fly_enemy": _make_unit(2, [fly_model], ["FLY", "JUMP PACK", "INFANTRY"]),
	})

	var result = RulesEngineScript.is_eligible_to_fight("aircraft1", board)
	assert_true(result, "AIRCRAFT unit should be eligible to fight FLY enemy")

## Non-FLY unit should NOT be eligible to fight when only Aircraft enemies in range
func test_non_fly_not_eligible_when_only_aircraft_in_range():
	var infantry_model = _make_model("im1", 100.0, 200.0)
	var aircraft_model = _make_model("am1", 160.0, 200.0)

	var board = _make_board({
		"infantry1": _make_unit(1, [infantry_model], ["INFANTRY"]),
		"aircraft1": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var result = RulesEngineScript.is_eligible_to_fight("infantry1", board)
	assert_false(result, "Non-FLY unit should NOT be eligible to fight when only AIRCRAFT in range")

## FLY unit SHOULD be eligible to fight Aircraft
func test_fly_unit_eligible_to_fight_aircraft():
	var fly_model = _make_model("fm1", 100.0, 200.0)
	var aircraft_model = _make_model("am1", 160.0, 200.0)

	var board = _make_board({
		"fly_unit": _make_unit(1, [fly_model], ["FLY", "JUMP PACK", "INFANTRY"]),
		"aircraft1": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var result = RulesEngineScript.is_eligible_to_fight("fly_unit", board)
	assert_true(result, "FLY unit SHOULD be eligible to fight AIRCRAFT")

## Normal units should still be eligible to fight each other
func test_normal_units_eligible_to_fight():
	var model1 = _make_model("m1", 100.0, 200.0)
	var model2 = _make_model("m2", 160.0, 200.0)

	var board = _make_board({
		"unit1": _make_unit(1, [model1], ["INFANTRY"]),
		"unit2": _make_unit(2, [model2], ["INFANTRY"]),
	})

	var result = RulesEngineScript.is_eligible_to_fight("unit1", board)
	assert_true(result, "Normal units in engagement range should be eligible to fight")

# ==========================================
# fight_targets_in_engagement — Aircraft filtering
# ==========================================

## AIRCRAFT attacker should NOT see non-FLY targets
func test_aircraft_cannot_target_non_fly():
	var aircraft_model = _make_model("am1", 100.0, 200.0)
	var infantry_model = _make_model("im1", 160.0, 200.0)

	var board = _make_board({
		"aircraft1": _make_unit(1, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
		"infantry1": _make_unit(2, [infantry_model], ["INFANTRY"]),
	})

	var targets = RulesEngineScript.fight_targets_in_engagement("aircraft1", board)
	assert_false(targets.has("infantry1"), "AIRCRAFT should not see non-FLY as melee target")

## AIRCRAFT attacker SHOULD see FLY targets
func test_aircraft_can_target_fly():
	var aircraft_model = _make_model("am1", 100.0, 200.0)
	var fly_model = _make_model("fm1", 160.0, 200.0)

	var board = _make_board({
		"aircraft1": _make_unit(1, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
		"fly_enemy": _make_unit(2, [fly_model], ["FLY", "JUMP PACK", "INFANTRY"]),
	})

	var targets = RulesEngineScript.fight_targets_in_engagement("aircraft1", board)
	assert_true(targets.has("fly_enemy"), "AIRCRAFT should see FLY unit as melee target")

## Non-FLY attacker should NOT see AIRCRAFT targets
func test_non_fly_cannot_target_aircraft():
	var infantry_model = _make_model("im1", 100.0, 200.0)
	var aircraft_model = _make_model("am1", 160.0, 200.0)

	var board = _make_board({
		"infantry1": _make_unit(1, [infantry_model], ["INFANTRY"]),
		"aircraft1": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var targets = RulesEngineScript.fight_targets_in_engagement("infantry1", board)
	assert_false(targets.has("aircraft1"), "Non-FLY unit should not see AIRCRAFT as melee target")

## FLY attacker SHOULD see AIRCRAFT targets
func test_fly_can_target_aircraft():
	var fly_model = _make_model("fm1", 100.0, 200.0)
	var aircraft_model = _make_model("am1", 160.0, 200.0)

	var board = _make_board({
		"fly_unit": _make_unit(1, [fly_model], ["FLY", "JUMP PACK", "INFANTRY"]),
		"aircraft1": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var targets = RulesEngineScript.fight_targets_in_engagement("fly_unit", board)
	assert_true(targets.has("aircraft1"), "FLY unit should see AIRCRAFT as melee target")

## Mixed targets: non-FLY sees infantry but not aircraft
func test_non_fly_mixed_targets_filters_aircraft():
	var infantry_model = _make_model("im1", 100.0, 200.0)
	var enemy_infantry = _make_model("eim1", 160.0, 200.0)
	var aircraft_model = _make_model("am1", 160.0, 240.0)

	var board = _make_board({
		"infantry1": _make_unit(1, [infantry_model], ["INFANTRY"]),
		"enemy_infantry": _make_unit(2, [enemy_infantry], ["INFANTRY"]),
		"enemy_aircraft": _make_unit(2, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var targets = RulesEngineScript.fight_targets_in_engagement("infantry1", board)
	assert_true(targets.has("enemy_infantry"), "Should see infantry target")
	assert_false(targets.has("enemy_aircraft"), "Should NOT see AIRCRAFT target without FLY")

# ==========================================
# can_unit_pile_in — Aircraft cannot Pile In
# ==========================================

## AIRCRAFT unit cannot pile in
func test_aircraft_cannot_pile_in():
	var aircraft_model = _make_model("am1", 100.0, 200.0)
	var board = _make_board({
		"aircraft1": _make_unit(1, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var result = RulesEngineScript.can_unit_pile_in("aircraft1", board)
	assert_false(result, "AIRCRAFT units should not be able to pile in")

## Non-AIRCRAFT unit can pile in
func test_non_aircraft_can_pile_in():
	var infantry_model = _make_model("im1", 100.0, 200.0)
	var board = _make_board({
		"infantry1": _make_unit(1, [infantry_model], ["INFANTRY"]),
	})

	var result = RulesEngineScript.can_unit_pile_in("infantry1", board)
	assert_true(result, "Non-AIRCRAFT units should be able to pile in")

## FLY unit without AIRCRAFT can pile in
func test_fly_without_aircraft_can_pile_in():
	var fly_model = _make_model("fm1", 100.0, 200.0)
	var board = _make_board({
		"fly_unit": _make_unit(1, [fly_model], ["FLY", "JUMP PACK", "INFANTRY"]),
	})

	var result = RulesEngineScript.can_unit_pile_in("fly_unit", board)
	assert_true(result, "FLY units without AIRCRAFT should be able to pile in")

# ==========================================
# can_unit_consolidate — Aircraft cannot Consolidate
# ==========================================

## AIRCRAFT unit cannot consolidate
func test_aircraft_cannot_consolidate():
	var aircraft_model = _make_model("am1", 100.0, 200.0)
	var board = _make_board({
		"aircraft1": _make_unit(1, [aircraft_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var result = RulesEngineScript.can_unit_consolidate("aircraft1", board)
	assert_false(result, "AIRCRAFT units should not be able to consolidate")

## Non-AIRCRAFT unit can consolidate
func test_non_aircraft_can_consolidate():
	var infantry_model = _make_model("im1", 100.0, 200.0)
	var board = _make_board({
		"infantry1": _make_unit(1, [infantry_model], ["INFANTRY"]),
	})

	var result = RulesEngineScript.can_unit_consolidate("infantry1", board)
	assert_true(result, "Non-AIRCRAFT units should be able to consolidate")

## FLY unit without AIRCRAFT can consolidate
func test_fly_without_aircraft_can_consolidate():
	var fly_model = _make_model("fm1", 100.0, 200.0)
	var board = _make_board({
		"fly_unit": _make_unit(1, [fly_model], ["FLY", "JUMP PACK", "INFANTRY"]),
	})

	var result = RulesEngineScript.can_unit_consolidate("fly_unit", board)
	assert_true(result, "FLY units without AIRCRAFT should be able to consolidate")

# ==========================================
# Edge cases
# ==========================================

## Units out of engagement range should not be eligible regardless
func test_out_of_range_not_eligible():
	var model1 = _make_model("m1", 100.0, 200.0)
	var model2 = _make_model("m2", 500.0, 200.0)  # Far away (~10")

	var board = _make_board({
		"unit1": _make_unit(1, [model1], ["INFANTRY"]),
		"unit2": _make_unit(2, [model2], ["INFANTRY"]),
	})

	var result = RulesEngineScript.is_eligible_to_fight("unit1", board)
	assert_false(result, "Units out of engagement range should not be eligible")

## Dead aircraft models should not affect eligibility
func test_dead_aircraft_not_eligible():
	var dead_model = _make_model("am1", 160.0, 200.0, false)  # dead
	var infantry_model = _make_model("im1", 100.0, 200.0)

	var board = _make_board({
		"infantry1": _make_unit(1, [infantry_model], ["INFANTRY"]),
		"aircraft1": _make_unit(2, [dead_model], ["AIRCRAFT", "FLY", "VEHICLE"]),
	})

	var result = RulesEngineScript.is_eligible_to_fight("infantry1", board)
	assert_false(result, "Dead aircraft should not make unit eligible to fight")
