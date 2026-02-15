extends BasePhase
class_name CommandPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# CommandPhase - Handles Command Phase including CP generation and Battle-shock tests
# Per 10th edition rules:
# 1. Generate Command Points (both players gain 1 CP)
# 2. Clear all battle_shocked flags at the start of the Command Phase
# 3. Identify units Below Half-strength
# 4. Each Below Half-strength unit takes a Battle-shock test (2D6 vs Leadership)
#    - INSANE BRAVERY stratagem can auto-pass a test (once per battle, 1 CP)
# 5. If the roll is below the unit's Leadership, the unit becomes Battle-shocked
# 6. Score primary objectives and end the phase

# Track which units still need battle-shock tests this phase
var _units_needing_test: Array = []
var _units_tested: Array = []
var _units_auto_passed: Array = []  # Units that auto-passed via Insane Bravery
var _rng: RandomNumberGenerator

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.COMMAND
	var current_player = get_current_player()
	var battle_round = GameState.get_battle_round()
	print("CommandPhase: Entering command phase for player ", current_player)
	print("CommandPhase: Battle round ", battle_round)

	# Step 1: Generate Command Points
	# Per 10th edition rules, both players gain 1 CP at the start of each Command Phase
	_generate_command_points(current_player)

	# Step 2: Clear all battle_shocked flags for the current player's units
	_clear_battle_shocked_flags()

	# Step 3: Identify units below half-strength that need battle-shock tests
	_identify_units_needing_tests()

	# Step 4: Check objectives at start of command phase
	if MissionManager:
		MissionManager.check_all_objectives()

	if _units_needing_test.size() == 0:
		print("CommandPhase: No units need battle-shock tests")
	else:
		print("CommandPhase: %d unit(s) need battle-shock tests" % _units_needing_test.size())

func _generate_command_points(active_player: int) -> void:
	var opponent = 1 if active_player == 2 else 2
	var changes = []

	# Active player gains 1 CP
	var active_cp = GameState.state.get("players", {}).get(str(active_player), {}).get("cp", 0)
	changes.append({
		"op": "set",
		"path": "players.%s.cp" % str(active_player),
		"value": active_cp + 1
	})

	# Opponent also gains 1 CP
	var opponent_cp = GameState.state.get("players", {}).get(str(opponent), {}).get("cp", 0)
	changes.append({
		"op": "set",
		"path": "players.%s.cp" % str(opponent),
		"value": opponent_cp + 1
	})

	# Apply via PhaseManager so changes propagate to network peers
	PhaseManager.apply_state_changes(changes)

	# Refresh our local snapshot to reflect the CP changes
	game_state_snapshot = GameState.create_snapshot()

	print("CommandPhase: Generated CP — Player %d: %d → %d, Player %d: %d → %d" % [
		active_player, active_cp, active_cp + 1,
		opponent, opponent_cp, opponent_cp + 1
	])

func _on_phase_exit() -> void:
	print("CommandPhase: Exiting command phase")
	_units_needing_test.clear()
	_units_tested.clear()
	_units_auto_passed.clear()

func _clear_battle_shocked_flags() -> void:
	# Per 10th edition: Clear battle-shocked status at the start of each Command Phase
	var current_player = get_current_player()
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != current_player:
			continue

		var was_shocked = unit.get("flags", {}).get("battle_shocked", false)
		if was_shocked:
			# Ensure flags dict exists before writing
			if not unit.has("flags"):
				unit["flags"] = {}
			unit["flags"]["battle_shocked"] = false
			print("CommandPhase: Cleared battle-shocked from %s" % unit_id)

	print("CommandPhase: Cleared battle-shocked flags for player %d" % current_player)

func _identify_units_needing_tests() -> void:
	_units_needing_test.clear()
	_units_tested.clear()

	var current_player = get_current_player()
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != current_player:
			continue

		# Skip destroyed units (no alive models)
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Skip undeployed units
		var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
		if status == GameStateData.UnitStatus.UNDEPLOYED:
			continue

		# Check if unit is below half-strength
		if GameState.is_below_half_strength(unit):
			_units_needing_test.append(unit_id)
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("CommandPhase: %s (%s) is below half-strength - needs battle-shock test" % [unit_name, unit_id])

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()

	# Offer battle-shock tests for units that haven't tested yet
	for unit_id in _units_needing_test:
		if unit_id in _units_tested:
			continue

		var unit = GameState.state.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var ld = unit.get("meta", {}).get("stats", {}).get("leadership", 7)

		actions.append({
			"type": "BATTLE_SHOCK_TEST",
			"unit_id": unit_id,
			"description": "Battle-shock test for %s (Ld %d)" % [unit_name, ld],
			"player": current_player
		})

		# Check if Insane Bravery is available for this unit
		var strat_manager = get_node_or_null("/root/StratagemManager")
		if strat_manager:
			var can_use = strat_manager.can_use_stratagem(current_player, "insane_bravery", unit_id)
			if can_use.can_use:
				actions.append({
					"type": "USE_STRATAGEM",
					"stratagem_id": "insane_bravery",
					"target_unit_id": unit_id,
					"description": "INSANE BRAVERY on %s (1 CP - auto-pass battle-shock)" % unit_name,
					"player": current_player
				})

	# Always allow ending command phase (but warn if tests remain)
	actions.append({
		"type": "END_COMMAND",
		"description": "End Command Phase",
		"player": current_player
	})

	return actions

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	var errors = []

	match action_type:
		"END_COMMAND":
			# END_COMMAND is always valid in command phase
			pass
		"BATTLE_SHOCK_TEST":
			errors = _validate_battle_shock_test(action)
		"USE_STRATAGEM":
			errors = _validate_use_stratagem(action)
		"DEBUG_MOVE":
			# Already validated by base class
			return {"valid": true, "errors": []}
		_:
			errors.append("Unknown action type: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func _validate_battle_shock_test(action: Dictionary) -> Array:
	var errors = []

	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		errors.append("Missing unit_id for battle-shock test")
		return errors

	# Unit must exist
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		errors.append("Unit not found: %s" % unit_id)
		return errors

	# Unit must belong to current player
	if unit.get("owner", 0) != get_current_player():
		errors.append("Unit %s does not belong to active player" % unit_id)

	# Unit must be in the needing-test list
	if unit_id not in _units_needing_test:
		errors.append("Unit %s does not need a battle-shock test" % unit_id)

	# Unit must not have already been tested this phase
	if unit_id in _units_tested:
		errors.append("Unit %s has already taken a battle-shock test this phase" % unit_id)

	return errors

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"END_COMMAND":
			return _handle_end_command()
		"BATTLE_SHOCK_TEST":
			return _handle_battle_shock_test(action)
		"USE_STRATAGEM":
			return _handle_use_stratagem(action)
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_battle_shock_test(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var leadership = unit.get("meta", {}).get("stats", {}).get("leadership", 7)

	# Roll 2D6 (allow override for testing via dice_roll parameter)
	var die1: int
	var die2: int
	if action.has("dice_roll"):
		# Accept pre-set roll for deterministic testing
		var roll = action.get("dice_roll", [])
		die1 = roll[0] if roll.size() > 0 else _rng.randi_range(1, 6)
		die2 = roll[1] if roll.size() > 1 else _rng.randi_range(1, 6)
	else:
		die1 = _rng.randi_range(1, 6)
		die2 = _rng.randi_range(1, 6)

	var roll_total = die1 + die2

	# Per 10th edition: if roll is below Leadership, the test FAILS
	# Roll >= Ld = pass, Roll < Ld = fail
	var test_passed = roll_total >= leadership

	# Mark unit as tested
	_units_tested.append(unit_id)

	# Apply battle-shocked flag if test failed
	if not test_passed:
		# Ensure flags dict exists
		if not unit.has("flags"):
			unit["flags"] = {}
		unit["flags"]["battle_shocked"] = true

		print("CommandPhase: %s FAILED battle-shock test (rolled %d+%d=%d vs Ld %d) - now Battle-shocked!" % [
			unit_name, die1, die2, roll_total, leadership
		])
	else:
		print("CommandPhase: %s PASSED battle-shock test (rolled %d+%d=%d vs Ld %d)" % [
			unit_name, die1, die2, roll_total, leadership
		])

	var result = {
		"success": true,
		"unit_id": unit_id,
		"unit_name": unit_name,
		"die1": die1,
		"die2": die2,
		"roll_total": roll_total,
		"leadership": leadership,
		"test_passed": test_passed,
		"battle_shocked": not test_passed,
		"message": "%s %s battle-shock test (rolled %d vs Ld %d)" % [
			unit_name,
			"passed" if test_passed else "FAILED",
			roll_total,
			leadership
		]
	}

	# Log the test result to phase log
	var log_entry = {
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"die1": die1,
		"die2": die2,
		"roll_total": roll_total,
		"leadership": leadership,
		"passed": test_passed,
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return result

# ============================================================================
# STRATAGEM HANDLING
# ============================================================================

func _validate_use_stratagem(action: Dictionary) -> Array:
	var errors = []
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")

	if stratagem_id == "":
		errors.append("Missing stratagem_id")
		return errors

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		errors.append("StratagemManager not available")
		return errors

	var current_player = get_current_player()
	var validation = strat_manager.can_use_stratagem(current_player, stratagem_id, target_unit_id)
	if not validation.can_use:
		errors.append(validation.reason)

	# For Insane Bravery: target must need a battle-shock test and not have been tested yet
	if stratagem_id == "insane_bravery":
		if target_unit_id == "":
			errors.append("Insane Bravery requires a target unit")
		elif target_unit_id not in _units_needing_test:
			errors.append("Unit %s does not need a battle-shock test" % target_unit_id)
		elif target_unit_id in _units_tested:
			errors.append("Unit %s has already taken a battle-shock test this phase" % target_unit_id)

	return errors

func _handle_use_stratagem(action: Dictionary) -> Dictionary:
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return {"success": false, "error": "StratagemManager not available"}

	# Use the stratagem (validates, deducts CP, records usage)
	var result = strat_manager.use_stratagem(current_player, stratagem_id, target_unit_id)
	if not result.success:
		return result

	# Apply stratagem-specific effects
	match stratagem_id:
		"insane_bravery":
			return _apply_insane_bravery(target_unit_id, result)
		_:
			print("CommandPhase: Stratagem %s used but no phase-specific handler" % stratagem_id)
			return result

func _apply_insane_bravery(unit_id: String, strat_result: Dictionary) -> Dictionary:
	"""Apply Insane Bravery: auto-pass the battle-shock test for the target unit."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Mark unit as tested (auto-passed)
	_units_tested.append(unit_id)
	_units_auto_passed.append(unit_id)

	# Unit passes automatically - no dice rolled, no battle-shocked flag set
	print("CommandPhase: %s AUTO-PASSED battle-shock test via INSANE BRAVERY!" % unit_name)

	# Log to phase log
	var log_entry = {
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"die1": 0,
		"die2": 0,
		"roll_total": 0,
		"leadership": unit.get("meta", {}).get("stats", {}).get("leadership", 7),
		"passed": true,
		"auto_passed": true,
		"stratagem": "insane_bravery",
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return {
		"success": true,
		"unit_id": unit_id,
		"unit_name": unit_name,
		"die1": 0,
		"die2": 0,
		"roll_total": 0,
		"leadership": unit.get("meta", {}).get("stats", {}).get("leadership", 7),
		"test_passed": true,
		"battle_shocked": false,
		"auto_passed": true,
		"stratagem_used": "insane_bravery",
		"message": "%s AUTO-PASSED battle-shock test (INSANE BRAVERY - 1 CP)" % unit_name
	}

func _handle_end_command() -> Dictionary:
	var current_player = get_current_player()

	# Auto-resolve any remaining battle-shock tests
	var auto_resolved = []
	for unit_id in _units_needing_test:
		if unit_id not in _units_tested:
			var auto_result = _handle_battle_shock_test({"unit_id": unit_id})
			auto_resolved.append(auto_result)

	if auto_resolved.size() > 0:
		print("CommandPhase: Auto-resolved %d remaining battle-shock test(s)" % auto_resolved.size())

	print("CommandPhase: Player %d ending command phase" % current_player)

	# Score primary objectives before ending phase
	if MissionManager:
		MissionManager.score_primary_objectives()

	# Emit phase completion signal to proceed to next phase
	emit_signal("phase_completed")

	return {
		"success": true,
		"message": "Command phase ended, objectives scored",
		"auto_resolved_tests": auto_resolved
	}

func _should_complete_phase() -> bool:
	# Don't auto-complete - phase completion will be triggered by END_COMMAND action
	return false
