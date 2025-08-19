extends BasePhase
class_name MoralePhase

# MoralePhase - Stub implementation for the Morale phase
# This is a placeholder that can be expanded with full morale mechanics

func _init():
	phase_type = GameStateData.Phase.MORALE

func _on_phase_enter() -> void:
	log_phase_message("Entering Morale Phase")
	
	# Initialize morale phase state
	_initialize_morale()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Morale Phase")

func _initialize_morale() -> void:
	# Check if there are any units that need to take morale tests
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	var units_needing_morale = []
	for unit_id in units:
		var unit = units[unit_id]
		if _unit_needs_morale_test(unit):
			units_needing_morale.append(unit_id)
	
	if units_needing_morale.size() == 0:
		log_phase_message("No units need morale tests, completing phase")
		emit_signal("phase_completed")
	else:
		log_phase_message("Found %d units needing morale tests" % units_needing_morale.size())

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"MORALE_TEST":
			return _validate_morale_test_action(action)
		"USE_STRATAGEM":
			return _validate_use_stratagem_action(action)
		"SKIP_MORALE":
			return _validate_skip_morale_action(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func _validate_morale_test_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check required fields
	var required_fields = ["unit_id", "morale_roll"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var morale_roll = action.morale_roll
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}
	
	# Check if unit belongs to active player
	if unit.get("owner", 0) != get_current_player():
		errors.append("Unit does not belong to active player")
	
	# Check if unit needs a morale test
	if not _unit_needs_morale_test(unit):
		errors.append("Unit does not need a morale test")
	
	# Validate morale roll (should be 1-6 on a D6)
	if morale_roll < 1 or morale_roll > 6:
		errors.append("Invalid morale roll: " + str(morale_roll))
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_use_stratagem_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	var required_fields = ["stratagem_id", "target_unit_id"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var stratagem_id = action.stratagem_id
	var target_unit_id = action.target_unit_id
	
	var unit = get_unit(target_unit_id)
	if unit.is_empty():
		errors.append("Target unit not found: " + target_unit_id)
		return {"valid": false, "errors": errors}
	
	# TODO: Add stratagem validation
	# - Check if player has enough command points
	# - Check if stratagem is applicable in morale phase
	# - Check stratagem restrictions and targeting
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_skip_morale_action(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	# Check if unit actually can skip morale (e.g., special rules)
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "FEARLESS" in keywords or "ATSKNF" in keywords:
		return {"valid": true, "errors": []}
	else:
		return {"valid": false, "errors": ["Unit cannot skip morale test"]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"MORALE_TEST":
			return _process_morale_test(action)
		"USE_STRATAGEM":
			return _process_use_stratagem(action)
		"SKIP_MORALE":
			return _process_skip_morale(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

func _process_morale_test(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var morale_roll = action.morale_roll
	var changes = []
	
	var unit = get_unit(unit_id)
	var casualties_this_turn = unit.get("casualties_this_turn", 0)
	var current_ld = unit.get("meta", {}).get("stats", {}).get("leadership", 7)
	
	# Calculate morale test result
	var morale_value = casualties_this_turn + morale_roll
	var morale_passed = morale_value <= current_ld
	
	if morale_passed:
		log_phase_message("Unit %s passed morale test (%d vs Ld %d)" % [unit_id, morale_value, current_ld])
	else:
		var additional_casualties = morale_value - current_ld
		log_phase_message("Unit %s failed morale test, %d additional casualties" % [unit_id, additional_casualties])
		
		# TODO: Remove additional models due to morale failure
		# For now, just record the failure
		changes.append({
			"op": "set",
			"path": "units.%s.morale_casualties" % unit_id,
			"value": additional_casualties
		})
	
	# Mark unit as having taken morale test
	changes.append({
		"op": "set",
		"path": "units.%s.morale_tested" % unit_id,
		"value": true
	})
	
	# Record the test result
	changes.append({
		"op": "add",
		"path": "units.%s.morale_tests" % unit_id,
		"value": {
			"roll": morale_roll,
			"casualties": casualties_this_turn,
			"leadership": current_ld,
			"passed": morale_passed,
			"turn": get_turn_number()
		}
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	return create_result(true, changes)

func _process_use_stratagem(action: Dictionary) -> Dictionary:
	var stratagem_id = action.stratagem_id
	var target_unit_id = action.target_unit_id
	var changes = []
	
	# TODO: Implement actual stratagem effects
	# For now, just record that stratagem was used
	
	var current_player = get_current_player()
	
	# Deduct command points (assuming cost of 1 for now)
	changes.append({
		"op": "set",
		"path": "players.%d.cp" % current_player,
		"value": max(0, game_state_snapshot.get("players", {}).get(str(current_player), {}).get("cp", 0) - 1)
	})
	
	# Record stratagem usage
	changes.append({
		"op": "add",
		"path": "players.%d.stratagems_used" % current_player,
		"value": {
			"id": stratagem_id,
			"target": target_unit_id,
			"phase": "morale",
			"turn": get_turn_number()
		}
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	log_phase_message("Used stratagem %s on %s" % [stratagem_id, target_unit_id])
	return create_result(true, changes)

func _process_skip_morale(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var changes = []
	
	# Mark unit as having resolved morale (skipped)
	changes.append({
		"op": "set",
		"path": "units.%s.morale_tested" % unit_id,
		"value": true
	})
	
	changes.append({
		"op": "set",
		"path": "units.%s.morale_skipped" % unit_id,
		"value": true
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	log_phase_message("Skipped morale test for %s (special rule)" % unit_id)
	return create_result(true, changes)

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _unit_needs_morale_test(unit):
			var morale_tested = unit.get("morale_tested", false)
			
			if not morale_tested:
				# Check if unit can skip morale
				var keywords = unit.get("meta", {}).get("keywords", [])
				if "FEARLESS" in keywords or "ATSKNF" in keywords:
					actions.append({
						"type": "SKIP_MORALE",
						"unit_id": unit_id,
						"description": "Skip morale for " + unit.get("meta", {}).get("name", unit_id) + " (special rule)"
					})
				else:
					# Normal morale test
					actions.append({
						"type": "MORALE_TEST",
						"unit_id": unit_id,
						"description": "Take morale test for " + unit.get("meta", {}).get("name", unit_id)
					})
				
				# Stratagem options (example)
				var player_cp = game_state_snapshot.get("players", {}).get(str(current_player), {}).get("cp", 0)
				if player_cp > 0:
					actions.append({
						"type": "USE_STRATAGEM",
						"stratagem_id": "insane_bravery",
						"target_unit_id": unit_id,
						"description": "Use Insane Bravery on " + unit.get("meta", {}).get("name", unit_id)
					})
	
	return actions

func _should_complete_phase() -> bool:
	# Phase completes when all units have resolved morale
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _unit_needs_morale_test(unit):
			var morale_tested = unit.get("morale_tested", false)
			if not morale_tested:
				return false  # Still units that need morale tests
	
	return true

# Helper methods
func _unit_needs_morale_test(unit: Dictionary) -> bool:
	# Unit needs morale test if it lost models this turn
	var casualties_this_turn = unit.get("casualties_this_turn", 0)
	var models = unit.get("models", [])
	
	# Check if unit has any models alive
	var models_alive = 0
	for model in models:
		if model.get("alive", true):
			models_alive += 1
	
	# Need morale test if lost models and still have models remaining
	return casualties_this_turn > 0 and models_alive > 0

func _calculate_morale_modifiers(unit: Dictionary) -> Dictionary:
	var modifiers = {
		"leadership_bonus": 0,
		"reroll_allowed": false,
		"auto_pass": false,
		"description": []
	}
	
	# TODO: Implement morale modifiers based on:
	# - Unit keywords and special rules
	# - Nearby characters and banners
	# - Battlefield conditions
	# - Stratagems in effect
	
	var keywords = unit.get("meta", {}).get("keywords", [])
	
	if "FEARLESS" in keywords:
		modifiers.auto_pass = true
		modifiers.description.append("Fearless")
	
	if "ATSKNF" in keywords:
		modifiers.reroll_allowed = true
		modifiers.description.append("And They Shall Know No Fear")
	
	return modifiers

# TODO: Add helper methods for morale mechanics
# func _remove_morale_casualties(unit: Dictionary, casualties: int) -> Array
# func _check_unit_destroyed(unit: Dictionary) -> bool
# func _apply_morale_stratagem(stratagem_id: String, unit: Dictionary) -> Dictionary
# func _find_nearby_characters(unit: Dictionary) -> Array