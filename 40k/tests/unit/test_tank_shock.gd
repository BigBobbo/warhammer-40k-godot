extends "res://addons/gut/test.gd"

# Tests for TANK SHOCK stratagem implementation
#
# TANK SHOCK (Core – Strategic Ploy Stratagem, 1 CP)
# - WHEN: Your Charge phase, just after a VEHICLE unit ends a Charge move.
# - TARGET: That VEHICLE unit.
# - EFFECT: Select one enemy unit within Engagement Range. Roll a number of D6
#           equal to the Toughness of the VEHICLE (max 6). For each 5+, the
#           enemy unit suffers 1 mortal wound.
# - RESTRICTION: Once per phase.
#
# These tests verify:
# 1. Stratagem definition (name, cost, timing, effects, restrictions)
# 2. Validation (CP, once-per-phase, battle-shocked)
# 3. Unit eligibility (VEHICLE keyword, charged_this_turn)
# 4. Target eligibility (enemy, in Engagement Range, alive)
# 5. Dice rolling (D6 = Toughness, max 6, threshold 5+)
# 6. Mortal wound application (bypasses saves, applies directly, FNP)
# 7. CP deduction
# 8. Usage tracking
# 9. Integration with ChargePhase timing

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_unit(id: String, model_count: int, owner: int = 1, keywords: Array = ["INFANTRY"], toughness: int = 4, wounds_per_model: int = 1, base_mm: int = 32) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": wounds_per_model,
			"current_wounds": wounds_per_model,
			"base_mm": base_mm,
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
			"toughness": toughness,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": 3,
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

func _create_vehicle(id: String, owner: int = 1, toughness: int = 9, wounds: int = 12, base_mm: int = 100) -> Dictionary:
	"""Create a VEHICLE unit for Tank Shock testing."""
	var unit = _create_unit(id, 1, owner, ["VEHICLE"], toughness, wounds, base_mm)
	# Position close to enemy for engagement range
	unit.models[0].position = {"x": 200, "y": 200}
	unit.flags["charged_this_turn"] = true
	return unit

func _setup_tank_shock_scenario() -> void:
	"""Set up a basic Tank Shock scenario: Player 1's VEHICLE in engagement with Player 2's unit."""
	GameState.state.meta.phase = GameStateData.Phase.CHARGE
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Player 1 (attacker) VEHICLE unit - just charged
	var vehicle = _create_vehicle("U_VEHICLE_A", 1, 9, 12)
	GameState.state.units["U_VEHICLE_A"] = vehicle

	# Player 2 (defender) infantry unit - within engagement range (1")
	var enemy_close = _create_unit("U_ENEMY_CLOSE", 5, 2, ["INFANTRY"], 4, 1)
	# Position within 1" (engagement range) — 1" = 40px at 40px/inch
	for i in range(enemy_close.models.size()):
		enemy_close.models[i].position = {"x": 200 + i * 20, "y": 230}
	GameState.state.units["U_ENEMY_CLOSE"] = enemy_close

	# Player 2 (defender) unit - far away (not in engagement range)
	var enemy_far = _create_unit("U_ENEMY_FAR", 3, 2, ["INFANTRY"], 4, 1)
	for i in range(enemy_far.models.size()):
		enemy_far.models[i].position = {"x": 100 + i * 20, "y": 1000}
	GameState.state.units["U_ENEMY_FAR"] = enemy_far

	# Player 2 multi-wound unit for testing damage allocation
	var enemy_tough = _create_unit("U_ENEMY_TOUGH", 3, 2, ["INFANTRY"], 5, 3)
	for i in range(enemy_tough.models.size()):
		enemy_tough.models[i].position = {"x": 200 + i * 20, "y": 230}
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

func test_tank_shock_stratagem_exists():
	"""Test that the TANK SHOCK stratagem is loaded."""
	var strat = StratagemManager.get_stratagem("tank_shock")
	assert_false(strat.is_empty(), "TANK SHOCK stratagem should exist")
	assert_eq(strat.name, "TANK SHOCK")
	assert_eq(strat.cp_cost, 1)

func test_tank_shock_timing():
	"""Test Tank Shock timing: your Charge phase, after charge move."""
	var strat = StratagemManager.get_stratagem("tank_shock")
	assert_eq(strat.timing.turn, "your")
	assert_eq(strat.timing.phase, "charge")
	assert_eq(strat.timing.trigger, "after_charge_move")

func test_tank_shock_effect_definition():
	"""Test that TANK SHOCK has correct effect definition."""
	var strat = StratagemManager.get_stratagem("tank_shock")
	assert_eq(strat.effects.size(), 1)
	assert_eq(strat.effects[0].type, "mortal_wounds_toughness_based")
	assert_eq(strat.effects[0].threshold, 5)
	assert_eq(strat.effects[0].max, 6)

func test_tank_shock_once_per_phase_restriction():
	"""Test that TANK SHOCK has once-per-phase restriction."""
	var strat = StratagemManager.get_stratagem("tank_shock")
	assert_eq(strat.restrictions.once_per, "phase")

func test_tank_shock_target_conditions():
	"""Test target conditions: VEHICLE keyword, charged_this_turn."""
	var strat = StratagemManager.get_stratagem("tank_shock")
	var conditions = strat.target.conditions
	assert_true("keyword:VEHICLE" in conditions, "Should require VEHICLE keyword")
	assert_true("charged_this_turn" in conditions, "Should require charged_this_turn")


# ==========================================
# Validation Tests
# ==========================================

func test_can_use_tank_shock_with_cp():
	"""Test validation passes when player has CP."""
	_setup_tank_shock_scenario()
	var result = StratagemManager.can_use_stratagem(1, "tank_shock", "U_VEHICLE_A")
	assert_true(result.can_use, "Should be able to use Tank Shock with CP: %s" % result.get("reason", ""))

func test_cannot_use_tank_shock_without_cp():
	"""Test validation fails when player has 0 CP."""
	_setup_tank_shock_scenario()
	GameState.state.players["1"]["cp"] = 0
	var result = StratagemManager.can_use_stratagem(1, "tank_shock", "U_VEHICLE_A")
	assert_false(result.can_use, "Should not be able to use Tank Shock without CP")
	assert_true("Not enough CP" in result.reason)

func test_cannot_use_tank_shock_battle_shocked():
	"""Test that battle-shocked vehicles cannot use Tank Shock."""
	_setup_tank_shock_scenario()
	GameState.state.units["U_VEHICLE_A"].flags["battle_shocked"] = true
	var result = StratagemManager.can_use_stratagem(1, "tank_shock", "U_VEHICLE_A")
	assert_false(result.can_use, "Battle-shocked unit should not be targetable by stratagems")

func test_tank_shock_availability_check():
	"""Test is_tank_shock_available quick check."""
	_setup_tank_shock_scenario()
	var result = StratagemManager.is_tank_shock_available(1)
	assert_true(result.available, "Tank Shock should be available for player with CP")

func test_tank_shock_unavailable_no_cp():
	"""Test is_tank_shock_available with no CP."""
	_setup_tank_shock_scenario()
	GameState.state.players["1"]["cp"] = 0
	var result = StratagemManager.is_tank_shock_available(1)
	assert_false(result.available, "Tank Shock should not be available without CP")


# ==========================================
# Target Eligibility Tests
# ==========================================

func test_get_eligible_targets_finds_enemy_in_engagement():
	"""Test that eligible targets includes enemy units within 1\"."""
	_setup_tank_shock_scenario()
	var snapshot = GameState.create_snapshot()
	var targets = StratagemManager.get_tank_shock_eligible_targets("U_VEHICLE_A", snapshot)

	# Should find U_ENEMY_CLOSE and U_ENEMY_TOUGH (both within engagement range)
	var target_ids = []
	for t in targets:
		target_ids.append(t.unit_id)

	assert_true("U_ENEMY_CLOSE" in target_ids, "Should find close enemy unit")
	assert_true("U_ENEMY_TOUGH" in target_ids, "Should find tough enemy unit")

func test_get_eligible_targets_excludes_far_enemy():
	"""Test that eligible targets excludes enemy units beyond engagement range."""
	_setup_tank_shock_scenario()
	var snapshot = GameState.create_snapshot()
	var targets = StratagemManager.get_tank_shock_eligible_targets("U_VEHICLE_A", snapshot)

	var target_ids = []
	for t in targets:
		target_ids.append(t.unit_id)

	assert_false("U_ENEMY_FAR" in target_ids, "Should not find far enemy unit")

func test_get_eligible_targets_excludes_friendly():
	"""Test that eligible targets excludes friendly units."""
	_setup_tank_shock_scenario()
	# Add a friendly unit in engagement range
	var friendly = _create_unit("U_FRIENDLY", 3, 1, ["INFANTRY"], 4, 1)
	for i in range(friendly.models.size()):
		friendly.models[i].position = {"x": 200 + i * 20, "y": 230}
	GameState.state.units["U_FRIENDLY"] = friendly

	var snapshot = GameState.create_snapshot()
	var targets = StratagemManager.get_tank_shock_eligible_targets("U_VEHICLE_A", snapshot)

	var target_ids = []
	for t in targets:
		target_ids.append(t.unit_id)

	assert_false("U_FRIENDLY" in target_ids, "Should not find friendly unit")

func test_get_eligible_targets_excludes_dead_units():
	"""Test that eligible targets excludes destroyed units."""
	_setup_tank_shock_scenario()
	# Kill all models in close enemy
	for model in GameState.state.units["U_ENEMY_CLOSE"].models:
		model.alive = false

	var snapshot = GameState.create_snapshot()
	var targets = StratagemManager.get_tank_shock_eligible_targets("U_VEHICLE_A", snapshot)

	var target_ids = []
	for t in targets:
		target_ids.append(t.unit_id)

	assert_false("U_ENEMY_CLOSE" in target_ids, "Should not find destroyed enemy unit")

func test_eligible_targets_returns_model_count():
	"""Test that eligible targets includes alive model count."""
	_setup_tank_shock_scenario()
	var snapshot = GameState.create_snapshot()
	var targets = StratagemManager.get_tank_shock_eligible_targets("U_VEHICLE_A", snapshot)

	for t in targets:
		if t.unit_id == "U_ENEMY_CLOSE":
			assert_eq(t.model_count, 5, "Close enemy should have 5 alive models")
		elif t.unit_id == "U_ENEMY_TOUGH":
			assert_eq(t.model_count, 3, "Tough enemy should have 3 alive models")


# ==========================================
# Execution Tests
# ==========================================

func test_execute_tank_shock_deducts_cp():
	"""Test that Tank Shock deducts 1 CP from the player."""
	_setup_tank_shock_scenario()
	var initial_cp = GameState.state.players["1"]["cp"]
	StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	var final_cp = GameState.state.players["1"]["cp"]
	assert_eq(final_cp, initial_cp - 1, "Should deduct 1 CP")

func test_execute_tank_shock_returns_success():
	"""Test that execute_tank_shock returns success result."""
	_setup_tank_shock_scenario()
	var result = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_true(result.success, "Tank Shock should succeed")
	assert_true(result.has("dice_rolls"), "Should include dice_rolls")
	assert_true(result.has("mortal_wounds"), "Should include mortal_wounds")
	assert_true(result.has("casualties"), "Should include casualties")
	assert_true(result.has("toughness"), "Should include toughness")
	assert_true(result.has("dice_count"), "Should include dice_count")

func test_execute_tank_shock_rolls_correct_dice_count():
	"""Test that Tank Shock rolls D6 equal to Toughness (max 6)."""
	_setup_tank_shock_scenario()
	# Vehicle has Toughness 9, but max is 6 dice
	var result = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_eq(result.dice_count, 6, "Should roll max 6 dice (T9 capped at 6)")
	assert_eq(result.dice_rolls.size(), 6, "Should have 6 dice results")
	assert_eq(result.toughness, 9, "Should report toughness as 9")

func test_execute_tank_shock_low_toughness():
	"""Test that Tank Shock rolls fewer dice for low toughness vehicles."""
	_setup_tank_shock_scenario()
	# Create a low-toughness vehicle (T4)
	var light_vehicle = _create_vehicle("U_LIGHT_VEHICLE", 1, 4, 6)
	GameState.state.units["U_LIGHT_VEHICLE"] = light_vehicle

	var result = StratagemManager.execute_tank_shock(1, "U_LIGHT_VEHICLE", "U_ENEMY_CLOSE")
	assert_eq(result.dice_count, 4, "Should roll 4 dice for T4 vehicle")
	assert_eq(result.dice_rolls.size(), 4, "Should have 4 dice results")
	assert_eq(result.toughness, 4, "Should report toughness as 4")

func test_execute_tank_shock_mortal_wounds_on_5_plus():
	"""Test that mortal wounds are counted on 5+ rolls."""
	_setup_tank_shock_scenario()
	var result = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")

	# Count manually from the dice_rolls
	var expected_mw = 0
	for roll in result.dice_rolls:
		if roll >= 5:
			expected_mw += 1

	assert_eq(result.mortal_wounds, expected_mw, "Mortal wounds should equal count of 5+ rolls")

func test_execute_tank_shock_once_per_phase():
	"""Test that Tank Shock can only be used once per phase."""
	_setup_tank_shock_scenario()

	# First use should succeed
	var result1 = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_true(result1.success, "First Tank Shock should succeed")

	# Second use should fail
	var result2 = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_TOUGH")
	assert_false(result2.success, "Second Tank Shock should fail (once per phase)")

func test_execute_tank_shock_records_usage():
	"""Test that Tank Shock usage is recorded."""
	_setup_tank_shock_scenario()
	StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")

	# Should not be able to use again this phase
	var validation = StratagemManager.can_use_stratagem(1, "tank_shock", "U_VEHICLE_A")
	assert_false(validation.can_use, "Should not be able to use Tank Shock again this phase")

func test_execute_tank_shock_tracks_active_effect():
	"""Test that Tank Shock is tracked in active effects."""
	_setup_tank_shock_scenario()
	var initial_effects = StratagemManager.active_effects.size()
	StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_eq(StratagemManager.active_effects.size(), initial_effects + 1, "Should add one active effect")

	var last_effect = StratagemManager.active_effects[-1]
	assert_eq(last_effect.stratagem_id, "tank_shock")
	assert_eq(last_effect.player, 1)
	assert_eq(last_effect.target_unit_id, "U_VEHICLE_A")

func test_execute_tank_shock_fails_without_cp():
	"""Test that Tank Shock execution fails without CP."""
	_setup_tank_shock_scenario()
	GameState.state.players["1"]["cp"] = 0
	var result = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_false(result.success, "Should fail without CP")

func test_execute_tank_shock_message():
	"""Test that Tank Shock returns a descriptive message."""
	_setup_tank_shock_scenario()
	var result = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_true(result.message != "", "Should return a message")
	assert_true("TANK SHOCK" in result.message, "Message should mention TANK SHOCK")


# ==========================================
# Mortal Wound Application Tests
# ==========================================

func test_mortal_wounds_kill_single_wound_models():
	"""Test that mortal wounds kill 1-wound models."""
	_setup_tank_shock_scenario()
	# We can't control dice, but we can test the mortal wound application directly
	var board = GameState.create_snapshot()
	var rng = RulesEngine.RNGService.new()
	var mw_result = RulesEngine.apply_mortal_wounds("U_ENEMY_CLOSE", 3, board, rng)

	assert_eq(mw_result.casualties, 3, "3 mortal wounds should kill 3 single-wound models")

func test_mortal_wounds_damage_multi_wound_models():
	"""Test that mortal wounds carry over between multi-wound models."""
	_setup_tank_shock_scenario()
	var board = GameState.create_snapshot()
	var rng = RulesEngine.RNGService.new()

	# U_ENEMY_TOUGH has 3 models with 3 wounds each
	var mw_result = RulesEngine.apply_mortal_wounds("U_ENEMY_TOUGH", 5, board, rng)

	# 5 MW into 3W models: first model takes 3 (dies), second takes 2 (survives)
	assert_eq(mw_result.casualties, 1, "5 mortal wounds should kill 1 three-wound model and wound another")


# ==========================================
# Edge Cases
# ==========================================

func test_tank_shock_with_exactly_1_cp():
	"""Test Tank Shock works with exactly 1 CP."""
	_setup_tank_shock_scenario()
	GameState.state.players["1"]["cp"] = 1
	var result = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_true(result.success, "Should succeed with exactly 1 CP")
	assert_eq(GameState.state.players["1"]["cp"], 0, "Should have 0 CP after use")

func test_tank_shock_no_persistent_flags():
	"""Test that Tank Shock doesn't set persistent flags on units."""
	_setup_tank_shock_scenario()
	StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")

	# Check vehicle unit flags - should not have any stratagem-specific flags
	var vehicle_flags = GameState.state.units["U_VEHICLE_A"].get("flags", {})
	# Tank Shock is instant - no persistent effect flags
	assert_false(vehicle_flags.has("effect_tank_shock"), "Should not set persistent effect flag")

func test_tank_shock_dice_all_valid_range():
	"""Test that all dice rolls are valid D6 values (1-6)."""
	_setup_tank_shock_scenario()
	var result = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	for roll in result.dice_rolls:
		assert_true(roll >= 1 and roll <= 6, "Each die should be 1-6, got %d" % roll)

func test_tank_shock_toughness_6_rolls_6_dice():
	"""Test that T6 vehicle rolls exactly 6 dice."""
	_setup_tank_shock_scenario()
	var t6_vehicle = _create_vehicle("U_T6_VEHICLE", 1, 6, 10)
	GameState.state.units["U_T6_VEHICLE"] = t6_vehicle

	var result = StratagemManager.execute_tank_shock(1, "U_T6_VEHICLE", "U_ENEMY_CLOSE")
	assert_eq(result.dice_count, 6, "T6 should roll 6 dice")
	assert_eq(result.dice_rolls.size(), 6, "Should have 6 dice results")

func test_tank_shock_toughness_3_rolls_3_dice():
	"""Test that T3 vehicle rolls exactly 3 dice."""
	_setup_tank_shock_scenario()
	var t3_vehicle = _create_vehicle("U_T3_VEHICLE", 1, 3, 6)
	GameState.state.units["U_T3_VEHICLE"] = t3_vehicle

	var result = StratagemManager.execute_tank_shock(1, "U_T3_VEHICLE", "U_ENEMY_CLOSE")
	assert_eq(result.dice_count, 3, "T3 should roll 3 dice")
	assert_eq(result.dice_rolls.size(), 3, "Should have 3 dice results")

func test_tank_shock_toughness_12_capped_at_6():
	"""Test that T12 vehicle is capped at 6 dice."""
	_setup_tank_shock_scenario()
	var t12_vehicle = _create_vehicle("U_T12_VEHICLE", 1, 12, 20)
	GameState.state.units["U_T12_VEHICLE"] = t12_vehicle

	var result = StratagemManager.execute_tank_shock(1, "U_T12_VEHICLE", "U_ENEMY_CLOSE")
	assert_eq(result.dice_count, 6, "T12 should be capped at 6 dice")
	assert_eq(result.dice_rolls.size(), 6, "Should have 6 dice results")

func test_both_players_can_use_separately():
	"""Test that both players can each use Tank Shock in the same phase."""
	_setup_tank_shock_scenario()

	# Add a vehicle for player 2
	var p2_vehicle = _create_vehicle("U_P2_VEHICLE", 2, 8, 10)
	GameState.state.units["U_P2_VEHICLE"] = p2_vehicle

	# Add enemy for player 2 (player 1 unit close to player 2's vehicle)
	var p1_close = _create_unit("U_P1_CLOSE", 3, 1, ["INFANTRY"], 4, 1)
	for i in range(p1_close.models.size()):
		p1_close.models[i].position = {"x": 200 + i * 20, "y": 230}
	GameState.state.units["U_P1_CLOSE"] = p1_close

	# Player 1 uses Tank Shock
	var result1 = StratagemManager.execute_tank_shock(1, "U_VEHICLE_A", "U_ENEMY_CLOSE")
	assert_true(result1.success, "Player 1 Tank Shock should succeed")

	# Player 2 uses Tank Shock (different player, once-per-phase is per-player)
	var result2 = StratagemManager.execute_tank_shock(2, "U_P2_VEHICLE", "U_P1_CLOSE")
	assert_true(result2.success, "Player 2 Tank Shock should succeed")
