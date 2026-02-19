extends "res://addons/gut/test.gd"

# Tests for T3-8: Charge move direction constraint
#
# 10e rule: Each model making a charge move must end that move closer to
# at least one of the charge target units than it started.
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
	return {"units": units}

# ==========================================
# RulesEngine._validate_charge_direction_constraint_rules tests
# ==========================================

## Model moves closer to target — should pass
func test_model_moves_closer_to_target_passes():
	# Charging model starts at x=0, target at x=400 (10")
	# Model moves from x=0 to x=200 (closer to target)
	var charger = _make_model("m1", 0.0, 200.0)
	var target_model = _make_model("tm1", 400.0, 200.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger]),
		"enemy1": _make_unit(2, [target_model]),
	})

	# Path: model moves from (0,200) to (200,200) — closer to target at (400,200)
	var paths = {"m1": [[0.0, 200.0], [200.0, 200.0]]}
	var result = RulesEngineScript._validate_charge_direction_constraint_rules("u1", paths, ["enemy1"], board)

	assert_true(result.valid, "Model moving closer to target should pass direction constraint")
	assert_eq(result.errors.size(), 0, "No errors expected")

## Model moves away from target — should fail
func test_model_moves_away_from_target_fails():
	# Charging model starts at x=200, target at x=400
	# Model moves from x=200 to x=100 (farther from target)
	var charger = _make_model("m1", 200.0, 200.0)
	var target_model = _make_model("tm1", 400.0, 200.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger]),
		"enemy1": _make_unit(2, [target_model]),
	})

	# Path: model moves from (200,200) to (100,200) — farther from target at (400,200)
	var paths = {"m1": [[200.0, 200.0], [100.0, 200.0]]}
	var result = RulesEngineScript._validate_charge_direction_constraint_rules("u1", paths, ["enemy1"], board)

	assert_false(result.valid, "Model moving away from target should fail direction constraint")
	assert_eq(result.errors.size(), 1, "Should have exactly one error")
	assert_true("closer to at least one charge target" in result.errors[0], "Error should mention direction constraint")

## Model moves laterally (same distance from target) — should fail
func test_model_moves_laterally_fails():
	# Charging model starts at x=200, y=200, target at x=400, y=200
	# Model moves from (200,200) to (200,100) — same distance from target
	var charger = _make_model("m1", 200.0, 200.0)
	var target_model = _make_model("tm1", 400.0, 200.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger]),
		"enemy1": _make_unit(2, [target_model]),
	})

	# Pure lateral movement — distance stays the same (actually increases slightly)
	var paths = {"m1": [[200.0, 200.0], [200.0, 100.0]]}
	var result = RulesEngineScript._validate_charge_direction_constraint_rules("u1", paths, ["enemy1"], board)

	assert_false(result.valid, "Model moving laterally (not closer) should fail direction constraint")

## Model closer to one target but farther from another — should pass
func test_model_closer_to_one_of_multiple_targets_passes():
	# Model starts at (200,200), two targets: (400,200) and (0,200)
	# Model moves to (250,200) — closer to target at (400,200), farther from (0,200)
	# Rule only requires closer to AT LEAST ONE target
	var charger = _make_model("m1", 200.0, 200.0)
	var target1 = _make_model("tm1", 400.0, 200.0)
	var target2 = _make_model("tm2", 0.0, 200.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger]),
		"enemy1": _make_unit(2, [target1]),
		"enemy2": _make_unit(2, [target2]),
	})

	var paths = {"m1": [[200.0, 200.0], [250.0, 200.0]]}
	var result = RulesEngineScript._validate_charge_direction_constraint_rules("u1", paths, ["enemy1", "enemy2"], board)

	assert_true(result.valid, "Model closer to one of multiple targets should pass")

## Multiple models — one moves closer, one moves away — mixed result
func test_multiple_models_mixed_direction():
	var charger_m1 = _make_model("m1", 200.0, 200.0)
	var charger_m2 = _make_model("m2", 200.0, 250.0)
	var target_model = _make_model("tm1", 400.0, 200.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger_m1, charger_m2]),
		"enemy1": _make_unit(2, [target_model]),
	})

	# m1 moves closer, m2 moves away
	var paths = {
		"m1": [[200.0, 200.0], [300.0, 200.0]],
		"m2": [[200.0, 250.0], [100.0, 250.0]],
	}
	var result = RulesEngineScript._validate_charge_direction_constraint_rules("u1", paths, ["enemy1"], board)

	assert_false(result.valid, "Should fail because m2 moves away from target")
	assert_eq(result.errors.size(), 1, "Only m2 should fail")
	assert_true("m2" in result.errors[0], "Error should mention model m2")

## Model closer to a different target model within the same target unit — should pass
func test_model_closer_to_different_model_in_target_unit():
	# Two target models at different positions within the same unit
	# Model moves away from tm1 but closer to tm2 in the same target unit
	var charger = _make_model("m1", 200.0, 200.0)
	var target1 = _make_model("tm1", 400.0, 200.0)
	var target2 = _make_model("tm2", 200.0, 400.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger]),
		"enemy1": _make_unit(2, [target1, target2]),
	})

	# Move downward — farther from tm1 but closer to tm2
	var paths = {"m1": [[200.0, 200.0], [200.0, 300.0]]}
	var result = RulesEngineScript._validate_charge_direction_constraint_rules("u1", paths, ["enemy1"], board)

	assert_true(result.valid, "Closer to different model in same target unit should pass")

# ==========================================
# Full validate_charge_paths integration tests
# ==========================================

## Full validation with direction constraint failing — verify it's in the errors
func test_full_validation_includes_direction_constraint():
	# Setup: model moves away from target but within roll distance
	# Target is at 6" away (240px), model moves backwards 1" (40px)
	var charger = _make_model("m1", 200.0, 200.0)
	var target_model = _make_model("tm1", 440.0, 200.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger]),
		"enemy1": _make_unit(2, [target_model]),
	})

	# Model moves backward — within distance but wrong direction
	var paths = {"m1": [[200.0, 200.0], [160.0, 200.0]]}
	var result = RulesEngineScript.validate_charge_paths("u1", ["enemy1"], 7, paths, board)

	assert_false(result.valid, "Full validation should catch direction constraint violation")
	var has_direction_error = false
	for reason in result.reasons:
		if "closer to at least one charge target" in reason:
			has_direction_error = true
			break
	assert_true(has_direction_error, "Errors should include direction constraint message")

## Full validation with model moving closer — should pass direction check
## (may fail other checks like engagement range, but direction should pass)
func test_full_validation_direction_passes_when_closer():
	# Setup: model starts 3" from target, moves 2" closer
	# 3" = 120px, 2" = 80px
	var charger = _make_model("m1", 200.0, 200.0)
	var target_model = _make_model("tm1", 320.0, 200.0)

	var board = _make_board({
		"u1": _make_unit(1, [charger]),
		"enemy1": _make_unit(2, [target_model]),
	})

	# Model moves 80px closer to target (from 120px gap to 40px gap)
	var paths = {"m1": [[200.0, 200.0], [280.0, 200.0]]}
	var result = RulesEngineScript.validate_charge_paths("u1", ["enemy1"], 7, paths, board)

	# Check that direction constraint specifically is not in the errors
	var has_direction_error = false
	for reason in result.get("reasons", []):
		if "closer to at least one charge target" in reason:
			has_direction_error = true
			break
	assert_false(has_direction_error, "Direction constraint should pass when model moves closer")
