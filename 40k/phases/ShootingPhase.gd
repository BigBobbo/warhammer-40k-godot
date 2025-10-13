extends BasePhase
class_name ShootingPhase

# ShootingPhase - Full implementation of the Shooting phase following 10e rules
# Supports: Target selection, weapon assignment, attack resolution, damage allocation

signal unit_selected_for_shooting(unit_id: String)
signal targets_available(unit_id: String, eligible_targets: Dictionary)
signal shooting_begun(unit_id: String)
signal shooting_resolved(unit_id: String, target_unit_id: String, result: Dictionary)
signal dice_rolled(dice_data: Dictionary)
signal saves_required(save_data_list: Array)  # For interactive save resolution
signal weapon_order_required(assignments: Array)  # For weapon ordering when 2+ weapon types
signal next_weapon_confirmation_required(remaining_weapons: Array, current_index: int)  # For sequential resolution pause

# Shooting state tracking
var active_shooter_id: String = ""
var pending_assignments: Array = []  # Weapon assignments before confirmation
var confirmed_assignments: Array = []  # Assignments ready to resolve
var resolution_state: Dictionary = {}  # State for step-by-step resolution
var dice_log: Array = []
var units_that_shot: Array = []  # Track which units have completed shooting
var pending_save_data: Array = []  # Save data awaiting resolution

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
	
	_initialize_shooting()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")

	# CRITICAL: Close any open SaveDialog before exiting
	# This prevents stale dialogs from remaining open after phase change
	_close_save_dialogs()

	# CRITICAL: Clear all shooting visuals BEFORE controller is freed
	# This ensures range circles and other visuals are removed immediately
	_clear_shooting_visuals()

	# Clear shooting flags
	_clear_phase_flags()

	# Clear pending save data
	pending_save_data.clear()

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
		log_phase_message("No units available for shooting, completing phase")
		emit_signal("phase_completed")

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
	confirmed_assignments = pending_assignments.duplicate(true)
	pending_assignments.clear()

	emit_signal("shooting_begun", active_shooter_id)
	log_phase_message("Confirmed targets, ready to resolve shooting")

	# Check if we have multiple weapon types - if so, show weapon order dialog
	var unique_weapons = {}
	for assignment in confirmed_assignments:
		var weapon_id = assignment.get("weapon_id", "")
		unique_weapons[weapon_id] = true

	var weapon_count = unique_weapons.size()
	print("ShootingPhase: Confirmed %d assignments with %d unique weapon types" % [confirmed_assignments.size(), weapon_count])

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
	# Initialize resolution state
	resolution_state = {
		"current_assignment": 0,
		"phase": "ready"  # ready, hitting, wounding, saving, damage
	}

	# AUTO-RESOLVE: Immediately trigger shooting resolution
	var initial_result = create_result(true, [])

	# Call resolution directly
	var resolve_result = _process_resolve_shooting({})

	# Combine results
	if resolve_result.success:
		initial_result.changes.append_array(resolve_result.get("changes", []))
		initial_result["dice"] = resolve_result.get("dice", [])
		initial_result["log_text"] = resolve_result.get("log_text", "")
		# CRITICAL: Copy save_data_list for multiplayer sync
		if resolve_result.has("save_data_list"):
			initial_result["save_data_list"] = resolve_result.get("save_data_list", [])

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

	# Record hit/wound dice rolls
	var dice_data = result.get("dice", [])
	for dice_block in dice_data:
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Attack rolls complete"))

	# Check if any saves are needed
	var save_data_list = result.get("save_data_list", [])

	if save_data_list.is_empty():
		# No wounds caused - complete immediately
		var shooter_id = active_shooter_id  # Store before clearing
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]

		units_that_shot.append(active_shooter_id)
		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		# Emit signal to clear visuals
		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "No wounds caused", {"dice": dice_data})

	# Store save data and trigger interactive saves
	pending_save_data = save_data_list

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
	# Full shoot action - select shooter, assign targets, and resolve
	var unit_id = action.get("actor_unit_id", "")

	# Select shooter
	var select_result = _process_select_shooter({"actor_unit_id": unit_id})
	if not select_result.success:
		return select_result

	# Process assignments
	var assignments = action.get("payload", {}).get("assignments", [])
	for assignment in assignments:
		pending_assignments.append(assignment)

	# Confirm targets
	var confirm_result = _process_confirm_targets({})
	if not confirm_result.success:
		return confirm_result

	# Resolve shooting
	return _process_resolve_shooting({})

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

	# Record dice rolls
	var dice_data = result.get("dice", [])
	print("ShootingPhase: Dice blocks returned: %d" % dice_data.size())
	for dice_block in dice_data:
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Weapon attacks complete"))
	print("ShootingPhase: Log text: ", result.get("log_text", ""))

	# Check if saves are needed
	var save_data_list = result.get("save_data_list", [])
	print("ShootingPhase: save_data_list.size() = %d" % save_data_list.size())

	if save_data_list.is_empty():
		# No wounds - move to next weapon
		print("ShootingPhase: ⚠ No wounds caused by this weapon, moving to next weapon")
		resolution_state.completed_weapons.append({
			"weapon_id": weapon_id,
			"wounds": 0,
			"casualties": 0
		})
		resolution_state.current_index += 1
		print("ShootingPhase: Incremented current_index to %d" % resolution_state.current_index)
		print("ShootingPhase: Recursing to _resolve_next_weapon()...")
		print("========================================")

		# Continue with next weapon
		return _resolve_next_weapon()

	# Store save data and trigger interactive saves
	pending_save_data = save_data_list
	resolution_state.awaiting_saves = true

	# Add sequence context to save data for SaveDialog
	for save_data in save_data_list:
		save_data["sequence_context"] = {
			"current_weapon": current_index + 1,
			"total_weapons": weapon_order.size(),
			"weapon_name": RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		}

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
		"save_data_list": save_data_list
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

	# Check restriction flags
	if flags.get("cannot_shoot", false):
		return false

	if flags.get("has_shot", false):
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

	# Check if unit is in engagement range (MVP: units in engagement cannot shoot)
	if flags.get("in_engagement", false):
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

func _close_save_dialogs() -> void:
	"""Close any open SaveDialog when phase changes"""
	print("ShootingPhase: Closing any open SaveDialogs...")
	var root = get_tree().root
	if not root:
		return

	var dialogs_found = 0
	for child in root.get_children():
		# Check if this is a SaveDialog by checking its script path
		if child is AcceptDialog:
			var script = child.get_script()
			if script and script.resource_path == "res://scripts/SaveDialog.gd":
				print("ShootingPhase: Found open SaveDialog, closing it")
				child.hide()
				child.queue_free()
				dialogs_found += 1

	if dialogs_found > 0:
		print("ShootingPhase: Closed %d SaveDialog(s)" % dialogs_found)
	else:
		print("ShootingPhase: No SaveDialogs found")

func _clear_phase_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			unit.flags.erase("has_shot")

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

func _process_apply_saves(action: Dictionary) -> Dictionary:
	"""Process save results and apply damage"""
	var payload = action.get("payload", {})
	var save_results_list = payload.get("save_results_list", [])

	var all_diffs = []
	var total_casualties = 0

	# Process each save result (one per target unit)
	for i in range(save_results_list.size()):
		if i >= pending_save_data.size():
			break

		var save_result = save_results_list[i]
		var save_data = pending_save_data[i]

		# Apply damage using RulesEngine
		var damage_result = RulesEngine.apply_save_damage(
			save_result.save_results,
			save_data,
			game_state_snapshot
		)

		# Collect diffs
		all_diffs.append_array(damage_result.diffs)
		total_casualties += damage_result.casualties

		# Log results
		var target_name = save_data.get("target_unit_name", "Unknown")
		var saved_count = 0
		var failed_count = 0

		for sr in save_result.save_results:
			if sr.saved:
				saved_count += 1
			else:
				failed_count += 1

		log_phase_message("%s: %d saves passed, %d failed → %d casualties" % [
			target_name,
			saved_count,
			failed_count,
			damage_result.casualties
		])

	# Check if we're in sequential weapon resolution mode
	var mode = resolution_state.get("mode", "")
	var is_sequential = (mode == "sequential")

	if is_sequential:
		# Sequential mode - record results and PAUSE for attacker to confirm next weapon
		var current_index = resolution_state.get("current_index", 0)
		var weapon_order = resolution_state.get("weapon_order", [])

		print("========================================")
		print("ShootingPhase: APPLY_SAVES complete in sequential mode")
		print("ShootingPhase: current_index = %d, weapon_order.size() = %d" % [current_index, weapon_order.size()])

		if current_index < weapon_order.size():
			var weapon_id = weapon_order[current_index].get("weapon_id", "")
			print("ShootingPhase: Completed weapon %d: %s" % [current_index + 1, weapon_id])

			# Record completed weapon
			resolution_state.completed_weapons.append({
				"weapon_id": weapon_id,
				"wounds": pending_save_data.size() if not pending_save_data.is_empty() else 0,
				"casualties": total_casualties
			})

			# Move to next weapon INDEX
			resolution_state.current_index += 1
			resolution_state.awaiting_saves = false

			# Clear pending save data
			pending_save_data.clear()

			print("ShootingPhase: Moving to next weapon index: %d" % resolution_state.current_index)
			print("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index))

			# Check if there are more weapons to resolve
			if resolution_state.current_index < weapon_order.size():
				# PAUSE: Don't auto-continue to next weapon
				# Wait for attacker to confirm before continuing
				print("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon")
				print("ShootingPhase: Remaining weapons: ", weapon_order.size() - resolution_state.current_index)

				# Get remaining weapons for potential reordering
				var remaining_weapons = []
				for i in range(resolution_state.current_index, weapon_order.size()):
					remaining_weapons.append(weapon_order[i])

				# Emit signal to show confirmation dialog to attacker
				emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index)

				# Return success with pause indicator for multiplayer sync
				return create_result(true, all_diffs, "Weapon %d complete - awaiting next weapon confirmation" % (current_index + 1), {
					"sequential_pause": true,
					"current_weapon_index": resolution_state.current_index,
					"total_weapons": weapon_order.size(),
					"weapons_remaining": weapon_order.size() - resolution_state.current_index,
					"remaining_weapons": remaining_weapons
				})
			else:
				# All weapons complete
				print("ShootingPhase: All weapons in sequence complete!")
				print("========================================")
				# Fall through to normal completion below

	# Normal mode or end of sequential mode - mark shooter as done
	var shooter_id = active_shooter_id  # Store before clearing
	all_diffs.append({
		"op": "set",
		"path": "units.%s.flags.has_shot" % active_shooter_id,
		"value": true
	})

	units_that_shot.append(active_shooter_id)

	# Clear state
	pending_save_data.clear()
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()

	log_phase_message("Save resolution complete - %d total casualties" % total_casualties)

	# Emit resolved signal to clear visuals
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": total_casualties})

	return create_result(true, all_diffs, "Saves resolved")

func _process_continue_sequence(action: Dictionary) -> Dictionary:
	"""Process continuation to next weapon in sequential mode"""
	print("========================================")
	print("ShootingPhase: _process_continue_sequence CALLED")

	var payload = action.get("payload", {})
	var updated_weapon_order = payload.get("weapon_order", [])

	print("ShootingPhase: updated_weapon_order provided: ", not updated_weapon_order.is_empty())
	print("ShootingPhase: current resolution_state = ", resolution_state)

	# If attacker provided a new weapon order (reordering), update it
	if not updated_weapon_order.is_empty():
		print("ShootingPhase: Attacker reordered weapons, updating weapon_order")
		# Keep completed weapons, update remaining
		var current_index = resolution_state.get("current_index", 0)
		var original_order = resolution_state.get("weapon_order", [])

		# Build new complete order: completed weapons + reordered remaining weapons
		var new_complete_order = []
		for i in range(current_index):
			if i < original_order.size():
				new_complete_order.append(original_order[i])

		new_complete_order.append_array(updated_weapon_order)
		resolution_state.weapon_order = new_complete_order
		print("ShootingPhase: Updated weapon order with %d weapons" % new_complete_order.size())

	# Continue with next weapon
	print("ShootingPhase: Calling _resolve_next_weapon()...")
	var next_result = _resolve_next_weapon()
	print("ShootingPhase: _resolve_next_weapon returned = ", next_result)
	print("========================================")

	return next_result
