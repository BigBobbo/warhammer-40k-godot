extends "res://addons/gut/test.gd"

# Tests for GRENADE stratagem implementation
#
# GRENADE (Core – Wargear Stratagem, 1 CP)
# - WHEN: Your Shooting phase.
# - TARGET: One GRENADES unit from your army that has not Advanced, Fallen Back,
#           shot this phase, or is in Engagement Range.
# - EFFECT: Select one enemy unit within 8" and visible. Roll six D6: for each 4+,
#           that enemy unit suffers 1 mortal wound.
# - RESTRICTION: Once per phase.
#
# These tests verify:
# 1. StratagemManager validation for GRENADE
# 2. CP deduction when used
# 3. Once-per-phase restriction
# 4. Unit eligibility (GRENADES keyword, not advanced, not fell back, not shot, not in engagement)
# 5. Target eligibility (enemy, within 8", alive)
# 6. Dice rolling (6D6, 4+ threshold)
# 7. Mortal wound application (bypasses saves, applies directly)
# 8. Casualty tracking
# 9. Unit marked as has_shot after using grenade
# 10. RulesEngine mortal wound application

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_unit(id: String, model_count: int, owner: int = 1, keywords: Array = ["INFANTRY", "GRENADES"], save: int = 3, toughness: int = 4, wounds_per_model: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": wounds_per_model,
			"current_wounds": wounds_per_model,
			"base_mm": 32,
			"position": {"x": 100 + i * 20, "y": 100},
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
				"wounds": wounds_per_model,
				"leadership": 7,
				"objective_control": 1
			},
			"weapons": [],
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _setup_grenade_scenario() -> void:
	"""Set up a basic grenade scenario: Player 1's GRENADES unit near Player 2's unit."""
	GameState.state.meta.phase = GameStateData.Phase.SHOOTING
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Player 1 (attacker) GRENADES unit - close to enemy
	var grenade_unit = _create_unit("U_GRENADE_A", 5, 1, ["INFANTRY", "GRENADES"])
	GameState.state.units["U_GRENADE_A"] = grenade_unit

	# Player 1 unit WITHOUT GRENADES keyword
	var non_grenade_unit = _create_unit("U_NO_GRENADE", 5, 1, ["INFANTRY"])
	GameState.state.units["U_NO_GRENADE"] = non_grenade_unit

	# Player 2 (defender) unit - close by (within 8")
	var enemy_close = _create_unit("U_ENEMY_CLOSE", 5, 2, ["INFANTRY"])
	# Position within 8" of grenade unit (8" = 320px at 40px/inch)
	for i in range(enemy_close.models.size()):
		enemy_close.models[i].position = {"x": 100 + i * 20, "y": 300}
	GameState.state.units["U_ENEMY_CLOSE"] = enemy_close

	# Player 2 (defender) unit - far away (beyond 8")
	var enemy_far = _create_unit("U_ENEMY_FAR", 3, 2, ["INFANTRY"])
	for i in range(enemy_far.models.size()):
		enemy_far.models[i].position = {"x": 100 + i * 20, "y": 1000}
	GameState.state.units["U_ENEMY_FAR"] = enemy_far

	# Player 2 multi-wound unit for testing damage allocation
	var enemy_tough = _create_unit("U_ENEMY_TOUGH", 3, 2, ["INFANTRY"], 3, 4, 3)
	for i in range(enemy_tough.models.size()):
		enemy_tough.models[i].position = {"x": 100 + i * 20, "y": 300}
	GameState.state.units["U_ENEMY_TOUGH"] = enemy_tough

	# Give both players CP
	GameState.state.players["1"]["cp"] = 5
	GameState.state.players["2"]["cp"] = 5

	StratagemManager.reset_for_new_game()

func before_each():
	# Clear game state units before each test
	GameState.state.units = {}
	GameState.state.players = {
		"1": {"cp": 5, "faction": ""},
		"2": {"cp": 5, "faction": ""}
	}
	StratagemManager.reset_for_new_game()


# ==========================================
# Stratagem Definition Tests
# ==========================================

func test_grenade_stratagem_exists():
	"""Test that the GRENADE stratagem is loaded."""
	var strat = StratagemManager.get_stratagem("grenade")
	assert_false(strat.is_empty(), "GRENADE stratagem should exist")
	assert_eq(strat.name, "GRENADE")
	assert_eq(strat.cp_cost, 1)
	assert_eq(strat.timing.turn, "your")
	assert_eq(strat.timing.phase, "shooting")

func test_grenade_effect_definition():
	"""Test that GRENADE has correct effect definition."""
	var strat = StratagemManager.get_stratagem("grenade")
	assert_eq(strat.effects.size(), 1)
	assert_eq(strat.effects[0].type, "mortal_wounds")
	assert_eq(strat.effects[0].dice, 6)
	assert_eq(strat.effects[0].threshold, 4)

func test_grenade_once_per_phase_restriction():
	"""Test that GRENADE has once-per-phase restriction."""
	var strat = StratagemManager.get_stratagem("grenade")
	assert_eq(strat.restrictions.once_per, "phase")


# ==========================================
# Validation Tests
# ==========================================

func test_can_use_grenade_with_cp():
	"""Test validation passes when player has CP."""
	_setup_grenade_scenario()
	var result = StratagemManager.can_use_stratagem(1, "grenade", "U_GRENADE_A")
	assert_true(result.can_use, "Should be able to use GRENADE with 5 CP")

func test_cannot_use_grenade_without_cp():
	"""Test validation fails when player has 0 CP."""
	_setup_grenade_scenario()
	GameState.state.players["1"]["cp"] = 0
	var result = StratagemManager.can_use_stratagem(1, "grenade", "U_GRENADE_A")
	assert_false(result.can_use, "Should not be able to use GRENADE with 0 CP")
	assert_string_contains(result.reason, "Not enough CP")

func test_cannot_use_grenade_on_battle_shocked_unit():
	"""Test validation fails when grenade unit is battle-shocked."""
	_setup_grenade_scenario()
	GameState.state.units["U_GRENADE_A"].flags["battle_shocked"] = true
	var result = StratagemManager.can_use_stratagem(1, "grenade", "U_GRENADE_A")
	assert_false(result.can_use, "Should not be able to use GRENADE on battle-shocked unit")


# ==========================================
# Unit Eligibility Tests
# ==========================================

func test_get_grenade_eligible_units_with_grenades_keyword():
	"""Test that units with GRENADES keyword are eligible."""
	_setup_grenade_scenario()
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_GRENADE_A":
			found = true
			break
	assert_true(found, "Unit with GRENADES keyword should be eligible")

func test_get_grenade_eligible_units_without_grenades_keyword():
	"""Test that units WITHOUT GRENADES keyword are not eligible."""
	_setup_grenade_scenario()
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_NO_GRENADE":
			found = true
			break
	assert_false(found, "Unit without GRENADES keyword should NOT be eligible")

func test_advanced_unit_not_eligible():
	"""Test that units that Advanced are not eligible."""
	_setup_grenade_scenario()
	GameState.state.units["U_GRENADE_A"].flags["advanced"] = true
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_GRENADE_A":
			found = true
			break
	assert_false(found, "Advanced unit should NOT be eligible for GRENADE")

func test_fell_back_unit_not_eligible():
	"""Test that units that Fell Back are not eligible."""
	_setup_grenade_scenario()
	GameState.state.units["U_GRENADE_A"].flags["fell_back"] = true
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_GRENADE_A":
			found = true
			break
	assert_false(found, "Fell-back unit should NOT be eligible for GRENADE")

func test_already_shot_unit_not_eligible():
	"""Test that units that have shot are not eligible."""
	_setup_grenade_scenario()
	GameState.state.units["U_GRENADE_A"].flags["has_shot"] = true
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_GRENADE_A":
			found = true
			break
	assert_false(found, "Unit that has shot should NOT be eligible for GRENADE")

func test_in_engagement_unit_not_eligible():
	"""Test that units in Engagement Range are not eligible."""
	_setup_grenade_scenario()
	GameState.state.units["U_GRENADE_A"].flags["in_engagement"] = true
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_GRENADE_A":
			found = true
			break
	assert_false(found, "Unit in engagement should NOT be eligible for GRENADE")

func test_battle_shocked_unit_not_eligible():
	"""Test that battle-shocked units are not eligible."""
	_setup_grenade_scenario()
	GameState.state.units["U_GRENADE_A"].flags["battle_shocked"] = true
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_GRENADE_A":
			found = true
			break
	assert_false(found, "Battle-shocked unit should NOT be eligible for GRENADE")


# ==========================================
# Target Eligibility Tests
# ==========================================

func test_get_grenade_eligible_targets_within_range():
	"""Test that enemy units within 8\" are eligible targets."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	var targets = RulesEngine.get_grenade_eligible_targets("U_GRENADE_A", board)
	var found_close = false
	for target in targets:
		if target.unit_id == "U_ENEMY_CLOSE":
			found_close = true
			break
	assert_true(found_close, "Enemy unit within 8\" should be an eligible target")

func test_get_grenade_eligible_targets_beyond_range():
	"""Test that enemy units beyond 8\" are not eligible targets."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	var targets = RulesEngine.get_grenade_eligible_targets("U_GRENADE_A", board)
	var found_far = false
	for target in targets:
		if target.unit_id == "U_ENEMY_FAR":
			found_far = true
			break
	assert_false(found_far, "Enemy unit beyond 8\" should NOT be an eligible target")

func test_get_grenade_eligible_targets_excludes_friendly():
	"""Test that friendly units are not eligible targets."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	var targets = RulesEngine.get_grenade_eligible_targets("U_GRENADE_A", board)
	for target in targets:
		var unit = GameState.get_unit(target.unit_id)
		assert_ne(unit.get("owner", 0), 1, "Friendly units should not be in target list")

func test_get_grenade_eligible_targets_excludes_destroyed():
	"""Test that destroyed units are not eligible targets."""
	_setup_grenade_scenario()
	# Kill all models in enemy close unit
	for model in GameState.state.units["U_ENEMY_CLOSE"].models:
		model.alive = false
	var board = GameState.create_snapshot()
	var targets = RulesEngine.get_grenade_eligible_targets("U_GRENADE_A", board)
	var found_close = false
	for target in targets:
		if target.unit_id == "U_ENEMY_CLOSE":
			found_close = true
			break
	assert_false(found_close, "Destroyed unit should NOT be an eligible target")


# ==========================================
# Execution Tests
# ==========================================

func test_execute_grenade_deducts_cp():
	"""Test that using GRENADE deducts 1 CP."""
	_setup_grenade_scenario()
	var initial_cp = GameState.state.players["1"]["cp"]
	StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	var final_cp = GameState.state.players["1"]["cp"]
	assert_eq(final_cp, initial_cp - 1, "GRENADE should deduct 1 CP")

func test_execute_grenade_returns_success():
	"""Test that execute_grenade returns success."""
	_setup_grenade_scenario()
	var result = StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	assert_true(result.success, "execute_grenade should return success")

func test_execute_grenade_returns_dice_rolls():
	"""Test that execute_grenade returns 6 dice rolls."""
	_setup_grenade_scenario()
	var result = StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	assert_eq(result.dice_rolls.size(), 6, "Should roll exactly 6 dice")
	for roll in result.dice_rolls:
		assert_gte(roll, 1, "Each die should be at least 1")
		assert_lte(roll, 6, "Each die should be at most 6")

func test_execute_grenade_mortal_wounds_count():
	"""Test that mortal wounds count matches 4+ rolls."""
	_setup_grenade_scenario()
	var result = StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	var expected_mw = 0
	for roll in result.dice_rolls:
		if roll >= 4:
			expected_mw += 1
	assert_eq(result.mortal_wounds, expected_mw, "Mortal wounds should match count of 4+ rolls")

func test_execute_grenade_marks_unit_as_shot():
	"""Test that grenade unit is marked as has_shot."""
	_setup_grenade_scenario()
	StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	var unit = GameState.get_unit("U_GRENADE_A")
	assert_true(unit.get("flags", {}).get("has_shot", false), "Grenade unit should be marked as has_shot")

func test_execute_grenade_once_per_phase():
	"""Test that GRENADE can only be used once per phase."""
	_setup_grenade_scenario()
	# Use grenade first time
	var result1 = StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	assert_true(result1.success, "First GRENADE use should succeed")

	# Try to use again (should fail due to once-per-phase restriction)
	# We need another eligible unit to test this
	var grenade_unit2 = _create_unit("U_GRENADE_B", 5, 1, ["INFANTRY", "GRENADES"])
	GameState.state.units["U_GRENADE_B"] = grenade_unit2
	var result2 = StratagemManager.execute_grenade(1, "U_GRENADE_B", "U_ENEMY_CLOSE")
	assert_false(result2.success, "Second GRENADE use should fail (once per phase)")

func test_execute_grenade_fails_without_cp():
	"""Test that execute_grenade fails when player has 0 CP."""
	_setup_grenade_scenario()
	GameState.state.players["1"]["cp"] = 0
	var result = StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	assert_false(result.success, "GRENADE should fail with 0 CP")


# ==========================================
# Mortal Wound Application Tests
# ==========================================

func test_apply_mortal_wounds_single_wound_models():
	"""Test mortal wounds kill 1-wound models (1 MW = 1 dead model)."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	var result = RulesEngine.apply_mortal_wounds("U_ENEMY_CLOSE", 3, board)
	assert_eq(result.casualties, 3, "3 mortal wounds should kill 3 one-wound models")
	assert_eq(result.wounds_applied, 3, "Should apply 3 wounds")

func test_apply_mortal_wounds_multi_wound_models():
	"""Test mortal wounds distribute across multi-wound models."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	# 3 models with 3 wounds each; 4 mortal wounds should wound 1 model and kill 1
	var result = RulesEngine.apply_mortal_wounds("U_ENEMY_TOUGH", 4, board)
	# 3 damage kills first model (3W), 1 damage wounds second model (2W remaining)
	assert_eq(result.casualties, 1, "4 MW against 3W models should kill 1 model")
	assert_eq(result.wounds_applied, 4)

func test_apply_mortal_wounds_zero():
	"""Test applying 0 mortal wounds causes no damage."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	var result = RulesEngine.apply_mortal_wounds("U_ENEMY_CLOSE", 0, board)
	assert_eq(result.casualties, 0, "0 mortal wounds should cause 0 casualties")
	assert_eq(result.wounds_applied, 0)

func test_apply_mortal_wounds_returns_diffs():
	"""Test that mortal wound application returns correct diffs."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	var result = RulesEngine.apply_mortal_wounds("U_ENEMY_CLOSE", 2, board)
	assert_gt(result.diffs.size(), 0, "Should return diffs for wound application")
	# Check that diffs contain the expected paths
	var has_wounds_diff = false
	var has_alive_diff = false
	for diff in result.diffs:
		if "current_wounds" in diff.path:
			has_wounds_diff = true
		if "alive" in diff.path:
			has_alive_diff = true
	assert_true(has_wounds_diff, "Should have wound diffs")
	assert_true(has_alive_diff, "Should have alive diffs for killed models")

func test_apply_mortal_wounds_to_destroyed_unit():
	"""Test applying mortal wounds to a fully destroyed unit does nothing."""
	_setup_grenade_scenario()
	for model in GameState.state.units["U_ENEMY_CLOSE"].models:
		model.alive = false
		model.current_wounds = 0
	var board = GameState.create_snapshot()
	var result = RulesEngine.apply_mortal_wounds("U_ENEMY_CLOSE", 3, board)
	assert_eq(result.casualties, 0, "No casualties on already destroyed unit")
	assert_eq(result.wounds_applied, 0, "No wounds applied to destroyed unit")

func test_apply_mortal_wounds_excess_damage():
	"""Test that excess mortal wounds don't cause issues."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	# 5 one-wound models, 10 mortal wounds
	var result = RulesEngine.apply_mortal_wounds("U_ENEMY_CLOSE", 10, board)
	assert_eq(result.casualties, 5, "Can't kill more models than exist")

func test_apply_mortal_wounds_invalid_unit():
	"""Test applying mortal wounds to non-existent unit."""
	_setup_grenade_scenario()
	var board = GameState.create_snapshot()
	var result = RulesEngine.apply_mortal_wounds("NONEXISTENT", 3, board)
	assert_eq(result.casualties, 0)
	assert_eq(result.diffs.size(), 0)


# ==========================================
# Integration Tests
# ==========================================

func test_grenade_full_flow():
	"""Test the full grenade flow: eligible units -> execute -> damage applied."""
	_setup_grenade_scenario()

	# 1. Check eligible units
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	assert_gt(eligible.size(), 0, "Should have eligible grenade units")

	# 2. Check eligible targets
	var board = GameState.create_snapshot()
	var targets = RulesEngine.get_grenade_eligible_targets("U_GRENADE_A", board)
	assert_gt(targets.size(), 0, "Should have eligible targets")

	# 3. Execute grenade
	var result = StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	assert_true(result.success)
	assert_eq(result.dice_rolls.size(), 6)

	# 4. Verify CP deducted
	assert_eq(GameState.state.players["1"]["cp"], 4)

	# 5. Verify unit marked as shot
	assert_true(GameState.get_unit("U_GRENADE_A").flags.get("has_shot", false))

	# 6. Verify mortal wounds match dice
	var expected_mw = 0
	for roll in result.dice_rolls:
		if roll >= 4:
			expected_mw += 1
	assert_eq(result.mortal_wounds, expected_mw)

func test_grenade_unit_no_longer_eligible_after_use():
	"""Test that grenade unit is no longer eligible after using grenade."""
	_setup_grenade_scenario()
	StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	var eligible = StratagemManager.get_grenade_eligible_units(1)
	var found = false
	for unit in eligible:
		if unit.unit_id == "U_GRENADE_A":
			found = true
			break
	assert_false(found, "Unit should NOT be eligible after using GRENADE (marked as has_shot)")

func test_grenade_message_format():
	"""Test that the result message is properly formatted."""
	_setup_grenade_scenario()
	var result = StratagemManager.execute_grenade(1, "U_GRENADE_A", "U_ENEMY_CLOSE")
	assert_true(result.message.length() > 0, "Should have a non-empty message")
	assert_string_contains(result.message, "GRENADE")
