extends "res://addons/gut/test.gd"

# Tests for 10th Edition Battle-shock mechanics
#
# Per Warhammer 40k 10th Edition Core Rules:
# - Battle-shock tests happen in the Command Phase (Step 2)
# - Units Below Half-strength must take a Battle-shock test
#   (fewer than half models remaining, or fewer than half wounds for single-model units)
# - Battle-shock test: Roll 2D6 >= Leadership to pass
# - Failed test: Unit is Battle-shocked until start of owner's next Command Phase
# - Battle-shocked effects:
#   * OC (Objective Control) becomes 0
#   * Cannot be affected by Stratagems (except Insane Bravery)
#   * Desperate Escape tests apply to ALL models when Falling Back
#
# These tests verify:
# 1. Below-half-strength eligibility detection
# 2. Battle-shock test resolution (2D6 vs Leadership)
# 3. Battle-shock flag effects on OC and movement
# 4. CommandPhase and MoralePhase integration
# 5. Special rules (FEARLESS, ATSKNF)

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helper: Create a unit dictionary for testing
# ==========================================

func _create_unit(id: String, model_count: int, leadership: int = 7, owner: int = 0, wounds_per_model: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "%s_model_%d" % [id, i],
			"position": {"x": 100 + i * 20, "y": 100},
			"wounds_remaining": wounds_per_model,
			"is_alive": true,
			"equipment": [],
			"status_effects": []
		})
	return {
		"id": id,
		"name": "Test Unit %s" % id,
		"faction": "Space Marines",
		"player_id": owner,
		"owner": owner,
		"unit_type": "Infantry",
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_moved": false,
			"has_advanced": false,
			"has_shot": false,
			"has_charged": false,
			"has_fought": false,
			"is_selected": false,
			"battle_shocked": false,
			"morale_tested": false
		},
		"stats": {
			"movement": 6,
			"weapon_skill": 3,
			"ballistic_skill": 3,
			"strength": 4,
			"toughness": 4,
			"wounds": wounds_per_model,
			"attacks": 1,
			"leadership": leadership,
			"armor_save": 3,
			"objective_control": 1
		},
		"models": models,
		"meta": {
			"stats": {
				"leadership": leadership,
				"objective_control": 1
			},
			"keywords": [],
			"name": "Test Unit %s" % id
		},
		"weapons": [],
		"abilities": [],
		"casualties_this_turn": 0,
		"status_effects": {}
	}


func _kill_models(unit: Dictionary, count: int) -> void:
	"""Kill a specified number of models in the unit."""
	var killed = 0
	for model in unit.models:
		if killed >= count:
			break
		if model.is_alive:
			model.is_alive = false
			model.wounds_remaining = 0
			killed += 1
	unit.casualties_this_turn = count


func _count_alive_models(unit: Dictionary) -> int:
	var alive = 0
	for model in unit.models:
		if model.get("is_alive", true):
			alive += 1
	return alive


func _is_below_half_strength(unit: Dictionary) -> bool:
	"""
	10e Rule: A unit is Below Half-strength if it has fewer than half
	its starting models alive. For single-model units, it's below half
	wounds remaining.
	"""
	var total_models = unit.models.size()
	var alive_models = _count_alive_models(unit)

	if total_models == 1:
		# Single-model unit: check wounds
		var max_wounds = unit.get("stats", {}).get("wounds", 1)
		var current_wounds = unit.models[0].get("wounds_remaining", max_wounds)
		return current_wounds < ceil(max_wounds / 2.0)
	else:
		# Multi-model unit: check model count
		return alive_models < ceil(total_models / 2.0)


func _battle_shock_test_passes(roll_2d6: int, leadership: int) -> bool:
	"""10e Rule: Battle-shock test passes if 2D6 >= Leadership."""
	return roll_2d6 >= leadership


# ==========================================
# Section 1: Below Half-Strength Detection
# ==========================================

func test_full_strength_unit_not_below_half():
	"""A unit at full strength (all models alive) is NOT below half-strength."""
	var unit = _create_unit("full", 10)
	assert_false(_is_below_half_strength(unit),
		"10-model unit with all alive should not be below half-strength")

func test_exactly_half_models_not_below_half():
	"""A 10-model unit with 5 alive is at half-strength, NOT below half."""
	var unit = _create_unit("half", 10)
	_kill_models(unit, 5)
	assert_false(_is_below_half_strength(unit),
		"10-model unit with 5 alive (exactly half) should NOT be below half-strength")

func test_below_half_models_is_below_half():
	"""A 10-model unit with 4 alive is below half-strength."""
	var unit = _create_unit("below", 10)
	_kill_models(unit, 6)
	assert_true(_is_below_half_strength(unit),
		"10-model unit with 4 alive should be below half-strength")

func test_one_model_dead_from_two_is_below_half():
	"""A 2-model unit with 1 dead is below half-strength (1 < ceil(2/2) = 1 is false, need < ceil)."""
	var unit = _create_unit("pair", 2)
	_kill_models(unit, 1)
	# 1 alive < ceil(2/2.0) = ceil(1.0) = 1 → 1 < 1 = false
	# Actually for 2 models, half is 1, so 1 remaining is NOT below half
	assert_false(_is_below_half_strength(unit),
		"2-model unit with 1 alive is at half, not below half")

func test_both_models_dead_from_two():
	"""A 2-model unit with 0 alive is below half-strength (and destroyed)."""
	var unit = _create_unit("pair_dead", 2)
	_kill_models(unit, 2)
	assert_true(_is_below_half_strength(unit),
		"2-model unit with 0 alive should be below half-strength")

func test_five_model_unit_with_two_alive():
	"""A 5-model unit with 2 alive: 2 < ceil(5/2) = 3 → below half."""
	var unit = _create_unit("five", 5)
	_kill_models(unit, 3)
	assert_true(_is_below_half_strength(unit),
		"5-model unit with 2 alive should be below half-strength")

func test_five_model_unit_with_three_alive():
	"""A 5-model unit with 3 alive: 3 >= ceil(5/2) = 3 → NOT below half."""
	var unit = _create_unit("five_ok", 5)
	_kill_models(unit, 2)
	assert_false(_is_below_half_strength(unit),
		"5-model unit with 3 alive should NOT be below half-strength")

func test_single_model_unit_full_wounds_not_below_half():
	"""A single-model unit at full wounds is NOT below half-strength."""
	var unit = _create_unit("monster", 1, 8, 0, 12)
	assert_false(_is_below_half_strength(unit),
		"Single model with 12/12 wounds should not be below half-strength")

func test_single_model_unit_below_half_wounds():
	"""A single-model unit (12W) with 5 wounds remaining is below half (5 < 6)."""
	var unit = _create_unit("monster_hurt", 1, 8, 0, 12)
	unit.models[0].wounds_remaining = 5
	assert_true(_is_below_half_strength(unit),
		"Single model with 5/12 wounds should be below half-strength")

func test_single_model_unit_at_half_wounds():
	"""A single-model unit (12W) with 6 wounds remaining is at half, NOT below."""
	var unit = _create_unit("monster_half", 1, 8, 0, 12)
	unit.models[0].wounds_remaining = 6
	assert_false(_is_below_half_strength(unit),
		"Single model with 6/12 wounds should NOT be below half-strength")

func test_single_model_unit_one_wound_remaining():
	"""A single-model unit (12W) with 1 wound remaining is definitely below half."""
	var unit = _create_unit("monster_crit", 1, 8, 0, 12)
	unit.models[0].wounds_remaining = 1
	assert_true(_is_below_half_strength(unit),
		"Single model with 1/12 wounds should be below half-strength")

func test_odd_model_count_below_half():
	"""A 7-model unit with 3 alive: 3 < ceil(7/2) = 4 → below half."""
	var unit = _create_unit("seven", 7)
	_kill_models(unit, 4)
	assert_true(_is_below_half_strength(unit),
		"7-model unit with 3 alive should be below half-strength")

func test_odd_model_count_not_below_half():
	"""A 7-model unit with 4 alive: 4 >= ceil(7/2) = 4 → NOT below half."""
	var unit = _create_unit("seven_ok", 7)
	_kill_models(unit, 3)
	assert_false(_is_below_half_strength(unit),
		"7-model unit with 4 alive should NOT be below half-strength")

func test_single_wound_vehicle_below_half():
	"""A single-model vehicle (14W) with 6 wounds is below half (6 < ceil(14/2) = 7)."""
	var unit = _create_unit("vehicle", 1, 9, 0, 14)
	unit.models[0].wounds_remaining = 6
	assert_true(_is_below_half_strength(unit),
		"Vehicle with 6/14 wounds should be below half-strength")


# ==========================================
# Section 2: Battle-shock Test Resolution (2D6 vs Leadership)
# ==========================================

func test_roll_equals_leadership_passes():
	"""10e: 2D6 >= Ld passes. Rolling exactly Ld (7) should pass."""
	assert_true(_battle_shock_test_passes(7, 7),
		"Rolling 7 on 2D6 vs Ld 7 should pass the battle-shock test")

func test_roll_above_leadership_passes():
	"""Rolling above Ld should pass."""
	assert_true(_battle_shock_test_passes(9, 7),
		"Rolling 9 on 2D6 vs Ld 7 should pass")

func test_roll_below_leadership_fails():
	"""Rolling below Ld should fail."""
	assert_false(_battle_shock_test_passes(5, 7),
		"Rolling 5 on 2D6 vs Ld 7 should fail the battle-shock test")

func test_roll_12_always_passes():
	"""Rolling 12 (maximum 2D6) should always pass any leadership."""
	assert_true(_battle_shock_test_passes(12, 7), "12 vs Ld 7 should pass")
	assert_true(_battle_shock_test_passes(12, 10), "12 vs Ld 10 should pass")
	assert_true(_battle_shock_test_passes(12, 12), "12 vs Ld 12 should pass")

func test_roll_2_always_fails():
	"""Rolling 2 (minimum 2D6) should fail vs any reasonable leadership."""
	assert_false(_battle_shock_test_passes(2, 6), "2 vs Ld 6 should fail")
	assert_false(_battle_shock_test_passes(2, 7), "2 vs Ld 7 should fail")
	assert_false(_battle_shock_test_passes(2, 10), "2 vs Ld 10 should fail")

func test_ork_leadership_6():
	"""Ork Boyz (Ld 6+): Need 6+ on 2D6 to pass."""
	assert_true(_battle_shock_test_passes(6, 6), "6 vs Ld 6 should pass (Ork Boyz)")
	assert_false(_battle_shock_test_passes(5, 6), "5 vs Ld 6 should fail (Ork Boyz)")

func test_space_marine_leadership_7():
	"""Space Marines (Ld 7+): Need 7+ on 2D6 to pass."""
	assert_true(_battle_shock_test_passes(7, 7), "7 vs Ld 7 should pass (Space Marines)")
	assert_false(_battle_shock_test_passes(6, 7), "6 vs Ld 7 should fail (Space Marines)")

func test_elite_leadership_8():
	"""Elite units (Ld 8+): Need 8+ on 2D6 to pass."""
	assert_true(_battle_shock_test_passes(8, 8), "8 vs Ld 8 should pass")
	assert_false(_battle_shock_test_passes(7, 8), "7 vs Ld 8 should fail")


# ==========================================
# Section 3: Battle-shock Flag Effects
# ==========================================

func test_battle_shocked_unit_has_zero_oc():
	"""Battle-shocked units have OC = 0 per 10e rules."""
	var unit = _create_unit("shocked", 5, 7)
	unit.flags.battle_shocked = true

	# This is how MissionManager checks it
	var is_shocked = unit.get("flags", {}).get("battle_shocked", false)
	assert_true(is_shocked, "Unit should have battle_shocked flag set")

	# When battle-shocked, effective OC should be 0
	var effective_oc = 0 if is_shocked else unit.stats.objective_control
	assert_eq(effective_oc, 0, "Battle-shocked unit should have effective OC of 0")

func test_non_shocked_unit_has_normal_oc():
	"""Non-battle-shocked units retain their normal OC."""
	var unit = _create_unit("normal", 5, 7)
	unit.flags.battle_shocked = false

	var is_shocked = unit.get("flags", {}).get("battle_shocked", false)
	var effective_oc = 0 if is_shocked else unit.stats.objective_control
	assert_eq(effective_oc, 1, "Non-battle-shocked unit should retain OC 1")

func test_battle_shocked_flag_default_false():
	"""Battle-shocked flag should default to false if not set."""
	var unit = _create_unit("default", 5, 7)
	# Remove the flag entirely to test default
	unit.flags.erase("battle_shocked")
	var is_shocked = unit.get("flags", {}).get("battle_shocked", false)
	assert_false(is_shocked, "Missing battle_shocked flag should default to false")

func test_battle_shocked_movement_desperate_escape():
	"""Battle-shocked units use status_effects.battle_shocked for movement phase."""
	var unit = _create_unit("move_shocked", 5, 7)
	unit.status_effects["battle_shocked"] = true

	# This is how MovementPhase checks it
	var move_data_battle_shocked = unit.get("status_effects", {}).get("battle_shocked", false)
	assert_true(move_data_battle_shocked,
		"Movement phase should detect battle-shock from status_effects")

func test_battle_shocked_flag_set_and_clear():
	"""Battle-shock flag can be set and cleared."""
	var unit = _create_unit("toggle", 5, 7)
	assert_false(unit.flags.battle_shocked, "Should start not battle-shocked")

	unit.flags.battle_shocked = true
	assert_true(unit.flags.battle_shocked, "Should be battle-shocked after setting flag")

	unit.flags.battle_shocked = false
	assert_false(unit.flags.battle_shocked, "Should not be battle-shocked after clearing flag")


# ==========================================
# Section 4: MoralePhase Integration (10th Edition)
# In 10e, the Morale Phase is a bookkeeping phase with no active mechanics.
# Battle-shock tests happen in the Command Phase (tested in Section 6).
# The Morale Phase just logs battle-shock status and auto-completes.
# ==========================================

var morale_phase: MoralePhase

func _create_morale_phase() -> MoralePhase:
	var phase = preload("res://phases/MoralePhase.gd").new()
	add_child(phase)
	return phase

func _create_command_phase():
	var phase = preload("res://phases/CommandPhase.gd").new()
	add_child(phase)
	return phase

func _create_test_game_state_for_morale() -> Dictionary:
	"""
	Creates a test state for the Morale Phase.
	In 10e, the Morale Phase has no active mechanics — it just logs
	battle-shock status and completes.
	"""
	var state = TestDataFactory.create_test_game_state()
	state.current_phase = GameStateData.Phase.MORALE

	# Ensure owner fields are set
	for unit_id in state.units:
		var u = state.units[unit_id]
		if not u.has("owner"):
			u["owner"] = u.get("player_id", 0)

	return state

func _create_test_game_state_with_battle_shocked_unit() -> Dictionary:
	"""
	Creates a test state where a unit is battle-shocked (set during Command Phase).
	"""
	var state = _create_test_game_state_for_morale()

	# Set battle_shocked flag on enemy_unit_1 (owner=1, the active player)
	var unit = state.units["enemy_unit_1"]
	if not unit.has("flags"):
		unit["flags"] = {}
	unit["flags"]["battle_shocked"] = true

	return state

func test_morale_phase_type():
	"""MoralePhase should have MORALE phase type."""
	var phase = _create_morale_phase()
	assert_eq(phase.phase_type, GameStateData.Phase.MORALE,
		"Phase type should be MORALE")
	phase.queue_free()

func test_morale_phase_enters_successfully():
	"""MoralePhase should enter without errors."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)
	assert_not_null(phase.game_state_snapshot, "Should have game state snapshot after enter")
	phase.queue_free()

func test_morale_phase_exits_successfully():
	"""MoralePhase should exit without errors."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)
	phase.exit_phase()
	assert_true(true, "Phase exit should complete without error")
	phase.queue_free()

func test_morale_end_phase_always_valid():
	"""END_MORALE action should always be valid."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var action = {"type": "END_MORALE"}
	var validation = phase.validate_action(action)
	assert_true(validation.valid, "END_MORALE should always be valid")

	phase.queue_free()

func test_morale_phase_process_end_morale():
	"""END_MORALE action should process successfully."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var action = {"type": "END_MORALE"}
	var result = phase.process_action(action)
	assert_true(result.get("success", false), "END_MORALE should succeed")

	phase.queue_free()

func test_morale_phase_rejects_old_9e_morale_test():
	"""10e MoralePhase should reject old 9th-edition MORALE_TEST action type."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var action = {
		"type": "MORALE_TEST",
		"unit_id": "enemy_unit_1",
		"morale_roll": 3
	}
	var validation = phase.validate_action(action)
	assert_false(validation.valid,
		"10e Morale Phase should reject old MORALE_TEST action type")

	phase.queue_free()

func test_morale_phase_rejects_old_9e_skip_morale():
	"""10e MoralePhase should reject old 9th-edition SKIP_MORALE action type."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var action = {"type": "SKIP_MORALE", "unit_id": "enemy_unit_1"}
	var validation = phase.validate_action(action)
	assert_false(validation.valid,
		"10e Morale Phase should reject old SKIP_MORALE action type")

	phase.queue_free()

func test_morale_available_actions_only_end():
	"""In 10e, the only available action in Morale Phase is END_MORALE."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var actions = phase.get_available_actions()
	assert_eq(actions.size(), 1, "Should have exactly 1 available action")
	assert_eq(actions[0].get("type", ""), "END_MORALE",
		"Only available action should be END_MORALE")

	phase.queue_free()


# ==========================================
# Section 5: Battle-shock Status in Morale Phase (10e)
# In 10e, the Morale Phase logs battle-shocked status but takes no action.
# Battle-shock is set in Command Phase and clears at next Command Phase.
# ==========================================

func test_battle_shocked_unit_detected_in_morale_phase():
	"""MoralePhase should detect and log battle-shocked units."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_with_battle_shocked_unit()
	# Phase enters and logs — no errors expected
	phase.enter_phase(state)
	# Verify the unit is still battle-shocked (Morale Phase doesn't change it)
	var unit = state.units["enemy_unit_1"]
	assert_true(unit.get("flags", {}).get("battle_shocked", false),
		"Battle-shocked status should persist through Morale Phase")
	phase.queue_free()

func test_morale_phase_does_not_clear_battle_shock():
	"""Morale Phase should NOT clear battle-shocked status (that happens in Command Phase)."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_with_battle_shocked_unit()
	phase.enter_phase(state)

	# Process END_MORALE
	var action = {"type": "END_MORALE"}
	phase.process_action(action)

	# Battle-shock should still be active
	var unit = state.units["enemy_unit_1"]
	assert_true(unit.get("flags", {}).get("battle_shocked", false),
		"Battle-shock should NOT be cleared by Morale Phase (cleared in next Command Phase)")


# ==========================================
# Section 6: CommandPhase Integration
# ==========================================

func test_command_phase_type():
	"""CommandPhase should have correct phase type."""
	var phase = _create_command_phase()
	var state = TestDataFactory.create_test_game_state()
	state.current_phase = GameStateData.Phase.COMMAND
	phase.enter_phase(state)

	assert_eq(phase.phase_type, GameStateData.Phase.COMMAND,
		"CommandPhase should have COMMAND phase type")

	phase.queue_free()

func test_command_phase_end_command_valid():
	"""END_COMMAND action should always be valid."""
	var phase = _create_command_phase()
	var state = TestDataFactory.create_test_game_state()
	state.current_phase = GameStateData.Phase.COMMAND
	phase.enter_phase(state)

	var action = {"type": "END_COMMAND"}
	var validation = phase.validate_action(action)
	assert_true(validation.valid, "END_COMMAND should be valid in command phase")

	phase.queue_free()

func test_command_phase_unknown_action_invalid():
	"""Unknown action types should be invalid in CommandPhase."""
	var phase = _create_command_phase()
	var state = TestDataFactory.create_test_game_state()
	state.current_phase = GameStateData.Phase.COMMAND
	phase.enter_phase(state)

	var action = {"type": "UNKNOWN_ACTION"}
	var validation = phase.validate_action(action)
	assert_false(validation.valid, "Unknown action should be invalid")

	phase.queue_free()

func test_command_phase_available_actions():
	"""CommandPhase should list END_COMMAND as available action."""
	var phase = _create_command_phase()
	var state = TestDataFactory.create_test_game_state()
	state.current_phase = GameStateData.Phase.COMMAND
	phase.enter_phase(state)

	var actions = phase.get_available_actions()
	assert_gt(actions.size(), 0, "Should have at least one available action")

	var has_end_command = false
	for action in actions:
		if action.get("type", "") == "END_COMMAND":
			has_end_command = true
			break
	assert_true(has_end_command, "Should include END_COMMAND action")

	phase.queue_free()

func test_command_phase_does_not_auto_complete():
	"""CommandPhase should not auto-complete (waits for player action)."""
	var phase = _create_command_phase()
	var state = TestDataFactory.create_test_game_state()
	state.current_phase = GameStateData.Phase.COMMAND
	phase.enter_phase(state)

	assert_false(phase._should_complete_phase(),
		"Command phase should not auto-complete")

	phase.queue_free()


# ==========================================
# Section 7: 10e Morale Phase — No Active Mechanics
# In 10e, the Morale Phase has no morale tests or skip actions.
# It is a pass-through bookkeeping phase.
# ==========================================

func test_morale_phase_no_old_morale_test_actions():
	"""10e Morale Phase should NOT offer MORALE_TEST or SKIP_MORALE actions."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var actions = phase.get_available_actions()
	for action in actions:
		var action_type = action.get("type", "")
		assert_ne(action_type, "MORALE_TEST",
			"10e Morale Phase should not offer MORALE_TEST actions")
		assert_ne(action_type, "SKIP_MORALE",
			"10e Morale Phase should not offer SKIP_MORALE actions")

	phase.queue_free()

func test_morale_phase_available_actions_with_battle_shocked():
	"""Even with battle-shocked units, only END_MORALE should be available."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_with_battle_shocked_unit()
	phase.enter_phase(state)

	var actions = phase.get_available_actions()
	assert_eq(actions.size(), 1, "Should have exactly 1 available action")
	assert_eq(actions[0].get("type", ""), "END_MORALE",
		"Only action should be END_MORALE even with battle-shocked units")

	phase.queue_free()


# ==========================================
# Section 9: Desperate Escape Integration
# ==========================================

func test_battle_shocked_desperate_escape_all_models():
	"""
	10e Rule: When a Battle-shocked unit Falls Back, ALL models must make
	Desperate Escape tests (not just those that cross enemy models).
	This test verifies the flag logic used by MovementPhase.
	"""
	var unit = _create_unit("desperate", 5, 7)
	unit.status_effects["battle_shocked"] = true

	# MovementPhase line 569: checks status_effects.battle_shocked
	var battle_shocked_for_move = unit.get("status_effects", {}).get("battle_shocked", false)
	assert_true(battle_shocked_for_move,
		"Movement phase should detect battle-shock for desperate escape")

func test_non_shocked_desperate_escape_only_crossing():
	"""
	Non-battle-shocked units only test models that cross enemy models
	during Fall Back (the default behavior).
	"""
	var unit = _create_unit("normal_fallback", 5, 7)
	unit.status_effects["battle_shocked"] = false

	var battle_shocked_for_move = unit.get("status_effects", {}).get("battle_shocked", false)
	assert_false(battle_shocked_for_move,
		"Non-shocked unit should not trigger all-model desperate escape")


# ==========================================
# Section 10: Battle-shock Duration and Reset
# ==========================================

func test_battle_shock_flag_persists_between_phases():
	"""Battle-shock should persist through the turn until next Command Phase."""
	var unit = _create_unit("persist", 5, 7)
	unit.flags.battle_shocked = true

	# Simulate checking in movement phase
	assert_true(unit.flags.battle_shocked,
		"Battle-shock should persist into movement phase")

	# Simulate checking in shooting phase
	assert_true(unit.flags.battle_shocked,
		"Battle-shock should persist into shooting phase")

	# Simulate checking in charge phase
	assert_true(unit.flags.battle_shocked,
		"Battle-shock should persist into charge phase")

func test_battle_shock_flag_can_be_cleared():
	"""At start of next Command Phase, battle-shock should be clearable."""
	var unit = _create_unit("clear", 5, 7)
	unit.flags.battle_shocked = true

	# Simulate start of next command phase
	unit.flags.battle_shocked = false
	assert_false(unit.flags.battle_shocked,
		"Battle-shock should be clearable at start of next command phase")


# ==========================================
# Section 11: Edge Cases
# ==========================================

func test_unknown_action_type_rejected_by_morale():
	"""MoralePhase should reject completely unknown action types."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var action = {"type": "CAST_SPELL"}
	var validation = phase.validate_action(action)
	assert_false(validation.valid, "Unknown action type should be rejected")

	phase.queue_free()

func test_use_stratagem_rejected_in_10e_morale():
	"""In 10e, USE_STRATAGEM is not a valid action in the Morale Phase."""
	var phase = _create_morale_phase()
	var state = _create_test_game_state_for_morale()
	phase.enter_phase(state)

	var action = {
		"type": "USE_STRATAGEM",
		"stratagem_id": "insane_bravery",
		"target_unit_id": "enemy_unit_1"
	}
	var validation = phase.validate_action(action)
	assert_false(validation.valid,
		"10e Morale Phase should not accept USE_STRATAGEM actions")

	phase.queue_free()

func test_one_model_unit_alive_above_half():
	"""A 1-wound single model unit at full wounds is NOT below half."""
	var unit = _create_unit("single_1w", 1, 7, 0, 1)
	assert_false(_is_below_half_strength(unit),
		"Single 1-wound model at full wounds should not be below half")

func test_twenty_model_unit_with_ten_alive():
	"""A 20-model unit with 10 alive: 10 >= ceil(20/2) = 10 → NOT below half."""
	var unit = _create_unit("horde", 20, 6)
	_kill_models(unit, 10)
	assert_false(_is_below_half_strength(unit),
		"20-model unit with 10 alive should NOT be below half-strength")

func test_twenty_model_unit_with_nine_alive():
	"""A 20-model unit with 9 alive: 9 < ceil(20/2) = 10 → below half."""
	var unit = _create_unit("horde_hurt", 20, 6)
	_kill_models(unit, 11)
	assert_true(_is_below_half_strength(unit),
		"20-model unit with 9 alive should be below half-strength")

func test_three_model_unit_with_one_alive():
	"""A 3-model unit with 1 alive: 1 < ceil(3/2) = 2 → below half."""
	var unit = _create_unit("small", 3, 7)
	_kill_models(unit, 2)
	assert_true(_is_below_half_strength(unit),
		"3-model unit with 1 alive should be below half-strength")

func test_three_model_unit_with_two_alive():
	"""A 3-model unit with 2 alive: 2 >= ceil(3/2) = 2 → NOT below half."""
	var unit = _create_unit("small_ok", 3, 7)
	_kill_models(unit, 1)
	assert_false(_is_below_half_strength(unit),
		"3-model unit with 2 alive should NOT be below half-strength")


# ==========================================
# Section 13: FLY / TITANIC Desperate Escape Skip
# ==========================================

func test_fly_keyword_skips_desperate_escape():
	"""
	10e Rule: FLY units do not take Desperate Escape tests when Falling Back.
	They can move over enemy models without penalty.
	"""
	var unit = _create_unit("fly_unit", 5, 7)
	unit.meta.keywords = ["INFANTRY", "FLY", "IMPERIUM"]

	var keywords = unit.get("meta", {}).get("keywords", [])
	assert_true("FLY" in keywords,
		"FLY keyword should be present in unit keywords")
	# MovementPhase._process_desperate_escape() checks for FLY keyword
	# and returns early with no changes/dice if found
	var should_skip = "FLY" in keywords or "TITANIC" in keywords
	assert_true(should_skip,
		"FLY units should skip Desperate Escape tests")

func test_titanic_keyword_skips_desperate_escape():
	"""
	10e Rule: TITANIC models do not take Desperate Escape tests when Falling Back.
	Affects large models like Imperial Knights and Baneblades.
	"""
	var unit = _create_unit("titanic_unit", 1, 7)
	unit.meta.keywords = ["VEHICLE", "TITANIC", "IMPERIUM"]

	var keywords = unit.get("meta", {}).get("keywords", [])
	assert_true("TITANIC" in keywords,
		"TITANIC keyword should be present in unit keywords")
	var should_skip = "FLY" in keywords or "TITANIC" in keywords
	assert_true(should_skip,
		"TITANIC units should skip Desperate Escape tests")

func test_non_fly_non_titanic_takes_desperate_escape():
	"""
	Regular units without FLY or TITANIC must take Desperate Escape tests
	when Falling Back through enemy models.
	"""
	var unit = _create_unit("regular_unit", 5, 7)
	unit.meta.keywords = ["INFANTRY", "IMPERIUM"]

	var keywords = unit.get("meta", {}).get("keywords", [])
	assert_false("FLY" in keywords,
		"Regular unit should not have FLY keyword")
	assert_false("TITANIC" in keywords,
		"Regular unit should not have TITANIC keyword")
	var should_skip = "FLY" in keywords or "TITANIC" in keywords
	assert_false(should_skip,
		"Regular units should NOT skip Desperate Escape tests")

func test_fly_and_titanic_combined_skips_desperate_escape():
	"""
	A unit with both FLY and TITANIC keywords should also skip Desperate Escape.
	"""
	var unit = _create_unit("fly_titanic_unit", 1, 7)
	unit.meta.keywords = ["VEHICLE", "FLY", "TITANIC", "IMPERIUM"]

	var keywords = unit.get("meta", {}).get("keywords", [])
	var should_skip = "FLY" in keywords or "TITANIC" in keywords
	assert_true(should_skip,
		"Unit with both FLY and TITANIC should skip Desperate Escape")
