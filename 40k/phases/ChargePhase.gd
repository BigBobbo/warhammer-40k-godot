extends BasePhase
class_name ChargePhase

const BasePhase = preload("res://phases/BasePhase.gd")


# ChargePhase - Full implementation of the Charge phase following 10e rules
# Supports: Charge declarations, 2D6 charge rolls, movement validation, engagement range

signal unit_selected_for_charge(unit_id: String)
signal targets_declared(unit_id: String, target_ids: Array)
signal charge_targets_available(unit_id: String, eligible_targets: Dictionary)
signal charge_roll_made(unit_id: String, distance: int, dice: Array)
signal charge_path_preview(unit_id: String, per_model_paths: Dictionary)
signal charge_path_tools_enabled(unit_id: String, rolled_distance: int)
signal charge_validation_feedback(unit_id: String, validation_result: Dictionary)
signal charge_resolved(unit_id: String, success: bool, result: Dictionary)
signal charge_unit_completed(unit_id: String)
signal charge_unit_skipped(unit_id: String)
signal dice_rolled(dice_data: Dictionary)
signal command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)

const ENGAGEMENT_RANGE_INCHES: float = 1.0  # 10e standard ER
const CHARGE_RANGE_INCHES: float = 12.0     # Maximum charge declaration range

# Charge state tracking
var active_charges: Dictionary = {}     # unit_id -> charge_data
var pending_charges: Dictionary = {}    # units awaiting resolution
var dice_log: Array = []
var units_that_charged: Array = []     # Track which units have completed charges
var current_charging_unit = null       # Track which unit is actively charging
var completed_charges: Array = []      # Units that finished charging this phase
var failed_charge_attempts: Array = [] # Structured failure records for UI tooltips
var awaiting_reroll_decision: bool = false  # True when waiting for Command Re-roll response
var reroll_pending_unit_id: String = ""     # Unit awaiting reroll decision

# Failure category constants for structured error reporting
const FAIL_INSUFFICIENT_ROLL = "INSUFFICIENT_ROLL"
const FAIL_DISTANCE = "DISTANCE"
const FAIL_ENGAGEMENT = "ENGAGEMENT"
const FAIL_NON_TARGET_ER = "NON_TARGET_ER"
const FAIL_COHERENCY = "COHERENCY"
const FAIL_OVERLAP = "OVERLAP"
const FAIL_BASE_CONTACT = "BASE_CONTACT"

# Human-readable explanations for each failure category (teaches players the rules)
const FAIL_CATEGORY_TOOLTIPS = {
	FAIL_INSUFFICIENT_ROLL: "The 2D6 charge roll was too low for any model to reach engagement range (1\") of the declared targets. Try charging closer targets or units with fewer declared targets.",
	FAIL_DISTANCE: "A model's movement path exceeded the rolled charge distance. Each model can move at most the rolled distance in inches during a charge move.",
	FAIL_ENGAGEMENT: "The charging unit must end its move with at least one model within engagement range (1\") of EVERY declared target. If you declared multiple targets, you must reach all of them.",
	FAIL_NON_TARGET_ER: "No charging model may end within engagement range (1\") of an enemy unit that was NOT declared as a charge target. Plan your movement to avoid non-target enemies.",
	FAIL_COHERENCY: "All models in the unit must maintain unit coherency (within 2\" of at least one other model) after the charge move completes.",
	FAIL_OVERLAP: "Models cannot end their charge movement overlapping with other models (friendly or enemy). Reposition to avoid base overlaps.",
	FAIL_BASE_CONTACT: "If a charging model CAN make base-to-base contact with an enemy model while still satisfying all other charge conditions, it MUST do so (10e core rule).",
}

func _init():
	phase_type = GameStateData.Phase.CHARGE

func _on_phase_enter() -> void:
	log_phase_message("Entering Charge Phase")
	active_charges.clear()
	pending_charges.clear()
	dice_log.clear()
	units_that_charged.clear()
	current_charging_unit = null
	completed_charges.clear()
	failed_charge_attempts.clear()
	awaiting_reroll_decision = false
	reroll_pending_unit_id = ""

	_initialize_charge()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Charge Phase")
	# Clear charge flags
	_clear_phase_flags()

func _initialize_charge() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	var can_charge = false
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit):
			can_charge = true
			break

	if not can_charge:
		log_phase_message("No units available for charging, ready to end phase")
		# Don't auto-complete - wait for END_CHARGE action

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"SELECT_CHARGE_UNIT":
			return _validate_select_charge_unit(action)
		"DECLARE_CHARGE":
			return _validate_declare_charge(action)
		"CHARGE_ROLL":
			return _validate_charge_roll(action)
		"APPLY_CHARGE_MOVE":
			return _validate_apply_charge_move(action)
		"COMPLETE_UNIT_CHARGE":
			return _validate_complete_unit_charge(action)
		"SKIP_CHARGE":
			return _validate_skip_charge(action)
		"END_CHARGE":
			return _validate_end_charge(action)
		"USE_COMMAND_REROLL":
			return _validate_command_reroll(action)
		"DECLINE_COMMAND_REROLL":
			return _validate_command_reroll(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"SELECT_CHARGE_UNIT":
			return _process_select_charge_unit(action)
		"DECLARE_CHARGE":
			return _process_declare_charge(action)
		"CHARGE_ROLL":
			return _process_charge_roll(action)
		"APPLY_CHARGE_MOVE":
			return _process_apply_charge_move(action)
		"COMPLETE_UNIT_CHARGE":
			return _process_complete_unit_charge(action)
		"SKIP_CHARGE":
			return _process_skip_charge(action)
		"END_CHARGE":
			return _process_end_charge(action)
		"USE_COMMAND_REROLL":
			return _process_use_command_reroll(action)
		"DECLINE_COMMAND_REROLL":
			return _process_decline_command_reroll(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_select_charge_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if not _can_unit_charge(unit):
		return {"valid": false, "errors": ["Unit cannot charge"]}
	
	if unit_id in completed_charges:
		return {"valid": false, "errors": ["Unit has already charged this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_complete_unit_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if unit_id != current_charging_unit:
		return {"valid": false, "errors": ["Unit is not currently charging"]}
	
	return {"valid": true, "errors": []}

func _validate_declare_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var target_ids = action.get("payload", {}).get("target_unit_ids", [])
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if target_ids.is_empty():
		return {"valid": false, "errors": ["Missing target_unit_ids"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if not _can_unit_charge(unit):
		return {"valid": false, "errors": ["Unit cannot charge"]}
	
	if unit_id in completed_charges:
		return {"valid": false, "errors": ["Unit has already charged this phase"]}
	
	# Validate each target
	for target_id in target_ids:
		var target_unit = get_unit(target_id)
		if target_unit.is_empty():
			return {"valid": false, "errors": ["Target unit not found: " + target_id]}
		
		if target_unit.get("owner", 0) == get_current_player():
			return {"valid": false, "errors": ["Cannot charge own units"]}
		
		# Check 12" range
		if not _is_target_within_charge_range(unit_id, target_id):
			return {"valid": false, "errors": ["Target beyond 12\" charge range: " + target_id]}
	
	return {"valid": true, "errors": []}

func _validate_charge_roll(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not pending_charges.has(unit_id):
		return {"valid": false, "errors": ["No charge declared for unit"]}
	
	return {"valid": true, "errors": []}

func _validate_apply_charge_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if per_model_paths.is_empty():
		return {"valid": false, "errors": ["Missing per_model_paths"]}
	
	if not pending_charges.has(unit_id):
		return {"valid": false, "errors": ["No charge roll made for unit"]}
	
	var charge_data = pending_charges[unit_id]
	if not charge_data.has("distance"):
		return {"valid": false, "errors": ["No charge distance available"]}
	
	# Validate all movement constraints
	var validation = _validate_charge_movement_constraints(unit_id, per_model_paths, charge_data)
	return validation

func _validate_skip_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit_id in completed_charges:
		return {"valid": false, "errors": ["Unit has already acted this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_end_charge(action: Dictionary) -> Dictionary:
	# Can always end the phase
	return {"valid": true, "errors": []}

# Processing Methods

func _process_select_charge_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	current_charging_unit = unit_id
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Selected %s for charging" % unit_name)
	
	emit_signal("unit_selected_for_charge", unit_id)
	
	return create_result(true, [])

func _process_complete_unit_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")

	completed_charges.append(unit_id)
	current_charging_unit = null

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Completed charge sequence for %s" % unit_name)

	emit_signal("charge_unit_completed", unit_id)

	# Don't end phase - allow selection of next unit
	return create_result(true, [])

func _process_declare_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var target_ids = action.get("payload", {}).get("target_unit_ids", [])
	
	# Store charge declaration
	pending_charges[unit_id] = {
		"targets": target_ids,
		"declared_at": Time.get_unix_time_from_system()
	}
	
	# Get eligible targets for UI
	var eligible_targets = _get_eligible_targets_for_unit(unit_id)
	
	emit_signal("unit_selected_for_charge", unit_id)
	emit_signal("targets_declared", unit_id, target_ids)
	emit_signal("charge_targets_available", unit_id, eligible_targets)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var target_names = []
	for target_id in target_ids:
		var target = get_unit(target_id)
		target_names.append(target.get("meta", {}).get("name", target_id))
	
	log_phase_message("%s declared charge against %s" % [unit_name, ", ".join(target_names)])
	
	return create_result(true, [])

func _process_charge_roll(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var charge_data = pending_charges[unit_id]

	# Roll 2D6 for charge distance
	var rng = RulesEngine.RNGService.new()
	var rolls = rng.roll_d6(2)
	var total_distance = rolls[0] + rolls[1]

	# Store rolled distance
	charge_data.distance = total_distance
	charge_data.dice_rolls = rolls

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var target_ids = charge_data.targets

	log_phase_message("Charge roll: 2D6 = %d (%d + %d)" % [total_distance, rolls[0], rolls[1]])

	# Check if Command Re-roll is available for the charging player
	var current_player = get_current_player()
	var strat_manager = get_node_or_null("/root/StratagemManager")
	var reroll_available = false
	if strat_manager:
		var reroll_check = strat_manager.is_command_reroll_available(current_player)
		reroll_available = reroll_check.available

	if reroll_available:
		# Pause resolution — offer Command Re-roll to player
		awaiting_reroll_decision = true
		reroll_pending_unit_id = unit_id

		var min_distance = _get_min_distance_to_any_target(unit_id, target_ids)
		var needed = max(0.0, min_distance - ENGAGEMENT_RANGE_INCHES)
		var context_text = "Need %.1f\" to reach engagement range (nearest target %.1f\" away)" % [needed, min_distance]

		var roll_context = {
			"roll_type": "charge_roll",
			"original_rolls": rolls,
			"total": total_distance,
			"unit_id": unit_id,
			"unit_name": unit_name,
			"context_text": context_text,
			"min_distance": min_distance,
		}

		print("ChargePhase: Command Re-roll available for %s — pausing for player decision" % unit_name)
		emit_signal("command_reroll_opportunity", unit_id, current_player, roll_context)

		# Return the initial roll result with reroll_available flag
		# The actual resolution will happen after USE/DECLINE action
		return create_result(true, [], "", {
			"dice": [{"context": "charge_roll", "unit_id": unit_id, "unit_name": unit_name, "rolls": rolls, "total": total_distance, "targets": target_ids}],
			"awaiting_reroll": true,
		})

	# No Command Re-roll available — resolve immediately
	return _resolve_charge_roll(unit_id)

func _resolve_charge_roll(unit_id: String) -> Dictionary:
	"""Resolve the charge roll after any reroll decision. Uses the current dice stored in pending_charges."""
	var charge_data = pending_charges[unit_id]
	var rolls = charge_data.dice_rolls
	var total_distance = charge_data.distance
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var target_ids = charge_data.targets

	# Server-side feasibility check: can any model reach engagement range?
	var roll_sufficient = _is_charge_roll_sufficient(unit_id, total_distance)
	var min_distance = _get_min_distance_to_any_target(unit_id, target_ids)

	# Build dice result with success/failure flag so clients don't need to recompute
	var dice_result = {
		"context": "charge_roll",
		"unit_id": unit_id,
		"unit_name": unit_name,
		"rolls": rolls,
		"total": total_distance,
		"targets": target_ids,
		"charge_failed": not roll_sufficient,
		"min_distance": min_distance,
	}
	dice_log.append(dice_result)

	if not roll_sufficient:
		# Charge roll failed — record structured failure, clean up state, broadcast
		print("ChargePhase: Charge roll INSUFFICIENT for %s (rolled %d, min dist %.1f\")" % [unit_name, total_distance, min_distance])
		record_insufficient_roll_failure(unit_id, total_distance, rolls, target_ids, min_distance)

		# Clean up phase state so unit can't retry
		units_that_charged.append(unit_id)
		completed_charges.append(unit_id)
		pending_charges.erase(unit_id)
		current_charging_unit = null

		# Build failure data for the result (broadcast to clients via NetworkManager)
		var failure_record = failed_charge_attempts[-1]  # The one we just recorded

		# Emit signals — charge_roll_made first (for dice log on host), then charge_resolved
		emit_signal("charge_roll_made", unit_id, total_distance, rolls)
		emit_signal("dice_rolled", dice_result)
		emit_signal("charge_resolved", unit_id, false, {
			"reason": failure_record.errors[0] if failure_record.errors.size() > 0 else "Insufficient roll",
			"failure_record": failure_record,
		})

		return create_result(true, [], "", {
			"dice": [dice_result],
			"charge_failed": true,
			"failure_record": failure_record,
			"min_distance": min_distance,
		})

	# Roll sufficient — emit normal signals and allow movement
	print("ChargePhase: Charge roll SUFFICIENT for %s (rolled %d)" % [unit_name, total_distance])
	emit_signal("charge_roll_made", unit_id, total_distance, rolls)
	emit_signal("charge_path_tools_enabled", unit_id, total_distance)
	emit_signal("dice_rolled", dice_result)

	return create_result(true, [], "", {
		"dice": [dice_result],
		"charge_failed": false,
	})

func _validate_command_reroll(action: Dictionary) -> Dictionary:
	"""Validate USE_COMMAND_REROLL or DECLINE_COMMAND_REROLL action."""
	if not awaiting_reroll_decision:
		return {"valid": false, "errors": ["Not awaiting a Command Re-roll decision"]}
	return {"valid": true, "errors": []}

func _process_use_command_reroll(action: Dictionary) -> Dictionary:
	"""Process USE_COMMAND_REROLL: re-roll the charge dice and resolve."""
	var unit_id = reroll_pending_unit_id
	awaiting_reroll_decision = false
	reroll_pending_unit_id = ""

	if not pending_charges.has(unit_id):
		return create_result(false, [], "No pending charge for reroll")

	var charge_data = pending_charges[unit_id]
	var old_rolls = charge_data.dice_rolls.duplicate()
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var current_player = get_current_player()

	# Execute the stratagem (deduct CP, record usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var roll_context = {
			"roll_type": "charge_roll",
			"original_rolls": old_rolls,
			"unit_name": unit_name,
		}
		var strat_result = strat_manager.execute_command_reroll(current_player, unit_id, roll_context)
		if not strat_result.success:
			print("ChargePhase: Command Re-roll failed: %s" % strat_result.get("error", ""))
			# Fall through to resolve with original roll
			return _resolve_charge_roll(unit_id)

	# Re-roll the 2D6
	var rng = RulesEngine.RNGService.new()
	var new_rolls = rng.roll_d6(2)
	var new_total = new_rolls[0] + new_rolls[1]

	# Update the charge data with new rolls
	charge_data.distance = new_total
	charge_data.dice_rolls = new_rolls

	log_phase_message("COMMAND RE-ROLL: Charge re-rolled from %d (%s) → %d (%d + %d)" % [
		old_rolls[0] + old_rolls[1], str(old_rolls), new_total, new_rolls[0], new_rolls[1]
	])

	print("ChargePhase: COMMAND RE-ROLL — %s charge re-rolled: %s → %s (total %d → %d)" % [
		unit_name, str(old_rolls), str(new_rolls), old_rolls[0] + old_rolls[1], new_total
	])

	# Now resolve the charge with the new roll
	return _resolve_charge_roll(unit_id)

func _process_decline_command_reroll(action: Dictionary) -> Dictionary:
	"""Process DECLINE_COMMAND_REROLL: resolve charge with original dice."""
	var unit_id = reroll_pending_unit_id
	awaiting_reroll_decision = false
	reroll_pending_unit_id = ""

	if not pending_charges.has(unit_id):
		return create_result(false, [], "No pending charge for reroll decline")

	print("ChargePhase: Command Re-roll DECLINED for %s — resolving with original roll" % unit_id)

	# Resolve with the original roll
	return _resolve_charge_roll(unit_id)

func _process_apply_charge_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})
	var per_model_rotations = payload.get("per_model_rotations", {})

	# Enhanced validation - check for empty per_model_paths
	if per_model_paths.is_empty():
		print("ERROR: No model paths provided for charge movement")
		return create_result(false, [], "No model paths provided")

	if not pending_charges.has(unit_id):
		print("ERROR: No pending charge data found for unit ", unit_id)
		return create_result(false, [], "No pending charge data found")

	var charge_data = pending_charges[unit_id]

	# Final validation
	var validation = _validate_charge_movement_constraints(unit_id, per_model_paths, charge_data)
	if not validation.valid:
		# Charge fails - no movement applied
		var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
		log_phase_message("Charge failed for %s: %s" % [unit_name, validation.errors[0]])

		# Build structured failure record
		var categorized = validation.get("categorized_errors", [])
		var primary_category = categorized[0].category if categorized.size() > 0 else "UNKNOWN"
		var failure_record = {
			"unit_id": unit_id,
			"unit_name": unit_name,
			"target_ids": charge_data.targets,
			"roll": charge_data.distance,
			"dice": charge_data.get("dice_rolls", []),
			"timestamp": Time.get_unix_time_from_system(),
			"primary_category": primary_category,
			"categorized_errors": categorized,
			"errors": validation.errors,
		}
		failed_charge_attempts.append(failure_record)
		print("ChargePhase: Recorded structured failure - [%s] %s" % [primary_category, validation.errors[0]])

		# Mark as charged (attempted) but unsuccessful
		units_that_charged.append(unit_id)
		pending_charges.erase(unit_id)

		emit_signal("charge_resolved", unit_id, false, {
			"reason": validation.errors[0],
			"failure_record": failure_record,
		})
		return create_result(true, [])
	
	# Apply successful charge movement
	var changes = []

	# Update model positions
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]

		if not (path is Array and path.size() > 0):
			print("WARNING: Invalid path for model ", model_id, " - skipping")
			continue

		var final_pos = path[-1]  # Last position in path
		var model_index = _get_model_index(unit_id, model_id)

		if model_index < 0:
			print("ERROR: Invalid model_index for ", model_id, " - model not found in unit")
			continue

		var change = {
			"op": "set",
			"path": "units.%s.models.%d.position" % [unit_id, model_index],
			"value": {"x": final_pos[0], "y": final_pos[1]}
		}
		changes.append(change)

		# Also apply rotation if provided
		if per_model_rotations.has(model_id):
			var rotation = per_model_rotations[model_id]
			var rotation_change = {
				"op": "set",
				"path": "units.%s.models.%d.rotation" % [unit_id, model_index],
				"value": rotation
			}
			changes.append(rotation_change)
	
	# Mark unit as charged and grant Fights First
	changes.append({
		"op": "set",
		"path": "units.%s.flags.charged_this_turn" % unit_id,
		"value": true
	})
	changes.append({
		"op": "set",
		"path": "units.%s.flags.fights_first" % unit_id,
		"value": true
	})

	# Mark target units as "has been charged" (10e rule: target units gain this
	# status until end of turn, relevant for ability interactions)
	for target_id in charge_data.targets:
		changes.append({
			"op": "set",
			"path": "units.%s.flags.has_been_charged" % target_id,
			"value": true
		})

	# Clean up charge state
	units_that_charged.append(unit_id)
	pending_charges.erase(unit_id)
	# Don't mark as completed yet - wait for COMPLETE_UNIT_CHARGE action
	
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("Successful charge: %s moved into engagement range" % unit_name)

	emit_signal("charge_resolved", unit_id, true, {"distance": charge_data.distance})

	return create_result(true, changes)

func _process_skip_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")

	units_that_charged.append(unit_id)
	completed_charges.append(unit_id)
	current_charging_unit = null

	# Clear any pending charge for this unit
	if pending_charges.has(unit_id):
		pending_charges.erase(unit_id)

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Skipped charge for %s" % unit_name)

	emit_signal("charge_unit_skipped", unit_id)

	return create_result(true, [])

func _process_end_charge(action: Dictionary) -> Dictionary:
	log_phase_message("Ending Charge Phase")
	emit_signal("phase_completed")
	return create_result(true, [])

# Helper Methods

func _can_unit_charge(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})
	
	# Check if unit is deployed
	if not (status == GameStateData.UnitStatus.DEPLOYED or 
			status == GameStateData.UnitStatus.MOVED or 
			status == GameStateData.UnitStatus.SHOT):
		return false
	
	# Check restriction flags
	if flags.get("cannot_charge", false):
		return false
	
	if flags.get("advanced", false):
		return false
	
	if flags.get("fell_back", false):
		return false
	
	if flags.get("charged_this_turn", false):
		return false
	
	# Check if already in engagement range (cannot declare charges)
	if _is_unit_in_engagement_range(unit):
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

func _is_unit_in_engagement_range(unit: Dictionary) -> bool:
	var unit_id = unit.get("id", "")
	var models = unit.get("models", [])
	var current_player = get_current_player()
	var all_units = game_state_snapshot.get("units", {})

	for model in models:
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue

		# Check against all enemy models using shape-aware distance
		for enemy_unit_id in all_units:
			var enemy_unit = all_units[enemy_unit_id]
			if enemy_unit.get("owner", 0) == current_player:
				continue  # Skip friendly units

			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue

				var enemy_pos = _get_model_position(enemy_model)
				if enemy_pos == null:
					continue

				# Use shape-aware engagement range check
				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, ENGAGEMENT_RANGE_INCHES):
					return true

	return false

func _is_target_within_charge_range(unit_id: String, target_id: String) -> bool:
	var unit = get_unit(unit_id)
	var target = get_unit(target_id)

	if unit.is_empty() or target.is_empty():
		return false

	# Find closest edge-to-edge distance between any models using shape-aware calculations
	var min_distance = INF

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue

		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position(target_model)
			if target_pos == null:
				continue

			# Use shape-aware distance calculation
			var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)

			min_distance = min(min_distance, distance_inches)

	return min_distance <= CHARGE_RANGE_INCHES

func _get_eligible_targets_for_unit(unit_id: String) -> Dictionary:
	var eligible = {}
	var current_player = get_current_player()
	var all_units = game_state_snapshot.get("units", {})
	
	for target_id in all_units:
		var target_unit = all_units[target_id]
		if target_unit.get("owner", 0) != current_player:  # Enemy unit
			if _is_target_within_charge_range(unit_id, target_id):
				eligible[target_id] = {
					"name": target_unit.get("meta", {}).get("name", target_id),
					"distance": _get_min_distance_to_target(unit_id, target_id)
				}
	
	return eligible

func _get_min_distance_to_target(unit_id: String, target_id: String) -> float:
	var unit = get_unit(unit_id)
	var target = get_unit(target_id)
	var min_distance = INF

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue

		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position(target_model)
			if target_pos == null:
				continue

			# Use shape-aware edge-to-edge distance, consistent with _is_target_within_charge_range
			var distance = Measurement.model_to_model_distance_inches(model, target_model)
			min_distance = min(min_distance, distance)

	return min_distance

func _validate_charge_movement_constraints(unit_id: String, per_model_paths: Dictionary, charge_data: Dictionary) -> Dictionary:
	var errors = []
	var categorized_errors = []  # Array of {category, detail} for structured reporting
	var rolled_distance = charge_data.distance
	var target_ids = charge_data.targets

	# 1. Validate path distances
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() >= 2:
			var path_distance = Measurement.distance_polyline_inches(path)
			if path_distance > rolled_distance:
				var err = "Model %s path exceeds charge distance: %.1f\" > %d\"" % [model_id, path_distance, rolled_distance]
				errors.append(err)
				categorized_errors.append({"category": FAIL_DISTANCE, "detail": err})

	# 2. Validate no model overlaps
	var overlap_validation = _validate_no_model_overlaps(unit_id, per_model_paths)
	if not overlap_validation.valid:
		errors.append_array(overlap_validation.errors)
		for err in overlap_validation.errors:
			categorized_errors.append({"category": FAIL_OVERLAP, "detail": err})

	# 3. Validate engagement range with ALL targets
	var engagement_validation = _validate_engagement_range_constraints(unit_id, per_model_paths, target_ids)
	if not engagement_validation.valid:
		errors.append_array(engagement_validation.errors)
		for err in engagement_validation.errors:
			# Distinguish between "must reach target" vs "too close to non-target"
			if "non-target" in err.to_lower():
				categorized_errors.append({"category": FAIL_NON_TARGET_ER, "detail": err})
			else:
				categorized_errors.append({"category": FAIL_ENGAGEMENT, "detail": err})

	# 4. Validate unit coherency
	var coherency_validation = _validate_unit_coherency_for_charge(unit_id, per_model_paths)
	if not coherency_validation.valid:
		errors.append_array(coherency_validation.errors)
		for err in coherency_validation.errors:
			categorized_errors.append({"category": FAIL_COHERENCY, "detail": err})

	# 5. Validate base-to-base if possible
	var base_to_base_validation = _validate_base_to_base_possible(unit_id, per_model_paths, target_ids)
	if not base_to_base_validation.valid:
		errors.append_array(base_to_base_validation.errors)
		for err in base_to_base_validation.errors:
			categorized_errors.append({"category": FAIL_BASE_CONTACT, "detail": err})

	return {"valid": errors.is_empty(), "errors": errors, "categorized_errors": categorized_errors}

func _validate_engagement_range_constraints(unit_id: String, per_model_paths: Dictionary, target_ids: Array) -> Dictionary:
	var errors = []
	var current_player = get_current_player()
	var all_units = game_state_snapshot.get("units", {})

	# Check that unit ends within ER of ALL targets
	for target_id in target_ids:
		var target_unit = all_units.get(target_id, {})
		if target_unit.is_empty():
			continue

		var unit_in_er_of_target = false

		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit(unit_id, model_id)

				# Create a temporary model dict with the final position for shape-aware checks
				var model_at_final_pos = model.duplicate()
				model_at_final_pos["position"] = final_pos

				# Check if this model is in ER of any target model using shape-aware distance
				for target_model in target_unit.get("models", []):
					if not target_model.get("alive", true):
						continue

					var target_pos = _get_model_position(target_model)
					if target_pos == null:
						continue

					if Measurement.is_in_engagement_range_shape_aware(model_at_final_pos, target_model, ENGAGEMENT_RANGE_INCHES):
						unit_in_er_of_target = true
						break

				if unit_in_er_of_target:
					break

		if not unit_in_er_of_target:
			var target_name = target_unit.get("meta", {}).get("name", target_id)
			errors.append("Must end within engagement range of all targets: " + target_name)

	# Check that unit does NOT end in ER of non-target enemies
	for enemy_unit_id in all_units:
		var enemy_unit = all_units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == current_player:
			continue  # Skip friendly

		if enemy_unit_id in target_ids:
			continue  # Skip declared targets

		# Check if any charging model ends in ER of this non-target
		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit(unit_id, model_id)

				# Create a temporary model dict with the final position for shape-aware checks
				var model_at_final_pos = model.duplicate()
				model_at_final_pos["position"] = final_pos

				for enemy_model in enemy_unit.get("models", []):
					if not enemy_model.get("alive", true):
						continue

					var enemy_pos = _get_model_position(enemy_model)
					if enemy_pos == null:
						continue

					if Measurement.is_in_engagement_range_shape_aware(model_at_final_pos, enemy_model, ENGAGEMENT_RANGE_INCHES):
						var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
						errors.append("Cannot end within engagement range of non-target unit: " + enemy_name)
						break

	return {"valid": errors.is_empty(), "errors": errors}

func _validate_unit_coherency_for_charge(unit_id: String, per_model_paths: Dictionary) -> Dictionary:
	var errors = []

	# Build model dicts with final positions for shape-aware distance checks
	var final_models = []
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() > 0:
			var model = _get_model_in_unit(unit_id, model_id)
			var model_at_final = model.duplicate()
			model_at_final["position"] = Vector2(path[-1][0], path[-1][1])
			final_models.append(model_at_final)

	if final_models.size() < 2:
		return {"valid": true, "errors": []}  # Single model or no movement

	# Check that each model is within 2" of at least one other model (edge-to-edge)
	for i in range(final_models.size()):
		var has_nearby_model = false

		for j in range(final_models.size()):
			if i == j:
				continue

			var distance = Measurement.model_to_model_distance_inches(final_models[i], final_models[j])

			if distance <= 2.0:
				has_nearby_model = true
				break

		if not has_nearby_model:
			errors.append("Unit coherency broken: model %d too far from other models" % i)

	return {"valid": errors.is_empty(), "errors": errors}

func _validate_base_to_base_possible(unit_id: String, per_model_paths: Dictionary, target_ids: Array) -> Dictionary:
	# For MVP, we'll implement a simplified check
	# In full implementation, this would check if base-to-base contact is achievable
	# and required when all other constraints are satisfied
	return {"valid": true, "errors": []}

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _get_model_in_unit(unit_id: String, model_id: String) -> Dictionary:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id:
			return model
	return {}

func _get_model_index(unit_id: String, model_id: String) -> int:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	for i in range(models.size()):
		if models[i].get("id", "") == model_id:
			return i
	return -1

func _clear_phase_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			unit.flags.erase("charged_this_turn")
			unit.flags.erase("fights_first")

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	# Units that can declare charges
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit) and unit_id not in completed_charges:
			
			# If no charge declared, can declare charge
			if not pending_charges.has(unit_id):
				var eligible_targets = _get_eligible_targets_for_unit(unit_id)
				for target_id in eligible_targets:
					actions.append({
						"type": "DECLARE_CHARGE",
						"actor_unit_id": unit_id,
						"payload": {"target_unit_ids": [target_id]},
						"description": "Declare charge: %s -> %s" % [unit.get("meta", {}).get("name", unit_id), eligible_targets[target_id].name]
					})
				
				# Skip charge option
				actions.append({
					"type": "SKIP_CHARGE",
					"actor_unit_id": unit_id,
					"description": "Skip charge for " + unit.get("meta", {}).get("name", unit_id)
				})
			
			# If charge declared but no roll made, can roll
			elif pending_charges.has(unit_id) and not pending_charges[unit_id].has("distance"):
				actions.append({
					"type": "CHARGE_ROLL",
					"actor_unit_id": unit_id,
					"description": "Roll 2D6 for charge distance"
				})
			
			# If roll made, can apply movement (handled by UI typically)
	
	# Always can end phase
	actions.append({
		"type": "END_CHARGE",
		"description": "End Charge Phase"
	})
	
	return actions

func _should_complete_phase() -> bool:
	# Check if all eligible units have charged or been skipped
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit) and unit_id not in completed_charges:
			return false
	
	return true

func get_dice_log() -> Array:
	return dice_log

func _validate_no_model_overlaps(unit_id: String, per_model_paths: Dictionary) -> Dictionary:
	var errors = []
	var all_units = game_state_snapshot.get("units", {})

	# Get all models from the charging unit
	var unit = all_units.get(unit_id, {})
	var models = unit.get("models", [])

	# Check each model's final position
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var final_pos = Vector2(path[-1][0], path[-1][1])
		var model = _get_model_in_unit(unit_id, model_id)
		if model.is_empty():
			continue

		# Build model dict with final position
		var check_model = model.duplicate()
		check_model["position"] = final_pos

		# Check against all other models (both friendly and enemy)
		for check_unit_id in all_units:
			var check_unit = all_units[check_unit_id]
			var check_models = check_unit.get("models", [])

			for i in range(check_models.size()):
				var other_model = check_models[i]
				var other_model_id = other_model.get("id", "m%d" % (i+1))

				# Skip self
				if check_unit_id == unit_id and other_model_id == model_id:
					continue

				# Skip dead models
				if not other_model.get("alive", true):
					continue

				# Get the current position of the other model
				# For other charging models in same unit, use their final positions
				var other_position = _get_model_position(other_model)
				if check_unit_id == unit_id and per_model_paths.has(other_model_id):
					var other_path = per_model_paths[other_model_id]
					if other_path is Array and other_path.size() > 0:
						other_position = Vector2(other_path[-1][0], other_path[-1][1])

				if other_position == null:
					continue

				# Build other model dict with correct position
				var other_model_check = other_model.duplicate()
				other_model_check["position"] = other_position

				# Check for overlap
				if Measurement.models_overlap(check_model, other_model_check):
					errors.append("Model %s would overlap with %s/%s" % [model_id, check_unit_id, other_model_id])

	return {"valid": errors.is_empty(), "errors": errors}

func get_pending_charges() -> Dictionary:
	return pending_charges

func get_units_that_charged() -> Array:
	return units_that_charged

func get_eligible_charge_units() -> Array:
	var eligible = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit) and unit_id not in completed_charges:
			eligible.append(unit_id)
	
	return eligible

func get_completed_charges() -> Array:
	return completed_charges

func get_failed_charge_attempts() -> Array:
	return failed_charge_attempts

func get_failure_category_tooltip(category: String) -> String:
	return FAIL_CATEGORY_TOOLTIPS.get(category, "Charge failed due to an unknown constraint.")

func record_insufficient_roll_failure(unit_id: String, rolled_distance: int, dice: Array, target_ids: Array, min_distance: float) -> void:
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var detail = "Rolled %d\" but nearest target is %.1f\" away (need to close to within 1\" engagement range)" % [rolled_distance, min_distance]
	var failure_record = {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"target_ids": target_ids,
		"roll": rolled_distance,
		"dice": dice,
		"timestamp": Time.get_unix_time_from_system(),
		"primary_category": FAIL_INSUFFICIENT_ROLL,
		"categorized_errors": [{"category": FAIL_INSUFFICIENT_ROLL, "detail": detail}],
		"errors": [detail],
	}
	failed_charge_attempts.append(failure_record)
	print("ChargePhase: Recorded insufficient roll failure - [INSUFFICIENT_ROLL] %s" % detail)

func has_pending_charge(unit_id: String) -> bool:
	return pending_charges.has(unit_id)

func _is_charge_roll_sufficient(unit_id: String, rolled_distance: int) -> bool:
	"""Check if the rolled distance is sufficient for at least one model to reach
	engagement range (1") of at least one target model in any declared target unit.
	This is the server-side feasibility check performed immediately after the roll."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false

	if not pending_charges.has(unit_id):
		return false

	var target_ids = pending_charges[unit_id].get("targets", [])
	if target_ids.is_empty():
		return false

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		for target_id in target_ids:
			var target_unit = get_unit(target_id)
			if target_unit.is_empty():
				continue

			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue

				# Edge-to-edge distance in inches, minus engagement range
				var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
				var distance_to_close = distance_inches - ENGAGEMENT_RANGE_INCHES
				if distance_to_close <= rolled_distance:
					return true

	return false

func _get_min_distance_to_any_target(unit_id: String, target_ids: Array) -> float:
	"""Get the minimum edge-to-edge distance (inches) from any charging model to any target model."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return INF

	var min_dist = INF
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		for target_id in target_ids:
			var target_unit = get_unit(target_id)
			if target_unit.is_empty():
				continue
			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue
				var dist = Measurement.model_to_model_distance_inches(model, target_model)
				min_dist = min(min_dist, dist)

	return min_dist

func get_charge_distance(unit_id: String) -> int:
	if pending_charges.has(unit_id) and pending_charges[unit_id].has("distance"):
		return pending_charges[unit_id].distance
	return 0

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
