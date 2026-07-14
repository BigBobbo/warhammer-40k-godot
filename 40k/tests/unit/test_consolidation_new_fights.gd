extends "res://addons/gut/test.gd"

# Tests for 12.08 (Engaging Consolidation): a consolidation move that drags a
# NEW enemy unit into engagement range forces that unit to fight ("new foes to
# face"). _scan_newly_eligible_units_after_consolidation returns the newly
# engaged enemy units; the FightSequencer picks them up from live engagement
# once the consolidation positions land.
#
# 11e note: the 10e per-tier fight_sequence / normal_sequence lists were
# removed. "Already in the fight" is now pre-move engagement (a unit already in
# engagement range is picked up by the normal fight flow, not forced), so this
# suite asserts on the function's RETURN value, not on tier-list mutations.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   Two models touching (b2b): center distance ≈ 50.4 px (edge-to-edge ≈ 0")

var fight_phase = null
var _saved_state = null

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return

	# _scan_newly_eligible reads game_state_snapshot, which is a property that
	# returns GameState.state (its setter is a no-op) — so the test board must
	# be injected into GameState.state, and restored afterward.
	_saved_state = GameState.state
	var FightPhaseScript = preload("res://phases/FightPhase.gd")
	fight_phase = FightPhaseScript.new()

func after_each():
	if _saved_state != null:
		GameState.state = _saved_state
		_saved_state = null

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
	"""Inject the test board into GameState.state (game_state_snapshot reads it)."""
	GameState.state = {"units": units, "board": {"objectives": [], "terrain_features": []}, "meta": {"active_player": 1}}
	fight_phase.units_that_fought = []

# ==========================================
# Consolidate into a new enemy → that enemy is forced to fight (12.08)
# ==========================================

func test_consolidation_into_new_enemy_is_returned():
	"""When a unit consolidates into a new enemy, that enemy is returned as forced."""
	# unit_a (P1) @ (200,200) — consolidating; unit_b (P2) @ (250.4,200) — already
	# engaged with unit_a; unit_c (P2) @ (370,200) — NOT engaged (~3" from unit_a).
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
	}
	_setup_fight_phase(units)

	# unit_a consolidates 3" toward unit_c → moves to (320,200), reaching ER.
	var movements = {"0": Vector2(320, 200)}
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 1, "Should have 1 newly engaged enemy")
	assert_has(newly_eligible, "unit_c", "unit_c should be newly engaged")

func test_consolidation_no_new_enemies_returns_nothing():
	"""When consolidation doesn't bring anyone new into ER, nothing is returned."""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(600, 200)], "Unit C (P2)"),  # Far away
	}
	_setup_fight_phase(units)

	var movements = {"0": Vector2(210, 200)}  # barely moves, stays near unit_b
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "No new units should become eligible")

func test_already_engaged_unit_not_forced():
	"""A unit already in engagement range before the move is not a new foe."""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
	}
	_setup_fight_phase(units)

	var movements = {"0": Vector2(210, 200)}
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "Already-engaged units should not be forced")

func test_units_that_already_fought_not_forced():
	"""Units that have already fought this phase should not be forced again."""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
	}
	_setup_fight_phase(units)
	fight_phase.units_that_fought = ["unit_c"]

	var movements = {"0": Vector2(320, 200)}  # consolidates into ER with unit_c
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "Units that already fought should not be forced")

func test_dead_units_not_forced():
	"""Units with no alive models should not become eligible."""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_c": _make_unit(2, [_make_model(370, 200, false)], "Unit C (P2) - dead"),
	}
	_setup_fight_phase(units)

	var movements = {"0": Vector2(320, 200)}
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 0, "Dead units should not become eligible")

func test_multiple_new_enemies_forced():
	"""Multiple enemy units can be forced at once from one consolidation."""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_c": _make_unit(2, [_make_model(370, 200)], "Unit C (P2)"),
		"unit_d": _make_unit(2, [_make_model(370, 250)], "Unit D (P2)"),
	}
	_setup_fight_phase(units)

	# Move to (320,225) — within ER of both unit_c and unit_d.
	var movements = {"0": Vector2(320, 225)}
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 2, "Both unit_c and unit_d should be forced")
	assert_has(newly_eligible, "unit_c", "unit_c should be newly engaged")
	assert_has(newly_eligible, "unit_d", "unit_d should be newly engaged")

func test_friendly_units_not_forced():
	"""Friendly units of the consolidating player should not become eligible."""
	var units = {
		"unit_a": _make_unit(1, [_make_model(200, 200)], "Unit A (P1)"),
		"unit_b": _make_unit(2, [_make_model(250.4, 200)], "Unit B (P2)"),
		"unit_e": _make_unit(1, [_make_model(370, 200)], "Unit E (P1)"),  # Same team as unit_a
	}
	_setup_fight_phase(units)

	var movements = {"0": Vector2(320, 200)}
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_false("unit_e" in newly_eligible, "Friendly units shouldn't be forced")

func test_p1_unit_forced_when_p2_consolidates():
	"""A P1 unit is forced to fight when a P2 unit consolidates into it."""
	var units = {
		"unit_a": _make_unit(2, [_make_model(200, 200)], "Unit A (P2)"),
		"unit_c": _make_unit(1, [_make_model(370, 200)], "Unit C (P1)"),
	}
	_setup_fight_phase(units)

	var movements = {"0": Vector2(320, 200)}
	var newly_eligible = fight_phase._scan_newly_eligible_units_after_consolidation("unit_a", movements)

	assert_eq(newly_eligible.size(), 1, "P1 unit should be forced")
	assert_has(newly_eligible, "unit_c", "unit_c should be newly engaged")

# ==========================================
# _units_in_engagement_range_with_override helper
# ==========================================

func test_engagement_range_with_override_in_range():
	"""_units_in_engagement_range_with_override detects engagement with updated positions."""
	var unit1 = _make_unit(2, [_make_model(370, 200)], "Defender")
	var unit2_override = _make_unit(1, [_make_model(320, 200)], "Attacker override")

	var result = fight_phase._units_in_engagement_range_with_override(unit1, unit2_override)

	assert_true(result, "Units with overridden positions within ER should be engaged")

func test_engagement_range_with_override_out_of_range():
	"""_units_in_engagement_range_with_override rejects units too far apart."""
	var unit1 = _make_unit(2, [_make_model(500, 200)], "Far defender")
	var unit2_override = _make_unit(1, [_make_model(200, 200)], "Attacker override")

	var result = fight_phase._units_in_engagement_range_with_override(unit1, unit2_override)

	assert_false(result, "Units far apart should not be in engagement range")
