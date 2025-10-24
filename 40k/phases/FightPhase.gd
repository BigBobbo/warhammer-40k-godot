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

# New signals for subphase dialog system
signal fight_selection_required(data: Dictionary)
signal pile_in_required(unit_id: String, max_distance: float)
signal attack_assignment_required(unit_id: String, eligible_targets: Dictionary)
signal attack_assigned(attacker_id: String, target_id: String, weapon_id: String)  # Notify when an attack is assigned
signal consolidate_required(unit_id: String, max_distance: float)
signal subphase_transition(from_subphase: String, to_subphase: String)

# Fight state tracking
var active_fighter_id: String = ""
var selected_weapon_id: String = ""  # Currently selected weapon for active fighter
var fight_sequence: Array = []  # Ordered list of units to fight (kept for compatibility)
var current_fight_index: int = 0
var pending_attacks: Array = []
var confirmed_attacks: Array = []
var resolution_state: Dictionary = {}
var dice_log: Array = []
var units_that_fought: Array = []

# New subphase tracking
var fights_first_sequence: Dictionary = {"1": [], "2": []}  # Player -> Array of unit IDs
var normal_sequence: Dictionary = {"1": [], "2": []}  # Player -> Array of unit IDs, called "remaining_units" in PRP
var fights_last_sequence: Dictionary = {"1": [], "2": []}  # Player -> Array of unit IDs
var current_selecting_player: int = 2  # Which player is currently selecting (defending player starts)

# Fight priority tiers
enum FightPriority {
	FIGHTS_FIRST = 0,  # Charged units + abilities
	NORMAL = 1,
	FIGHTS_LAST = 2
}

# Subphase enum
enum Subphase {
	FIGHTS_FIRST,
	REMAINING_COMBATS,
	COMPLETE
}

var current_subphase: Subphase = Subphase.FIGHTS_FIRST

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
	# Clear sequences
	fights_first_sequence = {"1": [], "2": []}
	normal_sequence = {"1": [], "2": []}
	fights_last_sequence = {"1": [], "2": []}
	fight_sequence.clear()  # Keep for compatibility
	
	var all_units = game_state_snapshot.get("units", {})
	log_phase_message("Checking %d units for combat eligibility" % all_units.size())
	
	for unit_id in all_units:
		var unit = all_units[unit_id]
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var owner_val = unit.get("owner", 1)
		# Convert owner to int then to string for dictionary key (handles float values from saves)
		var owner = str(int(owner_val))
		var models_alive = 0
		for model in unit.get("models", []):
			if model.get("alive", true):
				models_alive += 1
		
		log_phase_message("Unit %s (player %s) has %d alive models" % [unit_name, owner, models_alive])
		
		if _is_unit_in_combat(unit):
			log_phase_message("Unit %s is in combat!" % unit_name)
			var priority = _get_fight_priority(unit)
			match priority:
				FightPriority.FIGHTS_FIRST:
					if owner in fights_first_sequence:
						fights_first_sequence[owner].append(unit_id)
					log_phase_message("Added %s (player %s) to FIGHTS_FIRST" % [unit_name, owner])
				FightPriority.NORMAL:
					if owner in normal_sequence:
						normal_sequence[owner].append(unit_id)
					log_phase_message("Added %s (player %s) to NORMAL" % [unit_name, owner])
				FightPriority.FIGHTS_LAST:
					if owner in fights_last_sequence:
						fights_last_sequence[owner].append(unit_id)
					log_phase_message("Added %s (player %s) to FIGHTS_LAST" % [unit_name, owner])
		else:
			log_phase_message("Unit %s is NOT in combat" % unit_name)
	
	# Set initial subphase and defending player (per 10e rules)
	current_subphase = Subphase.FIGHTS_FIRST
	current_selecting_player = _get_defending_player()

	log_phase_message("=== FIGHT PHASE INITIALIZATION ===")
	log_phase_message("Active Player: %d" % GameState.get_active_player())
	log_phase_message("Defending Player (starts first): %d" % current_selecting_player)
	log_phase_message("Fight sequences initialized:")
	log_phase_message("  Fights First P1: %s" % str(fights_first_sequence["1"]))
	log_phase_message("  Fights First P2: %s" % str(fights_first_sequence["2"]))
	log_phase_message("  Normal P1: %s" % str(normal_sequence["1"]))
	log_phase_message("  Normal P2: %s" % str(normal_sequence["2"]))
	log_phase_message("  Current subphase: %s, Selecting Player: %d (defending)" % [Subphase.keys()[current_subphase], current_selecting_player])
	log_phase_message("===================================")

	# Build legacy fight_sequence for compatibility
	fight_sequence = _build_alternating_sequence(fights_first_sequence["1"] + fights_first_sequence["2"])
	fight_sequence.append_array(_build_alternating_sequence(normal_sequence["1"] + normal_sequence["2"]))
	fight_sequence.append_array(_build_alternating_sequence(fights_last_sequence["1"] + fights_last_sequence["2"]))

	emit_signal("fight_order_determined", fight_sequence)
	emit_signal("fight_sequence_updated")
	emit_signal("fight_sequence_updated", fight_sequence)  # Compatibility signal

	# Emit fight selection required signal to show dialog
	_emit_fight_selection_required()

func _check_for_combats() -> void:
	if fight_sequence.size() == 0:
		log_phase_message("No units in combat, ready to end fight phase")
		# Don't auto-complete - wait for END_FIGHT action
	else:
		log_phase_message("Found %d units in fight sequence" % fight_sequence.size())
		if fight_sequence.size() > 0:
			log_phase_message("First to fight: %s" % fight_sequence[0])

func execute_action(action: Dictionary) -> Dictionary:
	"""Override to emit dialog signals after action processing"""
	var result = super.execute_action(action)

	# After successful action execution, emit appropriate dialog signals
	# This ensures signals are emitted on BOTH host and client in multiplayer
	if result.success:
		var action_type = action.get("type", "")
		match action_type:
			"SELECT_FIGHTER":
				# Emit pile_in_required signal
				if active_fighter_id != "":
					log_phase_message("[execute_action] Emitting pile_in_required for %s" % active_fighter_id)
					emit_signal("pile_in_required", active_fighter_id, 3.0)
			"PILE_IN":
				# Emit attack_assignment_required signal
				if active_fighter_id != "":
					var targets = _get_eligible_melee_targets(active_fighter_id)
					log_phase_message("[execute_action] Emitting attack_assignment_required for %s" % active_fighter_id)
					emit_signal("attack_assignment_required", active_fighter_id, targets)
			"ROLL_DICE":
				# Emit consolidate_required signal
				if active_fighter_id != "":
					log_phase_message("[execute_action] Emitting consolidate_required for %s" % active_fighter_id)
					emit_signal("consolidate_required", active_fighter_id, 3.0)

	return result

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
		"ROLL_DICE":
			return _validate_roll_dice(action)
		"CONSOLIDATE":
			return _validate_consolidate(action)
		"SKIP_UNIT":
			return _validate_skip_unit(action)
		"HEROIC_INTERVENTION":
			return _validate_heroic_intervention_action(action)
		"END_FIGHT":
			return _validate_end_fight(action)
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
		"ROLL_DICE":
			return _process_roll_dice(action)
		"CONSOLIDATE":
			return _process_consolidate(action)
		"SKIP_UNIT":
			return _process_skip_unit(action)
		"HEROIC_INTERVENTION":
			return _process_heroic_intervention(action)
		"END_FIGHT":
			return _process_end_fight(action)
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

	# Check it's the right player's turn
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found")
		return {"valid": false, "errors": errors}

	if unit.owner != current_selecting_player:
		var error_msg = "Not your turn to select (Player %d's turn, you are Player %d)" % [current_selecting_player, unit.owner]
		errors.append(error_msg)
		log_phase_message("VALIDATION FAILED: Player %d tried to select unit owned by Player %d during Player %d's selection" % [
			unit.owner, unit.owner, current_selecting_player
		])
		return {"valid": false, "errors": errors}

	# Check unit is eligible in current subphase
	var player_key = str(current_selecting_player)
	var source_list = fights_first_sequence if current_subphase == Subphase.FIGHTS_FIRST else normal_sequence

	if unit_id not in source_list.get(player_key, []):
		errors.append("Unit not eligible in this subphase")
		return {"valid": false, "errors": errors}

	# Check unit hasn't already fought
	if unit_id in units_that_fought:
		errors.append("Unit has already fought")
		return {"valid": false, "errors": errors}

	# Check unit is in engagement range
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
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))
	var movements = action.get("movements", {})
	var errors = []
	
	# Handle single position movement (from FightController)
	if movements.is_empty() and action.has("position"):
		var position = action.get("position")
		movements["0"] = Vector2(position.get("x", 0), position.get("y", 0))
	
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

	# Check for model overlaps
	var overlap_check = _validate_no_overlaps_for_movement(unit_id, movements)
	if not overlap_check.valid:
		errors.append_array(overlap_check.errors)

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
	elif weapon.get("type", "").to_lower() != "melee":
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

	log_phase_message("Player %d selects %s to fight" % [
		current_selecting_player,
		get_unit(active_fighter_id).get("meta", {}).get("name", active_fighter_id)
	])

	emit_signal("unit_selected_for_fighting", active_fighter_id)
	emit_signal("fighter_selected", active_fighter_id)  # Compatibility signal

	# Start unit activation sequence: Pile In → Attack → Consolidate
	log_phase_message("Emitting pile_in_required for %s" % active_fighter_id)
	emit_signal("pile_in_required", active_fighter_id, 3.0)

	# Add metadata for NetworkManager to re-emit signal on client
	var result = create_result(true, [])
	result["trigger_pile_in"] = true
	result["pile_in_unit_id"] = active_fighter_id
	result["pile_in_distance"] = 3.0
	return result

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
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))

	# Handle single position movement (from FightController) vs movements dict
	var movements = action.get("movements", {})
	if movements.is_empty() and action.has("position"):
		# Convert single position to movements dict for first model
		var position = action.get("position")
		movements["0"] = Vector2(position.get("x", 0), position.get("y", 0))

	# Apply movements (if any provided)
	for model_id in movements:
		var new_pos = movements[model_id]
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, model_id],
			"value": {"x": new_pos.x, "y": new_pos.y}
		})

	emit_signal("pile_in_preview", unit_id, movements)
	log_phase_message("Unit %s piled in" % unit_id)

	# After pile-in, request attack assignment
	var targets = _get_eligible_melee_targets(unit_id)
	emit_signal("attack_assignment_required", unit_id, targets)

	# Add metadata for NetworkManager to re-emit signal on client
	var result = create_result(true, changes)
	result["trigger_attack_assignment"] = true
	result["attack_unit_id"] = unit_id
	result["attack_targets"] = targets
	return result

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

	# Emit signal so both host and client can update UI
	emit_signal("attack_assigned", unit_id, target_id, weapon_id)

	return create_result(true, [])

func _process_confirm_and_resolve_attacks(action: Dictionary) -> Dictionary:
	# Move pending attacks to confirmed attacks (but don't resolve yet)
	confirmed_attacks = pending_attacks.duplicate(true)
	pending_attacks.clear()
	
	emit_signal("fighting_begun", active_fighter_id)
	
	# Show mathhammer predictions before rolling
	_show_mathhammer_predictions()
	
	log_phase_message("Attack assignments confirmed for %s - ready to roll dice!" % active_fighter_id)
	return create_result(true, [])

func _validate_roll_dice(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check that attacks are confirmed and ready to roll
	if confirmed_attacks.is_empty():
		errors.append("No confirmed attacks to resolve")
	
	if active_fighter_id == "":
		errors.append("No active fighter")
	
	return {"valid": errors.is_empty(), "errors": errors}

func _process_roll_dice(action: Dictionary) -> Dictionary:
	# Emit signal to indicate resolution is starting
	emit_signal("dice_rolled", {"context": "resolution_start", "message": "Beginning melee combat resolution..."})
	
	# Build full fight action for RulesEngine
	var melee_action = {
		"type": "FIGHT", 
		"actor_unit_id": active_fighter_id,
		"payload": {
			"assignments": confirmed_attacks
		}
	}
	
	# Resolve with RulesEngine
	var rng_service = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_melee_attacks(melee_action, game_state_snapshot, rng_service)
	
	if not result.success:
		return create_result(false, [], result.get("log_text", "Melee combat failed"))
	
	# Process dice results step by step (like shooting phase)
	for dice_block in result.get("dice", []):
		emit_signal("dice_rolled", dice_block)
	
	# Apply changes and emit resolution signals
	if result.success:
		_apply_combat_results(result)
		
		# Emit resolution signals for each target
		for assignment in confirmed_attacks:
			emit_signal("attacks_resolved", active_fighter_id, assignment.target, result)
			emit_signal("fight_resolved", active_fighter_id, assignment.target, result)  # Compatibility signal
	
	# Clear confirmed attacks after resolution
	confirmed_attacks.clear()

	log_phase_message("Melee combat resolved for %s" % active_fighter_id)

	# After attacks, request consolidate
	emit_signal("consolidate_required", active_fighter_id, 3.0)

	# Add metadata for NetworkManager to re-emit signal on client
	var final_result = create_result(true, result.get("diffs", []), result.get("log_text", ""))
	final_result["trigger_consolidate"] = true
	final_result["consolidate_unit_id"] = active_fighter_id
	final_result["consolidate_distance"] = 3.0

	# Preserve dice and save_data_list from combat resolution
	if result.has("dice"):
		final_result["dice"] = result["dice"]
	if result.has("save_data_list"):
		final_result["save_data_list"] = result["save_data_list"]

	return final_result

func _show_mathhammer_predictions() -> void:
	# Use mathhammer to calculate expected results before rolling
	if not confirmed_attacks.is_empty():
		# Build config for mathhammer simulation
		var attacker_unit = get_unit(active_fighter_id)
		var defender_units = {}
		
		# Collect all target units
		for attack in confirmed_attacks:
			var target_id = attack.get("target", "")
			if target_id != "" and not defender_units.has(target_id):
				defender_units[target_id] = get_unit(target_id)
		
		# For now, show basic prediction text
		# TODO: Integrate full mathhammer simulation for melee
		var prediction_text = "Expected: Calculating melee predictions for %s vs %d targets..." % [
			attacker_unit.get("meta", {}).get("name", active_fighter_id),
			defender_units.size()
		]
		
		# Display predictions via dice_rolled signal (like shooting phase)
		emit_signal("dice_rolled", {
			"context": "mathhammer_prediction", 
			"message": prediction_text
		})

func _process_consolidate(action: Dictionary) -> Dictionary:
	var changes = []
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})

	# Apply movements
	for model_id in movements:
		var new_pos = movements[model_id]
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, model_id],
			"value": {"x": new_pos.x, "y": new_pos.y}
		})

	# Mark unit as having fought
	changes.append({
		"op": "set",
		"path": "units.%s.flags.has_fought" % unit_id,
		"value": true
	})
	units_that_fought.append(unit_id)
	active_fighter_id = ""
	confirmed_attacks.clear()

	# Legacy support - update old index
	current_fight_index += 1

	# Switch to next player
	_switch_selecting_player()

	# IMPORTANT: For multiplayer sync, we need to capture the dialog data BEFORE emitting
	# the signal so we can send it to clients
	var dialog_data = _build_fight_selection_dialog_data()

	# Request next fight selection on host
	emit_signal("fight_selection_required", dialog_data)

	# Add flag and data to result for NetworkManager to trigger on clients
	var result = create_result(true, changes)
	result["trigger_fight_selection"] = true
	result["fight_selection_data"] = dialog_data

	return result

func _process_skip_unit(action: Dictionary) -> Dictionary:
	# Skip this unit and advance to next
	units_that_fought.append(action.unit_id)
	active_fighter_id = ""

	# Legacy support - update old index
	current_fight_index += 1

	# Switch to next player
	_switch_selecting_player()

	# Request next fight selection
	_emit_fight_selection_required()

	log_phase_message("Skipped unit %s" % action.unit_id)
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

func _get_defending_player() -> int:
	"""Returns the defending player (non-active player)"""
	var active_player = GameState.get_active_player()
	return 2 if active_player == 1 else 1

func _build_fight_selection_dialog_data_internal() -> Dictionary:
	"""Internal version that builds dialog data without triggering transitions.
	Used when we're already inside a transition to avoid recursion."""
	log_phase_message("=== REQUESTING FIGHT SELECTION ===")
	log_phase_message("Current Subphase: %s" % Subphase.keys()[current_subphase])
	log_phase_message("Selecting Player: %d" % current_selecting_player)

	# Get eligible units for current player and subphase
	var eligible_units = _get_eligible_units_for_selection()
	log_phase_message("Eligible Units: %d" % eligible_units.size())
	if not eligible_units.is_empty():
		log_phase_message("Available: %s" % str(eligible_units.keys()))

	# Build dialog data
	var dialog_data = {
		"current_subphase": Subphase.keys()[current_subphase],
		"selecting_player": current_selecting_player,
		"eligible_units": eligible_units,
		"fights_first_units": fights_first_sequence,
		"remaining_units": normal_sequence,  # PRP calls normal_sequence "remaining_units"
		"units_that_fought": units_that_fought
	}

	log_phase_message("Emitting fight_selection_required signal")
	log_phase_message("===================================")

	return dialog_data

func _build_fight_selection_dialog_data() -> Dictionary:
	"""Build dialog data for fight selection. Extracted for multiplayer sync.
	Handles player switching and subphase transitions."""
	log_phase_message("=== REQUESTING FIGHT SELECTION ===")
	log_phase_message("Current Subphase: %s" % Subphase.keys()[current_subphase])
	log_phase_message("Selecting Player: %d" % current_selecting_player)

	# Get eligible units for current player and subphase
	var eligible_units = _get_eligible_units_for_selection()
	log_phase_message("Eligible Units: %d" % eligible_units.size())
	if not eligible_units.is_empty():
		log_phase_message("Available: %s" % str(eligible_units.keys()))

	if eligible_units.is_empty():
		# Current player has no units, switch to opponent
		log_phase_message("No eligible units for Player %d, switching..." % current_selecting_player)
		_switch_selecting_player()
		eligible_units = _get_eligible_units_for_selection()
		log_phase_message("After switch, Player %d has %d eligible units" % [current_selecting_player, eligible_units.size()])
		if not eligible_units.is_empty():
			log_phase_message("Available: %s" % str(eligible_units.keys()))

		if eligible_units.is_empty():
			# No units left in this subphase, transition
			log_phase_message("Still no eligible units, transitioning subphase")
			log_phase_message("===================================")
			var transition_data = _transition_subphase()
			return transition_data  # Return data from new subphase or empty dict if phase complete

	# Build dialog data
	var dialog_data = {
		"current_subphase": Subphase.keys()[current_subphase],
		"selecting_player": current_selecting_player,
		"eligible_units": eligible_units,
		"fights_first_units": fights_first_sequence,
		"remaining_units": normal_sequence,  # PRP calls normal_sequence "remaining_units"
		"units_that_fought": units_that_fought
	}

	log_phase_message("Emitting fight_selection_required signal")
	log_phase_message("===================================")

	return dialog_data

func _emit_fight_selection_required() -> void:
	"""Emit signal to show fight selection dialog with current state"""
	var dialog_data = _build_fight_selection_dialog_data()
	if not dialog_data.is_empty():
		emit_signal("fight_selection_required", dialog_data)

func _get_eligible_units_for_selection() -> Dictionary:
	"""Get units eligible for selection by current player in current subphase"""
	var eligible = {}
	var player_key = str(current_selecting_player)
	var source_list = fights_first_sequence if current_subphase == Subphase.FIGHTS_FIRST else normal_sequence

	for unit_id in source_list.get(player_key, []):
		if unit_id not in units_that_fought:
			var unit = get_unit(unit_id)
			if not unit.is_empty():
				eligible[unit_id] = {
					"name": unit.get("meta", {}).get("name", unit_id),
					"weapons": RulesEngine.get_unit_melee_weapons(unit_id, game_state_snapshot),
					"targets": _get_eligible_melee_targets(unit_id)
				}

	return eligible

func _switch_selecting_player() -> void:
	"""Switch to the other player for unit selection"""
	var old_player = current_selecting_player
	current_selecting_player = 2 if current_selecting_player == 1 else 1
	log_phase_message("Selection SWITCHED: Player %d → Player %d" % [old_player, current_selecting_player])

func _transition_subphase() -> Dictionary:
	"""Transition from Fights First to Remaining Combats or complete phase.
	Returns dialog data for the new subphase if there are units to fight, empty dict otherwise."""
	if current_subphase == Subphase.FIGHTS_FIRST:
		log_phase_message("Fights First complete. Starting Remaining Combats.")
		emit_signal("subphase_transition", "FIGHTS_FIRST", "REMAINING_COMBATS")

		current_subphase = Subphase.REMAINING_COMBATS
		current_selecting_player = _get_defending_player()  # Reset to defender

		# Check if there are any remaining combats
		if normal_sequence["1"].is_empty() and normal_sequence["2"].is_empty():
			log_phase_message("No remaining combats. Fight Phase complete.")
			emit_signal("phase_completed")
			return {}
		else:
			# Build and return dialog data for new subphase WITHOUT calling _emit_fight_selection_required
			# The caller will handle emitting the signal
			return _build_fight_selection_dialog_data_internal()
	else:
		# Remaining Combats complete
		log_phase_message("Fight Phase complete.")
		emit_signal("phase_completed")
		return {}

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
			if pos == null:
				return Vector2.ZERO
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
			if model_pos_data == null:
				continue
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
			if pos_data == null:
				continue
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
	
	# If attacks are assigned, can confirm them
	if not pending_attacks.is_empty():
		actions.append({
			"type": "CONFIRM_AND_RESOLVE_ATTACKS", 
			"description": "Confirm attacks"
		})
	
	# If attacks are confirmed, can roll dice
	if not confirmed_attacks.is_empty() and pending_attacks.is_empty():
		actions.append({
			"type": "ROLL_DICE",
			"description": "Roll dice"
		})
	
	# If attacks resolved, can consolidate
	if active_fighter_id != "" and pending_attacks.is_empty() and confirmed_attacks.is_empty():
		actions.append({
			"type": "CONSOLIDATE",
			"unit_id": active_fighter_id,
			"description": "Consolidate %s" % active_fighter_id
		})
	
	# Add END_FIGHT action when appropriate
	if fight_sequence.is_empty() or current_fight_index >= fight_sequence.size():
		actions.append({
			"type": "END_FIGHT",
			"description": "End Fight Phase"
		})
		log_phase_message("Adding END_FIGHT action - all units processed or no fights")
	
	log_phase_message("Returning %d available actions: %s" % [actions.size(), str(actions)])
	log_phase_message("=== END get_available_actions DEBUG ===")
	return actions

func _should_complete_phase() -> bool:
	# Phase only completes when explicitly requested via END_FIGHT action
	# Don't auto-complete based on fight sequence anymore
	return false

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
		if pos1_data == null:
			continue
		var pos1 = Vector2(pos1_data.get("x", 0), pos1_data.get("y", 0))
		var base1_mm = model1.get("base_mm", 25.0)

		if pos1 == Vector2.ZERO:
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue

			var pos2_data = model2.get("position", {})
			if pos2_data == null:
				continue
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

func _validate_no_overlaps_for_movement(unit_id: String, movements: Dictionary) -> Dictionary:
	var errors = []
	var all_units = game_state_snapshot.get("units", {})

	# Get unit and models
	var unit = all_units.get(unit_id, {})
	var models = unit.get("models", [])

	# Check each model's new position
	for model_id in movements:
		var new_pos = movements[model_id]
		if new_pos is Vector2:
			# Get the model data
			var model_index = int(model_id) if model_id is String else model_id
			if model_index < models.size():
				var model = models[model_index]

				# Build model dict with new position
				var check_model = model.duplicate()
				check_model["position"] = new_pos

				# Check against all other models
				for check_unit_id in all_units:
					var check_unit = all_units[check_unit_id]
					var check_models = check_unit.get("models", [])

					for i in range(check_models.size()):
						var other_model = check_models[i]

						# Skip self
						if check_unit_id == unit_id and i == model_index:
							continue

						# Skip dead models
						if not other_model.get("alive", true):
							continue

						# Get position (use new position if this model is also moving)
						var other_position = _get_model_position(check_unit_id, str(i))
						if check_unit_id == unit_id and movements.has(str(i)):
							other_position = movements[str(i)]

						if other_position == null:
							continue

						# Build other model dict with position
						var other_model_check = other_model.duplicate()
						other_model_check["position"] = other_position

						# Check for overlap
						if Measurement.models_overlap(check_model, other_model_check):
							errors.append("Model %s would overlap with %s/%d" % [model_id, check_unit_id, i])

				# Check for wall collision
				if Measurement.model_overlaps_any_wall(check_model):
					errors.append("Model %s would overlap with walls" % model_id)

	return {"valid": errors.is_empty(), "errors": errors}

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

func _validate_end_fight(action: Dictionary) -> Dictionary:
	# END_FIGHT is always valid - it's the manual way to end the fight phase
	return {"valid": true, "errors": []}

func _process_end_fight(action: Dictionary) -> Dictionary:
	log_phase_message("Fight phase ended manually")
	emit_signal("phase_completed")
	return create_result(true, [])

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
		"resolution_state": resolution_state,
		# New subphase data
		"fights_first_sequence": fights_first_sequence,
		"normal_sequence": normal_sequence,
		"fights_last_sequence": fights_last_sequence,
		"current_subphase": current_subphase,
		"current_selecting_player": current_selecting_player
	}

func get_eligible_fighters_for_player(player: int) -> Dictionary:
	"""Get eligible fighters for a specific player in current subphase"""
	var player_key = str(player)
	var result = {
		"fights_first": [],
		"normal": [],
		"current_subphase": current_subphase,
		"active_player": current_selecting_player == player
	}
	
	# Get Fights First units that haven't fought
	if player_key in fights_first_sequence:
		for unit_id in fights_first_sequence[player_key]:
			if unit_id not in units_that_fought:
				result["fights_first"].append(unit_id)
	
	# Get Normal units that haven't fought
	if player_key in normal_sequence:
		for unit_id in normal_sequence[player_key]:
			if unit_id not in units_that_fought:
				result["normal"].append(unit_id)
	
	return result

func advance_to_next_fighter() -> void:
	"""Move to next fighter after one completes fighting"""
	# Check if we need to switch players or subphases
	var current_player_key = str(current_selecting_player)
	var other_player = 2 if current_selecting_player == 1 else 1
	var other_player_key = str(other_player)
	
	# Count remaining eligible units
	var current_player_remaining = 0
	var other_player_remaining = 0
	
	if current_subphase == Subphase.FIGHTS_FIRST:
		for unit_id in fights_first_sequence[current_player_key]:
			if unit_id not in units_that_fought:
				current_player_remaining += 1
		for unit_id in fights_first_sequence[other_player_key]:
			if unit_id not in units_that_fought:
				other_player_remaining += 1
				
		# Check if we should switch players
		if other_player_remaining > 0:
			# Alternate to other player
			current_selecting_player = other_player
			log_phase_message("Switching to player %d for Fights First" % other_player)
		elif current_player_remaining > 0:
			# Stay with current player
			log_phase_message("Continuing with player %d for Fights First" % current_selecting_player)
		else:
			# Move to Normal subphase
			log_phase_message("All Fights First units have fought, moving to Normal subphase")
			current_subphase = Subphase.REMAINING_COMBATS
			# Start with player 1 or whoever has units
			if normal_sequence["1"].size() > 0:
				current_selecting_player = 1
			elif normal_sequence["2"].size() > 0:
				current_selecting_player = 2
	
	elif current_subphase == Subphase.REMAINING_COMBATS:
		for unit_id in normal_sequence[current_player_key]:
			if unit_id not in units_that_fought:
				current_player_remaining += 1
		for unit_id in normal_sequence[other_player_key]:
			if unit_id not in units_that_fought:
				other_player_remaining += 1
				
		# Check if we should switch players
		if other_player_remaining > 0:
			# Alternate to other player
			current_selecting_player = other_player
			log_phase_message("Switching to player %d for Normal fights" % other_player)
		elif current_player_remaining > 0:
			# Stay with current player
			log_phase_message("Continuing with player %d for Normal fights" % current_selecting_player)
		else:
			# All units have fought
			log_phase_message("All units have fought")
			# Could transition to FIGHTS_LAST if we implement it
	
	emit_signal("fight_sequence_updated")
