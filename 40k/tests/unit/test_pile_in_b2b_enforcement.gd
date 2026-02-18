extends "res://addons/gut/test.gd"

# Tests for T1-6: Base-to-base contact enforcement in pile-in/consolidation
#
# 10e rule: "Each model that makes a Pile-in move must end closer to the
# closest enemy model, and in base-to-base contact with it if possible."
# Same requirement for consolidation in engagement mode.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   Two models touching (b2b): center distance ≈ 50.4 px (edge-to-edge ≈ 0")
#   1" edge gap: center distance ≈ 90.4 px  (50.4 + 40)
#   3" edge gap: center distance ≈ 170.4 px (50.4 + 120)

var fight_phase = null

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return

	# Create a FightPhase instance for testing
	var FightPhaseScript = preload("res://phases/FightPhase.gd")
	fight_phase = FightPhaseScript.new()

# ==========================================
# Helpers
# ==========================================

func _make_model(pos_x: float, pos_y: float, alive: bool = true) -> Dictionary:
	return {
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
			"stats": {"toughness": 4, "save": 3, "wounds": 1},
			"keywords": ["INFANTRY"]
		},
		"flags": {}
	}

func _setup_fight_phase(units: Dictionary) -> void:
	"""Configure the FightPhase with a game state snapshot for testing."""
	fight_phase.game_state_snapshot = {"units": units}

# ==========================================
# Test: Model CAN reach b2b and DOES — valid
# ==========================================

func test_pile_in_model_achieves_b2b_is_valid():
	"""When a model can reach b2b and ends in b2b, validation should pass"""
	# Enemy at (200, 200), attacker model starts at (370.4, 200) — ~3" edge-to-edge
	# Model piles in to (250.4, 200) — touching enemy (b2b achieved)
	var units = {
		"attacker": _make_unit(1, [_make_model(370.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Model moves to b2b (center distance = 50.4px = bases touching)
	var movements = {"0": Vector2(250.4, 200)}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_true(result.valid, "Should be valid when model achieves b2b: %s" % str(result.errors))
	assert_eq(result.errors.size(), 0, "Should have no errors")

# ==========================================
# Test: Model CAN reach b2b but DOES NOT — invalid
# ==========================================

func test_pile_in_model_could_reach_b2b_but_didnt():
	"""When a model can reach b2b but stops short, validation should fail"""
	# Enemy at (200, 200), attacker starts at (370.4, 200) — ~3" edge-to-edge
	# Model piles in to (282, 200) — ~0.79" edge-to-edge (NOT b2b, still in ER)
	var units = {
		"attacker": _make_unit(1, [_make_model(370.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Model stops 0.79" from enemy (in ER but NOT b2b)
	var movements = {"0": Vector2(282, 200)}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_false(result.valid, "Should be invalid when model could reach b2b but didn't")
	assert_eq(result.errors.size(), 1, "Should have exactly one error")
	assert_true("base-to-base contact" in result.errors[0], "Error should mention base-to-base contact")

# ==========================================
# Test: Model CANNOT reach b2b (too far) — valid even without b2b
# ==========================================

func test_pile_in_model_cannot_reach_b2b_is_valid():
	"""When b2b is unreachable (enemy >3" away), not reaching it is valid"""
	# Enemy at (200, 200), attacker starts at (400, 200) — ~3.74" edge-to-edge (>3")
	# Model piles in 3" toward enemy but can't reach b2b
	# 3" = 120px, so model moves from 400 to 280 — ~0.74" edge-to-edge (in ER but not b2b)
	var units = {
		"attacker": _make_unit(1, [_make_model(400, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Model ends at ~0.74" from enemy (3" movement used up, can't reach b2b)
	var movements = {"0": Vector2(280, 200)}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_true(result.valid, "Should be valid when b2b is unreachable (>3\" away): %s" % str(result.errors))

# ==========================================
# Test: Model is within tolerance — counts as b2b
# ==========================================

func test_model_within_tolerance_counts_as_b2b():
	"""Model ending within BASE_CONTACT_TOLERANCE (0.25\") should count as b2b"""
	# Enemy at (200, 200), attacker starts at (330, 200) — ~2" edge-to-edge
	# Model ends at (258.4, 200) — ~0.2" edge-to-edge (within 0.25" tolerance)
	var units = {
		"attacker": _make_unit(1, [_make_model(330, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# 0.2" edge gap = 8px, center distance = 50.4 + 8 = 58.4
	var movements = {"0": Vector2(258.4, 200)}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_true(result.valid, "Model within b2b tolerance should be valid: %s" % str(result.errors))

# ==========================================
# Test: Multiple models — one can reach, one cannot
# ==========================================

func test_multiple_models_mixed_reachability():
	"""Model that can reach b2b must do so; model that can't is exempt"""
	# Enemy at (200, 200)
	# Model 0 at (330, 200) — ~2" away, CAN reach b2b, must do so
	# Model 1 at (400, 200) — ~3.74" away, CANNOT reach b2b
	var units = {
		"attacker": _make_unit(1, [
			_make_model(330, 200),  # 2" from enemy — can reach b2b
			_make_model(400, 200),  # 3.74" from enemy — cannot reach b2b
		]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Model 0 achieves b2b, Model 1 moves as close as possible
	var movements = {
		"0": Vector2(250.4, 200),  # b2b position
		"1": Vector2(280, 200),    # In ER but not b2b (can't reach)
	}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_true(result.valid, "Should be valid when unreachable model doesn't make b2b: %s" % str(result.errors))

# ==========================================
# Test: Multiple models — both can reach b2b, one doesn't
# ==========================================

func test_multiple_models_both_can_reach_one_doesnt():
	"""Both models can reach b2b; one does, one doesn't — should fail"""
	# Enemy at (200, 200)
	# Model 0 at (290, 200) — ~1" away, CAN reach b2b
	# Model 1 at (330, 200) — ~2" away, CAN reach b2b
	var units = {
		"attacker": _make_unit(1, [
			_make_model(290, 200),
			_make_model(330, 200),
		]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Model 0 achieves b2b, Model 1 stops short
	var movements = {
		"0": Vector2(250.4, 200),  # b2b ✓
		"1": Vector2(282, 200),    # 0.79" from enemy ✗ (could reach b2b)
	}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_false(result.valid, "Should be invalid when model 1 could reach b2b but didn't")
	assert_eq(result.errors.size(), 1, "Should have one error for model 1")
	assert_true("Model 1" in result.errors[0], "Error should reference model 1")

# ==========================================
# Test: Model that didn't move is exempt
# ==========================================

func test_stationary_model_not_checked():
	"""Models that didn't move should not be checked for b2b"""
	# Even though the model is 2" from enemy and COULD reach b2b,
	# if it's included in movements but at the same position, skip it.
	var units = {
		"attacker": _make_unit(1, [_make_model(330, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Model "moved" to same position (effectively stationary)
	var movements = {"0": Vector2(330, 200)}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_true(result.valid, "Stationary model should not be checked: %s" % str(result.errors))

# ==========================================
# Test: Dead models are excluded
# ==========================================

func test_dead_model_excluded():
	"""Dead models in movements dict should be skipped"""
	var units = {
		"attacker": _make_unit(1, [_make_model(330, 200, false)]),  # Dead
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Dead model "moves" but should be ignored
	var movements = {"0": Vector2(282, 200)}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_true(result.valid, "Dead model should be ignored: %s" % str(result.errors))

# ==========================================
# Test: Empty movements — valid
# ==========================================

func test_empty_movements_valid():
	"""Empty movements dict should be valid (nothing to check)"""
	var units = {
		"attacker": _make_unit(1, [_make_model(330, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	var result = fight_phase._validate_base_to_base_if_possible("attacker", {}, 3.0)

	assert_true(result.valid, "Empty movements should be valid: %s" % str(result.errors))

# ==========================================
# Test: Model exactly at 3" boundary — can barely reach b2b
# ==========================================

func test_model_at_exact_3_inch_boundary():
	"""Model exactly 3\" from enemy can just barely reach b2b — must do so"""
	# 3" edge-to-edge = 120px + 50.4px center = 170.4px center-to-center
	var units = {
		"attacker": _make_unit(1, [_make_model(370.4, 200)]),  # Exactly 3" edge-to-edge
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Model stops 0.5" from enemy (not b2b, but was reachable)
	var movements = {"0": Vector2(270.4, 200)}  # ~0.5" edge-to-edge

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	assert_false(result.valid, "Should be invalid — model at exactly 3\" could reach b2b but didn't")

# ==========================================
# Test: Dead enemy models are ignored (closest enemy calculation)
# ==========================================

func test_dead_enemy_models_ignored():
	"""Dead enemy models should not count as closest enemy for b2b"""
	var units = {
		"attacker": _make_unit(1, [_make_model(330, 200)]),
		"enemy": _make_unit(2, [
			_make_model(260, 200, false),  # Dead, nearby
			_make_model(600, 200),          # Alive but far (~13.7")
		])
	}
	_setup_fight_phase(units)

	# Model moves toward the alive enemy but can't reach b2b (too far)
	var movements = {"0": Vector2(280, 200)}

	var result = fight_phase._validate_base_to_base_if_possible("attacker", movements, 3.0)

	# Dead model at 260 is ignored; alive enemy at 600 is ~13.7" away — can't reach b2b
	assert_true(result.valid, "Dead enemy should be ignored, alive enemy too far: %s" % str(result.errors))
