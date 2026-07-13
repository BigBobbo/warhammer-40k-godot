extends BasePhase
class_name ChargePhase

const BasePhase = preload("res://phases/BasePhase.gd")


# ChargePhase - Full implementation of the Charge phase following 10e rules
# Supports: Charge declarations, 2D6 charge rolls, movement validation, engagement range

# Floating-point tolerance for distance cap checks (< 1px)
const MOVEMENT_CAP_EPSILON: float = 0.02

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
signal piston_driven_brutality_resolved(unit_id: String, result: Dictionary)  # OA-36: Piston-driven Brutality mortal wounds result

# ISS-002: engagement range comes from GameConstants.engagement_range_inches()
# (edition-dependent). Do not re-declare it as a local constant.
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
var heroic_intervention_charging_unit_id: String = ""  # The enemy unit that just charged (10e window; "" at the 11e end-of-phase window)
var heroic_intervention_unit_id: String = ""  # Unit selected for HI (set on USE)
var heroic_intervention_pending_charge: Dictionary = {}  # Pending charge data for HI unit
# 11e 15.11: HI happens once, at the END of the opponent's Charge phase,
# with a mode choice — not after each enemy charge like 10e.
var _hi_end_phase_offered: bool = false        # the end-of-phase window has been offered
var _hi_pending_phase_complete: bool = false   # END_CHARGE arrived; complete the phase after HI resolves

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
const FAIL_MUST_END_CLOSER = "MUST_END_CLOSER"
const FAIL_WALL = "WALL"
const FAIL_TERRAIN = "TERRAIN"

# Human-readable explanations for each failure category (teaches players the rules)
# "{er}" is substituted with the edition's engagement range by get_failure_category_tooltip.
const FAIL_CATEGORY_TOOLTIPS = {
	FAIL_INSUFFICIENT_ROLL: "The 2D6 charge roll was too low for any model to reach engagement range ({er}) of the declared targets. Try charging closer targets or units with fewer declared targets.",
	FAIL_DISTANCE: "A model's movement path exceeded the rolled charge distance. Each model can move at most the rolled distance in inches during a charge move.",
	FAIL_ENGAGEMENT: "The charging unit must end its move with at least one model within engagement range ({er}) of EVERY declared target. If you declared multiple targets, you must reach all of them.",
	FAIL_NON_TARGET_ER: "No charging model may end within engagement range ({er}) of an enemy unit that was NOT declared as a charge target. Plan your movement to avoid non-target enemies.",
	FAIL_COHERENCY: "All models in the unit must maintain unit coherency (within 2\" horizontally and 5\" vertically of at least one other model) after the charge move completes.",
	FAIL_OVERLAP: "Models cannot end their charge movement overlapping with other models (friendly or enemy). Reposition to avoid base overlaps.",
	FAIL_BASE_CONTACT: "Charge Move 11.04: any charging model that CAN end its move within 1\" of a charge target (while still satisfying every other charge condition) MUST do so. Drag that model in — it snaps to base contact, which always satisfies the 1\" requirement.",
	FAIL_DIRECTION: "Each model making a charge move must end that move closer to at least one of the charge target units than it started. Reposition the model so it ends nearer to a declared target.",
	FAIL_MUST_END_CLOSER: "Each model making a charge move must end closer to at least one declared charge target than it started. Models cannot move laterally or away from all targets during a charge.",
	FAIL_WALL: "Models cannot end their charge movement overlapping a terrain wall. Models may move through walls during the charge (per their keywords), but the final position must be clear of every wall segment.",
	FAIL_TERRAIN: "A model's charge path passes through a solid terrain feature (such as a ruin wall) it cannot cross. Infantry-type units move through dense terrain freely and Fly units charge over it; other units must go around.",
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
	_hi_end_phase_offered = false
	_hi_pending_phase_complete = false
	awaiting_tank_shock = false
	tank_shock_vehicle_unit_id = ""
	tank_shock_pending_changes = []

	# Apply unit ability effects for charge phase
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.CHARGE)

	# Refresh snapshot after ability effects mutated GameState flags
	game_state_snapshot = GameState.create_snapshot()

	_initialize_charge()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Charge Phase")

	# Clear unit ability effect flags
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_end(GameStateData.Phase.CHARGE)

	# P3-106: Clear stratagem phase-scoped effects at end of Charge phase
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		strat_manager.on_phase_end(GameStateData.Phase.CHARGE)

	# T-056: deliberately do NOT clear `charged_this_turn` / `fights_first` flags
	# here. The fight phase reads them to compute fight order; clearing on charge
	# exit was a bug that made charging units lose Fights First in the very next
	# subphase. The flags are scoped to the player turn and cleared by
	# TurnManager / Round transition, not by phase exit.

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
		"USE_STRATAGEM":
			return _validate_use_stratagem(action)
		"END_SHOOTING":
			# Idempotent no-op: previous phase auto-advanced before END_SHOOTING was dispatched.
			return {"valid": true}
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
		"USE_STRATAGEM":
			return _process_use_stratagem(action)
		"END_SHOOTING":
			return create_result(true, [], "")
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
	
	# ISS-049 step 2 (11e 11.02): targets are selected AFTER the charge
	# roll — declaring with an empty target list is legal at edition >= 11
	# (it commits the unit to charging; selectable targets arrive with the
	# roll). Pre-declared targets are still validated below.
	if target_ids.is_empty() and GameConstants.edition < 11:
		return {"valid": false, "errors": ["Missing target_unit_ids"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if GameConstants.edition >= 11:
		var el_11e = MoveTypes.get_type("charge").eligible(unit_id, GameState.state)
		if not el_11e.eligible:
			return {"valid": false, "errors": el_11e.reasons}
	elif not _can_unit_charge(unit):
		return {"valid": false, "errors": ["Unit cannot charge"]}

	if unit_id in completed_charges:
		return {"valid": false, "errors": ["Unit has already charged this phase"]}

	# A unit whose 2D6 are already rolled must resolve that charge (move or
	# skip) — re-declaring would grant a free re-roll of the charge dice.
	if pending_charges.has(unit_id) and pending_charges[unit_id].has("distance"):
		return {"valid": false, "errors": ["Charge roll already made — complete the charge move or skip the unit"]}

	# No new declarations while a Fire Overwatch decision is pending (it would
	# clobber the overwatch bookkeeping for the charge that triggered it).
	if awaiting_fire_overwatch:
		return {"valid": false, "errors": ["Awaiting Fire Overwatch decision"]}

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

	# Reaction windows pause the flow — no rolling while a decision is pending.
	if awaiting_ability_reroll or awaiting_reroll_decision:
		return {"valid": false, "errors": ["Awaiting re-roll decision"]}
	if awaiting_fire_overwatch:
		return {"valid": false, "errors": ["Awaiting Fire Overwatch decision"]}

	# The 2D6 are rolled once per declared charge — a repeat CHARGE_ROLL would
	# grant a free re-roll (only Command Re-roll / abilities may re-roll).
	if pending_charges[unit_id].has("distance"):
		return {"valid": false, "errors": ["Charge roll already made for this unit"]}

	return {"valid": true, "errors": []}

func _validate_apply_charge_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if per_model_paths.is_empty():
		return {"valid": false, "errors": ["Missing per_model_paths"]}

	# A Heroic Intervention unit's charge lives in
	# heroic_intervention_pending_charge, not pending_charges — route any
	# APPLY_CHARGE_MOVE sent for it to the HI validator.
	if unit_id == heroic_intervention_unit_id and not heroic_intervention_pending_charge.is_empty():
		return _validate_apply_heroic_intervention_move(action)

	if not pending_charges.has(unit_id):
		return {"valid": false, "errors": ["No charge roll made for unit"]}
	
	var charge_data = pending_charges[unit_id]
	if not charge_data.has("distance"):
		return {"valid": false, "errors": ["No charge distance available"]}

	# ISS-049 step 2 (11e 11.02): the post-roll target selection arrives
	# with the move; it must come from the selectable list (within 12"
	# AND within the roll). pending_charges is phase-local scratch, so
	# recording the selection here (before constraint validation, which
	# reads it) is safe.
	if GameConstants.edition >= 11:
		var sel_targets: Array = payload.get("target_unit_ids", [])
		if not sel_targets.is_empty():
			var selectable: Array = charge_data.get("selectable_targets", [])
			for tid in sel_targets:
				if not tid in selectable:
					return {"valid": false, "errors": ["Target %s is not selectable (must be within 12\" and within the charge roll, 11.02)" % tid]}
			charge_data.targets = sel_targets
		if charge_data.targets.is_empty():
			return {"valid": false, "errors": ["No charge targets selected (11e: select targets after the roll)"]}
	
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

	# Store charge declaration. declared_targets preserves the original
	# declaration so the 11e roll-resolution can re-filter it against the
	# FINAL roll total (after re-rolls / +N bonuses), not the first raw 2D6.
	pending_charges[unit_id] = {
		"targets": target_ids,
		"declared_targets": target_ids.duplicate(),
		"declared_at": Time.get_unix_time_from_system()
	}

	# Track once-per-battle ability usage when a unit charges after advancing
	var declaring_unit = get_unit(unit_id)
	var declaring_flags = declaring_unit.get("flags", {})
	if declaring_flags.get("advanced", false) and EffectPrimitivesData.has_effect_advance_and_charge(declaring_unit):
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr:
			ability_mgr.mark_once_per_battle_used(unit_id, "Martial Inspiration")
			DebugLogger.info(str("ChargePhase: Marked Martial Inspiration as used for unit %s (charged after advancing)" % unit_id))

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

	# Log charge declaration to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(unit.get("owner", 0))
		game_event_log.add_player_entry(owner, "%s declares charge against %s" % [unit_name, ", ".join(target_names)])

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
		DebugLogger.info(str("ChargePhase: Sneaky Surprise — %s cannot be targeted by Fire Overwatch" % unit_name))
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
					DebugLogger.info(str("ChargePhase: Fire Overwatch opportunity — Player %d has %d eligible units" % [defending_player, ow_eligible.size()]))

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
	# Issue #329: honor payload.rng_seed (multiplayer + tests); fall back to test_mode_seed
	var rng_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var rng = RulesEngine.RNGService.new(rng_seed)
	var rolls = rng.roll_d6(2)
	var total_distance = rolls[0] + rolls[1]

	# Store rolled distance
	charge_data.distance = total_distance
	charge_data.dice_rolls = rolls

	# ISS-049 step 2 (11e 11.02): the roll IS the maximum distance — targets
	# are selected after the roll, from enemies within 12" AND within the
	# roll (the pg-37 example). This list is PROVISIONAL so paused re-roll
	# flows can introspect it; _resolve_charge_roll recomputes it from the
	# FINAL total (after re-rolls / +N charge bonuses) — resolving from the
	# raw first 2D6 made re-rolled/bonused charges fail against a stale list.
	if GameConstants.edition >= 11:
		var tmpl_11e = MoveTypes.get_type("charge")
		charge_data["selectable_targets"] = tmpl_11e._targets_within(unit_id, GameState.state, ChargeMove11e.selectable_distance_ceiling(float(total_distance)))

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var target_ids = charge_data.targets

	log_phase_message("Charge roll: 2D6 = %d (%d + %d)" % [total_distance, rolls[0], rolls[1]])

	# Reset ability reroll tracking for this charge attempt
	ability_reroll_used = false

	# Check if unit has ability-granted charge reroll (e.g. Swift Onslaught,
	# Plummeting Descent, Green Tide's Bloodthirsty Belligerence while the
	# bearer's unit counts as 10+ models, or the Prey rule / DAT ONE'S EVEN
	# BIGGA! for a BEAST SNAGGA unit charging its owner's Prey)
	var unit_data = get_unit(unit_id)
	var has_ability_reroll = EffectPrimitivesData.has_effect_reroll_charge(unit_data) \
		or FactionAbilityManager.unit_has_green_tide_charge_reroll(unit_data, GameState.state.get("units", {})) \
		or FactionAbilityManager.unit_has_prey_charge_reroll(unit_data, target_ids, GameState.state.get("units", {})) \
		or FactionAbilityManager.unit_has_detachment_charge_reroll(unit_data)

	if has_ability_reroll:
		# Offer free ability reroll first (before Command Re-roll)
		awaiting_ability_reroll = true
		ability_reroll_unit_id = unit_id

		# OA-23: Determine which ability granted the charge reroll for display
		var reroll_ability_name = _get_charge_reroll_ability_name(unit_id)

		var min_distance = _get_min_distance_to_any_target(unit_id, target_ids)
		var needed = max(0.0, min_distance - GameConstants.engagement_range_inches())
		var context_text = "Need %.1f\" to reach engagement range (nearest target %.1f\" away)" % [needed, min_distance]

		var roll_context = {
			"roll_type": "charge_roll",
			"original_rolls": rolls,
			"total": total_distance,
			"unit_id": unit_id,
			"unit_name": unit_name,
			"context_text": context_text,
			"min_distance": min_distance,
			"ability_name": reroll_ability_name,
		}

		DebugLogger.info(str("ChargePhase: Ability reroll (%s) available for %s — pausing for player decision" % [reroll_ability_name, unit_name]))
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
		DebugLogger.info(str("ChargePhase: Ability reroll already used for %s — cannot Command Re-roll (dice re-rolled once rule)" % unit_name))
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
		var needed = max(0.0, min_distance - GameConstants.engagement_range_inches())
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

		DebugLogger.info(str("ChargePhase: Command Re-roll available for %s — pausing for player decision" % unit_name))
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

	# Issue #372: apply persistent +N to charge roll (e.g. 'ERE WE GO grants +2).
	# The dice rolls themselves remain the raw 2D6 (for display); the total is
	# what feeds the engagement-range feasibility check and movement budget.
	var unit_for_charge_bonus = get_unit(unit_id)
	var charge_bonus = EffectPrimitivesData.get_effect_plus_charge(unit_for_charge_bonus)
	# Runnin' Boots (Blitz Brigade): +1 to Charge rolls while the bearer's
	# unit disembarked from a Transport this turn.
	charge_bonus += FactionAbilityManager.runnin_boots_charge_bonus(unit_for_charge_bonus, GameState.state.get("units", {}))
	# Boarding Ramps (Rollin' Deff): +1 to Charge rolls for a unit that
	# disembarked this turn from the WAGON bearing the enhancement.
	charge_bonus += FactionAbilityManager.boarding_ramps_charge_bonus(unit_for_charge_bonus, GameState.state.get("units", {}))
	if charge_bonus > 0:
		total_distance += charge_bonus
		charge_data.distance = total_distance
		log_phase_message("Charge modifier: +%d → %d total" % [charge_bonus, total_distance])
		DebugLogger.info(str("ChargePhase: PLUS_CHARGE active for %s — base %d + %d = %d" % [
			unit_name, charge_data.dice_rolls[0] + charge_data.dice_rolls[1], charge_bonus, total_distance
		]))

	# ISS-049 step 2 (11e 11.02): targets are selected after the roll, from
	# enemies within 12" AND reachable by the roll. Reachable means the roll can
	# close the gap to ENGAGEMENT RANGE (not full base contact), so the raw-gap
	# ceiling is min(12, roll + ER) — see ChargeMove11e.selectable_distance_ceiling.
	# Computed HERE — from the FINAL total (after re-rolls and +N bonuses) — and
	# the original declaration is re-filtered against it. Pre-declared targets the
	# roll cannot reach are dropped; ones a re-roll newly reaches come back.
	if GameConstants.edition >= 11:
		var tmpl_11e = MoveTypes.get_type("charge")
		var selectable: Array = tmpl_11e._targets_within(unit_id, GameState.state, ChargeMove11e.selectable_distance_ceiling(float(total_distance)))
		charge_data["selectable_targets"] = selectable
		var declared: Array = charge_data.get("declared_targets", charge_data.targets)
		if not declared.is_empty():
			var kept: Array = []
			for tid in declared:
				if tid in selectable:
					kept.append(tid)
				else:
					log_phase_message("[11e] Charge target %s beyond the roll (%d\") — dropped" % [tid, total_distance])
			charge_data.targets = kept
			target_ids = kept
		log_phase_message("[11e] Selectable charge targets after roll of %d: %s" % [total_distance, str(selectable)])
		# charge_targets_available carries a Dictionary (target_id -> data) —
		# passing the raw `selectable` Array made Godot drop the signal call
		# ("Cannot convert argument 2 from Array to Dictionary") on every
		# post-roll re-target, so the controller never saw the filtered list.
		var selectable_dict = {}
		var all_eligible_after_roll = _get_eligible_targets_for_unit(unit_id)
		for tid in selectable:
			if all_eligible_after_roll.has(tid):
				selectable_dict[tid] = all_eligible_after_roll[tid]
		emit_signal("charge_targets_available", unit_id, selectable_dict)

	# ── Per-target reachability verdict ─────────────────────────────────
	# A charge must end engaged with EVERY declared target (10e move validator +
	# 11e 11.04). The previous check only asked whether the NEAREST target was
	# reachable, so an over-declared charge (e.g. 3 targets, roll reaches only 1)
	# logged a false SUCCESS and then either silently failed at move-apply (10e)
	# or had its far targets quietly dropped (11e). Decompose per declared target
	# so the verdict, the displayed "needed" distance, and the player-facing
	# message reflect the binding (farthest) target.
	var declared_targets: Array = charge_data.get("declared_targets", target_ids)
	var per_target := _per_target_charge_requirements(unit_id, declared_targets, float(total_distance))
	var unreachable_targets: Array = []
	var needed_for_all: float = 0.0
	for tid in declared_targets:
		var info: Dictionary = per_target.get(tid, {})
		needed_for_all = maxf(needed_for_all, float(info.get("cost", INF)))
		if not info.get("reachable", false):
			unreachable_targets.append(tid)

	var roll_sufficient: bool
	var min_distance: float

	if GameConstants.edition >= 11:
		# 11e (11.02): targets beyond the roll were already filtered out of
		# target_ids above; the charge proceeds against the reachable subset.
		# Preserve the original cost-based verdict exactly and only ADD the
		# dropped-target reporting so a partial charge is never a silent surprise.
		roll_sufficient = _is_charge_roll_sufficient(unit_id, total_distance)
		min_distance = _get_min_distance_to_any_target(unit_id, target_ids)
		if target_ids.is_empty():
			# ISS-049 step 2 (11e 11.02): with no pre-declared targets, success is
			# judged against the SELECTABLE list (enemies within 12" AND the roll)
			# — the player picks targets with the move. Only an empty selectable
			# list is a failed charge.
			var selectable_11e: Array = charge_data.get("selectable_targets", [])
			roll_sufficient = not selectable_11e.is_empty()
			var md_ids: Array = selectable_11e
			if md_ids.is_empty():
				md_ids = charge_data.get("declared_targets", [])
			min_distance = _get_min_distance_to_any_target(unit_id, md_ids)
			log_phase_message("[11e] No pre-declared targets — charge %s (selectable: %s)" % [
				"continues, select targets with the move" if roll_sufficient else "FAILED (nothing reachable)",
				str(selectable_11e)])
		# Report declared targets dropped as out-of-reach (partial charge).
		var dropped: Array = []
		for tid in declared_targets:
			if not tid in target_ids:
				dropped.append(tid)
		if roll_sufficient and not dropped.is_empty() and not target_ids.is_empty():
			_report_partial_charge(unit_id, target_ids, dropped, total_distance, per_target)
	else:
		# 10e: every declared target must be reachable or the whole charge fails
		# (the move validator would reject it anyway — fail it here, with a clear
		# reason, instead of logging a false SUCCESS the player cannot act on).
		roll_sufficient = not declared_targets.is_empty() and unreachable_targets.is_empty()
		min_distance = needed_for_all if needed_for_all < INF else _get_min_distance_to_any_target(unit_id, declared_targets)

	# Build dice result with success/failure flag so clients don't need to recompute
	var dice_result = {
		"context": "charge_roll",
		"unit_id": unit_id,
		"unit_name": unit_name,
		"rolls": rolls,
		"total": total_distance,
		"charge_bonus": charge_bonus,
		"targets": target_ids,
		"charge_failed": not roll_sufficient,
		"min_distance": min_distance,
	}

	# Include command reroll original rolls for visualization (P3-118)
	if charge_data.has("command_reroll_original"):
		dice_result["command_reroll"] = true
		dice_result["original_rolls"] = charge_data["command_reroll_original"]
		charge_data.erase("command_reroll_original")

	dice_log.append(dice_result)

	# Log charge roll result to GameEventLog
	var charge_event_log = get_node_or_null("/root/GameEventLog")
	var charge_owner = int(get_unit(unit_id).get("owner", 0))
	if charge_event_log:
		var target_name_list = []
		for tid in target_ids:
			target_name_list.append(get_unit(tid).get("meta", {}).get("name", tid))
		if roll_sufficient:
			charge_event_log.add_player_entry(charge_owner,
				"%s charge roll: [%d, %d] = %d\" vs %.1f\" needed - SUCCESS" % [
					unit_name, rolls[0], rolls[1], total_distance, min_distance])
		elif GameConstants.edition < 11 and unreachable_targets.size() > 0 and declared_targets.size() > 1:
			# 10e over-declared multi-target charge: name the unreachable target(s)
			# so the player learns a charge must reach EVERY declared target. (In
			# 11e unreachable targets are dropped and the charge proceeds against
			# the subset, so a FAILED there means nothing was reachable.)
			charge_event_log.add_player_entry(charge_owner,
				"%s charge roll: [%d, %d] = %d\" - FAILED (need %.1f\" to reach ALL targets; out of range: %s)" % [
					unit_name, rolls[0], rolls[1], total_distance, min_distance, _format_target_names(unreachable_targets)])
		else:
			charge_event_log.add_player_entry(charge_owner,
				"%s charge roll: [%d, %d] = %d\" vs %.1f\" needed - FAILED" % [
					unit_name, rolls[0], rolls[1], total_distance, min_distance])

	if not roll_sufficient:
		# Charge roll failed — record structured failure, clean up state, broadcast
		DebugLogger.info(str("ChargePhase: Charge roll INSUFFICIENT for %s (rolled %d, min dist %.1f\")" % [unit_name, total_distance, min_distance]))
		record_insufficient_roll_failure(unit_id, total_distance, rolls, target_ids, min_distance, _target_names_array(unreachable_targets))

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
	DebugLogger.info(str("ChargePhase: Charge roll SUFFICIENT for %s (rolled %d)" % [unit_name, total_distance]))
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
	# Issue #329: honor payload.rng_seed
	var rng_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var rng = RulesEngine.RNGService.new(rng_seed)
	var new_rolls = rng.roll_d6(2)
	var new_total = new_rolls[0] + new_rolls[1]

	# Update the charge data with new rolls
	charge_data.distance = new_total
	charge_data.dice_rolls = new_rolls

	log_phase_message("SWIFT ONSLAUGHT: Charge re-rolled from %d (%s) → %d (%d + %d)" % [
		old_rolls[0] + old_rolls[1], str(old_rolls), new_total, new_rolls[0], new_rolls[1]
	])

	DebugLogger.info(str("ChargePhase: ABILITY REROLL (Swift Onslaught) — %s charge re-rolled: %s → %s (total %d → %d)" % [
		unit_name, str(old_rolls), str(new_rolls), old_rolls[0] + old_rolls[1], new_total
	]))

	# Dice already re-rolled once — cannot Command Re-roll per 10e rules
	return _resolve_charge_roll(unit_id)

func _process_decline_ability_reroll(action: Dictionary) -> Dictionary:
	"""Process DECLINE_ABILITY_REROLL: skip free reroll, proceed to Command Re-roll check."""
	var unit_id = ability_reroll_unit_id
	awaiting_ability_reroll = false
	ability_reroll_unit_id = ""

	if not pending_charges.has(unit_id):
		return create_result(false, [], "No pending charge for ability reroll decline")

	DebugLogger.info(str("ChargePhase: Ability reroll DECLINED for %s — checking Command Re-roll" % unit_id))

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
			DebugLogger.info(str("ChargePhase: Command Re-roll failed: %s" % strat_result.get("error", "")))
			# Fall through to resolve with original roll
			return _resolve_charge_roll(unit_id)

	# Re-roll the 2D6
	# Issue #329: honor payload.rng_seed
	var rng_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var rng = RulesEngine.RNGService.new(rng_seed)
	var new_rolls = rng.roll_d6(2)
	var new_total = new_rolls[0] + new_rolls[1]

	# Update the charge data with new rolls and store original for visualization
	charge_data.distance = new_total
	charge_data.dice_rolls = new_rolls
	charge_data["command_reroll_original"] = old_rolls

	log_phase_message("COMMAND RE-ROLL: Charge re-rolled from %d (%s) → %d (%d + %d)" % [
		old_rolls[0] + old_rolls[1], str(old_rolls), new_total, new_rolls[0], new_rolls[1]
	])

	DebugLogger.info(str("ChargePhase: COMMAND RE-ROLL — %s charge re-rolled: %s → %s (total %d → %d)" % [
		unit_name, str(old_rolls), str(new_rolls), old_rolls[0] + old_rolls[1], new_total
	]))

	# Now resolve the charge with the new roll
	return _resolve_charge_roll(unit_id)

func _process_decline_command_reroll(action: Dictionary) -> Dictionary:
	"""Process DECLINE_COMMAND_REROLL: resolve charge with original dice."""
	var unit_id = reroll_pending_unit_id
	awaiting_reroll_decision = false
	reroll_pending_unit_id = ""

	if not pending_charges.has(unit_id):
		return create_result(false, [], "No pending charge for reroll decline")

	DebugLogger.info(str("ChargePhase: Command Re-roll DECLINED for %s — resolving with original roll" % unit_id))

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
		DebugLogger.info(str("ChargePhase: Tank Shock failed: %s" % ts_result.get("error", "")))
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

	DebugLogger.info("ChargePhase: Tank Shock DECLINED")

	# Still need to check Heroic Intervention
	return _check_heroic_intervention_after_tank_shock(vehicle_unit_id, pending_changes)

func _check_heroic_intervention_after_tank_shock(vehicle_unit_id: String, pending_changes: Array) -> Dictionary:
	"""After Tank Shock resolves (or is declined), check Heroic Intervention for the defender."""
	var charging_unit = get_unit(vehicle_unit_id)
	var charging_owner = int(charging_unit.get("owner", 0))
	var defending_player = 2 if charging_owner == 1 else 1

	# 11e (15.11): HI happens at the END of the Charge phase, not per charge
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager and GameConstants.edition < 11:
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

# ============================================================================
# SPIKED RAM (OA-50)
# ============================================================================
# "Each time this model ends a Charge move, select one enemy unit within
# Engagement Range of it and roll one D6: on a 2-5, that unit suffers D3
# mortal wounds; on a 6, that unit suffers 3 mortal wounds."
# Applied automatically to the first charge target (most common case: one target).

func _unit_has_spiked_ram(unit: Dictionary) -> bool:
	"""Check if a unit has the Spiked Ram ability (Trukk)."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Spiked Ram":
			return true
	return false

func _apply_spiked_ram_if_applicable(unit_id: String, charge_targets: Array, changes: Array, rng_seed: int = -1) -> void:
	"""OA-50: If charging unit has Spiked Ram, roll D6 and deal mortal wounds to first charge target."""
	var unit = get_unit(unit_id)
	if not _unit_has_spiked_ram(unit):
		return

	if charge_targets.is_empty():
		return

	# Select first charge target (auto-select: Trukk typically charges one unit)
	var target_unit_id = charge_targets[0]
	var target_unit = get_unit(target_unit_id)
	if target_unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	# Issue #329: route through RNGService; seed forwarded by caller (action.payload.rng_seed)
	var rng = RulesEngine.RNGService.new(rng_seed)
	var roll = rng.roll_d6(1)[0]

	var mortal_wounds = 0
	if roll >= 6:
		mortal_wounds = 3
	elif roll >= 2:
		# D3 mortal wounds: roll D6, divide by 2 (round up)
		var d3_roll = rng.roll_d6(1)[0]
		mortal_wounds = ceili(float(d3_roll) / 2.0)

	log_phase_message("SPIKED RAM: %s rolled %d → %d mortal wound(s) on %s" % [unit_name, roll, mortal_wounds, target_name])
	DebugLogger.info(str("ChargePhase: SPIKED RAM — %s rolled %d → %d mortal wound(s) on %s" % [unit_name, roll, mortal_wounds, target_name]))

	if mortal_wounds <= 0:
		log_phase_message("SPIKED RAM: %s rolled 1 — no mortal wounds" % unit_name)
		return

	var board = GameState.create_snapshot()
	var mw_result = RulesEngine.apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)
	var mw_diffs = mw_result.get("diffs", [])
	if not mw_diffs.is_empty():
		PhaseManager.apply_state_changes(mw_diffs)
		changes.append_array(mw_diffs)
		DebugLogger.info(str("ChargePhase: SPIKED RAM applied %d mortal wound(s) to %s (%d casualties)" % [mortal_wounds, target_unit_id, mw_result.get("casualties", 0)]))

func _process_apply_charge_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})
	var per_model_rotations = payload.get("per_model_rotations", {})

	# Enhanced validation - check for empty per_model_paths
	if per_model_paths.is_empty():
		DebugLogger.info("ERROR: No model paths provided for charge movement")
		return create_result(false, [], "No model paths provided")

	# Heroic Intervention counter-charge routed through the generic action
	if unit_id == heroic_intervention_unit_id and not heroic_intervention_pending_charge.is_empty():
		return _process_apply_heroic_intervention_move(action)

	if not pending_charges.has(unit_id):
		DebugLogger.info(str("ERROR: No pending charge data found for unit ", unit_id))
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
		DebugLogger.info(str("ChargePhase: Recorded structured failure - [%s] %s" % [primary_category, validation.errors[0]]))

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
			DebugLogger.info(str("WARNING: Invalid path for model ", model_id, " - skipping"))
			continue

		var final_pos = path[-1]  # Last position in path
		var model_index = _get_model_index(unit_id, model_id)

		if model_index < 0:
			DebugLogger.info(str("ERROR: Invalid model_index for ", model_id, " - model not found in unit"))
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

	# Attached CHARACTER(s) ride the charge with their bodyguard — the whole
	# Attached unit moves as one (e.g. a Shield-Captain leading Vertus Praetors).
	# Appended before the tank-shock / heroic-intervention snapshots below so
	# their distance checks see the character's new position too.
	changes.append_array(_charge_attached_character_changes(unit_id, per_model_paths))

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

	# SPIKED RAM (OA-50): After charge move, deal mortal wounds to a charge target.
	# "Each time this model ends a Charge move, select one enemy unit within Engagement Range
	# and roll D6: on 2-5 = D3 mortal wounds; on 6 = 3 mortal wounds."
	# Issue #329: forward action.payload.rng_seed for deterministic test replay
	var apply_seed: int = action.get("payload", {}).get("rng_seed", -1)
	_apply_spiked_ram_if_applicable(unit_id, charge_data.targets, changes, apply_seed)

	# OA-36: Piston-driven Brutality — after Charge move, auto-resolve mortal wounds
	_resolve_piston_driven_brutality_after_charge(unit_id, changes, apply_seed)

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
						int(charging_unit.get("meta", {}).get("stats", {}).get("toughness", 4)),
						ts_targets.size()
					])
					DebugLogger.info(str("ChargePhase: Tank Shock opportunity — Player %d, vehicle %s, %d eligible targets" % [
						charging_owner, vehicle_name, ts_targets.size()
					]))

					emit_signal("tank_shock_opportunity", charging_owner, unit_id, ts_targets)

					var result = create_result(true, changes)
					result["trigger_tank_shock"] = true
					result["awaiting_tank_shock"] = true
					result["tank_shock_player"] = charging_owner
					result["tank_shock_vehicle_unit_id"] = unit_id
					result["tank_shock_eligible_targets"] = ts_targets
					return result

	# Check if Heroic Intervention is available for the defending player
	# Per 10e rules: "just after an enemy unit ends a Charge move".
	# 11e (15.11) moved HI to the END of the Charge phase — see
	# _process_end_charge; the per-charge window is 10e-only.
	if strat_manager and GameConstants.edition < 11:
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

# ── Attached characters ride the charge ─────────────────────────────
# An Attached unit (bodyguard + CHARACTER leader, e.g. Vertus Praetors led by
# a Shield-Captain) is a single unit: when the bodyguard makes its Charge move
# the attached character(s) move with it. ChargePhase's drag UI only positions
# the bodyguard's own models, so — mirroring MovementPhase._move_attached_
# characters — we ride the character models along by the bodyguard's movement
# delta and grant them the same charge flags. Without this the character is
# left behind, splitting the unit apart (it looks like the attachment broke).
func _charge_attached_character_changes(bodyguard_id: String, per_model_paths: Dictionary, grant_fights_first: bool = true) -> Array:
	var changes = []
	var bodyguard = get_unit(bodyguard_id)
	if bodyguard.is_empty():
		return changes
	var attached_chars = bodyguard.get("attachment_data", {}).get("attached_characters", [])
	if attached_chars.is_empty():
		return changes

	var move_delta = _charge_bodyguard_delta(bodyguard_id, per_model_paths)
	if move_delta == null:
		DebugLogger.info(str("ChargePhase: could not determine charge delta for attached characters of %s" % bodyguard_id))
		return changes

	for char_id in attached_chars:
		var char_unit = get_unit(str(char_id))
		if char_unit.is_empty():
			continue
		var char_models = char_unit.get("models", [])
		for i in range(char_models.size()):
			var model = char_models[i]
			if not model.get("alive", true):
				continue
			if model.get("position") == null:
				continue
			var model_pos = _get_model_position(model)
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [str(char_id), i],
				"value": {"x": model_pos.x + move_delta.x, "y": model_pos.y + move_delta.y}
			})
		# The whole Attached unit charged — the character gets the same flags.
		# Heroic Intervention grants charged_this_turn but NOT fights_first.
		changes.append({
			"op": "set",
			"path": "units.%s.flags.charged_this_turn" % str(char_id),
			"value": true
		})
		if grant_fights_first:
			changes.append({
				"op": "set",
				"path": "units.%s.flags.fights_first" % str(char_id),
				"value": true
			})
		var char_name = char_unit.get("meta", {}).get("name", str(char_id))
		DebugLogger.info(str("ChargePhase: attached character %s rode the charge of %s (delta %s)" % [char_name, bodyguard_id, str(move_delta)]))
	return changes

# Movement delta of a charging bodyguard: (end - start) of its first moved
# model in model order. Returns null if no model had a usable path.
func _charge_bodyguard_delta(unit_id: String, per_model_paths: Dictionary):
	var unit = get_unit(unit_id)
	for model in unit.get("models", []):
		var mid = model.get("id", "")
		if not per_model_paths.has(mid):
			continue
		var path = per_model_paths[mid]
		if not (path is Array and path.size() > 0):
			continue
		var end_vec = Vector2(path[-1][0], path[-1][1])
		var start_vec
		if path.size() >= 2:
			start_vec = Vector2(path[0][0], path[0][1])
		else:
			if model.get("position") == null:
				return null
			start_vec = _get_model_position(model)
		return end_vec - start_vec
	return null

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
	# 11e 15.11: HEROIC INTERVENTION happens once, at the END of the
	# opponent's Charge phase (the 10e per-charge window is retired) —
	# offer it to the defender before the phase completes.
	if GameConstants.edition >= 11 and not _hi_end_phase_offered:
		_hi_end_phase_offered = true
		var strat_manager = get_node_or_null("/root/StratagemManager")
		if strat_manager:
			var defending_player = 2 if GameState.get_active_player() == 1 else 1
			var hi_check = strat_manager.is_heroic_intervention_available(defending_player)
			if hi_check.available and strat_manager.has_method("get_heroic_intervention_eligible_units_11e"):
				var hi_eligible = strat_manager.get_heroic_intervention_eligible_units_11e(defending_player)
				if not hi_eligible.is_empty():
					awaiting_heroic_intervention = true
					heroic_intervention_player = defending_player
					heroic_intervention_charging_unit_id = ""  # end-of-phase window: no single charger
					_hi_pending_phase_complete = true
					log_phase_message("[11e 15.11] HEROIC INTERVENTION window at end of Charge phase — Player %d (%d eligible units)" % [defending_player, hi_eligible.size()])
					emit_signal("heroic_intervention_opportunity", defending_player, hi_eligible, "")
					var result = create_result(true, [])
					result["trigger_heroic_intervention"] = true
					result["awaiting_heroic_intervention"] = true
					result["heroic_intervention_player"] = defending_player
					result["heroic_intervention_eligible_units"] = hi_eligible
					result["heroic_intervention_charging_unit_id"] = ""
					return result
				else:
					log_phase_message("[11e 15.11] HI window skipped: Player %d has no eligible units (no unit with an actionable LEAP/FRAY target)" % defending_player)
			elif not hi_check.available:
				log_phase_message("[11e 15.11] HI window skipped: %s" % hi_check.reason)
			else:
				log_phase_message("[11e 15.11] HI window skipped: StratagemManager has no get_heroic_intervention_eligible_units_11e")
		else:
			log_phase_message("[11e 15.11] HI window skipped: no StratagemManager autoload")

	log_phase_message("Ending Charge Phase")
	emit_signal("phase_completed")
	return create_result(true, [])

# 11e: the END_CHARGE that opened the HI window still owes a phase
# completion once HI resolves (used, declined, failed, or moved).
func _complete_phase_after_heroic_intervention_if_pending() -> void:
	if _hi_pending_phase_complete:
		_hi_pending_phase_complete = false
		log_phase_message("Ending Charge Phase (after Heroic Intervention window)")
		emit_signal("phase_completed")

# Helper Methods

func _can_unit_charge(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})

	# Check if unit is destroyed (all models dead)
	if _is_unit_destroyed_check(unit):
		return false

	# Attached CHARACTERs charge as part of their bodyguard unit — they are
	# not independently selectable (they ride the bodyguard's charge move).
	# Mirrors MovementPhase._validate_begin_normal_move.
	if unit.get("attached_to", null) != null:
		return false

	# Check if unit is deployed
	if not (status == GameStateData.UnitStatus.DEPLOYED or
			status == GameStateData.UnitStatus.MOVED or
			status == GameStateData.UnitStatus.SHOT):
		return false
	
	# Turbo Boostas (Speedwaaagh!): a unit that used its turbo cannot declare
	# a charge this turn — a hard lock no advance-and-charge effect (Waaagh!,
	# Adrenaline Junkies) can override.
	if flags.get("turbo_boosted", false):
		return false

	# Check restriction flags
	# cannot_charge is set by both Advance and Fall Back moves, but abilities like
	# Waaagh! (advance_and_charge) or Full Throttle (fall_back_and_charge) can override it.
	if flags.get("cannot_charge", false):
		var can_override = false
		# Adrenaline Junkies (Kult of Speed): Speed Freeks may charge after
		# Advancing or Falling Back. It does NOT override other charge locks
		# (e.g. Wazblasta's post-shooting move).
		var adrenaline = FactionAbilityManager.unit_has_adrenaline_junkies(unit) \
			and not flags.get("wazblasta_no_charge", false)
		if flags.get("advanced", false) and (EffectPrimitivesData.has_effect_advance_and_charge(unit) or adrenaline):
			can_override = true
			DebugLogger.info(str("ChargePhase: Unit %s advanced but has advance_and_charge effect — overriding cannot_charge" % unit.get("id", "unknown")))
		if flags.get("fell_back", false) and (EffectPrimitivesData.has_effect_fall_back_and_charge(unit) or adrenaline):
			can_override = true
			DebugLogger.info(str("ChargePhase: Unit %s fell back but has fall_back_and_charge effect — overriding cannot_charge" % unit.get("id", "unknown")))
		if not can_override:
			return false

	# Units that burned an objective (Scorched Earth) cannot charge this turn
	if flags.get("burned_objective", false):
		return false

	# Units that performed a ritual action (The Ritual) cannot charge this turn
	if flags.get("performed_ritual", false):
		return false

	# Units that performed a terraform action (Terraform) cannot charge this turn
	if flags.get("performed_terraform", false):
		return false

	if flags.get("advanced", false):
		if not EffectPrimitivesData.has_effect_advance_and_charge(unit):
			return false
		else:
			DebugLogger.info(str("ChargePhase: Unit %s advanced but has advance_and_charge effect — eligible to charge" % unit.get("id", "unknown")))

	if flags.get("fell_back", false):
		if not EffectPrimitivesData.has_effect_fall_back_and_charge(unit):
			return false
		else:
			DebugLogger.info(str("ChargePhase: Unit %s fell back but has fall_back_and_charge effect — eligible to charge" % unit.get("id", "unknown")))

	if flags.get("charged_this_turn", false):
		return false

	# P3-32: Embarked units cannot declare charges (they're inside a transport)
	if unit.get("embarked_in", null) != null:
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
		DebugLogger.info(str("[ChargePhase] _is_target_within_charge_range: %s or %s is EMPTY" % [unit_id, target_id]))
		return false

	# Find closest edge-to-edge distance between any models using shape-aware calculations
	var min_distance = INF
	var checked_pairs = 0
	var skipped_null_charger = 0
	var skipped_null_target = 0

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == null:
			skipped_null_charger += 1
			continue

		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position(target_model)
			if target_pos == null:
				skipped_null_target += 1
				continue

			# Use shape-aware distance calculation
			var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
			checked_pairs += 1

			if distance_inches < min_distance:
				min_distance = distance_inches
				if distance_inches <= CHARGE_RANGE_INCHES:
					DebugLogger.info(str("[ChargePhase] CHARGE IN RANGE: %s model %s (pos %s) -> %s model %s (pos %s) = %.2f\"" % [unit_id, model.get("id","?"), str(model_pos), target_id, target_model.get("id","?"), str(target_pos), distance_inches]))

	if checked_pairs == 0:
		DebugLogger.info(str("[ChargePhase] _is_target_within_charge_range: %s -> %s — 0 pairs checked (null_charger=%d, null_target=%d)" % [unit_id, target_id, skipped_null_charger, skipped_null_target]))

	var result = min_distance <= CHARGE_RANGE_INCHES
	DebugLogger.info(str("[ChargePhase] _is_target_within_charge_range: %s -> %s, min_dist=%.2f\", range=%.1f\", eligible=%s" % [unit_id, target_id, min_distance, CHARGE_RANGE_INCHES, str(result)]))
	return result

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
			# Issue #320: Skip off-board units (Reserves / not yet deployed).
			# _get_model_position() coerces null -> Vector2.ZERO, so distance
			# checks alone treat reserved units as if they were at (0,0).
			if not _is_unit_on_board(target_unit):
				continue

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
			var terrain_penalty = _calculate_path_terrain_penalty(path, has_fly, unit_keywords)
			var effective_distance = path_distance + terrain_penalty

			if terrain_penalty > 0.0:
				DebugLogger.info(str("ChargePhase: Model %s terrain penalty: %.1f\" (FLY=%s), effective distance: %.1f\"" % [
					model_id, terrain_penalty, str(has_fly), effective_distance]))

			if effective_distance > rolled_distance + MOVEMENT_CAP_EPSILON:
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

	# 3b. Validate no model ends overlapping a wall. Charging models may move
	# *through* authored wall segments during the charge (path-traversal
	# honors keywords), but no model may *end* on a wall — mirrors the
	# movement-phase endpoint rule and the client-side ChargeController drag
	# gate. Required server-side so APPLY_CHARGE_MOVE / heroic-intervention
	# actions dispatched without the drag UI (multiplayer, tests, AI) still
	# hit the rule.
	var wall_validation = _validate_no_wall_overlaps(unit_id, per_model_paths)
	if not wall_validation.valid:
		errors.append_array(wall_validation.errors)
		for err in wall_validation.errors:
			categorized_errors.append({"category": FAIL_WALL, "detail": err})

	# 3c. ISS-054 (11e 13.06): solid dense terrain blocks the charge PATH of
	# units that cannot traverse it — a Stompa cannot charge through a 5"
	# ruin wall. FLY units charge over terrain, so they are exempt from the
	# path sweep (their endpoints are still checked in 3b). Shape-aware: the
	# whole base is swept along each path segment.
	if not has_fly:
		var terrain_validation = _validate_no_solid_terrain_on_paths(unit_id, per_model_paths, unit_keywords)
		if not terrain_validation.valid:
			errors.append_array(terrain_validation.errors)
			for err in terrain_validation.errors:
				categorized_errors.append({"category": FAIL_TERRAIN, "detail": err})

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

	# 6. Validate each model ends closer to at least one target
	var closer_validation = _validate_must_end_closer(unit_id, per_model_paths, target_ids)
	if not closer_validation.valid:
		errors.append_array(closer_validation.errors)
		for err in closer_validation.errors:
			categorized_errors.append({"category": FAIL_MUST_END_CLOSER, "detail": err})

	return {"valid": errors.is_empty(), "errors": errors, "categorized_errors": categorized_errors}

func _validate_engagement_range_constraints(unit_id: String, per_model_paths: Dictionary, target_ids: Array) -> Dictionary:
	var errors = []
	# "Friendly" is relative to the CHARGING UNIT's owner, not the active
	# player — a Heroic Intervention charge is made by the DEFENDER, and
	# keying on get_current_player() made every defender unit (including the
	# HI unit itself) count as a "non-target enemy", self-rejecting the move.
	var charging_owner = int(get_unit(unit_id).get("owner", get_current_player()))
	var all_units = game_state_snapshot.get("units", {})

	# Check that unit ends within ER of ALL targets
	for target_id in target_ids:
		var target_unit = all_units.get(target_id, {})
		if target_unit.is_empty():
			print("ChargePhase ER_DEBUG: target_id=%s not found in units" % target_id)
			continue

		var unit_in_er_of_target = false

		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit(unit_id, model_id)

				if model.is_empty():
					print("ChargePhase ER_DEBUG: model_id=%s NOT FOUND in unit %s — using empty dict" % [model_id, unit_id])
				else:
					print("ChargePhase ER_DEBUG: model_id=%s found, base_mm=%s base_type=%s pos=%s" % [model_id, model.get("base_mm", "?"), model.get("base_type", "?"), str(final_pos)])

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
					var dist_px = Measurement.model_to_model_distance_px(model_at_final_pos, target_model)
					var er_px = Measurement.inches_to_px(effective_er)
					print("ChargePhase ER_DEBUG: model %s→target_model %s: dist_px=%.1f er_px=%.1f (%.2f\") center_dist=%.1f target_base=%s target_type=%s" % [
						model_id, target_model.get("id", "?"), dist_px, er_px, dist_px / 40.0,
						final_pos.distance_to(target_pos), target_model.get("base_mm", "?"), target_model.get("base_type", "?")])
					if Measurement.is_in_engagement_range_shape_aware(model_at_final_pos, target_model, effective_er):
						unit_in_er_of_target = true
						break

				if unit_in_er_of_target:
					break

		if not unit_in_er_of_target:
			var target_name = target_unit.get("meta", {}).get("name", target_id)
			print("ChargePhase ER_DEBUG: FAILED — no model of %s reached ER of target %s (%s)" % [unit_id, target_id, target_name])
			errors.append("Must end within engagement range of all targets: " + target_name)

	# Check that unit does NOT end in ER of non-target enemies
	for enemy_unit_id in all_units:
		var enemy_unit = all_units[enemy_unit_id]
		if int(enemy_unit.get("owner", 0)) == charging_owner:
			continue  # Skip friendly (relative to the charging unit)

		if enemy_unit_id in target_ids:
			continue  # Skip declared targets

		if not _is_unit_on_board(enemy_unit):
			continue  # Issue #320: Reserves units have no board position — they'd read as (0,0)

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
	var moved_ids := {}
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() > 0:
			moved_ids[model_id] = true
			var model = _get_model_in_unit(unit_id, model_id)
			var model_at_final = model.duplicate()
			model_at_final["position"] = Vector2(path[-1][0], path[-1][1])
			final_models.append(model_at_final)

	# Coherency is a whole-unit condition: include the UNMOVED alive models at
	# their current positions. Checking only the moved subset let a single
	# dragged model legally break away from the rest of its unit.
	var unit = get_unit(unit_id)
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		if model.get("position") == null:
			continue
		var mid = model.get("id", "")
		if moved_ids.has(mid):
			continue
		var model_at_current = model.duplicate()
		model_at_current["position"] = _get_model_position(model)
		final_models.append(model_at_current)

	if final_models.size() < 2:
		return {"valid": true, "errors": []}  # Single model or no movement

	# Check that each model is within 2" horizontally AND 5" vertically of at least one other model
	for i in range(final_models.size()):
		var has_nearby_model = false

		for j in range(final_models.size()):
			if i == j:
				continue

			if Measurement.is_within_coherency(final_models[i], final_models[j]):
				has_nearby_model = true
				break

		if not has_nearby_model:
			errors.append("Unit coherency broken: model %d too far from other models" % i)

	return {"valid": errors.is_empty(), "errors": errors}

func _validate_base_to_base_possible(unit_id: String, per_model_paths: Dictionary, target_ids: Array, rolled_distance: int) -> Dictionary:
	# 11.04 WHILE MOVING (11e): each charging model that CAN end within 1" of a
	# charge target MUST do so. Delegates to the single implementation in
	# RulesEngine so the rule cannot drift between the two call sites (this was
	# a ~200-line duplicate that had already diverged on tolerance).
	return RulesEngine.validate_base_to_base_possible_rules(unit_id, per_model_paths, target_ids, game_state_snapshot, rolled_distance)

func _validate_must_end_closer(unit_id: String, per_model_paths: Dictionary, target_ids: Array) -> Dictionary:
	# 10e Rule: Each model making a charge move must end that move closer to at
	# least one of the declared charge targets than it started.
	var errors = []
	var all_units = game_state_snapshot.get("units", {})

	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() >= 2):
			continue

		var start_pos = Vector2(path[0][0], path[0][1])
		var final_pos = Vector2(path[-1][0], path[-1][1])

		# If the model didn't move, skip this check (no movement = no violation)
		if start_pos.distance_to(final_pos) < 0.5:
			continue

		var model = _get_model_in_unit(unit_id, model_id)
		if model.is_empty():
			continue

		# Build model dicts at start and final positions
		var model_at_start = model.duplicate()
		model_at_start["position"] = start_pos
		var model_at_final = model.duplicate()
		model_at_final["position"] = final_pos

		# Check if model ends closer to ANY declared target
		var ends_closer_to_any_target = false

		for target_id in target_ids:
			var target_unit = all_units.get(target_id, {})
			if target_unit.is_empty():
				continue

			# Find closest distance to this target unit from start and end
			var min_start_distance = INF
			var min_end_distance = INF

			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue

				var start_dist = Measurement.model_to_model_distance_inches(model_at_start, target_model)
				var end_dist = Measurement.model_to_model_distance_inches(model_at_final, target_model)

				min_start_distance = min(min_start_distance, start_dist)
				min_end_distance = min(min_end_distance, end_dist)

			if min_end_distance < min_start_distance:
				ends_closer_to_any_target = true
				break

		if not ends_closer_to_any_target:
			var unit = get_unit(unit_id)
			var model_name = model_id
			errors.append("Model %s did not end closer to any declared charge target" % model_name)
			DebugLogger.info(str("ChargePhase: Must-end-closer violation - model %s is not closer to any target after move" % model_id))

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
			DebugLogger.info(str("ChargePhase: Direction constraint - %s" % err))

	return {"valid": errors.is_empty(), "errors": errors}

## Calculate the total terrain penalty for a charge path.
## Units always stay on ground floor — no height penalty. Only difficult ground applies.
func _calculate_path_terrain_penalty(path: Array, has_fly: bool, unit_keywords: Array = []) -> float:
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

		# Forward unit_keywords so INFANTRY can traverse ruins without paying
		# the climb penalty (matches movement-phase rules).
		total_penalty += terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, has_fly, unit_keywords)

	return total_penalty

## T3-9: Get the effective engagement range between two model positions,
## accounting for barricade terrain (2" instead of 1" if barricade is between them).
func _get_effective_engagement_range(model1_pos: Vector2, model2_pos: Vector2) -> float:
	if not is_inside_tree():
		return GameConstants.engagement_range_inches()
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.has_method("get_engagement_range_for_positions"):
		return terrain_manager.get_engagement_range_for_positions(model1_pos, model2_pos)
	return GameConstants.engagement_range_inches()

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _is_unit_on_board(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	if status == GameStateData.UnitStatus.IN_RESERVES or status == GameStateData.UnitStatus.UNDEPLOYED:
		return false
	var models = unit.get("models", [])
	if models.is_empty():
		return false
	return models[0].get("position") != null

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

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	# --- Reaction states: these block normal charge actions until resolved ---

	# Ability reroll decision pending (e.g. Swift Onslaught, Plummeting Descent — free reroll)
	if awaiting_ability_reroll and ability_reroll_unit_id != "":
		var reroll_ability = _get_charge_reroll_ability_name(ability_reroll_unit_id)
		actions.append({
			"type": "USE_ABILITY_REROLL",
			"actor_unit_id": ability_reroll_unit_id,
			"description": "Use %s — re-roll charge dice (free)" % reroll_ability
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

	# Heroic Intervention move pending (HI accepted, charge roll succeeded, awaiting move)
	if heroic_intervention_unit_id != "" and not heroic_intervention_pending_charge.is_empty() and heroic_intervention_pending_charge.has("distance"):
		var hi_distance = heroic_intervention_pending_charge.get("distance", 0)
		var hi_targets = heroic_intervention_pending_charge.get("targets", [])
		actions.append({
			"type": "APPLY_HEROIC_INTERVENTION_MOVE",
			"actor_unit_id": heroic_intervention_unit_id,
			"rolled_distance": hi_distance,
			"target_ids": hi_targets,
			"player": heroic_intervention_player,
			"description": "Apply Heroic Intervention movement for %s" % heroic_intervention_unit_id
		})
		return actions  # Block other actions until HI move is applied

	# --- Normal charge actions ---

	# Units that can declare charges
	for unit_id in units:
		var unit = units[unit_id]
		var can_charge = _can_unit_charge(unit)
		var not_completed = unit_id not in completed_charges
		if can_charge and not_completed:

			# If no charge declared, can declare charge
			if not pending_charges.has(unit_id):
				var eligible_targets = _get_eligible_targets_for_unit(unit_id)
				DebugLogger.info(str("[ChargePhase] get_available_actions: %s can_charge=%s, eligible_targets=%d" % [unit_id, str(can_charge), eligible_targets.size()]))
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
					# 11e 11.02: targets are picked after the roll from this list
					# (enemies within 12" AND within the roll). Empty at 10e.
					"selectable_targets": charge_data.get("selectable_targets", []),
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
	# 11e 15.11: the end-of-phase Heroic Intervention window is part of the
	# Charge phase — never auto-complete while it is pending, and don't
	# auto-complete past it before it has been offered (END_CHARGE opens
	# it; the window's resolution completes the phase).
	if GameConstants.edition >= 11:
		if awaiting_heroic_intervention or _hi_pending_phase_complete \
				or not heroic_intervention_pending_charge.is_empty():
			return false
		if not _hi_end_phase_offered:
			return false

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

func _validate_no_wall_overlaps(unit_id: String, per_model_paths: Dictionary) -> Dictionary:
	var errors = []
	# Keywords make the 11e solid-feature half of the endpoint check
	# keyword-aware (infantry may end among walls; vehicles/monsters may not).
	var unit_keywords = get_unit(unit_id).get("meta", {}).get("keywords", [])

	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var final_pos = Vector2(path[-1][0], path[-1][1])
		var model = _get_model_in_unit(unit_id, model_id)
		if model.is_empty():
			continue

		var check_model = model.duplicate(true)
		check_model["position"] = final_pos

		if Measurement.model_overlaps_any_wall(check_model, unit_keywords):
			errors.append("Model %s would end its charge overlapping a wall" % model_id)

	return {"valid": errors.is_empty(), "errors": errors}

## ISS-054 (11e 13.06): sweep each charge-path segment's base against solid
## dense features (ruin walls and the like). Pieces the model already
## overlaps at a segment start never block (escape clause for pre-fix
## saves), matching TerrainManager.can_move_through_11e semantics.
func _validate_no_solid_terrain_on_paths(unit_id: String, per_model_paths: Dictionary, unit_keywords: Array) -> Dictionary:
	var errors = []
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null or not tm.has_method("can_move_through_11e"):
		return {"valid": true, "errors": []}

	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() >= 2):
			continue
		var model = _get_model_in_unit(unit_id, model_id)
		if model.is_empty():
			continue
		for i in range(path.size() - 1):
			var seg_from = Vector2(path[i][0], path[i][1])
			var seg_to = Vector2(path[i + 1][0], path[i + 1][1])
			var trav = tm.can_move_through_11e(unit_keywords, seg_from, seg_to, [], model)
			if not trav.allowed:
				errors.append("Model %s charge path is blocked by solid terrain (13.06): %s" % [model_id, str(trav.blockers)])
				break

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
	var text: String = FAIL_CATEGORY_TOOLTIPS.get(category, "Charge failed due to an unknown constraint.")
	return text.replace("{er}", "%.0f\"" % GameConstants.engagement_range_inches())

func record_insufficient_roll_failure(unit_id: String, rolled_distance: int, dice: Array, target_ids: Array, min_distance: float, unreachable_names: Array = []) -> void:
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var er_in = GameConstants.engagement_range_inches()
	var detail: String
	if unreachable_names.size() > 0 and target_ids.size() > 1:
		# Over-declared multi-target charge: name the target(s) the roll can't
		# reach so the player learns a charge must reach EVERY declared target.
		detail = "Rolled %d\" — cannot reach every declared target (out of range: %s). A charge must end within %.0f\" engagement range of ALL targets; you needed to roll %.1f\"." % [
			rolled_distance, ", ".join(unreachable_names), er_in, min_distance]
	else:
		detail = "Rolled %d\" but nearest target is %.1f\" away (need to close to within %.0f\" engagement range)" % [rolled_distance, min_distance, er_in]
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
	DebugLogger.info(str("ChargePhase: Recorded insufficient roll failure - [INSUFFICIENT_ROLL] %s" % detail))

func has_pending_charge(unit_id: String) -> bool:
	return pending_charges.has(unit_id)

func _is_charge_roll_sufficient(unit_id: String, rolled_distance: int) -> bool:
	"""Check if the rolled distance is sufficient for at least one model to reach
	engagement range of at least one target model in any declared target unit.
	This is the server-side feasibility check performed immediately after the roll.
	T2-8: Accounts for terrain vertical distance penalties along the charge path.

	Charge-fix (false INSUFFICIENT_ROLL): the old check penalized the full
	straight line from model centre to target centre. But (a) a charging model
	stops as soon as it reaches engagement range — terrain beyond that point is
	never crossed — and (b) the real charge move validator scores the PLAYER'S
	drawn path, which may legally go around terrain. Both made this pre-check
	strictly harsher than the move it gates, failing makeable charges (e.g. a
	6\" roll vs a target 2.5\" away with a ruin corner clipping the line).
	Now: cost = distance travelled to the ER stop point + penalties on that
	travelled portion, and if the straight approach pays a penalty we also try
	detour paths around the offending terrain, mirroring what
	_validate_charge_movement_constraints would accept."""
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

	# Pass 1 (cheap): straight approach, stopping at engagement range.
	# Collect pairs whose raw distance fits the roll but whose straight
	# approach pays a terrain penalty — those get the detour pass.
	var detour_candidates: Array = []
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

				var direct = _direct_charge_cost(model, target_model, has_fly, unit_keywords)
				if direct.cost <= float(rolled_distance) + MOVEMENT_CAP_EPSILON:
					return true
				# Any path is at least `required` long, so only pairs whose raw
				# required distance fits the roll can be saved by a detour.
				if direct.required <= float(rolled_distance) + MOVEMENT_CAP_EPSILON:
					detour_candidates.append({
						"model": model, "target_model": target_model,
						"required": direct.required,
					})

	# Pass 2: try paths around the penalizing terrain for the closest few pairs.
	detour_candidates.sort_custom(func(a, b): return a.required < b.required)
	var tried := 0
	for cand in detour_candidates:
		if tried >= 4:
			break
		tried += 1
		var around_cost = _detour_charge_cost(cand.model, cand.target_model, has_fly, unit_keywords, float(rolled_distance))
		DebugLogger.info(str("ChargePhase: charge feasibility detour cost %.2f\" (roll %d\", required %.2f\")" % [around_cost, rolled_distance, cand.required]))
		if around_cost <= float(rolled_distance) + MOVEMENT_CAP_EPSILON:
			return true

	return false

func _per_target_charge_requirements(unit_id: String, target_ids: Array, rolled_distance: float) -> Dictionary:
	"""Decompose a charge into its per-target reachability. For each target in
	`target_ids`, find the cheapest terrain-aware charge cost (inches) for any
	alive model of `unit_id` to reach engagement range of that target, using the
	same direct+detour cost model as _is_charge_roll_sufficient and the move
	validator. Returns { target_id: {required, cost, reachable, name} } where:
	  • required  = raw distance-to-ER of the closest model pair (roll needed on
	                open ground, ignoring terrain);
	  • cost      = required + terrain penalties along the cheapest reaching path;
	  • reachable = cost <= rolled_distance (+ epsilon).

	This is the per-target decomposition the SUCCESS/FAILED verdict, the displayed
	'needed' distance, and the declaration-time hint are all built on. A charge is
	only makeable if EVERY declared target is reachable — both 10e's move
	validator and 11e 11.04 require the move to end engaged with every declared
	target. The old feasibility check only asked whether the NEAREST target was
	reachable, which let an over-declared charge log a false SUCCESS."""
	var out := {}
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return out
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	for target_id in target_ids:
		var target_unit = get_unit(target_id)
		if target_unit.is_empty():
			continue
		var best_required := INF
		var best_cost := INF
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue
				var direct = _direct_charge_cost(model, target_model, has_fly, unit_keywords)
				best_required = minf(best_required, direct.required)
				best_cost = minf(best_cost, direct.cost)
				# Straight approach pays a terrain penalty but the raw distance
				# fits the roll — angling around the obstacle may be cheaper
				# (mirrors _is_charge_roll_sufficient's pass-2 detour + what the
				# move validator will accept).
				if direct.cost > direct.required + MOVEMENT_CAP_EPSILON and direct.required <= rolled_distance + MOVEMENT_CAP_EPSILON:
					var around = _detour_charge_cost(model, target_model, has_fly, unit_keywords, rolled_distance)
					best_cost = minf(best_cost, around)
		out[target_id] = {
			"required": best_required,
			"cost": best_cost,
			"reachable": best_cost <= rolled_distance + MOVEMENT_CAP_EPSILON,
			"name": target_unit.get("meta", {}).get("name", target_id),
		}
	return out

func _target_names_array(target_ids: Array) -> Array:
	"""Display names for a list of target unit ids."""
	var names: Array = []
	for tid in target_ids:
		names.append(get_unit(tid).get("meta", {}).get("name", tid))
	return names

func _format_target_names(target_ids: Array) -> String:
	"""Comma-joined display names for a list of target unit ids."""
	return ", ".join(_target_names_array(target_ids))

func _report_partial_charge(unit_id: String, kept_ids: Array, dropped_ids: Array, roll: int, per_target: Dictionary) -> void:
	"""11e: a successful roll that only reaches a SUBSET of the declared targets
	drops the rest. That drop is otherwise silent (debug log only), so from the
	player's side a 3-target declaration that fights only 1 unit looks like a bug.
	Emit a visible entry naming what is engaged and what fell out of reach."""
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var dropped_desc: Array = []
	for tid in dropped_ids:
		var need = float(per_target.get(tid, {}).get("cost", INF))
		var nm = get_unit(tid).get("meta", {}).get("name", tid)
		dropped_desc.append("%s (needs %.1f\")" % [nm, need] if need < INF else nm)
	var msg = "%s charge reaches %s; beyond the %d\" roll: %s" % [
		unit_name, _format_target_names(kept_ids), roll, ", ".join(dropped_desc)]
	log_phase_message("[11e] " + msg)
	var gel = get_node_or_null("/root/GameEventLog")
	if gel:
		gel.add_player_entry(int(get_unit(unit_id).get("owner", 0)), msg)

func _direct_charge_cost(model: Dictionary, target_model: Dictionary, has_fly: bool, unit_keywords: Array) -> Dictionary:
	"""Effective cost (inches) for `model` to charge straight at `target_model`,
	stopping as soon as its base reaches engagement range. Returns
	{required: raw distance to close, cost: required + terrain penalties on the
	travelled portion of the line}."""
	var a = _get_model_position(model)
	var b = _get_model_position(target_model)
	var edge_dist_in = Measurement.model_to_model_distance_inches(model, target_model)
	var er_in = _get_effective_engagement_range(a, b)
	var required_in = maxf(0.0, edge_dist_in - er_in)
	if required_in <= 0.0:
		return {"required": 0.0, "cost": 0.0}
	var dir = b - a
	if dir.length() < 0.001:
		return {"required": required_in, "cost": required_in}
	# Penalties only accrue on the portion of the line actually travelled.
	var stop_pt = a + dir.normalized() * Measurement.inches_to_px(required_in)
	var penalty = _calculate_path_terrain_penalty([a, stop_pt], has_fly, unit_keywords)
	return {"required": required_in, "cost": required_in + penalty}

func _detour_charge_cost(model: Dictionary, target_model: Dictionary, has_fly: bool, unit_keywords: Array, budget_inches: float) -> float:
	"""Cheapest cost (inches, straight-drag length + terrain penalties) over
	candidate FINAL positions sampled on the engagement ring around
	`target_model`. Both the drag UI and the AI submit 2-point paths
	(origin -> final), so this is exactly the cost model
	_validate_charge_movement_constraints will apply — a sample within the
	budget means a confirmable move exists (e.g. angling around a ruin corner
	instead of over it)."""
	var a = _get_model_position(model)
	var b = _get_model_position(target_model)
	var edge_dist_in = Measurement.model_to_model_distance_inches(model, target_model)
	var er_in = _get_effective_engagement_range(a, b)
	var required_in = maxf(0.0, edge_dist_in - er_in)
	if required_in <= 0.0:
		return 0.0
	var center_dist_px = a.distance_to(b)
	# Centre distance at which the bases are exactly ER apart along this
	# bearing (base-shape allowance baked in) — the "stop ring" around b.
	var ring_px = maxf(0.0, center_dist_px - Measurement.inches_to_px(required_in))
	if ring_px <= 0.0:
		return required_in + _calculate_path_terrain_penalty([a, b], has_fly, unit_keywords)
	var budget_px = Measurement.inches_to_px(budget_inches)

	var best := INF
	const RING_SAMPLES := 24
	for i in range(RING_SAMPLES):
		var ang = TAU * float(i) / float(RING_SAMPLES)
		var final_pos = b + Vector2(cos(ang), sin(ang)) * ring_px
		# Cheap lower-bound cull before the terrain-penalty sweep
		if a.distance_to(final_pos) > budget_px + 1.0:
			continue
		var cost = _charge_segment_cost(a, final_pos, has_fly, unit_keywords)
		best = minf(best, cost)
		if best <= budget_inches:
			break
	return best

func _charge_segment_cost(p: Vector2, q: Vector2, has_fly: bool, unit_keywords: Array) -> float:
	return Measurement.px_to_inches(p.distance_to(q)) + _calculate_path_terrain_penalty([p, q], has_fly, unit_keywords)

func _get_charge_reroll_ability_name(unit_id: String) -> String:
	"""OA-23: Determine which ability granted the charge reroll flag for display purposes."""
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		for entry in ability_mgr._active_ability_effects:
			if entry.get("target_unit_id", "") == unit_id:
				for effect in entry.get("effects", []):
					if effect.get("type", "") == "reroll_charge":
						return entry.get("ability_name", "ability")
	# Prey rule (Da Big Hunt): reroll granted live vs the owner's Prey
	var unit_data = get_unit(unit_id)
	var declared_targets: Array = pending_charges.get(unit_id, {}).get("targets", [])
	if not EffectPrimitivesData.has_effect_reroll_charge(unit_data) \
			and FactionAbilityManager.unit_has_prey_charge_reroll(unit_data, declared_targets, GameState.state.get("units", {})):
		return "Prey"
	return "ability"

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
	# The overwatching unit arrives as `unit_id` from the AI but as
	# `actor_unit_id` from the human dialog / get_available_actions — accept
	# both (reading only `unit_id` made human Fire Overwatch always reject).
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))
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
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))
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
	DebugLogger.info(str("ChargePhase: Fire Overwatch activated — %s (Player %d) shooting at %s" % [unit_name, player, enemy_unit_name]))

	# Log targeting notification to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_overwatch_entry(">>> FIRE OVERWATCH <<<")
		game_event_log.add_overwatch_entry("P%d: %s fires at %s (only 6s hit)" % [player, unit_name, enemy_unit_name])

	# P1-59: Set out-of-phase flag before resolving overwatch shooting
	# This blocks any phase-specific abilities/stratagems during the out-of-phase action
	if strat_manager:
		strat_manager.set_out_of_phase_active(true, player, unit_id)

	# Resolve Overwatch shooting using RulesEngine
	# Overwatch only hits on unmodified 6s (special rule)
	# Issue #329: forward action.payload.rng_seed
	var ow_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var overwatch_result = _resolve_overwatch_shooting(unit_id, enemy_unit_id, player, ow_seed)

	# P1-59: Clear out-of-phase flag after overwatch resolves
	if strat_manager:
		strat_manager.set_out_of_phase_active(false)

	# Log detailed overwatch roll results to GameEventLog
	if game_event_log:
		_log_overwatch_results_to_game_log(game_event_log, overwatch_result, unit_name, enemy_unit_name, player)

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
	DebugLogger.info(str("ChargePhase: Fire Overwatch DECLINED by Player %d" % player))

	# Clear Overwatch state (both local and remote)
	awaiting_fire_overwatch = false
	awaiting_overwatch_decision = false
	overwatch_charging_unit_id = ""
	fire_overwatch_player = 0
	fire_overwatch_enemy_unit_id = ""
	fire_overwatch_eligible_units = []

	return create_result(true, [])

func _resolve_overwatch_shooting(shooting_unit_id: String, target_unit_id: String, player: int, rng_seed: int = -1) -> Dictionary:
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
	# Issue #329: forward rng_seed from caller (action.payload.rng_seed)
	var board = game_state_snapshot
	shoot_action["payload"]["rng_seed"] = rng_seed
	var rng = RulesEngine.RNGService.new(rng_seed)
	var shoot_result = RulesEngine.resolve_shoot(shoot_action, board, rng)

	var total_damage = 0
	for diff in shoot_result.get("diffs", []):
		if diff.get("op", "") == "set" and "wounds" in diff.get("path", ""):
			total_damage += 1

	var ow_shooter_name = shooting_unit.get("meta", {}).get("name", shooting_unit_id)
	var ow_target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	log_phase_message("FIRE OVERWATCH result: %s fired at %s — %s" % [
		ow_shooter_name, ow_target_name,
		shoot_result.get("log_text", "no hits")
	])

	return shoot_result

func _log_overwatch_results_to_game_log(game_event_log, ow_result: Dictionary, shooter_name: String, target_name: String, player: int) -> void:
	"""Log detailed overwatch roll results (hits, wounds, saves, casualties) to the GameEventLog."""
	var dice_entries = ow_result.get("dice", [])
	var total_hits = 0
	var total_wounds = 0

	for dice_entry in dice_entries:
		var context = dice_entry.get("context", "")
		var weapon_name = dice_entry.get("weapon_name", "")
		var rolls_raw = dice_entry.get("rolls_raw", [])
		var threshold = dice_entry.get("threshold", "")
		var successes = dice_entry.get("successes", 0)
		var rolls_str = ", ".join(rolls_raw.map(func(r): return str(r)))

		if context == "overwatch_to_hit" or context == "to_hit":
			total_hits += successes
			game_event_log.add_overwatch_entry("  %s - Hit rolls: [%s] vs %s (%d hit%s)" % [
				weapon_name, rolls_str, str(threshold), successes, "" if successes == 1 else "s"])
		elif context == "to_wound":
			total_wounds += successes
			game_event_log.add_overwatch_entry("  %s - Wound rolls: [%s] vs %s (%d wound%s)" % [
				weapon_name, rolls_str, str(threshold), successes, "" if successes == 1 else "s"])
		elif context == "save":
			var fails = dice_entry.get("fails", 0)
			var sv = dice_entry.get("sv", str(threshold))
			game_event_log.add_overwatch_entry("  Save roll: [%s] vs %s (%s)" % [
				rolls_str, str(sv), "failed!" if fails > 0 else "saved"])

	# Count casualties from diffs (models set to alive=false)
	var total_casualties = 0
	for diff in ow_result.get("diffs", []):
		var path = diff.get("path", "")
		if path.ends_with(".alive") and diff.get("value") == false:
			total_casualties += 1

	# Log the final outcome summary
	if total_casualties > 0:
		game_event_log.add_overwatch_entry("  >>> %d model%s destroyed! <<<" % [
			total_casualties, "" if total_casualties == 1 else "s"])
	elif total_wounds > 0:
		game_event_log.add_overwatch_entry("  Result: All wounds saved - no casualties")
	elif total_hits > 0:
		game_event_log.add_overwatch_entry("  Result: Hits failed to wound")
	else:
		game_event_log.add_overwatch_entry("  Result: No hits (only unmodified 6s hit)")

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
	var strat_manager = get_node_or_null("/root/StratagemManager")

	# Targets: 10e — only the enemy unit that just charged. 11e (15.11) —
	# mode choice: LEAP TO DEFEND (only units that made a charge move this
	# turn may be targets) or INTO THE FRAY (targets within 6"; roll capped
	# at 6). Single-target selection uses the closest qualifying enemy —
	# the same one-target shape as the 10e flow. Resolve the target BEFORE
	# spending CP so a mode with no reachable target costs nothing.
	var hi_mode := str(action.get("mode", "leap_to_defend"))
	var target_ids: Array = [heroic_intervention_charging_unit_id]
	if GameConstants.edition >= 11:
		var max_range := 6.0 if hi_mode == "into_the_fray" else 12.0
		var require_charged := hi_mode != "into_the_fray"
		var picked := _closest_hi_target_11e(unit_id, player, max_range, require_charged)
		if picked == "":
			# Let the player pick the other mode or decline — the dialog
			# self-closed on Use, so re-open the window.
			awaiting_heroic_intervention = true
			if strat_manager and strat_manager.has_method("get_heroic_intervention_eligible_units_11e"):
				emit_signal("heroic_intervention_opportunity", player,
					strat_manager.get_heroic_intervention_eligible_units_11e(player), "")
			return create_result(false, [], "No eligible %s target (%s)" % [
				"charged enemy within 12\"" if require_charged else "enemy within 6\"", hi_mode])
		target_ids = [picked]

	# Use the stratagem via StratagemManager (deducts CP, records usage)
	if strat_manager:
		var strat_result = strat_manager.use_stratagem(player, "heroic_intervention", unit_id)
		if not strat_result.success:
			return create_result(false, [], "Failed to use Heroic Intervention: %s" % strat_result.get("error", "unknown"))

	log_phase_message("Player %d uses HEROIC INTERVENTION — %s will counter-charge!" % [player, unit_name])

	# Set up the heroic intervention charge
	awaiting_heroic_intervention = false
	heroic_intervention_unit_id = unit_id

	heroic_intervention_pending_charge = {
		"targets": target_ids.duplicate(),
		"mode": hi_mode,
		"declared_at": Time.get_unix_time_from_system()
	}

	# Now auto-roll the charge dice (HI uses a normal 2D6 charge roll)
	# Issue #329: honor payload.rng_seed
	var rng_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var rng = RulesEngine.RNGService.new(rng_seed)
	var rolls = rng.roll_d6(2)
	var total_distance = rolls[0] + rolls[1]
	# 11e INTO THE FRAY: "the charge roll cannot exceed 6"
	if GameConstants.edition >= 11 and hi_mode == "into_the_fray" and total_distance > 6:
		log_phase_message("[11e 15.11] INTO THE FRAY — charge roll %d capped at 6" % total_distance)
		total_distance = 6

	heroic_intervention_pending_charge.distance = total_distance
	heroic_intervention_pending_charge.dice_rolls = rolls

	log_phase_message("HEROIC INTERVENTION charge roll: 2D6 = %d (%d + %d)%s" % [
		total_distance, rolls[0], rolls[1],
		" [mode: %s]" % hi_mode if GameConstants.edition >= 11 else ""])
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
		DebugLogger.info(str("ChargePhase: Heroic Intervention charge roll INSUFFICIENT for %s (rolled %d)" % [unit_name, total_distance]))

		# Clean up HI state
		heroic_intervention_unit_id = ""
		heroic_intervention_pending_charge = {}
		heroic_intervention_charging_unit_id = ""
		heroic_intervention_player = 0

		# 11e end-of-phase window: the phase completes once HI resolves
		_complete_phase_after_heroic_intervention_if_pending()

		return create_result(true, [], "", {
			"dice": [dice_result],
			"heroic_intervention_failed": true,
			"heroic_intervention_unit_id": unit_id,
		})

	# Roll sufficient — enable movement
	DebugLogger.info(str("ChargePhase: Heroic Intervention charge roll SUFFICIENT for %s (rolled %d)" % [unit_name, total_distance]))
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

	# 11e end-of-phase window: the phase completes once HI resolves
	_complete_phase_after_heroic_intervention_if_pending()

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
		# 11e end-of-phase window: the phase completes once HI resolves
		_complete_phase_after_heroic_intervention_if_pending()
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

	# Attached CHARACTER(s) ride the Heroic Intervention with their bodyguard.
	# HI does NOT grant Fights First, so neither does the character.
	changes.append_array(_charge_attached_character_changes(unit_id, per_model_paths, false))

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

	# 11e end-of-phase window: the phase completes once HI resolves
	_complete_phase_after_heroic_intervention_if_pending()

	return create_result(true, changes)

# 11e 15.11: pick the closest enemy unit within max_range inches
# (edge-to-edge) as the HI charge target; LEAP TO DEFEND additionally
# requires the target to have made a charge move this turn.
func _closest_hi_target_11e(unit_id: String, player: int, max_range: float, require_charged: bool) -> String:
	var unit = get_unit(unit_id)
	var best_id := ""
	var best_px := INF
	var range_px = Measurement.inches_to_px(max_range)
	for other_id in game_state_snapshot.get("units", {}):
		var other = game_state_snapshot.units[other_id]
		if int(other.get("owner", 0)) == player:
			continue
		if require_charged and not other.get("flags", {}).get("charged_this_turn", false):
			continue
		var any_alive := false
		for em in other.get("models", []):
			if em.get("alive", true) and em.get("position") != null:
				any_alive = true
				break
		if not any_alive:
			continue
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			for em in other.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				var d = Measurement.model_to_model_distance_px(m, em)
				if d <= range_px and d < best_px:
					best_px = d
					best_id = other_id
	return best_id

func _is_heroic_intervention_roll_sufficient(unit_id: String, rolled_distance: int, target_ids: Array) -> bool:
	"""Check if the HI charge roll is sufficient to reach engagement range of the target.
	P2-77: Now accounts for terrain vertical distance penalties along the charge path."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false

	# P2-77: Check FLY keyword for terrain penalty calculation
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

				var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
				# T3-9: Use barricade-aware engagement range
				var target_pos = _get_model_position(target_model)
				var effective_er = _get_effective_engagement_range(model_pos, target_pos)
				var distance_to_close = distance_inches - effective_er

				# P2-77: Add terrain penalty for the straight-line path
				var terrain_penalty = _calculate_path_terrain_penalty(
					[model_pos, target_pos], has_fly, unit_keywords)
				var effective_distance = distance_to_close + terrain_penalty

				if terrain_penalty > 0.0:
					DebugLogger.info(str("ChargePhase: HI model terrain penalty: %.1f\" (FLY=%s), effective distance: %.1f\"" % [
						terrain_penalty, str(has_fly), effective_distance]))

				if effective_distance <= rolled_distance:
					return true

	return false

# Override create_result to support additional data
# ============================================================================
# OA-36: PISTON-DRIVEN BRUTALITY — Mortal wounds after Charge move
# ============================================================================

func _resolve_piston_driven_brutality_after_charge(unit_id: String, changes: Array, rng_seed: int = -1) -> void:
	"""OA-36: Check if the charging unit has Piston-driven Brutality.
	If so, auto-resolve mortal wounds against one enemy in Engagement Range.
	Roll 1D6: on 2-5, D3 MW; on 6, D3+3 MW; on 1, nothing.
	Applied immediately via PhaseManager (like Dread Foe in FightPhase)."""
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr or not ability_mgr.has_piston_driven_brutality(unit_id):
		return

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Build a temp snapshot with charge move positions applied
	# so engagement range checks use post-move positions
	var temp_snapshot = game_state_snapshot.duplicate(true)
	for change in changes:
		if change.get("op", "") == "set":
			var path_parts = change.path.split(".")
			if path_parts.size() >= 5 and path_parts[0] == "units" and path_parts[2] == "models":
				var u_id = path_parts[1]
				var m_idx = int(path_parts[3])
				var field = path_parts[4] if path_parts.size() > 4 else ""
				if field == "position" and temp_snapshot.get("units", {}).has(u_id):
					var models = temp_snapshot.units[u_id].get("models", [])
					if m_idx < models.size():
						models[m_idx]["position"] = change.value

	# Find enemy units within Engagement Range using post-move positions
	var targets = _get_piston_brutality_targets(unit_id, temp_snapshot)
	if targets.is_empty():
		log_phase_message("PISTON-DRIVEN BRUTALITY: %s has ability but no enemies in Engagement Range" % unit_name)
		DebugLogger.info(str("ChargePhase: Piston-driven Brutality — %s has no valid targets in Engagement Range" % unit_name))
		return

	# Auto-select first target (same pattern as Dread Foe)
	var target_id = targets[0].get("unit_id", "")
	var target_name = targets[0].get("unit_name", target_id)
	log_phase_message("PISTON-DRIVEN BRUTALITY: %s targets %s within Engagement Range" % [unit_name, target_name])

	# Resolve via RulesEngine
	# Issue #329: forward seed from action.payload.rng_seed (caller passes it through)
	var rng_service = RulesEngine.RNGService.new(rng_seed)
	var result = RulesEngine.resolve_piston_driven_brutality(
		unit_id, target_id, temp_snapshot, rng_service
	)

	# Apply state changes if mortal wounds were dealt
	var pdb_diffs = result.get("diffs", [])
	if not pdb_diffs.is_empty():
		PhaseManager.apply_state_changes(pdb_diffs)
		# Update our snapshot
		game_state_snapshot = GameState.state.duplicate(true)
		log_phase_message("PISTON-DRIVEN BRUTALITY: Applied %d state change(s)" % pdb_diffs.size())

	# Emit signal for UI/logging
	emit_signal("piston_driven_brutality_resolved", unit_id, result)

	# Log to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(unit.get("owner", 0))
		game_event_log.add_player_entry(owner,
			"Piston-driven Brutality: %s rolled [%d] — %d mortal wound(s) to %s (%d casualt(y/ies))" % [
				unit_name, result.get("roll", 0), result.get("mortal_wounds", 0),
				target_name, result.get("casualties", 0)
			])

	log_phase_message("PISTON-DRIVEN BRUTALITY: %s rolled %d — %d mortal wound(s) to %s, %d casualt(y/ies)" % [
		unit_name,
		result.get("roll", 0),
		result.get("mortal_wounds", 0),
		target_name,
		result.get("casualties", 0)
	])

	# Check if mortal wounds killed any units (could trigger Deadly Demise)
	if not pdb_diffs.is_empty():
		_check_kill_diffs_for_deadly_demise(pdb_diffs)

func _get_piston_brutality_targets(unit_id: String, snapshot: Dictionary) -> Array:
	"""OA-36: Get enemy units within Engagement Range of a unit for Piston-driven Brutality targeting.
	Uses post-charge-move positions from the provided snapshot.
	Returns array of { unit_id, unit_name } dictionaries."""
	var unit = snapshot.get("units", {}).get(unit_id, {})
	var unit_owner = unit.get("owner", 0)
	var all_units = snapshot.get("units", {})
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

		# Check if any model of our unit is within Engagement Range of any model of the enemy
		var in_range = false
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = _get_model_position(model)
			if model_pos == Vector2.ZERO:
				continue

			for enemy_model in other.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				var enemy_pos = _get_model_position(enemy_model)
				if enemy_pos == Vector2.ZERO:
					continue

				var effective_er = _get_effective_engagement_range(model_pos, enemy_pos)
				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, effective_er):
					in_range = true
					break
			if in_range:
				break

		if in_range:
			targets.append({
				"unit_id": other_id,
				"unit_name": other.get("meta", {}).get("name", other_id)
			})

	return targets

func _check_kill_diffs_for_deadly_demise(diffs: Array) -> void:
	"""OA-36: Check if mortal wound diffs killed any models that might trigger Deadly Demise.
	Follows same pattern as FightPhase._check_kill_diffs."""
	for diff in diffs:
		if diff.get("op", "") == "set" and diff.get("path", "").ends_with(".alive") and diff.get("value", true) == false:
			var path_parts = diff.path.split(".")
			if path_parts.size() >= 2:
				var killed_unit_id = path_parts[1]
				var killed_unit = get_unit(killed_unit_id)
				if killed_unit.is_empty():
					continue
				# Check if any models in unit are still alive
				var any_alive = false
				for m in killed_unit.get("models", []):
					if m.get("alive", true):
						any_alive = true
						break
				if not any_alive:
					var killed_name = killed_unit.get("meta", {}).get("name", killed_unit_id)
					log_phase_message("PISTON-DRIVEN BRUTALITY: %s destroyed — checking for Deadly Demise" % killed_name)
					DebugLogger.info(str("ChargePhase: Piston-driven Brutality destroyed %s — Deadly Demise check may apply" % killed_name))

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

# ============================================================================
# STRATAGEM HANDLING (active stratagems with phase: "charge")
# Mirrors CommandPhase._validate_use_stratagem / _process_use_stratagem.
# ============================================================================

func _validate_use_stratagem(action: Dictionary) -> Dictionary:
	var errors = []
	var stratagem_id = action.get("stratagem_id", "")

	if stratagem_id == "":
		errors.append("Missing stratagem_id")
		return {"valid": false, "errors": errors}

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		errors.append("StratagemManager not available")
		return {"valid": false, "errors": errors}

	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()
	var validation = strat_manager.can_use_stratagem(current_player, stratagem_id, target_unit_id)
	if not validation.can_use:
		errors.append(validation.reason)
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _process_use_stratagem(action: Dictionary) -> Dictionary:
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return create_result(false, [], "StratagemManager not available")

	var result = strat_manager.use_stratagem(current_player, stratagem_id, target_unit_id)
	if not result.get("success", false):
		return create_result(false, [], result.get("error", "Stratagem use failed"))

	var strat_name = result.get("stratagem_name", stratagem_id)
	DebugLogger.info(str("ChargePhase: Stratagem %s used (target=%s)" % [strat_name, target_unit_id]))
	return create_result(true, result.get("diffs", []), "Used " + strat_name)
