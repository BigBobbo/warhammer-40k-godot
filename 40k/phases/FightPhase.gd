extends BasePhase
class_name FightPhase

# FightPhase - Stub implementation for the Fight phase
# This is a placeholder that can be expanded with full combat mechanics

func _init():
	phase_type = GameStateData.Phase.FIGHT

func _on_phase_enter() -> void:
	log_phase_message("Entering Fight Phase")
	
	# Initialize fight phase state
	_initialize_fight()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Fight Phase")

func _initialize_fight() -> void:
	# Check if there are any units in combat
	var all_units = game_state_snapshot.get("units", {})
	var units_in_combat = []
	
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if _is_unit_in_combat(unit):
			units_in_combat.append(unit_id)
	
	if units_in_combat.size() == 0:
		log_phase_message("No units in combat, completing phase")
		emit_signal("phase_completed")
	else:
		log_phase_message("Found %d units in combat" % units_in_combat.size())

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"FIGHT_UNIT":
			return _validate_fight_unit_action(action)
		"PILE_IN":
			return _validate_pile_in_action(action)
		"CONSOLIDATE":
			return _validate_consolidate_action(action)
		"HEROIC_INTERVENTION":
			return _validate_heroic_intervention_action(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func _validate_fight_unit_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check required fields
	var required_fields = ["unit_id", "target_unit_id"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var target_unit_id = action.target_unit_id
	
	var unit = get_unit(unit_id)
	var target_unit = get_unit(target_unit_id)
	
	# Check if units exist
	if unit.is_empty():
		errors.append("Fighting unit not found: " + unit_id)
	if target_unit.is_empty():
		errors.append("Target unit not found: " + target_unit_id)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	# Check if unit is in combat
	if not _is_unit_in_combat(unit):
		errors.append("Unit is not in combat")
	
	# Check if units are enemies
	if unit.get("owner", 0) == target_unit.get("owner", 0):
		errors.append("Cannot fight units from the same army")
	
	# Check if units are within engagement range
	if not _units_in_engagement_range(unit, target_unit):
		errors.append("Units are not within engagement range")
	
	# TODO: Add more detailed fight validation
	# - Check if unit has already fought this turn
	# - Check weapon eligibility
	# - Check special combat rules
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_pile_in_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	var required_fields = ["unit_id", "new_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var unit = get_unit(unit_id)
	
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}
	
	# Check if unit is in combat
	if not _is_unit_in_combat(unit):
		errors.append("Unit is not in combat and cannot pile in")
	
	# TODO: Add pile-in specific validation
	# - Check 3" movement limit
	# - Check that unit moves closer to nearest enemy
	# - Check coherency after pile-in
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_consolidate_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	var required_fields = ["unit_id", "new_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var unit = get_unit(unit_id)
	
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}
	
	# Check if unit has fought this turn
	var has_fought = unit.get("has_fought", false)
	if not has_fought:
		errors.append("Unit has not fought this turn and cannot consolidate")
	
	# TODO: Add consolidate specific validation
	# - Check 3" movement limit
	# - Check that unit can move towards nearest enemy
	# - Check coherency after consolidation
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_heroic_intervention_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	var required_fields = ["unit_id", "new_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var unit = get_unit(unit_id)
	
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}
	
	# Check if unit is a character
	var keywords = unit.get("meta", {}).get("keywords", [])
	if not "CHARACTER" in keywords:
		errors.append("Only characters can perform heroic interventions")
	
	# TODO: Add heroic intervention specific validation
	# - Check 6" range from enemy units
	# - Check that character is not already in combat
	# - Check timing (at start of fight phase)
	
	return {"valid": errors.size() == 0, "errors": errors}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"FIGHT_UNIT":
			return _process_fight_unit(action)
		"PILE_IN":
			return _process_pile_in(action)
		"CONSOLIDATE":
			return _process_consolidate(action)
		"HEROIC_INTERVENTION":
			return _process_heroic_intervention(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

func _process_fight_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var target_unit_id = action.target_unit_id
	var changes = []
	
	# TODO: Implement actual combat resolution
	# - Roll to hit
	# - Roll to wound
	# - Target saves
	# - Apply damage
	# - Remove casualties
	# - Check morale if needed
	
	# For now, just mark unit as having fought
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.FOUGHT
	})
	
	changes.append({
		"op": "set",
		"path": "units.%s.has_fought" % unit_id,
		"value": true
	})
	
	# Record the combat
	changes.append({
		"op": "add",
		"path": "units.%s.combat_actions" % unit_id,
		"value": {
			"type": "fight",
			"target": target_unit_id,
			"turn": get_turn_number()
		}
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("%s fought %s" % [unit_name, target_unit_id])
	
	return create_result(true, changes)

func _process_pile_in(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var new_positions = action.new_positions
	var changes = []
	
	# Update model positions
	for i in range(new_positions.size()):
		var pos = new_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})
	
	# Mark as piled in
	changes.append({
		"op": "set",
		"path": "units.%s.piled_in" % unit_id,
		"value": true
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	log_phase_message("Unit %s piled in" % unit_id)
	return create_result(true, changes)

func _process_consolidate(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var new_positions = action.new_positions
	var changes = []
	
	# Update model positions
	for i in range(new_positions.size()):
		var pos = new_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})
	
	# Mark as consolidated
	changes.append({
		"op": "set",
		"path": "units.%s.consolidated" % unit_id,
		"value": true
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	log_phase_message("Unit %s consolidated" % unit_id)
	return create_result(true, changes)

func _process_heroic_intervention(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var new_positions = action.new_positions
	var changes = []
	
	# Update model positions
	for i in range(new_positions.size()):
		var pos = new_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})
	
	# Mark as having performed heroic intervention
	changes.append({
		"op": "set",
		"path": "units.%s.heroic_intervention" % unit_id,
		"value": true
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	log_phase_message("Character %s performed heroic intervention" % unit_id)
	return create_result(true, changes)

func get_available_actions() -> Array:
	var actions = []
	var all_units = game_state_snapshot.get("units", {})
	
	# Find units in combat
	for unit_id in all_units:
		var unit = all_units[unit_id]
		
		if _is_unit_in_combat(unit):
			var unit_owner = unit.get("owner", 0)
			var has_fought = unit.get("has_fought", false)
			
			if not has_fought:
				# Find enemy units in engagement range
				var enemy_targets = _find_enemies_in_engagement_range(unit)
				for target_unit_id in enemy_targets:
					actions.append({
						"type": "FIGHT_UNIT",
						"unit_id": unit_id,
						"target_unit_id": target_unit_id,
						"description": "Fight: %s -> %s" % [unit.get("meta", {}).get("name", unit_id), target_unit_id]
					})
				
				# Pile in option
				actions.append({
					"type": "PILE_IN",
					"unit_id": unit_id,
					"description": "Pile in with " + unit.get("meta", {}).get("name", unit_id)
				})
			else:
				# Unit has fought, can consolidate
				actions.append({
					"type": "CONSOLIDATE",
					"unit_id": unit_id,
					"description": "Consolidate " + unit.get("meta", {}).get("name", unit_id)
				})
	
	return actions

func _should_complete_phase() -> bool:
	# Phase completes when all combats are resolved
	var all_units = game_state_snapshot.get("units", {})
	
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if _is_unit_in_combat(unit):
			var has_fought = unit.get("has_fought", false)
			if not has_fought:
				return false  # Still units that need to fight
	
	return true

# Helper methods
func _is_unit_in_combat(unit: Dictionary) -> bool:
	# TODO: Implement proper combat detection
	# For now, check if unit is marked as charged or in base contact
	var status = unit.get("status", 0)
	return status == GameStateData.UnitStatus.CHARGED

func _units_in_engagement_range(unit1: Dictionary, unit2: Dictionary) -> bool:
	# TODO: Implement proper engagement range calculation
	# For now, return true if both units exist
	return not unit1.is_empty() and not unit2.is_empty()

func _find_enemies_in_engagement_range(unit: Dictionary) -> Array:
	var enemies = []
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)
	
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		var other_owner = other_unit.get("owner", 0)
		
		if other_owner != unit_owner and _units_in_engagement_range(unit, other_unit):
			enemies.append(other_unit_id)
	
	return enemies

# TODO: Add helper methods for combat mechanics
# func _calculate_engagement_range(unit1: Dictionary, unit2: Dictionary) -> float
# func _roll_to_hit_melee(weapon_skill: int, modifiers: Dictionary) -> Array
# func _roll_to_wound_melee(strength: int, toughness: int, modifiers: Dictionary) -> Array
# func _resolve_combat(attacker: Dictionary, defender: Dictionary, weapon: Dictionary) -> Dictionary
# func _determine_fight_order(units_in_combat: Array) -> Array