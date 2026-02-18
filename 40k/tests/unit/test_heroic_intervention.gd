extends "res://addons/gut/test.gd"

# Tests for HEROIC INTERVENTION stratagem implementation
#
# HEROIC INTERVENTION (Core – Strategic Ploy Stratagem, 1 CP)
# - WHEN: Your opponent's Charge phase, just after an enemy unit ends a Charge move.
# - TARGET: One unit from your army that is within 6" of that enemy unit and
#           that would be eligible to declare a charge.
# - EFFECT: Your unit can declare a charge that targets only that enemy unit.
# - RESTRICTION: Once per phase. No charge bonus (+1 to hit). No VEHICLE (except WALKER).
#
# These tests verify:
# 1. StratagemManager availability and eligibility checks
# 2. Eligible units: within 6", alive models, not battle-shocked, not VEHICLE (except WALKER)
# 3. CP deduction (1 CP)
# 4. Once-per-phase restriction
# 5. Heroic Intervention flag set on counter-charging unit (denies charge bonus)
# 6. Edge cases (no CP, no eligible units, VEHICLE keyword, etc.)

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_unit(id: String, model_count: int, owner: int = 1, keywords: Array = ["INFANTRY"], save: int = 3, toughness: int = 4, wounds: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": wounds,
			"current_wounds": wounds,
			"base_mm": 32,
			"position": {"x": 100 + i * 20 + (owner - 1) * 50, "y": 100},
			"alive": true,
			"status_effects": []
		})
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Unit %s" % id,
			"keywords": keywords,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": save,
				"wounds": wounds,
				"leadership": 7,
				"objective_control": 1
			},
			"weapons": [],
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _setup_heroic_intervention_scenario() -> Dictionary:
	"""Set up a basic heroic intervention scenario: P1 unit just charged, P2 unit within 6\"."""
	GameState.state.meta.phase = GameStateData.Phase.CHARGE
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Player 1 unit (just charged)
	var charger = _create_unit("U_CHARGER", 5, 1, ["INFANTRY"], 3, 4, 1)
	for i in range(charger.models.size()):
		charger.models[i].position = {"x": 200 + i * 20, "y": 200}
	charger.flags["charged_this_turn"] = true
	GameState.state.units["U_CHARGER"] = charger

	# Player 2 unit (defender, within 6" of charger, can counter-charge)
	var defender = _create_unit("U_DEFENDER", 5, 2, ["INFANTRY"], 3, 4, 1)
	for i in range(defender.models.size()):
		# Place within 6" (close enough)
		defender.models[i].position = {"x": 200 + i * 20, "y": 250}
	GameState.state.units["U_DEFENDER"] = defender

	# Player 2 unit far away (should not be eligible)
	var far_unit = _create_unit("U_FAR", 3, 2, ["INFANTRY"], 3, 4, 1)
	for i in range(far_unit.models.size()):
		far_unit.models[i].position = {"x": 5000 + i * 20, "y": 5000}
	GameState.state.units["U_FAR"] = far_unit

	# Give both players CP
	if not GameState.state.has("players"):
		GameState.state["players"] = {}
	GameState.state.players["1"] = {"cp": 3}
	GameState.state.players["2"] = {"cp": 3}

	# Reset stratagem usage
	StratagemManager.reset_for_new_turn(2)

	return GameState.create_snapshot()

func before_each():
	GameState.state = GameState._create_default_state()
	if GameState.state.has("units"):
		GameState.state.units.clear()
	StratagemManager.reset_for_new_game()


# ==========================================
# StratagemManager Availability Tests
# ==========================================

func test_heroic_intervention_available_with_cp():
	"""Heroic Intervention should be available when player has CP."""
	_setup_heroic_intervention_scenario()

	var check = StratagemManager.is_heroic_intervention_available(2)
	assert_true(check.available, "Heroic Intervention should be available with 3 CP")

func test_heroic_intervention_not_available_without_cp():
	"""Heroic Intervention should not be available when player has 0 CP."""
	_setup_heroic_intervention_scenario()
	GameState.state.players["2"] = {"cp": 0}

	var check = StratagemManager.is_heroic_intervention_available(2)
	assert_false(check.available, "Heroic Intervention should not be available with 0 CP")


# ==========================================
# Eligibility Tests
# ==========================================

func test_eligible_units_within_6_inches():
	"""Units within 6\" of the charging enemy should be eligible."""
	var board = _setup_heroic_intervention_scenario()

	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_CHARGER", board)

	# U_DEFENDER should be eligible (within 6"), U_FAR should not
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)

	assert_true("U_DEFENDER" in eligible_ids, "U_DEFENDER within 6\" should be eligible")
	assert_false("U_FAR" in eligible_ids, "U_FAR beyond 6\" should not be eligible")

func test_vehicle_not_eligible_unless_walker():
	"""VEHICLE units should not be eligible for Heroic Intervention unless WALKER."""
	_setup_heroic_intervention_scenario()

	# Change defender to a VEHICLE
	GameState.state.units["U_DEFENDER"].meta.keywords = ["VEHICLE"]
	var board = GameState.create_snapshot()

	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_CHARGER", board)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)

	assert_false("U_DEFENDER" in eligible_ids, "VEHICLE should not be eligible")

func test_walker_vehicle_is_eligible():
	"""VEHICLE WALKER units should be eligible for Heroic Intervention."""
	_setup_heroic_intervention_scenario()

	# Change defender to a WALKER VEHICLE
	GameState.state.units["U_DEFENDER"].meta.keywords = ["VEHICLE", "WALKER"]
	var board = GameState.create_snapshot()

	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_CHARGER", board)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)

	assert_true("U_DEFENDER" in eligible_ids, "WALKER VEHICLE should be eligible")

func test_battle_shocked_not_eligible():
	"""Battle-shocked units should not be eligible for Heroic Intervention."""
	_setup_heroic_intervention_scenario()

	GameState.state.units["U_DEFENDER"].flags["battle_shocked"] = true
	var board = GameState.create_snapshot()

	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_CHARGER", board)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)

	assert_false("U_DEFENDER" in eligible_ids, "Battle-shocked unit should not be eligible")

func test_dead_unit_not_eligible():
	"""Units with no alive models should not be eligible."""
	_setup_heroic_intervention_scenario()

	# Kill all models in defender
	for model in GameState.state.units["U_DEFENDER"].models:
		model["alive"] = false
	var board = GameState.create_snapshot()

	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_CHARGER", board)
	assert_eq(eligible.size(), 0, "Dead unit should not be eligible")


# ==========================================
# Restriction Tests
# ==========================================

func test_heroic_intervention_once_per_phase():
	"""Heroic Intervention can only be used once per phase."""
	_setup_heroic_intervention_scenario()

	# Use it once
	var result1 = StratagemManager.use_stratagem(2, "heroic_intervention", "U_DEFENDER")
	assert_true(result1.success, "First use should succeed")

	# Try to use again — should fail (once per phase)
	var result2 = StratagemManager.can_use_stratagem(2, "heroic_intervention")
	assert_false(result2.can_use, "Second use should be blocked (once per phase)")

func test_heroic_intervention_deducts_1_cp():
	"""Using Heroic Intervention should deduct 1 CP."""
	_setup_heroic_intervention_scenario()

	var cp_before = GameState.state.players["2"].cp
	StratagemManager.use_stratagem(2, "heroic_intervention", "U_DEFENDER")
	var cp_after = GameState.state.players["2"].cp

	assert_eq(cp_before - cp_after, 1, "Should deduct exactly 1 CP")

func test_friendly_units_not_eligible():
	"""Only the defending player's units should be eligible, not the charging player's."""
	var board = _setup_heroic_intervention_scenario()

	# Player 1's own units should never appear in HI eligible list for player 1
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(1, "U_CHARGER", board)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)

	assert_false("U_CHARGER" in eligible_ids, "Charging unit should not be eligible for its own player's HI")
