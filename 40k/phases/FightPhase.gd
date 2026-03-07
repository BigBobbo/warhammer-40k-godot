extends BasePhase
class_name FightPhase

const BasePhase = preload("res://phases/BasePhase.gd")


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
signal command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)  # For Command Re-roll on save rolls (future expansion)
signal fight_order_determined(fight_sequence: Array)

# New signals for subphase dialog system
signal fight_selection_required(data: Dictionary)
signal pile_in_required(unit_id: String, max_distance: float)
signal attack_assignment_required(unit_id: String, eligible_targets: Dictionary)
signal attack_assigned(attacker_id: String, target_id: String, weapon_id: String)  # Notify when an attack is assigned
signal consolidate_required(unit_id: String, max_distance: float)
signal subphase_transition(from_subphase: String, to_subphase: String)
signal epic_challenge_opportunity(unit_id: String, player: int)
signal counter_offensive_opportunity(player: int, eligible_units: Array)
signal katah_stance_required(unit_id: String, player: int)
signal dread_foe_resolved(unit_id: String, result: Dictionary)  # P1-17: Dread Foe mortal wounds result
signal saves_required(save_data_list: Array)  # P0-58: Interactive wound allocation for defender

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
var units_that_piled_in: Dictionary = {}  # unit_id -> true, tracks which units have already piled in

# P0-58: Pending melee save data for interactive wound allocation
var pending_melee_save_data: Array = []  # Save data list for WoundAllocationOverlay
var pending_melee_hit_wound_result: Dictionary = {}  # Dice/log from hit+wound resolution
var awaiting_melee_saves: bool = false  # True while waiting for defender to allocate wounds

# New subphase tracking
var fights_first_sequence: Dictionary = {"1": [], "2": []}  # Player -> Array of unit IDs
var normal_sequence: Dictionary = {"1": [], "2": []}  # Player -> Array of unit IDs, called "remaining_units" in PRP
var fights_last_sequence: Dictionary = {"1": [], "2": []}  # Player -> Array of unit IDs
var current_selecting_player: int = 2  # Which player is currently selecting (defending player starts)

# T3-13: Pending dialog data for controller sync on phase entry
# Stores the last fight selection dialog data so the controller can retrieve it
# after connecting signals, eliminating the race condition with signal timing.
var _pending_fight_selection_data: Dictionary = {}

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
	FIGHTS_LAST,
	COMPLETE
}

# Counter-Offensive state tracking
var awaiting_counter_offensive: bool = false
var counter_offensive_player: int = 0  # Player being offered Counter-Offensive
var counter_offensive_unit_id: String = ""  # Unit selected for Counter-Offensive (set on USE)

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
	units_that_piled_in.clear()
	awaiting_counter_offensive = false
	counter_offensive_player = 0
	counter_offensive_unit_id = ""
	_pending_fight_selection_data = {}

	# Apply unit ability effects (leader abilities, always-on abilities)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	_initialize_fight_sequence()
	_check_for_combats()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Fight Phase")

	# T5-V13: Clear engagement indicator flags
	_clear_engagement_flags()

	# Clear unit ability effect flags
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_end(GameStateData.Phase.FIGHT)

	# P3-106: Clear stratagem phase-scoped effects at end of Fight phase
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		strat_manager.on_phase_end(GameStateData.Phase.FIGHT)

	# Clear any temporary fight data
	for unit_id in units_that_fought:
		_clear_unit_fight_state(unit_id)

	# P3-103: Recheck objective control at end of Fight phase
	# Per 10e core rules: "A player controls an objective marker at the end of any phase or turn."
	# Units destroyed during fighting can change objective control state.
	if MissionManager:
		MissionManager.check_all_objectives()
		print("FightPhase: P3-103 Updated objective control at end of Fight phase")

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
	log_phase_message("  Fights Last P1: %s" % str(fights_last_sequence["1"]))
	log_phase_message("  Fights Last P2: %s" % str(fights_last_sequence["2"]))
	log_phase_message("  Current subphase: %s, Selecting Player: %d (defending)" % [Subphase.keys()[current_subphase], current_selecting_player])
	log_phase_message("===================================")

	# T5-V13: Set is_engaged and fight_priority flags on engaged units for board indicators
	_set_engagement_flags()

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
	"""Override to log fight-phase actions. Signal emission is handled by:
	- _process_* methods (for the host)
	- trigger_* metadata + NetworkManager._emit_client_visual_updates (for the client)
	Do NOT re-emit signals here - that causes duplicate dialog windows."""
	var result = super.execute_action(action)

	# Kill hook: after diffs are applied, scan for alive=false changes
	if result.get("success", false) and result.has("changes"):
		_check_kill_diffs(result.changes)

	return result

func _check_kill_diffs(changes: Array) -> void:
	"""Scan state-change diffs for models set to alive=false, then report unit destruction."""
	var unit_ids_to_check: Dictionary = {}  # Use dict as set for dedup

	for diff in changes:
		if diff.get("op", "") != "set":
			continue
		var path = diff.get("path", "")
		if not path.ends_with(".alive") or diff.get("value", true) != false:
			continue

		# Path format: "units.<UNIT_ID>.models.<IDX>.alive"
		var parts = path.split(".")
		if parts.size() >= 2 and parts[0] == "units":
			unit_ids_to_check[parts[1]] = true

	for unit_id in unit_ids_to_check:
		SecondaryMissionManager.check_and_report_unit_destroyed(unit_id)
		# Track kills for primary mission scoring (Purge the Foe)
		if MissionManager:
			var unit = GameState.state.get("units", {}).get(unit_id, {})
			if not unit.is_empty():
				var all_dead = true
				for model in unit.get("models", []):
					if model.get("alive", true):
						all_dead = false
						break
				if all_dead:
					var destroyed_by = get_current_player()
					MissionManager.record_unit_destroyed(destroyed_by)
					# T7-57: Track unit kills/losses for AI performance summary
					var destroyed_owner = unit.get("owner", 0)
					if AIPlayer and AIPlayer.enabled:
						if AIPlayer.is_ai_player(destroyed_by):
							AIPlayer.record_ai_unit_killed(destroyed_by)
						if AIPlayer.is_ai_player(destroyed_owner):
							AIPlayer.record_ai_unit_lost(destroyed_owner)
					# P1-60: Check for transport destruction (must happen BEFORE Deadly Demise)
					_resolve_transport_destruction_if_applicable(unit_id)
					# P1-13: Check for Deadly Demise on destroyed unit
					_resolve_deadly_demise_if_applicable(unit_id)

func _resolve_transport_destruction_if_applicable(destroyed_unit_id: String) -> void:
	"""P1-60: Check if a destroyed unit is a transport with embarked units and resolve emergency disembarkation."""
	var transport_mgr = get_node_or_null("/root/TransportManager")
	if not transport_mgr:
		return
	if not transport_mgr.is_transport_with_embarked_units(destroyed_unit_id):
		return

	var transport_name = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {}).get("name", destroyed_unit_id)
	print("FightPhase: P1-60 Transport destruction detected — %s (%s) has embarked units" % [transport_name, destroyed_unit_id])
	log_phase_message("Transport %s destroyed! Embarked units must emergency disembark!" % transport_name)

	var result = RulesEngine.resolve_transport_destruction(destroyed_unit_id, GameState.state)

	if not result.get("all_diffs", []).is_empty():
		PhaseManager.apply_state_changes(result.all_diffs)

		for unit_info in result.get("per_unit", []):
			var mw = unit_info.get("mortal_wounds", 0)
			var destroyed_models = unit_info.get("models_destroyed", 0)
			var unit_name = unit_info.get("unit_name", "Unknown")
			if mw > 0:
				log_phase_message("  %s: %d mortal wound(s), %d model(s) destroyed" % [unit_name, mw, destroyed_models])
			else:
				log_phase_message("  %s: disembarked safely" % unit_name)

		# Recursively check if transport destruction casualties caused further deaths
		_check_kill_diffs(result.all_diffs)

func _resolve_deadly_demise_if_applicable(destroyed_unit_id: String) -> void:
	"""P1-13: Check if a destroyed unit has Deadly Demise and resolve it."""
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr:
		return
	if not ability_mgr.has_deadly_demise(destroyed_unit_id):
		return

	var dd_value = ability_mgr.get_deadly_demise_value(destroyed_unit_id)
	if dd_value == "":
		return

	var unit_name = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {}).get("name", destroyed_unit_id)
	print("FightPhase: P1-13 Deadly Demise detected on destroyed unit %s (%s) — value: %s" % [unit_name, destroyed_unit_id, dd_value])
	log_phase_message("Deadly Demise %s triggered for %s!" % [dd_value, unit_name])

	var dd_result = RulesEngine.resolve_deadly_demise(destroyed_unit_id, dd_value, GameState.state)

	if dd_result.get("triggered", false):
		# Apply the mortal wound diffs
		var diffs = dd_result.get("diffs", [])
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)
			log_phase_message("Deadly Demise %s: %d mortal wound(s) dealt to %d unit(s)" % [
				dd_value, dd_result.get("total_mortal_wounds", 0), dd_result.get("per_target", []).size()
			])
			# Recursively check if Deadly Demise caused any further unit deaths
			_check_kill_diffs(diffs)
	else:
		log_phase_message("Deadly Demise %s: roll of %d — did not trigger (needed 6)" % [
			dd_value, dd_result.get("trigger_roll", 0)
		])

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
		"USE_EPIC_CHALLENGE":
			return _validate_use_epic_challenge(action)
		"DECLINE_EPIC_CHALLENGE":
			return {"valid": true}
		"USE_COUNTER_OFFENSIVE":
			return _validate_use_counter_offensive(action)
		"DECLINE_COUNTER_OFFENSIVE":
			return {"valid": true}
		"SELECT_KATAH_STANCE":
			return _validate_select_katah_stance(action)
		"END_FIGHT":
			return _validate_end_fight(action)
		"BATCH_FIGHT_ACTIONS":
			return _validate_batch_fight_actions(action)
		"APPLY_MELEE_SAVES":
			return _validate_apply_melee_saves(action)
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
		"USE_EPIC_CHALLENGE":
			return _process_use_epic_challenge(action)
		"DECLINE_EPIC_CHALLENGE":
			return _process_decline_epic_challenge(action)
		"USE_COUNTER_OFFENSIVE":
			return _process_use_counter_offensive(action)
		"DECLINE_COUNTER_OFFENSIVE":
			return _process_decline_counter_offensive(action)
		"SELECT_KATAH_STANCE":
			return _process_select_katah_stance(action)
		"END_FIGHT":
			return _process_end_fight(action)
		"BATCH_FIGHT_ACTIONS":
			return _process_batch_fight_actions(action)
		"APPLY_MELEE_SAVES":
			return _process_apply_melee_saves(action)
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

	# T4-4: Aircraft cannot Pile In
	var unit = get_unit(unit_id)
	if _unit_has_keyword(unit, "AIRCRAFT"):
		log_phase_message("[T4-4] AIRCRAFT unit %s cannot Pile In — skipping movement" % unit_id)
		if not movements.is_empty():
			errors.append("AIRCRAFT units cannot Pile In")
			return {"valid": false, "errors": errors}
		# Empty movements = skip, which is valid for Aircraft
		return {"valid": true, "errors": []}
	
	# Validate each model movement
	for model_id in movements:
		var old_pos = _get_model_position(unit_id, model_id)
		var new_pos = movements[model_id]

		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % model_id)
			continue

		# T4-5: Reject movement for models already in base contact with an enemy
		if _is_model_in_base_contact_with_enemy(unit_id, model_id):
			var move_distance = Measurement.distance_inches(old_pos, new_pos)
			if move_distance > 0.01:  # Model actually moved
				errors.append("Model %s is already in base contact — cannot move during pile-in" % model_id)
				log_phase_message("[T4-5] Model %s rejected: already in base contact, moved %.2f\"" % [model_id, move_distance])
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

	# T1-5: After pile-in, at least one model must be within Engagement Range (1") of an enemy.
	# Rule: "A Pile-in Move is a 3" move that, if made, must result in the unit being in
	# Unit Coherency and within Engagement Range of one or more enemy units."
	unit = get_unit(unit_id)
	if not unit.is_empty() and not movements.is_empty():
		if not _can_unit_maintain_engagement_after_movement(unit, movements):
			errors.append("Unit must end within Engagement Range of at least one enemy after pile-in")
			log_phase_message("[Pile-In] REJECTED: Unit %s would not be in Engagement Range after pile-in" % unit_id)

	# T1-6: Base-to-base contact enforcement
	# Rule: "Each model must end closer to the closest enemy model, and in base-to-base
	# contact with it if possible." If a model CAN reach b2b within 3", it MUST.
	if not unit.is_empty() and not movements.is_empty():
		var b2b_check = _validate_base_to_base_if_possible(unit_id, movements, 3.0)
		if not b2b_check.valid:
			errors.append_array(b2b_check.errors)

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
	# Consolidate has different rules than pile-in:
	# 1. Try to end in engagement range (closer to enemy, base contact if possible)
	# 2. If can't maintain engagement, move toward closest objective
	# 3. If neither is possible, no consolidation allowed
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})
	var errors = []

	# Check unit is active fighter and has fought
	if unit_id != active_fighter_id:
		errors.append("Not the active fighter")
		return {"valid": false, "errors": errors}

	# Unit must have resolved attacks (pending_attacks should be empty)
	if not pending_attacks.is_empty():
		errors.append("Must resolve attacks before consolidating")
		return {"valid": false, "errors": errors}

	# T4-4: Aircraft cannot Consolidate
	var unit_for_kw = get_unit(unit_id)
	if _unit_has_keyword(unit_for_kw, "AIRCRAFT"):
		log_phase_message("[T4-4] AIRCRAFT unit %s cannot Consolidate — skipping movement" % unit_id)
		if not movements.is_empty():
			errors.append("AIRCRAFT units cannot Consolidate")
			return {"valid": false, "errors": errors}
		# Empty movements = skip, which is valid for Aircraft
		return {"valid": true, "errors": []}

	# FGT-1 / P2-78: Per FAQ, consolidation for a unit is NOT optional — the step
	# must always occur. However, each individual model's Consolidation move IS
	# optional. Empty movements means the unit consolidates but no models move,
	# which is valid per the FAQ ruling.
	if movements.is_empty():
		log_phase_message("[FGT-1] Unit %s consolidation step completed (no individual models moved — permitted per FAQ)" % unit_id)
		return {"valid": true, "errors": []}

	# Determine which consolidate mode is available
	var unit = get_unit(unit_id)
	var consolidate_mode = _determine_consolidate_mode(unit, movements)

	log_phase_message("[Consolidate] Mode for %s: %s" % [unit_id, consolidate_mode])

	if consolidate_mode == "ENGAGEMENT":
		# Validate engagement range consolidate
		return _validate_consolidate_engagement_range(unit_id, movements)
	elif consolidate_mode == "OBJECTIVE":
		# Validate objective-based consolidate
		return _validate_consolidate_objective(unit_id, movements)
	else:
		# No valid consolidation possible
		if not movements.is_empty():
			errors.append("No valid consolidation possible (cannot maintain engagement or reach objectives)")
		return {"valid": errors.is_empty(), "errors": errors}

func _determine_consolidate_mode(unit: Dictionary, movements: Dictionary) -> String:
	"""Determine which consolidate mode applies:
	- ENGAGEMENT: Can end in engagement range with at least one enemy (within 4" total distance)
	- OBJECTIVE: Cannot reach engagement, but can reach objective
	- NONE: Neither is possible"""

	# Check if it's POSSIBLE for unit to end in engagement range
	# "if possible" means: can ANY model get within 1" of an enemy with 3" movement?
	var can_reach_engagement = _can_unit_reach_engagement_range(unit)

	if can_reach_engagement:
		return "ENGAGEMENT"

	# If cannot reach engagement, try objective mode
	var can_reach_objective = _can_unit_reach_objective_after_movement(unit, movements)

	if can_reach_objective:
		return "OBJECTIVE"

	return "NONE"

func _can_unit_reach_engagement_range(unit: Dictionary) -> bool:
	"""Check if it's POSSIBLE for unit to reach engagement range with 3" movement.
	This means: is ANY enemy model within 4" of ANY friendly model?
	(3" consolidate movement + 1" engagement range)"""
	var models = unit.get("models", [])
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)

	# Check each of our models
	for model in models:
		if not model.get("alive", true):
			continue

		var pos_data = model.get("position", {})
		if pos_data == null:
			continue
		var our_pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))

		# Check against all enemy models
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if other_unit.get("owner", 0) == unit_owner:
				continue

			var enemy_models = other_unit.get("models", [])
			for enemy_model in enemy_models:
				if not enemy_model.get("alive", true):
					continue

				# Check if within 4" (3" move + 1" engagement) using shape-aware edge-to-edge
				var distance = Measurement.model_to_model_distance_inches(model, enemy_model)
				if distance <= 4.0:
					return true

	return false

func _can_unit_maintain_engagement_after_movement(unit: Dictionary, movements: Dictionary) -> bool:
	"""Check if the unit will be in engagement range with at least one enemy after movements"""
	var unit_id = unit.get("id", "")
	var models = unit.get("models", [])
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)

	# Build model dicts with updated positions after movement
	var final_models = []
	for i in models.size():
		var model = models[i]
		if not model.get("alive", true):
			continue

		var model_id = str(i)
		if model_id in movements:
			var moved_model = model.duplicate()
			moved_model["position"] = movements[model_id]
			final_models.append(moved_model)
		else:
			final_models.append(model)

	# Check if any of our models will be in engagement range
	for our_model in final_models:
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if other_unit.get("owner", 0) == unit_owner:
				continue

			var enemy_models = other_unit.get("models", [])
			for enemy_model in enemy_models:
				if not enemy_model.get("alive", true):
					continue

				# T3-9: Check engagement range using barricade-aware distance
				var our_pos = our_model.get("position", Vector2.ZERO)
				if our_pos is Dictionary:
					our_pos = Vector2(our_pos.get("x", 0), our_pos.get("y", 0))
				var enemy_pos = enemy_model.get("position", Vector2.ZERO)
				if enemy_pos is Dictionary:
					enemy_pos = Vector2(enemy_pos.get("x", 0), enemy_pos.get("y", 0))
				var effective_er = _get_effective_engagement_range(our_pos, enemy_pos)
				if Measurement.is_in_engagement_range_shape_aware(our_model, enemy_model, effective_er):
					return true

	return false

func _can_unit_reach_objective_after_movement(unit: Dictionary, movements: Dictionary) -> bool:
	"""Check if unit can reach an objective after movement.
	At least one model must end within range of an objective (3" range as per rules)."""
	var objectives = GameState.state.board.get("objectives", [])
	if objectives.is_empty():
		return false

	var models = unit.get("models", [])

	# Build final positions after movement
	var final_positions = []
	for i in models.size():
		var model = models[i]
		if not model.get("alive", true):
			continue

		var model_id = str(i)
		if model_id in movements:
			final_positions.append(movements[model_id])
		else:
			var pos_data = model.get("position", {})
			final_positions.append(Vector2(pos_data.get("x", 0), pos_data.get("y", 0)))

	# Check if any model's BASE EDGE will be within 3" of objective BASE EDGE
	# This is edge-to-edge distance using proper base shape calculations
	# Objectives have 40mm radius = ~0.787"
	const OBJECTIVE_RADIUS_MM = 40.0

	for i in models.size():
		var model = models[i]
		if not model.get("alive", true):
			continue

		var model_id = str(i)
		var model_pos: Vector2
		if model_id in movements:
			model_pos = movements[model_id]
		else:
			var pos_data = model.get("position", {})
			model_pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))

		# Create model with position for shape-aware distance calculation
		var model_with_pos = model.duplicate()
		model_with_pos["position"] = model_pos

		for objective in objectives:
			var obj_pos = objective.get("position", Vector2.ZERO)
			if obj_pos == Vector2.ZERO:
				continue

			# Calculate shape-aware edge-to-edge distance from model to objective
			var edge_distance = _model_to_objective_distance_inches(model_with_pos, obj_pos, OBJECTIVE_RADIUS_MM)

			# Check if edge-to-edge distance is within 3"
			if edge_distance <= 3.0:
				return true

	return false

func _model_to_objective_distance_inches(model: Dictionary, objective_pos: Vector2, objective_radius_mm: float) -> float:
	"""Calculate edge-to-edge distance from model base to objective marker.
	Handles circular, oval, and rectangular bases correctly."""
	var model_pos = model.get("position", Vector2.ZERO)
	if model_pos is Dictionary:
		model_pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))

	var rotation = model.get("rotation", 0.0)

	# Create model's base shape
	var model_shape = Measurement.create_base_shape(model)

	# Get closest point on model's base edge to objective center
	var closest_point_on_model = model_shape.get_closest_edge_point(objective_pos, model_pos, rotation)

	# Distance from model edge to objective center
	var distance_to_center_px = closest_point_on_model.distance_to(objective_pos)

	# Convert to inches and subtract objective radius
	var distance_to_center_inches = Measurement.px_to_inches(distance_to_center_px)
	var objective_radius_inches = objective_radius_mm / 25.4

	# Edge-to-edge distance
	return distance_to_center_inches - objective_radius_inches

func _validate_consolidate_engagement_range(unit_id: String, movements: Dictionary) -> Dictionary:
	"""Validate consolidate when ending in engagement range"""
	var errors = []
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])

	# Each model must:
	# 1. Move max 3"
	# 2. End closer to closest enemy
	# 3. End in base contact if possible
	# 4. Maintain unit coherency
	# 5. Not overlap other models

	for model_id in movements:
		var old_pos = _get_model_position(unit_id, model_id)
		var new_pos = movements[model_id]

		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % model_id)
			continue

		# T4-5: Reject movement for models already in base contact with an enemy
		if _is_model_in_base_contact_with_enemy(unit_id, model_id):
			var move_distance = Measurement.distance_inches(old_pos, new_pos)
			if move_distance > 0.01:  # Model actually moved
				errors.append("Model %s is already in base contact — cannot move during consolidation" % model_id)
				log_phase_message("[T4-5] Model %s rejected: already in base contact, moved %.2f\" during consolidation" % [model_id, move_distance])
				continue

		# Check 3" movement limit
		var distance = Measurement.distance_inches(old_pos, new_pos)
		if distance > 3.0:
			errors.append("Model %s consolidate exceeds 3\" limit (%.1f\")" % [model_id, distance])

		# Check movement is toward closest enemy
		if not _is_moving_toward_closest_enemy(unit_id, model_id, old_pos, new_pos):
			errors.append("Model %s must consolidate toward closest enemy" % model_id)

	# Check for model overlaps
	var overlap_check = _validate_no_overlaps_for_movement(unit_id, movements)
	if not overlap_check.valid:
		errors.append_array(overlap_check.errors)

	# Check unit coherency maintained
	var coherency_check = _validate_unit_coherency(unit_id, movements)
	if not coherency_check.get("valid", false):
		errors.append_array(coherency_check.get("errors", []))

	# Check unit ends in engagement range
	if not _can_unit_maintain_engagement_after_movement(unit, movements):
		errors.append("Unit must end within Engagement Range of at least one enemy")

	# T1-6: Base-to-base contact enforcement for consolidation in engagement mode
	# Same rule as pile-in: models must end in b2b with closest enemy if possible.
	var b2b_check = _validate_base_to_base_if_possible(unit_id, movements, 3.0)
	if not b2b_check.valid:
		errors.append_array(b2b_check.errors)

	return {"valid": errors.is_empty(), "errors": errors}

func _validate_consolidate_objective(unit_id: String, movements: Dictionary) -> Dictionary:
	"""Validate consolidate when moving toward objective (fallback mode)"""
	var errors = []
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var objectives = GameState.state.board.get("objectives", [])

	if objectives.is_empty():
		errors.append("No objectives available for consolidate")
		return {"valid": false, "errors": errors}

	# Each model must:
	# 1. Move max 3"
	# 2. Move toward closest objective marker
	# 3. Unit must end within range of objective (at least one model)
	# 4. Maintain unit coherency
	# 5. Not overlap other models

	for model_id in movements:
		var old_pos = _get_model_position(unit_id, model_id)
		var new_pos = movements[model_id]

		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % model_id)
			continue

		# Check 3" movement limit
		var distance = Measurement.distance_inches(old_pos, new_pos)
		if distance > 3.0:
			errors.append("Model %s consolidate exceeds 3\" limit (%.1f\")" % [model_id, distance])

		# Check movement is toward closest objective
		if not _is_moving_toward_closest_objective(old_pos, new_pos, objectives):
			errors.append("Model %s must consolidate toward closest objective" % model_id)

	# Check for model overlaps
	var overlap_check = _validate_no_overlaps_for_movement(unit_id, movements)
	if not overlap_check.valid:
		errors.append_array(overlap_check.errors)

	# Check unit coherency maintained
	var coherency_check = _validate_unit_coherency(unit_id, movements)
	if not coherency_check.get("valid", false):
		errors.append_array(coherency_check.get("errors", []))

	# Check unit ends within range of objective
	if not _can_unit_reach_objective_after_movement(unit, movements):
		errors.append("At least one model must end within 3\" of an objective marker")

	return {"valid": errors.is_empty(), "errors": errors}

func _is_moving_toward_closest_objective(old_pos: Vector2, new_pos: Vector2, objectives: Array) -> bool:
	"""Check if model is moving toward the closest objective marker"""
	var closest_obj_pos = _find_closest_objective_position(old_pos, objectives)
	if closest_obj_pos == Vector2.ZERO:
		return true  # No objectives found, allow movement

	# Check if new position is closer to objective than old position
	var old_distance = old_pos.distance_to(closest_obj_pos)
	var new_distance = new_pos.distance_to(closest_obj_pos)
	return new_distance <= old_distance

func _find_closest_objective_position(from_pos: Vector2, objectives: Array) -> Vector2:
	"""Find the closest objective marker position"""
	var closest_pos = Vector2.ZERO
	var closest_distance = INF

	for objective in objectives:
		var obj_pos = objective.get("position", Vector2.ZERO)
		if obj_pos == Vector2.ZERO:
			continue

		var distance = from_pos.distance_to(obj_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_pos = obj_pos

	return closest_pos

func _validate_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var errors = []

	# FGT-1 / P2-78: Cannot skip a unit that is mid-fight and needs to consolidate.
	# Consolidation is mandatory at the unit level per FAQ.
	if active_fighter_id == unit_id and pending_attacks.is_empty() and confirmed_attacks.is_empty():
		errors.append("Unit must complete mandatory consolidation before being skipped (FAQ: consolidation is not optional)")
		return {"valid": false, "errors": errors}

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

	# Check for Epic Challenge opportunity before pile-in
	var epic_check = StratagemManager.is_epic_challenge_available(current_selecting_player, active_fighter_id)
	if epic_check.available:
		log_phase_message("EPIC CHALLENGE available for %s (CHARACTER unit)" % active_fighter_id)
		emit_signal("epic_challenge_opportunity", active_fighter_id, current_selecting_player)

		# Add metadata so NetworkManager can re-emit on client
		var result = create_result(true, [])
		result["trigger_epic_challenge"] = true
		result["epic_challenge_unit_id"] = active_fighter_id
		result["epic_challenge_player"] = current_selecting_player
		return result

	# No Epic Challenge available - check for Martial Ka'tah before pile-in
	return _check_katah_or_proceed_to_pile_in(active_fighter_id)

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
	units_that_piled_in[unit_id] = true
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

	# T3-3: Auto-inject Extra Attacks weapons if not already assigned
	# This is a safety net for AI/auto-resolve paths that bypass the dialog
	_auto_inject_extra_attacks_weapons()

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
	# Trigger attack animation on the fighting unit
	_trigger_unit_animation(active_fighter_id, "attack")

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

	# P0-58: Determine if defender is a human player for interactive wound allocation
	var defender_is_human = _is_defender_human_player()

	if defender_is_human:
		# P0-58: Interactive path — resolve hits+wounds only, then let defender allocate wounds
		return _process_roll_dice_interactive(melee_action)
	else:
		# AI/auto-resolve path — existing full resolution
		return _process_roll_dice_auto(melee_action)

# P0-58: Check if any target unit's owner is a human player
func _is_defender_human_player() -> bool:
	"""Check if the defending player (target unit owner) should get interactive wound allocation."""
	var ai_player = get_node_or_null("/root/AIPlayer")
	for assignment in confirmed_attacks:
		var target_id = assignment.get("target", "")
		if target_id.is_empty():
			continue
		var target_unit = get_unit(target_id)
		if target_unit.is_empty():
			continue
		var defender_owner = target_unit.get("owner", 0)
		# If AI is not enabled, or if the defender is not an AI player, they're human
		if not ai_player or not ai_player.enabled:
			return true
		if not ai_player.is_ai_player(defender_owner):
			return true
	return false

# P0-58: Interactive path — resolve hits and wounds, then emit saves_required for defender
func _process_roll_dice_interactive(melee_action: Dictionary) -> Dictionary:
	var rng_service = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_melee_attacks_interactive(melee_action, game_state_snapshot, rng_service)

	if not result.success:
		return create_result(false, [], result.get("log_text", "Melee combat failed"))

	# Emit dice results for hit/wound rolls
	for dice_block in result.get("dice", []):
		emit_signal("dice_rolled", dice_block)

	var save_data_list = result.get("save_data_list", [])

	# VERBOSE COMBAT LOG: Emit hit/wound details for interactive melee
	for assignment in confirmed_attacks:
		var vcl_target_id = assignment.get("target", "")
		var non_save_dice = []
		for dice_block in result.get("dice", []):
			var dctx = dice_block.get("context", "")
			if dctx != "save_roll" and dctx != "save" and dctx != "feel_no_pain":
				non_save_dice.append(dice_block)
		_emit_verbose_melee_combat_log(active_fighter_id, vcl_target_id, non_save_dice, [], 0)

	if save_data_list.is_empty():
		# No wounds caused — proceed directly to consolidate (no saves needed)
		print("[FightPhase] P0-58: No wounds caused in interactive melee — skipping saves")
		# Emit resolution signals
		for assignment in confirmed_attacks:
			emit_signal("attacks_resolved", active_fighter_id, assignment.get("target", ""), result)
			emit_signal("fight_resolved", active_fighter_id, result)
		confirmed_attacks.clear()
		log_phase_message("Melee combat resolved for %s (no wounds)" % active_fighter_id)
		emit_signal("consolidate_required", active_fighter_id, 3.0)

		var final_result = create_result(true, result.get("diffs", []))
		final_result["trigger_consolidate"] = true
		final_result["consolidate_unit_id"] = active_fighter_id
		final_result["consolidate_distance"] = 3.0
		final_result["log_text"] = result.get("log_text", "")
		if result.has("dice"):
			final_result["dice"] = result["dice"]
		return final_result

	# Wounds caused — store state and emit saves_required for WoundAllocationOverlay
	pending_melee_save_data = save_data_list
	pending_melee_hit_wound_result = result
	awaiting_melee_saves = true

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ P0-58: MELEE SAVES_REQUIRED EMISSION")
	print("║ Source: FightPhase._process_roll_dice_interactive")
	print("║ Save data list size: %d" % save_data_list.size())
	for i in range(save_data_list.size()):
		var sd = save_data_list[i]
		print("║   [%d] Target: %s, Weapon: %s, Wounds: %d" % [i, sd.get("target_unit_name", "?"), sd.get("weapon_name", "?"), sd.get("wounds_to_save", 0)])
	print("╚═══════════════════════════════════════════════════════════════")

	emit_signal("saves_required", save_data_list)

	log_phase_message("Awaiting defender wound allocation for melee combat...")

	# Return success but don't proceed to consolidate — wait for APPLY_MELEE_SAVES
	var pause_result = create_result(true, result.get("diffs", []), "Awaiting melee save resolution")
	pause_result["awaiting_melee_saves"] = true
	pause_result["log_text"] = result.get("log_text", "")
	if result.has("dice"):
		pause_result["dice"] = result["dice"]
	if not save_data_list.is_empty():
		pause_result["save_data_list"] = save_data_list
	return pause_result

# Original auto-resolve path (for AI defenders)
func _process_roll_dice_auto(melee_action: Dictionary) -> Dictionary:
	var rng_service = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_melee_attacks(melee_action, game_state_snapshot, rng_service)

	# Debug logging for state changes
	if result.has("diffs") and not result.diffs.is_empty():
		print("[FightPhase] RulesEngine returned %d state changes" % result.diffs.size())
		for diff in result.diffs:
			print("  - %s: %s = %s" % [diff.op, diff.path, diff.value])

	if not result.success:
		return create_result(false, [], result.get("log_text", "Melee combat failed"))

	# Process dice results step by step (like shooting phase)
	for dice_block in result.get("dice", []):
		emit_signal("dice_rolled", dice_block)

	# VERBOSE COMBAT LOG: Emit detailed melee combat log
	if result.success:
		for assignment in confirmed_attacks:
			var target_id = assignment.get("target", "")
			var save_blocks = []
			for dice_block in result.get("dice", []):
				var dctx = dice_block.get("context", "")
				if dctx == "save_roll" or dctx == "save" or dctx == "feel_no_pain":
					save_blocks.append(dice_block)
			var non_save_dice = []
			for dice_block in result.get("dice", []):
				var dctx = dice_block.get("context", "")
				if dctx != "save_roll" and dctx != "save" and dctx != "feel_no_pain":
					non_save_dice.append(dice_block)
			var melee_casualties = 0
			for diff in result.get("diffs", []):
				if diff.get("path", "").ends_with(".alive") and diff.get("value") == false:
					melee_casualties += 1
			_emit_verbose_melee_combat_log(active_fighter_id, target_id, non_save_dice, save_blocks, melee_casualties)

	# Emit resolution signals for each target
	if result.success:
		for assignment in confirmed_attacks:
			emit_signal("attacks_resolved", active_fighter_id, assignment.target, result)
			emit_signal("fight_resolved", active_fighter_id, result)  # Compatibility signal (2 params)

	# Clear confirmed attacks after resolution
	confirmed_attacks.clear()

	# Return fighter to idle animation
	_trigger_unit_animation(active_fighter_id, "idle")

	log_phase_message("Melee combat resolved for %s" % active_fighter_id)

	# After attacks, request consolidate
	emit_signal("consolidate_required", active_fighter_id, 3.0)

	# Add metadata for NetworkManager to re-emit signal on client
	var final_result = create_result(true, result.get("diffs", []))
	final_result["trigger_consolidate"] = true
	final_result["consolidate_unit_id"] = active_fighter_id
	final_result["consolidate_distance"] = 3.0
	final_result["log_text"] = result.get("log_text", "")

	# Preserve dice and save_data_list from combat resolution
	if result.has("dice"):
		final_result["dice"] = result["dice"]
	if result.has("save_data_list"):
		final_result["save_data_list"] = result["save_data_list"]

	return final_result

# T3-12: Batch fight actions to avoid multiplayer race conditions
# Instead of sending individual ASSIGN_ATTACKS + CONFIRM + ROLL_DICE with fixed delays,
# the controller sends a single BATCH_FIGHT_ACTIONS that is processed atomically.
func _validate_batch_fight_actions(action: Dictionary) -> Dictionary:
	var sub_actions = action.get("sub_actions", [])
	if sub_actions.is_empty():
		return {"valid": false, "errors": ["BATCH_FIGHT_ACTIONS requires non-empty sub_actions array"]}

	# Validate each sub-action individually
	for i in range(sub_actions.size()):
		var sub = sub_actions[i]
		# Copy player/timestamp from parent action if not present on sub-action
		if not sub.has("player"):
			sub["player"] = action.get("player", 0)
		if not sub.has("timestamp"):
			sub["timestamp"] = action.get("timestamp", 0)
		var sub_result = validate_action(sub)
		if not sub_result.get("valid", false):
			# For ASSIGN_ATTACKS, validate only the first one before processing
			# (subsequent ones depend on state changes from earlier actions)
			# So we only validate the first sub-action strictly
			if i == 0:
				return {"valid": false, "errors": sub_result.get("errors", ["Sub-action %d failed validation" % i])}
			else:
				# Skip validation for later sub-actions since state will change
				# as earlier actions are processed
				break

	return {"valid": true}

func _process_batch_fight_actions(action: Dictionary) -> Dictionary:
	var sub_actions = action.get("sub_actions", [])
	var all_changes = []
	var last_result = {}

	print("[FightPhase] Processing BATCH_FIGHT_ACTIONS with %d sub-actions" % sub_actions.size())

	for i in range(sub_actions.size()):
		var sub = sub_actions[i]
		# Copy player/timestamp from parent action if not present
		if not sub.has("player"):
			sub["player"] = action.get("player", 0)
		if not sub.has("timestamp"):
			sub["timestamp"] = action.get("timestamp", 0)

		print("[FightPhase] Batch sub-action %d: %s" % [i, sub.get("type", "")])
		var result = process_action(sub)

		if not result.get("success", false):
			push_error("[FightPhase] Batch sub-action %d (%s) failed: %s" % [i, sub.get("type", ""), result.get("log_text", "unknown error")])
			return result

		# Accumulate state changes from all sub-actions
		if result.has("changes"):
			all_changes.append_array(result.get("changes", []))

		last_result = result

	# Return the last result (ROLL_DICE result) with all accumulated changes
	# This preserves metadata like trigger_consolidate, dice, save_data_list
	if not all_changes.is_empty():
		last_result["changes"] = all_changes

	print("[FightPhase] BATCH_FIGHT_ACTIONS completed successfully")
	return last_result

# P0-58: Validate APPLY_MELEE_SAVES action
func _validate_apply_melee_saves(action: Dictionary) -> Dictionary:
	if not awaiting_melee_saves:
		return {"valid": false, "errors": ["Not awaiting melee saves"]}
	return {"valid": true}

# P0-58: Process APPLY_MELEE_SAVES — apply damage from interactive wound allocation
func _process_apply_melee_saves(action: Dictionary) -> Dictionary:
	"""Process save results from WoundAllocationOverlay and apply melee damage."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ P0-58: APPLY_MELEE_SAVES PROCESSING START")
	print("║ Timestamp: ", Time.get_ticks_msec())
	print("║ pending_melee_save_data.size(): ", pending_melee_save_data.size())
	print("╚═══════════════════════════════════════════════════════════════")

	var payload = action.get("payload", {})
	var save_results_list = payload.get("save_results_list", [])

	var all_diffs = []
	var total_casualties = 0
	var save_dice_blocks = []

	# Include any diffs from the hit/wound phase (e.g., hazardous self-damage)
	if pending_melee_hit_wound_result.has("diffs"):
		all_diffs.append_array(pending_melee_hit_wound_result.get("diffs", []))

	for i in range(save_results_list.size()):
		if i >= pending_melee_save_data.size():
			break

		var save_result_summary = save_results_list[i]
		var save_data = pending_melee_save_data[i]
		var target_name = save_data.get("target_unit_name", "Unknown")
		var target_unit_id = save_data.get("target_unit_id", "")

		print("╔═══════════════════════════════════════════════════════════════")
		print("║ P0-58: PROCESSING MELEE SAVE RESULT %d" % i)
		print("║ Target: %s" % target_name)
		print("║ save_result_summary keys: ", save_result_summary.keys())
		print("╚═══════════════════════════════════════════════════════════════")

		# Convert allocation_history to save_results format if needed
		var save_results = []
		if save_result_summary.has("save_results"):
			save_results = save_result_summary.save_results
		elif save_result_summary.has("allocation_history"):
			print("[FightPhase] P0-58: Converting allocation_history to save_results format")
			for alloc in save_result_summary.allocation_history:
				save_results.append({
					"saved": alloc.get("saved", false),
					"model_id": alloc.get("model_id", ""),
					"model_index": alloc.get("model_index", 0),
					"roll": alloc.get("roll", 0),
					"damage": alloc.get("damage", 0),
					"model_destroyed": alloc.get("model_destroyed", false)
				})

		# DEVASTATING WOUNDS: Apply devastating damage
		var devastating_damage = save_result_summary.get("devastating_damage", 0)
		if devastating_damage > 0:
			print("[FightPhase] P0-58: Devastating wounds: %d damage" % devastating_damage)

		# Apply damage using RulesEngine
		if not save_results.is_empty():
			var fnp_rng = RulesEngine.RNGService.new()
			var damage_result = RulesEngine.apply_save_damage(
				save_results,
				save_data,
				game_state_snapshot,
				-1,
				fnp_rng
			)

			all_diffs.append_array(damage_result.diffs)
			total_casualties += damage_result.casualties

			# Check if bodyguard unit was destroyed
			if damage_result.casualties > 0 and target_unit_id != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id)

			# Build save dice block for logging
			var saved_count = 0
			var failed_count = 0
			var save_rolls_raw = []
			for sr in save_results:
				save_rolls_raw.append(sr.get("roll", 0))
				if sr.get("saved", false):
					saved_count += 1
				else:
					failed_count += 1

			if not save_rolls_raw.is_empty():
				var save_dice_block = {
					"context": "save_roll_melee",
					"threshold": str(save_data.get("base_save", 7)) + "+",
					"rolls_raw": save_rolls_raw,
					"successes": saved_count,
					"failed": failed_count,
					"ap": save_data.get("ap", 0),
					"original_save": save_data.get("base_save", 7),
					"weapon_name": save_data.get("weapon_name", ""),
					"target_unit_name": target_name
				}
				save_dice_blocks.append(save_dice_block)
				dice_log.append(save_dice_block)
				emit_signal("dice_rolled", save_dice_block)

			# Emit FNP dice blocks
			var fnp_rolls = damage_result.get("fnp_rolls", [])
			for fnp_block in fnp_rolls:
				var fnp_dice_block = {
					"context": "feel_no_pain",
					"threshold": str(fnp_block.get("fnp_value", 0)) + "+",
					"rolls_raw": fnp_block.get("rolls", []),
					"fnp_value": fnp_block.get("fnp_value", 0),
					"wounds_prevented": fnp_block.get("wounds_prevented", 0),
					"wounds_remaining": fnp_block.get("wounds_remaining", 0),
					"total_wounds": fnp_block.get("total_wounds", 0),
					"source": fnp_block.get("source", ""),
					"target_unit_name": target_name
				}
				dice_log.append(fnp_dice_block)
				emit_signal("dice_rolled", fnp_dice_block)

			# Also collect FNP data from allocation_history
			if save_result_summary.has("allocation_history"):
				var fnp_rolls_from_overlay = []
				for alloc in save_result_summary.allocation_history:
					var alloc_fnp = alloc.get("fnp_rolls", [])
					if not alloc_fnp.is_empty():
						fnp_rolls_from_overlay.append_array(alloc_fnp)
				if not fnp_rolls_from_overlay.is_empty():
					var fnp_val = save_result_summary.allocation_history[0].get("fnp_value", 0)
					var total_prevented = 0
					for alloc in save_result_summary.allocation_history:
						total_prevented += alloc.get("fnp_prevented", 0)
					var fnp_overlay_block = {
						"context": "feel_no_pain",
						"threshold": str(fnp_val) + "+",
						"rolls_raw": fnp_rolls_from_overlay,
						"fnp_value": fnp_val,
						"wounds_prevented": total_prevented,
						"wounds_remaining": fnp_rolls_from_overlay.size() - total_prevented,
						"total_wounds": fnp_rolls_from_overlay.size(),
						"source": "interactive_melee_saves",
						"target_unit_name": target_name
					}
					dice_log.append(fnp_overlay_block)
					emit_signal("dice_rolled", fnp_overlay_block)

			log_phase_message("Melee saves for %s: %d saved, %d failed → %d casualties" % [
				target_name, saved_count, failed_count, damage_result.casualties
			])

	# VERBOSE COMBAT LOG: Emit save details and result for melee saves
	# Normalize save_roll_melee context to save_roll for our log helpers
	var normalized_save_blocks = []
	for sb in save_dice_blocks:
		var nsb = sb.duplicate()
		if nsb.get("context", "") == "save_roll_melee":
			nsb["context"] = "save_roll"
			# Get proper threshold from model profiles
			var sb_profiles = []
			for sd in pending_melee_save_data:
				sb_profiles = sd.get("model_save_profiles", [])
				break
			if not sb_profiles.is_empty():
				nsb["threshold"] = str(sb_profiles[0].get("save_needed", 7)) + "+"
				nsb["using_invuln"] = sb_profiles[0].get("using_invuln", false)
		normalized_save_blocks.append(nsb)
	for nsb in normalized_save_blocks:
		var nsb_ctx = nsb.get("context", "")
		if nsb_ctx == "save_roll":
			_emit_melee_save_detail(nsb)
		elif nsb_ctx == "feel_no_pain":
			_emit_melee_fnp_detail(nsb)
	if total_casualties > 0:
		GameEventLog.add_combat_result("  Result: %d model(s) destroyed" % total_casualties)
	else:
		GameEventLog.add_combat_result("  Result: No models destroyed")

	# Clear pending state
	awaiting_melee_saves = false
	pending_melee_save_data.clear()
	pending_melee_hit_wound_result.clear()

	# Emit resolution signals for each confirmed attack target
	var result_for_signals = {"success": true, "diffs": all_diffs, "dice": save_dice_blocks}
	for assignment in confirmed_attacks:
		emit_signal("attacks_resolved", active_fighter_id, assignment.get("target", ""), result_for_signals)
		emit_signal("fight_resolved", active_fighter_id, result_for_signals)

	# Clear confirmed attacks after resolution
	confirmed_attacks.clear()

	log_phase_message("Melee combat resolved for %s (interactive saves)" % active_fighter_id)

	# After attacks, request consolidate
	emit_signal("consolidate_required", active_fighter_id, 3.0)

	# Build final result
	var final_result = create_result(true, all_diffs)
	final_result["trigger_consolidate"] = true
	final_result["consolidate_unit_id"] = active_fighter_id
	final_result["consolidate_distance"] = 3.0
	final_result["log_text"] = "Melee saves applied — %d casualties" % total_casualties
	final_result["dice"] = save_dice_blocks

	print("[FightPhase] P0-58: APPLY_MELEE_SAVES complete — %d casualties, %d diffs" % [total_casualties, all_diffs.size()])

	return final_result

# T3-3: Auto-inject Extra Attacks weapons that aren't already in confirmed_attacks
# Extra Attacks weapons must be used IN ADDITION to the selected weapon, not instead of it.
# This ensures AI/auto-resolve paths also correctly include Extra Attacks.
func _auto_inject_extra_attacks_weapons() -> void:
	if active_fighter_id.is_empty():
		return

	var unit = get_unit(active_fighter_id)
	if unit.is_empty():
		return

	var weapons_data = unit.get("meta", {}).get("weapons", [])

	# Find Extra Attacks melee weapons
	var ea_weapons = []
	for weapon in weapons_data:
		if weapon.get("type", "").to_lower() == "melee":
			if RulesEngine.weapon_data_has_extra_attacks(weapon):
				ea_weapons.append(weapon)

	if ea_weapons.is_empty():
		return

	# Check which EA weapons are already assigned
	var assigned_weapon_ids = {}
	for attack in confirmed_attacks:
		assigned_weapon_ids[attack.get("weapon", "")] = true

	# Determine default target: use first confirmed attack's target, or first known target
	var default_target = ""
	if not confirmed_attacks.is_empty():
		default_target = confirmed_attacks[0].get("target", "")

	for weapon in ea_weapons:
		var weapon_name = weapon.get("name", "Unknown")
		var weapon_id = RulesEngine._generate_weapon_id(weapon_name, weapon.get("type", ""))

		if assigned_weapon_ids.has(weapon_id):
			print("[FightPhase] T3-3: Extra Attacks weapon '%s' already assigned, skipping" % weapon_name)
			continue

		if default_target.is_empty():
			print("[FightPhase] T3-3: No target available for Extra Attacks weapon '%s'" % weapon_name)
			continue

		confirmed_attacks.append({
			"attacker": active_fighter_id,
			"weapon": weapon_id,
			"target": default_target
		})
		print("[FightPhase] T3-3: Auto-injected Extra Attacks weapon '%s' → '%s'" % [weapon_name, default_target])

	log_phase_message("T3-3: Extra Attacks weapons auto-included for %s" % active_fighter_id)

func _show_mathhammer_predictions() -> void:
	# Use mathhammer to calculate expected results before rolling
	if confirmed_attacks.is_empty():
		return

	var attacker_unit = get_unit(active_fighter_id)
	var attacker_name = attacker_unit.get("meta", {}).get("name", active_fighter_id)
	var attacker_models = attacker_unit.get("models", [])

	# Group confirmed attacks by target for per-target simulations
	var attacks_by_target: Dictionary = {}
	for attack in confirmed_attacks:
		var target_id = attack.get("target", "")
		if target_id == "":
			continue
		if not attacks_by_target.has(target_id):
			attacks_by_target[target_id] = []
		attacks_by_target[target_id].append(attack)

	var prediction_lines = ["[b]Mathhammer Melee Predictions:[/b]"]

	for target_id in attacks_by_target:
		var target_attacks = attacks_by_target[target_id]
		var target_unit = get_unit(target_id)
		var target_name = target_unit.get("meta", {}).get("name", target_id)

		# Build attacker weapon configs from confirmed attacks for this target
		var weapons = []
		for attack in target_attacks:
			var weapon_id = attack.get("weapon", "")
			var attacking_models = attack.get("models", [])

			# Build model_ids list from attacking models
			var model_ids = []
			if not attacking_models.is_empty():
				model_ids = attacking_models
			else:
				# Default to all alive models
				for i in range(attacker_models.size()):
					if attacker_models[i].get("alive", true):
						model_ids.append(str(i))

			# Get weapon profile to determine attack count
			var weapon_profile = RulesEngine.get_weapon_profile(weapon_id, game_state_snapshot)
			var base_attacks = weapon_profile.get("attacks", 1)

			weapons.append({
				"weapon_id": weapon_id,
				"model_ids": model_ids,
				"attacks": base_attacks
			})

		var attacker_config = {
			"unit_id": active_fighter_id,
			"weapons": weapons
		}

		# Check if attacker has charged this turn (for Lance bonus)
		var rule_toggles = {}
		var flags = attacker_unit.get("flags", {})
		if flags.get("charged_this_turn", false):
			rule_toggles["lance_charged"] = true

		# Build mathhammer simulation config
		var config = {
			"trials": 1000,  # Reduced for real-time predictions
			"attackers": [attacker_config],
			"defender": {"unit_id": target_id},
			"rule_toggles": rule_toggles,
			"phase": "fight",
			"seed": randi()
		}

		# Run simulation
		var result = Mathhammer.simulate_combat(config)
		var avg_damage = result.get_average_damage()
		var kill_prob = result.kill_probability * 100.0

		# Build weapon breakdown text
		var weapon_texts = []
		for attack in target_attacks:
			var w_id = attack.get("weapon", "")
			var w_profile = RulesEngine.get_weapon_profile(w_id, game_state_snapshot)
			var w_name = w_profile.get("name", w_id)
			weapon_texts.append(w_name)

		prediction_lines.append(
			"%s (%s) -> %s: ~%.1f wounds, %.0f%% kill" % [
				attacker_name,
				", ".join(weapon_texts),
				target_name,
				avg_damage,
				kill_prob
			]
		)

	var prediction_text = "\n".join(prediction_lines)
	print("[FightPhase] Mathhammer prediction: %s" % prediction_text)

	# Display predictions via dice_rolled signal (like shooting phase)
	emit_signal("dice_rolled", {
		"context": "mathhammer_prediction",
		"message": prediction_text
	})

func _process_consolidate(action: Dictionary) -> Dictionary:
	var changes = []
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})

	# FGT-1 / P2-78: Consolidation is mandatory at unit level per FAQ.
	# "Consolidation for a unit is not optional. However, for each model,
	# whether or not that model makes a Consolidation move is optional."
	if movements.is_empty():
		log_phase_message("[FGT-1] %s completes mandatory consolidation step — no models elected to move" % unit_id)
	else:
		log_phase_message("[Consolidate] %s — %d model(s) moved" % [unit_id, movements.size()])

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

	# Clear Martial Ka'tah stance — "active until the unit finishes attacking"
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr:
		faction_mgr.clear_katah_stance(unit_id)
		# Also clear from snapshot
		if game_state_snapshot.has("units") and game_state_snapshot.units.has(unit_id):
			var snap_flags = game_state_snapshot.units[unit_id].get("flags", {})
			snap_flags.erase("effect_sustained_hits")
			snap_flags.erase("effect_lethal_hits")
			snap_flags.erase("katah_stance")
			snap_flags.erase("katah_sustained_hits_value")

	# Legacy support - update old index
	current_fight_index += 1

	# T2-6: After consolidation, scan for newly eligible units.
	# Per 10e rules: "After an enemy unit has finished its Consolidation move,
	# if previously ineligible units are now eligible to Fight — these units can
	# then be selected to fight."
	# We must check using post-consolidation positions since the game_state_snapshot
	# hasn't been updated yet (diffs are applied after process_action returns).
	var newly_eligible = _scan_newly_eligible_units_after_consolidation(unit_id, movements)

	# Determine which player just fought and which is the opponent
	var fought_unit = get_unit(unit_id)
	var fought_unit_owner = int(fought_unit.get("owner", 0))
	var opponent_player = 2 if fought_unit_owner == 1 else 1

	# Check if Counter-Offensive is available for the opponent
	var co_check = StratagemManager.is_counter_offensive_available(opponent_player)
	var co_eligible = []
	if co_check.available:
		co_eligible = StratagemManager.get_counter_offensive_eligible_units(
			opponent_player, units_that_fought, game_state_snapshot
		)

	if not co_eligible.is_empty():
		# Counter-Offensive is available! Pause and offer it to the opponent
		awaiting_counter_offensive = true
		counter_offensive_player = opponent_player
		log_phase_message("COUNTER-OFFENSIVE available for Player %d (%d eligible units)" % [opponent_player, co_eligible.size()])

		emit_signal("counter_offensive_opportunity", opponent_player, co_eligible)

		var result = create_result(true, changes)
		result["trigger_counter_offensive"] = true
		result["counter_offensive_player"] = opponent_player
		result["counter_offensive_eligible_units"] = co_eligible
		if not newly_eligible.is_empty():
			result["newly_eligible_units"] = newly_eligible
		return result

	# No Counter-Offensive available — proceed with normal fight selection
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
	if not newly_eligible.is_empty():
		result["newly_eligible_units"] = newly_eligible

	return result

func _process_skip_unit(action: Dictionary) -> Dictionary:
	# Skip this unit and advance to next
	units_that_fought.append(action.unit_id)
	active_fighter_id = ""

	# Clear Martial Ka'tah stance if any
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr:
		faction_mgr.clear_katah_stance(action.unit_id)

	# Legacy support - update old index
	current_fight_index += 1

	# Switch to next player
	_switch_selecting_player()

	# Request next fight selection
	_emit_fight_selection_required()

	log_phase_message("Skipped unit %s" % action.unit_id)
	return create_result(true, [])

func _process_heroic_intervention(action: Dictionary) -> Dictionary:
	# Heroic Intervention is now handled in ChargePhase.gd (after enemy charge move).
	# This action type in FightPhase is kept for backwards compatibility but redirects
	# to an informative error since the stratagem window occurs during the Charge phase.
	log_phase_message("Heroic Intervention is handled during the Charge phase, not the Fight phase")
	return create_result(false, [], "Heroic Intervention is handled during the Charge phase (after an enemy unit ends a Charge move)")

# Helper methods
func _get_fight_priority(unit: Dictionary) -> int:
	var flags = unit.get("flags", {})

	# Determine Fights First status
	# Charged units get Fights First — but Heroic Intervention units do NOT
	# Per 10e: "That unit is not eligible to fight in the Fights First step of the following
	# Fight phase." Heroic Intervention sets charged_this_turn but also heroic_intervention flag.
	var has_fights_first = false
	if flags.get("charged_this_turn", false) and not flags.get("heroic_intervention", false):
		has_fights_first = true

	# Check for Fights First ability
	if not has_fights_first:
		var abilities = unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			if "fights_first" in str(ability).to_lower():
				has_fights_first = true
				break

	# Determine Fights Last status
	var has_fights_last = unit.get("status_effects", {}).get("fights_last", false)

	# Per 10e Rules Commentary: If a unit has both Fights First and Fights Last,
	# they cancel out and the unit fights in the Remaining Combats step (NORMAL).
	if has_fights_first and has_fights_last:
		var unit_name = unit.get("meta", {}).get("name", "Unknown")
		log_phase_message("Unit %s has both Fights First and Fights Last — cancellation applies, fighting in Remaining Combats" % unit_name)
		return FightPriority.NORMAL

	if has_fights_first:
		return FightPriority.FIGHTS_FIRST

	if has_fights_last:
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
		"fights_last_units": fights_last_sequence,
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
		"fights_last_units": fights_last_sequence,
		"units_that_fought": units_that_fought
	}

	log_phase_message("Emitting fight_selection_required signal")
	log_phase_message("===================================")

	return dialog_data

func _emit_fight_selection_required() -> void:
	"""Emit signal to show fight selection dialog with current state.
	Also stores the data in _pending_fight_selection_data so the controller
	can retrieve it after connecting signals (T3-13 fix)."""
	var dialog_data = _build_fight_selection_dialog_data()
	if not dialog_data.is_empty():
		# T3-13: Store pending data for controller sync
		_pending_fight_selection_data = dialog_data
		emit_signal("fight_selection_required", dialog_data)

func get_pending_fight_selection_data() -> Dictionary:
	"""T3-13: Returns any pending fight selection dialog data and clears it.
	Called by FightController after connecting signals to handle the case where
	the signal fired before the controller was connected."""
	var data = _pending_fight_selection_data
	_pending_fight_selection_data = {}
	return data

func _get_eligible_units_for_selection() -> Dictionary:
	"""Get units eligible for selection by current player in current subphase"""
	var eligible = {}
	var player_key = str(current_selecting_player)
	var source_list: Dictionary
	match current_subphase:
		Subphase.FIGHTS_FIRST:
			source_list = fights_first_sequence
		Subphase.REMAINING_COMBATS:
			source_list = normal_sequence
		Subphase.FIGHTS_LAST:
			source_list = fights_last_sequence
		_:
			return eligible

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
	"""Transition from Fights First → Remaining Combats → Fights Last → Complete.
	Returns dialog data for the new subphase if there are units to fight, empty dict otherwise."""
	if current_subphase == Subphase.FIGHTS_FIRST:
		log_phase_message("Fights First complete. Starting Remaining Combats.")
		emit_signal("subphase_transition", "FIGHTS_FIRST", "REMAINING_COMBATS")

		current_subphase = Subphase.REMAINING_COMBATS
		current_selecting_player = _get_defending_player()  # Reset to defender

		# Check if there are any remaining combats
		if normal_sequence["1"].is_empty() and normal_sequence["2"].is_empty():
			log_phase_message("No remaining combats. Checking for Fights Last units.")
			# Fall through to transition to FIGHTS_LAST
			return _transition_subphase()
		else:
			# Build and return dialog data for new subphase WITHOUT calling _emit_fight_selection_required
			# The caller will handle emitting the signal
			return _build_fight_selection_dialog_data_internal()
	elif current_subphase == Subphase.REMAINING_COMBATS:
		log_phase_message("Remaining Combats complete. Starting Fights Last.")
		emit_signal("subphase_transition", "REMAINING_COMBATS", "FIGHTS_LAST")

		current_subphase = Subphase.FIGHTS_LAST
		current_selecting_player = _get_defending_player()  # Reset to defender

		# Check if there are any Fights Last units
		if fights_last_sequence["1"].is_empty() and fights_last_sequence["2"].is_empty():
			log_phase_message("No Fights Last units. All eligible units have fought.")
			log_phase_message("Waiting for player to click 'End Fight Phase' button.")
			# DO NOT auto-emit phase_completed - wait for explicit END_FIGHT action
			return {}
		else:
			log_phase_message("Fights Last units found - P1: %s, P2: %s" % [str(fights_last_sequence["1"]), str(fights_last_sequence["2"])])
			return _build_fight_selection_dialog_data_internal()
	else:
		# Fights Last complete - all eligible units have fought
		log_phase_message("All eligible units have fought in Fight Phase.")
		log_phase_message("Waiting for player to click 'End Fight Phase' button.")
		# DO NOT auto-emit phase_completed - wait for explicit END_FIGHT action
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
	var unit_is_aircraft = _unit_has_keyword(unit, "AIRCRAFT")
	var unit_has_fly = _unit_has_keyword(unit, "FLY")

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		var other_owner = other_unit.get("owner", 0)

		if other_owner != unit_owner and _units_in_engagement_range(unit, other_unit):
			# T4-4: Aircraft can only fight against units that can Fly
			var other_is_aircraft = _unit_has_keyword(other_unit, "AIRCRAFT")
			if unit_is_aircraft and not _unit_has_keyword(other_unit, "FLY"):
				log_phase_message("[T4-4] Target %s excluded: AIRCRAFT %s can only fight FLY units" % [other_unit_id, unit_id])
				continue
			# T4-4: Non-FLY units cannot target Aircraft
			if other_is_aircraft and not unit_has_fly:
				log_phase_message("[T4-4] Target AIRCRAFT %s excluded: attacker %s does not have FLY" % [other_unit_id, unit_id])
				continue

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
	# Get the model data for shape-aware distance
	var unit = get_unit(unit_id)
	var model_data = {}
	var models = unit.get("models", [])
	for i in models.size():
		var m = models[i]
		if str(i) == model_id or m.get("id", "") == model_id:
			model_data = m
			break

	# Find closest enemy model using edge-to-edge distance
	var closest_enemy = _find_closest_enemy_model(unit_id, model_data, old_pos)
	if closest_enemy.is_empty():
		return true  # No enemies found, allow movement

	# Check if new position is closer to enemy than old position (edge-to-edge)
	var model_at_old = model_data.duplicate()
	model_at_old["position"] = old_pos
	var model_at_new = model_data.duplicate()
	model_at_new["position"] = new_pos
	var old_distance = Measurement.model_to_model_distance_px(model_at_old, closest_enemy)
	var new_distance = Measurement.model_to_model_distance_px(model_at_new, closest_enemy)
	return new_distance <= old_distance

func _find_closest_enemy_model(unit_id: String, model_data: Dictionary, from_pos: Vector2) -> Dictionary:
	"""Find the closest enemy model using shape-aware edge-to-edge distance.
	T4-4: Unless a model can Fly, ignore Aircraft when determining the closest enemy model."""
	var unit = get_unit(unit_id)
	var unit_owner = unit.get("owner", 0)
	var unit_has_fly = _unit_has_keyword(unit, "FLY")
	var all_units = game_state_snapshot.get("units", {})
	var closest_enemy = {}
	var closest_distance = INF

	# Create a temporary model dict at from_pos for distance calculation
	var model_at_pos = model_data.duplicate()
	model_at_pos["position"] = from_pos

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit.get("owner", 0) == unit_owner:
			continue  # Skip same army

		# T4-4: Unless a model can Fly, ignore Aircraft when determining closest enemy
		if _unit_has_keyword(other_unit, "AIRCRAFT") and not unit_has_fly:
			continue

		var enemy_models = other_unit.get("models", [])
		for enemy_model in enemy_models:
			if not enemy_model.get("alive", true):
				continue

			var enemy_pos_data = enemy_model.get("position", {})
			if enemy_pos_data == null:
				continue

			var distance = Measurement.model_to_model_distance_px(model_at_pos, enemy_model)

			if distance < closest_distance:
				closest_distance = distance
				closest_enemy = enemy_model

	return closest_enemy

# Keep the position-based version for backward compatibility with callers that only have positions
func _find_closest_enemy_position(unit_id: String, from_pos: Vector2) -> Vector2:
	var unit = get_unit(unit_id)
	var unit_owner = unit.get("owner", 0)
	var unit_has_fly = _unit_has_keyword(unit, "FLY")
	var all_units = game_state_snapshot.get("units", {})
	var closest_pos = Vector2.ZERO
	var closest_distance = INF

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit.get("owner", 0) == unit_owner:
			continue  # Skip same army

		# T4-4: Unless a model can Fly, ignore Aircraft when determining closest enemy
		if _unit_has_keyword(other_unit, "AIRCRAFT") and not unit_has_fly:
			continue

		var models_list = other_unit.get("models", [])
		for model in models_list:
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

const BASE_CONTACT_TOLERANCE_INCHES: float = 0.25  # Match RulesEngine tolerance for digital positioning

func _is_model_in_base_contact_with_enemy(unit_id: String, model_id: String) -> bool:
	"""T4-5: Check if a model is currently in base-to-base contact with any enemy model.
	Uses the original positions from game_state_snapshot (before any pile-in/consolidate movement)."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false

	var models = unit.get("models", [])
	var model_index = int(model_id)
	if model_index >= models.size():
		return false

	var model = models[model_index]
	if not model.get("alive", true):
		return false

	var unit_owner = unit.get("owner", 0)
	var all_units = game_state_snapshot.get("units", {})

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit.get("owner", 0) == unit_owner:
			continue  # Skip friendly units

		for enemy_model in other_unit.get("models", []):
			if not enemy_model.get("alive", true):
				continue

			var distance = Measurement.model_to_model_distance_inches(model, enemy_model)
			if distance <= BASE_CONTACT_TOLERANCE_INCHES:
				return true

	return false

func _validate_base_to_base_if_possible(unit_id: String, movements: Dictionary, max_move_inches: float) -> Dictionary:
	"""T1-6: Enforce base-to-base contact in pile-in/consolidation.
	Rule: Each model must end in base-to-base contact with the closest enemy model
	IF it is possible to reach b2b within the movement limit (3").
	For each moved model:
	  1. Find the closest enemy model (from original position, edge-to-edge)
	  2. If the edge-to-edge distance to that enemy is <= max_move_inches, b2b IS reachable
	  3. If reachable, check if the model's final position IS in b2b (within tolerance)
	  4. If reachable but NOT achieved, flag an error."""
	var errors = []
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)

	for model_id in movements:
		var model_index = int(model_id)
		if model_index >= models.size():
			continue

		var model = models[model_index]
		if not model.get("alive", true):
			continue

		var old_pos = _get_model_position(unit_id, model_id)
		var new_pos = movements[model_id]
		if old_pos == Vector2.ZERO:
			continue

		# Skip models that didn't actually move (no enforcement needed)
		if old_pos.distance_to(new_pos) < 0.5:  # Sub-pixel tolerance
			continue

		# Create model dict at original position for distance calculation
		var model_at_old = model.duplicate()
		model_at_old["position"] = old_pos

		# Find the closest enemy model using shape-aware edge-to-edge distance
		var closest_enemy = _find_closest_enemy_model(unit_id, model, old_pos)
		if closest_enemy.is_empty():
			continue  # No enemies found, skip

		# Check if b2b is reachable: edge-to-edge distance from original position <= max_move_inches
		# Use small tolerance (0.05") to account for floating-point imprecision in px↔inch conversion
		var distance_to_closest = Measurement.model_to_model_distance_inches(model_at_old, closest_enemy)
		var reachability_tolerance: float = 0.05

		if distance_to_closest <= max_move_inches + reachability_tolerance:
			# B2B IS reachable — check if model actually achieved it
			var model_at_new = model.duplicate()
			model_at_new["position"] = new_pos
			var final_distance = Measurement.model_to_model_distance_inches(model_at_new, closest_enemy)

			if final_distance > BASE_CONTACT_TOLERANCE_INCHES:
				var enemy_name = "enemy model"
				errors.append("Model %s can reach base-to-base contact with %s (%.2f\" away) but did not (%.2f\" gap) — must make base contact when possible" % [model_id, enemy_name, distance_to_closest, final_distance])
				log_phase_message("[B2B Enforcement] Model %s could reach b2b (%.2f\" to closest enemy) but ended %.2f\" away" % [model_id, distance_to_closest, final_distance])
		else:
			log_phase_message("[B2B Enforcement] Model %s cannot reach b2b (%.2f\" to closest enemy, max move %.1f\") — no enforcement needed" % [model_id, distance_to_closest, max_move_inches])

	return {"valid": errors.is_empty(), "errors": errors}

func _validate_unit_coherency(unit_id: String, new_positions: Dictionary) -> Dictionary:
	# Use similar logic to MovementPhase coherency checking
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var errors = []

	# Build model dicts with updated positions
	var all_models = []
	for i in models.size():
		var model = models[i]
		var model_id = str(i)

		if model_id in new_positions:
			var moved_model = model.duplicate()
			moved_model["position"] = new_positions[model_id]
			all_models.append(moved_model)
		else:
			var pos_data = model.get("position", {})
			if pos_data == null:
				continue
			all_models.append(model)

	# Check coherency rule: within 2" horizontally AND 5" vertically (shape-aware edge-to-edge)
	for i in range(all_models.size()):
		var has_nearby_model = false
		for j in range(all_models.size()):
			if i == j:
				continue
			if Measurement.is_within_coherency(all_models[i], all_models[j]):
				has_nearby_model = true
				break

		if not has_nearby_model and all_models.size() > 1:
			errors.append("Model %d breaks unit coherency (not within 2\" horizontally and 5\" vertically of any other model)" % i)
	
	return {"valid": errors.is_empty(), "errors": errors}

func _clear_unit_fight_state(unit_id: String) -> void:
	# Clear any temporary fight flags
	pass

# T5-V13: Set is_engaged + fight_priority flags on all units currently in combat
func _set_engagement_flags() -> void:
	# Collect engaged unit IDs with their fight priority from the already-built sequences
	var engaged_units: Dictionary = {}  # unit_id -> fight_priority (int)
	for uid in fights_first_sequence.get("1", []) + fights_first_sequence.get("2", []):
		engaged_units[uid] = FightPriority.FIGHTS_FIRST
	for uid in normal_sequence.get("1", []) + normal_sequence.get("2", []):
		engaged_units[uid] = FightPriority.NORMAL
	for uid in fights_last_sequence.get("1", []) + fights_last_sequence.get("2", []):
		engaged_units[uid] = FightPriority.FIGHTS_LAST

	# Set flags directly on GameState so TokenVisual can read them
	for unit_id in engaged_units:
		var gs_unit = GameState.get_unit(unit_id)
		if gs_unit.is_empty():
			continue
		if not gs_unit.has("flags"):
			gs_unit["flags"] = {}
		gs_unit["flags"]["is_engaged"] = true
		gs_unit["flags"]["fight_priority"] = engaged_units[unit_id]

	log_phase_message("T5-V13: Set is_engaged flag on %d units" % engaged_units.size())

# T5-V13: Clear is_engaged + fight_priority flags from all units
func _clear_engagement_flags() -> void:
	var all_units = GameState.state.get("units", {}) if GameState.state is Dictionary else {}
	var cleared = 0
	for unit_id in all_units:
		var unit = all_units[unit_id]
		var flags = unit.get("flags", {})
		if flags.has("is_engaged"):
			flags.erase("is_engaged")
			cleared += 1
		if flags.has("fight_priority"):
			flags.erase("fight_priority")
	if cleared > 0:
		log_phase_message("T5-V13: Cleared is_engaged flag from %d units" % cleared)

func get_available_actions() -> Array:
	var actions = []

	log_phase_message("=== get_available_actions DEBUG ===")
	log_phase_message("active_fighter_id: '%s'" % active_fighter_id)
	log_phase_message("current_fight_index: %d" % current_fight_index)
	log_phase_message("fight_sequence.size(): %d" % fight_sequence.size())
	log_phase_message("fight_sequence: %s" % str(fight_sequence))

	# P0-58: If awaiting melee saves, only allow APPLY_MELEE_SAVES
	if awaiting_melee_saves:
		actions.append({
			"type": "APPLY_MELEE_SAVES",
			"description": "Apply melee saves (interactive wound allocation)"
		})
		log_phase_message("P0-58: Awaiting melee saves — returning APPLY_MELEE_SAVES only")
		return actions

	# If no active fighter, need to select one
	# Skip units that are no longer in engagement range (enemies may have been destroyed during earlier fights)
	if active_fighter_id == "" and current_fight_index < fight_sequence.size():
		while current_fight_index < fight_sequence.size():
			var candidate_unit_id = fight_sequence[current_fight_index]
			var candidate_unit = game_state_snapshot.get("units", {}).get(candidate_unit_id, {})
			if not candidate_unit.is_empty() and _is_unit_in_combat(candidate_unit):
				break
			log_phase_message("Skipping %s from fight sequence — no longer in engagement range" % candidate_unit_id)
			units_that_fought.append(candidate_unit_id)  # Mark as fought so it's not re-offered
			current_fight_index += 1
		if current_fight_index < fight_sequence.size():
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
			# Only offer pile-in if the unit hasn't already piled in
			if not units_that_piled_in.get(active_fighter_id, false):
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
	# The END_FIGHT button should ALWAYS be available to the active player
	# This allows them to end the fight phase even if there are eligible units
	var can_end_fight = false

	# Can always end if no units are in combat
	if fight_sequence.is_empty():
		can_end_fight = true
		log_phase_message("Adding END_FIGHT action - no units in combat")
	# Can end if all eligible units have fought
	elif _all_eligible_units_have_fought():
		can_end_fight = true
		log_phase_message("Adding END_FIGHT action - all eligible units have fought")
	# Also allow ending if using legacy system and all units processed
	elif current_fight_index >= fight_sequence.size():
		can_end_fight = true
		log_phase_message("Adding END_FIGHT action - all units processed (legacy)")

	if can_end_fight:
		actions.append({
			"type": "END_FIGHT",
			"description": "End Fight Phase"
		})
	
	log_phase_message("Returning %d available actions: %s" % [actions.size(), str(actions)])
	log_phase_message("=== END get_available_actions DEBUG ===")
	return actions

func _should_complete_phase() -> bool:
	# Phase only completes when explicitly requested via END_FIGHT action
	# Don't auto-complete based on fight sequence anymore
	return false

func _all_eligible_units_have_fought() -> bool:
	"""Check if all eligible units in all subphases have fought"""
	# Check Fights First subphase
	for player_key in ["1", "2"]:
		for unit_id in fights_first_sequence.get(player_key, []):
			if unit_id not in units_that_fought:
				return false

	# Check Normal/Remaining Combats subphase
	for player_key in ["1", "2"]:
		for unit_id in normal_sequence.get(player_key, []):
			if unit_id not in units_that_fought:
				return false

	# Check Fights Last subphase (if implemented)
	for player_key in ["1", "2"]:
		for unit_id in fights_last_sequence.get(player_key, []):
			if unit_id not in units_that_fought:
				return false

	return true

# T4-4: Helper to check if a unit has a specific keyword
func _unit_has_keyword(unit: Dictionary, keyword: String) -> bool:
	var keywords = unit.get("meta", {}).get("keywords", [])
	return keyword in keywords

# Legacy method compatibility (for existing helper methods)
func _is_unit_in_combat(unit: Dictionary) -> bool:
	# Check if unit is within engagement range of any enemy
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)
	var unit_name = unit.get("meta", {}).get("name", unit.get("id", "unknown"))
	var unit_is_aircraft = _unit_has_keyword(unit, "AIRCRAFT")

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		var other_owner = other_unit.get("owner", 0)
		var other_name = other_unit.get("meta", {}).get("name", other_unit_id)

		if other_owner != unit_owner:
			# T4-4: Aircraft restrictions in fight phase
			# Aircraft can only fight against units that can Fly
			# Non-FLY units ignore Aircraft for combat eligibility
			var other_is_aircraft = _unit_has_keyword(other_unit, "AIRCRAFT")
			if unit_is_aircraft and not _unit_has_keyword(other_unit, "FLY"):
				log_phase_message("[T4-4] Skipping %s: AIRCRAFT unit %s can only fight FLY units" % [other_name, unit_name])
				continue
			if other_is_aircraft and not _unit_has_keyword(unit, "FLY"):
				log_phase_message("[T4-4] Skipping AIRCRAFT %s: unit %s does not have FLY" % [other_name, unit_name])
				continue

			log_phase_message("Checking engagement between %s (player %d) and %s (player %d)" % [unit_name, unit_owner, other_name, other_owner])
			if _units_in_engagement_range(unit, other_unit):
				log_phase_message("Units %s and %s are in engagement range!" % [unit_name, other_name])
				return true

	return false

## T3-9: Get the effective engagement range between two model positions,
## accounting for barricade terrain (2" instead of 1" if barricade is between them).
func _get_effective_engagement_range(pos1: Vector2, pos2: Vector2) -> float:
	if not is_inside_tree():
		return 1.0
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.has_method("get_engagement_range_for_positions"):
		return terrain_manager.get_engagement_range_for_positions(pos1, pos2)
	return 1.0

func _units_in_engagement_range(unit1: Dictionary, unit2: Dictionary) -> bool:
	# Check if any model from unit1 is within 1" of any model from unit2
	# Uses shape-aware distance to correctly handle non-circular bases (oval, rectangular)
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
		var pos1 = Vector2(pos1_data.get("x", 0), pos1_data.get("y", 0)) if pos1_data is Dictionary else pos1_data

		if pos1 == Vector2.ZERO:
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue

			var pos2_data = model2.get("position", {})
			if pos2_data == null:
				continue
			var pos2 = Vector2(pos2_data.get("x", 0), pos2_data.get("y", 0)) if pos2_data is Dictionary else pos2_data

			if pos2 == Vector2.ZERO:
				continue

			# T3-9: Use barricade-aware engagement range (2" through barricades)
			var effective_er = _get_effective_engagement_range(pos1, pos2)
			if Measurement.is_in_engagement_range_shape_aware(model1, model2, effective_er):
				var distance_inches = Measurement.model_to_model_distance_inches(model1, model2)
				log_phase_message("Units %s and %s are within engagement range! (%.2f\")" % [unit1_name, unit2_name, distance_inches])
				return true
	return false

func _find_enemies_in_engagement_range(unit: Dictionary) -> Array:
	var enemies = []
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)
	var unit_is_aircraft = _unit_has_keyword(unit, "AIRCRAFT")
	var unit_has_fly = _unit_has_keyword(unit, "FLY")

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		var other_owner = other_unit.get("owner", 0)

		if other_owner != unit_owner:
			# T4-4: Aircraft restrictions
			if unit_is_aircraft and not _unit_has_keyword(other_unit, "FLY"):
				continue
			if _unit_has_keyword(other_unit, "AIRCRAFT") and not unit_has_fly:
				continue
			if _units_in_engagement_range(unit, other_unit):
				enemies.append(other_unit_id)

	return enemies

func _scan_newly_eligible_units_after_consolidation(consolidating_unit_id: String, movements: Dictionary) -> Array:
	"""T2-6: After consolidation, check if any previously ineligible units are now
	eligible to fight (newly in engagement range). Per 10e rules, these units can
	then be selected to fight in the current phase.

	Since game_state_snapshot hasn't been updated with the consolidation positions yet
	(diffs are applied after process_action returns), we build a temporary view of
	positions with the consolidation moves applied."""

	var newly_eligible = []
	var all_units = game_state_snapshot.get("units", {})

	# Build a set of all unit IDs already in any fight sequence
	var already_in_sequence = {}
	for player_key in ["1", "2"]:
		for uid in fights_first_sequence.get(player_key, []):
			already_in_sequence[uid] = true
		for uid in normal_sequence.get(player_key, []):
			already_in_sequence[uid] = true
		for uid in fights_last_sequence.get(player_key, []):
			already_in_sequence[uid] = true

	# Build a temporary copy of the consolidating unit with updated positions
	var consolidating_unit = all_units.get(consolidating_unit_id, {})
	if consolidating_unit.is_empty():
		return newly_eligible

	var temp_consolidating_unit = consolidating_unit.duplicate(true)
	var temp_models = temp_consolidating_unit.get("models", [])
	for model_id in movements:
		var idx = int(model_id)
		if idx < temp_models.size():
			var new_pos = movements[model_id]
			temp_models[idx]["position"] = {"x": new_pos.x, "y": new_pos.y}

	var consolidating_owner = consolidating_unit.get("owner", 0)

	# Check every unit NOT already in a fight sequence
	for check_unit_id in all_units:
		if check_unit_id in already_in_sequence:
			continue
		if check_unit_id in units_that_fought:
			continue

		var check_unit = all_units[check_unit_id]
		var check_owner = check_unit.get("owner", 0)

		# Check if any models are alive
		var has_alive = false
		for model in check_unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# T4-4: Apply Aircraft restrictions when checking newly eligible units
		var check_is_aircraft = _unit_has_keyword(check_unit, "AIRCRAFT")
		var check_has_fly = _unit_has_keyword(check_unit, "FLY")

		# Check if this unit is now in engagement range with any enemy
		# We need to consider the consolidated unit's new positions
		var is_now_eligible = false

		# If the check_unit is an enemy of the consolidating unit,
		# check against the updated positions
		if check_owner != consolidating_owner:
			# T4-4: Aircraft can only fight FLY units; non-FLY units ignore Aircraft
			var consol_is_aircraft = _unit_has_keyword(consolidating_unit, "AIRCRAFT")
			var consol_has_fly = _unit_has_keyword(consolidating_unit, "FLY")
			var skip_pair = false
			if check_is_aircraft and not consol_has_fly:
				skip_pair = true
			if consol_is_aircraft and not check_has_fly:
				skip_pair = true
			if not skip_pair and _units_in_engagement_range_with_override(check_unit, temp_consolidating_unit):
				is_now_eligible = true

		# Also check against all other units (not affected by consolidation) at their current positions
		if not is_now_eligible:
			for other_unit_id in all_units:
				if other_unit_id == check_unit_id:
					continue
				var other_unit = all_units[other_unit_id]
				if other_unit.get("owner", 0) == check_owner:
					continue  # Same team

				# For the consolidating unit, use updated positions
				if other_unit_id == consolidating_unit_id:
					continue  # Already checked above with override

				# T4-4: Aircraft restrictions
				var other_is_aircraft = _unit_has_keyword(other_unit, "AIRCRAFT")
				if check_is_aircraft and not _unit_has_keyword(other_unit, "FLY"):
					continue
				if other_is_aircraft and not check_has_fly:
					continue

				if _units_in_engagement_range(check_unit, other_unit):
					is_now_eligible = true
					break

		if is_now_eligible:
			# This unit was NOT previously in any fight sequence but IS now in engagement range
			var check_name = check_unit.get("meta", {}).get("name", check_unit_id)
			var owner_key = str(int(check_owner))

			# Add to normal_sequence (Remaining Combats) since they became eligible mid-phase
			if owner_key in normal_sequence:
				normal_sequence[owner_key].append(check_unit_id)
				newly_eligible.append(check_unit_id)
				log_phase_message("[T2-6] NEW FIGHT ELIGIBLE: %s (player %s) is now in engagement range after consolidation by %s — added to Remaining Combats" % [
					check_name, owner_key, consolidating_unit_id
				])

			# Also update legacy fight_sequence for compatibility
			fight_sequence.append(check_unit_id)

	if newly_eligible.size() > 0:
		log_phase_message("[T2-6] %d unit(s) became newly eligible to fight after consolidation" % newly_eligible.size())
		emit_signal("fight_sequence_updated", fight_sequence)
	else:
		log_phase_message("[T2-6] No new units became eligible to fight after consolidation")

	return newly_eligible

func _units_in_engagement_range_with_override(unit1: Dictionary, unit2_override: Dictionary) -> bool:
	"""Check engagement range using a unit with overridden model positions.
	Used for checking engagement after consolidation before game state is updated."""
	var models1 = unit1.get("models", [])
	var models2 = unit2_override.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue
		var pos1_data = model1.get("position", {})
		if pos1_data == null:
			continue
		var pos1 = Vector2(pos1_data.get("x", 0), pos1_data.get("y", 0)) if pos1_data is Dictionary else pos1_data
		if pos1 == Vector2.ZERO:
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue
			var pos2_data = model2.get("position", {})
			if pos2_data == null:
				continue
			var pos2 = Vector2(pos2_data.get("x", 0), pos2_data.get("y", 0)) if pos2_data is Dictionary else pos2_data
			if pos2 == Vector2.ZERO:
				continue

			# T3-9: Use barricade-aware engagement range
			var effective_er = _get_effective_engagement_range(pos1, pos2)
			if Measurement.is_in_engagement_range_shape_aware(model1, model2, effective_er):
				return true
	return false

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

# Legacy method compatibility — Heroic Intervention is now fully implemented in ChargePhase.gd
# This validator is kept for the HEROIC_INTERVENTION action type routing in FightPhase
func _validate_heroic_intervention_action(action: Dictionary) -> Dictionary:
	# Heroic Intervention is now handled in ChargePhase.gd after enemy charge moves.
	# This action type should no longer be used from the Fight phase.
	return {"valid": false, "errors": ["Heroic Intervention is now handled during the Charge phase (use USE_HEROIC_INTERVENTION during Charge phase)"]}

func _validate_use_epic_challenge(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", current_selecting_player)

	if unit_id.is_empty():
		errors.append("No unit specified for Epic Challenge")
		return {"valid": false, "errors": errors}

	# Validate through StratagemManager
	var check = StratagemManager.is_epic_challenge_available(player, unit_id)
	if not check.available:
		errors.append(check.reason)

	return {"valid": errors.size() == 0, "errors": errors}

func _process_use_epic_challenge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", current_selecting_player)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)

	# Use the stratagem via StratagemManager
	var strat_result = StratagemManager.use_stratagem(player, "epic_challenge", unit_id)
	if not strat_result.success:
		return create_result(false, [], "Failed to use Epic Challenge: %s" % strat_result.get("reason", "unknown"))

	log_phase_message("Player %d uses EPIC CHALLENGE on %s — melee attacks gain [PRECISION]" % [player, unit_name])

	# Apply the flag to the game state snapshot so RulesEngine can see it
	if game_state_snapshot.has("units") and game_state_snapshot.units.has(unit_id):
		if not game_state_snapshot.units[unit_id].has("flags"):
			game_state_snapshot.units[unit_id]["flags"] = {}
		game_state_snapshot.units[unit_id].flags[EffectPrimitivesData.FLAG_PRECISION_MELEE] = true

	# Check for Martial Ka'tah before proceeding to pile-in
	var katah_result = _check_katah_or_proceed_to_pile_in(unit_id)
	# Merge diffs from stratagem result
	if not strat_result.get("diffs", []).is_empty():
		var merged_changes = strat_result.get("diffs", [])
		merged_changes.append_array(katah_result.get("changes", []))
		katah_result["changes"] = merged_changes
	return katah_result

func _process_decline_epic_challenge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", active_fighter_id)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)

	log_phase_message("Player declined EPIC CHALLENGE for %s" % unit_name)

	# Check for Martial Ka'tah before proceeding to pile-in
	return _check_katah_or_proceed_to_pile_in(unit_id)

# ============================================================================
# MARTIAL KA'TAH — Stance Selection
# ============================================================================

func _check_katah_or_proceed_to_pile_in(unit_id: String) -> Dictionary:
	"""Check if unit has Martial Ka'tah. If so, emit stance dialog signal.
	Otherwise, proceed directly to pile-in."""
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr and faction_mgr.unit_has_katah(unit_id):
		# Check if Master of the Stances is available for this unit
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		var master_available = ability_mgr and ability_mgr.has_master_of_the_stances(unit_id)
		if master_available:
			log_phase_message("MARTIAL KA'TAH: %s has Ka'tah + Master of the Stances available — stance selection required" % unit_id)
		else:
			log_phase_message("MARTIAL KA'TAH: %s has Ka'tah — stance selection required" % unit_id)
		emit_signal("katah_stance_required", unit_id, current_selecting_player)

		var result = create_result(true, [])
		result["trigger_katah_stance"] = true
		result["katah_unit_id"] = unit_id
		result["katah_player"] = current_selecting_player
		result["master_of_the_stances_available"] = master_available
		return result

	# No Ka'tah — check for Dread Foe, then proceed to pile-in
	return _resolve_dread_foe_then_pile_in(unit_id)

# ============================================================================
# P1-17: DREAD FOE — Mortal wounds on fight selection
# ============================================================================

func _resolve_dread_foe_then_pile_in(unit_id: String) -> Dictionary:
	"""P1-17: Check if unit has Dread Foe ability. If so, auto-resolve mortal wounds
	against one enemy within Engagement Range, then proceed to pile-in.
	Dread Foe: Roll 1D6 (+2 if charged this turn). On 4-5, D3 MW. On 6+, 3 MW."""
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr and ability_mgr.has_dread_foe(unit_id):
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		# Find enemy units within Engagement Range
		var targets = _get_dread_foe_targets(unit_id)
		if targets.is_empty():
			log_phase_message("DREAD FOE: %s has Dread Foe but no enemies in Engagement Range" % unit_name)
		else:
			# Auto-select first target (highest priority: most models, or first found)
			var target_id = targets[0].get("unit_id", "")
			var target_name = targets[0].get("unit_name", target_id)
			log_phase_message("DREAD FOE: %s targets %s within Engagement Range" % [unit_name, target_name])

			# Check if this unit charged this turn
			var flags = unit.get("flags", {})
			var charged_this_turn = flags.get("charged_this_turn", false)

			# Resolve Dread Foe via RulesEngine
			var rng_service = RulesEngine.RNGService.new()
			var dread_foe_result = RulesEngine.resolve_dread_foe(
				unit_id, target_id, charged_this_turn, GameState.state, rng_service
			)

			# Apply state changes if mortal wounds were dealt
			var dread_foe_diffs = dread_foe_result.get("diffs", [])
			if not dread_foe_diffs.is_empty():
				PhaseManager.apply_state_changes(dread_foe_diffs)
				# Also update our snapshot
				game_state_snapshot = GameState.state.duplicate(true)
				log_phase_message("DREAD FOE: Applied %d state change(s)" % dread_foe_diffs.size())

			# Emit signal for UI/logging
			emit_signal("dread_foe_resolved", unit_id, dread_foe_result)

			log_phase_message("DREAD FOE: %s rolled %d (modified %d) — %d mortal wound(s) to %s, %d casualt(y/ies)" % [
				unit_name,
				dread_foe_result.get("roll", 0),
				dread_foe_result.get("modified_roll", 0),
				dread_foe_result.get("mortal_wounds", 0),
				target_name,
				dread_foe_result.get("casualties", 0)
			])

			# Check if Dread Foe killed any units (could trigger Deadly Demise)
			if not dread_foe_diffs.is_empty():
				_check_kill_diffs(dread_foe_diffs)

	# Proceed to pile-in
	log_phase_message("Emitting pile_in_required for %s" % unit_id)
	emit_signal("pile_in_required", unit_id, 3.0)

	var result = create_result(true, [])
	result["trigger_pile_in"] = true
	result["pile_in_unit_id"] = unit_id
	result["pile_in_distance"] = 3.0
	return result

func _get_dread_foe_targets(unit_id: String) -> Array:
	"""P1-17: Get enemy units within Engagement Range of a unit for Dread Foe targeting.
	Returns array of { unit_id, unit_name } dictionaries."""
	var unit = get_unit(unit_id)
	var unit_owner = unit.get("owner", 0)
	var all_units = game_state_snapshot.get("units", {})
	var targets: Array = []

	for other_id in all_units:
		var other = all_units[other_id]
		# Only enemy units
		if other.get("owner", 0) == unit_owner:
			continue
		# Must have alive models
		var has_alive = false
		for m in other.get("models", []):
			if m.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue
		# Must be within Engagement Range
		if _units_in_engagement_range(unit, other):
			targets.append({
				"unit_id": other_id,
				"unit_name": other.get("meta", {}).get("name", other_id)
			})

	return targets

func _validate_select_katah_stance(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var stance = action.get("stance", "")

	if unit_id.is_empty():
		errors.append("Missing unit_id")
		return {"valid": false, "errors": errors}

	if unit_id != active_fighter_id:
		errors.append("Unit is not the active fighter")
		return {"valid": false, "errors": errors}

	if stance != "dacatarai" and stance != "rendax" and stance != "both":
		errors.append("Invalid stance: %s (must be 'dacatarai', 'rendax', or 'both')" % stance)
		return {"valid": false, "errors": errors}

	# "both" requires Master of the Stances (once per battle)
	if stance == "both":
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if not ability_mgr or not ability_mgr.has_master_of_the_stances(unit_id):
			errors.append("Master of the Stances not available for this unit")
			return {"valid": false, "errors": errors}

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr or not faction_mgr.unit_has_katah(unit_id):
		errors.append("Unit does not have Martial Ka'tah ability")
		return {"valid": false, "errors": errors}

	return {"valid": true}

func _process_select_katah_stance(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var stance = action.get("stance", "")
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)

	# If "both" stance selected, mark Master of the Stances as used
	if stance == "both":
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr:
			ability_mgr.mark_once_per_battle_used(unit_id, "Master of the Stances")
			log_phase_message("MASTER OF THE STANCES: %s activates both Ka'tah stances (once per battle)" % unit_name)

	# Apply the stance via FactionAbilityManager
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	var stance_result = faction_mgr.apply_katah_stance(unit_id, stance)

	if not stance_result.get("success", false):
		return create_result(false, [], "Failed to apply Ka'tah stance: %s" % stance_result.get("error", "unknown"))

	log_phase_message("MARTIAL KA'TAH: %s assumes %s stance" % [unit_name, stance_result.get("stance_display", stance)])

	# Also apply the flag to the game state snapshot so RulesEngine can see it during this fight
	if game_state_snapshot.has("units") and game_state_snapshot.units.has(unit_id):
		if not game_state_snapshot.units[unit_id].has("flags"):
			game_state_snapshot.units[unit_id]["flags"] = {}
		if stance == "both":
			game_state_snapshot.units[unit_id].flags["effect_sustained_hits"] = true
			game_state_snapshot.units[unit_id].flags["effect_lethal_hits"] = true
			game_state_snapshot.units[unit_id].flags["katah_stance"] = "both"
			game_state_snapshot.units[unit_id].flags["katah_sustained_hits_value"] = 1
		elif stance == "dacatarai":
			game_state_snapshot.units[unit_id].flags["effect_sustained_hits"] = true
			game_state_snapshot.units[unit_id].flags["katah_stance"] = "dacatarai"
			game_state_snapshot.units[unit_id].flags["katah_sustained_hits_value"] = 1
		elif stance == "rendax":
			game_state_snapshot.units[unit_id].flags["effect_lethal_hits"] = true
			game_state_snapshot.units[unit_id].flags["katah_stance"] = "rendax"

	# After Ka'tah — check for Dread Foe, then proceed to pile-in
	return _resolve_dread_foe_then_pile_in(unit_id)

func _validate_use_counter_offensive(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", counter_offensive_player)

	if not awaiting_counter_offensive:
		errors.append("Not awaiting Counter-Offensive decision")
		return {"valid": false, "errors": errors}

	if unit_id.is_empty():
		errors.append("No unit specified for Counter-Offensive")
		return {"valid": false, "errors": errors}

	# Validate through StratagemManager
	var check = StratagemManager.is_counter_offensive_available(player)
	if not check.available:
		errors.append(check.reason)
		return {"valid": false, "errors": errors}

	# Validate the unit is eligible
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: %s" % unit_id)
		return {"valid": false, "errors": errors}

	if int(unit.get("owner", 0)) != player:
		errors.append("Unit does not belong to player %d" % player)
		return {"valid": false, "errors": errors}

	if unit_id in units_that_fought:
		errors.append("Unit has already fought this phase")
		return {"valid": false, "errors": errors}

	if not _is_unit_in_combat(unit):
		errors.append("Unit is not in engagement range")
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _process_use_counter_offensive(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", counter_offensive_player)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)

	# Use the stratagem via StratagemManager
	var strat_result = StratagemManager.use_stratagem(player, "counter_offensive", unit_id)
	if not strat_result.success:
		return create_result(false, [], "Failed to use Counter-Offensive: %s" % strat_result.get("error", "unknown"))

	log_phase_message("Player %d uses COUNTER-OFFENSIVE — %s fights next!" % [player, unit_name])

	# Clear the awaiting state
	awaiting_counter_offensive = false
	counter_offensive_unit_id = unit_id

	# Set the selecting player to the Counter-Offensive user so their unit fights next
	current_selecting_player = player
	active_fighter_id = unit_id

	log_phase_message("Player %d selects %s to fight (via COUNTER-OFFENSIVE)" % [player, unit_name])

	emit_signal("unit_selected_for_fighting", active_fighter_id)
	emit_signal("fighter_selected", active_fighter_id)

	# Check for Epic Challenge opportunity before pile-in (same as normal selection)
	var epic_check = StratagemManager.is_epic_challenge_available(player, unit_id)
	if epic_check.available:
		log_phase_message("EPIC CHALLENGE available for %s (CHARACTER unit)" % unit_id)
		emit_signal("epic_challenge_opportunity", unit_id, player)

		var result = create_result(true, strat_result.get("diffs", []))
		result["trigger_epic_challenge"] = true
		result["epic_challenge_unit_id"] = unit_id
		result["epic_challenge_player"] = player
		return result

	# No Epic Challenge — proceed directly to pile-in
	log_phase_message("Emitting pile_in_required for %s" % unit_id)
	emit_signal("pile_in_required", unit_id, 3.0)

	var result = create_result(true, strat_result.get("diffs", []))
	result["trigger_pile_in"] = true
	result["pile_in_unit_id"] = unit_id
	result["pile_in_distance"] = 3.0
	return result

func _process_decline_counter_offensive(action: Dictionary) -> Dictionary:
	var player = action.get("player", counter_offensive_player)

	log_phase_message("Player %d declined COUNTER-OFFENSIVE" % player)

	# Clear the awaiting state
	awaiting_counter_offensive = false
	counter_offensive_player = 0

	# Resume normal fight selection flow: switch to next player and show dialog
	_switch_selecting_player()

	var dialog_data = _build_fight_selection_dialog_data()

	emit_signal("fight_selection_required", dialog_data)

	var result = create_result(true, [])
	result["trigger_fight_selection"] = true
	result["fight_selection_data"] = dialog_data
	return result

func _validate_end_fight(action: Dictionary) -> Dictionary:
	# END_FIGHT is always valid - it's the manual way to end the fight phase
	return {"valid": true, "errors": []}

func _process_end_fight(action: Dictionary) -> Dictionary:
	log_phase_message("Fight phase ended manually")
	emit_signal("phase_completed")
	return create_result(true, [])

func get_unfought_eligible_units() -> Array:
	"""Return array of {unit_id, unit_name, player, subphase} for units that haven't fought yet.
	Used by the end-fight-phase confirmation dialog (T5-UX7)."""
	var unfought = []
	var all_units = game_state_snapshot.get("units", {})

	for player_key in ["1", "2"]:
		for unit_id in fights_first_sequence.get(player_key, []):
			if unit_id not in units_that_fought:
				var unit_name = all_units.get(unit_id, {}).get("meta", {}).get("name", unit_id)
				unfought.append({"unit_id": unit_id, "unit_name": unit_name, "player": int(player_key), "subphase": "Fights First"})
		for unit_id in normal_sequence.get(player_key, []):
			if unit_id not in units_that_fought:
				var unit_name = all_units.get(unit_id, {}).get("meta", {}).get("name", unit_id)
				unfought.append({"unit_id": unit_id, "unit_name": unit_name, "player": int(player_key), "subphase": "Remaining Combats"})
		for unit_id in fights_last_sequence.get(player_key, []):
			if unit_id not in units_that_fought:
				var unit_name = all_units.get(unit_id, {}).get("meta", {}).get("name", unit_id)
				unfought.append({"unit_id": unit_id, "unit_name": unit_name, "player": int(player_key), "subphase": "Fights Last"})

	return unfought

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
		"fights_last": [],
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

	# Get Fights Last units that haven't fought
	if player_key in fights_last_sequence:
		for unit_id in fights_last_sequence[player_key]:
			if unit_id not in units_that_fought:
				result["fights_last"].append(unit_id)

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
			# Transition to Fights Last subphase
			log_phase_message("All Remaining Combats units have fought, moving to Fights Last subphase")
			current_subphase = Subphase.FIGHTS_LAST
			emit_signal("subphase_transition", "REMAINING_COMBATS", "FIGHTS_LAST")
			current_selecting_player = _get_defending_player()  # Reset to defender
			# Start with whoever has units
			var has_p1 = false
			var has_p2 = false
			for unit_id in fights_last_sequence.get("1", []):
				if unit_id not in units_that_fought:
					has_p1 = true
					break
			for unit_id in fights_last_sequence.get("2", []):
				if unit_id not in units_that_fought:
					has_p2 = true
					break
			if not has_p1 and not has_p2:
				log_phase_message("No Fights Last units to process")

	elif current_subphase == Subphase.FIGHTS_LAST:
		for unit_id in fights_last_sequence[current_player_key]:
			if unit_id not in units_that_fought:
				current_player_remaining += 1
		for unit_id in fights_last_sequence[other_player_key]:
			if unit_id not in units_that_fought:
				other_player_remaining += 1

		# Check if we should switch players
		if other_player_remaining > 0:
			# Alternate to other player
			current_selecting_player = other_player
			log_phase_message("Switching to player %d for Fights Last" % other_player)
		elif current_player_remaining > 0:
			# Stay with current player
			log_phase_message("Continuing with player %d for Fights Last" % current_selecting_player)
		else:
			# All units have fought
			log_phase_message("All units have fought (including Fights Last)")

	emit_signal("fight_sequence_updated")


# ============================================================================
# VERBOSE COMBAT LOG — Detailed melee dice breakdown for Game Event Log
# ============================================================================

func _emit_verbose_melee_combat_log(fighter_id: String, target_id: String, dice_data: Array,
		save_dice_blocks: Array, casualties: int) -> void:
	"""Emit detailed melee combat log entries to GameEventLog from dice_data and save results."""
	var fighter_unit = game_state_snapshot.get("units", {}).get(fighter_id, {})
	var fighter_name = fighter_unit.get("meta", {}).get("name", fighter_id)
	var target_unit = game_state_snapshot.get("units", {}).get(target_id, {})
	var target_name = target_unit.get("meta", {}).get("name", target_id)
	var player = get_current_player()

	# Header
	GameEventLog.add_combat_header("P%d: %s fights %s" % [player, fighter_name, target_name])

	# Extract hit and wound dice blocks
	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "resolution_start":
			continue
		if context == "to_hit" or context == "hit_roll":
			_emit_melee_hit_detail(dice_block)
		elif context == "auto_hit":
			GameEventLog.add_combat_detail("  To Hit: Auto-hit — %d hits" % dice_block.get("successes", dice_block.get("total_attacks", 0)))
		elif context == "to_wound" or context == "wound_roll":
			_emit_melee_wound_detail(dice_block)

	# Save rolls
	for save_block in save_dice_blocks:
		var scontext = save_block.get("context", "")
		if scontext == "save_roll" or scontext == "save":
			_emit_melee_save_detail(save_block)
		elif scontext == "feel_no_pain":
			_emit_melee_fnp_detail(save_block)

	# Result
	if casualties > 0:
		GameEventLog.add_combat_result("  Result: %d model(s) destroyed" % casualties)
	else:
		GameEventLog.add_combat_result("  Result: No models destroyed")

func _emit_melee_hit_detail(dice_block: Dictionary) -> void:
	"""Emit detailed melee hit roll log."""
	var threshold = dice_block.get("threshold", "?")
	var rolls_raw = dice_block.get("rolls_raw", [])
	var successes = dice_block.get("successes", 0)
	var total_attacks = rolls_raw.size()
	var weapon_name = dice_block.get("weapon_name", "")

	if weapon_name != "":
		var attacks_desc = "%d attacks" % total_attacks
		if dice_block.get("variable_attacks", false):
			attacks_desc = "%s → %d attacks" % [dice_block.get("attacks_notation", "?"), total_attacks]
		GameEventLog.add_combat_detail("  Weapon: %s — %s" % [weapon_name, attacks_desc])

	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	GameEventLog.add_combat_detail("  To Hit: needed %s — rolled %s — %d/%d hit" % [threshold, rolls_str, successes, total_attacks])

	# Rerolls
	var rerolls = dice_block.get("rerolls", [])
	if not rerolls.is_empty():
		var rr_strs = []
		for rr in rerolls:
			rr_strs.append("%d→%d" % [rr.get("original", 0), rr.get("rerolled_to", rr.get("new", 0))])
		GameEventLog.add_combat_detail("    Re-rolls: %s" % ", ".join(rr_strs))

	# Critical hits
	var crits = dice_block.get("critical_hits", 0)
	if crits > 0:
		var crit_parts = ["%d critical hit(s)" % crits]
		if dice_block.get("lethal_hits_weapon", false):
			crit_parts.append("Lethal Hits (crits auto-wound)")
		if dice_block.get("sustained_hits_weapon", false):
			crit_parts.append("Sustained Hits: +%d bonus" % dice_block.get("sustained_bonus_hits", 0))
		GameEventLog.add_combat_detail("    Criticals: %s" % " | ".join(crit_parts))

func _emit_melee_wound_detail(dice_block: Dictionary) -> void:
	"""Emit detailed melee wound roll log."""
	var threshold = dice_block.get("threshold", "?")
	var rolls_raw = dice_block.get("rolls_raw", [])
	var successes = dice_block.get("successes", 0)
	var total = rolls_raw.size()

	var auto_wounds = dice_block.get("lethal_hits_auto_wounds", 0)
	if auto_wounds > 0:
		GameEventLog.add_combat_detail("  Lethal Hits: %d auto-wound(s)" % auto_wounds)

	if total > 0:
		var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
		var wounds_from_rolls = dice_block.get("wounds_from_rolls", successes - auto_wounds)
		GameEventLog.add_combat_detail("  To Wound: needed %s — rolled %s — %d/%d wounded" % [threshold, rolls_str, wounds_from_rolls, total])

	var wound_mod_net = dice_block.get("wound_modifier_net", 0)
	if wound_mod_net != 0:
		GameEventLog.add_combat_detail("    Wound modifier: %+d" % wound_mod_net)

	var wound_rerolls = dice_block.get("wound_rerolls", [])
	if not wound_rerolls.is_empty():
		var wrr_strs = []
		for wrr in wound_rerolls:
			wrr_strs.append("%d→%d" % [wrr.get("original", 0), wrr.get("rerolled_to", wrr.get("new", 0))])
		GameEventLog.add_combat_detail("    Re-rolls: %s" % ", ".join(wrr_strs))

	if dice_block.get("anti_keyword_active", false):
		GameEventLog.add_combat_detail("    Anti-keyword: critical wounds on %d+" % dice_block.get("critical_wound_threshold", 6))

	var dw_count = dice_block.get("critical_wounds", 0)
	if dice_block.get("devastating_wounds_weapon", false) and dw_count > 0:
		GameEventLog.add_combat_detail("    DEVASTATING WOUNDS: %d bypass saves" % dw_count)

	GameEventLog.add_combat_detail("  Total wounds caused: %d" % successes)

func _emit_melee_save_detail(save_block: Dictionary) -> void:
	"""Emit detailed melee save roll log."""
	var target_name = save_block.get("target_unit_name", "Unknown")
	var threshold = save_block.get("threshold", "?")
	var rolls_raw = save_block.get("rolls_raw", [])
	var passed = save_block.get("successes", 0)
	var failed = save_block.get("failed", 0)
	var ap = save_block.get("ap", 0)
	var using_invuln = save_block.get("using_invuln", false)
	var weapon_name = save_block.get("weapon_name", "")

	var save_type = ""
	if using_invuln:
		save_type = "Invulnerable Save %s" % threshold
	else:
		save_type = "Armour Save %s (AP -%d)" % [threshold, ap]

	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	GameEventLog.add_combat_detail("  %s Saves vs %s: %s — rolled %s — %d passed, %d failed" % [
		target_name, weapon_name, save_type, rolls_str, passed, failed])

func _emit_melee_fnp_detail(fnp_block: Dictionary) -> void:
	"""Emit Feel No Pain roll details for melee."""
	var target_name = fnp_block.get("target_unit_name", "Unknown")
	var threshold = fnp_block.get("threshold", "?")
	var rolls_raw = fnp_block.get("rolls_raw", [])
	var prevented = fnp_block.get("wounds_prevented", 0)
	var total = fnp_block.get("total_wounds", 0)

	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	GameEventLog.add_combat_detail("  %s Feel No Pain %s: rolled %s — %d/%d prevented" % [
		target_name, threshold, rolls_str, prevented, total])

func _trigger_unit_animation(unit_id: String, anim_name: String) -> void:
	"""Trigger an animation on all token visuals for a unit."""
	var tl = get_node_or_null("/root/Main/BoardRoot/TokenLayer")
	if not tl:
		return
	for child in tl.get_children():
		if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id:
			if child.has_method("play_animation"):
				child.play_animation(anim_name)
			else:
				for grandchild in child.get_children():
					if grandchild.has_method("play_animation"):
						grandchild.play_animation(anim_name)
