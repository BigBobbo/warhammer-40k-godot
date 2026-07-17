extends BasePhase
class_name FightPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# FightPhase - Full implementation for the Fight phase following 10e rules
# Supports fight sequencing, pile in, attack resolution, and consolidation

# Floating-point tolerance for distance cap checks (< 1px)
const MOVEMENT_CAP_EPSILON: float = 0.02

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
signal sweeping_advance_available(unit_id: String, player: int, in_engagement: bool, move_distance: float)  # Sweeping Advance opportunity
signal acrobatic_escape_available(unit_id: String, player: int, move_distance: float)  # Acrobatic Escape opportunity (Callidus Assassin)
signal consolidation_step_required(data: Dictionary)  # 11e 12.07: global Consolidate step — a player must consolidate/pass
signal pile_in_step_required(data: Dictionary)  # 11e 12.02: global Pile In step — a player must pile in/pass
# Emitted when a fighter's attack assignments are confirmed (the melee
# analogue of ShootingPhase.shooting_begun — remote/visual feedback hook).
# Was emitted UNDECLARED, raising a runtime error on every melee confirm.
signal fighting_begun(unit_id: String)
# STAGED FIGHT: paused after the hit roll ("hits") or wound roll ("wounds") of
# the current weapon so the attacker can read the dice / use Command Re-roll;
# "complete" fires when the whole staged sequence finishes. Mirrors
# ShootingPhase.shooting_stage_paused.
signal fight_stage_paused(stage: String, info: Dictionary)

# Fight state tracking
var active_fighter_id: String = ""
var selected_weapon_id: String = ""  # Currently selected weapon for active fighter
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

# STAGED FIGHT (non-networked, human attacker): assignment-by-assignment melee
# resolution with pauses after the hit roll and the wound roll (Command Re-roll
# windows) — mirrors ShootingPhase's sequential_staged mode. Empty = inactive.
# Keys: assignments, current_index, stage ("hits_pending"/"wounds_pending"/
# "saves_pending"), hit_context, wound_result, wound_context, save_data_list,
# assignment_dice, interactive_saves, total_casualties, reroll flags.
var staged_fight_state: Dictionary = {}

# ISS-050: the 11e fight-step state machine (12.04-12.06) — the single source
# of truth for fight selection (there is no 10e tier-list state any more).
var sequencer_11e: FightSequencer = null
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

# Counter-Offensive state tracking
var awaiting_counter_offensive: bool = false
var counter_offensive_player: int = 0  # Player being offered Counter-Offensive
var counter_offensive_unit_id: String = ""  # Unit selected for Counter-Offensive (set on USE)

# Sweeping Advance state tracking
var awaiting_sweeping_advance: bool = false
var sweeping_advance_pending_units: Array = []  # Units eligible for Sweeping Advance at end of fight phase

# Acrobatic Escape state tracking (Callidus Assassin)
var awaiting_acrobatic_escape: bool = false
var acrobatic_escape_pending_units: Array = []  # Units eligible for Acrobatic Escape at end of fight phase

# Moment Shackle tracking (Trajann Valoris)
var _moment_shackle_pending_units: Array = []  # Unit IDs with Moment Shackle available this phase

# 11e 12.07-12.08: the global end-of-phase CONSOLIDATE step (edition >= 11
# only). NOT_STARTED while the Fight step runs; ACTIVE once END_FIGHT is
# requested with every fight resolved — the active player consolidates all
# eligible units they choose, then the opponent; DONE when both halves are
# finished, at which point the end-of-fight-phase triggers (Sweeping
# Advance, Acrobatic Escape) run and the phase can complete.
enum ConsolidationStep11e { NOT_STARTED, ACTIVE, DONE }
var consolidation_step_11e: int = ConsolidationStep11e.NOT_STARTED
var consolidating_player_11e: int = 0                # whose half of the step it is
var consolidation_done_players_11e: Dictionary = {}  # player(int) -> true once they passed
var units_that_consolidated_11e: Dictionary = {}     # unit_id -> true (12.07: one move per unit)

# 11e 12.02-12.03: the global PILE IN step at the START of the fight phase
# (edition >= 11 only). ACTIVE from phase entry while each player in turn
# (active player first) makes pile-in moves with the eligible units they
# choose (engaged / charged this turn; one move per unit, optional per
# unit); DONE when both halves finish, at which point the Fight step's
# selection begins. During the Fight step only an OVERRUN fight (12.06)
# gets an additional pile-in move — tracked by overrun_pile_in_unit_11e.
enum PileInStep11e { NOT_STARTED, ACTIVE, DONE }
var pile_in_step_11e: int = PileInStep11e.NOT_STARTED
var piling_in_player_11e: int = 0                # whose half of the step it is
var pile_in_done_players_11e: Dictionary = {}    # player(int) -> true once they passed
var overrun_pile_in_unit_11e: String = ""        # unit granted the 12.06 additional pile-in
# T3-13-style pending data so the controller can pull the step dialog it
# missed while connecting (the step starts during phase entry).
var _pending_pile_in_step_data: Dictionary = {}

func _init():
	phase_type = GameStateData.Phase.FIGHT

func _on_phase_enter() -> void:
	log_phase_message("Entering Fight Phase")
	# Big Gob (Bully Boyz enhancement): at the start of the Fight phase the
	# bearer bellows at the nearest engaged enemy — Battle-shock test at -1.
	var fam = get_node_or_null("/root/FactionAbilityManager")
	if fam and fam.has_method("process_big_gob"):
		fam.process_big_gob(1)
		fam.process_big_gob(2)
	# Clear previous state
	active_fighter_id = ""
	pending_attacks.clear()
	confirmed_attacks.clear()
	resolution_state.clear()
	staged_fight_state.clear()
	dice_log.clear()
	units_that_fought.clear()
	units_that_piled_in.clear()
	awaiting_counter_offensive = false
	counter_offensive_player = 0
	counter_offensive_unit_id = ""
	_pending_fight_selection_data = {}
	awaiting_sweeping_advance = false
	sweeping_advance_pending_units.clear()
	awaiting_acrobatic_escape = false
	acrobatic_escape_pending_units.clear()
	_moment_shackle_pending_units.clear()
	consolidation_step_11e = ConsolidationStep11e.NOT_STARTED
	consolidating_player_11e = 0
	consolidation_done_players_11e.clear()
	units_that_consolidated_11e.clear()
	pile_in_step_11e = PileInStep11e.NOT_STARTED
	piling_in_player_11e = 0
	pile_in_done_players_11e.clear()
	overrun_pile_in_unit_11e = ""
	_pending_pile_in_step_data = {}
	# Clear stale eligibility stamps from a previous fight phase (e.g. a
	# loaded save) before this phase re-stamps them.
	_clear_fight_eligibility_stamps_11e()

	# Detect Moment Shackle eligible units
	var ms_units = GameState.state.get("units", {})
	for ms_uid in ms_units:
		var ms_unit = ms_units[ms_uid]
		if ms_unit.get("owner", 0) != get_current_player():
			continue
		if ms_unit.get("flags", {}).get("moment_shackle_used", false):
			continue
		var ms_abilities = ms_unit.get("meta", {}).get("abilities", [])
		for ms_ab in ms_abilities:
			var ms_name = ms_ab.get("name", "") if ms_ab is Dictionary else str(ms_ab)
			if ms_name == "Moment Shackle":
				_moment_shackle_pending_units.append(ms_uid)
				break

	# Apply unit ability effects (leader abilities, always-on abilities)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	# Refresh snapshot after ability effects mutated GameState flags
	game_state_snapshot = GameState.create_snapshot()

	_initialize_fight_sequence()
	_check_for_combats()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Fight Phase")

	# TRY DAT BUTTON! (Dread Mob): Button Effects last until end of phase
	var fam_tdb_exit = get_node_or_null("/root/FactionAbilityManager")
	if fam_tdb_exit:
		fam_tdb_exit.clear_try_dat_flags("melee")

	# T5-V13: Clear engagement indicator flags
	_clear_engagement_flags()

	# 11e: eligibility stamps are phase-scoped — clear them on exit
	_clear_fight_eligibility_stamps_11e()

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
		DebugLogger.info("FightPhase: P3-103 Updated objective control at end of Fight phase")

func _initialize_fight_sequence() -> void:
	var all_units = game_state_snapshot.get("units", {})
	log_phase_message("Checking %d units for combat eligibility" % all_units.size())

	current_selecting_player = _get_defending_player()

	# 12.04: the FightSequencer drives selection — alternation starts with the
	# ACTIVE player, and the eligibility matrix includes charge-survivors that
	# are no longer engaged (overrun fights, 12.06).
	sequencer_11e = FightSequencer.new()
	sequencer_11e.begin(GameState.state, GameState.get_active_player())
	var sel_11e = sequencer_11e.next_selection(GameState.state)
	if not sel_11e.done:
		current_selecting_player = sel_11e.player
	log_phase_message("[11e] FightSequencer: %s step, Player %d picks from %s" % [
		sel_11e.step, sel_11e.player, str(sel_11e.candidates)])
	# 12.08: consolidation eligibility ("was eligible to fight this
	# phase") is cumulative — stamp the units eligible from the start.
	_stamp_fight_eligibility_11e()

	log_phase_message("=== FIGHT PHASE INITIALIZATION ===")
	log_phase_message("Active Player: %d" % GameState.get_active_player())
	log_phase_message("Selecting Player (starts first): %d" % current_selecting_player)
	log_phase_message("===================================")

	# T5-V13: Set is_engaged and fight_priority flags on engaged units for board indicators
	_set_engagement_flags()

	var combatants = _combatants_11e()
	emit_signal("fight_order_determined", combatants)
	emit_signal("fight_sequence_updated", combatants)

	# 11e 12.02: the fight phase OPENS with the global Pile In step — both
	# players pile in their eligible units (active player first) before any
	# unit is selected to fight.
	_begin_pile_in_step_11e()

func _check_for_combats() -> void:
	var combatants = _combatants_11e()
	if combatants.is_empty():
		log_phase_message("No units in combat, ready to end fight phase")
		# Don't auto-complete - wait for END_FIGHT action
	else:
		log_phase_message("Found %d unit(s) in combat" % combatants.size())

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
						# Superior Creation (Lions enhancement): queue the end-of-phase revival roll
					_record_superior_creation_if_applicable(unit_id)
					# P3-32: Check if destroyed unit is a transport with embarked units
					_resolve_transport_destroyed_if_applicable(unit_id)

func _resolve_transport_destroyed_if_applicable(destroyed_unit_id: String) -> void:
	"""P3-32: If a destroyed unit is a transport, resolve emergency disembark for embarked units."""
	if not TransportManager.is_transport_with_embarked(destroyed_unit_id):
		return

	var unit_name = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {}).get("name", destroyed_unit_id)
	DebugLogger.info(str("FightPhase: P3-32 Transport %s (%s) destroyed — resolving emergency disembark" % [unit_name, destroyed_unit_id]))
	log_phase_message("Transport %s destroyed! Embarked units must emergency disembark!" % unit_name)

	var result = TransportManager.resolve_transport_destroyed(destroyed_unit_id)
	if result.get("triggered", false):
		var diffs = result.get("diffs", [])
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)

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
			_check_kill_diffs(diffs)

func _resolve_transport_destruction_if_applicable(destroyed_unit_id: String) -> void:
	"""P1-60: Check if a destroyed unit is a transport with embarked units and resolve emergency disembarkation."""
	var transport_mgr = get_node_or_null("/root/TransportManager")
	if not transport_mgr:
		return
	if not transport_mgr.is_transport_with_embarked_units(destroyed_unit_id):
		return

	var transport_name = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {}).get("name", destroyed_unit_id)
	DebugLogger.info(str("FightPhase: P1-60 Transport destruction detected — %s (%s) has embarked units" % [transport_name, destroyed_unit_id]))
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

func _record_superior_creation_if_applicable(destroyed_unit_id: String) -> void:
	"""Superior Creation (Lions of the Emperor): first bearer death queues a
	2+ revival roll that PhaseManager resolves at the end of the phase."""
	var result = RulesEngine.record_superior_creation_death(destroyed_unit_id, GameState.state)
	if not result.get("applicable", false):
		return
	var diffs = result.get("diffs", [])
	if not diffs.is_empty():
		PhaseManager.apply_state_changes(diffs)
	var _sc_meta = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {})
	log_phase_message("Superior Creation: %s destroyed — revival roll (2+) at end of phase" % _sc_meta.get("name", destroyed_unit_id))

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
	DebugLogger.info(str("FightPhase: P1-13 Deadly Demise detected on destroyed unit %s (%s) — value: %s" % [unit_name, destroyed_unit_id, dd_value]))
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
		"END_CONSOLIDATION":
			return _validate_end_consolidation(action)
		"END_PILE_IN":
			return _validate_end_pile_in(action)
		"SWEEPING_ADVANCE":
			return _validate_sweeping_advance(action)
		"DECLINE_SWEEPING_ADVANCE":
			return {"valid": true}
		"ACROBATIC_ESCAPE":
			return _validate_acrobatic_escape(action)
		"DECLINE_ACROBATIC_ESCAPE":
			return {"valid": true}
		"BATCH_FIGHT_ACTIONS":
			return _validate_batch_fight_actions(action)
		"APPLY_MELEE_SAVES":
			return _validate_apply_melee_saves(action)
		"CONTINUE_TO_WOUNDS", "CONTINUE_TO_SAVES", "USE_FIGHT_REROLL":  # Staged sequential steps
			return _validate_staged_fight_continue(action)
		"USE_MOMENT_SHACKLE":
			var ms_uid = action.get("unit_id", "")
			if ms_uid not in _moment_shackle_pending_units:
				return {"valid": false, "errors": ["Unit does not have Moment Shackle pending"]}
			var ms_choice = action.get("choice", "")
			if ms_choice not in ["attacks_12", "invuln_2"]:
				return {"valid": false, "errors": ["Invalid Moment Shackle choice: %s" % ms_choice]}
			return {"valid": true}
		"DECLINE_MOMENT_SHACKLE":
			var ms_uid2 = action.get("unit_id", "")
			if ms_uid2 not in _moment_shackle_pending_units:
				return {"valid": false, "errors": ["Unit does not have Moment Shackle pending"]}
			return {"valid": true}
		"USE_STRATAGEM":
			return _validate_use_stratagem(action)
		"END_CHARGE":
			# Idempotent no-op: previous phase auto-advanced before END_CHARGE was dispatched.
			return {"valid": true}
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
			return _process_consolidate_step_11e(action)
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
		"END_CONSOLIDATION":
			return _process_end_consolidation(action)
		"END_PILE_IN":
			return _process_end_pile_in(action)
		"SWEEPING_ADVANCE":
			return _process_sweeping_advance(action)
		"DECLINE_SWEEPING_ADVANCE":
			return _process_decline_sweeping_advance(action)
		"ACROBATIC_ESCAPE":
			return _process_acrobatic_escape(action)
		"DECLINE_ACROBATIC_ESCAPE":
			return _process_decline_acrobatic_escape(action)
		"BATCH_FIGHT_ACTIONS":
			return _process_batch_fight_actions(action)
		"APPLY_MELEE_SAVES":
			return _process_apply_melee_saves(action)
		"CONTINUE_TO_WOUNDS":  # Staged: roll the wound roll for the paused weapon
			return _staged_fight_continue_to_wounds()
		"CONTINUE_TO_SAVES":  # Staged: hand the paused weapon's wounds to saves
			return _staged_fight_continue_to_saves()
		"USE_FIGHT_REROLL":  # Staged: Command Re-roll a hit or wound die
			return _process_use_fight_reroll(action)
		"USE_MOMENT_SHACKLE":
			return _process_use_moment_shackle(action)
		"DECLINE_MOMENT_SHACKLE":
			return _process_decline_moment_shackle(action)
		"USE_STRATAGEM":
			return _process_use_stratagem(action)
		"END_CHARGE":
			return create_result(true, [], "")
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

	# 11e 12.02: no unit is selected to fight until the Pile In step is over
	if pile_in_step_11e == PileInStep11e.ACTIVE:
		return {"valid": false, "errors": ["The Pile In step (12.02) must finish before units are selected to fight"]}

	# 12.04: the FightSequencer is the selection authority — including
	# charge-survivors that are unengaged (pg-39 overrun case).
	if sequencer_11e == null:
		return {"valid": false, "errors": ["Fight sequencer not initialized"]}
	var sel_11e = sequencer_11e.next_selection(GameState.state)
	if sel_11e.done:
		return {"valid": false, "errors": ["Fight step is over (no eligible units, 12.04)"]}
	if int(unit.owner) != int(sel_11e.player):
		return {"valid": false, "errors": ["Not your selection (Player %d picks, 12.04 %s step)" % [sel_11e.player, sel_11e.step]]}
	if not unit_id in sel_11e.candidates:
		return {"valid": false, "errors": ["Unit not eligible to fight in the %s step (12.04)" % sel_11e.step]}
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
	# 11e 12.02-12.03: the PileInMove template is authoritative — eligibility
	# incl. charge-survivor/overrun, pile-in target selection, base-contact
	# lock, and the started-engaged-pairs AFTER rule.
	return _validate_pile_in_11e(action)

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

	# 11e core rules (Fight — Select Melee Weapon): "you must select one melee
	# weapon that model has" — each model fights with ONE melee weapon per
	# activation; [EXTRA ATTACKS] weapons are used IN ADDITION and are exempt.
	var conflicting_weapon = _find_one_weapon_rule_conflict(weapon_id, action.get("attacking_models", []))
	if conflicting_weapon != "":
		errors.append("Each model fights with only ONE melee weapon per activation — '%s' is already assigned for these models ([EXTRA ATTACKS] weapons are the exception)" % conflicting_weapon)

	# Per-model fight eligibility: each model in `attacking_models` must be in engagement range,
	# OR in base-to-base contact with a friendly model that is in base contact with an enemy
	# (10e: only models satisfying one of those criteria can fight). RulesEngine returns the
	# eligible model indices for the unit; validate every requested attacker is eligible.
	var attacking_models = action.get("attacking_models", [])
	if not attacking_models.is_empty():
		var eligible_indices = RulesEngine.get_eligible_melee_model_indices(unit, game_state_snapshot)
		var unit_models = unit.get("models", [])
		var eligible_ids: Array = []  # mirror of eligible indices as model_id strings
		for idx in eligible_indices:
			if idx >= 0 and idx < unit_models.size():
				var mid = unit_models[idx].get("id", "")
				if mid != "":
					eligible_ids.append(str(mid))
		for entry in attacking_models:
			var entry_str = str(entry)
			# Treat the entry as either a model_id ("m1") or an index ("0").
			var matched = false
			if entry_str in eligible_ids:
				matched = true
			elif entry_str.is_valid_int():
				var idx = entry_str.to_int()
				if idx in eligible_indices:
					matched = true
			if not matched:
				errors.append("Model %s is not eligible to fight (not in engagement range and not in base-to-base contact with a friendly model that is)" % entry_str)
				break

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
	# 11e 12.07-12.08: the ConsolidationMove template is authoritative —
	# mandatory mode selection ongoing/engaging/objective + per-mode
	# movement + AFTER conditions.
	return _validate_consolidate_11e(action)

func _can_unit_reach_engagement_range(unit: Dictionary, consol_dist: float = 3.0) -> bool:
	"""Check if it's POSSIBLE for unit to reach engagement range within consolidation distance.
	This means: is ANY enemy model within (consol_dist + 1") of ANY friendly model?
	(consolidation movement + 1" engagement range)"""
	var max_reach = consol_dist + 1.0  # consolidation distance + engagement range
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

				# Check if within reach (consolidation dist + 1" engagement) using shape-aware edge-to-edge
				var distance = Measurement.model_to_model_distance_inches(model, enemy_model)
				if distance <= max_reach:
					return true

	return false

func _validate_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var errors = []

	# 11e: the sequencer governs order — SKIP_UNIT is valid for the active
	# fighter (aborting its activation) or any unit still owed a fight.
	if sequencer_11e == null:
		return {"valid": false, "errors": ["Fight sequencer not initialized"]}
	if unit_id == active_fighter_id or sequencer_11e.eligible_to_fight(unit_id, GameState.state):
		return {"valid": true, "errors": []}
	errors.append("Unit %s has no fight to skip" % unit_id)
	return {"valid": false, "errors": errors}

# Action processing methods
func _process_select_fighter(action: Dictionary) -> Dictionary:
	active_fighter_id = action.unit_id

	# 12.04: commit the selection in the sequencer and surface the
	# available fight types (NORMAL 12.05 / OVERRUN 12.06).
	var fight_types_11e: Array = []
	if sequencer_11e != null:
		var ft = sequencer_11e.select_to_fight(active_fighter_id, GameState.state)
		fight_types_11e = ft.fight_types
		log_phase_message("[11e] %s selected to fight — types: %s" % [active_fighter_id, str(fight_types_11e)])
		# 12.08 stamps stay cumulative: positions have settled since the
		# last activation, so re-stamp anything that became eligible.
		_stamp_fight_eligibility_11e()

	log_phase_message("Player %d selects %s to fight" % [
		current_selecting_player,
		get_unit(active_fighter_id).get("meta", {}).get("name", active_fighter_id)
	])

	# TRY DAT BUTTON! (Dread Mob): roll the Button Effect when a Mek / Orks
	# Walker / Grots Vehicle unit is selected to fight.
	var fam_tdb = get_node_or_null("/root/FactionAbilityManager")
	if fam_tdb:
		fam_tdb.process_try_dat_button(active_fighter_id, "melee")

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

	# Apply movements (if any provided). Keys may address the unit's own
	# models or an attached character's ("char_unit:key") — 19.03: the whole
	# Attached unit piles in as one unit in one move.
	for model_id in movements:
		var route = _fight_split_move_key(unit_id, model_id)
		var route_index = _fight_model_index_for_key(get_unit(route.unit_id).get("models", []), route.model_key)
		if route_index < 0:
			log_phase_message("PILE_IN: movement key %s did not resolve to a model — skipped" % str(model_id))
			continue
		var new_pos = movements[model_id]
		changes.append({
			"op": "set",
			"path": "units.%s.models.%d.position" % [route.unit_id, route_index],
			"value": {"x": new_pos.x, "y": new_pos.y}
		})

	# Apply pivots (new facings) for any non-circular bases that rotated
	var rotations = _fight_rotations_from_action(action)
	for model_id in rotations:
		var rot_route = _fight_split_move_key(unit_id, model_id)
		var rot_index = _fight_model_index_for_key(get_unit(rot_route.unit_id).get("models", []), rot_route.model_key)
		if rot_index < 0:
			continue
		changes.append({
			"op": "set",
			"path": "units.%s.models.%d.rotation" % [rot_route.unit_id, rot_index],
			"value": float(rotations[model_id])
		})

	emit_signal("pile_in_preview", unit_id, movements)
	units_that_piled_in[unit_id] = true
	# The attached characters' one pile-in move is spent with their
	# bodyguard's — they are the same Attached unit (19.03).
	for char_id in _fight_attached_char_ids(unit_id):
		units_that_piled_in[char_id] = true
	log_phase_message("Unit %s piled in" % unit_id)

	# 11e 12.02: a move in the global Pile In step — apply now (idempotent
	# re-apply, same pattern as the Consolidate step) so newly-engaged
	# enemies become fight-eligible, then continue the step.
	if pile_in_step_11e == PileInStep11e.ACTIVE:
		if not changes.is_empty():
			PhaseManager.apply_state_changes(changes)
		_stamp_fight_eligibility_11e()
		return _advance_pile_in_step_11e(create_result(true, changes))

	# 11e 12.06: the Overrun fight's additional pile-in — the grant is
	# used up; apply the move so attack targets reflect the new engagement.
	if unit_id == overrun_pile_in_unit_11e:
		overrun_pile_in_unit_11e = ""
		if not changes.is_empty():
			PhaseManager.apply_state_changes(changes)
		_stamp_fight_eligibility_11e()

	# After pile-in, request attack assignment
	return _request_attack_assignment(unit_id, create_result(true, changes))

# Ask the active fighter's player to assign melee attacks (signal for the
# local UI + trigger metadata for the NetworkManager client re-emit).
func _request_attack_assignment(unit_id: String, result: Dictionary) -> Dictionary:
	# Movement diffs still pending in the result (the legacy per-activation
	# pile-in path returns them without applying) must land before
	# engagement is measured — execute_action's re-apply is idempotent
	# (set ops), same pattern as _finish_fight_activation_11e.
	var pending_changes = result.get("changes", [])
	if pending_changes is Array and not pending_changes.is_empty():
		PhaseManager.apply_state_changes(pending_changes)
	var targets = _get_eligible_melee_targets(unit_id)
	if targets.is_empty():
		# No enemy within Engagement Range — e.g. an OVERRUN fight (12.06)
		# whose pile-in could not reach, or the last engaged enemy died
		# mid-activation (Dread Foe / Deadly Demise). Making Attacks needs a
		# target in ER, so the fight ends with no attacks. Opening the
		# assignment dialog here soft-locked the game: nothing to assign,
		# no way to skip the activation.
		var _naa_unit = get_unit(unit_id)
		var _naa_name = _naa_unit.get("meta", {}).get("name", unit_id)
		var _naa_owner = int(_naa_unit.get("owner", get_current_player()))
		log_phase_message("[11e] %s has no enemies within Engagement Range after its fight moves — no attacks possible, activation ends" % unit_id)
		GameEventLog.add_combat_result("P%d: %s — no enemies in engagement range, fight ends without attacks" % [_naa_owner, _naa_name])
		return _finish_fight_activation_11e(result)
	emit_signal("attack_assignment_required", unit_id, targets)
	result["trigger_attack_assignment"] = true
	result["attack_unit_id"] = unit_id
	result["attack_targets"] = targets
	return result

# 11e core rules (Fight — Select Melee Weapon): a model makes its attacks with
# ONE selected melee weapon; [EXTRA ATTACKS] weapons are used in addition.
# Returns the already-pending regular weapon that the new assignment collides
# with, or "" when the assignment is legal. Two assignments collide when both
# are regular (non-Extra-Attacks) melee weapons and their model sets overlap —
# an empty attacking_models list means "all eligible models" and overlaps
# everything.
func _find_one_weapon_rule_conflict(weapon_id: String, attacking_models: Array) -> String:
	if RulesEngine.has_extra_attacks(weapon_id, game_state_snapshot):
		return ""
	var new_models = _normalize_model_refs(attacking_models)
	for pending in pending_attacks:
		var pending_weapon = str(pending.get("weapon", ""))
		if pending_weapon == "":
			continue
		if RulesEngine.has_extra_attacks(pending_weapon, game_state_snapshot):
			continue
		var pending_models = _normalize_model_refs(pending.get("models", []))
		if new_models.is_empty() or pending_models.is_empty():
			return pending_weapon
		for m in new_models:
			if m in pending_models:
				return pending_weapon
	return ""

# Assignments reference models either as index strings ("0") or model-id
# strings ("m0"/"m1"); strip the "m" prefix so overlap checks compare like
# with like regardless of which convention the caller used.
func _normalize_model_refs(models: Array) -> Array:
	var out: Array = []
	for entry in models:
		var s = str(entry)
		if s.begins_with("m") and s.substr(1).is_valid_int():
			s = s.substr(1)
		out.append(s)
	return out

func _process_assign_attacks(action: Dictionary) -> Dictionary:
	# Mirror ShootingPhase weapon assignment pattern
	var unit_id = action.get("unit_id", "")
	var target_id = action.get("target_id", "")
	var weapon_id = action.get("weapon_id", "")

	# One-weapon rule safety net: BATCH_FIGHT_ACTIONS and networked paths skip
	# per-sub-action validation, so re-check here. Drop the extra weapon and
	# keep the batch alive (the first assigned weapon wins) instead of failing
	# the whole atomic batch mid-flight.
	var conflicting_weapon = _find_one_weapon_rule_conflict(weapon_id, action.get("attacking_models", []))
	if conflicting_weapon != "":
		log_phase_message("REJECTED assignment %s → %s: each model fights with only ONE melee weapon per activation ('%s' already assigned)" % [weapon_id, target_id, conflicting_weapon])
		DebugLogger.warn(str("[FightPhase] One-weapon rule: dropped %s for %s — '%s' already assigned" % [weapon_id, unit_id, conflicting_weapon]))
		return create_result(true, [])

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

	# VERBOSE COMBAT LOG: Emit combat header BEFORE resolution so dice display in real-time
	var _rd_fighter_unit = game_state_snapshot.get("units", {}).get(active_fighter_id, {})
	var _rd_fighter_name = _rd_fighter_unit.get("meta", {}).get("name", active_fighter_id)
	var _rd_target_names = []
	for _rd_assignment in confirmed_attacks:
		var _rd_tid = _rd_assignment.get("target", "")
		var _rd_target_unit = game_state_snapshot.get("units", {}).get(_rd_tid, {})
		var _rd_tname = _rd_target_unit.get("meta", {}).get("name", _rd_tid)
		if _rd_tname not in _rd_target_names:
			_rd_target_names.append(_rd_tname)
	GameEventLog.add_combat_header("P%d: %s fights %s" % [get_current_player(), _rd_fighter_name, ", ".join(_rd_target_names)])

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

	# DEFENDER CONTROL: a human defender rolls their own melee saves through
	# the interactive overlay by default. The auto-allocate-wounds setting
	# (now default OFF) lets a LOCAL player delegate allocation to the
	# computer; in networked play the remote defender always gets control —
	# the attacker's machine settings must never take the defender's dice.
	# (null SettingsService only happens in stripped headless harnesses —
	# treat it as auto so engine-level tests keep one-shot resolution.)
	var _ss = get_node_or_null("/root/SettingsService")
	var _auto_alloc_11e: bool = _ss == null or _ss.get_auto_allocate_wounds()
	if NetworkManager.is_networked():
		_auto_alloc_11e = false

	# STAGED FIGHT: in non-networked play a HUMAN attacker resolves weapon by
	# weapon with pauses after the hit roll and the wound roll (Command Re-roll
	# windows) — mirrors ShootingPhase's sequential_staged mode. AI attackers,
	# networked games and explicit fast_roll keep the one-shot paths below.
	var interactive_saves = defender_is_human and not _auto_alloc_11e
	if _should_stage_fight(action):
		return _staged_fight_begin(interactive_saves)

	if interactive_saves:
		# P0-58: Interactive path — resolve hits+wounds only, then let defender allocate wounds
		return _process_roll_dice_interactive(melee_action)
	else:
		# AI/auto-resolve path — full resolution (11e allocation at edition >= 11)
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
	# Issue #329: honor melee_action.payload.rng_seed
	var rdi_seed: int = melee_action.get("payload", {}).get("rng_seed", -1)
	var rng_service = RulesEngine.RNGService.new(rdi_seed)
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
		DebugLogger.info("[FightPhase] P0-58: No wounds caused in interactive melee — skipping saves")
		# Emit resolution signals
		for assignment in confirmed_attacks:
			emit_signal("attacks_resolved", active_fighter_id, assignment.get("target", ""), result)
			emit_signal("fight_resolved", active_fighter_id, result)
		confirmed_attacks.clear()
		log_phase_message("Melee combat resolved for %s (no wounds)" % active_fighter_id)

		var final_result = create_result(true, result.get("diffs", []))
		final_result["log_text"] = result.get("log_text", "")
		if result.has("dice"):
			final_result["dice"] = result["dice"]
		# 11e: no per-fighter consolidation — the activation ends when the
		# attacks are resolved (consolidation is the global 12.07 step).
		return _finish_fight_activation_11e(final_result)

	# Wounds caused — store state and emit saves_required for WoundAllocationOverlay
	pending_melee_save_data = save_data_list
	pending_melee_hit_wound_result = result
	awaiting_melee_saves = true

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P0-58: MELEE SAVES_REQUIRED EMISSION")
	DebugLogger.info("║ Source: FightPhase._process_roll_dice_interactive")
	DebugLogger.info(str("║ Save data list size: %d" % save_data_list.size()))
	for i in range(save_data_list.size()):
		var sd = save_data_list[i]
		DebugLogger.info(str("║   [%d] Target: %s, Weapon: %s, Wounds: %d" % [i, sd.get("target_unit_name", "?"), sd.get("weapon_name", "?"), sd.get("wounds_to_save", 0)]))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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
	# Issue #329: honor melee_action.payload.rng_seed
	var rda_seed: int = melee_action.get("payload", {}).get("rng_seed", -1)
	var rng_service = RulesEngine.RNGService.new(rda_seed)
	var result = RulesEngine.resolve_melee_attacks(melee_action, game_state_snapshot, rng_service)

	# Debug logging for state changes
	if result.has("diffs") and not result.diffs.is_empty():
		DebugLogger.info(str("[FightPhase] RulesEngine returned %d state changes" % result.diffs.size()))
		for diff in result.diffs:
			DebugLogger.info(str("  - %s: %s = %s" % [diff.op, diff.path, diff.value]))

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

	var final_result = create_result(true, result.get("diffs", []))
	final_result["log_text"] = result.get("log_text", "")

	# Preserve dice and save_data_list from combat resolution
	if result.has("dice"):
		final_result["dice"] = result["dice"]
	if result.has("save_data_list"):
		final_result["save_data_list"] = result["save_data_list"]

	# 11e: no per-fighter consolidation — the activation ends when the
	# attacks are resolved (consolidation is the global 12.07 step).
	return _finish_fight_activation_11e(final_result)

# =============================================================================
# STAGED FIGHT RESOLUTION (mirrors ShootingPhase's sequential_staged mode)
#
# In non-networked play a HUMAN attacker resolves melee weapon by weapon:
#   ROLL_DICE            -> roll hits for weapon 1, PAUSE (fight_stage_paused "hits")
#   CONTINUE_TO_WOUNDS   -> roll wounds, PAUSE (fight_stage_paused "wounds")
#   CONTINUE_TO_SAVES    -> saving throws (auto-allocate or WoundAllocationOverlay),
#                           then next weapon's hits or finish the activation
#   USE_FIGHT_REROLL     -> Command Re-roll one hit/wound die at either pause
#
# Networked games and AI attackers keep the one-shot paths above (mirrors how
# staged shooting / Command Re-roll are host/SP only elsewhere).
# =============================================================================

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

func _should_stage_fight(action: Dictionary) -> bool:
	if action.get("payload", {}).get("fast_roll", false):
		return false
	if NetworkManager.is_networked():
		return false
	# Only stage for human attackers — AI activations must not pause.
	var fighter_owner = get_unit(active_fighter_id).get("owner", get_current_player())
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.get("enabled") and ai_player.has_method("is_ai_player") and ai_player.is_ai_player(fighter_owner):
		return false
	return true

func _fight_reroll_available() -> bool:
	# A staged hit/wound Command Re-roll is offered when the ATTACKING player has
	# not already used Command Re-roll this phase and can pay the CP.
	var sm = get_node_or_null("/root/StratagemManager")
	if sm == null or not sm.has_method("is_command_reroll_available"):
		return false
	var fighter_owner = get_unit(active_fighter_id).get("owner", get_current_player())
	var chk = sm.is_command_reroll_available(fighter_owner)
	return chk.get("available", false)

func _staged_fight_begin(interactive_saves: bool) -> Dictionary:
	staged_fight_state = {
		"assignments": confirmed_attacks.duplicate(true),
		"current_index": 0,
		"stage": "",
		"hit_context": {},
		"wound_result": {},
		"wound_context": {},
		"save_data_list": [],
		"interactive_saves": interactive_saves,
		"total_casualties": 0,
		"completed": []
	}
	log_phase_message("Starting staged fight resolution (%d weapon assignment(s))" % staged_fight_state.assignments.size())
	return _staged_fight_roll_hits([])

func _staged_fight_target_destroyed(target_id: String) -> bool:
	var unit = get_unit(target_id)
	if unit.is_empty():
		return true
	for model in unit.get("models", []):
		if model.get("alive", true):
			return false
	return true

func _staged_fight_roll_hits(carry_changes: Array) -> Dictionary:
	var assignments = staged_fight_state.get("assignments", [])
	var idx = int(staged_fight_state.get("current_index", 0))

	# Skip assignments whose target has been destroyed by an earlier weapon.
	while idx < assignments.size():
		var target_id = assignments[idx].get("target", "")
		if target_id != "" and not _staged_fight_target_destroyed(target_id):
			break
		var skipped_weapon = RulesEngine.get_weapon_profile(assignments[idx].get("weapon", ""), game_state_snapshot).get("name", assignments[idx].get("weapon", ""))
		log_phase_message("Skipped %s — target destroyed" % skipped_weapon)
		emit_signal("dice_rolled", {"context": "weapon_progress",
			"message": "Skipped %s — target destroyed" % skipped_weapon})
		idx += 1
		staged_fight_state.current_index = idx

	if idx >= assignments.size():
		return _staged_fight_finish(carry_changes)

	var assignment = assignments[idx]
	var weapon_id = assignment.get("weapon", "")
	var target_id = assignment.get("target", "")
	var weapon_name = RulesEngine.get_weapon_profile(weapon_id, game_state_snapshot).get("name", weapon_id)
	var target_name = get_unit(target_id).get("meta", {}).get("name", target_id)
	var fighter_name = get_unit(active_fighter_id).get("meta", {}).get("name", active_fighter_id)

	GameEventLog.add_combat_header("P%d: %s → %s with %s (weapon %d/%d)" % [
		get_unit(active_fighter_id).get("owner", get_current_player()), fighter_name, target_name, weapon_name,
		idx + 1, assignments.size()])

	var progress = {
		"context": "weapon_progress",
		"message": "Weapon %d of %d — %s → %s" % [idx + 1, assignments.size(), weapon_name, target_name],
		"weapon_name": weapon_name,
		"target_name": target_name,
		"current_index": idx,
		"total_weapons": assignments.size(),
		"stage": "hits"
	}
	emit_signal("dice_rolled", progress)

	var melee_action = {"type": "FIGHT", "actor_unit_id": active_fighter_id, "payload": {"assignments": [assignment]}}
	var rng = RulesEngine.make_rng()
	var hres = RulesEngine.resolve_melee_hits(melee_action, game_state_snapshot, rng)
	if not hres.get("success", false):
		return create_result(false, [], hres.get("log_text", "Melee hit resolution failed"))

	for db in hres.get("dice", []):
		dice_log.append(db)
		emit_signal("dice_rolled", db)
		if db.get("context", "") == "hit_roll_melee":
			_emit_melee_hit_detail(db)
	if hres.get("log_text", "") != "":
		log_phase_message(hres.get("log_text", ""))

	if hres.get("early_exit", false):
		# No eligible models / bad assignment — skip to the next weapon.
		staged_fight_state.current_index = idx + 1
		return _staged_fight_roll_hits(carry_changes)

	var hc = hres.get("hit_context", {})
	staged_fight_state.stage = "hits_pending"
	staged_fight_state.hit_context = hc
	staged_fight_state.wound_result = {}
	staged_fight_state.wound_context = {}
	staged_fight_state.save_data_list = []

	var can_reroll = _fight_reroll_available() and not hc.get("is_torrent", false) and not (hc.get("hit_rolls", []) as Array).is_empty()
	var pause_info = {
		"weapon_name": weapon_name,
		"target_name": target_name,
		"unit_name": fighter_name,
		"current_index": idx,
		"total_weapons": assignments.size(),
		"reroll_available": can_reroll,
		"hit_rolls": hc.get("hit_rolls", []),
		"modified_rolls": hc.get("modified_rolls", []),
		"hits": hc.get("hits", 0),
		"threshold": str(hc.get("ws", hc.get("bs", 4))) + "+"
	}
	emit_signal("fight_stage_paused", "hits", pause_info)
	log_phase_message("Weapon %d of %d hit roll complete — awaiting attacker to continue to wound roll" % [idx + 1, assignments.size()])
	return create_result(true, carry_changes, "", {
		"staged_pause": "hits",
		"current_weapon_index": idx,
		"total_weapons": assignments.size(),
		"weapon_name": weapon_name,
		"target_name": target_name,
		"reroll_available": can_reroll,
		"hit_rolls": hc.get("hit_rolls", []),
		"hits": hc.get("hits", 0),
		"dice": hres.get("dice", [])
	})

func _staged_fight_continue_to_wounds() -> Dictionary:
	if staged_fight_state.get("stage", "") != "hits_pending":
		return create_result(false, [], "Not awaiting continue-to-wounds")
	var hc = staged_fight_state.get("hit_context", {})
	var idx = int(staged_fight_state.get("current_index", 0))
	var assignments = staged_fight_state.get("assignments", [])
	var interactive_saves = staged_fight_state.get("interactive_saves", false)

	var rng = RulesEngine.make_rng()
	# Hold Still MW ride on the interactive save_data; the auto tail rolls its own.
	var wres = RulesEngine.resolve_melee_wounds(hc, game_state_snapshot, rng, interactive_saves)

	for db in wres.get("dice", []):
		dice_log.append(db)
		emit_signal("dice_rolled", db)
		if db.get("context", "") == "wound_roll_melee":
			_emit_melee_wound_detail(db)
	if wres.get("log_text", "") != "":
		log_phase_message(wres.get("log_text", ""))

	staged_fight_state.wound_result = wres.get("wound_result", {})
	staged_fight_state.wound_context = wres.get("wound_context", {})
	staged_fight_state.save_data_list = wres.get("save_data_list", [])

	if wres.get("no_wounds", false):
		# No wounds — this weapon is done; hazardous check, then next weapon.
		staged_fight_state.stage = ""
		return _staged_fight_assignment_complete([])

	staged_fight_state.stage = "wounds_pending"
	var wc = wres.get("wound_context", {})
	var can_reroll = _fight_reroll_available() and not (wc.get("wound_evals", []) as Array).is_empty()
	var wounds = 0
	var sdl = wres.get("save_data_list", [])
	if not sdl.is_empty():
		wounds = int(sdl[0].get("wounds_to_save", wres.get("wounds_caused", 0)))
	else:
		wounds = int(wres.get("wounds_caused", 0))
	var pause_info = {
		"current_index": idx,
		"total_weapons": assignments.size(),
		"reroll_available": can_reroll,
		"wound_rolls": wc.get("wound_rolls", []),
		"wounds": wounds,
		"target_name": get_unit(assignments[idx].get("target", "")).get("meta", {}).get("name", ""),
		"threshold": str(wc.get("wound_threshold", 4)) + "+"
	}
	emit_signal("fight_stage_paused", "wounds", pause_info)
	log_phase_message("Weapon %d of %d wound roll complete — awaiting attacker to continue to saving throws" % [idx + 1, assignments.size()])
	return create_result(true, [], "", {
		"staged_pause": "wounds",
		"current_weapon_index": idx,
		"total_weapons": assignments.size(),
		"reroll_available": can_reroll,
		"wounds": wounds,
		"dice": wres.get("dice", [])
	})

func _staged_fight_continue_to_saves() -> Dictionary:
	if staged_fight_state.get("stage", "") != "wounds_pending":
		return create_result(false, [], "Not awaiting continue-to-saves")
	var hc = staged_fight_state.get("hit_context", {})
	var wound_result = staged_fight_state.get("wound_result", {})
	var save_data_list = staged_fight_state.get("save_data_list", [])

	if staged_fight_state.get("interactive_saves", false) and not save_data_list.is_empty():
		# Defender allocates wounds via WoundAllocationOverlay; the staged
		# sequence resumes in _process_apply_melee_saves.
		staged_fight_state.stage = "saves_pending"
		pending_melee_save_data = save_data_list
		pending_melee_hit_wound_result = {"diffs": [], "dice": []}
		awaiting_melee_saves = true
		emit_signal("saves_required", save_data_list)
		log_phase_message("Awaiting defender wound allocation for melee combat (staged)...")
		return create_result(true, [], "", {
			"awaiting_melee_saves": true,
			"save_data_list": save_data_list
		})

	# Auto-allocate: run the save/damage tail synchronously (rolls Hold Still
	# itself, exactly like the one-shot monolith path).
	var rng = RulesEngine.make_rng()
	var sres = RulesEngine.resolve_melee_saves_auto(hc, wound_result, game_state_snapshot, rng)
	var changes = sres.get("diffs", [])
	var save_blocks = []
	for db in sres.get("dice", []):
		dice_log.append(db)
		emit_signal("dice_rolled", db)
		save_blocks.append(db)
	if sres.get("log_text", "") != "":
		log_phase_message(sres.get("log_text", ""))

	var casualties = 0
	for diff in changes:
		if str(diff.get("path", "")).ends_with(".alive") and diff.get("value") == false:
			casualties += 1
	staged_fight_state.total_casualties = int(staged_fight_state.get("total_casualties", 0)) + casualties

	# Verbose save/FNP log lines (normalize save_roll_melee -> save_roll)
	for sb in save_blocks:
		var ctx = sb.get("context", "")
		if ctx == "save_roll_melee" or ctx == "save_roll" or ctx == "save":
			var nsb = sb.duplicate()
			nsb["context"] = "save_roll"
			_emit_melee_save_detail(nsb)
		elif ctx == "feel_no_pain":
			_emit_melee_fnp_detail(sb)
	if casualties > 0:
		var cas_label = "model" if casualties == 1 else "models"
		GameEventLog.add_combat_result("  Result: %d %s destroyed" % [casualties, cas_label])
	else:
		GameEventLog.add_combat_result("  Result: No models destroyed")

	staged_fight_state.stage = ""
	return _staged_fight_assignment_complete(changes)

# One weapon fully resolved (saves applied or no wounds) — run its Hazardous
# check, advance to the next weapon or finish the activation.
func _staged_fight_assignment_complete(changes: Array) -> Dictionary:
	var assignments = staged_fight_state.get("assignments", [])
	var idx = int(staged_fight_state.get("current_index", 0))
	if idx < assignments.size():
		var assignment = assignments[idx]
		var weapon_id = assignment.get("weapon", "")
		var fighter_unit = get_unit(active_fighter_id)
		if RulesEngine.is_hazardous_weapon(weapon_id, game_state_snapshot) \
				or fighter_unit.get("flags", {}).get("effect_grant_hazardous_melee", false):
			var models_that_fought = assignment.get("models", []).size()
			var rng = RulesEngine.make_rng()
			var hazard = RulesEngine.resolve_hazardous_check(active_fighter_id, weapon_id, models_that_fought, game_state_snapshot, rng)
			if hazard.get("hazardous_triggered", false):
				changes = changes + hazard.get("diffs", [])
			for db in hazard.get("dice", []):
				dice_log.append(db)
				emit_signal("dice_rolled", db)
			if hazard.get("log_text", "") != "":
				log_phase_message(hazard.get("log_text", ""))
		staged_fight_state.completed.append(assignment)
	staged_fight_state.current_index = idx + 1
	return _staged_fight_roll_hits(changes)

func _staged_fight_finish(changes: Array) -> Dictionary:
	var total_casualties = int(staged_fight_state.get("total_casualties", 0))
	var fighter_name = get_unit(active_fighter_id).get("meta", {}).get("name", active_fighter_id)
	var summary = {"success": true, "diffs": changes, "casualties": total_casualties}

	emit_signal("fight_stage_paused", "complete", {
		"unit_name": fighter_name,
		"casualties": total_casualties,
		"total_weapons": staged_fight_state.get("assignments", []).size()
	})

	# Emit resolution signals for each target (mirrors _process_roll_dice_auto)
	for assignment in staged_fight_state.get("assignments", []):
		emit_signal("attacks_resolved", active_fighter_id, assignment.get("target", ""), summary)
		emit_signal("fight_resolved", active_fighter_id, summary)

	staged_fight_state.clear()
	confirmed_attacks.clear()
	_trigger_unit_animation(active_fighter_id, "idle")
	log_phase_message("Melee combat resolved for %s (staged)" % active_fighter_id)

	var final_result = create_result(true, changes)
	final_result["log_text"] = "Melee combat resolved for %s" % fighter_name

	# 11e: no per-fighter consolidation — the activation ends when the
	# attacks are resolved (consolidation is the global 12.07 step).
	return _finish_fight_activation_11e(final_result)

func _process_use_fight_reroll(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var stage = str(payload.get("stage", ""))
	var die_index = int(payload.get("die_index", -1))
	var expected = "hits_pending" if stage == "hits" else ("wounds_pending" if stage == "wounds" else "")
	if expected == "" or staged_fight_state.get("stage", "") != expected:
		return create_result(false, [], "No re-roll available at this stage")

	# Spend the CP + record the once-per-phase Command Re-roll usage (attacker).
	var sm = get_node_or_null("/root/StratagemManager")
	if sm == null or not sm.has_method("execute_command_reroll"):
		return create_result(false, [], "Command Re-roll unavailable")
	var fighter_owner = get_unit(active_fighter_id).get("owner", get_current_player())
	var strat_result = sm.execute_command_reroll(fighter_owner, active_fighter_id, {"roll_type": stage + "_roll"})
	if not strat_result.get("success", false):
		return create_result(false, [], str(strat_result.get("reason", "Cannot use Command Re-roll")))

	var rng = RulesEngine.make_rng()
	if stage == "hits":
		var hc = staged_fight_state.get("hit_context", {})
		var rr = RulesEngine.reroll_hit_die(hc, die_index, rng)
		if not rr.get("success", false):
			return create_result(false, [], str(rr.get("error", "Re-roll failed")))
		emit_signal("dice_rolled", {"context": "reroll_note",
			"message": "Command Re-roll (1 CP): hit die %d → %d" % [rr.get("old_display", rr.get("old_value", 0)), rr.get("new_display", rr.get("new_value", 0))]})
		emit_signal("dice_rolled", rr.get("dice_block", {}))
		dice_log.append(rr.get("dice_block", {}))
		var uhc = rr.get("hit_context", {})
		staged_fight_state.hit_context = uhc
		emit_signal("fight_stage_paused", "hits", {
			"reroll_available": false,
			"hit_rolls": uhc.get("hit_rolls", []),
			"modified_rolls": uhc.get("modified_rolls", []),
			"hits": uhc.get("hits", 0)
		})
		return create_result(true, [], "", {
			"staged_pause": "hits", "reroll_used": true, "reroll_available": false,
			"dice_block": rr.get("dice_block", {}), "hits": uhc.get("hits", 0)
		})
	else:
		var wc = staged_fight_state.get("wound_context", {})
		var rr = RulesEngine.reroll_wound_die(wc, die_index, game_state_snapshot, rng)
		if not rr.get("success", false):
			return create_result(false, [], str(rr.get("error", "Re-roll failed")))
		var new_wounds = int(rr.get("wounds_caused", 0))
		# Keep the wound_result tallies in sync — the auto save tail reads them.
		var wres = staged_fight_state.get("wound_result", {})
		wres["wounds_caused"] = new_wounds
		wres["critical_wound_count"] = rr.get("critical_wounds", 0)
		wres["regular_wound_count"] = rr.get("regular_wounds", 0)
		wres["all_critical_wound_count"] = rr.get("all_critical_wounds", 0)
		# Rebuild the pending save list (may now have more/fewer wounds).
		if new_wounds > 0:
			var sd = rr.get("save_data", {})
			if staged_fight_state.get("interactive_saves", false):
				var hs_mw = RulesEngine.roll_hold_still_mortal_wounds(
					staged_fight_state.get("hit_context", {}), int(rr.get("all_critical_wounds", 0)), rng)
				if hs_mw > 0:
					sd["hold_still_mortal_wounds"] = hs_mw
			staged_fight_state.save_data_list = [sd]
		else:
			staged_fight_state.save_data_list = []
		emit_signal("dice_rolled", {"context": "reroll_note",
			"message": "Command Re-roll (1 CP): wound die %d → %d" % [rr.get("old_value", 0), rr.get("new_value", 0)]})
		emit_signal("dice_rolled", rr.get("dice_block", {}))
		dice_log.append(rr.get("dice_block", {}))
		emit_signal("fight_stage_paused", "wounds", {
			"reroll_available": false,
			"wound_rolls": rr.get("wound_context", {}).get("wound_rolls", []),
			"wounds": new_wounds
		})
		return create_result(true, [], "", {
			"staged_pause": "wounds", "reroll_used": true, "reroll_available": false,
			"dice_block": rr.get("dice_block", {}), "wounds": new_wounds
		})

func _validate_staged_fight_continue(action: Dictionary) -> Dictionary:
	var t = action.get("type", "")
	if t == "CONTINUE_TO_WOUNDS":
		if staged_fight_state.get("stage", "") != "hits_pending":
			return {"valid": false, "errors": ["Not awaiting continue-to-wounds"]}
	elif t == "CONTINUE_TO_SAVES":
		if staged_fight_state.get("stage", "") != "wounds_pending":
			return {"valid": false, "errors": ["Not awaiting continue-to-saves"]}
	elif t == "USE_FIGHT_REROLL":
		var stage = str(action.get("payload", {}).get("stage", ""))
		var expected = "hits_pending" if stage == "hits" else ("wounds_pending" if stage == "wounds" else "")
		if expected == "" or staged_fight_state.get("stage", "") != expected:
			return {"valid": false, "errors": ["No re-roll available at this stage"]}
	return {"valid": true, "errors": []}

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

	DebugLogger.info(str("[FightPhase] Processing BATCH_FIGHT_ACTIONS with %d sub-actions" % sub_actions.size()))

	for i in range(sub_actions.size()):
		var sub = sub_actions[i]
		# Copy player/timestamp from parent action if not present
		if not sub.has("player"):
			sub["player"] = action.get("player", 0)
		if not sub.has("timestamp"):
			sub["timestamp"] = action.get("timestamp", 0)

		DebugLogger.info(str("[FightPhase] Batch sub-action %d: %s" % [i, sub.get("type", "")]))
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

	DebugLogger.info("[FightPhase] BATCH_FIGHT_ACTIONS completed successfully")
	return last_result

# P0-58: Validate APPLY_MELEE_SAVES action
func _validate_apply_melee_saves(action: Dictionary) -> Dictionary:
	if not awaiting_melee_saves:
		return {"valid": false, "errors": ["Not awaiting melee saves"]}
	return {"valid": true}

# Defender-side save Command Re-roll (1 CP): the AllocationGroupOverlay
# re-rolls one save die locally and stamps `command_reroll` on its summary;
# the phase deducts the CP + records stratagem usage authoritatively here.
func _apply_defender_save_command_reroll(save_result_summary: Dictionary, save_data: Dictionary) -> Array:
	var cr = save_result_summary.get("command_reroll", {})
	if not cr.get("used", false):
		return []
	var reroll_player = int(cr.get("player", 0))
	var target_unit_id = str(save_data.get("target_unit_id", save_result_summary.get("target_unit_id", "")))
	var target_name = get_unit(target_unit_id).get("meta", {}).get("name", target_unit_id)
	var result = StratagemManager.execute_command_reroll(reroll_player, target_unit_id, {
		"roll_type": "save_roll",
		"original_rolls": [int(cr.get("original", 0))],
		"unit_name": target_name
	})
	if not result.get("success", false):
		push_warning("FightPhase: defender save Command Re-roll could not be paid: %s" % str(result.get("error", "unknown")))
		log_phase_message("⚠ Save Command Re-roll by player %d could not be paid (%s)" % [reroll_player, str(result.get("error", ""))])
		return []
	log_phase_message("Player %d used COMMAND RE-ROLL on a save for %s (%d → %d)" % [
		reroll_player, target_name, int(cr.get("original", 0)), int(cr.get("new", 0))])
	return result.get("diffs", [])

# P0-58: Process APPLY_MELEE_SAVES — apply damage from interactive wound allocation
func _process_apply_melee_saves(action: Dictionary) -> Dictionary:
	"""Process save results from WoundAllocationOverlay and apply melee damage."""
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P0-58: APPLY_MELEE_SAVES PROCESSING START")
	DebugLogger.info(str("║ Timestamp: ", Time.get_ticks_msec()))
	DebugLogger.info(str("║ pending_melee_save_data.size(): ", pending_melee_save_data.size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

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

		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info(str("║ P0-58: PROCESSING MELEE SAVE RESULT %d" % i))
		DebugLogger.info(str("║ Target: %s" % target_name))
		DebugLogger.info(str("║ save_result_summary keys: ", save_result_summary.keys()))
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

		# ISS-045 (11e): the AllocationGroupOverlay resolved the whole batch
		# (05.03-05.04) on the defending peer — apply its idempotent set-diffs
		# directly instead of the 10e per-wound conversion below.
		if save_result_summary.get("is_allocation_11e", false):
			all_diffs.append_array(save_result_summary.get("diffs", []))
			all_diffs.append_array(_apply_defender_save_command_reroll(save_result_summary, save_data))
			var alloc_casualties = int(save_result_summary.get("casualties", 0))
			total_casualties += alloc_casualties
			if alloc_casualties > 0 and str(target_unit_id) != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id)
			for dice_block in save_result_summary.get("dice", []):
				save_dice_blocks.append(dice_block)
				dice_log.append(dice_block)
				emit_signal("dice_rolled", dice_block)
			log_phase_message("Melee saves for %s: %d saved, %d failed → %d casualties (11e allocation)" % [
				target_name,
				save_result_summary.get("saves_passed", 0),
				save_result_summary.get("saves_failed", 0),
				alloc_casualties])
			continue

		# Convert allocation_history to save_results format if needed
		var save_results = []
		if save_result_summary.has("save_results"):
			save_results = save_result_summary.save_results
		elif save_result_summary.has("allocation_history"):
			DebugLogger.info("[FightPhase] P0-58: Converting allocation_history to save_results format")
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
			DebugLogger.info(str("[FightPhase] P0-58: Devastating wounds: %d damage" % devastating_damage))

		# Apply damage using RulesEngine
		if not save_results.is_empty():
			# Issue #329: honor action.payload.rng_seed
			var ams_seed: int = action.get("payload", {}).get("rng_seed", -1)
			var fnp_rng = RulesEngine.RNGService.new(ams_seed)
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
		var _cas_label = "model" if total_casualties == 1 else "models"
		GameEventLog.add_combat_result("  Result: %d %s destroyed" % [total_casualties, _cas_label])
	else:
		GameEventLog.add_combat_result("  Result: No models destroyed")

	# OA-19: Apply Hold Still and Say 'Aargh!' mortal wounds after saves
	for sd in pending_melee_save_data:
		var hs_mw = sd.get("hold_still_mortal_wounds", 0)
		if hs_mw > 0:
			var hs_target_id = sd.get("target_unit_id", "")
			var hs_target_name = sd.get("target_unit_name", "Unknown")
			DebugLogger.info(str("[FightPhase] OA-19: HOLD STILL AND SAY 'AARGH!' — applying %d mortal wounds to %s" % [hs_mw, hs_target_name]))
			# Issue #329: honor action.payload.rng_seed
			var hs_seed: int = action.get("payload", {}).get("rng_seed", -1)
			var hs_rng = RulesEngine.RNGService.new(hs_seed)
			var hs_result = RulesEngine.apply_mortal_wounds(hs_target_id, hs_mw, game_state_snapshot, hs_rng)
			all_diffs.append_array(hs_result.get("diffs", []))
			var hs_casualties = hs_result.get("casualties", 0)
			total_casualties += hs_casualties
			GameEventLog.add_combat_result("  Hold Still and Say 'Aargh!': %d mortal wounds → %s (%d slain)" % [hs_mw, hs_target_name, hs_casualties])
			log_phase_message("Hold Still and Say 'Aargh!': %d mortal wounds → %s (%d casualties)" % [hs_mw, hs_target_name, hs_casualties])

	# STAGED FIGHT: these saves belong to ONE weapon of a staged sequence —
	# advance to the next weapon (or finish the activation) instead of ending
	# the activation here.
	if not staged_fight_state.is_empty() and staged_fight_state.get("stage", "") == "saves_pending":
		awaiting_melee_saves = false
		pending_melee_save_data.clear()
		pending_melee_hit_wound_result.clear()
		staged_fight_state.total_casualties = int(staged_fight_state.get("total_casualties", 0)) + total_casualties
		staged_fight_state.stage = ""
		log_phase_message("Staged melee saves applied (%d casualties) — continuing sequence" % total_casualties)
		return _staged_fight_assignment_complete(all_diffs)

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

	# Build final result
	var final_result = create_result(true, all_diffs)
	final_result["log_text"] = "Melee saves applied — %d casualties" % total_casualties
	final_result["dice"] = save_dice_blocks

	DebugLogger.info(str("[FightPhase] P0-58: APPLY_MELEE_SAVES complete — %d casualties, %d diffs" % [total_casualties, all_diffs.size()]))

	# 11e: no per-fighter consolidation — the activation ends when the
	# attacks are resolved (consolidation is the global 12.07 step).
	return _finish_fight_activation_11e(final_result)

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
		var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))

		if assigned_weapon_ids.has(weapon_id):
			DebugLogger.info(str("[FightPhase] T3-3: Extra Attacks weapon '%s' already assigned, skipping" % weapon_name))
			continue

		if default_target.is_empty():
			DebugLogger.info(str("[FightPhase] T3-3: No target available for Extra Attacks weapon '%s'" % weapon_name))
			continue

		confirmed_attacks.append({
			"attacker": active_fighter_id,
			"weapon": weapon_id,
			"target": default_target
		})
		DebugLogger.info(str("[FightPhase] T3-3: Auto-injected Extra Attacks weapon '%s' → '%s'" % [weapon_name, default_target]))

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
		# Issue #329: route through RNGService so RNGService.test_mode_seed applies for deterministic UI snapshots
		var _mh_rng = RulesEngine.make_rng()
		var config = {
			"trials": 1000,  # Reduced for real-time predictions
			"attackers": [attacker_config],
			"defender": {"unit_id": target_id},
			"rule_toggles": rule_toggles,
			"phase": "fight",
			"seed": _mh_rng.randi()
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
	DebugLogger.info(str("[FightPhase] Mathhammer prediction: %s" % prediction_text))

	# Display predictions via dice_rolled signal (like shooting phase)
	emit_signal("dice_rolled", {
		"context": "mathhammer_prediction",
		"message": prediction_text
	})

func _get_consolidation_distance(unit_id: String) -> float:
	"""OA-26: Returns the consolidation distance for a unit.
	Normally 3\", but 6\" for units with 'Drive-by Krumpin'' ability, and the
	numeric effect_consolidate_max flag (ALWAYS LOOKIN' FER A FIGHT,
	Squig-hide Tyres) overrides with its own cap when larger."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return 3.0
	var dist := 3.0
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is Dictionary:
			ability_name = ability.get("name", "")
		elif ability is String:
			ability_name = ability
		if ability_name == "Drive-by Krumpin'":
			log_phase_message("[OA-26] Drive-by Krumpin': Consolidation distance 6\" for %s" % unit_id)
			dist = 6.0
			break
	# Squig-hide Tyres (Kult of Speed): 6" consolidation for the bearer's unit
	if dist < 6.0 and FactionAbilityManager._unit_or_attached_has_enhancement(unit, "Squig-hide Tyres", GameState.state.get("units", {})):
		log_phase_message("Squig-hide Tyres: Consolidation distance 6\" for %s" % unit_id)
		dist = 6.0
	var flag_max = float(unit.get("flags", {}).get("effect_consolidate_max", 0.0))
	if flag_max > dist:
		log_phase_message("Consolidation distance %.0f\" for %s (effect_consolidate_max)" % [flag_max, unit_id])
		dist = flag_max
	return dist

# 11e: a unit's activation ends when its attacks are resolved — there is
# NO per-fighter consolidation (that is the global 12.07 step at the end
# of the phase). This performs the activation-completion bookkeeping that
# _process_consolidate performs at edition 10 (has_fought, Ka'tah clear,
# Counter-Offensive window, next-fighter handoff), then either offers the
# next fight selection or — when the Fight step is over — waits for
# END_FIGHT, or resumes the Consolidate step if a 12.08 forced fight just
# finished. Augments and returns the caller's final_result so the
# trigger_* metadata rides the same result NetworkManager broadcasts.
func _finish_fight_activation_11e(final_result: Dictionary) -> Dictionary:
	var unit_id = active_fighter_id
	var changes: Array = final_result.get("changes", [])

	# The attack-resolution diffs are normally applied by execute_action
	# AFTER process returns — but the next-selection / Counter-Offensive /
	# Consolidate-step decisions below must see the post-attack board
	# (casualties change eligibility). Apply them now; execute_action's
	# re-apply is idempotent (set ops), same pattern as Dread Foe.
	if not changes.is_empty():
		PhaseManager.apply_state_changes(changes)

	changes.append({
		"op": "set",
		"path": "units.%s.flags.has_fought" % unit_id,
		"value": true
	})
	final_result["changes"] = changes
	units_that_fought.append(unit_id)
	active_fighter_id = ""
	confirmed_attacks.clear()

	# The 12.06 overrun grant (if any) ends with the activation
	overrun_pile_in_unit_11e = ""
	var _of_unit = GameState.get_unit(unit_id)
	if not _of_unit.is_empty():
		_of_unit.get("flags", {}).erase("selected_for_overrun_fight")

	# Clear Martial Ka'tah stance — "active until the unit finishes attacking"
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr:
		faction_mgr.clear_katah_stance(unit_id)
		if game_state_snapshot.has("units") and game_state_snapshot.units.has(unit_id):
			var snap_flags = game_state_snapshot.units[unit_id].get("flags", {})
			snap_flags.erase("effect_sustained_hits")
			snap_flags.erase("effect_lethal_hits")
			snap_flags.erase("katah_stance")
			snap_flags.erase("katah_sustained_hits_value")

	# Units engaged mid-phase (pile-ins, overruns) become eligible to fight
	# — keep the 12.08 consolidation-eligibility stamps cumulative.
	_stamp_fight_eligibility_11e()

	# Counter-Offensive window: "after an enemy unit has fought"
	var fought_unit = get_unit(unit_id)
	var fought_unit_owner = int(fought_unit.get("owner", 0))
	var opponent_player = 2 if fought_unit_owner == 1 else 1
	var co_check = StratagemManager.is_counter_offensive_available(opponent_player)
	var co_eligible = []
	if co_check.available:
		co_eligible = StratagemManager.get_counter_offensive_eligible_units(
			opponent_player, units_that_fought, game_state_snapshot
		)
	if not co_eligible.is_empty():
		awaiting_counter_offensive = true
		counter_offensive_player = opponent_player
		log_phase_message("COUNTER-OFFENSIVE available for Player %d (%d eligible units)" % [opponent_player, co_eligible.size()])
		emit_signal("counter_offensive_opportunity", opponent_player, co_eligible)
		final_result["trigger_counter_offensive"] = true
		final_result["counter_offensive_player"] = opponent_player
		final_result["counter_offensive_eligible_units"] = co_eligible
		return final_result

	# Hand over to the next fighter selection (the sequencer decides).
	_switch_selecting_player()
	var dialog_data = _build_fight_selection_dialog_data()
	if not dialog_data.is_empty():
		emit_signal("fight_selection_required", dialog_data)
		final_result["trigger_fight_selection"] = true
		final_result["fight_selection_data"] = dialog_data
		return final_result

	# Nobody left to fight. If this was a fight forced by an Engaging
	# Consolidation (12.08), resume the Consolidate step; otherwise the
	# Fight step is over and the phase waits for END_FIGHT.
	if consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		return _advance_consolidation_step_11e(final_result)
	log_phase_message("[11e] Fight step complete — waiting for END_FIGHT to enter the Consolidate step (12.07)")
	return final_result

# 11e 12.07-12.08: one consolidation move during the global Consolidate
# step. Applies the movement, marks the unit's single move used, and —
# for an Engaging Consolidation that tagged unfought enemy units — hands
# those units to the opponent to fight (12.08 AFTER MOVING) before the
# step continues.
func _process_consolidate_step_11e(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var movements = _fight_movements_from_action(action)
	var changes = []

	if movements.is_empty():
		log_phase_message("[11e 12.07] %s consolidates — no models moved" % unit_id)
	else:
		log_phase_message("[11e 12.07] %s consolidates — %d model(s) moved" % [unit_id, movements.size()])

	# Keys may address the unit's own models or an attached character's
	# ("char_unit:key") — 19.03: the Attached unit consolidates as one unit.
	for model_id in movements:
		var route = _fight_split_move_key(unit_id, model_id)
		var route_index = _fight_model_index_for_key(get_unit(route.unit_id).get("models", []), route.model_key)
		if route_index < 0:
			log_phase_message("CONSOLIDATE: movement key %s did not resolve to a model — skipped" % str(model_id))
			continue
		var new_pos = movements[model_id]
		changes.append({
			"op": "set",
			"path": "units.%s.models.%d.position" % [route.unit_id, route_index],
			"value": {"x": new_pos.x, "y": new_pos.y}
		})
	# Apply pivots (new facings) for any non-circular bases that rotated
	var consolidate_rotations = _fight_rotations_from_action(action)
	for model_id in consolidate_rotations:
		var rot_route = _fight_split_move_key(unit_id, model_id)
		var rot_index = _fight_model_index_for_key(get_unit(rot_route.unit_id).get("models", []), rot_route.model_key)
		if rot_index < 0:
			continue
		changes.append({
			"op": "set",
			"path": "units.%s.models.%d.rotation" % [rot_route.unit_id, rot_index],
			"value": float(consolidate_rotations[model_id])
		})
	units_that_consolidated_11e[unit_id] = true
	# The attached characters' one consolidation move is spent with their
	# bodyguard's — they are the same Attached unit (19.03).
	for char_id in _fight_attached_char_ids(unit_id):
		units_that_consolidated_11e[char_id] = true

	# Apply the movement now (execute_action's re-apply is idempotent) so
	# the step data / forced-fight decisions below see the real positions.
	if not changes.is_empty():
		PhaseManager.apply_state_changes(changes)

	var result = create_result(true, changes)

	# 12.08 AFTER MOVING (Engaging Consolidation): enemy units engaged by
	# this move that have not been selected to fight this phase must be
	# selected by the opponent, one at a time, and fight now. The scan
	# simulates the post-move positions (diffs apply after this returns)
	# and patches the selection lists; the sequencer picks the units up
	# from live engagement once the positions land.
	var newly_eligible = _scan_newly_eligible_units_after_consolidation(unit_id, movements)
	if not newly_eligible.is_empty():
		var forced_owner = 0
		for forced_id in newly_eligible:
			var forced_unit = get_unit(forced_id)
			forced_owner = int(forced_unit.get("owner", 0))
			# Stamp eligibility now (positions are only simulated yet, so
			# the cumulative stamp helper cannot see the new engagement).
			var gs_unit = GameState.get_unit(forced_id)
			if not gs_unit.is_empty():
				if not gs_unit.has("flags"):
					gs_unit["flags"] = {}
				gs_unit["flags"]["was_eligible_to_fight"] = true
		log_phase_message("[11e 12.08] Engaging Consolidation by %s forces %d enemy unit(s) to fight: %s" % [
			unit_id, newly_eligible.size(), str(newly_eligible)])
		current_selecting_player = forced_owner
		var dialog_data = _build_fight_selection_dialog_data_internal()
		_pending_fight_selection_data = dialog_data
		emit_signal("fight_selection_required", dialog_data)
		result["trigger_fight_selection"] = true
		result["fight_selection_data"] = dialog_data
		result["forced_by_consolidation"] = true
		return result

	# Step continues: same player until they pass or run out of units.
	return _advance_consolidation_step_11e(result)

func _process_skip_unit(action: Dictionary) -> Dictionary:
	# Skip this unit and advance to next
	units_that_fought.append(action.unit_id)
	active_fighter_id = ""

	# 11e: keep the sequencer's candidate list consistent — a skipped unit
	# forfeits its fight and must not be re-offered forever.
	if sequencer_11e != null:
		sequencer_11e.mark_fought(action.unit_id)
		# A skipped activation also forfeits any 12.06 overrun grant
		if overrun_pile_in_unit_11e == action.unit_id:
			overrun_pile_in_unit_11e = ""
		var _sk_unit = GameState.get_unit(action.unit_id)
		if not _sk_unit.is_empty():
			_sk_unit.get("flags", {}).erase("selected_for_overrun_fight")

	# Clear Martial Ka'tah stance if any
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr:
		faction_mgr.clear_katah_stance(action.unit_id)

	# Switch to next player
	_switch_selecting_player()

	log_phase_message("Skipped unit %s" % action.unit_id)

	# Request next fight selection; when nobody is left and the 11e global
	# Consolidate step is running (a forced fight was skipped), resume it.
	var result = create_result(true, [])
	var dialog_data = _build_fight_selection_dialog_data()
	if not dialog_data.is_empty():
		_pending_fight_selection_data = dialog_data
		emit_signal("fight_selection_required", dialog_data)
		result["trigger_fight_selection"] = true
		result["fight_selection_data"] = dialog_data
	elif consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		return _advance_consolidation_step_11e(result)
	return result

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
			var ability_str = str(ability).to_lower().replace(" ", "_")
			if "fights_first" in ability_str:
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

# --- 11e display/dialog derivation ------------------------------------------
# The 10e Subphase enum + fights_first/normal/fights_last tier lists were
# removed; the FightSequencer (12.04) is the single source of truth. These
# helpers reconstruct the dialog-data shape the right panel's fighter-selection
# section (FightController), the FightPhaseStateBanner and the AI still
# consume, sourced from the sequencer.

func _subphase_string_11e() -> String:
	if sequencer_11e != null and sequencer_11e.step == "fights_first":
		return "FIGHTS_FIRST"
	return "REMAINING_COMBATS"

func _fights_first_units_11e() -> Dictionary:
	var d = {"1": [], "2": []}
	if sequencer_11e != null:
		d["1"] = sequencer_11e.eligible_units(GameState.state, 1, true)
		d["2"] = sequencer_11e.eligible_units(GameState.state, 2, true)
	return d

func _remaining_units_11e() -> Dictionary:
	# Display list for the REMAINING_COMBATS section. The sequencer's
	# eligible_units(..., only_fights_first=false) returns ALL eligible units
	# (Fights First included — 12.04 lets them be picked in the remaining step
	# too), but listing them here duplicated every Fights First unit into both
	# dialog sections even though each unit only fights once. Filter with the
	# same is_fights_first predicate _fights_first_units_11e() uses so the two
	# sections partition cleanly.
	var d = {"1": [], "2": []}
	if sequencer_11e != null:
		var units = GameState.state.get("units", {})
		for player_key in ["1", "2"]:
			var out: Array = []
			for unit_id in sequencer_11e.eligible_units(GameState.state, int(player_key), false):
				if not sequencer_11e.is_fights_first(units.get(unit_id, {})):
					out.append(unit_id)
			d[player_key] = out
	return d

func _combatants_11e() -> Array:
	# Units that are or were in the fight this phase, for UI display (fighter
	# list + fight-order signals): still-eligible first, then already-fought.
	var out: Array = []
	if sequencer_11e == null:
		return out
	for unit_id in GameState.state.get("units", {}):
		if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
			out.append(unit_id)
	for unit_id in units_that_fought:
		if unit_id not in out:
			out.append(unit_id)
	return out

func _build_fight_selection_dialog_data_internal() -> Dictionary:
	"""Build dialog data from the FightSequencer without switching player."""
	log_phase_message("=== REQUESTING FIGHT SELECTION ===")
	log_phase_message("Current Subphase: %s" % _subphase_string_11e())
	log_phase_message("Selecting Player: %d" % current_selecting_player)

	# Get eligible units for current player (sequencer-driven)
	var eligible_units = _get_eligible_units_for_selection()
	log_phase_message("Eligible Units: %d" % eligible_units.size())
	if not eligible_units.is_empty():
		log_phase_message("Available: %s" % str(eligible_units.keys()))

	# Build dialog data (12.04 has only Fights First + untiered Remaining)
	var dialog_data = {
		"current_subphase": _subphase_string_11e(),
		"selecting_player": current_selecting_player,
		"eligible_units": eligible_units,
		"fights_first_units": _fights_first_units_11e(),
		"remaining_units": _remaining_units_11e(),
		"fights_last_units": {"1": [], "2": []},
		"units_that_fought": units_that_fought
	}

	log_phase_message("Emitting fight_selection_required signal")
	log_phase_message("===================================")

	return dialog_data

func _build_fight_selection_dialog_data() -> Dictionary:
	"""Build dialog data for fight selection (extracted for multiplayer sync).
	Switches to the opponent when the current player has nothing eligible; the
	FightSequencer ends the step when neither player can select (returns {})."""
	log_phase_message("=== REQUESTING FIGHT SELECTION ===")
	log_phase_message("Current Subphase: %s" % _subphase_string_11e())
	log_phase_message("Selecting Player: %d" % current_selecting_player)

	# Get eligible units for current player (sequencer-driven)
	var eligible_units = _get_eligible_units_for_selection()
	log_phase_message("Eligible Units: %d" % eligible_units.size())
	if not eligible_units.is_empty():
		log_phase_message("Available: %s" % str(eligible_units.keys()))

	if eligible_units.is_empty():
		# Current player has no units — the sequencer decides who (if anyone)
		# selects next.
		log_phase_message("No eligible units for Player %d, switching..." % current_selecting_player)
		_switch_selecting_player()
		eligible_units = _get_eligible_units_for_selection()
		log_phase_message("After switch, Player %d has %d eligible units" % [current_selecting_player, eligible_units.size()])
		if eligible_units.is_empty():
			# Nobody left to fight — the Fight step is over.
			log_phase_message("Still no eligible units — Fight step complete")
			log_phase_message("===================================")
			return {}

	# Build dialog data (12.04 has only Fights First + untiered Remaining)
	var dialog_data = {
		"current_subphase": _subphase_string_11e(),
		"selecting_player": current_selecting_player,
		"eligible_units": eligible_units,
		"fights_first_units": _fights_first_units_11e(),
		"remaining_units": _remaining_units_11e(),
		"fights_last_units": {"1": [], "2": []},
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
	"""Get units eligible for selection by the current player (12.04 — the
	FightSequencer is the eligibility authority)."""
	var eligible = {}
	if sequencer_11e == null:
		return eligible
	var only_ff = sequencer_11e.step == "fights_first"
	for unit_id in sequencer_11e.eligible_units(GameState.state, current_selecting_player, only_ff):
		var unit = get_unit(unit_id)
		if not unit.is_empty():
			eligible[unit_id] = {
				"name": unit.get("meta", {}).get("name", unit_id),
				"weapons": RulesEngine.get_unit_melee_weapons(unit_id, game_state_snapshot),
				"targets": _get_eligible_melee_targets(unit_id)
			}
	return eligible

func _switch_selecting_player() -> void:
	# 12.04: the sequencer decides who picks next (it skips a player with
	# nothing eligible, returns to Fights First after a remaining-step
	# fight, and ends the step when nobody can).
	if sequencer_11e == null:
		return
	sequencer_11e.after_fight_resolved(GameState.state)
	var sel_11e = sequencer_11e.next_selection(GameState.state)
	if not sel_11e.done:
		current_selecting_player = sel_11e.player
		log_phase_message("[11e] Next: Player %d picks in the %s step (%s)" % [sel_11e.player, sel_11e.step, str(sel_11e.candidates)])

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

const BASE_CONTACT_TOLERANCE_INCHES: float = 0.1  # Match RulesEngine tolerance for digital positioning (was 0.25 — too generous)

func _is_model_in_base_contact_with_enemy(unit_id: String, model_id: String) -> bool:
	"""T4-5: Check if a model is currently in base-to-base contact with any enemy model.
	Uses the original positions from game_state_snapshot (before any pile-in/consolidate movement)."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false

	var models = unit.get("models", [])
	# Resolve by id/index, not int(model_id) — int("m2") == 2 mis-indexes the
	# 1-based model ids the FightController submits (m2 is at index 1).
	var model_index = _fight_model_index_for_key(models, model_id)
	if model_index < 0:
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

func _validate_unit_coherency(unit_id: String, new_positions: Dictionary) -> Dictionary:
	# Delegates to the edition-aware AttackSequence.check_unit_coherency() single source
	# of truth (11e 03.03: within 2" of a mate AND within 9" of every other model).
	# 19.03: coherency is judged on the ATTACHED unit — the bodyguard's and its
	# attached characters' models together; payload keys may address either
	# (plain for the chosen unit, "char_unit:key" for an attached character).
	var all_models = []
	for gid in _fight_move_group_ids(unit_id):
		var models = get_unit(gid).get("models", [])
		for i in models.size():
			var model = models[i]
			var np = _fight_payload_for_model(unit_id, new_positions, gid, i, model)
			if np != null:
				var moved_model = model.duplicate()
				moved_model["position"] = np
				all_models.append(moved_model)
			else:
				var pos_data = model.get("position", {})
				if pos_data == null:
					continue
				all_models.append(model)

	if all_models.size() <= 1:
		return {"valid": true, "errors": []}

	var result = AttackSequence.check_unit_coherency({"models": all_models})
	if result.get("coherent", true):
		return {"valid": true, "errors": []}

	var offenders = result.get("offenders", [])
	return {"valid": false, "errors": ["Unit coherency broken: %d model(s) out of coherency — every model must be within 2\" of a mate AND within 9\" of every other model in the unit" % offenders.size()]}

func _clear_unit_fight_state(unit_id: String) -> void:
	# Clear any temporary fight flags
	pass

# T5-V13: Set is_engaged + fight_priority flags on all units currently in combat
func _set_engagement_flags() -> void:
	# T5-V13: mark each unit in combat with its fight priority so TokenVisual
	# can colour the board indicators. Selection is driven by the
	# FightSequencer (12.04); this is display only, so it keeps the full
	# priority scale (incl. the fights-last board tint) via _get_fight_priority.
	var count := 0
	for unit_id in game_state_snapshot.get("units", {}):
		var unit = game_state_snapshot.units[unit_id]
		if not _is_unit_in_combat(unit):
			continue
		var gs_unit = GameState.get_unit(unit_id)
		if gs_unit.is_empty():
			continue
		if not gs_unit.has("flags"):
			gs_unit["flags"] = {}
		gs_unit["flags"]["is_engaged"] = true
		gs_unit["flags"]["fight_priority"] = _get_fight_priority(unit)
		count += 1

	log_phase_message("T5-V13: Set is_engaged flag on %d units" % count)

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

# ============================================================================
# 11e 19.03: ATTACHED-UNIT SUPPORT FOR FIGHT-PHASE MOVES
# ============================================================================
# While a CHARACTER is attached to a bodyguard unit they are ONE Attached
# unit for all rules purposes (19.03). For the global Pile In (12.02) and
# Consolidate (12.07) steps that means ONE selectable entry and ONE move
# covering the bodyguard's AND the attached characters' models — the Blade
# Champion attached to Custodian Guard must not be offered as its own unit.
# The state model keeps the pieces as separate unit dicts (character:
# attached_to, bodyguard: attachment_data.attached_characters), so the
# fight-move pipeline folds them together:
#  - movement/rotation payload keys: "<idx>"/"m<id>" address the CHOSEN
#    unit's own models; "<char_unit_id>:<idx-or-id>" addresses an attached
#    character's model (mirrors the movement phase's "unit:model" keys).
#  - shared geometry (pile-in targets, engaged-after, coherency, modes) is
#    evaluated on a FOLDED board where the attached characters' models are
#    appended to the bodyguard unit (same idea as RulesEngine's
#    _build_attached_allocation_unit_11e for wound allocation).

# Ids of the character units attached to unit_id (as Strings, existing only).
func _fight_attached_char_ids(unit_id: String) -> Array:
	var out: Array = []
	for char_id in get_unit(unit_id).get("attachment_data", {}).get("attached_characters", []):
		if not get_unit(str(char_id)).is_empty():
			out.append(str(char_id))
	return out

# The unit ids whose models move together in one fight-phase move:
# the chosen unit plus its attached characters.
func _fight_move_group_ids(unit_id: String) -> Array:
	return [unit_id] + _fight_attached_char_ids(unit_id)

# True when unit_id is an attached CHARACTER (a component of some Attached
# unit). Checks the character's own attached_to back-pointer AND every
# bodyguard's attachment_data.attached_characters forward list — saves and
# fixtures exist where only one side of the linkage was written, and the
# forward list is the side the fold itself relies on.
func _fight_is_attached_character(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	if unit.get("attached_to", null) != null:
		return true
	for other_id in game_state_snapshot.get("units", {}):
		if other_id == unit_id:
			continue
		var chars = game_state_snapshot.units[other_id].get("attachment_data", {}).get("attached_characters", [])
		if unit_id in chars:
			return true
	return false

# Split a movement/rotation payload key: plain keys are the chosen unit's
# own models, "unit:model" keys are an attached character's models.
func _fight_split_move_key(base_unit_id: String, key) -> Dictionary:
	var s := str(key)
	var sep := s.find(":")
	if sep < 0:
		return {"unit_id": base_unit_id, "model_key": s}
	return {"unit_id": s.substr(0, sep), "model_key": s.substr(sep + 1)}

# The payload value (position/rotation) addressed to models[index] of
# group-member unit_id, or null. Accepts index or model-id keys, plain
# (chosen unit only) or "unit:key" prefixed forms.
func _fight_payload_for_model(base_unit_id: String, payload: Dictionary, unit_id: String, index: int, model: Dictionary):
	var keys: Array = []
	var mid := str(model.get("id", ""))
	if unit_id == base_unit_id:
		keys.append(str(index))
		if mid != "":
			keys.append(mid)
	keys.append("%s:%d" % [unit_id, index])
	if mid != "":
		keys.append("%s:%s" % [unit_id, mid])
	for k in keys:
		if payload.has(k):
			return payload[k]
	return null

# Board where the attached characters' models are folded into unit_id's
# model list (and the character units removed) so engagement / target /
# coherency geometry sees the Attached unit as the single unit it is.
# Move-eligibility flags are OR-merged (the whole Attached unit charged
# when its bodyguard charged — ChargePhase already stamps both).
func _fight_folded_board(unit_id: String, board: Dictionary) -> Dictionary:
	var char_ids = _fight_attached_char_ids(unit_id)
	if char_ids.is_empty():
		return board
	var folded = board.duplicate(true)
	var units = folded.get("units", {})
	var base = units.get(unit_id, {})
	if base.is_empty():
		return folded
	if not base.has("models"):
		base["models"] = []
	if not base.has("flags"):
		base["flags"] = {}
	for char_id in char_ids:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue
		for m in char_unit.get("models", []):
			base.models.append(m)
		for flag in ["charged_this_turn", "selected_for_overrun_fight", "was_eligible_to_fight", "fights_first"]:
			if char_unit.get("flags", {}).get(flag, false):
				base.flags[flag] = true
		units.erase(char_id)
	return folded

# Display name for the Attached unit's single picker entry:
# "Custodian Guard + Blade Champion" (movement panel convention).
func _fight_attached_display_name(unit_id: String) -> String:
	var meta = get_unit(unit_id).get("meta", {})
	var name = meta.get("display_name", meta.get("name", unit_id))
	var char_names: Array = []
	for char_id in _fight_attached_char_ids(unit_id):
		var cmeta = get_unit(char_id).get("meta", {})
		char_names.append(cmeta.get("display_name", cmeta.get("name", char_id)))
	if char_names.is_empty():
		return name
	return "%s + %s" % [name, ", ".join(char_names)]

# ============================================================================
# 11e 12.02-12.03: GLOBAL PILE IN STEP
# ============================================================================

# 12.03 ELIGIBLE IF: engaged, or made a charge move this turn (the third
# clause — selected for an overrun fight — grants the ADDITIONAL pile-in
# during the Fight step, not a move in this step). Plus alive, hasn't made
# its one step move yet (12.02), and not AIRCRAFT (T4-4: cannot Pile In).
# 19.03: an attached CHARACTER is part of its bodyguard's entry, never its
# own; the bodyguard's eligibility is the ATTACHED unit's (any component
# sub-unit eligible — e.g. only the Leader's model in engagement range).
func _pile_in_eligible_units_11e(player: int) -> Array:
	var out: Array = []
	var tmpl: PileInMove = MoveTypes.get_type("pile_in")
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if _fight_is_attached_character(unit_id):
			continue
		if units_that_piled_in.get(unit_id, false):
			continue
		if _unit_has_keyword(unit, "AIRCRAFT"):
			continue
		var any_alive = false
		for gid in _fight_move_group_ids(unit_id):
			for model in get_unit(gid).get("models", []):
				if model.get("alive", true):
					any_alive = true
					break
			if any_alive:
				break
		if not any_alive:
			continue
		if tmpl == null:
			continue
		var group_eligible = false
		for gid in _fight_move_group_ids(unit_id):
			if tmpl.eligible(gid, GameState.state).eligible:
				group_eligible = true
				break
		if not group_eligible:
			continue
		out.append(unit_id)
	return out

# Enter the Pile In step (12.02) — the fight phase opens here at e11:
# both players make pile-in moves with the eligible units they choose,
# the player whose turn it is first.
func _begin_pile_in_step_11e() -> void:
	pile_in_step_11e = PileInStep11e.ACTIVE
	pile_in_done_players_11e = {}
	piling_in_player_11e = GameState.get_active_player()
	log_phase_message("[11e 12.02] PILE IN step begins — Player %d (active) first" % piling_in_player_11e)
	emit_signal("subphase_transition", "START_OF_FIGHT_PHASE", "PILE_IN")
	_advance_pile_in_step_11e(create_result(true, []))

# Drive the Pile In step forward: offer the current player their remaining
# eligible units, auto-pass a player with none left, and when both players
# are done begin the Fight step's selection.
func _advance_pile_in_step_11e(result: Dictionary) -> Dictionary:
	while true:
		var eligible = _pile_in_eligible_units_11e(piling_in_player_11e)
		if not eligible.is_empty() and not pile_in_done_players_11e.has(piling_in_player_11e):
			current_selecting_player = piling_in_player_11e
			var data = _build_pile_in_step_data_11e(eligible)
			_pending_pile_in_step_data = data
			emit_signal("pile_in_step_required", data)
			result["trigger_pile_in_selection"] = true
			result["pile_in_selection_data"] = data
			return result
		# Nothing (left) for this player — their half is over.
		if not pile_in_done_players_11e.has(piling_in_player_11e):
			pile_in_done_players_11e[piling_in_player_11e] = true
			log_phase_message("[11e 12.02] Player %d's pile-in half complete" % piling_in_player_11e)
		var other = 2 if piling_in_player_11e == 1 else 1
		if not pile_in_done_players_11e.has(other):
			piling_in_player_11e = other
			continue
		# Both players done — the Fight step begins.
		pile_in_step_11e = PileInStep11e.DONE
		_pending_pile_in_step_data = {}
		log_phase_message("[11e 12.02] PILE IN step complete — the Fight step begins (12.04)")
		emit_signal("subphase_transition", "PILE_IN", "FIGHT")
		# Selection order is the sequencer's; sync the pointer before the dialog.
		if sequencer_11e != null:
			var sel_11e = sequencer_11e.next_selection(GameState.state)
			if not sel_11e.done:
				current_selecting_player = sel_11e.player
		var dialog_data = _build_fight_selection_dialog_data()
		if not dialog_data.is_empty():
			_pending_fight_selection_data = dialog_data
			emit_signal("fight_selection_required", dialog_data)
			result["trigger_fight_selection"] = true
			result["fight_selection_data"] = dialog_data
		return result
	return result

func _build_pile_in_step_data_11e(eligible: Array) -> Dictionary:
	var units := {}
	for unit_id in eligible:
		# 19.03: one entry for the Attached unit — "Guard + Blade Champion" —
		# engaged if ANY of its component sub-units is (the Leader's model in
		# engagement range engages the whole Attached unit).
		var engaged := false
		for gid in _fight_move_group_ids(unit_id):
			if RulesEngine.is_unit_engaged(gid, GameState.state):
				engaged = true
				break
		units[unit_id] = {
			"name": _fight_attached_display_name(unit_id),
			"engaged": engaged,
			"attached_characters": _fight_attached_char_ids(unit_id)
		}
	return {
		"piling_in_player": piling_in_player_11e,
		"eligible_units": units,
		"piled_in_units": units_that_piled_in.keys(),
		"done_players": pile_in_done_players_11e.keys()
	}

func get_pending_pile_in_step_data() -> Dictionary:
	"""T3-13 pattern: the Pile In step starts during phase entry, before the
	controller connects — it pulls (and clears) the missed dialog data here."""
	var data = _pending_pile_in_step_data
	_pending_pile_in_step_data = {}
	return data

# ============================================================================
# 11e 12.07-12.08: GLOBAL CONSOLIDATE STEP
# ============================================================================

# 12.08 consolidation eligibility is "was eligible to fight this phase" — a
# CUMULATIVE predicate, while FightSequencer.eligible_to_fight is
# point-in-time. Stamp flags.was_eligible_to_fight (the flag
# ConsolidationMove.eligible() reads) whenever a unit is, or becomes,
# eligible: at phase init, on every fighter selection, after each
# activation, and when a consolidation tags new units into the fight.
# Same direct-GameState idiom as _set_engagement_flags (T5-V13).
func _stamp_fight_eligibility_11e() -> void:
	if sequencer_11e == null:
		return
	var stamped = 0
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if unit.get("flags", {}).get("was_eligible_to_fight", false):
			continue
		if sequencer_11e.fought.get(unit_id, false) or sequencer_11e.eligible_to_fight(unit_id, GameState.state):
			if not unit.has("flags"):
				unit["flags"] = {}
			unit["flags"]["was_eligible_to_fight"] = true
			stamped += 1
	if stamped > 0:
		log_phase_message("[11e 12.08] Stamped was_eligible_to_fight on %d unit(s)" % stamped)

func _clear_fight_eligibility_stamps_11e() -> void:
	var all_units = GameState.state.get("units", {}) if GameState.state is Dictionary else {}
	for unit_id in all_units:
		var flags = all_units[unit_id].get("flags", {})
		flags.erase("was_eligible_to_fight")
		flags.erase("selected_for_overrun_fight")

# 12.08 ELIGIBLE IF: the unit was eligible to fight this phase — plus it
# is alive, hasn't already made its one consolidation move this step
# (12.07), and isn't an AIRCRAFT (T4-4: cannot Consolidate, so offering
# it would only ever be a no-op).
func _consolidation_eligible_units_11e(player: int) -> Array:
	var out: Array = []
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		# 19.03: an attached CHARACTER consolidates as part of its bodyguard's
		# entry — never as a separate unit.
		if _fight_is_attached_character(unit_id):
			continue
		if units_that_consolidated_11e.has(unit_id):
			continue
		# The Attached unit was eligible to fight if ANY of its component
		# sub-units carries the cumulative 12.08 stamp.
		var group_was_eligible = false
		for gid in _fight_move_group_ids(unit_id):
			if get_unit(gid).get("flags", {}).get("was_eligible_to_fight", false):
				group_was_eligible = true
				break
		if not group_was_eligible:
			continue
		if _unit_has_keyword(unit, "AIRCRAFT"):
			continue
		var any_alive = false
		for gid in _fight_move_group_ids(unit_id):
			for model in get_unit(gid).get("models", []):
				if model.get("alive", true):
					any_alive = true
					break
			if any_alive:
				break
		if not any_alive:
			continue
		out.append(unit_id)
	return out

# True while fights forced by an Engaging Consolidation (12.08 AFTER
# MOVING) are still unresolved — consolidation pauses until the opponent
# has selected each of those units and their attacks are resolved.
func _forced_fights_pending_11e() -> bool:
	if consolidation_step_11e != ConsolidationStep11e.ACTIVE:
		return false
	return sequencer_11e != null and sequencer_11e.has_eligible(GameState.state)

# Enter the Consolidate step (12.07). Called from _process_end_fight at
# edition >= 11: after all fighting, both players make consolidation
# moves with the eligible units they choose — the player whose turn it
# is resolves ALL of their moves first, followed by their opponent.
func _begin_consolidation_step_11e() -> Dictionary:
	consolidation_step_11e = ConsolidationStep11e.ACTIVE
	consolidation_done_players_11e = {}
	units_that_consolidated_11e = {}
	_stamp_fight_eligibility_11e()

	# END_FIGHT is an always-valid escape hatch (T5-UX7): if the player
	# ended the phase with fights still owed, those units forfeit their
	# fight — mark them fought so the sequencer doesn't re-offer them as
	# 12.08 forced fights mid-consolidation.
	if sequencer_11e != null:
		for unit_id in GameState.state.get("units", {}):
			if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
				log_phase_message("[11e 12.07] %s forfeits its fight (phase ended early)" % unit_id)
				sequencer_11e.mark_fought(unit_id)

	consolidating_player_11e = GameState.get_active_player()
	log_phase_message("[11e 12.07] CONSOLIDATE step begins — Player %d (active) first" % consolidating_player_11e)
	emit_signal("subphase_transition", _subphase_string_11e(), "CONSOLIDATE")
	return _advance_consolidation_step_11e(create_result(true, []))

# Drive the Consolidate step forward: offer the current player their
# remaining eligible units, auto-pass a player with none left, and when
# both players are done run the end-of-fight-phase triggers.
func _advance_consolidation_step_11e(result: Dictionary) -> Dictionary:
	while true:
		var eligible = _consolidation_eligible_units_11e(consolidating_player_11e)
		if not eligible.is_empty() and not consolidation_done_players_11e.has(consolidating_player_11e):
			current_selecting_player = consolidating_player_11e
			var data = _build_consolidation_step_data_11e(eligible)
			emit_signal("consolidation_step_required", data)
			result["trigger_consolidation_selection"] = true
			result["consolidation_selection_data"] = data
			return result
		# Nothing (left) for this player — their half is over.
		if not consolidation_done_players_11e.has(consolidating_player_11e):
			consolidation_done_players_11e[consolidating_player_11e] = true
			log_phase_message("[11e 12.07] Player %d's consolidation half complete" % consolidating_player_11e)
		var other = 2 if consolidating_player_11e == 1 else 1
		if not consolidation_done_players_11e.has(other):
			consolidating_player_11e = other
			continue
		# Both players done — the Consolidate step ends.
		consolidation_step_11e = ConsolidationStep11e.DONE
		log_phase_message("[11e 12.07] CONSOLIDATE step complete — resolving end-of-fight-phase triggers")
		return _run_end_of_fight_triggers(result)
	return result

func _build_consolidation_step_data_11e(eligible: Array) -> Dictionary:
	var units := {}
	var tmpl: ConsolidationMove = MoveTypes.get_type("consolidation")
	for unit_id in eligible:
		# 19.03: one entry for the Attached unit; the 12.08 mode is assessed
		# on the folded board so the characters' models count as part of it.
		var mode = ""
		if tmpl != null:
			mode = str(tmpl.select_mode(unit_id, _fight_folded_board(unit_id, GameState.state)).mode)
		units[unit_id] = {
			"name": _fight_attached_display_name(unit_id),
			"mode": mode,
			"attached_characters": _fight_attached_char_ids(unit_id)
		}
	return {
		"consolidating_player": consolidating_player_11e,
		"eligible_units": units,
		"consolidated_units": units_that_consolidated_11e.keys(),
		"done_players": consolidation_done_players_11e.keys()
	}

func get_available_actions() -> Array:
	var actions = []

	log_phase_message("=== get_available_actions DEBUG ===")
	log_phase_message("active_fighter_id: '%s'" % active_fighter_id)

	# Moment Shackle: offer choice before any fighting starts
	if _moment_shackle_pending_units.size() > 0:
		for ms_uid in _moment_shackle_pending_units:
			var ms_unit = game_state_snapshot.get("units", {}).get(ms_uid, {})
			var ms_name = ms_unit.get("meta", {}).get("name", ms_uid)
			actions.append({
				"type": "USE_MOMENT_SHACKLE",
				"unit_id": ms_uid,
				"choice": "attacks_12",
				"description": "Moment Shackle (%s): Watcher's Axe gets 12 Attacks" % ms_name
			})
			actions.append({
				"type": "USE_MOMENT_SHACKLE",
				"unit_id": ms_uid,
				"choice": "invuln_2",
				"description": "Moment Shackle (%s): 2+ invulnerable save" % ms_name
			})
			actions.append({
				"type": "DECLINE_MOMENT_SHACKLE",
				"unit_id": ms_uid,
				"description": "Decline Moment Shackle for %s" % ms_name
			})
		return actions

	# P0-58: If awaiting melee saves, only allow APPLY_MELEE_SAVES
	if awaiting_melee_saves:
		actions.append({
			"type": "APPLY_MELEE_SAVES",
			"description": "Apply melee saves (interactive wound allocation)"
		})
		log_phase_message("P0-58: Awaiting melee saves — returning APPLY_MELEE_SAVES only")
		return actions

	# STAGED FIGHT: while paused after a hit/wound roll, the attacker's options
	# are exactly: continue to the next stage, or Command Re-roll one die.
	var staged_stage = staged_fight_state.get("stage", "")
	if staged_stage == "hits_pending":
		actions.append({
			"type": "CONTINUE_TO_WOUNDS",
			"description": "Roll to wound for the paused weapon"
		})
		if _fight_reroll_available():
			actions.append({
				"type": "USE_FIGHT_REROLL",
				"payload": {"stage": "hits", "die_index": 0},
				"description": "Command Re-roll (1 CP) — re-roll one hit die"
			})
		return actions
	elif staged_stage == "wounds_pending":
		actions.append({
			"type": "CONTINUE_TO_SAVES",
			"description": "Continue to saving throws for the paused weapon"
		})
		if _fight_reroll_available():
			actions.append({
				"type": "USE_FIGHT_REROLL",
				"payload": {"stage": "wounds", "die_index": 0},
				"description": "Command Re-roll (1 CP) — re-roll one wound die"
			})
		return actions

	# 11e 12.02: during the global Pile In step, the piling-in player's
	# options are exactly: pile in one of their remaining eligible units,
	# or end their half.
	if pile_in_step_11e == PileInStep11e.ACTIVE:
		for pi_uid in _pile_in_eligible_units_11e(piling_in_player_11e):
			actions.append({
				"type": "PILE_IN",
				"unit_id": pi_uid,
				"description": "Pile in with %s" % pi_uid
			})
		actions.append({
			"type": "END_PILE_IN",
			"player": piling_in_player_11e,
			"description": "End Player %d's pile-in" % piling_in_player_11e
		})
		log_phase_message("[11e 12.02] Pile In step — returning %d pile-in action(s)" % actions.size())
		return actions

	# 11e 12.07: during the global Consolidate step, the consolidating
	# player's options are exactly: consolidate one of their remaining
	# eligible units, or end their half. (While an Engaging Consolidation
	# has forced fights pending, fall through to the normal fight actions.)
	if consolidation_step_11e == ConsolidationStep11e.ACTIVE \
			and not _forced_fights_pending_11e():
		for cons_uid in _consolidation_eligible_units_11e(consolidating_player_11e):
			actions.append({
				"type": "CONSOLIDATE",
				"unit_id": cons_uid,
				"description": "Consolidate %s" % cons_uid
			})
		actions.append({
			"type": "END_CONSOLIDATION",
			"player": consolidating_player_11e,
			"description": "End Player %d's consolidation" % consolidating_player_11e
		})
		log_phase_message("[11e 12.07] Consolidate step — returning %d consolidation action(s)" % actions.size())
		return actions

	# If no active fighter, need to select one.
	# 12.04: the FightSequencer is the selection AUTHORITY — offer exactly ITS
	# candidates, tagged with the picking player.
	if sequencer_11e != null:
		if active_fighter_id == "":
			var sel_11e = sequencer_11e.peek_selection(GameState.state)
			if not sel_11e.done:
				for cand_id in sel_11e.candidates:
					actions.append({
						"type": "SELECT_FIGHTER",
						"unit_id": cand_id,
						"player": sel_11e.player,
						"description": "Select %s to fight (%s step, 12.04)" % [cand_id, sel_11e.step]
					})
				log_phase_message("[11e 12.04] Sequencer offers %d SELECT_FIGHTER candidate(s) for Player %d (%s step)" % [
					sel_11e.candidates.size(), sel_11e.player, sel_11e.step])
		else:
			log_phase_message("NOT adding SELECT_FIGHTER: active_fighter_id='%s'" % active_fighter_id)

	# If active fighter is selected, show simple control actions
	if active_fighter_id != "":
		if pending_attacks.is_empty():
			# 11e: only the Overrun fight's additional pile-in (12.06) is
			# offered here — the routine pile-in happened in the global
			# 12.02 step.
			var offer_pile_in: bool = overrun_pile_in_unit_11e == active_fighter_id
			if offer_pile_in:
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
	
	# Add END_FIGHT action when appropriate
	# The END_FIGHT button should ALWAYS be available to the active player
	# This allows them to end the fight phase even if there are eligible units
	var can_end_fight = false

	# 12.04: the FightSequencer is the authority on "everyone has fought".
	if sequencer_11e != null:
		if active_fighter_id == "" and not sequencer_11e.has_eligible(GameState.state):
			can_end_fight = true
			log_phase_message("Adding END_FIGHT action - fight step complete (11e sequencer)")

	if can_end_fight and not awaiting_sweeping_advance and not awaiting_acrobatic_escape:
		actions.append({
			"type": "END_FIGHT",
			"description": "End Fight Phase"
		})

	# Sweeping Advance actions when awaiting
	if awaiting_sweeping_advance and not sweeping_advance_pending_units.is_empty():
		var sa_unit = sweeping_advance_pending_units[0]
		actions.append({
			"type": "SWEEPING_ADVANCE",
			"unit_id": sa_unit.unit_id,
			"in_engagement": sa_unit.in_engagement,
			"move_distance": sa_unit.move_distance,
			"description": "Sweeping Advance: %s" % sa_unit.unit_name
		})
		actions.append({
			"type": "DECLINE_SWEEPING_ADVANCE",
			"unit_id": sa_unit.unit_id,
			"description": "Decline Sweeping Advance: %s" % sa_unit.unit_name
		})

	# Acrobatic Escape actions when awaiting
	if awaiting_acrobatic_escape and not acrobatic_escape_pending_units.is_empty():
		var ae_unit = acrobatic_escape_pending_units[0]
		actions.append({
			"type": "ACROBATIC_ESCAPE",
			"unit_id": ae_unit.unit_id,
			"move_distance": ae_unit.move_distance,
			"description": "Acrobatic Escape: %s (D6 = %.0f\")" % [ae_unit.unit_name, ae_unit.move_distance]
		})
		actions.append({
			"type": "DECLINE_ACROBATIC_ESCAPE",
			"unit_id": ae_unit.unit_id,
			"description": "Decline Acrobatic Escape: %s" % ae_unit.unit_name
		})
	
	log_phase_message("Returning %d available actions: %s" % [actions.size(), str(actions)])
	log_phase_message("=== END get_available_actions DEBUG ===")
	return actions

func _should_complete_phase() -> bool:
	# Phase only completes when explicitly requested via END_FIGHT action
	# Don't auto-complete based on fight sequence anymore
	return false

# T4-4: Helper to check if a unit has a specific keyword
func _unit_has_keyword(unit: Dictionary, keyword: String) -> bool:
	var keywords = unit.get("meta", {}).get("keywords", [])
	return keyword in keywords

# Legacy method compatibility (for existing helper methods)
func _is_unit_in_combat(unit: Dictionary) -> bool:
	# Destroyed units cannot be in combat
	if _is_unit_destroyed_check(unit):
		return false

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

	# Units already in the fight this phase carry the cumulative 12.08
	# eligibility stamp (was_eligible_to_fight, set via the FightSequencer when a
	# unit becomes eligible). An Engaging Consolidation only forces NEW foes —
	# units this move drags into engagement range that were NOT already eligible
	# (12.08 AFTER MOVING). The consolidating unit is likewise never a new foe.
	# Using the stamp (not a live engagement re-check) keeps this consistent with
	# the sequencer's own engagement definition.
	var already_in_sequence = {consolidating_unit_id: true}
	# 19.03: the attached characters moved as part of this consolidation —
	# they are the same Attached unit, never a "new foe" of their own.
	var scan_char_ids = _fight_attached_char_ids(consolidating_unit_id)
	for char_id in scan_char_ids:
		already_in_sequence[char_id] = true
	for uid in all_units:
		if all_units[uid].get("flags", {}).get("was_eligible_to_fight", false):
			already_in_sequence[uid] = true

	# Build a temporary copy of the consolidating unit with updated positions
	var consolidating_unit = all_units.get(consolidating_unit_id, {})
	if consolidating_unit.is_empty():
		return newly_eligible

	# The temp view FOLDS the attached characters' models into the unit (with
	# their own proposed positions applied) so an Engaging Consolidation led
	# by the Leader's model still forces the fight (19.03: one Attached unit).
	var temp_consolidating_unit = consolidating_unit.duplicate(true)
	var temp_models = temp_consolidating_unit.get("models", [])
	for i in temp_models.size():
		var np = _fight_payload_for_model(consolidating_unit_id, movements, consolidating_unit_id, i, temp_models[i])
		if np != null:
			temp_models[i]["position"] = {"x": np.x, "y": np.y}
	for char_id in scan_char_ids:
		var char_models = all_units.get(char_id, {}).get("models", [])
		for i in char_models.size():
			var cm = char_models[i].duplicate(true)
			var cnp = _fight_payload_for_model(consolidating_unit_id, movements, char_id, i, cm)
			if cnp != null:
				cm["position"] = {"x": cnp.x, "y": cnp.y}
			temp_models.append(cm)

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
				# Attached characters moved with it — their models are part of
				# the folded temp view checked above, not stale entries here.
				if other_unit_id in scan_char_ids:
					continue

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
			# NOT previously in the fight, but now in engagement range — the
			# FightSequencer will pick it up from live engagement once the
			# consolidation positions land (12.08 "new foes to face").
			var check_name = check_unit.get("meta", {}).get("name", check_unit_id)
			var owner_key = str(int(check_owner))
			newly_eligible.append(check_unit_id)
			log_phase_message("[11e 12.08] NEW FIGHT ELIGIBLE: %s (player %s) is now in engagement range after consolidation by %s" % [
				check_name, owner_key, consolidating_unit_id
			])

	if newly_eligible.size() > 0:
		log_phase_message("[11e 12.08] %d unit(s) became newly eligible to fight after consolidation" % newly_eligible.size())
		emit_signal("fight_sequence_updated", _combatants_11e())
	else:
		log_phase_message("[11e 12.08] No new units became eligible to fight after consolidation")

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

	# 19.03: one fight-phase move may reposition the chosen unit's own models
	# AND its attached characters' ("char_unit:key" payload keys). Precompute
	# every moved model's proposed position (keyed "unit|index") so any pair —
	# including cross-unit bodyguard/character pairs — compares proposed
	# against proposed, not against a stale position.
	var proposed := {}
	for gid in _fight_move_group_ids(unit_id):
		var gmodels = all_units.get(gid, {}).get("models", [])
		for i in gmodels.size():
			var np = _fight_payload_for_model(unit_id, movements, gid, i, gmodels[i])
			if np != null:
				proposed["%s|%d" % [gid, i]] = np

	# Check each model's new position
	for model_id in movements:
		var new_pos = movements[model_id]
		if new_pos is Vector2:
			var route = _fight_split_move_key(unit_id, model_id)
			var route_unit = all_units.get(route.unit_id, {})
			var models = route_unit.get("models", [])
			var unit_keywords = route_unit.get("meta", {}).get("keywords", [])
			# Resolve the movement key ("m2" id or "1" index) to an array index.
			# NOT int(model_id): GDScript's int("m2") == 2 (it parses the trailing
			# digits), which is off by one for the 1-based model ids the
			# FightController submits (m2 is at index 1, not 2). That mis-index
			# compared the moving model against a sibling's — and its own — stale
			# position, producing phantom "would overlap with <unit>/N" errors
			# during pile-in / consolidate, and skipped the last model entirely
			# (int("m3") == size).
			var model_index = _fight_model_index_for_key(models, route.model_key)
			if model_index >= 0:
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
						if check_unit_id == route.unit_id and i == model_index:
							continue

						# Skip dead models
						if not other_model.get("alive", true):
							continue

						# If this other model is ALSO being moved in the same
						# submission (same unit or an attached character), compare
						# against its proposed position rather than the stale one.
						var other_position = proposed.get("%s|%d" % [check_unit_id, i], _get_model_position(check_unit_id, str(i)))

						if other_position == null:
							continue

						# Build other model dict with position
						var other_model_check = other_model.duplicate()
						other_model_check["position"] = other_position

						# Check for overlap
						if Measurement.models_overlap(check_model, other_model_check):
							errors.append("Model %s would overlap with %s/%d" % [model_id, check_unit_id, i])

				# Check for wall collision, honoring the unit's traversal keywords.
				if Measurement.model_overlaps_any_wall(check_model, unit_keywords):
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

	# ISS-024: apply through the pipeline (the snapshot is a live view —
	# direct writes would bypass replay/MP sync).
	PhaseManager.apply_state_changes([{"op": "set",
		"path": "units.%s.flags.%s" % [unit_id, EffectPrimitivesData.FLAG_PRECISION_MELEE],
		"value": true}])

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
			var rng_service = RulesEngine.make_rng()
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

	# Proceed to the activation's fight moves
	return _proceed_to_fight_moves(unit_id)

# What happens between "selected to fight" and "assign attacks":
# - 10e: the per-activation pile-in.
# - 11e: pile-in already happened in the global 12.02 step. Only an
#   OVERRUN fight (12.06 — unengaged, or engaged now but unengaged at the
#   start of the Fight step) gets ONE additional pile-in move here; a
#   normal fight (12.05) goes straight to attack assignment.
func _proceed_to_fight_moves(unit_id: String) -> Dictionary:
	var overrun_available := false
	if sequencer_11e != null:
		var engaged_now = RulesEngine.is_unit_engaged(unit_id, GameState.state)
		overrun_available = (not engaged_now) or not sequencer_11e.engaged_at_step_start.get(unit_id, false)
	if overrun_available:
		overrun_pile_in_unit_11e = unit_id
		# The template's 12.03 eligibility reads this flag (a unit that
		# neither is engaged nor charged may still make the overrun
		# move). Same direct-flag idiom as _set_engagement_flags.
		var gs_unit = GameState.get_unit(unit_id)
		if not gs_unit.is_empty():
			if not gs_unit.has("flags"):
				gs_unit["flags"] = {}
			gs_unit["flags"]["selected_for_overrun_fight"] = true
		log_phase_message("[11e 12.06] %s makes an OVERRUN fight — one additional pile-in move" % unit_id)
		emit_signal("pile_in_required", unit_id, 3.0)
		var overrun_result = create_result(true, [])
		overrun_result["trigger_pile_in"] = true
		overrun_result["pile_in_unit_id"] = unit_id
		overrun_result["pile_in_distance"] = 3.0
		return overrun_result
	# Normal fight (12.05): straight to attack assignment.
	return _request_attack_assignment(unit_id, create_result(true, []))

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

	# ISS-024: apply through the pipeline (the snapshot is a live view).
	var katah_diffs: Array = []
	if true:
		if stance == "both":
			for kf in [["effect_sustained_hits", true], ["effect_lethal_hits", true],
					["katah_stance", "both"], ["katah_sustained_hits_value", 1]]:
				katah_diffs.append({"op": "set", "path": "units.%s.flags.%s" % [unit_id, kf[0]], "value": kf[1]})
		elif stance == "dacatarai":
			for kf in [["effect_sustained_hits", true], ["katah_stance", "dacatarai"],
					["katah_sustained_hits_value", 1]]:
				katah_diffs.append({"op": "set", "path": "units.%s.flags.%s" % [unit_id, kf[0]], "value": kf[1]})
		elif stance == "rendax":
			for kf in [["effect_lethal_hits", true], ["katah_stance", "rendax"]]:
				katah_diffs.append({"op": "set", "path": "units.%s.flags.%s" % [unit_id, kf[0]], "value": kf[1]})
	if not katah_diffs.is_empty():
		PhaseManager.apply_state_changes(katah_diffs)

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

	# 11e: register the out-of-sequence selection with the sequencer, or it
	# would keep offering this unit as an unfought candidate forever.
	if sequencer_11e != null:
		sequencer_11e.mark_fought(unit_id)

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

	# No Epic Challenge — proceed to the activation's fight moves (10e:
	# pile-in; 11e: overrun extra pile-in or straight to attacks)
	var result = _proceed_to_fight_moves(unit_id)
	if not strat_result.get("diffs", []).is_empty():
		var merged_changes = strat_result.get("diffs", [])
		merged_changes.append_array(result.get("changes", []))
		result["changes"] = merged_changes
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

	var result = create_result(true, [])
	if not dialog_data.is_empty():
		emit_signal("fight_selection_required", dialog_data)
		result["trigger_fight_selection"] = true
		result["fight_selection_data"] = dialog_data
		return result

	# Nobody left to fight — if a 12.08 forced fight triggered this
	# Counter-Offensive window, resume the Consolidate step (11e).
	if consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		return _advance_consolidation_step_11e(result)
	return result

func _validate_end_fight(action: Dictionary) -> Dictionary:
	# END_FIGHT is always valid - it's the manual way to end the fight phase
	return {"valid": true, "errors": []}

# 11e 12.02: the piling-in player passes — ends their half of the global
# Pile In step (any units they didn't move forfeit their pile-in; it is
# optional per unit).
func _validate_end_pile_in(action: Dictionary) -> Dictionary:
	if pile_in_step_11e != PileInStep11e.ACTIVE:
		return {"valid": false, "errors": ["The Pile In step is not in progress (12.02)"]}
	var player = int(action.get("player", piling_in_player_11e))
	if player != piling_in_player_11e:
		return {"valid": false, "errors": ["Not your half of the Pile In step — Player %d piles in first (12.02)" % piling_in_player_11e]}
	return {"valid": true, "errors": []}

func _process_end_pile_in(action: Dictionary) -> Dictionary:
	pile_in_done_players_11e[piling_in_player_11e] = true
	log_phase_message("[11e 12.02] Player %d ends their pile-in half" % piling_in_player_11e)
	return _advance_pile_in_step_11e(create_result(true, []))

# 11e 12.07: the consolidating player passes — ends their half of the
# global Consolidate step (any units they didn't move forfeit their
# consolidation; it is optional per unit at 11e).
func _validate_end_consolidation(action: Dictionary) -> Dictionary:
	if consolidation_step_11e != ConsolidationStep11e.ACTIVE:
		return {"valid": false, "errors": ["The Consolidate step is not in progress (12.07)"]}
	if _forced_fights_pending_11e():
		return {"valid": false, "errors": ["Fights forced by an Engaging Consolidation must be resolved first (12.08)"]}
	var player = int(action.get("player", consolidating_player_11e))
	if player != consolidating_player_11e:
		return {"valid": false, "errors": ["Not your half of the Consolidate step — Player %d is consolidating (12.07)" % consolidating_player_11e]}
	return {"valid": true, "errors": []}

func _process_end_consolidation(action: Dictionary) -> Dictionary:
	consolidation_done_players_11e[consolidating_player_11e] = true
	log_phase_message("[11e 12.07] Player %d ends their consolidation half" % consolidating_player_11e)
	return _advance_consolidation_step_11e(create_result(true, []))

func _process_end_fight(action: Dictionary) -> Dictionary:
	log_phase_message("Fight phase ending...")

	# 11e 12.07: the global CONSOLIDATE step happens after all fighting and
	# BEFORE the end-of-fight-phase triggers. The first END_FIGHT enters
	# the step; while it is active, END_FIGHT doubles as "end my
	# consolidation half" (keeps turn-timer and escape-hatch semantics:
	# repeated END_FIGHT still walks the phase to completion).
	# 12.02: END_FIGHT during the Pile In step ends the current half
	# (same walk-forward semantics as the Consolidate step below).
	if pile_in_step_11e == PileInStep11e.ACTIVE:
		pile_in_done_players_11e[piling_in_player_11e] = true
		log_phase_message("[11e 12.02] Player %d ends their pile-in half via END_FIGHT" % piling_in_player_11e)
		return _advance_pile_in_step_11e(create_result(true, []))
	if consolidation_step_11e == ConsolidationStep11e.NOT_STARTED:
		# Fight-phase scope fix: "End Fight Phase" ends only the ENDING
		# player's own fights. Per 12.04, when one player stops selecting,
		# the OTHER player still fights all of their remaining eligible
		# units — so if the opponent is owed a fight, hand the Fight step
		# over to them instead of forfeiting everyone and jumping to the
		# Consolidate step (the previous behaviour, which wrongly cut the
		# opponent's units out of the phase).
		var ending_player := int(action.get("player", GameState.get_active_player()))
		var opponent := 2 if ending_player == 1 else 1
		if sequencer_11e != null \
				and _player_has_eligible_fights_11e(ending_player) \
				and _player_has_eligible_fights_11e(opponent):
			_forfeit_player_fights_11e(ending_player)
			log_phase_message("[11e 12.04] Player %d ended their fights — Player %d still fights their remaining units" % [ending_player, opponent])
			return _resume_fight_step_after_end_11e(create_result(true, []))
		return _begin_consolidation_step_11e()
	if consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		if sequencer_11e != null:
			for uid in GameState.state.get("units", {}):
				if sequencer_11e.eligible_to_fight(uid, GameState.state):
					log_phase_message("[11e 12.08] %s forfeits its forced fight (END_FIGHT during Consolidate step)" % uid)
					sequencer_11e.mark_fought(uid)
		consolidation_done_players_11e[consolidating_player_11e] = true
		log_phase_message("[11e 12.07] Player %d ends their consolidation half via END_FIGHT" % consolidating_player_11e)
		return _advance_consolidation_step_11e(create_result(true, []))

	return _run_end_of_fight_triggers(create_result(true, []))

# True while `player` still owns at least one unit the sequencer would offer
# a fight to. Used by END_FIGHT to decide whether the opponent still gets to
# fight (12.04) before the phase moves on to the Consolidate step.
func _player_has_eligible_fights_11e(player: int) -> bool:
	if sequencer_11e == null:
		return false
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
			return true
	return false

# Mark every remaining eligible fight owned by `player` as fought — they
# forfeit those fights because the player chose to end their fighting. Only
# this player's units are touched; the opponent's stay eligible so they still
# get to fight (12.04).
func _forfeit_player_fights_11e(player: int) -> void:
	if sequencer_11e == null:
		return
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
			log_phase_message("[11e 12.04] %s forfeits its fight (Player %d ended their fights)" % [unit_id, player])
			sequencer_11e.mark_fought(unit_id)

# After the ending player forfeits their own fights, hand the Fight step over
# to the opponent (12.04) and emit the next fight-selection request. Mirrors
# _finish_fight_activation_11e's hand-off so the AI / controller / network
# sync all pick it up the same way. If the sequencer unexpectedly reports no
# one left, fall through to the Consolidate step instead of stalling.
func _resume_fight_step_after_end_11e(result: Dictionary) -> Dictionary:
	_switch_selecting_player()
	var dialog_data = _build_fight_selection_dialog_data()
	if dialog_data.is_empty():
		return _begin_consolidation_step_11e()
	emit_signal("fight_selection_required", dialog_data)
	result["trigger_fight_selection"] = true
	result["fight_selection_data"] = dialog_data
	return result

# End-of-fight-phase triggers (12.09): Sweeping Advance, then Acrobatic
# Escape, then phase completion. At edition >= 11 this runs only after the
# global Consolidate step is DONE; at edition 10 it is END_FIGHT's tail.
func _run_end_of_fight_triggers(result: Dictionary) -> Dictionary:
	# Check for Sweeping Advance eligibility before ending the phase
	var sa_eligible = _get_sweeping_advance_eligible_units()
	if not sa_eligible.is_empty() and not awaiting_sweeping_advance:
		awaiting_sweeping_advance = true
		sweeping_advance_pending_units = sa_eligible.duplicate()

		# Offer Sweeping Advance to the first eligible unit
		var first = sa_eligible[0]
		log_phase_message("SWEEPING ADVANCE: %s (player %d) is eligible — offering ability" % [first.unit_name, first.player])
		emit_signal("sweeping_advance_available", first.unit_id, first.player, first.in_engagement, first.move_distance)

		result["trigger_sweeping_advance"] = true
		result["sweeping_advance_unit_id"] = first.unit_id
		result["sweeping_advance_player"] = first.player
		result["sweeping_advance_in_engagement"] = first.in_engagement
		result["sweeping_advance_move_distance"] = first.move_distance
		return result

	# Check for Acrobatic Escape before ending
	var ae_result = _check_acrobatic_escape_or_complete(result.get("changes", []))
	if ae_result != null:
		return ae_result

	log_phase_message("Fight phase ended")
	emit_signal("phase_completed")
	return result

# ============================================================================
# SWEEPING ADVANCE
# ============================================================================

func _get_sweeping_advance_eligible_units() -> Array:
	"""Find units with the Sweeping Advance ability that fought this phase and haven't used it yet."""
	var eligible = []
	var all_units = game_state_snapshot.get("units", {})
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")

	for unit_id in units_that_fought:
		var unit = all_units.get(unit_id, {})
		if unit.is_empty():
			continue

		# Check if unit or its attached characters have Sweeping Advance ability
		var has_sweeping_advance = false
		var abilities = unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			if ability is Dictionary and ability.get("name", "") == "Sweeping Advance":
				has_sweeping_advance = true
				break
			elif ability is String and ability == "Sweeping Advance":
				has_sweeping_advance = true
				break

		# Also check attached characters (e.g. Shield-Captain attached to Vertus Praetors)
		if not has_sweeping_advance:
			var attached_ids = unit.get("attachment_data", {}).get("attached_characters", [])
			for char_id in attached_ids:
				var char_unit = all_units.get(char_id, {})
				var char_abilities = char_unit.get("meta", {}).get("abilities", [])
				for ability in char_abilities:
					if ability is Dictionary and ability.get("name", "") == "Sweeping Advance":
						has_sweeping_advance = true
						break
					elif ability is String and ability == "Sweeping Advance":
						has_sweeping_advance = true
						break
				if has_sweeping_advance:
					break

		if not has_sweeping_advance:
			continue

		# Check if already used this battle (once per battle)
		if ability_mgr and ability_mgr.is_once_per_battle_used(unit_id, "Sweeping Advance"):
			log_phase_message("SWEEPING ADVANCE: %s already used this battle — skipping" % unit_id)
			continue

		# Check if unit is still alive
		if _is_unit_destroyed_check(unit):
			continue

		# Determine if unit is in engagement range with any enemy
		var in_engagement = _is_unit_in_combat(unit)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var move_distance = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
		var player = int(unit.get("owner", 0))

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"player": player,
			"in_engagement": in_engagement,
			"move_distance": move_distance
		})

		log_phase_message("SWEEPING ADVANCE: %s eligible (in_engagement=%s, move=%.0f\")" % [
			unit_name, str(in_engagement), move_distance
		])

	return eligible

func _validate_sweeping_advance(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})
	var errors = []

	if unit_id.is_empty():
		errors.append("No unit_id provided for Sweeping Advance")
		return {"valid": false, "errors": errors}

	if not awaiting_sweeping_advance:
		errors.append("No Sweeping Advance is pending")
		return {"valid": false, "errors": errors}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit %s not found" % unit_id)
		return {"valid": false, "errors": errors}

	var move_distance = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
	var in_engagement = _is_unit_in_combat(unit)

	# Validate movements — each model can move up to its M value
	for model_idx in movements:
		var new_pos = movements[model_idx]
		var models = unit.get("models", [])
		var idx = int(model_idx)
		if idx < 0 or idx >= models.size():
			errors.append("Invalid model index: %s" % model_idx)
			continue

		var model = models[idx]
		if not model.get("alive", true):
			errors.append("Cannot move destroyed model %s" % model_idx)
			continue

		var mpos = model.get("position", {})
		var old_pos = Vector2(mpos.x, mpos.y) if mpos is Vector2 else Vector2(float(mpos.get("x", 0)), float(mpos.get("y", 0)))
		var npos = new_pos if new_pos is Vector2 else Vector2(float(new_pos.get("x", 0)), float(new_pos.get("y", 0)))
		var distance = Measurement.distance_inches(old_pos, npos)
		if distance > move_distance + 0.1:  # Small tolerance
			errors.append("Model %s exceeds move distance (%.1f\" > %.0f\")" % [model_idx, distance, move_distance])

	# If in engagement, this is a Fall Back: models must end outside engagement range of all enemies
	# If not in engagement, this is a Normal Move: standard movement rules apply
	# We allow the movement to be validated more loosely here since the fight phase
	# doesn't have the full movement validation infrastructure

	return {"valid": errors.is_empty(), "errors": errors}

func _process_sweeping_advance(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})
	var changes = []

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var in_engagement = _is_unit_in_combat(unit)
	var move_type = "Fall Back" if in_engagement else "Normal Move"

	log_phase_message("SWEEPING ADVANCE: %s performs %s" % [unit_name, move_type])

	# Apply model position changes
	for model_idx in movements:
		var new_pos = movements[model_idx]
		var np = new_pos if new_pos is Vector2 else Vector2(float(new_pos.get("x", 0)), float(new_pos.get("y", 0)))
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, model_idx],
			"value": {"x": np.x, "y": np.y}
		})

	# If this was a Fall Back move, mark the unit as having fallen back
	if in_engagement:
		changes.append({
			"op": "set",
			"path": "units.%s.flags.fell_back" % unit_id,
			"value": true
		})

	# Mark the ability as used (once per battle)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.mark_once_per_battle_used(unit_id, "Sweeping Advance")

	# Remove this unit from pending list
	sweeping_advance_pending_units = sweeping_advance_pending_units.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check if there are more Sweeping Advance units to process
	if not sweeping_advance_pending_units.is_empty():
		var next = sweeping_advance_pending_units[0]
		log_phase_message("SWEEPING ADVANCE: Next eligible unit — %s (player %d)" % [next.unit_name, next.player])
		emit_signal("sweeping_advance_available", next.unit_id, next.player, next.in_engagement, next.move_distance)

		var result = create_result(true, changes)
		result["trigger_sweeping_advance"] = true
		result["sweeping_advance_unit_id"] = next.unit_id
		result["sweeping_advance_player"] = next.player
		result["sweeping_advance_in_engagement"] = next.in_engagement
		result["sweeping_advance_move_distance"] = next.move_distance
		return result

	# All Sweeping Advances resolved — check for Acrobatic Escape before ending
	log_phase_message("SWEEPING ADVANCE: All resolved — checking Acrobatic Escape")
	awaiting_sweeping_advance = false

	var ae_result = _check_acrobatic_escape_or_complete(changes)
	if ae_result != null:
		return ae_result

	log_phase_message("Fight phase ended")
	emit_signal("phase_completed")
	var result = create_result(true, changes)
	return result

func _process_decline_sweeping_advance(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit_name = ""
	if not unit_id.is_empty():
		var unit = get_unit(unit_id)
		unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("SWEEPING ADVANCE: %s declined" % unit_name)

	# Remove this unit from pending list
	sweeping_advance_pending_units = sweeping_advance_pending_units.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check for more eligible units
	if not sweeping_advance_pending_units.is_empty():
		var next = sweeping_advance_pending_units[0]
		log_phase_message("SWEEPING ADVANCE: Next eligible unit — %s (player %d)" % [next.unit_name, next.player])
		emit_signal("sweeping_advance_available", next.unit_id, next.player, next.in_engagement, next.move_distance)

		var result = create_result(true, [])
		result["trigger_sweeping_advance"] = true
		result["sweeping_advance_unit_id"] = next.unit_id
		result["sweeping_advance_player"] = next.player
		result["sweeping_advance_in_engagement"] = next.in_engagement
		result["sweeping_advance_move_distance"] = next.move_distance
		return result

	# All done — check for Acrobatic Escape before ending fight phase
	log_phase_message("SWEEPING ADVANCE: All resolved — checking Acrobatic Escape")
	awaiting_sweeping_advance = false

	var ae_result = _check_acrobatic_escape_or_complete([])
	if ae_result != null:
		return ae_result

	log_phase_message("Fight phase ended")
	emit_signal("phase_completed")
	return create_result(true, [])

# ============================================================================
# ACROBATIC ESCAPE (Callidus Assassin)
# ============================================================================

func _check_acrobatic_escape_or_complete(changes: Array):
	"""Check for Acrobatic Escape eligible units. Returns a result Dictionary if
	Acrobatic Escape is triggered, or null if the phase should complete normally."""
	if awaiting_acrobatic_escape:
		return null  # Already processing

	var ae_eligible = _get_acrobatic_escape_eligible_units()
	if ae_eligible.is_empty():
		return null  # No eligible units, proceed to phase_completed

	awaiting_acrobatic_escape = true
	acrobatic_escape_pending_units = ae_eligible.duplicate()

	var first = ae_eligible[0]
	log_phase_message("ACROBATIC ESCAPE: %s (player %d) is eligible — D6 roll = %.0f\" — offering ability" % [
		first.unit_name, first.player, first.move_distance
	])
	emit_signal("acrobatic_escape_available", first.unit_id, first.player, first.move_distance)

	var result = create_result(true, changes)
	result["trigger_acrobatic_escape"] = true
	result["acrobatic_escape_unit_id"] = first.unit_id
	result["acrobatic_escape_player"] = first.player
	result["acrobatic_escape_move_distance"] = first.move_distance
	return result

func _get_acrobatic_escape_eligible_units() -> Array:
	"""Find units with the Acrobatic Escape ability that are within Engagement Range at end of Fight phase."""
	var eligible = []
	var all_units = game_state_snapshot.get("units", {})

	for unit_id in all_units:
		var unit = all_units.get(unit_id, {})
		if unit.is_empty():
			continue

		# Check if unit has Acrobatic Escape ability
		var abilities = unit.get("meta", {}).get("abilities", [])
		var has_acrobatic_escape = false
		for ability in abilities:
			if ability is Dictionary and ability.get("name", "") == "Acrobatic Escape":
				has_acrobatic_escape = true
				break
			elif ability is String and ability == "Acrobatic Escape":
				has_acrobatic_escape = true
				break

		if not has_acrobatic_escape:
			continue

		# Check if unit is still alive
		if _is_unit_destroyed_check(unit):
			continue

		# Must be deployed on the battlefield
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue

		# Must be within Engagement Range of one or more enemy units
		if not _is_unit_in_combat(unit):
			log_phase_message("ACROBATIC ESCAPE: %s not in engagement range — skipping" % unit.get("meta", {}).get("name", unit_id))
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var player = int(unit.get("owner", 0))

		# Roll D6 for move distance
		var rng = RulesEngine.make_rng()
		var d6_roll = rng.roll_d6(1)[0]

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"player": player,
			"move_distance": float(d6_roll)
		})

		log_phase_message("ACROBATIC ESCAPE: %s eligible (in engagement, D6 = %d\")" % [unit_name, d6_roll])

	return eligible

func _validate_acrobatic_escape(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})
	var errors = []

	if unit_id.is_empty():
		errors.append("No unit_id provided for Acrobatic Escape")
		return {"valid": false, "errors": errors}

	if not awaiting_acrobatic_escape:
		errors.append("No Acrobatic Escape is pending")
		return {"valid": false, "errors": errors}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit %s not found" % unit_id)
		return {"valid": false, "errors": errors}

	# Get the D6 move distance from pending units
	var move_distance = 6.0  # fallback
	for pending in acrobatic_escape_pending_units:
		if pending.unit_id == unit_id:
			move_distance = pending.move_distance
			break

	# Validate movements — each model can move up to the D6 roll distance
	for model_idx in movements:
		var new_pos = movements[model_idx]
		var models = unit.get("models", [])
		var idx = int(model_idx)
		if idx < 0 or idx >= models.size():
			errors.append("Invalid model index: %s" % model_idx)
			continue

		var model = models[idx]
		if not model.get("alive", true):
			errors.append("Cannot move destroyed model %s" % model_idx)
			continue

		var mpos = model.get("position", {})
		var old_pos = Vector2(mpos.x, mpos.y) if mpos is Vector2 else Vector2(float(mpos.get("x", 0)), float(mpos.get("y", 0)))
		var npos = new_pos if new_pos is Vector2 else Vector2(float(new_pos.get("x", 0)), float(new_pos.get("y", 0)))
		var distance = Measurement.distance_inches(old_pos, npos)
		if distance > move_distance + 0.1:  # Small tolerance
			errors.append("Model %s exceeds Acrobatic Escape distance (%.1f\" > %.0f\")" % [model_idx, distance, move_distance])

	return {"valid": errors.is_empty(), "errors": errors}

func _process_acrobatic_escape(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var movements = action.get("movements", {})
	var changes = []

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	log_phase_message("ACROBATIC ESCAPE: %s performs Fall Back move" % unit_name)

	# Apply model position changes
	for model_idx in movements:
		var new_pos = movements[model_idx]
		var np = new_pos if new_pos is Vector2 else Vector2(float(new_pos.get("x", 0)), float(new_pos.get("y", 0)))
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, model_idx],
			"value": {"x": np.x, "y": np.y}
		})

	# Mark the unit as having fallen back
	changes.append({
		"op": "set",
		"path": "units.%s.flags.fell_back" % unit_id,
		"value": true
	})

	# Remove this unit from pending list
	acrobatic_escape_pending_units = acrobatic_escape_pending_units.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check if there are more Acrobatic Escape units to process
	if not acrobatic_escape_pending_units.is_empty():
		var next = acrobatic_escape_pending_units[0]
		log_phase_message("ACROBATIC ESCAPE: Next eligible unit — %s (player %d)" % [next.unit_name, next.player])
		emit_signal("acrobatic_escape_available", next.unit_id, next.player, next.move_distance)

		var result = create_result(true, changes)
		result["trigger_acrobatic_escape"] = true
		result["acrobatic_escape_unit_id"] = next.unit_id
		result["acrobatic_escape_player"] = next.player
		result["acrobatic_escape_move_distance"] = next.move_distance
		return result

	# All Acrobatic Escapes resolved — end the fight phase
	log_phase_message("ACROBATIC ESCAPE: All resolved — ending Fight phase")
	awaiting_acrobatic_escape = false
	emit_signal("phase_completed")

	var result = create_result(true, changes)
	return result

func _process_decline_acrobatic_escape(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit_name = ""
	if not unit_id.is_empty():
		var unit = get_unit(unit_id)
		unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("ACROBATIC ESCAPE: %s declined" % unit_name)

	# Remove this unit from pending list
	acrobatic_escape_pending_units = acrobatic_escape_pending_units.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check for more eligible units
	if not acrobatic_escape_pending_units.is_empty():
		var next = acrobatic_escape_pending_units[0]
		log_phase_message("ACROBATIC ESCAPE: Next eligible unit — %s (player %d)" % [next.unit_name, next.player])
		emit_signal("acrobatic_escape_available", next.unit_id, next.player, next.move_distance)

		var result = create_result(true, [])
		result["trigger_acrobatic_escape"] = true
		result["acrobatic_escape_unit_id"] = next.unit_id
		result["acrobatic_escape_player"] = next.player
		result["acrobatic_escape_move_distance"] = next.move_distance
		return result

	# All done — end fight phase
	log_phase_message("ACROBATIC ESCAPE: All resolved — ending Fight phase")
	awaiting_acrobatic_escape = false
	emit_signal("phase_completed")
	return create_result(true, [])

# Helper to check if any enemy model is within a given distance of any model in a unit
func _is_unit_within_distance_of_enemies(unit: Dictionary, distance_inches: float) -> bool:
	"""Check if any enemy model is within the specified distance (edge-to-edge) of any model in the unit."""
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = unit.get("owner", 0)

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit.get("owner", 0) == unit_owner:
			continue
		if _is_unit_destroyed_check(other_unit):
			continue

		var models1 = unit.get("models", [])
		var models2 = other_unit.get("models", [])

		for model1 in models1:
			if not model1.get("alive", true):
				continue
			for model2 in models2:
				if not model2.get("alive", true):
					continue
				var dist = Measurement.model_to_model_distance_inches(model1, model2)
				if dist <= distance_inches:
					return true

	return false

func get_fight_step_11e() -> String:
	"""Which of the three 11e Fight-phase steps is currently active:
	  "PILE_IN"     — the global Pile In step (12.02) the phase opens with,
	  "CONSOLIDATE" — the global Consolidate step (12.07) at the end,
	  "FIGHT"       — the alternating Fight step (12.04), the default.
	The Main HUD reads this to label the phase-action button and to decide
	whether ending the current step forfeits any fights: only ending the
	Fight step does. During the Pile In / Consolidate steps the button just
	finishes that step (no unit is skipped), so the "units haven't fought"
	warning must not fire there."""
	if pile_in_step_11e == PileInStep11e.ACTIVE:
		return "PILE_IN"
	if consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		return "CONSOLIDATE"
	return "FIGHT"

func get_unfought_eligible_units(only_player: int = -1) -> Array:
	"""Return array of {unit_id, unit_name, player, subphase} for units that haven't fought yet.
	Used by the end-fight-phase confirmation dialog (T5-UX7).

	When only_player >= 1, restrict the result to that player's units. The
	end-fight confirmation passes the ending (active) player so the warning
	lists only the units THAT player would forfeit — the opponent's units are
	not forfeited by ending your own fights (12.04), so listing them as
	"won't fight" would be misleading."""
	var unfought = []

	# 12.04: the FightSequencer is authoritative for who is still owed a fight.
	if sequencer_11e == null:
		return unfought
	for unit_id in GameState.state.get("units", {}):
		if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
			var unit = GameState.state.units[unit_id]
			if only_player >= 1 and int(unit.get("owner", 0)) != only_player:
				continue
			unfought.append({
				"unit_id": unit_id,
				"unit_name": unit.get("meta", {}).get("name", unit_id),
				"player": int(unit.get("owner", 0)),
				"subphase": "Fights First" if sequencer_11e.is_fights_first(unit) else "Remaining Combats"
			})
	return unfought

# State access methods
func get_current_fight_state() -> Dictionary:
	"""Return current fight state for the UI (fighter list + banner). Derived
	from the FightSequencer (12.04) — the 10e Subphase/tier-list state is gone.
	fight_sequence = combatants (eligible + fought); current_fight_index = the
	number that have fought (so the FightController status tags still work)."""
	return {
		"current_fighter_id": active_fighter_id,
		"fight_sequence": _combatants_11e(),
		"current_fight_index": units_that_fought.size(),
		"pending_attacks": pending_attacks,
		"confirmed_attacks": confirmed_attacks,
		"units_that_fought": units_that_fought,
		"resolution_state": resolution_state,
		"current_subphase": _subphase_string_11e(),
		"current_selecting_player": current_selecting_player
	}

# ============================================================================
# VERBOSE COMBAT LOG — Detailed melee dice breakdown for Game Event Log
# ============================================================================

func _emit_verbose_melee_combat_log(fighter_id: String, target_id: String, dice_data: Array,
		save_dice_blocks: Array, casualties: int) -> void:
	"""Emit detailed melee combat log entries to GameEventLog from dice_data and save results.
	Note: Combat header is already created in _process_roll_dice before resolution for real-time dice display."""

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
		var _cas_label2 = "model" if casualties == 1 else "models"
		GameEventLog.add_combat_result("  Result: %d %s destroyed" % [casualties, _cas_label2])
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
	var tl = SceneRefs.token_layer()
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
# STRATAGEM HANDLING (active stratagems with phase: "fight")
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
	# SOAK-2: fight-phase stratagems are usable in the OPPONENT'S turn (both
	# players fight). Validate for the submitting player, not the turn owner —
	# validating against get_current_player() rejected every legal
	# opponent's-turn use ("This stratagem belongs to player N") and the AI
	# burned its whole action budget retrying.
	var current_player = int(action.get("player", get_current_player()))
	var validation = strat_manager.can_use_stratagem(current_player, stratagem_id, target_unit_id)
	if not validation.can_use:
		errors.append(validation.reason)
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _process_use_stratagem(action: Dictionary) -> Dictionary:
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	# SOAK-2: apply for the submitting player (see _validate_use_stratagem)
	var current_player = int(action.get("player", get_current_player()))

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return create_result(false, [], "StratagemManager not available")

	var result = strat_manager.use_stratagem(current_player, stratagem_id, target_unit_id)
	if not result.get("success", false):
		return create_result(false, [], result.get("error", "Stratagem use failed"))

	var strat_name = result.get("stratagem_name", stratagem_id)
	DebugLogger.info(str("FightPhase: Stratagem %s used (target=%s)" % [strat_name, target_unit_id]))
	return create_result(true, result.get("diffs", []), "Used " + strat_name)

func _process_use_moment_shackle(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var choice = action.get("choice", "")
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var diffs = []

	diffs.append({"op": "set", "path": "units.%s.flags.moment_shackle_used" % unit_id, "value": true})
	_moment_shackle_pending_units.erase(unit_id)

	if choice == "attacks_12":
		diffs.append({"op": "set", "path": "units.%s.flags.moment_shackle_attacks_12" % unit_id, "value": true})
		log_phase_message("Moment Shackle: %s — Watcher's Axe gets 12 Attacks this phase" % unit_name)
		DebugLogger.info("[10][INFO] Moment Shackle: %s chose 12 Attacks on Watcher's Axe" % unit_name)
	elif choice == "invuln_2":
		diffs.append({"op": "set", "path": "units.%s.flags.effect_invuln" % unit_id, "value": 2})
		diffs.append({"op": "set", "path": "units.%s.flags.effect_invuln_source" % unit_id, "value": "Moment Shackle"})
		log_phase_message("Moment Shackle: %s — 2+ invulnerable save this phase" % unit_name)
		DebugLogger.info("[10][INFO] Moment Shackle: %s chose 2+ invulnerable save" % unit_name)

	return create_result(true, diffs)

func _process_decline_moment_shackle(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	_moment_shackle_pending_units.erase(unit_id)
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Moment Shackle: %s declined" % unit_name)
	return create_result(true, [])


# ============================================================================
# ISS-066 — 11e pile-in / consolidation wiring (12.02-12.08)
# ============================================================================

func _fight_movements_from_action(action: Dictionary) -> Dictionary:
	# Normalise the movement payload: a {model_key: Vector2} dict, or a
	# single {"position": {...}} for model index 0 (FightController form).
	var movements: Dictionary = action.get("movements", {}).duplicate()
	if movements.is_empty() and action.has("position"):
		var position = action.get("position")
		movements["0"] = Vector2(position.get("x", 0), position.get("y", 0))
	return movements

func _fight_rotations_from_action(action: Dictionary) -> Dictionary:
	# Normalise the rotation payload: a {model_key: float} dict of new facings
	# (radians) for models that were pivoted during a pile-in / consolidate.
	return action.get("rotations", {}).duplicate()

func _fight_pivot_cost_for_model(unit: Dictionary, model: Dictionary) -> float:
	# Cost in inches a pivot deducts from a model's 3" pile-in / consolidate move.
	# Mirrors MovementPhase.get_pivot_value_for_unit but resolved per model so a
	# mixed-base unit is handled correctly. All non-round bases cost 2" (Pariah
	# Nexus); a round base >32mm with a flying stem costs 2" on a VEHICLE.
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in keywords:
		return 0.0
	var base_type = model.get("base_type", "circular")
	if base_type != "circular":
		return 2.0
	var base_mm = int(model.get("base_mm", 32))
	if base_mm > 32 and model.get("flying_stem", false) and "VEHICLE" in keywords:
		return 2.0
	return 0.0

func _fight_effective_move_cap(unit: Dictionary, model: Dictionary, rotations: Dictionary, key) -> float:
	# The positional distance a model may move: 3" minus the pivot cost if the
	# action pivots it (new facing differs from its current stored facing).
	var cap := 3.0
	var new_rot = _fight_rotation_for_key(rotations, key)
	if new_rot != null:
		var old_rot = float(model.get("rotation", 0.0))
		if abs(float(new_rot) - old_rot) > 0.001:
			cap -= _fight_pivot_cost_for_model(unit, model)
	return max(0.0, cap)

func _fight_rotation_for_key(rotations: Dictionary, key):
	# Rotations may be keyed by array index ("0") or model id ("m1"), matching
	# the movement payload. Return the new facing or null if this model unrotated.
	if rotations.has(key):
		return rotations[key]
	if rotations.has(str(key)):
		return rotations[str(key)]
	return null

func _resolve_fight_model(unit_id: String, key) -> Dictionary:
	# A movement key may be an array index ("0") or a model id ("m1").
	var models = get_unit(unit_id).get("models", [])
	for i in models.size():
		if str(i) == str(key) or str(models[i].get("id", "")) == str(key):
			return models[i]
	return {}

func _fight_model_index_for_key(models: Array, key) -> int:
	# A movement key may be an array index ("0") or a model id ("m1"). Return the
	# matching array index, or -1 if none. Mirrors _resolve_fight_model so the
	# overlap validator agrees with the rest of the fight-move pipeline. Do NOT
	# use int(key): GDScript's int("m2") parses the trailing digits and returns
	# 2, which is off by one for 1-based model ids (m2 is at index 1).
	for i in models.size():
		if str(i) == str(key) or str(models[i].get("id", "")) == str(key):
			return i
	return -1

func _simulate_fight_board_with_movements(unit_id: String, movements: Dictionary, rotations: Dictionary = {}) -> Dictionary:
	# Deep copy of live state with the proposed model positions (and pivot
	# facings) applied — used to evaluate a template's AFTER conditions before
	# committing. Rotation matters for non-circular bases whose engagement reach
	# depends on their orientation. Payload keys may address the unit's own
	# models OR an attached character's ("char_unit:key") — 19.03 moves the
	# whole Attached unit in one action.
	var sim = GameState.state.duplicate(true)
	for gid in _fight_move_group_ids(unit_id):
		var models = sim.get("units", {}).get(gid, {}).get("models", [])
		for i in models.size():
			var np = _fight_payload_for_model(unit_id, movements, gid, i, models[i])
			if np != null:
				models[i]["position"] = {"x": np.x, "y": np.y}
			var nr = _fight_payload_for_model(unit_id, rotations, gid, i, models[i])
			if nr != null:
				models[i]["rotation"] = float(nr)
	return sim

func _validate_pile_in_11e(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))
	var movements = _fight_movements_from_action(action)
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit %s not found" % unit_id]}

	# 19.03: an attached CHARACTER has no pile-in of its own — the Attached
	# unit moves once, through its bodyguard's PILE_IN.
	if _fight_is_attached_character(unit_id):
		return {"valid": false, "errors": ["%s is an attached character — the Attached unit piles in as one unit through its bodyguard (19.03)" % unit_id]}

	# 12.02: pile-in happens in the global step at the START of the fight
	# phase — or as an Overrun fight's ADDITIONAL move (12.06), never as a
	# routine part of an activation.
	if pile_in_step_11e == PileInStep11e.ACTIVE:
		if int(unit.get("owner", 0)) != piling_in_player_11e:
			return {"valid": false, "errors": ["Not your half of the Pile In step — Player %d piles in first (12.02)" % piling_in_player_11e]}
		if units_that_piled_in.get(unit_id, false):
			return {"valid": false, "errors": ["%s has already made its pile-in move this step (12.02)" % unit_id]}
	elif unit_id == active_fighter_id and unit_id == overrun_pile_in_unit_11e:
		pass  # 12.06: the overrun fight's one additional pile-in move
	else:
		return {"valid": false, "errors": ["Pile-in happens in the Pile In step at the start of the Fight phase (12.02), or as an Overrun fight's additional move (12.06)"]}

	if _unit_has_keyword(unit, "AIRCRAFT"):
		if not movements.is_empty():
			return {"valid": false, "errors": ["AIRCRAFT units cannot Pile In"]}
		return {"valid": true, "errors": []}
	var tmpl: PileInMove = MoveTypes.get_type("pile_in")
	# 19.03: eligibility and shared geometry (targets, engaged-after) are the
	# ATTACHED unit's — evaluate the template on the folded board so attached
	# character models count as part of this unit.
	var folded_board = _fight_folded_board(unit_id, GameState.state)
	var el = tmpl.eligible(unit_id, folded_board)
	if not el.eligible:
		return {"valid": false, "errors": el.reasons}
	# An eligible unit may decline to move (the step/extra move is optional)
	if movements.is_empty():
		return {"valid": true, "errors": []}
	var ctx = tmpl.before_moving(unit_id, folded_board, null, {})
	if ctx.has("error"):
		return {"valid": false, "errors": [ctx.error]}
	var rotations = _fight_rotations_from_action(action)
	var errors: Array = []
	var attached_ids = _fight_attached_char_ids(unit_id)
	for key in movements:
		var route = _fight_split_move_key(unit_id, key)
		if route.unit_id != unit_id and not route.unit_id in attached_ids:
			errors.append("Model key %s does not address %s or one of its attached characters" % [str(key), unit_id])
			continue
		var old_pos = _get_model_position(route.unit_id, route.model_key)
		var new_pos = movements[key]
		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % str(key))
			continue
		var dist = Measurement.distance_inches(old_pos, new_pos)
		# A pivoted model spends part of its 3" on the pivot cost (Pariah Nexus).
		var move_model = _resolve_fight_model(route.unit_id, route.model_key)
		var cap = _fight_effective_move_cap(get_unit(route.unit_id), move_model, rotations, key)
		if dist > cap + MOVEMENT_CAP_EPSILON:
			if cap < 3.0:
				errors.append("Model %s pile in exceeds %.0f\" limit after pivot cost (%.1f\")" % [str(key), cap, dist])
			else:
				errors.append("Model %s pile in exceeds 3\" limit (%.1f\")" % [str(key), dist])
		if dist > 0.01:
			var ok = tmpl.model_move_allowed(unit_id, move_model, {"x": new_pos.x, "y": new_pos.y}, GameState.state, ctx)
			if not ok.allowed:
				errors.append("Model %s: %s" % [str(key), ok.reason])
	var overlap_check = _validate_no_overlaps_for_movement(unit_id, movements)
	if not overlap_check.valid:
		errors.append_array(overlap_check.errors)
	var coherency_check = _validate_unit_coherency(unit_id, movements)
	if not coherency_check.get("valid", false):
		errors.append_array(coherency_check.get("errors", []))
	# 12.03 AFTER — engaged + started-engaged pairs maintained (on the folded
	# post-move board, so the Attached unit is judged as one unit).
	var sim = _simulate_fight_board_with_movements(unit_id, movements, rotations)
	var after = tmpl.after_moving_conditions(unit_id, _fight_folded_board(unit_id, sim), ctx)
	if not after.ok:
		errors.append_array(after.violations)
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_consolidate_11e(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))
	var movements = _fight_movements_from_action(action)
	# 12.07: consolidation happens in the global end-of-phase Consolidate
	# step — never during a unit's activation.
	if consolidation_step_11e != ConsolidationStep11e.ACTIVE:
		return {"valid": false, "errors": ["Consolidation happens in the Consolidate step at the end of the Fight phase (12.07) — finish the Fight step first"]}
	if _forced_fights_pending_11e():
		return {"valid": false, "errors": ["Fights forced by an Engaging Consolidation must be resolved first (12.08)"]}
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit %s not found" % unit_id]}
	# 19.03: an attached CHARACTER has no consolidation of its own — the
	# Attached unit moves once, through its bodyguard's CONSOLIDATE.
	if _fight_is_attached_character(unit_id):
		return {"valid": false, "errors": ["%s is an attached character — the Attached unit consolidates as one unit through its bodyguard (19.03)" % unit_id]}
	if int(unit.get("owner", 0)) != consolidating_player_11e:
		return {"valid": false, "errors": ["Not your half of the Consolidate step — Player %d consolidates first (12.07)" % consolidating_player_11e]}
	if units_that_consolidated_11e.has(unit_id):
		return {"valid": false, "errors": ["%s has already made its consolidation move this step (12.07)" % unit_id]}
	if _unit_has_keyword(unit, "AIRCRAFT"):
		if not movements.is_empty():
			return {"valid": false, "errors": ["AIRCRAFT units cannot Consolidate"]}
		return {"valid": true, "errors": []}
	var tmpl: ConsolidationMove = MoveTypes.get_type("consolidation")
	# 19.03: eligibility, mode selection and shared geometry are the ATTACHED
	# unit's — evaluate the template on the folded board so attached character
	# models count as part of this unit.
	var folded_board = _fight_folded_board(unit_id, GameState.state)
	# 12.08 ELIGIBLE IF: the unit was eligible to fight this phase.
	var el = tmpl.eligible(unit_id, folded_board)
	if not el.eligible:
		return {"valid": false, "errors": el.reasons}
	var sel = tmpl.select_mode(unit_id, folded_board)
	var mode = str(sel.mode)
	# Per-model consolidation is optional (FAQ): an empty payload completes
	# the mandatory step without moving. Only validate geometry when models
	# actually move.
	if movements.is_empty():
		return {"valid": true, "errors": []}
	if mode == "":
		return {"valid": false, "errors": ["no consolidation mode applies — the unit cannot move (12.08)"]}
	var ctx = tmpl.before_moving(unit_id, folded_board, null, {"mode": mode})
	if ctx.has("error"):
		return {"valid": false, "errors": [ctx.error]}
	var rotations = _fight_rotations_from_action(action)
	var errors: Array = []
	var attached_ids = _fight_attached_char_ids(unit_id)
	for key in movements:
		var route = _fight_split_move_key(unit_id, key)
		if route.unit_id != unit_id and not route.unit_id in attached_ids:
			errors.append("Model key %s does not address %s or one of its attached characters" % [str(key), unit_id])
			continue
		var old_pos = _get_model_position(route.unit_id, route.model_key)
		var new_pos = movements[key]
		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % str(key))
			continue
		var dist = Measurement.distance_inches(old_pos, new_pos)
		# A pivoted model spends part of its 3" on the pivot cost (Pariah Nexus).
		var move_model = _resolve_fight_model(route.unit_id, route.model_key)
		var cap = _fight_effective_move_cap(get_unit(route.unit_id), move_model, rotations, key)
		if dist > cap + MOVEMENT_CAP_EPSILON:
			if cap < 3.0:
				errors.append("Model %s consolidation exceeds %.0f\" limit after pivot cost (%.1f\")" % [str(key), cap, dist])
			else:
				errors.append("Model %s consolidation exceeds 3\" limit (%.1f\")" % [str(key), dist])
		if dist > 0.01:
			var ok = tmpl.model_move_allowed(unit_id, move_model, {"x": new_pos.x, "y": new_pos.y}, GameState.state, ctx)
			if not ok.allowed:
				errors.append("Model %s: %s" % [str(key), ok.reason])
	var overlap_check = _validate_no_overlaps_for_movement(unit_id, movements)
	if not overlap_check.valid:
		errors.append_array(overlap_check.errors)
	# 12.08 AFTER — evaluated on the folded post-move board so the Attached
	# unit (bodyguard + attached characters) is judged as one unit, including
	# its coherency check inside after_moving_conditions.
	var sim = _simulate_fight_board_with_movements(unit_id, movements, rotations)
	var after = tmpl.after_moving_conditions(unit_id, _fight_folded_board(unit_id, sim), ctx)
	if not after.ok:
		errors.append_array(after.violations)
	return {"valid": errors.is_empty(), "errors": errors}
