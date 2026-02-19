extends BasePhase
class_name ShootingPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# ShootingPhase - Full implementation of the Shooting phase following 10e rules
# Supports: Target selection, weapon assignment, attack resolution, damage allocation

signal unit_selected_for_shooting(unit_id: String)
signal targets_available(unit_id: String, eligible_targets: Dictionary)
signal shooting_begun(unit_id: String)
signal shooting_resolved(unit_id: String, target_unit_id: String, result: Dictionary)
signal dice_rolled(dice_data: Dictionary)
signal saves_required(save_data_list: Array)  # For interactive save resolution
signal weapon_order_required(assignments: Array)  # For weapon ordering when 2+ weapon types
signal next_weapon_confirmation_required(remaining_weapons: Array, current_index: int, last_weapon_result: Dictionary)  # For sequential resolution pause
signal reactive_stratagem_opportunity(defending_player: int, available_stratagems: Array, target_unit_ids: Array)  # For opponent reactive stratagems
signal grenade_result(result: Dictionary)  # For grenade stratagem result display
signal command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)  # For Command Re-roll on save rolls (future expansion)

# Shooting state tracking
var active_shooter_id: String = ""
var pending_assignments: Array = []  # Weapon assignments before confirmation
var confirmed_assignments: Array = []  # Assignments ready to resolve
var resolution_state: Dictionary = {}  # State for step-by-step resolution
var dice_log: Array = []
var units_that_shot: Array = []  # Track which units have completed shooting
var pending_save_data: Array = []  # Save data awaiting resolution
var pending_hazardous_weapons: Array = []  # HAZARDOUS (T2-3): Weapons needing post-save hazardous check
var pending_one_shot_diffs: Array = []  # ONE SHOT (T4-2): Diffs to mark one-shot weapons as fired
var awaiting_reactive_stratagem: bool = false  # True when waiting for defender stratagem decision

func _init():
	phase_type = GameStateData.Phase.SHOOTING

func _on_phase_enter() -> void:
	log_phase_message("Entering Shooting Phase")
	active_shooter_id = ""
	pending_assignments.clear()
	confirmed_assignments.clear()
	resolution_state.clear()
	dice_log.clear()
	units_that_shot.clear()
	pending_hazardous_weapons.clear()
	pending_one_shot_diffs.clear()
	awaiting_reactive_stratagem = false

	# Apply unit ability effects (leader abilities, always-on abilities)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	_initialize_shooting()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")

	# CRITICAL: Clear all shooting visuals BEFORE controller is freed
	# This ensures range circles and other visuals are removed immediately
	_clear_shooting_visuals()

	# NEW: Clear death markers from board at phase end
	_clear_death_markers()

	# Clear shooting flags
	_clear_phase_flags()

	# Clear unit ability effect flags
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_end(GameStateData.Phase.SHOOTING)

	# Clear stratagem flags (Go to Ground, Smokescreen effects expire at end of phase)
	_clear_stratagem_phase_flags()

	# Clear pending save data
	pending_save_data.clear()

func execute_action(action: Dictionary) -> Dictionary:
	"""Override to detect unit kills from diffs (AI/batch shooting path)."""
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

func _initialize_shooting() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	var can_shoot = false
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit):
			can_shoot = true
			break

	if not can_shoot:
		log_phase_message("No units available for shooting, ready to end phase")
		# Don't auto-complete - wait for END_SHOOTING action

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"SELECT_SHOOTER":
			return _validate_select_shooter(action)
		"ASSIGN_TARGET":
			return _validate_assign_target(action)
		"CLEAR_ASSIGNMENT":
			return _validate_clear_assignment(action)
		"CLEAR_ALL_ASSIGNMENTS":
			return _validate_clear_all_assignments(action)
		"CONFIRM_TARGETS":
			return _validate_confirm_targets(action)
		"RESOLVE_SHOOTING":
			return _validate_resolve_shooting(action)
		"RESOLVE_WEAPON_SEQUENCE":  # Sequential weapon resolution
			return _validate_resolve_weapon_sequence(action)
		"SKIP_UNIT":
			return _validate_skip_unit(action)
		"END_SHOOTING":
			return _validate_end_shooting(action)
		"SHOOT":  # Full shooting action from UI
			return _validate_shoot(action)
		"APPLY_SAVES":  # Interactive save resolution
			return _validate_apply_saves(action)
		"CONTINUE_SEQUENCE":  # Continue to next weapon in sequential mode
			return _validate_continue_sequence(action)
		"COMPLETE_SHOOTING_FOR_UNIT":  # Complete shooting after final weapon
			return _validate_complete_shooting_for_unit(action)
		"USE_REACTIVE_STRATAGEM":  # Defender uses a reactive stratagem
			return _validate_use_reactive_stratagem(action)
		"DECLINE_REACTIVE_STRATAGEM":  # Defender declines to use a reactive stratagem
			return _validate_decline_reactive_stratagem(action)
		"USE_GRENADE_STRATAGEM":  # Active player uses GRENADE stratagem
			return _validate_use_grenade_stratagem(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	print("========================================")
	print("ShootingPhase: process_action CALLED")
	print("ShootingPhase: action = ", action)

	var action_type = action.get("type", "")
	print("ShootingPhase: action_type = ", action_type)

	match action_type:
		"SELECT_SHOOTER":
			print("ShootingPhase: Matched SELECT_SHOOTER")
			return _process_select_shooter(action)
		"ASSIGN_TARGET":
			print("ShootingPhase: Matched ASSIGN_TARGET")
			return _process_assign_target(action)
		"CLEAR_ASSIGNMENT":
			print("ShootingPhase: Matched CLEAR_ASSIGNMENT")
			return _process_clear_assignment(action)
		"CLEAR_ALL_ASSIGNMENTS":
			print("ShootingPhase: Matched CLEAR_ALL_ASSIGNMENTS")
			return _process_clear_all_assignments(action)
		"CONFIRM_TARGETS":
			print("ShootingPhase: Matched CONFIRM_TARGETS")
			return _process_confirm_targets(action)
		"RESOLVE_SHOOTING":
			print("ShootingPhase: Matched RESOLVE_SHOOTING")
			return _process_resolve_shooting(action)
		"RESOLVE_WEAPON_SEQUENCE":  # Sequential weapon resolution
			print("ShootingPhase: Matched RESOLVE_WEAPON_SEQUENCE")
			return _process_resolve_weapon_sequence(action)
		"SKIP_UNIT":
			print("ShootingPhase: Matched SKIP_UNIT")
			return _process_skip_unit(action)
		"END_SHOOTING":
			print("ShootingPhase: Matched END_SHOOTING")
			return _process_end_shooting(action)
		"SHOOT":  # Full shooting action
			print("ShootingPhase: Matched SHOOT")
			return _process_shoot(action)
		"APPLY_SAVES":  # Interactive save resolution
			print("ShootingPhase: Matched APPLY_SAVES")
			return _process_apply_saves(action)
		"CONTINUE_SEQUENCE":  # Continue to next weapon in sequential mode
			print("ShootingPhase: Matched CONTINUE_SEQUENCE")
			return _process_continue_sequence(action)
		"COMPLETE_SHOOTING_FOR_UNIT":  # Complete shooting after final weapon
			print("ShootingPhase: Matched COMPLETE_SHOOTING_FOR_UNIT")
			return _process_complete_shooting_for_unit(action)
		"USE_REACTIVE_STRATAGEM":  # Defender uses a reactive stratagem
			print("ShootingPhase: Matched USE_REACTIVE_STRATAGEM")
			return _process_use_reactive_stratagem(action)
		"DECLINE_REACTIVE_STRATAGEM":  # Defender declines reactive stratagem
			print("ShootingPhase: Matched DECLINE_REACTIVE_STRATAGEM")
			return _process_decline_reactive_stratagem(action)
		"USE_GRENADE_STRATAGEM":  # Active player uses GRENADE stratagem
			print("ShootingPhase: Matched USE_GRENADE_STRATAGEM")
			return _process_use_grenade_stratagem(action)
		_:
			print("ShootingPhase: NO MATCH - returning error")
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_select_shooter(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if not _can_unit_shoot(unit):
		return {"valid": false, "errors": ["Unit cannot shoot"]}
	
	if unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_assign_target(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	var target_unit_id = payload.get("target_unit_id", "")
	var model_ids = payload.get("model_ids", [])
	
	if active_shooter_id == "":
		return {"valid": false, "errors": ["No shooter selected"]}
	
	if weapon_id == "" or target_unit_id == "":
		return {"valid": false, "errors": ["Missing weapon_id or target_unit_id"]}
	
	# Check if weapon assignment would split attacks
	for assignment in pending_assignments:
		if assignment.weapon_id == weapon_id and assignment.target_unit_id != target_unit_id:
			return {"valid": false, "errors": ["Cannot split a weapon's attacks across multiple targets"]}

	# PISTOL MUTUAL EXCLUSIVITY (T2-5): Cannot mix Pistol and non-Pistol weapons
	# Per 10e: "If a model is equipped with one or more Pistols, unless it is a
	# MONSTER or VEHICLE model, it can either shoot with its Pistols or with all
	# of its other ranged weapons."
	var shooter_unit = get_unit(active_shooter_id)
	if not RulesEngine.is_monster_or_vehicle(shooter_unit):
		var new_weapon_is_pistol = RulesEngine.is_pistol_weapon(weapon_id, game_state_snapshot)
		for assignment in pending_assignments:
			var existing_weapon_id = assignment.get("weapon_id", "")
			if existing_weapon_id == "":
				continue
			var existing_is_pistol = RulesEngine.is_pistol_weapon(existing_weapon_id, game_state_snapshot)
			if new_weapon_is_pistol and not existing_is_pistol:
				return {"valid": false, "errors": ["Cannot fire Pistol weapons when non-Pistol weapons are already assigned — must choose one or the other"]}
			if not new_weapon_is_pistol and existing_is_pistol:
				return {"valid": false, "errors": ["Cannot fire non-Pistol weapons when Pistol weapons are already assigned — must choose one or the other"]}

	# Validate with RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": [{
				"weapon_id": weapon_id,
				"target_unit_id": target_unit_id,
				"model_ids": model_ids
			}]
		}
	}

	var validation = RulesEngine.validate_shoot(shoot_action, game_state_snapshot)
	return validation

func _validate_clear_assignment(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	
	if weapon_id == "":
		return {"valid": false, "errors": ["Missing weapon_id"]}
	
	return {"valid": true, "errors": []}

func _validate_clear_all_assignments(action: Dictionary) -> Dictionary:
	return {"valid": true, "errors": []}

func _validate_confirm_targets(action: Dictionary) -> Dictionary:
	if pending_assignments.is_empty():
		return {"valid": false, "errors": ["No targets assigned"]}
	
	return {"valid": true, "errors": []}

func _validate_resolve_shooting(action: Dictionary) -> Dictionary:
	if confirmed_assignments.is_empty():
		return {"valid": false, "errors": ["No confirmed targets to resolve"]}
	
	return {"valid": true, "errors": []}

func _validate_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	return {"valid": true, "errors": []}

func _validate_end_shooting(action: Dictionary) -> Dictionary:
	# Can always end the phase
	return {"valid": true, "errors": []}

func _validate_shoot(action: Dictionary) -> Dictionary:
	# Full shoot action validation
	var validation = RulesEngine.validate_shoot(action, game_state_snapshot)
	return validation

func _validate_resolve_weapon_sequence(action: Dictionary) -> Dictionary:
	"""Validate weapon sequence resolution"""
	var payload = action.get("payload", {})
	var weapon_order = payload.get("weapon_order", [])
	var fast_roll = payload.get("fast_roll", false)

	if weapon_order.is_empty():
		return {"valid": false, "errors": ["Missing weapon_order in payload"]}

	if active_shooter_id == "":
		return {"valid": false, "errors": ["No active shooter"]}

	return {"valid": true, "errors": []}

# Processing Methods

func _process_select_shooter(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	active_shooter_id = unit_id
	pending_assignments.clear()
	confirmed_assignments.clear()

	var unit = get_unit(unit_id)

	# Check if this is a transport with firing deck
	if unit.has("transport_data") and unit.transport_data.get("firing_deck", 0) > 0:
		var has_eligible_embarked = false
		for embarked_id in unit.transport_data.get("embarked_units", []):
			var embarked = get_unit(embarked_id)
			if embarked and not embarked.get("flags", {}).get("has_shot", false):
				has_eligible_embarked = true
				break

		if has_eligible_embarked:
			# Show firing deck dialog to select which embarked models will shoot
			call_deferred("_show_firing_deck_dialog", unit_id)
			log_phase_message("Selected transport %s - choosing firing deck models" % unit.get("meta", {}).get("name", unit_id))
			return create_result(true, [])

	# Normal shooting flow
	# Get eligible targets
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)

	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	log_phase_message("Selected %s for shooting" % unit.get("meta", {}).get("name", unit_id))

	return create_result(true, [])

func _process_assign_target(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	var target_unit_id = payload.get("target_unit_id", "")
	var model_ids = payload.get("model_ids", [])
	
	# Remove any existing assignment for this weapon
	pending_assignments = pending_assignments.filter(func(a): return a.weapon_id != weapon_id)
	
	# Add new assignment
	pending_assignments.append({
		"weapon_id": weapon_id,
		"target_unit_id": target_unit_id,
		"model_ids": model_ids
	})
	
	log_phase_message("Assigned %s to target %s" % [weapon_id, target_unit_id])
	
	return create_result(true, [])

func _process_clear_assignment(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	
	pending_assignments = pending_assignments.filter(func(a): return a.weapon_id != weapon_id)
	
	log_phase_message("Cleared assignment for %s" % weapon_id)
	
	return create_result(true, [])

func _process_clear_all_assignments(action: Dictionary) -> Dictionary:
	pending_assignments.clear()
	log_phase_message("Cleared all weapon assignments")
	
	return create_result(true, [])

func _process_confirm_targets(action: Dictionary) -> Dictionary:
	# CRITICAL FIX: Merge assignments with the same weapon_id to ensure all models
	# with the same weapon type are batched together
	var merged_assignments = {}
	for assignment in pending_assignments:
		var weapon_id = assignment.get("weapon_id", "")
		var target_unit_id = assignment.get("target_unit_id", "")

		# Create unique key: weapon_id + target_unit_id
		var key = weapon_id + "_" + target_unit_id

		if merged_assignments.has(key):
			# Merge model_ids with existing assignment
			var existing = merged_assignments[key]
			var existing_model_ids = existing.get("model_ids", [])
			var new_model_ids = assignment.get("model_ids", [])

			# Combine model IDs (avoid duplicates)
			for model_id in new_model_ids:
				if model_id not in existing_model_ids:
					existing_model_ids.append(model_id)

			existing["model_ids"] = existing_model_ids

			# Merge modifiers if present
			if assignment.has("modifiers"):
				existing["modifiers"] = assignment.get("modifiers", {})
		else:
			# First assignment for this weapon+target combo
			merged_assignments[key] = assignment.duplicate(true)

	# Convert merged assignments back to array
	confirmed_assignments = []
	for key in merged_assignments:
		confirmed_assignments.append(merged_assignments[key])

	pending_assignments.clear()

	# T3-3: Auto-inject Extra Attacks ranged weapons if not already assigned
	_auto_inject_extra_attacks_weapons_shooting()

	emit_signal("shooting_begun", active_shooter_id)
	log_phase_message("Confirmed targets, ready to resolve shooting")

	# REACTIVE STRATAGEMS: Check if defending player can use Go to Ground or Smokescreen
	var reactive_check = _check_reactive_stratagems()
	if reactive_check.has_opportunities:
		# Pause for defender to decide on reactive stratagems
		awaiting_reactive_stratagem = true
		resolution_state = {
			"phase": "awaiting_reactive_stratagem",
			"assignments": confirmed_assignments
		}
		log_phase_message("Opponent may use reactive stratagems...")
		emit_signal("reactive_stratagem_opportunity",
			reactive_check.defending_player,
			reactive_check.available_stratagems,
			reactive_check.target_unit_ids)
		return create_result(true, [], "Awaiting defender stratagem decision", {
			"reactive_stratagem_opportunity": true,
			"defending_player": reactive_check.defending_player,
			"available_stratagems": reactive_check.available_stratagems,
			"target_unit_ids": reactive_check.target_unit_ids
		})

	# No reactive stratagems available - proceed to resolution
	return _continue_after_reactive_stratagems()

func _continue_after_reactive_stratagems() -> Dictionary:
	"""Continue shooting resolution after reactive stratagem decision (or if none available)."""
	# Check if we have multiple weapon types - if so, show weapon order dialog
	var unique_weapons = {}
	for assignment in confirmed_assignments:
		var weapon_id = assignment.get("weapon_id", "")
		unique_weapons[weapon_id] = true

	var weapon_count = unique_weapons.size()
	print("ShootingPhase: Merged and confirmed %d assignments with %d unique weapon types" % [confirmed_assignments.size(), weapon_count])

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ WEAPON COUNT CHECK IN _process_confirm_targets")
	print("║ weapon_count: ", weapon_count)
	print("║ Will enter sequential mode: ", weapon_count >= 2)
	print("║ Single weapon path: ", weapon_count == 1)
	print("╚═══════════════════════════════════════════════════════════════")

	# If 2+ weapon types, emit signal for weapon ordering dialog
	if weapon_count >= 2:
		log_phase_message("Multiple weapon types detected - awaiting weapon order selection")
		emit_signal("weapon_order_required", confirmed_assignments)

		# Initialize resolution state for weapon ordering
		resolution_state = {
			"phase": "awaiting_weapon_order",
			"assignments": confirmed_assignments
		}

		# Return success but don't resolve yet - wait for weapon order
		# IMPORTANT: Include assignments in result for multiplayer sync
		return create_result(true, [], "Awaiting weapon order selection", {
			"weapon_order_required": true,
			"confirmed_assignments": confirmed_assignments
		})

	# Single weapon type - proceed with normal resolution
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SINGLE WEAPON PATH - _process_confirm_targets")
	print("║ Initializing resolution_state with mode: 'ready'")
	print("║ This is NOT sequential mode")
	print("║ Calling _process_resolve_shooting() directly")
	print("╚═══════════════════════════════════════════════════════════════")

	# Initialize resolution state
	resolution_state = {
		"current_assignment": 0,
		"phase": "ready",  # ready, hitting, wounding, saving, damage
		"mode": ""  # EXPLICITLY empty - not sequential
	}

	# AUTO-RESOLVE: Immediately trigger shooting resolution
	var initial_result = create_result(true, [])

	# Call resolution directly
	var resolve_result = _process_resolve_shooting({})

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SINGLE WEAPON - _process_resolve_shooting returned")
	print("║ resolve_result.success: ", resolve_result.success)
	print("║ resolve_result has save_data_list: ", resolve_result.has("save_data_list"))
	if resolve_result.has("save_data_list"):
		print("║ save_data_list size: ", resolve_result.get("save_data_list", []).size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Combine results
	if resolve_result.success:
		initial_result.changes.append_array(resolve_result.get("changes", []))
		initial_result["dice"] = resolve_result.get("dice", [])
		initial_result["log_text"] = resolve_result.get("log_text", "")
		# CRITICAL: Copy save_data_list for multiplayer sync
		if resolve_result.has("save_data_list"):
			initial_result["save_data_list"] = resolve_result.get("save_data_list", [])
		# CRITICAL FIX: Copy sequential_pause and related data for single weapon miss!
		if resolve_result.has("sequential_pause"):
			initial_result["sequential_pause"] = resolve_result.get("sequential_pause", false)
			initial_result["remaining_weapons"] = resolve_result.get("remaining_weapons", [])
			initial_result["last_weapon_result"] = resolve_result.get("last_weapon_result", {})
			initial_result["current_weapon_index"] = resolve_result.get("current_weapon_index", 0)
			initial_result["total_weapons"] = resolve_result.get("total_weapons", 1)

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SINGLE WEAPON - Returning from _process_confirm_targets")
	if initial_result.has("sequential_pause"):
		print("║ ✅ sequential_pause INCLUDED in result: ", initial_result.get("sequential_pause", false))
		print("║ ✅ remaining_weapons size: ", initial_result.get("remaining_weapons", []).size())
		print("║ ✅ last_weapon_result exists: ", initial_result.has("last_weapon_result"))
	elif resolve_result.has("save_data_list") and not resolve_result.get("save_data_list", []).is_empty():
		print("║ Result will trigger saves dialog")
		print("║ After saves, _process_apply_saves will be called")
	else:
		print("║ ⚠️  WARNING: No sequential_pause or save_data_list in result!")
		print("║ This weapon likely missed and dialog won't show!")
	print("╚═══════════════════════════════════════════════════════════════")

	return initial_result

func _process_resolve_shooting(action: Dictionary) -> Dictionary:
	# Emit signal to indicate resolution is starting
	emit_signal("dice_rolled", {"context": "resolution_start", "message": "Beginning attack resolution..."})

	# Build full shoot action for RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": confirmed_assignments
		}
	}

	# Resolve with RulesEngine UP TO WOUNDS (interactive saves)
	var rng_service = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

	if not result.success:
		return create_result(false, [], result.get("log_text", "Shooting failed"))

	# ONE SHOT (T4-2): Collect one-shot diffs from result (weapon marked as fired immediately)
	var one_shot_diffs = result.get("one_shot_diffs", [])

	# Record hit/wound dice rolls
	var dice_data = result.get("dice", [])
	for dice_block in dice_data:
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Attack rolls complete"))

	# Extract hit/wound data from dice blocks and store in resolution_state
	# so _process_apply_saves can build accurate last_weapon_result (T4-15)
	var hit_data = {}
	var wound_data = {}
	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "hit_roll":
			hit_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"rerolls": dice_block.get("rerolls", []),
				"threshold": dice_block.get("threshold", "")
			}
		elif context == "wound_roll":
			wound_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"threshold": dice_block.get("threshold", "")
			}
	resolution_state.last_weapon_dice_data = dice_data
	resolution_state.last_weapon_hit_data = hit_data
	resolution_state.last_weapon_wound_data = wound_data

	# Check if any saves are needed
	var save_data_list = result.get("save_data_list", [])

	if save_data_list.is_empty():
		# No wounds caused
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ NO WOUNDS CAUSED - Weapon missed!")
		print("║ resolution_state.mode: '", resolution_state.get("mode", ""), "'")
		print("║ Is single weapon: ", resolution_state.get("mode", "") == "")
		print("║ active_shooter_id: ", active_shooter_id)
		print("╚═══════════════════════════════════════════════════════════════")

		# HAZARDOUS (T2-3): Still process Hazardous check even if weapon missed
		var haz_diffs_on_miss = []
		var hazardous_weapons_on_miss = result.get("hazardous_weapons", [])
		if not hazardous_weapons_on_miss.is_empty():
			print("║ HAZARDOUS: Processing %d hazardous weapon check(s) despite miss" % hazardous_weapons_on_miss.size())
			var haz_rng = RulesEngine.RNGService.new()
			for haz_weapon in hazardous_weapons_on_miss:
				var haz_result = RulesEngine.resolve_hazardous_check(
					active_shooter_id,
					haz_weapon.get("weapon_id", ""),
					haz_weapon.get("models_that_fired", 0),
					game_state_snapshot,
					haz_rng
				)
				if haz_result.hazardous_triggered:
					haz_diffs_on_miss.append_array(haz_result.diffs)
				for haz_dice in haz_result.dice:
					dice_log.append(haz_dice)
					dice_data.append(haz_dice)
				if haz_result.log_text:
					log_phase_message(haz_result.log_text)

		# Check if this is single weapon mode (not sequential)
		var mode = resolution_state.get("mode", "")
		if mode != "sequential" and active_shooter_id != "":
			# Single weapon that missed - show results dialog before completing
			print("╔═══════════════════════════════════════════════════════════════")
			print("║ 🎯 SINGLE WEAPON MISS - Showing results dialog")
			print("║ Building last_weapon_result for missed shot...")
			print("╚═══════════════════════════════════════════════════════════════")

			# Build last weapon result for missed shot
			var last_weapon_result = {}
			if not confirmed_assignments.is_empty():
				var assignment = confirmed_assignments[0]
				var weapon_id = assignment.get("weapon_id", "")
				var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
				var target_unit_id = assignment.get("target_unit_id", "")
				var target_unit = get_unit(target_unit_id)

				# T4-15: Retrieve hit/wound data from resolution_state (stored earlier in this function)
				var miss_hit_data = resolution_state.get("last_weapon_hit_data", {})
				var miss_wound_data = resolution_state.get("last_weapon_wound_data", {})
				var hits = miss_hit_data.get("successes", 0)
				var total_attacks = miss_hit_data.get("total", 0)

				last_weapon_result = {
					"weapon_id": weapon_id,
					"weapon_name": weapon_profile.get("name", weapon_id),
					"target_unit_id": target_unit_id,
					"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
					"hits": hits,
					"wounds": 0,  # No wounds caused
					"saves_failed": 0,
					"casualties": 0,
					"total_attacks": total_attacks,
					"dice_rolls": dice_data,
					"hit_data": miss_hit_data,
					"wound_data": miss_wound_data
				}

				print("║ last_weapon_result built:")
				print("║   weapon: ", last_weapon_result.get("weapon_name", ""))
				print("║   hits: ", hits, " / ", total_attacks)
				print("║   wounds: 0 (missed)")
				print("║   casualties: 0")

			# Emit signal with EMPTY remaining_weapons (signals completion)
			print("║")
			print("║ 📡 EMITTING next_weapon_confirmation_required SIGNAL (for miss)")
			print("╚═══════════════════════════════════════════════════════════════")

			emit_signal("next_weapon_confirmation_required", [], 0, last_weapon_result)

			# Return with pause indicator - completion will happen when user clicks "Complete Shooting"
			# IMPORTANT: Do NOT mark has_shot yet - that happens when user confirms
			# ONE SHOT (T4-2): Include one-shot diffs even on miss
			var miss_one_shot_changes = haz_diffs_on_miss.duplicate()
			miss_one_shot_changes.append_array(one_shot_diffs)
			return create_result(true, miss_one_shot_changes, "Single weapon missed - awaiting confirmation", {
				"sequential_pause": true,
				"remaining_weapons": [],
				"last_weapon_result": last_weapon_result,
				"current_weapon_index": 0,
				"total_weapons": 1,
				"dice": dice_data
			})

		# Sequential mode - already handled with dialog
		print("║ Sequential mode - completing immediately")
		var shooter_id = active_shooter_id  # Store before clearing
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]
		# HAZARDOUS (T2-3): Include hazardous diffs in changes
		changes.append_array(haz_diffs_on_miss)
		# ONE SHOT (T4-2): Include one-shot diffs in changes
		changes.append_array(one_shot_diffs)

		units_that_shot.append(active_shooter_id)
		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		# Emit signal to clear visuals
		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "No wounds caused", {"dice": dice_data})

	# Store save data and trigger interactive saves
	pending_save_data = save_data_list

	# HAZARDOUS (T2-3): Store hazardous weapon data for post-save resolution
	pending_hazardous_weapons = result.get("hazardous_weapons", [])

	# ONE SHOT (T4-2): Store one-shot diffs for inclusion in saves result
	pending_one_shot_diffs = one_shot_diffs

	# LOGGING: Track saves_required emission
	var timestamp = Time.get_ticks_msec()
	var save_context = {
		"timestamp": timestamp,
		"source": "ShootingPhase._process_resolve_shooting",
		"save_count": save_data_list.size(),
		"target": save_data_list[0].get("target_unit_id", "unknown") if save_data_list.size() > 0 else "none",
		"weapon": save_data_list[0].get("weapon_name", "unknown") if save_data_list.size() > 0 else "none",
		"wounds": save_data_list[0].get("wounds_to_save", 0) if save_data_list.size() > 0 else 0
	}
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SAVES_REQUIRED EMISSION #1 (from resolve_shooting)")
	print("║ Timestamp: ", timestamp)
	print("║ Source: ShootingPhase._process_resolve_shooting (line 444)")
	print("║ Target: ", save_context.target)
	print("║ Weapon: ", save_context.weapon)
	print("║ Wounds: ", save_context.wounds)
	print("║ Save data list size: ", save_data_list.size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Emit signal to show save dialog (handled by ShootingController or Main)
	emit_signal("saves_required", save_data_list)

	log_phase_message("Awaiting defender to make saves...")

	# Return success but NO changes yet - changes will come after saves resolved
	# Include save_data_list in result so it can be broadcast to clients
	return create_result(true, [], "Awaiting save resolution", {
		"dice": dice_data,
		"save_data_list": save_data_list  # IMPORTANT: For multiplayer sync
	})

func _process_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	units_that_shot.append(unit_id)
	
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]
	
	# Clear any active state
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()
	
	var unit = get_unit(unit_id)
	log_phase_message("Skipped shooting for %s" % unit.get("meta", {}).get("name", unit_id))
	
	return create_result(true, changes)

func _process_end_shooting(action: Dictionary) -> Dictionary:
	log_phase_message("Ending Shooting Phase")
	emit_signal("phase_completed")
	return create_result(true, [])

func _process_shoot(action: Dictionary) -> Dictionary:
	# Full atomic shoot action - used exclusively by AI
	# Handles the complete flow: select shooter, assign targets, resolve hits/wounds,
	# auto-roll saves, apply damage, mark unit done, and clear state.
	# Does NOT emit UI signals (weapon_order_required, next_weapon_confirmation_required,
	# saves_required) to avoid creating orphaned dialogs during AI play.
	var unit_id = action.get("actor_unit_id", "")

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ AI SHOOT (atomic): Starting for unit %s" % unit_id)
	print("╚═══════════════════════════════════════════════════════════════")

	# Step 1: Select shooter
	var select_result = _process_select_shooter({"actor_unit_id": unit_id})
	if not select_result.success:
		return select_result

	# Step 2: Merge assignments into confirmed_assignments (inline, no signals)
	var assignments = action.get("payload", {}).get("assignments", [])
	var merged_assignments = {}
	for assignment in assignments:
		var weapon_id = assignment.get("weapon_id", "")
		var target_unit_id = assignment.get("target_unit_id", "")
		var key = weapon_id + "_" + target_unit_id
		if merged_assignments.has(key):
			var existing = merged_assignments[key]
			var existing_model_ids = existing.get("model_ids", [])
			var new_model_ids = assignment.get("model_ids", [])
			for model_id in new_model_ids:
				if model_id not in existing_model_ids:
					existing_model_ids.append(model_id)
			existing["model_ids"] = existing_model_ids
		else:
			merged_assignments[key] = assignment.duplicate(true)

	confirmed_assignments = []
	for key in merged_assignments:
		confirmed_assignments.append(merged_assignments[key])
	pending_assignments.clear()

	log_phase_message("AI: Confirmed %d weapon assignments for %s" % [confirmed_assignments.size(), unit_id])

	# Step 3: Resolve shooting (hits + wounds) via RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": confirmed_assignments
		}
	}

	var rng_service = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

	if not result.success:
		# Resolution failed - clean up and return
		active_shooter_id = ""
		confirmed_assignments.clear()
		return create_result(false, [], result.get("log_text", "Shooting failed"))

	# Record dice rolls
	var all_dice = []
	var dice_data = result.get("dice", [])
	for dice_block in dice_data:
		dice_log.append(dice_block)
		all_dice.append(dice_block)

	log_phase_message(result.get("log_text", "Attack rolls complete"))

	# Step 4: Auto-roll saves if wounds were caused
	var save_data_list = result.get("save_data_list", [])
	var all_changes = []
	var total_casualties = 0

	if not save_data_list.is_empty():
		var save_result = _auto_roll_saves(save_data_list)
		all_changes.append_array(save_result.get("changes", []))
		total_casualties = save_result.get("casualties", 0)
		all_dice.append_array(save_result.get("dice_blocks", []))

		print("║ AI SHOOT: Saves resolved - %d casualties" % total_casualties)
	else:
		print("║ AI SHOOT: No wounds caused (all missed)")

	# HAZARDOUS (T2-3): Process Hazardous self-damage after saves resolve (AI path)
	var hazardous_weapons = result.get("hazardous_weapons", [])
	if not hazardous_weapons.is_empty():
		print("║ AI SHOOT: Processing %d hazardous weapon check(s)" % hazardous_weapons.size())
		var haz_rng = RulesEngine.RNGService.new()
		for haz_weapon in hazardous_weapons:
			var haz_result = RulesEngine.resolve_hazardous_check(
				active_shooter_id,
				haz_weapon.get("weapon_id", ""),
				haz_weapon.get("models_that_fired", 0),
				game_state_snapshot,
				haz_rng
			)
			if haz_result.hazardous_triggered:
				all_changes.append_array(haz_result.diffs)
			all_dice.append_array(haz_result.dice)
			if haz_result.log_text:
				log_phase_message(haz_result.log_text)

	# ONE SHOT (T4-2): Include one-shot diffs in AI path
	var ai_one_shot_diffs = result.get("one_shot_diffs", [])
	if not ai_one_shot_diffs.is_empty():
		all_changes.append_array(ai_one_shot_diffs)
		print("║ AI SHOOT: ONE SHOT — included %d one-shot diffs" % ai_one_shot_diffs.size())

	# Step 5: Build comprehensive attack summary for game event log
	var actor_name = game_state_snapshot.get("units", {}).get(unit_id, {}).get("meta", {}).get("name", unit_id)
	var target_names = []
	for a in confirmed_assignments:
		var tid = a.get("target_unit_id", "")
		var tn = game_state_snapshot.get("units", {}).get(tid, {}).get("meta", {}).get("name", tid)
		if tn not in target_names:
			target_names.append(tn)

	var total_hits = 0
	var total_wounds = 0
	var total_saves_passed = 0
	var total_saves_failed = 0
	for db in all_dice:
		var ctx = db.get("context", "")
		if ctx == "to_hit" or ctx == "hit_roll" or ctx == "auto_hit":
			total_hits += db.get("successes", 0)
		elif ctx == "to_wound":
			total_wounds += db.get("successes", 0)
		elif ctx == "save_roll":
			total_saves_passed += db.get("successes", 0)
			total_saves_failed += db.get("failed", 0)

	var target_text = ", ".join(target_names)
	var attack_summary = "%s → %s: %d hits, %d wounds" % [actor_name, target_text, total_hits, total_wounds]
	if total_saves_passed > 0 or total_saves_failed > 0:
		attack_summary += ", %d saved, %d failed" % [total_saves_passed, total_saves_failed]
	if total_casualties > 0:
		attack_summary += " → %d slain" % total_casualties

	# Step 6: Mark unit as done
	all_changes.append({
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	})
	units_that_shot.append(unit_id)

	# Step 7: Clear state
	var shooter_id = active_shooter_id
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()

	# Step 8: Emit shooting_resolved for visual cleanup (non-blocking)
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": total_casualties})

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ AI SHOOT (atomic): Complete for %s - %d casualties" % [unit_id, total_casualties])
	print("╚═══════════════════════════════════════════════════════════════")

	return create_result(true, all_changes, "", {
		"dice": all_dice,
		"casualties": total_casualties,
		"log_text": attack_summary
	})

func _auto_roll_saves(save_data_list: Array) -> Dictionary:
	# Auto-roll saves for AI - no UI interaction needed
	# Returns: {changes: [], casualties: int, dice_blocks: []}
	var all_changes = []
	var total_casualties = 0
	var all_dice_blocks = []

	for save_data in save_data_list:
		var wounds_to_save = save_data.get("wounds_to_save", 0)
		var model_save_profiles = save_data.get("model_save_profiles", [])

		if wounds_to_save <= 0 and save_data.get("devastating_wounds", 0) <= 0:
			continue

		# Roll saves: allocate wounds to models in priority order (wounded first)
		var rng = RulesEngine.RNGService.new()
		var save_results = []
		var saves_passed = 0
		var saves_failed = 0
		var save_rolls_raw = []

		# Build allocation order: wounded models first, then by model_index
		var allocation_order = []
		# PRECISION (T3-4): Separate character and non-character models
		var character_profiles = []
		var bodyguard_profiles = []
		for profile in model_save_profiles:
			if profile.get("is_character", false):
				character_profiles.append(profile)
			else:
				bodyguard_profiles.append(profile)
			allocation_order.append(profile)

		# Sort: wounded models first (is_wounded = true first)
		allocation_order.sort_custom(func(a, b):
			if a.get("is_wounded", false) and not b.get("is_wounded", false):
				return true
			if not a.get("is_wounded", false) and b.get("is_wounded", false):
				return false
			return a.get("model_index", 0) < b.get("model_index", 0)
		)

		# PRECISION (T3-4): Check if weapon has Precision and there are character models
		var has_precision = save_data.get("has_precision", false)
		var precision_wounds = save_data.get("precision_wounds", 0)
		var precision_wounds_remaining = precision_wounds if has_precision else 0
		var bodyguard_alive = not bodyguard_profiles.is_empty()

		if has_precision and precision_wounds > 0 and not character_profiles.is_empty():
			print("ShootingPhase: PRECISION — %d wounds can target CHARACTER models" % precision_wounds)

		# Roll all saves at once, then allocate to models in priority order
		var all_rolls = rng.roll_d6(wounds_to_save)
		var alloc_idx = 0
		# PRECISION (T3-4): Track character allocation index separately
		var char_alloc_idx = 0
		for w in range(wounds_to_save):
			# PRECISION (T3-4): Allocate precision wounds to CHARACTER models first
			var use_character_target = false
			if precision_wounds_remaining > 0 and not character_profiles.is_empty():
				use_character_target = true
				precision_wounds_remaining -= 1

			var profile: Dictionary
			if use_character_target:
				if char_alloc_idx >= character_profiles.size():
					char_alloc_idx = 0  # Wrap around
				profile = character_profiles[char_alloc_idx]
				char_alloc_idx += 1
			else:
				# Normal allocation: bodyguard models (or all models if no bodyguard)
				var normal_order = bodyguard_profiles if bodyguard_alive else allocation_order
				if normal_order.is_empty():
					break
				if alloc_idx >= normal_order.size():
					alloc_idx = 0  # Wrap around
				profile = normal_order[alloc_idx]
				alloc_idx += 1

			var save_needed = profile.get("save_needed", 7)
			var roll = all_rolls[w]
			save_rolls_raw.append(roll)
			var saved = roll >= save_needed

			save_results.append({
				"saved": saved,
				"model_id": profile.get("model_id", ""),
				"model_index": profile.get("model_index", 0),
				"roll": roll,
				"damage": save_data.get("damage", 1),
				"model_destroyed": false,  # Will be determined by apply_save_damage
				"precision_wound": use_character_target  # PRECISION (T3-4): Track precision wounds
			})

			if saved:
				saves_passed += 1
			else:
				saves_failed += 1

		# Build dice block for save rolls
		if not save_rolls_raw.is_empty():
			var save_threshold = 7
			var using_invuln = false
			if not allocation_order.is_empty():
				save_threshold = allocation_order[0].get("save_needed", 7)
				using_invuln = allocation_order[0].get("using_invuln", false)

			var save_dice_block = {
				"context": "save_roll",
				"threshold": str(save_threshold) + "+",
				"rolls_raw": save_rolls_raw,
				"successes": saves_passed,
				"failed": saves_failed,
				"ap": save_data.get("ap", 0),
				"original_save": save_data.get("base_save", 7),
				"using_invuln": using_invuln,
				"weapon_name": save_data.get("weapon_name", ""),
				"target_unit_name": save_data.get("target_unit_name", "")
			}
			all_dice_blocks.append(save_dice_block)
			dice_log.append(save_dice_block)
			emit_signal("dice_rolled", save_dice_block)

		# Apply damage using RulesEngine
		var fnp_rng = RulesEngine.RNGService.new()
		var damage_result = RulesEngine.apply_save_damage(
			save_results,
			save_data,
			game_state_snapshot,
			-1,
			fnp_rng
		)

		all_changes.append_array(damage_result.diffs)
		total_casualties += damage_result.casualties

		# Check if bodyguard unit was destroyed
		if damage_result.casualties > 0:
			var target_unit_id = save_data.get("target_unit_id", "")
			if target_unit_id != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id)

		# Log FNP dice blocks
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
				"target_unit_name": save_data.get("target_unit_name", "")
			}
			dice_log.append(fnp_dice_block)
			emit_signal("dice_rolled", fnp_dice_block)
			all_dice_blocks.append(fnp_dice_block)

		var target_name = save_data.get("target_unit_name", "Unknown")
		log_phase_message("AI saves: %s - %d passed, %d failed → %d casualties" % [
			target_name, saves_passed, saves_failed, damage_result.casualties
		])

	return {"changes": all_changes, "casualties": total_casualties, "dice_blocks": all_dice_blocks}

func _process_resolve_weapon_sequence(action: Dictionary) -> Dictionary:
	"""Process weapon sequence resolution - either fast roll or sequential"""
	print("========================================")
	print("ShootingPhase: _process_resolve_weapon_sequence CALLED")
	print("ShootingPhase: action = ", action)

	var payload = action.get("payload", {})
	print("ShootingPhase: payload = ", payload)

	var weapon_order = payload.get("weapon_order", [])
	print("ShootingPhase: weapon_order size = ", weapon_order.size())

	var fast_roll = payload.get("fast_roll", false)
	print("ShootingPhase: fast_roll = ", fast_roll)

	var is_reorder = payload.get("is_reorder", false)
	print("ShootingPhase: is_reorder = ", is_reorder)

	print("ShootingPhase: active_shooter_id = ", active_shooter_id)
	print("ShootingPhase: confirmed_assignments before = ", confirmed_assignments)

	# If this is a reorder during sequential resolution, update the weapon_order
	if is_reorder and resolution_state.get("mode", "") == "sequential":
		print("ShootingPhase: Updating weapon order for remaining weapons")
		var current_index = resolution_state.get("current_index", 0)
		var existing_order = resolution_state.get("weapon_order", [])

		# Replace remaining weapons with the new order
		var new_full_order = []
		# Keep completed weapons
		for i in range(current_index):
			new_full_order.append(existing_order[i])
		# Add reordered remaining weapons
		new_full_order.append_array(weapon_order)

		resolution_state["weapon_order"] = new_full_order
		resolution_state["phase"] = "ready"
		print("ShootingPhase: Updated weapon_order, continuing to next weapon")

		# Continue with next weapon
		var next_result = _resolve_next_weapon()
		print("ShootingPhase: _resolve_next_weapon returned = ", next_result)
		print("========================================")
		return next_result

	# Update confirmed assignments with the ordered weapons
	confirmed_assignments = weapon_order.duplicate(true)
	print("ShootingPhase: confirmed_assignments after = ", confirmed_assignments)

	if fast_roll:
		# Fast roll all weapons at once (existing behavior)
		log_phase_message("Fast rolling all weapons")
		resolution_state = {
			"mode": "fast",
			"current_assignment": 0,
			"phase": "ready"
		}

		# Call normal resolution
		print("ShootingPhase: Calling _process_resolve_shooting for fast roll...")
		var resolve_result = _process_resolve_shooting({})
		print("ShootingPhase: Fast roll result = ", resolve_result)
		print("========================================")
		return resolve_result
	else:
		# Sequential resolution - resolve one weapon at a time
		log_phase_message("Starting sequential weapon resolution")
		print("ShootingPhase: Starting sequential resolution...")
		resolution_state = {
			"mode": "sequential",
			"weapon_order": weapon_order,
			"current_index": 0,
			"completed_weapons": [],
			"awaiting_saves": false
		}
		print("ShootingPhase: resolution_state = ", resolution_state)

		# Start resolving first weapon
		print("ShootingPhase: Calling _resolve_next_weapon()...")
		var next_result = _resolve_next_weapon()
		print("ShootingPhase: _resolve_next_weapon returned = ", next_result)
		print("========================================")
		return next_result

func _resolve_next_weapon() -> Dictionary:
	"""Resolve the next weapon in the sequence"""
	print("========================================")
	print("ShootingPhase: _resolve_next_weapon CALLED")
	print("ShootingPhase: resolution_state = ", resolution_state)

	var current_index = resolution_state.get("current_index", 0)
	var weapon_order = resolution_state.get("weapon_order", [])

	print("ShootingPhase: current_index = ", current_index)
	print("ShootingPhase: weapon_order.size() = ", weapon_order.size())
	print("ShootingPhase: active_shooter_id = ", active_shooter_id)

	if current_index >= weapon_order.size():
		# All weapons complete
		print("ShootingPhase: All weapons complete!")
		log_phase_message("All weapons resolved sequentially")

		# Mark shooter as done
		var shooter_id = active_shooter_id  # Store before clearing
		units_that_shot.append(active_shooter_id)
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]

		# Clear state
		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		# Emit signal to clear visuals
		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "Sequential weapon resolution complete")

	# Get current weapon assignment
	var current_assignment = weapon_order[current_index]
	var weapon_id = current_assignment.get("weapon_id", "")

	print("ShootingPhase: Resolving weapon %d of %d: %s" % [current_index + 1, weapon_order.size(), weapon_id])

	# Emit progress signal
	emit_signal("dice_rolled", {
		"context": "weapon_progress",
		"message": "Resolving weapon %d of %d" % [current_index + 1, weapon_order.size()],
		"current_index": current_index,
		"total_weapons": weapon_order.size()
	})

	# Build shoot action for this single weapon
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": [current_assignment]  # Only this weapon
		}
	}

	# Resolve with RulesEngine UP TO WOUNDS
	var rng_service = RulesEngine.RNGService.new()
	print("ShootingPhase: Calling RulesEngine.resolve_shoot_until_wounds()...")
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)
	print("ShootingPhase: RulesEngine returned: success=%s" % result.success)

	if not result.success:
		print("ShootingPhase: ❌ Weapon resolution FAILED: ", result.get("log_text", ""))
		print("========================================")
		return create_result(false, [], result.get("log_text", "Weapon resolution failed"))

	# ONE SHOT (T4-2): Collect one-shot diffs from result (weapon marked as fired immediately)
	var seq_one_shot_diffs = result.get("one_shot_diffs", [])
	# Store for inclusion in subsequent results
	pending_one_shot_diffs.append_array(seq_one_shot_diffs)

	# Record dice rolls
	var dice_data = result.get("dice", [])
	print("ShootingPhase: Dice blocks returned: %d" % dice_data.size())
	for dice_block in dice_data:
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Weapon attacks complete"))
	print("ShootingPhase: Log text: ", result.get("log_text", ""))

	# Extract dice data for storage
	var hit_data = {}
	var wound_data = {}

	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "hit_roll":
			hit_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"rerolls": dice_block.get("rerolls", []),
				"threshold": dice_block.get("threshold", "")
			}
		elif context == "wound_roll":
			wound_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"threshold": dice_block.get("threshold", "")
			}

	# Get target unit name for display
	var target_unit = get_unit(current_assignment.target_unit_id)
	var target_unit_name = target_unit.get("meta", {}).get("name", current_assignment.target_unit_id)

	# Store dice data in resolution_state for later retrieval (when saves complete)
	resolution_state.last_weapon_dice_data = dice_data
	resolution_state.last_weapon_hit_data = hit_data
	resolution_state.last_weapon_wound_data = wound_data
	resolution_state.last_weapon_target_name = target_unit_name
	resolution_state.last_weapon_target_id = current_assignment.target_unit_id

	# Check if saves are needed
	var save_data_list = result.get("save_data_list", [])
	print("ShootingPhase: save_data_list.size() = %d" % save_data_list.size())

	if save_data_list.is_empty():
		# No wounds - but still PAUSE for attacker to confirm next weapon (sequential mode)
		print("ShootingPhase: ⚠ No wounds caused by this weapon")
		resolution_state.completed_weapons.append({
			"weapon_id": weapon_id,
			"target_unit_id": current_assignment.target_unit_id,
			"target_unit_name": target_unit_name,
			"wounds": 0,
			"casualties": 0,
			"hits": hit_data.get("successes", 0),
			"total_attacks": hit_data.get("total", 0),
			"saves_failed": 0,
			"dice_rolls": dice_data,
			"hit_data": hit_data,
			"wound_data": wound_data
		})
		resolution_state.current_index += 1
		print("ShootingPhase: Incremented current_index to %d" % resolution_state.current_index)
		print("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index))

		# ALWAYS PAUSE for attacker to confirm (even if last weapon)
		# Wait for attacker to confirm before continuing or completing
		print("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon (no hits)")
		print("ShootingPhase: Weapons remaining: ", weapon_order.size() - resolution_state.current_index)

		# Build remaining weapons with validation (may be empty array if this is the last weapon)
		var remaining_weapons = []

		print("╔═══════════════════════════════════════════════════════════════")
		print("║ BUILDING REMAINING WEAPONS (after miss)")
		print("║ weapon_order.size() = %d" % weapon_order.size())
		print("║ current_index = %d" % resolution_state.current_index)
		print("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index))

		for i in range(resolution_state.current_index, weapon_order.size()):
			var weapon = weapon_order[i]
			remaining_weapons.append(weapon)

			# Validate weapon structure
			var remaining_weapon_id = weapon.get("weapon_id", "")
			if remaining_weapon_id == "":
				push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
				print("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i)
				print("║   Full weapon object: %s" % str(weapon))
			else:
				print("║ Added weapon %d: %s" % [i, remaining_weapon_id])

		print("║ Total remaining weapons: %d" % remaining_weapons.size())
		if remaining_weapons.is_empty():
			print("║ ✓ This is the FINAL weapon - dialog will show 'Complete Shooting' button")
		print("╚═══════════════════════════════════════════════════════════════")

		# Get last weapon result for dialog display
		var last_weapon_result = _get_last_weapon_result()

		# Emit signal to show confirmation dialog to attacker
		# NOTE: remaining_weapons may be EMPTY if this is the final weapon
		emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index, last_weapon_result)

		# Return success with pause indicator for multiplayer sync
		# ONE SHOT (T4-2): Include one-shot diffs in the result
		var seq_miss_changes = []
		if not pending_one_shot_diffs.is_empty():
			seq_miss_changes.append_array(pending_one_shot_diffs)
			pending_one_shot_diffs.clear()
		print("ShootingPhase: Returning result with sequential_pause indicator")
		print("========================================")
		return create_result(true, seq_miss_changes, "Weapon %d complete (0 hits) - awaiting confirmation" % (current_index + 1), {
			"sequential_pause": true,
			"current_weapon_index": resolution_state.current_index,
			"total_weapons": weapon_order.size(),
			"weapons_remaining": weapon_order.size() - resolution_state.current_index,
			"remaining_weapons": remaining_weapons,
			"last_weapon_result": last_weapon_result,
			"dice": dice_data,
			"log_text": result.get("log_text", "")
		})

	# Store save data and trigger interactive saves
	pending_save_data = save_data_list
	resolution_state.awaiting_saves = true

	# HAZARDOUS (T2-3): Store hazardous weapon data for post-save resolution
	pending_hazardous_weapons = result.get("hazardous_weapons", [])

	# Add sequence context to save data for WoundAllocationOverlay
	for save_data in save_data_list:
		save_data["sequence_context"] = {
			"current_weapon": current_index + 1,
			"total_weapons": weapon_order.size(),
			"weapon_name": RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		}

	# LOGGING: Track saves_required emission
	var timestamp = Time.get_ticks_msec()
	var save_context = {
		"timestamp": timestamp,
		"source": "ShootingPhase._resolve_next_weapon",
		"save_count": save_data_list.size(),
		"target": save_data_list[0].get("target_unit_id", "unknown") if save_data_list.size() > 0 else "none",
		"weapon": save_data_list[0].get("weapon_name", "unknown") if save_data_list.size() > 0 else "none",
		"wounds": save_data_list[0].get("wounds_to_save", 0) if save_data_list.size() > 0 else 0,
		"sequence_weapon": current_index + 1,
		"sequence_total": weapon_order.size()
	}
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SAVES_REQUIRED EMISSION #2 (from resolve_next_weapon)")
	print("║ Timestamp: ", timestamp)
	print("║ Source: ShootingPhase._resolve_next_weapon (line 750)")
	print("║ Target: ", save_context.target)
	print("║ Weapon: ", save_context.weapon, " (", save_context.sequence_weapon, "/", save_context.sequence_total, ")")
	print("║ Wounds: ", save_context.wounds)
	print("║ Save data list size: ", save_data_list.size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Emit signal to show save dialog
	print("ShootingPhase: ✅ Emitting saves_required signal with %d save data entries" % save_data_list.size())
	emit_signal("saves_required", save_data_list)

	log_phase_message("Awaiting defender to make saves for weapon %d of %d..." % [current_index + 1, weapon_order.size()])

	# Return success but don't advance to next weapon yet - wait for saves
	print("ShootingPhase: Returning result with save_data_list for multiplayer broadcast")
	print("ShootingPhase: Result will include %d dice blocks and %d save data entries" % [dice_data.size(), save_data_list.size()])
	print("========================================")
	return create_result(true, [], "Awaiting save resolution", {
		"dice": dice_data,
		"save_data_list": save_data_list,
		"log_text": result.get("log_text", "")
	})

# Helper Methods

func _can_unit_shoot(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})

	# Check if unit is embarked (can't shoot directly, only through transport's firing deck)
	if unit.get("embarked_in", null) != null:
		return false

	# Check if unit is deployed
	if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
		return false

	# Check if unit has already shot
	if flags.get("has_shot", false):
		return false

	# BATTLE-SHOCKED: Battle-shocked units cannot shoot (10e rules)
	if flags.get("battle_shocked", false):
		return false

	# ASSAULT RULES: Units that Advanced can shoot with Assault weapons ONLY
	# Check this BEFORE cannot_shoot flag since Advanced units CAN shoot (with restrictions)
	if flags.get("advanced", false):
		# Unit advanced - can only shoot if it has Assault weapons
		return _unit_has_assault_weapons(unit)

	# Units that Fell Back cannot shoot (unless special rules)
	if flags.get("fell_back", false):
		return false

	# Check other restriction flags (but skip for advanced units handled above)
	if flags.get("cannot_shoot", false):
		return false

	# Check if this is a transport with firing deck capability
	if unit.has("transport_data") and unit.transport_data.get("firing_deck", 0) > 0:
		# Transport with firing deck can shoot if it has embarked units
		if unit.transport_data.get("embarked_units", []).size() > 0:
			# Check if any embarked unit hasn't shot yet
			for embarked_id in unit.transport_data.embarked_units:
				var embarked = get_unit(embarked_id)
				if embarked and not embarked.get("flags", {}).get("has_shot", false):
					return true  # Transport can use firing deck

	# Check if unit is in engagement range - units in engagement can ONLY shoot with Pistols (10e rules)
	# EXCEPTION: Big Guns Never Tire - Monsters/Vehicles can shoot with any weapon at -1 to hit
	if flags.get("in_engagement", false):
		# Check for Pistol weapons (any unit can shoot Pistols in engagement)
		if _unit_has_pistol_weapons(unit):
			return true

		# Check for Big Guns Never Tire (Monsters/Vehicles can shoot any weapon)
		if RulesEngine.is_monster_or_vehicle(unit):
			return true

		# No valid shooting options while in engagement
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

func _unit_has_pistol_weapons(unit: Dictionary) -> bool:
	"""Check if unit has any Pistol weapons (used for engagement range shooting)"""
	# Find the unit_id by searching through game state units
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		if units[unit_id] == unit:
			return RulesEngine.unit_has_pistol_weapons(unit_id, game_state_snapshot)

	# Fallback: search by matching models array reference
	for unit_id in units:
		var u = units[unit_id]
		if u.get("models", []) == unit.get("models", []):
			return RulesEngine.unit_has_pistol_weapons(unit_id, game_state_snapshot)

	return false

func _unit_has_assault_weapons(unit: Dictionary) -> bool:
	"""Check if unit has any Assault weapons (used for shooting after Advancing)"""
	# Find the unit_id by searching through game state units
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		if units[unit_id] == unit:
			return RulesEngine.unit_has_assault_weapons(unit_id, game_state_snapshot)

	# Fallback: search by matching models array reference
	for unit_id in units:
		var u = units[unit_id]
		if u.get("models", []) == unit.get("models", []):
			return RulesEngine.unit_has_assault_weapons(unit_id, game_state_snapshot)

	return false

# ============================================================================
# REACTIVE STRATAGEM SUPPORT (Go to Ground, Smokescreen)
# ============================================================================

# T3-3: Auto-inject Extra Attacks ranged weapons that aren't already in confirmed_assignments
# Extra Attacks weapons are used IN ADDITION to other weapons, not instead of them.
func _auto_inject_extra_attacks_weapons_shooting() -> void:
	if active_shooter_id.is_empty():
		return

	var unit = get_unit(active_shooter_id)
	if unit.is_empty():
		return

	var weapons_data = unit.get("meta", {}).get("weapons", [])

	# Find Extra Attacks ranged weapons
	var ea_weapons = []
	for weapon in weapons_data:
		if weapon.get("type", "").to_lower() != "melee":
			if RulesEngine.weapon_data_has_extra_attacks(weapon):
				ea_weapons.append(weapon)

	if ea_weapons.is_empty():
		return

	# Check which EA weapons are already assigned
	var assigned_weapon_ids = {}
	for assignment in confirmed_assignments:
		assigned_weapon_ids[assignment.get("weapon_id", "")] = true

	# Determine default target: use first confirmed assignment's target
	var default_target = ""
	if not confirmed_assignments.is_empty():
		default_target = confirmed_assignments[0].get("target_unit_id", "")

	for weapon in ea_weapons:
		var weapon_name = weapon.get("name", "Unknown")
		var weapon_id = RulesEngine._generate_weapon_id(weapon_name, weapon.get("type", ""))

		if assigned_weapon_ids.has(weapon_id):
			print("[ShootingPhase] T3-3: Extra Attacks weapon '%s' already assigned, skipping" % weapon_name)
			continue

		if default_target.is_empty():
			print("[ShootingPhase] T3-3: No target available for Extra Attacks weapon '%s'" % weapon_name)
			continue

		confirmed_assignments.append({
			"weapon_id": weapon_id,
			"target_unit_id": default_target,
			"model_ids": []
		})
		print("[ShootingPhase] T3-3: Auto-injected Extra Attacks weapon '%s' → '%s'" % [weapon_name, default_target])

	log_phase_message("T3-3: Extra Attacks weapons auto-included for %s" % active_shooter_id)

func _check_reactive_stratagems() -> Dictionary:
	"""
	Check if the defending player has reactive stratagems available for the current targets.
	Returns { has_opportunities: bool, defending_player: int, available_stratagems: Array, target_unit_ids: Array }
	"""
	var active_player = get_current_player()
	var defending_player = 2 if active_player == 1 else 1

	# Collect unique target unit IDs from confirmed assignments
	var target_unit_ids = []
	for assignment in confirmed_assignments:
		var target_id = assignment.get("target_unit_id", "")
		if target_id != "" and target_id not in target_unit_ids:
			target_unit_ids.append(target_id)

	if target_unit_ids.is_empty():
		return {"has_opportunities": false}

	# Ask StratagemManager for available reactive stratagems
	var available = StratagemManager.get_reactive_stratagems_for_shooting(defending_player, target_unit_ids)

	if available.is_empty():
		print("ShootingPhase: No reactive stratagems available for defender (player %d)" % defending_player)
		return {"has_opportunities": false}

	print("ShootingPhase: %d reactive stratagem(s) available for defender (player %d)" % [available.size(), defending_player])
	for entry in available:
		print("  - %s: eligible units = %s" % [entry.stratagem.name, str(entry.eligible_units)])

	return {
		"has_opportunities": true,
		"defending_player": defending_player,
		"available_stratagems": available,
		"target_unit_ids": target_unit_ids
	}

func _validate_use_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Validate using a reactive stratagem during opponent's shooting."""
	if not awaiting_reactive_stratagem:
		return {"valid": false, "errors": ["Not waiting for reactive stratagem decision"]}

	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")

	if stratagem_id == "":
		return {"valid": false, "errors": ["Missing stratagem_id"]}
	if target_unit_id == "":
		return {"valid": false, "errors": ["Missing target_unit_id"]}

	# Validate through StratagemManager
	var active_player = get_current_player()
	var defending_player = 2 if active_player == 1 else 1
	var validation = StratagemManager.can_use_stratagem(defending_player, stratagem_id, target_unit_id)

	if not validation.can_use:
		return {"valid": false, "errors": [validation.reason]}

	return {"valid": true, "errors": []}

func _validate_decline_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Validate declining to use a reactive stratagem."""
	if not awaiting_reactive_stratagem:
		return {"valid": false, "errors": ["Not waiting for reactive stratagem decision"]}
	return {"valid": true, "errors": []}

func _process_use_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Process the defender using a reactive stratagem (Go to Ground / Smokescreen)."""
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var active_player = get_current_player()
	var defending_player = 2 if active_player == 1 else 1

	# Use the stratagem via StratagemManager (deducts CP, records usage, applies effects)
	var result = StratagemManager.use_stratagem(defending_player, stratagem_id, target_unit_id)

	if not result.success:
		return create_result(false, [], result.get("error", "Stratagem use failed"))

	# Refresh game state snapshot so RulesEngine sees the new flags
	game_state_snapshot = GameState.create_snapshot()

	# Clear awaiting state and continue to resolution
	awaiting_reactive_stratagem = false
	log_phase_message("Player %d used %s on %s" % [defending_player, StratagemManager.get_stratagem(stratagem_id).name, target_unit_id])

	# Continue shooting resolution
	var continue_result = _continue_after_reactive_stratagems()

	# Merge diffs
	var all_diffs = result.get("diffs", [])
	if continue_result.success:
		all_diffs.append_array(continue_result.get("changes", []))

	# Build combined result
	var combined = create_result(true, all_diffs)
	# Copy over all extra fields from the continue result
	for key in continue_result:
		if key != "success" and key != "changes" and key != "phase" and key != "timestamp":
			combined[key] = continue_result[key]

	combined["stratagem_used"] = {
		"stratagem_id": stratagem_id,
		"stratagem_name": StratagemManager.get_stratagem(stratagem_id).name,
		"target_unit_id": target_unit_id,
		"player": defending_player
	}

	return combined

func _process_decline_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Process the defender declining to use any reactive stratagem."""
	awaiting_reactive_stratagem = false
	log_phase_message("Defender declined reactive stratagems")

	# Continue shooting resolution
	return _continue_after_reactive_stratagems()

# ============================================================================
# GRENADE STRATAGEM SUPPORT
# ============================================================================

func _validate_use_grenade_stratagem(action: Dictionary) -> Dictionary:
	"""Validate using the GRENADE stratagem during the active player's shooting phase."""
	var grenade_unit_id = action.get("grenade_unit_id", "")
	var target_unit_id = action.get("target_unit_id", "")

	if grenade_unit_id == "":
		return {"valid": false, "errors": ["Missing grenade_unit_id"]}
	if target_unit_id == "":
		return {"valid": false, "errors": ["Missing target_unit_id"]}

	var current_player = get_current_player()

	# Check that the grenade unit belongs to the active player
	var grenade_unit = get_unit(grenade_unit_id)
	if grenade_unit.is_empty():
		return {"valid": false, "errors": ["Grenade unit not found"]}
	if grenade_unit.get("owner", 0) != current_player:
		return {"valid": false, "errors": ["Grenade unit does not belong to active player"]}

	# Check that the grenade unit hasn't already shot
	if grenade_unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot this phase"]}

	# Check that the target is an enemy unit
	var target_unit = get_unit(target_unit_id)
	if target_unit.is_empty():
		return {"valid": false, "errors": ["Target unit not found"]}
	if target_unit.get("owner", 0) == current_player:
		return {"valid": false, "errors": ["Cannot target friendly units with GRENADE"]}

	# Validate through StratagemManager
	var validation = StratagemManager.can_use_stratagem(current_player, "grenade", grenade_unit_id)
	if not validation.can_use:
		return {"valid": false, "errors": [validation.reason]}

	return {"valid": true, "errors": []}

func _process_use_grenade_stratagem(action: Dictionary) -> Dictionary:
	"""Process the GRENADE stratagem: roll 6D6, 4+ = mortal wound."""
	var grenade_unit_id = action.get("grenade_unit_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	# Execute via StratagemManager (handles CP deduction, dice rolling, mortal wound application)
	# NOTE: execute_grenade applies all diffs internally via PhaseManager.apply_state_changes()
	var result = StratagemManager.execute_grenade(current_player, grenade_unit_id, target_unit_id)

	if not result.success:
		return create_result(false, [], result.get("error", "Grenade stratagem failed"))

	# Mark unit as having shot in our local tracking
	units_that_shot.append(grenade_unit_id)

	# Clear active shooter if this was the active unit
	if active_shooter_id == grenade_unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Refresh game state snapshot
	game_state_snapshot = GameState.create_snapshot()

	log_phase_message(result.get("message", "GRENADE used"))

	# Emit grenade result signal for UI
	emit_signal("grenade_result", result)

	# Emit dice rolled for dice log display
	emit_signal("dice_rolled", {
		"context": "grenade",
		"rolls_raw": result.get("dice_rolls", []),
		"successes": result.get("mortal_wounds", 0),
		"threshold": "4+",
		"message": result.get("message", "")
	})

	# Emit shooting resolved to refresh visuals
	emit_signal("shooting_resolved", grenade_unit_id, target_unit_id, {
		"casualties": result.get("casualties", 0),
		"grenade": true
	})

	# Return empty changes since execute_grenade already applied all diffs internally
	# (BasePhase.execute_action would double-apply if we returned diffs here)
	return create_result(true, [], result.get("message", ""), {
		"grenade_result": {
			"dice_rolls": result.get("dice_rolls", []),
			"mortal_wounds": result.get("mortal_wounds", 0),
			"casualties": result.get("casualties", 0),
			"grenade_unit_id": grenade_unit_id,
			"target_unit_id": target_unit_id,
			"message": result.get("message", "")
		}
	})

func _get_last_weapon_result() -> Dictionary:
	"""Build complete result summary for last weapon"""
	var completed = resolution_state.get("completed_weapons", [])
	if completed.is_empty():
		return {}

	var last_weapon = completed[completed.size() - 1]
	var weapon_profile = RulesEngine.get_weapon_profile(last_weapon.get("weapon_id", ""))

	return {
		"weapon_id": last_weapon.get("weapon_id", ""),
		"weapon_name": weapon_profile.get("name", last_weapon.get("weapon_id", "Unknown")),
		"target_unit_id": last_weapon.get("target_unit_id", ""),
		"target_unit_name": last_weapon.get("target_unit_name", "Unknown"),
		"hits": last_weapon.get("hits", 0),
		"wounds": last_weapon.get("wounds", 0),
		"saves_failed": last_weapon.get("saves_failed", 0),
		"casualties": last_weapon.get("casualties", 0),
		"dice_rolls": last_weapon.get("dice_rolls", []),
		"total_attacks": last_weapon.get("total_attacks", 0),
		"hit_data": last_weapon.get("hit_data", {}),
		"wound_data": last_weapon.get("wound_data", {}),
		"skipped": last_weapon.get("skipped", false),
		"skip_reason": last_weapon.get("skip_reason", "")
	}

func _clear_phase_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			unit.flags.erase("has_shot")

func _clear_stratagem_phase_flags() -> void:
	"""Clear effect-granted flags from all units at end of shooting phase."""
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			var flags = unit.flags
			EffectPrimitivesData.clear_all_effect_flags(flags)
	# Also tell StratagemManager to clear its phase-scoped effects
	StratagemManager.on_phase_end(GameStateData.Phase.SHOOTING)

func _clear_shooting_visuals() -> void:
	"""Clear all shooting-related visuals from the board when phase ends"""
	# Get the ShootingController from Main
	var main = get_node_or_null("/root/Main")
	if not main:
		print("ShootingPhase: Warning - Main node not found for visual cleanup")
		return

	var shooting_controller = main.get("shooting_controller")
	if shooting_controller and is_instance_valid(shooting_controller):
		print("ShootingPhase: Clearing shooting visuals via controller")
		# Call controller's cleanup method
		if shooting_controller.has_method("_clear_visuals"):
			shooting_controller._clear_visuals()
		print("ShootingPhase: Shooting visuals cleared")
	else:
		# Fallback: If controller already freed, clean up BoardRoot directly
		print("ShootingPhase: Controller not available, cleaning BoardRoot directly")
		_cleanup_boardroot_visuals()

func _cleanup_boardroot_visuals() -> void:
	"""Fallback cleanup - remove shooting visuals directly from BoardRoot"""
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		return

	# Remove shooting-specific visual nodes
	var visual_names = [
		"ShootingRangeVisual",
		"ShootingLoSVisual",
		"ShootingTargetHighlights",
		"LoSDebugVisual"
	]

	for visual_name in visual_names:
		var visual_node = board_root.get_node_or_null(visual_name)
		if visual_node and is_instance_valid(visual_node):
			print("ShootingPhase: Removing ", visual_name, " from BoardRoot")
			board_root.remove_child(visual_node)
			visual_node.queue_free()

func _clear_death_markers() -> void:
	"""Clear all death markers from the board at phase end"""
	var main = get_node_or_null("/root/Main")
	if not main:
		print("ShootingPhase: Warning - Main node not found for death marker cleanup")
		return

	var board_view = main.get_node_or_null("BoardRoot/BoardView")
	if not board_view:
		print("ShootingPhase: Warning - BoardView not found for death marker cleanup")
		return

	# Find WoundAllocationBoardHighlights instance
	var highlighter = board_view.get_node_or_null("WoundHighlights")
	if highlighter and is_instance_valid(highlighter):
		if highlighter.has_method("clear_death_markers"):
			highlighter.clear_death_markers()
			print("ShootingPhase: Cleared death markers via highlighter")
		else:
			print("ShootingPhase: Warning - highlighter has no clear_death_markers method")
	else:
		print("ShootingPhase: No highlighter found to clear death markers")

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	# If we have an active shooter with pending assignments
	if active_shooter_id != "" and not pending_assignments.is_empty():
		actions.append({
			"type": "CONFIRM_TARGETS",
			"description": "Confirm target assignments"
		})
		actions.append({
			"type": "CLEAR_ALL_ASSIGNMENTS",
			"description": "Clear all assignments"
		})
	
	# If we have confirmed assignments ready to resolve
	if not confirmed_assignments.is_empty():
		actions.append({
			"type": "RESOLVE_SHOOTING",
			"description": "Resolve shooting"
		})

	# Pending saves need resolution (safety net for AI)
	if not pending_save_data.is_empty():
		actions.append({
			"type": "APPLY_SAVES",
			"description": "Apply pending saves"
		})

	# Sequential mode: continue or complete (safety net for AI)
	if resolution_state.get("mode", "") == "sequential":
		var idx = resolution_state.get("current_index", 0)
		var order = resolution_state.get("weapon_order", [])
		if idx < order.size():
			actions.append({
				"type": "CONTINUE_SEQUENCE",
				"description": "Continue to next weapon"
			})
		elif active_shooter_id != "":
			actions.append({
				"type": "COMPLETE_SHOOTING_FOR_UNIT",
				"actor_unit_id": active_shooter_id,
				"description": "Complete shooting for unit"
			})

	# Single weapon completed but awaiting confirmation (safety net for AI)
	if resolution_state.get("phase", "") == "awaiting_confirmation" and active_shooter_id != "":
		actions.append({
			"type": "COMPLETE_SHOOTING_FOR_UNIT",
			"actor_unit_id": active_shooter_id,
			"description": "Complete shooting for unit"
		})

	# Units that can shoot
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit) and unit_id not in units_that_shot:
			actions.append({
				"type": "SELECT_SHOOTER",
				"actor_unit_id": unit_id,
				"description": "Select %s for shooting" % unit.get("meta", {}).get("name", unit_id)
			})

			actions.append({
				"type": "SKIP_UNIT",
				"actor_unit_id": unit_id,
				"description": "Skip shooting for %s" % unit.get("meta", {}).get("name", unit_id)
			})

	# Always can end phase
	actions.append({
		"type": "END_SHOOTING",
		"description": "End Shooting Phase"
	})

	return actions

func _should_complete_phase() -> bool:
	# Check if all eligible units have shot or been skipped
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit) and unit_id not in units_that_shot:
			return false
	
	return true

func get_dice_log() -> Array:
	return dice_log

func get_active_shooter() -> String:
	return active_shooter_id

func get_pending_assignments() -> Array:
	return pending_assignments

func get_confirmed_assignments() -> Array:
	return confirmed_assignments

func get_units_that_shot() -> Array:
	return units_that_shot

func has_active_shooter() -> bool:
	return active_shooter_id != ""

func get_current_shooting_state() -> Dictionary:
	return {
		"active_shooter_id": active_shooter_id,
		"pending_assignments": pending_assignments,
		"confirmed_assignments": confirmed_assignments,
		"units_that_shot": units_that_shot,
		"eligible_targets": {} # Will be populated when targets are queried
	}

# Override create_result to support additional data
func create_result(success: bool, changes: Array = [], error: String = "", additional_data: Dictionary = {}) -> Dictionary:
	var result = {
		"success": success,
		"phase": phase_type,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if success:
		result["changes"] = changes
		for key in additional_data:
			result[key] = additional_data[key]
	else:
		result["error"] = error
	
	return result

func validate_loaded_state() -> bool:
	"""Validate that the loaded shooting phase state is consistent"""
	# Check if active shooter is valid
	if active_shooter_id != "":
		var shooter = get_unit(active_shooter_id)
		if shooter.is_empty():
			print("WARNING: Invalid active shooter after load: ", active_shooter_id)
			active_shooter_id = ""
			return false
		
		if not _can_unit_shoot(shooter):
			print("WARNING: Active shooter cannot shoot after load: ", active_shooter_id) 
			active_shooter_id = ""
			return false
	
	# Validate assignments reference valid units and weapons
	for assignment in pending_assignments:
		var target = get_unit(assignment.target_unit_id)
		if target.is_empty():
			print("WARNING: Invalid target in assignments: ", assignment.target_unit_id)
			return false

	return true

# Transport Firing Deck support

func _show_firing_deck_dialog(transport_id: String) -> void:
	"""Show dialog to select which embarked models will shoot through firing deck"""
	var transport = get_unit(transport_id)
	var firing_deck_capacity = transport.transport_data.get("firing_deck", 0)
	var embarked_units = transport.transport_data.get("embarked_units", [])

	# Create firing deck dialog
	var dialog_script = load("res://scripts/FiringDeckDialog.gd")
	var dialog = dialog_script.new()
	dialog.setup(transport_id, embarked_units, firing_deck_capacity)
	dialog.models_selected.connect(_on_firing_deck_models_selected.bind(transport_id))

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_firing_deck_models_selected(selected_weapons: Array, transport_id: String) -> void:
	"""Handle selection of weapons from embarked units for firing deck"""
	# Store the selected weapons as part of transport's temporary shooting state
	if not resolution_state.has("firing_deck_weapons"):
		resolution_state["firing_deck_weapons"] = {}

	resolution_state["firing_deck_weapons"][transport_id] = selected_weapons

	# Mark those units as having shot
	var changes = []
	for weapon_data in selected_weapons:
		var unit_id = weapon_data.get("unit_id", "")
		if unit_id != "":
			changes.append({
				"op": "set",
				"path": "units.%s.flags.has_shot" % unit_id,
				"value": true
			})

	# Apply state changes
	if changes.size() > 0:
		# Apply through parent if it exists
		if get_parent() and get_parent().has_method("apply_state_changes"):
			get_parent().apply_state_changes(changes)

	# Now proceed with normal target selection for the transport
	# The transport will use the selected weapons from embarked units
	var eligible_targets = RulesEngine.get_eligible_targets(transport_id, game_state_snapshot)

	emit_signal("unit_selected_for_shooting", transport_id)
	emit_signal("targets_available", transport_id, eligible_targets)

	log_phase_message("Firing deck weapons selected for %s" % get_unit(transport_id).get("meta", {}).get("name", transport_id))

# Interactive Save Resolution

func _validate_apply_saves(action: Dictionary) -> Dictionary:
	"""Validate that save data is ready to be applied"""
	if pending_save_data.is_empty():
		return {"valid": false, "errors": ["No pending saves to apply"]}

	var payload = action.get("payload", {})
	if not payload.has("save_results_list"):
		return {"valid": false, "errors": ["Missing save_results_list in payload"]}

	return {"valid": true, "errors": []}

func _validate_continue_sequence(action: Dictionary) -> Dictionary:
	"""Validate continuing to next weapon in sequential mode"""
	var mode = resolution_state.get("mode", "")
	if mode != "sequential":
		return {"valid": false, "errors": ["Not in sequential mode"]}

	var current_index = resolution_state.get("current_index", 0)
	var weapon_order = resolution_state.get("weapon_order", [])

	if current_index >= weapon_order.size():
		return {"valid": false, "errors": ["No more weapons to resolve"]}

	return {"valid": true, "errors": []}

func _validate_complete_shooting_for_unit(action: Dictionary) -> Dictionary:
	"""Validate completing shooting for a unit after final weapon"""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	if unit_id != active_shooter_id:
		return {"valid": false, "errors": ["Unit is not the active shooter"]}

	return {"valid": true, "errors": []}

func _process_complete_shooting_for_unit(action: Dictionary) -> Dictionary:
	"""Mark shooter as done and clear state"""
	var unit_id = action.get("actor_unit_id", "")

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SHOOTING PHASE: COMPLETE_SHOOTING_FOR_UNIT")
	print("║ Unit ID: ", unit_id)
	print("║ This is triggered when user views final weapon results")
	print("╚═══════════════════════════════════════════════════════════════")

	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]

	units_that_shot.append(unit_id)

	# Clear state
	var shooter_id = active_shooter_id  # Store before clearing
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()

	log_phase_message("Shooting complete for unit %s" % unit_id)

	# Emit signal to clear visuals
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

	return create_result(true, changes, "Shooting complete")

func _process_apply_saves(action: Dictionary) -> Dictionary:
	"""Process save results and apply damage"""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ APPLY_SAVES PROCESSING START")
	print("║ Timestamp: ", Time.get_ticks_msec())
	print("║ resolution_state: ", resolution_state)
	print("║ pending_save_data.size(): ", pending_save_data.size())
	print("╚═══════════════════════════════════════════════════════════════")

	var payload = action.get("payload", {})
	var save_results_list = payload.get("save_results_list", [])

	var all_diffs = []
	var total_casualties = 0
	var save_dice_blocks = []  # Collect save dice for dice log + multiplayer sync
	var save_log_parts = []  # Accumulate per-target save summaries for game event log
	var shooter_unit = game_state_snapshot.get("units", {}).get(active_shooter_id, {})
	var shooter_name = shooter_unit.get("meta", {}).get("name", active_shooter_id)

	# Process each save result (one per target unit)
	for i in range(save_results_list.size()):
		if i >= pending_save_data.size():
			break

		var save_result_summary = save_results_list[i]
		var save_data = pending_save_data[i]

		print("╔═══════════════════════════════════════════════════════════════")
		print("║ PROCESSING SAVE RESULT %d" % i)
		print("║ save_result_summary keys: ", save_result_summary.keys())
		print("║ Has save_results: ", save_result_summary.has("save_results"))
		print("║ Has allocation_history: ", save_result_summary.has("allocation_history"))
		print("╚═══════════════════════════════════════════════════════════════")

		# Convert allocation_history to save_results format if needed
		var save_results = []
		if save_result_summary.has("save_results"):
			save_results = save_result_summary.save_results
		elif save_result_summary.has("allocation_history"):
			# Convert allocation_history format to save_results format
			print("║ Converting allocation_history to save_results format")
			for alloc in save_result_summary.allocation_history:
				save_results.append({
					"saved": alloc.get("saved", false),
					"model_id": alloc.get("model_id", ""),
					"model_index": alloc.get("model_index", 0),  # CRITICAL: RulesEngine needs this!
					"roll": alloc.get("roll", 0),
					"damage": alloc.get("damage", 0),
					"model_destroyed": alloc.get("model_destroyed", false)
				})
			print("║ Converted %d allocation entries to save_results" % save_results.size())

		# DEVASTATING WOUNDS (PRP-012): Get devastating damage from save_result_summary
		var devastating_damage = save_result_summary.get("devastating_damage", 0)
		if devastating_damage > 0:
			print("║ DEVASTATING WOUNDS: %d damage to apply (unsaveable)" % devastating_damage)
			# Update save_data with devastating damage for apply_save_damage
			save_data["devastating_damage"] = devastating_damage

		# Apply damage using RulesEngine (with RNG for Feel No Pain rolls)
		var fnp_rng = RulesEngine.RNGService.new()
		var damage_result = RulesEngine.apply_save_damage(
			save_results,
			save_data,
			game_state_snapshot,
			-1,
			fnp_rng
		)

		# Collect diffs
		all_diffs.append_array(damage_result.diffs)
		total_casualties += damage_result.casualties

		# Check if bodyguard unit was destroyed — detach characters if needed
		if damage_result.casualties > 0:
			var target_unit_id_for_check = save_data.get("target_unit_id", "")
			if target_unit_id_for_check != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id_for_check)

		# Log results
		var target_name = save_data.get("target_unit_name", "Unknown")
		var saved_count = save_result_summary.get("saves_passed", 0)
		var failed_count = save_result_summary.get("saves_failed", 0)

		# Fall back to counting if not in summary
		if saved_count == 0 and failed_count == 0:
			for sr in save_results:
				if sr.get("saved", false):
					saved_count += 1
				else:
					failed_count += 1

		log_phase_message("%s: %d saves passed, %d failed → %d casualties" % [
			target_name,
			saved_count,
			failed_count,
			damage_result.casualties
		])
		save_log_parts.append("%s → %s: %d saved, %d failed → %d slain" % [
			shooter_name, target_name, saved_count, failed_count, damage_result.casualties
		])

		# Build save dice block for dice log (so both players can see save rolls)
		var save_rolls_raw = []
		for sr in save_results:
			if sr.has("roll"):
				save_rolls_raw.append(sr.get("roll", 0))

		if not save_rolls_raw.is_empty():
			var ap = save_data.get("ap", 0)
			var base_save = save_data.get("base_save", 7)
			# Get the effective save threshold from the first model's profile
			var save_threshold = 7
			var using_invuln = false
			var profiles = save_data.get("model_save_profiles", [])
			if not profiles.is_empty():
				save_threshold = profiles[0].get("save_needed", 7)
				using_invuln = profiles[0].get("using_invuln", false)

			var save_dice_block = {
				"context": "save_roll",
				"threshold": str(save_threshold) + "+",
				"rolls_raw": save_rolls_raw,
				"successes": saved_count,
				"failed": failed_count,
				"ap": ap,
				"original_save": base_save,
				"using_invuln": using_invuln,
				"weapon_name": save_data.get("weapon_name", ""),
				"target_unit_name": target_name
			}
			save_dice_blocks.append(save_dice_block)
			dice_log.append(save_dice_block)
			emit_signal("dice_rolled", save_dice_block)
			print("ShootingPhase: Emitted save_roll dice block - %d rolls, %d passed, %d failed" % [save_rolls_raw.size(), saved_count, failed_count])

		# FEEL NO PAIN: Emit FNP dice blocks from RulesEngine batch path
		var fnp_rolls_from_engine = damage_result.get("fnp_rolls", [])
		for fnp_block in fnp_rolls_from_engine:
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
			print("ShootingPhase: Emitted feel_no_pain dice block - %d prevented / %d total" % [fnp_block.get("wounds_prevented", 0), fnp_block.get("total_wounds", 0)])

		# FEEL NO PAIN: Also collect FNP data from WoundAllocationOverlay allocation_history
		var fnp_rolls_from_overlay = []
		if save_result_summary.has("allocation_history"):
			for alloc in save_result_summary.allocation_history:
				var alloc_fnp_rolls = alloc.get("fnp_rolls", [])
				if not alloc_fnp_rolls.is_empty():
					fnp_rolls_from_overlay.append_array(alloc_fnp_rolls)
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
					"source": "interactive_saves",
					"target_unit_name": target_name
				}
				dice_log.append(fnp_overlay_block)
				emit_signal("dice_rolled", fnp_overlay_block)
				print("ShootingPhase: Emitted feel_no_pain dice block from overlay - %d prevented / %d total" % [total_prevented, fnp_rolls_from_overlay.size()])

	# HAZARDOUS (T2-3): Process Hazardous self-damage after saves resolve
	if not pending_hazardous_weapons.is_empty():
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ HAZARDOUS CHECK — Processing %d hazardous weapon(s)" % pending_hazardous_weapons.size())
		print("╚═══════════════════════════════════════════════════════════════")
		var haz_rng = RulesEngine.RNGService.new()
		for haz_weapon in pending_hazardous_weapons:
			var haz_result = RulesEngine.resolve_hazardous_check(
				active_shooter_id,
				haz_weapon.get("weapon_id", ""),
				haz_weapon.get("models_that_fired", 0),
				game_state_snapshot,
				haz_rng
			)
			if haz_result.hazardous_triggered:
				all_diffs.append_array(haz_result.diffs)
			for haz_dice in haz_result.dice:
				dice_log.append(haz_dice)
				emit_signal("dice_rolled", haz_dice)
			if haz_result.log_text:
				log_phase_message(haz_result.log_text)
		pending_hazardous_weapons.clear()

	# ONE SHOT (T4-2): Include one-shot diffs in save result changes
	if not pending_one_shot_diffs.is_empty():
		all_diffs.append_array(pending_one_shot_diffs)
		pending_one_shot_diffs.clear()

	# Build combined save log text for game event log
	var save_log_text = ", ".join(save_log_parts)

	# Check if we're in sequential weapon resolution mode
	var mode = resolution_state.get("mode", "")
	var is_sequential = (mode == "sequential")

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ MODE CHECK IN _process_apply_saves")
	print("║ resolution_state keys: ", resolution_state.keys())
	print("║ mode from resolution_state: '", mode, "'")
	print("║ is_sequential: ", is_sequential)
	print("║ active_shooter_id: ", active_shooter_id)
	print("║ confirmed_assignments.size(): ", confirmed_assignments.size())
	print("║")
	print("║ PATH DECISION:")
	if is_sequential:
		print("║ → Will take SEQUENTIAL path (lines 1401-1508)")
	else:
		print("║ → Will take SINGLE WEAPON path (lines 1510+)")
	print("╚═══════════════════════════════════════════════════════════════")

	if is_sequential:
		# Sequential mode - record results and PAUSE for attacker to confirm next weapon
		var current_index = resolution_state.get("current_index", 0)
		var weapon_order = resolution_state.get("weapon_order", [])

		print("========================================")
		print("ShootingPhase: APPLY_SAVES complete in sequential mode")
		print("ShootingPhase: current_index = %d, weapon_order.size() = %d" % [current_index, weapon_order.size()])

		if current_index < weapon_order.size():
			var weapon_id = weapon_order[current_index].get("weapon_id", "")
			var current_assignment_data = weapon_order[current_index]
			print("ShootingPhase: Completed weapon %d: %s" % [current_index + 1, weapon_id])

			# Calculate saves_failed from save results
			var saves_failed = 0
			for save_result in save_results_list:
				saves_failed += save_result.get("saves_failed", 0)

			# Get dice data from resolution_state (stored when weapon was resolved)
			var dice_data = resolution_state.get("last_weapon_dice_data", [])
			var hit_data = resolution_state.get("last_weapon_hit_data", {})
			var wound_data = resolution_state.get("last_weapon_wound_data", {})
			var target_unit_name = resolution_state.get("last_weapon_target_name", "Unknown")
			var target_unit_id = resolution_state.get("last_weapon_target_id", "")

			var hits = hit_data.get("successes", 0)
			var total_attacks = hit_data.get("total", 0)

			# Record completed weapon with full data
			resolution_state.completed_weapons.append({
				"weapon_id": weapon_id,
				"target_unit_id": target_unit_id,
				"target_unit_name": target_unit_name,
				"wounds": pending_save_data.size() if not pending_save_data.is_empty() else 0,
				"casualties": total_casualties,
				"hits": hits,
				"total_attacks": total_attacks,
				"saves_failed": saves_failed,
				"dice_rolls": dice_data,
				"hit_data": hit_data,
				"wound_data": wound_data
			})

			# Move to next weapon INDEX
			resolution_state.current_index += 1
			resolution_state.awaiting_saves = false

			# Clear pending save data
			pending_save_data.clear()

			print("ShootingPhase: Moving to next weapon index: %d" % resolution_state.current_index)
			print("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index))

			# ALWAYS PAUSE for attacker to confirm (even if last weapon)
			# Wait for attacker to confirm before continuing or completing
			print("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon")
			print("ShootingPhase: Remaining weapons: ", weapon_order.size() - resolution_state.current_index)

			# Build remaining weapons with validation (may be empty array if this is the last weapon)
			var remaining_weapons = []

			print("╔═══════════════════════════════════════════════════════════════")
			print("║ BUILDING REMAINING WEAPONS (after saves)")
			print("║ weapon_order.size() = %d" % weapon_order.size())
			print("║ current_index = %d" % resolution_state.current_index)
			print("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index))

			for i in range(resolution_state.current_index, weapon_order.size()):
				var weapon = weapon_order[i]
				remaining_weapons.append(weapon)

				# Validate weapon structure
				var remaining_weapon_id = weapon.get("weapon_id", "")
				if remaining_weapon_id == "":
					push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
					print("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i)
					print("║   Full weapon object: %s" % str(weapon))
				else:
					print("║ Added weapon %d: %s" % [i, remaining_weapon_id])

			print("║ Total remaining weapons: %d" % remaining_weapons.size())
			if remaining_weapons.is_empty():
				print("║ ✓ This is the FINAL weapon - dialog will show 'Complete Shooting' button")
			print("╚═══════════════════════════════════════════════════════════════")

			# Get last weapon result for dialog display
			var last_weapon_result = _get_last_weapon_result()

			# Emit signal to show confirmation dialog to attacker
			# NOTE: remaining_weapons may be EMPTY if this is the final weapon
			print("╔═══════════════════════════════════════════════════════════════")
			print("║ EMITTING next_weapon_confirmation_required SIGNAL")
			print("║ remaining_weapons.size(): ", remaining_weapons.size())
			print("║ current_index: ", resolution_state.current_index)
			print("║ last_weapon_result keys: ", last_weapon_result.keys())
			print("╚═══════════════════════════════════════════════════════════════")
			emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index, last_weapon_result)

			# Return success with pause indicator for multiplayer sync
			var result = create_result(true, all_diffs, "Weapon %d complete - awaiting confirmation" % (current_index + 1), {
				"sequential_pause": true,
				"current_weapon_index": resolution_state.current_index,
				"total_weapons": weapon_order.size(),
				"dice": save_dice_blocks,
				"weapons_remaining": weapon_order.size() - resolution_state.current_index,
				"remaining_weapons": remaining_weapons,
				"last_weapon_result": last_weapon_result,
				"log_text": save_log_text
			})

			print("╔═══════════════════════════════════════════════════════════════")
			print("║ APPLY_SAVES RESULT (with sequential_pause)")
			print("║ result.sequential_pause: ", result.get("sequential_pause", false))
			print("║ result.remaining_weapons.size(): ", result.get("remaining_weapons", []).size())
			print("║ result.current_weapon_index: ", result.get("current_weapon_index", -1))
			print("╚═══════════════════════════════════════════════════════════════")

			return result

	# Normal mode (single weapon) or fast mode - show results dialog before completing
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ 🎯 SINGLE WEAPON PATH REACHED! (Line 1548)")
	print("║ mode: '", mode, "'")
	print("║ total_casualties: ", total_casualties)
	print("║ confirmed_assignments.size(): ", confirmed_assignments.size())
	print("║ all_diffs.size(): ", all_diffs.size())
	print("║")
	print("║ NOW: Building last_weapon_result...")
	print("╚═══════════════════════════════════════════════════════════════")

	# Build last weapon result for single weapon case
	var last_weapon_result = {}
	if not confirmed_assignments.is_empty():
		print("║ ✓ confirmed_assignments NOT empty, building result...")
		var assignment = confirmed_assignments[0]
		var weapon_id = assignment.get("weapon_id", "")
		print("║   weapon_id: ", weapon_id)

		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		print("║   weapon_name: ", weapon_profile.get("name", weapon_id))

		var target_unit_id = assignment.get("target_unit_id", "")
		var target_unit = get_unit(target_unit_id)
		print("║   target: ", target_unit.get("meta", {}).get("name", target_unit_id))

		# Build result from save data
		var saves_failed = 0
		for save_result in save_results_list:
			saves_failed += save_result.get("saves_failed", 0)

		# T4-15: Retrieve hit/wound data from resolution_state (stored during _process_resolve_shooting)
		var sw_dice_data = resolution_state.get("last_weapon_dice_data", [])
		var sw_hit_data = resolution_state.get("last_weapon_hit_data", {})
		var sw_wound_data = resolution_state.get("last_weapon_wound_data", {})
		var sw_hits = sw_hit_data.get("successes", 0)
		var sw_total_attacks = sw_hit_data.get("total", 0)

		print("║   saves_failed: ", saves_failed)
		print("║   casualties: ", total_casualties)
		print("║   hits: ", sw_hits, " / ", sw_total_attacks)

		last_weapon_result = {
			"weapon_id": weapon_id,
			"weapon_name": weapon_profile.get("name", weapon_id),
			"target_unit_id": target_unit_id,
			"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
			"hits": sw_hits,
			"wounds": pending_save_data.size() if not pending_save_data.is_empty() else 0,
			"saves_failed": saves_failed,
			"casualties": total_casualties,
			"total_attacks": sw_total_attacks,
			"dice_rolls": sw_dice_data,
			"hit_data": sw_hit_data,
			"wound_data": sw_wound_data
		}
		print("║ ✓ last_weapon_result built successfully!")
	else:
		print("║ ⚠️  WARNING: confirmed_assignments is EMPTY!")

	# Emit signal with EMPTY remaining_weapons (signals completion)
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ 📡 EMITTING next_weapon_confirmation_required SIGNAL")
	print("║ Signal name: 'next_weapon_confirmation_required'")
	print("║ Parameter 1 (remaining_weapons): [] (empty array)")
	print("║ Parameter 2 (current_index): 0")
	print("║ Parameter 3 (last_weapon_result): ", last_weapon_result)
	print("║")
	print("║ This signal should trigger ShootingController to show dialog!")
	print("╚═══════════════════════════════════════════════════════════════")

	emit_signal("next_weapon_confirmation_required", [], 0, last_weapon_result)

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ✅ Signal emitted successfully!")
	print("║ Returning result with sequential_pause=true")
	print("╚═══════════════════════════════════════════════════════════════")

	# Return with pause indicator (completion will happen when user clicks "Complete Shooting")
	var result = create_result(true, all_diffs, "Single weapon complete - awaiting confirmation", {
		"sequential_pause": true,
		"remaining_weapons": [],
		"last_weapon_result": last_weapon_result,
		"current_weapon_index": 0,
		"total_weapons": 1,
		"dice": save_dice_blocks,
		"log_text": save_log_text
	})

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ 🎬 SINGLE WEAPON PATH COMPLETE")
	print("║ Returning to caller with result")
	print("║ User should now see NextWeaponDialog")
	print("╚═══════════════════════════════════════════════════════════════")

	return result

func _process_continue_sequence(action: Dictionary) -> Dictionary:
	"""Process continuation to next weapon in sequential mode"""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ SHOOTING PHASE: _process_continue_sequence CALLED")
	print("║")

	var payload = action.get("payload", {})
	var updated_weapon_order = payload.get("weapon_order", [])

	print("║ CURRENT STATE:")
	print("║   resolution_state.current_index: ", resolution_state.get("current_index", 0))
	print("║   resolution_state.weapon_order.size(): ", resolution_state.get("weapon_order", []).size())
	print("║   resolution_state.completed_weapons: ", resolution_state.get("completed_weapons", []).size())
	print("║")
	print("║ ACTION PAYLOAD:")
	print("║   updated_weapon_order provided: ", not updated_weapon_order.is_empty())
	print("║   updated_weapon_order.size(): ", updated_weapon_order.size())
	if not updated_weapon_order.is_empty():
		print("║   First 3 weapons in updated order:")
		for i in range(min(3, updated_weapon_order.size())):
			print("║     %d: %s" % [i, updated_weapon_order[i].get("weapon_id", "UNKNOWN")])
	print("║")

	# If attacker provided a new weapon order (reordering), update it
	if not updated_weapon_order.is_empty():
		print("║ REORDERING: Attacker provided new weapon order")
		# Keep completed weapons, update remaining
		var current_index = resolution_state.get("current_index", 0)
		var original_order = resolution_state.get("weapon_order", [])

		print("║   current_index: ", current_index)
		print("║   original_order.size(): ", original_order.size())
		print("║   Keeping first %d completed weapons" % current_index)

		# Build new complete order: completed weapons + reordered remaining weapons
		var new_complete_order = []
		for i in range(current_index):
			if i < original_order.size():
				new_complete_order.append(original_order[i])
				print("║   Kept completed weapon %d: %s" % [i, original_order[i].get("weapon_id", "UNKNOWN")])

		print("║   Appending %d reordered weapons" % updated_weapon_order.size())
		new_complete_order.append_array(updated_weapon_order)

		print("║")
		print("║   NEW COMPLETE ORDER (%d weapons):" % new_complete_order.size())
		for i in range(min(5, new_complete_order.size())):
			var status = "✓ COMPLETED" if i < current_index else "⏳ PENDING"
			print("║     %d: %s %s" % [i, new_complete_order[i].get("weapon_id", "UNKNOWN"), status])
		if new_complete_order.size() > 5:
			print("║     ... and %d more weapons" % (new_complete_order.size() - 5))

		resolution_state.weapon_order = new_complete_order
		print("║   Updated resolution_state.weapon_order")
	else:
		print("║ NO REORDERING: Using existing weapon order")

	print("║")
	print("║ FINAL STATE BEFORE _resolve_next_weapon():")
	print("║   current_index: ", resolution_state.get("current_index", 0))
	print("║   weapon_order.size(): ", resolution_state.get("weapon_order", []).size())
	print("║   Next weapon to resolve: index %d" % resolution_state.get("current_index", 0))
	if resolution_state.get("current_index", 0) < resolution_state.get("weapon_order", []).size():
		var next_weapon = resolution_state.get("weapon_order", [])[resolution_state.get("current_index", 0)]
		print("║   Next weapon ID: %s" % next_weapon.get("weapon_id", "UNKNOWN"))
	print("║")
	print("║ Calling _resolve_next_weapon()...")
	print("╚═══════════════════════════════════════════════════════════════")

	var next_result = _resolve_next_weapon()

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ _resolve_next_weapon() RETURNED")
	print("║   success: ", next_result.get("success", false))
	print("║   log_text: ", next_result.get("log_text", ""))
	if next_result.has("sequential_pause"):
		print("║   sequential_pause: ", next_result.get("sequential_pause", false))
		print("║   weapons_remaining: ", next_result.get("weapons_remaining", 0))
	print("╚═══════════════════════════════════════════════════════════════")

	return next_result
