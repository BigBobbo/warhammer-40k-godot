extends "res://addons/gut/test.gd"

# Tests for T4-5: Models in base contact should not move during pile-in
#
# 10e rule: "Models that are already in base-to-base contact with an enemy
# model are not moved" during pile-in or consolidation.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   Two models touching (b2b): center distance ≈ 50.4 px (edge-to-edge ≈ 0")
#   BASE_CONTACT_TOLERANCE = 0.25" ≈ 10px edge gap → center distance ≈ 60.4 px
#   1" edge gap: center distance ≈ 90.4 px

var fight_phase = null
var _autoloads_ok: bool = false

func before_each():
	_autoloads_ok = AutoloadHelper.verify_autoloads_available()
	if not _autoloads_ok:
		push_warning("Autoloads not fully available — tests may be skipped")
		return

	# Create a FightPhase instance for testing
	var FightPhaseScript = load("res://phases/FightPhase.gd")
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

func _setup_fight_phase(units: Dictionary, active_fighter_id: String = "attacker") -> void:
	"""Configure the FightPhase with a game state snapshot for testing."""
	if not fight_phase:
		return
	fight_phase.game_state_snapshot = {"units": units}
	fight_phase.active_fighter_id = active_fighter_id

func _skip_if_no_autoloads() -> bool:
	if not _autoloads_ok or fight_phase == null:
		gut.p("SKIP: Autoloads not available")
		pass_test("Skipped — autoloads unavailable")
		return true
	return false

# ==========================================
# _is_model_in_base_contact_with_enemy tests
# ==========================================

func test_model_in_base_contact_detected():
	"""Model touching enemy (0\" gap) should be detected as in base contact"""
	if _skip_if_no_autoloads(): return
	# Two models with bases touching: center distance = 50.4 px
	var units = {
		"attacker": _make_unit(1, [_make_model(250.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	var result = fight_phase._is_model_in_base_contact_with_enemy("attacker", "0")

	assert_true(result, "Model touching enemy should be detected as in base contact")

func test_model_within_tolerance_detected():
	"""Model within BASE_CONTACT_TOLERANCE (0.25\") should be detected as in base contact"""
	if _skip_if_no_autoloads(): return
	# Edge-to-edge ~0.2": center distance ≈ 58.4 px (50.4 + 8)
	var units = {
		"attacker": _make_unit(1, [_make_model(258.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	var result = fight_phase._is_model_in_base_contact_with_enemy("attacker", "0")

	assert_true(result, "Model within 0.25\" tolerance should count as base contact")

func test_model_not_in_base_contact():
	"""Model more than 0.25\" from enemy should NOT be in base contact"""
	if _skip_if_no_autoloads(): return
	# Edge-to-edge ~1": center distance ≈ 90.4 px
	var units = {
		"attacker": _make_unit(1, [_make_model(290.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	var result = fight_phase._is_model_in_base_contact_with_enemy("attacker", "0")

	assert_false(result, "Model 1\" from enemy should NOT be in base contact")

func test_dead_enemy_ignored():
	"""Dead enemy models should not count for base contact detection"""
	if _skip_if_no_autoloads(): return
	# Attacker touching dead enemy
	var units = {
		"attacker": _make_unit(1, [_make_model(250.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200, false)])  # dead
	}
	_setup_fight_phase(units)

	var result = fight_phase._is_model_in_base_contact_with_enemy("attacker", "0")

	assert_false(result, "Dead enemy model should not count as base contact")

func test_friendly_model_ignored():
	"""Friendly models should not count for base contact detection"""
	if _skip_if_no_autoloads(): return
	# Two friendly models touching
	var units = {
		"attacker": _make_unit(1, [_make_model(250.4, 200), _make_model(200, 200)])
	}
	_setup_fight_phase(units)

	var result = fight_phase._is_model_in_base_contact_with_enemy("attacker", "0")

	assert_false(result, "Friendly model touching should NOT count as base contact with enemy")

# ==========================================
# Pile-in validation: models in b2b cannot move
# ==========================================

func test_pile_in_rejects_movement_of_b2b_model():
	"""A model already in base contact that is moved should be rejected"""
	if _skip_if_no_autoloads(): return
	# Model 0 is in b2b with enemy (touching), model 1 is far away
	var units = {
		"attacker": _make_unit(1, [
			_make_model(250.4, 200),   # model 0: touching enemy
			_make_model(400, 200)      # model 1: far from enemy
		]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Try to move model 0 (which is in base contact) — should be rejected
	var action = {
		"unit_id": "attacker",
		"movements": {"0": Vector2(260, 200)}  # moved slightly
	}

	var result = fight_phase._validate_pile_in(action)

	assert_false(result.valid, "Moving a model in base contact should be invalid")
	assert_true(result.errors.size() > 0, "Should have at least one error")
	var has_b2b_error = false
	for err in result.errors:
		if "already in base contact" in err:
			has_b2b_error = true
			break
	assert_true(has_b2b_error, "Error should mention 'already in base contact': %s" % str(result.errors))

func test_pile_in_allows_movement_of_non_b2b_model():
	"""A model NOT in base contact can still be moved during pile-in"""
	if _skip_if_no_autoloads(): return
	# Model 0 is far from enemy, moves closer
	var units = {
		"attacker": _make_unit(1, [_make_model(370.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Move model 0 closer to enemy (valid pile-in)
	var action = {
		"unit_id": "attacker",
		"movements": {"0": Vector2(250.4, 200)}  # move to b2b
	}

	var result = fight_phase._validate_pile_in(action)

	assert_true(result.valid, "Non-b2b model should be allowed to move: %s" % str(result.errors))

func test_pile_in_mixed_b2b_and_non_b2b():
	"""In a unit with mixed b2b/non-b2b models, only b2b models are blocked"""
	if _skip_if_no_autoloads(): return
	# Model 0 is in b2b, model 1 is not
	var units = {
		"attacker": _make_unit(1, [
			_make_model(250.4, 200),   # model 0: touching enemy
			_make_model(370.4, 200)    # model 1: 3" from enemy
		]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Only move model 1 (not in b2b) — should be allowed
	var action = {
		"unit_id": "attacker",
		"movements": {"1": Vector2(260.4, 200)}  # model 1 moves closer
	}

	var result = fight_phase._validate_pile_in(action)

	assert_true(result.valid, "Moving only non-b2b model should be valid: %s" % str(result.errors))

func test_pile_in_b2b_model_with_zero_movement_is_ok():
	"""A model in b2b that doesn't actually move (same position) should be fine"""
	if _skip_if_no_autoloads(): return
	# Model is in b2b but submits with same position (no actual movement)
	var units = {
		"attacker": _make_unit(1, [_make_model(250.4, 200)]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)

	# Submit with the same position (not actually moved)
	var action = {
		"unit_id": "attacker",
		"movements": {"0": Vector2(250.4, 200)}  # same position
	}

	var result = fight_phase._validate_pile_in(action)

	assert_true(result.valid, "B2B model with zero movement should be valid: %s" % str(result.errors))

# ==========================================
# Consolidation validation: same rule applies
# ==========================================

func test_consolidate_rejects_movement_of_b2b_model():
	"""A model in base contact should also be blocked during consolidation"""
	if _skip_if_no_autoloads(): return
	# Model 0 is in b2b with enemy
	var units = {
		"attacker": _make_unit(1, [
			_make_model(250.4, 200),   # model 0: touching enemy
			_make_model(290.4, 200)    # model 1: 1" from enemy (in ER)
		]),
		"enemy": _make_unit(2, [_make_model(200, 200)])
	}
	_setup_fight_phase(units)
	fight_phase.pending_attacks = []  # Must be empty for consolidation

	# Try to move model 0 (in base contact) during consolidation
	var action = {
		"unit_id": "attacker",
		"movements": {"0": Vector2(260, 200)}  # moved slightly
	}

	var result = fight_phase._validate_consolidate_engagement_range("attacker", action.movements)

	assert_false(result.valid, "Moving b2b model during consolidation should be invalid")
	var has_b2b_error = false
	for err in result.errors:
		if "already in base contact" in err:
			has_b2b_error = true
			break
	assert_true(has_b2b_error, "Error should mention 'already in base contact': %s" % str(result.errors))
