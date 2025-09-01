extends BasePhase
class_name FightPhase

# FightPhase - Full implementation for the Fight phase following 10e rules
# Supports fight sequencing, pile in, attack resolution, and consolidation

# Signals (mirror ShootingPhase pattern)
signal unit_selected_for_fighting(unit_id: String)
signal fighter_selected(unit_id: String)  # Alias for compatibility
signal targets_available(unit_id: String, targets: Array)  # For UI updates
signal fight_resolved(unit_id: String, target_id: String, result: Dictionary)  # Alias for attacks_resolved
signal fight_sequence_updated(sequence: Array)  # For UI updates
signal pile_in_preview(unit_id: String, movements: Dictionary)
signal attacks_resolved(unit_id: String, target_id: String, result: Dictionary)
signal consolidate_preview(unit_id: String, movements: Dictionary)
signal dice_rolled(dice_data: Dictionary)
signal fight_order_determined(fight_sequence: Array)

# Fight state tracking
var active_fighter_id: String = ""
var selected_weapon_id: String = ""  # Currently selected weapon for active fighter
var fight_sequence: Array = []  # Ordered list of units to fight
var current_fight_index: int = 0
var pending_attacks: Array = []
var confirmed_attacks: Array = []
var resolution_state: Dictionary = {}
var dice_log: Array = []
var units_that_fought: Array = []

# Fight priority tiers
enum FightPriority {
	FIGHTS_FIRST = 0,  # Charged units + abilities
	NORMAL = 1,
	FIGHTS_LAST = 2
}

func _init():
	phase_type = GameStateData.Phase.FIGHT

func _on_phase_enter() -> void:
	log_phase_message("Entering Fight Phase")
	# Clear previous state
	active_fighter_id = ""
	fight_sequence.clear()
	current_fight_index = 0
	pending_attacks.clear()
	confirmed_attacks.clear()
	resolution_state.clear()
	dice_log.clear()
	units_that_fought.clear()
	
	_initialize_fight_sequence()
	_check_for_combats()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Fight Phase")
	# Clear any temporary fight data
	for unit_id in units_that_fought:
		_clear_unit_fight_state(unit_id)

func _initialize_fight_sequence() -> void:
	# Build fight order: Fights First -> Normal -> Fights Last
	var fights_first = []
	var normal = []
	var fights_last = []
	
	var all_units = game_state_snapshot.get("units", {})
	log_phase_message("Checking %d units for combat eligibility" % all_units.size())
	
	for unit_id in all_units:
		var unit = all_units[unit_id]
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var models_alive = 0
		for model in unit.get("models", []):
			if model.get("alive", true):
				models_alive += 1
		
		log_phase_message("Unit %s has %d alive models" % [unit_name, models_alive])
		
		if _is_unit_in_combat(unit):
			log_phase_message("Unit %s is in combat!" % unit_name)
			var priority = _get_fight_priority(unit)
			match priority:
				FightPriority.FIGHTS_FIRST:
					fights_first.append(unit_id)
					log_phase_message("Added %s to FIGHTS_FIRST" % unit_name)
				FightPriority.NORMAL:
					normal.append(unit_id)
					log_phase_message("Added %s to NORMAL" % unit_name)
				FightPriority.FIGHTS_LAST:
					fights_last.append(unit_id)
					log_phase_message("Added %s to FIGHTS_LAST" % unit_name)
		else:
			log_phase_message("Unit %s is NOT in combat" % unit_name)
	
	# Build alternating sequence for each tier
	log_phase_message("Building fight sequence from:")
	log_phase_message("  fights_first: %s" % str(fights_first))
	log_phase_message("  normal: %s" % str(normal))
	log_phase_message("  fights_last: %s" % str(fights_last))
	
	fight_sequence = _build_alternating_sequence(fights_first)
	fight_sequence.append_array(_build_alternating_sequence(normal))
	fight_sequence.append_array(_build_alternating_sequence(fights_last))
	
	log_phase_message("Final fight_sequence: %s" % str(fight_sequence))
	log_phase_message("current_fight_index: %d" % current_fight_index)
	
	emit_signal("fight_order_determined", fight_sequence)
	emit_signal("fight_sequence_updated", fight_sequence)  # Compatibility signal

func _check_for_combats() -> void:
	if fight_sequence.size() == 0:
		log_phase_message("No units in combat, completing phase")
		emit_signal("phase_completed")
	else:
		log_phase_message("Found %d units in fight sequence" % fight_sequence.size())
		if fight_sequence.size() > 0:
			log_phase_message("First to fight: %s" % fight_sequence[0])

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"SELECT_FIGHTER":
			return _validate_select_fighter(action)
		"SELECT_MELEE_WEAPON":
			return _validate_select_melee_weapon(action)
		"PILE_IN":
			return _validate_pile_in(action)
		"ASSIGN_ATTACKS":
			return _validate_assign_attacks(action)
		"CONFIRM_AND_RESOLVE_ATTACKS":
			return _validate_confirm_and_resolve_attacks(action)
		"CONSOLIDATE":
			return _validate_consolidate(action)
		"SKIP_UNIT":
			return _validate_skip_unit(action)
		"HEROIC_INTERVENTION":
			return _validate_heroic_intervention_action(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"SELECT_FIGHTER":
			return _process_select_fighter(action)
		"SELECT_MELEE_WEAPON":
			return _process_select_melee_weapon(action)
		"PILE_IN":
			return _process_pile_in(action)
		"ASSIGN_ATTACKS":
			return _process_assign_attacks(action)
		"CONFIRM_AND_RESOLVE_ATTACKS":
			return _process_confirm_and_resolve_attacks(action)
		"CONSOLIDATE":
			return _process_consolidate(action)
		"SKIP_UNIT":
			return _process_skip_unit(action)
		"HEROIC_INTERVENTION":
			return _process_heroic_intervention(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# Action validation methods
func _validate_select_fighter(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var errors = []
	
	# Check if unit_id is provided
	if unit_id == "":
		errors.append("Missing unit_id")
		return {"valid": false, "errors": errors}
	
	# Check if fight sequence is empty
	if fight_sequence.is_empty():
		errors.append("No fight sequence established")
		return {"valid": false, "errors": errors}
	
	# Check it's this unit's turn in sequence
	if current_fight_index >= fight_sequence.size():
		errors.append("All units have fought")
		return {"valid": false, "errors": errors}
	
	if fight_sequence[current_fight_index] != unit_id:
		errors.append("Not this unit's turn to fight (expected: %s)" % fight_sequence[current_fight_index])
		return {"valid": false, "errors": errors}
	
	# Check unit hasn't already fought
	if unit_id in units_that_fought:
		errors.append("Unit has already fought")
		return {"valid": false, "errors": errors}
	
	# Check unit exists and is in engagement range
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found")
		return {"valid": false, "errors": errors}
	
	if not _is_unit_in_combat(unit):
		errors.append("Unit not in engagement range")
		return {"valid": false, "errors": errors}
	
	return {"valid": true}

func _validate_select_melee_weapon(action: Dictionary) -> Dictionary:
	var weapon_id = action.get("weapon_id", "")
	var unit_id = action.get("unit_id", "")
	var errors = []
	
	if weapon_id == "":
		errors.append("Missing weapon_id")
	if unit_id == "":
		errors.append("Missing unit_id")
	if unit_id != active_fighter_id:
		errors.append("Can only select weapons for active fighter")
	
	# Validate weapon exists for this unit
	var melee_weapons = RulesEngine.get_unit_melee_weapons(unit_id, game_state_snapshot)
	if not melee_weapons.has(weapon_id):
		errors.append("Weapon not available for this unit: " + weapon_id)
	
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_pile_in(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})  # model_id -> new_position
	var errors = []
	
	# Check unit is active fighter
	if unit_id != active_fighter_id:
		errors.append("Not the active fighter")
		return {"valid": false, "errors": errors}
	
	# Validate each model movement
	for model_id in movements:
		var old_pos = _get_model_position(unit_id, model_id)
		var new_pos = movements[model_id]
		
		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % model_id)
			continue
		
		# Check 3" movement limit
		var distance = Measurement.distance_inches(old_pos, new_pos)
		if distance > 3.0:
			errors.append("Model %s pile in exceeds 3\" limit (%.1f\")" % [model_id, distance])
		
		# Check movement is toward closest enemy
		if not _is_moving_toward_closest_enemy(unit_id, model_id, old_pos, new_pos):
			errors.append("Model %s must pile in toward closest enemy" % model_id)
	
	# Check unit coherency maintained
	var coherency_check = _validate_unit_coherency(unit_id, movements)
	if not coherency_check.get("valid", false):
		errors.append_array(coherency_check.get("errors", []))
	
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_assign_attacks(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var target_id = action.get("target_id", "")
	var weapon_id = action.get("weapon_id", "")
	var errors = []
	
	# Check unit is active fighter
	if unit_id != active_fighter_id:
		errors.append("Not the active fighter")
		return {"valid": false, "errors": errors}
	
	# Check required fields
	if target_id == "":
		errors.append("Missing target_id")
	if weapon_id == "":
		errors.append("Missing weapon_id")
	
	if not errors.is_empty():
		return {"valid": false, "errors": errors}
	
	# Check units exist
	var unit = get_unit(unit_id)
	var target_unit = get_unit(target_id)
	
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
	if target_unit.is_empty():
		errors.append("Target unit not found: " + target_id)
	
	if not errors.is_empty():
		return {"valid": false, "errors": errors}
	
	# Check units are enemies
	if unit.get("owner", 0) == target_unit.get("owner", 0):
		errors.append("Cannot fight units from the same army")
	
	# Check units are within engagement range
	if not _units_in_engagement_range(unit, target_unit):
		errors.append("Units are not within engagement range")
	
	# Check weapon exists and is melee
	var weapon = RulesEngine.get_weapon_profile(weapon_id)
	if weapon.is_empty():
		errors.append("Weapon not found: " + weapon_id)
	elif weapon.get("type", "") != "melee":
		errors.append("Weapon is not a melee weapon: " + weapon_id)
	
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_confirm_and_resolve_attacks(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check there are pending attacks
	if pending_attacks.is_empty():
		errors.append("No attacks assigned")
	
	# Check active fighter is set
	if active_fighter_id == "":
		errors.append("No active fighter selected")
	
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_consolidate(action: Dictionary) -> Dictionary:
	# Identical validation to pile in but happens after fighting
	var unit_id = action.get("unit_id", "")
	var errors = []
	
	# Check unit is active fighter and has fought
	if unit_id != active_fighter_id:
		errors.append("Not the active fighter")
		return {"valid": false, "errors": errors}
	
	# Unit must have resolved attacks (pending_attacks should be empty)
	if not pending_attacks.is_empty():
		errors.append("Must resolve attacks before consolidating")
	
	# Use same movement validation as pile in
	return _validate_pile_in(action)

func _validate_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var errors = []
	
	# Check it's this unit's turn
	if current_fight_index >= fight_sequence.size():
		errors.append("All units have fought")
		return {"valid": false, "errors": errors}
	
	if fight_sequence[current_fight_index] != unit_id:
		errors.append("Not this unit's turn to fight")
	
	return {"valid": errors.is_empty(), "errors": errors}

# Action processing methods
func _process_select_fighter(action: Dictionary) -> Dictionary:
	active_fighter_id = action.unit_id
	
	# Get eligible targets (enemy units within engagement)
	var targets = _get_eligible_melee_targets(active_fighter_id)
	emit_signal("unit_selected_for_fighting", active_fighter_id)
	emit_signal("fighter_selected", active_fighter_id)  # Compatibility signal
	emit_signal("targets_available", active_fighter_id, targets)
	
	log_phase_message("Selected %s to fight" % active_fighter_id)
	return create_result(true, [])

func _process_select_melee_weapon(action: Dictionary) -> Dictionary:
	var weapon_id = action.get("weapon_id", "")
	var unit_id = action.get("unit_id", "")
	
	# Store the selected weapon for this fighter
	selected_weapon_id = weapon_id
	
	# Get eligible targets now that we have a weapon selected
	var targets = _get_eligible_melee_targets(unit_id)
	emit_signal("weapon_selected", unit_id, weapon_id)
	emit_signal("targets_available", unit_id, targets)
	
	log_phase_message("Selected weapon %s for %s" % [weapon_id, unit_id])
	return create_result(true, [])

func _process_pile_in(action: Dictionary) -> Dictionary:
	var changes = []
	var movements = action.get("movements", {})
	
	for model_id in movements:
		var new_pos = movements[model_id]
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [action.unit_id, model_id],
			"value": {"x": new_pos.x, "y": new_pos.y}
		})
	
	emit_signal("pile_in_preview", action.unit_id, movements)
	log_phase_message("Unit %s piled in" % action.unit_id)
	return create_result(true, changes)

func _process_assign_attacks(action: Dictionary) -> Dictionary:
	# Mirror ShootingPhase weapon assignment pattern
	var unit_id = action.get("unit_id", "")
	var target_id = action.get("target_id", "")
	var weapon_id = action.get("weapon_id", "")
	
	pending_attacks.append({
		"attacker": unit_id,
		"target": target_id,
		"weapon": weapon_id,
		"models": action.get("attacking_models", [])
	})
	
	log_phase_message("Assigned %s attacks to %s" % [weapon_id, target_id])
	return create_result(true, [])

func _process_confirm_and_resolve_attacks(action: Dictionary) -> Dictionary:
	confirmed_attacks = pending_attacks.duplicate(true)
	pending_attacks.clear()
	
	emit_signal("fighting_begun", active_fighter_id)
	
	# AUTO-RESOLVE like ShootingPhase
	var melee_action = {
		"type": "FIGHT",
		"actor_unit_id": active_fighter_id,
		"payload": {
			"assignments": confirmed_attacks
		}
	}
	
	var rng_service = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_melee_attacks(melee_action, game_state_snapshot, rng_service)
	
	# Process casualties and state changes
	if result.success:
		_apply_combat_results(result)
		if not confirmed_attacks.is_empty():
			emit_signal("attacks_resolved", active_fighter_id, confirmed_attacks[0].target, result)
			emit_signal("fight_resolved", active_fighter_id, confirmed_attacks[0].target, result)  # Compatibility signal
		emit_signal("dice_rolled", result.get("dice", {}))
	
	log_phase_message("Combat resolved for %s" % active_fighter_id)
	return result

func _process_consolidate(action: Dictionary) -> Dictionary:
	var result = _process_pile_in(action)  # Reuse pile in logic
	
	# Mark unit as complete and advance fight sequence
	units_that_fought.append(action.unit_id)
	active_fighter_id = ""
	current_fight_index += 1
	confirmed_attacks.clear()
	
	# Check if more units to fight
	if current_fight_index < fight_sequence.size():
		var next_unit = fight_sequence[current_fight_index]
		log_phase_message("Next to fight: %s" % next_unit)
	else:
		log_phase_message("All units have fought, phase complete")
		emit_signal("phase_completed")
	
	return result

func _process_skip_unit(action: Dictionary) -> Dictionary:
	# Skip this unit and advance to next
	units_that_fought.append(action.unit_id)
	current_fight_index += 1
	
	if current_fight_index < fight_sequence.size():
		var next_unit = fight_sequence[current_fight_index]
		log_phase_message("Skipped %s, next to fight: %s" % [action.unit_id, next_unit])
	else:
		log_phase_message("All units processed, phase complete")
		emit_signal("phase_completed")
	
	return create_result(true, [])

func _process_heroic_intervention(action: Dictionary) -> Dictionary:
	# Placeholder for heroic intervention
	log_phase_message("Heroic intervention not yet implemented")
	return create_result(false, [], "Heroic intervention not implemented")

# Helper methods
func _get_fight_priority(unit: Dictionary) -> int:
	# Check if unit charged this turn
	if unit.get("flags", {}).get("charged_this_turn", false):
		return FightPriority.FIGHTS_FIRST
	
	# Check for Fights First ability
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		if "fights_first" in str(ability).to_lower():
			return FightPriority.FIGHTS_FIRST
	
	# Check for Fights Last debuff
	if unit.get("status_effects", {}).get("fights_last", false):
		return FightPriority.FIGHTS_LAST
	
	return FightPriority.NORMAL

func _build_alternating_sequence(units: Array) -> Array:
	# Build alternating sequence by player for fair activation
	var player1_units = []
	var player2_units = []
	
	for unit_id in units:
		var unit = get_unit(unit_id)
		var owner = unit.get("owner", 0)
		if owner == 0:
			player1_units.append(unit_id)
		else:
			player2_units.append(unit_id)
	
	# Alternate between players
	var alternating = []
	var max_units = max(player1_units.size(), player2_units.size())
	for i in max_units:
		if i < player1_units.size():
			alternating.append(player1_units[i])
		if i < player2_units.size():
			alternating.append(player2_units[i])
	
	return alternating

func _get_eligible_melee_targets(unit_id: String) -> Dictionary:
	var targets = {}
	var unit = get_unit(unit_id)
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)
	
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		var other_owner = other_unit.get("owner", 0)
		
		if other_owner != unit_owner and _units_in_engagement_range(unit, other_unit):
			targets[other_unit_id] = {
				"name": other_unit.get("meta", {}).get("name", other_unit_id),
				"owner": other_owner
			}
	
	return targets

func _get_model_position(unit_id: String, model_id: String) -> Vector2:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	
	for i in models.size():
		var model = models[i]
		if str(i) == model_id or model.get("id", "") == model_id:
			var pos = model.get("position", {})
			return Vector2(pos.get("x", 0), pos.get("y", 0))
	
	return Vector2.ZERO

func _is_moving_toward_closest_enemy(unit_id: String, model_id: String, old_pos: Vector2, new_pos: Vector2) -> bool:
	# Find closest enemy model
	var closest_enemy_pos = _find_closest_enemy_position(unit_id, old_pos)
	if closest_enemy_pos == Vector2.ZERO:
		return true  # No enemies found, allow movement
	
	# Check if new position is closer to enemy than old position
	var old_distance = old_pos.distance_to(closest_enemy_pos)
	var new_distance = new_pos.distance_to(closest_enemy_pos)
	return new_distance <= old_distance

func _find_closest_enemy_position(unit_id: String, from_pos: Vector2) -> Vector2:
	var unit = get_unit(unit_id)
	var unit_owner = unit.get("owner", 0)
	var all_units = game_state_snapshot.get("units", {})
	var closest_pos = Vector2.ZERO
	var closest_distance = INF
	
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit.get("owner", 0) == unit_owner:
			continue  # Skip same army
		
		var models = other_unit.get("models", [])
		for model in models:
			if not model.get("alive", true):
				continue
			
			var model_pos_data = model.get("position", {})
			var model_pos = Vector2(model_pos_data.get("x", 0), model_pos_data.get("y", 0))
			var distance = from_pos.distance_to(model_pos)
			
			if distance < closest_distance:
				closest_distance = distance
				closest_pos = model_pos
	
	return closest_pos

func _validate_unit_coherency(unit_id: String, new_positions: Dictionary) -> Dictionary:
	# Use similar logic to MovementPhase coherency checking
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var errors = []
	
	# Build combined positions (existing + new)
	var all_positions = []
	for i in models.size():
		var model = models[i]
		var model_id = str(i)
		
		if model_id in new_positions:
			all_positions.append(new_positions[model_id])
		else:
			var pos_data = model.get("position", {})
			all_positions.append(Vector2(pos_data.get("x", 0), pos_data.get("y", 0)))
	
	# Check 2" coherency rule (simplified)
	for i in range(all_positions.size()):
		var has_nearby_model = false
		for j in range(all_positions.size()):
			if i == j:
				continue
			var distance = Measurement.distance_inches(all_positions[i], all_positions[j])
			if distance <= 2.0:
				has_nearby_model = true
				break
		
		if not has_nearby_model and all_positions.size() > 1:
			errors.append("Model %d breaks unit coherency (>2\" from all other models)" % i)
	
	return {"valid": errors.is_empty(), "errors": errors}

func _apply_combat_results(result: Dictionary) -> void:
	# Apply state changes from combat resolution
	var changes = result.get("changes", [])
	if changes.is_empty():
		changes = result.get("diffs", [])  # RulesEngine uses "diffs"
	
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

func _clear_unit_fight_state(unit_id: String) -> void:
	# Clear any temporary fight flags
	pass

func get_available_actions() -> Array:
	var actions = []
	
	log_phase_message("=== get_available_actions DEBUG ===")
	log_phase_message("active_fighter_id: '%s'" % active_fighter_id)
	log_phase_message("current_fight_index: %d" % current_fight_index)
	log_phase_message("fight_sequence.size(): %d" % fight_sequence.size())
	log_phase_message("fight_sequence: %s" % str(fight_sequence))
	
	# If no active fighter, need to select one
	if active_fighter_id == "" and current_fight_index < fight_sequence.size():
		var next_unit = fight_sequence[current_fight_index]
		log_phase_message("Adding SELECT_FIGHTER action for: %s" % next_unit)
		actions.append({
			"type": "SELECT_FIGHTER",
			"unit_id": next_unit,
			"description": "Select %s to fight" % next_unit
		})
	else:
		log_phase_message("NOT adding SELECT_FIGHTER: active_fighter_id='%s', index=%d, size=%d" % [active_fighter_id, current_fight_index, fight_sequence.size()])
	
	# If active fighter is selected, show simple control actions
	if active_fighter_id != "":
		if pending_attacks.is_empty():
			actions.append({
				"type": "PILE_IN",
				"unit_id": active_fighter_id,
				"description": "Pile in with %s" % active_fighter_id
			})
			
			# Action to assign attacks (weapon/target selection handled by UI)
			actions.append({
				"type": "ASSIGN_ATTACKS_UI",
				"unit_id": active_fighter_id,
				"description": "Assign attacks"
			})
	
	# If attacks are assigned, can confirm and resolve
	if not pending_attacks.is_empty():
		actions.append({
			"type": "CONFIRM_AND_RESOLVE_ATTACKS",
			"description": "Resolve combat"
		})
	
	# If attacks resolved, can consolidate
	if active_fighter_id != "" and pending_attacks.is_empty() and confirmed_attacks.is_empty():
		actions.append({
			"type": "CONSOLIDATE",
			"unit_id": active_fighter_id,
			"description": "Consolidate %s" % active_fighter_id
		})
	
	log_phase_message("Returning %d available actions: %s" % [actions.size(), str(actions)])
	log_phase_message("=== END get_available_actions DEBUG ===")
	return actions

func _should_complete_phase() -> bool:
	# Phase completes when all units in fight sequence have fought
	return current_fight_index >= fight_sequence.size()

# Legacy method compatibility (for existing helper methods)
func _is_unit_in_combat(unit: Dictionary) -> bool:
	# Check if unit is within engagement range of any enemy
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)
	var unit_name = unit.get("meta", {}).get("name", unit.get("id", "unknown"))
	
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		var other_owner = other_unit.get("owner", 0)
		var other_name = other_unit.get("meta", {}).get("name", other_unit_id)
		
		if other_owner != unit_owner:
			log_phase_message("Checking engagement between %s (player %d) and %s (player %d)" % [unit_name, unit_owner, other_name, other_owner])
			if _units_in_engagement_range(unit, other_unit):
				log_phase_message("Units %s and %s are in engagement range!" % [unit_name, other_name])
				return true
	
	return false

func _units_in_engagement_range(unit1: Dictionary, unit2: Dictionary) -> bool:
	# Check if any model from unit1 is within 1" of any model from unit2
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])
	var unit1_name = unit1.get("meta", {}).get("name", "unit1")
	var unit2_name = unit2.get("meta", {}).get("name", "unit2")
	
	for model1 in models1:
		if not model1.get("alive", true):
			continue
		
		var pos1_data = model1.get("position", {})
		var pos1 = Vector2(pos1_data.get("x", 0), pos1_data.get("y", 0))
		var base1_mm = model1.get("base_mm", 25.0)
		
		if pos1 == Vector2.ZERO:
			continue
		
		for model2 in models2:
			if not model2.get("alive", true):
				continue
			
			var pos2_data = model2.get("position", {})
			var pos2 = Vector2(pos2_data.get("x", 0), pos2_data.get("y", 0))
			var base2_mm = model2.get("base_mm", 25.0)
			
			if pos2 == Vector2.ZERO:
				continue
			
			# Check engagement range (1" = 25.4mm)
			# Use Measurement class for proper conversions
			var distance_px = pos1.distance_to(pos2)
			
			# Convert base sizes from mm to pixel radius
			var base1_radius_px = Measurement.base_radius_px(base1_mm)
			var base2_radius_px = Measurement.base_radius_px(base2_mm)
			
			# Calculate edge-to-edge distance
			var edge_distance_px = Measurement.edge_to_edge_distance_px(pos1, base1_radius_px, pos2, base2_radius_px)
			var edge_distance_inches = Measurement.px_to_inches(edge_distance_px)
			
			if edge_distance_inches <= 1.0:  # 1" engagement range
				log_phase_message("Units %s and %s are within engagement range! (%.2f\")" % [unit1_name, unit2_name, edge_distance_inches])
				return true
	return false

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

# Legacy method compatibility 
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

# State access methods
func get_current_fight_state() -> Dictionary:
	"""Return current fight state for UI restoration and external access"""
	return {
		"current_fighter_id": active_fighter_id,
		"fight_sequence": fight_sequence,
		"current_fight_index": current_fight_index,
		"pending_attacks": pending_attacks,
		"confirmed_attacks": confirmed_attacks,
		"units_that_fought": units_that_fought,
		"resolution_state": resolution_state
	}
