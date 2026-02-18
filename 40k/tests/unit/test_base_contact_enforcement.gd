extends "res://addons/gut/test.gd"

# Tests for T1-7: Base-to-base contact enforcement in charge
#
# 10e rule: If a charging model CAN make base-to-base contact with an enemy
# model while still satisfying all other charge conditions, it MUST do so.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   Two models touching (b2b): center distance ≈ 50.4 px (edge-to-edge ≈ 0")
#   1" edge gap: center distance ≈ 90.4 px  (50.4 + 40)
#   5" edge gap: center distance ≈ 250.4 px (50.4 + 200)

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

func _make_unit(owner: int, models: Array) -> Dictionary:
	return {
		"owner": owner,
		"models": models,
		"meta": {
			"name": "Test Unit (owner %d)" % owner,
		}
	}

func _make_board(units: Dictionary) -> Dictionary:
	return {"units": units}

# ==========================================
# Test: Model CAN reach b2b and DOES — valid
# ==========================================

func test_model_in_b2b_is_valid():
	# Charging model starts 3" away from target, rolled 7, ends in b2b (touching)
	# Start: (0, 0), Target: (170.4, 0) — edge distance ≈ 3" for 32mm bases
	# Final: right next to target, touching
	var target_x = 170.4  # ~3" edge-to-edge for 32mm bases
	var touching_x = target_x - 50.4  # Center distance for bases touching

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(0, [charger]),
		"target_unit": _make_unit(1, [target])
	})

	# Path: model moves to b2b position (bases touching)
	var per_model_paths = {
		"marine_1": [[0, 0], [touching_x, 0]]
	}

	var result = RulesEngineScript._validate_base_to_base_possible_rules(
		"charger_unit", per_model_paths, ["target_unit"], board, 7
	)

	assert_true(result.valid, "Should be valid when model achieves b2b: %s" % str(result.errors))
	assert_eq(result.errors.size(), 0, "Should have no errors")

# ==========================================
# Test: Model CAN reach b2b but DOES NOT — invalid
# ==========================================

func test_model_could_reach_b2b_but_didnt():
	# Charging model starts 3" away, rolled 7 (plenty to reach b2b),
	# but stops 0.8" away from target — violation
	var target_x = 170.4  # ~3" edge-to-edge
	var stop_x = target_x - 82.4  # ~0.8" edge-to-edge (not b2b, still in ER)

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(0, [charger]),
		"target_unit": _make_unit(1, [target])
	})

	# Path: model stops short of b2b
	var per_model_paths = {
		"marine_1": [[0, 0], [stop_x, 0]]
	}

	var result = RulesEngineScript._validate_base_to_base_possible_rules(
		"charger_unit", per_model_paths, ["target_unit"], board, 7
	)

	assert_false(result.valid, "Should be invalid when model could reach b2b but didn't")
	assert_eq(result.errors.size(), 1, "Should have exactly one error")
	assert_true("base-to-base contact" in result.errors[0], "Error should mention base-to-base contact")

# ==========================================
# Test: Model CANNOT reach b2b (too far) — valid even without b2b
# ==========================================

func test_model_cannot_reach_b2b_is_valid():
	# Charging model starts 12.5" away from target (edge-to-edge), rolled 12
	# Can reach ER (need 11.5" to be within 1") but NOT b2b (need 12.5" > 12 roll)
	# 12.5" edge-to-edge = 12.5 * 40 + 50.4 = 550.4 px center-to-center
	var target_x = 550.4
	# Model ends ~0.9" from target edge — in ER but not b2b
	# 0.9" = 36 px edge gap, center distance = 50.4 + 36 = 86.4 px
	var stop_x = target_x - 86.4

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(0, [charger]),
		"target_unit": _make_unit(1, [target])
	})

	var per_model_paths = {
		"marine_1": [[0, 0], [stop_x, 0]]
	}

	var result = RulesEngineScript._validate_base_to_base_possible_rules(
		"charger_unit", per_model_paths, ["target_unit"], board, 12
	)

	assert_true(result.valid, "Should be valid when b2b is unreachable (12.5\" away, rolled 12): %s" % str(result.errors))

# ==========================================
# Test: Multiple models — one can reach b2b, one cannot
# ==========================================

func test_multiple_models_mixed_reachability():
	# Model 1: 3" away from target, rolled 7 — can reach b2b, must do so
	# Model 2: 11.5" away from target, rolled 7 — cannot reach b2b, only needs ER
	var target_x = 170.4  # ~3" edge-to-edge
	var touching_x = target_x - 50.4  # b2b position for model 1

	var charger1 = _make_model("marine_1", 0, 0)
	var charger2 = _make_model("marine_2", -340, 0)  # far away
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(0, [charger1, charger2]),
		"target_unit": _make_unit(1, [target])
	})

	# Model 1 achieves b2b, Model 2 can't reach b2b (too far with roll 7)
	var per_model_paths = {
		"marine_1": [[0, 0], [touching_x, 0]],
		"marine_2": [[-340, 0], [-60, 0]]  # Moves but can't reach b2b
	}

	var result = RulesEngineScript._validate_base_to_base_possible_rules(
		"charger_unit", per_model_paths, ["target_unit"], board, 7
	)

	assert_true(result.valid, "Should be valid when unreachable model doesn't make b2b: %s" % str(result.errors))

# ==========================================
# Test: Dead target models are ignored
# ==========================================

func test_dead_target_models_ignored():
	# Only alive target model is 12.5" away — can't reach b2b with roll 12
	# Dead target model is right next to charger — should be ignored
	var far_target_x = 550.4  # ~12.5" edge-to-edge

	var charger = _make_model("marine_1", 0, 0)
	var dead_target = _make_model("ork_dead", 60, 0, false)  # Dead, nearby
	var alive_target = _make_model("ork_1", far_target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(0, [charger]),
		"target_unit": _make_unit(1, [dead_target, alive_target])
	})

	# Model ends near the far target in ER but not b2b
	var stop_x = far_target_x - 86.4
	var per_model_paths = {
		"marine_1": [[0, 0], [stop_x, 0]]
	}

	var result = RulesEngineScript._validate_base_to_base_possible_rules(
		"charger_unit", per_model_paths, ["target_unit"], board, 12
	)

	assert_true(result.valid, "Dead target models should be ignored for b2b check: %s" % str(result.errors))

# ==========================================
# Test: Empty paths or missing models — graceful handling
# ==========================================

func test_empty_paths_handled_gracefully():
	var board = _make_board({
		"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
		"target_unit": _make_unit(1, [_make_model("ork_1", 100, 0)])
	})

	# Empty per_model_paths
	var result = RulesEngineScript._validate_base_to_base_possible_rules(
		"charger_unit", {}, ["target_unit"], board, 7
	)

	assert_true(result.valid, "Empty paths should be valid (nothing to check): %s" % str(result.errors))

# ==========================================
# Test: Model is already at b2b tolerance distance — valid
# ==========================================

func test_model_within_tolerance_is_b2b():
	# Model ends 0.2" from target edge — within BASE_CONTACT_TOLERANCE (0.25")
	# 0.2" = 8 px edge gap, center distance = 50.4 + 8 = 58.4
	var target_x = 170.4  # ~3" away
	var almost_touching_x = target_x - 58.4  # ~0.2" edge gap — within tolerance

	var charger = _make_model("marine_1", 0, 0)
	var target = _make_model("ork_1", target_x, 0)

	var board = _make_board({
		"charger_unit": _make_unit(0, [charger]),
		"target_unit": _make_unit(1, [target])
	})

	var per_model_paths = {
		"marine_1": [[0, 0], [almost_touching_x, 0]]
	}

	var result = RulesEngineScript._validate_base_to_base_possible_rules(
		"charger_unit", per_model_paths, ["target_unit"], board, 7
	)

	assert_true(result.valid, "Model within b2b tolerance should count as b2b: %s" % str(result.errors))
