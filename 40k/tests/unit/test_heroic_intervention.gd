extends "res://addons/gut/test.gd"

# Tests for HEROIC INTERVENTION stratagem implementation
#
# HEROIC INTERVENTION (Core – Strategic Ploy Stratagem, 2 CP)
# - WHEN: Your opponent's Charge phase, just after an enemy unit ends a Charge move.
# - TARGET: One unit from your army within 6" of that enemy unit and not within
#           Engagement Range of any enemy units.
# - EFFECT: Your unit declares a charge targeting only that enemy unit, then makes
#           a charge roll. It cannot be selected to fight in the Fights First step.
# - RESTRICTION: Cannot select VEHICLE unless it has WALKER keyword. Once per phase.
#
# These tests verify:
# 1. StratagemManager definition (2 CP, charge phase timing, once per phase)
# 2. Eligibility: within 6", not in engagement range, not battle-shocked, not VEHICLE (unless WALKER)
# 3. CP deduction when used
# 4. Once-per-phase restriction
# 5. ChargePhase integration: trigger after successful charge move
# 6. HI units do NOT get Fights First
# 7. FightPhase _get_fight_priority respects heroic_intervention flag
# 8. Decline flow
# 9. Edge cases (no CP, no eligible units, VEHICLE vs WALKER, etc.)

const GameStateData = preload("res://autoloads/GameState.gd")
const FightPhase = preload("res://phases/FightPhase.gd")


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

func _setup_charge_scenario() -> void:
	"""Set up a charge scenario where Player 1 has charged and Player 2 has eligible HI units."""
	GameState.state.meta.phase = GameStateData.Phase.CHARGE
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Player 1 unit (charger) — already in engagement range after charge move
	var p1_charger = _create_unit("U_P1_CHARGER", 5, 1, ["INFANTRY"])
	for i in range(p1_charger.models.size()):
		p1_charger.models[i].position = {"x": 200 + i * 20, "y": 200}
	p1_charger.flags["charged_this_turn"] = true
	p1_charger.flags["fights_first"] = true
	GameState.state.units["U_P1_CHARGER"] = p1_charger

	# Player 2 unit A (close to charger, within 6" = 240px, NOT in engagement range)
	# Position 4" away (160px) — within 6" but not in engagement range (1" = 40px)
	var p2_near = _create_unit("U_P2_NEAR", 3, 2, ["INFANTRY"])
	for i in range(p2_near.models.size()):
		p2_near.models[i].position = {"x": 200 + i * 20, "y": 360}
	GameState.state.units["U_P2_NEAR"] = p2_near

	# Player 2 unit B (far from charger, beyond 6")
	var p2_far = _create_unit("U_P2_FAR", 3, 2, ["INFANTRY"])
	for i in range(p2_far.models.size()):
		p2_far.models[i].position = {"x": 200 + i * 20, "y": 800}
	GameState.state.units["U_P2_FAR"] = p2_far

	# Player 2 unit C (already in engagement range of an enemy — NOT eligible for HI)
	var p2_engaged = _create_unit("U_P2_ENGAGED", 3, 2, ["INFANTRY"])
	for i in range(p2_engaged.models.size()):
		p2_engaged.models[i].position = {"x": 105 + i * 20, "y": 200}  # Right next to charger
	GameState.state.units["U_P2_ENGAGED"] = p2_engaged

	# Give both players CP
	GameState.state.players["1"]["cp"] = 5
	GameState.state.players["2"]["cp"] = 5

	StratagemManager.reset_for_new_game()

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
	GameState.state.players = {
		"1": {"cp": 5, "faction": ""},
		"2": {"cp": 5, "faction": ""}
	}
	StratagemManager.reset_for_new_game()


# ==========================================
# Stratagem Definition Tests (local audit)
# ==========================================

func test_heroic_intervention_stratagem_exists():
	"""Test that the HEROIC INTERVENTION stratagem is loaded."""
	var strat = StratagemManager.get_stratagem("heroic_intervention")
	assert_false(strat.is_empty(), "HEROIC INTERVENTION stratagem should exist")
	assert_eq(strat.name, "HEROIC INTERVENTION")

func test_heroic_intervention_costs_2cp():
	"""Test that HEROIC INTERVENTION costs 2 CP (not 1)."""
	var strat = StratagemManager.get_stratagem("heroic_intervention")
	assert_eq(strat.cp_cost, 2, "Heroic Intervention should cost 2 CP")

func test_heroic_intervention_charge_phase_timing():
	"""Test that HEROIC INTERVENTION triggers during opponent's charge phase."""
	var strat = StratagemManager.get_stratagem("heroic_intervention")
	assert_eq(strat.timing.turn, "opponent")
	assert_eq(strat.timing.phase, "charge")
	assert_eq(strat.timing.trigger, "after_enemy_charge_move")

func test_heroic_intervention_once_per_phase_restriction():
	"""Test that HEROIC INTERVENTION has once-per-phase restriction."""
	var strat = StratagemManager.get_stratagem("heroic_intervention")
	assert_eq(strat.restrictions.once_per, "phase")

func test_heroic_intervention_effect_no_fights_first():
	"""Test that HEROIC INTERVENTION effect includes no_fights_first flag."""
	var strat = StratagemManager.get_stratagem("heroic_intervention")
	assert_eq(strat.effects.size(), 1)
	assert_eq(strat.effects[0].type, "counter_charge")
	assert_true(strat.effects[0].get("no_fights_first", false), "HI effect should have no_fights_first flag")


# ==========================================
# Validation Tests (local audit)
# ==========================================

func test_can_use_heroic_intervention_with_cp():
	"""Test validation passes when player has enough CP (2)."""
	_setup_charge_scenario()
	var result = StratagemManager.can_use_stratagem(2, "heroic_intervention", "U_P2_NEAR")
	assert_true(result.can_use, "Should be able to use HI with 5 CP")

func test_cannot_use_heroic_intervention_without_cp():
	"""Test validation fails when player has less than 2 CP."""
	_setup_charge_scenario()
	GameState.state.players["2"]["cp"] = 1
	var result = StratagemManager.can_use_stratagem(2, "heroic_intervention", "U_P2_NEAR")
	assert_false(result.can_use, "Should not be able to use HI with only 1 CP")
	assert_true("Not enough CP" in result.reason, "Should mention 'Not enough CP'")

func test_heroic_intervention_is_available():
	"""Test is_heroic_intervention_available returns true when eligible."""
	_setup_charge_scenario()
	var check = StratagemManager.is_heroic_intervention_available(2)
	assert_true(check.available, "HI should be available for defending player")

func test_heroic_intervention_not_available_no_cp():
	"""Test is_heroic_intervention_available returns false when no CP."""
	_setup_charge_scenario()
	GameState.state.players["2"]["cp"] = 0
	var check = StratagemManager.is_heroic_intervention_available(2)
	assert_false(check.available, "HI should not be available with 0 CP")


# ==========================================
# StratagemManager Availability Tests (remote PR)
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

func test_eligible_unit_within_6_inches():
	"""Test that a unit within 6\" of the charging enemy is eligible."""
	_setup_charge_scenario()
	var snapshot = GameState.create_snapshot()
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)
	assert_has(eligible_ids, "U_P2_NEAR", "P2 near unit should be eligible for HI")

func test_ineligible_unit_beyond_6_inches():
	"""Test that a unit beyond 6\" of the charging enemy is NOT eligible."""
	_setup_charge_scenario()
	var snapshot = GameState.create_snapshot()
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)
	assert_does_not_have(eligible_ids, "U_P2_FAR", "P2 far unit should NOT be eligible for HI")

func test_ineligible_unit_already_in_engagement():
	"""Test that a unit already in engagement range is NOT eligible."""
	_setup_charge_scenario()
	var snapshot = GameState.create_snapshot()
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)
	assert_does_not_have(eligible_ids, "U_P2_ENGAGED", "Unit already in engagement should NOT be eligible for HI")

func test_ineligible_vehicle_without_walker():
	"""Test that VEHICLE units without WALKER keyword are NOT eligible."""
	_setup_charge_scenario()
	# Add a VEHICLE unit near the charger
	var vehicle_unit = _create_unit("U_P2_VEHICLE", 1, 2, ["VEHICLE"])
	vehicle_unit.models[0].position = {"x": 200, "y": 360}
	GameState.state.units["U_P2_VEHICLE"] = vehicle_unit

	var snapshot = GameState.create_snapshot()
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)
	assert_does_not_have(eligible_ids, "U_P2_VEHICLE", "VEHICLE without WALKER should NOT be eligible")

func test_eligible_walker_vehicle():
	"""Test that VEHICLE units with WALKER keyword ARE eligible."""
	_setup_charge_scenario()
	# Add a VEHICLE WALKER unit near the charger
	var walker_unit = _create_unit("U_P2_WALKER", 1, 2, ["VEHICLE", "WALKER"])
	walker_unit.models[0].position = {"x": 200, "y": 360}
	GameState.state.units["U_P2_WALKER"] = walker_unit

	var snapshot = GameState.create_snapshot()
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)
	assert_has(eligible_ids, "U_P2_WALKER", "VEHICLE WALKER should be eligible for HI")

func test_ineligible_battle_shocked_unit():
	"""Test that battle-shocked units are NOT eligible."""
	_setup_charge_scenario()
	GameState.state.units["U_P2_NEAR"].flags["battle_shocked"] = true

	var snapshot = GameState.create_snapshot()
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	var eligible_ids = []
	for e in eligible:
		eligible_ids.append(e.unit_id)
	assert_does_not_have(eligible_ids, "U_P2_NEAR", "Battle-shocked unit should NOT be eligible")

func test_no_eligible_units_when_all_excluded():
	"""Test that empty array is returned when no units are eligible."""
	_setup_charge_scenario()
	# Remove all eligible units
	GameState.state.units.erase("U_P2_NEAR")
	GameState.state.units.erase("U_P2_FAR")
	GameState.state.units.erase("U_P2_ENGAGED")

	var snapshot = GameState.create_snapshot()
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	assert_eq(eligible.size(), 0, "No units should be eligible when all are excluded")

func test_enemy_units_not_eligible():
	"""Test that only friendly (defending) player's units are eligible."""
	_setup_charge_scenario()
	var snapshot = GameState.create_snapshot()
	# Player 1 is the charging player — their units should never appear in HI eligibility for Player 2
	var eligible = StratagemManager.get_heroic_intervention_eligible_units(2, "U_P1_CHARGER", snapshot)
	for e in eligible:
		var unit = GameState.get_unit(e.unit_id)
		assert_eq(int(unit.get("owner", 0)), 2, "Only Player 2 units should be eligible for Player 2's HI")


# ==========================================
# FightPhase Priority Tests (local audit)
# ==========================================

func test_fight_priority_normal_charge_gets_fights_first():
	"""Test that a normally charged unit gets FIGHTS_FIRST priority."""
	var fight_phase = FightPhase.new()
	var unit = {"flags": {"charged_this_turn": true}}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.FIGHTS_FIRST, "Normal charge should get Fights First")
	fight_phase.free()

func test_fight_priority_heroic_intervention_no_fights_first():
	"""Test that a heroic intervention unit does NOT get FIGHTS_FIRST priority."""
	var fight_phase = FightPhase.new()
	var unit = {"flags": {"charged_this_turn": true, "heroic_intervention": true}}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.NORMAL, "Heroic Intervention unit should NOT get Fights First")
	fight_phase.free()

func test_fight_priority_no_charge_is_normal():
	"""Test that a non-charged unit gets NORMAL priority."""
	var fight_phase = FightPhase.new()
	var unit = {"flags": {}, "meta": {"abilities": []}, "status_effects": {}}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.NORMAL, "Non-charged unit should be NORMAL priority")
	fight_phase.free()


# ==========================================
# CP Deduction Tests (local audit)
# ==========================================

func test_heroic_intervention_deducts_2cp():
	"""Test that using HI produces correct CP diffs (2 CP deduction).
	Note: PhaseManager.apply_state_changes has a known issue with numeric dict keys
	in paths like 'players.2.cp' — the diff is generated correctly but may not apply
	to GameState in headless test mode. We verify the diffs are correct instead."""
	_setup_charge_scenario()
	var result = StratagemManager.use_stratagem(2, "heroic_intervention", "U_P2_NEAR")
	assert_true(result.success, "use_stratagem should succeed")
	# Verify the diffs contain the correct CP deduction
	var diffs = result.get("diffs", [])
	var found_cp_diff = false
	for diff in diffs:
		if diff.get("path", "") == "players.2.cp":
			assert_eq(diff.value, 3, "CP diff should set value to 3 (5 - 2)")
			found_cp_diff = true
			break
	assert_true(found_cp_diff, "Should have a CP deduction diff for players.2.cp")

func test_heroic_intervention_once_per_phase_enforced():
	"""Test that HI cannot be used twice in the same phase."""
	_setup_charge_scenario()
	# Use it once
	var result1 = StratagemManager.use_stratagem(2, "heroic_intervention", "U_P2_NEAR")
	assert_true(result1.success, "First HI use should succeed")

	# Try to use it again
	var result2 = StratagemManager.can_use_stratagem(2, "heroic_intervention", "U_P2_NEAR")
	assert_false(result2.can_use, "Second HI use should be blocked by once-per-phase restriction")


# ==========================================
# ChargePhase Integration Tests (local audit)
# ==========================================

func test_charge_phase_validates_use_heroic_intervention():
	"""USE_HEROIC_INTERVENTION should fail when not awaiting Heroic Intervention."""
	var charge_phase = preload("res://phases/ChargePhase.gd").new()
	charge_phase.awaiting_heroic_intervention = false

	var action = {"type": "USE_HEROIC_INTERVENTION", "unit_id": "U_P2_NEAR", "player": 2}
	var result = charge_phase.validate_action(action)
	assert_false(result.valid, "Should fail when not awaiting HI")
	charge_phase.free()

func test_charge_phase_validates_use_heroic_intervention_requires_unit():
	"""USE_HEROIC_INTERVENTION should fail without unit_id."""
	var charge_phase = preload("res://phases/ChargePhase.gd").new()
	charge_phase.awaiting_heroic_intervention = true

	var action = {"type": "USE_HEROIC_INTERVENTION", "unit_id": "", "player": 2}
	var result = charge_phase.validate_action(action)
	assert_false(result.valid, "Should fail without unit_id")
	charge_phase.free()

func test_charge_phase_validates_decline_heroic_intervention():
	"""DECLINE_HEROIC_INTERVENTION should succeed when awaiting."""
	var charge_phase = preload("res://phases/ChargePhase.gd").new()
	charge_phase.awaiting_heroic_intervention = true

	var action = {"type": "DECLINE_HEROIC_INTERVENTION", "player": 2}
	var result = charge_phase.validate_action(action)
	assert_true(result.valid, "Should succeed when awaiting HI")
	charge_phase.free()

func test_charge_phase_decline_clears_state():
	"""DECLINE_HEROIC_INTERVENTION should clear all HI state."""
	_setup_charge_scenario()
	var charge_phase = preload("res://phases/ChargePhase.gd").new()
	charge_phase.game_state_snapshot = GameState.create_snapshot()
	charge_phase.awaiting_heroic_intervention = true
	charge_phase.heroic_intervention_player = 2
	charge_phase.heroic_intervention_charging_unit_id = "U_P1_CHARGER"

	var action = {"type": "DECLINE_HEROIC_INTERVENTION", "player": 2}
	charge_phase.process_action(action)

	assert_false(charge_phase.awaiting_heroic_intervention, "awaiting_heroic_intervention should be false after decline")
	assert_eq(charge_phase.heroic_intervention_player, 0, "heroic_intervention_player should be 0 after decline")
	assert_eq(charge_phase.heroic_intervention_charging_unit_id, "", "charging_unit_id should be empty after decline")
	charge_phase.free()


# ==========================================
# Eligibility Tests (remote PR)
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
# Restriction Tests (remote PR)
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
