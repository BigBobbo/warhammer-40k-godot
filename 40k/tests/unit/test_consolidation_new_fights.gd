extends "res://addons/gut/test.gd"

# Tests for T2-6: Consolidation into new enemies triggers new fights
#
# 10e rule: "After an enemy unit has finished its Consolidation move,
# if previously ineligible units are now eligible to Fight — these units
# can then be selected to fight."
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   Two models touching (b2b): center distance ≈ 50.4 px (edge-to-edge ≈ 0")
#   1" edge gap: center distance ≈ 90.4 px  (50.4 + 40)
#   3" edge gap: center distance ≈ 170.4 px (50.4 + 120)
#   4" edge gap: center distance ≈ 210.4 px (50.4 + 160)

var fight_phase = null

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return

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

func _make_unit(owner: int, models: Array, name: String = "", charged: bool = false) -> Dictionary:
	var unit_name = name if name != "" else "Test Unit (owner %d)" % owner
	var flags = {}
	if charged:
		flags["charged_this_turn"] = true
	return {
		"owner": owner,
		"models": models,
		"meta": {
			"name": unit_name,
			"stats": {"toughness": 4, "save": 3, "wounds": 1},
			"keywords": ["INFANTRY"],
			"abilities": []
		},
		"flags": flags
	}

func _setup_fight_phase(units: Dictionary) -> void:
	"""Configure the FightPhase with a game state snapshot for testing."""
	fight_phase.game_state_snapshot = {"units": units}
	# Reset fight state
	fight_phase.units_that_fought = []
	fight_phase.fights_first_sequence = {"1": [], "2": []}
	fight_phase.normal_sequence = {"1": [], "2": []}
	fight_phase.fights_last_sequence = {"1": [], "2": []}
	fight_phase.fight_sequence = []

# ==========================================
# Test: Unit consolidates into new enemy — new enemy added to fight sequence
# ==========================================

func test_consolidation_into_new_enemy_adds_to_fight_sequence():
	"""When a unit consolidates into a new enemy, that enemy becomes eligible to fight"""
	# Setup: Player 1's unit_a is fighting Player 2's unit_b (already in engagement)
	# Player 2's unit_c is NOT in engagement range of anyone (3" away from unit_a)
	# After consolidation, unit_a moves within 1" of unit_c → unit_c becomes eligible
	#
	# unit_a (P1) at (200, 200) — consolidating unit
	# unit_b (P2) at (250.4, 200) — in engagement with unit_a (b2b)
	# unit_c (P2) at (370, 200) — NOT in engagement with anyone (~3" from unit_a)
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
	}
	_setup_fight_phase(units)

	# unit_a and unit_b are in the fight sequence already
	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": ["unit_b"]}
	fight_phase.fight_sequence = ["unit_a", "unit_b"]

	# unit_a consolidates 3" toward unit_c — moves to (320, 200)
	# Distance from (320,200) to (370,200) = 50px center-to-center ≈ touching (50.4px for b2b)
	# Edge-to-edge ≈ 0" — within engagement range!
	var movements = {"0": Vector2(320, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 1, "Should have 1 newly eligible unit")
	assert_has(newly_eligible, "unit_c", "unit_c should be newly eligible")

	# Verify it was added to normal_sequence
	assert_has(fight_phase.normal_sequence["2"], "unit_c", "unit_c should be in P2's normal sequence")

func test_consolidation_into_new_enemy_adds_to_legacy_fight_sequence():
	"""Newly eligible units should also be added to the legacy fight_sequence"""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
	}
	_setup_fight_phase(units)

	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": ["unit_b"]}
	fight_phase.fight_sequence = ["unit_a", "unit_b"]

	var movements = {"0": Vector2(320, 200)}
	fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_has(fight_phase.fight_sequence, "unit_c", "unit_c should be in legacy fight_sequence")

# ==========================================
# Test: No new enemies — no new units added
# ==========================================

func test_consolidation_no_new_enemies_adds_nothing():
	"""When consolidation doesn't bring anyone new into engagement, nothing changes"""
	# unit_a consolidates but stays near unit_b, doesn't reach unit_c
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(600, 200)], "Unit C (P2)"),  # Far away
	}
	_setup_fight_phase(units)

	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": ["unit_b"]}
	fight_phase.fight_sequence = ["unit_a", "unit_b"]

	# unit_a barely moves — stays near unit_b
	var movements = {"0": Vector2(210, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "No new units should become eligible")

# ==========================================
# Test: Already-in-sequence units are NOT re-added
# ==========================================

func test_already_in_sequence_not_re_added():
	"""Units already in any fight sequence should not be added again"""
	# unit_b is already in fights_first_sequence and is in engagement range
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
	}
	_setup_fight_phase(units)

	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": ["unit_b"]}
	fight_phase.fight_sequence = ["unit_a", "unit_b"]

	# unit_a consolidates, still near unit_b
	var movements = {"0": Vector2(210, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "Already-in-sequence units should not be re-added")
	# Verify unit_b not duplicated in normal_sequence
	assert_eq(fight_phase.normal_sequence["2"].size(), 0, "normal_sequence should remain empty")

# ==========================================
# Test: Units that already fought are NOT added
# ==========================================

func test_units_that_already_fought_not_added():
	"""Units that have already fought this phase should not become eligible again"""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
	}
	_setup_fight_phase(units)

	# unit_c already fought
	fight_phase.units_that_fought = ["unit_c"]

	# unit_a consolidates into engagement with unit_c
	var movements = {"0": Vector2(320, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "Units that already fought should not be re-added")

# ==========================================
# Test: Dead units are NOT added
# ==========================================

func test_dead_units_not_added():
	"""Units with no alive models should not become eligible"""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_c": _make_unit(2, [_make_model(370, 200, false)], "Unit C (P2) - dead"),  # Dead model
	}
	_setup_fight_phase(units)

	# unit_a consolidates near unit_c, but unit_c is dead
	var movements = {"0": Vector2(320, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "Dead units should not become eligible")

# ==========================================
# Test: Multiple new enemies can become eligible
# ==========================================

func test_multiple_new_enemies_eligible():
	"""Multiple enemy units can become eligible at once from consolidation"""
	# unit_a consolidates into engagement range of BOTH unit_c and unit_d
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
		"unit_d": _make_unit(2, [_make_model(370, 250)], "Unit D (P2)"),
	}
	_setup_fight_phase(units)

	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": ["unit_b"]}
	fight_phase.fight_sequence = ["unit_a", "unit_b"]

	# unit_a consolidates close to both unit_c and unit_d
	# Move to (320, 225) — within ~1" of both unit_c at (370,200) and unit_d at (370,250)
	# Distance to unit_c: sqrt((370-320)^2 + (200-225)^2) = sqrt(2500+625) = ~55.9px center
	# Edge-to-edge: 55.9 - 50.4 ≈ 5.5px ≈ 0.14" — in engagement range!
	# Distance to unit_d: sqrt((370-320)^2 + (250-225)^2) = same = ~55.9px — also in ER!
	var movements = {"0": Vector2(320, 225)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 2, "Both unit_c and unit_d should become eligible")
	assert_has(newly_eligible, "unit_c", "unit_c should be newly eligible")
	assert_has(newly_eligible, "unit_d", "unit_d should be newly eligible")

# ==========================================
# Test: Friendly units are NOT made eligible (same team as consolidator)
# ==========================================

func test_friendly_units_not_eligible():
	"""Friendly units of the consolidating player should not become eligible"""
	# unit_a (P1) consolidates near unit_e (P1) — same team, shouldn't be eligible
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_e": _make_unit(1, [_make_model(370, 200)], "Unit E (P1)"),  # Same team
	}
	_setup_fight_phase(units)

	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": ["unit_b"]}

	var movements = {"0": Vector2(320, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	# unit_e is the same team as unit_a — it could be in engagement range with unit_b
	# but there's no enemy within engagement range of unit_e at its position, so it won't be eligible
	# unless unit_b is also within ER of unit_e (which it isn't at 250.4 vs 370)
	assert_false("unit_e" in newly_eligible, "Friendly units shouldn't be incorrectly added")

# ==========================================
# Test: Newly eligible unit added to correct player's normal_sequence
# ==========================================

func test_newly_eligible_added_to_correct_player():
	"""Newly eligible units should be added to the correct player's normal_sequence"""
	# P1 unit consolidates into P2 unit → P2 unit becomes eligible
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
	}
	_setup_fight_phase(units)

	var movements = {"0": Vector2(320, 200)}

	fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(fight_phase.normal_sequence["1"].size(), 0, "P1 normal_sequence should be empty")
	assert_eq(fight_phase.normal_sequence["2"].size(), 1, "P2 normal_sequence should have 1 unit")
	assert_has(fight_phase.normal_sequence["2"], "unit_c", "unit_c should be in P2 normal_sequence")

# ==========================================
# Test: P1 unit becomes eligible when P2 consolidates into it
# ==========================================

func test_p1_unit_eligible_when_p2_consolidates():
	"""Player 1 units should become eligible when Player 2 consolidates into them"""
	# P2 unit consolidates into P1 unit
	var units = {
		"unit_a": _make_unit(2, [_make_model(200, 200)], "Unit A (P2)"),
		"unit_c": _make_unit(1, [_make_model(370, 200)], "Unit C (P1)"),
	}
	_setup_fight_phase(units)

	var movements = {"0": Vector2(320, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 1, "P1 unit should become eligible")
	assert_has(newly_eligible, "unit_c", "unit_c should be newly eligible")
	assert_has(fight_phase.normal_sequence["1"], "unit_c", "unit_c should be in P1 normal_sequence")

# ==========================================
# Test: Unit already in engagement with OTHER enemies but not in sequence
# ==========================================

func test_unit_in_engagement_with_other_enemy_not_in_sequence():
	"""A unit already in engagement range with a non-consolidating enemy should
	also become eligible if it wasn't in any fight sequence"""
	# unit_c is in engagement range with unit_d (different P1 unit) but wasn't in any sequence
	# After consolidation check, it should be found eligible due to existing engagement
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),  # Consolidating
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(500, 200)], "Unit C (P2)"),  # In ER with unit_d
		"unit_d": _make_unit(1, [_make_model(550.4, 200)], "Unit D (P1)"),  # In ER with unit_c
	}
	_setup_fight_phase(units)

	# Only unit_a and unit_b are in sequences; unit_c and unit_d somehow missed
	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": ["unit_b"]}

	# unit_a consolidates away from unit_c (not adding engagement)
	var movements = {"0": Vector2(210, 200)}

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	# unit_c is in ER with unit_d (at current positions) and isn't in any sequence
	# unit_d is also not in any sequence and is in ER with unit_c
	assert_true(newly_eligible.size() >= 2, "Both unit_c and unit_d should be newly eligible (found %d)" % newly_eligible.size())
	assert_has(newly_eligible, "unit_c", "unit_c should be newly eligible")
	assert_has(newly_eligible, "unit_d", "unit_d should be newly eligible")

# ==========================================
# Test: Empty movements — just scans existing state
# ==========================================

func test_empty_consolidation_movements():
	"""Even with no actual consolidation movement, should still scan for eligibility"""
	# unit_c is already in ER with unit_a but wasn't in any sequence
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_c": _make_unit(2, [_make_model(250.4, 200)], "Unit C (P2)"),
	}
	_setup_fight_phase(units)

	# unit_a is already in sequence (it's the one consolidating)
	fight_phase.fights_first_sequence = {"1": ["unit_a"], "2": []}

	# unit_c not in any sequence but IS in ER with unit_a
	var movements = {}  # No actual movement

	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 1, "unit_c should become eligible even with empty movements")
	assert_has(newly_eligible, "unit_c", "unit_c should be newly eligible")

# ==========================================
# Test: _units_in_engagement_range_with_override works correctly
# ==========================================

func test_engagement_range_with_override_in_range():
	"""_units_in_engagement_range_with_override should detect engagement with updated positions"""
	var unit1 = _make_unit(2, [_make_model(370, 200)], "Defender")
	var unit2_override = _make_unit(1, [_make_model(320, 200)], "Attacker override")
	# Center distance: 50px ≈ touching for 32mm bases (50.4px)

	var result = fight_phase._units_in_engagement_range_with_override(unit1, unit2_override)

	assert_true(result, "Units with overridden positions within 1\" should be in engagement range")

func test_engagement_range_with_override_out_of_range():
	"""_units_in_engagement_range_with_override should reject units too far apart"""
	var unit1 = _make_unit(2, [_make_model(500, 200)], "Far defender")
	var unit2_override = _make_unit(1, [_make_model(200, 200)], "Attacker override")
	# Center distance: 300px ≈ 7.5" edge-to-edge — way too far

	var result = fight_phase._units_in_engagement_range_with_override(unit1, unit2_override)

	assert_false(result, "Units far apart should not be in engagement range")
