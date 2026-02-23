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
signal overwatch_opportunity(charging_unit_id: String, defending_player: int, eligible_units: Array)
signal overwatch_result(shooter_unit_id: String, target_unit_id: String, result: Dictionary)
signal heroic_intervention_opportunity(player: int, eligible_units: Array, charging_unit_id: String)
signal fire_overwatch_opportunity(player: int, eligible_units: Array, enemy_unit_id: String)
signal tank_shock_opportunity(player: int, vehicle_unit_id: String, eligible_targets: Array)
signal tank_shock_result(vehicle_unit_id: String, target_unit_id: String, result: Dictionary)
signal ability_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)

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
var awaiting_ability_reroll: bool = false   # True when waiting for ability reroll response (e.g. Swift Onslaught)
var ability_reroll_unit_id: String = ""     # Unit awaiting ability reroll decision
var ability_reroll_used: bool = false       # True if ability reroll was used for current charge (prevents Command Re-roll)
# Fire Overwatch state tracking (T3-11 + remote PR)
var awaiting_overwatch_decision: bool = false  # True when waiting for Fire Overwatch response (remote)
var overwatch_charging_unit_id: String = ""   # The unit that declared the charge (overwatch target, remote)
var awaiting_fire_overwatch: bool = false      # True when waiting for Fire Overwatch (local T3-11)
var fire_overwatch_player: int = 0             # Defending player being offered Overwatch
var fire_overwatch_enemy_unit_id: String = ""  # The enemy unit that triggered the opportunity
var fire_overwatch_eligible_units: Array = []  # Units eligible for Overwatch

# Heroic Intervention state tracking
var awaiting_heroic_intervention: bool = false  # True when waiting for Heroic Intervention response
var heroic_intervention_player: int = 0  # Defending player being offered HI
var heroic_intervention_charging_unit_id: String = ""  # The enemy unit that just charged
var heroic_intervention_unit_id: String = ""  # Unit selected for HI (set on USE)
var heroic_intervention_pending_charge: Dictionary = {}  # Pending charge data for HI unit

# Tank Shock state tracking
var awaiting_tank_shock: bool = false  # True when waiting for Tank Shock response
var tank_shock_vehicle_unit_id: String = ""  # The VEHICLE unit that just charged
var tank_shock_pending_changes: Array = []  # Charge move changes to return after Tank Shock resolves

# Failure category constants for structured error reporting
const FAIL_INSUFFICIENT_ROLL = "INSUFFICIENT_ROLL"
const FAIL_DISTANCE = "DISTANCE"
const FAIL_ENGAGEMENT = "ENGAGEMENT"
const FAIL_NON_TARGET_ER = "NON_TARGET_ER"
const FAIL_COHERENCY = "COHERENCY"
const FAIL_OVERLAP = "OVERLAP"
const FAIL_BASE_CONTACT = "BASE_CONTACT"
const FAIL_DIRECTION = "DIRECTION"

# Human-readable explanations for each failure category (teaches players the rules)
const FAIL_CATEGORY_TOOLTIPS = {
	FAIL_INSUFFICIENT_ROLL: "The 2D6 charge roll was too low for any model to reach engagement range (1\") of the declared targets. Try charging closer targets or units with fewer declared targets.",
	FAIL_DISTANCE: "A model's movement path exceeded the rolled charge distance. Each model can move at most the rolled distance in inches during a charge move.",
	FAIL_ENGAGEMENT: "The charging unit must end its move with at least one model within engagement range (1\") of EVERY declared target. If you declared multiple targets, you must reach all of them.",
	FAIL_NON_TARGET_ER: "No charging model may end within engagement range (1\") of an enemy unit that was NOT declared as a charge target. Plan your movement to avoid non-target enemies.",
	FAIL_COHERENCY: "All models in the unit must maintain unit coherency (within 2\" of at least one other model) after the charge move completes.",
	FAIL_OVERLAP: "Models cannot end their charge movement overlapping with other models (friendly or enemy). Reposition to avoid base overlaps.",
	FAIL_BASE_CONTACT: "If a charging model CAN make base-to-base contact with an enemy model while still satisfying all other charge conditions, it MUST do so (10e core rule).",
	FAIL_DIRECTION: "Each model making a charge move must end that move closer to at least one of the charge target units than it started. Reposition the model so it ends nearer to a declared target.",
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
	awaiting_ability_reroll = false
	ability_reroll_unit_id = ""
	ability_reroll_used = false
	awaiting_overwatch_decision = false
	overwatch_charging_unit_id = ""
	awaiting_fire_overwatch = false
	fire_overwatch_player = 0
	fire_overwatch_enemy_unit_id = ""
	fire_overwatch_eligible_units = []
	awaiting_heroic_intervention = false
	heroic_intervention_player = 0
	heroic_intervention_charging_unit_id = ""
	heroic_intervention_unit_id = ""
	heroic_intervention_pending_charge = {}
	awaiting_tank_shock = false
	tank_shock_vehicle_unit_id = ""
	tank_shock_pending_changes = []

	# Apply unit ability effects for charge phase
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.CHARGE)

	_initialize_charge()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Charge Phase")

	# Clear unit ability effect flags
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_end(GameStateData.Phase.CHARGE)

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
		"USE_ABILITY_REROLL":
			return _validate_ability_reroll(action)
		"DECLINE_ABILITY_REROLL":
			return _validate_ability_reroll(action)
		"USE_COMMAND_REROLL":
			return _validate_command_reroll(action)
		"DECLINE_COMMAND_REROLL":
			return _validate_command_reroll(action)
		"USE_FIRE_OVERWATCH":
			return _validate_use_fire_overwatch(action)
		"DECLINE_FIRE_OVERWATCH":
			return _validate_decline_fire_overwatch(action)
		"USE_HEROIC_INTERVENTION":
			return _validate_use_heroic_intervention(action)
		"DECLINE_HEROIC_INTERVENTION":
			return _validate_decline_heroic_intervention(action)
		"HEROIC_INTERVENTION_CHARGE_ROLL":
			return _validate_heroic_intervention_charge_roll(action)
		"APPLY_HEROIC_INTERVENTION_MOVE":
			return _validate_apply_heroic_intervention_move(action)
		"USE_TANK_SHOCK":
			return _validate_use_tank_shock(action)
		"DECLINE_TANK_SHOCK":
			return _validate_decline_tank_shock(action)
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
		"USE_ABILITY_REROLL":
			return _process_use_ability_reroll(action)
		"DECLINE_ABILITY_REROLL":
			return _process_decline_ability_reroll(action)
		"USE_COMMAND_REROLL":
			return _process_use_command_reroll(action)
		"DECLINE_COMMAND_REROLL":
			return _process_decline_command_reroll(action)
		"USE_FIRE_OVERWATCH":
			return _process_use_fire_overwatch(action)
		"DECLINE_FIRE_OVERWATCH":
			return _process_decline_fire_overwatch(action)
		"USE_HEROIC_INTERVENTION":
			return _process_use_heroic_intervention(action)
		"DECLINE_HEROIC_INTERVENTION":
			return _process_decline_heroic_intervention(action)
		"HEROIC_INTERVENTION_CHARGE_ROLL":
			return _process_heroic_intervention_charge_roll(action)
		"APPLY_HEROIC_INTERVENTION_MOVE":
			return _process_apply_heroic_intervention_move(action)
		"USE_TANK_SHOCK":
			return _process_use_tank_shock(action)
		"DECLINE_TANK_SHOCK":
			return _process_decline_tank_shock(action)
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

	# T2-9: Check if charging unit has FLY keyword (needed to charge AIRCRAFT targets)
	var charger_keywords = unit.get("meta", {}).get("keywords", [])
	var charger_has_fly = "FLY" in charger_keywords

	# Validate each target
	for target_id in target_ids:
		var target_unit = get_unit(target_id)
		if target_unit.is_empty():
			return {"valid": false, "errors": ["Target unit not found: " + target_id]}

		if target_unit.get("owner", 0) == get_current_player():
			return {"valid": false, "errors": ["Cannot charge own units"]}

		# T2-9: Only FLY units can charge AIRCRAFT targets
		var target_keywords = target_unit.get("meta", {}).get("keywords", [])
		if "AIRCRAFT" in target_keywords and not charger_has_fly:
			return {"valid": false, "errors": ["Only units with FLY can charge AIRCRAFT: " + target_id]}

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

	# Track once-per-battle ability usage when a unit charges after advancing
	var declaring_unit = get_unit(unit_id)
	var declaring_flags = declaring_unit.get("flags", {})
	if declaring_flags.get("advanced", false) and EffectPrimitivesData.has_effect_advance_and_charge(declaring_unit):
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr:
			ability_mgr.mark_once_per_battle_used(unit_id, "Martial Inspiration")
			print("ChargePhase: Marked Martial Inspiration as used for unit %s (charged after advancing)" % unit_id)

	# Track the currently charging unit (may not have been set via SELECT_CHARGE_UNIT)
	current_charging_unit = unit_id

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

	# T3-11: Check for Fire Overwatch opportunity for the defending player
	# Per 10e rules: After a charge is declared, the defending player may use
	# Fire Overwatch (1CP) to shoot at the charging unit (only hits on unmodified 6s)
	# P2-25: Sneaky Surprise — unit cannot be targeted by Fire Overwatch
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	var has_sneaky_surprise = false
	if ability_mgr:
		has_sneaky_surprise = ability_mgr.has_sneaky_surprise(unit_id)

	if has_sneaky_surprise:
		log_phase_message("Sneaky Surprise: %s is immune to Fire Overwatch" % unit_name)
		print("ChargePhase: Sneaky Surprise — %s cannot be targeted by Fire Overwatch" % unit_name)
	else:
		var charging_owner = int(unit.get("owner", 0))
		var defending_player = 2 if charging_owner == 1 else 1

		var strat_manager = get_node_or_null("/root/StratagemManager")
		if strat_manager:
			var ow_check = strat_manager.is_fire_overwatch_available(defending_player)
			if ow_check.available:
				var ow_eligible = strat_manager.get_fire_overwatch_eligible_units(
					defending_player, unit_id, game_state_snapshot
				)

				if not ow_eligible.is_empty():
					# Fire Overwatch is available! Pause and offer it to the defender
					awaiting_fire_overwatch = true
					awaiting_overwatch_decision = true
					overwatch_charging_unit_id = unit_id
					fire_overwatch_player = defending_player
					fire_overwatch_enemy_unit_id = unit_id
					fire_overwatch_eligible_units = ow_eligible
					log_phase_message("FIRE OVERWATCH available for Player %d (%d eligible units) against charging %s" % [defending_player, ow_eligible.size(), unit_name])
					print("ChargePhase: Fire Overwatch opportunity — Player %d has %d eligible units" % [defending_player, ow_eligible.size()])

					emit_signal("fire_overwatch_opportunity", defending_player, ow_eligible, unit_id)
					emit_signal("overwatch_opportunity", unit_id, defending_player, ow_eligible)

					var result = create_result(true, [])
					result["trigger_fire_overwatch"] = true
					result["awaiting_overwatch"] = true
					result["fire_overwatch_player"] = defending_player
					result["fire_overwatch_eligible_units"] = ow_eligible
					result["fire_overwatch_enemy_unit_id"] = unit_id
					return result

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

	# Reset ability reroll tracking for this charge attempt
	ability_reroll_used = false

	# Check if unit has ability-granted charge reroll (e.g. Swift Onslaught)
	var unit_data = get_unit(unit_id)
	var has_ability_reroll = EffectPrimitivesData.has_effect_reroll_charge(unit_data)

	if has_ability_reroll:
		# Offer free ability reroll first (before Command Re-roll)
		awaiting_ability_reroll = true
		ability_reroll_unit_id = unit_id

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
			"ability_name": "Swift Onslaught",
		}

		print("ChargePhase: Ability reroll (Swift Onslaught) available for %s — pausing for player decision" % unit_name)
		emit_signal("ability_reroll_opportunity", unit_id, get_current_player(), roll_context)

		return create_result(true, [], "", {
			"dice": [{"context": "charge_roll", "unit_id": unit_id, "unit_name": unit_name, "rolls": rolls, "total": total_distance, "targets": target_ids}],
			"awaiting_ability_reroll": true,
		})

	# No ability reroll — check Command Re-roll
	return _check_command_reroll_or_resolve(unit_id)

func _check_command_reroll_or_resolve(unit_id: String) -> Dictionary:
	"""After ability reroll decision (or if none available), check Command Re-roll or resolve."""
	var charge_data = pending_charges[unit_id]
	var rolls = charge_data.dice_rolls
	var total_distance = charge_data.distance
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var target_ids = charge_data.targets

	# Per 10e rules: a dice can only be re-rolled once. If ability reroll was used, skip Command Re-roll.
	if ability_reroll_used:
		print("ChargePhase: Ability reroll already used for %s — cannot Command Re-roll (dice re-rolled once rule)" % unit_name)
		return _resolve_charge_roll(unit_id)

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

	# No rerolls available — resolve immediately
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

func _validate_ability_reroll(action: Dictionary) -> Dictionary:
	"""Validate USE_ABILITY_REROLL or DECLINE_ABILITY_REROLL action."""
	if not awaiting_ability_reroll:
		return {"valid": false, "errors": ["Not awaiting an ability reroll decision"]}
	return {"valid": true, "errors": []}

func _process_use_ability_reroll(action: Dictionary) -> Dictionary:
	"""Process USE_ABILITY_REROLL: re-roll the charge dice using ability (free, no CP cost)."""
	var unit_id = ability_reroll_unit_id
	awaiting_ability_reroll = false
	ability_reroll_unit_id = ""
	ability_reroll_used = true

	if not pending_charges.has(unit_id):
		return create_result(false, [], "No pending charge for ability reroll")

	var charge_data = pending_charges[unit_id]
	var old_rolls = charge_data.dice_rolls.duplicate()
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)

	# Re-roll the 2D6 (free — no CP cost)
	var rng = RulesEngine.RNGService.new()
	var new_rolls = rng.roll_d6(2)
	var new_total = new_rolls[0] + new_rolls[1]

	# Update the charge data with new rolls
	charge_data.distance = new_total
	charge_data.dice_rolls = new_rolls

	log_phase_message("SWIFT ONSLAUGHT: Charge re-rolled from %d (%s) → %d (%d + %d)" % [
		old_rolls[0] + old_rolls[1], str(old_rolls), new_total, new_rolls[0], new_rolls[1]
	])

	print("ChargePhase: ABILITY REROLL (Swift Onslaught) — %s charge re-rolled: %s → %s (total %d → %d)" % [
		unit_name, str(old_rolls), str(new_rolls), old_rolls[0] + old_rolls[1], new_total
	])

	# Dice already re-rolled once — cannot Command Re-roll per 10e rules
	return _resolve_charge_roll(unit_id)

func _process_decline_ability_reroll(action: Dictionary) -> Dictionary:
	"""Process DECLINE_ABILITY_REROLL: skip free reroll, proceed to Command Re-roll check."""
	var unit_id = ability_reroll_unit_id
	awaiting_ability_reroll = false
	ability_reroll_unit_id = ""

	if not pending_charges.has(unit_id):
		return create_result(false, [], "No pending charge for ability reroll decline")

	print("ChargePhase: Ability reroll DECLINED for %s — checking Command Re-roll" % unit_id)

	# Player chose not to use ability reroll — check Command Re-roll
	return _check_command_reroll_or_resolve(unit_id)

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

# _process_use_fire_overwatch and _process_decline_fire_overwatch are defined
# in the T3-11 Fire Overwatch section below (around line 2056+).
# They handle both remote and local overwatch state cleanup.

# _process_use_heroic_intervention and _process_decline_heroic_intervention are defined
# in the T3-11 Heroic Intervention section below.
# They handle both remote and local heroic intervention state cleanup.

# ============================================================================
# TANK SHOCK HANDLERS
# ============================================================================

func _validate_use_tank_shock(action: Dictionary) -> Dictionary:
	"""Validate USE_TANK_SHOCK action."""
	if not awaiting_tank_shock:
		return {"valid": false, "errors": ["Not awaiting a Tank Shock decision"]}
	var target_unit_id = action.get("payload", {}).get("target_unit_id", "")
	if target_unit_id == "":
		return {"valid": false, "errors": ["Missing target_unit_id for Tank Shock"]}
	return {"valid": true, "errors": []}

func _validate_decline_tank_shock(action: Dictionary) -> Dictionary:
	"""Validate DECLINE_TANK_SHOCK action."""
	if not awaiting_tank_shock:
		return {"valid": false, "errors": ["Not awaiting a Tank Shock decision"]}
	return {"valid": true, "errors": []}

func _process_use_tank_shock(action: Dictionary) -> Dictionary:
	"""Process USE_TANK_SHOCK: charging player rams an enemy unit."""
	var target_unit_id = action.get("payload", {}).get("target_unit_id", "")
	var vehicle_unit_id = tank_shock_vehicle_unit_id
	var pending_changes = tank_shock_pending_changes

	awaiting_tank_shock = false
	tank_shock_vehicle_unit_id = ""
	tank_shock_pending_changes = []

	if vehicle_unit_id == "" or target_unit_id == "":
		return create_result(false, [], "Missing vehicle or target unit for Tank Shock")

	var current_player = get_current_player()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return _check_heroic_intervention_after_tank_shock(vehicle_unit_id, pending_changes)

	var ts_result = strat_manager.execute_tank_shock(current_player, vehicle_unit_id, target_unit_id)

	if not ts_result.success:
		print("ChargePhase: Tank Shock failed: %s" % ts_result.get("error", ""))
		return _check_heroic_intervention_after_tank_shock(vehicle_unit_id, pending_changes)

	log_phase_message(ts_result.get("message", "Tank Shock executed"))
	emit_signal("tank_shock_result", vehicle_unit_id, target_unit_id, ts_result)

	# After Tank Shock resolves, check Heroic Intervention
	return _check_heroic_intervention_after_tank_shock(vehicle_unit_id, pending_changes)

func _process_decline_tank_shock(action: Dictionary) -> Dictionary:
	"""Process DECLINE_TANK_SHOCK: charging player declines Tank Shock."""
	var vehicle_unit_id = tank_shock_vehicle_unit_id
	var pending_changes = tank_shock_pending_changes

	awaiting_tank_shock = false
	tank_shock_vehicle_unit_id = ""
	tank_shock_pending_changes = []

	print("ChargePhase: Tank Shock DECLINED")

	# Still need to check Heroic Intervention
	return _check_heroic_intervention_after_tank_shock(vehicle_unit_id, pending_changes)

func _check_heroic_intervention_after_tank_shock(vehicle_unit_id: String, pending_changes: Array) -> Dictionary:
	"""After Tank Shock resolves (or is declined), check Heroic Intervention for the defender."""
	var charging_unit = get_unit(vehicle_unit_id)
	var charging_owner = int(charging_unit.get("owner", 0))
	var defending_player = 2 if charging_owner == 1 else 1

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var hi_check = strat_manager.is_heroic_intervention_available(defending_player)
		if hi_check.available:
			# Build a temporary snapshot with the charge move applied
			var temp_snapshot = game_state_snapshot.duplicate(true)
			for change in pending_changes:
				if change.get("op", "") == "set":
					var path_parts = change.path.split(".")
					if path_parts.size() >= 4 and path_parts[0] == "units" and path_parts[2] == "models":
						var u_id = path_parts[1]
						var m_idx = int(path_parts[3])
						var field = path_parts[4] if path_parts.size() > 4 else ""
						if field == "position" and temp_snapshot.get("units", {}).has(u_id):
							var models = temp_snapshot.units[u_id].get("models", [])
							if m_idx < models.size():
								models[m_idx]["position"] = change.value

			var hi_eligible = strat_manager.get_heroic_intervention_eligible_units(
				defending_player, vehicle_unit_id, temp_snapshot
			)

			if not hi_eligible.is_empty():
				awaiting_heroic_intervention = true
				heroic_intervention_player = defending_player
				heroic_intervention_charging_unit_id = vehicle_unit_id
				log_phase_message("HEROIC INTERVENTION available for Player %d (%d eligible units)" % [defending_player, hi_eligible.size()])

				emit_signal("heroic_intervention_opportunity", defending_player, hi_eligible, vehicle_unit_id)

				var result = create_result(true, [])
				result["trigger_heroic_intervention"] = true
				result["awaiting_heroic_intervention"] = true
				result["heroic_intervention_player"] = defending_player
				result["heroic_intervention_eligible_units"] = hi_eligible
				result["heroic_intervention_charging_unit_id"] = vehicle_unit_id
				return result

	return create_result(true, [])

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

	# T7-39: Recheck objective control after charge movement
	if MissionManager:
		MissionManager.call_deferred("check_all_objectives")

	# Check if Tank Shock is available for the charging player
	# Per 10e rules: "just after a VEHICLE unit ends a Charge move"
	var charging_unit = get_unit(unit_id)
	var charging_owner = int(charging_unit.get("owner", 0))
	var defending_player = 2 if charging_owner == 1 else 1

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		# Tank Shock: active player's VEHICLE just completed a charge
		var ts_check = strat_manager.is_tank_shock_available(charging_owner)
		if ts_check.available:
			# Check if the charging unit is a VEHICLE
			var keywords = charging_unit.get("meta", {}).get("keywords", [])
			var is_vehicle = false
			for kw in keywords:
				if kw.to_upper() == "VEHICLE":
					is_vehicle = true
					break

			if is_vehicle:
				# Build a temporary snapshot with the charge move applied
				# so engagement range checks use the post-move positions
				var temp_snapshot = game_state_snapshot.duplicate(true)
				for change in changes:
					if change.get("op", "") == "set":
						var path_parts = change.path.split(".")
						if path_parts.size() >= 4 and path_parts[0] == "units" and path_parts[2] == "models":
							var u_id = path_parts[1]
							var m_idx = int(path_parts[3])
							var field = path_parts[4] if path_parts.size() > 4 else ""
							if field == "position" and temp_snapshot.get("units", {}).has(u_id):
								var models = temp_snapshot.units[u_id].get("models", [])
								if m_idx < models.size():
									models[m_idx]["position"] = change.value

				var ts_targets = strat_manager.get_tank_shock_eligible_targets(unit_id, temp_snapshot)
				if not ts_targets.is_empty():
					# Tank Shock is available! Pause and offer it to the charging player
					awaiting_tank_shock = true
					tank_shock_vehicle_unit_id = unit_id
					tank_shock_pending_changes = changes
					var vehicle_name = charging_unit.get("meta", {}).get("name", unit_id)
					log_phase_message("TANK SHOCK available for Player %d — %s (T%d, %d eligible targets)" % [
						charging_owner, vehicle_name,
						int(charging_unit.get("meta", {}).get("toughness", 4)),
						ts_targets.size()
					])
					print("ChargePhase: Tank Shock opportunity — Player %d, vehicle %s, %d eligible targets" % [
						charging_owner, vehicle_name, ts_targets.size()
					])

					emit_signal("tank_shock_opportunity", charging_owner, unit_id, ts_targets)

					var result = create_result(true, changes)
					result["trigger_tank_shock"] = true
					result["awaiting_tank_shock"] = true
					result["tank_shock_player"] = charging_owner
					result["tank_shock_vehicle_unit_id"] = unit_id
					result["tank_shock_eligible_targets"] = ts_targets
					return result

	# Check if Heroic Intervention is available for the defending player
	# Per 10e rules: "just after an enemy unit ends a Charge move"
	if strat_manager:
		var hi_check = strat_manager.is_heroic_intervention_available(defending_player)
		if hi_check.available:
			# Need to apply changes first so the snapshot is up-to-date for distance checks
			# We do this through the result — BasePhase.execute_action applies changes before
			# we check, but we need to use the FUTURE state. Build a temporary snapshot.
			var temp_snapshot = game_state_snapshot.duplicate(true)
			# Apply position changes to temp snapshot for distance calculation
			for change in changes:
				if change.get("op", "") == "set":
					var path_parts = change.path.split(".")
					if path_parts.size() >= 4 and path_parts[0] == "units" and path_parts[2] == "models":
						var u_id = path_parts[1]
						var m_idx = int(path_parts[3])
						var field = path_parts[4] if path_parts.size() > 4 else ""
						if field == "position" and temp_snapshot.get("units", {}).has(u_id):
							var models = temp_snapshot.units[u_id].get("models", [])
							if m_idx < models.size():
								models[m_idx]["position"] = change.value

			var hi_eligible = strat_manager.get_heroic_intervention_eligible_units(
				defending_player, unit_id, temp_snapshot
			)

			if not hi_eligible.is_empty():
				# Heroic Intervention is available! Pause and offer it to the defender
				awaiting_heroic_intervention = true
				heroic_intervention_player = defending_player
				heroic_intervention_charging_unit_id = unit_id
				log_phase_message("HEROIC INTERVENTION available for Player %d (%d eligible units)" % [defending_player, hi_eligible.size()])

				emit_signal("heroic_intervention_opportunity", defending_player, hi_eligible, unit_id)

				var result = create_result(true, changes)
				result["trigger_heroic_intervention"] = true
				result["awaiting_heroic_intervention"] = true
				result["heroic_intervention_player"] = defending_player
				result["heroic_intervention_eligible_units"] = hi_eligible
				result["heroic_intervention_charging_unit_id"] = unit_id
				return result

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
		if not EffectPrimitivesData.has_effect_advance_and_charge(unit):
			return false
		else:
			print("ChargePhase: Unit %s advanced but has advance_and_charge effect — eligible to charge" % unit.get("id", "unknown"))

	if flags.get("fell_back", false):
		if not EffectPrimitivesData.has_effect_fall_back_and_charge(unit):
			return false
		else:
			print("ChargePhase: Unit %s fell back but has fall_back_and_charge effect — eligible to charge" % unit.get("id", "unknown"))

	if flags.get("charged_this_turn", false):
		return false

	# T2-9: AIRCRAFT units cannot declare charges
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in keywords:
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

				# T3-9: Use barricade-aware engagement range check
				var effective_er = _get_effective_engagement_range(model_pos, enemy_pos)
				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, effective_er):
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

	# T2-9: Check if charging unit has FLY keyword (needed to charge AIRCRAFT targets)
	var charger_unit = get_unit(unit_id)
	var charger_keywords = charger_unit.get("meta", {}).get("keywords", [])
	var charger_has_fly = "FLY" in charger_keywords

	for target_id in all_units:
		var target_unit = all_units[target_id]
		if target_unit.get("owner", 0) != current_player:  # Enemy unit
			# T2-9: Only FLY units can charge AIRCRAFT targets
			var target_keywords = target_unit.get("meta", {}).get("keywords", [])
			if "AIRCRAFT" in target_keywords and not charger_has_fly:
				continue

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

	# Check if unit has FLY keyword (for terrain penalty calculation)
	var unit = get_unit(unit_id)
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	# 1. Validate path distances (including terrain vertical distance penalties)
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() >= 2:
			var path_distance = Measurement.distance_polyline_inches(path)

			# T2-8: Add terrain vertical distance penalty
			# Terrain >2" high costs vertical distance against charge roll
			# FLY units measure diagonally instead (shorter penalty)
			var terrain_penalty = _calculate_path_terrain_penalty(path, has_fly)
			var effective_distance = path_distance + terrain_penalty

			if terrain_penalty > 0.0:
				print("ChargePhase: Model %s terrain penalty: %.1f\" (FLY=%s), effective distance: %.1f\"" % [
					model_id, terrain_penalty, str(has_fly), effective_distance])

			if effective_distance > rolled_distance:
				var err = ""
				if terrain_penalty > 0.0:
					err = "Model %s path (%.1f\") + terrain penalty (%.1f\") = %.1f\" exceeds charge distance %d\"" % [
						model_id, path_distance, terrain_penalty, effective_distance, rolled_distance]
				else:
					err = "Model %s path exceeds charge distance: %.1f\" > %d\"" % [model_id, path_distance, rolled_distance]
				errors.append(err)
				categorized_errors.append({"category": FAIL_DISTANCE, "detail": err})

	# 2. Validate each model ends closer to at least one charge target (T3-8)
	var direction_validation = _validate_charge_direction_constraint(unit_id, per_model_paths, target_ids)
	if not direction_validation.valid:
		errors.append_array(direction_validation.errors)
		for err in direction_validation.errors:
			categorized_errors.append({"category": FAIL_DIRECTION, "detail": err})

	# 3. Validate no model overlaps
	var overlap_validation = _validate_no_model_overlaps(unit_id, per_model_paths)
	if not overlap_validation.valid:
		errors.append_array(overlap_validation.errors)
		for err in overlap_validation.errors:
			categorized_errors.append({"category": FAIL_OVERLAP, "detail": err})

	# 5. Validate engagement range with ALL targets
	var engagement_validation = _validate_engagement_range_constraints(unit_id, per_model_paths, target_ids)
	if not engagement_validation.valid:
		errors.append_array(engagement_validation.errors)
		for err in engagement_validation.errors:
			# Distinguish between "must reach target" vs "too close to non-target"
			if "non-target" in err.to_lower():
				categorized_errors.append({"category": FAIL_NON_TARGET_ER, "detail": err})
			else:
				categorized_errors.append({"category": FAIL_ENGAGEMENT, "detail": err})

	# 6. Validate unit coherency
	var coherency_validation = _validate_unit_coherency_for_charge(unit_id, per_model_paths)
	if not coherency_validation.valid:
		errors.append_array(coherency_validation.errors)
		for err in coherency_validation.errors:
			categorized_errors.append({"category": FAIL_COHERENCY, "detail": err})

	# 7. Validate base-to-base if possible
	var base_to_base_validation = _validate_base_to_base_possible(unit_id, per_model_paths, target_ids, rolled_distance)
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

					# T3-9: Use barricade-aware engagement range (2" through barricades)
					var effective_er = _get_effective_engagement_range(final_pos, target_pos)
					if Measurement.is_in_engagement_range_shape_aware(model_at_final_pos, target_model, effective_er):
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

					# T3-9: Use barricade-aware engagement range for non-target check too
					var effective_er = _get_effective_engagement_range(final_pos, enemy_pos)
					if Measurement.is_in_engagement_range_shape_aware(model_at_final_pos, enemy_model, effective_er):
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

func _validate_base_to_base_possible(unit_id: String, per_model_paths: Dictionary, target_ids: Array, rolled_distance: int) -> Dictionary:
	# 10e rule: If a charging model CAN make base-to-base contact with an enemy
	# model while still satisfying all other charge conditions, it MUST do so.
	#
	# For each charging model, we check:
	# 1. Could it reach base-to-base with any target model (straight-line distance <= rolled distance)?
	# 2. If yes, does its final position actually achieve base-to-base contact?
	# 3. If it could but didn't, flag a validation error.
	var errors = []
	var all_units = game_state_snapshot.get("units", {})
	const BASE_CONTACT_TOLERANCE_INCHES: float = 0.25  # Match RulesEngine tolerance for digital positioning

	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var model = _get_model_in_unit(unit_id, model_id)
		if model.is_empty():
			continue

		var start_pos = _get_model_position(model)
		var final_pos = Vector2(path[-1][0], path[-1][1])

		# Create model dict at final position for shape-aware distance checks
		var model_at_final = model.duplicate()
		model_at_final["position"] = final_pos

		# Check if this model could reach b2b with any target model and whether it did
		var could_reach_b2b = false
		var is_in_b2b = false
		var closest_reachable_target_name = ""

		for target_id in target_ids:
			var target_unit = all_units.get(target_id, {})
			if target_unit.is_empty():
				continue

			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue

				var target_pos = _get_model_position(target_model)
				if target_pos == null:
					continue

				# Check if model could reach b2b from its starting position
				# Straight-line edge-to-edge distance from start to target
				var start_distance = Measurement.model_to_model_distance_inches(model, target_model)
				if start_distance <= float(rolled_distance):
					could_reach_b2b = true
					if closest_reachable_target_name.is_empty():
						var target_name = target_unit.get("meta", {}).get("name", target_id)
						var target_model_id = target_model.get("id", "unknown")
						closest_reachable_target_name = "%s (model %s)" % [target_name, target_model_id]

				# Check if model's final position IS in b2b with this target model
				var final_distance = Measurement.model_to_model_distance_inches(model_at_final, target_model)
				if final_distance <= BASE_CONTACT_TOLERANCE_INCHES:
					is_in_b2b = true

		# If model could reach b2b but didn't, flag the error
		if could_reach_b2b and not is_in_b2b:
			var err = "Model %s can reach base-to-base contact with %s but did not — charging models must make base contact when possible" % [model_id, closest_reachable_target_name]
			errors.append(err)
			print("ChargePhase: B2B enforcement - %s" % err)

	return {"valid": errors.is_empty(), "errors": errors}

## T3-8: Validate that each model ends its charge move closer to at least one
## charge target than it started. This is a 10e core rule for charge moves.
func _validate_charge_direction_constraint(unit_id: String, per_model_paths: Dictionary, target_ids: Array) -> Dictionary:
	var errors = []
	var all_units = game_state_snapshot.get("units", {})

	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var model = _get_model_in_unit(unit_id, model_id)
		if model.is_empty():
			continue

		var start_pos = _get_model_position(model)
		if start_pos == null or start_pos == Vector2.ZERO:
			continue

		var final_pos = Vector2(path[-1][0], path[-1][1])

		# Check if model ends closer to at least one target model in any target unit
		var ends_closer_to_any_target = false

		for target_id in target_ids:
			var target_unit = all_units.get(target_id, {})
			if target_unit.is_empty():
				continue

			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue

				var target_pos = _get_model_position(target_model)
				if target_pos == null:
					continue

				var start_distance = start_pos.distance_to(target_pos)
				var final_distance = final_pos.distance_to(target_pos)

				if final_distance < start_distance:
					ends_closer_to_any_target = true
					break

			if ends_closer_to_any_target:
				break

		if not ends_closer_to_any_target:
			var err = "Model %s must end its charge move closer to at least one charge target" % model_id
			errors.append(err)
			print("ChargePhase: Direction constraint - %s" % err)

	return {"valid": errors.is_empty(), "errors": errors}

## T2-8: Calculate the total terrain vertical distance penalty for a charge path.
## For each segment of the path that crosses terrain >2" high, adds vertical
## distance (climb up + down for non-FLY, diagonal for FLY units).
func _calculate_path_terrain_penalty(path: Array, has_fly: bool) -> float:
	var total_penalty: float = 0.0
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if not terrain_manager:
		return 0.0

	# Check each segment of the path for terrain crossings
	for i in range(1, path.size()):
		var from_pos: Vector2
		var to_pos: Vector2

		# Handle both Vector2 and Array [x, y] formats
		if path[i - 1] is Vector2:
			from_pos = path[i - 1]
		elif path[i - 1] is Array:
			from_pos = Vector2(path[i - 1][0], path[i - 1][1])
		else:
			continue

		if path[i] is Vector2:
			to_pos = path[i]
		elif path[i] is Array:
			to_pos = Vector2(path[i][0], path[i][1])
		else:
			continue

		total_penalty += terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, has_fly)

	return total_penalty

## T3-9: Get the effective engagement range between two model positions,
## accounting for barricade terrain (2" instead of 1" if barricade is between them).
func _get_effective_engagement_range(model1_pos: Vector2, model2_pos: Vector2) -> float:
	if not is_inside_tree():
		return ENGAGEMENT_RANGE_INCHES
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.has_method("get_engagement_range_for_positions"):
		return terrain_manager.get_engagement_range_for_positions(model1_pos, model2_pos)
	return ENGAGEMENT_RANGE_INCHES

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

	# --- Reaction states: these block normal charge actions until resolved ---

	# Ability reroll decision pending (e.g. Swift Onslaught — free reroll)
	if awaiting_ability_reroll and ability_reroll_unit_id != "":
		actions.append({
			"type": "USE_ABILITY_REROLL",
			"actor_unit_id": ability_reroll_unit_id,
			"description": "Use Swift Onslaught — re-roll charge dice (free)"
		})
		actions.append({
			"type": "DECLINE_ABILITY_REROLL",
			"actor_unit_id": ability_reroll_unit_id,
			"description": "Keep original charge roll"
		})
		return actions  # Block other actions until resolved

	# Command Re-roll decision pending
	if awaiting_reroll_decision and reroll_pending_unit_id != "":
		actions.append({
			"type": "USE_COMMAND_REROLL",
			"actor_unit_id": reroll_pending_unit_id,
			"description": "Use Command Re-roll on charge dice"
		})
		actions.append({
			"type": "DECLINE_COMMAND_REROLL",
			"actor_unit_id": reroll_pending_unit_id,
			"description": "Decline Command Re-roll"
		})
		return actions  # Block other actions until resolved

	# Fire Overwatch decision pending (defending player)
	if awaiting_fire_overwatch:
		for ow_unit_id in fire_overwatch_eligible_units:
			actions.append({
				"type": "USE_FIRE_OVERWATCH",
				"actor_unit_id": ow_unit_id,
				"enemy_unit_id": fire_overwatch_enemy_unit_id,
				"player": fire_overwatch_player,
				"description": "Fire Overwatch with %s" % ow_unit_id
			})
		actions.append({
			"type": "DECLINE_FIRE_OVERWATCH",
			"player": fire_overwatch_player,
			"description": "Decline Fire Overwatch"
		})
		return actions  # Block other actions until resolved

	# Heroic Intervention decision pending (defending player)
	if awaiting_heroic_intervention:
		actions.append({
			"type": "USE_HEROIC_INTERVENTION",
			"player": heroic_intervention_player,
			"charging_unit_id": heroic_intervention_charging_unit_id,
			"description": "Use Heroic Intervention"
		})
		actions.append({
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": heroic_intervention_player,
			"description": "Decline Heroic Intervention"
		})
		return actions  # Block other actions until resolved

	# Tank Shock decision pending (charging player)
	if awaiting_tank_shock and tank_shock_vehicle_unit_id != "":
		actions.append({
			"type": "USE_TANK_SHOCK",
			"actor_unit_id": tank_shock_vehicle_unit_id,
			"description": "Use Tank Shock"
		})
		actions.append({
			"type": "DECLINE_TANK_SHOCK",
			"actor_unit_id": tank_shock_vehicle_unit_id,
			"description": "Decline Tank Shock"
		})
		return actions  # Block other actions until resolved

	# --- Normal charge actions ---

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

			# If roll made and successful, can apply movement or complete
			elif pending_charges.has(unit_id) and pending_charges[unit_id].has("distance"):
				var charge_data = pending_charges[unit_id]
				var rolled_distance = charge_data.distance
				actions.append({
					"type": "APPLY_CHARGE_MOVE",
					"actor_unit_id": unit_id,
					"rolled_distance": rolled_distance,
					"target_ids": charge_data.get("targets", []),
					"description": "Apply charge movement for " + unit.get("meta", {}).get("name", unit_id)
				})

	# Check for units that need COMPLETE_UNIT_CHARGE
	# (units in units_that_charged but not in completed_charges, with current_charging_unit set)
	if current_charging_unit != null and current_charging_unit in units_that_charged and current_charging_unit not in completed_charges:
		actions.append({
			"type": "COMPLETE_UNIT_CHARGE",
			"actor_unit_id": current_charging_unit,
			"description": "Complete charge for " + units.get(current_charging_unit, {}).get("meta", {}).get("name", str(current_charging_unit))
		})

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
	This is the server-side feasibility check performed immediately after the roll.
	T2-8: Now accounts for terrain vertical distance penalties along the charge path."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false

	if not pending_charges.has(unit_id):
		return false

	var target_ids = pending_charges[unit_id].get("targets", [])
	if target_ids.is_empty():
		return false

	# T2-8: Check FLY keyword for terrain penalty calculation
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)

		for target_id in target_ids:
			var target_unit = get_unit(target_id)
			if target_unit.is_empty():
				continue

			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue

				# Edge-to-edge distance in inches, minus engagement range
				var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
				# T3-9: Use barricade-aware engagement range
				var target_pos = _get_model_position(target_model)
				var effective_er = _get_effective_engagement_range(model_pos, target_pos)
				var distance_to_close = distance_inches - effective_er

				# T2-8: Add terrain penalty for the straight-line path
				var terrain_penalty = _calculate_path_terrain_penalty(
					[model_pos, target_pos], has_fly)
				var effective_distance = distance_to_close + terrain_penalty

				if effective_distance <= rolled_distance:
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

# ============================================================================
# FIRE OVERWATCH (T3-11)
# ============================================================================

func _validate_use_fire_overwatch(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", fire_overwatch_player)

	if not awaiting_fire_overwatch:
		errors.append("Not awaiting Fire Overwatch decision")
		return {"valid": false, "errors": errors}

	if unit_id.is_empty():
		errors.append("No unit specified for Fire Overwatch")
		return {"valid": false, "errors": errors}

	# Validate through StratagemManager
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var check = strat_manager.is_fire_overwatch_available(player)
		if not check.available:
			errors.append(check.reason)
			return {"valid": false, "errors": errors}

	# Validate the unit is eligible
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if int(unit.get("owner", 0)) != player:
		errors.append("Unit does not belong to player %d" % player)
		return {"valid": false, "errors": errors}

	# Check unit is not battle-shocked
	var flags = unit.get("flags", {})
	if flags.get("battle_shocked", false):
		errors.append("Battle-shocked units cannot use Stratagems")
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _validate_decline_fire_overwatch(action: Dictionary) -> Dictionary:
	if not awaiting_fire_overwatch:
		return {"valid": false, "errors": ["Not awaiting Fire Overwatch decision"]}
	return {"valid": true, "errors": []}

func _process_use_fire_overwatch(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", fire_overwatch_player)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var enemy_unit_id = fire_overwatch_enemy_unit_id
	var enemy_unit_name = get_unit(enemy_unit_id).get("meta", {}).get("name", enemy_unit_id)

	# Use the stratagem via StratagemManager (deducts CP, records usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var strat_result = strat_manager.use_stratagem(player, "fire_overwatch", unit_id)
		if not strat_result.success:
			return create_result(false, [], "Failed to use Fire Overwatch: %s" % strat_result.get("error", "unknown"))

	log_phase_message("Player %d uses FIRE OVERWATCH — %s shoots at charging %s!" % [player, unit_name, enemy_unit_name])
	print("ChargePhase: Fire Overwatch activated — %s (Player %d) shooting at %s" % [unit_name, player, enemy_unit_name])

	# Resolve Overwatch shooting using RulesEngine
	# Overwatch only hits on unmodified 6s (special rule)
	var overwatch_result = _resolve_overwatch_shooting(unit_id, enemy_unit_id, player)

	# Clear Overwatch state (both local and remote)
	awaiting_fire_overwatch = false
	awaiting_overwatch_decision = false
	overwatch_charging_unit_id = ""
	fire_overwatch_player = 0
	fire_overwatch_enemy_unit_id = ""
	fire_overwatch_eligible_units = []

	var result = create_result(true, overwatch_result.get("diffs", []))
	result["fire_overwatch_used"] = true
	result["fire_overwatch_unit_id"] = unit_id
	result["fire_overwatch_target_id"] = enemy_unit_id
	result["fire_overwatch_shooting_result"] = overwatch_result
	if overwatch_result.has("dice"):
		result["dice"] = overwatch_result.dice
	if overwatch_result.has("log_text"):
		result["log_text"] = overwatch_result.log_text
	return result

func _process_decline_fire_overwatch(action: Dictionary) -> Dictionary:
	var player = action.get("player", fire_overwatch_player)
	log_phase_message("Player %d declined FIRE OVERWATCH" % player)
	print("ChargePhase: Fire Overwatch DECLINED by Player %d" % player)

	# Clear Overwatch state (both local and remote)
	awaiting_fire_overwatch = false
	awaiting_overwatch_decision = false
	overwatch_charging_unit_id = ""
	fire_overwatch_player = 0
	fire_overwatch_enemy_unit_id = ""
	fire_overwatch_eligible_units = []

	return create_result(true, [])

func _resolve_overwatch_shooting(shooting_unit_id: String, target_unit_id: String, player: int) -> Dictionary:
	"""
	Resolve Overwatch shooting. Uses the normal shooting resolution but forces
	all hit rolls to only succeed on unmodified 6s (per 10e Overwatch rules).
	"""
	var shooting_unit = get_unit(shooting_unit_id)
	var target_unit = get_unit(target_unit_id)

	if shooting_unit.is_empty() or target_unit.is_empty():
		return {"diffs": [], "dice": [], "log_text": "Overwatch: Invalid units"}

	# Build weapon assignments from all ranged weapons
	var assignments = []
	var weapons = shooting_unit.get("meta", {}).get("weapons", [])
	var alive_model_ids = []
	for model in shooting_unit.get("models", []):
		if model.get("alive", true):
			alive_model_ids.append(model.get("id", ""))

	for weapon in weapons:
		var weapon_type = weapon.get("type", "").to_lower()
		var weapon_range = weapon.get("range", "")
		var is_melee = weapon_type == "melee" or weapon_range == "Melee"
		if is_melee:
			continue

		# All alive models fire their ranged weapons
		assignments.append({
			"weapon_id": weapon.get("id", weapon.get("name", "")),
			"target_unit_id": target_unit_id,
			"model_ids": alive_model_ids,
			"overwatch": true,  # Flag for RulesEngine to use hit_on: 6
		})

	if assignments.is_empty():
		log_phase_message("Overwatch: %s has no ranged weapons to fire" % shooting_unit.get("meta", {}).get("name", shooting_unit_id))
		return {"diffs": [], "dice": [], "log_text": "No ranged weapons available for Overwatch"}

	# Build the shooting action for RulesEngine
	var shoot_action = {
		"actor_unit_id": shooting_unit_id,
		"payload": {
			"assignments": assignments,
			"overwatch": true,  # Global overwatch flag
		}
	}

	# Use RulesEngine.resolve_shoot for full resolution
	var board = game_state_snapshot
	var rng = RulesEngine.RNGService.new()
	var shoot_result = RulesEngine.resolve_shoot(shoot_action, board, rng)

	var total_damage = 0
	for diff in shoot_result.get("diffs", []):
		if diff.get("op", "") == "set" and "wounds" in diff.get("path", ""):
			total_damage += 1

	log_phase_message("FIRE OVERWATCH result: %s fired at %s — %s" % [
		shooting_unit.get("meta", {}).get("name", shooting_unit_id),
		target_unit.get("meta", {}).get("name", target_unit_id),
		shoot_result.get("log_text", "no hits")
	])

	return shoot_result

# ============================================================================
# HEROIC INTERVENTION
# ============================================================================

func _validate_use_heroic_intervention(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", heroic_intervention_player)

	if not awaiting_heroic_intervention:
		errors.append("Not awaiting Heroic Intervention decision")
		return {"valid": false, "errors": errors}

	if unit_id.is_empty():
		errors.append("No unit specified for Heroic Intervention")
		return {"valid": false, "errors": errors}

	# Validate through StratagemManager
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var check = strat_manager.is_heroic_intervention_available(player)
		if not check.available:
			errors.append(check.reason)
			return {"valid": false, "errors": errors}

	# Validate the unit is eligible
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if int(unit.get("owner", 0)) != player:
		errors.append("Unit does not belong to player %d" % player)
		return {"valid": false, "errors": errors}

	# Check unit is not battle-shocked
	var flags = unit.get("flags", {})
	if flags.get("battle_shocked", false):
		errors.append("Battle-shocked units cannot use Stratagems")
		return {"valid": false, "errors": errors}

	# Check VEHICLE restriction
	var keywords = unit.get("meta", {}).get("keywords", [])
	var is_vehicle = false
	var is_walker = false
	for kw in keywords:
		var kw_upper = kw.to_upper()
		if kw_upper == "VEHICLE":
			is_vehicle = true
		if kw_upper == "WALKER":
			is_walker = true
	if is_vehicle and not is_walker:
		errors.append("VEHICLE units cannot use Heroic Intervention unless they have the WALKER keyword")
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _validate_decline_heroic_intervention(action: Dictionary) -> Dictionary:
	if not awaiting_heroic_intervention:
		return {"valid": false, "errors": ["Not awaiting Heroic Intervention decision"]}
	return {"valid": true, "errors": []}

func _validate_heroic_intervention_charge_roll(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id.is_empty():
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if heroic_intervention_unit_id.is_empty():
		return {"valid": false, "errors": ["No unit selected for Heroic Intervention charge"]}
	if unit_id != heroic_intervention_unit_id:
		return {"valid": false, "errors": ["Unit does not match Heroic Intervention selection"]}
	if heroic_intervention_pending_charge.is_empty():
		return {"valid": false, "errors": ["No Heroic Intervention charge pending"]}
	return {"valid": true, "errors": []}

func _validate_apply_heroic_intervention_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})

	if unit_id.is_empty():
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if per_model_paths.is_empty():
		return {"valid": false, "errors": ["Missing per_model_paths"]}
	if unit_id != heroic_intervention_unit_id:
		return {"valid": false, "errors": ["Unit does not match Heroic Intervention selection"]}
	if heroic_intervention_pending_charge.is_empty():
		return {"valid": false, "errors": ["No Heroic Intervention charge data"]}

	# Validate movement constraints (same as normal charge but target is only the charging enemy)
	var charge_data = heroic_intervention_pending_charge
	if not charge_data.has("distance"):
		return {"valid": false, "errors": ["No charge distance rolled yet"]}

	var validation = _validate_charge_movement_constraints(unit_id, per_model_paths, charge_data)
	return validation

func _process_use_heroic_intervention(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", heroic_intervention_player)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)

	# Use the stratagem via StratagemManager (deducts CP, records usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var strat_result = strat_manager.use_stratagem(player, "heroic_intervention", unit_id)
		if not strat_result.success:
			return create_result(false, [], "Failed to use Heroic Intervention: %s" % strat_result.get("error", "unknown"))

	log_phase_message("Player %d uses HEROIC INTERVENTION — %s will counter-charge!" % [player, unit_name])

	# Set up the heroic intervention charge
	awaiting_heroic_intervention = false
	heroic_intervention_unit_id = unit_id

	# Set up pending charge data targeting only the charging enemy unit
	heroic_intervention_pending_charge = {
		"targets": [heroic_intervention_charging_unit_id],
		"declared_at": Time.get_unix_time_from_system()
	}

	# Now auto-roll the charge dice (HI uses a normal 2D6 charge roll)
	var rng = RulesEngine.RNGService.new()
	var rolls = rng.roll_d6(2)
	var total_distance = rolls[0] + rolls[1]

	heroic_intervention_pending_charge.distance = total_distance
	heroic_intervention_pending_charge.dice_rolls = rolls

	log_phase_message("HEROIC INTERVENTION charge roll: 2D6 = %d (%d + %d)" % [total_distance, rolls[0], rolls[1]])

	# Check if the charge roll is sufficient
	var target_ids = [heroic_intervention_charging_unit_id]
	var roll_sufficient = _is_heroic_intervention_roll_sufficient(unit_id, total_distance, target_ids)

	var dice_result = {
		"context": "heroic_intervention_charge_roll",
		"unit_id": unit_id,
		"unit_name": unit_name,
		"rolls": rolls,
		"total": total_distance,
		"targets": target_ids,
		"charge_failed": not roll_sufficient,
	}
	dice_log.append(dice_result)
	emit_signal("dice_rolled", dice_result)

	if not roll_sufficient:
		# Heroic Intervention charge failed
		log_phase_message("HEROIC INTERVENTION charge FAILED for %s (rolled %d)" % [unit_name, total_distance])
		print("ChargePhase: Heroic Intervention charge roll INSUFFICIENT for %s (rolled %d)" % [unit_name, total_distance])

		# Clean up HI state
		heroic_intervention_unit_id = ""
		heroic_intervention_pending_charge = {}
		heroic_intervention_charging_unit_id = ""
		heroic_intervention_player = 0

		return create_result(true, [], "", {
			"dice": [dice_result],
			"heroic_intervention_failed": true,
			"heroic_intervention_unit_id": unit_id,
		})

	# Roll sufficient — enable movement
	print("ChargePhase: Heroic Intervention charge roll SUFFICIENT for %s (rolled %d)" % [unit_name, total_distance])
	emit_signal("charge_path_tools_enabled", unit_id, total_distance)

	return create_result(true, [], "", {
		"dice": [dice_result],
		"heroic_intervention_roll_success": true,
		"heroic_intervention_unit_id": unit_id,
		"heroic_intervention_distance": total_distance,
	})

func _process_decline_heroic_intervention(action: Dictionary) -> Dictionary:
	var player = action.get("player", heroic_intervention_player)
	log_phase_message("Player %d declined HEROIC INTERVENTION" % player)

	# Clear HI state
	awaiting_heroic_intervention = false
	heroic_intervention_player = 0
	heroic_intervention_charging_unit_id = ""
	heroic_intervention_unit_id = ""
	heroic_intervention_pending_charge = {}

	return create_result(true, [])

func _process_heroic_intervention_charge_roll(action: Dictionary) -> Dictionary:
	# This action is for manual triggering of the charge roll if needed
	# In the current flow, the roll is done automatically in _process_use_heroic_intervention
	# This is kept for compatibility with potential future UI changes
	return create_result(true, [])

func _process_apply_heroic_intervention_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})
	var per_model_rotations = payload.get("per_model_rotations", {})

	if heroic_intervention_pending_charge.is_empty():
		return create_result(false, [], "No Heroic Intervention charge data")

	var charge_data = heroic_intervention_pending_charge

	# Final validation
	var validation = _validate_charge_movement_constraints(unit_id, per_model_paths, charge_data)
	if not validation.valid:
		var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
		log_phase_message("Heroic Intervention charge failed for %s: %s" % [unit_name, validation.errors[0]])

		# Clean up HI state
		heroic_intervention_unit_id = ""
		heroic_intervention_pending_charge = {}
		heroic_intervention_charging_unit_id = ""
		heroic_intervention_player = 0

		emit_signal("charge_resolved", unit_id, false, {
			"reason": validation.errors[0],
			"heroic_intervention": true,
		})
		return create_result(true, [])

	# Apply successful HI charge movement
	var changes = []

	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var final_pos = path[-1]
		var model_index = _get_model_index(unit_id, model_id)
		if model_index < 0:
			continue

		changes.append({
			"op": "set",
			"path": "units.%s.models.%d.position" % [unit_id, model_index],
			"value": {"x": final_pos[0], "y": final_pos[1]}
		})

		if per_model_rotations.has(model_id):
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.rotation" % [unit_id, model_index],
				"value": per_model_rotations[model_id]
			})

	# Mark unit as charged BUT NOT fights_first (key difference for Heroic Intervention)
	# Per 10e rules: Heroic Intervention does NOT grant Fights First
	changes.append({
		"op": "set",
		"path": "units.%s.flags.charged_this_turn" % unit_id,
		"value": true
	})
	# Explicitly do NOT set fights_first — this is the key mechanical difference
	# The unit fights in the normal (Remaining Combats) subphase

	# Mark as heroic intervention unit for tracking
	changes.append({
		"op": "set",
		"path": "units.%s.flags.heroic_intervention" % unit_id,
		"value": true
	})

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("HEROIC INTERVENTION successful: %s counter-charged into engagement range" % unit_name)

	emit_signal("charge_resolved", unit_id, true, {
		"distance": charge_data.distance,
		"heroic_intervention": true,
	})

	# Clean up HI state
	heroic_intervention_unit_id = ""
	heroic_intervention_pending_charge = {}
	heroic_intervention_charging_unit_id = ""
	heroic_intervention_player = 0

	return create_result(true, changes)

func _is_heroic_intervention_roll_sufficient(unit_id: String, rolled_distance: int, target_ids: Array) -> bool:
	"""Check if the HI charge roll is sufficient to reach engagement range of the target."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
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

				var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
				# T3-9: Use barricade-aware engagement range
				var model_pos = _get_model_position(model)
				var target_pos = _get_model_position(target_model)
				var effective_er = _get_effective_engagement_range(model_pos, target_pos)
				var distance_to_close = distance_inches - effective_er
				if distance_to_close <= rolled_distance:
					return true

	return false

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
