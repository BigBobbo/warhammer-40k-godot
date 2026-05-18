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
signal shooting_damage_applied(shooter_id: String, diffs: Array)  # T7-53: For floating damage numbers after saves resolved
signal ai_shooting_visual(shooter_id: String, target_data: Array, result_summary: Dictionary)  # T7-38: AI shooting targeting line + result text
signal sentinel_storm_available(unit_id: String, player: int)  # P1-10: Sentinel Storm shoot-again prompt
signal sanctified_flames_result(shooter_id: String, target_id: String, test_result: Dictionary)  # P1-11: Sanctified Flames battle-shock test result
signal throat_slittas_available(unit_id: String, player: int, eligible_targets: Array)  # P1-12: Throat Slittas mortal wounds prompt
signal throat_slittas_result(unit_id: String, results: Dictionary)  # P1-12: Throat Slittas resolution result
signal distraction_grot_available(unit_id: String, player: int)  # P2-25: Distraction Grot invuln save prompt
signal distraction_grot_result(unit_id: String, activated: bool)  # P2-25: Distraction Grot decision result
signal ammo_runt_available(unit_id: String, player: int, remaining: int)  # OA-10: Ammo Runt Lethal Hits prompt
signal ammo_runt_result(unit_id: String, activated: bool)  # OA-10: Ammo Runt decision result
signal pulsa_rokkit_available(unit_id: String, player: int)  # OA-31: Pulsa Rokkit +1S/+1AP prompt
signal pulsa_rokkit_result(unit_id: String, activated: bool)  # OA-31: Pulsa Rokkit decision result
signal shooty_power_trip_available(unit_id: String, player: int)  # OA-37: Shooty Power Trip D6 roll prompt
signal shooty_power_trip_result(unit_id: String, d6_roll: int, effect: String)  # OA-37: Shooty Power Trip result

# Shooting state tracking
var active_shooter_id: String = ""
var pending_assignments: Array = []  # Weapon assignments before confirmation
var confirmed_assignments: Array = []  # Assignments ready to resolve
var resolution_state: Dictionary = {}  # State for step-by-step resolution
var dice_log: Array = []
var units_that_shot: Array = []  # Track which units have completed shooting
var phase_shooting_log: Array = []  # T5-UX9: Per-weapon shot summaries persisted across all units in this phase
                                    # Each entry: {shooter_unit_id, shooter_unit_name, weapon_id, weapon_name,
                                    # target_unit_id, target_unit_name, hits, total_attacks, wounds, saves_failed, casualties}
var pending_save_data: Array = []  # Save data awaiting resolution
var pending_hazardous_weapons: Array = []  # HAZARDOUS (T2-3): Weapons needing post-save hazardous check
var pending_one_shot_diffs: Array = []  # ONE SHOT (T4-2): Diffs to mark one-shot weapons as fired
var awaiting_reactive_stratagem: bool = false  # True when waiting for defender stratagem decision
var sentinel_storm_pending_unit: String = ""  # P1-10: Unit awaiting Sentinel Storm decision
var throat_slittas_pending_unit: String = ""  # P1-12: Unit awaiting Throat Slittas decision
var distraction_grot_pending_unit: String = ""  # P2-25: Defending unit awaiting Distraction Grot decision
var awaiting_distraction_grot: bool = false  # P2-25: True when waiting for Distraction Grot response
var ammo_runt_pending_unit: String = ""  # OA-10: Unit awaiting Ammo Runt decision
var awaiting_ammo_runt: bool = false  # OA-10: True when waiting for Ammo Runt response
var pulsa_rokkit_pending_unit: String = ""  # OA-31: Unit awaiting Pulsa Rokkit decision
var awaiting_pulsa_rokkit: bool = false  # OA-31: True when waiting for Pulsa Rokkit response
var shooty_power_trip_pending_unit: String = ""  # OA-37: Unit awaiting Shooty Power Trip decision
var awaiting_shooty_power_trip: bool = false  # OA-37: True when waiting for Shooty Power Trip response
var _targets_hit_by_shooter: Dictionary = {}  # P1-11: Track which enemy units were hit { target_unit_id: hit_count }
var _rng = RulesEngine.RNGService.new()  # P1-11: RNG for battle-shock tests (issue #329: routes through test_mode_seed)
# Issue #386 Big Booms: queued struck-unit IDs from a supa-kannon target selection.
# Resolved after the supa-kannon's attacks against the chosen target finish; D3 MW per struck unit.
var _big_booms_pending: Array = []  # entries: {target_unit_id: String, struck_unit_ids: Array, rolls: Array}
var swift_as_eagle_pending_unit: String = ""
var swift_as_eagle_move_inches: int = 0
var awaiting_swift_as_eagle: bool = false

func _init():
	phase_type = GameStateData.Phase.SHOOTING

func _on_phase_enter() -> void:
	log_phase_message("Entering Shooting Phase")
	active_shooter_id = ""
	pending_assignments.clear()
	_big_booms_pending.clear()
	confirmed_assignments.clear()
	resolution_state.clear()
	dice_log.clear()
	units_that_shot.clear()
	phase_shooting_log.clear()  # T5-UX9: Reset per-phase shot summary log
	pending_hazardous_weapons.clear()
	pending_one_shot_diffs.clear()
	awaiting_reactive_stratagem = false
	sentinel_storm_pending_unit = ""
	throat_slittas_pending_unit = ""
	distraction_grot_pending_unit = ""
	awaiting_distraction_grot = false
	ammo_runt_pending_unit = ""
	awaiting_ammo_runt = false
	pulsa_rokkit_pending_unit = ""
	awaiting_pulsa_rokkit = false
	shooty_power_trip_pending_unit = ""
	awaiting_shooty_power_trip = false
	swift_as_eagle_pending_unit = ""
	swift_as_eagle_move_inches = 0
	awaiting_swift_as_eagle = false
	_targets_hit_by_shooter.clear()

	# Apply unit ability effects (leader abilities, always-on abilities)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	# Refresh snapshot after ability effects mutated GameState flags
	game_state_snapshot = GameState.create_snapshot()

	# Compute in_engagement flags from actual model positions
	_compute_engagement_flags()

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

	# P3-103: Recheck objective control at end of Shooting phase
	# Per 10e core rules: "A player controls an objective marker at the end of any phase or turn."
	# Units destroyed during shooting can change objective control state.
	if MissionManager:
		MissionManager.check_all_objectives()
		DebugLogger.info("ShootingPhase: P3-103 Updated objective control at end of Shooting phase")

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
					# P3-32: Check if destroyed unit is a transport with embarked units
					_resolve_transport_destroyed_if_applicable(unit_id)

func _resolve_transport_destroyed_if_applicable(destroyed_unit_id: String) -> void:
	"""P3-32: If a destroyed unit is a transport, resolve emergency disembark for embarked units."""
	if not TransportManager.is_transport_with_embarked(destroyed_unit_id):
		return

	var unit_name = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {}).get("name", destroyed_unit_id)
	DebugLogger.info(str("ShootingPhase: P3-32 Transport %s (%s) destroyed — resolving emergency disembark" % [unit_name, destroyed_unit_id]))
	log_phase_message("Transport %s destroyed! Embarked units must emergency disembark!" % unit_name)

	var result = TransportManager.resolve_transport_destroyed(destroyed_unit_id)
	if result.get("triggered", false):
		var diffs = result.get("diffs", [])
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)

		# Log per-unit results
		for unit_result in result.get("per_unit", []):
			var msg = "%s: %d models disembarked (rolls: %s)" % [
				unit_result.unit_name, unit_result.models_disembarked, str(unit_result.rolls)]
			if unit_result.casualties > 0:
				var _cas_label = "model" if unit_result.casualties == 1 else "models"
				msg += " — %d %s destroyed!" % [unit_result.casualties, _cas_label]
			log_phase_message(msg)

		if result.total_casualties > 0:
			var _tca_label = "casualty" if result.total_casualties == 1 else "casualties"
			log_phase_message("Emergency disembark: %d total %s from transport destruction" % [result.total_casualties, _tca_label])
			# Check if any disembarked units were fully destroyed
			_check_kill_diffs(diffs)

func _resolve_transport_destruction_if_applicable(destroyed_unit_id: String) -> void:
	"""P1-60: Check if a destroyed unit is a transport with embarked units and resolve emergency disembarkation."""
	var transport_mgr = get_node_or_null("/root/TransportManager")
	if not transport_mgr:
		return
	if not transport_mgr.is_transport_with_embarked_units(destroyed_unit_id):
		return

	var transport_name = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {}).get("name", destroyed_unit_id)
	DebugLogger.info(str("ShootingPhase: P1-60 Transport destruction detected — %s (%s) has embarked units" % [transport_name, destroyed_unit_id]))
	log_phase_message("Transport %s destroyed! Embarked units must emergency disembark!" % transport_name)

	var result = RulesEngine.resolve_transport_destruction(destroyed_unit_id, GameState.state)

	if not result.get("all_diffs", []).is_empty():
		PhaseManager.apply_state_changes(result.all_diffs)

		for unit_info in result.get("per_unit", []):
			var mw = unit_info.get("mortal_wounds", 0)
			var destroyed_models = unit_info.get("models_destroyed", 0)
			var unit_name = unit_info.get("unit_name", "Unknown")
			if mw > 0:
				var _mw_label = "mortal wound" if mw == 1 else "mortal wounds"
				var _md_label = "model" if destroyed_models == 1 else "models"
				log_phase_message("  %s: %d %s, %d %s destroyed" % [unit_name, mw, _mw_label, destroyed_models, _md_label])
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
	DebugLogger.info(str("ShootingPhase: P1-13 Deadly Demise detected on destroyed unit %s (%s) — value: %s" % [unit_name, destroyed_unit_id, dd_value]))
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

func _compute_engagement_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) != 2:
			continue
		var owner = unit.get("owner", 0)
		var in_engagement = false
		for other_id in units:
			if other_id == unit_id:
				continue
			var other = units[other_id]
			if other.get("owner", 0) == owner:
				continue
			if other.get("status", 0) != 2:
				continue
			if RulesEngine._check_units_in_engagement_range(unit, other, game_state_snapshot):
				in_engagement = true
				break
		var gs_unit = GameState.state["units"].get(unit_id, {})
		if not gs_unit.is_empty():
			if not gs_unit.has("flags"):
				gs_unit["flags"] = {}
			gs_unit["flags"]["in_engagement"] = in_engagement
			if in_engagement:
				log_phase_message("Unit %s is in engagement range" % unit_id)
	game_state_snapshot = GameState.create_snapshot()

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
		"USE_STRATAGEM":  # Active player uses a proactive (non-grenade) stratagem with phase: "shooting"
			return _validate_use_stratagem(action)
		"USE_SENTINEL_STORM":  # P1-10: Player uses Sentinel Storm shoot-again
			return _validate_use_sentinel_storm(action)
		"DECLINE_SENTINEL_STORM":  # P1-10: Player declines Sentinel Storm
			return _validate_decline_sentinel_storm(action)
		"USE_THROAT_SLITTAS":  # P1-12: Player uses Throat Slittas mortal wounds
			return _validate_use_throat_slittas(action)
		"DECLINE_THROAT_SLITTAS":  # P1-12: Player declines Throat Slittas
			return _validate_decline_throat_slittas(action)
		"USE_DISTRACTION_GROT":  # P2-25: Defender activates Distraction Grot
			return _validate_use_distraction_grot(action)
		"DECLINE_DISTRACTION_GROT":  # P2-25: Defender declines Distraction Grot
			return _validate_decline_distraction_grot(action)
		"USE_AMMO_RUNT":  # OA-10: Player activates Ammo Runt
			return _validate_use_ammo_runt(action)
		"DECLINE_AMMO_RUNT":  # OA-10: Player declines Ammo Runt
			return _validate_decline_ammo_runt(action)
		"USE_PULSA_ROKKIT":  # OA-31: Player activates Pulsa Rokkit
			return _validate_use_pulsa_rokkit(action)
		"DECLINE_PULSA_ROKKIT":  # OA-31: Player declines Pulsa Rokkit
			return _validate_decline_pulsa_rokkit(action)
		"USE_SHOOTY_POWER_TRIP":  # OA-37: Player activates Shooty Power Trip
			return _validate_use_shooty_power_trip(action)
		"DECLINE_SHOOTY_POWER_TRIP":  # OA-37: Player declines Shooty Power Trip
			return _validate_decline_shooty_power_trip(action)
		"PERFORM_SECONDARY_ACTION":  # Action-based secondary mission (Establish Locus, Cleanse, Deploy Teleport Homer)
			return _validate_perform_secondary_action(action)
		"BURN_OBJECTIVE":  # Scorched Earth: unit burns an objective instead of shooting
			return _validate_burn_objective(action)
		"PERFORM_RITUAL_ACTION":  # The Ritual: unit performs ritual action at objective
			return _validate_perform_ritual_action(action)
		"PERFORM_TERRAFORM_ACTION":  # Terraform: unit terraforms an objective
			return _validate_perform_terraform_action(action)
		"USE_SWIFT_AS_THE_EAGLE":
			return _validate_use_swift_as_the_eagle(action)
		"DECLINE_SWIFT_AS_THE_EAGLE":
			return _validate_decline_swift_as_the_eagle(action)
		"END_MOVEMENT":
			# Idempotent no-op: previous phase auto-advanced before END_MOVEMENT was dispatched.
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	DebugLogger.info("========================================")
	DebugLogger.info("ShootingPhase: process_action CALLED")
	DebugLogger.info(str("ShootingPhase: action = ", action))

	var action_type = action.get("type", "")
	DebugLogger.info(str("ShootingPhase: action_type = ", action_type))

	match action_type:
		"SELECT_SHOOTER":
			DebugLogger.info("ShootingPhase: Matched SELECT_SHOOTER")
			return _process_select_shooter(action)
		"ASSIGN_TARGET":
			DebugLogger.info("ShootingPhase: Matched ASSIGN_TARGET")
			return _process_assign_target(action)
		"CLEAR_ASSIGNMENT":
			DebugLogger.info("ShootingPhase: Matched CLEAR_ASSIGNMENT")
			return _process_clear_assignment(action)
		"CLEAR_ALL_ASSIGNMENTS":
			DebugLogger.info("ShootingPhase: Matched CLEAR_ALL_ASSIGNMENTS")
			return _process_clear_all_assignments(action)
		"CONFIRM_TARGETS":
			DebugLogger.info("ShootingPhase: Matched CONFIRM_TARGETS")
			return _process_confirm_targets(action)
		"RESOLVE_SHOOTING":
			DebugLogger.info("ShootingPhase: Matched RESOLVE_SHOOTING")
			return _process_resolve_shooting(action)
		"RESOLVE_WEAPON_SEQUENCE":  # Sequential weapon resolution
			DebugLogger.info("ShootingPhase: Matched RESOLVE_WEAPON_SEQUENCE")
			return _process_resolve_weapon_sequence(action)
		"SKIP_UNIT":
			DebugLogger.info("ShootingPhase: Matched SKIP_UNIT")
			return _process_skip_unit(action)
		"END_SHOOTING":
			DebugLogger.info("ShootingPhase: Matched END_SHOOTING")
			return _process_end_shooting(action)
		"SHOOT":  # Full shooting action
			DebugLogger.info("ShootingPhase: Matched SHOOT")
			return _process_shoot(action)
		"APPLY_SAVES":  # Interactive save resolution
			DebugLogger.info("ShootingPhase: Matched APPLY_SAVES")
			return _process_apply_saves(action)
		"CONTINUE_SEQUENCE":  # Continue to next weapon in sequential mode
			DebugLogger.info("ShootingPhase: Matched CONTINUE_SEQUENCE")
			return _process_continue_sequence(action)
		"COMPLETE_SHOOTING_FOR_UNIT":  # Complete shooting after final weapon
			DebugLogger.info("ShootingPhase: Matched COMPLETE_SHOOTING_FOR_UNIT")
			return _process_complete_shooting_for_unit(action)
		"USE_REACTIVE_STRATAGEM":  # Defender uses a reactive stratagem
			DebugLogger.info("ShootingPhase: Matched USE_REACTIVE_STRATAGEM")
			return _process_use_reactive_stratagem(action)
		"DECLINE_REACTIVE_STRATAGEM":  # Defender declines reactive stratagem
			DebugLogger.info("ShootingPhase: Matched DECLINE_REACTIVE_STRATAGEM")
			return _process_decline_reactive_stratagem(action)
		"USE_GRENADE_STRATAGEM":  # Active player uses GRENADE stratagem
			DebugLogger.info("ShootingPhase: Matched USE_GRENADE_STRATAGEM")
			return _process_use_grenade_stratagem(action)
		"USE_STRATAGEM":  # Active player uses a proactive (non-grenade) stratagem with phase: "shooting"
			DebugLogger.info("ShootingPhase: Matched USE_STRATAGEM")
			return _process_use_stratagem(action)
		"USE_SENTINEL_STORM":  # P1-10: Player uses Sentinel Storm
			DebugLogger.info("ShootingPhase: Matched USE_SENTINEL_STORM")
			return _process_use_sentinel_storm(action)
		"DECLINE_SENTINEL_STORM":  # P1-10: Player declines Sentinel Storm
			DebugLogger.info("ShootingPhase: Matched DECLINE_SENTINEL_STORM")
			return _process_decline_sentinel_storm(action)
		"USE_THROAT_SLITTAS":  # P1-12: Player uses Throat Slittas
			DebugLogger.info("ShootingPhase: Matched USE_THROAT_SLITTAS")
			return _process_use_throat_slittas(action)
		"DECLINE_THROAT_SLITTAS":  # P1-12: Player declines Throat Slittas
			DebugLogger.info("ShootingPhase: Matched DECLINE_THROAT_SLITTAS")
			return _process_decline_throat_slittas(action)
		"USE_DISTRACTION_GROT":  # P2-25: Defender activates Distraction Grot
			DebugLogger.info("ShootingPhase: Matched USE_DISTRACTION_GROT")
			return _process_use_distraction_grot(action)
		"DECLINE_DISTRACTION_GROT":  # P2-25: Defender declines Distraction Grot
			DebugLogger.info("ShootingPhase: Matched DECLINE_DISTRACTION_GROT")
			return _process_decline_distraction_grot(action)
		"USE_AMMO_RUNT":  # OA-10: Player activates Ammo Runt
			DebugLogger.info("ShootingPhase: Matched USE_AMMO_RUNT")
			return _process_use_ammo_runt(action)
		"DECLINE_AMMO_RUNT":  # OA-10: Player declines Ammo Runt
			DebugLogger.info("ShootingPhase: Matched DECLINE_AMMO_RUNT")
			return _process_decline_ammo_runt(action)
		"USE_PULSA_ROKKIT":  # OA-31: Player activates Pulsa Rokkit
			DebugLogger.info("ShootingPhase: Matched USE_PULSA_ROKKIT")
			return _process_use_pulsa_rokkit(action)
		"DECLINE_PULSA_ROKKIT":  # OA-31: Player declines Pulsa Rokkit
			DebugLogger.info("ShootingPhase: Matched DECLINE_PULSA_ROKKIT")
			return _process_decline_pulsa_rokkit(action)
		"USE_SHOOTY_POWER_TRIP":  # OA-37: Player activates Shooty Power Trip
			DebugLogger.info("ShootingPhase: Matched USE_SHOOTY_POWER_TRIP")
			return _process_use_shooty_power_trip(action)
		"DECLINE_SHOOTY_POWER_TRIP":  # OA-37: Player declines Shooty Power Trip
			DebugLogger.info("ShootingPhase: Matched DECLINE_SHOOTY_POWER_TRIP")
			return _process_decline_shooty_power_trip(action)
		"PERFORM_SECONDARY_ACTION":  # Action-based secondary mission
			DebugLogger.info("ShootingPhase: Matched PERFORM_SECONDARY_ACTION")
			return _process_perform_secondary_action(action)
		"BURN_OBJECTIVE":  # Scorched Earth: burn objective
			DebugLogger.info("ShootingPhase: Matched BURN_OBJECTIVE")
			return _process_burn_objective(action)
		"PERFORM_RITUAL_ACTION":  # The Ritual: perform ritual action
			DebugLogger.info("ShootingPhase: Matched PERFORM_RITUAL_ACTION")
			return _process_perform_ritual_action(action)
		"PERFORM_TERRAFORM_ACTION":  # Terraform: terraform an objective
			DebugLogger.info("ShootingPhase: Matched PERFORM_TERRAFORM_ACTION")
			return _process_perform_terraform_action(action)
		"USE_SWIFT_AS_THE_EAGLE":
			DebugLogger.info("ShootingPhase: Matched USE_SWIFT_AS_THE_EAGLE")
			return _process_use_swift_as_the_eagle(action)
		"DECLINE_SWIFT_AS_THE_EAGLE":
			DebugLogger.info("ShootingPhase: Matched DECLINE_SWIFT_AS_THE_EAGLE")
			return _process_decline_swift_as_the_eagle(action)
		"END_MOVEMENT":
			DebugLogger.info("ShootingPhase: Matched END_MOVEMENT (no-op, phase already advanced)")
			return create_result(true, [], "")
		_:
			DebugLogger.info("ShootingPhase: NO MATCH - returning error")
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

	# P3-96: "Unless at least one model in a unit has an eligible target,
	# that unit cannot be selected to shoot." (SHOOT-7)
	if not _has_eligible_targets(unit_id):
		DebugLogger.info(str("ShootingPhase: P3-96 Unit %s cannot be selected to shoot — no eligible targets" % unit_id))
		return {"valid": false, "errors": ["Unit has no eligible targets to shoot"]}

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
	
	# P2-91: Allow reassigning a weapon to a different target.
	# The old check blocked reassignment by treating it as "splitting attacks".
	# In reality, _process_assign_target() replaces the old assignment, so
	# there's never two targets for the same weapon simultaneously.
	# No validation needed here — reassignment is always valid.

	# MA-25: PISTOL MUTUAL EXCLUSIVITY — per-model check (was unit-wide before MA-25)
	# Per 10e: "If a model is equipped with one or more Pistols, unless it is a
	# MONSTER or VEHICLE model, it can either shoot with its Pistols or with all
	# of its other ranged weapons."
	# Per-model: each model individually must choose pistol or non-pistol, but
	# different models in the same unit can make different choices.
	var shooter_unit = get_unit(active_shooter_id)
	if not RulesEngine.is_monster_or_vehicle(shooter_unit):
		var new_weapon_is_pistol = RulesEngine.is_pistol_weapon(weapon_id, game_state_snapshot)
		# Check each model in the new assignment against existing assignments
		for new_model_id in model_ids:
			for assignment in pending_assignments:
				var existing_weapon_id = assignment.get("weapon_id", "")
				if existing_weapon_id == "":
					continue
				var existing_model_ids = assignment.get("model_ids", [])
				if new_model_id not in existing_model_ids:
					continue  # This existing assignment doesn't involve this model
				var existing_is_pistol = RulesEngine.is_pistol_weapon(existing_weapon_id, game_state_snapshot)
				if new_weapon_is_pistol and not existing_is_pistol:
					return {"valid": false, "errors": ["Model '%s' cannot fire Pistol weapons when non-Pistol weapons are already assigned — must choose one or the other" % new_model_id]}
				if not new_weapon_is_pistol and existing_is_pistol:
					return {"valid": false, "errors": ["Model '%s' cannot fire non-Pistol weapons when Pistol weapons are already assigned — must choose one or the other" % new_model_id]}

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

	# Enforce engagement range restrictions (Pistol-only, engaged targets only)
	var shooter_unit = get_unit(active_shooter_id)
	if shooter_unit.get("flags", {}).get("in_engagement", false):
		var is_monster_vehicle = RulesEngine.is_monster_or_vehicle(shooter_unit)
		for assignment in pending_assignments:
			var wid = assignment.get("weapon_id", "")
			var tid = assignment.get("target_unit_id", "")
			if not is_monster_vehicle and not RulesEngine.is_pistol_weapon(wid, game_state_snapshot):
				return {"valid": false, "errors": ["Unit is in engagement — only Pistol weapons can fire"]}
			if not RulesEngine._check_units_in_engagement_range(shooter_unit, get_unit(tid), game_state_snapshot):
				return {"valid": false, "errors": ["Unit is in engagement — can only target engaged units"]}

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

func _validate_perform_secondary_action(action: Dictionary) -> Dictionary:
	"""Validate a unit performing a secondary mission action instead of shooting."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting — deployed, not battle-shocked, hasn't shot
	if not _can_unit_shoot(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform an action (same requirements as shooting)"]}

	if unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	var action_name = action.get("payload", {}).get("action_name", "")
	if action_name == "":
		return {"valid": false, "errors": ["Missing action_name in payload"]}

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
	_targets_hit_by_shooter.clear()  # P1-11: Reset hit tracking for new shooter

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

	# P1-12: Check for Throat Slittas — offer mortal wounds instead of shooting
	if not action.get("payload", {}).get("skip_throat_slittas_check", false):
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_throat_slittas_ability(unit_id):
			var ts_targets = _get_throat_slittas_targets(unit_id)
			if not ts_targets.is_empty():
				DebugLogger.info(str("ShootingPhase: P1-12 Throat Slittas: Unit %s has enemies within 9\" — prompting" % unit_id))
				throat_slittas_pending_unit = unit_id

				var current_player = get_current_player()
				emit_signal("throat_slittas_available", unit_id, current_player, ts_targets)

				log_phase_message("Throat Slittas available for %s — awaiting decision" % unit.get("meta", {}).get("name", unit_id))

				return create_result(true, [], "Throat Slittas available", {
					"throat_slittas_available": true,
					"unit_id": unit_id,
					"eligible_targets": ts_targets
				})

	# OA-10: Check for Ammo Runt — offer Lethal Hits for ranged weapons
	if not action.get("payload", {}).get("skip_ammo_runt_check", false):
		var ability_mgr_ar = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr_ar and ability_mgr_ar.has_ammo_runt(unit_id):
			var remaining = ability_mgr_ar.get_ammo_runts_remaining(unit_id)
			var total = ability_mgr_ar.get_ammo_runt_count(unit_id)
			DebugLogger.info(str("ShootingPhase: OA-10 Ammo Runt: Unit %s has %d/%d runts remaining — prompting" % [unit_id, remaining, total]))
			ammo_runt_pending_unit = unit_id
			awaiting_ammo_runt = true

			var current_player = get_current_player()
			emit_signal("ammo_runt_available", unit_id, current_player, remaining)

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("Ammo Runt available for %s (%d remaining) — awaiting decision" % [unit_name, remaining])

			return create_result(true, [], "Ammo Runt available", {
				"ammo_runt_available": true,
				"unit_id": unit_id,
				"remaining": remaining,
				"total": total
			})

	# OA-31: Check for Pulsa Rokkit — offer +1S/+1AP for ranged weapons
	if not action.get("payload", {}).get("skip_pulsa_rokkit_check", false):
		var ability_mgr_pr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr_pr and ability_mgr_pr.has_pulsa_rokkit(unit_id):
			DebugLogger.info(str("ShootingPhase: OA-31 Pulsa Rokkit: Unit %s has unused Pulsa Rokkit — prompting" % unit_id))
			pulsa_rokkit_pending_unit = unit_id
			awaiting_pulsa_rokkit = true

			var current_player = get_current_player()
			emit_signal("pulsa_rokkit_available", unit_id, current_player)

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("Pulsa Rokkit available for %s — awaiting decision" % unit_name)

			return create_result(true, [], "Pulsa Rokkit available", {
				"pulsa_rokkit_available": true,
				"unit_id": unit_id
			})

	# OA-37: Check for Shooty Power Trip — offer D6 roll (Killa Kans)
	if not action.get("payload", {}).get("skip_shooty_power_trip_check", false):
		var ability_mgr_spt = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr_spt and ability_mgr_spt.has_shooty_power_trip(unit_id):
			DebugLogger.info(str("ShootingPhase: OA-37 Shooty Power Trip: Unit %s has Shooty Power Trip — prompting" % unit_id))
			shooty_power_trip_pending_unit = unit_id
			awaiting_shooty_power_trip = true

			var current_player = get_current_player()
			emit_signal("shooty_power_trip_available", unit_id, current_player)

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("Shooty Power Trip available for %s — awaiting decision" % unit_name)

			return create_result(true, [], "Shooty Power Trip available", {
				"shooty_power_trip_available": true,
				"unit_id": unit_id
			})

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

	# Issue #386 Big Booms: roll concussive wave on supa-kannon target selection.
	# Trigger phrase: "just after selecting a target for this model's supa-kannon".
	if weapon_id.to_lower().find("supa-kannon") != -1 and active_shooter_id != "":
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_method("roll_big_booms_concussive_wave"):
			var rolls = ability_mgr.roll_big_booms_concussive_wave(active_shooter_id, target_unit_id)
			if not rolls.is_empty():
				var struck_ids: Array = []
				for r in rolls:
					if r.get("struck", false):
						struck_ids.append(r.get("unit_id", ""))
				if not struck_ids.is_empty():
					_big_booms_pending.append({
						"target_unit_id": target_unit_id,
						"struck_unit_ids": struck_ids,
						"rolls": rolls,
					})
					log_phase_message("Big Booms concussive wave: %d unit(s) struck (rolls=%s)" % [struck_ids.size(), str(rolls)])
				else:
					log_phase_message("Big Booms concussive wave: no units struck (rolls=%s)" % [str(rolls)])

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

	# P2-25: Check for Distraction Grot on targeted units
	var distraction_grot_check = _check_distraction_grot()
	if distraction_grot_check.get("has_opportunity", false):
		var dg_unit_id = distraction_grot_check.unit_id
		var dg_player = distraction_grot_check.player
		awaiting_distraction_grot = true
		distraction_grot_pending_unit = dg_unit_id
		resolution_state = {
			"phase": "awaiting_distraction_grot",
			"assignments": confirmed_assignments
		}
		var dg_name = get_unit(dg_unit_id).get("meta", {}).get("name", dg_unit_id)
		log_phase_message("Distraction Grot available for %s — awaiting decision" % dg_name)
		emit_signal("distraction_grot_available", dg_unit_id, dg_player)
		return create_result(true, [], "Awaiting Distraction Grot decision", {
			"distraction_grot_available": true,
			"unit_id": dg_unit_id,
			"player": dg_player
		})

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
	DebugLogger.info(str("ShootingPhase: Merged and confirmed %d assignments with %d unique weapon types" % [confirmed_assignments.size(), weapon_count]))

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ WEAPON COUNT CHECK IN _process_confirm_targets")
	DebugLogger.info(str("║ weapon_count: ", weapon_count))
	DebugLogger.info(str("║ Will enter sequential mode: ", weapon_count >= 2))
	DebugLogger.info(str("║ Single weapon path: ", weapon_count == 1))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SINGLE WEAPON PATH - _process_confirm_targets")
	DebugLogger.info("║ Initializing resolution_state with mode: 'ready'")
	DebugLogger.info("║ This is NOT sequential mode")
	DebugLogger.info("║ Calling _process_resolve_shooting() directly")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SINGLE WEAPON - _process_resolve_shooting returned")
	DebugLogger.info(str("║ resolve_result.success: ", resolve_result.success))
	DebugLogger.info(str("║ resolve_result has save_data_list: ", resolve_result.has("save_data_list")))
	if resolve_result.has("save_data_list"):
		DebugLogger.info(str("║ save_data_list size: ", resolve_result.get("save_data_list", []).size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SINGLE WEAPON - Returning from _process_confirm_targets")
	if initial_result.has("sequential_pause"):
		DebugLogger.info(str("║ ✅ sequential_pause INCLUDED in result: ", initial_result.get("sequential_pause", false)))
		DebugLogger.info(str("║ ✅ remaining_weapons size: ", initial_result.get("remaining_weapons", []).size()))
		DebugLogger.info(str("║ ✅ last_weapon_result exists: ", initial_result.has("last_weapon_result")))
	elif resolve_result.has("save_data_list") and not resolve_result.get("save_data_list", []).is_empty():
		DebugLogger.info("║ Result will trigger saves dialog")
		DebugLogger.info("║ After saves, _process_apply_saves will be called")
	else:
		DebugLogger.info("║ ⚠️  WARNING: No sequential_pause or save_data_list in result!")
		DebugLogger.info("║ This weapon likely missed and dialog won't show!")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	return initial_result

func _process_resolve_shooting(action: Dictionary) -> Dictionary:
	# Trigger attack animation on the shooting unit
	_trigger_unit_animation(active_shooter_id, "attack")

	# VERBOSE COMBAT LOG: Emit combat header BEFORE resolution so dice can display in real-time
	var _vcl_shooter = game_state_snapshot.get("units", {}).get(active_shooter_id, {})
	var _vcl_shooter_name = _vcl_shooter.get("meta", {}).get("name", active_shooter_id)
	if not confirmed_assignments.is_empty():
		var _vcl_target_id = confirmed_assignments[0].get("target_unit_id", "")
		var _vcl_target = game_state_snapshot.get("units", {}).get(_vcl_target_id, {})
		var _vcl_target_name = _vcl_target.get("meta", {}).get("name", _vcl_target_id)
		var _vcl_weapon_id = confirmed_assignments[0].get("weapon_id", "")
		var _vcl_weapon_profile = RulesEngine.get_weapon_profile(_vcl_weapon_id)
		var _vcl_weapon_name = _vcl_weapon_profile.get("name", _vcl_weapon_id)
		GameEventLog.add_combat_header("P%d: %s shoots at %s with %s" % [
			get_current_player(), _vcl_shooter_name, _vcl_target_name, _vcl_weapon_name])

	# T5-MP5: Build resolution_start block and emit locally + include in result for remote sync
	var _rs_weapon_name = ""
	var _rs_target_name = ""
	if not confirmed_assignments.is_empty():
		var _rs_wid = confirmed_assignments[0].get("weapon_id", "")
		_rs_weapon_name = RulesEngine.get_weapon_profile(_rs_wid).get("name", _rs_wid)
		var _rs_tid = confirmed_assignments[0].get("target_unit_id", "")
		_rs_target_name = game_state_snapshot.get("units", {}).get(_rs_tid, {}).get("meta", {}).get("name", _rs_tid)
	var _rs_msg = "%s → %s" % [_rs_weapon_name, _rs_target_name] if _rs_weapon_name != "" else "Beginning attack resolution..."
	var resolution_start_block = {"context": "resolution_start", "message": _rs_msg}
	emit_signal("dice_rolled", resolution_start_block)

	# Build full shoot action for RulesEngine
	# Issue #329: forward action.payload.rng_seed into the dispatched shoot_action so RulesEngine
	# routes it through RNGService (deterministic when test_mode_seed or explicit seed is set)
	var rs_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": confirmed_assignments,
			"rng_seed": rs_seed
		}
	}

	# Resolve with RulesEngine UP TO WOUNDS (interactive saves)
	var rng_service = RulesEngine.RNGService.new(rs_seed)
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

	if not result.success:
		return create_result(false, [], result.get("log_text", "Shooting failed"))

	# ONE SHOT (T4-2): Collect one-shot diffs from result (weapon marked as fired immediately)
	var one_shot_diffs = result.get("one_shot_diffs", [])

	# Record hit/wound dice rolls
	# T5-MP5: Prepend resolution_start block so remote player sees it in broadcast
	var dice_data = [resolution_start_block] + result.get("dice", [])
	for dice_block in result.get("dice", []):
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Attack rolls complete"))

	# Emit hit/wound detail lines from dice data
	_emit_verbose_combat_log(active_shooter_id, dice_data, [], 0, "shooting_hits")

	# Extract hit/wound data from dice blocks and store in resolution_state
	# so _process_apply_saves can build accurate last_weapon_result (T4-15)
	var hit_data = {}
	var wound_data = {}
	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "hit_roll" or context == "to_hit":
			hit_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"rerolls": dice_block.get("rerolls", []),
				"threshold": dice_block.get("threshold", "")
			}
		elif context == "auto_hit":
			hit_data = {
				"rolls": [],
				"modified_rolls": [],
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("total_attacks", 0),
				"rerolls": [],
				"threshold": "auto",
				"torrent": true
			}
		elif context == "wound_roll" or context == "to_wound":
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

	# P1-11: Track hits for Sanctified Flames (single-weapon resolve path)
	var resolve_hits = hit_data.get("successes", 0)
	if resolve_hits > 0 and not confirmed_assignments.is_empty():
		var resolve_tid = confirmed_assignments[0].get("target_unit_id", "")
		if resolve_tid != "":
			_targets_hit_by_shooter[resolve_tid] = _targets_hit_by_shooter.get(resolve_tid, 0) + resolve_hits
			DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking (resolve): %d hit(s) on %s" % [resolve_hits, resolve_tid]))

	# Check if any saves are needed
	var save_data_list = result.get("save_data_list", [])

	if save_data_list.is_empty():
		# No wounds caused — finalize the combat log card
		GameEventLog.add_combat_result("  Result: No wounds caused — attack missed")
		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info("║ NO WOUNDS CAUSED - Weapon missed!")
		DebugLogger.info(str("║ resolution_state.mode: '", resolution_state.get("mode", ""), "'"))
		DebugLogger.info(str("║ Is single weapon: ", resolution_state.get("mode", "") == ""))
		DebugLogger.info(str("║ active_shooter_id: ", active_shooter_id))
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

		# HAZARDOUS (T2-3): Still process Hazardous check even if weapon missed
		var haz_diffs_on_miss = []
		var hazardous_weapons_on_miss = result.get("hazardous_weapons", [])
		if not hazardous_weapons_on_miss.is_empty():
			DebugLogger.info(str("║ HAZARDOUS: Processing %d hazardous weapon check(s) despite miss" % hazardous_weapons_on_miss.size()))
			var haz_rng = RulesEngine.RNGService.new(rs_seed)  # Issue #329: forward seed
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
			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ 🎯 SINGLE WEAPON MISS - Showing results dialog")
			DebugLogger.info("║ Building last_weapon_result for missed shot...")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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

				# P1-11: Track hits for Sanctified Flames (single weapon miss path)
				if hits > 0 and target_unit_id != "":
					_targets_hit_by_shooter[target_unit_id] = _targets_hit_by_shooter.get(target_unit_id, 0) + hits
					DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking (single miss): %d hit(s) on %s" % [hits, target_unit_id]))

				DebugLogger.info("║ last_weapon_result built:")
				DebugLogger.info(str("║   weapon: ", last_weapon_result.get("weapon_name", "")))
				DebugLogger.info(str("║   hits: ", hits, " / ", total_attacks))
				DebugLogger.info("║   wounds: 0 (missed)")
				DebugLogger.info("║   casualties: 0")

				# Record completed weapon so phase_shooting_log captures single-weapon miss
				if not resolution_state.has("completed_weapons"):
					resolution_state["completed_weapons"] = []
				resolution_state.completed_weapons.append({
					"weapon_id": weapon_id,
					"target_unit_id": target_unit_id,
					"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
					"wounds": 0,
					"casualties": 0,
					"hits": hits,
					"total_attacks": total_attacks,
					"saves_failed": 0,
					"dice_rolls": dice_data,
					"hit_data": miss_hit_data,
					"wound_data": miss_wound_data
				})

			# Emit signal with EMPTY remaining_weapons (signals completion)
			DebugLogger.info("║")
			DebugLogger.info("║ 📡 EMITTING next_weapon_confirmation_required SIGNAL (for miss)")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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
		DebugLogger.info("║ Sequential mode - completing immediately")
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
		# Return shooter to idle animation
		_trigger_unit_animation(active_shooter_id, "idle")
		_record_completed_weapons_to_phase_log(shooter_id)  # T5-UX9: capture before clearing
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

	# T5-MP4-RELIABILITY: stamp every entry with a unique broadcast id BEFORE
	# emitting locally / bundling into the result, so the defender's controller
	# and the attacker's ack/retry timer have a precise match key.
	var broadcast_id := _generate_save_broadcast_id()
	_stamp_save_broadcast_id(save_data_list, broadcast_id)

	# LOGGING: Track saves_required emission
	var timestamp = Time.get_ticks_msec()
	var save_context = {
		"timestamp": timestamp,
		"source": "ShootingPhase._process_resolve_shooting",
		"save_count": save_data_list.size(),
		"target": save_data_list[0].get("target_unit_id", "unknown") if save_data_list.size() > 0 else "none",
		"weapon": save_data_list[0].get("weapon_name", "unknown") if save_data_list.size() > 0 else "none",
		"wounds": save_data_list[0].get("wounds_to_save", 0) if save_data_list.size() > 0 else 0,
		"broadcast_id": broadcast_id
	}
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SAVES_REQUIRED EMISSION #1 (from resolve_shooting)")
	DebugLogger.info(str("║ Timestamp: ", timestamp))
	DebugLogger.info("║ Source: ShootingPhase._process_resolve_shooting (line 444)")
	DebugLogger.info(str("║ Target: ", save_context.target))
	DebugLogger.info(str("║ Weapon: ", save_context.weapon))
	DebugLogger.info(str("║ Wounds: ", save_context.wounds))
	DebugLogger.info(str("║ Broadcast ID: ", broadcast_id))
	DebugLogger.info(str("║ Save data list size: ", save_data_list.size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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

func _process_perform_secondary_action(action: Dictionary) -> Dictionary:
	"""Process a unit performing a secondary mission action (gives up shooting)."""
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var action_name = payload.get("action_name", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s performs action '%s' (gives up shooting)" % [unit_name, action_name]))

	# Mark unit as having shot (it gave up shooting to perform the action)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}, {
		"op": "set",
		"path": "units.%s.flags.performed_action" % unit_id,
		"value": action_name
	}]

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Determine location context for the action
	var action_data = {
		"action_name": action_name,
		"completed": true,
		"unit_id": unit_id,
	}

	match action_name:
		"Establish Locus":
			action_data["location"] = _determine_locus_location(unit_id, player)
		"Deploy Teleport Homer":
			action_data["location"] = _determine_homer_location(unit_id, player)
		"Cleanse":
			action_data["location"] = "objective"
			var obj_id = _determine_cleanse_objective(unit_id)
			if obj_id != "":
				action_data["objective_id"] = obj_id

	# Report action completion to SecondaryMissionManager
	SecondaryMissionManager.on_action_completed(player, action_data)

	log_phase_message("%s performs %s (gives up shooting)" % [unit_name, action_name])

	return create_result(true, changes)

# ============================================================================
# BURN OBJECTIVE — Scorched Earth mission action
# ============================================================================

func _validate_burn_objective(action: Dictionary) -> Dictionary:
	"""Validate a burn objective action for Scorched Earth mission."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting
	if not _can_unit_shoot(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform burn action"]}

	if unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	var objective_id = action.get("objective_id", "")
	if objective_id == "":
		return {"valid": false, "errors": ["Missing objective_id"]}

	# Verify the objective is actually burnable by this unit
	var burnable = MissionManager.get_burnable_objectives_for_unit(unit_id)
	var found = false
	for b in burnable:
		if b.objective_id == objective_id:
			found = true
			break

	if not found:
		return {"valid": false, "errors": ["Objective %s is not burnable by this unit" % objective_id]}

	return {"valid": true, "errors": []}

func _process_burn_objective(action: Dictionary) -> Dictionary:
	"""Process a burn objective action — unit gives up shooting to burn an objective."""
	var unit_id = action.get("actor_unit_id", "")
	var objective_id = action.get("objective_id", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s burns objective %s (gives up shooting)" % [unit_name, objective_id]))

	# Mark unit as having shot (it gave up shooting to burn)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]

	# Also mark as unable to charge this turn (burn action costs charging too)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.burned_objective" % unit_id,
		"value": true
	})

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Register the burn with MissionManager
	var success = MissionManager.register_burn_action(unit_id, objective_id)
	if success:
		log_phase_message("SCORCHED EARTH: %s burned %s for Player %d" % [unit_name, objective_id, player])
	else:
		log_phase_message("ERROR: Burn action failed for %s on %s" % [unit_name, objective_id])

	return create_result(true, changes)

func _get_burn_objective_options(unit_id: String) -> Array:
	"""Get available burn objective options for a unit (Scorched Earth mission only).
	Returns array of {objective_id, zone, burn_vp, position}."""
	if not MissionManager or not MissionManager.is_scorched_earth_mission():
		return []

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	# Unit must not be battle-shocked
	if unit.get("flags", {}).get("battle_shocked", false):
		return []

	return MissionManager.get_burnable_objectives_for_unit(unit_id)

# ============================================================================
# PERFORM RITUAL ACTION — The Ritual mission action
# ============================================================================

func _validate_perform_ritual_action(action: Dictionary) -> Dictionary:
	"""Validate a ritual action for The Ritual mission."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting — deployed, not battle-shocked, hasn't shot
	if not _can_unit_shoot(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform ritual action"]}

	if unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	# Units that Advanced or Fell Back cannot perform actions
	var flags = unit.get("flags", {})
	if flags.get("advanced", false):
		return {"valid": false, "errors": ["Unit Advanced this turn and cannot perform actions"]}
	if flags.get("fell_back", false):
		return {"valid": false, "errors": ["Unit Fell Back this turn and cannot perform actions"]}

	var objective_id = action.get("objective_id", "")
	if objective_id == "":
		return {"valid": false, "errors": ["Missing objective_id"]}

	# Verify the objective is valid for ritual by this unit
	var ritual_targets = MissionManager.get_ritual_objectives_for_unit(unit_id)
	var found = false
	for r in ritual_targets:
		if r.objective_id == objective_id:
			found = true
			break

	if not found:
		return {"valid": false, "errors": ["Objective %s is not a valid ritual target for this unit" % objective_id]}

	return {"valid": true, "errors": []}

func _process_perform_ritual_action(action: Dictionary) -> Dictionary:
	"""Process a ritual action — unit gives up shooting to perform ritual at objective."""
	var unit_id = action.get("actor_unit_id", "")
	var objective_id = action.get("objective_id", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s performs ritual action at %s (gives up shooting)" % [unit_name, objective_id]))

	# Mark unit as having shot (it gave up shooting to perform the ritual)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]

	# Mark as unable to charge this turn (action costs charging too)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.performed_ritual" % unit_id,
		"value": true
	})

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Register the ritual with MissionManager
	var success = MissionManager.register_ritual_action(unit_id, objective_id)
	if success:
		log_phase_message("THE RITUAL: %s performed ritual at %s for Player %d" % [unit_name, objective_id, player])
	else:
		log_phase_message("ERROR: Ritual action failed for %s at %s" % [unit_name, objective_id])

	return create_result(true, changes)

func _get_ritual_action_options(unit_id: String) -> Array:
	"""Get available ritual action options for a unit (The Ritual mission only).
	Returns array of {objective_id, position}."""
	if not MissionManager or not MissionManager.is_ritual_mission():
		return []

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	# Unit must not be battle-shocked
	if unit.get("flags", {}).get("battle_shocked", false):
		return []

	# Units that Advanced or Fell Back cannot perform actions
	if unit.get("flags", {}).get("advanced", false):
		return []
	if unit.get("flags", {}).get("fell_back", false):
		return []

	return MissionManager.get_ritual_objectives_for_unit(unit_id)

# ============================================================================
# PERFORM TERRAFORM ACTION — Terraform mission action
# ============================================================================

func _validate_perform_terraform_action(action: Dictionary) -> Dictionary:
	"""Validate a terraform action for the Terraform mission."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting — deployed, not battle-shocked, hasn't shot
	if not _can_unit_shoot(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform terraform action"]}

	if unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	# Units that Advanced or Fell Back cannot perform actions
	var flags = unit.get("flags", {})
	if flags.get("advanced", false):
		return {"valid": false, "errors": ["Unit Advanced this turn and cannot perform actions"]}
	if flags.get("fell_back", false):
		return {"valid": false, "errors": ["Unit Fell Back this turn and cannot perform actions"]}

	var objective_id = action.get("objective_id", "")
	if objective_id == "":
		return {"valid": false, "errors": ["Missing objective_id"]}

	# Verify the objective is valid for terraforming by this unit
	var terraform_targets = MissionManager.get_terraformable_objectives_for_unit(unit_id)
	var found = false
	for t in terraform_targets:
		if t.objective_id == objective_id:
			found = true
			break

	if not found:
		return {"valid": false, "errors": ["Objective %s is not a valid terraform target for this unit" % objective_id]}

	return {"valid": true, "errors": []}

func _process_perform_terraform_action(action: Dictionary) -> Dictionary:
	"""Process a terraform action — unit gives up shooting to terraform an objective."""
	var unit_id = action.get("actor_unit_id", "")
	var objective_id = action.get("objective_id", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s performs terraform action at %s (gives up shooting)" % [unit_name, objective_id]))

	# Mark unit as having shot (it gave up shooting to perform the terraform)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]

	# Mark as unable to charge this turn (action costs charging too)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.performed_terraform" % unit_id,
		"value": true
	})

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Register the terraform with MissionManager
	var success = MissionManager.register_terraform_action(unit_id, objective_id)
	if success:
		var is_flip = action.get("is_flip", false)
		if is_flip:
			log_phase_message("TERRAFORM: %s flipped %s for Player %d" % [unit_name, objective_id, player])
		else:
			log_phase_message("TERRAFORM: %s terraformed %s for Player %d" % [unit_name, objective_id, player])
	else:
		log_phase_message("ERROR: Terraform action failed for %s at %s" % [unit_name, objective_id])

	return create_result(true, changes)

func _get_terraform_action_options(unit_id: String) -> Array:
	"""Get available terraform action options for a unit (Terraform mission only).
	Returns array of {objective_id, zone, position, is_flip}."""
	if not MissionManager or not MissionManager.is_terraform_mission():
		return []

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	# Unit must not be battle-shocked
	if unit.get("flags", {}).get("battle_shocked", false):
		return []

	# Units that Advanced or Fell Back cannot perform actions
	if unit.get("flags", {}).get("advanced", false):
		return []
	if unit.get("flags", {}).get("fell_back", false):
		return []

	return MissionManager.get_terraformable_objectives_for_unit(unit_id)

func _determine_locus_location(unit_id: String, player: int) -> String:
	"""Determine location qualifier for Establish Locus: 'opponent_zone' or 'center'."""
	var unit = get_unit(unit_id)
	var opponent = 2 if player == 1 else 1
	var opponent_zone = SecondaryMissionManager._get_deployment_zone_polygon(opponent)

	# Check opponent zone first (higher VP)
	if not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone):
		return "opponent_zone"

	# Check within 6" of board center
	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_px = Vector2(
		Measurement.inches_to_px(board_width / 2.0),
		Measurement.inches_to_px(board_height / 2.0)
	)
	if SecondaryMissionManager._has_model_within_range(unit, center_px, Measurement.inches_to_px(6.0)):
		return "center"

	return "other"

func _determine_homer_location(unit_id: String, player: int) -> String:
	"""Determine location qualifier for Deploy Teleport Homer: 'opponent_zone' or 'other'."""
	var unit = get_unit(unit_id)
	var opponent = 2 if player == 1 else 1
	var opponent_zone = SecondaryMissionManager._get_deployment_zone_polygon(opponent)

	if not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone):
		return "opponent_zone"

	return "other"

func _determine_cleanse_objective(unit_id: String) -> String:
	"""Find the objective within control range (3\" + 20mm marker base) of a unit's model for Cleanse action. Returns objective id or empty."""
	var unit = get_unit(unit_id)
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	var control_radius = Measurement.inches_to_px(3.78740157)

	for obj in objectives:
		var obj_pos = obj.get("position", Vector2.ZERO)
		if obj_pos == Vector2.ZERO:
			continue
		if SecondaryMissionManager._has_model_within_range(unit, obj_pos, control_radius):
			return obj.get("id", "")

	return ""

func _get_secondary_action_options(unit_id: String) -> Array:
	"""Get available secondary action options for a unit based on its position.
	Returns array of dicts: [{action_name, location, description, mission_id}]"""
	var player = get_current_player()
	var options = []

	var action_missions = SecondaryMissionManager.get_action_missions_for_player(player)
	if action_missions.is_empty():
		DebugLogger.info(str("ShootingPhase: _get_secondary_action_options - no action missions for player %d" % player))
		return options
	DebugLogger.info(str("ShootingPhase: _get_secondary_action_options - %d action missions for player %d" % [action_missions.size(), player]))

	var unit = get_unit(unit_id)
	if unit.is_empty():
		DebugLogger.info(str("ShootingPhase: _get_secondary_action_options - unit %s is empty" % unit_id))
		return options

	var opponent = 2 if player == 1 else 1
	var opponent_zone = SecondaryMissionManager._get_deployment_zone_polygon(opponent)
	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_px = Vector2(
		Measurement.inches_to_px(board_width / 2.0),
		Measurement.inches_to_px(board_height / 2.0)
	)

	for mission in action_missions:
		var mission_id = mission.get("id", "")
		var action_info = mission.get("action", {})
		var action_name = action_info.get("name", "")

		match mission_id:
			"establish_locus":
				# Check if unit is in opponent zone (5 VP) or within 6" of center (3 VP)
				var in_opp_zone = not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone)
				var near_center = SecondaryMissionManager._has_model_within_range(unit, center_px, Measurement.inches_to_px(6.0))

				if in_opp_zone:
					options.append({
						"action_name": action_name,
						"location": "opponent_zone",
						"description": "Establish Locus in opponent zone (5 VP)",
						"mission_id": mission_id,
						"vp_value": 5
					})
				elif near_center:
					options.append({
						"action_name": action_name,
						"location": "center",
						"description": "Establish Locus near center (3 VP)",
						"mission_id": mission_id,
						"vp_value": 3
					})

			"deploy_teleport_homer":
				var in_opp_zone = not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone)

				if in_opp_zone:
					options.append({
						"action_name": action_name,
						"location": "opponent_zone",
						"description": "Deploy Homer in opponent zone (5 VP)",
						"mission_id": mission_id,
						"vp_value": 5
					})
				else:
					# Can deploy homer anywhere (3 VP)
					options.append({
						"action_name": action_name,
						"location": "other",
						"description": "Deploy Teleport Homer (3 VP)",
						"mission_id": mission_id,
						"vp_value": 3
					})

			"cleanse":
				# Check if unit has a model within objective control range (3" + 20mm marker base)
				var objectives = GameState.state.get("board", {}).get("objectives", [])
				var control_radius = Measurement.inches_to_px(3.78740157)
				DebugLogger.info(str("ShootingPhase: Cleanse check - %d objectives, control_radius=%.1fpx, unit=%s" % [objectives.size(), control_radius, unit_id]))
				var found_cleanse = false
				for obj in objectives:
					var obj_pos = obj.get("position", Vector2.ZERO)
					if obj_pos == Vector2.ZERO:
						DebugLogger.info("ShootingPhase: Cleanse - skipping objective with zero position")
						continue
					var in_range = SecondaryMissionManager._has_model_within_range(unit, obj_pos, control_radius)
					var obj_id = obj.get("id", "unknown")
					DebugLogger.info(str("ShootingPhase: Cleanse - obj %s at %s, in_range=%s" % [obj_id, obj_pos, in_range]))
					if in_range:
						options.append({
							"action_name": action_name,
							"location": "objective",
							"description": "Cleanse %s (2-5 VP)" % obj_id,
							"mission_id": mission_id,
							"vp_value": 2,
							"objective_id": obj_id
						})
						found_cleanse = true
						break  # One cleanse per unit
				if not found_cleanse:
					DebugLogger.info(str("ShootingPhase: Cleanse - no objective in range for unit %s" % unit_id))

	return options

func _process_end_shooting(action: Dictionary) -> Dictionary:
	var changes = []
	# P1-11: Check Sanctified Flames for the last shooter before ending phase
	if active_shooter_id != "":
		var sanctified_changes = _check_sanctified_flames(active_shooter_id)
		changes.append_array(sanctified_changes)
		_targets_hit_by_shooter.clear()
		active_shooter_id = ""
	log_phase_message("Ending Shooting Phase")
	emit_signal("phase_completed")
	return create_result(true, changes)

func _process_shoot(action: Dictionary) -> Dictionary:
	# Full atomic shoot action - used exclusively by AI
	# Handles the complete flow: select shooter, assign targets, resolve hits/wounds,
	# auto-roll saves, apply damage, mark unit done, and clear state.
	# Does NOT emit UI signals (weapon_order_required, next_weapon_confirmation_required,
	# saves_required) to avoid creating orphaned dialogs during AI play.
	var unit_id = action.get("actor_unit_id", "")
	# Issue #329: extract action.payload.rng_seed once for all sub-rolls in this method
	var ps_seed: int = action.get("payload", {}).get("rng_seed", -1)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info(str("║ AI SHOOT (atomic): Starting for unit %s" % unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Step 1: Select shooter (skip Throat Slittas prompt for AI — handle automatically)
	var select_result = _process_select_shooter({"actor_unit_id": unit_id, "payload": {"skip_throat_slittas_check": true}})
	if not select_result.success:
		return select_result

	# P1-12: AI auto-resolve Throat Slittas if applicable
	# The AI always uses Throat Slittas when enemies are within 9"
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr and ability_mgr.has_throat_slittas_ability(unit_id):
		var ts_targets = _get_throat_slittas_targets(unit_id)
		if not ts_targets.is_empty():
			DebugLogger.info(str("║ AI SHOOT: P1-12 Throat Slittas — auto-activating for %s" % unit_id))
			var ts_result = _resolve_throat_slittas(unit_id)
			var ts_changes = ts_result.get("diffs", [])
			ts_changes.append({
				"op": "set",
				"path": "units.%s.flags.has_shot" % unit_id,
				"value": true
			})
			units_that_shot.append(unit_id)
			active_shooter_id = ""
			confirmed_assignments.clear()
			resolution_state.clear()
			pending_save_data.clear()

			var ai_unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
			return create_result(true, ts_changes, "Throat Slittas resolved", {
				"throat_slittas": true,
				"mortal_wounds": ts_result.get("total_mortal_wounds", 0),
				"casualties": ts_result.get("total_casualties", 0)
			})

	# OA-10: AI auto-use Ammo Runt if available
	var ability_mgr_ai = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr_ai and ability_mgr_ai.has_ammo_runt(unit_id):
		var ar_remaining = ability_mgr_ai.get_ammo_runts_remaining(unit_id)
		DebugLogger.info(str("║ AI SHOOT: OA-10 Ammo Runt — auto-activating for %s (%d remaining)" % [unit_id, ar_remaining]))
		var runt_idx = ability_mgr_ai.mark_ammo_runt_used(unit_id)

		# Apply Lethal Hits flag
		var ar_diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_lethal_hits" % unit_id,
			"value": true
		}]
		PhaseManager.apply_state_changes(ar_diffs)
		game_state_snapshot = GameState.create_snapshot()

		var ai_unit_name_ar = get_unit(unit_id).get("meta", {}).get("name", unit_id)
		log_phase_message("AI: Ammo Runt activated for %s — Lethal Hits granted (runt #%d)" % [ai_unit_name_ar, runt_idx + 1])

	# OA-31: AI auto-use Pulsa Rokkit if available
	var ability_mgr_pr_ai = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr_pr_ai and ability_mgr_pr_ai.has_pulsa_rokkit(unit_id):
		DebugLogger.info(str("║ AI SHOOT: OA-31 Pulsa Rokkit — auto-activating for %s" % unit_id))
		ability_mgr_pr_ai.mark_pulsa_rokkit_used(unit_id)

		# Apply Pulsa Rokkit flag (+1S/+1AP to ranged weapons for the phase)
		var pr_diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_pulsa_rokkit_active" % unit_id,
			"value": true
		}]
		PhaseManager.apply_state_changes(pr_diffs)
		game_state_snapshot = GameState.create_snapshot()

		var ai_unit_name_pr = get_unit(unit_id).get("meta", {}).get("name", unit_id)
		log_phase_message("AI: Pulsa Rokkit activated for %s — +1S/+1AP to ranged weapons" % ai_unit_name_pr)

	# OA-37: AI auto-use Shooty Power Trip if available
	var ability_mgr_spt_ai = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr_spt_ai and ability_mgr_spt_ai.has_shooty_power_trip(unit_id):
		var ai_d6_roll = _rng.rng.randi_range(1, 6)
		var ai_spt_unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
		DebugLogger.info(str("║ AI SHOOT: OA-37 Shooty Power Trip — auto-rolling for %s (D6 = %d)" % [unit_id, ai_d6_roll]))

		if ai_d6_roll <= 2:
			# 1-2: D3 mortal wounds to self
			var ai_d3_roll = _rng.rng.randi_range(1, 6)
			var ai_mortal_wounds = ((ai_d3_roll - 1) / 2) + 1
			DebugLogger.info(str("║ AI SHOOT: OA-37 Shooty Power Trip — D3 mortal wounds to self (D3 = %d, MW = %d)" % [ai_d3_roll, ai_mortal_wounds]))

			var ai_rng_service = RulesEngine.RNGService.new(ps_seed)  # Issue #329: forward seed
			var ai_mw_result = RulesEngine.apply_mortal_wounds(unit_id, ai_mortal_wounds, game_state_snapshot, ai_rng_service)
			var ai_mw_diffs = ai_mw_result.get("diffs", [])
			if not ai_mw_diffs.is_empty():
				PhaseManager.apply_state_changes(ai_mw_diffs)
				game_state_snapshot = GameState.create_snapshot()

			var ai_casualties = ai_mw_result.get("casualties", 0)
			log_phase_message("AI: Shooty Power Trip — %s rolled %d, suffers %d mortal wounds (%d casualties)" % [ai_spt_unit_name, ai_d6_roll, ai_mortal_wounds, ai_casualties])

			# Check if unit was destroyed
			var ai_unit_after = get_unit(unit_id)
			if ai_unit_after.is_empty() or RulesEngine.count_alive_models(ai_unit_after) <= 0:
				DebugLogger.info(str("║ AI SHOOT: OA-37 Unit %s destroyed by Shooty Power Trip self-damage!" % unit_id))
				log_phase_message("AI: Shooty Power Trip — %s destroyed by self-inflicted mortal wounds!" % ai_spt_unit_name)
				return create_result(true, ai_mw_diffs, "AI: Shooty Power Trip — unit destroyed", {
					"shooty_power_trip_used": true,
					"d6_roll": ai_d6_roll,
					"effect": "self_damage",
					"unit_destroyed": true
				})

		elif ai_d6_roll <= 4:
			# 3-4: +1 Strength to ranged weapons
			var spt_s_diffs = [{
				"op": "set",
				"path": "units.%s.flags.effect_shooty_power_trip_strength" % unit_id,
				"value": true
			}]
			PhaseManager.apply_state_changes(spt_s_diffs)
			game_state_snapshot = GameState.create_snapshot()
			log_phase_message("AI: Shooty Power Trip — %s rolled %d, ranged weapons gain +1 Strength" % [ai_spt_unit_name, ai_d6_roll])
		else:
			# 5-6: +1 Attacks to ranged weapons
			var spt_a_diffs = [{
				"op": "set",
				"path": "units.%s.flags.effect_shooty_power_trip_attacks" % unit_id,
				"value": true
			}]
			PhaseManager.apply_state_changes(spt_a_diffs)
			game_state_snapshot = GameState.create_snapshot()
			log_phase_message("AI: Shooty Power Trip — %s rolled %d, ranged weapons gain +1 Attacks" % [ai_spt_unit_name, ai_d6_roll])

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
	# Issue #329: forward action.payload.rng_seed to RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": confirmed_assignments,
			"rng_seed": ps_seed
		}
	}

	var rng_service = RulesEngine.RNGService.new(ps_seed)
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

		DebugLogger.info(str("║ AI SHOOT: Saves resolved - %d casualties" % total_casualties))
	else:
		DebugLogger.info("║ AI SHOOT: No wounds caused (all missed)")

	# HAZARDOUS (T2-3): Process Hazardous self-damage after saves resolve (AI path)
	var hazardous_weapons = result.get("hazardous_weapons", [])
	if not hazardous_weapons.is_empty():
		DebugLogger.info(str("║ AI SHOOT: Processing %d hazardous weapon check(s)" % hazardous_weapons.size()))
		var haz_rng = RulesEngine.RNGService.new(ps_seed)  # Issue #329: forward seed
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
		DebugLogger.info(str("║ AI SHOOT: ONE SHOT — included %d one-shot diffs" % ai_one_shot_diffs.size()))

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

	# T7-38: Emit AI shooting visual signals BEFORE clearing state
	# Collect unique targets with weapon names for targeting line visualization
	var ai_target_data = []
	var seen_targets = {}
	for a in confirmed_assignments:
		var tid = a.get("target_unit_id", "")
		if tid.is_empty() or seen_targets.has(tid):
			continue
		seen_targets[tid] = true
		var weapon_names_for_target = []
		for a2 in confirmed_assignments:
			if a2.get("target_unit_id", "") == tid:
				var wid = a2.get("weapon_id", "")
				var wp = RulesEngine.get_weapon_profile(wid)
				var wn = wp.get("name", wid)
				if wn not in weapon_names_for_target:
					weapon_names_for_target.append(wn)
		ai_target_data.append({
			"target_unit_id": tid,
			"weapon_names": weapon_names_for_target
		})

	emit_signal("ai_shooting_visual", unit_id, ai_target_data, {
		"hits": total_hits,
		"wounds": total_wounds,
		"saves_passed": total_saves_passed,
		"saves_failed": total_saves_failed,
		"casualties": total_casualties
	})
	DebugLogger.info(str("║ T7-38: Emitted ai_shooting_visual for %d target(s)" % ai_target_data.size()))

	# T7-38: Emit shooting_damage_applied for floating damage numbers (AI path)
	var damage_diffs = []
	for change in all_changes:
		if change.get("op") == "set":
			var path: String = change.get("path", "")
			if ".models." in path and (path.ends_with(".alive") or path.ends_with(".current_wounds")):
				damage_diffs.append(change)
	if not damage_diffs.is_empty():
		emit_signal("shooting_damage_applied", unit_id, damage_diffs)
		DebugLogger.info(str("║ T7-38: Emitted shooting_damage_applied with %d diffs" % damage_diffs.size()))

	# P1-11: Track hits for Sanctified Flames (AI atomic path)
	# Build _targets_hit_by_shooter from the dice + assignment data
	_targets_hit_by_shooter.clear()
	if total_hits > 0:
		# Assign hits to target units from assignments
		for a in confirmed_assignments:
			var ai_tid = a.get("target_unit_id", "")
			if ai_tid != "":
				# Use total_hits as a proxy — hits are distributed across targets
				# For accuracy, we just need to know which units were hit at all
				_targets_hit_by_shooter[ai_tid] = _targets_hit_by_shooter.get(ai_tid, 0) + 1

	# P1-11: Check for Sanctified Flames and apply Battle-shock if triggered
	var sanctified_diffs = _check_sanctified_flames(unit_id)
	all_changes.append_array(sanctified_diffs)

	# Step 6: Mark unit as done
	all_changes.append({
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	})
	units_that_shot.append(unit_id)

	# T5-UX9: Record per-target shot summary for end-of-phase panel.
	# AI atomic path doesn't populate completed_weapons, so build entries from
	# confirmed_assignments + save_data_list + per-target casualties from all_changes.
	var ai_actor_name = game_state_snapshot.get("units", {}).get(unit_id, {}).get("meta", {}).get("name", unit_id)
	var per_target_casualties: Dictionary = {}
	for ch in all_changes:
		var cpath = ch.get("path", "")
		if cpath.ends_with(".alive") and ch.get("value") == false:
			var cparts = cpath.split(".")
			if cparts.size() >= 2 and cparts[0] == "units":
				var dead_uid = cparts[1]
				per_target_casualties[dead_uid] = per_target_casualties.get(dead_uid, 0) + 1
	# Sum hits/wounds/saves_failed per target by scanning save_data_list and all_dice
	# (save_data_list groups data per weapon → target)
	var per_target_aggregate: Dictionary = {}
	for sd in save_data_list:
		var sd_tid = sd.get("target_unit_id", "")
		if sd_tid == "":
			continue
		if not per_target_aggregate.has(sd_tid):
			per_target_aggregate[sd_tid] = {
				"target_unit_name": sd.get("target_unit_name", sd_tid),
				"weapons": [],
				"wounds": 0,
				"saves_failed": 0
			}
		per_target_aggregate[sd_tid].weapons.append(sd.get("weapon_id", ""))
		per_target_aggregate[sd_tid].wounds += int(sd.get("wounds_to_save", 0))
	# Pull saves_failed from save dice blocks per target
	for db in all_dice:
		if db.get("context", "") == "save_roll":
			var db_tname = db.get("target_unit_name", "")
			for tid_key in per_target_aggregate:
				if per_target_aggregate[tid_key].target_unit_name == db_tname:
					per_target_aggregate[tid_key].saves_failed += int(db.get("failed", 0))
					break
	# Also include targets that got assigned but had 0 wounds caused
	for a in confirmed_assignments:
		var a_tid = a.get("target_unit_id", "")
		if a_tid == "" or per_target_aggregate.has(a_tid):
			continue
		var a_target = game_state_snapshot.get("units", {}).get(a_tid, {})
		var a_target_name = a_target.get("meta", {}).get("name", a_tid)
		per_target_aggregate[a_tid] = {
			"target_unit_name": a_target_name,
			"weapons": [a.get("weapon_id", "")],
			"wounds": 0,
			"saves_failed": 0
		}

	# Approximate hits-per-target: split total_hits proportionally by wounds-per-target.
	# When total wounds > 0, share by wound ratio; else share evenly across targets.
	var ai_total_wounds = 0
	for tid_key2 in per_target_aggregate:
		ai_total_wounds += per_target_aggregate[tid_key2].wounds
	for tid_key3 in per_target_aggregate:
		var bucket = per_target_aggregate[tid_key3]
		var hits_share = 0
		if ai_total_wounds > 0:
			hits_share = int(round(float(total_hits) * float(bucket.wounds) / float(ai_total_wounds)))
		elif per_target_aggregate.size() > 0:
			hits_share = int(total_hits / per_target_aggregate.size())
		_append_phase_shooting_entry({
			"shooter_unit_id": unit_id,
			"shooter_unit_name": ai_actor_name,
			"weapon_id": str(bucket.weapons[0]) if not bucket.weapons.is_empty() else "",
			"weapon_name": "",  # AI atomic aggregates across weapons; weapon-level breakdown not available
			"target_unit_id": tid_key3,
			"target_unit_name": bucket.target_unit_name,
			"hits": hits_share,
			"total_attacks": 0,
			"wounds": bucket.wounds,
			"saves_failed": bucket.saves_failed,
			"casualties": int(per_target_casualties.get(tid_key3, 0)),
			"skipped_target_destroyed": false
		})

	# Step 7: Clear state
	var shooter_id = active_shooter_id
	# Return shooter to idle animation
	_trigger_unit_animation(active_shooter_id, "idle")
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()
	_targets_hit_by_shooter.clear()

	# Step 8: Emit shooting_resolved for visual cleanup (non-blocking)
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": total_casualties})

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info(str("║ AI SHOOT (atomic): Complete for %s - %d casualties" % [unit_id, total_casualties]))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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
	# Track which units have been destroyed by previous weapon saves in this batch
	var _destroyed_units_in_batch: Dictionary = {}

	for save_data in save_data_list:
		# Skip saves for targets already destroyed by earlier weapons in this batch
		var target_unit_id = save_data.get("target_unit_id", "")
		if _destroyed_units_in_batch.has(target_unit_id):
			var target_name = save_data.get("target_unit_name", target_unit_id)
			var weapon_name = save_data.get("weapon_name", "Unknown")
			DebugLogger.info(str("ShootingPhase: AI SKIP — %s saves skipped, target %s already destroyed" % [weapon_name, target_name]))
			log_phase_message("Skipped %s — target %s destroyed" % [weapon_name, target_name])
			continue

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
			DebugLogger.info(str("ShootingPhase: PRECISION — %d wounds can target CHARACTER models" % precision_wounds))

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
			if target_unit_id != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id)

		# Check if target unit was fully destroyed by this weapon's damage
		# (compute from diffs since game_state_snapshot hasn't been updated yet)
		if damage_result.casualties > 0 and target_unit_id != "":
			var models_killed_count = 0
			for diff in all_changes:
				var dpath = diff.get("path", "")
				if dpath.begins_with("units.%s.models." % target_unit_id) and dpath.ends_with(".alive") and diff.get("value") == false:
					models_killed_count += 1
			var target_unit_data = game_state_snapshot.get("units", {}).get(target_unit_id, {})
			var alive_in_snapshot = 0
			for m in target_unit_data.get("models", []):
				if m.get("alive", true):
					alive_in_snapshot += 1
			if alive_in_snapshot > 0 and models_killed_count >= alive_in_snapshot:
				_destroyed_units_in_batch[target_unit_id] = true
				DebugLogger.info(str("ShootingPhase: AI — target unit %s fully destroyed, will skip remaining saves" % target_unit_id))

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

		# VERBOSE COMBAT LOG: Emit save and FNP detail for this weapon's saves
		_emit_verbose_combat_log(active_shooter_id, [], all_dice_blocks, damage_result.casualties, "shooting_saves")

	return {"changes": all_changes, "casualties": total_casualties, "dice_blocks": all_dice_blocks}

func _process_resolve_weapon_sequence(action: Dictionary) -> Dictionary:
	"""Process weapon sequence resolution - either fast roll or sequential"""
	DebugLogger.info("========================================")
	DebugLogger.info("ShootingPhase: _process_resolve_weapon_sequence CALLED")
	DebugLogger.info(str("ShootingPhase: action = ", action))

	var payload = action.get("payload", {})
	DebugLogger.info(str("ShootingPhase: payload = ", payload))

	var weapon_order = payload.get("weapon_order", [])
	DebugLogger.info(str("ShootingPhase: weapon_order size = ", weapon_order.size()))

	var fast_roll = payload.get("fast_roll", false)
	DebugLogger.info(str("ShootingPhase: fast_roll = ", fast_roll))

	var is_reorder = payload.get("is_reorder", false)
	DebugLogger.info(str("ShootingPhase: is_reorder = ", is_reorder))

	DebugLogger.info(str("ShootingPhase: active_shooter_id = ", active_shooter_id))
	DebugLogger.info(str("ShootingPhase: confirmed_assignments before = ", confirmed_assignments))

	# If this is a reorder during sequential resolution, update the weapon_order
	if is_reorder and resolution_state.get("mode", "") == "sequential":
		DebugLogger.info("ShootingPhase: Updating weapon order for remaining weapons")
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
		DebugLogger.info("ShootingPhase: Updated weapon_order, continuing to next weapon")

		# Continue with next weapon
		var next_result = _resolve_next_weapon()
		DebugLogger.info(str("ShootingPhase: _resolve_next_weapon returned = ", next_result))
		DebugLogger.info("========================================")
		return next_result

	# Update confirmed assignments with the ordered weapons
	confirmed_assignments = weapon_order.duplicate(true)
	DebugLogger.info(str("ShootingPhase: confirmed_assignments after = ", confirmed_assignments))

	if fast_roll:
		# Fast roll all weapons at once (existing behavior)
		log_phase_message("Fast rolling all weapons")
		resolution_state = {
			"mode": "fast",
			"weapon_order": weapon_order,
			"current_assignment": 0,
			"current_index": 0,
			"completed_weapons": [],
			"awaiting_saves": false,
			"phase": "ready"
		}

		# Call normal resolution
		DebugLogger.info("ShootingPhase: Calling _process_resolve_shooting for fast roll...")
		var resolve_result = _process_resolve_shooting({})
		DebugLogger.info(str("ShootingPhase: Fast roll result = ", resolve_result))
		DebugLogger.info("========================================")
		return resolve_result
	else:
		# Sequential resolution - resolve one weapon at a time
		log_phase_message("Starting sequential weapon resolution")
		DebugLogger.info("ShootingPhase: Starting sequential resolution...")
		resolution_state = {
			"mode": "sequential",
			"weapon_order": weapon_order,
			"current_index": 0,
			"completed_weapons": [],
			"awaiting_saves": false
		}
		DebugLogger.info(str("ShootingPhase: resolution_state = ", resolution_state))

		# Start resolving first weapon
		DebugLogger.info("ShootingPhase: Calling _resolve_next_weapon()...")
		var next_result = _resolve_next_weapon()
		DebugLogger.info(str("ShootingPhase: _resolve_next_weapon returned = ", next_result))
		DebugLogger.info("========================================")
		return next_result

func _resolve_next_weapon() -> Dictionary:
	"""Resolve the next weapon in the sequence"""
	DebugLogger.info("========================================")
	DebugLogger.info("ShootingPhase: _resolve_next_weapon CALLED")
	DebugLogger.info(str("ShootingPhase: resolution_state = ", resolution_state))

	var current_index = resolution_state.get("current_index", 0)
	var weapon_order = resolution_state.get("weapon_order", [])

	DebugLogger.info(str("ShootingPhase: current_index = ", current_index))
	DebugLogger.info(str("ShootingPhase: weapon_order.size() = ", weapon_order.size()))
	DebugLogger.info(str("ShootingPhase: active_shooter_id = ", active_shooter_id))

	if current_index >= weapon_order.size():
		# All weapons complete
		DebugLogger.info("ShootingPhase: All weapons complete!")
		log_phase_message("All weapons resolved sequentially")

		# Mark shooter as done
		var shooter_id = active_shooter_id  # Store before clearing
		units_that_shot.append(active_shooter_id)
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]

		# Return shooter to idle animation
		_trigger_unit_animation(active_shooter_id, "idle")

		# T5-UX9: capture per-weapon shot results before clearing resolution_state
		_record_completed_weapons_to_phase_log(shooter_id)

		# Clear state
		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		# Emit signal to clear visuals
		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "Sequential weapon resolution complete")

	# Skip weapons whose target unit has been fully destroyed
	while current_index < weapon_order.size():
		var next_assignment = weapon_order[current_index]
		var next_target_id = next_assignment.get("target_unit_id", "")
		if next_target_id == "" or not _is_unit_destroyed(next_target_id):
			break
		# Target is destroyed — skip this weapon
		var skipped_weapon_id = next_assignment.get("weapon_id", "")
		var skipped_weapon_profile = RulesEngine.get_weapon_profile(skipped_weapon_id)
		var skipped_weapon_name = skipped_weapon_profile.get("name", skipped_weapon_id)
		var skipped_target_name = get_unit(next_target_id).get("meta", {}).get("name", next_target_id)
		DebugLogger.info(str("ShootingPhase: SKIPPING weapon %d (%s) — target unit %s is destroyed" % [current_index + 1, skipped_weapon_name, skipped_target_name]))
		log_phase_message("Skipped %s — target %s destroyed" % [skipped_weapon_name, skipped_target_name])
		resolution_state.completed_weapons.append({
			"weapon_id": skipped_weapon_id,
			"target_unit_id": next_target_id,
			"target_unit_name": skipped_target_name,
			"wounds": 0,
			"casualties": 0,
			"hits": 0,
			"total_attacks": 0,
			"saves_failed": 0,
			"dice_rolls": [],
			"hit_data": {},
			"wound_data": {},
			"skipped_target_destroyed": true
		})
		current_index += 1
		resolution_state.current_index = current_index

	# Re-check if all weapons are now complete (some may have been skipped)
	if current_index >= weapon_order.size():
		DebugLogger.info("ShootingPhase: All weapons complete (some skipped due to destroyed targets)")
		log_phase_message("All weapons resolved sequentially")

		var shooter_id = active_shooter_id
		units_that_shot.append(active_shooter_id)
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]

		# T5-UX9: capture before clearing
		_record_completed_weapons_to_phase_log(shooter_id)

		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "Sequential weapon resolution complete (remaining targets destroyed)")

	# Get current weapon assignment
	var current_assignment = weapon_order[current_index]
	var weapon_id = current_assignment.get("weapon_id", "")

	DebugLogger.info(str("ShootingPhase: Resolving weapon %d of %d: %s" % [current_index + 1, weapon_order.size(), weapon_id]))

	# VERBOSE COMBAT LOG: Header BEFORE resolution so dice can display in real-time
	var _seq_shooter = game_state_snapshot.get("units", {}).get(active_shooter_id, {})
	var _seq_shooter_name = _seq_shooter.get("meta", {}).get("name", active_shooter_id)
	var _seq_weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
	var _seq_weapon_name = _seq_weapon_profile.get("name", weapon_id)
	var _seq_target = get_unit(current_assignment.target_unit_id)
	var _seq_target_name = _seq_target.get("meta", {}).get("name", current_assignment.target_unit_id)
	GameEventLog.add_combat_header("P%d: %s → %s with %s (weapon %d/%d)" % [
		get_current_player(), _seq_shooter_name, _seq_target_name, _seq_weapon_name,
		current_index + 1, weapon_order.size()])

	# T5-MP5: Build weapon_progress block and emit locally + include in result for remote sync
	var weapon_progress_block = {
		"context": "weapon_progress",
		"message": "Resolving weapon %d of %d" % [current_index + 1, weapon_order.size()],
		"current_index": current_index,
		"total_weapons": weapon_order.size()
	}
	emit_signal("dice_rolled", weapon_progress_block)

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
	DebugLogger.info("ShootingPhase: Calling RulesEngine.resolve_shoot_until_wounds()...")
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)
	DebugLogger.info(str("ShootingPhase: RulesEngine returned: success=%s" % result.success))

	if not result.success:
		DebugLogger.info(str("ShootingPhase: ❌ Weapon resolution FAILED: ", result.get("log_text", "")))
		DebugLogger.info("========================================")
		return create_result(false, [], result.get("log_text", "Weapon resolution failed"))

	# ONE SHOT (T4-2): Collect one-shot diffs from result (weapon marked as fired immediately)
	var seq_one_shot_diffs = result.get("one_shot_diffs", [])
	# Store for inclusion in subsequent results
	pending_one_shot_diffs.append_array(seq_one_shot_diffs)

	# Record dice rolls
	# T5-MP5: Prepend weapon_progress block so remote player sees it in broadcast
	var dice_data = [weapon_progress_block] + result.get("dice", [])
	DebugLogger.info(str("ShootingPhase: Dice blocks returned: %d (including weapon_progress)" % dice_data.size()))
	for dice_block in result.get("dice", []):
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Weapon attacks complete"))
	DebugLogger.info(str("ShootingPhase: Log text: ", result.get("log_text", "")))

	# Emit hit/wound details
	_emit_verbose_combat_log(active_shooter_id, dice_data, [], 0, "sequential_hits")

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
	DebugLogger.info(str("ShootingPhase: save_data_list.size() = %d" % save_data_list.size()))

	if save_data_list.is_empty():
		# No wounds - but still PAUSE for attacker to confirm next weapon (sequential mode)
		DebugLogger.info("ShootingPhase: ⚠ No wounds caused by this weapon")

		# P1-11: Track hits for Sanctified Flames
		var seq_hits = hit_data.get("successes", 0)
		if seq_hits > 0:
			var tid = current_assignment.target_unit_id
			_targets_hit_by_shooter[tid] = _targets_hit_by_shooter.get(tid, 0) + seq_hits
			DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking: %d hit(s) on %s (total: %d)" % [seq_hits, tid, _targets_hit_by_shooter[tid]]))

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
		DebugLogger.info(str("ShootingPhase: Incremented current_index to %d" % resolution_state.current_index))
		DebugLogger.info(str("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index)))

		# ALWAYS PAUSE for attacker to confirm (even if last weapon)
		# Wait for attacker to confirm before continuing or completing
		DebugLogger.info("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon (no hits)")
		DebugLogger.info(str("ShootingPhase: Weapons remaining: ", weapon_order.size() - resolution_state.current_index))

		# Build remaining weapons with validation (may be empty array if this is the last weapon)
		var remaining_weapons = []

		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info("║ BUILDING REMAINING WEAPONS (after miss)")
		DebugLogger.info(str("║ weapon_order.size() = %d" % weapon_order.size()))
		DebugLogger.info(str("║ current_index = %d" % resolution_state.current_index))
		DebugLogger.info(str("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index)))

		for i in range(resolution_state.current_index, weapon_order.size()):
			var weapon = weapon_order[i]
			var miss_target_id = weapon.get("target_unit_id", "")

			# Filter out weapons whose target unit is already destroyed
			if miss_target_id != "" and _is_unit_destroyed(miss_target_id):
				var skipped_wid = weapon.get("weapon_id", "")
				var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
				DebugLogger.info(str("║ Filtered weapon %d: %s (target %s already destroyed)" % [i, skipped_wp.get("name", skipped_wid), miss_target_id]))
				continue

			remaining_weapons.append(weapon)

			# Validate weapon structure
			var remaining_weapon_id = weapon.get("weapon_id", "")
			if remaining_weapon_id == "":
				push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
				DebugLogger.info(str("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i))
				DebugLogger.info(str("║   Full weapon object: %s" % str(weapon)))
			else:
				DebugLogger.info(str("║ Added weapon %d: %s" % [i, remaining_weapon_id]))

		DebugLogger.info(str("║ Total remaining weapons: %d" % remaining_weapons.size()))
		if remaining_weapons.is_empty():
			DebugLogger.info("║ ✓ All remaining weapons skipped or this is the FINAL weapon")
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

		# AUTO-COMPLETE: If all remaining weapons target destroyed units, skip them
		# and complete shooting automatically (no dialog needed)
		var _has_destroyed_targets = false
		for i in range(resolution_state.current_index, weapon_order.size()):
			var check_tid = weapon_order[i].get("target_unit_id", "")
			if check_tid != "" and _is_unit_destroyed(check_tid):
				_has_destroyed_targets = true
				break

		if remaining_weapons.is_empty() and _has_destroyed_targets:
			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ AUTO-COMPLETE: All remaining targets destroyed (miss path)")

			var auto_changes = []
			if not pending_one_shot_diffs.is_empty():
				auto_changes.append_array(pending_one_shot_diffs)
				pending_one_shot_diffs.clear()

			# Record skipped weapons in completed_weapons
			for i in range(resolution_state.current_index, weapon_order.size()):
				var skipped_assignment = weapon_order[i]
				var skipped_wid = skipped_assignment.get("weapon_id", "")
				var skipped_tid = skipped_assignment.get("target_unit_id", "")
				var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
				var skipped_wname = skipped_wp.get("name", skipped_wid)
				var skipped_tname = get_unit(skipped_tid).get("meta", {}).get("name", skipped_tid)
				DebugLogger.info(str("║ Skipped: %s → %s (target destroyed)" % [skipped_wname, skipped_tname]))
				log_phase_message("Skipped %s — target %s destroyed" % [skipped_wname, skipped_tname])
				resolution_state.completed_weapons.append({
					"weapon_id": skipped_wid,
					"target_unit_id": skipped_tid,
					"target_unit_name": skipped_tname,
					"wounds": 0,
					"casualties": 0,
					"hits": 0,
					"total_attacks": 0,
					"saves_failed": 0,
					"dice_rolls": [],
					"hit_data": {},
					"wound_data": {},
					"skipped_target_destroyed": true
				})

			# Mark shooter as done
			var shooter_id = active_shooter_id
			auto_changes.append({
				"op": "set",
				"path": "units.%s.flags.has_shot" % active_shooter_id,
				"value": true
			})
			units_that_shot.append(active_shooter_id)

			# P1-11: Check for Sanctified Flames before clearing state
			var sanctified_changes = _check_sanctified_flames(active_shooter_id)
			auto_changes.append_array(sanctified_changes)

			# T5-UX9: capture before clearing
			_record_completed_weapons_to_phase_log(shooter_id)

			# Clear state
			active_shooter_id = ""
			confirmed_assignments.clear()
			resolution_state.clear()
			pending_save_data.clear()
			_targets_hit_by_shooter.clear()

			# Emit signal to clear visuals
			emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

			DebugLogger.info("║ Shooting auto-completed — all remaining targets destroyed")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			return create_result(true, auto_changes, "Sequential weapon resolution complete (remaining targets destroyed)", {
				"dice": dice_data,
				"log_text": result.get("log_text", "")
			})

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
		DebugLogger.info("ShootingPhase: Returning result with sequential_pause indicator")
		DebugLogger.info("========================================")
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

	# T5-MP4-RELIABILITY: Stamp broadcast id (see _generate_save_broadcast_id)
	var broadcast_id := _generate_save_broadcast_id()
	_stamp_save_broadcast_id(save_data_list, broadcast_id)

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
		"sequence_total": weapon_order.size(),
		"broadcast_id": broadcast_id
	}
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SAVES_REQUIRED EMISSION #2 (from resolve_next_weapon)")
	DebugLogger.info(str("║ Timestamp: ", timestamp))
	DebugLogger.info("║ Source: ShootingPhase._resolve_next_weapon (line 750)")
	DebugLogger.info(str("║ Target: ", save_context.target))
	DebugLogger.info(str("║ Weapon: ", save_context.weapon, " (", save_context.sequence_weapon, "/", save_context.sequence_total, ")"))
	DebugLogger.info(str("║ Wounds: ", save_context.wounds))
	DebugLogger.info(str("║ Broadcast ID: ", broadcast_id))
	DebugLogger.info(str("║ Save data list size: ", save_data_list.size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Emit signal to show save dialog
	DebugLogger.info(str("ShootingPhase: ✅ Emitting saves_required signal with %d save data entries" % save_data_list.size()))
	emit_signal("saves_required", save_data_list)

	log_phase_message("Awaiting defender to make saves for weapon %d of %d..." % [current_index + 1, weapon_order.size()])

	# Return success but don't advance to next weapon yet - wait for saves
	DebugLogger.info("ShootingPhase: Returning result with save_data_list for multiplayer broadcast")
	DebugLogger.info(str("ShootingPhase: Result will include %d dice blocks and %d save data entries" % [dice_data.size(), save_data_list.size()]))
	DebugLogger.info("========================================")
	return create_result(true, [], "Awaiting save resolution", {
		"dice": dice_data,
		"save_data_list": save_data_list,
		"log_text": result.get("log_text", "")
	})

# T5-MP4-RELIABILITY: Save broadcast identity helpers
#
# Each batch of save_data emitted via `saves_required` carries a unique
# `save_broadcast_id` so the defender's controller (and the attacker's retry
# logic) can dedupe re-emissions and match acknowledgments precisely. Without
# the id, the existing dedupe falls back to (target_unit_id + weapon_name),
# which is ambiguous when the same weapon hits the same target across multiple
# rounds or after a retry. The id is `<msec_timestamp>-<monotonic-counter>` so
# it sorts naturally and is unique per broadcast even within the same tick.

static var _save_broadcast_counter: int = 0

static func _generate_save_broadcast_id() -> String:
	_save_broadcast_counter += 1
	return "sbid-%d-%d" % [Time.get_ticks_msec(), _save_broadcast_counter]

static func _stamp_save_broadcast_id(save_data_list: Array, broadcast_id: String) -> void:
	# Mutate each entry in-place so both the locally-emitted signal and the
	# returned result["save_data_list"] carry the same id. Caller passes the
	# id it has already generated so the same value flows into logs.
	for save_data in save_data_list:
		# Don't overwrite an existing id (retry path re-uses the same id).
		if save_data.get("save_broadcast_id", "") == "":
			save_data["save_broadcast_id"] = broadcast_id

# Helper Methods

func _is_unit_destroyed(unit_id: String) -> bool:
	"""Check if a target unit has been fully destroyed (all models dead)."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return true
	var models = unit.get("models", [])
	if models.is_empty():
		return true
	for model in models:
		if model.get("alive", true):
			return false
	return true

func _can_unit_shoot(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})
	var unit_name = unit.get("meta", {}).get("name", unit.get("id", "?"))
	DebugLogger.info(str("ShootingPhase: _can_unit_shoot(%s) — status=%s, destroyed=%s, embarked=%s, has_shot=%s, advanced=%s" % [unit_name, str(status), str(_is_unit_destroyed_check(unit)), str(unit.get("embarked_in", null)), str(flags.get("has_shot", false)), str(flags.get("advanced", false))]))

	# Check if unit is destroyed (all models dead)
	if _is_unit_destroyed_check(unit):
		return false

	# Check if unit is embarked (can't shoot directly, only through transport's firing deck)
	if unit.get("embarked_in", null) != null:
		return false

	# Check if unit is deployed
	if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
		DebugLogger.info(str("ShootingPhase: _can_unit_shoot(%s) — REJECTED: status %s is not DEPLOYED(%d) or MOVED(%d)" % [unit_name, str(status), GameStateData.UnitStatus.DEPLOYED, GameStateData.UnitStatus.MOVED]))
		return false

	# Check if unit has already shot
	if flags.get("has_shot", false):
		return false

	# Issue #383: removed 9e-carryover "battle-shocked cannot shoot" check.
	# 10e Battle-shock effects are: OC=0, Desperate Escape on Fall Back,
	# no stratagem use/target. Cannot-shoot is NOT a battle-shock effect.

	# ASSAULT RULES: Units that Advanced can shoot with Assault weapons ONLY
	# Check this BEFORE cannot_shoot flag since Advanced units CAN shoot (with restrictions)
	# EXCEPTION: Units with advance_and_shoot effect can shoot with ALL weapons after Advancing
	if flags.get("advanced", false):
		if EffectPrimitivesData.has_effect_advance_and_shoot(unit):
			DebugLogger.info(str("ShootingPhase: Unit %s advanced but has advance_and_shoot effect — eligible to shoot with all weapons" % unit.get("id", "unknown")))
		else:
			# Unit advanced - can only shoot if it has Assault weapons
			return _unit_has_assault_weapons(unit)

	# Units that Fell Back cannot shoot (unless special rules)
	if flags.get("fell_back", false):
		if not EffectPrimitivesData.has_effect_fall_back_and_shoot(unit):
			return false
		else:
			DebugLogger.info(str("ShootingPhase: Unit %s fell back but has fall_back_and_shoot effect — eligible to shoot" % unit.get("id", "unknown")))

	# Check other restriction flags (but skip for advanced units handled above)
	# fall_back_and_shoot effect (e.g., MULTIPOTENTIALITY) overrides the cannot_shoot lockout from Fall Back
	if flags.get("cannot_shoot", false):
		if flags.get("fell_back", false) and EffectPrimitivesData.has_effect_fall_back_and_shoot(unit):
			DebugLogger.info(str("ShootingPhase: Unit %s fell back but has fall_back_and_shoot effect — overriding cannot_shoot" % unit.get("id", "unknown")))
		else:
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

func _has_eligible_targets(unit_id: String) -> bool:
	"""P3-96: Check if a unit has at least one eligible shooting target.
	Also returns true if the unit has Throat Slittas targets (alternative to shooting)."""
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	if not eligible_targets.is_empty():
		return true
	# Check for Throat Slittas alternative (mortal wounds within 9")
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr and ability_mgr.has_throat_slittas_ability(unit_id):
		var ts_targets = _get_throat_slittas_targets(unit_id)
		if not ts_targets.is_empty():
			return true
	return false

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
			DebugLogger.info(str("[ShootingPhase] T3-3: Extra Attacks weapon '%s' already assigned, skipping" % weapon_name))
			continue

		if default_target.is_empty():
			DebugLogger.info(str("[ShootingPhase] T3-3: No target available for Extra Attacks weapon '%s'" % weapon_name))
			continue

		confirmed_assignments.append({
			"weapon_id": weapon_id,
			"target_unit_id": default_target,
			"model_ids": []
		})
		DebugLogger.info(str("[ShootingPhase] T3-3: Auto-injected Extra Attacks weapon '%s' → '%s'" % [weapon_name, default_target]))

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
		DebugLogger.info(str("ShootingPhase: No reactive stratagems available for defender (player %d)" % defending_player))
		return {"has_opportunities": false}

	DebugLogger.info(str("ShootingPhase: %d reactive stratagem(s) available for defender (player %d)" % [available.size(), defending_player]))
	for entry in available:
		DebugLogger.info(str("  - %s: eligible units = %s" % [entry.stratagem.name, str(entry.eligible_units)]))

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
	# T5-MP5: Build dice block once, emit locally AND include in result["dice"] so
	# the remote player's dice log gets the same block via NetworkManager broadcast.
	var grenade_dice_block = {
		"context": "grenade",
		"rolls_raw": result.get("dice_rolls", []),
		"successes": result.get("mortal_wounds", 0),
		"threshold": "4+",
		"message": result.get("message", "")
	}
	emit_signal("dice_rolled", grenade_dice_block)

	# Emit shooting resolved to refresh visuals
	emit_signal("shooting_resolved", grenade_unit_id, target_unit_id, {
		"casualties": result.get("casualties", 0),
		"grenade": true
	})

	# Return empty changes since execute_grenade already applied all diffs internally
	# (BasePhase.execute_action would double-apply if we returned diffs here)
	return create_result(true, [], result.get("message", ""), {
		"dice": [grenade_dice_block],
		"grenade_result": {
			"dice_rolls": result.get("dice_rolls", []),
			"mortal_wounds": result.get("mortal_wounds", 0),
			"casualties": result.get("casualties", 0),
			"grenade_unit_id": grenade_unit_id,
			"target_unit_id": target_unit_id,
			"message": result.get("message", "")
		}
	})

# T5-UX9: Persist per-weapon results from the active shooter into the phase-level log.
# Called at the moment a unit's shooting concludes (before resolution_state is cleared).
# Each entry retains shooter identity so the end-of-phase summary can attribute hits.
func _record_completed_weapons_to_phase_log(shooter_id: String) -> void:
	if shooter_id == "":
		return
	var completed = resolution_state.get("completed_weapons", [])
	if completed.is_empty():
		return
	var shooter_unit = get_unit(shooter_id)
	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_id)
	for entry in completed:
		var weapon_id = entry.get("weapon_id", "")
		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		var weapon_name = weapon_profile.get("name", weapon_id)
		phase_shooting_log.append({
			"shooter_unit_id": shooter_id,
			"shooter_unit_name": shooter_name,
			"weapon_id": weapon_id,
			"weapon_name": weapon_name,
			"target_unit_id": entry.get("target_unit_id", ""),
			"target_unit_name": entry.get("target_unit_name", "Unknown"),
			"hits": entry.get("hits", 0),
			"total_attacks": entry.get("total_attacks", 0),
			"wounds": entry.get("wounds", 0),
			"saves_failed": entry.get("saves_failed", 0),
			"casualties": entry.get("casualties", 0),
			"skipped_target_destroyed": entry.get("skipped_target_destroyed", false)
		})
	DebugLogger.info(str("ShootingPhase: T5-UX9 recorded %d weapon entries for %s into phase_shooting_log (total: %d)" % [
		completed.size(), shooter_name, phase_shooting_log.size()]))

# T5-UX9: Append a single ad-hoc entry to the phase log. Used by the AI atomic path
# which doesn't populate resolution_state.completed_weapons.
func _append_phase_shooting_entry(entry: Dictionary) -> void:
	phase_shooting_log.append(entry)

# T5-UX9: Aggregate phase_shooting_log into per-target-unit totals for the end-of-phase summary panel.
# Returns: {
#   "by_target": { target_unit_id: { target_unit_name, hits, total_attacks, wounds, saves_failed, casualties, shooters: [name,...] } },
#   "totals": { hits, total_attacks, wounds, saves_failed, casualties },
#   "shooters_count": int,           # distinct shooter units
#   "targets_count": int,            # distinct target units
#   "weapon_entries": int,           # number of recorded weapon resolutions
#   "raw_entries": Array             # the full phase_shooting_log for debugging / drill-down
# }
func get_phase_shooting_summary() -> Dictionary:
	var by_target: Dictionary = {}
	var totals = {"hits": 0, "total_attacks": 0, "wounds": 0, "saves_failed": 0, "casualties": 0}
	var shooter_set: Dictionary = {}
	for entry in phase_shooting_log:
		var tid = entry.get("target_unit_id", "")
		if tid == "":
			continue
		if not by_target.has(tid):
			by_target[tid] = {
				"target_unit_id": tid,
				"target_unit_name": entry.get("target_unit_name", tid),
				"hits": 0,
				"total_attacks": 0,
				"wounds": 0,
				"saves_failed": 0,
				"casualties": 0,
				"shooters": []
			}
		var bucket = by_target[tid]
		bucket.hits += int(entry.get("hits", 0))
		bucket.total_attacks += int(entry.get("total_attacks", 0))
		bucket.wounds += int(entry.get("wounds", 0))
		bucket.saves_failed += int(entry.get("saves_failed", 0))
		bucket.casualties += int(entry.get("casualties", 0))
		var sname = entry.get("shooter_unit_name", "")
		if sname != "" and sname not in bucket.shooters:
			bucket.shooters.append(sname)

		totals.hits += int(entry.get("hits", 0))
		totals.total_attacks += int(entry.get("total_attacks", 0))
		totals.wounds += int(entry.get("wounds", 0))
		totals.saves_failed += int(entry.get("saves_failed", 0))
		totals.casualties += int(entry.get("casualties", 0))

		var sid = entry.get("shooter_unit_id", "")
		if sid != "":
			shooter_set[sid] = true

	return {
		"by_target": by_target,
		"totals": totals,
		"shooters_count": shooter_set.size(),
		"targets_count": by_target.size(),
		"weapon_entries": phase_shooting_log.size(),
		"raw_entries": phase_shooting_log.duplicate(true)
	}

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
			unit.flags.erase("performed_action")

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
		DebugLogger.info("ShootingPhase: Warning - Main node not found for visual cleanup")
		return

	var shooting_controller = main.get("shooting_controller")
	if shooting_controller and is_instance_valid(shooting_controller):
		DebugLogger.info("ShootingPhase: Clearing shooting visuals via controller")
		# Call controller's cleanup method
		if shooting_controller.has_method("_clear_visuals"):
			shooting_controller._clear_visuals()
		DebugLogger.info("ShootingPhase: Shooting visuals cleared")
	else:
		# Fallback: If controller already freed, clean up BoardRoot directly
		DebugLogger.info("ShootingPhase: Controller not available, cleaning BoardRoot directly")
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
			DebugLogger.info(str("ShootingPhase: Removing ", visual_name, " from BoardRoot"))
			board_root.remove_child(visual_node)
			visual_node.queue_free()

func _clear_death_markers() -> void:
	"""Clear all death markers from the board at phase end"""
	var main = get_node_or_null("/root/Main")
	if not main:
		DebugLogger.info("ShootingPhase: Warning - Main node not found for death marker cleanup")
		return

	var board_view = main.get_node_or_null("BoardRoot/BoardView")
	if not board_view:
		DebugLogger.info("ShootingPhase: Warning - BoardView not found for death marker cleanup")
		return

	# Find WoundAllocationBoardHighlights instance
	var highlighter = board_view.get_node_or_null("WoundHighlights")
	if highlighter and is_instance_valid(highlighter):
		if highlighter.has_method("clear_death_markers"):
			highlighter.clear_death_markers()
			DebugLogger.info("ShootingPhase: Cleared death markers via highlighter")
		else:
			DebugLogger.info("ShootingPhase: Warning - highlighter has no clear_death_markers method")
	else:
		DebugLogger.info("ShootingPhase: No highlighter found to clear death markers")

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
			"actor_unit_id": active_shooter_id,
			"description": "Resolve shooting"
		})

	# SWIFT AS THE EAGLE pending — offer use/decline (defender's choice)
	if awaiting_swift_as_eagle and swift_as_eagle_pending_unit != "":
		var sae_unit = get_unit(swift_as_eagle_pending_unit)
		var sae_name = sae_unit.get("meta", {}).get("name", swift_as_eagle_pending_unit) if not sae_unit.is_empty() else swift_as_eagle_pending_unit
		var sae_player = int(sae_unit.get("owner", 0))
		actions.append({
			"type": "USE_SWIFT_AS_THE_EAGLE",
			"actor_unit_id": swift_as_eagle_pending_unit,
			"player": sae_player,
			"description": "Swift as the Eagle — %s makes a Normal move of up to %d\"" % [sae_name, swift_as_eagle_move_inches]
		})
		actions.append({
			"type": "DECLINE_SWIFT_AS_THE_EAGLE",
			"actor_unit_id": swift_as_eagle_pending_unit,
			"player": sae_player,
			"description": "Decline Swift as the Eagle — %s" % sae_name
		})
		return actions

	# P2-25: Distraction Grot pending — offer use/decline (defender's choice)
	if awaiting_distraction_grot and distraction_grot_pending_unit != "":
		var dg_unit = get_unit(distraction_grot_pending_unit)
		var dg_name = dg_unit.get("meta", {}).get("name", distraction_grot_pending_unit) if not dg_unit.is_empty() else distraction_grot_pending_unit
		var dg_player = int(dg_unit.get("owner", 0))
		actions.append({
			"type": "USE_DISTRACTION_GROT",
			"actor_unit_id": distraction_grot_pending_unit,
			"player": dg_player,
			"description": "Activate Distraction Grot — %s gains 5+ invuln" % dg_name
		})
		actions.append({
			"type": "DECLINE_DISTRACTION_GROT",
			"actor_unit_id": distraction_grot_pending_unit,
			"player": dg_player,
			"description": "Decline Distraction Grot — %s" % dg_name
		})
		return actions  # Block other actions until resolved

	# OA-10: Ammo Runt pending — offer use/decline (active player's choice)
	if awaiting_ammo_runt and ammo_runt_pending_unit != "":
		var ar_unit = get_unit(ammo_runt_pending_unit)
		var ar_name = ar_unit.get("meta", {}).get("name", ammo_runt_pending_unit) if not ar_unit.is_empty() else ammo_runt_pending_unit
		var ar_player = int(ar_unit.get("owner", 0))
		var ability_mgr_ar = get_node_or_null("/root/UnitAbilityManager")
		var ar_remaining = ability_mgr_ar.get_ammo_runts_remaining(ammo_runt_pending_unit) if ability_mgr_ar else 0
		actions.append({
			"type": "USE_AMMO_RUNT",
			"actor_unit_id": ammo_runt_pending_unit,
			"player": ar_player,
			"description": "Use Ammo Runt — %s gains Lethal Hits (%d remaining)" % [ar_name, ar_remaining]
		})
		actions.append({
			"type": "DECLINE_AMMO_RUNT",
			"actor_unit_id": ammo_runt_pending_unit,
			"player": ar_player,
			"description": "Decline Ammo Runt — %s" % ar_name
		})
		# When Ammo Runt is pending, only these actions should be available
		actions.append({
			"type": "END_SHOOTING",
			"description": "End Shooting Phase"
		})
		return actions

	# OA-31: Pulsa Rokkit pending — offer use/decline (active player's choice)
	if awaiting_pulsa_rokkit and pulsa_rokkit_pending_unit != "":
		var pr_unit = get_unit(pulsa_rokkit_pending_unit)
		var pr_name = pr_unit.get("meta", {}).get("name", pulsa_rokkit_pending_unit) if not pr_unit.is_empty() else pulsa_rokkit_pending_unit
		var pr_player = int(pr_unit.get("owner", 0))
		actions.append({
			"type": "USE_PULSA_ROKKIT",
			"actor_unit_id": pulsa_rokkit_pending_unit,
			"player": pr_player,
			"description": "Use Pulsa Rokkit — %s gains +1S/+1AP on ranged weapons" % pr_name
		})
		actions.append({
			"type": "DECLINE_PULSA_ROKKIT",
			"actor_unit_id": pulsa_rokkit_pending_unit,
			"player": pr_player,
			"description": "Decline Pulsa Rokkit — %s" % pr_name
		})
		# When Pulsa Rokkit is pending, only these actions should be available
		actions.append({
			"type": "END_SHOOTING",
			"description": "End Shooting Phase"
		})
		return actions

	# OA-37: Shooty Power Trip pending — offer use/decline (active player's choice)
	if awaiting_shooty_power_trip and shooty_power_trip_pending_unit != "":
		var spt_unit = get_unit(shooty_power_trip_pending_unit)
		var spt_name = spt_unit.get("meta", {}).get("name", shooty_power_trip_pending_unit) if not spt_unit.is_empty() else shooty_power_trip_pending_unit
		var spt_player = int(spt_unit.get("owner", 0))
		actions.append({
			"type": "USE_SHOOTY_POWER_TRIP",
			"actor_unit_id": shooty_power_trip_pending_unit,
			"player": spt_player,
			"description": "Use Shooty Power Trip — %s rolls D6 (risk: 1-2 = D3 MW to self)" % spt_name
		})
		actions.append({
			"type": "DECLINE_SHOOTY_POWER_TRIP",
			"actor_unit_id": shooty_power_trip_pending_unit,
			"player": spt_player,
			"description": "Decline Shooty Power Trip — %s" % spt_name
		})
		# When Shooty Power Trip is pending, only these actions should be available
		actions.append({
			"type": "END_SHOOTING",
			"description": "End Shooting Phase"
		})
		return actions

	# P1-12: Throat Slittas pending — offer use/decline
	if throat_slittas_pending_unit != "":
		var ts_unit = get_unit(throat_slittas_pending_unit)
		var ts_name = ts_unit.get("meta", {}).get("name", throat_slittas_pending_unit) if not ts_unit.is_empty() else throat_slittas_pending_unit
		actions.append({
			"type": "USE_THROAT_SLITTAS",
			"actor_unit_id": throat_slittas_pending_unit,
			"description": "Activate Throat Slittas — %s deals mortal wounds" % ts_name
		})
		actions.append({
			"type": "DECLINE_THROAT_SLITTAS",
			"actor_unit_id": throat_slittas_pending_unit,
			"description": "Decline Throat Slittas — %s shoots normally" % ts_name
		})
		# When Throat Slittas is pending, only these actions should be available
		actions.append({
			"type": "END_SHOOTING",
			"description": "End Shooting Phase"
		})
		return actions

	# P1-10: Sentinel Storm pending — offer use/decline
	if sentinel_storm_pending_unit != "":
		var ss_unit = get_unit(sentinel_storm_pending_unit)
		var ss_name = ss_unit.get("meta", {}).get("name", sentinel_storm_pending_unit) if not ss_unit.is_empty() else sentinel_storm_pending_unit
		actions.append({
			"type": "USE_SENTINEL_STORM",
			"actor_unit_id": sentinel_storm_pending_unit,
			"description": "Activate Sentinel Storm — %s shoots again" % ss_name
		})
		actions.append({
			"type": "DECLINE_SENTINEL_STORM",
			"actor_unit_id": sentinel_storm_pending_unit,
			"description": "Decline Sentinel Storm for %s" % ss_name
		})
		# When Sentinel Storm is pending, only these actions should be available
		actions.append({
			"type": "END_SHOOTING",
			"description": "End Shooting Phase"
		})
		return actions

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
			# P3-96: "Unless at least one model in a unit has an eligible target,
			# that unit cannot be selected to shoot." (SHOOT-7)
			# Only gate SELECT_SHOOTER/SKIP_UNIT — secondary actions (mission actions,
			# burn, ritual, terraform) are still available without eligible targets.
			var has_targets = _has_eligible_targets(unit_id)

			if has_targets:
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

			# Check if unit qualifies for a secondary action
			var action_options = _get_secondary_action_options(unit_id)
			for opt in action_options:
				actions.append({
					"type": "PERFORM_SECONDARY_ACTION",
					"actor_unit_id": unit_id,
					"payload": {
						"action_name": opt.action_name,
						"location": opt.location,
						"mission_id": opt.mission_id,
						"vp_value": opt.get("vp_value", 0),
					},
					"description": "%s: %s" % [unit.get("meta", {}).get("name", unit_id), opt.description]
				})

			# Check if unit can burn an objective (Scorched Earth mission)
			var burn_options = _get_burn_objective_options(unit_id)
			for burn_opt in burn_options:
				actions.append({
					"type": "BURN_OBJECTIVE",
					"actor_unit_id": unit_id,
					"objective_id": burn_opt.objective_id,
					"burn_vp": burn_opt.burn_vp,
					"description": "%s: Burn %s (+%d VP end-of-game)" % [
						unit.get("meta", {}).get("name", unit_id),
						burn_opt.objective_id,
						burn_opt.burn_vp]
				})

			# Check if unit can perform a ritual action (The Ritual mission)
			var ritual_options = _get_ritual_action_options(unit_id)
			for ritual_opt in ritual_options:
				actions.append({
					"type": "PERFORM_RITUAL_ACTION",
					"actor_unit_id": unit_id,
					"objective_id": ritual_opt.objective_id,
					"description": "%s: Perform Ritual at %s (create new objective)" % [
						unit.get("meta", {}).get("name", unit_id),
						ritual_opt.objective_id]
				})

			# Check if unit can perform a terraform action (Terraform mission)
			var terraform_options = _get_terraform_action_options(unit_id)
			for tf_opt in terraform_options:
				var tf_desc = "Terraform %s" % tf_opt.objective_id
				if tf_opt.get("is_flip", false):
					tf_desc = "Flip %s (opponent's terraform)" % tf_opt.objective_id
				actions.append({
					"type": "PERFORM_TERRAFORM_ACTION",
					"actor_unit_id": unit_id,
					"objective_id": tf_opt.objective_id,
					"is_flip": tf_opt.get("is_flip", false),
					"description": "%s: %s" % [
						unit.get("meta", {}).get("name", unit_id),
						tf_desc]
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
			DebugLogger.info(str("WARNING: Invalid active shooter after load: ", active_shooter_id))
			active_shooter_id = ""
			return false
		
		if not _can_unit_shoot(shooter):
			DebugLogger.info(str("WARNING: Active shooter cannot shoot after load: ", active_shooter_id))
			active_shooter_id = ""
			return false
	
	# Validate assignments reference valid units and weapons
	for assignment in pending_assignments:
		var target = get_unit(assignment.target_unit_id)
		if target.is_empty():
			DebugLogger.info(str("WARNING: Invalid target in assignments: ", assignment.target_unit_id))
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
	"""Mark shooter as done and clear state. Checks for Sentinel Storm shoot-again ability first."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SHOOTING PHASE: COMPLETE_SHOOTING_FOR_UNIT")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ This is triggered when user views final weapon results")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# P1-10: Check for Sentinel Storm shoot-again ability before completing
	# Skip this check if the unit is already in its shoot-again round (already used Sentinel Storm)
	# P1-59: Also skip if out-of-phase action is active (e.g. Fire Overwatch) — cannot use
	# phase-specific abilities during out-of-phase actions per core rules
	var strat_mgr_for_oop = get_node_or_null("/root/StratagemManager")
	var is_out_of_phase = strat_mgr_for_oop and strat_mgr_for_oop.is_out_of_phase_active()
	if not action.get("payload", {}).get("skip_sentinel_storm_check", false) and not is_out_of_phase:
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_shoot_again_ability(unit_id):
			DebugLogger.info(str("║ SENTINEL STORM: Unit %s has unused Sentinel Storm — prompting player" % unit_id))
			sentinel_storm_pending_unit = unit_id

			# Clear resolution state but keep active_shooter_id for the decision
			confirmed_assignments.clear()
			resolution_state.clear()
			pending_save_data.clear()

			# Emit signal for UI to show prompt
			var current_player = get_current_player()
			emit_signal("sentinel_storm_available", unit_id, current_player)

			log_phase_message("Sentinel Storm available for unit %s — awaiting player decision" % unit_id)

			return create_result(true, [], "Sentinel Storm available", {
				"sentinel_storm_available": true,
				"unit_id": unit_id
			})
	elif is_out_of_phase:
		DebugLogger.info(str("║ SENTINEL STORM: Blocked for %s — out-of-phase action active (P1-59)" % unit_id))

	# P1-11: Check for Sanctified Flames — force Battle-shock test on hit enemy
	# P1-59: Also skip if out-of-phase action is active
	var sanctified_changes = _check_sanctified_flames(unit_id) if not is_out_of_phase else []
	if is_out_of_phase:
		DebugLogger.info("ShootingPhase: Sanctified Flames check skipped — out-of-phase action active (P1-59)")

	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]
	changes.append_array(sanctified_changes)

	# Issue #386 Big Booms: apply D3 MW per struck unit after supa-kannon attacks finish.
	if not _big_booms_pending.is_empty():
		var bb_board = GameState.create_snapshot()
		var bb_rng = RulesEngine.RNGService.new()
		for entry in _big_booms_pending:
			for struck_uid in entry.get("struck_unit_ids", []):
				var d3 = bb_rng.randi_range(1, 3)
				var bb_result = RulesEngine.apply_mortal_wounds(struck_uid, d3, bb_board, bb_rng)
				changes.append_array(bb_result.get("diffs", []))
				log_phase_message("Big Booms: %s suffers %d mortal wound(s)" % [struck_uid, d3])
		_big_booms_pending.clear()

	units_that_shot.append(unit_id)

	# Capture target IDs before clearing for post-shooting checks (Swift as the Eagle)
	var targeted_unit_ids_for_post: Array = []
	for ca in confirmed_assignments:
		var tid = ca.get("target_unit_id", "")
		if tid != "" and tid not in targeted_unit_ids_for_post:
			targeted_unit_ids_for_post.append(tid)

	# Clear state
	var shooter_id = active_shooter_id  # Store before clearing

	# T5-UX9: capture per-weapon shot results before clearing resolution_state
	_record_completed_weapons_to_phase_log(shooter_id)

	# Also capture targets from phase log for multi-weapon shots
	for entry in phase_shooting_log:
		if entry.get("shooter_unit_id", "") == shooter_id:
			var tid = entry.get("target_unit_id", "")
			if tid != "" and tid not in targeted_unit_ids_for_post:
				targeted_unit_ids_for_post.append(tid)

	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()
	sentinel_storm_pending_unit = ""
	_targets_hit_by_shooter.clear()

	log_phase_message("Shooting complete for unit %s" % unit_id)

	# Emit signal to clear visuals
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

	# SWIFT AS THE EAGLE: After enemy finishes shooting, check if a targeted
	# Custodes non-VEHICLE unit can make a reactive D6" Normal move.
	# Only on opponent's turn (active player is the shooter, defending Custodes player reacts).
	var swift_check = _check_swift_as_the_eagle(shooter_id, targeted_unit_ids_for_post)
	if swift_check.available:
		PhaseManager.apply_state_changes(changes)
		awaiting_swift_as_eagle = true
		swift_as_eagle_pending_unit = swift_check.unit_id
		swift_as_eagle_move_inches = swift_check.move_inches
		log_phase_message("SWIFT AS THE EAGLE available for %s — D6\" Normal move (rolled %d\")" % [swift_check.unit_name, swift_check.move_inches])
		return create_result(true, changes, "Swift as the Eagle available", {
			"swift_as_eagle_available": true,
			"unit_id": swift_check.unit_id,
			"move_inches": swift_check.move_inches,
			"unit_name": swift_check.unit_name
		})

	return create_result(true, changes, "Shooting complete")

# ============================================================================
# P1-10: SENTINEL STORM — SHOOT AGAIN MECHANIC
# ============================================================================

func _validate_use_sentinel_storm(action: Dictionary) -> Dictionary:
	"""Validate activating Sentinel Storm shoot-again ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if sentinel_storm_pending_unit == "" or sentinel_storm_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Sentinel Storm pending for this unit"]}
	return {"valid": true, "errors": []}

func _validate_decline_sentinel_storm(action: Dictionary) -> Dictionary:
	"""Validate declining Sentinel Storm shoot-again ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if sentinel_storm_pending_unit == "" or sentinel_storm_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Sentinel Storm pending for this unit"]}
	return {"valid": true, "errors": []}

func _process_use_sentinel_storm(action: Dictionary) -> Dictionary:
	"""Player activates Sentinel Storm — unit shoots again.
	Mark the ability as used, then reset the unit's shooting state so it can shoot again."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SENTINEL STORM: ACTIVATED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ Unit will shoot again this phase")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Mark Sentinel Storm as used (once per battle)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.mark_once_per_battle_used(unit_id, "Sentinel Storm")

	# Clear the pending state
	sentinel_storm_pending_unit = ""

	# Reset the unit's shooting state so it can be selected again
	# The unit is NOT added to units_that_shot, and has_shot flag stays false
	# active_shooter_id was already set to this unit
	active_shooter_id = ""
	pending_assignments.clear()
	confirmed_assignments.clear()
	resolution_state.clear()

	log_phase_message("Sentinel Storm activated! %s will shoot again" % unit_id)

	return create_result(true, [], "Sentinel Storm activated — unit shoots again")

func _process_decline_sentinel_storm(action: Dictionary) -> Dictionary:
	"""Player declines Sentinel Storm — complete shooting normally."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SENTINEL STORM: DECLINED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ Completing shooting normally")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	sentinel_storm_pending_unit = ""

	# P1-11: Check for Sanctified Flames — force Battle-shock test on hit enemy
	var sanctified_changes = _check_sanctified_flames(unit_id)

	# Now complete shooting normally — set has_shot flag and add to units_that_shot
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]
	changes.append_array(sanctified_changes)

	units_that_shot.append(unit_id)

	# Clear state
	var shooter_id = active_shooter_id  # Store before clearing
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()
	_targets_hit_by_shooter.clear()

	log_phase_message("Sentinel Storm declined — shooting complete for unit %s" % unit_id)

	# Emit signal to clear visuals
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

	return create_result(true, changes, "Shooting complete (Sentinel Storm declined)")

# ============================================================================
# P1-11: SANCTIFIED FLAMES — FORCED BATTLE-SHOCK TEST AFTER SHOOTING
# ============================================================================

func _check_sanctified_flames(shooter_unit_id: String) -> Array:
	"""Check if the shooter has Sanctified Flames and trigger a Battle-shock test
	on one enemy unit that was hit. Returns state-change diffs (empty if not applicable).

	Sanctified Flames (Witchseekers): "In your Shooting phase, after this unit has shot,
	select one enemy unit hit by one or more of those attacks. That enemy unit must take
	a Battle-shock test."
	"""
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr or not ability_mgr.has_sanctified_flames_ability(shooter_unit_id):
		return []

	# Get the list of enemy units that were hit
	var hit_targets = _targets_hit_by_shooter.duplicate()
	if hit_targets.is_empty():
		DebugLogger.info("ShootingPhase: P1-11 Sanctified Flames: No enemy units were hit — no Battle-shock test triggered")
		return []

	# Filter out already-destroyed units
	var valid_targets: Array = []
	for target_id in hit_targets:
		var target_unit = get_unit(target_id)
		if target_unit.is_empty():
			continue
		var has_alive = false
		for model in target_unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if has_alive:
			valid_targets.append(target_id)

	if valid_targets.is_empty():
		DebugLogger.info("ShootingPhase: P1-11 Sanctified Flames: All hit targets destroyed — no Battle-shock test triggered")
		return []

	# Select target: if only one valid target, auto-select. Otherwise select the one
	# most likely to fail (lowest Leadership) for AI benefit, or first one for player.
	var selected_target_id = valid_targets[0]
	if valid_targets.size() > 1:
		# Select the target with the lowest Leadership (most likely to fail)
		var lowest_ld = 99
		for tid in valid_targets:
			var t_unit = get_unit(tid)
			var t_ld = t_unit.get("meta", {}).get("stats", {}).get("leadership", 7)
			if t_ld < lowest_ld:
				lowest_ld = t_ld
				selected_target_id = tid
		DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames: Multiple targets hit, selecting %s (Ld %d)" % [selected_target_id, lowest_ld]))

	# Perform the Battle-shock test on the selected target
	return _resolve_sanctified_flames_battle_shock(shooter_unit_id, selected_target_id)

func _resolve_sanctified_flames_battle_shock(shooter_unit_id: String, target_unit_id: String) -> Array:
	"""Roll a forced Battle-shock test for Sanctified Flames.
	Returns state-change diffs to set battle_shocked flag if failed."""
	var target_unit = get_unit(target_unit_id)
	if target_unit.is_empty():
		return []

	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	var leadership = target_unit.get("meta", {}).get("stats", {}).get("leadership", 7)
	var shooter_unit = get_unit(shooter_unit_id)
	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_unit_id)

	# Check if already battle-shocked (no need to re-test)
	var already_shocked = target_unit.get("flags", {}).get("battle_shocked", false)
	if already_shocked:
		DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames: %s is already Battle-shocked — skipping test" % target_name))
		log_phase_message("Sanctified Flames: %s already Battle-shocked — no additional test" % target_name)
		return []

	# Roll 2D6 for Battle-shock test
	var die1 = _rng.rng.randi_range(1, 6)
	var die2 = _rng.rng.randi_range(1, 6)
	var roll_total = die1 + die2
	var test_passed = roll_total >= leadership

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P1-11: SANCTIFIED FLAMES — Battle-shock Test")
	DebugLogger.info(str("║ Shooter: %s" % shooter_name))
	DebugLogger.info(str("║ Target: %s (Ld %d)" % [target_name, leadership]))
	DebugLogger.info(str("║ Roll: 2D6 = %d + %d = %d (need %d+)" % [die1, die2, roll_total, leadership]))
	DebugLogger.info(str("║ Result: %s" % ("PASSED" if test_passed else "FAILED — Battle-shocked!")))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	log_phase_message("Sanctified Flames (%s): %s takes Battle-shock test — 2D6 = %d (%d+%d) vs Ld %d — %s" % [
		shooter_name, target_name, roll_total, die1, die2, leadership,
		"PASSED" if test_passed else "FAILED (Battle-shocked!)"
	])

	# Emit signal for UI/log display
	var test_result = {
		"target_unit_id": target_unit_id,
		"target_name": target_name,
		"die1": die1,
		"die2": die2,
		"roll_total": roll_total,
		"leadership": leadership,
		"test_passed": test_passed,
		"battle_shocked": not test_passed
	}
	emit_signal("sanctified_flames_result", shooter_unit_id, target_unit_id, test_result)

	# If test failed, apply battle_shocked flag
	if not test_passed:
		return [{
			"op": "set",
			"path": "units.%s.flags.battle_shocked" % target_unit_id,
			"value": true
		}]

	return []

# ============================================================================
# P1-12: THROAT SLITTAS — MORTAL WOUNDS INSTEAD OF SHOOTING (Kommandos)
# ============================================================================
# "At the start of your Shooting phase, if this unit is within 9" of one or more
# enemy units, it can use this ability. If it does, until the end of the phase,
# this unit is not eligible to shoot, but you roll one D6 for each model in this
# unit that is within 9" of an enemy unit: for each 5+, that enemy unit suffers
# 1 mortal wound."

func _validate_use_throat_slittas(action: Dictionary) -> Dictionary:
	"""Validate activating Throat Slittas mortal wounds ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if throat_slittas_pending_unit == "" or throat_slittas_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Throat Slittas pending for this unit"]}
	return {"valid": true, "errors": []}

func _validate_decline_throat_slittas(action: Dictionary) -> Dictionary:
	"""Validate declining Throat Slittas ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if throat_slittas_pending_unit == "" or throat_slittas_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Throat Slittas pending for this unit"]}
	return {"valid": true, "errors": []}

func _process_use_throat_slittas(action: Dictionary) -> Dictionary:
	"""Player activates Throat Slittas — roll mortal wounds, unit cannot shoot."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P1-12: THROAT SLITTAS — ACTIVATED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ Unit will deal mortal wounds instead of shooting")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear the pending state
	throat_slittas_pending_unit = ""

	# Resolve the ability
	var result = _resolve_throat_slittas(unit_id)

	# Mark unit as done shooting (cannot shoot after using Throat Slittas)
	var changes = result.get("diffs", [])
	changes.append({
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	})
	units_that_shot.append(unit_id)

	# Clear shooter state
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()

	# Emit signal to clear visuals
	emit_signal("shooting_resolved", unit_id, "", {"casualties": result.get("total_casualties", 0)})

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("Throat Slittas: %s dealt %d mortal wound(s) — unit cannot shoot" % [
		unit_name, result.get("total_mortal_wounds", 0)
	])

	return create_result(true, changes, "Throat Slittas resolved")

func _process_decline_throat_slittas(action: Dictionary) -> Dictionary:
	"""Player declines Throat Slittas — proceed with normal shooting."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P1-12: THROAT SLITTAS — DECLINED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ Proceeding with normal shooting")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	throat_slittas_pending_unit = ""

	# Re-process as a normal select_shooter, skipping the Throat Slittas check
	return _process_select_shooter({
		"actor_unit_id": unit_id,
		"payload": {"skip_throat_slittas_check": true}
	})

func _get_throat_slittas_targets(unit_id: String) -> Array:
	"""Find enemy units within 9\" of the unit. Returns array of
	{target_unit_id, target_name, models_in_range} dictionaries."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	var unit_owner = unit.get("owner", 0)
	var unit_models = unit.get("models", [])
	var units = game_state_snapshot.get("units", {})
	var targets: Array = []

	for other_id in units:
		var other = units[other_id]
		# Skip friendly units and destroyed units
		if other.get("owner", 0) == unit_owner:
			continue
		var other_alive = false
		for m in other.get("models", []):
			if m.get("alive", true):
				other_alive = true
				break
		if not other_alive:
			continue

		# Count how many of our models are within 9" of this enemy unit
		var models_in_range = _count_models_within_range(unit_models, other, 9.0)
		if models_in_range > 0:
			targets.append({
				"target_unit_id": other_id,
				"target_name": other.get("meta", {}).get("name", other_id),
				"models_in_range": models_in_range
			})

	return targets

func _count_models_within_range(our_models: Array, enemy_unit: Dictionary, range_inches: float) -> int:
	"""Count how many of our alive models are within range_inches of any alive model
	in the enemy unit (edge-to-edge measurement)."""
	var count = 0
	var enemy_models = enemy_unit.get("models", [])

	for our_model in our_models:
		if not our_model.get("alive", true):
			continue

		var in_range = false
		for enemy_model in enemy_models:
			if not enemy_model.get("alive", true):
				continue

			var distance_inches = Measurement.model_to_model_distance_inches(our_model, enemy_model)
			if distance_inches <= range_inches:
				in_range = true
				break

		if in_range:
			count += 1

	return count

func _resolve_throat_slittas(unit_id: String) -> Dictionary:
	"""Resolve Throat Slittas mortal wounds.
	For each enemy unit within 9\", roll 1D6 per model in range. 5+ = 1 mortal wound.
	Returns {diffs: Array, total_mortal_wounds: int, total_casualties: int, per_target: Array}."""
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var targets = _get_throat_slittas_targets(unit_id)

	var all_diffs: Array = []
	var total_mortal_wounds = 0
	var total_casualties = 0
	var per_target: Array = []

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P1-12: THROAT SLITTAS — Resolution")
	DebugLogger.info(str("║ Unit: %s (%s)" % [unit_name, unit_id]))
	DebugLogger.info(str("║ Targets within 9\": %d" % targets.size()))

	for target_info in targets:
		var target_unit_id = target_info.get("target_unit_id", "")
		var target_name = target_info.get("target_name", target_unit_id)
		var models_in_range = target_info.get("models_in_range", 0)

		# Roll 1D6 per model in range
		var rolls: Array = []
		var mortal_wounds = 0
		for i in range(models_in_range):
			var roll = _rng.rng.randi_range(1, 6)
			rolls.append(roll)
			if roll >= 5:
				mortal_wounds += 1

		DebugLogger.info(str("║ Target: %s — %d models in range, rolls: %s → %d mortal wound(s)" % [
			target_name, models_in_range, str(rolls), mortal_wounds
		]))

		var target_result = {
			"target_unit_id": target_unit_id,
			"target_name": target_name,
			"models_in_range": models_in_range,
			"rolls": rolls,
			"mortal_wounds": mortal_wounds,
			"casualties": 0
		}

		# Apply mortal wounds as damage (1 damage each, with proper model allocation)
		if mortal_wounds > 0:
			var target_unit = get_unit(target_unit_id)
			var target_models = target_unit.get("models", []).duplicate(true)
			var damage_result = RulesEngine._apply_damage_to_unit_pool(
				target_unit_id, mortal_wounds, target_models, game_state_snapshot
			)
			all_diffs.append_array(damage_result.get("diffs", []))
			target_result["casualties"] = damage_result.get("casualties", 0)
			total_casualties += damage_result.get("casualties", 0)

		total_mortal_wounds += mortal_wounds
		per_target.append(target_result)

	DebugLogger.info(str("║ TOTAL: %d mortal wound(s), %d casualt%s" % [
		total_mortal_wounds, total_casualties,
		"y" if total_casualties == 1 else "ies"
	]))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	log_phase_message("Throat Slittas (%s): %d mortal wound(s), %d casualt%s" % [
		unit_name, total_mortal_wounds, total_casualties,
		"y" if total_casualties == 1 else "ies"
	])

	# Emit signal for UI display
	var result = {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"total_mortal_wounds": total_mortal_wounds,
		"total_casualties": total_casualties,
		"per_target": per_target,
		"diffs": all_diffs
	}
	emit_signal("throat_slittas_result", unit_id, result)

	return result

# ============================================================================
# DISTRACTION GROT (P2-25)
# ============================================================================
# "Once per battle, in your opponent's Shooting phase, when this unit is selected
# as the target of a ranged attack, until the end of the phase, models in this
# unit have a 5+ invulnerable save."

func _check_distraction_grot() -> Dictionary:
	"""Check if any targeted unit has an unused Distraction Grot ability.
	Returns { has_opportunity: bool, unit_id: String, player: int }."""
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr:
		return {"has_opportunity": false}

	var active_player = get_current_player()

	# Collect unique target unit IDs from confirmed assignments
	var target_unit_ids = []
	for assignment in confirmed_assignments:
		var target_id = assignment.get("target_unit_id", "")
		if target_id != "" and target_id not in target_unit_ids:
			target_unit_ids.append(target_id)

	for target_id in target_unit_ids:
		var target_unit = get_unit(target_id)
		var target_owner = int(target_unit.get("owner", 0))

		# Only the defending player's units can use Distraction Grot
		if target_owner == active_player:
			continue

		if ability_mgr.has_distraction_grot(target_id):
			DebugLogger.info(str("ShootingPhase: P2-25 Distraction Grot available for %s (%s)" % [
				target_unit.get("meta", {}).get("name", target_id), target_id
			]))
			return {
				"has_opportunity": true,
				"unit_id": target_id,
				"player": target_owner
			}

	return {"has_opportunity": false}

func _validate_use_distraction_grot(action: Dictionary) -> Dictionary:
	"""Validate activating Distraction Grot ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_distraction_grot:
		return {"valid": false, "errors": ["Not awaiting Distraction Grot decision"]}
	if distraction_grot_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Distraction Grot pending for this unit"]}
	return {"valid": true, "errors": []}

func _validate_decline_distraction_grot(action: Dictionary) -> Dictionary:
	"""Validate declining Distraction Grot ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_distraction_grot:
		return {"valid": false, "errors": ["Not awaiting Distraction Grot decision"]}
	return {"valid": true, "errors": []}

func _process_use_distraction_grot(action: Dictionary) -> Dictionary:
	"""Defender activates Distraction Grot — unit gains 5+ invulnerable save for the phase."""
	var unit_id = action.get("actor_unit_id", distraction_grot_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P2-25: DISTRACTION GROT — ACTIVATED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ Unit gains 5+ invulnerable save until end of phase")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_distraction_grot = false
	distraction_grot_pending_unit = ""

	# Mark as used (once per battle)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.mark_once_per_battle_used(unit_id, "Distraction Grot")

	# Apply 5+ invulnerable save flag to the unit
	var diffs = []
	diffs.append({
		"op": "set",
		"path": "units.%s.flags.effect_invuln" % unit_id,
		"value": 5
	})
	diffs.append({
		"op": "set",
		"path": "units.%s.flags.effect_invuln_source" % unit_id,
		"value": "Distraction Grot"
	})
	PhaseManager.apply_state_changes(diffs)

	# Refresh snapshot so RulesEngine sees the invuln
	game_state_snapshot = GameState.create_snapshot()

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("Distraction Grot: %s gains 5+ invulnerable save" % unit_name)

	emit_signal("distraction_grot_result", unit_id, true)

	# Now continue to check reactive stratagems
	var reactive_check = _check_reactive_stratagems()
	if reactive_check.has_opportunities:
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
		return create_result(true, diffs, "Distraction Grot activated, awaiting stratagem decision", {
			"reactive_stratagem_opportunity": true,
			"defending_player": reactive_check.defending_player,
			"available_stratagems": reactive_check.available_stratagems,
			"target_unit_ids": reactive_check.target_unit_ids,
			"distraction_grot_used": true,
			"distraction_grot_unit_id": unit_id
		})

	# No reactive stratagems — continue to resolution
	var resolution_result = _continue_after_reactive_stratagems()
	resolution_result["distraction_grot_used"] = true
	resolution_result["distraction_grot_unit_id"] = unit_id
	return resolution_result

func _process_decline_distraction_grot(action: Dictionary) -> Dictionary:
	"""Defender declines Distraction Grot — proceed with normal shooting."""
	var unit_id = action.get("actor_unit_id", distraction_grot_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P2-25: DISTRACTION GROT — DECLINED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_distraction_grot = false
	distraction_grot_pending_unit = ""

	emit_signal("distraction_grot_result", unit_id, false)

	# Continue to check reactive stratagems
	var reactive_check = _check_reactive_stratagems()
	if reactive_check.has_opportunities:
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

	return _continue_after_reactive_stratagems()

# ============================================================================
# OA-10: AMMO RUNT — Lethal Hits on ranged weapons when selected to shoot
# ============================================================================
# "Once per battle for each ammo runt this unit has, when this unit is selected
# to shoot, it can use this ability. If it does, until the end of the phase,
# ranged weapons equipped by models in this unit have the [LETHAL HITS] ability."

func _validate_use_ammo_runt(action: Dictionary) -> Dictionary:
	"""Validate activating Ammo Runt ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_ammo_runt:
		return {"valid": false, "errors": ["Not awaiting Ammo Runt decision"]}
	if ammo_runt_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Ammo Runt pending for this unit"]}
	return {"valid": true, "errors": []}

func _validate_decline_ammo_runt(action: Dictionary) -> Dictionary:
	"""Validate declining Ammo Runt ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_ammo_runt:
		return {"valid": false, "errors": ["Not awaiting Ammo Runt decision"]}
	return {"valid": true, "errors": []}

func _process_use_ammo_runt(action: Dictionary) -> Dictionary:
	"""Player activates Ammo Runt — unit's ranged weapons gain Lethal Hits for the phase."""
	var unit_id = action.get("actor_unit_id", ammo_runt_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ OA-10: AMMO RUNT — ACTIVATED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_ammo_runt = false
	ammo_runt_pending_unit = ""

	# Mark one ammo runt as used (independently tracked)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	var runt_index = -1
	if ability_mgr:
		runt_index = ability_mgr.mark_ammo_runt_used(unit_id)

	# Apply Lethal Hits flag to the unit for this phase
	var diffs = []
	diffs.append({
		"op": "set",
		"path": "units.%s.flags.effect_lethal_hits" % unit_id,
		"value": true
	})
	PhaseManager.apply_state_changes(diffs)

	# Refresh snapshot
	game_state_snapshot = GameState.create_snapshot()

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var remaining = ability_mgr.get_ammo_runts_remaining(unit_id) if ability_mgr else 0
	log_phase_message("Ammo Runt: %s gains Lethal Hits (runt #%d used, %d remaining)" % [unit_name, runt_index + 1, remaining])

	emit_signal("ammo_runt_result", unit_id, true)

	# Log ability activation to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(get_unit(unit_id).get("owner", 0))
		game_event_log.add_player_entry(owner,
			"Ammo Runt activated: %s gains [LETHAL HITS] on ranged weapons (%d runts remaining)" % [unit_name, remaining])

	# Continue to normal shooting flow (target selection)
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	return create_result(true, diffs, "Ammo Runt activated — Lethal Hits granted", {
		"ammo_runt_used": true,
		"ammo_runt_unit_id": unit_id,
		"ammo_runt_index": runt_index,
		"remaining": remaining
	})

func _process_decline_ammo_runt(action: Dictionary) -> Dictionary:
	"""Player declines Ammo Runt — proceed with normal shooting."""
	var unit_id = action.get("actor_unit_id", ammo_runt_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ OA-10: AMMO RUNT — DECLINED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_ammo_runt = false
	ammo_runt_pending_unit = ""

	emit_signal("ammo_runt_result", unit_id, false)

	# Continue to normal shooting flow (target selection)
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	log_phase_message("Ammo Runt declined for %s — proceeding with normal shooting" % get_unit(unit_id).get("meta", {}).get("name", unit_id))

	return create_result(true, [], "Ammo Runt declined")

# ============================================================================
# OA-31: PULSA ROKKIT — +1 Strength and +1 AP to ranged weapons when selected to shoot
# ============================================================================
# "Once per battle, when the bearer's unit is selected to shoot in your Shooting phase,
# the bearer can use its pulsa rokkit. If it does, until the end of the phase, improve
# the Strength and Armour Penetration characteristics of ranged weapons equipped by
# models in the bearer's unit by 1."

func _validate_use_pulsa_rokkit(action: Dictionary) -> Dictionary:
	"""Validate activating Pulsa Rokkit ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_pulsa_rokkit:
		return {"valid": false, "errors": ["Not awaiting Pulsa Rokkit decision"]}
	if pulsa_rokkit_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Pulsa Rokkit pending for this unit"]}
	return {"valid": true, "errors": []}

func _validate_decline_pulsa_rokkit(action: Dictionary) -> Dictionary:
	"""Validate declining Pulsa Rokkit ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_pulsa_rokkit:
		return {"valid": false, "errors": ["Not awaiting Pulsa Rokkit decision"]}
	return {"valid": true, "errors": []}

func _process_use_pulsa_rokkit(action: Dictionary) -> Dictionary:
	"""Player activates Pulsa Rokkit — unit's ranged weapons gain +1S/+1AP for the phase."""
	var unit_id = action.get("actor_unit_id", pulsa_rokkit_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ OA-31: PULSA ROKKIT — ACTIVATED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_pulsa_rokkit = false
	pulsa_rokkit_pending_unit = ""

	# Mark Pulsa Rokkit as used (once per battle)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.mark_pulsa_rokkit_used(unit_id)

	# Apply Pulsa Rokkit flag to the unit for this phase
	var diffs = []
	diffs.append({
		"op": "set",
		"path": "units.%s.flags.effect_pulsa_rokkit_active" % unit_id,
		"value": true
	})
	PhaseManager.apply_state_changes(diffs)

	# Refresh snapshot
	game_state_snapshot = GameState.create_snapshot()

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("Pulsa Rokkit: %s gains +1 Strength and +1 AP on ranged weapons" % unit_name)

	emit_signal("pulsa_rokkit_result", unit_id, true)

	# Log ability activation to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(get_unit(unit_id).get("owner", 0))
		game_event_log.add_player_entry(owner,
			"Pulsa Rokkit activated: %s gains [+1 STRENGTH] [+1 AP] on ranged weapons" % unit_name)

	# Continue to normal shooting flow (target selection)
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	return create_result(true, diffs, "Pulsa Rokkit activated — +1S/+1AP granted", {
		"pulsa_rokkit_used": true,
		"pulsa_rokkit_unit_id": unit_id
	})

func _process_decline_pulsa_rokkit(action: Dictionary) -> Dictionary:
	"""Player declines Pulsa Rokkit — proceed with normal shooting."""
	var unit_id = action.get("actor_unit_id", pulsa_rokkit_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ OA-31: PULSA ROKKIT — DECLINED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_pulsa_rokkit = false
	pulsa_rokkit_pending_unit = ""

	emit_signal("pulsa_rokkit_result", unit_id, false)

	# Continue to normal shooting flow (target selection)
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	log_phase_message("Pulsa Rokkit declined for %s — proceeding with normal shooting" % get_unit(unit_id).get("meta", {}).get("name", unit_id))

	return create_result(true, [], "Pulsa Rokkit declined")

# ============================================================================
# OA-37: SHOOTY POWER TRIP — Killa Kans D6 roll when selected to shoot
# ============================================================================
# "Each time this unit is selected to shoot, you can roll one D6:
# On a 1-2, this unit suffers D3 mortal wounds.
# On a 3-4, until the end of the phase, add 1 to the Strength characteristic
#   of ranged weapons equipped by models in this unit.
# On a 5-6, until the end of the phase, add 1 to the Attacks characteristic
#   of ranged weapons equipped by models in this unit."

func _validate_use_shooty_power_trip(action: Dictionary) -> Dictionary:
	"""Validate activating Shooty Power Trip ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_shooty_power_trip:
		return {"valid": false, "errors": ["Not awaiting Shooty Power Trip decision"]}
	if shooty_power_trip_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Shooty Power Trip pending for this unit"]}
	return {"valid": true, "errors": []}

func _validate_decline_shooty_power_trip(action: Dictionary) -> Dictionary:
	"""Validate declining Shooty Power Trip ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if not awaiting_shooty_power_trip:
		return {"valid": false, "errors": ["Not awaiting Shooty Power Trip decision"]}
	return {"valid": true, "errors": []}

func _process_use_shooty_power_trip(action: Dictionary) -> Dictionary:
	"""Player activates Shooty Power Trip — roll D6 and apply effect."""
	var unit_id = action.get("actor_unit_id", shooty_power_trip_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ OA-37: SHOOTY POWER TRIP — ACTIVATED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_shooty_power_trip = false
	shooty_power_trip_pending_unit = ""

	# Roll D6 to determine effect
	# Issue #329: honor payload.rng_seed; fall back to persistent _rng
	var spt_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var spt_rng = RulesEngine.RNGService.new(spt_seed) if spt_seed >= 0 else _rng
	var d6_roll = spt_rng.rng.randi_range(1, 6)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var diffs = []
	var effect_name = ""

	DebugLogger.info(str("║ OA-37: Shooty Power Trip D6 roll = %d" % d6_roll))

	if d6_roll <= 2:
		# 1-2: D3 mortal wounds to self
		effect_name = "self_damage"
		var d3_roll = spt_rng.rng.randi_range(1, 6)
		var mortal_wounds = ((d3_roll - 1) / 2) + 1  # 1-2→1, 3-4→2, 5-6→3
		DebugLogger.info(str("║ OA-37: Result 1-2 — D3 mortal wounds to self (D3 roll = %d, MW = %d)" % [d3_roll, mortal_wounds]))

		# Apply mortal wounds to the unit
		var board = game_state_snapshot
		var rng_service = RulesEngine.RNGService.new(spt_seed)
		var mw_result = RulesEngine.apply_mortal_wounds(unit_id, mortal_wounds, board, rng_service)
		diffs.append_array(mw_result.get("diffs", []))

		var casualties = mw_result.get("casualties", 0)
		log_phase_message("Shooty Power Trip: %s rolled %d — suffers %d mortal wounds! (%d casualties)" % [unit_name, d6_roll, mortal_wounds, casualties])

		# Apply diffs to game state
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)
			game_state_snapshot = GameState.create_snapshot()

		# Log to GameEventLog
		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			var owner = int(get_unit(unit_id).get("owner", 0))
			game_event_log.add_player_entry(owner,
				"Shooty Power Trip: %s rolled %d — suffers %d mortal wounds (%d casualties)" % [unit_name, d6_roll, mortal_wounds, casualties])

		emit_signal("shooty_power_trip_result", unit_id, d6_roll, "self_damage")

		# Check if unit was destroyed by self-damage
		var unit_after = get_unit(unit_id)
		if unit_after.is_empty() or RulesEngine.count_alive_models(unit_after) <= 0:
			DebugLogger.info(str("║ OA-37: Unit %s destroyed by Shooty Power Trip self-damage!" % unit_id))
			log_phase_message("Shooty Power Trip: %s destroyed by self-inflicted mortal wounds!" % unit_name)
			return create_result(true, diffs, "Shooty Power Trip — unit destroyed by self-damage", {
				"shooty_power_trip_used": true,
				"d6_roll": d6_roll,
				"effect": "self_damage",
				"mortal_wounds": mortal_wounds,
				"unit_destroyed": true
			})

	elif d6_roll <= 4:
		# 3-4: +1 Strength to ranged weapons
		effect_name = "plus_one_strength"
		DebugLogger.info("║ OA-37: Result 3-4 — +1 Strength to ranged weapons for the phase")

		diffs.append({
			"op": "set",
			"path": "units.%s.flags.effect_shooty_power_trip_strength" % unit_id,
			"value": true
		})
		PhaseManager.apply_state_changes(diffs)
		game_state_snapshot = GameState.create_snapshot()

		log_phase_message("Shooty Power Trip: %s rolled %d — ranged weapons gain +1 Strength" % [unit_name, d6_roll])

		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			var owner = int(get_unit(unit_id).get("owner", 0))
			game_event_log.add_player_entry(owner,
				"Shooty Power Trip: %s rolled %d — ranged weapons gain [+1 STRENGTH]" % [unit_name, d6_roll])

		emit_signal("shooty_power_trip_result", unit_id, d6_roll, "plus_one_strength")

	else:
		# 5-6: +1 Attacks to ranged weapons
		effect_name = "plus_one_attacks"
		DebugLogger.info("║ OA-37: Result 5-6 — +1 Attacks to ranged weapons for the phase")

		diffs.append({
			"op": "set",
			"path": "units.%s.flags.effect_shooty_power_trip_attacks" % unit_id,
			"value": true
		})
		PhaseManager.apply_state_changes(diffs)
		game_state_snapshot = GameState.create_snapshot()

		log_phase_message("Shooty Power Trip: %s rolled %d — ranged weapons gain +1 Attacks" % [unit_name, d6_roll])

		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			var owner = int(get_unit(unit_id).get("owner", 0))
			game_event_log.add_player_entry(owner,
				"Shooty Power Trip: %s rolled %d — ranged weapons gain [+1 ATTACKS]" % [unit_name, d6_roll])

		emit_signal("shooty_power_trip_result", unit_id, d6_roll, "plus_one_attacks")

	# Continue to normal shooting flow (target selection)
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	return create_result(true, diffs, "Shooty Power Trip activated — rolled %d (%s)" % [d6_roll, effect_name], {
		"shooty_power_trip_used": true,
		"d6_roll": d6_roll,
		"effect": effect_name
	})

func _process_decline_shooty_power_trip(action: Dictionary) -> Dictionary:
	"""Player declines Shooty Power Trip — proceed with normal shooting."""
	var unit_id = action.get("actor_unit_id", shooty_power_trip_pending_unit)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ OA-37: SHOOTY POWER TRIP — DECLINED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	awaiting_shooty_power_trip = false
	shooty_power_trip_pending_unit = ""

	emit_signal("shooty_power_trip_result", unit_id, 0, "declined")

	# Continue to normal shooting flow (target selection)
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	log_phase_message("Shooty Power Trip declined for %s — proceeding with normal shooting" % get_unit(unit_id).get("meta", {}).get("name", unit_id))

	return create_result(true, [], "Shooty Power Trip declined")

func _process_apply_saves(action: Dictionary) -> Dictionary:
	"""Process save results and apply damage"""
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ APPLY_SAVES PROCESSING START")
	DebugLogger.info(str("║ Timestamp: ", Time.get_ticks_msec()))
	DebugLogger.info(str("║ resolution_state: ", resolution_state))
	DebugLogger.info(str("║ pending_save_data.size(): ", pending_save_data.size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")
	# Issue #329: extract action.payload.rng_seed once for all sub-rolls in this method
	var pas_seed: int = action.get("payload", {}).get("rng_seed", -1)

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

		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info(str("║ PROCESSING SAVE RESULT %d" % i))
		DebugLogger.info(str("║ save_result_summary keys: ", save_result_summary.keys()))
		DebugLogger.info(str("║ Has save_results: ", save_result_summary.has("save_results")))
		DebugLogger.info(str("║ Has allocation_history: ", save_result_summary.has("allocation_history")))
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

		# Convert allocation_history to save_results format if needed
		var save_results = []
		if save_result_summary.has("save_results"):
			save_results = save_result_summary.save_results
		elif save_result_summary.has("allocation_history"):
			# Convert allocation_history format to save_results format
			DebugLogger.info("║ Converting allocation_history to save_results format")
			for alloc in save_result_summary.allocation_history:
				save_results.append({
					"saved": alloc.get("saved", false),
					"model_id": alloc.get("model_id", ""),
					"model_index": alloc.get("model_index", 0),  # CRITICAL: RulesEngine needs this!
					"roll": alloc.get("roll", 0),
					"damage": alloc.get("damage", 0),
					"model_destroyed": alloc.get("model_destroyed", false)
				})
			DebugLogger.info(str("║ Converted %d allocation entries to save_results" % save_results.size()))

		# DEVASTATING WOUNDS (PRP-012): Get devastating damage from save_result_summary
		var devastating_damage = save_result_summary.get("devastating_damage", 0)
		if devastating_damage > 0:
			DebugLogger.info(str("║ DEVASTATING WOUNDS: %d damage to apply (unsaveable)" % devastating_damage))
			# Update save_data with devastating damage for apply_save_damage
			save_data["devastating_damage"] = devastating_damage

		# Apply damage using RulesEngine (with RNG for Feel No Pain rolls)
		var fnp_rng = RulesEngine.RNGService.new(pas_seed)  # Issue #329: forward seed
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

		# Build verbose save log with dice details
		var verbose_save_parts = ["%s → %s" % [shooter_name, target_name]]
		var weapon_for_log = save_data.get("weapon_name", "")
		if weapon_for_log != "":
			verbose_save_parts[0] += " (%s)" % weapon_for_log
		var save_rolls_for_log = []
		for sr in save_results:
			if sr.has("roll"):
				save_rolls_for_log.append(sr.get("roll", 0))
		var save_threshold_for_log = save_data.get("base_save", 7)
		var ap_for_log = save_data.get("ap", 0)
		var profiles_for_log = save_data.get("model_save_profiles", [])
		var effective_save_for_log = save_threshold_for_log
		var using_invuln_for_log = false
		if not profiles_for_log.is_empty():
			effective_save_for_log = profiles_for_log[0].get("save_needed", 7)
			using_invuln_for_log = profiles_for_log[0].get("using_invuln", false)
		var save_type_str = "Invuln %d+" % effective_save_for_log if using_invuln_for_log else "Save %d+ (AP-%d)" % [effective_save_for_log, ap_for_log]
		if not save_rolls_for_log.is_empty():
			verbose_save_parts.append("%s [%s]: %d passed, %d failed" % [
				save_type_str,
				", ".join(save_rolls_for_log.map(func(r): return str(r))),
				saved_count, failed_count])
		else:
			verbose_save_parts.append("%s: %d passed, %d failed" % [save_type_str, saved_count, failed_count])

		# Include FNP info
		var fnp_prevented_total = damage_result.get("fnp_prevented", 0)
		if fnp_prevented_total > 0:
			verbose_save_parts.append("FNP prevented %d" % fnp_prevented_total)
		# Include devastating wounds info
		if devastating_damage > 0:
			verbose_save_parts.append("%d DEVASTATING damage (no save)" % devastating_damage)

		verbose_save_parts.append("%d slain" % damage_result.casualties)
		save_log_parts.append(" - ".join(verbose_save_parts))

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
			DebugLogger.info(str("ShootingPhase: Emitted save_roll dice block - %d rolls, %d passed, %d failed" % [save_rolls_raw.size(), saved_count, failed_count]))

		# FEEL NO PAIN: Emit FNP dice blocks from RulesEngine batch path
		# T5-MP5: Append to save_dice_blocks so the FNP dice are included in the
		# APPLY_SAVES result["dice"] payload and re-emitted on the remote peer.
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
			save_dice_blocks.append(fnp_dice_block)
			emit_signal("dice_rolled", fnp_dice_block)
			DebugLogger.info(str("ShootingPhase: Emitted feel_no_pain dice block - %d prevented / %d total" % [fnp_block.get("wounds_prevented", 0), fnp_block.get("total_wounds", 0)]))

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
				# T5-MP5: Include in save_dice_blocks for remote-player sync
				save_dice_blocks.append(fnp_overlay_block)
				emit_signal("dice_rolled", fnp_overlay_block)
				DebugLogger.info(str("ShootingPhase: Emitted feel_no_pain dice block from overlay - %d prevented / %d total" % [total_prevented, fnp_rolls_from_overlay.size()]))

	# HAZARDOUS (T2-3): Process Hazardous self-damage after saves resolve
	if not pending_hazardous_weapons.is_empty():
		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info(str("║ HAZARDOUS CHECK — Processing %d hazardous weapon(s)" % pending_hazardous_weapons.size()))
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")
		var haz_rng = RulesEngine.RNGService.new(pas_seed)  # Issue #329: forward seed
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
				# T5-MP5: Include hazardous dice in save_dice_blocks so remote
				# player sees the post-save hazardous self-damage rolls in real time
				save_dice_blocks.append(haz_dice)
				emit_signal("dice_rolled", haz_dice)
			if haz_result.log_text:
				log_phase_message(haz_result.log_text)
		pending_hazardous_weapons.clear()

	# ONE SHOT (T4-2): Include one-shot diffs in save result changes
	if not pending_one_shot_diffs.is_empty():
		all_diffs.append_array(pending_one_shot_diffs)
		pending_one_shot_diffs.clear()

	# T7-53: Emit shooting_damage_applied signal for floating damage numbers
	# This fires BEFORE diffs are applied by BasePhase.execute_action, allowing
	# handlers to read pre-damage values from GameState (same pattern as FightPhase.attacks_resolved)
	if not all_diffs.is_empty():
		emit_signal("shooting_damage_applied", active_shooter_id, all_diffs)
		DebugLogger.info(str("[ShootingPhase] T7-53: Emitted shooting_damage_applied with %d diffs" % all_diffs.size()))

	# Build combined save log text for game event log
	var save_log_text = ", ".join(save_log_parts)

	# VERBOSE COMBAT LOG: Emit save and result details
	_emit_verbose_combat_log(active_shooter_id, [], save_dice_blocks, total_casualties, "shooting_saves")

	# Check if we're in sequential weapon resolution mode
	var mode = resolution_state.get("mode", "")
	var is_sequential = (mode == "sequential" or mode == "fast")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ MODE CHECK IN _process_apply_saves")
	DebugLogger.info(str("║ resolution_state keys: ", resolution_state.keys()))
	DebugLogger.info(str("║ mode from resolution_state: '", mode, "'"))
	DebugLogger.info(str("║ is_sequential: ", is_sequential))
	DebugLogger.info(str("║ active_shooter_id: ", active_shooter_id))
	DebugLogger.info(str("║ confirmed_assignments.size(): ", confirmed_assignments.size()))
	DebugLogger.info("║")
	DebugLogger.info("║ PATH DECISION:")
	if is_sequential:
		DebugLogger.info("║ → Will take SEQUENTIAL path (lines 1401-1508)")
	else:
		DebugLogger.info("║ → Will take SINGLE WEAPON path (lines 1510+)")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	if is_sequential:
		# Sequential mode - record results and PAUSE for attacker to confirm next weapon
		var current_index = resolution_state.get("current_index", 0)
		var weapon_order = resolution_state.get("weapon_order", [])

		DebugLogger.info("========================================")
		DebugLogger.info("ShootingPhase: APPLY_SAVES complete in sequential mode")
		DebugLogger.info(str("ShootingPhase: current_index = %d, weapon_order.size() = %d" % [current_index, weapon_order.size()]))

		if current_index < weapon_order.size():
			var weapon_id = weapon_order[current_index].get("weapon_id", "")
			var current_assignment_data = weapon_order[current_index]
			DebugLogger.info(str("ShootingPhase: Completed weapon %d: %s" % [current_index + 1, weapon_id]))

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

			# Torrent/auto-hit weapons have empty hit_data — count from dice_data entries
			if hits == 0 and not dice_data.is_empty():
				for dice_entry in dice_data:
					if dice_entry is Dictionary and dice_entry.get("context", "") == "auto_hit":
						hits += dice_entry.get("successes", 0)
						total_attacks += dice_entry.get("total_attacks", 0)

			# P1-11: Track hits for Sanctified Flames
			if hits > 0 and target_unit_id != "":
				_targets_hit_by_shooter[target_unit_id] = _targets_hit_by_shooter.get(target_unit_id, 0) + hits
				DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking: %d hit(s) on %s (total: %d)" % [hits, target_unit_id, _targets_hit_by_shooter[target_unit_id]]))

			# Record completed weapon with full data
			resolution_state.completed_weapons.append({
				"weapon_id": weapon_id,
				"target_unit_id": target_unit_id,
				"target_unit_name": target_unit_name,
				"wounds": pending_save_data[0].get("wounds_to_save", 0) if not pending_save_data.is_empty() else 0,
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

			DebugLogger.info(str("ShootingPhase: Moving to next weapon index: %d" % resolution_state.current_index))
			DebugLogger.info(str("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index)))

			# ALWAYS PAUSE for attacker to confirm (even if last weapon)
			# Wait for attacker to confirm before continuing or completing
			DebugLogger.info("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon")
			DebugLogger.info(str("ShootingPhase: Remaining weapons: ", weapon_order.size() - resolution_state.current_index))

			# Determine which target units are fully destroyed by the pending diffs
			# (diffs haven't been applied to game state yet, so compute from diff + snapshot)
			var _models_killed_by_unit = {}
			for diff in all_diffs:
				var dpath = diff.get("path", "")
				if dpath.ends_with(".alive") and diff.get("value") == false:
					var dparts = dpath.split(".")
					if dparts.size() >= 2 and dparts[0] == "units":
						var uid = dparts[1]
						_models_killed_by_unit[uid] = _models_killed_by_unit.get(uid, 0) + 1
			var _targets_destroyed_by_diffs = {}
			for uid in _models_killed_by_unit:
				var tunit = get_unit(uid)
				var alive_count = 0
				for m in tunit.get("models", []):
					if m.get("alive", true):
						alive_count += 1
				if alive_count > 0 and alive_count <= _models_killed_by_unit[uid]:
					_targets_destroyed_by_diffs[uid] = true
					DebugLogger.info(str("ShootingPhase: Target unit %s fully destroyed by current saves — will skip remaining weapons targeting it" % uid))

			# Build remaining weapons with validation (may be empty array if this is the last weapon)
			# Filter out weapons targeting units destroyed by the current save diffs
			var remaining_weapons = []

			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ BUILDING REMAINING WEAPONS (after saves)")
			DebugLogger.info(str("║ weapon_order.size() = %d" % weapon_order.size()))
			DebugLogger.info(str("║ current_index = %d" % resolution_state.current_index))
			DebugLogger.info(str("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index)))

			for i in range(resolution_state.current_index, weapon_order.size()):
				var weapon = weapon_order[i]
				var weapon_target_id = weapon.get("target_unit_id", "")

				# Filter out weapons whose target was just destroyed (for UI display only)
				# Actual skipping and index management is handled by _resolve_next_weapon
				if _targets_destroyed_by_diffs.has(weapon_target_id):
					var skipped_wid = weapon.get("weapon_id", "")
					var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
					DebugLogger.info(str("║ Filtered weapon %d: %s (target %s destroyed)" % [i, skipped_wp.get("name", skipped_wid), weapon_target_id]))
					continue

				remaining_weapons.append(weapon)

				# Validate weapon structure
				var remaining_weapon_id = weapon.get("weapon_id", "")
				if remaining_weapon_id == "":
					push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
					DebugLogger.info(str("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i))
					DebugLogger.info(str("║   Full weapon object: %s" % str(weapon)))
				else:
					DebugLogger.info(str("║ Added weapon %d: %s" % [i, remaining_weapon_id]))

			DebugLogger.info(str("║ Total remaining weapons: %d" % remaining_weapons.size()))
			if remaining_weapons.is_empty():
				DebugLogger.info("║ ✓ All remaining weapons skipped or this is the FINAL weapon")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			# AUTO-COMPLETE: If all remaining weapons target destroyed units, skip them
			# and complete shooting automatically (no dialog needed)
			if remaining_weapons.is_empty() and not _targets_destroyed_by_diffs.is_empty():
				DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
				DebugLogger.info("║ AUTO-COMPLETE: All remaining targets destroyed — skipping weapons")

				# Record skipped weapons in completed_weapons
				for i in range(resolution_state.current_index, weapon_order.size()):
					var skipped_assignment = weapon_order[i]
					var skipped_wid = skipped_assignment.get("weapon_id", "")
					var skipped_tid = skipped_assignment.get("target_unit_id", "")
					var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
					var skipped_wname = skipped_wp.get("name", skipped_wid)
					var skipped_tname = get_unit(skipped_tid).get("meta", {}).get("name", skipped_tid)
					DebugLogger.info(str("║ Skipped: %s → %s (target destroyed)" % [skipped_wname, skipped_tname]))
					log_phase_message("Skipped %s — target %s destroyed" % [skipped_wname, skipped_tname])
					resolution_state.completed_weapons.append({
						"weapon_id": skipped_wid,
						"target_unit_id": skipped_tid,
						"target_unit_name": skipped_tname,
						"wounds": 0,
						"casualties": 0,
						"hits": 0,
						"total_attacks": 0,
						"saves_failed": 0,
						"dice_rolls": [],
						"hit_data": {},
						"wound_data": {},
						"skipped_target_destroyed": true
					})

				# Mark shooter as done
				var shooter_id = active_shooter_id
				all_diffs.append({
					"op": "set",
					"path": "units.%s.flags.has_shot" % active_shooter_id,
					"value": true
				})
				units_that_shot.append(active_shooter_id)

				# P1-11: Check for Sanctified Flames before clearing state
				var sanctified_changes = _check_sanctified_flames(active_shooter_id)
				all_diffs.append_array(sanctified_changes)

				# T5-UX9: capture before clearing
				_record_completed_weapons_to_phase_log(shooter_id)

				# Clear state
				active_shooter_id = ""
				confirmed_assignments.clear()
				resolution_state.clear()
				pending_save_data.clear()
				_targets_hit_by_shooter.clear()

				# Emit signal to clear visuals
				emit_signal("shooting_resolved", shooter_id, "", {"casualties": total_casualties})

				DebugLogger.info("║ Shooting auto-completed — all remaining targets destroyed")
				DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

				return create_result(true, all_diffs, "Sequential weapon resolution complete (remaining targets destroyed)", {
					"dice": save_dice_blocks,
					"log_text": save_log_text
				})

			# Get last weapon result for dialog display
			var last_weapon_result = _get_last_weapon_result()

			# Emit signal to show confirmation dialog to attacker
			# NOTE: remaining_weapons may be EMPTY if this is the final weapon
			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ EMITTING next_weapon_confirmation_required SIGNAL")
			DebugLogger.info(str("║ remaining_weapons.size(): ", remaining_weapons.size()))
			DebugLogger.info(str("║ current_index: ", resolution_state.current_index))
			DebugLogger.info(str("║ last_weapon_result keys: ", last_weapon_result.keys()))
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")
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

			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ APPLY_SAVES RESULT (with sequential_pause)")
			DebugLogger.info(str("║ result.sequential_pause: ", result.get("sequential_pause", false)))
			DebugLogger.info(str("║ result.remaining_weapons.size(): ", result.get("remaining_weapons", []).size()))
			DebugLogger.info(str("║ result.current_weapon_index: ", result.get("current_weapon_index", -1)))
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			return result

	# Normal mode (single weapon) or fast mode - show results dialog before completing
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ 🎯 SINGLE WEAPON PATH REACHED! (Line 1548)")
	DebugLogger.info(str("║ mode: '", mode, "'"))
	DebugLogger.info(str("║ total_casualties: ", total_casualties))
	DebugLogger.info(str("║ confirmed_assignments.size(): ", confirmed_assignments.size()))
	DebugLogger.info(str("║ all_diffs.size(): ", all_diffs.size()))
	DebugLogger.info("║")
	DebugLogger.info("║ NOW: Building last_weapon_result...")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Build last weapon result for single weapon case
	var last_weapon_result = {}
	if not confirmed_assignments.is_empty():
		DebugLogger.info("║ ✓ confirmed_assignments NOT empty, building result...")
		var assignment = confirmed_assignments[0]
		var weapon_id = assignment.get("weapon_id", "")
		DebugLogger.info(str("║   weapon_id: ", weapon_id))

		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		DebugLogger.info(str("║   weapon_name: ", weapon_profile.get("name", weapon_id)))

		var target_unit_id = assignment.get("target_unit_id", "")
		var target_unit = get_unit(target_unit_id)
		DebugLogger.info(str("║   target: ", target_unit.get("meta", {}).get("name", target_unit_id)))

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

		# Torrent/auto-hit weapons have empty hit_data — count from dice_data entries
		if sw_hits == 0 and not sw_dice_data.is_empty():
			for dice_entry in sw_dice_data:
				if dice_entry is Dictionary and dice_entry.get("context", "") == "auto_hit":
					sw_hits += dice_entry.get("successes", 0)
					sw_total_attacks += dice_entry.get("total_attacks", 0)

		DebugLogger.info(str("║   saves_failed: ", saves_failed))
		DebugLogger.info(str("║   casualties: ", total_casualties))
		DebugLogger.info(str("║   hits: ", sw_hits, " / ", sw_total_attacks))

		last_weapon_result = {
			"weapon_id": weapon_id,
			"weapon_name": weapon_profile.get("name", weapon_id),
			"target_unit_id": target_unit_id,
			"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
			"hits": sw_hits,
			"wounds": pending_save_data[0].get("wounds_to_save", 0) if not pending_save_data.is_empty() else 0,
			"saves_failed": saves_failed,
			"casualties": total_casualties,
			"total_attacks": sw_total_attacks,
			"dice_rolls": sw_dice_data,
			"hit_data": sw_hit_data,
			"wound_data": sw_wound_data
		}
		DebugLogger.info("║ ✓ last_weapon_result built successfully!")

		# P1-11: Track hits for Sanctified Flames (single-weapon path)
		if sw_hits > 0 and target_unit_id != "":
			_targets_hit_by_shooter[target_unit_id] = _targets_hit_by_shooter.get(target_unit_id, 0) + sw_hits
			DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking: %d hit(s) on %s (total: %d)" % [sw_hits, target_unit_id, _targets_hit_by_shooter[target_unit_id]]))

		# Record completed weapon so phase_shooting_log captures single-weapon results
		if not resolution_state.has("completed_weapons"):
			resolution_state["completed_weapons"] = []
		resolution_state.completed_weapons.append({
			"weapon_id": weapon_id,
			"target_unit_id": target_unit_id,
			"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
			"wounds": pending_save_data[0].get("wounds_to_save", 0) if not pending_save_data.is_empty() else 0,
			"casualties": total_casualties,
			"hits": sw_hits,
			"total_attacks": sw_total_attacks,
			"saves_failed": saves_failed,
			"dice_rolls": sw_dice_data,
			"hit_data": sw_hit_data,
			"wound_data": sw_wound_data
		})
	else:
		DebugLogger.info("║ ⚠️  WARNING: confirmed_assignments is EMPTY!")

	# Emit signal with EMPTY remaining_weapons (signals completion)
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ 📡 EMITTING next_weapon_confirmation_required SIGNAL")
	DebugLogger.info("║ Signal name: 'next_weapon_confirmation_required'")
	DebugLogger.info("║ Parameter 1 (remaining_weapons): [] (empty array)")
	DebugLogger.info("║ Parameter 2 (current_index): 0")
	DebugLogger.info(str("║ Parameter 3 (last_weapon_result): ", last_weapon_result))
	DebugLogger.info("║")
	DebugLogger.info("║ This signal should trigger ShootingController to show dialog!")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	emit_signal("next_weapon_confirmation_required", [], 0, last_weapon_result)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ ✅ Signal emitted successfully!")
	DebugLogger.info("║ Returning result with sequential_pause=true")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ 🎬 SINGLE WEAPON PATH COMPLETE")
	DebugLogger.info("║ Returning to caller with result")
	DebugLogger.info("║ User should now see NextWeaponDialog")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	return result

func _process_continue_sequence(action: Dictionary) -> Dictionary:
	"""Process continuation to next weapon in sequential mode"""
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SHOOTING PHASE: _process_continue_sequence CALLED")
	DebugLogger.info("║")

	var payload = action.get("payload", {})
	var updated_weapon_order = payload.get("weapon_order", [])

	DebugLogger.info("║ CURRENT STATE:")
	DebugLogger.info(str("║   resolution_state.current_index: ", resolution_state.get("current_index", 0)))
	DebugLogger.info(str("║   resolution_state.weapon_order.size(): ", resolution_state.get("weapon_order", []).size()))
	DebugLogger.info(str("║   resolution_state.completed_weapons: ", resolution_state.get("completed_weapons", []).size()))
	DebugLogger.info("║")
	DebugLogger.info("║ ACTION PAYLOAD:")
	DebugLogger.info(str("║   updated_weapon_order provided: ", not updated_weapon_order.is_empty()))
	DebugLogger.info(str("║   updated_weapon_order.size(): ", updated_weapon_order.size()))
	if not updated_weapon_order.is_empty():
		DebugLogger.info("║   First 3 weapons in updated order:")
		for i in range(min(3, updated_weapon_order.size())):
			DebugLogger.info(str("║     %d: %s" % [i, updated_weapon_order[i].get("weapon_id", "UNKNOWN")]))
	DebugLogger.info("║")

	# If attacker provided a new weapon order (reordering), update it
	if not updated_weapon_order.is_empty():
		DebugLogger.info("║ REORDERING: Attacker provided new weapon order")
		# Keep completed weapons, update remaining
		var current_index = resolution_state.get("current_index", 0)
		var original_order = resolution_state.get("weapon_order", [])

		DebugLogger.info(str("║   current_index: ", current_index))
		DebugLogger.info(str("║   original_order.size(): ", original_order.size()))
		DebugLogger.info(str("║   Keeping first %d completed weapons" % current_index))

		# Build new complete order: completed weapons + reordered remaining weapons
		var new_complete_order = []
		for i in range(current_index):
			if i < original_order.size():
				new_complete_order.append(original_order[i])
				DebugLogger.info(str("║   Kept completed weapon %d: %s" % [i, original_order[i].get("weapon_id", "UNKNOWN")]))

		DebugLogger.info(str("║   Appending %d reordered weapons" % updated_weapon_order.size()))
		new_complete_order.append_array(updated_weapon_order)

		DebugLogger.info("║")
		DebugLogger.info(str("║   NEW COMPLETE ORDER (%d weapons):" % new_complete_order.size()))
		for i in range(min(5, new_complete_order.size())):
			var status = "✓ COMPLETED" if i < current_index else "⏳ PENDING"
			DebugLogger.info(str("║     %d: %s %s" % [i, new_complete_order[i].get("weapon_id", "UNKNOWN"), status]))
		if new_complete_order.size() > 5:
			DebugLogger.info(str("║     ... and %d more weapons" % (new_complete_order.size() - 5)))

		resolution_state.weapon_order = new_complete_order
		DebugLogger.info("║   Updated resolution_state.weapon_order")
	else:
		DebugLogger.info("║ NO REORDERING: Using existing weapon order")

	DebugLogger.info("║")
	DebugLogger.info("║ FINAL STATE BEFORE _resolve_next_weapon():")
	DebugLogger.info(str("║   current_index: ", resolution_state.get("current_index", 0)))
	DebugLogger.info(str("║   weapon_order.size(): ", resolution_state.get("weapon_order", []).size()))
	DebugLogger.info(str("║   Next weapon to resolve: index %d" % resolution_state.get("current_index", 0)))
	if resolution_state.get("current_index", 0) < resolution_state.get("weapon_order", []).size():
		var next_weapon = resolution_state.get("weapon_order", [])[resolution_state.get("current_index", 0)]
		DebugLogger.info(str("║   Next weapon ID: %s" % next_weapon.get("weapon_id", "UNKNOWN")))
	DebugLogger.info("║")
	DebugLogger.info("║ Calling _resolve_next_weapon()...")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	var next_result = _resolve_next_weapon()

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ _resolve_next_weapon() RETURNED")
	DebugLogger.info(str("║   success: ", next_result.get("success", false)))
	DebugLogger.info(str("║   log_text: ", next_result.get("log_text", "")))
	if next_result.has("sequential_pause"):
		DebugLogger.info(str("║   sequential_pause: ", next_result.get("sequential_pause", false)))
		DebugLogger.info(str("║   weapons_remaining: ", next_result.get("weapons_remaining", 0)))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	return next_result


# ============================================================================
# VERBOSE COMBAT LOG — Detailed dice breakdown for Game Event Log
# ============================================================================

func _emit_verbose_combat_log(shooter_id: String, dice_data: Array, save_dice_blocks: Array, casualties: int, phase_type: String) -> void:
	"""Emit detailed combat log entries to GameEventLog from dice_data and save results.
	Called after combat resolution completes (hits+wounds+saves all done)."""
	var shooter_unit = game_state_snapshot.get("units", {}).get(shooter_id, {})
	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_id)
	var player = get_current_player()

	# Extract hit and wound dice blocks
	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "resolution_start":
			continue

		if context == "to_hit" or context == "hit_roll":
			_emit_hit_detail_log(shooter_name, dice_block, player)
		elif context == "auto_hit":
			_emit_torrent_detail_log(shooter_name, dice_block, player)
		elif context == "to_wound" or context == "wound_roll":
			_emit_wound_detail_log(dice_block, player)

	# Save dice blocks
	for save_block in save_dice_blocks:
		var scontext = save_block.get("context", "")
		if scontext == "save_roll":
			_emit_save_detail_log(save_block)
		elif scontext == "feel_no_pain":
			_emit_fnp_detail_log(save_block)

	# Final result line — only show after saves are resolved (not for hit/wound-only phases)
	if phase_type == "shooting_saves":
		if casualties > 0:
			var _cas_label2 = "model" if casualties == 1 else "models"
			GameEventLog.add_combat_result("  Result: %d %s destroyed" % [casualties, _cas_label2])
		else:
			GameEventLog.add_combat_result("  Result: No models destroyed")

func _emit_hit_detail_log(shooter_name: String, dice_block: Dictionary, player: int) -> void:
	"""Emit detailed hit roll log from a to_hit dice block."""
	var weapon_name = dice_block.get("weapon_name", "")
	var threshold = dice_block.get("threshold", "?")
	var rolls_raw = dice_block.get("rolls_raw", [])
	var rolls_modified = dice_block.get("rolls_modified", [])
	var successes = dice_block.get("successes", 0)
	var base_attacks = dice_block.get("base_attacks", rolls_raw.size())
	var total_attacks = rolls_raw.size()

	# Header - weapon and attack count
	var attacks_desc = "%d attacks" % total_attacks
	# Variable attacks
	if dice_block.get("variable_attacks", false):
		attacks_desc = "%s → %d attacks" % [dice_block.get("attacks_notation", "?"), total_attacks]
	# Rapid fire bonus
	var rf_bonus = dice_block.get("rapid_fire_bonus", 0)
	if rf_bonus > 0:
		attacks_desc += " (incl. +%d Rapid Fire)" % rf_bonus
	# Blast bonus
	var blast_bonus = dice_block.get("blast_bonus_attacks", 0)
	if blast_bonus > 0:
		attacks_desc += " (incl. +%d Blast vs %d models)" % [blast_bonus, dice_block.get("target_model_count", 0)]

	if weapon_name != "":
		GameEventLog.add_combat_detail("  Weapon: %s — %s" % [weapon_name, attacks_desc])

	# Hit rolls line
	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	var hit_line = "  To Hit: needed %s — rolled %s — %d/%d hit" % [threshold, rolls_str, successes, total_attacks]
	GameEventLog.add_combat_detail(hit_line)

	# Modified rolls (if different from raw)
	if not rolls_modified.is_empty() and rolls_modified != rolls_raw:
		GameEventLog.add_combat_detail("    Modified rolls: %s" % GameEventLog._format_dice_rolls(rolls_modified))

	# Hit modifiers description
	var mods_parts = []
	if dice_block.get("heavy_bonus_applied", false):
		mods_parts.append("Heavy +1")
	if dice_block.get("bgnt_penalty_applied", false):
		mods_parts.append("Big Guns Never Tire -1")
	if dice_block.get("indirect_fire_applied", false):
		mods_parts.append("Indirect Fire -1")
	if dice_block.get("conversion_active", false):
		mods_parts.append("Conversion %d+" % dice_block.get("critical_hit_threshold", 6))
	if not mods_parts.is_empty():
		GameEventLog.add_combat_detail("    Hit modifiers: %s" % ", ".join(mods_parts))

	# Rerolls
	var rerolls = dice_block.get("rerolls", [])
	if not rerolls.is_empty():
		var rr_strs = []
		for rr in rerolls:
			rr_strs.append("%d→%d" % [rr.get("original", 0), rr.get("rerolled_to", rr.get("new", 0))])
		GameEventLog.add_combat_detail("    Re-rolls: %s" % ", ".join(rr_strs))

	# Critical hits and special abilities
	var crits = dice_block.get("critical_hits", 0)
	if crits > 0:
		var crit_parts = ["%d critical hit(s)" % crits]
		if dice_block.get("lethal_hits_weapon", false):
			crit_parts.append("Lethal Hits active (crits auto-wound)")
		if dice_block.get("sustained_hits_weapon", false):
			var sh_bonus = dice_block.get("sustained_bonus_hits", 0)
			crit_parts.append("Sustained Hits: +%d bonus hit(s)" % sh_bonus)
		GameEventLog.add_combat_detail("    Criticals: %s" % " | ".join(crit_parts))

func _emit_torrent_detail_log(shooter_name: String, dice_block: Dictionary, player: int) -> void:
	"""Emit log for a Torrent (auto-hit) weapon."""
	var total = dice_block.get("total_attacks", 0)
	GameEventLog.add_combat_detail("  To Hit: Torrent — %d automatic hit(s)" % total)

func _emit_wound_detail_log(dice_block: Dictionary, player: int) -> void:
	"""Emit detailed wound roll log from a to_wound dice block."""
	var threshold = dice_block.get("threshold", "?")
	var rolls_raw = dice_block.get("rolls_raw", [])
	var successes = dice_block.get("successes", 0)
	var total = rolls_raw.size()

	# Auto-wounds from Lethal Hits
	var auto_wounds = dice_block.get("lethal_hits_auto_wounds", 0)
	if auto_wounds > 0:
		GameEventLog.add_combat_detail("  Lethal Hits: %d auto-wound(s) (no roll needed)" % auto_wounds)

	# Wound rolls
	if total > 0:
		var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
		var wounds_from_rolls = dice_block.get("wounds_from_rolls", successes - auto_wounds)
		var wound_line = "  To Wound: needed %s — rolled %s — %d/%d wounded" % [threshold, rolls_str, wounds_from_rolls, total]
		GameEventLog.add_combat_detail(wound_line)

	# Wound modifiers
	var wound_mod_net = dice_block.get("wound_modifier_net", 0)
	if wound_mod_net != 0:
		GameEventLog.add_combat_detail("    Wound modifier: %+d" % wound_mod_net)

	# Wound rerolls (Twin-linked, etc.)
	var wound_rerolls = dice_block.get("wound_rerolls", [])
	if not wound_rerolls.is_empty():
		var wrr_strs = []
		for wrr in wound_rerolls:
			wrr_strs.append("%d→%d" % [wrr.get("original", 0), wrr.get("rerolled_to", wrr.get("new", 0))])
		var reroll_source = "Twin-linked" if dice_block.get("twin_linked_weapon", false) else "Re-roll"
		GameEventLog.add_combat_detail("    %s: %s" % [reroll_source, ", ".join(wrr_strs)])

	# Anti-keyword
	if dice_block.get("anti_keyword_active", false):
		GameEventLog.add_combat_detail("    Anti-keyword: critical wounds on %d+" % dice_block.get("critical_wound_threshold", 6))

	# Devastating Wounds
	var dw_count = dice_block.get("critical_wounds", 0)
	if dice_block.get("devastating_wounds_weapon", false) and dw_count > 0:
		GameEventLog.add_combat_detail("    DEVASTATING WOUNDS: %d wound(s) bypass saves" % dw_count)

	# Total wounds summary
	GameEventLog.add_combat_detail("  Total wounds caused: %d" % successes)

func _emit_save_detail_log(save_block: Dictionary) -> void:
	"""Emit detailed save roll log from a save_roll dice block."""
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
	var save_line = "  %s Saves vs %s: %s — rolled %s — %d passed, %d failed" % [
		target_name, weapon_name, save_type, rolls_str, passed, failed]
	GameEventLog.add_combat_detail(save_line)

func _emit_fnp_detail_log(fnp_block: Dictionary) -> void:
	"""Emit Feel No Pain roll details."""
	var target_name = fnp_block.get("target_unit_name", "Unknown")
	var threshold = fnp_block.get("threshold", "?")
	var rolls_raw = fnp_block.get("rolls_raw", [])
	var prevented = fnp_block.get("wounds_prevented", 0)
	var total = fnp_block.get("total_wounds", 0)

	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	GameEventLog.add_combat_detail("  %s Feel No Pain %s: rolled %s — %d/%d wounds prevented" % [
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

# ============================================================================
# STRATAGEM HANDLING (active stratagems with phase: "shooting")
# Mirrors CommandPhase._validate_use_stratagem / _process_use_stratagem.
# Distinct from USE_GRENADE_STRATAGEM (hardcoded grenade carve-out) and
# USE_REACTIVE_STRATAGEM (defender reactive). This is the generic active path.
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
	DebugLogger.info(str("ShootingPhase: Stratagem %s used (target=%s)" % [strat_name, target_unit_id]))
	return create_result(true, result.get("diffs", []), "Used " + strat_name)

# ============================================================================
# SWIFT AS THE EAGLE — Reactive D6" Normal move after being shot at
# ============================================================================

func _check_swift_as_the_eagle(shooter_id: String, targeted_unit_ids: Array) -> Dictionary:
	var result = {"available": false, "unit_id": "", "unit_name": "", "move_inches": 0}
	if targeted_unit_ids.is_empty():
		return result

	var strat_mgr = get_node_or_null("/root/StratagemManager")
	if not strat_mgr:
		return result

	var shooter_unit = GameState.get_unit(shooter_id)
	if shooter_unit.is_empty():
		return result
	var shooter_owner = int(shooter_unit.get("owner", 0))
	var defending_player = 1 if shooter_owner == 2 else 2

	var strat_id = strat_mgr.find_faction_stratagem_by_name(defending_player, "SWIFT AS THE EAGLE")
	if strat_id == "":
		return result

	var validation = strat_mgr.can_use_stratagem(defending_player, strat_id)
	if not validation.can_use:
		return result

	for tid in targeted_unit_ids:
		var unit = GameState.get_unit(tid)
		if unit.is_empty():
			continue
		if int(unit.get("owner", 0)) != defending_player:
			continue
		if unit.get("flags", {}).get("battle_shocked", false):
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_custodes = false
		var is_vehicle = false
		for kw in keywords:
			var kw_upper = kw.to_upper()
			if kw_upper == "ADEPTUS CUSTODES":
				is_custodes = true
			if kw_upper == "VEHICLE":
				is_vehicle = true
		if is_custodes and not is_vehicle:
			var has_alive = false
			for m in unit.get("models", []):
				if m.get("alive", true):
					has_alive = true
					break
			if has_alive:
				var d6 = _rng.randi_range(1, 6)
				result.available = true
				result.unit_id = tid
				result.unit_name = unit.get("meta", {}).get("name", tid)
				result.move_inches = d6
				return result
	return result

func _validate_use_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	if not awaiting_swift_as_eagle or swift_as_eagle_pending_unit == "":
		return {"valid": false, "errors": ["No Swift as the Eagle pending"]}
	return {"valid": true, "errors": []}

func _validate_decline_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	if not awaiting_swift_as_eagle or swift_as_eagle_pending_unit == "":
		return {"valid": false, "errors": ["No Swift as the Eagle pending"]}
	return {"valid": true, "errors": []}

func _process_use_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	var unit_id = swift_as_eagle_pending_unit
	var move_inches = swift_as_eagle_move_inches
	var unit = GameState.get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var unit_owner = int(unit.get("owner", 0))

	var strat_mgr = get_node_or_null("/root/StratagemManager")
	if strat_mgr:
		var strat_id = strat_mgr.find_faction_stratagem_by_name(unit_owner, "SWIFT AS THE EAGLE")
		if strat_id != "":
			strat_mgr.use_stratagem(unit_owner, strat_id, unit_id)

	var changes: Array = [{
		"op": "set",
		"path": "units.%s.flags.effect_swift_as_the_eagle" % unit_id,
		"value": true
	}, {
		"op": "set",
		"path": "units.%s.flags.swift_eagle_move_remaining" % unit_id,
		"value": move_inches
	}]

	log_phase_message("SWIFT AS THE EAGLE: %s can make a Normal move of up to %d\" (D6 rolled %d)" % [unit_name, move_inches, move_inches])
	awaiting_swift_as_eagle = false
	swift_as_eagle_pending_unit = ""
	swift_as_eagle_move_inches = 0
	return create_result(true, changes, "Swift as the Eagle activated — %d\" move" % move_inches)

func _process_decline_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	var unit_name = GameState.get_unit(swift_as_eagle_pending_unit).get("meta", {}).get("name", swift_as_eagle_pending_unit)
	log_phase_message("SWIFT AS THE EAGLE: %s declines reactive move" % unit_name)
	awaiting_swift_as_eagle = false
	swift_as_eagle_pending_unit = ""
	swift_as_eagle_move_inches = 0
	return create_result(true, [], "Swift as the Eagle declined")
