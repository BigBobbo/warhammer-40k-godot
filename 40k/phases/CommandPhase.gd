extends BasePhase
class_name CommandPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# CommandPhase - Handles Command Phase including Battle-shock tests
# Per 10th edition rules:
# 1. Clear all battle_shocked flags at the start of the Command Phase
# 2. Identify units Below Half-strength
# 3. Each Below Half-strength unit takes a Battle-shock test (2D6 vs Leadership)
# 4. If the roll is below the unit's Leadership, the unit becomes Battle-shocked
# 5. Score primary objectives and end the phase

# Track which units still need battle-shock tests this phase
var _units_needing_test: Array = []
var _units_tested: Array = []
var _rng: RandomNumberGenerator

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.COMMAND
	print("CommandPhase: Entering command phase for player ", get_current_player())
	print("CommandPhase: Battle round ", GameState.get_battle_round())

	# Step 1: Clear all battle_shocked flags for the current player's units
	_clear_battle_shocked_flags()

	# Step 2: Identify units below half-strength that need battle-shock tests
	_identify_units_needing_tests()

	# Step 3: Check objectives at start of command phase
	if MissionManager:
		MissionManager.check_all_objectives()

	if _units_needing_test.size() == 0:
		print("CommandPhase: No units need battle-shock tests")
	else:
		print("CommandPhase: %d unit(s) need battle-shock tests" % _units_needing_test.size())

func _on_phase_exit() -> void:
	print("CommandPhase: Exiting command phase")
	_units_needing_test.clear()
	_units_tested.clear()

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
			"player": get_current_player()
		})

	# Always allow ending command phase (but warn if tests remain)
	actions.append({
		"type": "END_COMMAND",
		"description": "End Command Phase",
		"player": get_current_player()
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
