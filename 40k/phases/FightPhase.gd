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
# ISS-050 step 2: the 11e fight-step state machine (12.04-12.06);
# null at edition 10.
var sequencer_11e: FightSequencer = null
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

	# ISS-050 step 2 (11e 12.04): the FightSequencer drives selection —
	# alternation starts with the ACTIVE player, and the eligibility
	# matrix includes charge-survivors that are no longer engaged
	# (overrun fights, 12.06). The 10e tier lists above remain for UI
	# display; ordering decisions defer to the sequencer.
	sequencer_11e = null
	if GameConstants.edition >= 11:
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

	# 11e 12.02: the fight phase OPENS with the global Pile In step — both
	# players pile in their eligible units (active player first) before any
	# unit is selected to fight. At 10e, fight selection starts immediately.
	if GameConstants.edition >= 11:
		_begin_pile_in_step_11e()
	else:
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
	if GameConstants.edition >= 11 and pile_in_step_11e == PileInStep11e.ACTIVE:
		return {"valid": false, "errors": ["The Pile In step (12.02) must finish before units are selected to fight"]}

	# ISS-050 step 2: at 11e the sequencer (12.04) is authoritative —
	# including charge-survivors that are unengaged (pg-39 overrun case),
	# which the 10e engagement check below would wrongly refuse.
	if GameConstants.edition >= 11 and sequencer_11e != null:
		var sel_11e = sequencer_11e.next_selection(GameState.state)
		if sel_11e.done:
			return {"valid": false, "errors": ["Fight step is over (no eligible units, 12.04)"]}
		if int(unit.owner) != int(sel_11e.player):
			return {"valid": false, "errors": ["Not your selection (Player %d picks, 12.04 %s step)" % [sel_11e.player, sel_11e.step]]}
		if not unit_id in sel_11e.candidates:
			return {"valid": false, "errors": ["Unit not eligible to fight in the %s step (12.04)" % sel_11e.step]}
		return {"valid": true}

	if unit.owner != current_selecting_player:
		var error_msg = "Not your turn to select (Player %d's turn, you are Player %d)" % [current_selecting_player, unit.owner]
		errors.append(error_msg)
		log_phase_message("VALIDATION FAILED: Player %d tried to select unit owned by Player %d during Player %d's selection" % [
			unit.owner, unit.owner, current_selecting_player
		])
		return {"valid": false, "errors": errors}

	# Check unit is eligible in current subphase
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
			source_list = normal_sequence

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
	# ISS-066 (11e 12.02-12.03): the PileInMove template is authoritative
	# at edition >= 11 (eligibility incl. charge-survivor/overrun, pile-in
	# target selection, base-contact lock, and the started-engaged-pairs
	# AFTER rule). 10e keeps the legacy path below.
	if GameConstants.edition >= 11:
		return _validate_pile_in_11e(action)
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

		# Check 3" movement limit (with floating-point tolerance)
		var distance = Measurement.distance_inches(old_pos, new_pos)
		if distance > 3.0 + MOVEMENT_CAP_EPSILON:
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
	# ISS-066 (11e 12.07-12.08): the ConsolidationMove template is
	# authoritative at edition >= 11 (mandatory mode selection
	# ongoing/engaging/objective + per-mode movement + AFTER conditions).
	if GameConstants.edition >= 11:
		return _validate_consolidate_11e(action)
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
	# "if possible" means: can ANY model get within 1" of an enemy within consolidation distance?
	var unit_id_for_consol = unit.get("id", "")
	var consol_dist = _get_consolidation_distance(unit_id_for_consol)
	var can_reach_engagement = _can_unit_reach_engagement_range(unit, consol_dist)

	if can_reach_engagement:
		return "ENGAGEMENT"

	# If cannot reach engagement, try objective mode
	var can_reach_objective = _can_unit_reach_objective_after_movement(unit, movements)

	if can_reach_objective:
		return "OBJECTIVE"

	return "NONE"

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
	var max_consol_dist = _get_consolidation_distance(unit_id)

	# Each model must:
	# 1. Move max consolidation distance (3" normally, 6" with Drive-by Krumpin')
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

		# Check consolidation movement limit (with floating-point tolerance)
		var distance = Measurement.distance_inches(old_pos, new_pos)
		if distance > max_consol_dist + MOVEMENT_CAP_EPSILON:
			errors.append("Model %s consolidate exceeds %.0f\" limit (%.1f\")" % [model_id, max_consol_dist, distance])

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
	var b2b_check = _validate_base_to_base_if_possible(unit_id, movements, max_consol_dist)
	if not b2b_check.valid:
		errors.append_array(b2b_check.errors)

	return {"valid": errors.is_empty(), "errors": errors}

func _validate_consolidate_objective(unit_id: String, movements: Dictionary) -> Dictionary:
	"""Validate consolidate when moving toward objective (fallback mode)"""
	var errors = []
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var objectives = GameState.state.board.get("objectives", [])
	var max_consol_dist = _get_consolidation_distance(unit_id)

	if objectives.is_empty():
		errors.append("No objectives available for consolidate")
		return {"valid": false, "errors": errors}

	# Each model must:
	# 1. Move max consolidation distance (3" normally, 6" with Drive-by Krumpin')
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

		# Check consolidation movement limit (with floating-point tolerance)
		var distance = Measurement.distance_inches(old_pos, new_pos)
		if distance > max_consol_dist + MOVEMENT_CAP_EPSILON:
			errors.append("Model %s consolidate exceeds %.0f\" limit (%.1f\")" % [model_id, max_consol_dist, distance])

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

	# FGT-1 / P2-78 (10e FAQ): Cannot skip a unit that is mid-fight and needs
	# to consolidate — consolidation is mandatory at the unit level. 11e has
	# no per-fighter consolidation (12.07 global step, optional per unit),
	# so the block does not apply there.
	if GameConstants.edition < 11 and active_fighter_id == unit_id and pending_attacks.is_empty() and confirmed_attacks.is_empty():
		errors.append("Unit must complete mandatory consolidation before being skipped (FAQ: consolidation is not optional)")
		return {"valid": false, "errors": errors}

	# 11e: the sequencer governs order — SKIP_UNIT is valid for the active
	# fighter (aborting its activation) or any unit still owed a fight.
	if GameConstants.edition >= 11 and sequencer_11e != null:
		if unit_id == active_fighter_id or sequencer_11e.eligible_to_fight(unit_id, GameState.state):
			return {"valid": true, "errors": []}
		errors.append("Unit %s has no fight to skip" % unit_id)
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

	# ISS-050 step 2 (11e): commit the selection in the sequencer and
	# surface the available fight types (NORMAL 12.05 / OVERRUN 12.06).
	var fight_types_11e: Array = []
	if GameConstants.edition >= 11 and sequencer_11e != null:
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

	# 11e 12.02: a move in the global Pile In step — apply now (idempotent
	# re-apply, same pattern as the Consolidate step) so newly-engaged
	# enemies become fight-eligible, then continue the step.
	if GameConstants.edition >= 11 and pile_in_step_11e == PileInStep11e.ACTIVE:
		if not changes.is_empty():
			PhaseManager.apply_state_changes(changes)
		_stamp_fight_eligibility_11e()
		return _advance_pile_in_step_11e(create_result(true, changes))

	# 11e 12.06: the Overrun fight's additional pile-in — the grant is
	# used up; apply the move so attack targets reflect the new engagement.
	if GameConstants.edition >= 11 and unit_id == overrun_pile_in_unit_11e:
		overrun_pile_in_unit_11e = ""
		if not changes.is_empty():
			PhaseManager.apply_state_changes(changes)
		_stamp_fight_eligibility_11e()

	# After pile-in, request attack assignment
	return _request_attack_assignment(unit_id, create_result(true, changes))

# Ask the active fighter's player to assign melee attacks (signal for the
# local UI + trigger metadata for the NetworkManager client re-emit).
func _request_attack_assignment(unit_id: String, result: Dictionary) -> Dictionary:
	var targets = _get_eligible_melee_targets(unit_id)
	emit_signal("attack_assignment_required", unit_id, targets)
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

	# A1 (11e): the auto-resolve path now uses the 11e allocation groups +
	# [DEVASTATING WOUNDS] cap (24.10) + 06.02 mortal-wound priority. When the
	# auto-allocate-wounds setting is ON (its default), the computer picks
	# casualties anyway, so route human defenders through auto-resolve so melee
	# gets the correct 11e resolution. The legacy interactive overlay (still 10e)
	# only applies at e11 when auto-allocate is explicitly OFF. 10e unchanged.
	var _auto_alloc_11e := false
	if GameConstants.edition >= 11:
		var _ss = get_node_or_null("/root/SettingsService")
		_auto_alloc_11e = _ss == null or _ss.get_auto_allocate_wounds()

	if defender_is_human and not _auto_alloc_11e:
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
		if GameConstants.edition >= 11:
			return _finish_fight_activation_11e(final_result)

		var consol_dist = _get_consolidation_distance(active_fighter_id)
		emit_signal("consolidate_required", active_fighter_id, consol_dist)
		final_result["trigger_consolidate"] = true
		final_result["consolidate_unit_id"] = active_fighter_id
		final_result["consolidate_distance"] = consol_dist
		return final_result

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
	if GameConstants.edition >= 11:
		return _finish_fight_activation_11e(final_result)

	# After attacks, request consolidate
	var consol_dist = _get_consolidation_distance(active_fighter_id)
	emit_signal("consolidate_required", active_fighter_id, consol_dist)

	# Add metadata for NetworkManager to re-emit signal on client
	final_result["trigger_consolidate"] = true
	final_result["consolidate_unit_id"] = active_fighter_id
	final_result["consolidate_distance"] = consol_dist

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
	if GameConstants.edition >= 11:
		return _finish_fight_activation_11e(final_result)

	# After attacks, request consolidate
	var consol_dist = _get_consolidation_distance(active_fighter_id)
	emit_signal("consolidate_required", active_fighter_id, consol_dist)
	final_result["trigger_consolidate"] = true
	final_result["consolidate_unit_id"] = active_fighter_id
	final_result["consolidate_distance"] = consol_dist

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
	Normally 3\", but 6\" for units with 'Drive-by Krumpin'' ability."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return 3.0
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is Dictionary:
			ability_name = ability.get("name", "")
		elif ability is String:
			ability_name = ability
		if ability_name == "Drive-by Krumpin'":
			log_phase_message("[OA-26] Drive-by Krumpin': Consolidation distance 6\" for %s" % unit_id)
			return 6.0
	return 3.0

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

	# Legacy support - update old index
	current_fight_index += 1

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

func _process_consolidate(action: Dictionary) -> Dictionary:
	# 11e 12.07-12.08: consolidation is a move in the global end-of-phase
	# Consolidate step, not the tail of a unit's activation.
	if GameConstants.edition >= 11:
		return _process_consolidate_step_11e(action)

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

	# Request next fight selection on host (only if there are units to select)
	if not dialog_data.is_empty():
		emit_signal("fight_selection_required", dialog_data)

	# Add flag and data to result for NetworkManager to trigger on clients
	var result = create_result(true, changes)
	if not dialog_data.is_empty():
		result["trigger_fight_selection"] = true
		result["fight_selection_data"] = dialog_data
	if not newly_eligible.is_empty():
		result["newly_eligible_units"] = newly_eligible

	return result

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

	for model_id in movements:
		var new_pos = movements[model_id]
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, model_id],
			"value": {"x": new_pos.x, "y": new_pos.y}
		})
	units_that_consolidated_11e[unit_id] = true

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
		current_subphase = Subphase.REMAINING_COMBATS
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
	if GameConstants.edition >= 11 and sequencer_11e != null:
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

	# Legacy support - update old index
	current_fight_index += 1

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
	elif GameConstants.edition >= 11 and consolidation_step_11e == ConsolidationStep11e.ACTIVE:
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

	# 11e: the FightSequencer is the eligibility authority — the 10e tier
	# lists drift from it (units added mid-phase, mark_fought bookkeeping)
	# and would offer/withhold the wrong candidates.
	if GameConstants.edition >= 11 and sequencer_11e != null:
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
	# ISS-050 step 2 (11e 12.04): the sequencer decides who picks next
	# (it skips a player with nothing eligible, returns to Fights First
	# after a remaining-step fight, and ends the step when nobody can).
	if GameConstants.edition >= 11 and sequencer_11e != null:
		sequencer_11e.after_fight_resolved(GameState.state)
		var sel_11e = sequencer_11e.next_selection(GameState.state)
		if not sel_11e.done:
			current_selecting_player = sel_11e.player
			current_subphase = Subphase.FIGHTS_FIRST if sel_11e.step == "fights_first" else Subphase.REMAINING_COMBATS
			log_phase_message("[11e] Next: Player %d picks in the %s step (%s)" % [sel_11e.player, sel_11e.step, str(sel_11e.candidates)])
		return

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

# ============================================================================
# 11e 12.02-12.03: GLOBAL PILE IN STEP
# ============================================================================

# 12.03 ELIGIBLE IF: engaged, or made a charge move this turn (the third
# clause — selected for an overrun fight — grants the ADDITIONAL pile-in
# during the Fight step, not a move in this step). Plus alive, hasn't made
# its one step move yet (12.02), and not AIRCRAFT (T4-4: cannot Pile In).
func _pile_in_eligible_units_11e(player: int) -> Array:
	var out: Array = []
	var tmpl: PileInMove = MoveTypes.get_type("pile_in")
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if units_that_piled_in.get(unit_id, false):
			continue
		if _unit_has_keyword(unit, "AIRCRAFT"):
			continue
		var any_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				any_alive = true
				break
		if not any_alive:
			continue
		if tmpl == null or not tmpl.eligible(unit_id, GameState.state).eligible:
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
		var unit = get_unit(unit_id)
		units[unit_id] = {
			"name": unit.get("meta", {}).get("name", unit_id),
			"engaged": RulesEngine.is_unit_engaged(unit_id, GameState.state)
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
	if GameConstants.edition < 11 or sequencer_11e == null:
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
		if units_that_consolidated_11e.has(unit_id):
			continue
		if not unit.get("flags", {}).get("was_eligible_to_fight", false):
			continue
		if _unit_has_keyword(unit, "AIRCRAFT"):
			continue
		var any_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				any_alive = true
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
	emit_signal("subphase_transition", Subphase.keys()[current_subphase], "CONSOLIDATE")
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
		var unit = get_unit(unit_id)
		var mode = ""
		if tmpl != null:
			mode = str(tmpl.select_mode(unit_id, GameState.state).mode)
		units[unit_id] = {
			"name": unit.get("meta", {}).get("name", unit_id),
			"mode": mode
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
	log_phase_message("current_fight_index: %d" % current_fight_index)
	log_phase_message("fight_sequence.size(): %d" % fight_sequence.size())
	log_phase_message("fight_sequence: %s" % str(fight_sequence))

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

	# 11e 12.02: during the global Pile In step, the piling-in player's
	# options are exactly: pile in one of their remaining eligible units,
	# or end their half.
	if GameConstants.edition >= 11 and pile_in_step_11e == PileInStep11e.ACTIVE:
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
	if GameConstants.edition >= 11 and consolidation_step_11e == ConsolidationStep11e.ACTIVE \
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

	# ISS-050 / AI-vs-AI benchmark finding: at 11e the sequencer (12.04) is the
	# selection authority — _validate_select_fighter accepts its candidates even
	# when the legacy fight_sequence queue is empty (e.g. a Fights-First unit
	# with no queued fights). If the queue-based branch above offered nothing
	# while a selection is actually pending, surface the sequencer's candidates
	# so action-driven players (the AI) can answer instead of hanging.
	if GameConstants.edition >= 11 and active_fighter_id == "" and sequencer_11e != null:
		var has_select := false
		for a in actions:
			if a.get("type", "") == "SELECT_FIGHTER":
				has_select = true
				break
		if not has_select:
			var sel_11e = sequencer_11e.next_selection(GameState.state)
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
	
	# If active fighter is selected, show simple control actions
	if active_fighter_id != "":
		if pending_attacks.is_empty():
			# 10e: per-activation pile-in (once per unit). 11e: only the
			# Overrun fight's additional pile-in (12.06) is offered here —
			# the routine pile-in happened in the global 12.02 step.
			var offer_pile_in: bool
			if GameConstants.edition >= 11:
				offer_pile_in = overrun_pile_in_unit_11e == active_fighter_id
			else:
				offer_pile_in = not units_that_piled_in.get(active_fighter_id, false)
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
	
	# If attacks resolved, can consolidate (10e per-fighter flow only —
	# at 11e consolidation lives in the global 12.07 step above)
	if GameConstants.edition < 11 and active_fighter_id != "" and pending_attacks.is_empty() and confirmed_attacks.is_empty():
		actions.append({
			"type": "CONSOLIDATE",
			"unit_id": active_fighter_id,
			"description": "Consolidate %s" % active_fighter_id
		})

	# Add END_FIGHT action when appropriate
	# The END_FIGHT button should ALWAYS be available to the active player
	# This allows them to end the fight phase even if there are eligible units
	var can_end_fight = false

	# 11e: the sequencer is the authority on "everyone has fought" — the
	# 10e tier lists can disagree (T2-6 additions, overrun eligibility).
	if GameConstants.edition >= 11 and sequencer_11e != null:
		if active_fighter_id == "" and not sequencer_11e.has_eligible(GameState.state):
			can_end_fight = true
			log_phase_message("Adding END_FIGHT action - fight step complete (11e sequencer)")
	# Can always end if no units are in combat
	elif fight_sequence.is_empty():
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
	var unit_keywords = unit.get("meta", {}).get("keywords", [])

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
	if GameConstants.edition >= 11:
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
	if GameConstants.edition >= 11 and sequencer_11e != null:
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
	if GameConstants.edition >= 11 and consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		return _advance_consolidation_step_11e(result)
	return result

func _validate_end_fight(action: Dictionary) -> Dictionary:
	# END_FIGHT is always valid - it's the manual way to end the fight phase
	return {"valid": true, "errors": []}

# 11e 12.02: the piling-in player passes — ends their half of the global
# Pile In step (any units they didn't move forfeit their pile-in; it is
# optional per unit).
func _validate_end_pile_in(action: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"valid": false, "errors": ["END_PILE_IN is an 11e action (12.02)"]}
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
	if GameConstants.edition < 11:
		return {"valid": false, "errors": ["END_CONSOLIDATION is an 11e action (12.07)"]}
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
	if GameConstants.edition >= 11:
		# 12.02: END_FIGHT during the Pile In step ends the current half
		# (same walk-forward semantics as the Consolidate step below).
		if pile_in_step_11e == PileInStep11e.ACTIVE:
			pile_in_done_players_11e[piling_in_player_11e] = true
			log_phase_message("[11e 12.02] Player %d ends their pile-in half via END_FIGHT" % piling_in_player_11e)
			return _advance_pile_in_step_11e(create_result(true, []))
		if consolidation_step_11e == ConsolidationStep11e.NOT_STARTED:
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

func get_unfought_eligible_units() -> Array:
	"""Return array of {unit_id, unit_name, player, subphase} for units that haven't fought yet.
	Used by the end-fight-phase confirmation dialog (T5-UX7)."""
	var unfought = []

	# 11e: the sequencer is authoritative — the 10e tier lists can disagree
	# (T2-6 additions, unengaged charge-survivors owed an overrun fight).
	if GameConstants.edition >= 11 and sequencer_11e != null:
		for unit_id in GameState.state.get("units", {}):
			if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
				var unit = GameState.state.units[unit_id]
				unfought.append({
					"unit_id": unit_id,
					"unit_name": unit.get("meta", {}).get("name", unit_id),
					"player": int(unit.get("owner", 0)),
					"subphase": "Fights First" if sequencer_11e.is_fights_first(unit) else "Remaining Combats"
				})
		return unfought

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

func _resolve_fight_model(unit_id: String, key) -> Dictionary:
	# A movement key may be an array index ("0") or a model id ("m1").
	var models = get_unit(unit_id).get("models", [])
	for i in models.size():
		if str(i) == str(key) or str(models[i].get("id", "")) == str(key):
			return models[i]
	return {}

func _simulate_fight_board_with_movements(unit_id: String, movements: Dictionary) -> Dictionary:
	# Deep copy of live state with the proposed model positions applied —
	# used to evaluate a template's AFTER conditions before committing.
	var sim = GameState.state.duplicate(true)
	var models = sim.get("units", {}).get(unit_id, {}).get("models", [])
	for key in movements:
		var np = movements[key]
		for i in models.size():
			if str(i) == str(key) or str(models[i].get("id", "")) == str(key):
				models[i]["position"] = {"x": np.x, "y": np.y}
				break
	return sim

func _validate_pile_in_11e(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))
	var movements = _fight_movements_from_action(action)
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit %s not found" % unit_id]}

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
	var el = tmpl.eligible(unit_id, GameState.state)
	if not el.eligible:
		return {"valid": false, "errors": el.reasons}
	# An eligible unit may decline to move (the step/extra move is optional)
	if movements.is_empty():
		return {"valid": true, "errors": []}
	var ctx = tmpl.before_moving(unit_id, GameState.state, null, {})
	if ctx.has("error"):
		return {"valid": false, "errors": [ctx.error]}
	var errors: Array = []
	for key in movements:
		var old_pos = _get_model_position(unit_id, key)
		var new_pos = movements[key]
		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % str(key))
			continue
		var dist = Measurement.distance_inches(old_pos, new_pos)
		if dist > 3.0 + MOVEMENT_CAP_EPSILON:
			errors.append("Model %s pile in exceeds 3\" limit (%.1f\")" % [str(key), dist])
		if dist > 0.01:
			var model = _resolve_fight_model(unit_id, key)
			var ok = tmpl.model_move_allowed(unit_id, model, {"x": new_pos.x, "y": new_pos.y}, GameState.state, ctx)
			if not ok.allowed:
				errors.append("Model %s: %s" % [str(key), ok.reason])
	var overlap_check = _validate_no_overlaps_for_movement(unit_id, movements)
	if not overlap_check.valid:
		errors.append_array(overlap_check.errors)
	var coherency_check = _validate_unit_coherency(unit_id, movements)
	if not coherency_check.get("valid", false):
		errors.append_array(coherency_check.get("errors", []))
	# 12.03 AFTER — engaged + started-engaged pairs maintained.
	var sim = _simulate_fight_board_with_movements(unit_id, movements)
	var after = tmpl.after_moving_conditions(unit_id, sim, ctx)
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
	if int(unit.get("owner", 0)) != consolidating_player_11e:
		return {"valid": false, "errors": ["Not your half of the Consolidate step — Player %d consolidates first (12.07)" % consolidating_player_11e]}
	if units_that_consolidated_11e.has(unit_id):
		return {"valid": false, "errors": ["%s has already made its consolidation move this step (12.07)" % unit_id]}
	if _unit_has_keyword(unit, "AIRCRAFT"):
		if not movements.is_empty():
			return {"valid": false, "errors": ["AIRCRAFT units cannot Consolidate"]}
		return {"valid": true, "errors": []}
	var tmpl: ConsolidationMove = MoveTypes.get_type("consolidation")
	# 12.08 ELIGIBLE IF: the unit was eligible to fight this phase.
	var el = tmpl.eligible(unit_id, GameState.state)
	if not el.eligible:
		return {"valid": false, "errors": el.reasons}
	var sel = tmpl.select_mode(unit_id, GameState.state)
	var mode = str(sel.mode)
	# Per-model consolidation is optional (FAQ): an empty payload completes
	# the mandatory step without moving. Only validate geometry when models
	# actually move.
	if movements.is_empty():
		return {"valid": true, "errors": []}
	if mode == "":
		return {"valid": false, "errors": ["no consolidation mode applies — the unit cannot move (12.08)"]}
	var ctx = tmpl.before_moving(unit_id, GameState.state, null, {"mode": mode})
	if ctx.has("error"):
		return {"valid": false, "errors": [ctx.error]}
	var errors: Array = []
	for key in movements:
		var old_pos = _get_model_position(unit_id, key)
		var new_pos = movements[key]
		if old_pos == Vector2.ZERO:
			errors.append("Model %s position not found" % str(key))
			continue
		var dist = Measurement.distance_inches(old_pos, new_pos)
		if dist > 3.0 + MOVEMENT_CAP_EPSILON:
			errors.append("Model %s consolidation exceeds 3\" limit (%.1f\")" % [str(key), dist])
		if dist > 0.01:
			var model = _resolve_fight_model(unit_id, key)
			var ok = tmpl.model_move_allowed(unit_id, model, {"x": new_pos.x, "y": new_pos.y}, GameState.state, ctx)
			if not ok.allowed:
				errors.append("Model %s: %s" % [str(key), ok.reason])
	var overlap_check = _validate_no_overlaps_for_movement(unit_id, movements)
	if not overlap_check.valid:
		errors.append_array(overlap_check.errors)
	var sim = _simulate_fight_board_with_movements(unit_id, movements)
	var after = tmpl.after_moving_conditions(unit_id, sim, ctx)
	if not after.ok:
		errors.append_array(after.violations)
	return {"valid": errors.is_empty(), "errors": errors}
