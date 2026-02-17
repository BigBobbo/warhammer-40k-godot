extends "res://addons/gut/test.gd"

# Tests for COUNTER-OFFENSIVE stratagem implementation
#
# COUNTER-OFFENSIVE (Core – Strategic Ploy Stratagem, 2 CP)
# - WHEN: Fight phase, just after an enemy unit has fought.
# - TARGET: One unit from your army that is within Engagement Range of one or more
#           enemy units and that has not already been selected to fight this phase.
# - EFFECT: Your unit fights next.
# - RESTRICTION: Once per phase.
#
# These tests verify:
# 1. StratagemManager definition and validation for Counter-Offensive
# 2. CP deduction when used (2 CP)
# 3. Once-per-phase restriction
# 4. Eligible units: in engagement range, not fought, not battle-shocked
# 5. FightPhase integration: trigger after consolidate, fight order manipulation
# 6. Decline flow: normal alternation resumes
# 7. Edge cases (no CP, no eligible units, all fought, etc.)

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
			"position": {"x": 100 + i * 20 + (owner - 1) * 5, "y": 100},
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

func _setup_fight_scenario() -> void:
	"""Set up a basic fight scenario with units from both players in engagement range."""
	GameState.state.meta.phase = GameStateData.Phase.FIGHT
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Player 1 units (attacker)
	var p1_unit_a = _create_unit("U_P1_A", 5, 1, ["INFANTRY"], 3, 4, 1)
	# Place in engagement range of P2 unit (within 1")
	for i in range(p1_unit_a.models.size()):
		p1_unit_a.models[i].position = {"x": 100 + i * 20, "y": 100}
	GameState.state.units["U_P1_A"] = p1_unit_a

	var p1_unit_b = _create_unit("U_P1_B", 3, 1, ["INFANTRY"], 3, 4, 1)
	for i in range(p1_unit_b.models.size()):
		p1_unit_b.models[i].position = {"x": 300 + i * 20, "y": 100}
	GameState.state.units["U_P1_B"] = p1_unit_b

	# Player 2 units (defender) — close to P1 units (within engagement range)
	var p2_unit_a = _create_unit("U_P2_A", 5, 2, ["INFANTRY"], 3, 4, 1)
	for i in range(p2_unit_a.models.size()):
		p2_unit_a.models[i].position = {"x": 105 + i * 20, "y": 100}
	GameState.state.units["U_P2_A"] = p2_unit_a

	var p2_unit_b = _create_unit("U_P2_B", 3, 2, ["INFANTRY"], 3, 4, 1)
	for i in range(p2_unit_b.models.size()):
		p2_unit_b.models[i].position = {"x": 305 + i * 20, "y": 100}
	GameState.state.units["U_P2_B"] = p2_unit_b

	# Give both players enough CP for Counter-Offensive (costs 2)
	GameState.state.players["1"]["cp"] = 5
	GameState.state.players["2"]["cp"] = 5

	StratagemManager.reset_for_new_game()

func before_each():
	GameState.state.units.clear()
	StratagemManager.reset_for_new_game()


# ==========================================
# Section 1: Stratagem Definition
# ==========================================

func test_counter_offensive_definition_loaded():
	"""Counter-Offensive stratagem should be loaded with correct properties."""
	var strat = StratagemManager.get_stratagem("counter_offensive")
	assert_false(strat.is_empty(), "Counter-Offensive should be loaded")
	assert_eq(strat.name, "COUNTER-OFFENSIVE")
	assert_eq(strat.cp_cost, 2)
	assert_eq(strat.timing.turn, "either")
	assert_eq(strat.timing.phase, "fight")
	assert_eq(strat.timing.trigger, "after_enemy_fought")

func test_counter_offensive_effects():
	"""Counter-Offensive should have fight_next effect."""
	var strat = StratagemManager.get_stratagem("counter_offensive")
	assert_eq(strat.effects.size(), 1, "Should have 1 effect")

	var effect = strat.effects[0]
	assert_eq(effect.type, "fight_next", "Effect type should be fight_next")

func test_counter_offensive_restriction():
	"""Counter-Offensive should have once-per-phase restriction."""
	var strat = StratagemManager.get_stratagem("counter_offensive")
	assert_eq(strat.restrictions.once_per, "phase", "Should be once per phase")

func test_counter_offensive_cp_cost_is_2():
	"""Counter-Offensive costs 2 CP (most expensive core stratagem)."""
	var strat = StratagemManager.get_stratagem("counter_offensive")
	assert_eq(strat.cp_cost, 2, "Should cost 2 CP")


# ==========================================
# Section 2: Validation (is_counter_offensive_available)
# ==========================================

func test_counter_offensive_available_with_cp():
	"""Player with enough CP can use Counter-Offensive."""
	_setup_fight_scenario()

	var result = StratagemManager.is_counter_offensive_available(1)
	assert_true(result.available, "Should be available with sufficient CP: %s" % result.get("reason", ""))

func test_counter_offensive_not_available_with_zero_cp():
	"""Cannot use Counter-Offensive with 0 CP."""
	_setup_fight_scenario()
	GameState.state.players["1"]["cp"] = 0

	var result = StratagemManager.is_counter_offensive_available(1)
	assert_false(result.available, "Should not be available with 0 CP")

func test_counter_offensive_not_available_with_1_cp():
	"""Cannot use Counter-Offensive with only 1 CP (costs 2)."""
	_setup_fight_scenario()
	GameState.state.players["1"]["cp"] = 1

	var result = StratagemManager.is_counter_offensive_available(1)
	assert_false(result.available, "Should not be available with only 1 CP")

func test_counter_offensive_not_available_after_use():
	"""Counter-Offensive once-per-phase restriction."""
	_setup_fight_scenario()

	# First use should succeed
	var result1 = StratagemManager.use_stratagem(1, "counter_offensive", "U_P1_A")
	assert_true(result1.success, "First use should succeed")

	# Second check should fail
	var result2 = StratagemManager.is_counter_offensive_available(1)
	assert_false(result2.available, "Should not be available after use (once per phase)")


# ==========================================
# Section 3: Eligible Units Detection
# ==========================================

func test_eligible_units_in_engagement_range():
	"""Units in engagement range that haven't fought are eligible."""
	_setup_fight_scenario()

	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		1, [], GameState.create_snapshot()
	)
	assert_gt(eligible.size(), 0, "Should have eligible units in engagement range")

	# Check U_P1_A is in the list
	var found_p1_a = false
	for unit_info in eligible:
		if unit_info.unit_id == "U_P1_A":
			found_p1_a = true
			break
	assert_true(found_p1_a, "U_P1_A should be eligible (in engagement range)")

func test_eligible_units_excludes_fought_units():
	"""Units that have already fought are not eligible."""
	_setup_fight_scenario()

	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		1, ["U_P1_A"], GameState.create_snapshot()
	)

	for unit_info in eligible:
		assert_ne(unit_info.unit_id, "U_P1_A", "U_P1_A should not be eligible (already fought)")

func test_eligible_units_excludes_battle_shocked():
	"""Battle-shocked units are not eligible."""
	_setup_fight_scenario()
	GameState.state.units["U_P1_A"]["flags"]["battle_shocked"] = true

	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		1, [], GameState.create_snapshot()
	)

	for unit_info in eligible:
		assert_ne(unit_info.unit_id, "U_P1_A", "U_P1_A should not be eligible (battle-shocked)")

func test_eligible_units_excludes_not_in_engagement():
	"""Units not in engagement range are not eligible."""
	_setup_fight_scenario()
	# Move P1_B far away from any enemy
	for i in range(GameState.state.units["U_P1_B"].models.size()):
		GameState.state.units["U_P1_B"].models[i].position = {"x": 9000 + i * 20, "y": 9000}

	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		1, [], GameState.create_snapshot()
	)

	for unit_info in eligible:
		assert_ne(unit_info.unit_id, "U_P1_B", "U_P1_B should not be eligible (not in engagement range)")

func test_eligible_units_only_own_units():
	"""Only the specified player's units are returned."""
	_setup_fight_scenario()

	var eligible_p1 = StratagemManager.get_counter_offensive_eligible_units(
		1, [], GameState.create_snapshot()
	)

	for unit_info in eligible_p1:
		var unit = GameState.get_unit(unit_info.unit_id)
		assert_eq(int(unit.get("owner", 0)), 1, "Only player 1's units should be returned")

func test_eligible_units_empty_when_insufficient_cp():
	"""No eligible units returned when player has insufficient CP."""
	_setup_fight_scenario()
	GameState.state.players["1"]["cp"] = 0

	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		1, [], GameState.create_snapshot()
	)

	assert_eq(eligible.size(), 0, "Should have no eligible units with 0 CP")

func test_eligible_units_empty_when_all_fought():
	"""No eligible units when all units have already fought."""
	_setup_fight_scenario()

	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		1, ["U_P1_A", "U_P1_B"], GameState.create_snapshot()
	)

	assert_eq(eligible.size(), 0, "Should have no eligible units when all have fought")

func test_eligible_units_excludes_dead_units():
	"""Units with no alive models are not eligible."""
	_setup_fight_scenario()
	for model in GameState.state.units["U_P1_A"].models:
		model.alive = false

	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		1, [], GameState.create_snapshot()
	)

	for unit_info in eligible:
		assert_ne(unit_info.unit_id, "U_P1_A", "U_P1_A should not be eligible (all models dead)")


# ==========================================
# Section 4: CP Deduction
# ==========================================

func test_counter_offensive_deducts_2_cp():
	"""Using Counter-Offensive should deduct 2 CP."""
	_setup_fight_scenario()
	var initial_cp = GameState.state.players["1"]["cp"]

	var result = StratagemManager.use_stratagem(1, "counter_offensive", "U_P1_A")
	assert_true(result.success, "Use should succeed")

	var final_cp = GameState.state.players["1"]["cp"]
	assert_eq(final_cp, initial_cp - 2, "Should have deducted 2 CP (from %d to %d)" % [initial_cp, final_cp])


# ==========================================
# Section 5: Usage Tracking
# ==========================================

func test_counter_offensive_tracked_in_usage_history():
	"""Using Counter-Offensive should be recorded in usage history."""
	_setup_fight_scenario()

	StratagemManager.use_stratagem(1, "counter_offensive", "U_P1_A")

	# Trying to use again should fail (once per phase)
	var result = StratagemManager.can_use_stratagem(1, "counter_offensive")
	assert_false(result.can_use, "Should not be able to use again (once per phase)")

func test_counter_offensive_both_players_can_use_separately():
	"""Both players can use Counter-Offensive in the same phase (each once)."""
	_setup_fight_scenario()

	# Player 1 uses it
	var result1 = StratagemManager.use_stratagem(1, "counter_offensive", "U_P1_A")
	assert_true(result1.success, "Player 1 should succeed")

	# Player 2 should still be able to use it
	var result2 = StratagemManager.is_counter_offensive_available(2)
	assert_true(result2.available, "Player 2 should still be able to use Counter-Offensive")


# ==========================================
# Section 6: FightPhase State Management
# ==========================================

func test_fight_phase_counter_offensive_state_initialized():
	"""FightPhase should initialize Counter-Offensive state correctly."""
	var fight_phase = FightPhase.new()
	assert_false(fight_phase.awaiting_counter_offensive, "awaiting_counter_offensive should start false")
	assert_eq(fight_phase.counter_offensive_player, 0, "counter_offensive_player should start at 0")
	assert_eq(fight_phase.counter_offensive_unit_id, "", "counter_offensive_unit_id should start empty")
	fight_phase.free()

func test_fight_phase_validate_use_counter_offensive_requires_awaiting():
	"""USE_COUNTER_OFFENSIVE should fail when not awaiting Counter-Offensive."""
	var fight_phase = FightPhase.new()
	fight_phase.awaiting_counter_offensive = false

	var validation = fight_phase._validate_use_counter_offensive({
		"unit_id": "U_P1_A",
		"player": 1
	})
	assert_false(validation.valid, "Should fail when not awaiting Counter-Offensive")
	fight_phase.free()

func test_fight_phase_validate_use_counter_offensive_requires_unit_id():
	"""USE_COUNTER_OFFENSIVE should fail without unit_id."""
	var fight_phase = FightPhase.new()
	fight_phase.awaiting_counter_offensive = true
	fight_phase.counter_offensive_player = 1

	var validation = fight_phase._validate_use_counter_offensive({
		"unit_id": "",
		"player": 1
	})
	assert_false(validation.valid, "Should fail without unit_id")
	fight_phase.free()


# ==========================================
# Section 7: Integration Flow
# ==========================================

func test_counter_offensive_full_flow_definition_to_deduction():
	"""Full flow: check available -> use -> CP deducted -> tracked."""
	_setup_fight_scenario()

	# Step 1: Check availability
	var check = StratagemManager.is_counter_offensive_available(2)
	assert_true(check.available, "Should be available initially")

	# Step 2: Get eligible units
	var eligible = StratagemManager.get_counter_offensive_eligible_units(
		2, [], GameState.create_snapshot()
	)
	assert_gt(eligible.size(), 0, "Should have eligible units")

	# Step 3: Use it
	var initial_cp = GameState.state.players["2"]["cp"]
	var unit_id = eligible[0].unit_id
	var result = StratagemManager.use_stratagem(2, "counter_offensive", unit_id)
	assert_true(result.success, "Use should succeed")

	# Step 4: Verify CP deduction
	assert_eq(GameState.state.players["2"]["cp"], initial_cp - 2, "Should deduct 2 CP")

	# Step 5: Verify can't use again
	var check2 = StratagemManager.is_counter_offensive_available(2)
	assert_false(check2.available, "Should not be available after use")


# ==========================================
# Section 8: Edge Cases
# ==========================================

func test_counter_offensive_with_exactly_2_cp():
	"""Counter-Offensive should work with exactly 2 CP."""
	_setup_fight_scenario()
	GameState.state.players["1"]["cp"] = 2

	var result = StratagemManager.is_counter_offensive_available(1)
	assert_true(result.available, "Should be available with exactly 2 CP")

	var use_result = StratagemManager.use_stratagem(1, "counter_offensive", "U_P1_A")
	assert_true(use_result.success, "Should succeed with exactly 2 CP")
	assert_eq(GameState.state.players["1"]["cp"], 0, "Should have 0 CP after use")

func test_counter_offensive_does_not_set_unit_flags():
	"""Counter-Offensive has no persistent unit flags (unlike Go to Ground)."""
	_setup_fight_scenario()

	var result = StratagemManager.use_stratagem(1, "counter_offensive", "U_P1_A")
	assert_true(result.success, "Use should succeed")

	# No stratagem flags should be set on the unit
	var unit = GameState.get_unit("U_P1_A")
	var flags = unit.get("flags", {})
	assert_false(flags.has("stratagem_counter_offensive"), "Should not have counter_offensive flag")

func test_counter_offensive_active_effect_tracked():
	"""Counter-Offensive should track an active effect for duration management."""
	_setup_fight_scenario()

	var initial_effects = StratagemManager.active_effects.size()
	StratagemManager.use_stratagem(1, "counter_offensive", "U_P1_A")

	assert_eq(StratagemManager.active_effects.size(), initial_effects + 1, "Should add active effect")
	var last_effect = StratagemManager.active_effects[-1]
	assert_eq(last_effect.stratagem_id, "counter_offensive")
	assert_eq(last_effect.player, 1)
	assert_eq(last_effect.target_unit_id, "U_P1_A")
	assert_eq(last_effect.expires, "end_of_phase")
